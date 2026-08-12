import Foundation

// CONTENIDO deportivo v1 de los arquetipos grandes (Mejorar 5K, Media
// Maratón, Maratón). Generado DECLARATIVAMENTE — cada número sale de
// una progresión explícita, no de un JSON tipeado a mano.
//
// Principios aplicados (citas completas en METODOLOGIA.md):
// - Distribución ~80/20: una sola sesión de calidad semanal; el resto
//   del volumen es fácil/recuperación (Seiler 2010).
// - Descarga cada 4ª semana: volumen de la larga −25-30% (consenso de
//   periodización, declarado como consenso).
// - Taper: 2 semanas en media maratón y 3 en maratón, reduciendo
//   volumen 40-60% y MANTENIENDO intensidad (Bosquet et al. 2007,
//   meta-análisis).
// - Larga: progresión ≤ +1-2 km/semana con tope (30 km en maratón,
//   18 km en media) — consenso; el tope evita que la larga domine el
//   volumen semanal.
// - Zonas SIMBÓLICAS (fácil/umbral/intervalo/maratón): las resuelve
//   MetodologiaMaratoniaV1 contra el baseline al adoptar; sin
//   baseline quedan simbólicas y el plan funciona igual.
//
// La ESTRUCTURA semanal es contenido original de Maratonia aplicando
// esos principios — nada copiado de planes propietarios (Runna u
// otros: solo benchmark de FORMA de producto).

enum ContenidoPlanes {

    // MARK: Helpers declarativos

    private static func seg(_ nombre: String, km: Double? = nil,
                            min: Int? = nil, zona: TipoRitmo? = nil) -> SegmentoBase {
        SegmentoBase(nombre: nombre, distanciaKm: km,
                     duracionSegundos: min.map { $0 * 60 },
                     ritmoMinSegKm: nil, ritmoMaxSegKm: nil, tipoRitmo: zona)
    }

    private static func facil(_ dia: Int, km: Double,
                              nombre: String = "Rodaje suave") -> EntrenamientoBase {
        EntrenamientoBase(diaDeSemana: dia, tipo: .facil, nombre: nombre,
                          descripcion: "Rodaje continuo cómodo: tenés que poder hablar.",
                          segmentos: [seg("Rodaje", km: km, zona: .facil)])
    }

    private static func recuperacion(_ dia: Int, km: Double) -> EntrenamientoBase {
        EntrenamientoBase(diaDeSemana: dia, tipo: .recuperacion, nombre: "Recuperación",
                          descripcion: "Trote muy suave. Si el cuerpo pide caminar, se camina.",
                          segmentos: [seg("Trote suave", km: km, zona: .recuperacion)])
    }

    private static func larga(_ dia: Int, km: Double,
                              finalMaraton: Double? = nil) -> EntrenamientoBase {
        var segmentos = [seg("Larga cómoda", km: km - (finalMaraton ?? 0), zona: .facil)]
        if let finalMaraton {
            segmentos.append(seg("Final a ritmo de maratón", km: finalMaraton, zona: .maraton))
        }
        return EntrenamientoBase(
            diaDeSemana: dia, tipo: .largo, nombre: "Tirada larga",
            descripcion: finalMaraton == nil
                ? "La sesión que construye tu resistencia. Ritmo conversable de principio a fin."
                : "Larga con final a ritmo objetivo: los últimos kilómetros se corren a ritmo de maratón.",
            segmentos: segmentos)
    }

    private static func umbral(_ dia: Int, minutos: Int) -> EntrenamientoBase {
        EntrenamientoBase(
            diaDeSemana: dia, tipo: .umbral, nombre: "Umbral \(minutos)′",
            descripcion: "Bloque sostenido a ritmo de umbral: exigente pero controlado (~el ritmo que aguantarías 1 hora en carrera).",
            segmentos: [seg("Calentamiento", km: 1.5, zona: .facil),
                        seg("Bloque umbral", min: minutos, zona: .umbral),
                        seg("Vuelta a la calma", km: 1, zona: .recuperacion)])
    }

