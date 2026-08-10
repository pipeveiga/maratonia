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

    /// La proyección del día que mandó el iPhone (Fase E). Persiste en
    /// disco: abrir el reloj sin iPhone a mano muestra el último HOY
    /// conocido — y su vigencia se valida contra el día local, así una
    /// proyección de ayer no ofrece entrenamientos viejos.
    @Published var proyeccion: ProyeccionDia?

    /// Programados que ESTE reloj ya corrió y guardó (aunque el iPhone
    /// todavía no se haya enterado): la Home los deja de ofrecer al
    /// instante, sin esperar la re-proyección. Se persiste acotado.
    @Published private(set) var programadosCompletados: [UUID] = []

    /// Cómo terminó cada uno LOCALMENTE (true = estructura completa):
    /// mientras el resultado viaja al iPhone, la Home ya puede mostrar
    /// "Completado"/"Parcial" en vez de caer a la vista legacy.
    @Published private(set) var estructuraCompletaLocal: [UUID: Bool] = [:]

    private static let claveCompletados = "programadosCompletadosWatch"
    private static let claveEstructuras = "estructurasCompletasWatch"

    private static var urlDocumentos: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var urlCarpetaPistas: URL {
        urlDocumentos.appendingPathComponent("Pistas", isDirectory: true)
    }

    private static var urlPlan: URL {
        urlDocumentos.appendingPathComponent("plan.json")
    }

    private static var urlProyeccion: URL {
        urlDocumentos.appendingPathComponent("proyeccion.json")
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
        if let datos = try? Data(contentsOf: Self.urlProyeccion) {
            proyeccion = try? JSONDecoder().decode(ProyeccionDia.self, from: datos)
        }
        programadosCompletados = (UserDefaults.standard
            .stringArray(forKey: Self.claveCompletados) ?? [])
            .compactMap(UUID.init(uuidString:))
        let crudas = UserDefaults.standard
            .dictionary(forKey: Self.claveEstructuras) as? [String: Bool] ?? [:]
        estructuraCompletaLocal = Dictionary(uniqueKeysWithValues:
            crudas.compactMap { clave, valor in UUID(uuidString: clave).map { ($0, valor) } })
        refrescarArchivosLocales()
    }

    // MARK: Fase E — proyección y resultados

    /// El entrenamiento que la Home puede ofrecer HOY (la decisión pura
    /// vive en ProyeccionDia.entrenamientoOfrecible, en Shared).
    func entrenamientoDeHoy(_ hoy: DiaLocal) -> (id: UUID, definicion: DefinicionEntrenamiento)? {
        proyeccion?.entrenamientoOfrecible(hoy: hoy,
                                           completadosLocal: Set(programadosCompletados))
    }

    private func guardarProyeccion(_ nueva: ProyeccionDia, datos: Data) {
        try? datos.write(to: Self.urlProyeccion, options: .atomic)
        DispatchQueue.main.async {
            self.proyeccion = nueva
        }
    }

    /// El resultado de HOY para la Home (la decisión pura vive en
    /// ProyeccionDia.resultadoDeHoy, en Shared).
    func resultadoDeHoy(_ hoy: DiaLocal) -> (nombre: String, resolucion: ResolucionProgramado)? {
        proyeccion?.resultadoDeHoy(hoy: hoy,
                                   completadosLocal: Set(programadosCompletados),
                                   estructuraLocal: estructuraCompletaLocal)
    }

    /// El reloj corrió y guardó este programado: dejar de ofrecerlo ya
    /// mismo. Acotado a los últimos 50 (no crece para siempre).
    func marcarCompletadoLocal(_ programadoID: UUID, estructuraCompleta: Bool) {
        var lista = programadosCompletados.filter { $0 != programadoID }
        lista.append(programadoID)
        programadosCompletados = Array(lista.suffix(50))
        UserDefaults.standard.set(programadosCompletados.map(\.uuidString),
                                  forKey: Self.claveCompletados)
        var estructuras = estructuraCompletaLocal
        estructuras[programadoID] = estructuraCompleta
        // Mismo tope que la lista: lo que salió de la lista, sale acá.
        let vigentes = Set(programadosCompletados)
        estructuraCompletaLocal = estructuras.filter { vigentes.contains($0.key) }
        UserDefaults.standard.set(
            Dictionary(uniqueKeysWithValues: estructuraCompletaLocal.map { ($0.key.uuidString, $0.value) }),
            forKey: Self.claveEstructuras)
    }

    /// Manda el resultado por transferUserInfo: la cola es confiable,
    /// sobrevive a reloj offline y entrega tarde si hace falta. El
    /// iPhone es idempotente, así que reenviar de más nunca duplica.
    func enviar(resultado: ResultadoSesionWatch) {
        guard let datos = try? JSONEncoder().encode(resultado) else { return }
        WCSession.default.transferUserInfo([MensajesWC.claveResultado: datos])
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
        // La proyección puede haber llegado con la app cerrada: al
        // activar, el contexto recibido ya la trae.
        procesarContexto(session.receivedApplicationContext)
        DispatchQueue.main.async {
            self.avisarArchivosAlTelefono()
        }
    }

    /// Llega la proyección del día (applicationContext: gana la última).
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        procesarContexto(applicationContext)
    }

    private func procesarContexto(_ contexto: [String: Any]) {
        guard let datos = contexto[MensajesWC.claveProyeccion] as? Data,
              let nueva = try? JSONDecoder().decode(ProyeccionDia.self, from: datos),
              nueva.version <= ProyeccionDia.versionActual else { return }
        guardarProyeccion(nueva, datos: datos)
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
