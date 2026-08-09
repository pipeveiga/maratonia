import Foundation
import WatchConnectivity

// Lado reloj de WatchConnectivity, y a la vez el almacenamiento local del
// watch: guarda el plan en Documents/plan.json y las pistas en
// Documents/Pistas/. Al abrir la app sin iPhone presente, todo se carga
// de disco. Cada vez que cambian los archivos locales, le avisa al
// iPhone qué tiene (para que no reenvíe lo que ya está).

/// Cumplimiento del entrenamiento planificado, persistido en el reloj.
/// Guarda la HUELLA de los tramos cumplidos (identidad por contenido,
/// no heurísticas de fecha/distancia): si el iPhone reenvía el mismo
/// plan, sigue cumplido; si el usuario edita los tramos, la huella
/// cambia y es un entrenamiento nuevo pendiente. Sobrevive a cerrar la
/// app y reiniciar el reloj (UserDefaults). El historial de la carrera
/// vive en Salud y no se toca.
final class EstadoPlanWatch: ObservableObject {
    static let compartido = EstadoPlanWatch()

    @Published private(set) var huellaCumplida: String?
    @Published private(set) var fechaCumplida: Date?

    private static let claveHuella = "huellaEntrenamientoCumplido"
    private static let claveFecha = "fechaEntrenamientoCumplido"

    private init() {
        huellaCumplida = UserDefaults.standard.string(forKey: Self.claveHuella)
        let cruda = UserDefaults.standard.double(forKey: Self.claveFecha)
        fechaCumplida = cruda > 0 ? Date(timeIntervalSince1970: cruda) : nil
    }

    /// Idempotente: marcar dos veces la misma huella no duplica nada
    /// (es un único valor, no una lista).
    func marcarCumplida(huella: String) {
        huellaCumplida = huella
        fechaCumplida = Date()
        UserDefaults.standard.set(huella, forKey: Self.claveHuella)
        UserDefaults.standard.set(fechaCumplida!.timeIntervalSince1970, forKey: Self.claveFecha)
    }
}

final class ConectividadWatch: NSObject, ObservableObject {
    static let compartida = ConectividadWatch()

    @Published var plan: Plan?
    @Published var archivosLocales: Set<String> = []

    private static var urlDocumentos: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var urlCarpetaPistas: URL {
        urlDocumentos.appendingPathComponent("Pistas", isDirectory: true)
    }

    private static var urlPlan: URL {
        urlDocumentos.appendingPathComponent("plan.json")
    }

    override private init() {
        super.init()
        try? FileManager.default.createDirectory(
            at: Self.urlCarpetaPistas, withIntermediateDirectories: true)
        cargarDeDisco()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func urlDePista(_ nombre: String) -> URL {
        Self.urlCarpetaPistas.appendingPathComponent(nombre)
    }

    /// Pistas que el plan pide y todavía no llegaron al reloj.
    var pistasFaltantes: [String] {
        guard let plan else { return [] }
        return plan.pistas.filter { !archivosLocales.contains($0) }
    }

    private func cargarDeDisco() {
        if let datos = try? Data(contentsOf: Self.urlPlan) {
            plan = try? JSONDecoder().decode(Plan.self, from: datos)
        }
        refrescarArchivosLocales()
    }

    private func refrescarArchivosLocales() {
        let nombres = (try? FileManager.default.contentsOfDirectory(
            atPath: Self.urlCarpetaPistas.path)) ?? []
        archivosLocales = Set(nombres)
    }

    private func avisarArchivosAlTelefono() {
        try? WCSession.default.updateApplicationContext(
            ["archivos": Array(archivosLocales)])
    }

    /// Borra del reloj los MP3 que ya no figuran en el plan: si no, el
    /// reloj acumula archivos viejos para siempre y se queda sin espacio.
    /// NUNCA durante una sesión: si el plan llega en plena carrera,
    /// borraría las pistas que están sonando y mataría la música.
    private func limpiarPistasHuerfanas() {
        guard Reproductor.compartido.estado == .detenido else {
            refrescarArchivosLocales()
            avisarArchivosAlTelefono()
            return
        }
        guard let plan else { return }
        let vigentes = Set(plan.pistas)
        for nombre in archivosLocales where !vigentes.contains(nombre) {
            try? FileManager.default.removeItem(at: urlDePista(nombre))
        }
        refrescarArchivosLocales()
        avisarArchivosAlTelefono()
    }
}

extension ConectividadWatch: WCSessionDelegate {

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        DispatchQueue.main.async {
            self.avisarArchivosAlTelefono()
        }
    }

    /// Llega el plan (transferUserInfo desde el iPhone).
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let datos = userInfo["plan"] as? Data,
              let nuevo = try? JSONDecoder().decode(Plan.self, from: datos) else { return }
        try? datos.write(to: Self.urlPlan, options: .atomic)
        DispatchQueue.main.async {
            self.plan = nuevo
            self.limpiarPistasHuerfanas()
        }
    }

    /// Llega un MP3. OJO: la URL es temporal — hay que MOVER el archivo acá
    /// mismo, antes de salir de este método, o el sistema lo borra.
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let nombre = (file.metadata?["nombre"] as? String) ?? file.fileURL.lastPathComponent
        let destino = Self.urlCarpetaPistas.appendingPathComponent(nombre)
        try? FileManager.default.removeItem(at: destino)
        do {
            try FileManager.default.moveItem(at: file.fileURL, to: destino)
        } catch {
            return
        }
        DispatchQueue.main.async {
            self.refrescarArchivosLocales()
            self.avisarArchivosAlTelefono()
        }
    }
}
