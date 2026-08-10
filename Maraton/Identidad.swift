import SwiftUI
import AuthenticationServices
import CloudKit

// Identidad de Maratonia (RC1). Diseño:
//
// - userID (UUID) es LA identidad interna estable. Los proveedores
//   (Apple, Google, email) son VÍNCULOS hacia ese userID: una cuenta
//   puede tener varios y el email JAMÁS es clave primaria.
// - El dominio deportivo pertenece al userID (AlmacenV2.usuarioID).
// - Sign in with Apple es NATIVO (AuthenticationServices): funciona
//   sin backend, con subject ID estable, private relay y chequeo de
//   revocación. Google y email+contraseña llegan detrás del protocolo
//   ProveedorAutenticacion cuando exista el proyecto de backend
//   (ver AUTH_SETUP.md) — sus botones NO aparecen hasta entonces:
//   cero botones muertos.
// - La cuenta es OPCIONAL en V1: la app funciona completa sin cuenta
//   (Apple rechaza forzar registro para features que no lo requieren,
//   guideline 5.1.1). Crear cuenta ASOCIA los datos existentes al
//   userID — cero duplicados, HealthKit intacto.
// - Cerrar sesión ≠ eliminar cuenta: cerrar sesión solo desactiva la
//   sesión local; eliminar borra la cuenta y el respaldo cloud propio,
//   y explica qué queda en Apple Health.

// MARK: - Modelo

struct ProveedorVinculado: Codable, Equatable {
    enum Tipo: String, Codable {
        case apple, google, email
    }
    var tipo: Tipo
    /// Apple: user identifier estable; Google: subject; email: el
    /// email normalizado. Identifica el VÍNCULO, no la cuenta.
    var subjectID: String
    /// Informativo (puede ser un private relay). Nunca clave primaria.
    var email: String?
    var fechaVinculacion: Date
}

struct CuentaUsuario: Codable, Equatable {
    var userID = UUID()
    var nombre: String?
    var proveedores: [ProveedorVinculado] = []
    var fechaCreacion: Date
    var sesionActiva = true

    /// Vincular es idempotente: el mismo proveedor+subject no se
    /// duplica; un subject nuevo del mismo tipo se agrega (multi-
    /// proveedor por diseño).
    mutating func vincular(_ proveedor: ProveedorVinculado) {
        guard !proveedores.contains(where: {
            $0.tipo == proveedor.tipo && $0.subjectID == proveedor.subjectID
        }) else { return }
        proveedores.append(proveedor)
    }

    func vinculo(de tipo: ProveedorVinculado.Tipo) -> ProveedorVinculado? {
        proveedores.first { $0.tipo == tipo }
    }
}

// MARK: - Disponibilidad de proveedores

/// Qué métodos de autenticación están DISPONIBLES en este build.
/// Apple es nativo (siempre, con la capability activada). Google y
/// email dependen de la configuración externa del backend: hasta que
/// exista (AUTH_SETUP.md), sus botones no se muestran.
enum ProveedoresDisponibles {
    static var apple: Bool { true }
    /// Se enciende solo cuando el proyecto de backend esté configurado
    /// (la config viaja en el bundle, p. ej. GoogleService-Info.plist).
    static var google: Bool {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
    }
    static var email: Bool {
        Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist") != nil
    }
}

// MARK: - Store

final class IdentidadStore: ObservableObject {

    @Published private(set) var cuenta: CuentaUsuario?
    @Published var mensajeError: String?

    private let url: URL
    /// Cómo asociar el dominio deportivo al userID. Se inyecta en init
    /// (tests) o después vía conectar(_:con:) — los @StateObject de la
    /// app se crean por separado.
    var asociarDominio: ((UUID?) -> Void)?

    var haySesion: Bool { cuenta?.sesionActiva == true }

    init(url: URL = IdentidadStore.urlPorDefecto,
         asociarDominio: ((UUID?) -> Void)? = nil) {
        self.url = url
        self.asociarDominio = asociarDominio
        cuenta = (try? Data(contentsOf: url))
            .flatMap { try? JSONDecoder().decode(CuentaUsuario.self, from: $0) }
    }

    /// Cablea cuenta ↔ dominio cuando ambos stores ya existen, y
    /// reasegura la asociación si la cuenta ya estaba creada.
    static func conectar(_ identidad: IdentidadStore, con almacen: AlmacenStore) {
        identidad.asociarDominio = { [weak almacen] usuarioID in
            almacen?.asociarUsuario(usuarioID)
        }
        if identidad.haySesion, let usuarioID = identidad.cuenta?.userID {
            almacen.asociarUsuario(usuarioID)
        }
    }

