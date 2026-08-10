import SwiftUI
import CryptoKit
import Security
import AuthenticationServices
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

// AUTENTICACIÓN REAL (build 44). Decisión de arquitectura: UNA sola
// autoridad de credenciales — Firebase Auth — para los TRES caminos.
// Apple se FEDERA contra Firebase (nonce + identityToken) para que
// Apple/Google/email no creen sistemas de cuentas paralelos. La
// identidad del DOMINIO sigue siendo nuestra: CuentaUsuario.userID
// (UUID interno); el UID de Firebase es un atributo del vínculo, jamás
// la clave del dominio (AlmacenV2.usuarioID no depende de Firebase).
//
// Sin Firebase configurado (falta GoogleService-Info.plist) la app
// entera funciona igual: la cuenta simplemente no se ofrece salvo el
// camino Apple nativo de respaldo. El Watch no sabe nada de todo esto.

// MARK: - Validación pura de credenciales (testeable sin Firebase)

enum ValidacionCredenciales {

    /// Sanidad mínima de email (el veredicto final es de Firebase).
    static func emailValido(_ email: String) -> Bool {
        let limpio = email.trimmingCharacters(in: .whitespaces)
        guard limpio.count >= 5, limpio.count <= 254,
              !limpio.contains(" ") else { return false }
        let partes = limpio.split(separator: "@")
        guard partes.count == 2, !partes[0].isEmpty else { return false }
        let dominio = partes[1]
        return dominio.contains(".") && !dominio.hasPrefix(".") && !dominio.hasSuffix(".")
    }

    /// Regla local: 8+ caracteres. (Firebase exige 6; pedimos un poco
    /// más — es una cuenta, no un candado de valija.)
    static func passwordValida(_ password: String) -> Bool {
        password.count >= 8
    }

    static func passwordsCoinciden(_ a: String, _ b: String) -> Bool {
        !a.isEmpty && a == b
    }
}

// MARK: - Servicio

@MainActor
final class ServicioAuth: ObservableObject {

    static let compartido = ServicioAuth()

    @Published var ocupado = false
    @Published var mensaje: String?

    /// Nonce crudo de la solicitud Apple EN CURSO (el hasheado viaja a
    /// Apple; el crudo se entrega a Firebase para validar el token).
    private var nonceActual: String?

    /// Código de autorización de la ÚLTIMA firma con Apple: hace falta
    /// FRESCO para revocar el token al eliminar la cuenta (los códigos
    /// son de un solo uso y vencen en minutos).
    private var ultimoCodigoAutorizacionApple: String?

    // MARK: Configuración

    /// Llamar UNA vez al arrancar la app. Solo configura si el plist
    /// está en el bundle — validación segura en runtime, sin crashear.
    static func configurar() {
        guard FirebaseApp.app() == nil,
              Bundle.main.url(forResource: "GoogleService-Info",
                              withExtension: "plist") != nil else { return }
        FirebaseApp.configure()
        if let clientID = FirebaseApp.app()?.options.clientID {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
        }
    }

    /// ¿Hay backend de identidad? (plist presente y Firebase arriba).
    /// nonisolated: consulta thread-safe a FirebaseApp, y se lee desde
    /// contextos no aislados (ProveedoresDisponibles).
    nonisolated static var disponible: Bool { FirebaseApp.app() != nil }

    /// ¿El URL scheme del callback de Google está configurado de
    /// verdad? (Sin esto el login de Google no puede volver a la app:
    /// el botón no se muestra.) nonisolated: solo lee Bundle.main.
    nonisolated static var esquemaGoogleConfigurado: Bool {
        let tipos = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes")
            as? [[String: Any]] ?? []
        return tipos.contains { tipo in
            ((tipo["CFBundleURLSchemes"] as? [String]) ?? [])
                .contains { $0.hasPrefix("com.googleusercontent.apps.") }
        }
    }

    nonisolated static func manejarURL(_ url: URL) {
        _ = GIDSignIn.sharedInstance.handle(url)
    }

    // MARK: Apple (federado contra Firebase cuando está disponible)

    /// Prepara la solicitud del botón oficial: scopes + nonce (SHA256
    /// viaja a Apple; el crudo queda para el intercambio con Firebase).
    func prepararSolicitudApple(_ solicitud: ASAuthorizationAppleIDRequest) {
        solicitud.requestedScopes = [.fullName, .email]
        if Self.disponible {
            let nonce = Self.nonceAleatorio()
            nonceActual = nonce
            solicitud.nonce = Self.sha256(nonce)
        }
    }

