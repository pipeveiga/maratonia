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
    /// QUÉ arquetipo es. Viaja al `PlanUsuario` al adoptar para que el
    /// nombre del plan tampoco quede congelado en español. El catálogo
    /// V1 (JSON embebido) no la declara y cae a `TextosLegado`.
    var clave: ClavePlan? = nil
    private var nombreGuardado: String
    /// La descripción NO se persiste en el plan adoptado (PlanUsuario no
    /// la tiene), así que se puede guardar ya localizada: el contenido
    /// declarativo la pasa por `String(localized:)` y el JSON del
    /// catálogo V1 la resuelve al decodificar.
    var descripcion: String

    /// El nombre a MOSTRAR. `nombreCrudo` es el que viaja al snapshot:
    /// lo que se congela tiene que seguir siendo el español canónico,
    /// porque es la clave con la que `TextosLegado` lo rescata después.
    var nombre: String { clave?.nombre ?? TextosLegado.plan(nombreGuardado) }
    var nombreCrudo: String { nombreGuardado }
    var distanciaObjetivoKm: Double
    var semanasTotales: Int
    var diasPorSemana: Int
    /// Contenido provisional: valida infraestructura, NO es metodología
    /// deportiva definitiva (se muestra en la UI).
    var provisional: Bool
    var semanas: [SemanaBase]

    /// Identidad completa template+versión, guardada como procedencia.
    var planBaseID: String { "\(id)@\(version)" }

    enum CodingKeys: String, CodingKey {
        case id, version, clave, descripcion, distanciaObjetivoKm
        case semanasTotales, diasPorSemana, provisional, semanas
        case nombreGuardado = "nombre"   // el JSON del catálogo no cambia
    }

    init(id: String, version: Int, clave: ClavePlan? = nil, nombre: String,
         descripcion: String, distanciaObjetivoKm: Double, semanasTotales: Int,
         diasPorSemana: Int, provisional: Bool, semanas: [SemanaBase]) {
        self.id = id
        self.version = version
        self.clave = clave
        self.nombreGuardado = nombre
        self.descripcion = descripcion
        self.distanciaObjetivoKm = distanciaObjetivoKm
        self.semanasTotales = semanasTotales
        self.diasPorSemana = diasPorSemana
        self.provisional = provisional
        self.semanas = semanas
    }
}

struct SemanaBase: Codable, Equatable {
    var numero: Int
    var entrenamientos: [EntrenamientoBase]
    /// Fase del bloque a la que pertenece esta semana. Opcional: el
    /// catálogo JSON viejo decodifica igual y queda sin declarar
    /// (nunca se inventa una fase que el contenido no declaró).
    var fase: TipoSemana? = nil

    /// Las reglas que esta semana le impone a cualquier adaptación.
    /// Se DERIVAN del propio contenido — no son números sueltos: el
    /// objetivo es lo que la semana prescribe, y la banda es una
    /// tolerancia declarada alrededor de eso.
    var reglasDerivadas: ReglasSemana {
        // Mismo cálculo que el dominio: los bloques por tiempo cuentan.
        // Antes esta banda salía de sumar solo distancias declaradas, y
        // el validador terminaba comparando el volumen real contra un
        // mínimo calculado sobre un número que ignoraba las calidades.
        // Sesión por sesión, no todo junto: el TOPE de duración es por
        // sesión, así que aplanar los segmentos de la semana lo haría
        // desaparecer (una semana de 5 sesiones nunca superaría un tope
        // de 3 h aplicado a la suma).
        let km = entrenamientos.reduce(into: 0.0) { total, entrenamiento in
            total += CalculoVolumen.volumen(
                entrenamiento.segmentos.map {
                    CalculoVolumen.Entrada(distanciaKm: $0.distanciaKm,
                                           duracionSegundos: $0.duracionSegundos,
                                           ritmo: $0.ritmo)
                },
                tope: entrenamiento.topeDuracionSegundos).totalKm
        }
        let calidad = entrenamientos.filter {
            let rol = RolSesion.para($0.tipo)
            return rol == .calidadPrincipal || rol == .calidadSecundaria
        }.count
        return ReglasSemana(
            fase: fase,
            volumenObjetivoKm: km > 0 ? km : nil,
            volumenMinimoKm: km > 0 ? (km * ReglasSemana.toleranciaAbajo * 10).rounded() / 10 : nil,
            volumenMaximoKm: km > 0 ? (km * ReglasSemana.toleranciaArriba * 10).rounded() / 10 : nil,
            maximoCalidad: calidad)
    }
}

extension ReglasSemana {
    /// Cuánto se puede bajar el volumen de una semana adaptándola sin
    /// que deje de ser esa semana. DECISIÓN MARATONIA (METODOLOGIA.md):
    /// −25 % es una semana floja; por debajo ya es otra semana.
    static let toleranciaAbajo = 0.75
    /// Hacia arriba el margen es mucho más chico a propósito (§40):
    /// adaptar nunca es una excusa para subir carga.
    static let toleranciaArriba = 1.05
}

/// Un entrenamiento RELATIVO: "semana N, día D" (día 1 = fecha de
/// inicio de esa semana). La adopción lo traduce a DiaLocal concreto.
struct EntrenamientoBase: Codable, Equatable {
    var diaDeSemana: Int        // 1...7
    var tipo: TipoEntrenamiento
    /// QUÉ ES esta sesión. La declara el contenido declarativo y viaja
    /// hasta el snapshot al adoptar, que es lo que permite mostrarla en
    /// el idioma de cada momento. El catálogo V1 (JSON embebido) no la
    /// trae: ese contenido se resuelve por `TextosLegado`.
    var clave: ClaveEntrenamiento? = nil
    var nombre: String
    var descripcion: String
    var segmentos: [SegmentoBase]
    /// Techo de duración de la sesión (ver `DefinicionEntrenamiento`).
    /// Opcional: el catálogo JSON viejo decodifica igual y queda sin
    /// tope, exactamente como se comportaba antes.
    var topeDuracionSegundos: Int? = nil
}

