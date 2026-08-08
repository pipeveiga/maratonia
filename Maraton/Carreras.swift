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
        // Después de la primera vez, cada entrada a la pestaña vuelve a
        // consultar: los workouts del reloj tardan minutos en sincronizar
        // y con una sola consulta la lista quedaba vieja hasta reabrir.
        guard !yaCargo else {
            consultarWorkouts()
            return
        }
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

    /// Para el gesto de "tirar hacia abajo" de la lista.
    func recargar() async {
        await withCheckedContinuation { continuacion in
            consultarWorkouts { continuacion.resume() }
        }
    }

    private func consultarWorkouts(alTerminar: (() -> Void)? = nil) {
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
                    self.mensaje = "Todavía no hay carreras. Corré con «Registrar carrera» activado en el reloj y van a aparecer acá solas. Ojo: la sincronización desde el reloj puede tardar unos minutos — tirá la lista hacia abajo para actualizar."
                } else {
                    self.mensaje = nil
                }
                alTerminar?()
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
                if store.carreras.isEmpty {
                    ContentUnavailableView {
                        Label("Sin carreras todavía", systemImage: "figure.run")
                    } description: {
                        Text(mensaje)
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Text(mensaje)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(store.carreras) { carrera in
                NavigationLink {
                    CarreraDetalleView(store: store, id: carrera.id)
                } label: {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.blue, .teal],
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing))
                            Image(systemName: "figure.run")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 44, height: 44)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(carrera.fecha.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                            HStack(spacing: 6) {
                                Chip(texto: String(format: "%.2f km", carrera.distanciaMetros / 1000))
                                Chip(texto: formatearDuracion(carrera.duracion))
                                if let ritmo = carrera.ritmoPromedioSegKm {
                                    Chip(texto: "\(formatearRitmo(ritmo)) /km")
                                }
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("Mis carreras")
        .onAppear { store.cargar() }
        .refreshable { await store.recargar() }
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

                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                              spacing: 10) {
                        TarjetaEstadistica(titulo: "Distancia",
                                           valor: String(format: "%.2f km", carrera.distanciaMetros / 1000),
                                           icono: "figure.run", color: .green)
                        TarjetaEstadistica(titulo: "Tiempo",
                                           valor: formatearDuracion(carrera.duracion),
                                           icono: "stopwatch.fill", color: .blue)
                        if let ritmo = carrera.ritmoPromedioSegKm {
                            TarjetaEstadistica(titulo: "Ritmo promedio",
                                               valor: "\(formatearRitmo(ritmo)) /km",
                                               icono: "speedometer", color: .orange)
                        }
                        if let fc = carrera.fcPromedio {
                            TarjetaEstadistica(titulo: "FC promedio",
                                               valor: "\(Int(fc)) ppm",
                                               icono: "heart.fill", color: .red)
                        }
                        if let kcal = carrera.calorias {
                            TarjetaEstadistica(titulo: "Calorías",
                                               valor: "\(Int(kcal)) kcal",
                                               icono: "flame.fill", color: .pink)
                        }
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                } header: {
                    Text(carrera.fecha.formatted(date: .long, time: .shortened))
                }
            }
            .navigationTitle("Carrera")
            .navigationBarTitleDisplayMode(.inline)
        } else {
            Text("No encontré esta carrera.")
                .foregroundStyle(.secondary)
        }
    }
}