    private static func intervalos(_ dia: Int, repeticiones: Int,
                                   minutosCada: Int) -> EntrenamientoBase {
        var segmentos = [seg("Calentamiento", km: 2, zona: .facil)]
        for numero in 1...repeticiones {
            segmentos.append(seg("Intervalo \(numero)", min: minutosCada, zona: .intervalo))
            segmentos.append(seg("Trote de pausa", min: 2, zona: .recuperacion))
        }
        segmentos.append(seg("Vuelta a la calma", km: 1, zona: .recuperacion))
        return EntrenamientoBase(
            diaDeSemana: dia, tipo: .series,
            nombre: "\(repeticiones)×\(minutosCada)′ fuertes",
            descripcion: "Intervalos a ritmo de 3-5K con trote de recuperación entre cada uno.",
            segmentos: segmentos)
    }

    private static func carrera(_ dia: Int, km: Double, nombre: String) -> EntrenamientoBase {
        EntrenamientoBase(diaDeSemana: dia, tipo: .ritmoCarrera, nombre: nombre,
                          descripcion: "El día que preparaste. Salí conservador y cerrá fuerte.",
                          segmentos: [seg(nombre, km: km)])
    }

    private static func activacion(_ dia: Int) -> EntrenamientoBase {
        EntrenamientoBase(
            diaDeSemana: dia, tipo: .facil, nombre: "Activación",
            descripcion: "Rodaje corto con 3 cambios de ritmo de 1′ para llegar despierto, no cansado.",
            segmentos: [seg("Rodaje", km: 3, zona: .facil),
                        seg("Cambio de ritmo 1", min: 1, zona: .umbral),
                        seg("Cambio de ritmo 2", min: 1, zona: .umbral),
                        seg("Cambio de ritmo 3", min: 1, zona: .umbral)])
    }

    /// Rodaje medio de mitad de semana: más largo que un rodaje suelto
    /// pero sin ser una segunda tirada larga. Aparece solo en los
    /// planes de más volumen, donde el tiempo en pie importa.
    private static func medioLargo(_ dia: Int, km: Double) -> EntrenamientoBase {
        EntrenamientoBase(
            diaDeSemana: dia, tipo: .facil, nombre: "Rodaje medio",
            descripcion: "Rodaje más largo de lo habitual, todo cómodo: suma tiempo en pie sin la fatiga de una larga.",
            segmentos: [seg("Rodaje medio", km: km, zona: .facil)])
    }

    /// Bloque continuo al ritmo objetivo de la carrera. Es la sesión
    /// más específica que existe: enseña el ritmo que vas a correr.
    private static func ritmoObjetivo(_ dia: Int, km: Double, nombre: String,
                                      zona: TipoRitmo) -> EntrenamientoBase {
        EntrenamientoBase(
            diaDeSemana: dia, tipo: .tempo, nombre: nombre,
            descripcion: "Bloque continuo al ritmo que querés correr el día de la carrera. Sirve tanto para las piernas como para la cabeza.",
            segmentos: [seg("Calentamiento", km: 2, zona: .facil),
                        seg("Al ritmo objetivo", km: km, zona: zona),
                        seg("Vuelta a la calma", km: 1, zona: .recuperacion)])
    }

    /// Semana estándar de 5 sesiones (recortable a 3-5 por rol):
    /// d1 recuperación, d2 calidad, d4 fácil, d6 fácil corto, d7 larga.
    private static func semana(_ numero: Int, calidad: EntrenamientoBase,
                               kmFacil: Double, kmLarga: Double,
                               finalMaraton: Double? = nil,
                               fase: TipoSemana? = nil) -> SemanaBase {
        SemanaBase(numero: numero, entrenamientos: [
            recuperacion(1, km: max(3, kmFacil - 2)),
            calidad,
            facil(4, km: kmFacil),
            facil(6, km: max(4, kmFacil - 1)),
            larga(7, km: kmLarga, finalMaraton: finalMaraton),
        ], fase: fase)
    }

