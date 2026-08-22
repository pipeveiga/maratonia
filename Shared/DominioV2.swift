import Foundation

// Modelo de dominio V2 (Fase A de ARCHITECTURE_V2.md).
//
// Separación central: QUÉ HAY QUE HACER (PlanUsuario → SemanaPlan →
// EntrenamientoProgramado → DefinicionEntrenamiento) vs QUÉ SE HIZO
// (RegistroSesion, cuyo id es el HKWorkout.uuid de Salud).
//
// Identidad ≠ contenido: cada entidad tiene un UUID estable que NO
// cambia al editar contenido ni al mover fechas. La huellaEntrenamiento
// de V1 queda como puente de migración (ver MigracionV2) y muere en
// Fase E, cuando el reloj pase a la proyección del día.
//
// En Fase A este modelo todavía NO alimenta ninguna pantalla: la app
// sigue corriendo sobre el Plan legacy. Acá viven el esquema, las
// transiciones y la migración — la base de las Fases B en adelante.

// MARK: - Día local

/// Un día de calendario en la zona horaria del corredor. NUNCA usar
/// `Date` para "el martes": un Date es un instante UTC y el
/// entrenamiento del martes no debe volverse del lunes al cruzar un
/// huso horario (regla de NIGHT_AUDIT).
struct DiaLocal: Codable, Equatable, Hashable, Comparable {
    var anio: Int
    var mes: Int
    var dia: Int

    init(anio: Int, mes: Int, dia: Int) {
        self.anio = anio
        self.mes = mes
        self.dia = dia
    }

    init(fecha: Date, calendario: Calendar = .current) {
        let partes = calendario.dateComponents([.year, .month, .day], from: fecha)
        anio = partes.year ?? 1970
        mes = partes.month ?? 1
        dia = partes.day ?? 1
    }

    static func < (lhs: DiaLocal, rhs: DiaLocal) -> Bool {
        (lhs.anio, lhs.mes, lhs.dia) < (rhs.anio, rhs.mes, rhs.dia)
    }

    /// El instante "medianoche local" de este día (para formateo y
    /// aritmética). nil solo ante componentes absurdos.
    func fecha(calendario: Calendar = .current) -> Date? {
        calendario.date(from: DateComponents(year: anio, month: mes, day: dia))
    }

    /// El día de la semana en forma CANÓNICA e independiente del idioma
    /// ("monday"… "sunday").
    ///
    /// Existe para que el contexto del Coach lleve fechas inequívocas.
    /// Una fecha ISO suelta ("2026-08-15") no le dice a un modelo qué
    /// día de la semana es, y sin eso no puede resolver "este sábado" —
    /// que fue exactamente el bug: el Coach decía que no había sesión el
    /// sábado teniendo una programada.
    ///
    /// Canónico y no localizado a propósito: es un identificador para
    /// máquinas, no texto para el corredor.
    var diaDeSemanaCanonico: String {
        let nombres = ["monday", "tuesday", "wednesday", "thursday",
                       "friday", "saturday", "sunday"]
        return nombres[max(0, min(6, numeroDeDiaDeSemana - 1))]
    }

    /// 1 = lunes … 7 = domingo (la convención de `EntrenamientoBase`).
    var numeroDeDiaDeSemana: Int {
        var calendario = Calendar(identifier: .gregorian)
        calendario.timeZone = .current
        guard let fecha = fecha(calendario: calendario) else { return 1 }
        // `weekday` de Foundation es 1 = domingo; el dominio usa 1 = lunes.
        let domingoPrimero = calendario.component(.weekday, from: fecha)
        return ((domingoPrimero + 5) % 7) + 1
    }

    /// El LUNES de la semana de este día (semana deportiva L-D, sin
    /// depender del firstWeekday del locale).
    func lunesDeLaSemana(calendario: Calendar = .current) -> DiaLocal {
        guard let fecha = fecha(calendario: calendario) else { return self }
        let diaDeSemana = calendario.component(.weekday, from: fecha)  // 1 = domingo
        let atras = (diaDeSemana + 5) % 7
        return sumando(dias: -atras, calendario: calendario)
    }

    /// Aritmética de calendario real (meses de 28-31 días, años
    /// bisiestos): siempre vía Calendar, jamás sumando a mano.
    func sumando(dias: Int, calendario: Calendar = .current) -> DiaLocal {
        guard let base = fecha(calendario: calendario),
              let nueva = calendario.date(byAdding: .day, value: dias, to: base) else {
            return self
        }
        return DiaLocal(fecha: nueva, calendario: calendario)
    }
}

// MARK: - Definición (QUÉ es el entrenamiento)

enum TipoEntrenamiento: String, Codable {
    case facil, recuperacion, largo, tempo, umbral, series, ritmoCarrera
    case testEvaluacion
    case personalizado   // planes armados a mano / migrados de V1
}

/// Ritmo objetivo de un segmento. `.simbolico` se resuelve contra el
/// baseline con una metodología versionada (Fase G); hasta entonces los
/// planes usan `.absoluto` (compatible con los tramos de hoy).
enum RitmoObjetivo: Codable, Equatable {
    case libre
    case absoluto(minSegKm: Int?, maxSegKm: Int?)
    case simbolico(TipoRitmo)
}

enum TipoRitmo: String, Codable {
    case facil, recuperacion, maraton, umbral, intervalo, repeticion
}

/// Un segmento del entrenamiento: por distancia O por duración (la
/// ejecución por duración es extensión de motor de Fase D; el MODELO ya
/// la representa para no re-migrar esquema).
struct Segmento: Codable, Equatable, Identifiable {
    var id = UUID()
    /// QUÉ ES este tramo. Cuando está, manda sobre el texto guardado y
    /// el nombre se arma en el idioma actual (ver `TextosDeportivos`).
    var clave: ClaveSegmento? = nil
    /// El texto tal cual quedó escrito en el plan. Es el RESPALDO, no la
    /// fuente de verdad: sirve para los planes adoptados antes de que
    /// existieran las claves y para los tramos que se armó el corredor.
    private var nombreGuardado: String
    var distanciaKm: Double?
    var duracionSegundos: Int?
    var ritmo: RitmoObjetivo = .libre

    /// El nombre a MOSTRAR, siempre en el idioma de ahora.
    var nombre: String {
        get { clave?.nombre ?? TextosLegado.segmento(nombreGuardado) }
        set { nombreGuardado = newValue; clave = nil }
    }

    /// Lo que hay escrito en el disco, sin traducir. Solo lo necesita la
    /// persistencia y los tests de compatibilidad.
    var nombreCrudo: String { nombreGuardado }

    enum CodingKeys: String, CodingKey {
        case id, clave, distanciaKm, duracionSegundos, ritmo
        case nombreGuardado = "nombre"   // el JSON no cambia de forma
    }

    init(id: UUID = UUID(), clave: ClaveSegmento? = nil, nombre: String,
         distanciaKm: Double? = nil, duracionSegundos: Int? = nil,
         ritmo: RitmoObjetivo = .libre) {
        self.id = id
        self.clave = clave
        self.nombreGuardado = nombre
        self.distanciaKm = distanciaKm
        self.duracionSegundos = duracionSegundos
        self.ritmo = ritmo
    }

    /// Una clave DESCONOCIDA (guardada por una build futura) no puede
    /// tirar el almacén entero: se ignora y queda el texto guardado.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        clave = try? c.decodeIfPresent(ClaveSegmento.self, forKey: .clave)
        nombreGuardado = try c.decode(String.self, forKey: .nombreGuardado)
        distanciaKm = try c.decodeIfPresent(Double.self, forKey: .distanciaKm)
        duracionSegundos = try c.decodeIfPresent(Int.self, forKey: .duracionSegundos)
        ritmo = try c.decodeIfPresent(RitmoObjetivo.self, forKey: .ritmo) ?? .libre
    }
}

struct DefinicionEntrenamiento: Codable, Equatable, Identifiable {
    var id = UUID()                      // definicionID: estable ante ediciones
    var tipo: TipoEntrenamiento
    /// QUÉ ES esta sesión. Cuando está, de acá salen título y
    /// descripción, en el idioma actual (ver `TextosDeportivos`).
    var clave: ClaveEntrenamiento? = nil
    /// El texto congelado al adoptar. RESPALDO: planes viejos, contenido
    /// provisional del catálogo V1 y entrenamientos del corredor.
    private var nombreGuardado: String
    private var descripcionGuardada: String = ""
    var segmentos: [Segmento] = []

    /// Título y descripción a MOSTRAR, siempre en el idioma de ahora.
    var nombre: String {
        get { clave?.nombre ?? TextosLegado.entrenamiento(nombreGuardado) }
        set { nombreGuardado = newValue; clave = nil }
    }

    var descripcion: String {
        get { clave?.descripcion ?? TextosLegado.descripcion(descripcionGuardada) }
        set { descripcionGuardada = newValue; clave = nil }
    }

    /// Lo que hay escrito en el disco, sin traducir.
    var nombreCrudo: String { nombreGuardado }
    var descripcionCruda: String { descripcionGuardada }

    /// TECHO de duración de la sesión, en segundos. No es una meta: es
    /// un límite. La sesión sigue terminando por DISTANCIA cuando el
    /// corredor llega a los kilómetros antes del tope; el tope solo
    /// recorta cuando, al ritmo previsto, esos kilómetros no entran.
    ///
    /// Existe porque la distancia sola no describe la carga: 30 km son
    /// 2:45 para quien corre 5 km en 20:00 y 4:30 para quien los corre
    /// en 33:00. Ver METODOLOGIA.md §"Tope de duración del fondo".
    ///
    /// Opcional: nil = sin tope (todo el contenido anterior decodifica
    /// igual y se comporta exactamente como antes).
    var topeDuracionSegundos: Int? = nil

    enum CodingKeys: String, CodingKey {
        case id, tipo, clave, segmentos, topeDuracionSegundos
        case nombreGuardado = "nombre"            // el JSON no cambia de forma
        case descripcionGuardada = "descripcion"
    }

    init(id: UUID = UUID(), tipo: TipoEntrenamiento, clave: ClaveEntrenamiento? = nil,
         nombre: String, descripcion: String = "", segmentos: [Segmento] = [],
         topeDuracionSegundos: Int? = nil) {
        self.id = id
        self.tipo = tipo
        self.clave = clave
        self.nombreGuardado = nombre
        self.descripcionGuardada = descripcion
        self.segmentos = segmentos
        self.topeDuracionSegundos = topeDuracionSegundos
    }

    /// Una clave DESCONOCIDA (guardada por una build futura) no puede
    /// tirar el almacén entero: se ignora y quedan los textos guardados.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        tipo = try c.decode(TipoEntrenamiento.self, forKey: .tipo)
        clave = try? c.decodeIfPresent(ClaveEntrenamiento.self, forKey: .clave)
        nombreGuardado = try c.decode(String.self, forKey: .nombreGuardado)
        descripcionGuardada = try c.decodeIfPresent(String.self, forKey: .descripcionGuardada) ?? ""
        segmentos = try c.decodeIfPresent([Segmento].self, forKey: .segmentos) ?? []
        topeDuracionSegundos = try c.decodeIfPresent(Int.self, forKey: .topeDuracionSegundos)
    }
}

// MARK: - Volumen planificado (UNA sola definición)

