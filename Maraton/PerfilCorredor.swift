import Foundation

// PERFIL REAL DEL CORREDOR + HISTORIAL + ELEGIBILIDAD.
//
// Las tres entradas del motor adaptativo que hoy no existían:
//
//   1. ResumenHistorial  — qué viene haciendo, en ventanas de 7/28/42
//      días, calculado desde las sesiones de Salud. Descriptivo puro:
//      km, salidas, tirada más larga, consistencia, pausas. NINGUNA
//      métrica fisiológica inventada (nada de "readiness" ni "carga
//      aguda/crónica" sin fuente).
//
//   2. ActividadDetectada — la propuesta que la app le muestra al
//      corredor para CONFIRMAR o CORREGIR, en vez de preguntarle algo
//      que ya sabemos. Ausencia de datos NUNCA significa "sedentario":
//      significa "no sabemos, preguntemos".
//
//   3. Elegibilidad — si el objetivo elegido es razonable con lo que
//      el corredor trae. Determinístico y explicable: cada veredicto
//      viene con sus motivos, y ninguno es un insulto.
//
// Todo acá es lógica PURA (Foundation): sin HealthKit, sin SwiftUI,
// sin red. Los lectores de Salud viven en Progreso.swift y le pasan
// las sesiones ya reducidas a SesionMetrica.

// MARK: - Ventanas de historial (§5)

/// Los números descriptivos de una ventana temporal. Todo son cuentas
/// y sumas sobre lo efectivamente corrido — nada estimado.
struct ResumenVentana: Equatable {
    var dias: Int
    var km: Double = 0
    var minutos: Double = 0
    var salidas: Int = 0
    var tiradaMasLargaKm: Double = 0
    /// Días de calendario distintos con al menos una salida (dos
    /// carreras el mismo día no son dos días de entrenamiento).
    var diasConCarrera: Int = 0
    /// Hueco más grande sin correr dentro de la ventana, en días,
    /// contando desde el inicio de la ventana y hasta hoy.
    var mayorPausaDias: Int = 0
    /// Semanas de la ventana con al menos una salida.
    var semanasConSalida: Int = 0
    var semanasEnLaVentana: Int = 0
    /// Salidas notablemente largas para ESTE corredor: ≥ 1.5× la
    /// mediana de la ventana. Descriptivo, no fisiológico.
    var fondos: Int = 0
    /// Salidas notablemente rápidas para ESTE corredor: ritmo ≥ 8 %
    /// más rápido que su mediana de la ventana. También descriptivo.
    var salidasRapidas: Int = 0

    var semanas: Double { max(1, Double(dias) / 7) }
    var kmPorSemana: Double { km / semanas }
    var salidasPorSemana: Double { Double(salidas) / semanas }
    var minutosPorSemana: Double { minutos / semanas }

    /// Fracción de semanas de la ventana con actividad (0…1).
    var consistencia: Double {
        guard semanasEnLaVentana > 0 else { return 0 }
        return Double(semanasConSalida) / Double(semanasEnLaVentana)
    }

    var estaVacia: Bool { salidas == 0 }
}

enum ResumenHistorial {

    /// Las ventanas que el motor mira. 42 días entra porque un bloque
    /// de 6 semanas es lo mínimo para ver una tendencia sin que un
    /// resfrío la borre.
    static let ventanasEstandar = [7, 28, 42]