    /// Semana de 6 sesiones con DOS calidades, para los planes de
    /// rendimiento: solo se ofrece cuando la elegibilidad confirma que
    /// hay base para sostenerla.
    private static func semanaDoble(_ numero: Int, calidad: EntrenamientoBase,
                                    segundaCalidad: EntrenamientoBase,
                                    kmFacil: Double, kmMedio: Double, kmLarga: Double,
                                    finalMaraton: Double? = nil,
                                    fase: TipoSemana? = nil) -> SemanaBase {
        SemanaBase(numero: numero, entrenamientos: [
            recuperacion(1, km: max(4, kmFacil - 2)),
            calidad,
            medioLargo(3, km: kmMedio),
            segundaCalidad,
            facil(6, km: kmFacil),
            larga(7, km: kmLarga, finalMaraton: finalMaraton),
        ], fase: fase)
    }

    /// Reparto ESTRUCTURAL de fases sobre las semanas de construcción.
    /// No es metodología: es cómo se nombra el bloque para que el
    /// corredor entienda por qué esta semana es como es.
    /// - descarga y pico mandan sobre todo lo demás;
    /// - el primer ~30 % es base, hasta ~65 % construcción, el resto
    ///   específica (el trabajo más parecido a la carrera).
    private static func fase(_ numero: Int, construccion: Int,
                             esDescarga: Bool, esPico: Bool) -> TipoSemana {
        if esDescarga { return .descarga }
        if esPico { return .pico }
        let fraccion = Double(numero) / Double(max(1, construccion))
        if fraccion <= 0.3 { return .base }
        if fraccion <= 0.65 { return .construccion }
        return .especifica
    }

    // MARK: Mejorar 5K — 8 semanas

    static func mejorar5K() -> PlanBase {
        var semanas: [SemanaBase] = []
        for numero in 1...7 {
            let esDescarga = numero == 4
            // Calidad alternada: umbral (impares) / intervalos (pares).
            // En descarga la calidad se acorta, no desaparece (Bosquet:
            // la intensidad se mantiene, baja el volumen).
            let calidad = numero % 2 == 1
                ? umbral(2, minutos: esDescarga ? 12 : min(15 + (numero / 2) * 3, 24))
                : intervalos(2, repeticiones: esDescarga ? 4 : 5 + numero / 4, minutosCada: 3)
            let larga = esDescarga ? 7.0 : min(8 + Double(numero), 12)
            semanas.append(semana(numero, calidad: calidad,
                                  kmFacil: esDescarga ? 5 : 6, kmLarga: larga,
                                  fase: fase(numero, construccion: 7,
                                             esDescarga: esDescarga, esPico: numero == 7)))
        }
        semanas.append(SemanaBase(numero: 8, entrenamientos: [
            facil(2, km: 5),
            activacion(4),
            carrera(7, km: 5, nombre: "5K a fondo"),
        ], fase: .semanaDeCarrera))
        return PlanBase(
            id: "mejorar-5k", version: 1, nombre: "Mejorar mis 5K",
            descripcion: "8 semanas con una sesión de calidad semanal (umbral e intervalos alternados), rodajes fáciles y tirada larga progresiva. Cierra con un 5K a fondo.",
            distanciaObjetivoKm: 5, semanasTotales: 8, diasPorSemana: 4,
            provisional: false, semanas: semanas)
    }

    // MARK: Media maratón — 12 semanas

