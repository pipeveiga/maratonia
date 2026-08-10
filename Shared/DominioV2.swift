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
    var nombre: String
    var distanciaKm: Double?
    var duracionSegundos: Int?
    var ritmo: RitmoObjetivo = .libre
}

struct DefinicionEntrenamiento: Codable, Equatable, Identifiable {
    var id = UUID()                      // definicionID: estable ante ediciones
    var tipo: TipoEntrenamiento
    var nombre: String
    var descripcion: String = ""
    var segmentos: [Segmento] = []
}

extension DefinicionEntrenamiento {

    /// Distancia total prevista (nil si ningún segmento es por distancia).
    var distanciaTotalKm: Double? {
        let kms = segmentos.compactMap(\.distanciaKm)
        guard !kms.isEmpty else { return nil }
        return kms.reduce(0, +)
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
        if let km = distanciaTotalKm {
            medidas.append(km == km.rounded() ? "\(Int(km)) km" : String(format: "%.1f km", km))
        }
        if let segundos = duracionPorTiempoSegundos {
            medidas.append(duracionTexto(segundos))
        }
        var partes: [String] = []
        if !medidas.isEmpty { partes.append(medidas.joined(separator: " + ")) }
        partes.append(segmentos.count == 1 ? "1 segmento" : "\(segmentos.count) segmentos")
        return partes.joined(separator: " · ")
    }

    /// Puente al motor: cada segmento se vuelve un Tramo ejecutable.
    /// DISTANCIA tiene prioridad si un segmento trae las dos metas; un
    /// segmento sin ninguna meta no es ejecutable y se descarta.
    var tramosEjecutables: [Tramo] {
        segmentos.compactMap { segmento in
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
                return Tramo(nombre: segmento.nombre, kilometros: km,
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
    var nombre: String
    var origen: OrigenPlan = .personalizado
    var fechaAdopcion: Date
    var semanas: [SemanaPlan] = []

    /// Con qué referencia de rendimiento se armó este plan (RC1,
    /// motor de planes). Opcional y retrocompatible: los planes
    /// anteriores no la tienen. La versión del arquetipo/metodología
    /// ya viaja en `origen` ("id@versión").
    var referenciaUsadaID: UUID? = nil
}

struct SemanaPlan: Codable, Equatable, Identifiable {
    var id = UUID()
    var numero: Int
    var programados: [EntrenamientoProgramado] = []
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

    var esLibre: Bool { vinculoProgramadoID == nil }
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

/// La meta que el corredor eligió. Enum cerrado a propósito: el plan
/// generator y el coach futuro razonan sobre esto.
enum ObjetivoDeportivo: String, Codable, CaseIterable {
    case primeros5K, mejorar5K, diez, mediaMaraton, maraton
}

/// Lo que el onboarding recolecta. TODO opcional: el perfil incompleto
/// es un estado normal (usuario viejo, onboarding salteado) y ninguna
/// pantalla debe romperse por un campo vacío. Las MARCAS no viven acá:
/// son ReferenciaRendimiento (datos crudos, con fecha y fuente).
struct PerfilDeportivo: Codable, Equatable {
    var objetivo: ObjetivoDeportivo?
    var diasPorSemana: Int?
    var fechaObjetivo: DiaLocal?
    /// Cuándo completó el onboarding (nil = nunca lo hizo).
    var fechaOnboarding: Date?
    /// Eligió "hacer el test de 5K" y todavía no lo corrió.
    var testPendiente: Bool = false
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
    /// nil = los ritmos simbólicos quedan pendientes (se ejecutan
    /// libres, se muestran como "a personalizar").
    static var activa: MetodologiaRitmos? { nil }

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

    /// Adoptar un plan nuevo archiva el activo (read-only): nada se
    /// pisa ni se borra.
    mutating func adoptarPlan(_ nuevo: PlanUsuario) {
        if let actual = planActivo {
            planesAnteriores = historialDePlanes + [actual]
        }
        planActivo = nuevo
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
