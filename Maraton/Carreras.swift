import Foundation
import HealthKit
import SwiftUI
import MapKit

// Historial de carreras en el iPhone. Los entrenamientos que graba el
// reloj llegan solos por la sincronización de Salud; acá se listan los
// de Maratonia con sus números (tiempo, distancia, ritmo, FC, calorías)
// y el recorrido dibujado en un mapa.

struct CarreraResumen: Identifiable {
    let id = UUID()
    let workout: HKWorkout
    var fcPromedio: Double?
    var ruta: [CLLocationCoordinate2D] = []
    var rutaCargada = false

    var fecha: Date { workout.startDate }
    var duracion: TimeInterval { workout.duration }
    var distanciaMetros: Double {
        workout.totalDistance?.doubleValue(for: .meter()) ?? 0
    }
    var calorias: Double? {
        workout.totalEnergyBurned?.doubleValue(for: .kilocalorie())
    }
    var ritmoPromedioSegKm: Int? {
        guard distanciaMetros > 100 else { return nil }
        return Int(duracion / distanciaMetros * 1000)
    }
}

final class CarrerasStore: ObservableObject {
    @Published var carreras: [CarreraResumen] = []
    @Published var mensaje: String?

    private let healthStore = HKHealthStore()
    private var yaCargo = false

    func cargar() {
        guard !yaCargo else { return }
        yaCargo = true
        guard HKHealthStore.isHealthDataAvailable() else {
            mensaje = "Salud no está disponible en este dispositivo."
            return
        }
        let paraLeer: Set<HKObjectType> = [
            HKObjectType.workoutType(),
            HKSeriesType.workoutRoute(),
            HKQuantityType(.heartRate),
        ]
        healthStore.requestAuthorization(toShare: [], read: paraLeer) { [weak self] _, _ in
            self?.consultarWorkouts()
        }
    }

    private func consultarWorkouts() {
        let predicado = HKQuery.predicateForWorkouts(with: .running)
        let orden = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)
        let consulta = HKSampleQuery(
            sampleType: .workoutType(), predicate: predicado,
            limit: 50, sortDescriptors: [orden]
        ) { [weak self] _, muestras, error in
            guard let self else { return }
            let nuestras = (muestras as? [HKWorkout] ?? []).filter {
                $0.sourceRevision.source.bundleIdentifier.hasPrefix("com.pipeveiga.maraton")
            }
            DispatchQueue.main.async {
                self.carreras = nuestras.map { CarreraResumen(workout: $0) }
                if let error {
                    self.mensaje = "No pude leer Salud: \(error.localizedDescription)"
                } else if nuestras.isEmpty {
                    self.mensaje = "Todavía no hay carreras. Corré con «Registrar carrera» activado en el reloj y van a aparecer acá solas."
                } else {
                    self.mensaje = nil
                }
            }
            nuestras.forEach { self.cargarDetalles(de: $0) }
        }
        healthStore.execute(consulta)
    }

    private func cargarDetalles(de workout: HKWorkout) {
        // FC promedio de la carrera.
        let predicadoFC = HKQuery.predicateForSamples(
            withStart: workout.startDate, end: workout.endDate)
        let consultaFC = HKStatisticsQuery(
            quantityType: HKQuantityType(.heartRate),
            quantitySamplePredicate: predicadoFC,
            options: .discreteAverage
        ) { [weak self] _, estadisticas, _ in
            let ppm = HKUnit.count().unitDivided(by: .minute())
            let promedio = estadisticas?.averageQuantity()?.doubleValue(for: ppm)
            DispatchQueue.main.async {
                self?.actualizar(workout: workout) { $0.fcPromedio = promedio }
            }
        }
        healthStore.execute(consultaFC)

        // Recorrido GPS asociado al workout.
        let predicadoRuta = HKQuery.predicateForObjects(from: workout)
        let consultaRuta = HKSampleQuery(
            sampleType: HKSeriesType.workoutRoute(), predicate: predicadoRuta,
            limit: 1, sortDescriptors: nil
        ) { [weak self] _, muestras, _ in
            guard let self else { return }
            guard let ruta = (muestras as? [HKWorkoutRoute])?.first else {
                DispatchQueue.main.async {
                    self.actualizar(workout: workout) { $0.rutaCargada = true }
                }
                return
            }
            var puntos: [CLLocationCoordinate2D] = []
            let recorrido = HKWorkoutRouteQuery(route: ruta) { _, ubicaciones, terminado, _ in
                if let ubicaciones {
                    puntos.append(contentsOf: ubicaciones.map(\.coordinate))
                }
                if terminado {
                    DispatchQueue.main.async {
                        self.actualizar(workout: workout) {
                            $0.ruta = puntos
                            $0.rutaCargada = true
                        }
                    }
                }
            }
            self.healthStore.execute(recorrido)
        }
        healthStore.execute(consultaRuta)
    }

    private func actualizar(workout: HKWorkout, cambio: (inout CarreraResumen) -> Void) {
        guard let indice = carreras.firstIndex(where: { $0.workout.uuid == workout.uuid }) else { return }
        cambio(&carreras[indice])
    }
}

// MARK: - Pantallas

struct CarrerasView: View {
    @StateObject private var store = CarrerasStore()

    var body: some View {
        List {
            if let mensaje = store.mensaje {
                Text(mensaje)
                    .foregroundStyle(.secondary)
            }
            ForEach(store.carreras) { carrera in
                NavigationLink {
                    CarreraDetalleView(store: store, id: carrera.id)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(carrera.fecha.formatted(date: .abbreviated, time: .shortened))
                        Text("\(String(format: "%.2f km", carrera.distanciaMetros / 1000)) · \(formatearDuracion(carrera.duracion))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Mis carreras")
        .onAppear { store.cargar() }
    }
}

struct CarreraDetalleView: View {
    @ObservedObject var store: CarrerasStore
    let id: UUID

    var body: some View {
        if let carrera = store.carreras.first(where: { $0.id == id }) {
            List {
                Section {
                    if !carrera.ruta.isEmpty {
                        // .automatic encuadra solo el contenido del mapa.
                        Map {
                            MapPolyline(coordinates: carrera.ruta)
                                .stroke(.blue, lineWidth: 4)
                        }
                        .frame(height: 280)
                        .listRowInsets(EdgeInsets())
                    } else if carrera.rutaCargada {
                        Label("Esta carrera no tiene recorrido GPS.", systemImage: "map")
                            .foregroundStyle(.secondary)
                    } else {
                        HStack {
                            ProgressView()
                            Text("Cargando recorrido…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Números") {
                    fila("Fecha", carrera.fecha.formatted(date: .long, time: .shortened))
                    fila("Tiempo", formatearDuracion(carrera.duracion))
                    fila("Distancia", String(format: "%.2f km", carrera.distanciaMetros / 1000))
                    if let ritmo = carrera.ritmoPromedioSegKm {
                        fila("Ritmo promedio", "\(formatearRitmo(ritmo)) /km")
                    }
                    if let fc = carrera.fcPromedio {
                        fila("FC promedio", "\(Int(fc)) ppm")
                    }
                    if let kcal = carrera.calorias {
                        fila("Calorías", "\(Int(kcal)) kcal")
                    }
                }
            }
            .navigationTitle("Carrera")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            Text("No encontré esta carrera.")
                .foregroundStyle(.secondary)
        }
    }

    private func fila(_ titulo: String, _ valor: String) -> some View {
        HStack {
            Text(titulo)
            Spacer()
            Text(valor)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }
}