    static func mediaMaraton() -> PlanBase {
        var semanas: [SemanaBase] = []
        // Larga: 10 → 18 km con descargas en 4 y 8; pico en semana 10.
        let largas: [Double] = [10, 11, 12, 10, 13, 14, 15, 12, 16, 18]
        for numero in 1...10 {
            let esDescarga = numero == 4 || numero == 8
            let calidad = numero < 3
                ? facil(2, km: 7, nombre: "Rodaje medio")
                : umbral(2, minutos: esDescarga ? 15 : min(18 + (numero - 3) * 2, 28))
            semanas.append(semana(numero, calidad: calidad,
                                  kmFacil: esDescarga ? 6 : 7,
                                  kmLarga: largas[numero - 1],
                                  fase: fase(numero, construccion: 10,
                                             esDescarga: esDescarga, esPico: numero == 10)))
        }
        // Taper de 2 semanas (Bosquet 2007): volumen −40-60%, la
        // intensidad se mantiene con toques cortos.
        semanas.append(SemanaBase(numero: 11, entrenamientos: [
            umbral(2, minutos: 15),
            facil(4, km: 6),
            larga(7, km: 12),
        ], fase: .taper))
        semanas.append(SemanaBase(numero: 12, entrenamientos: [
            facil(2, km: 5),
            activacion(4),
            carrera(7, km: 21.1, nombre: "Media maratón"),
        ], fase: .semanaDeCarrera))
        return PlanBase(
            id: "media-maraton", version: 1, nombre: "Media maratón",
            descripcion: "12 semanas: larga progresiva hasta 18 km con descargas, umbral semanal desde la semana 3 y taper de 2 semanas.",
            distanciaObjetivoKm: 21.1, semanasTotales: 12, diasPorSemana: 4,
            provisional: false, semanas: semanas)
    }

    // MARK: Maratón — 16 semanas

    static func maraton() -> PlanBase {
        var semanas: [SemanaBase] = []
        // Larga: 12 → 30 km (tope), descargas en 4, 8 y 12.
        let largas: [Double] = [12, 14, 16, 12, 18, 20, 22, 16, 24, 26, 28, 20, 30]
        for numero in 1...13 {
            let esDescarga = numero == 4 || numero == 8 || numero == 12
            let calidad = umbral(2, minutos: esDescarga ? 15 : min(20 + numero, 32))
            // Final a ritmo de maratón dentro de la larga desde la
            // semana 9 (las de descarga van todas cómodas).
            let finalMaraton: Double? = (numero >= 9 && !esDescarga) ? 4 : nil
            // kmFacil 8 → 11: la tirada larga llegaba a ocupar el 51 %
            // del volumen semanal en el pico (30 km sobre 59). Sube el
            // volumen COMPLEMENTARIO — la progresión de fondos no se
            // toca, porque pasó la auditoría de saltos de sesión.
            semanas.append(semana(numero, calidad: calidad,
                                  kmFacil: esDescarga ? 8 : 11,
                                  kmLarga: largas[numero - 1],
                                  finalMaraton: finalMaraton,
                                  fase: fase(numero, construccion: 13,
                                             esDescarga: esDescarga, esPico: numero == 13)))
        }
        // Taper de 3 semanas (Bosquet 2007).
        semanas.append(SemanaBase(numero: 14, entrenamientos: [
            umbral(2, minutos: 18),
            facil(4, km: 7),
            larga(7, km: 20),
        ], fase: .taper))
        semanas.append(SemanaBase(numero: 15, entrenamientos: [
            umbral(2, minutos: 12),
            facil(4, km: 6),
            larga(7, km: 12),
        ], fase: .taper))
        semanas.append(SemanaBase(numero: 16, entrenamientos: [
            facil(2, km: 5),
            activacion(4),
            carrera(7, km: 42.195, nombre: "Maratón"),
        ], fase: .semanaDeCarrera))
        return PlanBase(
            id: "maraton", version: 1, nombre: "Maratón",
            descripcion: "16 semanas: larga hasta 30 km con descargas cada 4ª semana, umbral semanal, finales a ritmo de maratón desde la semana 9 y taper de 3 semanas.",
            distanciaObjetivoKm: 42.195, semanasTotales: 16, diasPorSemana: 4,
            provisional: false, semanas: semanas)
    }

