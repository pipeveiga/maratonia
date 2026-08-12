import Foundation

// MOTOR ADAPTATIVO. El orden es siempre el mismo y no se saltea:
//
//   sesión guardada → ANÁLISIS POST-CARRERA (determinístico)
//                   → DETECTOR DE EVENTOS (determinístico)
//                   → ¿hay algo? NO  → "tu plan sigue según lo previsto"
//                                 SÍ → DTO → backend → IA
//                   → OPERACIONES (keep/move/reduce/replace/skip)
//                   → VALIDADOR (determinístico, rechaza por defecto)
//                   → PREVIEW → el corredor acepta → APLICAR + historial
//
// Reglas duras de todo el archivo:
// - la IA JAMÁS escribe el dominio: propone operaciones que el
//   validador aprueba una por una y el corredor confirma;
// - reducir es flexible, aumentar es casi imposible (§40): una buena
//   sesión suelta no habilita subir carga;
// - los entrenamientos perdidos NO se compensan apilando kilómetros
//   (§41): se pierden, y punto;
// - sin backend, sin internet o con schema roto, todo esto sigue
//   funcionando: el detector y el validador son locales (§49).

// MARK: - Análisis post-carrera (§32)

/// La foto determinística de una sesión contra lo que estaba
/// prescrito. Usa SOLO agregados (distancia, duración, ritmo promedio):
/// nada de ritmo instantáneo, que es ruidoso por naturaleza.
struct AnalisisPostCarrera: Equatable, Identifiable {
    var id: UUID { sesionID }
    var sesionID: UUID
    var fecha: Date
    var km: Double
    var minutos: Double
    var ritmoSegKm: Int?
    /// El programado que esta sesión resolvió (nil = carrera libre).
    var programadoID: UUID?
    var kmPrescritos: Double?
    var estructuraCompleta: Bool
    var sensacion: SensacionEsfuerzo?
    var conMolestia: Bool

    /// Qué fracción de lo prescrito se corrió (nil sin prescripción).
    var cumplimiento: Double? {
        guard let prescritos = kmPrescritos, prescritos > 0 else { return nil }
        return km / prescritos
    }

    var esLibre: Bool { programadoID == nil }

    static func desde(sesion: SesionMetrica, sesionID: UUID,
                      programado: EntrenamientoProgramado?,
                      registro: RegistroSesion?,
                      estructuraCompleta: Bool) -> AnalisisPostCarrera {
        AnalisisPostCarrera(
            sesionID: sesionID,
            fecha: sesion.fecha,
            km: sesion.metros / 1000,
            minutos: sesion.segundos / 60,
            ritmoSegKm: MetricasSesion.ritmoSegKm(metros: sesion.metros,
                                                  segundos: sesion.segundos),
            programadoID: programado?.id,
            kmPrescritos: programado?.definicion.distanciaTotalKm,
            estructuraCompleta: estructuraCompleta,
            sensacion: registro?.sensacion,
            conMolestia: registro?.conMolestia ?? false)
    }
}

// MARK: - Detector determinístico de eventos (§34)

/// Qué pasó que amerite mirar el plan. Si esta lista vuelve vacía, la
/// app NO llama a la IA y le dice al corredor que todo sigue igual.
enum EventoEntrenamiento: Equatable {
    case sesionPerdida(programadoID: UUID)
    case sesionParcial(programadoID: UUID, cumplimiento: Double)
    case variasAusencias(cantidad: Int)
    case volumenSemanalBajo(hechoKm: Double, previstoKm: Double)
    case esfuerzoMuyAlto(sesionID: UUID)
    case molestiaReportada(sesionID: UUID)
    case fondoComprometido(programadoID: UUID)
    case carreraLibreSignificativa(sesionID: UUID, km: Double)
    case cambioDeDisponibilidad
    case pedidoDelUsuario
    case cercaDeLaCarrera(diasRestantes: Int)

    /// Cuánto pesa. `.baja` es contexto que la IA agradece pero que
    /// por sí solo NO justifica una llamada.
    enum Severidad: Int, Comparable {
        case baja = 0, media = 1, alta = 2
        static func < (a: Severidad, b: Severidad) -> Bool { a.rawValue < b.rawValue }
    }

