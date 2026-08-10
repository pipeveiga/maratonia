import SwiftUI
import AuthenticationServices
import CloudKit

// Identidad de Maratonia (RC1). Diseño:
//
// - userID (UUID) es LA identidad interna estable. Los proveedores
//   (Apple, Google, email) son VÍNCULOS hacia ese userID: una cuenta
//   puede tener varios y el email JAMÁS es clave primaria.
// - El dominio deportivo pertenece al userID (AlmacenV2.usuarioID).
// - Firebase Auth es la ÚNICA autoridad de credenciales (build 44):
//   Apple se FEDERA contra Firebase (botón nativo + nonce), Google va
//   por GoogleSignIn→Firebase y email+contraseña es Firebase puro
//   (ver ServicioAuth.swift y AUTH_SETUP.md). Sin Firebase configurado
//   la app funciona igual: Apple cae a modo nativo puro y los botones
//   de Google/email NO aparecen — cero botones muertos.
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
    /// UID de Firebase Auth de este vínculo (build 44). ATRIBUTO del
    /// vínculo, jamás la identidad del dominio (esa es userID).
    /// Opcional: las cuentas de build ≤43 no lo tienen y decodifican
    /// igual.
    var firebaseUID: String? = nil
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
/// Apple es nativo/federado (siempre). Google exige Firebase arriba Y
/// el URL scheme real del callback; email exige Firebase. Sin eso, los
/// botones no aparecen — cero botones muertos.
enum ProveedoresDisponibles {
    static var apple: Bool { true }
    static var google: Bool {
        ServicioAuth.disponible && ServicioAuth.esquemaGoogleConfigurado
    }
    static var email: Bool { ServicioAuth.disponible }
}

// MARK: - Store