/// El volumen de una sesión o de una semana, con su procedencia a la
/// vista. Existe porque `distanciaTotalKm` contaba SOLO los segmentos
/// medidos en distancia: un `umbral(32′)` son 1,5 km de entrada + 32
/// minutos + 1 km de salida, y el motor lo contabilizaba como 2,5 km.
/// Los 32 minutos —más de 5 km reales— desaparecían del volumen
/// semanal, del arranque conservador, de las bandas del validador, del
/// detector y de Progreso.
///
/// Regla: los segmentos por DISTANCIA se suman tal cual; los segmentos
/// por TIEMPO se convierten a distancia equivalente con el ritmo de su
/// propia zona. Nunca se cuenta un segmento dos veces — cada uno cae en
/// exactamente una de las dos ramas (distancia tiene prioridad, igual
/// que en `tramosEjecutables`).
struct VolumenPlanificado: Equatable {
    /// Suma de los segmentos que declaran distancia.
    var kmMedidos: Double = 0
    /// Suma de los segmentos medidos en tiempo.
    var segundosPorTiempo: Int = 0
    /// Esos segundos convertidos a distancia.
    var kmEquivalentes: Double = 0
    /// true = al menos una conversión usó el ritmo de REFERENCIA porque
    /// el ritmo real no se pudo resolver. El número sigue siendo mucho
    /// mejor que cero, pero no es exacto y quien lo muestre debería
    /// poder decirlo.
    var hayEstimacion: Bool = false
    /// true = el tope de duración recortó kilómetros. El número de
    /// abajo ya viene recortado: es lo que se va a correr de verdad,
    /// no lo que declaraba el catálogo.
    var recortadoPorTope: Bool = false

    var totalKm: Double { kmMedidos + kmEquivalentes }
    var esVacio: Bool { kmMedidos == 0 && segundosPorTiempo == 0 }

    static func + (a: VolumenPlanificado, b: VolumenPlanificado) -> VolumenPlanificado {
        VolumenPlanificado(kmMedidos: a.kmMedidos + b.kmMedidos,
                           segundosPorTiempo: a.segundosPorTiempo + b.segundosPorTiempo,
                           kmEquivalentes: a.kmEquivalentes + b.kmEquivalentes,
                           hayEstimacion: a.hayEstimacion || b.hayEstimacion,
                           recortadoPorTope: a.recortadoPorTope || b.recortadoPorTope)
    }
}

/// Ritmos de último recurso para convertir tiempo en distancia cuando
/// el corredor todavía no tiene baseline.
///
/// HEURÍSTICA PROVISIONAL (ver METODOLOGIA.md). No son prescripción:
/// **nunca se le muestran al corredor ni se usan como objetivo de
/// ejecución** — sirven solo para contabilizar volumen. Y no son
/// números inventados: salen de correr `MetodologiaMaratoniaV1` sobre
/// un corredor de referencia declarado (5 km en 30:00, un tiempo
/// recreativo mediano), así que comparten metodología con todo lo demás.
enum RitmoDeReferencia {

    /// El corredor de referencia. Fecha fija: esto tiene que ser
    /// determinístico entre ejecuciones.
    static let referencia = ReferenciaRendimiento(
        fecha: Date(timeIntervalSince1970: 0), fuente: .estimacionInicial,
        distanciaMetros: 5000, segundos: 1800)

    static var baseline: PerformanceBaseline? { PerformanceBaseline(referencia: referencia) }

    /// Ritmo medio de una zona, en seg/km. Si la metodología no puede
    /// resolverla (no debería ocurrir con este baseline), cae al ritmo
    /// fácil de referencia antes que devolver nada.
    static func segKm(_ tipo: TipoRitmo) -> Int {
        if let baseline, case .resuelto(let rango, _) = Metodologias.resolver(tipo, baseline: baseline) {
            return (rango.minSegKm + rango.maxSegKm) / 2
        }
        return 480   // 8:00/km — el fácil del corredor de referencia, redondeado
    }
}

/// El cálculo de volumen, en UN solo lugar. Todo el resto de la app
/// —Progreso, validador, arranque conservador, detector, DTO del
/// Coach— pasa por acá.
enum CalculoVolumen {

    /// Un segmento reducido a lo que el cálculo necesita. Permite que
    /// `Segmento` (dominio) y `SegmentoBase` (catálogo) compartan
    /// exactamente la misma semántica sin duplicar lógica.
    struct Entrada {
        var distanciaKm: Double?
        var duracionSegundos: Int?
        var ritmo: RitmoObjetivo
    }

    /// Cuánto hay que escalar los segmentos POR DISTANCIA para que la
    /// sesión entre en su tope de duración. 1.0 = el tope no muerde
    /// (o no hay tope), y entonces todo se comporta como antes.
    ///
    /// Los bloques por TIEMPO no se tocan: un umbral de 20′ dura 20′
    /// para cualquiera. Lo que se recorta es la distancia, que es lo
    /// único cuya duración depende del ritmo de quien corre.
    static func factorDeTope(_ segmentos: [Entrada],
                             tope: Int?,
                             baseline: PerformanceBaseline? = nil) -> Double {
        guard let tope, tope > 0 else { return 1 }
        var fijo = 0.0          // segundos que no dependen del ritmo
        var variable = 0.0      // segundos que sí
        for segmento in segmentos {
            if let km = segmento.distanciaKm {
                variable += km * Double(ritmo(de: segmento.ritmo, baseline: baseline).segKm)
            } else if let segundos = segmento.duracionSegundos, segundos > 0 {
                fijo += Double(segundos)
            }
        }
        guard fijo + variable > Double(tope), variable > 0 else { return 1 }
        return max(0, (Double(tope) - fijo) / variable)
    }

    static func volumen(_ segmentos: [Entrada],
                        tope: Int? = nil,
                        baseline: PerformanceBaseline? = nil) -> VolumenPlanificado {
        var v = VolumenPlanificado()
        let factor = factorDeTope(segmentos, tope: tope, baseline: baseline)
        for segmento in segmentos {
            // DISTANCIA manda si el segmento trae las dos metas: es la
            // misma regla que usa el motor para ejecutar (tramosEjecutables),
            // y es lo que garantiza que nada se cuente dos veces.
            if let km = segmento.distanciaKm {
                v.kmMedidos += km * factor
                if factor < 1 { v.recortadoPorTope = true }
                continue
            }
            guard let segundos = segmento.duracionSegundos, segundos > 0 else { continue }
            v.segundosPorTiempo += segundos
            let (segKm, estimado) = ritmo(de: segmento.ritmo, baseline: baseline)
            v.kmEquivalentes += Double(segundos) / Double(segKm)
            if estimado { v.hayEstimacion = true }
        }
        return v
    }

    /// Seg/km con el que convertir un segmento, y si hubo que estimar.
    /// Orden: ritmo ya resuelto → metodología contra el baseline real →
    /// ritmo de referencia.
    static func ritmo(de objetivo: RitmoObjetivo,
                      baseline: PerformanceBaseline?) -> (segKm: Int, estimado: Bool) {
        switch objetivo {
        case .absoluto(let rapido, let lento):
            if let rapido, let lento { return ((rapido + lento) / 2, false) }
            if let rapido { return (rapido, false) }
            if let lento { return (lento, false) }
            return (RitmoDeReferencia.segKm(.facil), true)
        case .simbolico(let tipo):
            if let baseline,
               case .resuelto(let rango, _) = Metodologias.resolver(tipo, baseline: baseline) {
                return ((rango.minSegKm + rango.maxSegKm) / 2, false)
            }
            return (RitmoDeReferencia.segKm(tipo), true)
        case .libre:
            // Sin zona declarada no hay nada mejor que el fácil de
            // referencia. Devolver 0 km sería esconder el problema.
            return (RitmoDeReferencia.segKm(.facil), true)
        }
    }
}

extension DefinicionEntrenamiento {

    /// EL volumen de esta sesión. Pasar el baseline del corredor cuando
    /// exista: sin él la conversión usa el ritmo de referencia y marca
    /// `hayEstimacion`.
    func volumen(baseline: PerformanceBaseline? = nil) -> VolumenPlanificado {
        CalculoVolumen.volumen(entradasDeVolumen,
                               tope: topeDuracionSegundos, baseline: baseline)
    }

    /// Los segmentos reducidos a lo que el cálculo necesita. Un solo
    /// lugar: volumen, tope y tramos ejecutables leen exactamente lo
    /// mismo.
    var entradasDeVolumen: [CalculoVolumen.Entrada] {
        segmentos.map {
            CalculoVolumen.Entrada(distanciaKm: $0.distanciaKm,
                                   duracionSegundos: $0.duracionSegundos,
                                   ritmo: $0.ritmo)
        }
    }

    /// Cuánto se recorta la distancia para entrar en el tope (1 = nada).
    func factorDeTope(baseline: PerformanceBaseline? = nil) -> Double {
        CalculoVolumen.factorDeTope(entradasDeVolumen,
                                    tope: topeDuracionSegundos, baseline: baseline)
    }

    /// Volumen total en km, contando los bloques por tiempo. Es lo que
    /// hay que usar para CONTABILIDAD (semana, progreso, validador).
    func volumenKm(baseline: PerformanceBaseline? = nil) -> Double {
        volumen(baseline: baseline).totalKm
    }

    /// Distancia DECLARADA en segmentos por distancia. Sirve para saber
    /// si la sesión tiene algo que escalar (reducir) — NO para
    /// contabilidad. Para eso está `volumenKm`.
    var distanciaTotalKm: Double? {
        let kms = segmentos.compactMap(\.distanciaKm)
        guard !kms.isEmpty else { return nil }
        return kms.reduce(0, +)
    }

    /// La distancia que se le MUESTRA al corredor y que va a correr: la
    /// declarada, ya recortada por el tope de duración. Es la que tiene
    /// que aparecer en tarjetas y detalles — prometer 30 km cuando el
    /// tope va a cortar en 23 es mentirle al que entrena.
    var distanciaPrescritaKm: Double? {
        guard let declarada = distanciaTotalKm else { return nil }
        return (declarada * factorDeTope() * 10).rounded() / 10
    }

    /// Duración total prevista de los segmentos POR TIEMPO (nil si no
    /// hay ninguno). No estima tiempo de los segmentos por distancia.
    var duracionPorTiempoSegundos: Int? {
        let duraciones = segmentos.filter { $0.distanciaKm == nil }.compactMap(\.duracionSegundos)
        guard !duraciones.isEmpty else { return nil }
        return duraciones.reduce(0, +)
    }

    /// "8 km · 1 segmento" / "6 km + 12 min · 5 segmentos" para tarjetas.
    var resumenEstructura: String {
        var medidas: [String] = []
        if let declarada = distanciaTotalKm {
            // Lo que se muestra es lo que se va a correr: si el tope
            // recorta, la tarjeta no puede seguir prometiendo 30 km.
            let km = (declarada * factorDeTope() * 10).rounded() / 10
            medidas.append(Unidades.distancia(km: km))
        }
        if let segundos = duracionPorTiempoSegundos {
            medidas.append(duracionTexto(segundos))
        }
        var partes: [String] = []
        if !medidas.isEmpty { partes.append(medidas.joined(separator: " + ")) }
        partes.append(segmentos.count == 1
                      ? String(localized: "1 segmento")
                      : String(localized: "\(segmentos.count) segmentos"))
        return partes.joined(separator: " · ")
    }