    // MARK: Mejorar 10K — 10 semanas

    /// Misma lógica que Mejorar 5K con más volumen y una larga que
    /// llega a 16 km: para bajar en 10K hace falta base aeróbica, no
    /// solo series.
    static func mejorar10K() -> PlanBase {
        var semanas: [SemanaBase] = []
        let largas: [Double] = [10, 11, 12, 9, 13, 14, 15, 16]
        for numero in 1...8 {
            let esDescarga = numero == 4
            let calidad = numero % 2 == 1
                ? umbral(2, minutos: esDescarga ? 14 : min(18 + (numero / 2) * 3, 28))
                : intervalos(2, repeticiones: esDescarga ? 4 : 5 + numero / 4, minutosCada: 3)
            // kmFacil 7 → 8: con 3 días la tirada larga rozaba el 45 %
            // del volumen semanal. Sube el complemento, no baja la larga.
            semanas.append(semana(numero, calidad: calidad,
                                  kmFacil: esDescarga ? 7 : 8,
                                  kmLarga: largas[numero - 1],
                                  fase: fase(numero, construccion: 8,
                                             esDescarga: esDescarga, esPico: numero == 8)))
        }
        semanas.append(SemanaBase(numero: 9, entrenamientos: [
            umbral(2, minutos: 14),
            facil(4, km: 6),
            larga(7, km: 10),
        ], fase: .taper))
        semanas.append(SemanaBase(numero: 10, entrenamientos: [
            facil(2, km: 5),
            activacion(4),
            carrera(7, km: 10, nombre: "10K a fondo"),
        ], fase: .semanaDeCarrera))
        return PlanBase(
            id: "mejorar-10k", version: 1, nombre: "Mejorar mis 10K",
            descripcion: "10 semanas alternando umbral e intervalos, con larga progresiva hasta 16 km y taper de 2 semanas. Cierra con un 10K a fondo.",
            distanciaObjetivoKm: 10, semanasTotales: 10, diasPorSemana: 4,
            provisional: false, semanas: semanas)
    }

    // MARK: Mejorar media maratón — 12 semanas

    /// Diferencia real con "Primera media": la calidad deja de ser solo
    /// umbral y aparece el trabajo AL RITMO de media, que es lo que
    /// enseña a sostener la marca objetivo.
    static func mejorarMedia() -> PlanBase {
        var semanas: [SemanaBase] = []
        let largas: [Double] = [12, 13, 14, 11, 15, 16, 17, 13, 18, 20]
        for numero in 1...10 {
            let esDescarga = numero == 4 || numero == 8
            // Desde la semana 6 se alterna umbral con bloques a ritmo
            // de media: específico, no más duro porque sí.
            let calidad: EntrenamientoBase
            if numero >= 6 && numero % 2 == 0 && !esDescarga {
                calidad = ritmoObjetivo(2, km: Double(min(6 + numero / 2, 10)),
                                        nombre: "Ritmo de media \(min(6 + numero / 2, 10)) km",
                                        zona: .umbral)
            } else {
                calidad = umbral(2, minutos: esDescarga ? 16 : min(20 + numero * 2, 32))
            }
            semanas.append(semana(numero, calidad: calidad,
                                  kmFacil: esDescarga ? 7 : 9,
                                  kmLarga: largas[numero - 1],
                                  fase: fase(numero, construccion: 10,
                                             esDescarga: esDescarga, esPico: numero == 10)))
        }
        semanas.append(SemanaBase(numero: 11, entrenamientos: [
            umbral(2, minutos: 16),
            facil(4, km: 7),
            larga(7, km: 13),
        ], fase: .taper))
        semanas.append(SemanaBase(numero: 12, entrenamientos: [
            facil(2, km: 5),
            activacion(4),
            carrera(7, km: 21.1, nombre: "Media maratón"),
        ], fase: .semanaDeCarrera))
        return PlanBase(
            id: "mejorar-media", version: 1, nombre: "Mejorar mi media",
            descripcion: "12 semanas con umbral y bloques al ritmo objetivo de media desde la semana 6, larga hasta 20 km con dos descargas y taper de 2 semanas.",
            distanciaObjetivoKm: 21.1, semanasTotales: 12, diasPorSemana: 5,
            provisional: false, semanas: semanas)
    }

