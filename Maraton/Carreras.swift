import Foundation
import HealthKit
import SwiftUI
import MapKit
import UIKit

// Historial de carreras en el iPhone. Los entrenamientos que graba el
// reloj llegan solos por la sincronización de Salud; acá se listan los
// de Maratonia con sus números (tiempo, distancia, ritmo, FC, calorías)
// y el recorrido dibujado en un mapa.

struct CarreraResumen: Identifiable {
    let workout: HKWorkout

    /// ID estable entre recargas: el UUID del workout en Salud. Con un
    /// UUID nuevo por consulta, refrescar la lista con el detalle
    /// abierto lo rompía ("No encontré esta carrera").
    var id: UUID { workout.uuid }
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
    private var consultaEnCurso = false

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
        // Coalescer: onAppear + tirar-para-refrescar podían disparar dos
        // consultas en vuelo que se pisaban el array entre sí.
        guard !consultaEnCurso else {
            alTerminar?()
            return
        }
        consultaEnCurso = true
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
                self.consultaEnCurso = false
                // Fusionar preservando los detalles ya cargados (ruta,
                // FC): reemplazar todo reseteaba mapas y promedios en
                // cada refresh y relanzaba todas las queries de detalle.
                let previos = Dictionary(uniqueKeysWithValues: self.carreras.map { ($0.id, $0) })
                let nuevos = nuestras.filter { previos[$0.uuid] == nil }
                self.carreras = nuestras.map { previos[$0.uuid] ?? CarreraResumen(workout: $0) }
                nuevos.forEach { self.cargarDetalles(de: $0) }
                if let error {
                    self.mensaje = "No pude leer Salud: \(error.localizedDescription)"
                } else if nuestras.isEmpty {
                    self.mensaje = "Todavía no hay carreras. Corré con «Registrar carrera» activado y van a aparecer acá solas (la sincronización desde el reloj tarda unos minutos — tirá hacia abajo para actualizar). Si corriste y no aparecen, revisá los permisos en Salud → Compartir → Apps → Maratonia."
                } else {
                    self.mensaje = nil
                }
                alTerminar?()
            }
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
            let recorrido = HKWorkoutRouteQuery(route: ruta) { _, ubicaciones, terminado, error in
                // Error a mitad de la enumeración: "terminado" no llega
                // nunca y el spinner quedaba girando para siempre.
                if error != nil {
                    DispatchQueue.main.async {
                        self.actualizar(workout: workout) { $0.rutaCargada = true }
                    }
                    return
                }
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
            if !store.carreras.isEmpty {
                seccionProgreso
            }
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

    /// Tarjeta de progreso: la película de tu semana arriba de las fotos
    /// (las carreras sueltas).
    private var seccionProgreso: some View {
        let semana = resumenSemanal
        return Section {
            VStack(alignment: .leading, spacing: 12) {
                Label("ESTA SEMANA", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 0) {
                    estadisticaSemana(String(format: "%.1f", semana.km), "km")
                    estadisticaSemana("\(semana.carreras)",
                                      semana.carreras == 1 ? "carrera" : "carreras")
                    estadisticaSemana(semana.ritmo.map { "\(formatearRitmo($0))" } ?? "–:––",
                                      "ritmo /km")
                }
            }
            .padding(16)
            .background(
                LinearGradient(colors: [Color.accentColor, .teal],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
            .listRowInsets(EdgeInsets())
        }
    }

    private func estadisticaSemana(_ valor: String, _ nombre: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valor)
                .font(.title3.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
            Text(nombre)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var resumenSemanal: (km: Double, carreras: Int, ritmo: Int?) {
        let calendario = Calendar.current
        let ahora = Date()
        let delaSemana = store.carreras.filter {
            calendario.isDate($0.fecha, equalTo: ahora, toGranularity: .weekOfYear)
        }
        let metros = delaSemana.reduce(0.0) { $0 + $1.distanciaMetros }
        let duracion = delaSemana.reduce(0.0) { $0 + $1.duracion }
        let ritmo = metros > 100 ? Int(duracion / metros * 1000) : nil
        return (metros / 1000, delaSemana.count, ritmo)
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
            .toolbar {
                Menu {
                    ShareLink(item: imagenParaCompartir(carrera),
                              preview: SharePreview("Mi carrera con Maratonia",
                                                    image: imagenParaCompartir(carrera))) {
                        Label("Postal con fondo", systemImage: "photo")
                    }
                    ShareLink(item: urlPNGSinFondo(carrera),
                              preview: SharePreview("Mi carrera (PNG sin fondo)",
                                                    image: imagenSinFondo(carrera))) {
                        Label("PNG sin fondo, para tus fotos", systemImage: "photo.on.rectangle.angled")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        } else {
            Text("No encontré esta carrera.")
                .foregroundStyle(.secondary)
        }
    }

    /// La carrera como imagen linda para mandar al grupo o subir a redes.
    private func imagenParaCompartir(_ carrera: CarreraResumen) -> Image {
        let render = ImageRenderer(content: TarjetaCompartir(carrera: carrera, ruta: carrera.ruta))
        render.scale = 3
        if let imagen = render.uiImage {
            return Image(uiImage: imagen)
        }
        return Image(systemName: "figure.run")
    }

    private func imagenSinFondo(_ carrera: CarreraResumen) -> Image {
        let render = ImageRenderer(content: TarjetaCompartir(
            carrera: carrera, ruta: carrera.ruta, transparente: true))
        render.scale = 3
        render.isOpaque = false
        if let imagen = render.uiImage {
            return Image(uiImage: imagen)
        }
        return Image(systemName: "figure.run")
    }

    /// El PNG con transparencia real viaja como ARCHIVO: compartir la
    /// imagen "suelta" puede aplanarla a JPG y perder el alfa.
    private func urlPNGSinFondo(_ carrera: CarreraResumen) -> URL {
        let render = ImageRenderer(content: TarjetaCompartir(
            carrera: carrera, ruta: carrera.ruta, transparente: true))
        render.scale = 3
        render.isOpaque = false
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("maratonia-carrera.png")
        if let imagen = render.uiImage, let datos = imagen.pngData() {
            try? datos.write(to: url)
        }
        return url
    }
}

/// El recorrido como trazo estilo Strava: solo la línea, sin mapa de
/// fondo — queda canchero y no regala calles ni direcciones. Normaliza
/// las coordenadas al rectángulo corrigiendo el aspecto (un grado de
/// longitud mide cos(latitud) de lo que mide uno de latitud).
struct TrazadoRuta: Shape {
    let coordenadas: [CLLocationCoordinate2D]

    func path(in rect: CGRect) -> Path {
        // Adelgazar: con miles de puntos GPS el trazo no gana nada.
        let paso = max(1, coordenadas.count / 300)
        let puntos = stride(from: 0, to: coordenadas.count, by: paso).map { coordenadas[$0] }
        guard puntos.count > 1 else { return Path() }

        let latitudes = puntos.map(\.latitude)
        let longitudes = puntos.map(\.longitude)
        guard let latMin = latitudes.min(), let latMax = latitudes.max(),
              let lonMin = longitudes.min(), let lonMax = longitudes.max() else { return Path() }

        let escalaLon = cos((latMin + latMax) / 2 * .pi / 180)
        let ancho = max((lonMax - lonMin) * escalaLon, 1e-6)
        let alto = max(latMax - latMin, 1e-6)
        let escala = min(rect.width / ancho, rect.height / alto)
        let margenX = (rect.width - ancho * escala) / 2 + rect.minX
        let margenY = (rect.height - alto * escala) / 2 + rect.minY

        func punto(_ c: CLLocationCoordinate2D) -> CGPoint {
            CGPoint(x: margenX + (c.longitude - lonMin) * escalaLon * escala,
                    y: margenY + (latMax - c.latitude) * escala)
        }

        var trazo = Path()
        trazo.move(to: punto(puntos[0]))
        for coordenada in puntos.dropFirst() {
            trazo.addLine(to: punto(coordenada))
        }
        return trazo
    }
}

/// La postal para compartir: el trazado del recorrido protagonista, los
/// km grandes y los números. Dos variantes: con degradado de marca, o
/// transparente (todo blanco con sombra) para pegar sobre fotos.
struct TarjetaCompartir: View {
    let carrera: CarreraResumen
    var ruta: [CLLocationCoordinate2D] = []
    var transparente = false

    private var sombra: Color { transparente ? .black.opacity(0.45) : .clear }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                // El logo real de la app (asset LogoMaratonia, 1024 px:
                // sobra resolución a 22 pt × escala 3). La esquina
                // redondeada lo encapsula como sticker sobre cualquier
                // fondo; la sombra del contenedor ya le da contraste en
                // la variante transparente.
                Image("LogoMaratonia")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 22)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                Text("Maratonia")
                    .font(.headline)
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text(carrera.fecha.formatted(date: .long, time: .omitted))
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.75))

            if ruta.count > 1 {
                TrazadoRuta(coordenadas: ruta)
                    .stroke(.white, style: StrokeStyle(
                        lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(height: 190)
                    .shadow(color: sombra, radius: 3, y: 1)
                    .padding(.vertical, 4)
            }

            Text(String(format: "%.2f km", carrera.distanciaMetros / 1000))
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            HStack(spacing: 26) {
                datoCompartir("TIEMPO", formatearDuracion(carrera.duracion))
                if let ritmo = carrera.ritmoPromedioSegKm {
                    datoCompartir("RITMO", "\(formatearRitmo(ritmo)) /km")
                }
                if let fc = carrera.fcPromedio {
                    datoCompartir("FC MEDIA", "\(Int(fc))")
                }
            }
        }
        .shadow(color: sombra, radius: 2, y: 1)
        .padding(28)
        .frame(width: 380, alignment: .leading)
        .background {
            if !transparente {
                LinearGradient(colors: [Color(red: 0.15, green: 0.51, blue: 0.93), .teal],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 24))
    }

    private func datoCompartir(_ titulo: String, _ valor: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(titulo)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .tracking(1)
            Text(valor)
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }
}
