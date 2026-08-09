import SwiftUI
import Foundation

// Fase B del dominio V2: catálogo mínimo, adopción con snapshot,
// calendario y CUTOVER (dominio-v2.json pasa a ser la fuente de verdad
// de plan/calendario en el iPhone). El watch sigue en V1 hasta Fase E;
// el plan legacy (plan.json) sigue vivo como config de audio/música y
// como lo que se envía al reloj — read-only respecto del calendario.

// MARK: - Template del catálogo (PlanBase)

/// Un plan del catálogo. Es un TEMPLATE: adoptarlo crea un PlanUsuario
/// nuevo por snapshot; editar el catálogo en una versión futura de la
/// app jamás toca planes ya adoptados.
struct PlanBase: Codable, Equatable, Identifiable {
    var id: String              // "primeros-5k" (estable entre versiones)
    var version: Int
    var nombre: String
    var descripcion: String
    var distanciaObjetivoKm: Double
    var semanasTotales: Int
    var diasPorSemana: Int
    /// Contenido provisional: valida infraestructura, NO es metodología
    /// deportiva definitiva (se muestra en la UI).
    var provisional: Bool
    var semanas: [SemanaBase]

    /// Identidad completa template+versión, guardada como procedencia.
    var planBaseID: String { "\(id)@\(version)" }
}

struct SemanaBase: Codable, Equatable {
    var numero: Int
    var entrenamientos: [EntrenamientoBase]
}

/// Un entrenamiento RELATIVO: "semana N, día D" (día 1 = fecha de
/// inicio de esa semana). La adopción lo traduce a DiaLocal concreto.
struct EntrenamientoBase: Codable, Equatable {
    var diaDeSemana: Int        // 1...7
    var tipo: TipoEntrenamiento
    var nombre: String
    var descripcion: String
    var segmentos: [SegmentoBase]
}

/// Segmento del template, SIN identidad (los UUID nacen al adoptar).
struct SegmentoBase: Codable, Equatable {
    var nombre: String
    var distanciaKm: Double?
    var duracionSegundos: Int?
    var ritmoMinSegKm: Int?
    var ritmoMaxSegKm: Int?
}

// MARK: - Adopción (snapshot + fechas concretas)

extension PlanBase {
    /// Snapshot completo → PlanUsuario NUEVO: IDs recién generados,
    /// procedencia "id@versión", y fechas concretas determinísticas:
    /// día D de la semana N = inicio + (N-1)*7 + (D-1) días, con
    /// aritmética de Calendar (cruces de mes/año correctos).
    func adoptar(inicio: DiaLocal, fechaAdopcion: Date,
                 calendario: Calendar = .current) -> PlanUsuario {
        let semanasUsuario = semanas.map { semana in
            SemanaPlan(
                numero: semana.numero,
                programados: semana.entrenamientos.map { entrenamiento in
                    let desplazamiento = (semana.numero - 1) * 7 + (entrenamiento.diaDeSemana - 1)
                    return EntrenamientoProgramado(
                        definicion: DefinicionEntrenamiento(
                            tipo: entrenamiento.tipo,
                            nombre: entrenamiento.nombre,
                            descripcion: entrenamiento.descripcion,
                            segmentos: entrenamiento.segmentos.map { base in
                                Segmento(nombre: base.nombre,
                                         distanciaKm: base.distanciaKm,
                                         duracionSegundos: base.duracionSegundos,
                                         ritmo: base.ritmo)
                            }),
                        dia: inicio.sumando(dias: desplazamiento, calendario: calendario))
                })
        }
        return PlanUsuario(nombre: nombre,
                           origen: .catalogo(planBaseID: planBaseID),
                           fechaAdopcion: fechaAdopcion,
                           semanas: semanasUsuario)
    }
}

extension SegmentoBase {
    var ritmo: RitmoObjetivo {
        if ritmoMinSegKm == nil && ritmoMaxSegKm == nil { return .libre }
        return .absoluto(minSegKm: ritmoMinSegKm, maxSegKm: ritmoMaxSegKm)
    }
}