/// @MainActor: todo el estado de cuenta vive en el hilo principal (es
/// un ObservableObject de UI). Además lo hace Sendable, así los
/// completion handlers @Sendable de los SDKs (GoogleSignIn/Firebase)
/// pueden capturarlo y saltar a MainActor sin warnings de concurrencia.
@MainActor
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

    /// nonisolated: FileManager es thread-safe y esto se usa como valor
    /// por defecto del init.
    nonisolated static var urlPorDefecto: URL {
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
            // El callback llega en un hilo cualquiera: saltar a MainActor
            // (self es Sendable por el aislamiento de la clase).
            Task { @MainActor in
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

// MARK: - UI: login

/// Pantalla de autenticación, simple y premium: los tres caminos
/// (los no configurados no aparecen) y salida clara sin cuenta.
struct LoginView: View {
    @ObservedObject var identidad: IdentidadStore
    @ObservedObject private var servicio = ServicioAuth.compartido
    @Environment(\.dismiss) private var dismiss
    /// true = se ofrece "Más adelante" (bienvenida); false = vino de
    /// Perfil y con cancelar alcanza.
    var permiteSaltear = false
    var alTerminar: (() -> Void)? = nil

    @State private var mostrandoEmail = false

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

            if servicio.ocupado {
                ProgressView()
            }

            if ProveedoresDisponibles.apple {
                SignInWithAppleButton(.continue) { pedido in
                    servicio.prepararSolicitudApple(pedido)
                } onCompletion: { resultado in
                    servicio.completarApple(resultado, identidad: identidad)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 50)
                .padding(.horizontal, DV2.Espacio.xl)
            }

            if ProveedoresDisponibles.google {
                Button {
                    servicio.entrarConGoogle(identidad: identidad)
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
                .disabled(servicio.ocupado)
            }
            if ProveedoresDisponibles.email {
                Button {
                    mostrandoEmail = true
                } label: {
                    Label("Continuar con correo electrónico", systemImage: "envelope.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, DV2.Espacio.m)
                        .background(Color(.secondarySystemGroupedBackground),
                                    in: RoundedRectangle(cornerRadius: DV2.radioBoton))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, DV2.Espacio.xl)
                .disabled(servicio.ocupado)
            }

            if let error = servicio.mensaje ?? identidad.mensajeError {
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
        .sheet(isPresented: $mostrandoEmail) {
            EmailAuthView(identidad: identidad)
        }
        // La sesión puede nacer en cualquiera de los tres caminos: al
        // aparecer, cerrar la pantalla y seguir.
        .onChange(of: identidad.haySesion) { _, activa in
            if activa {
                alTerminar?()
                dismiss()
            }
        }
    }
}

// MARK: - UI: email + contraseña (Firebase es la autoridad)

struct EmailAuthView: View {
    @ObservedObject var identidad: IdentidadStore
    @ObservedObject private var servicio = ServicioAuth.compartido
    @Environment(\.dismiss) private var dismiss

    private enum Modo { case crear, entrar }
    @State private var modo: Modo = .crear
    @State private var email = ""
    @State private var password = ""
    @State private var repetida = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Modo", selection: $modo) {
                        Text("Crear cuenta").tag(Modo.crear)
                        Text("Ya tengo cuenta").tag(Modo.entrar)
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Contraseña", text: $password)
                        .textContentType(modo == .crear ? .newPassword : .password)
                    if modo == .crear {
                        SecureField("Repetir contraseña", text: $repetida)
                            .textContentType(.newPassword)
                    }
                } footer: {
                    if modo == .crear {
                        Text("Mínimo 8 caracteres. La contraseña vive en Firebase Authentication — Maratonia nunca la guarda.")
                    }
                }

                if let problema = validacionLocal {
                    Section {
                        Text(problema)
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
                if let mensaje = servicio.mensaje {
                    Section {
                        Text(mensaje)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    Button {
                        let limpio = email.trimmingCharacters(in: .whitespaces)
                        if modo == .crear {
                            servicio.crearCuentaEmail(limpio, password: password,
                                                      identidad: identidad)
                        } else {
                            servicio.entrarConEmail(limpio, password: password,
                                                    identidad: identidad)
                        }
                    } label: {
                        if servicio.ocupado {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            EtiquetaBotonPrimarioV2(
                                titulo: modo == .crear
                                    ? String(localized: "Crear cuenta")
                                    : String(localized: "Iniciar sesión"),
                                icono: "envelope.fill")
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .disabled(!formularioValido || servicio.ocupado)
                }

                if modo == .entrar {
                    Section {
                        Button("Olvidé mi contraseña") {
                            servicio.recuperarPassword(
                                email.trimmingCharacters(in: .whitespaces))
                        }
                        .disabled(!ValidacionCredenciales.emailValido(email))
                    } footer: {
                        Text("Te mandamos un email de Firebase para restablecerla.")
                    }
                }
            }
            .navigationTitle(Text("Correo electrónico"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
            }
            .onChange(of: identidad.haySesion) { _, activa in
                if activa { dismiss() }
            }
            .onAppear { servicio.mensaje = nil }
        }
    }

    /// Validaciones LOCALES claras antes de molestar a Firebase.
    private var validacionLocal: String? {
        guard !email.isEmpty else { return nil }
        if !ValidacionCredenciales.emailValido(email) {
            return String(localized: "Ese email no parece válido.")
        }
        guard !password.isEmpty else { return nil }
        if modo == .crear, !ValidacionCredenciales.passwordValida(password) {
            return String(localized: "La contraseña es muy corta: usá al menos 8 caracteres.")
        }
        if modo == .crear, !repetida.isEmpty,
           !ValidacionCredenciales.passwordsCoinciden(password, repetida) {
            return String(localized: "Las contraseñas no coinciden.")
        }
        return nil
    }

    private var formularioValido: Bool {
        guard ValidacionCredenciales.emailValido(email) else { return false }
        switch modo {
        case .crear:
            return ValidacionCredenciales.passwordValida(password)
                && ValidacionCredenciales.passwordsCoinciden(password, repetida)
        case .entrar:
            return !password.isEmpty
        }
    }
}

// MARK: - UI: sección de cuenta en Perfil

struct SeccionCuentaMaratonia: View {
    @ObservedObject var identidad: IdentidadStore
    @ObservedObject var cuentaCloud: CuentaStore
    @ObservedObject private var servicio = ServicioAuth.compartido
    @State private var mostrandoLogin = false
    @State private var confirmandoEliminar = false
    @State private var mensajeEliminacion: String?

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
                // Ancla del login de REAUTENTICACIÓN (eliminar cuenta
                // puede pedir re-login). Va en una FILA y no en el
                // Section: los modificadores de presentación colgados
                // de un Section dentro de List se auto-descartan en la
                // primera presentación (bug clásico de SwiftUI).
                .sheet(isPresented: $mostrandoLogin) {
                    LoginView(identidad: identidad)
                }
                Button("Cerrar sesión") {
                    servicio.cerrarSesion(identidad: identidad)
                }
                Button("Eliminar cuenta", role: .destructive) {
                    confirmandoEliminar = true
                }
                .disabled(servicio.ocupado)
                .confirmationDialog("¿Eliminar tu cuenta de Maratonia?",
                                    isPresented: $confirmandoEliminar,
                                    titleVisibility: .visible) {
                    Button("Eliminar cuenta", role: .destructive) {
                        eliminar()
                    }
                    Button("Cancelar", role: .cancel) {}
                } message: {
                    Text("Se borran tu identidad (incluida la de Firebase) y el respaldo de Maratonia en iCloud. Tus entrenamientos guardados en Apple Health NO se tocan: siguen siendo tuyos y se administran desde la app Salud.")
                }
                if let mensaje = mensajeEliminacion {
                    Text(mensaje)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } else {
                Button {
                    mostrandoLogin = true
                } label: {
                    HStack(spacing: 10) {
                        // Discreto a propósito: la cuenta es OPCIONAL y
                        // no compite con plan/Watch/entrenamiento.
                        IconoAjuste(sistema: "person.crop.circle.badge.plus", color: .gray)
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
                // Misma ancla de fila que arriba: nunca coexisten (las
                // ramas son excluyentes), así que hay UN solo sheet en
                // el árbol a la vez.
                .sheet(isPresented: $mostrandoLogin) {
                    LoginView(identidad: identidad)
                }
            }
        } header: {
            Text("Cuenta Maratonia")
        } footer: {
            if identidad.cuenta != nil && !identidad.haySesion {
                Text("Tu cuenta y tus datos siguen acá — solo cerraste la sesión.")
            }
        }
    }

    /// Borrado en dos capas: primero la identidad REMOTA (Firebase +
    /// revocación Apple), y solo si eso termina bien la cuenta local y
    /// el respaldo iCloud. Si Firebase exige login reciente, la cuenta
    /// local NO se toca — se guía al usuario a reautenticarse.
    private func eliminar() {
        mensajeEliminacion = nil
        servicio.eliminarIdentidadRemota { resultado in
            switch resultado {
            case .eliminada:
                identidad.eliminarCuenta(borrandoRespaldo: cuentaCloud)
                mensajeEliminacion = nil
            case .requiereReautenticacion:
                mensajeEliminacion = String(localized: "Por seguridad, Firebase pide que vuelvas a iniciar sesión antes de eliminar la cuenta. Iniciá sesión y reintentá.")
                mostrandoLogin = true
            case .fallo(let motivo):
                mensajeEliminacion = motivo
            }
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
