import Foundation
import HealthKit
import SwiftUI
import MapKit
import UIKit

// Historial de carreras en el iPhone. Los entrenamientos que graba el
// reloj llegan solos por la sincronización de Salud; acá se listan los
// de Maratonia con sus números (tiempo, distancia, ritmo, FC, calorías)
// y el recorrido dibujado en un mapa.

/// Carreras OCULTAS de Maratonia. Semántica segura y honesta:
/// - Ocultar NUNCA toca Apple Health: el workout sigue existiendo ahí
///   y en la app Salud; solo deja de aparecer en los listados y las
///   estadísticas de Maratonia.
/// - Persistente (UserDefaults) y reversible desde Perfil → Carreras
///   ocultas.
/// Inyectable para tests (suite propia).
struct CarrerasOcultas {
    static var compartidas = CarrerasOcultas(defaults: .standard)
    let defaults: UserDefaults
    private static let clave = "carrerasOcultasIDs"

    func ids() -> Set<UUID> {
        Set((defaults.stringArray(forKey: Self.clave) ?? [])
            .compactMap(UUID.init(uuidString:)))
    }

    func ocultar(_ id: UUID) {
        var actuales = ids(); actuales.insert(id)
        defaults.set(actuales.map(\.uuidString).sorted(), forKey: Self.clave)
    }

    func restaurar(_ id: UUID) {
        var actuales = ids(); actuales.remove(id)
        defaults.set(actuales.map(\.uuidString).sorted(), forKey: Self.clave)
    }

    func estaOculta(_ id: UUID) -> Bool { ids().contains(id) }
}

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
        MetricasSesion.ritmoSegKm(metros: distanciaMetros, segundos: duracion)
    }
}

final class CarrerasStore: ObservableObject {
    @Published var carreras: [CarreraResumen] = []
    @Published var mensaje: String?
    @Published var ocultasIDs: Set<UUID> = CarrerasOcultas.compartidas.ids()

    /// Lo que Maratonia MUESTRA: todo menos lo oculto. El workout
    /// oculto sigue intacto en Apple Health.
    var visibles: [CarreraResumen] { carreras.filter { !ocultasIDs.contains($0.id) } }
    var ocultas: [CarreraResumen] { carreras.filter { ocultasIDs.contains($0.id) } }

    func ocultar(_ id: UUID) {
        CarrerasOcultas.compartidas.ocultar(id)
        ocultasIDs = CarrerasOcultas.compartidas.ids()
    }

    func restaurar(_ id: UUID) {
        CarrerasOcultas.compartidas.restaurar(id)
        ocultasIDs = CarrerasOcultas.compartidas.ids()
    }

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
    @State private var aOcultar: UUID?

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
            ForEach(store.visibles) { carrera in
                NavigationLink {
                    CarreraDetalleView(store: store, id: carrera.id)
                } label: {
                    // La DISTANCIA manda; fecha y detalle acompañan.
                    HStack(spacing: 12) {
                        Image(systemName: "figure.run")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor.opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.2f", carrera.distanciaMetros / 1000))
                                    .font(.title3.weight(.bold))
                                    .monospacedDigit()
                                Text("km")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Text(subtituloCarrera(carrera))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 3)
                }
                .accessibilityLabel(etiquetaCarrera(carrera))
                .swipeActions(edge: .trailing) {
                    Button {
                        aOcultar = carrera.id
                    } label: {
                        Label("Ocultar", systemImage: "eye.slash")
                    }
                    .tint(.orange)
                }
            }
        }
        .navigationTitle("Mis carreras")
        .onAppear { store.cargar() }
        .refreshable { await store.recargar() }
        .confirmationDialog("¿Ocultar esta carrera de Maratonia?",
                            isPresented: .init(get: { aOcultar != nil },
                                               set: { if !$0 { aOcultar = nil } }),
                            titleVisibility: .visible) {
            Button("Ocultar de Maratonia") {
                if let id = aOcultar {
                    store.ocultar(id)
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                }
                aOcultar = nil
            }
            Button("Cancelar", role: .cancel) { aOcultar = nil }
        } message: {
            Text("Deja de aparecer en Maratonia y en sus estadísticas. El entrenamiento NO se borra: sigue intacto en Apple Health, y podés restaurarlo desde Perfil → Carreras ocultas.")
        }
    }

    /// La semana arriba de las carreras sueltas — mismo lenguaje visual
    /// que Progreso (sin degradados: tipografía y métricas).
    private var seccionProgreso: some View {
        let semana = resumenSemanal
        return Section {
            VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                EncabezadoSeccionV2(texto: "Esta semana")
                HStack(spacing: DV2.Espacio.xl) {
                    MetricaV2(titulo: "km", valor: String(format: "%.1f", semana.km))
                    MetricaV2(titulo: semana.carreras == 1 ? "carrera" : "carreras",
                              valor: "\(semana.carreras)")
                    MetricaV2(titulo: "ritmo /km",
                              valor: semana.ritmo.map { formatearRitmo($0) } ?? "–:––")
                }
            }
            .padding(.vertical, DV2.Espacio.xs)
        }
    }

    private func subtituloCarrera(_ carrera: CarreraResumen) -> String {
        var partes = [FormatoFecha.fechaYHora(carrera.fecha),
                      formatearDuracion(carrera.duracion)]
        if let ritmo = carrera.ritmoPromedioSegKm {
            partes.append("\(formatearRitmo(ritmo)) /km")
        }
        return partes.joined(separator: " · ")
    }

    private func etiquetaCarrera(_ carrera: CarreraResumen) -> String {
        "Carrera del \(FormatoFecha.completa(carrera.fecha)): "
            + String(format: "%.1f kilómetros", carrera.distanciaMetros / 1000)
            + ", \(formatearDuracion(carrera.duracion))"
    }

    private var resumenSemanal: (km: Double, carreras: Int, ritmo: Int?) {
        let calendario = Calendar.current
        let ahora = Date()
        let delaSemana = store.visibles.filter {
            calendario.isDate($0.fecha, equalTo: ahora, toGranularity: .weekOfYear)
        }
        let metros = delaSemana.reduce(0.0) { $0 + $1.distanciaMetros }
        let duracion = delaSemana.reduce(0.0) { $0 + $1.duracion }
        let ritmo = MetricasSesion.ritmoSegKm(metros: metros, segundos: duracion)
        return (metros / 1000, delaSemana.count, ritmo)
    }
}

