import SwiftUI
import Combine

// ARRANQUE ACCOUNT-FIRST.
//
// Hasta el build 69 Maratonia era device-first: la app abría, pedía
// objetivo y armaba un plan, y la cuenta era un extra opcional en
// Perfil. Eso hace que instalar la app en otro teléfono sea empezar de
// cero, y que el corredor no tenga forma de recuperar SU Maratonia.
//
// Ahora la cuenta es la fuente de verdad del producto y el dispositivo
// es caché, sensor y ejecución. El arranque pasa a ser:
//
//     abrir → identidad → ¿esta cuenta ya tiene Maratonia?
//                              │
//                    sí ───────┴─────── no
//                     │                  │
//                restaurar          onboarding
//
// Lo que NO cambia: sin conexión la app sigue funcionando con lo que
// tiene en disco. La cuenta decide QUÉ datos son tuyos; no es un
// peaje para poder correr.

/// En qué punto del arranque está la app.
enum EstadoSesion: Equatable {
    /// Resolviendo si hay sesión. Dura lo que tarda Firebase en
    /// restaurar la suya (normalmente nada: es local).
    case resolviendo
    /// No hay cuenta: la puerta de entrada.
    case necesitaAuth
    /// Hay cuenta y se está trayendo su Maratonia. Solo se MUESTRA si
    /// de verdad tarda — un parpadeo de "restaurando" en cada arranque
    /// es peor que no mostrar nada.
    case restaurando
    /// Cuenta sin perfil deportivo: onboarding.
    case necesitaOnboarding
    /// Adentro.
    case lista
}

/// El portero del arranque. Es lo único que decide qué se muestra
/// primero, para que esa regla no quede repartida entre `onAppear`s.
@MainActor
final class SesionApp: ObservableObject {

    @Published private(set) var estado: EstadoSesion = .resolviendo
    /// true = el estado `.restaurando` ya duró lo suficiente como para
    /// que valga la pena decirlo.
    @Published private(set) var restauracionLenta = false

    private let almacen: AlmacenStore
    private let identidad: IdentidadStore
    private var cancelables: Set<AnyCancellable> = []

    /// A partir de cuánto se avisa que se está restaurando. Por debajo
    /// de esto el corredor solo ve la app aparecer.
    static let umbralRestauracionLenta: TimeInterval = 0.8

    init(almacen: AlmacenStore, identidad: IdentidadStore) {
        self.almacen = almacen
        self.identidad = identidad
        // Cambiar de cuenta (o cerrar sesión) re-decide el arranque:
        // sin esto, cerrar sesión dejaba la app adentro con los datos
        // del usuario anterior a la vista.
        identidad.$cuenta
            .removeDuplicates()
            .sink { [weak self] _ in self?.reevaluar() }
            .store(in: &cancelables)
    }

    /// La decisión de arranque. Pura respecto de la UI: mira el estado
    /// y devuelve dónde hay que estar.
    nonisolated static func estadoPara(haySesion: Bool,
                           authDisponible: Bool,
                           tienePerfil: Bool) -> EstadoSesion {
        // Sin Firebase configurado la app no puede pedir cuenta y
        // tampoco puede quedarse trabada: sigue siendo local. Es lo que
        // mantiene usable una build de desarrollo sin
        // GoogleService-Info.plist, y lo que evita que un fallo de
        // configuración deje a un corredor afuera de sus propios datos.
        guard authDisponible else {
            return tienePerfil ? .lista : .necesitaOnboarding
        }
        guard haySesion else { return .necesitaAuth }
        return tienePerfil ? .lista : .necesitaOnboarding
    }

    func reevaluar() {
        let destino = Self.estadoPara(haySesion: identidad.haySesion,
                                      authDisponible: ServicioAuth.disponible,
                                      tienePerfil: Self.tienePerfil(almacen.almacen))
        if estado != destino { estado = destino }
        if destino != .restaurando { restauracionLenta = false }
    }

    /// Qué cuenta como "esta cuenta ya tiene Maratonia". El perfil
    /// deportivo terminado es la señal: es lo que produce el onboarding
    /// y lo que hace falta para que la app tenga algo que mostrar.
    nonisolated static func tienePerfil(_ almacen: AlmacenV2) -> Bool {
        almacen.perfilDeportivo.fechaOnboarding != nil
            || almacen.planActivo != nil
    }

    /// Arranca la restauración desde la cuenta. La UI no espera a que
    /// termine para dejar usar la app si ya hay datos en disco.
    func restaurar(con repositorio: RepositorioCuenta) async {
        guard identidad.haySesion else { return reevaluar() }
        let teniaDatos = Self.tienePerfil(almacen.almacen)
        if !teniaDatos {
            estado = .restaurando
            // El aviso aparece SOLO si tarda.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.umbralRestauracionLenta))
                guard let self, self.estado == .restaurando else { return }
                self.restauracionLenta = true
            }
        }
        await repositorio.sincronizarAlEntrar()
        reevaluar()
    }

    /// El onboarding terminó.
    func onboardingCompletado() { reevaluar() }
}
