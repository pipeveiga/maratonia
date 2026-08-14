import SwiftUI
import AVFoundation
import CoreLocation
import HealthKit

// Correr con el celular, sin Apple Watch: música propia, avisos por voz
// (por tiempo y por kilómetro), tramos con corrección de ritmo, GPS y
// guardado en Salud. Es el hermano iPhone del motor del reloj, con las
// mismas reglas: la pausa congela todo, y la voz pausa la música y la
// reanuda al terminar de hablar. Sin reloj no hay frecuencia cardíaca:
// la distancia y el ritmo salen del GPS del teléfono.

/// Los números finales de una carrera hecha con el celular.
struct ResumenCelu {
    var duracion: TimeInterval
    var distanciaMetros: Double
    var ritmoPromedioSegKm: Int?
    var puntosRuta: Int
    var guardadaEnSalud: Bool
}

/// Evidencia de que la sesión SE GUARDÓ en Salud: solo se emite con el
/// HKWorkout real en mano. Es lo único que el calendario acepta para
/// marcar cumplido/parcial — si Salud falla, esto no se emite y el
/// programado queda pendiente (nada de cumplidos fantasma).
struct SesionGuardada {
    let hkUUID: UUID
    let fecha: Date
    /// D1: estructura completa = TODOS los tramos ejecutables del plan
    /// de la sesión fueron recorridos (misma regla debeMarcarCumplido
    /// del reloj). Sin tramos no hay estructura que completar → false.
    let estructuraCompleta: Bool
    /// Tiempo ACTIVO (sin pausas) al momento de completar la estructura
    /// (nil si no se completó). Para el Test 5K esto ES la marca: el
    /// trote posterior no la ensucia.
    var tiempoEstructuraSegundos: Int? = nil
    /// Agregados de la sesión, para el análisis post-carrera (§32).
    /// Son los MISMOS números que se guardaron en Salud: ni ritmo
    /// instantáneo ni muestras — solo el total.
    var metrosRecorridos: Double = 0
    var segundosTotales: Double = 0
}

final class CarreraCelu: NSObject, ObservableObject {
    static let compartida = CarreraCelu()

    enum Estado { case detenida, corriendo, pausada }

    @Published var estado: Estado = .detenida
    @Published var musicaSilenciada = false
    @Published var nombrePistaActual = ""
    @Published var tiempoTranscurrido: TimeInterval = 0
    @Published var distanciaMetros: Double = 0
    @Published var ritmoActualSegKm: Int?
    @Published var puntosRuta = 0
    @Published var mensajeError: String?
    @Published var resumen: ResumenCelu?
    @Published var tramoActual: Tramo?

    /// "1.24 / 3.0 km" o "1:12 / 2 min" del tramo en curso, refrescado
    /// una vez por segundo (la UI no recalcula avances por su cuenta).
    @Published var textoProgresoTramo: String?

    /// Fracción 0...1 del tramo en curso, para la barra de progreso.
    @Published var fraccionTramo: Double?

    /// El plan completo y por cuál tramo vas (panel de estructura de la
    /// pantalla de carrera).
    @Published var tramosDelPlan: [Tramo] = []
    @Published var indiceTramoUI = 0

    /// true mientras la auto-pausa tiene todo congelado; el GPS sigue
    /// vivo solo para detectar que arrancaste de nuevo.
    @Published var enPausaAutomatica = false
    private var ubicacionPausa: CLLocation?

    /// Frescura del GPS y histéresis de reanudación (ver AutoPausa en
    /// Shared): perder señal congela la distancia, y eso NO es estar
    /// parado — sin esto, un túnel o un mal fix disparaba pausas falsas.
    private var fechaUltimoGPS: Date?
    private var supervisorReanudacion = AutoPausa.SupervisorReanudacion()

    /// Vigilancia del GPS durante la auto-pausa (bug 1 de build 38):
    /// Core Location puede dejar de entregar con el usuario quieto y la
    /// reanudación dependía de ese stream sin que nadie lo vigilara.
    private var fechaUltimaSenalPausa: Date?
    private var fechaUltimoEmpujonGPS: Date?

    private var autoPausaActiva: Bool {
        UserDefaults.standard.object(forKey: "autoPausaCelu") as? Bool ?? false
    }

    // Música: cola de pistas en loop, como en el reloj.
    private var pistas: [String] = []
    private var urlDe: (String) -> URL? = { _ in nil }
    private var indicePista = 0
    private var player: AVAudioPlayer?

    /// Plan sin pistas: no se toma la sesión de audio en forma
    /// permanente (mataba al Spotify del corredor toda la carrera); la
    /// voz activa una sesión con ducking por frase y la suelta al final.
    private var modoSoloAvisos = false

    /// Eventos de pausa/reanudación previos a que exista el builder (el
    /// permiso de Salud puede responderse minutos tarde): se acumulan y
    /// se vuelcan al crearlo — antes se perdían y Salud contaba la
    /// pausa como tiempo activo.
    private var eventosPendientes: [HKWorkoutEvent] = []

    // Voz.
    private let voz = AVSpeechSynthesizer()

    // Tiempo a reloj de pared: acumulado + tramo corriendo actual. El
    // Timer solo refresca la UI y dispara chequeos; no lleva la cuenta.
    private var acumuladoPrevio: TimeInterval = 0
    private var fechaReanudacion: Date?
    private var timer: Timer?

    // Avisos por tiempo, ya expandidos y ordenados.
    private var avisosPendientes: [AvisoProgramado] = []

    // Splits y avisos por distancia (mismas reglas que el reloj).
    private var ultimoKmAnunciado = 0
    private var tiempoAlUltimoKm: TimeInterval = 0
    private var avisosKm: [AvisoKm] = []
    private var proximoDisparoKm: [UUID: Double] = [:]

    // Tramos con objetivo de ritmo: el avance (por distancia o por
    // tiempo) vive en ProgresoTramos, lógica pura compartida con el
    // motor del reloj.
    private var progreso = ProgresoTramos(tramos: [])