    /// Puente al motor: cada segmento se vuelve un Tramo ejecutable.
    /// DISTANCIA tiene prioridad si un segmento trae las dos metas; un
    /// segmento sin ninguna meta no es ejecutable y se descarta.
    var tramosEjecutables: [Tramo] {
        // El tope se resuelve acá con el ritmo que el propio segmento
        // ya declara: al adoptar, el motor deja los ritmos en
        // `.absoluto`, así que no hace falta baseline y el reloj recibe
        // los kilómetros que de verdad va a correr. Sin ritmo resuelto
        // cae al corredor de referencia — la misma regla que el
        // volumen, no una segunda semántica.
        let factor = factorDeTope()
        return segmentos.compactMap { segmento in
            let minimo: Int?
            let maximo: Int?
            switch segmento.ritmo {
            case .libre, .simbolico:
                // Simbólico se resuelve recién en Fase G: hasta entonces
                // se ejecuta libre (nunca inventar números).
                (minimo, maximo) = (nil, nil)
            case .absoluto(let rapido, let lento):
                (minimo, maximo) = (rapido, lento)
            }
            if let km = segmento.distanciaKm {
                let recortado = (km * factor * 10).rounded() / 10
                guard recortado > 0 else { return nil }
                return Tramo(nombre: segmento.nombre, kilometros: recortado,
                             ritmoMinSegKm: minimo, ritmoMaxSegKm: maximo)
            }
            if let segundos = segmento.duracionSegundos, segundos > 0 {
                return Tramo(nombre: segmento.nombre, kilometros: 0,
                             ritmoMinSegKm: minimo, ritmoMaxSegKm: maximo,
                             duracionSegundos: segundos)
            }
            return nil
        }
    }
}

// MARK: - Metadata de sesión en HealthKit

/// El programadoID viaja también como metadata del HKWorkout: si el
/// almacén local se pierde, Salud conserva la evidencia de qué
/// entrenamiento produjo cada sesión. Es respaldo, no fuente diaria:
/// el iPhone sigue siendo el dueño del calendario.
enum MetadatosSesion {
    static let claveProgramadoID = "com.pipeveiga.maraton.programadoID"

    static func metadata(programadoID: UUID) -> [String: Any] {
        [claveProgramadoID: programadoID.uuidString]
    }

    static func programadoID(en metadata: [String: Any]?) -> UUID? {
        guard let crudo = metadata?[claveProgramadoID] as? String else { return nil }
        return UUID(uuidString: crudo)
    }
}

// MARK: - Rol, fase y adaptabilidad (estructura, no metodología)

/// El rol de una sesión dentro de la semana, en orden de PRIORIDAD
/// (menor rawValue = más importante). Es lo que permite recortar o
/// adaptar una semana sin destruir lo que la sostiene: primero se
/// sacrifica una recuperación, jamás la carrera objetivo.
///
/// Vive acá (y no en el motor) porque se persiste dentro del plan y
/// porque el Watch compila este archivo.
enum RolSesion: Int, Codable, Comparable, CaseIterable {
    case carrera = 0            // el día objetivo: nunca se recorta
    case tiradaLarga = 1
    case calidadPrincipal = 2
    case facil = 3
    case recuperacion = 4
    case calidadSecundaria = 5

    static func < (a: RolSesion, b: RolSesion) -> Bool { a.rawValue < b.rawValue }

    /// Tabla ESTRUCTURAL fija: qué rol cumple cada tipo de sesión. No
    /// es metodología deportiva — es cómo se ordenan las prioridades.
    static func para(_ tipo: TipoEntrenamiento) -> RolSesion {
        switch tipo {
        case .ritmoCarrera: return .carrera
        case .largo: return .tiradaLarga
        case .tempo, .umbral, .series, .testEvaluacion: return .calidadPrincipal
        case .recuperacion: return .recuperacion
        case .facil, .personalizado: return .facil
        }
    }
}

/// Fase del bloque de entrenamiento al que pertenece una semana. Cada
/// una declara su PROPÓSITO — el corredor tiene que poder leer por qué
/// esta semana es como es.
enum TipoSemana: String, Codable, CaseIterable {
    case base               // construir el hábito y el volumen fácil
    case construccion       // subir carga con calidad introductoria
    case especifica         // trabajo al ritmo de la carrera objetivo
    case pico               // la semana de mayor carga del bloque
    case descarga           // bajar volumen para asimilar
    case taper              // afinar antes de competir
    case semanaDeCarrera    // la carrera cae acá
    /// Compatibilidad: los arquetipos v1 usaban `carga` como genérico.
    case carga

    /// Semanas en las que la carga SOLO puede bajar. El validador las
    /// trata como zona protegida: acá no se agrega trabajo, no se sube
    /// intensidad y no se reorganiza la recuperación.
    var esProtegida: Bool { self == .taper || self == .semanaDeCarrera }

    /// ¿Es una semana de construcción? (las que auditan proporción).
    var esDeConstruccion: Bool { !esProtegida }
}

/// Qué se le puede hacer a una sesión sin traicionar su intención.
/// La adaptación (del motor o del coach) SOLO puede hacer lo que acá
/// está permitido — es el contrato que impide que una propuesta de IA
/// convierta una tirada larga en un trote de 3 km.
struct Adaptabilidad: Codable, Equatable {
    var sePuedeMover: Bool = true
    var sePuedeReducir: Bool = true
    var sePuedeConvertirEnFacil: Bool = true
    var sePuedeOmitir: Bool = true
    /// Piso de la reducción: 0.7 = no se puede bajar de un 70 % de lo
    /// prescrito. Reducir por debajo de esto no es adaptar, es otra
    /// sesión distinta (y entonces corresponde `replace`).
    var factorMinimo: Double = 0.7
    /// Días de recuperación que esta sesión necesita ANTES de otra
    /// sesión exigente. 0 = ninguno.
    var recuperacionMinimaDias: Int = 0

    /// Contrato por defecto según el rol. Estructural y conservador:
    /// la carrera objetivo es intocable; la larga se mueve y se acorta
    /// pero no se convierte; las calidades se convierten a fácil.
    static func para(_ rol: RolSesion) -> Adaptabilidad {
        switch rol {
        case .carrera:
            return Adaptabilidad(sePuedeMover: false, sePuedeReducir: false,
                                 sePuedeConvertirEnFacil: false, sePuedeOmitir: false,
                                 factorMinimo: 1, recuperacionMinimaDias: 0)
        case .tiradaLarga:
            return Adaptabilidad(sePuedeMover: true, sePuedeReducir: true,
                                 sePuedeConvertirEnFacil: false, sePuedeOmitir: true,
                                 factorMinimo: 0.6, recuperacionMinimaDias: 1)
        case .calidadPrincipal:
            return Adaptabilidad(sePuedeMover: true, sePuedeReducir: true,
                                 sePuedeConvertirEnFacil: true, sePuedeOmitir: true,
                                 factorMinimo: 0.6, recuperacionMinimaDias: 1)
        case .calidadSecundaria:
            return Adaptabilidad(sePuedeMover: true, sePuedeReducir: true,
                                 sePuedeConvertirEnFacil: true, sePuedeOmitir: true,
                                 factorMinimo: 0.5, recuperacionMinimaDias: 1)
        case .facil:
            return Adaptabilidad(sePuedeMover: true, sePuedeReducir: true,
                                 sePuedeConvertirEnFacil: true, sePuedeOmitir: true,
                                 factorMinimo: 0.5, recuperacionMinimaDias: 0)
        case .recuperacion:
            return Adaptabilidad(sePuedeMover: true, sePuedeReducir: true,
                                 sePuedeConvertirEnFacil: true, sePuedeOmitir: true,
                                 factorMinimo: 0.4, recuperacionMinimaDias: 0)
        }
    }
}

/// Reglas de una semana del plan: el marco dentro del cual una
/// adaptación sigue siendo válida. Sin esto, "reducir" no tiene techo
/// ni piso y cualquier propuesta parece razonable.
struct ReglasSemana: Codable, Equatable {
    var fase: TipoSemana? = nil
    var volumenObjetivoKm: Double? = nil
    /// Rango aceptable de volumen semanal (km). Fuera de esto el
    /// validador rechaza — NO existe una regla universal de +10 %.
    var volumenMinimoKm: Double? = nil
    var volumenMaximoKm: Double? = nil
    /// Cuántas sesiones de calidad tolera la semana.
    var maximoCalidad: Int? = nil

    /// Propósito legible de la fase, para que el corredor entienda
    /// POR QUÉ la semana es así. nil = fase sin declarar.
    var propositoFase: String? {
        switch fase {
        case .base: return String(localized: "Construir el hábito y el volumen cómodo.")
        case .construccion: return String(localized: "Subir la carga de a poco, con calidad introductoria.")
        case .especifica: return String(localized: "Trabajo específico al ritmo de tu carrera.")
        case .pico: return String(localized: "La semana más exigente del bloque.")
        case .descarga: return String(localized: "Bajar el volumen para asimilar lo hecho.")
        case .taper: return String(localized: "Afinar: menos volumen, la intensidad se mantiene.")
        case .semanaDeCarrera: return String(localized: "Tu carrera. Todo lo demás acompaña.")
        case .carga: return String(localized: "Semana de carga.")
        case nil: return nil
        }
    }
}

// MARK: - Programado (CUÁNDO hay que hacerlo)

/// Resolución PERSISTIDA de un programado. "Vencido" (overdue) NO se
/// persiste: se deriva de la fecha — así el paso del tiempo jamás muta
/// datos en silencio (decisión D3).
enum ResolucionProgramado: String, Codable {
    case pendiente
    case cumplido    // estructura completa + sesión vinculada
    case parcial     // sesión vinculada que no completó la estructura (D1)
    case omitido     // resuelto explícitamente como "no lo hice"
}

/// Estado DERIVADO para UI y lógica: pendiente se abre en programado /
/// vencido según la fecha. Reprogramar NO es un estado (decisión sobre
/// `rescheduled`): es mover `dia` conservando `diaOriginal` — la
/// historia queda y no hay estados contradictorios.
enum EstadoProgramado: Equatable {
    case programado
    case vencido      // pendiente con fecha pasada, sin resolver
    case cumplido
    case parcial
    case omitido
}

struct EntrenamientoProgramado: Codable, Equatable, Identifiable {
    var id = UUID()                       // programadoID: estable ante TODO
    var definicion: DefinicionEntrenamiento
    var dia: DiaLocal?                    // nil = sin fecha (migrado de V1)
    var diaOriginal: DiaLocal?            // primera fecha si fue reprogramado
    var resolucion: ResolucionProgramado = .pendiente
    var sesionVinculadaID: UUID?          // HKWorkout.uuid de la evidencia

    // ---- Motor adaptativo (opcionales: los planes ya adoptados
    // decodifican igual y siguen funcionando con los defaults).

    /// Prioridad de esta sesión dentro de su semana. nil = derivar del
    /// tipo con `RolSesion.para(_:)`.
    var rolGuardado: RolSesion? = nil
    /// Qué se le puede hacer sin traicionar su intención. nil =
    /// derivar del rol.
    var adaptabilidadGuardada: Adaptabilidad? = nil
    /// La PRESCRIPCIÓN ORIGINAL, congelada al adoptar el plan. Se
    /// escribe UNA sola vez, la primera vez que la sesión se adapta:
    /// así "plan original vs plan actual" es siempre respondible y
    /// adaptar no destruye historia (§45).
    var definicionOriginal: DefinicionEntrenamiento? = nil