    var severidad: Severidad {
        switch self {
        case .variasAusencias, .molestiaReportada, .esfuerzoMuyAlto,
             .cambioDeDisponibilidad, .pedidoDelUsuario:
            return .alta
        case .sesionPerdida, .fondoComprometido, .volumenSemanalBajo,
             .carreraLibreSignificativa:
            return .media
        case .sesionParcial, .cercaDeLaCarrera:
            return .baja
        }
    }
}

/// Todo lo que el detector mira, en un struct plano y testeable.
struct EntradaDeteccion {
    var hoy: DiaLocal
    var almacen: AlmacenV2
    /// Lo recién corrido, si el detector se dispara post-carrera.
    var analisis: AnalisisPostCarrera? = nil
    /// Km efectivamente corridos esta semana (de Salud).
    var kmSemanaActual: Double? = nil
    /// El corredor tocó "reorganizar mi semana".
    var pedidoExplicito: Bool = false
    /// Cambió los días que puede correr desde que adoptó el plan.
    var disponibilidadCambio: Bool = false
}

enum DetectorEventos {

    /// Umbral de "volumen muy por debajo": menos del 60 % de lo
    /// prescrito para la semana. Por encima de eso, una semana floja
    /// es una semana floja — no un evento.
    static let fraccionVolumenBajo = 0.6
    /// Una carrera libre importa si suma al menos el 40 % del volumen
    /// semanal prescrito: por debajo, es un trote y no mueve nada.
    static let fraccionLibreSignificativa = 0.4
    /// Ausencias que se miran hacia atrás.
    static let diasVentanaAusencias = 14
    static let ausenciasParaAlarma = 2

    static func detectar(_ entrada: EntradaDeteccion,
                         calendario: Calendar = .current) -> [EventoEntrenamiento] {
        var eventos: [EventoEntrenamiento] = []
        let almacen = entrada.almacen
        let hoy = entrada.hoy

        if entrada.pedidoExplicito { eventos.append(.pedidoDelUsuario) }
        if entrada.disponibilidadCambio { eventos.append(.cambioDeDisponibilidad) }

        // ---- Lo recién corrido.
        if let analisis = entrada.analisis {
            if analisis.conMolestia { eventos.append(.molestiaReportada(sesionID: analisis.sesionID)) }
            if analisis.sensacion?.pideAtencion == true {
                eventos.append(.esfuerzoMuyAlto(sesionID: analisis.sesionID))
            }
            if let programadoID = analisis.programadoID,
               let cumplimiento = analisis.cumplimiento, cumplimiento < 0.9,
               !analisis.estructuraCompleta {
                eventos.append(.sesionParcial(programadoID: programadoID,
                                              cumplimiento: cumplimiento))
                if almacen.todosLosProgramados.first(where: { $0.id == programadoID })?
                    .rol == .tiradaLarga {
                    eventos.append(.fondoComprometido(programadoID: programadoID))
                }
            }
            // Carrera libre: solo si movió la aguja de la semana (§42).
            if analisis.esLibre, let previsto = kmPrevistosSemana(almacen, hoy: hoy),
               previsto > 0, analisis.km >= previsto * fraccionLibreSignificativa {
                eventos.append(.carreraLibreSignificativa(sesionID: analisis.sesionID,
                                                          km: analisis.km))
            }
        }

        // ---- Ausencias recientes: vencidos sin resolver + omitidos.
        let desde = hoy.sumando(dias: -diasVentanaAusencias, calendario: calendario)
        let perdidos = almacen.todosLosProgramados.filter { programado in
            guard let dia = programado.dia, dia >= desde, dia < hoy else { return false }
            return programado.resolucion == .omitido
                || programado.estado(hoy: hoy) == .vencido
        }
        if perdidos.count >= ausenciasParaAlarma {
            eventos.append(.variasAusencias(cantidad: perdidos.count))
        } else if let uno = perdidos.first {
            eventos.append(.sesionPerdida(programadoID: uno.id))
            if uno.rol == .tiradaLarga {
                eventos.append(.fondoComprometido(programadoID: uno.id))
            }
        }

        // ---- Volumen de la semana en curso.
        if let hecho = entrada.kmSemanaActual,
           let previsto = kmPrevistosSemana(almacen, hoy: hoy), previsto > 0,
           hecho < previsto * fraccionVolumenBajo,
           semanaYaAvanzada(hoy, calendario: calendario) {
            eventos.append(.volumenSemanalBajo(hechoKm: hecho, previstoKm: previsto))
        }

        // ---- Cercanía de la carrera: contexto, nunca alarma.
        if let carrera = almacen.perfilDeportivo.fechaObjetivo,
           let dias = diasEntre(hoy, carrera, calendario: calendario),
           dias >= 0, dias <= 14 {
            eventos.append(.cercaDeLaCarrera(diasRestantes: dias))
        }

        return eventos
    }

