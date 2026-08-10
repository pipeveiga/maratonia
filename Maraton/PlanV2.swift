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

    /// false en tests: los stores de prueba no deben tocar WCSession ni
    /// pisarse el registro de resultados entre sí.
    private let conectadoAlReloj: Bool

    init(url: URL = PlanStore.urlDominioV2,
         urlLegacy: URL = PlanStore.urlPlanLegacy,
         fecha: Date = Date(),
         conectadoAlReloj: Bool = true) {
        self.url = url
        self.conectadoAlReloj = conectadoAlReloj
        almacen = Self.cargarConCutover(urlV2: url, urlLegacy: urlLegacy, fecha: fecha)
        guard conectadoAlReloj else { return }
        // Fase E: el reloj recibe la proyección de HOY y devuelve
        // resultados; este store es el dueño de las dos puntas.
        Conectividad.compartida.proveedorProyeccion = { [weak self] in
            self?.proyeccionDeHoy()
        }
        Conectividad.compartida.entregarResultados { [weak self] resultado in
            self?.procesar(resultado: resultado)
        }
        Conectividad.compartida.enviar(proyeccion: proyeccionDeHoy())
    }

    // MARK: Proyección del día (Fase E)

    /// La foto de HOY para el reloj: el pendiente del día si existe.
    /// También se manda "vacía" (sin definición) — así el reloj se
    /// entera de que hoy NO hay nada pendiente. Y si el programado de
    /// hoy ya se RESOLVIÓ, viaja como resultado para que el reloj lo
    /// muestre como estado del día (bug 2 de build 38).
    func proyeccionDeHoy(fecha: Date = Date()) -> ProyeccionDia {
        let hoy = DiaLocal(fecha: fecha)
        let deHoy = almacen.entrenamientoDeHoy(hoy)
        var proyeccion = ProyeccionDia(generadaEl: fecha,
                                       dia: hoy,
                                       programadoID: deHoy?.id,
                                       definicion: deHoy?.definicion,
                                       nombrePlan: almacen.planActivo?.nombre)
        if deHoy == nil,
           let resuelto = almacen.programadoDelDia(hoy),
           resuelto.resolucion != .pendiente {
            proyeccion.resolucionDeHoy = resuelto.resolucion
            proyeccion.nombreDeHoy = resuelto.definicion.nombre
            proyeccion.tipoDeHoy = resuelto.definicion.tipo
        }
        return proyeccion
    }

    // MARK: Resultados del reloj (Fase E)

    /// Idempotente y a prueba de desorden: el mismo resultado puede
    /// llegar dos veces (cola de WC) o tarde (reloj offline). Reglas:
    /// - programadoID nil o ya desconocido (plan cambiado/archivado) →
    ///   la sesión se registra como LIBRE: la evidencia nunca se tira;
    /// - programado ya resuelto por OTRA sesión (corriste desde el
    ///   iPhone y el resultado viejo del reloj llegó después) → LIBRE,
    ///   el vínculo existente no se pisa;
    /// - duplicado exacto → vincular/registrar ya son idempotentes.
    func procesar(resultado: ResultadoSesionWatch) {
        if let programadoID = resultado.programadoID,
           let programado = almacen.todosLosProgramados.first(where: { $0.id == programadoID }) {
            let resueltoPorOtra = programado.resolucion != .pendiente
                && programado.sesionVinculadaID != resultado.sesionID
            if !resueltoPorOtra {
                almacen.vincular(sesionID: resultado.sesionID,
                                 fechaSesion: resultado.fecha,
                                 aProgramado: programadoID,
                                 completo: resultado.estructuraCompleta)
                return
            }
        }
        almacen.registrarSesionLibre(sesionID: resultado.sesionID, fecha: resultado.fecha)
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

    // MARK: Perfil deportivo y referencias (Fase F)

    /// El onboarding terminó: se guarda el perfil y, si trajo una marca,
    /// la referencia cruda. NO toca plan, sesiones ni audio — el
    /// onboarding es aditivo por diseño.
    func guardarOnboarding(_ perfil: PerfilDeportivo,
                           marca: ReferenciaRendimiento?) {
        almacen.perfil = perfil
        if let marca {
            almacen.registrarReferencia(marca)
        }
    }

    func registrarResultadoDeTest(distanciaMetros: Double, segundos: Int, fecha: Date) {
        almacen.registrarReferencia(ReferenciaRendimiento(
            fecha: fecha, fuente: .test5K,
            distanciaMetros: distanciaMetros, segundos: segundos))
        if almacen.perfil?.testPendiente == true {
            almacen.perfil?.testPendiente = false
        }
    }

    private func guardar() {
        Self.escribir(almacen, en: url)
        // Cada mutación re-proyecta HOY al reloj: adopción, vínculo,
        // omitir, reprogramar — todo pasa por el didSet, así que el
        // reloj nunca queda mirando un "hoy" viejo por más de un canal
        // caído (y applicationContext lo entrega al reconectar).
        if conectadoAlReloj {
            Conectividad.compartida.enviar(proyeccion: proyeccionDeHoy())
        }
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
            // Test de evaluación completado: la marca CRUDA queda como
            // referencia (tiempo activo AL COMPLETAR los 5 km — el
            // trote posterior no la ensucia).
            if let definicion, definicion.tipo == .testEvaluacion,
               sesion.estructuraCompleta,
               let segundos = sesion.tiempoEstructuraSegundos, segundos > 0,
               let metros = definicion.distanciaTotalKm.map({ $0 * 1000 }) {
                almacen.registrarResultadoDeTest(distanciaMetros: metros,
                                                 segundos: segundos,
                                                 fecha: sesion.fecha)
            }
        }
    }

    /// El Test 5K del onboarding: un entrenamiento REAL (pasa por el
    /// mismo motor, se guarda en Salud) cuyo tiempo final es la
    /// referencia de rendimiento.
    static func definicionTest5K() -> DefinicionEntrenamiento {
        DefinicionEntrenamiento(
            tipo: .testEvaluacion,
            nombre: "Test 5K",
            descripcion: "5 km fuerte pero controlado: el objetivo es un ritmo que puedas sostener parejo hasta el final.",
            segmentos: [Segmento(nombre: "Test 5K", distanciaKm: 5)])
    }
}