    var rol: RolSesion { rolGuardado ?? RolSesion.para(definicion.tipo) }
    var adaptabilidad: Adaptabilidad { adaptabilidadGuardada ?? .para(rol) }

    /// ¿Esta sesión fue modificada respecto de lo planificado?
    var fueAdaptada: Bool {
        definicionOriginal != nil || (diaOriginal != nil && diaOriginal != dia)
    }

    /// Lo que se planificó originalmente (o lo actual, si nunca cambió).
    var prescripcionOriginal: DefinicionEntrenamiento { definicionOriginal ?? definicion }

    /// Congela la prescripción original antes de la PRIMERA
    /// modificación. Idempotente: llamarla de nuevo no pisa el
    /// original con una versión ya adaptada.
    mutating func congelarOriginalSiHaceFalta() {
        if definicionOriginal == nil { definicionOriginal = definicion }
    }

    func estado(hoy: DiaLocal) -> EstadoProgramado {
        switch resolucion {
        case .cumplido: return .cumplido
        case .parcial: return .parcial
        case .omitido: return .omitido
        case .pendiente:
            if let dia, dia < hoy { return .vencido }
            return .programado
        }
    }

    /// Mover de fecha conserva la identidad y la primera fecha original.
    mutating func reprogramar(a nuevoDia: DiaLocal) {
        if diaOriginal == nil { diaOriginal = dia }
        dia = nuevoDia
    }

    /// Omitir solo tiene sentido sobre algo sin resolver.
    mutating func omitir() {
        guard resolucion == .pendiente else { return }
        resolucion = .omitido
    }
}

// MARK: - Plan del usuario (snapshot adoptado)

enum OrigenPlan: Codable, Equatable {
    case personalizado                      // armado a mano / migrado de V1
    case catalogo(planBaseID: String)       // "primeros-5k@2": template + versión
}

/// La INSTANCIA del usuario: snapshot completo al adoptar. Actualizar
/// un template del catálogo jamás toca un PlanUsuario existente
/// (son structs copiados por valor y persistidos aparte).
struct PlanUsuario: Codable, Equatable, Identifiable {
    var id = UUID()                       // planUsuarioID
    /// QUÉ arquetipo es. Cuando está, el nombre sale de acá en el idioma
    /// actual; si no, del texto guardado (planes viejos o del corredor).
    var clave: ClavePlan? = nil
    private var nombreGuardado: String
    var origen: OrigenPlan = .personalizado
    var fechaAdopcion: Date
    var semanas: [SemanaPlan] = []

    /// El nombre a MOSTRAR, siempre en el idioma de ahora.
    var nombre: String {
        get { clave?.nombre ?? TextosLegado.plan(nombreGuardado) }
        set { nombreGuardado = newValue; clave = nil }
    }

    /// Lo que hay escrito en el disco, sin traducir.
    var nombreCrudo: String { nombreGuardado }

    /// Le pone identidad al plan: la clave (que es lo que se muestra) y
    /// el español canónico (que es lo que se congela). Existe porque
    /// `nombre = ...` a secas BORRA la clave a propósito —esa vía es
    /// para el nombre que escribe el corredor—, y el motor necesita
    /// poner las dos cosas juntas.
    mutating func identificar(clave: ClavePlan?, nombreCanonico: String) {
        nombreGuardado = nombreCanonico
        self.clave = clave
    }

    /// Con qué referencia de rendimiento se armó este plan (RC1,
    /// motor de planes). Opcional y retrocompatible: los planes
    /// anteriores no la tienen. La versión del arquetipo/metodología
    /// ya viaja en `origen` ("id@versión").
    var referenciaUsadaID: UUID? = nil

    enum CodingKeys: String, CodingKey {
        case id, clave, origen, fechaAdopcion, semanas, referenciaUsadaID
        case nombreGuardado = "nombre"   // el JSON no cambia de forma
    }

    init(id: UUID = UUID(), clave: ClavePlan? = nil, nombre: String,
         origen: OrigenPlan = .personalizado, fechaAdopcion: Date,
         semanas: [SemanaPlan] = [], referenciaUsadaID: UUID? = nil) {
        self.id = id
        self.clave = clave
        self.nombreGuardado = nombre
        self.origen = origen
        self.fechaAdopcion = fechaAdopcion
        self.semanas = semanas
        self.referenciaUsadaID = referenciaUsadaID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        clave = try? c.decodeIfPresent(ClavePlan.self, forKey: .clave)
        nombreGuardado = try c.decode(String.self, forKey: .nombreGuardado)
        origen = try c.decodeIfPresent(OrigenPlan.self, forKey: .origen) ?? .personalizado
        fechaAdopcion = try c.decode(Date.self, forKey: .fechaAdopcion)
        semanas = try c.decodeIfPresent([SemanaPlan].self, forKey: .semanas) ?? []
        referenciaUsadaID = try c.decodeIfPresent(UUID.self, forKey: .referenciaUsadaID)
    }
}

extension AlmacenV2 {
    /// El entrenamiento del plan que ESTA carrera cumplió, si alguno.
    /// `sesionVinculadaID` guarda el `HKWorkout.uuid`, así que una
    /// carrera de Salud puede encontrar su sesión sin inventar
    /// heurísticas por fecha.
    func programadoDeSesion(_ hkUUID: UUID) -> EntrenamientoProgramado? {
        for semana in planActivo?.semanas ?? [] {
            for programado in semana.programados
            where programado.sesionVinculadaID == hkUUID {
                return programado
            }
        }
        return nil
    }
}

extension PlanUsuario {
    /// En qué semana del plan cae `hoy`, si cae en alguna. Vivía dentro
    /// de una vista (el subtítulo del calendario) y lo necesitan al
    /// menos dos pantallas: acá arriba es un dato del plan, no una
    /// decisión de presentación.
    ///
    /// Una semana empieza el día del primer entrenamiento programado y
    /// dura siete días: los planes se distribuyen sobre los días que el
    /// corredor eligió, así que el lunes del calendario no sirve.
    func numeroDeSemana(hoy: DiaLocal) -> Int? {
        semanas.first { semana in
            guard let primero = semana.programados.compactMap(\.dia).min() else { return false }
            return !(hoy < primero) && !(primero.sumando(dias: 6) < hoy)
        }?.numero
    }
}

struct SemanaPlan: Codable, Equatable, Identifiable {
    var id = UUID()
    var numero: Int
    var programados: [EntrenamientoProgramado] = []
    /// Marco de la semana (fase, volumen objetivo y rango, tope de
    /// calidad). Opcional: los planes ya adoptados no lo tienen y el
    /// validador entonces solo aplica las reglas que no dependen de él.
    var reglas: ReglasSemana? = nil

    /// EL volumen prescrito de la semana, contando los bloques por
    /// tiempo (ver `CalculoVolumen`).
    func volumenPlanificado(baseline: PerformanceBaseline? = nil) -> VolumenPlanificado {
        programados.reduce(VolumenPlanificado()) { $0 + $1.definicion.volumen(baseline: baseline) }
    }

    /// Km prescritos de la semana. Antes sumaba solo distancias
    /// declaradas y perdía todos los bloques de calidad medidos en
    /// tiempo; ahora pasa por el cálculo único.
    func kmPrescritos(baseline: PerformanceBaseline? = nil) -> Double {
        volumenPlanificado(baseline: baseline).totalKm
    }

    /// Cuántas sesiones de calidad (principal o secundaria) tiene.
    var sesionesDeCalidad: Int {
        programados.filter { $0.rol == .calidadPrincipal || $0.rol == .calidadSecundaria }.count
    }
}

// MARK: - Sesión realizada (QUÉ se hizo)

/// Registro liviano: las métricas, la ruta y la FC viven en Salud
/// (HKWorkout es la fuente autoritativa de lo realizado). Acá solo el
/// vínculo. `id` ES el HKWorkout.uuid. Una sesión con vínculo nil es
/// Carrera Libre; el campo único garantiza por construcción que una
/// sesión se vincula a lo sumo a UN programado.
struct RegistroSesion: Codable, Equatable, Identifiable {
    var id: UUID                          // = HKWorkout.uuid
    var fecha: Date
    var vinculoProgramadoID: UUID?

    /// Cómo dijo el corredor que se sintió. SIEMPRE opcional: la
    /// pregunta es de un toque y se puede ignorar (§33).
    var sensacion: SensacionEsfuerzo? = nil
    /// Declaró una molestia en esta sesión. Bandera, no diagnóstico.
    var conMolestia: Bool? = nil

    var esLibre: Bool { vinculoProgramadoID == nil }
}

/// Esfuerzo percibido, en cuatro opciones que cualquiera entiende sin
/// explicación. Es el único dato subjetivo que la app pide.
enum SensacionEsfuerzo: String, Codable, CaseIterable {
    case muyBien, bien, exigido, muyExigido

    /// ¿Amerita mirar la semana? Solo el extremo alto — "muy bien" es
    /// una buena noticia, no un motivo para subir carga (§40).
    var pideAtencion: Bool { self == .muyExigido }

    var texto: String {
        switch self {
        case .muyBien: return String(localized: "Muy bien")
        case .bien: return String(localized: "Bien")
        case .exigido: return String(localized: "Exigido")
        case .muyExigido: return String(localized: "Muy exigido")
        }
    }
}

// MARK: - Historial de adaptaciones (§44)

/// Qué le pasó a una sesión y por qué. NO guarda razonamiento del
/// modelo (chain-of-thought): solo el hecho, el antes, el después y un
/// motivo corto que el corredor pueda leer.
struct RegistroAdaptacion: Codable, Equatable, Identifiable {
    enum Origen: String, Codable { case motor, coach, usuario }
    enum Tipo: String, Codable { case mover, reducir, convertir, omitir }

    var id = UUID()
    var fecha: Date
    var programadoID: UUID
    var tipo: Tipo
    var origen: Origen
    /// Descripción corta del estado previo ("8 km umbral · mar 12").
    var antes: String
    var despues: String
    /// Motivo en una frase, en el idioma del corredor.
    var motivo: String
}

// MARK: - Configuración de audio (separada del entrenamiento)

/// El audio deja de ser parte del "workout": es configuración de la
/// sesión (decisión 11). Los avisos por KM viven acá y no en la
/// definición — son recordatorios del corredor ("gel en el km 5") que
/// también valen en una Carrera Libre; los TRAMOS sí son entrenamiento.
/// (Refinamiento sobre §11 del documento, anotado ahí.)
struct ConfiguracionAudio: Codable, Equatable {
    var pistas: [String] = []
    var avisosFijos: [AvisoFijo] = []
    var avisosRepetidos: [AvisoRepetido] = []
    var avisosKm: [AvisoKm] = []
}

// MARK: - Perfil deportivo (Fase F: onboarding)

/// La distancia de la carrera objetivo. El corredor elige DISTANCIA e
/// INTENCIÓN por separado (dos preguntas cortas) y de ahí sale el
/// objetivo — mucho mejor que diez tarjetas gigantes en una lista.
enum DistanciaObjetivo: String, Codable, CaseIterable {
    case cinco, diez, media, maraton