    /// Reduce las sesiones a los números de una ventana que TERMINA
    /// hoy. `sesiones` puede venir de cualquier app que guarde en
    /// Salud — es lo corrido, no lo planificado.
    static func ventana(_ sesiones: [SesionMetrica], dias: Int, hoy: Date,
                        calendario: Calendar = .current) -> ResumenVentana {
        var resumen = ResumenVentana(dias: max(1, dias))
        guard dias > 0,
              let desde = calendario.date(byAdding: .day, value: -dias, to: hoy)
        else { return resumen }

        let enVentana = sesiones
            .filter { $0.fecha > desde && $0.fecha <= hoy && $0.metros > 0 }
            .sorted { $0.fecha < $1.fecha }
        resumen.semanasEnLaVentana = max(1, Int((Double(dias) / 7).rounded(.up)))
        guard !enVentana.isEmpty else {
            resumen.mayorPausaDias = dias
            return resumen
        }

        resumen.salidas = enVentana.count
        resumen.km = enVentana.reduce(0) { $0 + $1.metros } / 1000
        resumen.minutos = enVentana.reduce(0) { $0 + $1.segundos } / 60
        resumen.tiradaMasLargaKm = (enVentana.map(\.metros).max() ?? 0) / 1000

        let diasDistintos = Set(enVentana.map { DiaLocal(fecha: $0.fecha, calendario: calendario) })
        resumen.diasConCarrera = diasDistintos.count

        let semanas = Set(enVentana.compactMap {
            calendario.dateInterval(of: .weekOfYear, for: $0.fecha)?.start
        })
        resumen.semanasConSalida = min(semanas.count, resumen.semanasEnLaVentana)

        resumen.mayorPausaDias = mayorPausa(enVentana, desde: desde, hasta: hoy,
                                            calendario: calendario)

        // Fondos y salidas rápidas: relativos al propio corredor.
        let distancias = enVentana.map(\.metros).sorted()
        if let medianaDistancia = mediana(distancias), medianaDistancia > 0 {
            resumen.fondos = enVentana.filter { $0.metros >= medianaDistancia * 1.5 }.count
        }
        let ritmos = enVentana.compactMap { sesion -> Double? in
            guard sesion.metros >= 1000, sesion.segundos >= 300 else { return nil }
            return sesion.segundos / (sesion.metros / 1000)
        }.sorted()
        if let medianaRitmo = mediana(ritmos), medianaRitmo > 0 {
            resumen.salidasRapidas = ritmos.filter { $0 <= medianaRitmo * 0.92 }.count
        }
        return resumen
    }

    /// Las tres ventanas estándar de una vez.
    static func ventanas(_ sesiones: [SesionMetrica], hoy: Date,
                         calendario: Calendar = .current) -> [Int: ResumenVentana] {
        Dictionary(uniqueKeysWithValues: ventanasEstandar.map {
            ($0, ventana(sesiones, dias: $0, hoy: hoy, calendario: calendario))
        })
    }

    /// Hueco más grande sin correr: incluye el tramo desde el inicio de
    /// la ventana hasta la primera salida y el de la última hasta hoy
    /// (dejar de correr hace tres semanas ES la pausa relevante).
    private static func mayorPausa(_ sesiones: [SesionMetrica], desde: Date, hasta: Date,
                                   calendario: Calendar) -> Int {
        var mayor = 0
        var anterior = desde
        for sesion in sesiones {
            let dias = calendario.dateComponents([.day], from: anterior, to: sesion.fecha).day ?? 0
            mayor = max(mayor, dias)
            anterior = sesion.fecha
        }
        let cola = calendario.dateComponents([.day], from: anterior, to: hasta).day ?? 0
        return max(mayor, cola)
    }

    private static func mediana(_ ordenados: [Double]) -> Double? {
        guard !ordenados.isEmpty else { return nil }
        let medio = ordenados.count / 2
        if ordenados.count % 2 == 1 { return ordenados[medio] }
        return (ordenados[medio - 1] + ordenados[medio]) / 2
    }
}

// MARK: - Actividad detectada desde Salud (§4)

/// Lo que la app CREE que el corredor viene haciendo, para que él lo
/// confirme o lo corrija. Nunca se guarda como verdad sin su OK.
struct ActividadDetectada: Equatable {
    var diasPorSemana: Double
    var kmSemanales: Double
    var minutosSemanales: Double
    var tiradaLargaKm: Double
    var salidasConsideradas: Int
    var diasVentana: Int

