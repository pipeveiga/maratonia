import Foundation
import HealthKit

// La sesión de entrenamiento del reloj (HKWorkoutSession + builder).
// Al iniciarla, el reloj entra en modo workout: sensores activos, FC en
// tiempo real, distancia estimada, y al finalizar la carrera queda
// guardada en Salud/Fitness como un running al aire libre.
//
// OJO: mientras esta sesión está activa NO se puede usar Runna (u otra
// app de tracking) a la vez — watchOS permite una sola sesión. Para
// correr con Runna, usar el modo "solo audio" (el switch del lobby).

final class Entrenamiento: NSObject, ObservableObject {
    static let compartido = Entrenamiento()

    @Published var activo = false
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

    // Muestras (fecha, metros) del último minuto para suavizar el ritmo:
    // el pace crudo del GPS/sensores salta demasiado para corregir en voz.
    private var muestras: [(fecha: Date, metros: Double)] = []
    private var timerMuestras: Timer?
    private var inicioSesion: Date?

    func pedirPermisos(alTerminar: @escaping () -> Void) {
        guard HKHealthStore.isHealthDataAvailable() else {
            mensajeError = "HealthKit no está disponible en este dispositivo."
            alTerminar()
            return
        }
        let paraCompartir: Set<HKSampleType> = [HKQuantityType.workoutType()]
        let paraLeer: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceWalkingRunning),
        ]
        healthStore.requestAuthorization(toShare: paraCompartir, read: paraLeer) { _, _ in
            DispatchQueue.main.async {
                alTerminar()
            }
        }
    }

    func iniciar() {
        guard sesion == nil else { return }
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
            frecuenciaCardiaca = 0
            distanciaMetros = 0
            caloriasActivas = 0
            ritmoActualSegKm = nil
            ritmoPromedioSegKm = nil
            muestras = []
            inicioSesion = inicio
            mensajeError = nil
            activo = true

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

    /// Termina la sesión y guarda el workout en Salud. La limpieza final
    /// ocurre en el delegate, cuando la sesión pasa a .ended.
    func finalizar() {
        timerMuestras?.invalidate()
        timerMuestras = nil
        sesion?.end()
    }

    /// Una vez por segundo: agrega la muestra, recalcula el ritmo
    /// suavizado y el promedio, y le pasa el estado al entrenador de ritmo.
    private func registrarMuestra() {
        guard activo else { return }
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

        if let inicio = inicioSesion, distanciaMetros > 50 {
            ritmoPromedioSegKm = Int(ahora.timeIntervalSince(inicio) / distanciaMetros * 1000)
        }

        EntrenadorRitmo.compartido.chequear(
            distanciaMetros: distanciaMetros,
            ritmoActualSegKm: ritmoActualSegKm)
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
        builder?.endCollection(withEnd: date) { [weak self] _, _ in
            self?.builder?.finishWorkout { _, _ in
                DispatchQueue.main.async {
                    self?.activo = false
                    self?.sesion = nil
                    self?.builder = nil
                }
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        DispatchQueue.main.async {
            self.mensajeError = "Entrenamiento: \(error.localizedDescription)"
            self.activo = false
            self.sesion = nil
            self.builder = nil
            self.timerMuestras?.invalidate()
            self.timerMuestras = nil
        }
    }
}

extension Entrenamiento: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        actualizarEstadisticas(con: collectedTypes)
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