// MARK: - Catálogo (JSON embebido, mismo formato que usaría un recurso)

enum Catalogo {

    /// Los planes disponibles, decodificados del JSON: valida el
    /// formato de datos real aunque todavía viva embebido en código.
    static func planesDisponibles() -> [PlanBase] {
        [json5K, json10K].compactMap {
            try? JSONDecoder().decode(PlanBase.self, from: Data($0.utf8))
        }
    }

    /// CONTENIDO PROVISIONAL: progresión conservadora clásica de
    /// caminata/trote para validar la infraestructura del catálogo.
    /// Todos los ritmos son libres a propósito: sin baseline del
    /// corredor (Fase F/G) no corresponde prescribir números.
    static let json5K = """
    {
      "id": "primeros-5k", "version": 1,
      "nombre": "Primeros 5K",
      "descripcion": "De cero a correr 5 km de corrido, alternando caminata y trote con progresión suave. Ritmos libres: la regla es poder hablar mientras trotás. Contenido provisional.",
      "distanciaObjetivoKm": 5, "semanasTotales": 6, "diasPorSemana": 3,
      "provisional": true,
      "semanas": [
        { "numero": 1, "entrenamientos": [
          { "diaDeSemana": 1, "tipo": "facil", "nombre": "Caminata y trote 1", "descripcion": "Alterná 1 min de trote y 2 de caminata.", "segmentos": [ { "nombre": "Alternado suave", "distanciaKm": 2.5 } ] },
          { "diaDeSemana": 3, "tipo": "facil", "nombre": "Caminata y trote 2", "descripcion": "Alterná 1 min de trote y 2 de caminata.", "segmentos": [ { "nombre": "Alternado suave", "distanciaKm": 2.5 } ] },
          { "diaDeSemana": 5, "tipo": "facil", "nombre": "Caminata y trote largo", "descripcion": "Mismo juego, un poco más de distancia.", "segmentos": [ { "nombre": "Alternado suave", "distanciaKm": 3 } ] } ] },
        { "numero": 2, "entrenamientos": [
          { "diaDeSemana": 1, "tipo": "facil", "nombre": "Trote con pausas 1", "descripcion": "2 min de trote, 1 de caminata.", "segmentos": [ { "nombre": "Alternado", "distanciaKm": 3 } ] },
          { "diaDeSemana": 3, "tipo": "facil", "nombre": "Trote con pausas 2", "descripcion": "2 min de trote, 1 de caminata.", "segmentos": [ { "nombre": "Alternado", "distanciaKm": 3 } ] },
          { "diaDeSemana": 5, "tipo": "largo", "nombre": "Salida larga", "descripcion": "Tranquilo, caminá cuando lo necesites.", "segmentos": [ { "nombre": "Alternado largo", "distanciaKm": 3.5 } ] } ] },
        { "numero": 3, "entrenamientos": [
          { "diaDeSemana": 1, "tipo": "facil", "nombre": "Trote 5 y 1", "descripcion": "5 min de trote, 1 de caminata.", "segmentos": [ { "nombre": "Alternado", "distanciaKm": 3.5 } ] },
          { "diaDeSemana": 3, "tipo": "facil", "nombre": "Trote 5 y 1", "descripcion": "5 min de trote, 1 de caminata.", "segmentos": [ { "nombre": "Alternado", "distanciaKm": 3.5 } ] },
          { "diaDeSemana": 5, "tipo": "largo", "nombre": "Salida larga", "descripcion": "Sumá distancia sin apuro.", "segmentos": [ { "nombre": "Alternado largo", "distanciaKm": 4 } ] } ] },
        { "numero": 4, "entrenamientos": [
          { "diaDeSemana": 1, "tipo": "facil", "nombre": "Trote 8 y 1", "descripcion": "8 min de trote, 1 de caminata.", "segmentos": [ { "nombre": "Casi corrido", "distanciaKm": 4 } ] },
          { "diaDeSemana": 3, "tipo": "facil", "nombre": "Trote 8 y 1", "descripcion": "8 min de trote, 1 de caminata.", "segmentos": [ { "nombre": "Casi corrido", "distanciaKm": 4 } ] },
          { "diaDeSemana": 5, "tipo": "largo", "nombre": "Salida larga", "descripcion": "La más larga hasta ahora.", "segmentos": [ { "nombre": "Alternado largo", "distanciaKm": 4.5 } ] } ] },
        { "numero": 5, "entrenamientos": [
          { "diaDeSemana": 1, "tipo": "facil", "nombre": "Trote corrido corto", "descripcion": "Trotá de corrido; caminá solo si hace falta.", "segmentos": [ { "nombre": "Corrido", "distanciaKm": 4 } ] },
          { "diaDeSemana": 3, "tipo": "facil", "nombre": "Trote corrido", "descripcion": "De corrido, ritmo de charla.", "segmentos": [ { "nombre": "Corrido", "distanciaKm": 4.5 } ] },
          { "diaDeSemana": 5, "tipo": "largo", "nombre": "Ensayo casi 5K", "descripcion": "Cerca de la distancia objetivo.", "segmentos": [ { "nombre": "Corrido", "distanciaKm": 4.5 } ] } ] },
        { "numero": 6, "entrenamientos": [
          { "diaDeSemana": 1, "tipo": "recuperacion", "nombre": "Suave", "descripcion": "Cortito y fácil antes del objetivo.", "segmentos": [ { "nombre": "Suave", "distanciaKm": 3 } ] },
          { "diaDeSemana": 3, "tipo": "facil", "nombre": "Trote corrido", "descripcion": "Últimos ajustes, sin exigirte.", "segmentos": [ { "nombre": "Corrido", "distanciaKm": 4 } ] },
          { "diaDeSemana": 5, "tipo": "ritmoCarrera", "nombre": "¡Tus primeros 5K!", "descripcion": "El día: 5 km de corrido, a tu ritmo.", "segmentos": [ { "nombre": "5K corrido", "distanciaKm": 5 } ] } ] }
      ]
    }
    """

