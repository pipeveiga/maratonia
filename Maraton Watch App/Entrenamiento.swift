import Foundation
import HealthKit
import CoreLocation

// La sesión de entrenamiento del reloj (HKWorkoutSession + builder).
// Al iniciarla, el reloj entra en modo workout: sensores activos, FC en
// tiempo real, distancia estimada, y al finalizar la carrera queda
// guardada en Salud/Fitness como un running al aire libre.
//
// OJO: mientras esta sesión está activa NO se puede usar Runna (u otra
// app de tracking) a la vez — watchOS permite una sola sesión. Para
// correr con Runna, usar el modo "solo audio" (el switch del lobby).

/// Los números finales de una carrera guardada, para la tarjetita del lobby.
struct ResumenCarrera {
    var duracion: TimeInterval
    var distanciaMetros: Double
    var ritmoPromedioSegKm: Int?
    var fcPromedio: Int?
    var calorias: Double
}

final class Entrenamiento: NSObject, ObservableObject {
    static let compartido = Entrenamiento()

    @Published var activo = false
    @Published var pausado = false

    /// Resumen de la última carrera guardada, para mostrar al volver al
    /// lobby. Se limpia con el botón "Listo" o al arrancar otra sesión.
    @Published var resumen: ResumenCarrera?
    @Published var frecuenciaCardiaca: Double = 0   // pulsaciones por minuto
    @Published var distanciaMetros: Double = 0
    @Published var caloriasActivas: Double = 0
    @Published var mensajeError: String?

    /// Ritmo actual en seg/km, suavizado sobre los últimos ~45 s.
    /// nil = todavía no hay datos o estás prácticamente parado.
    @Published var ritmoActualSegKm: Int?
    /// Ritmo promedio de toda la sesión, en seg/km.
    @Published var ritmoPromedioSegKm: Int?

    private let healthStore = HKHealthStore()
    private var sesion: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    // Ruta GPS: las ubicaciones buenas se acumulan en el routeBuilder y al
    // finalizar se atan al workout, para ver el recorrido en el mapa.
    private let ubicaciones = CLLocationManager()
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var usaGPS = false
    private var descartarAlTerminar = false

    // Muestras (fecha, metros) del último minuto para suavizar el ritmo:
    // el pace crudo del GPS/sensores salta demasiado para corregir en voz.
    private var muestras: [(fecha: Date, metros: Double)] = []
    private var timerMuestras: Timer?

    override private init() {
        super.init()
        ubicaciones.delegate = self
        ubicaciones.desiredAccuracy = kCLLocationAccuracyBest
        ubicaciones.activityType = .fitness
    }

    /// ¿El Info.plist declara el modo "location" en segundo plano?
    /// Activar `allowsBackgroundLocationUpdates` sin ese modo declarado
    /// termina la app al instante, así que nunca se pone a ciegas.
    private static var permiteUbicacionEnFondo: Bool {
        let info = Bundle.main.infoDictionary
        let wk = info?["WKBackgroundModes"] as? [String] ?? []
        let ui = info?["UIBackgroundModes"] as? [String] ?? []
        return wk.contains("location") || ui.contains("location")
    }