    // MARK: Media maratón — rendimiento — 14 semanas

    /// DOS sesiones de calidad por semana y rodaje medio de mitad de
    /// semana. Solo se ofrece si la elegibilidad confirma base real:
    /// esta carga sobre alguien que corre 25 km/semana es una lesión.
    static func mediaRendimiento() -> PlanBase {
        var semanas: [SemanaBase] = []
        let largas: [Double] = [14, 15, 16, 12, 17, 18, 19, 15, 20, 21, 22, 17]
        for numero in 1...12 {
            let esDescarga = numero == 4 || numero == 8 || numero == 12
            let principal = umbral(2, minutos: esDescarga ? 18 : min(22 + numero * 2, 38))
            let segunda: EntrenamientoBase = numero % 2 == 0
                ? intervalos(5, repeticiones: esDescarga ? 4 : 6, minutosCada: 3)
                : ritmoObjetivo(5, km: Double(min(6 + numero / 2, 12)),
                                nombre: "Ritmo de media \(min(6 + numero / 2, 12)) km",
                                zona: .umbral)
            semanas.append(semanaDoble(numero, calidad: principal, segundaCalidad: segunda,
                                       kmFacil: esDescarga ? 8 : 10,
                                       kmMedio: esDescarga ? 10 : 13,
                                       kmLarga: largas[numero - 1],
                                       fase: fase(numero, construccion: 12,
                                                  esDescarga: esDescarga, esPico: numero == 11)))
        }
        semanas.append(SemanaBase(numero: 13, entrenamientos: [
            umbral(2, minutos: 18),
            facil(4, km: 8),
            larga(7, km: 14),
        ], fase: .taper))
        semanas.append(SemanaBase(numero: 14, entrenamientos: [
            facil(2, km: 6),
            activacion(4),
            carrera(7, km: 21.1, nombre: "Media maratón"),
        ], fase: .semanaDeCarrera))
        return PlanBase(
            id: "media-rendimiento", version: 1, nombre: "Media · rendimiento",
            descripcion: "14 semanas de alta especificidad: dos sesiones de calidad por semana, rodaje medio, larga hasta 22 km y taper de 2 semanas. Pide base real.",
            distanciaObjetivoKm: 21.1, semanasTotales: 14, diasPorSemana: 6,
            provisional: false, semanas: semanas)
    }

    // MARK: Mejorar maratón — 18 semanas