    var metros: Double {
        switch self {
        case .cinco: return 5000
        case .diez: return 10000
        case .media: return 21097.5
        case .maraton: return 42195
        }
    }

    /// Las intenciones que tienen sentido para esta distancia. Un 5K
    /// "de rendimiento" no es una categoría distinta de "mejorar";
    /// media y maratón sí (el salto de carga es real).
    var intencionesPosibles: [IntencionObjetivo] {
        switch self {
        case .cinco, .diez: return [.completar, .mejorar]
        case .media, .maraton: return [.completar, .mejorar, .rendimiento]
        }
    }
}

/// Qué quiere hacer con esa distancia.
enum IntencionObjetivo: String, Codable, CaseIterable {
    case completar      // primera vez / terminarla
    case mejorar        // ya la corre, quiere bajar la marca
    case rendimiento    // buscar el techo (exige base real)
}

/// La meta que el corredor eligió. Enum cerrado a propósito: el motor y
/// el coach razonan sobre esto.
///
/// Los cinco casos originales conservan su rawValue EXACTO: los
/// perfiles ya guardados en `dominio-v2.json` siguen decodificando sin
/// migración. Los cinco nuevos se suman al final.
enum ObjetivoDeportivo: String, Codable, CaseIterable {
    case primeros5K, mejorar5K
    case diez                       // primeros 10K (rawValue histórico)
    case mejorar10K
    case mediaMaraton               // primera media (rawValue histórico)
    case mejorarMedia, mediaRendimiento
    case maraton                    // primera maratón (rawValue histórico)
    case mejorarMaraton, maratonRendimiento

    var distancia: DistanciaObjetivo {
        switch self {
        case .primeros5K, .mejorar5K: return .cinco
        case .diez, .mejorar10K: return .diez
        case .mediaMaraton, .mejorarMedia, .mediaRendimiento: return .media
        case .maraton, .mejorarMaraton, .maratonRendimiento: return .maraton
        }
    }

    var intencion: IntencionObjetivo {
        switch self {
        case .primeros5K, .diez, .mediaMaraton, .maraton: return .completar
        case .mejorar5K, .mejorar10K, .mejorarMedia, .mejorarMaraton: return .mejorar
        case .mediaRendimiento, .maratonRendimiento: return .rendimiento
        }
    }

    /// La combinación inversa (lo que arma el onboarding en dos pasos).
    /// nil = combinación inexistente (5K rendimiento).
    static func combinando(_ distancia: DistanciaObjetivo,
                           _ intencion: IntencionObjetivo) -> ObjetivoDeportivo? {
        allCases.first { $0.distancia == distancia && $0.intencion == intencion }
    }
}

/// Lo que el onboarding recolecta. TODO opcional: el perfil incompleto
/// es un estado normal (usuario viejo, onboarding salteado) y ninguna
/// pantalla debe romperse por un campo vacío. Las MARCAS no viven acá:
/// son ReferenciaRendimiento (datos crudos, con fecha y fuente).
struct PerfilDeportivo: Codable, Equatable {
    var objetivo: ObjetivoDeportivo?
    var diasPorSemana: Int?
    /// Días CONCRETOS de la semana en que puede correr (1 = lunes …
    /// 7 = domingo, la misma convención que EntrenamientoBase
    /// .diaDeSemana). Opcional: perfiles anteriores no lo tienen y el
    /// motor cae a la distribución del template.
    var diasElegidos: [Int]? = nil
    var fechaObjetivo: DiaLocal?
    /// Cuándo completó el onboarding (nil = nunca lo hizo).
    var fechaOnboarding: Date?
    /// Eligió "hacer el test de 5K" y todavía no lo corrió.
    var testPendiente: Bool = false

    // ---- Motor adaptativo. TODO opcional y con default: un
    // dominio-v2.json de cualquier build anterior decodifica igual.

    /// Contexto biométrico. NO produce carga por sí solo (§2): el
    /// rendimiento real y el historial pesan mucho más.
    var datosBasicos: DatosBasicos? = nil
    /// Lo que el corredor viene haciendo HOY. Es el input más
    /// importante para elegibilidad y punto de partida.
    var actividad: ActividadActual? = nil
    /// Declaración conservadora de molestias. Jamás diagnóstico.
    var molestias: EstadoMolestias? = nil
    /// Preferencias de la semana (día de fondo, día imposible).
    var preferencias: PreferenciasSemana? = nil

    /// Sistema de unidades ELEGIDO por el corredor. nil = todavía no
    /// eligió, y entonces manda el default por región
    /// (`SistemaUnidades.segunRegion`). Opcional a propósito: los
    /// perfiles anteriores decodifican igual y reciben ese default sin
    /// migración ni escritura. NO afecta al dominio ni al motor — solo
    /// a cómo se presenta (ver `Shared/Unidades.swift`).
    var sistemaUnidades: SistemaUnidades? = nil

    /// Por qué el objetivo elegido TODAVÍA NO tiene plan.
    ///
    /// Existe porque `objetivo` guardaba dos cosas distintas bajo el
    /// mismo campo: lo que el corredor QUIERE y lo que efectivamente
    /// está entrenando. El onboarding guardaba el perfil antes de
    /// consultar al motor, así que elegir "Maratón" para dentro de 5
    /// semanas —que el motor rechaza— dejaba igual el objetivo puesto
    /// y la app mostraba "Faltan 5 semanas para tu carrera" sin ningún
    /// plan detrás. La intención se conserva (es información real y
    /// útil); lo que no se puede es presentarla como si fuera un plan.
    ///
    /// nil = no hay nada pendiente: o hay plan activo, o el corredor
    /// todavía no intentó armarlo.
    var objetivoSinPlan: MotivoSinPlan? = nil

    /// Cuántos días por semana DIJO que puede correr. Una sola regla
    /// para toda la app: mandan los días concretos si los marcó.
    ///
    /// **nil significa que no lo dijo**, y eso no se puede reemplazar
    /// por un número plausible: armar el plan sobre una disponibilidad
    /// inventada es exactamente la misma mentira que filtrarle las
    /// opciones (ver `DisponibilidadCorredor`). Quien la necesite y no
    /// la tenga, la pide.
    var disponibilidadDeclarada: Int? {
        if let dias = diasElegidos, !dias.isEmpty { return dias.count }
        return diasPorSemana
    }
}

/// Por qué un objetivo elegido no llegó a convertirse en plan. Es el
/// resultado del motor, guardado para que la app pueda explicarlo
/// después —no solo en el momento— y ofrecer la salida concreta.
enum MotivoSinPlan: String, Codable, Equatable, CaseIterable {
    /// La fecha no da para las semanas mínimas del plan.
    case fechaDemasiadoCerca
    /// Eligió menos días de los que el objetivo necesita.
    case diasInsuficientes
    /// Falta base deportiva para sostener el objetivo.
    case faltaBase
    /// El arquetipo recomienda una referencia de ritmo y no hay.
    case faltaReferencia
    /// El objetivo existe pero su contenido todavía no está validado.
    case sinContenido

    /// Qué se puede hacer al respecto. Ordenado: primero lo que más
    /// probablemente resuelve el caso.
    var accionesSugeridas: [AccionSinPlan] {
        switch self {
        // La fase base va PRIMERA: es lo único que se puede hacer hoy
        // mismo. Cambiar la fecha sigue siendo la vía para volver
        // viable el objetivo original, y por eso queda inmediatamente
        // después.
        case .fechaDemasiadoCerca:
            return [.empezarFaseBase, .cambiarFecha, .cambiarObjetivo]
        // Las TRES palancas, en orden de utilidad. La fecha va última
        // pero va: cambiar de objetivo cambia las semanas mínimas, así
        // que quien viene de acá suele tener que revisarla también.
        case .diasInsuficientes:
            return [.ajustarDisponibilidad, .cambiarObjetivo, .cambiarFecha]
        case .faltaBase: return [.objetivoPuente, .cambiarObjetivo]
        case .faltaReferencia: return [.hacerTest, .cambiarObjetivo]
        case .sinContenido: return [.cambiarObjetivo]
        }
    }
}

enum AccionSinPlan: String, Codable, Equatable {
    case cambiarFecha
    case cambiarObjetivo
    case ajustarDisponibilidad
    case objetivoPuente
    case hacerTest
    /// Empezar a entrenar YA con el puente que el dominio define,
    /// sin apuntar a la fecha que no entraba. No reemplaza al objetivo
    /// deseado: convive con él (ver `FaseBase`).
    case empezarFaseBase
}

// MARK: - Perfil del corredor: contexto, actividad, molestias

enum Sexo: String, Codable, CaseIterable {
    case femenino, masculino, otro, prefiereNoDecir
}

/// Datos biométricos. TODOS opcionales — la app funciona entera sin
/// ninguno. Se guarda la FECHA de nacimiento y no la edad: una edad
/// guardada envejece mal (queda congelada y miente al año siguiente).
struct DatosBasicos: Codable, Equatable {
    var fechaNacimiento: DiaLocal? = nil
    var sexo: Sexo? = nil
    var alturaCm: Double? = nil
    var pesoKg: Double? = nil

    /// Edad en años cumplidos a una fecha dada. nil sin fecha de
    /// nacimiento o ante datos absurdos.
    func edad(a hoy: DiaLocal, calendario: Calendar = .current) -> Int? {
        guard let nacimiento = fechaNacimiento,
              let desde = nacimiento.fecha(calendario: calendario),
              let hasta = hoy.fecha(calendario: calendario),
              let anios = calendario.dateComponents([.year], from: desde, to: hasta).year,
              (5...110).contains(anios) else { return nil }
        return anios
    }
}

/// Otros deportes que el corredor practica. Cambian el contexto de
/// recuperación, NO la prescripción de carrera.
enum OtroDeporte: String, Codable, CaseIterable {
    case fuerza, ciclismo, natacion, futbol, otroEquipo, otro
}

/// Cuánto y cómo viene corriendo AHORA. Cuantificable a propósito
/// (§3): nada de "sedentario / activo", que no sirve para decidir nada.
/// Todo opcional: un perfil a medio llenar es un estado válido.
struct ActividadActual: Codable, Equatable {
    /// De dónde salió: lo declaró el corredor o lo calculamos de Salud.
    enum Origen: String, Codable { case declarado, detectadoSalud, confirmado, corregido }

    var origen: Origen = .declarado
    var fecha: Date? = nil

    var diasPorSemana: Double? = nil        // salidas por semana (promedio)
    var kmSemanales: Double? = nil
    var minutosSemanales: Double? = nil
    var tiradaLargaKm: Double? = nil
    /// Hace cuántos meses corre de forma regular (nil = no lo dijo).
    var mesesCorriendoRegular: Int? = nil
    /// Volviendo después de una pausa larga: cambia el punto de partida
    /// aunque el historial viejo sea bueno.
    var volviendoDePausa: Bool? = nil
    var otrosDeportes: [OtroDeporte]? = nil

    var estaVacia: Bool {
        diasPorSemana == nil && kmSemanales == nil
            && minutosSemanales == nil && tiradaLargaKm == nil
    }
}

/// Declaración de molestias. Escala CONSERVADORA y no clínica: la app
/// no diagnostica, no trata y no nombra patologías. Lo único que hace
/// con esto es proponer un enfoque más prudente.
enum EstadoMolestias: String, Codable, CaseIterable {
    case ninguna
    case molestiaLeve          // molesta pero puede correr
    case lesionReciente        // dejó de correr por eso
    case enRecuperacion        // volviendo bajo indicación externa

