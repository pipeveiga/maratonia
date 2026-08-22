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
    /// Ritmo por punto de `ruta`, en segundos por km (nil donde no se
    /// puede calcular). Se guarda al cargar la ruta porque HealthKit
    /// entrega las ubicaciones CON timestamp y acá se descartaban: sin
    /// ellos el recorrido solo puede pintarse de un color.
    var ritmos: [Int?] = []
    /// Pendiente por punto, en porcentaje. Mismo motivo que `ritmos`:
    /// la altitud viene en las ubicaciones y se descartaba.
    var desniveles: [Double?] = []
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
    /// La consulta terminó bien y Salud no tiene ni una carrera. Es
    /// distinto de `mensaje`: eso es un ERROR, esto es el arranque
    /// normal de cualquiera que todavía no corrió. La pantalla los
    /// trata distinto y por eso el estado viaja aparte.
    @Published var sinCarreras = false
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
            mensaje = String(localized: "Salud no está disponible en este dispositivo.")
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
            let nuestras = (muestras as? [HKWorkout] ?? []).filter {
                $0.sourceRevision.source.bundleIdentifier.hasPrefix("com.pipeveiga.maraton")
            }
            // Captura débil PROPIA en el salto a main (no se reusa el
            // self desempaquetado del closure externo).
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.consultaEnCurso = false
                // Fusionar preservando los detalles ya cargados (ruta,
                // FC): reemplazar todo reseteaba mapas y promedios en
                // cada refresh y relanzaba todas las queries de detalle.
                let previos = Dictionary(uniqueKeysWithValues: self.carreras.map { ($0.id, $0) })
                let nuevos = nuestras.filter { previos[$0.uuid] == nil }
                self.carreras = nuestras.map { previos[$0.uuid] ?? CarreraResumen(workout: $0) }
                nuevos.forEach { self.cargarDetalles(de: $0) }
                if let error {
                    self.mensaje = String(localized: "No pude leer Salud: \(error.localizedDescription)")
                    self.sinCarreras = false
                } else {
                    self.mensaje = nil
                    self.sinCarreras = nuestras.isEmpty
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
            DispatchQueue.main.async { [weak self] in
                self?.actualizar(workout: workout) { $0.fcPromedio = promedio }
            }
        }
        healthStore.execute(consultaFC)

        // Recorrido GPS asociado al workout. Los lotes se acumulan en
        // CajaUbicaciones (con candado) y no en un `var` local: la
        // enumeración llega desde la cola de HealthKit y capturar un
        // mutable ahí era una carrera (error en Swift 6). Cada closure
        // captura self DÉBILMENTE por su cuenta — nada de reusar el
        // self desempaquetado de un closure externo.
        let predicadoRuta = HKQuery.predicateForObjects(from: workout)
        let consultaRuta = HKSampleQuery(
            sampleType: HKSeriesType.workoutRoute(), predicate: predicadoRuta,
            limit: 1, sortDescriptors: nil
        ) { [weak self] _, muestras, _ in
            guard let ruta = (muestras as? [HKWorkoutRoute])?.first else {
                DispatchQueue.main.async { [weak self] in
                    self?.actualizar(workout: workout) { $0.rutaCargada = true }
                }
                return
            }
            let caja = CajaUbicaciones()
            let recorrido = HKWorkoutRouteQuery(route: ruta) { [weak self] _, lote, terminado, error in
                caja.agregar(lote ?? [])
                // Error a mitad de la enumeración: "terminado" no llega
                // nunca y el spinner quedaba girando para siempre.
                // tomarResolucion garantiza UNA sola publicación.
                guard terminado || error != nil, caja.tomarResolucion() else { return }
                let ubicaciones = error == nil ? caja.contenido : []
                let puntos = ubicaciones.map(\.coordinate)
                let ritmos = AnalisisSesion.ritmos(de: ubicaciones)
                let desniveles = AnalisisSesion.desniveles(de: ubicaciones)
                let completa = error == nil
                DispatchQueue.main.async { [weak self] in
                    self?.actualizar(workout: workout) {
                        if completa {
                            $0.ruta = puntos
                            $0.ritmos = ritmos
                            $0.desniveles = desniveles
                        }
                        $0.rutaCargada = true
                    }
                }
            }
            self?.healthStore.execute(recorrido)
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
    /// Qué hacer cuando el estado vacío ofrece salir a correr. Opcional
    /// para no atar la vista a la barra de pestañas en previews y tests.
    var irACorrer: (() -> Void)?
    /// Para que el detalle pueda decir QUÉ sesión del plan fue esta
    /// carrera. Opcional: una carrera libre no tiene plan detrás.
    var almacen: AlmacenStore?

    var body: some View {
        List {
            if !store.carreras.isEmpty {
                seccionProgreso
            }
            if store.sinCarreras {
                // Una frase y una salida. El diagnóstico de permisos —que
                // antes ocupaba siete líneas acá— vive detrás de la
                // pregunta que lo pide: la mayoría no tiene ese problema,
                // solo todavía no corrió.
                EstadoVacio(
                    icono: "map",
                    titulo: String(localized: "Tu mapa está esperando"),
                    detalle: String(localized: "Cada carrera que corras queda acá con su recorrido, ritmo y pulso."),
                    accion: irACorrer.map { hacer in
                        (texto: String(localized: "Salir a correr"), hacer: hacer)
                    })
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                Tarjeta {
                    Detalle(titulo: String(localized: "Ya corrí y no aparecen")) {
                        Text("Corré con «Registrar carrera» activado: la sincronización desde el reloj tarda unos minutos — tirá hacia abajo para actualizar. Si aun así no aparecen, revisá los permisos en Salud → Compartir → Apps → Maratonia.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            } else if let mensaje = store.mensaje {
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
                    CarreraDetalleView(store: store, almacen: almacen, id: carrera.id)
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
                                Text(Unidades.distancia(km: carrera.distanciaMetros / 1000,
                                                        decimales: 2, conUnidad: false))
                                    .font(.title3.weight(.bold))
                                    .monospacedDigit()
                                Text(Unidades.actual.etiquetaDistancia)
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
                    // La etiqueta ya viene localizada de la capa de unidades:
                    // se pasa como clave directa en vez de interpolarla,
                    // que generaría la clave degenerada "%@".
                    MetricaV2(titulo: LocalizedStringKey(Unidades.actual.etiquetaDistancia),
                              valor: Unidades.distancia(km: semana.km, decimales: 1, conUnidad: false))
                    MetricaV2(titulo: semana.carreras == 1 ? "carrera" : "carreras",
                              valor: "\(semana.carreras)")
                    if let ritmo = semana.ritmo {
                        MetricaV2(titulo: "ritmo \(Unidades.actual.etiquetaRitmo)",
                                  valor: Unidades.ritmo(segundosPorKm: ritmo, conUnidad: false))
                    } else {
                        // Sin carreras esta semana: estado semántico,
                        // no un "–:––" que parece un error.
                        MetricaV2(titulo: "ritmo", valor: String(localized: "aún sin datos"))
                    }
                }
            }
            .padding(.vertical, DV2.Espacio.xs)
        }
    }

    private func subtituloCarrera(_ carrera: CarreraResumen) -> String {
        var partes = [FormatoFecha.fechaYHora(carrera.fecha),
                      formatearDuracion(carrera.duracion)]
        if let ritmo = carrera.ritmoPromedioSegKm {
            partes.append(Unidades.ritmo(segundosPorKm: ritmo))
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

/// Cómo se pinta el recorrido. Dos preguntas distintas sobre la misma
/// ruta: cuánto empujaste (magnitud) y contra qué terreno (polaridad).
enum ModoRecorrido: String, CaseIterable, Identifiable {
    case ritmo, desnivel
    var id: String { rawValue }

    var titulo: String {
        switch self {
        case .ritmo: return String(localized: "Ritmo")
        case .desnivel: return String(localized: "Desnivel")
        }
    }
}

struct CarreraDetalleView: View {
    @ObservedObject var store: CarrerasStore
    var almacen: AlmacenStore?
    let id: UUID
    @Environment(\.dismiss) private var dismiss
    @State private var confirmandoOcultar = false
    @State private var modo: ModoRecorrido = .ritmo

    var body: some View {
        if let carrera = store.carreras.first(where: { $0.id == id }) {
            List {
                Section {
                    if !carrera.ruta.isEmpty {
                        let tramos = modo == .ritmo
                            ? AnalisisSesion.tramos(coordenadas: carrera.ruta,
                                                    ritmos: carrera.ritmos)
                            : AnalisisSesion.tramosPorDesnivel(coordenadas: carrera.ruta,
                                                               desniveles: carrera.desniveles)
                        // .automatic encuadra solo el contenido del mapa.
                        Map {
                            // El CASING va primero y entero: una línea
                            // blanca ancha debajo. Sin él los pasos
                            // claros de la rampa desaparecen sobre un
                            // mapa claro, y los oscuros sobre uno de
                            // noche. Es lo que hace legible el color sin
                            // tener que oscurecer toda la escala.
                            MapPolyline(coordinates: carrera.ruta)
                                .stroke(.white, style: StrokeStyle(lineWidth: 9,
                                                                   lineCap: .round,
                                                                   lineJoin: .round))
                            if tramos.isEmpty {
                                // Carreras cargadas por una build anterior
                                // no tienen ritmo por punto guardado.
                                MapPolyline(coordinates: carrera.ruta)
                                    .stroke(DV2.Marca.primario,
                                            style: StrokeStyle(lineWidth: 5,
                                                               lineCap: .round,
                                                               lineJoin: .round))
                            } else {
                                ForEach(Array(tramos.enumerated()), id: \.offset) { par in
                                    MapPolyline(coordinates: par.element.coordenadas)
                                        .stroke(modo == .ritmo
                                                ? DV2.Intensidad.color(par.element.intensidad)
                                                : DV2.Pendiente.color(par.element.intensidad),
                                                style: StrokeStyle(lineWidth: 5,
                                                                   lineCap: .round,
                                                                   lineJoin: .round))
                                }
                            }
                        }
                        .frame(height: 280)
                        .listRowInsets(EdgeInsets())

                        if !tramos.isEmpty {
                            VStack(spacing: DV2.Espacio.s) {
                                // El selector solo si hay desnivel medido:
                                // una pestaña que lleva a una pantalla
                                // gris es peor que no tenerla.
                                if carrera.desniveles.contains(where: { $0 != nil }) {
                                    Picker("Pintar por", selection: $modo) {
                                        ForEach(ModoRecorrido.allCases) { m in
                                            Text(m.titulo).tag(m)
                                        }
                                    }
                                    .pickerStyle(.segmented)
                                }
                                LeyendaIntensidad(modo: modo)
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16,
                                                      bottom: 10, trailing: 16))
                        }
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
                                           valor: Unidades.distancia(km: carrera.distanciaMetros / 1000, decimales: 2),
                                           icono: "figure.run", color: .green)
                        TarjetaEstadistica(titulo: "Tiempo",
                                           valor: formatearDuracion(carrera.duracion),
                                           icono: "stopwatch.fill", color: .blue)
                        if let ritmo = carrera.ritmoPromedioSegKm {
                            TarjetaEstadistica(titulo: "Ritmo promedio",
                                               valor: Unidades.ritmo(segundosPorKm: ritmo),
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

                // Análisis real de la sesión (build 54): splits, ritmo
                // por km, FC y elevación — todo desde HealthKit, carga
                // al abrir, funciona también con carreras viejas.
                SeccionesAnalisis(workout: carrera.workout)
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

    /// "Larga · Semana 3 de 8" — qué era esta carrera dentro del plan.
    /// `nil` para una carrera libre: inventar contexto sería peor que no
    /// tenerlo.
    private func contextoDePlan(_ carrera: CarreraResumen) -> String? {
        guard let almacen,
              let programado = almacen.almacen.programadoDeSesion(carrera.id) else { return nil }
        let nombre = programado.definicion.nombre
        guard let semana = almacen.almacen.semanaDe(programadoID: programado.id)?.numero,
              let total = almacen.almacen.planActivo?.semanas.count, total > 0 else {
            return nombre
        }
        return String(localized: "\(nombre) · Semana \(semana) de \(total)")
    }

    /// Los tramos de intensidad de esta carrera, en UN solo lugar: las
    /// tres exportaciones tienen que pintar exactamente lo mismo.
    private func tramosDe(_ carrera: CarreraResumen) -> [AnalisisSesion.TramoIntensidad] {
        AnalisisSesion.tramos(coordenadas: carrera.ruta, ritmos: carrera.ritmos, maximo: 60)
    }

    /// La carrera como imagen linda para mandar al grupo o subir a redes.
    private func imagenParaCompartir(_ carrera: CarreraResumen) -> Image {
        let render = ImageRenderer(content: TarjetaCompartir(
            carrera: carrera, ruta: carrera.ruta, tramos: tramosDe(carrera),
            contexto: contextoDePlan(carrera)))
        render.scale = 3
        if let imagen = render.uiImage {
            return Image(uiImage: imagen)
        }
        return Image(systemName: "figure.run")
    }

    private func imagenSinFondo(_ carrera: CarreraResumen) -> Image {
        let render = ImageRenderer(content: TarjetaCompartir(
            carrera: carrera, ruta: carrera.ruta,
            tramos: tramosDe(carrera), contexto: contextoDePlan(carrera),
            transparente: true))
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
            carrera: carrera, ruta: carrera.ruta,
            tramos: tramosDe(carrera), contexto: contextoDePlan(carrera),
            transparente: true))
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
    /// La ruta COMPLETA, cuando este trazo es solo un tramo de ella. El
    /// encuadre tiene que salir del recorrido entero: si cada tramo
    /// calculara el suyo, cada uno se escalaría a su propia caja y el
    /// dibujo saldría descoyuntado.
    var encuadre: [CLLocationCoordinate2D]? = nil

    func path(in rect: CGRect) -> Path {
        // Adelgazar: con miles de puntos GPS el trazo no gana nada.
        let paso = max(1, coordenadas.count / 300)
        let puntos = stride(from: 0, to: coordenadas.count, by: paso).map { coordenadas[$0] }
        guard puntos.count > 1 else { return Path() }

        let base = encuadre ?? coordenadas
        let latitudes = base.map(\.latitude)
        let longitudes = base.map(\.longitude)
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
/// La escala del recorrido, explicada. Un mapa de calor sin leyenda es
/// decoración: el corredor no tiene cómo saber si el naranja oscuro es
/// lo bueno o lo malo.
struct LeyendaIntensidad: View {
    var modo: ModoRecorrido = .ritmo

    var body: some View {
        HStack(spacing: DV2.Espacio.s) {
            Text(modo == .ritmo ? "lento" : "bajada")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Capsule()
                .fill(modo == .ritmo ? DV2.Intensidad.degradado : DV2.Pendiente.degradado)
                .frame(height: 6)
            Text(modo == .ritmo ? "rápido" : "subida")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(modo == .ritmo
            ? "El recorrido está pintado por ritmo: más oscuro, más rápido."
            : "El recorrido está pintado por desnivel: azul bajada, gris llano, rojo subida."))
    }
}

struct TarjetaCompartir: View {
    let carrera: CarreraResumen
    var ruta: [CLLocationCoordinate2D] = []
    var tramos: [AnalisisSesion.TramoIntensidad] = []
    /// Qué era esta carrera dentro del plan. Le da sentido a la postal:
    /// no es "corrí 10 km", es "la larga de la semana 3 de 8".
    var contexto: String?
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
            VStack(alignment: .leading, spacing: 2) {
                Text(FormatoFecha.completa(carrera.fecha))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.75))
                if let contexto {
                    Text(contexto)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.95))
                }
            }

            if ruta.count > 1 {
                ZStack {
                    // Casing blanco debajo: sobre el azul profundo de la
                    // postal los pasos oscuros de la rampa no llegan a
                    // 3:1 solos. Además es lo que le da el aire de
                    // sticker que tenía el trazo blanco original.
                    TrazadoRuta(coordenadas: ruta)
                        .stroke(.white, style: StrokeStyle(
                            lineWidth: 7, lineCap: .round, lineJoin: .round))
                    if tramos.isEmpty {
                        TrazadoRuta(coordenadas: ruta)
                            .stroke(.white, style: StrokeStyle(
                                lineWidth: 4, lineCap: .round, lineJoin: .round))
                    } else {
                        ForEach(Array(tramos.enumerated()), id: \.offset) { par in
                            TrazadoRuta(coordenadas: par.element.coordenadas, encuadre: ruta)
                                .stroke(DV2.Intensidad.color(par.element.intensidad),
                                        style: StrokeStyle(lineWidth: 4.5,
                                                           lineCap: .round,
                                                           lineJoin: .round))
                        }
                    }
                }
                .frame(height: 190)
                .shadow(color: sombra, radius: 3, y: 1)
                .padding(.vertical, 4)

                // Una postal se mira sin contexto: sin esto el degradado
                // del recorrido es decoración bonita y nadie sabe que
                // está viendo el ritmo.
                if !tramos.isEmpty {
                    HStack(spacing: 6) {
                        Text("LENTO")
                        Capsule()
                            .fill(DV2.Intensidad.degradado)
                            .frame(width: 54, height: 4)
                        Text("RÁPIDO")
                    }
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.8))
                }
            }

            Text(Unidades.distancia(km: carrera.distanciaMetros / 1000, decimales: 2))
                .font(.system(size: 56, weight: .heavy, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
            HStack(spacing: 26) {
                datoCompartir("TIEMPO", formatearDuracion(carrera.duracion))
                if let ritmo = carrera.ritmoPromedioSegKm {
                    datoCompartir("RITMO", Unidades.ritmo(segundosPorKm: ritmo))
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
                        Text(Unidades.distancia(km: carrera.distanciaMetros / 1000, decimales: 2))
                            .font(.subheadline.weight(.semibold))
                        Text(FormatoFecha.media(carrera.fecha))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Restaurar") {
                        store.restaurar(carrera.id)
                        UINotificationFeedbackGenerator().notificationOccurred(.success)
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

// MARK: - Análisis post-carrera (build 54): splits, ritmo, FC, elevación

import Charts

/// Matemática PURA del análisis (testeable sin HealthKit). Todo deriva
/// de datos REALES: la ruta guardada del workout (posición+altitud+
/// timestamp) y las muestras de FC de Salud — nunca del estimador live.
enum AnalisisSesion {

    struct Punto { var t: TimeInterval; var d: Double; var alt: Double }

    /// Un tramo del recorrido con su intensidad relativa. `intensidad`
    /// va de 0 (lo más lento de ESTA carrera) a 1 (lo más rápido): el
    /// mapa de calor compara al corredor consigo mismo, no contra una
    /// tabla — un 6:00/km puede ser el tramo rápido de una salida suave
    /// y el lento de una serie.
    struct TramoIntensidad {
        var coordenadas: [CLLocationCoordinate2D]
        var intensidad: Double
    }

    /// Ritmo instantáneo por punto, en segundos por kilómetro.
    ///
    /// El GPS de muñeca es ruidoso: dos fixes consecutivos pueden dar
    /// 2:30/km o 12:00/km sin que el corredor haya cambiado nada. Por
    /// eso el ritmo de cada punto se mide sobre una VENTANA a su
    /// alrededor y no contra el punto anterior. `nil` donde la ventana
    /// no da para calcular (arranque, parado, salto de señal).
    static func ritmos(de ubicaciones: [CLLocation], ventana: Int = 9) -> [Int?] {
        guard ubicaciones.count > 1 else {
            return Array(repeating: nil, count: ubicaciones.count)
        }
        let mitad = max(1, ventana / 2)
        return ubicaciones.indices.map { i in
            let desde = max(0, i - mitad)
            let hasta = min(ubicaciones.count - 1, i + mitad)
            guard hasta > desde else { return nil }
            var metros = 0.0
            for j in (desde + 1)...hasta {
                metros += ubicaciones[j].distance(from: ubicaciones[j - 1])
            }
            let segundos = ubicaciones[hasta].timestamp
                .timeIntervalSince(ubicaciones[desde].timestamp)
            // Parado o retrocediendo en el tiempo: no hay ritmo, y un
            // 0 acá pintaría el tramo como "lo más rápido de la carrera".
            guard metros >= 5, segundos > 0 else { return nil }
            let segPorKm = Int((segundos / metros * 1000).rounded())
            // Fuera de lo humanamente posible = fix basura, no un ritmo.
            guard (120...1800).contains(segPorKm) else { return nil }
            return segPorKm
        }
    }

    /// Pendiente por punto, en porcentaje (positivo = subida).
    ///
    /// La altitud del GPS es MÁS ruidosa que la posición: fixes
    /// consecutivos saltan metros sin que el terreno cambie. Por eso la
    /// pendiente se mide sobre una ventana ancha y se descarta lo que
    /// sale de un rango que ya no es correr sino escalar.
    static func desniveles(de ubicaciones: [CLLocation], ventana: Int = 15) -> [Double?] {
        guard ubicaciones.count > 1 else {
            return Array(repeating: nil, count: ubicaciones.count)
        }
        let mitad = max(1, ventana / 2)
        return ubicaciones.indices.map { i in
            let desde = max(0, i - mitad)
            let hasta = min(ubicaciones.count - 1, i + mitad)
            guard hasta > desde else { return nil }
            var metros = 0.0
            for j in (desde + 1)...hasta {
                metros += ubicaciones[j].distance(from: ubicaciones[j - 1])
            }
            // Altitud sin medir (verticalAccuracy < 0) no es altitud 0.
            guard ubicaciones[desde].verticalAccuracy >= 0,
                  ubicaciones[hasta].verticalAccuracy >= 0,
                  metros >= 20 else { return nil }
            let subida = ubicaciones[hasta].altitude - ubicaciones[desde].altitude
            let porciento = subida / metros * 100
            guard porciento.isFinite, abs(porciento) <= 35 else { return nil }
            return porciento
        }
    }

    /// El recorrido partido en tramos por PENDIENTE. La intensidad
    /// vuelve normalizada a 0...1 con 0,5 = llano: la pendiente es
    /// POLARIDAD (subís o bajás), no magnitud, y por eso su escala tiene
    /// dos polos y un neutro en el medio — al revés que el ritmo.
    ///
    /// La escala es simétrica a propósito: si el máximo de subida y el
    /// de bajada se normalizaran por separado, una cuesta del 8 % y una
    /// bajadita del 1 % se pintarían igual de saturadas.
    static func tramosPorDesnivel(coordenadas: [CLLocationCoordinate2D],
                                  desniveles: [Double?],
                                  maximo: Int = 90) -> [TramoIntensidad] {
        guard coordenadas.count > 1, coordenadas.count == desniveles.count else { return [] }
        let validos = desniveles.compactMap { $0 }.map(abs).sorted()
        guard let tope = validos.last, tope > 0.5 else {
            // Terreno llano: pintarlo con contraste sería inventar
            // cuestas que no existen.
            return [TramoIntensidad(coordenadas: coordenadas, intensidad: 0.5)]
        }
        // Percentil 90 del valor absoluto: un pico de altímetro no fija
        // la escala de toda la carrera.
        let escala = max(1.0, validos[min(validos.count - 1, Int(Double(validos.count - 1) * 0.9))])

        let porTramo = max(2, Int((Double(coordenadas.count) / Double(maximo)).rounded(.up)))
        var resultado: [TramoIntensidad] = []
        var inicio = 0
        while inicio < coordenadas.count - 1 {
            let fin = min(coordenadas.count - 1, inicio + porTramo)
            let delTramo = desniveles[inicio...fin].compactMap { $0 }
            let intensidad: Double
            if delTramo.isEmpty {
                intensidad = 0.5
            } else {
                let medio = delTramo.reduce(0, +) / Double(delTramo.count)
                intensidad = min(1, max(0, 0.5 + 0.5 * (medio / escala)))
            }
            resultado.append(TramoIntensidad(
                coordenadas: Array(coordenadas[inicio...fin]),
                intensidad: intensidad))
            inicio = fin
        }
        return resultado
    }

    /// El recorrido partido en tramos con intensidad normalizada, listo
    /// para pintar. Se reduce a `maximo` tramos porque una ruta trae
    /// miles de puntos y dibujar uno por fix no cambia lo que se ve.
    ///
    /// La normalización usa los percentiles 5 y 95 y no el mínimo y el
    /// máximo: un solo fix malo en un semáforo aplastaría toda la escala
    /// contra un extremo y la carrera entera saldría de un color.
    static func tramos(coordenadas: [CLLocationCoordinate2D],
                       ritmos: [Int?],
                       maximo: Int = 90) -> [TramoIntensidad] {
        guard coordenadas.count > 1, coordenadas.count == ritmos.count else { return [] }

        let validos = ritmos.compactMap { $0 }.sorted()
        guard validos.count > 1 else {
            return [TramoIntensidad(coordenadas: coordenadas, intensidad: 0.5)]
        }
        let rapido = Double(validos[max(0, Int(Double(validos.count - 1) * 0.05))])
        let lento = Double(validos[min(validos.count - 1, Int(Double(validos.count - 1) * 0.95))])
        let rango = lento - rapido

        let porTramo = max(2, Int((Double(coordenadas.count) / Double(maximo)).rounded(.up)))
        var resultado: [TramoIntensidad] = []
        var inicio = 0
        while inicio < coordenadas.count - 1 {
            // El tramo COMPARTE su último punto con el primero del
            // siguiente: sin eso la línea sale cortada en cada empalme.
            let fin = min(coordenadas.count - 1, inicio + porTramo)
            let ritmosDelTramo = ritmos[inicio...fin].compactMap { $0 }
            let intensidad: Double
            if ritmosDelTramo.isEmpty || rango <= 0 {
                intensidad = 0.5
            } else {
                let medio = Double(ritmosDelTramo.reduce(0, +)) / Double(ritmosDelTramo.count)
                // Menos segundos por km = más rápido = más intensidad.
                intensidad = min(1, max(0, (lento - medio) / rango))
            }
            resultado.append(TramoIntensidad(
                coordenadas: Array(coordenadas[inicio...fin]),
                intensidad: intensidad))
            inicio = fin
        }
        return resultado
    }

    /// Un split completo. `numero` es el hito (km 3 o milla 3) y
    /// `ritmoSegKm` queda SIEMPRE en segundos por kilómetro canónicos:
    /// la conversión a min/mi la hace la capa de unidades al mostrarlo,
    /// no este cálculo.
    struct SplitKm: Identifiable {
        var id: Int { numero }
        var numero: Int
        var segundos: Int
        var ritmoSegKm: Int
    }

    /// Ruta → puntos (t desde el inicio, distancia acumulada, altitud).
    static func puntos(de ubicaciones: [CLLocation]) -> [Punto] {
        guard let primera = ubicaciones.first else { return [] }
        var acumulada = 0.0
        var resultado: [Punto] = []
        var previa = primera
        for ubicacion in ubicaciones {
            acumulada += ubicacion.distance(from: previa)
            previa = ubicacion
            resultado.append(Punto(t: ubicacion.timestamp.timeIntervalSince(primera.timestamp),
                                   d: acumulada, alt: ubicacion.altitude))
        }
        return resultado
    }

    /// Splits reales por unidad, interpolando el cruce exacto de cada
    /// hito. Con la preferencia en imperial son millas de verdad —el
    /// paso sale de `metrosPorHito`—, no kilómetros con otra etiqueta.
    /// Nota: usan el tiempo de RELOJ de la ruta (una pausa larga infla
    /// el split donde ocurrió — igual que el de cualquier GPS).
    static func splits(_ puntos: [Punto],
                       metrosPorHito: Double = Unidades.metrosPorHito()) -> [SplitKm] {
        guard puntos.count > 1, metrosPorHito > 0 else { return [] }
        var resultado: [SplitKm] = []
        var objetivo = metrosPorHito
        var tiempoAnterior = 0.0
        for (anterior, actual) in zip(puntos, puntos.dropFirst()) {
            while actual.d >= objetivo {
                let tramo = actual.d - anterior.d
                let fraccion = tramo > 0 ? (objetivo - anterior.d) / tramo : 0
                let tCruce = anterior.t + (actual.t - anterior.t) * fraccion
                let segundos = Int((tCruce - tiempoAnterior).rounded())
                let numero = Int((objetivo / metrosPorHito).rounded())
                if segundos > 0 {
                    // El ritmo se guarda en seg/km canónicos para que la
                    // capa de unidades lo formatee como cualquier otro.
                    let segPorKm = Int((Double(segundos) * 1000 / metrosPorHito).rounded())
                    resultado.append(SplitKm(numero: numero, segundos: segundos,
                                             ritmoSegKm: segPorKm))
                }
                tiempoAnterior = tCruce
                objetivo += metrosPorHito
            }
        }
        return resultado
    }

    /// Reducción para gráficos: como mucho `maximo` puntos.
    static func reducir<T>(_ valores: [T], a maximo: Int) -> [T] {
        guard valores.count > maximo, maximo > 0 else { return valores }
        let paso = Double(valores.count) / Double(maximo)
        return (0..<maximo).map { valores[Int(Double($0) * paso)] }
    }

    /// Ganancia acumulada de subida (con umbral de 1 m contra el ruido
    /// barométrico). nil si no hay altitudes útiles.
    static func desnivelPositivo(_ puntos: [Punto]) -> Double? {
        guard puntos.count > 1 else { return nil }
        var ganancia = 0.0
        var referencia = puntos[0].alt
        for punto in puntos.dropFirst() {
            let delta = punto.alt - referencia
            if delta >= 1 { ganancia += delta; referencia = punto.alt }
            else if delta < 0 { referencia = punto.alt }
        }
        return ganancia
    }
}

/// Acumulador de los lotes de la ruta. HKWorkoutRouteQuery entrega por
/// tandas desde su propia cola, así que el estado mutable vive acá con
/// candado en vez de en un `var` local capturado por closures
/// concurrentes (eso era una carrera real, y error en Swift 6).
/// `tomarResolucion` garantiza que la continuación se reanude UNA sola
/// vez: reanudarla dos veces hace crashear el proceso.
private final class CajaUbicaciones: @unchecked Sendable {
    private let candado = NSLock()
    private var todas: [CLLocation] = []
    private var resuelta = false

    func agregar(_ lote: [CLLocation]) {
        candado.lock(); defer { candado.unlock() }
        todas.append(contentsOf: lote)
    }

    var contenido: [CLLocation] {
        candado.lock(); defer { candado.unlock() }
        return todas
    }

    func tomarResolucion() -> Bool {
        candado.lock(); defer { candado.unlock() }
        if resuelta { return false }
        resuelta = true
        return true
    }
}

/// Carga bajo demanda (al ABRIR el detalle) la ruta completa con
/// timestamps y la serie de FC de ESA sesión. Nada de esto se carga en
/// la lista — la UI no se traba.
@MainActor
final class CargadorAnalisis: ObservableObject {
    @Published var puntos: [AnalisisSesion.Punto] = []
    @Published var fc: [(t: TimeInterval, ppm: Double)] = []
    @Published var cargando = true

    private let healthStore = HKHealthStore()

    func cargar(workout: HKWorkout) {
        cargando = true
        let store = healthStore
        Task { @MainActor in
            let ubicaciones = await Self.leerRuta(workout: workout, store: store)
            let buenas = ubicaciones.filter {
                $0.horizontalAccuracy > 0 && $0.horizontalAccuracy <= 50
            }
            self.puntos = AnalisisSesion.puntos(de: buenas)
            self.cargando = false
        }
        Task { @MainActor in
            let serie = await Self.leerFC(workout: workout, store: store)
            self.fc = AnalisisSesion.reducir(serie, a: 120)
        }
    }

    /// Consultas de HealthKit fuera del main actor y SIN capturar self:
    /// el resultado vuelve por continuación y recién ahí se publica.
    private nonisolated static func leerRuta(workout: HKWorkout,
                                             store: HKHealthStore) async -> [CLLocation] {
        await withCheckedContinuation { continuacion in
            let consulta = HKSampleQuery(
                sampleType: HKSeriesType.workoutRoute(),
                predicate: HKQuery.predicateForObjects(from: workout),
                limit: 1, sortDescriptors: nil
            ) { _, muestras, _ in
                guard let ruta = (muestras as? [HKWorkoutRoute])?.first else {
                    continuacion.resume(returning: [])
                    return
                }
                let caja = CajaUbicaciones()
                let recorrido = HKWorkoutRouteQuery(route: ruta) { _, lote, terminado, error in
                    caja.agregar(lote ?? [])
                    // Error también cierra: si no, el spinner quedaría
                    // girando para siempre.
                    if terminado || error != nil, caja.tomarResolucion() {
                        continuacion.resume(returning: caja.contenido)
                    }
                }
                store.execute(recorrido)
            }
            store.execute(consulta)
        }
    }

    private nonisolated static func leerFC(workout: HKWorkout, store: HKHealthStore)
        async -> [(t: TimeInterval, ppm: Double)] {
        await withCheckedContinuation { continuacion in
            let consulta = HKSampleQuery(
                sampleType: HKQuantityType(.heartRate),
                predicate: HKQuery.predicateForSamples(withStart: workout.startDate,
                                                       end: workout.endDate),
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate,
                                                   ascending: true)]
            ) { _, muestras, _ in
                let ppm = HKUnit.count().unitDivided(by: .minute())
                let inicio = workout.startDate
                let serie = (muestras as? [HKQuantitySample] ?? []).map {
                    (t: $0.startDate.timeIntervalSince(inicio),
                     ppm: $0.quantity.doubleValue(for: ppm))
                }
                continuacion.resume(returning: serie)
            }
            store.execute(consulta)
        }
    }
}

/// Las secciones de análisis del detalle: splits, ritmo/km, FC y
/// elevación — solo con datos reales, sin secciones vacías.
struct SeccionesAnalisis: View {
    let workout: HKWorkout
    @StateObject private var cargador = CargadorAnalisis()

    var body: some View {
        Group {
            if cargador.cargando && cargador.puntos.isEmpty {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }

            let splits = AnalisisSesion.splits(cargador.puntos)
            if !splits.isEmpty {
                // Con un solo split "el más rápido" no significa nada:
                // es el único.
                let masRapido = splits.count > 1
                    ? splits.min(by: { $0.ritmoSegKm < $1.ritmoSegKm })
                    : nil
                Section("Splits") {
                    ForEach(splits) { split in
                        let esElMasRapido = split.numero == masRapido?.numero
                        HStack {
                            Text("\(Unidades.actual.etiquetaDistancia) \(split.numero)")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            if esElMasRapido {
                                // Con etiqueta y no solo con color: el
                                // dato que la gente publica no puede
                                // depender de distinguir dos naranjas.
                                Text("más rápido")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(DV2.Intensidad.pasos.last ?? .orange,
                                                in: Capsule())
                            }
                            Spacer()
                            Text(formatearDuracion(TimeInterval(split.segundos)))
                                .font(.subheadline)
                                .monospacedDigit()
                            Text(Unidades.ritmo(segundosPorKm: split.ritmoSegKm))
                                .font(esElMasRapido ? .subheadline.weight(.bold) : .subheadline)
                                .foregroundStyle(esElMasRapido ? .primary : .secondary)
                                .monospacedDigit()
                        }
                    }
                }
                Section(String(localized: "Ritmo por \(Unidades.actual.etiquetaDistancia)")) {
                    Chart(splits) { split in
                        BarMark(x: .value(Unidades.actual.etiquetaDistancia, split.numero),
                                y: .value("ritmo", split.ritmoSegKm))
                            .foregroundStyle(split.numero == masRapido?.numero
                                             ? (DV2.Intensidad.pasos.last ?? .orange)
                                             : DV2.Marca.primario)
                    }
                    .chartYAxis {
                        AxisMarks { valor in
                            AxisValueLabel {
                                if let seg = valor.as(Int.self) {
                                    Text(Unidades.ritmo(segundosPorKm: seg, conUnidad: false))
                                }
                            }
                        }
                    }
                    .frame(height: 140)
                    .accessibilityLabel(Text("Ritmo por kilómetro"))
                }
            }

            if !cargador.fc.isEmpty {
                Section("Frecuencia cardíaca") {
                    Chart(Array(cargador.fc.enumerated()), id: \.offset) { _, muestra in
                        LineMark(x: .value("min", muestra.t / 60),
                                 y: .value("ppm", muestra.ppm))
                            .foregroundStyle(.red)
                            .interpolationMethod(.monotone)
                    }
                    .frame(height: 120)
                    .accessibilityLabel(Text("Frecuencia cardíaca durante la sesión"))
                    if let min = cargador.fc.map(\.ppm).min(),
                       let max = cargador.fc.map(\.ppm).max() {
                        Text("Rango: \(Int(min))–\(Int(max)) ppm")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            let perfil = AnalisisSesion.reducir(cargador.puntos, a: 80)
            if let desnivel = AnalisisSesion.desnivelPositivo(cargador.puntos),
               perfil.count > 1 {
                Section("Elevación") {
                    Chart(Array(perfil.enumerated()), id: \.offset) { _, punto in
                        LineMark(x: .value(Unidades.actual.etiquetaDistancia,
                                       Unidades.distanciaMostrable(km: punto.d / 1000)),
                                 y: .value("m", punto.alt))
                            .foregroundStyle(DV2.Marca.profundo)
                            .interpolationMethod(.monotone)
                    }
                    .frame(height: 100)
                    .accessibilityLabel(Text("Perfil de elevación"))
                    Text("Desnivel positivo: +\(Int(desnivel)) m")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { cargador.cargar(workout: workout) }
    }
}