    static var urlPorDefecto: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("cuenta.json")
    }

    /// Crea la cuenta (usuario nuevo) o vincula el proveedor a la
    /// existente (usuario que ya tenía datos o cuenta). SIEMPRE asocia
    /// el dominio local al userID — esa es la migración: los datos que
    /// ya estaban pasan a pertenecer a la cuenta, sin duplicar nada.
    func iniciarSesion(con proveedor: ProveedorVinculado, nombre: String? = nil) {
        var actual = cuenta ?? CuentaUsuario(nombre: nil, fechaCreacion: Date())
        if actual.nombre == nil { actual.nombre = nombre }
        actual.vincular(proveedor)
        actual.sesionActiva = true
        cuenta = actual
        guardar()
        asociarDominio?(actual.userID)
        mensajeError = nil
    }

    /// Cerrar sesión NO borra nada: la cuenta y los datos quedan; solo
    /// se apaga la sesión local.
    func cerrarSesion() {
        cuenta?.sesionActiva = false
        guardar()
    }

    /// Elimina la CUENTA Maratonia: el archivo local de cuenta, la
    /// asociación del dominio y el respaldo cloud propio. NO toca
    /// Apple Health (los entrenamientos guardados ahí son del usuario
    /// y se administran desde la app Salud) ni el historial local.
    func eliminarCuenta(borrandoRespaldo cuentaCloud: CuentaStore?) {
        try? FileManager.default.removeItem(at: url)
        cuenta = nil
        asociarDominio?(nil)
        cuentaCloud?.borrarRespaldo()
    }

    /// Sign in with Apple puede REVOCARSE desde Ajustes: al abrir la
    /// app se verifica el estado y, si fue revocado, la sesión se
    /// cierra (la cuenta y los datos quedan — puede volver a entrar).
    func verificarRevocacionApple() {
        guard let vinculo = cuenta?.vinculo(de: .apple), haySesion else { return }
        ASAuthorizationAppleIDProvider().getCredentialState(forUserID: vinculo.subjectID) {
            [weak self] estado, _ in
            DispatchQueue.main.async {
                if estado == .revoked {
                    self?.cerrarSesion()
                }
            }
        }
    }

    private func guardar() {
        if let cuenta, let datos = try? JSONEncoder().encode(cuenta) {
            try? datos.write(to: url, options: .atomic)
        }
    }
}

// MARK: - Sign in with Apple (nativo)

extension IdentidadStore {