    static func mejorarMaraton() -> PlanBase {
        var semanas: [SemanaBase] = []
        // Larga: 16 → 32 km (tope), descargas en 4, 8, 12.
        let largas: [Double] = [16, 18, 20, 15, 22, 24, 26, 18, 28, 30, 32, 22, 30, 24, 18]
        for numero in 1...15 {
            let esDescarga = numero == 4 || numero == 8 || numero == 12
            let calidad = umbral(2, minutos: esDescarga ? 18 : min(24 + numero, 38))
            // Final a ritmo de maratón desde la semana 7: la sesión que
            // enseña el ritmo con las piernas ya cansadas.
            let finalMaraton: Double? = (numero >= 7 && !esDescarga)
                ? min(6 + Double(numero - 7), 12) : nil
            // kmFacil 10 → 12, mismo motivo que en Primera Maratón
            // (la larga ocupaba el 48 % del pico).
            semanas.append(semana(numero, calidad: calidad,
                                  kmFacil: esDescarga ? 9 : 12,
                                  kmLarga: largas[numero - 1],
                                  finalMaraton: finalMaraton,
                                  fase: fase(numero, construccion: 15,
                                             esDescarga: esDescarga, esPico: numero == 11)))
        }
        semanas.append(SemanaBase(numero: 16, entrenamientos: [
            umbral(2, minutos: 20),
            facil(4, km: 8),
            larga(7, km: 20),
        ], fase: .taper))
        semanas.append(SemanaBase(numero: 17, entrenamientos: [
            umbral(2, minutos: 12),
            facil(4, km: 6),
            larga(7, km: 12),
        ], fase: .taper))
        semanas.append(SemanaBase(numero: 18, entrenamientos: [
            facil(2, km: 5),
            activacion(4),
            carrera(7, km: 42.195, nombre: "Maratón"),
        ], fase: .semanaDeCarrera))
        return PlanBase(
            id: "mejorar-maraton", version: 1, nombre: "Mejorar mi maratón",
            descripcion: "18 semanas: larga hasta 32 km con finales a ritmo de maratón cada vez más largos desde la semana 7, umbral semanal, tres descargas y taper de 3 semanas.",
            distanciaObjetivoKm: 42.195, semanasTotales: 18, diasPorSemana: 5,
            provisional: false, semanas: semanas)
    }

    // MARK: Maratón — rendimiento — 18 semanas

    static func maratonRendimiento() -> PlanBase {
        var semanas: [SemanaBase] = []
        let largas: [Double] = [18, 20, 22, 16, 24, 26, 28, 20, 30, 32, 32, 22, 32, 26, 20]
        for numero in 1...15 {
            let esDescarga = numero == 4 || numero == 8 || numero == 12
            let principal = umbral(2, minutos: esDescarga ? 20 : min(26 + numero, 40))
            let segunda: EntrenamientoBase = numero >= 6 && !esDescarga
                ? ritmoObjetivo(5, km: Double(min(8 + numero, 18)),
                                nombre: "Ritmo de maratón \(min(8 + numero, 18)) km",
                                zona: .maraton)
                : intervalos(5, repeticiones: esDescarga ? 4 : 6, minutosCada: 3)
            let finalMaraton: Double? = (numero >= 7 && !esDescarga)
                ? min(8 + Double(numero - 7), 14) : nil
            semanas.append(semanaDoble(numero, calidad: principal, segundaCalidad: segunda,
                                       kmFacil: esDescarga ? 10 : 12,
                                       kmMedio: esDescarga ? 12 : 16,
                                       kmLarga: largas[numero - 1],
                                       finalMaraton: finalMaraton,
                                       fase: fase(numero, construccion: 15,
                                                  esDescarga: esDescarga, esPico: numero == 11)))
        }
        semanas.append(SemanaBase(numero: 16, entrenamientos: [
            umbral(2, minutos: 22),
            facil(4, km: 10),
            larga(7, km: 22),
        ], fase: .taper))
        semanas.append(SemanaBase(numero: 17, entrenamientos: [
            umbral(2, minutos: 14),
            facil(4, km: 7),
            larga(7, km: 13),
        ], fase: .taper))
        semanas.append(SemanaBase(numero: 18, entrenamientos: [
            facil(2, km: 6),
            activacion(4),
            carrera(7, km: 42.195, nombre: "Maratón"),
        ], fase: .semanaDeCarrera))
        return PlanBase(
            id: "maraton-rendimiento", version: 1, nombre: "Maratón · rendimiento",
            descripcion: "18 semanas de máxima especificidad: dos calidades por semana, bloques largos a ritmo de maratón, rodaje medio, larga hasta 32 km y taper de 3 semanas. Pide base real y sin molestias.",
            distanciaObjetivoKm: 42.195, semanasTotales: 18, diasPorSemana: 6,
            provisional: false, semanas: semanas)
    }
}