/// Segmento del template, SIN identidad (los UUID nacen al adoptar).
struct SegmentoBase: Codable, Equatable {
    /// QUÉ ES este tramo (ver `EntrenamientoBase.clave`).
    var clave: ClaveSegmento? = nil
    var nombre: String
    var distanciaKm: Double?
    var duracionSegundos: Int?
    var ritmoMinSegKm: Int?
    var ritmoMaxSegKm: Int?
    /// Zona SIMBÓLICA (fácil/umbral/…): la resuelve la metodología
    /// activa contra el baseline al adoptar; sin baseline queda
    /// simbólica (se muestra "a personalizar", se ejecuta libre).
    /// Opcional: el catálogo viejo decodifica igual.
    var tipoRitmo: TipoRitmo? = nil
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
                    // El ROL y el CONTRATO de adaptación se congelan acá,
                    // al adoptar: así una sesión convertida a fácil no
                    // "recupera" su rol de calidad al releer el plan, y
                    // un cambio futuro en la tabla de roles no reescribe
                    // planes ya adoptados (siguen siendo snapshots).
                    let rol = RolSesion.para(entrenamiento.tipo)
                    return EntrenamientoProgramado(
                        definicion: DefinicionEntrenamiento(
                            tipo: entrenamiento.tipo,
                            // La CLAVE viaja al snapshot junto con el
                            // texto. El texto queda como respaldo (una
                            // build vieja leyendo este plan lo usa); la
                            // clave es la que hace que el título se
                            // pueda mostrar en otro idioma sin rehacer
                            // el plan.
                            clave: entrenamiento.clave,
                            nombre: entrenamiento.nombre,
                            descripcion: entrenamiento.descripcion,
                            segmentos: entrenamiento.segmentos.map { base in
                                Segmento(clave: base.clave,
                                         nombre: base.nombre,
                                         distanciaKm: base.distanciaKm,
                                         duracionSegundos: base.duracionSegundos,
                                         ritmo: base.ritmo)
                            },
                            topeDuracionSegundos: entrenamiento.topeDuracionSegundos),
                        dia: inicio.sumando(dias: desplazamiento, calendario: calendario),
                        rolGuardado: rol,
                        adaptabilidadGuardada: .para(rol))
                },
                reglas: semana.reglasDerivadas)
        }
        return PlanUsuario(clave: clave,
                           nombre: nombreCrudo,
                           origen: .catalogo(planBaseID: planBaseID),
                           fechaAdopcion: fechaAdopcion,
                           semanas: semanasUsuario)
    }
}

extension SegmentoBase {
    var ritmo: RitmoObjetivo {
        if let tipoRitmo { return .simbolico(tipoRitmo) }
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
            guard var plan = try? JSONDecoder().decode(PlanBase.self, from: Data($0.utf8))
            else { return nil }
            // El NOMBRE no se toca: viaja crudo al snapshot y se traduce
            // al mostrarlo. La descripción no se persiste, así que acá
            // ya queda en el idioma actual.
            plan.descripcion = TextosLegado.descripcionDePlan(plan.descripcion)
            return plan
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

    /// Lo recién corrido HOY, esperando el feedback subjetivo. nil =
    /// no hay nada que preguntar. La UI lo consume y lo limpia.
    @Published var sesionParaFeedback: AnalisisPostCarrera?

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
        // La preferencia de unidades del PERFIL manda sobre el caché del
        // dispositivo: es la que viaja con los datos del corredor y
        // sobrevive a reinstalar. Si el perfil no la tiene (usuario
        // anterior a este build), no se pisa nada y queda el default
        // determinístico por región — sin migración.
        PreferenciaUnidades.compartida.adoptarDelPerfil(almacen.perfilDeportivo.sistemaUnidades)
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
        // Las unidades viajan con la proyección: el reloj muestra y
        // habla en las mismas que el teléfono, sin preguntar aparte.
        proyeccion.sistemaUnidades = almacen.perfilDeportivo.sistemaUnidades
            ?? PreferenciaUnidades.compartida.sistema
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
        ofrecerFeedback(sesionID: sesion.hkUUID, fecha: sesion.fecha,
                        metros: sesion.metrosRecorridos, segundos: sesion.segundosTotales,
                        programadoID: programadoID,
                        estructuraCompleta: sesion.estructuraCompleta)
    }

    /// Arma el análisis determinístico de lo recién corrido y lo
    /// publica para que la UI ofrezca el feedback subjetivo. Solo para
    /// sesiones de HOY: un resultado del reloj que llega tres días
    /// tarde no puede abrir una pregunta sobre "cómo te sentiste".
    func ofrecerFeedback(sesionID: UUID, fecha: Date, metros: Double, segundos: Double,
                         programadoID: UUID?, estructuraCompleta: Bool,
                         hoy: Date = Date()) {
        guard DiaLocal(fecha: fecha) == DiaLocal(fecha: hoy), metros > 0 else { return }
        let programado = programadoID.flatMap { id in
            almacen.todosLosProgramados.first { $0.id == id }
        }
        sesionParaFeedback = AnalisisPostCarrera.desde(
            sesion: SesionMetrica(fecha: fecha, metros: metros, segundos: segundos),
            sesionID: sesionID,
            programado: programado,
            registro: almacen.sesiones.first { $0.id == sesionID },
            estructuraCompleta: estructuraCompleta,
            baseline: PerformanceBaseline(referencia: almacen.referenciaVigente))
    }