    /// Procesa el resultado del botón oficial. Nombre y email vienen
    /// SOLO la primera vez que el usuario autoriza — por eso se
    /// persisten al toque; el subject ID es estable para siempre.
    func procesarResultadoApple(_ resultado: Result<ASAuthorization, Error>) {
        switch resultado {
        case .success(let autorizacion):
            guard let credencial = autorizacion.credential as? ASAuthorizationAppleIDCredential else {
                mensajeError = String(localized: "No pude leer la credencial de Apple.")
                return
            }
            let nombre = [credencial.fullName?.givenName, credencial.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            iniciarSesion(
                con: ProveedorVinculado(tipo: .apple,
                                        subjectID: credencial.user,
                                        email: credencial.email,
                                        fechaVinculacion: Date()),
                nombre: nombre.isEmpty ? nil : nombre)
        case .failure(let error):
            // Cancelar no es un error para mostrar.
            if (error as? ASAuthorizationError)?.code != .canceled {
                mensajeError = String(localized: "No se pudo iniciar sesión con Apple. Probá de nuevo.")
            }
        }
    }
}

// MARK: - UI: login

/// Pantalla de autenticación, simple y premium: los tres caminos
/// (los no configurados no aparecen) y salida clara sin cuenta.
struct LoginView: View {
    @ObservedObject var identidad: IdentidadStore
    @Environment(\.dismiss) private var dismiss
    /// true = se ofrece "Más adelante" (bienvenida); false = vino de
    /// Perfil y con cancelar alcanza.
    var permiteSaltear = false
    var alTerminar: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DV2.Espacio.l) {
            Spacer()

            Image("LogoMaratonia")
                .resizable()
                .scaledToFit()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 16))
            Text("Maratonia")
                .font(.largeTitle.bold())
            Text("Tu identidad en Maratonia. Tus datos se respaldan en tu iCloud privado y tus entrenamientos viven en Apple Health.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DV2.Espacio.xl)

            Spacer()

            if ProveedoresDisponibles.apple {
                SignInWithAppleButton(.continue) { pedido in
                    pedido.requestedScopes = [.fullName, .email]
                } onCompletion: { resultado in
                    identidad.procesarResultadoApple(resultado)
                    if identidad.haySesion {
                        alTerminar?()
                        dismiss()
                    }
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal, DV2.Espacio.xl)
            }

            // Google y email aparecen SOLO con el backend configurado
            // (AUTH_SETUP.md): nada de botones que no funcionan.
            if ProveedoresDisponibles.google {
                Button {
                    identidad.mensajeError = String(localized: "Google estará disponible muy pronto.")
                } label: {
                    Label("Continuar con Google", systemImage: "g.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DV2.Espacio.m)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: DV2.radioBoton))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DV2.Espacio.xl)
            }
            if ProveedoresDisponibles.email {
                Button {
                    identidad.mensajeError = String(localized: "El registro con email estará disponible muy pronto.")
                } label: {
                    Label("Continuar con email", systemImage: "envelope.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DV2.Espacio.m)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: DV2.radioBoton))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DV2.Espacio.xl)
            }

            if let error = identidad.mensajeError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }

            if permiteSaltear {
                Button("Más adelante") {
                    alTerminar?()
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .padding(.bottom, DV2.Espacio.s)
            } else {
                Button("Cancelar") { dismiss() }
                    .font(.subheadline)
                    .padding(.bottom, DV2.Espacio.s)
            }

            Text("Tus entrenamientos viven en Apple Health y tu respaldo en tu iCloud privado. La cuenta es opcional.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DV2.Espacio.xl)
                .padding(.bottom, DV2.Espacio.m)
        }
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - UI: sección de cuenta en Perfil

struct SeccionCuentaMaratonia: View {
    @ObservedObject var identidad: IdentidadStore
    @ObservedObject var cuentaCloud: CuentaStore
    @State private var mostrandoLogin = false
    @State private var confirmandoEliminar = false

    var body: some View {
        Section {
            if let cuenta = identidad.cuenta, identidad.haySesion {
                HStack(spacing: 10) {
                    IconoAjuste(sistema: "person.crop.circle.badge.checkmark", color: .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cuenta.nombre ?? String(localized: "Tu cuenta"))
                        Text(subtituloProveedores(cuenta))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Button("Cerrar sesión") { identidad.cerrarSesion() }
                Button("Eliminar cuenta", role: .destructive) {
                    confirmandoEliminar = true
                }
                .confirmationDialog("¿Eliminar tu cuenta de Maratonia?",
                                    isPresented: $confirmandoEliminar,
                                    titleVisibility: .visible) {
                    Button("Eliminar cuenta", role: .destructive) {
                        identidad.eliminarCuenta(borrandoRespaldo: cuentaCloud)
                    }
                    Button("Cancelar", role: .cancel) {}
                } message: {
                    Text("Se borran tu cuenta y el respaldo de Maratonia en iCloud. Tus entrenamientos guardados en Apple Health NO se tocan: siguen siendo tuyos y se administran desde la app Salud.")
                }
            } else {
                Button {
                    mostrandoLogin = true
                } label: {
                    HStack(spacing: 10) {
                        IconoAjuste(sistema: "person.crop.circle.badge.plus", color: .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(identidad.cuenta == nil
                                 ? String(localized: "Crear cuenta o iniciar sesión")
                                 : String(localized: "Iniciar sesión"))
                                .foregroundStyle(.primary)
                            Text("Opcional — tu identidad en Maratonia")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Cuenta Maratonia")
        } footer: {
            if identidad.cuenta != nil && !identidad.haySesion {
                Text("Tu cuenta y tus datos siguen acá — solo cerraste la sesión.")
            }
        }
        .sheet(isPresented: $mostrandoLogin) {
            LoginView(identidad: identidad)
        }
    }

    private func subtituloProveedores(_ cuenta: CuentaUsuario) -> String {
        let nombres = cuenta.proveedores.map { proveedor -> String in
            switch proveedor.tipo {
            case .apple: return "Apple"
            case .google: return "Google"
            case .email: return proveedor.email ?? "Email"
            }
        }
        return nombres.isEmpty ? String(localized: "Sin proveedores vinculados")
                               : nombres.joined(separator: " · ")
    }
}

// MARK: - UI: bienvenida (instalación limpia)

/// Primera pantalla de una instalación NUEVA: marca + cuenta opcional.
/// Un usuario con datos existentes jamás la ve.
struct BienvenidaView: View {
    @ObservedObject var identidad: IdentidadStore
    var alContinuar: () -> Void

    var body: some View {
        LoginView(identidad: identidad, permiteSaltear: true, alTerminar: alContinuar)
            .interactiveDismissDisabled(true)
    }
}