    /// ¿Obliga al motor a la variante conservadora?
    var exigeCautela: Bool { self != .ninguna }
    /// ¿Bloquea directamente los objetivos de rendimiento?
    var bloqueaRendimiento: Bool {
        self == .lesionReciente || self == .enRecuperacion
    }
}

/// Preferencias de forma de la semana. Sin esto, el motor NO fuerza
/// domingo como día de fondo (§9): usa el último día disponible.
struct PreferenciasSemana: Codable, Equatable {
    /// 1 = lunes … 7 = domingo. nil = sin preferencia.
    var diaPreferidoFondo: Int? = nil
    /// Días en que NUNCA puede entrenar (además de los no elegidos).
    var diasImposibles: [Int]? = nil
}

// MARK: - Referencia de rendimiento (baseline, se llena en Fase F)

enum FuenteReferencia: String, Codable {
    case test5K, carreraReal, marcaManual, estimacionInicial
}

/// Datos OBJETIVOS siempre (distancia+tiempo+fuente+fecha), nunca
/// "nivel = intermedio". Un VDOT es derivable y recalculable (D4).
struct ReferenciaRendimiento: Codable, Equatable, Identifiable {
    var id = UUID()
    var fecha: Date
    var fuente: FuenteReferencia
    var distanciaMetros: Double
    var segundos: Int
}

/// Un día de la vista semanal: el día calendario, si es hoy, y el
/// programado que lo ocupa (nil = descanso).
struct DiaDeSemana: Identifiable, Equatable {
    var dia: DiaLocal
    var esHoy: Bool
    var programado: EntrenamientoProgramado?

    var id: DiaLocal { dia }
}

// MARK: - Baseline y metodologías de ritmo (Fase G — INFRAESTRUCTURA)

/// La foto de rendimiento que consumen las metodologías: derivada de la
/// referencia vigente, con TODO su linaje (fecha, fuente). No se
/// persiste: es recalculable siempre desde ReferenciaRendimiento.
struct PerformanceBaseline: Equatable {
    var referenciaID: UUID
    var fecha: Date
    var fuente: FuenteReferencia
    var distanciaMetros: Double
    var segundos: Int

    init?(referencia: ReferenciaRendimiento?) {
        guard let referencia, referencia.distanciaMetros > 0, referencia.segundos > 0
        else { return nil }
        referenciaID = referencia.id
        fecha = referencia.fecha
        fuente = referencia.fuente
        distanciaMetros = referencia.distanciaMetros
        segundos = referencia.segundos
    }

    /// Ritmo promedio de la referencia, en seg/km.
    var ritmoSegKm: Int {
        Int((Double(segundos) / (distanciaMetros / 1000)).rounded())
    }
}

/// Rango de ritmo concreto (seg/km): lo que una metodología produce.
struct RangoRitmo: Equatable {
    var minSegKm: Int   // límite rápido
    var maxSegKm: Int   // límite lento
}

/// Cómo quedó un ritmo simbólico al intentar resolverlo. La UI DEBE
/// saber mostrar `.pendiente` con dignidad ("se personaliza con tu
/// referencia") — un ritmo sin resolver NO es un error.
enum ResolucionRitmo: Equatable {
    case resuelto(RangoRitmo, metodologiaID: String)
    case pendiente(TipoRitmo)
}

/// Una metodología de ritmos de entrenamiento: resuelve los ritmos
/// SIMBÓLICOS (.facil/.umbral/…) contra un baseline. Identificada y
/// versionada (`id` tipo "nombre@versión") para que un plan pueda decir
/// CON QUÉ se calcularon sus ritmos; `fuentePublica` es la cita
/// verificable — sin fuente citable no hay metodología.
protocol MetodologiaRitmos {
    static var id: String { get }
    static var nombre: String { get }
    static var fuentePublica: String { get }
    func resolver(_ tipo: TipoRitmo, baseline: PerformanceBaseline) -> RangoRitmo?
}

/// Registro de metodologías. HOY NO HAY NINGUNA ACTIVA — deliberado:
/// las tablas de Daniels/VDOT son material propietario y no se copian,
/// y acá no se inventan números deportivos (regla dura de Fase G). El
/// día que exista una metodología con fuente pública verificable, se
/// implementa el protocolo, se registra acá, y TODA la resolución de
/// la app pasa por este único punto.
enum Metodologias {
    /// Maratonia v1: zonas derivadas de la proyección de Riegel con
    /// anclas fisiológicas publicadas (ver METODOLOGIA.md). Las tablas
    /// propietarias (VDOT/Daniels) siguen sin copiarse.
    static var activa: MetodologiaRitmos? { MetodologiaMaratoniaV1() }

    static func resolver(_ tipo: TipoRitmo, baseline: PerformanceBaseline?) -> ResolucionRitmo {
        guard let metodologia = activa, let baseline,
              let rango = metodologia.resolver(tipo, baseline: baseline) else {
            return .pendiente(tipo)
        }
        return .resuelto(rango, metodologiaID: type(of: metodologia).id)
    }
}

/// Equivalencias de tiempos de CARRERA (no de entrenamiento) por la
/// fórmula de Riegel: t2 = t1 · (d2/d1)^1.06. Fuente pública y
/// citable: Peter S. Riegel, "Athletic Records and Human Endurance",
/// American Scientist 69(3), 1981 (la fórmula con exponente 1.06 es
/// del propio autor; uso extendido y verificable). Predice el tiempo
/// equivalente en otra distancia — NO prescribe ritmos de
/// entrenamiento, así que no reemplaza a la metodología pendiente.
enum Riegel {
    static let exponente = 1.06
    static let fuente = "P. S. Riegel, American Scientist 69(3), 1981"

    /// Tiempo equivalente en `aMetros` partiendo de una marca. nil si
    /// la extrapolación es abusiva (fuera de 1/4x–4x de la distancia
    /// de origen, la fórmula pierde sentido — el propio paper la
    /// valida para esfuerzos de resistencia comparables).
    static func tiempoEquivalente(segundos: Int,
                                  deMetros: Double,
                                  aMetros: Double) -> Int? {
        guard segundos > 0, deMetros > 0, aMetros > 0 else { return nil }
        let factor = aMetros / deMetros
        guard factor >= 0.25, factor <= 4 else { return nil }
        let equivalente = Double(segundos) * pow(factor, exponente)
        return Int(equivalente.rounded())
    }
}

// MARK: - Metodología Maratonia v1 (zonas con fuente pública)

/// Zonas de entrenamiento derivadas DETERMINÍSTICAMENTE de una marca
/// real, sin tablas propietarias. Anclas (citas completas en
/// METODOLOGIA.md):
/// - Proyección entre distancias: Riegel 1981 (el paper valida la
///   fórmula de 1500 m a maratón; para DERIVAR ZONAS se usa ese rango
///   completo, distinto del predictor de marcas de la UI, que mantiene
///   su guarda conservadora de 1/4x–4x).
/// - Umbral ≈ ritmo sostenible ~45-60 min de carrera (Faude,
///   Kindermann & Meyer, Sports Medicine 2009).
/// - Intervalo ≈ ritmo de carrera de 3-5 km ~ vVO2max (Billat &
///   Koralsztein 1996; Billat 2001).
/// - Repetición ≈ ritmo de 1500 m (mismo marco de Billat: esfuerzos
///   cortos por encima de vVO2max).
/// - Fácil/recuperación: claramente por debajo del umbral, coherente
///   con la distribución ~80/20 (Seiler 2010). Sin ancla numérica
///   publicada única → offsets amplios sobre ritmo de maratón,
///   declarados CONSENSO (no paper).
struct MetodologiaMaratoniaV1: MetodologiaRitmos {
    static let id = "maratonia@1"
    static let nombre = "Maratonia v1"
    static let fuentePublica = "Riegel 1981; Faude et al. 2009; Billat 2001; Seiler 2010 — ver METODOLOGIA.md"

    /// Rango de referencia aceptado: marcas de 1500 m a maratón, de 4′
    /// a 4 h — fuera de eso la derivación no es defendible.
    private func proyectar(_ baseline: PerformanceBaseline, aMetros: Double) -> Int? {
        guard baseline.distanciaMetros >= 1500, baseline.distanciaMetros <= 42195,
              baseline.segundos >= 240, baseline.segundos <= 14400,
              aMetros >= 1500, aMetros <= 42195 else { return nil }
        let tiempo = Double(baseline.segundos)
            * pow(aMetros / baseline.distanciaMetros, Riegel.exponente)
        return Int(tiempo.rounded())
    }

    private func ritmo(_ segundos: Int, metros: Double) -> Int {
        Int((Double(segundos) / (metros / 1000)).rounded())
    }

    func resolver(_ tipo: TipoRitmo, baseline: PerformanceBaseline) -> RangoRitmo? {
        // Ritmo de maratón proyectado: ancla de las zonas suaves.
        let ritmoMaraton = proyectar(baseline, aMetros: 42195)
            .map { ritmo($0, metros: 42195) }

        switch tipo {
        case .repeticion:
            return proyectar(baseline, aMetros: 1500).map {
                let r = ritmo($0, metros: 1500)
                return RangoRitmo(minSegKm: r - 5, maxSegKm: r + 5)
            }
        case .intervalo:
            return proyectar(baseline, aMetros: 3000).map {
                let r = ritmo($0, metros: 3000)
                return RangoRitmo(minSegKm: r - 5, maxSegKm: r + 8)
            }
        case .umbral:
            // Distancia cuyo tiempo proyectado es 60 min (Faude 2009:
            // el umbral se sostiene ~45-60 min): d = dRef·(3600/tRef)^(1/b).
            guard baseline.segundos >= 240, baseline.segundos <= 14400,
                  baseline.distanciaMetros >= 1500 else { return nil }
            let d60 = baseline.distanciaMetros
                * pow(3600 / Double(baseline.segundos), 1 / Riegel.exponente)
            guard d60 >= 1500, d60 <= 42195 else { return nil }
            let r = ritmo(3600, metros: d60)
            return RangoRitmo(minSegKm: r - 5, maxSegKm: r + 8)
        case .maraton:
            return ritmoMaraton.map { RangoRitmo(minSegKm: $0 - 8, maxSegKm: $0 + 8) }
        case .facil:
            // CONSENSO: claramente bajo el umbral (Seiler 80/20).
            return ritmoMaraton.map { RangoRitmo(minSegKm: $0 + 45, maxSegKm: $0 + 90) }
        case .recuperacion:
            return ritmoMaraton.map { RangoRitmo(minSegKm: $0 + 90, maxSegKm: $0 + 150) }
        }
    }
}

// MARK: - Almacén raíz (lo que se persiste como dominio-v2.json)

struct AlmacenV2: Codable, Equatable {
    /// Versión del ESQUEMA (no de la app): sube solo con cambios
    /// incompatibles, con migración explícita.
    var versionEsquema = 1

    /// false = ensayo de migración (Fase A): regenerable desde el plan
    /// legacy en cada arranque, nadie lo consume todavía. true = fuente
    /// de verdad (a partir del cutover de Fase B): intocable por la
    /// migración. Así "migrar dos veces" jamás duplica ni pisa datos
    /// reales.
    var activado = false
    var planActivo: PlanUsuario?