    /// La regla de oro de §35: la mayoría de las carreras normales NO
    /// deben terminar en una propuesta de cambio.
    static func ameritaIA(_ eventos: [EventoEntrenamiento]) -> Bool {
        eventos.contains { $0.severidad >= .media }
    }

    static func kmPrevistosSemana(_ almacen: AlmacenV2, hoy: DiaLocal,
                                  calendario: Calendar = .current) -> Double? {
        let lunes = hoy.lunesDeLaSemana(calendario: calendario)
        let km = almacen.todosLosProgramados
            .filter { $0.dia?.lunesDeLaSemana(calendario: calendario) == lunes }
            .compactMap(\.definicion.distanciaTotalKm)
        return km.isEmpty ? nil : km.reduce(0, +)
    }

    /// Antes del jueves, "vas por debajo del volumen" es matemática
    /// correcta y consejo inútil: la semana todavía no pasó.
    private static func semanaYaAvanzada(_ hoy: DiaLocal, calendario: Calendar) -> Bool {
        guard let fecha = hoy.fecha(calendario: calendario) else { return false }
        let wd = calendario.component(.weekday, from: fecha)
        return (wd == 1 ? 7 : wd - 1) >= 5   // viernes en adelante
    }

    private static func diasEntre(_ desde: DiaLocal, _ hasta: DiaLocal,
                                  calendario: Calendar) -> Int? {
        guard let a = desde.fecha(calendario: calendario),
              let b = hasta.fecha(calendario: calendario) else { return nil }
        return calendario.dateComponents([.day], from: a, to: b).day
    }
}

// MARK: - Operaciones de adaptación (§38)

/// Lo ÚNICO que se puede proponer sobre un plan. Operaciones concretas
/// sobre sesiones REALES por ID — jamás un calendario entero en texto
/// libre, jamás "creá una sesión nueva".
///
/// (Este enum reemplaza al `CambioPropuesto` de tres casos: mismo rol,
/// mismo lugar en la arquitectura, más operaciones.)
enum CambioPropuesto: Equatable {
    /// Explícito a propósito: que la IA pueda decir "esto queda igual"
    /// es lo que evita que invente cambios para justificarse (§35).
    case mantener(programadoID: UUID)
    case reprogramar(programadoID: UUID, a: DiaLocal)
    case reducir(programadoID: UUID, factor: Double)
    case convertirEnFacil(programadoID: UUID)
    case omitir(programadoID: UUID)

    var programadoID: UUID {
        switch self {
        case .mantener(let id), .reprogramar(let id, _), .reducir(let id, _),
             .convertirEnFacil(let id), .omitir(let id):
            return id
        }
    }

    var tipoDeAdaptacion: RegistroAdaptacion.Tipo? {
        switch self {
        case .mantener: return nil
        case .reprogramar: return .mover
        case .reducir: return .reducir
        case .convertirEnFacil: return .convertir
        case .omitir: return .omitir
        }
    }
}

struct ValidacionDeCambio: Equatable {
    var permitido: Bool
    var motivo: String?

    static let ok = ValidacionDeCambio(permitido: true, motivo: nil)
    static func no(_ motivo: String) -> ValidacionDeCambio {
        ValidacionDeCambio(permitido: false, motivo: motivo)
    }
}

// MARK: - Validador determinístico (§39)

/// La autoridad. Rechaza por defecto: lo que no se puede verificar, no
/// se aplica. Cada regla es independiente y explica su rechazo en una
/// frase que el corredor entiende.
enum ValidadorDeCoach {