    func pedirPermisos(conGPS: Bool, alTerminar: @escaping () -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            mensajeError = "Salud no está disponible en este reloj."
            return
        }
        var paraCompartir: Set<HKSampleType> = [HKQuantityType.workoutType()]
        if conGPS {
            paraCompartir.insert(HKSeriesType.workoutRoute())
            ubicaciones.requestWhenInUseAuthorization()
        }
        let paraLeer: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
        ]
        healthStore.requestAuthorization(toShare: paraCompartir, read: paraLeer) { [weak self] ok, error in
            DispatchQueue.main.async {
                guard ok else {
                    self?.mensajeError = "Sin permisos de Salud: \(error?.localizedDescription ?? "los rechazaste")"
                    return
                }
                alTerminar()
            }
        }
    }

    func iniciar(conGPS: Bool) {
        guard sesion == nil else { return }
        usaGPS = conGPS
        descartarAlTerminar = false
        resumen = nil
        let configuracion = HKWorkoutConfiguration()
        configuracion.activityType = .running
        configuracion.locationType = .outdoor

        do {
            let nuevaSesion = try HKWorkoutSession(healthStore: healthStore, configuration: configuracion)
            let nuevoBuilder = nuevaSesion.associatedWorkoutBuilder()
            nuevoBuilder.dataSource = HKLiveWorkoutDataSource(
                healthStore: healthStore, workoutConfiguration: configuracion)
            nuevaSesion.delegate = self
            nuevoBuilder.delegate = self
            sesion = nuevaSesion
            builder = nuevoBuilder

            let inicio = Date()
            nuevaSesion.startActivity(with: inicio)
            nuevoBuilder.beginCollection(withStart: inicio) { _, _ in }

            if conGPS {
                routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
                // Solo si el modo está declarado: ponerlo sin declararlo
                // termina la app en el acto.
                ubicaciones.allowsBackgroundLocationUpdates = Self.permiteUbicacionEnFondo
                ubicaciones.startUpdatingLocation()
            }
            frecuenciaCardiaca = 0
            distanciaMetros = 0
            caloriasActivas = 0
            ritmoActualSegKm = nil
            ritmoPromedioSegKm = nil
            muestras = []
            mensajeError = nil
            activo = true
            pausado = false

            timerMuestras?.invalidate()
            timerMuestras = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                DispatchQueue.main.async {
                    self?.registrarMuestra()
                }
            }
        } catch {
            mensajeError = "No pude iniciar el entrenamiento: \(error.localizedDescription)"
            sesion = nil
            builder = nil
        }
    }

    /// Pausa REAL del entrenamiento: congela el registro (tiempo del
    /// workout), apaga el GPS y resetea el suavizado de ritmo.
    func pausar() {
        guard activo, !pausado else { return }
        pausado = true
        sesion?.pause()
        if usaGPS { ubicaciones.stopUpdatingLocation() }
        muestras = []
        ritmoActualSegKm = nil
    }

    func reanudar() {
        guard activo, pausado else { return }
        pausado = false
        sesion?.resume()
        if usaGPS { ubicaciones.startUpdatingLocation() }
        muestras = []  // arranca limpio: sin ritmo hasta juntar datos nuevos
    }

    /// Termina la sesión y guarda el workout en Salud. La limpieza final
    /// ocurre en el delegate, cuando la sesión pasa a .ended.
    func finalizar() {
        timerMuestras?.invalidate()
        timerMuestras = nil
        ubicaciones.stopUpdatingLocation()
        if activo, !descartarAlTerminar {
            let ppm = HKUnit.count().unitDivided(by: .minute())
            let fcPromedio = builder?
                .statistics(for: HKQuantityType(.heartRate))?
                .averageQuantity()?
                .doubleValue(for: ppm)
            resumen = ResumenCarrera(
                duracion: builder?.elapsedTime ?? 0,
                distanciaMetros: distanciaMetros,
                ritmoPromedioSegKm: ritmoPromedioSegKm,
                fcPromedio: fcPromedio.map { Int($0) },
                calorias: caloriasActivas)
        }
        sesion?.end()
    }

    /// Cancela la sesión DESCARTANDO todo: el entrenamiento no se guarda
    /// en Salud y la ruta se tira. Para arranques por error o de prueba.
    func cancelar() {
        descartarAlTerminar = true
        finalizar()
    }

    /// Una vez por segundo: agrega la muestra, recalcula el ritmo
    /// suavizado y el promedio, y le pasa el estado al entrenador de ritmo.
    private func registrarMuestra() {
        guard activo, !pausado else { return }
        let ahora = Date()
        muestras.append((ahora, distanciaMetros))
        muestras.removeAll { ahora.timeIntervalSince($0.fecha) > 60 }

        // Ritmo actual: contra la muestra más vieja dentro de ~45 s.
        if let referencia = muestras.first(where: { ahora.timeIntervalSince($0.fecha) <= 45 }) {
            let segundos = ahora.timeIntervalSince(referencia.fecha)
            let metros = distanciaMetros - referencia.metros
            if segundos >= 20 {
                ritmoActualSegKm = metros >= 15 ? Int(segundos / metros * 1000) : nil
            }
        }

        // El promedio usa el tiempo del builder, que descuenta las pausas.
        if let builder, distanciaMetros > 50 {
            ritmoPromedioSegKm = Int(builder.elapsedTime / distanciaMetros * 1000)
        }

        EntrenadorRitmo.compartido.chequear(
            distanciaMetros: distanciaMetros,
            ritmoActualSegKm: ritmoActualSegKm,
            tiempoActivo: builder?.elapsedTime ?? 0)
    }

    private func actualizarEstadisticas(con tipos: Set<HKSampleType>) {
        guard let builder else { return }
        for tipo in tipos {
            guard let tipoCantidad = tipo as? HKQuantityType,
                  let estadisticas = builder.statistics(for: tipoCantidad) else { continue }
            DispatchQueue.main.async {
                switch tipoCantidad {
                case HKQuantityType(.heartRate):
                    let ppm = HKUnit.count().unitDivided(by: .minute())
                    if let valor = estadisticas.mostRecentQuantity()?.doubleValue(for: ppm) {
                        self.frecuenciaCardiaca = valor
                    }
                case HKQuantityType(.distanceWalkingRunning):
                    if let valor = estadisticas.sumQuantity()?.doubleValue(for: .meter()) {
                        self.distanciaMetros = valor
                    }
                case HKQuantityType(.activeEnergyBurned):
                    if let valor = estadisticas.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                        self.caloriasActivas = valor
                    }
                default:
                    break
                }
            }
        }
    }
}