    // Sesión programada: el motor NO conoce el calendario — solo lleva
    // el ID opcional para la metadata de Salud y avisa por callback
    // cuando la sesión quedó guardada de verdad.
    private var programadoID: UUID?
    private var alGuardarSesion: ((SesionGuardada) -> Void)?
    /// Tiempo activo en el tick que cerró el último tramo del plan.
    private var tiempoAlCompletarEstructura: TimeInterval?
    private var fechaInicioTramo: Date?
    private var fechaUltimaCorreccion: Date?
    private let margenSegKm = 5

    // GPS: la distancia se suma entre puntos consecutivos con buena
    // precisión; los saltos malos no ensucian ni el total ni el mapa.
    private let ubicaciones = CLLocationManager()
    private var ultimaUbicacion: CLLocation?
    private var muestras: [(fecha: Date, metros: Double)] = []

    // Salud: en iOS no hay HKWorkoutSession; se usa HKWorkoutBuilder.
    private let healthStore = HKHealthStore()
    private var builder: HKWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var fechaInicio = Date()

    override private init() {
        super.init()
        voz.delegate = self
        ubicaciones.delegate = self
        ubicaciones.desiredAccuracy = kCLLocationAccuracyBest
        ubicaciones.activityType = .fitness
        // Una llamada o Siri cortan el audio y, sin esto, la música no
        // volvía nunca al terminar la interrupción.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil, queue: .main
        ) { [weak self] nota in
            self?.manejarInterrupcion(nota)
        }
        // Auriculares BT que se caen: sin esto, música y voz seguían a
        // todo volumen por el parlante del teléfono en plena calle.
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: nil, queue: .main
        ) { [weak self] nota in
            guard let self, self.estado == .corriendo,
                  let crudo = nota.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  AVAudioSession.RouteChangeReason(rawValue: crudo) == .oldDeviceUnavailable
            else { return }
            self.voz.stopSpeaking(at: .immediate)
            if !self.musicaSilenciada {
                self.alternarSoloMusica()  // el corredor la reactiva cuando quiera
            }
        }
    }

    private func manejarInterrupcion(_ nota: Notification) {
        guard estado == .corriendo,
              let info = nota.userInfo,
              let tipoCrudo = info[AVAudioSessionInterruptionTypeKey] as? UInt,
              let tipo = AVAudioSession.InterruptionType(rawValue: tipoCrudo) else { return }
        if tipo == .began {
            // Una frase pausada a medias por la interrupción dejaba
            // isSpeaking en true para siempre (ni didFinish ni didCancel)
            // y bloqueaba la vuelta de la música: cortarla ya.
            if voz.isSpeaking { voz.stopSpeaking(at: .immediate) }
            return
        }
        guard tipo == .ended else { return }
        let opciones = AVAudioSession.InterruptionOptions(
            rawValue: info[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0)
        guard opciones.contains(.shouldResume), !modoSoloAvisos,
              !musicaSilenciada, !voz.isSpeaking else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        player?.play()
    }

    private static var permiteUbicacionEnFondo: Bool {
        let modos = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] ?? []
        return modos.contains("location")
    }

    /// La voz sigue el idioma de la app (ver vozDeLaApp en Shared).
    private static var vozEnEspanol: AVSpeechSynthesisVoice? { vozDeLaApp() }

    // MARK: - Arranque

    func iniciar(plan: Plan, urlDe: @escaping (String) -> URL?,
                 programadoID: UUID? = nil,
                 alGuardar: ((SesionGuardada) -> Void)? = nil) {
        guard estado == .detenida else { return }
        self.programadoID = programadoID
        alGuardarSesion = alGuardar
        resumen = nil
        mensajeError = nil
        // Aislar la corrida nueva de la anterior: si la cadena de
        // guardado anterior quedó colgada, su builder no debe recibir
        // eventos de ESTA carrera (el completion viejo trabaja sobre su
        // propia captura local).
        builder = nil
        routeBuilder = nil
        self.urlDe = urlDe
        pistas = plan.pistas
        indicePista = 0
        avisosPendientes = plan.cronograma(duracionMaximaMinutos: 600)
        avisosKm = plan.avisosKmActivos
        proximoDisparoKm = Dictionary(uniqueKeysWithValues: avisosKm.map { ($0.id, $0.kilometro) })
        progreso = ProgresoTramos(tramos: plan.tramosActivos)
        tramoActual = progreso.tramoActual
        textoProgresoTramo = nil
        fraccionTramo = nil
        tramosDelPlan = progreso.tramos
        indiceTramoUI = 0
        tiempoAlCompletarEstructura = nil
        fechaInicioTramo = nil
        fechaUltimaCorreccion = nil
        ultimoKmAnunciado = 0
        tiempoAlUltimoKm = 0
        distanciaMetros = 0
        puntosRuta = 0
        ritmoActualSegKm = nil
        muestras = []
        ultimaUbicacion = nil
        fechaUltimoGPS = nil
        supervisorReanudacion.reiniciar()
        musicaSilenciada = false
        acumuladoPrevio = 0
        fechaReanudacion = Date()
        tiempoTranscurrido = 0
        fechaInicio = Date()
        enPausaAutomatica = false
        ubicacionPausa = nil

        // El estado pasa a "corriendo" ANTES de arrancar la música: la
        // primera pista chequea el estado para decidir si suena.
        estado = .corriendo
        modoSoloAvisos = plan.pistas.isEmpty
        eventosPendientes = []

        if !modoSoloAvisos {
            do {
                let sesion = AVAudioSession.sharedInstance()
                try sesion.setCategory(.playback, mode: .default, options: [])
                try sesion.setActive(true)
            } catch {
                mensajeError = String(localized: "No pude activar el audio: \(error.localizedDescription)")
            }
            reproducirPistaActual()
        }

        arrancarGPS()
        pedirPermisosSalud()

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    private func arrancarGPS() {
        switch ubicaciones.authorizationStatus {
        case .notDetermined:
            // El permiso puede llegar con la carrera andando: el delegate
            // enciende el GPS cuando el usuario acepta.
            ubicaciones.requestWhenInUseAuthorization()
        case .denied, .restricted:
            mensajeError = String(localized: "Ubicación negada: sin distancia, ritmo ni mapa. Activala en Ajustes → Privacidad → Localización → Maratonia.")
        default:
            break
        }
        ubicaciones.allowsBackgroundLocationUpdates = Self.permiteUbicacionEnFondo
        ubicaciones.pausesLocationUpdatesAutomatically = false
        ubicaciones.startUpdatingLocation()
    }

    /// Salud es opcional: si no dan permiso, la carrera corre igual y
    /// simplemente no se guarda como entrenamiento.
    private func pedirPermisosSalud() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let compartir: Set<HKSampleType> = [
            HKQuantityType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.distanceWalkingRunning),
        ]
        healthStore.requestAuthorization(toShare: compartir, read: []) { [weak self] ok, _ in
            DispatchQueue.main.async {
                guard let self, ok, self.estado != .detenida else { return }
                // ok == true no garantiza permiso de escritura: si guardar
                // workouts está negado, avisar ya y no armar el builder —
                // así el resumen dice la verdad ("terminada", no "guardada").
                guard self.healthStore.authorizationStatus(for: .workoutType()) != .sharingDenied else {
                    self.mensajeError = String(localized: "Salud tiene negado el permiso de guardar entrenamientos: la carrera NO se va a guardar. Activalo en Salud → Compartir → Apps → Maratonia.")
                    return
                }
                let configuracion = HKWorkoutConfiguration()
                configuracion.activityType = .running
                configuracion.locationType = .outdoor
                let nuevo = HKWorkoutBuilder(healthStore: self.healthStore,
                                             configuration: configuracion,
                                             device: .local())
                nuevo.beginCollection(withStart: self.fechaInicio) { _, _ in }
                if !self.eventosPendientes.isEmpty {
                    nuevo.addWorkoutEvents(self.eventosPendientes) { _, _ in }
                    self.eventosPendientes = []
                }
                self.builder = nuevo
                self.routeBuilder = HKWorkoutRouteBuilder(healthStore: self.healthStore, device: nil)
            }
        }
    }

    // MARK: - Tick (una vez por segundo)

    private func tick() {
        // En auto-pausa el tick no corre nada — pero VIGILA el GPS: si
        // Core Location dejó de entregar (throttling de estacionario),
        // la reanudación automática moría con él. Un empujón cada 10 s
        // lo despierta.
        if estado == .pausada, enPausaAutomatica {
            let ahora = Date()
            if AutoPausa.debeDespertarGPS(
                edadUltimaSenal: fechaUltimaSenalPausa.map { ahora.timeIntervalSince($0) },
                edadUltimoEmpujon: fechaUltimoEmpujonGPS.map { ahora.timeIntervalSince($0) }) {
                fechaUltimoEmpujonGPS = ahora
                ubicaciones.stopUpdatingLocation()
                ubicaciones.startUpdatingLocation()
            }
            return
        }
        guard estado == .corriendo, let reanudacion = fechaReanudacion else { return }
        tiempoTranscurrido = acumuladoPrevio + Date().timeIntervalSince(reanudacion)

        // Ritmo suavizado sobre ~45 s, igual que el reloj.
        let ahora = Date()
        muestras.append((ahora, distanciaMetros))
        muestras.removeAll { ahora.timeIntervalSince($0.fecha) > 60 }

        // Auto-pausa: ~10 s casi sin avanzar Y GPS fresco entregando
        // (una señal perdida congela la distancia y eso no es estar
        // parado). En el celu la distancia YA viene del GPS, así que
        // avance congelado + señal fresca = detención real.
        if autoPausaActiva, tiempoTranscurrido > 30,
           let vieja = muestras.first(where: { ahora.timeIntervalSince($0.fecha) <= 10 }),
           AutoPausa.debePausar(
               avanceMetros: distanciaMetros - vieja.metros,
               ventanaSegundos: ahora.timeIntervalSince(vieja.fecha),
               desplazamientoGPSMetros: nil,
               edadUltimoGPSSegundos: fechaUltimoGPS.map { ahora.timeIntervalSince($0) }) {
            pausar(automatica: true)
            anunciar(String(localized: "Pausa automática."))
            return
        }
        if let referencia = muestras.first(where: { ahora.timeIntervalSince($0.fecha) <= 45 }) {
            let segundos = ahora.timeIntervalSince(referencia.fecha)
            let metros = distanciaMetros - referencia.metros
            if segundos >= 20 {
                ritmoActualSegKm = metros >= 15 ? Int(segundos / metros * 1000) : nil
            }
        }

        chequearAvisosDeTiempo()
        chequearSplits()
        chequearAvisosPorKm()
        chequearTramos()
    }

    private func chequearAvisosDeTiempo() {
        let minuto = Int(tiempoTranscurrido / 60)
        var vencidos: [AvisoProgramado] = []
        while let primero = avisosPendientes.first, primero.minuto <= minuto {
            vencidos.append(avisosPendientes.removeFirst())
        }
        Self.avisosParaAnunciar(vencidos: vencidos, minuto: minuto)
            .forEach { anunciar($0) }
    }

    /// Regla de drenaje, pura y testeable. Tras una suspensión larga
    /// pueden vencer varios avisos de golpe: se descartan solo los
    /// VIEJOS (minutos ya pasados) — tres avisos configurados para el
    /// mismo minuto son legítimos y suenan todos, no son catch-up. Si
    /// todo era viejo, suena únicamente el más reciente.
    static func avisosParaAnunciar(vencidos: [AvisoProgramado], minuto: Int) -> [String] {
        let frescos = vencidos.filter { $0.minuto >= minuto - 1 }
        if frescos.isEmpty, let ultimo = vencidos.last {
            return [ultimo.texto]
        }
        return frescos.map(\.texto)
    }

    private func chequearSplits() {
        let km = Int(distanciaMetros / 1000)
        guard km > ultimoKmAnunciado, tiempoTranscurrido > 0 else { return }
        let parcial = tiempoTranscurrido - tiempoAlUltimoKm
        let cubiertos = km - ultimoKmAnunciado
        ultimoKmAnunciado = km
        tiempoAlUltimoKm = tiempoTranscurrido
        if cubiertos == 1, parcial > 60, parcial < 30 * 60 {
            anunciar(String(localized: "Kilómetro \(km): \(ritmoParaHablar(Int(parcial))) el último."))
        } else {
            anunciar(String(localized: "Kilómetro \(km)."))
        }
    }

    private func chequearAvisosPorKm() {
        let kmActual = distanciaMetros / 1000
        for aviso in avisosKm {
            guard let objetivo = proximoDisparoKm[aviso.id], kmActual >= objetivo else { continue }
            if let cada = aviso.cadaKm, cada > 0 {
                proximoDisparoKm[aviso.id] = objetivo + cada
            } else {
                proximoDisparoKm[aviso.id] = nil
            }
            anunciar(aviso.texto)
        }
    }

    private func chequearTramos() {
        guard !progreso.tramos.isEmpty, !progreso.terminado else { return }

        guard let inicioTramo = fechaInicioTramo else {
            fechaInicioTramo = Date()
            anunciar(anuncio(de: progreso.tramos[progreso.indice], numero: progreso.indice + 1))
            return
        }

        // ¿Se completó el tramo actual? (un tick puede cerrar varios)
        let eventos = progreso.avanzar(distanciaMetros: distanciaMetros,
                                       tiempoActivo: tiempoTranscurrido)
        if !eventos.isEmpty {
            tramoActual = progreso.tramoActual
            indiceTramoUI = progreso.indice
            for evento in eventos {
                switch evento {
                case .cambioTramo(let nuevo):
                    fechaInicioTramo = Date()
                    fechaUltimaCorreccion = nil
                    anunciar(anuncio(de: progreso.tramos[nuevo], numero: nuevo + 1))
                case .planCompletado:
                    textoProgresoTramo = nil
                    fraccionTramo = nil
                    tiempoAlCompletarEstructura = tiempoTranscurrido
                    anunciar(String(localized: "Plan de tramos completado. ¡Bien ahí!"))
                }
            }
            return
        }
        textoProgresoTramo = textoProgreso()
        fraccionTramo = progreso.progresoTramoActual(distanciaMetros: distanciaMetros,
                                                     tiempoActivo: tiempoTranscurrido)

        guard let ritmo = ritmoActualSegKm, let tramo = tramoActual else { return }
        guard Date().timeIntervalSince(inicioTramo) >= 45 else { return }
        if let ultima = fechaUltimaCorreccion, Date().timeIntervalSince(ultima) < 60 { return }

        if let rapido = tramo.ritmoMinSegKm, ritmo < rapido - margenSegKm {
            fechaUltimaCorreccion = Date()
            anunciar(String(localized: "Vas a \(ritmoParaHablar(ritmo)). Objetivo \(ritmoParaHablar(rapido)). Aflojá un poco."))
        } else if let lento = tramo.ritmoMaxSegKm, ritmo > lento + margenSegKm {
            fechaUltimaCorreccion = Date()
            anunciar(String(localized: "Vas a \(ritmoParaHablar(ritmo)). Objetivo \(ritmoParaHablar(lento)). Apurá un poco."))
        }
    }

    /// Progreso del tramo actual con la contabilidad real del avance.
    private func textoProgreso() -> String? {
        guard let tramo = progreso.tramoActual else { return nil }
        if tramo.esPorTiempo {
            let hecho = max(0, tiempoTranscurrido - progreso.inicioTiempoActivo)
            let segundos = Int(hecho)
            return "\(segundos / 60):" + String(format: "%02d", segundos % 60)
                + " / \(duracionTexto(tramo.duracionSegundos ?? 0))"
        }
        let recorrido = max(0, distanciaMetros - progreso.inicioDistanciaMetros) / 1000
        return String(format: "%.2f / %.1f km", recorrido, tramo.kilometros)
    }

    private func anuncio(de tramo: Tramo, numero: Int) -> String {
        anuncioDeTramo(tramo, numero: numero)
    }

    // MARK: - Voz (pausa la música, habla, y la música sigue)

    private func anunciar(_ texto: String) {
        if modoSoloAvisos {
            // Sesión por frase con ducking: baja el volumen de la app de
            // música del corredor solo mientras habla.
            let sesion = AVAudioSession.sharedInstance()
            try? sesion.setCategory(.playback, options: [.duckOthers])
            try? sesion.setActive(true)
        } else if player?.isPlaying == true {
            player?.pause()
        }
        let frase = AVSpeechUtterance(string: texto)
        frase.voice = Self.vozEnEspanol
        voz.speak(frase)
    }

    /// Para probar el volumen y la voz antes de salir.
    func probarAviso() {
        anunciar(String(localized: "Probando, probando. Así se escuchan los avisos."))
    }

    // MARK: - Música

    private func reproducirPistaActual() {
        let disponibles = pistas
        guard !disponibles.isEmpty else {
            nombrePistaActual = ""
            return
        }
        if indicePista >= disponibles.count { indicePista = 0 }
        let nombre = disponibles[indicePista]
        guard let url = urlDe(nombre) else {
            nombrePistaActual = ""
            return
        }
        do {
            let nuevo = try AVAudioPlayer(contentsOf: url)
            nuevo.delegate = self
            player = nuevo
            nombrePistaActual = nombre
            // No arrancar encima de la voz: si el asistente está hablando,
            // la pista queda lista y el didFinish de la voz la suelta.
            if estado == .corriendo && !musicaSilenciada && !voz.isSpeaking {
                nuevo.play()
            }
        } catch {
            mensajeError = String(localized: "No pude reproducir \(nombre).")
        }
    }

    func siguiente() {
        guard !pistas.isEmpty else { return }
        indicePista = (indicePista + 1) % pistas.count
        reproducirPistaActual()
    }

    /// Pausa/reanuda SOLO la música; avisos, GPS y cronómetro siguen.
    func alternarSoloMusica() {
        musicaSilenciada.toggle()
        if musicaSilenciada {
            player?.pause()
        } else if estado == .corriendo, !voz.isSpeaking {
            player?.play()
        }
    }

    // MARK: - Pausa total / final

    func alternarPausa() {
        estado == .corriendo ? pausar() : reanudar()
    }

    private func pausar(automatica: Bool = false) {
        guard estado == .corriendo, let reanudacion = fechaReanudacion else { return }
        acumuladoPrevio += Date().timeIntervalSince(reanudacion)
        fechaReanudacion = nil
        estado = .pausada
        enPausaAutomatica = automatica
        ubicacionPausa = nil
        supervisorReanudacion.reiniciar()
        // Gracia de 10 s antes del primer empujón al GPS.
        fechaUltimaSenalPausa = Date()
        fechaUltimoEmpujonGPS = nil
        player?.pause()
        // En auto-pausa el GPS queda vivo para detectar el arranque.
        if !automatica { ubicaciones.stopUpdatingLocation() }
        ultimaUbicacion = nil
        muestras = []
        ritmoActualSegKm = nil
        agregarEvento(.pause)
    }

    private func reanudar() {
        guard estado == .pausada else { return }
        fechaReanudacion = Date()
        estado = .corriendo
        enPausaAutomatica = false
        ubicacionPausa = nil
        // Con la voz hablando, la música no arranca encima: la suelta
        // el didFinish/didCancel de la voz al terminar.
        if !musicaSilenciada, !voz.isSpeaking { player?.play() }
        ubicaciones.startUpdatingLocation()
        agregarEvento(.resume)
    }

    /// Pausas y reanudaciones quedan registradas en el workout para que
    /// Salud descuente el tiempo parado.
    private func agregarEvento(_ tipo: HKWorkoutEventType) {
        let evento = HKWorkoutEvent(type: tipo,
                                    dateInterval: DateInterval(start: Date(), duration: 0),
                                    metadata: nil)
        guard let builder else {
            eventosPendientes.append(evento)
            return
        }
        builder.addWorkoutEvents([evento]) { _, _ in }
    }

    func terminar() {
        guard estado != .detenida else { return }
        if estado == .corriendo, let reanudacion = fechaReanudacion {
            acumuladoPrevio += Date().timeIntervalSince(reanudacion)
        }
        let duracion = acumuladoPrevio
        let ritmoPromedio = MetricasSesion.ritmoSegKm(metros: distanciaMetros,
                                                      segundos: duracion)
        resumen = ResumenCelu(duracion: duracion,
                              distanciaMetros: distanciaMetros,
                              ritmoPromedioSegKm: ritmoPromedio,
                              puntosRuta: puntosRuta,
                              guardadaEnSalud: builder != nil)
        guardarEnSalud()
        detenerComponentes()
    }

    func cancelar() {
        guard estado != .detenida else { return }
        builder?.discardWorkout()
        routeBuilder?.discard()
        builder = nil
        routeBuilder = nil
        resumen = nil
        detenerComponentes()
    }

    private func guardarEnSalud() {
        guard let builder else { return }
        // Capturas locales: el completion puede llegar con la carrera
        // SIGUIENTE ya andando — no debe atarle la ruta equivocada al
        // workout viejo, tocarle sus builders ni avisarle al calendario
        // con datos ajenos.
        let rutas = routeBuilder
        let puntos = puntosRuta
        let fin = Date()
        let callback = alGuardarSesion
        let idProgramado = programadoID
        // D1 sobre la estructura REALMENTE ejecutada (misma regla que
        // el cumplimiento del reloj): todos los tramos recorridos.
        let estructuraCompleta = debeMarcarCumplido(tramosTotales: progreso.tramos.count,
                                                    indiceAlcanzado: progreso.indice)
        let tiempoEstructura = tiempoAlCompletarEstructura.map { Int($0.rounded()) }
        // Agregados de la sesión, capturados ANTES de detener los
        // componentes (que ponen la distancia en cero).
        let metrosFinales = distanciaMetros
        let segundosFinales = acumuladoPrevio
        // La evidencia de origen viaja también en Salud (respaldo).
        if let idProgramado {
            builder.addMetadata(MetadatosSesion.metadata(programadoID: idProgramado)) { _, _ in }
        }
        let cerrar: () -> Void = { [weak self] in
            builder.endCollection(withEnd: fin) { _, errorColeccion in
                builder.finishWorkout { workout, errorFinal in
                    if let workout, let rutas, puntos > 0 {
                        rutas.finishRoute(with: workout, metadata: nil) { _, _ in }
                    }
                    // El vínculo con el calendario SOLO con el workout
                    // real en mano: si Salud falló, no se emite nada y
                    // el programado sigue pendiente.
                    if let workout {
                        DispatchQueue.main.async {
                            callback?(SesionGuardada(hkUUID: workout.uuid,
                                                     fecha: fin,
                                                     estructuraCompleta: estructuraCompleta,
                                                     tiempoEstructuraSegundos: tiempoEstructura,
                                                     metrosRecorridos: metrosFinales,
                                                     segundosTotales: segundosFinales))
                        }
                    }
                    DispatchQueue.main.async {
                        // El error se reporta SIEMPRE (aunque ya haya
                        // otra carrera andando: una corrida perdida no
                        // puede ser invisible)…
                        if let error = errorFinal ?? errorColeccion {
                            self?.mensajeError = String(localized: "La carrera NO se pudo guardar en Salud: \(error.localizedDescription)")
                        }
                        // …pero el estado solo se toca si seguimos en la
                        // MISMA carrera: este completion puede llegar
                        // tarde y antes pisaba el builder de la nueva.
                        guard self?.builder === builder else { return }
                        if errorFinal != nil || errorColeccion != nil {
                            self?.resumen?.guardadaEnSalud = false
                        }
                        self?.builder = nil
                        self?.routeBuilder = nil
                    }
                }
            }
        }
        if distanciaMetros > 0 {
            let muestra = HKQuantitySample(
                type: HKQuantityType(.distanceWalkingRunning),
                quantity: HKQuantity(unit: .meter(), doubleValue: distanciaMetros),
                start: fechaInicio, end: fin)
            builder.add([muestra]) { [weak self] _, errorMuestra in
                if let errorMuestra {
                    // Se puede permitir "Entrenamientos" y negar
                    // "Distancia": el workout se guardaba con 0 km mudo.
                    DispatchQueue.main.async {
                        self?.mensajeError = String(localized: "Salud rechazó la distancia (revisá el permiso «Distancia» en Salud → Apps → Maratonia): \(errorMuestra.localizedDescription)")
                    }
                }
                cerrar()
            }
        } else {
            cerrar()
        }
    }

    private func detenerComponentes() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        voz.stopSpeaking(at: .immediate)
        ubicaciones.stopUpdatingLocation()
        ultimaUbicacion = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
        estado = .detenida
        nombrePistaActual = ""
        musicaSilenciada = false
        tramoActual = nil
        textoProgresoTramo = nil
        fraccionTramo = nil
        tramosDelPlan = []
        indiceTramoUI = 0
        fechaReanudacion = nil
        enPausaAutomatica = false
        ubicacionPausa = nil
        modoSoloAvisos = false
        eventosPendientes = []
        programadoID = nil
        alGuardarSesion = nil  // guardarEnSalud ya capturó su copia local
    }
}

