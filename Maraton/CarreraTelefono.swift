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

    /// true mientras la auto-pausa tiene todo congelado; el GPS sigue
    /// vivo solo para detectar que arrancaste de nuevo.
    @Published var enPausaAutomatica = false
    private var ubicacionPausa: CLLocation?

    private var autoPausaActiva: Bool {
        UserDefaults.standard.object(forKey: "autoPausaCelu") as? Bool ?? true
    }

    // Música: cola de pistas en loop, como en el reloj.
    private var pistas: [String] = []
    private var urlDe: (String) -> URL? = { _ in nil }
    private var indicePista = 0
    private var player: AVAudioPlayer?

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

    // Tramos con objetivo de ritmo.
    private var tramos: [Tramo] = []
    private var indiceTramo = 0
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
    }

    private static var permiteUbicacionEnFondo: Bool {
        let modos = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] ?? []
        return modos.contains("location")
    }

    /// La voz en español más cercana: es-AR, si no es-MX, si no es-ES.
    private static var vozEnEspanol: AVSpeechSynthesisVoice? {
        for idioma in ["es-AR", "es-MX", "es-ES"] {
            if let voz = AVSpeechSynthesisVoice(language: idioma) { return voz }
        }
        return nil
    }

    // MARK: - Arranque

    func iniciar(plan: Plan, urlDe: @escaping (String) -> URL?) {
        guard estado == .detenida else { return }
        resumen = nil
        mensajeError = nil
        self.urlDe = urlDe
        pistas = plan.pistas
        indicePista = 0
        avisosPendientes = plan.cronograma(duracionMaximaMinutos: 600)
        avisosKm = plan.avisosKmActivos
        proximoDisparoKm = Dictionary(uniqueKeysWithValues: avisosKm.map { ($0.id, $0.kilometro) })
        tramos = plan.tramosActivos
        indiceTramo = 0
        tramoActual = tramos.first
        fechaInicioTramo = nil
        fechaUltimaCorreccion = nil
        ultimoKmAnunciado = 0
        tiempoAlUltimoKm = 0
        distanciaMetros = 0
        puntosRuta = 0
        ritmoActualSegKm = nil
        muestras = []
        ultimaUbicacion = nil
        musicaSilenciada = false
        acumuladoPrevio = 0
        fechaReanudacion = Date()
        tiempoTranscurrido = 0
        fechaInicio = Date()

        do {
            let sesion = AVAudioSession.sharedInstance()
            try sesion.setCategory(.playback, mode: .default, options: [])
            try sesion.setActive(true)
        } catch {
            mensajeError = "No pude activar el audio: \(error.localizedDescription)"
        }
        reproducirPistaActual()

        arrancarGPS()
        pedirPermisosSalud()

        estado = .corriendo
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
            mensajeError = "Ubicación negada: sin distancia, ritmo ni mapa. Activala en Ajustes → Privacidad → Localización → Maratonia."
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
                    self.mensajeError = "Salud tiene negado el permiso de guardar entrenamientos: la carrera NO se va a guardar. Activalo en Salud → Compartir → Apps → Maratonia."
                    return
                }
                let configuracion = HKWorkoutConfiguration()
                configuracion.activityType = .running
                configuracion.locationType = .outdoor
                let nuevo = HKWorkoutBuilder(healthStore: self.healthStore,
                                             configuration: configuracion,
                                             device: .local())
                nuevo.beginCollection(withStart: self.fechaInicio) { _, _ in }
                self.builder = nuevo
                self.routeBuilder = HKWorkoutRouteBuilder(healthStore: self.healthStore, device: nil)
            }
        }
    }

    // MARK: - Tick (una vez por segundo)

    private func tick() {
        guard estado == .corriendo, let reanudacion = fechaReanudacion else { return }
        tiempoTranscurrido = acumuladoPrevio + Date().timeIntervalSince(reanudacion)

        // Ritmo suavizado sobre ~45 s, igual que el reloj.
        let ahora = Date()
        muestras.append((ahora, distanciaMetros))
        muestras.removeAll { ahora.timeIntervalSince($0.fecha) > 60 }

        // Auto-pausa: ~10 s casi sin avanzar (menos de 6 m) = parado.
        // Exige puntos GPS reales: sin señal (o sin permiso) no hay
        // manera de detectar el arranque y quedaría pausada para siempre.
        if autoPausaActiva, puntosRuta > 0, tiempoTranscurrido > 30,
           let vieja = muestras.first(where: { ahora.timeIntervalSince($0.fecha) <= 10 }),
           ahora.timeIntervalSince(vieja.fecha) >= 9,
           distanciaMetros - vieja.metros < 6 {
            pausar(automatica: true)
            anunciar("Pausa automática.")
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
        while let primero = avisosPendientes.first, primero.minuto <= minuto {
            avisosPendientes.removeFirst()
            anunciar(primero.texto)
        }
    }

    private func chequearSplits() {
        let km = Int(distanciaMetros / 1000)
        guard km > ultimoKmAnunciado, tiempoTranscurrido > 0 else { return }
        let parcial = tiempoTranscurrido - tiempoAlUltimoKm
        let cubiertos = km - ultimoKmAnunciado
        ultimoKmAnunciado = km
        tiempoAlUltimoKm = tiempoTranscurrido
        if cubiertos == 1, parcial > 60, parcial < 30 * 60 {
            anunciar("Kilómetro \(km): \(ritmoParaHablar(Int(parcial))) el último.")
        } else {
            anunciar("Kilómetro \(km).")
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
        guard !tramos.isEmpty, indiceTramo < tramos.count else { return }

        guard let inicioTramo = fechaInicioTramo else {
            fechaInicioTramo = Date()
            anunciar(anuncio(de: tramos[indiceTramo], numero: indiceTramo + 1))
            return
        }

        let finTramoMetros = tramos.prefix(indiceTramo + 1).reduce(0) { $0 + $1.kilometros * 1000 }
        if distanciaMetros >= finTramoMetros {
            indiceTramo += 1
            if indiceTramo < tramos.count {
                tramoActual = tramos[indiceTramo]
                fechaInicioTramo = Date()
                fechaUltimaCorreccion = nil
                anunciar(anuncio(de: tramos[indiceTramo], numero: indiceTramo + 1))
            } else {
                tramoActual = nil
                anunciar("Plan de tramos completado. ¡Bien ahí!")
            }
            return
        }

        guard let ritmo = ritmoActualSegKm, let tramo = tramoActual else { return }
        guard Date().timeIntervalSince(inicioTramo) >= 45 else { return }
        if let ultima = fechaUltimaCorreccion, Date().timeIntervalSince(ultima) < 60 { return }

        if let rapido = tramo.ritmoMinSegKm, ritmo < rapido - margenSegKm {
            fechaUltimaCorreccion = Date()
            anunciar("Vas a \(ritmoParaHablar(ritmo)). Objetivo \(ritmoParaHablar(rapido)). Aflojá un poco.")
        } else if let lento = tramo.ritmoMaxSegKm, ritmo > lento + margenSegKm {
            fechaUltimaCorreccion = Date()
            anunciar("Vas a \(ritmoParaHablar(ritmo)). Objetivo \(ritmoParaHablar(lento)). Apurá un poco.")
        }
    }

    private func anuncio(de tramo: Tramo, numero: Int) -> String {
        let km = tramo.kilometros == tramo.kilometros.rounded()
            ? "\(Int(tramo.kilometros))"
            : String(format: "%.1f", tramo.kilometros)
        var texto = "Tramo \(numero): \(tramo.nombre). \(km) kilómetros"
        switch (tramo.ritmoMinSegKm, tramo.ritmoMaxSegKm) {
        case let (rapido?, lento?):
            texto += ", entre \(ritmoParaHablar(rapido)) y \(ritmoParaHablar(lento)) por kilómetro."
        case let (nil, lento?):
            texto += ", a \(ritmoParaHablar(lento)) por kilómetro o mejor."
        case let (rapido?, nil):
            texto += ", sin pasar de \(ritmoParaHablar(rapido)) por kilómetro."
        default:
            texto += ", a ritmo libre."
        }
        return texto
    }

    // MARK: - Voz (pausa la música, habla, y la música sigue)

    private func anunciar(_ texto: String) {
        if player?.isPlaying == true {
            player?.pause()
        }
        let frase = AVSpeechUtterance(string: texto)
        frase.voice = Self.vozEnEspanol
        voz.speak(frase)
    }

    /// Para probar el volumen y la voz antes de salir.
    func probarAviso() {
        anunciar("Probando, probando. Así se escuchan los avisos.")
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
            if estado != .pausada && !musicaSilenciada {
                nuevo.play()
            }
        } catch {
            mensajeError = "No pude reproducir \(nombre)."
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
        } else if estado == .corriendo {
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
        if !musicaSilenciada { player?.play() }
        ubicaciones.startUpdatingLocation()
        agregarEvento(.resume)
    }

    /// Pausas y reanudaciones quedan registradas en el workout para que
    /// Salud descuente el tiempo parado.
    private func agregarEvento(_ tipo: HKWorkoutEventType) {
        guard let builder else { return }
        let evento = HKWorkoutEvent(type: tipo,
                                    dateInterval: DateInterval(start: Date(), duration: 0),
                                    metadata: nil)
        builder.addWorkoutEvents([evento]) { _, _ in }
    }

    func terminar() {
        guard estado != .detenida else { return }
        if estado == .corriendo, let reanudacion = fechaReanudacion {
            acumuladoPrevio += Date().timeIntervalSince(reanudacion)
        }
        let duracion = acumuladoPrevio
        let ritmoPromedio = distanciaMetros > 100
            ? Int(duracion / distanciaMetros * 1000)
            : nil
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
        let fin = Date()
        let cerrar: () -> Void = { [weak self] in
            builder.endCollection(withEnd: fin) { _, errorColeccion in
                builder.finishWorkout { workout, errorFinal in
                    if let workout, let rutas = self?.routeBuilder, (self?.puntosRuta ?? 0) > 0 {
                        rutas.finishRoute(with: workout, metadata: nil) { _, _ in }
                    }
                    DispatchQueue.main.async {
                        if let error = errorFinal ?? errorColeccion {
                            self?.mensajeError = "La carrera NO se pudo guardar en Salud: \(error.localizedDescription)"
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
            builder.add([muestra]) { _, _ in cerrar() }
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
        fechaReanudacion = nil
    }
}

extension CarreraCelu: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        guard estado != .detenida else { return }
        siguiente()
    }
}

extension CarreraCelu: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        // Reanudar la música solo cuando no quedan frases en cola.
        guard !synthesizer.isSpeaking, estado == .corriendo, !musicaSilenciada else { return }
        player?.play()
    }
}

extension CarreraCelu: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Auto-pausa: si te alejaste más de 15 m del punto donde
        // frenaste, la carrera sigue sola.
        if estado == .pausada, enPausaAutomatica {
            // Precisión hasta 50 m con umbral dinámico: con mala señal
            // urbana, exigir 20 m de precisión dejaba la pausa clavada.
            guard let ubicacion = locations.last,
                  ubicacion.horizontalAccuracy > 0, ubicacion.horizontalAccuracy <= 50 else { return }
            if let referencia = ubicacionPausa {
                let umbral = max(15, ubicacion.horizontalAccuracy)
                if ubicacion.distance(from: referencia) > umbral {
                    reanudar()
                    anunciar("Seguimos.")
                }
            } else {
                ubicacionPausa = ubicacion
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
        puntosRuta += buenas.count
        routeBuilder?.insertRouteData(buenas) { _, _ in }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard estado != .detenida else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.startUpdatingLocation()
        case .denied, .restricted:
            mensajeError = "Ubicación negada: sin distancia, ritmo ni mapa. Activala en Ajustes → Privacidad → Localización → Maratonia."
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError, clError.code == .denied {
            mensajeError = "Ubicación negada: sin distancia, ritmo ni mapa. Activala en Ajustes → Privacidad → Localización → Maratonia."
        }
    }
}

// MARK: - Pestaña Correr

struct CorrerTab: View {
    @ObservedObject var store: PlanStore
    @ObservedObject private var carrera = CarreraCelu.compartida
    @AppStorage("autoPausaCelu") private var autoPausa = true

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
    }

    private var lobbyCelu: some View {
        ScrollView {
            VStack(spacing: 18) {
                if let resumen = carrera.resumen {
                    tarjetaResumen(resumen)
                }

                VStack(spacing: 6) {
                    Text(store.plan.nombre)
                        .font(.title3.bold())
                    Text(datosDelPlan)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)

                Button {
                    carrera.iniciar(plan: store.plan, urlDe: { store.urlDePista($0) })
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 40, weight: .heavy))
                        .foregroundStyle(.white)
                        .frame(width: 104, height: 104)
                        .background(Circle().fill(Color.green.gradient))
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)

                Toggle(isOn: $autoPausa) {
                    Label("Auto-pausa en las paradas", systemImage: "pause.circle.fill")
                        .font(.subheadline)
                }
                .frame(maxWidth: 320)
                .padding(.horizontal)

                Label("Sin Apple Watch: el GPS del teléfono mide la distancia. Llevá el celu con vos y los auriculares puestos.",
                      systemImage: "iphone")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
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

    private var datosDelPlan: String {
        var partes: [String] = []
        if !store.plan.pistas.isEmpty { partes.append("\(store.plan.pistas.count) pistas") }
        let avisos = store.plan.cronograma(duracionMaximaMinutos: 600).count
            + store.plan.avisosKmActivos.count
        if avisos > 0 { partes.append("\(avisos) avisos") }
        if !store.plan.tramosActivos.isEmpty { partes.append("\(store.plan.tramosActivos.count) tramos") }
        return partes.isEmpty ? "Plan vacío: igual podés correr con GPS." : partes.joined(separator: " · ")
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

    @ViewBuilder
    private var infoSecundaria: some View {
        if !carrera.nombrePistaActual.isEmpty {
            Label(nombreSinExtension(carrera.nombrePistaActual), systemImage: "music.note")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        if let tramo = carrera.tramoActual {
            Text("\(tramo.nombre): \(tramo.descripcion)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