    static func validar(_ cambio: CambioPropuesto, en almacen: AlmacenV2,
                        hoy: DiaLocal, calendario: Calendar = .current) -> ValidacionDeCambio {
        // ---- Existencia.
        guard let programado = almacen.todosLosProgramados
            .first(where: { $0.id == cambio.programadoID }) else {
            return .no(String(localized: "Ese entrenamiento no existe en tu plan."))
        }

        // "Mantener" no muta nada: siempre válido si el programado existe.
        if case .mantener = cambio { return .ok }

        // ---- Sesiones ya resueltas y pasado: historia, no material.
        guard programado.resolucion == .pendiente else {
            return .no(String(localized: "Ese entrenamiento ya está resuelto: no se toca."))
        }
        if let dia = programado.dia, dia < hoy {
            return .no(String(localized: "No se modifican entrenamientos de días que ya pasaron."))
        }

        // ---- La carrera objetivo es un ancla inmutable (§8).
        if programado.rol == .carrera {
            return .no(String(localized: "Tu carrera objetivo no se mueve ni se cambia."))
        }

        let contrato = programado.adaptabilidad
        let carrera = almacen.perfilDeportivo.fechaObjetivo

        switch cambio {
        case .mantener:
            return .ok

        case .reprogramar(_, let nuevoDia):
            guard contrato.sePuedeMover else {
                return .no(String(localized: "Esta sesión no se puede mover de día."))
            }
            guard !(nuevoDia < hoy) else {
                return .no(String(localized: "No se reprograma hacia el pasado."))
            }
            if let carrera, nuevoDia > carrera {
                return .no(String(localized: "No se programan entrenamientos después de tu carrera."))
            }
            if let motivo = diaNoDisponible(nuevoDia, almacen: almacen, calendario: calendario) {
                return .no(motivo)
            }
            if almacen.conflictoEnDia(nuevoDia, salvo: programado.id) != nil {
                return .no(String(localized: "Ese día ya tiene otro entrenamiento."))
            }
            if let motivo = rompeRecuperacion(programado, nuevoDia: nuevoDia,
                                              almacen: almacen, calendario: calendario) {
                return .no(motivo)
            }
            return .ok

        case .reducir(_, let factor):
            guard contrato.sePuedeReducir else {
                return .no(String(localized: "Esta sesión no se puede acortar."))
            }
            guard factor < 1 else {
                // §40: bajar es flexible, subir prácticamente no existe.
                return .no(String(localized: "El Coach no puede aumentar la carga: eso lo decide el motor."))
            }
            guard factor >= contrato.factorMinimo else {
                return .no(String(localized: "Recortarla tanto ya sería otra sesión distinta."))
            }
            guard programado.definicion.distanciaTotalKm != nil else {
                return .no(String(localized: "Esta sesión no se mide por distancia: no se puede acortar así."))
            }
            if let motivo = rompeVolumenSemanal(programado, factor: factor, almacen: almacen) {
                return .no(motivo)
            }
            return .ok

        case .convertirEnFacil:
            guard contrato.sePuedeConvertirEnFacil else {
                return .no(String(localized: "Esta sesión no se puede convertir en un rodaje fácil."))
            }
            guard programado.definicion.distanciaTotalKm != nil else {
                return .no(String(localized: "Esta sesión no se mide por distancia: no se puede convertir."))
            }
            return .ok

        case .omitir:
            guard contrato.sePuedeOmitir else {
                return .no(String(localized: "Esta sesión no se puede omitir."))
            }
            if let motivo = dejaLaSemanaSinFondo(programado, almacen: almacen) {
                return .no(motivo)
            }
            return .ok
        }
    }

    /// Filtra una tanda de propuestas dejando solo las válidas.
    static func validas(_ cambios: [CambioPropuesto], en almacen: AlmacenV2,
                        hoy: DiaLocal, calendario: Calendar = .current) -> [CambioPropuesto] {
        cambios.filter { validar($0, en: almacen, hoy: hoy, calendario: calendario).permitido }
    }

    // MARK: reglas auxiliares