extension Entrenamiento: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        guard toState == .ended else { return }

        if descartarAlTerminar {
            // Cancelación: se tira todo, nada llega a Salud.
            builder?.discardWorkout()
            routeBuilder?.discard()
            DispatchQueue.main.async {
                self.limpiarTrasFinal()
            }
            return
        }

        builder?.endCollection(withEnd: date) { [weak self] _, _ in
            self?.builder?.finishWorkout { workout, _ in
                // Atar la ruta GPS al workout guardado, para el mapa.
                if let workout, let rutas = self?.routeBuilder {
                    rutas.finishRoute(with: workout, metadata: nil) { _, _ in }
                }
                DispatchQueue.main.async {
                    self?.limpiarTrasFinal()
                }
            }
        }
    }

    private func limpiarTrasFinal() {
        activo = false
        pausado = false
        sesion = nil
        builder = nil
        routeBuilder = nil
        descartarAlTerminar = false
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.mensajeError = "Entrenamiento: \(error.localizedDescription)"
            self.activo = false
            self.pausado = false
            self.sesion = nil
            self.builder = nil
            self.routeBuilder = nil
            self.ubicaciones.stopUpdatingLocation()
            self.timerMuestras?.invalidate()
            self.timerMuestras = nil
        }
    }
}

extension Entrenamiento: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard activo, !pausado, let routeBuilder else { return }
        // Solo puntos con precisión decente; los malos ensucian el mapa.
        let buenas = locations.filter { $0.horizontalAccuracy > 0 && $0.horizontalAccuracy <= 50 }
        guard !buenas.isEmpty else { return }
        routeBuilder.insertRouteData(buenas) { _, _ in }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Sin GPS momentáneo (túnel, arranque): no es fatal, la ruta sigue
        // con los puntos que haya.
    }
}

extension Entrenamiento: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        actualizarEstadisticas(con: collectedTypes)
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