    static let json10K = """
    {
      "id": "10k-continuo", "version": 1,
      "nombre": "Rumbo a 10K",
      "descripcion": "Para quien ya corre ~5 km y quiere llegar a 10 de corrido. Tres salidas por semana con una larga progresiva. Ritmos libres y cómodos. Contenido provisional.",
      "distanciaObjetivoKm": 10, "semanasTotales": 8, "diasPorSemana": 3,
      "provisional": true,
      "semanas": [
        { "numero": 1, "entrenamientos": [
          { "diaDeSemana": 1, "tipo": "facil", "nombre": "Rodaje", "descripcion": "Ritmo de charla.", "segmentos": [ { "nombre": "Rodaje", "distanciaKm": 4 } ] },
          { "diaDeSemana": 3, "tipo": "facil", "nombre": "Rodaje", "descripcion": "Ritmo de charla.", "segmentos": [ { "nombre": "Rodaje", "distanciaKm": 4 } ] },
          { "diaDeSemana": 5, "tipo": "largo", "nombre": "Larga", "descripcion": "Tranquila y constante.", "segmentos": [ { "nombre": "Larga", "distanciaKm": 5 } ] } ] },
        { "numero": 2, "entrenamientos": [
          { "diaDeSemana": 1, "tipo": "facil", "nombre": "Rodaje", "descripcion": "Ritmo de charla.", "segmentos": [ { "nombre": "Rodaje", "distanciaKm": 4 } ] },
          { "diaDeSemana": 3, "tipo": "facil", "nombre": "Rodaje", "descripcion": "Ritmo de charla.", "segmentos": [ { "nombre": "Rodaje", "distanciaKm": 4.5 } ] },
          { "diaDeSemana": 5, "tipo": "largo", "nombre": "Larga", "descripcion": "Sumamos un poco.", "segmentos": [ { "nombre": "Larga", "distanciaKm": 6 } ] } ] },
        { "numero": 3, "entrenamientos": [
          { "diaDeSemana": 1, "tipo": "facil", "nombre": "Rodaje", "descripcion": "Cómodo.", "segmentos": [ { "nombre": "Rodaje", "distanciaKm": 4.5 } ] },
          { "diaDeSemana": 3, "tipo": "facil", "nombre": "Rodaje con final animado", "descripcion": "El último kilómetro un toque más vivo, sin ahogarte.", "segmentos": [ { "nombre": "Rodaje", "distanciaKm": 4 }, { "nombre": "Final animado", "distanciaKm": 1 } ] },
          { "diaDeSemana": 5, "tipo": "largo", "nombre": "Larga", "descripcion": "Constante.", "segmentos": [ { "nombre": "Larga", "distanciaKm": 6.5 } ] } ] },
        { "numero": 4, "entrenamientos": [
          { "diaDeSemana": 1, "tipo": "recuperacion", "nombre": "Suave", "descripcion": "Semana amable: recuperar también entrena.", "segmentos": [ { "nombre": "Suave", "distanciaKm": 4 } ] },
          { "diaDeSemana": 3, "tipo": "facil", "nombre": "Rodaje", "descripcion": "Cómodo.", "segmentos": [ { "nombre": "Rodaje", "distanciaKm": 5 } ] },
          { "diaDeSemana": 5, "tipo": "largo", "nombre": "Larga", "descripcion": "Igual que la anterior.", "segmentos": [ { "nombre": "Larga", "distanciaKm": 6.5 } ] } ] },
        { "numero": 5, "entrenamientos": [
          { "diaDeSemana": 1, "tipo": "facil", "nombre": "Rodaje", "descripcion": "Cómodo.", "segmentos": [ { "nombre": "Rodaje", "distanciaKm": 5 } ] },
          { "diaDeSemana": 3, "tipo": "facil", "nombre": "Rodaje con final animado", "descripcion": "Últimos 1,5 km más vivos.", "segmentos": [ { "nombre": "Rodaje", "distanciaKm": 4 }, { "nombre": "Final animado", "distanciaKm": 1.5 } ] },
          { "diaDeSemana": 5, "tipo": "largo", "nombre": "Larga", "descripcion": "Paso firme.", "segmentos": [ { "nombre": "Larga", "distanciaKm": 7.5 } ] } ] },
        { "numero": 6, "entrenamientos": [
          { "diaDeSemana": 1, "tipo": "facil", "nombre": "Rodaje", "descripcion": "Cómodo.", "segmentos": [ { "nombre": "Rodaje", "distanciaKm": 5 } ] },
          { "diaDeSemana": 3, "tipo": "facil", "nombre": "Rodaje", "descripcion": "Cómodo.", "segmentos": [ { "nombre": "Rodaje", "distanciaKm": 5.5 } ] },
          { "diaDeSemana": 5, "tipo": "largo", "nombre": "Larga", "descripcion": "Ya casi.", "segmentos": [ { "nombre": "Larga", "distanciaKm": 8.5 } ] } ] },
        { "numero": 7, "entrenamientos": [
          { "diaDeSemana": 1, "tipo": "facil", "nombre": "Rodaje", "descripcion": "Cómodo.", "segmentos": [ { "nombre": "Rodaje", "distanciaKm": 5 } ] },
          { "diaDeSemana": 3, "tipo": "facil", "nombre": "Rodaje con final animado", "descripcion": "Último ensayo con chispa.", "segmentos": [ { "nombre": "Rodaje", "distanciaKm": 4.5 }, { "nombre": "Final animado", "distanciaKm": 1.5 } ] },
          { "diaDeSemana": 5, "tipo": "largo", "nombre": "Larga grande", "descripcion": "La más larga del plan.", "segmentos": [ { "nombre": "Larga", "distanciaKm": 9 } ] } ] },
        { "numero": 8, "entrenamientos": [
          { "diaDeSemana": 1, "tipo": "recuperacion", "nombre": "Suave", "descripcion": "Descarga: piernas frescas.", "segmentos": [ { "nombre": "Suave", "distanciaKm": 4 } ] },
          { "diaDeSemana": 3, "tipo": "facil", "nombre": "Rodaje corto", "descripcion": "Soltar piernas.", "segmentos": [ { "nombre": "Rodaje", "distanciaKm": 4 } ] },
          { "diaDeSemana": 5, "tipo": "ritmoCarrera", "nombre": "¡Tus 10K!", "descripcion": "El día: 10 km de corrido, administrate.", "segmentos": [ { "nombre": "10K corrido", "distanciaKm": 10 } ] } ] }
      ]
    }
    """
}