    /// El día tiene que ser uno de los que el corredor dijo que puede
    /// correr, y nunca uno de los imposibles (§9).
    private static func diaNoDisponible(_ dia: DiaLocal, almacen: AlmacenV2,
                                        calendario: Calendar) -> String? {
        guard let fecha = dia.fecha(calendario: calendario) else {
            return String(localized: "Esa fecha no es válida.")
        }
        let wd = calendario.component(.weekday, from: fecha)
        let indice = wd == 1 ? 7 : wd - 1
        let perfil = almacen.perfilDeportivo
        if let imposibles = perfil.preferencias?.diasImposibles, imposibles.contains(indice) {
            return String(localized: "Marcaste ese día como imposible para entrenar.")
        }
        if let elegidos = perfil.diasElegidos, !elegidos.isEmpty, !elegidos.contains(indice) {
            return String(localized: "Ese no es uno de los días que elegiste para correr.")
        }
        return nil
    }

    /// Dos sesiones exigentes pegadas no son un plan: son una lesión
    /// con fecha. Si la sesión pide recuperación, el día anterior y el
    /// siguiente no pueden tener otra exigente.
    private static func rompeRecuperacion(_ programado: EntrenamientoProgramado,
                                          nuevoDia: DiaLocal, almacen: AlmacenV2,
                                          calendario: Calendar) -> String? {
        let dias = programado.adaptabilidad.recuperacionMinimaDias
        guard dias > 0 else { return nil }
        for desplazamiento in -dias...dias where desplazamiento != 0 {
            let vecino = nuevoDia.sumando(dias: desplazamiento, calendario: calendario)
            guard let otro = almacen.todosLosProgramados.first(where: {
                $0.dia == vecino && $0.id != programado.id
            }) else { continue }
            if otro.rol <= .calidadPrincipal || otro.rol == .calidadSecundaria {
                return String(localized: "Quedaría pegada a otra sesión exigente: hace falta un día de por medio.")
            }
        }
        return nil
    }

    /// Reducir no puede tirar el volumen de la semana por debajo del
    /// mínimo declarado por el arquetipo. Sin reglas declaradas, esta
    /// regla no opina (nunca inventa un mínimo).
    private static func rompeVolumenSemanal(_ programado: EntrenamientoProgramado,
                                            factor: Double, almacen: AlmacenV2) -> String? {
        guard let semana = almacen.semanaDe(programadoID: programado.id),
              let reglas = semana.reglas, let minimo = reglas.volumenMinimoKm,
              let km = programado.definicion.distanciaTotalKm else { return nil }
        let nuevo = semana.kmPrescritos - km + km * factor
        guard nuevo < minimo else { return nil }
        return String(localized: "Con ese recorte la semana queda por debajo de su volumen mínimo.")
    }

    /// Omitir la única tirada larga de la semana no es adaptar: es
    /// borrar la sesión que sostiene el plan. Se puede reducir o mover.
    private static func dejaLaSemanaSinFondo(_ programado: EntrenamientoProgramado,
                                             almacen: AlmacenV2) -> String? {
        guard programado.rol == .tiradaLarga,
              let semana = almacen.semanaDe(programadoID: programado.id) else { return nil }
        let otrasLargas = semana.programados.filter {
            $0.rol == .tiradaLarga && $0.id != programado.id && $0.resolucion != .omitido
        }
        guard otrasLargas.isEmpty else { return nil }
        return String(localized: "Es la única tirada larga de la semana: mejor acortarla o moverla que borrarla.")
    }
}

// MARK: - Aplicador (la única puerta de mutación)

/// Aplica cambios YA validados y deja rastro en el historial. Nada
/// entra al dominio por otro lado.
enum AplicadorAdaptacion {