extension CarreraCelu: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // El delegate puede llegar fuera de main; el estado vive en main.
        DispatchQueue.main.async {
            guard self.estado != .detenida else { return }
            self.siguiente()
        }
    }
}

extension CarreraCelu: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.terminoLaVoz(synthesizer)
        }
    }

    /// Voz cancelada (interrupción, terminar): sin esto la música
    /// quedaba muerta hasta el próximo aviso.
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.terminoLaVoz(synthesizer)
        }
    }

    /// Al terminar la última frase: en modo solo-avisos suelta la sesión
    /// de ducking (la app de música ajena recupera su volumen); con
    /// música propia, la reanuda.
    private func terminoLaVoz(_ synthesizer: AVSpeechSynthesizer) {
        guard !synthesizer.isSpeaking else { return }
        if modoSoloAvisos {
            try? AVAudioSession.sharedInstance().setActive(
                false, options: [.notifyOthersOnDeactivation])
            return
        }
        guard estado == .corriendo, !musicaSilenciada else { return }
        player?.play()
    }
}

extension CarreraCelu: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Auto-pausa → reanudación automática por desplazamiento
        // sostenido O velocidad GPS sostenida (SupervisorReanudacion en
        // Shared). La pausa MANUAL nunca entra acá (puedeAutoReanudar).
        if estado == .pausada,
           AutoPausa.puedeAutoReanudar(pausada: true, enPausaAutomatica: enPausaAutomatica) {
            guard let ubicacion = locations.last,
                  ubicacion.horizontalAccuracy > 0, ubicacion.horizontalAccuracy <= 50 else { return }
            fechaUltimaSenalPausa = Date()
            let desplazamiento = ubicacionPausa.map { ubicacion.distance(from: $0) }
            if ubicacionPausa == nil { ubicacionPausa = ubicacion }
            if supervisorReanudacion.procesar(
                desplazamiento: desplazamiento,
                velocidad: ubicacion.speed >= 0 ? ubicacion.speed : nil,
                umbral: max(15, ubicacion.horizontalAccuracy),
                fecha: Date()) {
                reanudar()
                anunciar(String(localized: "Seguimos."))
            }
            return
        }

        guard estado == .corriendo else { return }
        var buenas: [CLLocation] = []
        for ubicacion in locations where ubicacion.horizontalAccuracy > 0 && ubicacion.horizontalAccuracy <= 50 {
            if let anterior = ultimaUbicacion {
                let delta = ubicacion.distance(from: anterior)
                if delta >= 1 { distanciaMetros += delta }
            }
            ultimaUbicacion = ubicacion
            buenas.append(ubicacion)
        }
        guard !buenas.isEmpty else { return }
        fechaUltimoGPS = Date()
        puntosRuta += buenas.count
        routeBuilder?.insertRouteData(buenas) { _, _ in }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard estado != .detenida else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            mensajeError = String(localized: "Ubicación negada: sin distancia, ritmo ni mapa. Activala en Ajustes → Privacidad → Localización → Maratonia.")
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .denied {
            mensajeError = String(localized: "Ubicación negada: sin distancia, ritmo ni mapa. Activala en Ajustes → Privacidad → Localización → Maratonia.")
        }
    }
}