    // MARK: Cuenta (RC1)

    /// Asocia (o desasocia) el dominio deportivo a una cuenta. Es LA
    /// migración de usuario existente: sus datos pasan a pertenecer al
    /// userID sin duplicarse ni moverse; HealthKit no se toca.
    func asociarUsuario(_ usuarioID: UUID?) {
        guard almacen.usuarioID != usuarioID else { return }
        almacen.usuarioID = usuarioID
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

/// Explorar planes: los DIEZ objetivos del catálogo, siempre.
///
/// Antes esta pantalla listaba `Catalogo.planesDisponibles()` —los dos
/// planes provisionales de 5K y 10K embebidos como JSON— y por eso los
/// ocho arquetipos reales (incluidos TODOS los de 21K y 42K) eran
/// invisibles: el corredor abría "Explorar planes" y la app le decía
/// que solo existían 5K y 10K. No era un filtro de elegibilidad, era
/// que la pantalla leía la fuente vieja.
///
/// Regla de producto: **la elegibilidad describe, nunca esconde.** Un
/// objetivo para el que todavía falta base se muestra igual, con lo que
/// falta escrito al lado. Que un plan no sea para vos hoy es
/// información útil; que no exista es mentira.
struct CatalogoView: View {
    @ObservedObject var almacen: AlmacenStore

    @State private var filtroDistancia: Double?   // metros; nil = todas
    @State private var filtroDias: Int?           // nil = todos

    private static let distancias: [(nombre: String, metros: Double)] =
        [("5K", 5000), ("10K", 10000), ("21K", 21097.5), ("42K", 42195)]

    /// Qué se ve en la lista. Los ÚNICOS filtros son los que el
    /// corredor eligió (distancia y días). La elegibilidad NO filtra:
    /// si filtrara, un objetivo dejaría de existir para quien todavía
    /// no llega, que es exactamente el bug que esto arregla. Es
    /// `static` para que el test pueda comprobarlo sin montar la vista.
    static func visibles(distanciaMetros: Double?, dias: Int?,
                         biblioteca: [PlanArquetipo] = BibliotecaArquetipos.v1())
    -> [PlanArquetipo] {
        biblioteca.filter { arquetipo in
            guard let base = arquetipo.contenido else { return false }
            if let distanciaMetros,
               abs(base.distanciaObjetivoKm * 1000 - distanciaMetros) > 500 { return false }
            // El filtro de días acepta las frecuencias que el arquetipo
            // ADMITE: un plan de 4-5 días aparece tanto en "4 días" como
            // en "5 días". Acá filtrar es correcto —el corredor pidió
            // explícitamente "mostrame planes de N días"—, al revés de
            // la pantalla de disponibilidad, donde la pregunta es por su
            // semana y filtrar equivalía a no dejarlo responder.
            if let dias, !arquetipo.admite(dias: dias) { return false }
            return true
        }
    }

    private var filtrados: [PlanArquetipo] {
        Self.visibles(distanciaMetros: filtroDistancia, dias: filtroDias)
    }

    var body: some View {
        List {
            Section {
                // Solo distancia a la vista: es el filtro que el
                // corredor usa. Los días quedan detrás del menú — nueve
                // chips en fila eran más ruido que ayuda.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DV2.Espacio.s) {
                        chip("Todas", activo: filtroDistancia == nil) { filtroDistancia = nil }
                        ForEach(Self.distancias, id: \.metros) { distancia in
                            chip(distancia.nombre,
                                 activo: filtroDistancia == distancia.metros) {
                                filtroDistancia = distancia.metros
                            }
                        }
                        Menu {
                            Button {
                                filtroDias = nil
                            } label: {
                                Label("Cualquiera", systemImage: filtroDias == nil
                                      ? "checkmark" : "")
                            }
                            ForEach(DisponibilidadCorredor.opciones(), id: \.self) { dias in
                                Button {
                                    filtroDias = (filtroDias == dias) ? nil : dias
                                } label: {
                                    Label("\(dias) días por semana",
                                          systemImage: filtroDias == dias ? "checkmark" : "")
                                }
                            }
                        } label: {
                            chipEtiqueta(filtroDias.map { "\($0) días" }
                                         ?? String(localized: "Días"),
                                         activo: filtroDias != nil,
                                         icono: "line.3.horizontal.decrease")
                        }
                        .accessibilityLabel(String(localized: "Filtrar por días por semana"))
                    }
                }
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                .listRowBackground(Color.clear)
            }

            Section {
                if filtrados.isEmpty {
                    ContentUnavailableView {
                        Label("Nada con ese filtro", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Nada con esa combinación.")
                    }
                    .listRowBackground(Color.clear)
                }
                ForEach(filtrados) { arquetipo in
                    NavigationLink {
                        if let contenido = arquetipo.contenido {
                            PlanBaseDetalleView(almacen: almacen,
                                                arquetipo: arquetipo, base: contenido)
                        }
                    } label: {
                        filaArquetipo(arquetipo)
                    }
                }
            } footer: {
                if !filtrados.isEmpty {
                    Text("Están todos. Si a alguno le falta base, te decimos qué falta.")
                }
            }
        }
        .navigationTitle("Explorar planes")
    }

    /// Una tarjeta por plan: objetivo, duración, frecuencia, intención y
    /// cómo le queda a ESTE corredor. Todo de un vistazo, sin frases
    /// repetidas en cada fila.
    private func filaArquetipo(_ arquetipo: PlanArquetipo) -> some View {
        let semanas = arquetipo.contenido?.semanasTotales ?? arquetipo.semanasMinimas
        let dias = arquetipo.diasMinimos == arquetipo.diasMaximos
            ? "\(arquetipo.diasMinimos)"
            : "\(arquetipo.diasMinimos)-\(arquetipo.diasMaximos)"
        let estado = EstadoDeObjetivo(arquetipo: arquetipo,
                                      perfil: almacen.almacen.perfilDeportivo,
                                      tieneBaseline: almacen.almacen.referenciaVigente != nil)
        return VStack(alignment: .leading, spacing: DV2.Espacio.m) {
            HStack(alignment: .top, spacing: DV2.Espacio.m) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(arquetipo.nombre)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    if let intencion = Self.intencion(de: arquetipo.objetivo) {
                        Text(intencion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Text(Self.distanciaCorta(arquetipo.contenido?.distanciaObjetivoKm ?? 0))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(DV2.Marca.profundo)
                    .padding(.horizontal, DV2.Espacio.s)
                    .padding(.vertical, 3)
                    .background(DV2.Marca.primario.opacity(0.14), in: Capsule())
            }

            HStack(spacing: DV2.Espacio.l) {
                Label("\(semanas) sem", systemImage: "calendar")
                Label("\(dias) días", systemImage: "repeat")
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

            if let estado {
                HStack(spacing: DV2.Espacio.s) {
                    estado.chip
                    if let dias = estado.diasQueFaltan {
                        // Badge compacto, no una oración por fila.
                        Text("\(dias)d")
                            .font(.caption2.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, DV2.Espacio.s)
                            .padding(.vertical, 3)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                            .accessibilityLabel(
                                String(localized: "Pide \(dias) días por semana"))
                    }
                }
            }
        }
        .padding(.vertical, DV2.Espacio.xs)
    }

    static func distanciaCorta(_ km: Double) -> String {
        switch km {
        case ..<7: return "5K"
        case ..<15: return "10K"
        case ..<30: return "21K"
        default: return "42K"
        }
    }

    /// La intención del objetivo, que es lo que distingue dos planes de
    /// la misma distancia. Antes había que deducirla del nombre.
    static func intencion(de objetivo: ObjetivoDeportivo) -> String? {
        switch objetivo.intencion {
        case .completar: return String(localized: "Llegar por primera vez")
        case .mejorar: return String(localized: "Bajar tu marca")
        case .rendimiento: return String(localized: "Rendimiento")
        }
    }

    private func chip(_ texto: String, activo: Bool, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            chipEtiqueta(texto, activo: activo)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(activo ? .isSelected : [])
    }

    private func chipEtiqueta(_ texto: String, activo: Bool,
                              icono: String? = nil) -> some View {
        HStack(spacing: DV2.Espacio.xs) {
            if let icono {
                Image(systemName: icono).font(.caption2.weight(.bold))
            }
            Text(texto)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(activo ? Color.white : Color.primary)
        .padding(.horizontal, DV2.Espacio.m)
        .padding(.vertical, 6)
        .background(activo ? Color.accentColor : Color(.secondarySystemGroupedBackground),
                    in: Capsule())
    }
}

/// Cómo le queda HOY un objetivo al corredor, para mostrarlo al lado
/// del plan. Describe, no bloquea: ningún valor de este tipo esconde
/// un objetivo — solo cambia lo que dice.
struct EstadoDeObjetivo {
    enum Nivel { case listo, conservador, faltaBase }
    var nivel: Nivel
    var motivos: [MotivoElegibilidad]
    /// Días por semana que este objetivo pide y el corredor todavía no
    /// marcó. Va SEPARADO del nivel a propósito: que te falten días es
    /// un dato de agenda, no un veredicto deportivo, y no tiene por qué
    /// tapar lo otro. Antes este caso devolvía `nil` — o sea, el estado
    /// desaparecía y el corredor no se enteraba de por qué.
    var diasQueFaltan: Int?

    /// nil = el corredor no declaró nada todavía y no hay nada honesto
    /// que decir. En ese caso la fila no muestra estado — pero el
    /// objetivo sigue en la lista igual.
    init?(arquetipo: PlanArquetipo, perfil: PerfilDeportivo, tieneBaseline: Bool) {
        guard let contenido = arquetipo.contenido else { return nil }
        let actividad = perfil.actividad
        let diasDelCorredor = perfil.diasElegidos?.count ?? perfil.diasPorSemana
        guard actividad != nil || diasDelCorredor != nil else { return nil }

        let requisitos = RequisitosObjetivo.para(arquetipo.objetivo)
        if let diasDelCorredor, diasDelCorredor < requisitos.diasPorSemana {
            diasQueFaltan = requisitos.diasPorSemana
        }

        // Lo DEPORTIVO se juzga contra la variante más liviana que el
        // corredor podría recibir. Si marcó menos días de los que el
        // plan pide, igual queremos poder decirle cómo le queda el
        // volumen — no solo "te faltan días" y silencio sobre el resto.
        let dias = min(max(diasDelCorredor ?? arquetipo.diasMinimos, arquetipo.diasMinimos),
                       arquetipo.diasMaximos)
        let variante = MotorPlanificacion.recortar(
            arquetipo.contenido(para: dias) ?? contenido, aDias: dias)
        let veredicto = EvaluadorElegibilidad.evaluar(EntradaElegibilidad(
            objetivo: arquetipo.objetivo,
            semanasDisponibles: nil,
            semanasMinimasDelPlan: arquetipo.semanasMinimas,
            // Se pasa la frecuencia de la variante medida, no la del
            // corredor: el faltante de días ya quedó en `diasQueFaltan`
            // y acá solo se pregunta por lo deportivo.
            diasElegidos: dias,
            historial: nil,
            actividadDeclarada: actividad,
            tieneBaseline: tieneBaseline,
            molestias: perfil.molestias ?? .ninguna,
            mesesCorriendoRegular: actividad?.mesesCorriendoRegular,
            volviendoDePausa: actividad?.volviendoDePausa ?? false,
            kmSemana1DelPlan: variante.semanas.first.map {
                MotorPlanificacion.volumenSemanaBase($0)
            }))
        switch veredicto {
        case .elegible:
            nivel = .listo; motivos = []
        case .elegibleConservador(let m):
            nivel = .conservador; motivos = m
        case .requiereFaseBase(let m):
            nivel = .faltaBase; motivos = m
        case .fechaDemasiadoCerca, .frecuenciaInsuficiente:
            // No deberían salir con estas entradas (sin fecha, y con la
            // frecuencia de la variante). Si salieran, no se esconde el
            // objetivo: se informa lo que se sabe.
            nivel = .conservador; motivos = []
        }
    }

    /// Lo que hay que decir sobre los días, si falta algo.
    var textoDeDias: String? {
        guard let diasQueFaltan else { return nil }
        return String(localized: "Pide \(diasQueFaltan) días por semana")
    }

    var resumen: String {
        switch nivel {
        case .listo: return String(localized: "Listo para empezar")
        case .conservador: return String(localized: "Se puede, arrancando prudente")
        case .faltaBase: return String(localized: "Todavía no: falta base")
        }
    }

    var icono: String {
        switch nivel {
        case .listo: return "checkmark.circle"
        case .conservador: return "arrow.down.right.circle"
        case .faltaBase: return "figure.strengthtraining.functional"
        }
    }

    var color: Color {
        switch nivel {
        case .listo: return .green
        case .conservador: return DV2.Marca.primario
        case .faltaBase: return .orange
        }
    }
}

struct PlanBaseDetalleView: View {
    @ObservedObject var almacen: AlmacenStore
    let arquetipo: PlanArquetipo
    /// El contenido del arquetipo. La lista solo navega hasta acá con
    /// arquetipos que lo tienen, así que se pasa resuelto.
    let base: PlanBase
    @Environment(\.dismiss) private var dismiss
    @State private var resultado: ResultadoPlanificacion?
    @State private var mostrandoPropuesta = false
    /// Sin disponibilidad declarada no se arma nada: se la pide.
    @State private var mostrandoOnboarding = false

    private var estado: EstadoDeObjetivo? {
        EstadoDeObjetivo(arquetipo: arquetipo,
                         perfil: almacen.almacen.perfilDeportivo,
                         tieneBaseline: almacen.almacen.referenciaVigente != nil)
    }

    var body: some View {
        List {
            // Encabezado: qué es este plan, en tres números.
            Section {
                VStack(alignment: .leading, spacing: DV2.Espacio.l) {
                    HStack(spacing: DV2.Espacio.xl) {
                        Metrica(valor: CatalogoView.distanciaCorta(base.distanciaObjetivoKm),
                                etiqueta: String(localized: "Objetivo"),
                                color: DV2.Marca.profundo, alineacion: .center)
                        Metrica(valor: "\(base.semanasTotales)",
                                etiqueta: String(localized: "Semanas"), alineacion: .center)
                        Metrica(valor: arquetipo.diasMinimos == arquetipo.diasMaximos
                                ? "\(arquetipo.diasMinimos)"
                                : "\(arquetipo.diasMinimos)-\(arquetipo.diasMaximos)",
                                etiqueta: String(localized: "Días"), alineacion: .center)
                    }
                    if let estado {
                        estado.chip
                    }
                }
                .listRowInsets(EdgeInsets(top: DV2.Espacio.l, leading: DV2.Espacio.l,
                                          bottom: DV2.Espacio.l, trailing: DV2.Espacio.l))
            }

            // Vos contra el plan. Tres barras reemplazan las cinco filas
            // de requisitos más los dos párrafos que las explicaban.
            Section {
                let requisitos = RequisitosObjetivo.para(arquetipo.objetivo)
                let actividad = almacen.almacen.perfilDeportivo.actividad
                if requisitos.kmSemanales > 0 {
                    BarraComparativaDistancia(titulo: String(localized: "Volumen semanal"),
                                              tuyoKm: actividad?.kmSemanales ?? 0,
                                              pedidoKm: requisitos.kmSemanales)
                }
                if requisitos.tiradaLargaKm > 0 {
                    BarraComparativaDistancia(titulo: String(localized: "Tirada larga"),
                                              tuyoKm: actividad?.tiradaLargaKm ?? 0,
                                              pedidoKm: requisitos.tiradaLargaKm)
                }
                BarraComparativa(
                    titulo: String(localized: "Días por semana"),
                    tuyo: Double(almacen.almacen.perfilDeportivo.diasElegidos?.count
                                 ?? almacen.almacen.perfilDeportivo.diasPorSemana ?? 0),
                    pedido: Double(requisitos.diasPorSemana), unidad: "")
            } header: {
                Text("Tu punto de partida")
            }

            // Lo metodológico, detrás de un toque.
            Section {
                Detalle(titulo: String(localized: "Cómo funciona este plan")) {
                    VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                        Text(base.descripcion)
                            .font(.footnote)
                            .fixedSize(horizontal: false, vertical: true)
                        let requisitos = RequisitosObjetivo.para(arquetipo.objetivo)
                        if requisitos.mesesRegular > 0 {
                            Text("Conviene venir de al menos \(requisitos.mesesRegular) meses corriendo regular.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if requisitos.exigeBaseline {
                            Text("Necesita una referencia de ritmo real.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("Más días, un poco más de vara: el volumen sale de la semana 1 con tus días.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let estado, !estado.motivos.isEmpty || estado.diasQueFaltan != nil {
                    Detalle(titulo: String(localized: "Qué te falta")) {
                        VStack(alignment: .leading, spacing: DV2.Espacio.xs) {
                            ForEach(estado.motivos, id: \.self) { motivo in
                                Text(motivo.texto)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if let texto = estado.textoDeDias {
                                Text(texto)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            if estado.nivel == .faltaBase,
                               let puente = EvaluadorElegibilidad.objetivoPuente(
                                para: arquetipo.objetivo) {
                                Text("Un buen punto de partida es **\(TextosObjetivo.nombre(de: puente))**.")
                                    .font(.footnote)
                            }
                        }
                    }
                }
            }

            // Preparar pasa SIEMPRE por el motor: recorte a los días
            // del corredor, elegibilidad y atenuación del arranque. La
            // pantalla de propuesta ya sabe explicar cada resultado
            // —incluido "falta base"— así que desde acá no hace falta
            // (ni conviene) bloquear nada antes de tiempo.
            Section {
                // Sin días declarados el botón cambia de trabajo: pedir
                // el dato en vez de suponerlo. La promesa del pie —"lo
                // armamos con TUS días"— solo se puede cumplir así.
                if almacen.almacen.perfilDeportivo.disponibilidadDeclarada == nil {
                    Button {
                        mostrandoOnboarding = true
                    } label: {
                        Label("Decinos qué días podés correr",
                              systemImage: "calendar.badge.plus")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        prepararConElMotor()
                    } label: {
                        Label("Preparar mi plan", systemImage: "wand.and.stars")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } header: {
                Text("Arranque")
            } footer: {
                if almacen.almacen.perfilDeportivo.disponibilidadDeclarada == nil {
                    Text("Todavía no sabemos cuántos días por semana podés correr, y de eso depende todo el plan. Son dos toques.")
                } else {
                    Text(almacen.almacen.planActivo != nil
                         ? "Tenés un plan activo: si confirmás el nuevo, el actual queda archivado con su historial."
                         : "Vamos a armarlo con tus días, tu volumen actual y tu referencia de ritmo.")
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
        .navigationDestination(isPresented: $mostrandoPropuesta) {
            if let resultado {
                PropuestaPlanView(almacen: almacen, resultado: resultado) {
                    mostrandoPropuesta = false
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $mostrandoOnboarding) {
            // El botón prometía "son dos toques": abrir en el paso 1
            // obligaba a recorrer objetivo, actividad y experiencia para
            // contestar la única pregunta que se hizo.
            OnboardingDeportivo(almacen: almacen, desde: .disponibilidad)
        }
    }

    /// Arma el pedido con lo que el perfil ya sabe y deja que el motor
    /// decida. Nada de adoptar el template crudo: eso salteaba el
    /// recorte por días, la elegibilidad y la atenuación del arranque.
    ///
    /// Si el corredor todavía no dijo qué días puede correr, NO se
    /// supone: antes se usaba el mínimo del arquetipo y el plan salía
    /// calculado sobre una semana que nadie declaró.
    private func prepararConElMotor() {
        let perfil = almacen.almacen.perfilDeportivo
        guard let pedido = PedidoDePlan(perfil: perfil,
                                        objetivo: arquetipo.objetivo,
                                        referencia: almacen.almacen.referenciaVigente,
                                        hoy: DiaLocal(fecha: Date())) else {
            mostrandoOnboarding = true
            return
        }
        let salida = MotorPlanificacion.proponer(pedido)
        // Solo se registra lo pendiente si el corredor estaba mirando
        // SU objetivo: explorar otros planes no puede ensuciar el
        // estado del que eligió.
        if perfil.objetivo == arquetipo.objetivo {
            almacen.almacen.perfil?.objetivoSinPlan = salida.motivoSinPlan
        }
        resultado = salida
        mostrandoPropuesta = true
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

    /// Navegación PROGRAMÁTICA: siete NavigationLinks dentro de una
    /// misma fila de List se pisan entre sí (la fila entera dispara el
    /// primero); con Buttons + destino por estado cada círculo navega
    /// al día correcto.
    @State private var seleccionadoID: UUID?

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
        .navigationDestination(isPresented: Binding(
            get: { seleccionadoID != nil },
            set: { if !$0 { seleccionadoID = nil } })) {
            if let id = seleccionadoID {
                DetalleEntrenamientoView(almacen: almacen, store: store,
                                         pestana: $pestana, programadoID: id)
            }
        }
    }

    @ViewBuilder
    private func celda(_ item: DiaDeSemana) -> some View {
        if let programado = item.programado {
            Button {
                seleccionadoID = programado.id
            } label: {
                columna(item)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(etiquetaAccesible(item))
            .accessibilityAddTraits(.isButton)
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
            // El número del mes ancla la tira al calendario real: un
            // usuario nuevo entiende la semana sin leyenda.
            Text("\(item.dia.dia)")
                .font(.system(size: 9, weight: item.esHoy ? .bold : .regular))
                .monospacedDigit()
                .foregroundStyle(item.esHoy ? Color.accentColor : Color(.tertiaryLabel))
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

    /// Inicial del día desde el calendario del sistema, en el idioma de
    /// la app — sin arrays hardcodeados.
    private func letra(de dia: DiaLocal) -> String {
        guard let fecha = dia.fecha() else { return "" }
        var calendario = Calendar.current
        calendario.locale = FormatoFecha.locale
        let indice = calendario.component(.weekday, from: fecha) - 1
        return calendario.veryShortWeekdaySymbols[indice]
    }

    private func etiquetaAccesible(_ item: DiaDeSemana) -> String {
        let nombreDia = item.dia.fecha().map { FormatoFecha.diaDeSemana($0) } ?? ""
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
                        Text(FormatoFecha.larga(fecha))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let original = programado.diaOriginal, original != programado.dia,
                       let fechaOriginal = original.fecha() {
                        Text("Reprogramado (era el \(FormatoFecha.diaYMes(fechaOriginal)))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if !programado.definicion.descripcion.isEmpty {
                        Text(programado.definicion.descripcion)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: DV2.Espacio.xl) {
                        if let km = programado.definicion.distanciaPrescritaKm {
                            MetricaV2(titulo: "distancia",
                                      valor: Unidades.distancia(km: km))
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
                LabeledContent("Fecha", value: FormatoFecha.fechaYHora(sesion.fecha))
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
                    Text("Fecha original: \(FormatoFecha.corta(fechaOriginal))")
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

/// EL PLAN COMPLETO, desde el día 1.
///
/// Antes esto era una `List` con una `Section` por semana: dieciséis
/// secciones de texto que había que scrollear para ver el bloque. El
/// corredor no podía chusmear su plan — ver dónde están los fondos,
/// cuándo cae la descarga, cuánto dura el taper— sin leerlo entero.
///
/// Ahora es un navegador: una fila de semanas arriba, UNA semana a la
/// vez abajo. Nada se recalcula al abrirlo — se lee el SNAPSHOT del
/// plan tal como está hoy, con las adaptaciones ya aplicadas.
struct CalendarioView: View {
    @ObservedObject var almacen: AlmacenStore
    @ObservedObject var store: PlanStore
    @Binding var pestana: Pestana

    /// Qué semana se está mirando. Arranca en la actual.
    @State private var semanaElegida: Int?

    private var hoy: DiaLocal { DiaLocal(fecha: Date()) }

    var body: some View {
        Group {
            if let plan = almacen.almacen.planActivo, !plan.semanas.isEmpty {
                contenido(plan)
            } else {
                EstadoVacio(
                    icono: "calendar",
                    titulo: String(localized: "Todavía no hay plan"),
                    detalle: String(localized: "Cuando adoptes uno, acá vas a ver todas sus semanas: los fondos, las calidades, las descargas y el taper."))
                    .padding()
            }
        }
        .navigationTitle("Plan completo")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func contenido(_ plan: PlanUsuario) -> some View {
        let actual = numeroSemanaActual(plan) ?? plan.semanas.first?.numero ?? 1
        let elegida = semanaElegida ?? actual
        let semana = plan.semanas.first { $0.numero == elegida } ?? plan.semanas[0]
        return ScrollView {
            VStack(alignment: .leading, spacing: DV2.Espacio.l) {
                tiraDeSemanas(plan, actual: actual, elegida: elegida)
                resumen(semana, plan: plan, actual: actual)
                sesiones(semana)
            }
            .padding(.vertical)
        }
    }

    // MARK: La tira de semanas (el mapa del bloque en una línea)

    private func tiraDeSemanas(_ plan: PlanUsuario, actual: Int, elegida: Int) -> some View {
        ScrollViewReader { scroll in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DV2.Espacio.s) {
                    ForEach(plan.semanas) { semana in
                        chipSemana(semana, actual: actual, elegida: elegida)
                            .id(semana.numero)
                    }
                }
                .padding(.horizontal)
            }
            .onAppear { scroll.scrollTo(elegida, anchor: .center) }
        }
    }

    private func chipSemana(_ semana: SemanaPlan, actual: Int, elegida: Int) -> some View {
        let esElegida = semana.numero == elegida
        let pasada = semana.numero < actual
        let fase = semana.reglas?.fase
        return Button {
            semanaElegida = semana.numero
        } label: {
            VStack(spacing: 3) {
                Text("\(semana.numero)")
                    .font(DV2.Tipo.numero)
                // Un punto por fase: la descarga y el taper se ven de
                // un vistazo, que es justo lo que se viene a chusmear.
                Circle()
                    .fill(colorDeFase(fase))
                    .frame(width: 5, height: 5)
                    .opacity(fase == nil ? 0 : 1)
            }
            .frame(width: 44, height: 52)
            .background(esElegida ? AnyShapeStyle(DV2.gradienteMarca)
                                  : AnyShapeStyle(DV2.Superficie.tarjeta),
                        in: RoundedRectangle(cornerRadius: DV2.radioBoton, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: DV2.radioBoton, style: .continuous)
                .strokeBorder(semana.numero == actual && !esElegida
                              ? DV2.Marca.primario : Color.clear, lineWidth: 2))
            .foregroundStyle(esElegida ? Color.white : Color.primary)
            // Las semanas ya pasadas quedan secundarias: están, se
            // pueden mirar, pero no compiten con la que viene.
            .opacity(pasada && !esElegida ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Semana \(semana.numero)"))
        .accessibilityAddTraits(esElegida ? .isSelected : [])
    }

    private func colorDeFase(_ fase: TipoSemana?) -> Color {
        switch fase {
        case .descarga: return .green
        case .taper: return .yellow
        case .semanaDeCarrera: return .red
        case .pico: return .orange
        default: return DV2.Marca.primario.opacity(0.6)
        }
    }

    // MARK: Resumen de la semana elegida

    private func resumen(_ semana: SemanaPlan, plan: PlanUsuario, actual: Int) -> some View {
        let volumen = semana.volumenPlanificado(
            baseline: PerformanceBaseline(referencia: almacen.almacen.referenciaVigente))
        let calidades = semana.programados.filter {
            $0.rol == .calidadPrincipal || $0.rol == .calidadSecundaria
        }.count
        let larga = semana.programados
            .max { ($0.definicion.volumenKm()) < ($1.definicion.volumenKm()) }
        return TarjetaV2 {
            VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                HStack {
                    Text("Semana \(semana.numero) de \(plan.semanas.count)")
                        .font(DV2.Tipo.tituloChico)
                    Spacer()
                    if semana.numero == actual {
                        ChipEstado(texto: String(localized: "Actual"), tono: .prudente,
                                   icono: "location.fill", compacto: true)
                    } else if semana.numero < actual {
                        ChipEstado(texto: String(localized: "Pasada"), tono: .neutro,
                                   icono: "checkmark", compacto: true)
                    }
                }
                if let fase = semana.reglas?.fase {
                    Text(nombreDeFase(fase))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(colorDeFase(fase))
                        .tracking(0.8)
                        .textCase(.uppercase)
                }
                HStack(spacing: DV2.Espacio.xl) {
                    MetricaV2(titulo: "volumen",
                              valor: Unidades.distancia(km: volumen.totalKm, decimales: 0))
                    MetricaV2(titulo: "sesiones", valor: "\(semana.programados.count)")
                    if calidades > 0 {
                        MetricaV2(titulo: "calidad", valor: "\(calidades)")
                    }
                    if let larga, larga.definicion.volumenKm() > 0 {
                        MetricaV2(titulo: "larga",
                                  valor: Unidades.distancia(km: larga.definicion.volumenKm(),
                                                            decimales: 0))
                    }
                }
                if let proposito = semana.reglas?.propositoFase {
                    Text(proposito)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal)
    }

    private func nombreDeFase(_ fase: TipoSemana) -> String {
        switch fase {
        case .base: return String(localized: "Base")
        case .construccion, .carga: return String(localized: "Construcción")
        case .especifica: return String(localized: "Específica")
        case .pico: return String(localized: "Pico")
        case .descarga: return String(localized: "Descarga")
        case .taper: return String(localized: "Taper")
        case .semanaDeCarrera: return String(localized: "Semana de carrera")
        }
    }

    // MARK: Las sesiones de esa semana

    private func sesiones(_ semana: SemanaPlan) -> some View {
        VStack(spacing: DV2.Espacio.s) {
            ForEach(semana.programados.sorted { ($0.dia ?? hoy) < ($1.dia ?? hoy) }) { programado in
                NavigationLink {
                    DetalleEntrenamientoView(almacen: almacen, store: store,
                                             pestana: $pestana,
                                             programadoID: programado.id)
                } label: {
                    filaSesion(programado)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
    }

    private func filaSesion(_ programado: EntrenamientoProgramado) -> some View {
        let estado = programado.estado(hoy: hoy)
        let esHoy = programado.dia == hoy
        return TarjetaV2 {
            HStack(spacing: DV2.Espacio.m) {
                // Barra de color por tipo: el calendario se lee por
                // forma antes que por texto.
                RoundedRectangle(cornerRadius: 2)
                    .fill(DV2.color(de: programado.definicion.tipo))
                    .frame(width: 4)
                    .frame(maxHeight: .infinity)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: DV2.Espacio.s) {
                        if let dia = programado.dia, let fecha = dia.fecha() {
                            Text(FormatoFecha.diaCorto(fecha).uppercased())
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(esHoy ? DV2.Marca.primario : .secondary)
                        }
                        if esHoy {
                            Text("HOY")
                                .font(.caption2.weight(.heavy))
                                .foregroundStyle(DV2.Marca.primario)
                        }
                    }
                    Text(programado.definicion.nombre)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(programado.definicion.resumenEstructura)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: DV2.Espacio.s)
                insignia(estado)
            }
            .frame(minHeight: 44)
        }
        // Lo ya resuelto queda atrás; lo que viene, al frente.
        .opacity(estado == .cumplido || estado == .omitido ? 0.6 : 1)
    }

    @ViewBuilder
    private func insignia(_ estado: EstadoProgramado) -> some View {
        switch estado {
        case .cumplido:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .parcial:
            Image(systemName: "circle.bottomhalf.filled").foregroundStyle(.yellow)
        case .omitido:
            Image(systemName: "minus.circle.fill").foregroundStyle(.gray)
        case .vencido:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
        case .programado:
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
    }

    /// La semana cuyo rango [primer día programado, +6] contiene hoy.
    private func numeroSemanaActual(_ plan: PlanUsuario) -> Int? {
        plan.semanas.first { semana in
            guard let primero = semana.programados.compactMap(\.dia).min() else { return false }
            let fin = primero.sumando(dias: 6)
            return !(hoy < primero) && !(fin < hoy)
        }?.numero
    }
}