// MARK: - Store del almacén V2 (con cutover)

/// Dueño en runtime del dominio-v2.json. En su init hace el CUTOVER:
/// desde entonces el archivo es la fuente autoritativa de
/// plan/calendario en el iPhone y la migración legacy no lo toca más
/// (guard `activado` en PlanStore). Orden-independiente respecto de
/// PlanStore: si el ensayo existe se activa; si no, migra directo del
/// legacy; si tampoco hay legacy, almacén nuevo sin entidades basura.
final class AlmacenStore: ObservableObject {

    @Published var almacen: AlmacenV2 {
        didSet { guardar() }
    }

    private let url: URL

    init(url: URL = PlanStore.urlDominioV2,
         urlLegacy: URL = PlanStore.urlPlanLegacy,
         fecha: Date = Date()) {
        self.url = url
        almacen = Self.cargarConCutover(urlV2: url, urlLegacy: urlLegacy, fecha: fecha)
    }

    /// Idempotente entre arranques: activado → cargar y listo.
    static func cargarConCutover(urlV2: URL, urlLegacy: URL, fecha: Date) -> AlmacenV2 {
        if let datos = try? Data(contentsOf: urlV2),
           var existente = try? JSONDecoder().decode(AlmacenV2.self, from: datos) {
            guard !existente.activado else { return existente }
            // Cutover del ensayo (usuario existente): el snapshot de la
            // migración pasa a ser el PlanUsuario real.
            existente.activado = true
            escribir(existente, en: urlV2)
            return existente
        }
        // Sin ensayo: migrar directo del legacy si existe; usuario
        // nuevo → almacén limpio (sin plan fantasma).
        let legacy = (try? Data(contentsOf: urlLegacy))
            .flatMap { try? JSONDecoder().decode(Plan.self, from: $0) }
        var almacen = legacy.map {
            MigracionV2.migrar(planV1: $0, huellaCumplida: nil, fecha: fecha)
        } ?? AlmacenV2()
        almacen.activado = true
        escribir(almacen, en: urlV2)
        return almacen
    }