    /// Convierte lo detectado en el campo del perfil, marcado con su
    /// origen (confirmado por el corredor, o corregido a mano).
    func comoActividad(origen: ActividadActual.Origen, fecha: Date) -> ActividadActual {
        ActividadActual(
            origen: origen, fecha: fecha,
            diasPorSemana: (diasPorSemana * 10).rounded() / 10,
            kmSemanales: (kmSemanales * 10).rounded() / 10,
            minutosSemanales: minutosSemanales.rounded(),
            tiradaLargaKm: (tiradaLargaKm * 10).rounded() / 10)
    }
}

enum DeteccionActividad {

    /// Mínimo para animarse a proponer algo: 4 salidas repartidas en al
    /// menos 3 semanas distintas. Menos que eso no es una rutina, es
    /// ruido — y proponerlo como "tu actividad actual" sería mentir.
    static let salidasMinimas = 4
    static let semanasMinimasConSalida = 3
    static let diasVentana = 42

    /// nil = NO hay datos suficientes. Eso NO significa que el corredor
    /// sea sedentario: significa que hay que preguntarle (§4).
    static func detectar(_ sesiones: [SesionMetrica], hoy: Date,
                         calendario: Calendar = .current) -> ActividadDetectada? {
        let v = ResumenHistorial.ventana(sesiones, dias: diasVentana, hoy: hoy,
                                         calendario: calendario)
        guard v.salidas >= salidasMinimas,
              v.semanasConSalida >= semanasMinimasConSalida else { return nil }
        return ActividadDetectada(
            diasPorSemana: Double(v.diasConCarrera) / v.semanas,
            kmSemanales: v.kmPorSemana,
            minutosSemanales: v.minutosPorSemana,
            tiradaLargaKm: v.tiradaMasLargaKm,
            salidasConsideradas: v.salidas,
            diasVentana: diasVentana)
    }
}

// MARK: - Elegibilidad (§12)

/// Por qué el motor bajó el objetivo a conservador o pidió fase base.
/// Cada motivo es una frase que el corredor puede leer sin ofenderse:
/// describen la situación, no lo califican a él.
enum MotivoElegibilidad: String, Codable, Equatable, CaseIterable {
    case sinHistorial
    case volumenBajo
    case fondoCorto
    case frecuenciaBaja
    case experienciaCorta
    case sinBaseline
    case molestiaDeclarada
    case volviendoDePausa
    case inactividadReciente

    var texto: String {
        switch self {
        case .sinHistorial:
            return String(localized: "Todavía no tenemos historial tuyo de carreras.")
        case .volumenBajo:
            return String(localized: "Tu volumen semanal está por debajo de lo que este objetivo pide.")
        case .fondoCorto:
            return String(localized: "Tu salida más larga reciente queda corta para esta distancia.")
        case .frecuenciaBaja:
            return String(localized: "Estás corriendo menos días por semana de los que este objetivo necesita.")
        case .experienciaCorta:
            return String(localized: "Hace poco que corrés de forma regular.")
        case .sinBaseline:
            return String(localized: "Sin una marca de referencia no se pueden ajustar los ritmos.")
        case .molestiaDeclarada:
            return String(localized: "Declaraste una molestia reciente: vamos con cuidado.")
        case .volviendoDePausa:
            return String(localized: "Estás volviendo después de una pausa.")
        case .inactividadReciente:
            return String(localized: "Pasaste varias semanas sin correr.")
        }
    }
}

/// El veredicto. `elegible` y `elegibleConservador` GENERAN plan;
/// los otros tres no, y explican exactamente qué falta.
enum VeredictoElegibilidad: Equatable {
    case elegible
    /// Se puede, arrancando más abajo de lo que el arquetipo propone.
    case elegibleConservador([MotivoElegibilidad])
    /// Falta base: primero hay que construirla con otro objetivo.
    case requiereFaseBase([MotivoElegibilidad])
    case fechaDemasiadoCerca(semanasDisponibles: Int, semanasMinimas: Int)
    case frecuenciaInsuficiente(diasElegidos: Int, minimo: Int)