    /// Planes reemplazados: historial read-only (adoptar uno nuevo
    /// archiva el anterior, jamás lo pisa). Opcional para que los
    /// dominio-v2.json de Fase A sigan decodificando.
    var planesAnteriores: [PlanUsuario]? = nil

    var audio = ConfiguracionAudio()
    var sesiones: [RegistroSesion] = []
    var referencias: [ReferenciaRendimiento] = []

    /// Opcional para que los dominio-v2.json anteriores a Fase F sigan
    /// decodificando. Leer siempre vía `perfilDeportivo`.
    var perfil: PerfilDeportivo? = nil

    /// La cuenta Maratonia dueña de estos datos (RC1). nil = datos
    /// locales sin cuenta (estado válido: la cuenta es opcional).
    /// Asociar datos existentes a una cuenta nueva es SOLO poner este
    /// campo — cero duplicación, el contenido no se toca.
    var usuarioID: UUID? = nil

    /// Qué se adaptó, cuándo y por qué (§44). Opcional para que los
    /// almacenes anteriores decodifiquen.
    var adaptaciones: [RegistroAdaptacion]? = nil
    var historialAdaptaciones: [RegistroAdaptacion] { adaptaciones ?? [] }

    var historialDePlanes: [PlanUsuario] { planesAnteriores ?? [] }
    var perfilDeportivo: PerfilDeportivo { perfil ?? PerfilDeportivo() }

    /// Registra una marca CRUDA. Idempotencia por contenido: la misma
    /// (fuente, distancia, tiempo, fecha) no se duplica.
    mutating func registrarReferencia(_ nueva: ReferenciaRendimiento) {
        let repetida = referencias.contains {
            $0.fuente == nueva.fuente && $0.distanciaMetros == nueva.distanciaMetros
                && $0.segundos == nueva.segundos && $0.fecha == nueva.fecha
        }
        guard !repetida else { return }
        referencias.append(nueva)
    }

    /// La referencia MÁS RECIENTE (el baseline de Fase G parte de acá;
    /// "más reciente" y no "mejor marca": el estado actual del corredor
    /// pesa más que su mejor día histórico).
    var referenciaVigente: ReferenciaRendimiento? {
        referencias.max { $0.fecha < $1.fecha }
    }

    /// Vincula una sesión a un programado (la base de D2). Reglas:
    /// - idempotente: repetir el mismo vínculo no cambia nada;
    /// - una sesión se vincula a lo sumo a UN programado: si ya está
    ///   vinculada a otro, se RECHAZA (devuelve false) — deshacer un
    ///   vínculo es una acción aparte y explícita, nunca un efecto;
    /// - la resolución queda cumplido/parcial según `completo` (D1:
    ///   estructura entera = cumplido; iniciada sin terminar = parcial).
    @discardableResult
    mutating func vincular(sesionID: UUID, fechaSesion: Date,
                           aProgramado programadoID: UUID,
                           completo: Bool) -> Bool {
        // ¿La sesión ya está vinculada a OTRO programado?
        for semana in planActivo?.semanas ?? [] {
            for programado in semana.programados
            where programado.sesionVinculadaID == sesionID && programado.id != programadoID {
                return false
            }
        }
        guard let (s, p) = indiceDe(programadoID: programadoID) else { return false }
        planActivo?.semanas[s].programados[p].sesionVinculadaID = sesionID
        planActivo?.semanas[s].programados[p].resolucion = completo ? .cumplido : .parcial
        if let indice = sesiones.firstIndex(where: { $0.id == sesionID }) {
            sesiones[indice].vinculoProgramadoID = programadoID
        } else {
            sesiones.append(RegistroSesion(id: sesionID, fecha: fechaSesion,
                                           vinculoProgramadoID: programadoID))
        }
        return true
    }

    /// Registra una Carrera Libre (vínculo nil). Idempotente por id.
    mutating func registrarSesionLibre(sesionID: UUID, fecha: Date) {
        guard !sesiones.contains(where: { $0.id == sesionID }) else { return }
        sesiones.append(RegistroSesion(id: sesionID, fecha: fecha, vinculoProgramadoID: nil))
    }

    private func indiceDe(programadoID: UUID) -> (Int, Int)? {
        guard let semanas = planActivo?.semanas else { return nil }
        for (s, semana) in semanas.enumerated() {
            if let p = semana.programados.firstIndex(where: { $0.id == programadoID }) {
                return (s, p)
            }
        }
        return nil
    }

    // MARK: Consultas de calendario (la UI nunca rastrilla arrays a mano)

    var todosLosProgramados: [EntrenamientoProgramado] {
        (planActivo?.semanas ?? []).flatMap(\.programados)
    }

    /// "¿Qué me toca hoy?": el pendiente con fecha de hoy. Cumplidos,
    /// parciales y omitidos de hoy ya no "tocan"; los vencidos de días
    /// anteriores NO son "hoy" (se listan aparte, sin heurísticas de
    /// arrastre automático).
    func entrenamientoDeHoy(_ hoy: DiaLocal) -> EntrenamientoProgramado? {
        todosLosProgramados.first { $0.dia == hoy && $0.resolucion == .pendiente }
    }

    /// El programado de un día CON CUALQUIER resolución (para mostrar
    /// "hoy ya entrenaste" como contexto; entrenamientoDeHoy solo ve
    /// pendientes porque decide la acción principal).
    func programadoDelDia(_ dia: DiaLocal) -> EntrenamientoProgramado? {
        todosLosProgramados.first { $0.dia == dia }
    }

    /// Los 7 días (L a D) de la semana de `hoy`, cada uno con su
    /// programado si existe. La base de la vista "semana actual".
    func semanaActual(hoy: DiaLocal,
                      calendario: Calendar = .current) -> [DiaDeSemana] {
        let lunes = hoy.lunesDeLaSemana(calendario: calendario)
        return (0..<7).map { desplazamiento in
            let dia = lunes.sumando(dias: desplazamiento, calendario: calendario)
            return DiaDeSemana(dia: dia,
                               esHoy: dia == hoy,
                               programado: programadoDelDia(dia))
        }
    }

    /// Pendientes con fecha FUTURA, en orden.
    func proximosEntrenamientos(despuesDe hoy: DiaLocal, maximo: Int = 5) -> [EntrenamientoProgramado] {
        todosLosProgramados
            .filter { programado in
                guard let dia = programado.dia else { return false }
                return dia > hoy && programado.resolucion == .pendiente
            }
            .sorted { ($0.dia ?? hoy) < ($1.dia ?? hoy) }
            .prefix(maximo)
            .map { $0 }
    }

    /// Pendientes cuya fecha ya pasó (derivado, ver D3).
    func vencidos(_ hoy: DiaLocal) -> [EntrenamientoProgramado] {
        todosLosProgramados.filter { $0.estado(hoy: hoy) == .vencido }
    }

    // MARK: Gestión del programado (reprogramar / omitir / deshacer)

    /// ¿Qué otro entrenamiento ya ocupa ese día? Para avisar ANTES de
    /// reprogramar — la app nunca decide sola qué hacer con el choque.
    func conflictoEnDia(_ dia: DiaLocal, salvo programadoID: UUID) -> EntrenamientoProgramado? {
        todosLosProgramados.first { $0.dia == dia && $0.id != programadoID }
    }

    /// Mueve el programado de fecha CONSERVANDO identidad e historia
    /// (programadoID intacto, diaOriginal guarda la primera fecha).
    /// Solo un pendiente se puede mover: lo resuelto ya es historia.
    @discardableResult
    mutating func reprogramar(programadoID: UUID, a nuevoDia: DiaLocal) -> Bool {
        guard let (s, p) = indiceDe(programadoID: programadoID),
              planActivo?.semanas[s].programados[p].resolucion == .pendiente else { return false }
        planActivo?.semanas[s].programados[p].reprogramar(a: nuevoDia)
        return true
    }

    /// Marca explícitamente "no lo hice". No borra nada: el programado
    /// sigue visible en calendario e historial como omitido.
    @discardableResult
    mutating func omitir(programadoID: UUID) -> Bool {
        guard let (s, p) = indiceDe(programadoID: programadoID),
              planActivo?.semanas[s].programados[p].resolucion == .pendiente else { return false }
        planActivo?.semanas[s].programados[p].omitir()
        return true
    }

    /// Vuelve un omitido a pendiente — SOLO si no tiene sesión
    /// vinculada (con evidencia real, el estado no se pisa a mano).
    @discardableResult
    mutating func deshacerOmision(programadoID: UUID) -> Bool {
        guard let (s, p) = indiceDe(programadoID: programadoID),
              let programado = planActivo?.semanas[s].programados[p],
              programado.resolucion == .omitido,
              programado.sesionVinculadaID == nil else { return false }
        planActivo?.semanas[s].programados[p].resolucion = .pendiente
        return true
    }

    // MARK: Adaptación (reducir / convertir) — §36, §38

    /// La semana que contiene un programado (para las reglas semanales).
    func semanaDe(programadoID: UUID) -> SemanaPlan? {
        planActivo?.semanas.first { semana in
            semana.programados.contains { $0.id == programadoID }
        }
    }

    /// Escala TODOS los segmentos —los medidos en distancia y los
    /// medidos en tiempo— por el mismo factor. No toca los ritmos:
    /// reducir es hacer MENOS de lo mismo, nunca otra cosa (para eso
    /// está convertir).
    ///
    /// Escalar solo las distancias era un recorte falso: sobre un
    /// `umbral 32′` (1,5 km + 32′ + 1 km) un factor 0,8 recortaba
    /// medio kilómetro de calentamiento y dejaba el bloque duro
    /// intacto — un 6 % de reducción real donde el corredor veía 20 %.
    ///
    /// Rechaza si: el programado no existe, no está pendiente, su
    /// contrato no permite reducir, el factor cae fuera de
    /// [factorMinimo, 1), o no hay nada que escalar.
    @discardableResult
    mutating func reducir(programadoID: UUID, factor: Double) -> Bool {
        guard let (s, p) = indiceDe(programadoID: programadoID),
              let actual = planActivo?.semanas[s].programados[p],
              actual.resolucion == .pendiente,
              actual.adaptabilidad.sePuedeReducir,
              factor >= actual.adaptabilidad.factorMinimo, factor < 1,
              !actual.definicion.volumen().esVacio else { return false }
        planActivo?.semanas[s].programados[p].congelarOriginalSiHaceFalta()
        for g in actual.definicion.segmentos.indices {
            if let km = actual.definicion.segmentos[g].distanciaKm {
                planActivo?.semanas[s].programados[p].definicion.segmentos[g].distanciaKm =
                    (km * factor * 10).rounded() / 10
            } else if let segundos = actual.definicion.segmentos[g].duracionSegundos, segundos > 0 {
                // Redondeo a 10 s: un bloque de "25 min 36 s" no es una
                // prescripción, es ruido.
                planActivo?.semanas[s].programados[p].definicion.segmentos[g].duracionSegundos =
                    max(30, Int((Double(segundos) * factor / 10).rounded()) * 10)
            }
        }
        return true
    }