    func adoptar(_ base: PlanBase, inicio: DiaLocal, fecha: Date = Date()) {
        let nuevo = base.adoptar(inicio: inicio, fechaAdopcion: fecha)
        almacen.adoptarPlan(nuevo)  // archiva el anterior, no lo pisa
    }

    /// El calendario se entera de una sesión guardada (el didSet
    /// persiste y la UI se refresca sola — sin reiniciar nada).
    func registrar(_ sesion: SesionGuardada, programadoID: UUID?) {
        if let programadoID {
            almacen.vincular(sesionID: sesion.hkUUID, fechaSesion: sesion.fecha,
                             aProgramado: programadoID,
                             completo: sesion.estructuraCompleta)
        } else {
            almacen.registrarSesionLibre(sesionID: sesion.hkUUID, fecha: sesion.fecha)
        }
    }

    private func guardar() {
        Self.escribir(almacen, en: url)
    }

    private static func escribir(_ almacen: AlmacenV2, en url: URL) {
        if let datos = try? JSONEncoder().encode(almacen) {
            try? datos.write(to: url, options: .atomic)
        }
    }
}

// MARK: - Lanzador de sesiones (un solo camino al motor)

/// El ÚNICO camino para arrancar el motor del iPhone, desde cualquier
/// pantalla (Plan hoy, Correr programado, Correr libre): así el
/// entrenamiento del día y la carrera libre llegan al mismo motor sin
/// caminos paralelos. El audio sale de la config legacy (pistas y
/// avisos del PlanStore) hasta que la UI de audio migre a V2.
enum LanzadorSesion {
    static func iniciar(definicion: DefinicionEntrenamiento?,
                        programadoID: UUID?,
                        store: PlanStore,
                        almacen: AlmacenStore) {
        let legacy = store.plan
        let planSesion: Plan
        if let definicion {
            let tramos = definicion.tramosEjecutables
            planSesion = Plan(nombre: definicion.nombre,
                              pistas: legacy.pistas,
                              avisosFijos: legacy.avisosFijos,
                              avisosRepetidos: legacy.avisosRepetidos,
                              tramos: tramos.isEmpty ? nil : tramos,
                              avisosKm: legacy.avisosKm)
        } else {
            // Carrera libre: comportamiento actual intacto (el plan
            // legacy completo, incluidos sus tramos manuales si los hay).
            planSesion = legacy
        }
        CarreraCelu.compartida.iniciar(
            plan: planSesion,
            urlDe: { store.urlDePista($0) },
            programadoID: programadoID
        ) { sesion in
            almacen.registrar(sesion, programadoID: programadoID)
        }
    }
}