    var generaPlan: Bool {
        switch self {
        case .elegible, .elegibleConservador: return true
        default: return false
        }
    }

    var esConservador: Bool {
        if case .elegibleConservador = self { return true }
        return false
    }

    var motivos: [MotivoElegibilidad] {
        switch self {
        case .elegibleConservador(let m), .requiereFaseBase(let m): return m
        default: return []
        }
    }
}

/// Lo que el evaluador necesita saber. Se arma desde el dominio, pero
/// es un struct plano para que los tests no monten medio almacén.
struct EntradaElegibilidad {
    var objetivo: ObjetivoDeportivo
    var semanasDisponibles: Int?      // nil = objetivo sin fecha
    var semanasMinimasDelPlan: Int
    var diasElegidos: Int
    var historial: ResumenVentana?    // ventana de 42 días
    var actividadDeclarada: ActividadActual?
    var tieneBaseline: Bool
    var molestias: EstadoMolestias
    var mesesCorriendoRegular: Int?
    var volviendoDePausa: Bool

    /// Volumen semanal a usar: gana lo MEDIDO sobre lo declarado
    /// (Salud es la fuente de verdad cuando existe, §4), y si no hay
    /// medición se usa lo que el corredor dijo.
    var kmSemanales: Double? {
        if let historial, !historial.estaVacia { return historial.kmPorSemana }
        return actividadDeclarada?.kmSemanales
    }

    var tiradaLargaKm: Double? {
        if let historial, !historial.estaVacia { return historial.tiradaMasLargaKm }
        return actividadDeclarada?.tiradaLargaKm
    }

    var salidasPorSemana: Double? {
        if let historial, !historial.estaVacia {
            return Double(historial.diasConCarrera) / historial.semanas
        }
        return actividadDeclarada?.diasPorSemana
    }
}

/// Requisitos "cómodos" de un objetivo: con esto, el arquetipo se
/// puede correr tal cual. Se derivan de la DISTANCIA (no son números
/// sueltos) y su justificación está en METODOLOGIA.md como DECISIÓN
/// MARATONIA — consenso de entrenamiento, no un paper.
struct RequisitosObjetivo: Equatable {
    var kmSemanales: Double
    var tiradaLargaKm: Double
    var diasPorSemana: Int
    var mesesRegular: Int
    /// Exige una marca de referencia real (rendimiento).
    var exigeBaseline: Bool

    /// Por debajo de este porcentaje del requisito, ya no alcanza con
    /// "arrancar conservador": falta base de verdad.
    static let fraccionPiso = 0.4