    /// Convierte una sesión de calidad en una salida fácil de la misma
    /// distancia: un solo segmento a ritmo libre. Es la alternativa
    /// honesta a omitir cuando el corredor llegó cansado — mantiene el
    /// hábito y el volumen sin la carga de intensidad.
    @discardableResult
    mutating func convertirEnFacil(programadoID: UUID,
                                   baseline: PerformanceBaseline? = nil) -> Bool {
        guard let (s, p) = indiceDe(programadoID: programadoID),
              let actual = planActivo?.semanas[s].programados[p],
              actual.resolucion == .pendiente,
              actual.adaptabilidad.sePuedeConvertirEnFacil else { return false }
        // El rodaje equivalente conserva el VOLUMEN de la sesión, no su
        // distancia declarada: convertir un `umbral 32′` producía antes
        // un rodaje de 2,5 km — un cuarto del trabajo original.
        let km = (actual.definicion.volumenKm(baseline: baseline) * 10).rounded() / 10
        guard km > 0 else { return false }
        planActivo?.semanas[s].programados[p].congelarOriginalSiHaceFalta()
        planActivo?.semanas[s].programados[p].definicion = DefinicionEntrenamiento(
            id: actual.definicion.id,          // identidad estable
            tipo: .facil,
            nombre: String(localized: "Rodaje fácil"),
            descripcion: String(localized: "Versión suave de la sesión original: mismo tiempo en pie, sin la carga de intensidad."),
            segmentos: [Segmento(nombre: String(localized: "Rodaje"),
                                 distanciaKm: km, duracionSegundos: nil, ritmo: .libre)],
            // El TOPE viaja con la sesión. Convertir es aliviar, no una
            // puerta trasera para quitarle el techo de duración a un
            // fondo: sin esta línea, convertir la larga en rodaje
            // devolvía una sesión sin límite de tiempo.
            topeDuracionSegundos: actual.definicion.topeDuracionSegundos)
        // El rol baja a fácil: la semana ya no cuenta esto como calidad.
        planActivo?.semanas[s].programados[p].rolGuardado = .facil
        planActivo?.semanas[s].programados[p].adaptabilidadGuardada = .para(.facil)
        return true
    }

    /// Anota una adaptación en el historial. Siempre se llama DESPUÉS
    /// de que la mutación haya devuelto true.
    mutating func registrarAdaptacion(_ registro: RegistroAdaptacion) {
        adaptaciones = historialAdaptaciones + [registro]
    }

    /// Guarda el feedback subjetivo de una sesión ya registrada.
    /// Idempotente y no destructivo: si la sesión no existe, no crea
    /// una fantasma (el registro nace del guardado en Salud).
    @discardableResult
    mutating func registrarSensacion(sesionID: UUID, sensacion: SensacionEsfuerzo?,
                                     conMolestia: Bool?) -> Bool {
        guard let indice = sesiones.firstIndex(where: { $0.id == sesionID }) else { return false }
        if let sensacion { sesiones[indice].sensacion = sensacion }
        if let conMolestia { sesiones[indice].conMolestia = conMolestia }
        return true
    }

    /// Adoptar un plan nuevo archiva el activo (read-only): nada se
    /// pisa ni se borra.
    /// `esFaseBase` = el plan NO es el del objetivo declarado, sino un
    /// puente hacia él. En ese caso el motivo pendiente se conserva: el
    /// objetivo deseado sigue sin plan y la app tiene que poder decirlo
    /// sin inventar un estado nuevo (ver `FaseBase.esFaseBase`).
    mutating func adoptarPlan(_ nuevo: PlanUsuario, esFaseBase: Bool = false) {
        if let actual = planActivo {
            planesAnteriores = historialDePlanes + [actual]
        }
        planActivo = nuevo
        // Hay plan: el objetivo dejó de estar pendiente. Único lugar
        // donde se limpia, para que no pueda quedar un "no llegamos"
        // colgado encima de un plan que sí existe.
        if !esFaseBase { perfil?.objetivoSinPlan = nil }
    }

    /// Quitar el plan SIN reemplazo: se archiva igual que en un cambio
    /// de plan (nada se borra — sesiones, carreras y referencias
    /// intactas) y la app queda en modo libre: HOY vacío, el reloj cae
    /// a Carrera Libre y los tramos personalizados siguen mandando.
    mutating func abandonarPlan() {
        guard let actual = planActivo else { return }
        planesAnteriores = historialDePlanes + [actual]
        planActivo = nil
    }
}

// MARK: - Proyección del día y resultado (Watch V2, Fase E)

/// Lo que el iPhone le PROYECTA al reloj: el entrenamiento pendiente de
/// HOY (si hay) con su identidad estable. El reloj NO administra el
/// calendario — muestra esto, corre, y devuelve el resultado. Viaja por
/// applicationContext (siempre gana la última, sobrevive a reloj
/// apagado o lejos).
struct ProyeccionDia: Codable, Equatable {
    /// Se sube SOLO ante cambios incompatibles; un receptor viejo
    /// ignora versiones mayores en vez de malinterpretarlas.
    static let versionActual = 1
    var version: Int = ProyeccionDia.versionActual
    var generadaEl: Date
    /// El "hoy" del iPhone al generarla — la vigencia se decide acá.
    var dia: DiaLocal
    var programadoID: UUID?
    var definicion: DefinicionEntrenamiento?
    var nombrePlan: String?

    /// Si el programado de HOY ya se RESOLVIÓ (cumplido/parcial/
    /// omitido), viaja como resultado: el reloj lo muestra como estado
    /// del día y no vuelve a ofrecerlo como pendiente (bug 2 de build
    /// 38: al terminar, la Home caía a la experiencia legacy). Campos
    /// opcionales — un receptor viejo simplemente los ignora, así que
    /// la versión de esquema no cambia.
    var resolucionDeHoy: ResolucionProgramado? = nil
    var nombreDeHoy: String? = nil
    var tipoDeHoy: TipoEntrenamiento? = nil

    /// El sistema de unidades del corredor. Viaja con la proyección
    /// —que ya se reenvía ante cada cambio y al abrir la app— para que
    /// el reloj muestre y hable en las mismas unidades que el teléfono.
    /// Opcional: un receptor viejo lo ignora y la versión no sube.
    var sistemaUnidades: SistemaUnidades? = nil

    /// Una proyección de ayer NO ofrece el entrenamiento de ayer como
    /// si fuera de hoy: si el día no coincide, el reloj cae a Carrera
    /// Libre (y el iPhone re-proyecta cuando se abra).
    func vigente(hoy: DiaLocal) -> Bool {
        version <= Self.versionActual && dia == hoy
    }

    /// Qué puede OFRECER la Home del reloj hoy: el pendiente proyectado,
    /// salvo que este reloj ya lo haya corrido (garantía de que un mismo
    /// programadoID no se ejecuta dos veces desde la pantalla principal).
    func entrenamientoOfrecible(hoy: DiaLocal,
                                completadosLocal: Set<UUID>) -> (id: UUID, definicion: DefinicionEntrenamiento)? {
        guard vigente(hoy: hoy),
              let id = programadoID,
              let definicion,
              !completadosLocal.contains(id) else { return nil }
        return (id, definicion)
    }

    /// Qué RESULTADO muestra la Home del reloj hoy, con esta prioridad:
    /// 1. lo que dice el iPhone (dueño del calendario): resolucionDeHoy;
    /// 2. lo corrido LOCALMENTE mientras el resultado viaja al iPhone.
    /// nil = hoy no hay nada resuelto que mostrar.
    func resultadoDeHoy(hoy: DiaLocal,
                        completadosLocal: Set<UUID>,
                        estructuraLocal: [UUID: Bool]) -> (nombre: String, resolucion: ResolucionProgramado)? {
        guard vigente(hoy: hoy) else { return nil }
        if let resolucion = resolucionDeHoy, let nombre = nombreDeHoy {
            return (nombre, resolucion)
        }
        if let id = programadoID, let definicion,
           completadosLocal.contains(id) {
            let completa = estructuraLocal[id] ?? false
            return (definicion.nombre, completa ? .cumplido : .parcial)
        }
        return nil
    }
}

/// Lo que el reloj devuelve al guardar una sesión: la evidencia mínima
/// con IDs estables. Viaja por transferUserInfo (cola confiable que
/// sobrevive offline y llega tarde si hace falta); el receptor es
/// idempotente, así que llegar dos veces no duplica nada.
struct ResultadoSesionWatch: Codable, Equatable {
    static let versionActual = 1
    var version: Int = ResultadoSesionWatch.versionActual
    var sesionID: UUID          // HKWorkout.uuid — identidad global
    var fecha: Date
    var programadoID: UUID?     // nil = carrera libre
    var estructuraCompleta: Bool
}

/// Claves únicas de los diccionarios de WatchConnectivity (los strings
/// sueltos en dos targets divergen solos).
enum MensajesWC {
    static let claveProyeccion = "proyeccionDia"
    static let claveResultado = "resultadoSesion"
}

// MARK: - Migración V1 → V2

/// Transforma el modelo viejo (Plan con tramos+audio mezclados) en el
/// almacén V2, sin perder nada:
/// - pistas y avisos → ConfiguracionAudio;
/// - tramos → un PlanUsuario "personalizado" de 1 semana con 1
///   programado sin fecha;
/// - la huellaEntrenamiento de V1 es el PUENTE DE MIGRACIÓN: si
///   coincide con la huella cumplida guardada, el programado nace
///   cumplido (sin sesión vinculada: la evidencia pre-V2 no existe).
///   El puente muere en Fase E, cuando el reloj deje de usar huellas.
///
/// La función es pura (fechas inyectadas). La idempotencia de la
/// migración REAL la da el llamador: solo se migra si dominio-v2.json
/// no existe todavía (ver PlanStore).
enum MigracionV2 {
    static func migrar(planV1: Plan, huellaCumplida: String?, fecha: Date) -> AlmacenV2 {
        var almacen = AlmacenV2()
        almacen.audio = ConfiguracionAudio(
            pistas: planV1.pistas,
            avisosFijos: planV1.avisosFijos,
            avisosRepetidos: planV1.avisosRepetidos,
            avisosKm: planV1.avisosKmActivos)

        let tramos = planV1.tramosActivos
        guard !tramos.isEmpty else { return almacen }

        let segmentos = tramos.map { tramo in
            Segmento(nombre: tramo.nombre,
                     distanciaKm: tramo.kilometros,
                     duracionSegundos: nil,
                     ritmo: ritmo(de: tramo))
        }
        let definicion = DefinicionEntrenamiento(
            tipo: .personalizado,
            nombre: planV1.nombre,
            descripcion: "Migrado del plan original",
            segmentos: segmentos)
        var programado = EntrenamientoProgramado(definicion: definicion, dia: nil)
        if let huellaCumplida, huellaCumplida == planV1.huellaEntrenamiento {
            programado.resolucion = .cumplido
        }
        almacen.planActivo = PlanUsuario(
            nombre: planV1.nombre,
            origen: .personalizado,
            fechaAdopcion: fecha,
            semanas: [SemanaPlan(numero: 1, programados: [programado])])
        return almacen
    }

    private static func ritmo(de tramo: Tramo) -> RitmoObjetivo {
        if tramo.ritmoMinSegKm == nil && tramo.ritmoMaxSegKm == nil {
            return .libre
        }
        return .absoluto(minSegKm: tramo.ritmoMinSegKm, maxSegKm: tramo.ritmoMaxSegKm)
    }
}