// MARK: - Pestaña Correr

struct CorrerTab: View {
    @ObservedObject var store: PlanStore
    @ObservedObject var almacen: AlmacenStore
    @ObservedObject private var carrera = CarreraCelu.compartida
    @AppStorage("autoPausaCelu") private var autoPausa = false

    var body: some View {
        NavigationStack {
            Group {
                if carrera.estado == .detenida {
                    lobbyCelu
                } else {
                    PantallaCarreraCelu(carrera: carrera)
                }
            }
            .navigationTitle("Correr")
        }
        // El feedback subjetivo aparece UNA vez, al terminar de
        // guardar, y se puede cerrar sin responder nada.
        .sheet(item: $almacen.sesionParaFeedback) { analisis in
            FeedbackSesionView(almacen: almacen, sesionID: analisis.sesionID,
                               analisis: analisis) {
                almacen.sesionParaFeedback = nil
            }
        }
    }

    /// El lobby responde UNA pregunta: ¿qué puedo correr AHORA? Con
    /// entrenamiento pendiente hoy, ESE es el protagonista y Carrera
    /// Libre queda como alternativa. Sin entrenamiento hoy, Carrera
    /// Libre es la principal y el próximo programado aparece como
    /// contexto (nunca como traba).
    private var lobbyCelu: some View {
        let hoy = DiaLocal(fecha: Date())
        let deHoy = almacen.almacen.entrenamientoDeHoy(hoy)
        return ScrollView {
            VStack(spacing: DV2.Espacio.l) {
                if let resumen = carrera.resumen {
                    tarjetaResumen(resumen)
                }

                if let deHoy {
                    // Entrenamiento de hoy y Carrera Libre son dos
                    // acciones distintas que llegan al MISMO motor.
                    TarjetaEntrenamientoV2(programado: deHoy, mostrarEstructura: true) {
                        LanzadorSesion.iniciar(definicion: deHoy.definicion,
                                               programadoID: deHoy.id,
                                               store: store, almacen: almacen)
                    }
                    .padding(.horizontal)

                    botonCarreraLibre(protagonista: false)
                        .padding(.horizontal)
                } else if almacen.almacen.perfilDeportivo.testPendiente {
                    // El Test 5K del onboarding: disponible, nunca
                    // forzado — un entrenamiento real más.
                    TarjetaTest5K {
                        LanzadorSesion.iniciar(definicion: LanzadorSesion.definicionTest5K(),
                                               programadoID: nil,
                                               store: store, almacen: almacen)
                    }
                    .padding(.horizontal)

                    botonCarreraLibre(protagonista: false)
                        .padding(.horizontal)
                } else {
                    if let cumplidoHoy = almacen.almacen.programadoDelDia(hoy),
                       cumplidoHoy.resolucion != .pendiente {
                        TarjetaEntrenamientoV2(programado: cumplidoHoy)
                            .padding(.horizontal)
                    }

                    botonCarreraLibre(protagonista: true)
                        .padding(.horizontal)

                    if let proximo = almacen.almacen
                        .proximosEntrenamientos(despuesDe: hoy, maximo: 1).first {
                        TarjetaEntrenamientoV2(programado: proximo,
                                               etiqueta: etiquetaProxima(proximo))
                            .padding(.horizontal)
                    }
                }

                // Bloque compacto: cómo se va a REGISTRAR esta carrera
                // — todo junto, nada flotando.
                TarjetaV2 {
                    VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                        EncabezadoSeccionV2(texto: "Cómo se registra")
                        Toggle(isOn: $autoPausa) {
                            Label("Auto-pausa en las paradas", systemImage: "pause.circle.fill")
                                .font(.subheadline)
                        }
                        Label("Sin Apple Watch: el GPS del teléfono mide la distancia. Llevá el celu con vos y los auriculares puestos.",
                              systemImage: "iphone")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                if let error = carrera.mensajeError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)
        }
    }

    /// Carrera Libre como tarjeta: grande y verde cuando es LA acción
    /// del día, sobria cuando el protagonista es el entrenamiento.
    private func botonCarreraLibre(protagonista: Bool) -> some View {
        TarjetaV2 {
            VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                HStack {
                    Text(protagonista ? "AHORA" : "TAMBIÉN PODÉS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(protagonista ? Color.green : Color.secondary)
                        .tracking(1)
                    Spacer()
                }
                Text("Carrera libre")
                    .font(protagonista ? .title3.weight(.bold) : .headline)
                Text("Corrés sin objetivo obligatorio de distancia ni tiempo.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !store.plan.tramosActivos.isEmpty {
                    // El camino personalizado, dicho con todas las
                    // letras: acá corren TUS tramos importados.
                    Text("Corre con tu estructura personalizada: el reloj anuncia cada tramo y corrige por voz.")
                        .font(.caption)
                        .foregroundStyle(DV2.Marca.primario)
                }
                Text(datosDelPlan)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button {
                    LanzadorSesion.iniciar(definicion: nil, programadoID: nil,
                                           store: store, almacen: almacen)
                } label: {
                    if protagonista {
                        Label("Empezar", systemImage: "play.fill")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DV2.Espacio.m)
                            .background(Color.green,
                                        in: RoundedRectangle(cornerRadius: DV2.radioBoton))
                    } else {
                        // Acción SECUNDARIA pero claramente tocable:
                        // estilo de borde con el tint de Maratonia (no
                        // el gris que parecía deshabilitado).
                        Label("Correr libre", systemImage: "play.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DV2.Marca.primario)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DV2.Espacio.s)
                            .background(
                                RoundedRectangle(cornerRadius: DV2.radioBoton)
                                    .strokeBorder(DV2.Marca.primario.opacity(0.5), lineWidth: 1.5))
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// "PRÓXIMO · MAR 12/8" para la tarjeta de contexto.
    private func etiquetaProxima(_ programado: EntrenamientoProgramado) -> String {
        guard let fecha = programado.dia?.fecha() else { return String(localized: "PRÓXIMO") }
        return String(localized: "PRÓXIMO · \(FormatoFecha.diaCorto(fecha).uppercased())")
    }

    private var datosDelPlan: String {
        var partes: [String] = []
        if !store.plan.pistas.isEmpty { partes.append(Plurales.pistas(store.plan.pistas.count)) }
        let avisos = store.plan.cronograma(duracionMaximaMinutos: 600).count
            + store.plan.avisosKmActivos.count
        if avisos > 0 { partes.append("\(avisos) avisos") }
        if !store.plan.tramosActivos.isEmpty { partes.append(Plurales.tramos(store.plan.tramosActivos.count)) }
        return partes.isEmpty ? "Solo GPS: distancia, ritmo y mapa." : partes.joined(separator: " · ")
    }

    private func tarjetaResumen(_ resumen: ResumenCelu) -> some View {
        VStack(spacing: 8) {
            Text(resumen.guardadaEnSalud ? "¡Carrera guardada!" : "Carrera terminada")
                .font(.headline)
            HStack(spacing: 8) {
                Chip(texto: String(format: "%.2f km", resumen.distanciaMetros / 1000))
                Chip(texto: formatearDuracion(resumen.duracion))
                if let ritmo = resumen.ritmoPromedioSegKm {
                    Chip(texto: "\(formatearRitmo(ritmo)) /km")
                }
            }
            Text(resumen.puntosRuta > 0
                 ? "Recorrido: \(resumen.puntosRuta) puntos GPS · vela en «Carreras»."
                 : "Sin señal GPS: quedó sin recorrido.")
                .font(.footnote)
                .foregroundStyle(resumen.puntosRuta > 0 ? Color.secondary : Color.orange)
            Button("Listo") { carrera.resumen = nil }
                .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: Diseno.radioTarjeta))
        .padding(.horizontal)
    }
}

/// La pantalla durante la carrera: cronómetro protagonista, métricas y
/// los mismos controles redondos que el reloj.
struct PantallaCarreraCelu: View {
    @ObservedObject var carrera: CarreraCelu
    @State private var confirmandoTerminar = false
    @State private var confirmandoCancelar = false

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 0) {
                    Text(formatearDuracion(carrera.tiempoTranscurrido))
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("TIEMPO")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)
                }
                .padding(.top, 10)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    TarjetaEstadistica(titulo: "Distancia",
                                       valor: String(format: "%.2f km", carrera.distanciaMetros / 1000),
                                       icono: "figure.run", color: .green)
                    TarjetaEstadistica(titulo: "Ritmo",
                                       valor: carrera.ritmoActualSegKm.map { "\(formatearRitmo($0)) /km" } ?? "–:–– /km",
                                       icono: "speedometer", color: .orange)
                }
                .padding(.horizontal)

                tarjetaTramo

                infoSecundaria

                controles

                if let error = carrera.mensajeError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(.bottom, 20)
        }
        .confirmationDialog("¿Terminar la carrera?", isPresented: $confirmandoTerminar) {
            Button("Terminar y guardar", role: .destructive) { carrera.terminar() }
            Button("Seguir", role: .cancel) {}
        } message: {
            Text("La carrera se guarda en Salud.")
        }
        .confirmationDialog("¿Cancelar la carrera?", isPresented: $confirmandoCancelar) {
            Button("Descartar todo", role: .destructive) { carrera.cancelar() }
            Button("Seguir", role: .cancel) {}
        } message: {
            Text("No se guarda nada. No se puede deshacer.")
        }
    }