    /// TABLA EXPLÍCITA por distancia + intención.
    ///
    /// Reemplaza a la fórmula `factor × distancia`, que era lineal en la
    /// distancia cuando la relación entre volumen de entrenamiento y
    /// distancia objetivo no lo es. Producía dos absurdos simétricos:
    /// para mejorar un 5K pedía 15 km/semana (la mitad de lo que el
    /// propio plan exige en su primera semana) y para un maratón de
    /// rendimiento pedía 4 × 42,195 = 168,8 km/semana, volumen de élite,
    /// para un plan cuyo pico es 100. Además pedía una tirada larga
    /// reciente de 33,8 km: más de lo que ese plan te va a hacer correr
    /// en 18 semanas.
    ///
    /// Los valores de abajo son DECISIÓN MARATONIA (METODOLOGIA.md) y
    /// están ANCLADOS AL PROPIO PLAN: cada requisito de volumen queda
    /// por debajo del volumen de la primera semana del arquetipo que
    /// habilita, y cada requisito de tirada larga queda en el orden de
    /// su primer fondo. La idea es "esto ya lo podés sostener el día
    /// uno", no "ya sos capaz de terminar". Hay un test de catálogo que
    /// verifica esa coherencia contra el contenido real, así que la
    /// tabla no puede volver a divergir del plan en silencio.
    static func para(_ objetivo: ObjetivoDeportivo) -> RequisitosObjetivo {
        switch objetivo {
        // ---- 5K: la puerta de entrada. Completar no exige nada.
        case .primeros5K:
            return RequisitosObjetivo(kmSemanales: 0, tiradaLargaKm: 0,
                                      diasPorSemana: 2, mesesRegular: 0,
                                      exigeBaseline: false)
        case .mejorar5K:
            return RequisitosObjetivo(kmSemanales: 18, tiradaLargaKm: 6,
                                      diasPorSemana: 3, mesesRegular: 3,
                                      exigeBaseline: false)
        // ---- 10K
        case .diez:
            return RequisitosObjetivo(kmSemanales: 10, tiradaLargaKm: 4,
                                      diasPorSemana: 2, mesesRegular: 1,
                                      exigeBaseline: false)
        case .mejorar10K:
            return RequisitosObjetivo(kmSemanales: 22, tiradaLargaKm: 8,
                                      diasPorSemana: 3, mesesRegular: 3,
                                      exigeBaseline: false)
        // ---- 21K: de media maratón para arriba, mínimo 4 días. Con 3
        // la tirada larga pasa del 50 % del volumen semanal y el plan
        // deja de ser un plan de media (ver METODOLOGIA.md).
        case .mediaMaraton:
            return RequisitosObjetivo(kmSemanales: 28, tiradaLargaKm: 10,
                                      diasPorSemana: 4, mesesRegular: 4,
                                      exigeBaseline: false)
        case .mejorarMedia:
            return RequisitosObjetivo(kmSemanales: 30, tiradaLargaKm: 12,
                                      diasPorSemana: 4, mesesRegular: 6,
                                      exigeBaseline: false)
        case .mediaRendimiento:
            return RequisitosObjetivo(kmSemanales: 50, tiradaLargaKm: 14,
                                      diasPorSemana: 5, mesesRegular: 12,
                                      exigeBaseline: true)
        // ---- 42K
        case .maraton:
            return RequisitosObjetivo(kmSemanales: 40, tiradaLargaKm: 12,
                                      diasPorSemana: 4, mesesRegular: 6,
                                      exigeBaseline: false)
        case .mejorarMaraton:
            return RequisitosObjetivo(kmSemanales: 48, tiradaLargaKm: 16,
                                      diasPorSemana: 4, mesesRegular: 9,
                                      exigeBaseline: false)
        case .maratonRendimiento:
            return RequisitosObjetivo(kmSemanales: 65, tiradaLargaKm: 18,
                                      diasPorSemana: 5, mesesRegular: 12,
                                      exigeBaseline: true)
        }
    }
}

enum EvaluadorElegibilidad {

