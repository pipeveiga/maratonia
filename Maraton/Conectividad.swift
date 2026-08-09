import Foundation
import WatchConnectivity

// Lado iPhone de WatchConnectivity. Envía el plan (transferUserInfo: chico
// y confiable, se encola si el reloj no está disponible) y los MP3
// (transferFile, uno por uno). El reloj avisa qué archivos ya tiene vía
// updateApplicationContext, y eso permite no reenviar lo que ya está.

final class Conectividad: NSObject, ObservableObject {
    static let compartida = Conectividad()

    @Published var relojEmparejado = false
    @Published var appInstaladaEnReloj = false
    /// Archivos que el reloj confirmó tener (los reporta él mismo).
    @Published var archivosEnReloj: Set<String> = []
    /// Progreso 0...1 de cada transferencia en curso, por nombre de archivo.
    @Published var progresoEnvios: [String: Double] = [:]
    @Published var planEncolado = false
    @Published var mensajeError: String?

    /// Quién sabe qué proyectar (AlmacenStore): se consulta al activar
    /// la sesión y cuando cambia el estado del reloj, para que el reloj
    /// reciba HOY apenas haya canal — sin esperar a que el usuario
    /// toque algo.
    var proveedorProyeccion: (() -> ProyeccionDia?)?

    /// Entrega de resultados del reloj (en main). Si llega un resultado
    /// antes de que alguien se registre, queda en el buffer y se entrega
    /// al registrarse — un resultado no se pierde por orden de arranque.
    private var alRecibirResultado: ((ResultadoSesionWatch) -> Void)?
    private var resultadosSinEntregar: [ResultadoSesionWatch] = []

    private var timerProgreso: Timer?

    override private init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func enviar(plan: Plan, urlDePista: (String) -> URL) {
        let sesion = WCSession.default
        guard sesion.activationState == .activated else {
            mensajeError = "La conexión con el reloj no está activa todavía. Probá de nuevo en unos segundos."
            return
        }
        mensajeError = nil

        if let datos = try? JSONEncoder().encode(plan) {
            sesion.transferUserInfo(["plan": datos])
            planEncolado = true
        }

        let yaEnViaje = Set(sesion.outstandingFileTransfers.compactMap {
            $0.file.metadata?["nombre"] as? String
        })
        for nombre in plan.pistas {
            guard !archivosEnReloj.contains(nombre), !yaEnViaje.contains(nombre) else { continue }
            let url = urlDePista(nombre)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            sesion.transferFile(url, metadata: ["nombre": nombre])
        }
        iniciarTimerDeProgreso()
    }

    private func iniciarTimerDeProgreso() {
        timerProgreso?.invalidate()
        timerProgreso = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.actualizarProgreso()
        }
        actualizarProgreso()
    }

    private func actualizarProgreso() {
        let transferencias = WCSession.default.outstandingFileTransfers
        let planesPendientes = WCSession.default.outstandingUserInfoTransfers
        var progreso: [String: Double] = [:]
        for transferencia in transferencias {
            if let nombre = transferencia.file.metadata?["nombre"] as? String {
                progreso[nombre] = transferencia.progress.fractionCompleted
            }
        }
        DispatchQueue.main.async {
            self.progresoEnvios = progreso
            // "Plan encolado" solo mientras de verdad esté en la cola:
            // antes quedaba prendido para siempre.
            self.planEncolado = !planesPendientes.isEmpty
            if transferencias.isEmpty && planesPendientes.isEmpty {
                self.timerProgreso?.invalidate()
                self.timerProgreso = nil
            }
        }
    }

    private static func nombres(deContexto contexto: [String: Any]) -> Set<String> {
        Set((contexto["archivos"] as? [String]) ?? [])
    }

    // MARK: Proyección del día (iPhone → reloj)

    /// applicationContext PISA el contexto entero del lado iPhone: este
    /// es el ÚNICO punto que lo escribe, así la proyección nunca borra
    /// otra cosa (los "archivos" viven en el contexto DEL RELOJ, que es
    /// un diccionario aparte — no se tocan entre sí).
    func enviar(proyeccion: ProyeccionDia) {
        guard WCSession.isSupported(),
              WCSession.default.activationState == .activated,
              let datos = try? JSONEncoder().encode(proyeccion) else { return }
        try? WCSession.default.updateApplicationContext([MensajesWC.claveProyeccion: datos])
    }

    private func empujarProyeccionSiHay() {
        if let proyeccion = proveedorProyeccion?() {
            enviar(proyeccion: proyeccion)
        }
    }

    // MARK: Resultados (reloj → iPhone)

    /// Registra el receptor y drena lo que haya llegado antes.
    func entregarResultados(a receptor: @escaping (ResultadoSesionWatch) -> Void) {
        alRecibirResultado = receptor
        let pendientes = resultadosSinEntregar
        resultadosSinEntregar = []
        pendientes.forEach(receptor)
    }

    fileprivate func recibio(resultado: ResultadoSesionWatch) {
        if let receptor = alRecibirResultado {
            receptor(resultado)
        } else {
            resultadosSinEntregar.append(resultado)
        }
    }
}

extension Conectividad: WCSessionDelegate {

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async {
            self.relojEmparejado = session.isPaired
            self.appInstaladaEnReloj = session.isWatchAppInstalled
            self.archivosEnReloj = Self.nombres(deContexto: session.receivedApplicationContext)
            if let error {
                self.mensajeError = error.localizedDescription
            }
            self.empujarProyeccionSiHay()
        }
    }

    /// Llegan resultados del reloj (transferUserInfo: cola confiable).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let datos = userInfo[MensajesWC.claveResultado] as? Data,
              let resultado = try? JSONDecoder().decode(ResultadoSesionWatch.self, from: datos),
              resultado.version <= ResultadoSesionWatch.versionActual else { return }
        DispatchQueue.main.async {
            self.recibio(resultado: resultado)
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.relojEmparejado = session.isPaired
            self.appInstaladaEnReloj = session.isWatchAppInstalled
            self.empujarProyeccionSiHay()
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.archivosEnReloj = Self.nombres(deContexto: applicationContext)
        }
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        DispatchQueue.main.async {
            if let error {
                self.mensajeError = "Falló el envío de un archivo: \(error.localizedDescription)"
            }
            self.actualizarProgreso()
        }
    }
}