    /// Devuelve cuántos cambios se aplicaron de verdad. Revalida cada
    /// uno antes de tocar nada: entre la propuesta y el "aplicar" pudo
    /// pasar cualquier cosa (otra sesión guardada, un día que venció).
    @discardableResult
    static func aplicar(_ cambios: [CambioPropuesto], a almacen: inout AlmacenV2,
                        hoy: DiaLocal, origen: RegistroAdaptacion.Origen,
                        motivo: String, ahora: Date = Date(),
                        calendario: Calendar = .current) -> Int {
        var aplicados = 0
        for cambio in cambios {
            guard ValidadorDeCoach.validar(cambio, en: almacen, hoy: hoy,
                                           calendario: calendario).permitido,
                  let programado = almacen.todosLosProgramados
                    .first(where: { $0.id == cambio.programadoID }) else { continue }
            let antes = descripcion(programado, calendario: calendario)
            let hecho: Bool
            switch cambio {
            case .mantener:
                continue
            case .reprogramar(let id, let dia):
                hecho = almacen.reprogramar(programadoID: id, a: dia)
            case .reducir(let id, let factor):
                hecho = almacen.reducir(programadoID: id, factor: factor)
            case .convertirEnFacil(let id):
                hecho = almacen.convertirEnFacil(programadoID: id)
            case .omitir(let id):
                hecho = almacen.omitir(programadoID: id)
            }
            guard hecho, let tipo = cambio.tipoDeAdaptacion else { continue }
            let despues = almacen.todosLosProgramados
                .first(where: { $0.id == cambio.programadoID })
                .map { descripcion($0, calendario: calendario) } ?? antes
            almacen.registrarAdaptacion(RegistroAdaptacion(
                fecha: ahora, programadoID: cambio.programadoID, tipo: tipo,
                origen: origen, antes: antes, despues: despues, motivo: motivo))
            aplicados += 1
        }
        return aplicados
    }

    /// "8 km umbral · 12/8" — corta y legible, para el historial.
    static func descripcion(_ programado: EntrenamientoProgramado,
                            calendario: Calendar = .current) -> String {
        var partes: [String] = []
        if let km = programado.definicion.distanciaTotalKm {
            partes.append(km == km.rounded() ? "\(Int(km)) km"
                                             : String(format: "%.1f km", km))
        }
        partes.append(programado.definicion.nombre)
        if programado.resolucion == .omitido {
            partes.append(String(localized: "omitido"))
        } else if let dia = programado.dia, let fecha = dia.fecha(calendario: calendario) {
            partes.append(FormatoFecha.diaYMes(fecha))
        }
        return partes.joined(separator: " · ")
    }
}

// MARK: - Propuesta local sin IA (§49: el fallback siempre existe)

/// Lo que el motor propone SOLO, sin backend ni internet. Conservador
/// por diseño: mueve o acorta, jamás inventa sesiones ni sube carga.
enum PropuestaLocal {

    /// Ante eventos detectados, la respuesta determinística. Vacío =
    /// no hay nada razonable que proponer sin razonamiento contextual,
    /// y entonces la app simplemente informa.
    static func proponer(para eventos: [EventoEntrenamiento], en almacen: AlmacenV2,
                         hoy: DiaLocal, calendario: Calendar = .current) -> [CambioPropuesto] {
        var cambios: [CambioPropuesto] = []
        for evento in eventos {
            switch evento {
            case .esfuerzoMuyAlto, .molestiaReportada:
                // La próxima sesión exigente baja de intensidad. Una
                // sola: no se rediseña la semana por un mal día.
                if let siguiente = proximaExigente(almacen, hoy: hoy, calendario: calendario) {
                    cambios.append(.convertirEnFacil(programadoID: siguiente.id))
                }
            case .variasAusencias:
                // Nada de compensar kilómetros (§41). Lo único sensato
                // es aliviar la próxima calidad.
                if let siguiente = proximaExigente(almacen, hoy: hoy, calendario: calendario),
                   siguiente.rol != .tiradaLarga {
                    cambios.append(.reducir(programadoID: siguiente.id, factor: 0.8))
                }
            default:
                continue
            }
        }
        // Deduplicar por sesión: una sesión, una operación.
        var vistas = Set<UUID>()
        let unicos = cambios.filter { vistas.insert($0.programadoID).inserted }
        return ValidadorDeCoach.validas(unicos, en: almacen, hoy: hoy, calendario: calendario)
    }

    static func proximaExigente(_ almacen: AlmacenV2, hoy: DiaLocal,
                                calendario: Calendar = .current) -> EntrenamientoProgramado? {
        almacen.todosLosProgramados
            .filter { programado in
                guard let dia = programado.dia, dia >= hoy,
                      programado.resolucion == .pendiente else { return false }
                return programado.rol == .calidadPrincipal
                    || programado.rol == .calidadSecundaria
                    || programado.rol == .tiradaLarga
            }
            .sorted { ($0.dia ?? hoy) < ($1.dia ?? hoy) }
            .first
    }
}