    /// El tramo EN CURSO como tarjeta con barra de progreso y el
    /// siguiente a la vista: durante la carrera importa "qué estoy
    /// haciendo y qué viene", no la lista entera.
    @ViewBuilder
    private var tarjetaTramo: some View {
        if let tramo = carrera.tramoActual {
            TarjetaV2 {
                VStack(alignment: .leading, spacing: DV2.Espacio.s) {
                    HStack {
                        Text("TRAMO \(carrera.indiceTramoUI + 1) DE \(carrera.tramosDelPlan.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(Color.accentColor)
                            .tracking(1)
                        Spacer()
                        if let texto = carrera.textoProgresoTramo {
                            Text(texto)
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(tramo.nombre)
                        .font(.headline)
                    Text(tramo.descripcion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let fraccion = carrera.fraccionTramo {
                        ProgressView(value: fraccion)
                            .tint(.green)
                    }
                    if carrera.indiceTramoUI + 1 < carrera.tramosDelPlan.count {
                        let siguiente = carrera.tramosDelPlan[carrera.indiceTramoUI + 1]
                        Text("Siguiente: \(siguiente.nombre) · \(siguiente.descripcion)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Último tramo del plan")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal)
        } else if !carrera.tramosDelPlan.isEmpty,
                  carrera.indiceTramoUI >= carrera.tramosDelPlan.count {
            Label("Plan de tramos completado", systemImage: "checkmark.seal.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.green)
        }
    }

    @ViewBuilder
    private var infoSecundaria: some View {
        if !carrera.nombrePistaActual.isEmpty {
            Label(nombreSinExtension(carrera.nombrePistaActual), systemImage: "music.note")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        if carrera.estado == .corriendo, carrera.puntosRuta == 0 {
            Label("GPS: buscando señal…", systemImage: "location.slash")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
        if carrera.estado == .pausada {
            Text(carrera.enPausaAutomatica
                 ? "Pausa automática — al arrancar sigue solo"
                 : "En pausa — todo congelado")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.orange)
        }
    }

    private var controles: some View {
        VStack(spacing: 14) {
            HStack(spacing: 22) {
                botonRedondo(carrera.estado == .corriendo ? "Pausar" : "Reanudar",
                             icono: carrera.estado == .corriendo ? "pause.fill" : "play.fill",
                             color: carrera.estado == .corriendo ? .orange : .green) {
                    carrera.alternarPausa()
                }
                botonRedondo(carrera.musicaSilenciada ? "Música" : "Silenciar",
                             icono: carrera.musicaSilenciada ? "speaker.fill" : "speaker.slash.fill",
                             color: .blue) {
                    carrera.alternarSoloMusica()
                }
                botonRedondo("Siguiente", icono: "forward.fill", color: .teal) {
                    carrera.siguiente()
                }
            }
            HStack(spacing: 22) {
                botonRedondo("Aviso", icono: "speaker.wave.2.fill", color: .purple) {
                    carrera.probarAviso()
                }
                botonRedondo("Terminar", icono: "stop.fill", color: .red) {
                    confirmandoTerminar = true
                }
                botonRedondo("Cancelar", icono: "xmark", color: .gray) {
                    confirmandoCancelar = true
                }
            }
        }
        .padding(.top, 6)
    }

    private func botonRedondo(_ titulo: String, icono: String, color: Color,
                              accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            VStack(spacing: 5) {
                Image(systemName: icono)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 62, height: 62)
                    .background(Circle().fill(color.opacity(0.18)))
                Text(titulo)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
    }
}