struct CarreraDetalleView: View {
    @ObservedObject var store: CarrerasStore
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var confirmandoOcultar = false

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
                    Text("\(FormatoFecha.completa(carrera.fecha)) · \(FormatoFecha.hora(carrera.fecha))")
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
                Menu {
                    Button {
                        confirmandoOcultar = true
                    } label: {
                        Label("Ocultar de Maratonia", systemImage: "eye.slash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
            .confirmationDialog("¿Ocultar esta carrera de Maratonia?",
                                isPresented: $confirmandoOcultar,
                                titleVisibility: .visible) {
                Button("Ocultar de Maratonia") {
                    store.ocultar(carrera.id)
                    dismiss()
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Deja de aparecer en Maratonia y en sus estadísticas. El entrenamiento NO se borra: sigue intacto en Apple Health, y podés restaurarlo desde Perfil → Carreras ocultas.")
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
        // Nombre ÚNICO por exportación: el share sheet y varios destinos
        // cachean por URL, y con el nombre fijo servían el PNG viejo de
        // builds anteriores (sin logo) aunque el archivo nuevo estuviera
        // bien escrito. Bug real confirmado en dispositivo.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(Self.nombreDeExportacion())
        if let imagen = render.uiImage, let datos = imagen.pngData() {
            try? datos.write(to: url, options: .atomic)
        }
        return url
    }

    /// Separado y determinístico-testeable: siempre .png y nunca dos
    /// exportaciones con el mismo nombre.
    static func nombreDeExportacion(unico: String = UUID().uuidString) -> String {
        "maratonia-carrera-\(unico).png"
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
            Text(FormatoFecha.completa(carrera.fecha))
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

// MARK: - Carreras ocultas (Perfil → Datos): restaurar

struct CarrerasOcultasView: View {
    @StateObject private var store = CarrerasStore()

    var body: some View {
        List {
            if store.ocultas.isEmpty {
                ContentUnavailableView {
                    Label("No hay carreras ocultas", systemImage: "eye.slash")
                } description: {
                    Text("Las carreras que ocultes desde Mis carreras aparecen acá, listas para restaurar. Ocultar nunca borra nada de Apple Health.")
                }
                .listRowBackground(Color.clear)
            }
            ForEach(store.ocultas) { carrera in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(String(format: "%.2f", carrera.distanciaMetros / 1000)) km")
                            .font(.subheadline.weight(.semibold))
                        Text(FormatoFecha.media(carrera.fecha))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restaurar") {
                        store.restaurar(carrera.id)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .navigationTitle("Carreras ocultas")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.cargar() }
    }
}