    /// Cierra el círculo: credencial Apple → (Firebase si hay) →
    /// cuenta local. El subject de Apple sigue siendo el identificador
    /// del VÍNCULO; el UID de Firebase viaja como atributo.
    func completarApple(_ resultado: Result<ASAuthorization, Error>,
                        identidad: IdentidadStore) {
        switch resultado {
        case .success(let autorizacion):
            guard let credencial = autorizacion.credential
                    as? ASAuthorizationAppleIDCredential else {
                mensaje = String(localized: "No pude leer la credencial de Apple.")
                return
            }
            if let codigo = credencial.authorizationCode {
                ultimoCodigoAutorizacionApple = String(data: codigo, encoding: .utf8)
            }
            let nombre = [credencial.fullName?.givenName,
                          credencial.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")
            let vinculo = ProveedorVinculado(tipo: .apple,
                                             subjectID: credencial.user,
                                             email: credencial.email,
                                             fechaVinculacion: Date())

            guard Self.disponible,
                  let nonce = nonceActual,
                  let tokenDatos = credencial.identityToken,
                  let token = String(data: tokenDatos, encoding: .utf8) else {
                // Respaldo sin Firebase: Apple nativo solo (build ≤43).
                identidad.iniciarSesion(con: vinculo,
                                        nombre: nombre.isEmpty ? nil : nombre)
                return
            }
            let credencialFirebase = OAuthProvider.appleCredential(
                withIDToken: token, rawNonce: nonce,
                fullName: credencial.fullName)
            entrar(con: credencialFirebase, vinculo: vinculo,
                   nombre: nombre.isEmpty ? nil : nombre, identidad: identidad)
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code != .canceled {
                mensaje = String(localized: "No se pudo iniciar sesión con Apple. Probá de nuevo.")
            }
        }
    }

    // MARK: Google

    func entrarConGoogle(identidad: IdentidadStore) {
        guard Self.disponible, let presentador = Self.controladorRaiz() else { return }
        ocupado = true
        GIDSignIn.sharedInstance.signIn(withPresenting: presentador) {
            [weak self] resultado, error in
            Task { @MainActor in
                guard let self else { return }
                self.ocupado = false
                if let error {
                    // Cancelar no es un error para mostrar.
                    if (error as NSError).code != GIDSignInError.canceled.rawValue {
                        self.mensaje = String(localized: "No se pudo iniciar sesión con Google. Probá de nuevo.")
                    }
                    return
                }
                guard let usuario = resultado?.user,
                      let idToken = usuario.idToken?.tokenString else {
                    self.mensaje = String(localized: "Google no devolvió una credencial válida.")
                    return
                }
                let credencial = GoogleAuthProvider.credential(
                    withIDToken: idToken,
                    accessToken: usuario.accessToken.tokenString)
                let vinculo = ProveedorVinculado(
                    tipo: .google,
                    subjectID: usuario.userID ?? idToken,
                    email: usuario.profile?.email,
                    fechaVinculacion: Date())
                self.entrar(con: credencial, vinculo: vinculo,
                            nombre: usuario.profile?.name, identidad: identidad)
            }
        }
    }

    // MARK: Email + contraseña (Firebase es la autoridad; acá no se
    // guarda ninguna contraseña, jamás)

    func crearCuentaEmail(_ email: String, password: String,
                          identidad: IdentidadStore) {
        guard Self.disponible else { return }
        ocupado = true
        Auth.auth().createUser(withEmail: email, password: password) {
            [weak self] resultado, error in
            Task { @MainActor in
                self?.terminarEmail(resultado: resultado, error: error,
                                    email: email, identidad: identidad)
            }
        }
    }

    func entrarConEmail(_ email: String, password: String,
                        identidad: IdentidadStore) {
        guard Self.disponible else { return }
        ocupado = true
        Auth.auth().signIn(withEmail: email, password: password) {
            [weak self] resultado, error in
            Task { @MainActor in
                self?.terminarEmail(resultado: resultado, error: error,
                                    email: email, identidad: identidad)
            }
        }
    }

    /// "Olvidé mi contraseña": Firebase manda el email de reset y acá
    /// se reporta éxito/error DE VERDAD.
    func recuperarPassword(_ email: String) {
        guard Self.disponible else { return }
        ocupado = true
        Auth.auth().sendPasswordReset(withEmail: email) { [weak self] error in
            Task { @MainActor in
                self?.ocupado = false
                if let error {
                    self?.mensaje = Self.mensajeDeError(error)
                } else {
                    self?.mensaje = String(localized: "Listo: te mandamos un email para restablecer la contraseña. Revisá también spam.")
                }
            }
        }
    }

    private func terminarEmail(resultado: AuthDataResult?, error: Error?,
                               email: String, identidad: IdentidadStore) {
        ocupado = false
        if let error {
            mensaje = Self.mensajeDeError(error)
            return
        }
        guard let usuario = resultado?.user else { return }
        identidad.iniciarSesion(con: ProveedorVinculado(
            tipo: .email,
            subjectID: email.lowercased()
                .trimmingCharacters(in: .whitespaces),
            email: email,
            fechaVinculacion: Date(),
            firebaseUID: usuario.uid))
        mensaje = nil
    }

    /// Camino común Apple/Google → Firebase → cuenta local.
    private func entrar(con credencial: AuthCredential,
                        vinculo: ProveedorVinculado,
                        nombre: String?, identidad: IdentidadStore) {
        ocupado = true
        Auth.auth().signIn(with: credencial) { [weak self] resultado, error in
            Task { @MainActor in
                guard let self else { return }
                self.ocupado = false
                if let error {
                    self.mensaje = Self.mensajeDeError(error)
                    return
                }
                var vinculoConUID = vinculo
                vinculoConUID.firebaseUID = resultado?.user.uid
                identidad.iniciarSesion(con: vinculoConUID, nombre: nombre)
                self.mensaje = nil
            }
        }
    }

    // MARK: Cerrar sesión / eliminar cuenta

    func cerrarSesion(identidad: IdentidadStore) {
        if Self.disponible {
            try? Auth.auth().signOut()
            GIDSignIn.sharedInstance.signOut()
        }
        identidad.cerrarSesion()
    }

    enum ResultadoEliminacion {
        case eliminada
        /// Firebase exige login reciente: el usuario debe reingresar y
        /// reintentar (la UI lo guía).
        case requiereReautenticacion
        case fallo(String)
    }

    /// Elimina la identidad en Firebase (y revoca el token de Apple si
    /// hay un código fresco — requisito de App Store para cuentas con
    /// Sign in with Apple). La limpieza local la hace el llamador con
    /// IdentidadStore.eliminarCuenta.
    func eliminarIdentidadRemota(alTerminar: @escaping (ResultadoEliminacion) -> Void) {
        guard Self.disponible, let usuario = Auth.auth().currentUser else {
            alTerminar(.eliminada)   // sin backend no hay nada remoto que borrar
            return
        }
        ocupado = true
        let borrar: () -> Void = { [weak self] in
            usuario.delete { error in
                Task { @MainActor in
                    self?.ocupado = false
                    guard let error else {
                        GIDSignIn.sharedInstance.signOut()
                        alTerminar(.eliminada)
                        return
                    }
                    if (error as NSError).code == 17014 {   // requiresRecentLogin
                        alTerminar(.requiereReautenticacion)
                    } else {
                        alTerminar(.fallo(Self.mensajeDeError(error)))
                    }
                }
            }
        }
        // Revocación del token de Apple: solo posible con código fresco
        // (un login con Apple en esta sesión de app). Si no hay, el
        // borrado del usuario procede igual y la revocación queda para
        // el reintento con reautenticación.
        if let codigo = ultimoCodigoAutorizacionApple {
            Auth.auth().revokeToken(withAuthorizationCode: codigo) { _ in
                borrar()
            }
        } else {
            borrar()
        }
    }

    // MARK: Errores → mensajes cortos y accionables (ES/EN por catálogo)

    /// Mapeo por código NSError DOCUMENTADO de FirebaseAuth (estable
    /// entre versiones del SDK; no dependemos del enum del SDK, que
    /// cambió de forma entre majors).
    static func mensajeDeError(_ error: Error) -> String {
        switch (error as NSError).code {
        case 17007:
            return String(localized: "Ese email ya tiene una cuenta. Probá iniciar sesión (o recuperar la contraseña).")
        case 17008:
            return String(localized: "Ese email no parece válido.")
        case 17009, 17004:
            return String(localized: "Email o contraseña incorrectos.")
        case 17011:
            return String(localized: "No hay ninguna cuenta con ese email.")
        case 17026:
            return String(localized: "La contraseña es muy corta: usá al menos 8 caracteres.")
        case 17010:
            return String(localized: "Demasiados intentos. Esperá unos minutos y probá de nuevo.")
        case 17020:
            return String(localized: "Sin conexión: revisá internet e intentá de nuevo.")
        case 17012:
            return String(localized: "Ese email ya entra con otro proveedor (Apple o Google). Usá ese botón.")
        case 17014:
            return String(localized: "Por seguridad, volvé a iniciar sesión y reintentá.")
        default:
            return String(localized: "No se pudo completar. Probá de nuevo en un rato.")
        }
    }

    // MARK: Utilitarios

    private static func controladorRaiz() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?.rootViewController
    }

    private static func nonceAleatorio(largo: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: largo)
        _ = SecRandomCopyBytes(kSecRandomDefault, largo, &bytes)
        let alfabeto = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String(bytes.map { alfabeto[Int($0) % alfabeto.count] })
    }

    private static func sha256(_ entrada: String) -> String {
        SHA256.hash(data: Data(entrada.utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}