// MARK: - UI: catálogo

struct CatalogoView: View {
    @ObservedObject var almacen: AlmacenStore

    /// Filtros listos para cuando el catálogo crezca (hoy: 2 planes
    /// provisionales — el vacío se dice con honestidad, no se rellena
    /// con contenido deportivo inventado).
    @State private var filtroDistancia: Double?   // metros; nil = todas
    @State private var filtroDias: Int?           // nil = todos

    private static let distancias: [(nombre: String, metros: Double)] =
        [("5K", 5000), ("10K", 10000), ("21K", 21097.5), ("42K", 42195)]

    private var filtrados: [PlanBase] {
        Catalogo.planesDisponibles().filter { base in
            if let filtroDistancia,
               abs(base.distanciaObjetivoKm * 1000 - filtroDistancia) > 500 { return false }
            if let filtroDias, base.diasPorSemana != filtroDias { return false }
            return true
        }
    }

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DV2.Espacio.s) {
                        chip("Todas", activo: filtroDistancia == nil) { filtroDistancia = nil }
                        ForEach(Self.distancias, id: \.metros) { distancia in
                            chip(distancia.nombre,
                                 activo: filtroDistancia == distancia.metros) {
                                filtroDistancia = distancia.metros
                            }
                        }
                        Divider().frame(height: 20)
                        ForEach([2, 3, 4, 5], id: \.self) { dias in
                            chip("\(dias) días",
                                 activo: filtroDias == dias) {
                                filtroDias = (filtroDias == dias) ? nil : dias
                            }
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section {
                if filtrados.isEmpty {
                    ContentUnavailableView {
                        Label("Todavía no hay planes acá", systemImage: "hourglass")
                    } description: {
                        Text("Los planes de esta distancia están en camino — no vamos a inventar contenido deportivo para llenar tarjetas. Probá con 5K o 10K.")
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(filtrados) { base in
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
                if !filtrados.isEmpty {
                    Text("Planes iniciales para validar la experiencia — el contenido es provisional y con ritmos libres. Los planes con ritmos personalizados llegan con la evaluación inicial.")
                }
            }
        }
        .navigationTitle("Explorar planes")
    }

    private func chip(_ texto: String, activo: Bool, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            Text(texto)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(activo ? Color.white : Color.primary)
                .padding(.horizontal, DV2.Espacio.m)
                .padding(.vertical, 6)
                .background(activo ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                            in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(activo ? .isSelected : [])
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

// MARK: - UI: semana actual (el pulso del plan en una fila)

/// L M X J V S D con el estado de cada día — hechos, hoy, próximos,
/// parciales, vencidos y omitidos de un vistazo. Tocar un día con
/// entrenamiento abre su detalle.
struct SemanaActualV2: View {
    @ObservedObject var almacen: AlmacenStore
    @ObservedObject var store: PlanStore
    @Binding var pestana: Pestana

    private var hoy: DiaLocal { DiaLocal(fecha: Date()) }

    var body: some View {
        let dias = almacen.almacen.semanaActual(hoy: hoy)
        HStack(spacing: 0) {
            ForEach(dias) { item in
                celda(item)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, DV2.Espacio.xs)
    }

    @ViewBuilder
    private func celda(_ item: DiaDeSemana) -> some View {
        if let programado = item.programado {
            NavigationLink {
                DetalleEntrenamientoView(almacen: almacen, store: store,
                                         pestana: $pestana,
                                         programadoID: programado.id)
            } label: {
                columna(item)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(etiquetaAccesible(item))
        } else {
            columna(item)
                .accessibilityLabel(etiquetaAccesible(item))
        }
    }

    private func columna(_ item: DiaDeSemana) -> some View {
        VStack(spacing: 5) {
            Text(letra(de: item.dia))
                .font(.caption2.weight(item.esHoy ? .bold : .regular))
                .foregroundStyle(item.esHoy ? Color.accentColor : Color.secondary)
            ZStack {
                Circle()
                    .fill(colorDeFondo(item))
                    .frame(width: 34, height: 34)
                if item.esHoy {
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .frame(width: 34, height: 34)
                }
                simbolo(item)
            }
        }
    }

    @ViewBuilder
    private func simbolo(_ item: DiaDeSemana) -> some View {
        if let programado = item.programado {
            switch programado.estado(hoy: hoy) {
            case .cumplido:
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            case .parcial:
                Image(systemName: "circle.bottomhalf.filled")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
            case .omitido:
                Image(systemName: "minus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            case .vencido:
                Image(systemName: "exclamationmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            case .programado:
                Circle()
                    .fill(DV2.color(de: programado.definicion.tipo))
                    .frame(width: 10, height: 10)
            }
        } else {
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 5, height: 5)
        }
    }

    private func colorDeFondo(_ item: DiaDeSemana) -> Color {
        guard let programado = item.programado else {
            return Color(.tertiarySystemGroupedBackground)
        }
        switch programado.estado(hoy: hoy) {
        case .cumplido: return .green
        case .parcial: return .yellow
        case .omitido: return Color(.systemGray3)
        case .vencido: return .orange
        case .programado:
            return DV2.color(de: programado.definicion.tipo).opacity(0.15)
        }
    }

    private func letra(de dia: DiaLocal) -> String {
        guard let fecha = dia.fecha() else { return "" }
        let indice = (Calendar.current.component(.weekday, from: fecha) + 5) % 7
        return ["L", "M", "X", "J", "V", "S", "D"][indice]
    }

    private func etiquetaAccesible(_ item: DiaDeSemana) -> String {
        let nombreDia = item.dia.fecha()?.formatted(.dateTime.weekday(.wide)) ?? ""
        guard let programado = item.programado else { return "\(nombreDia): descanso" }
        let estado: String
        switch programado.estado(hoy: hoy) {
        case .cumplido: estado = "cumplido"
        case .parcial: estado = "parcial"
        case .omitido: estado = "omitido"
        case .vencido: estado = "vencido"
        case .programado: estado = item.esHoy ? "hoy" : "programado"
        }
        return "\(nombreDia): \(programado.definicion.nombre), \(estado)"
    }
}

// MARK: - UI: detalle del entrenamiento (acciones por estado)

/// TODO lo del programado en un lugar: qué es, cuándo, cómo quedó, y
/// las acciones que su estado permite — nunca acciones imposibles.
struct DetalleEntrenamientoView: View {
    @ObservedObject var almacen: AlmacenStore
    @ObservedObject var store: PlanStore
    @Binding var pestana: Pestana
    let programadoID: UUID

    @Environment(\.dismiss) private var dismiss
    @StateObject private var carreras = CarrerasStore()
    @State private var mostrandoReprogramar = false
    @State private var nuevaFecha = Date()
    @State private var confirmandoOmitir = false

    private var hoy: DiaLocal { DiaLocal(fecha: Date()) }

    var body: some View {
        if let programado = almacen.almacen.todosLosProgramados
            .first(where: { $0.id == programadoID }) {
            contenido(programado)
        } else {
            ContentUnavailableView {
                Label("Ya no está en el plan", systemImage: "calendar.badge.minus")
            } description: {
                Text("Este entrenamiento pertenece a un plan archivado o reemplazado.")
            }
        }
    }

    private func contenido(_ programado: EntrenamientoProgramado) -> some View {
        let estado = programado.estado(hoy: hoy)
        return List {
            Section {
                VStack(alignment: .leading, spacing: DV2.Espacio.s) {
                    HStack {
                        ChipTipoV2(tipo: programado.definicion.tipo)
                        Spacer()
                        insigniaEstado(estado)
                    }
                    Text(programado.definicion.nombre)
                        .font(.title2.bold())
                    if let fecha = programado.dia?.fecha() {
                        Text(fecha.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let original = programado.diaOriginal, original != programado.dia,
                       let fechaOriginal = original.fecha() {
                        Text("Reprogramado (era el \(fechaOriginal.formatted(.dateTime.day().month())))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !programado.definicion.descripcion.isEmpty {
                        Text(programado.definicion.descripcion)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: DV2.Espacio.xl) {
                        if let km = programado.definicion.distanciaTotalKm {
                            MetricaV2(titulo: "distancia",
                                      valor: km == km.rounded()
                                        ? "\(Int(km)) km" : String(format: "%.1f km", km))
                        }
                        if let segundos = programado.definicion.duracionPorTiempoSegundos {
                            MetricaV2(titulo: "por tiempo", valor: duracionTexto(segundos))
                        }
                    }
                    .padding(.top, DV2.Espacio.xs)
                }
                .padding(.vertical, DV2.Espacio.xs)
            }

            if !programado.definicion.segmentos.isEmpty {
                Section("Estructura") {
                    ForEach(Array(programado.definicion.segmentos.enumerated()),
                            id: \.element.id) { indice, segmento in
                        HStack(spacing: DV2.Espacio.m) {
                            Text("\(indice + 1)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Text(segmento.nombre)
                            Spacer()
                            Text(DV2.metaDeSegmento(segmento))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if let sesionID = programado.sesionVinculadaID {
                seccionSesion(sesionID)
            }

            seccionAcciones(programado, estado: estado)
        }
        .navigationTitle(programado.definicion.nombre)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $mostrandoReprogramar) {
            hojaReprogramar(programado)
        }
        .confirmationDialog("¿Omitir este entrenamiento?",
                            isPresented: $confirmandoOmitir,
                            titleVisibility: .visible) {
            Button("Omitir", role: .destructive) {
                almacen.almacen.omitir(programadoID: programadoID)
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Queda marcado como omitido en el calendario — no se borra nada y podés deshacerlo.")
        }
    }

    @ViewBuilder
    private func seccionSesion(_ sesionID: UUID) -> some View {
        Section("Sesión realizada") {
            if let sesion = almacen.almacen.sesiones.first(where: { $0.id == sesionID }) {
                LabeledContent("Fecha",
                               value: sesion.fecha.formatted(date: .abbreviated,
                                                             time: .shortened))
            }
            NavigationLink {
                CarreraDetalleView(store: carreras, id: sesionID)
            } label: {
                Label("Ver carrera", systemImage: "map.fill")
            }
            // Precarga: cuando el usuario toque "Ver carrera", el
            // detalle ya tiene los datos de Salud listos.
            .onAppear { carreras.cargar() }
        }
    }

    @ViewBuilder
    private func seccionAcciones(_ programado: EntrenamientoProgramado,
                                 estado: EstadoProgramado) -> some View {
        switch estado {
        case .programado, .vencido:
            Section {
                Button {
                    LanzadorSesion.iniciar(definicion: programado.definicion,
                                           programadoID: programado.id,
                                           store: store, almacen: almacen)
                    pestana = .correr
                    dismiss()
                } label: {
                    EtiquetaBotonPrimarioV2(titulo: "Empezar")
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            Section {
                Button {
                    nuevaFecha = programado.dia?.fecha() ?? Date()
                    mostrandoReprogramar = true
                } label: {
                    Label("Reprogramar", systemImage: "calendar.badge.clock")
                }
                Button(role: .destructive) {
                    confirmandoOmitir = true
                } label: {
                    Label("Omitir", systemImage: "minus.circle")
                }
            }
        case .omitido:
            if programado.sesionVinculadaID == nil {
                Section {
                    Button {
                        almacen.almacen.deshacerOmision(programadoID: programadoID)
                    } label: {
                        Label("Deshacer omisión", systemImage: "arrow.uturn.backward")
                    }
                } footer: {
                    Text("Vuelve a quedar pendiente en su día.")
                }
            }
        case .cumplido, .parcial:
            EmptyView()   // la sesión realizada ya está arriba
        }
    }

    private func hojaReprogramar(_ programado: EntrenamientoProgramado) -> some View {
        NavigationStack {
            Form {
                DatePicker("Nueva fecha", selection: $nuevaFecha,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)

                if let conflicto = almacen.almacen.conflictoEnDia(
                    DiaLocal(fecha: nuevaFecha), salvo: programadoID) {
                    Label("Ese día ya tiene «\(conflicto.definicion.nombre)». Pueden convivir los dos, pero vas a tener doble entrenamiento.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }

                if let original = programado.diaOriginal ?? programado.dia,
                   let fechaOriginal = original.fecha() {
                    Text("Fecha original: \(fechaOriginal.formatted(.dateTime.weekday(.abbreviated).day().month()))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Reprogramar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { mostrandoReprogramar = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirmar") {
                        almacen.almacen.reprogramar(programadoID: programadoID,
                                                    a: DiaLocal(fecha: nuevaFecha))
                        mostrandoReprogramar = false
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func insigniaEstado(_ estado: EstadoProgramado) -> some View {
        let (texto, icono, color): (String, String, Color) = {
            switch estado {
            case .programado: return ("Programado", "circle", .secondary)
            case .vencido: return ("Vencido", "exclamationmark.circle.fill", .orange)
            case .parcial: return ("Parcial", "circle.bottomhalf.filled", .yellow)
            case .cumplido: return ("Cumplido", "checkmark.seal.fill", .green)
            case .omitido: return ("Omitido", "minus.circle.fill", .gray)
            }
        }()
        return Label(texto, systemImage: icono)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
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
                    Text(DV2.nombre(de: programado.definicion.tipo))
                        .font(.caption)
                        .foregroundStyle(DV2.color(de: programado.definicion.tipo))
                }
                if programado.sesionVinculadaID != nil {
                    Text("Sesión guardada — vela en Carreras")
                        .font(.caption2)
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

}