// MARK: - UI: catálogo

struct CatalogoView: View {
    @ObservedObject var almacen: AlmacenStore

    var body: some View {
        List {
            Section {
                ForEach(Catalogo.planesDisponibles()) { base in
                    NavigationLink {
                        PlanBaseDetalleView(almacen: almacen, base: base)
                    } label: {
                        HStack(spacing: 12) {
                            IconoAjuste(sistema: "figure.run", color: .green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(base.nombre)
                                Text("\(base.semanasTotales) semanas · \(base.diasPorSemana) días por semana")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } footer: {
                Text("Planes iniciales para validar la experiencia — el contenido es provisional y con ritmos libres. Los planes con ritmos personalizados llegan con la evaluación inicial.")
            }
        }
        .navigationTitle("Explorar planes")
    }
}

struct PlanBaseDetalleView: View {
    @ObservedObject var almacen: AlmacenStore
    let base: PlanBase
    @Environment(\.dismiss) private var dismiss
    @State private var fechaInicio = Date()
    @State private var confirmandoReemplazo = false

    var body: some View {
        List {
            Section {
                Text(base.descripcion)
                    .font(.callout)
                HStack(spacing: 8) {
                    Chip(texto: String(format: "%.0f km objetivo", base.distanciaObjetivoKm))
                    Chip(texto: "\(base.semanasTotales) semanas")
                    Chip(texto: "\(base.diasPorSemana) días/sem")
                }
            }

            Section("Arranque") {
                DatePicker("Empezás el", selection: $fechaInicio, displayedComponents: .date)
                Button {
                    if almacen.almacen.planActivo != nil {
                        confirmandoReemplazo = true
                    } else {
                        adoptar()
                    }
                } label: {
                    Label("Adoptar este plan", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .confirmationDialog("Ya tenés un plan activo",
                                    isPresented: $confirmandoReemplazo,
                                    titleVisibility: .visible) {
                    Button("Reemplazar (el actual queda archivado)", role: .destructive) {
                        adoptar()
                    }
                    Button("Cancelar", role: .cancel) {}
                } message: {
                    Text("Tu plan actual no se borra: queda guardado como inactivo, con su historial.")
                }
            }

            ForEach(base.semanas, id: \.numero) { semana in
                Section("Semana \(semana.numero)") {
                    ForEach(Array(semana.entrenamientos.enumerated()), id: \.offset) { _, entrenamiento in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(entrenamiento.nombre)
                            Text(entrenamiento.descripcion)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(base.nombre)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func adoptar() {
        almacen.adoptar(base, inicio: DiaLocal(fecha: fechaInicio))
        dismiss()
    }
}

// MARK: - UI: calendario

struct CalendarioView: View {
    @ObservedObject var almacen: AlmacenStore

    var body: some View {
        List {
            if let plan = almacen.almacen.planActivo {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.nombre)
                            .font(.headline)
                        if case .catalogo(let origen) = plan.origen {
                            Text("Del catálogo (\(origen))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        textoDeHoy
                    }
                }
                ForEach(plan.semanas) { semana in
                    Section("Semana \(semana.numero)\(esSemanaActual(semana) ? " — actual" : "")") {
                        ForEach(semana.programados) { programado in
                            filaProgramado(programado)
                        }
                    }
                }
            } else {
                Text("Sin plan activo. Adoptá uno desde «Explorar planes».")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Calendario")
    }

    private var hoy: DiaLocal { DiaLocal(fecha: Date()) }

    @ViewBuilder
    private var textoDeHoy: some View {
        if let deHoy = almacen.almacen.entrenamientoDeHoy(hoy) {
            Label("Hoy: \(deHoy.definicion.nombre)", systemImage: "sun.max.fill")
                .font(.subheadline)
                .foregroundStyle(.orange)
        } else {
            Label("Hoy no tenés entrenamiento programado.", systemImage: "moon.zzz.fill")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// La semana cuyo rango [primer día programado, +6] contiene hoy.
    private func esSemanaActual(_ semana: SemanaPlan) -> Bool {
        guard let primero = semana.programados.compactMap(\.dia).min() else { return false }
        let fin = primero.sumando(dias: 6)
        return !(hoy < primero) && !(fin < hoy)
    }

    private func filaProgramado(_ programado: EntrenamientoProgramado) -> some View {
        let estado = programado.estado(hoy: hoy)
        return HStack(spacing: 10) {
            insignia(estado)
            VStack(alignment: .leading, spacing: 2) {
                Text(programado.definicion.nombre)
                HStack(spacing: 6) {
                    if let dia = programado.dia, let fecha = dia.fecha() {
                        Text(fecha.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                            .font(.caption)
                            .foregroundStyle(programado.dia == hoy ? Color.orange : Color.secondary)
                    }
                    Text(nombreDeTipo(programado.definicion.tipo))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if programado.dia == hoy && estado == .programado {
                Text("HOY")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.orange)
            }
        }
    }

    private func insignia(_ estado: EstadoProgramado) -> some View {
        let (icono, color): (String, Color) = {
            switch estado {
            case .programado: return ("circle", .secondary)
            case .vencido: return ("exclamationmark.circle.fill", .orange)
            case .parcial: return ("circle.bottomhalf.filled", .yellow)
            case .cumplido: return ("checkmark.circle.fill", .green)
            case .omitido: return ("minus.circle.fill", .gray)
            }
        }()
        return Image(systemName: icono)
            .font(.title3)
            .foregroundStyle(color)
    }

    private func nombreDeTipo(_ tipo: TipoEntrenamiento) -> String {
        switch tipo {
        case .facil: return "Fácil"
        case .recuperacion: return "Recuperación"
        case .largo: return "Larga"
        case .tempo: return "Tempo"
        case .umbral: return "Umbral"
        case .series: return "Series"
        case .ritmoCarrera: return "Ritmo de carrera"
        case .testEvaluacion: return "Evaluación"
        case .personalizado: return "Personalizado"
        }
    }
}