    /// Determinístico y en un orden fijo: primero los bloqueos duros
    /// (que no dependen de cuánto corre), después la severidad.
    ///
    /// Filosofía: el objetivo del corredor NO se descarta por
    /// capricho. La app solo dice que no cuando decir que sí sería
    /// venderle un plan que no se sostiene.
    static func evaluar(_ entrada: EntradaElegibilidad) -> VeredictoElegibilidad {
        let requisitos = RequisitosObjetivo.para(entrada.objetivo)

        // ---- Bloqueo 1: la fecha no da. Comprimir un plan es peor que
        // decir la verdad.
        if let disponibles = entrada.semanasDisponibles,
           disponibles < entrada.semanasMinimasDelPlan {
            return .fechaDemasiadoCerca(semanasDisponibles: disponibles,
                                        semanasMinimas: entrada.semanasMinimasDelPlan)
        }

        // ---- Bloqueo 2: no eligió días suficientes para este objetivo.
        if entrada.diasElegidos < requisitos.diasPorSemana {
            return .frecuenciaInsuficiente(diasElegidos: entrada.diasElegidos,
                                           minimo: requisitos.diasPorSemana)
        }

        // ---- Motivos acumulados.
        var motivos: [MotivoElegibilidad] = []
        var faltaBase = false

        let sinDatos = entrada.kmSemanales == nil && entrada.tiradaLargaKm == nil
        if sinDatos && requisitos.kmSemanales > 0 {
            // Ausencia de datos NO es sedentarismo: es incertidumbre.
            // Se arranca conservador, jamás se bloquea por esto.
            motivos.append(.sinHistorial)
        }

        if requisitos.kmSemanales > 0, let km = entrada.kmSemanales {
            if km < requisitos.kmSemanales * RequisitosObjetivo.fraccionPiso {
                motivos.append(.volumenBajo); faltaBase = true
            } else if km < requisitos.kmSemanales {
                motivos.append(.volumenBajo)
            }
        }

        if requisitos.tiradaLargaKm > 0, let larga = entrada.tiradaLargaKm {
            if larga < requisitos.tiradaLargaKm * RequisitosObjetivo.fraccionPiso {
                motivos.append(.fondoCorto); faltaBase = true
            } else if larga < requisitos.tiradaLargaKm {
                motivos.append(.fondoCorto)
            }
        }

        if let salidas = entrada.salidasPorSemana,
           salidas < Double(requisitos.diasPorSemana) - 0.5 {
            motivos.append(.frecuenciaBaja)
        }

        if requisitos.mesesRegular > 0, let meses = entrada.mesesCorriendoRegular,
           meses < requisitos.mesesRegular {
            motivos.append(.experienciaCorta)
            if meses * 2 < requisitos.mesesRegular { faltaBase = true }
        }

        if let historial = entrada.historial, historial.mayorPausaDias >= 21 {
            motivos.append(.inactividadReciente)
        }

        if entrada.volviendoDePausa { motivos.append(.volviendoDePausa) }

        if entrada.molestias.exigeCautela { motivos.append(.molestiaDeclarada) }

        // ---- Rendimiento: exige base REAL, sin excepciones.
        if entrada.objetivo.intencion == .rendimiento {
            if entrada.molestias.bloqueaRendimiento { faltaBase = true }
            if requisitos.exigeBaseline && !entrada.tieneBaseline {
                motivos.append(.sinBaseline); faltaBase = true
            }
        } else if !entrada.tieneBaseline && entrada.objetivo.intencion == .mejorar {
            // Mejorar sin referencia se puede: los ritmos quedan
            // simbólicos hasta que haya una marca.
            motivos.append(.sinBaseline)
        }

        let unicos = ordenarSinRepetir(motivos)
        if faltaBase { return .requiereFaseBase(unicos) }
        if unicos.isEmpty { return .elegible }
        return .elegibleConservador(unicos)
    }

    /// Sugerencia de por dónde empezar cuando falta base. Determinística
    /// y siempre hacia abajo: nunca propone algo más exigente.
    static func objetivoPuente(para objetivo: ObjetivoDeportivo) -> ObjetivoDeportivo? {
        switch objetivo {
        case .primeros5K: return nil
        case .mejorar5K: return .primeros5K
        case .diez: return .primeros5K
        case .mejorar10K: return .diez
        case .mediaMaraton: return .diez
        case .mejorarMedia, .mediaRendimiento: return .mediaMaraton
        case .maraton: return .mediaMaraton
        case .mejorarMaraton, .maratonRendimiento: return .maraton
        }
    }

    /// Orden estable (el de `allCases`) y sin repetidos: dos reglas
    /// distintas pueden agregar el mismo motivo y el corredor no tiene
    /// por qué leerlo dos veces.
    private static func ordenarSinRepetir(_ motivos: [MotivoElegibilidad]) -> [MotivoElegibilidad] {
        MotivoElegibilidad.allCases.filter(motivos.contains)
    }
}
