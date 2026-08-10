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

    /// Semana estándar de 5 sesiones (recortable a 3-5 por rol):
    /// d1 recuperación, d2 calidad, d4 fácil, d6 fácil corto, d7 larga.
    private static func semana(_ numero: Int, calidad: EntrenamientoBase,
                               kmFacil: Double, kmLarga: Double,
                               finalMaraton: Double? = nil) -> SemanaBase {
        SemanaBase(numero: numero, entrenamientos: [
            recuperacion(1, km: max(3, kmFacil - 2)),
            calidad,
            facil(4, km: kmFacil),
            facil(6, km: max(4, kmFacil - 1)),
            larga(7, km: kmLarga, finalMaraton: finalMaraton),
        ])
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
                                  kmFacil: esDescarga ? 5 : 6, kmLarga: larga))
        }
        semanas.append(SemanaBase(numero: 8, entrenamientos: [
            facil(2, km: 5),
            activacion(4),
            carrera(7, km: 5, nombre: "5K a fondo"),
        ]))
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
                                  kmLarga: largas[numero - 1]))
        }
        // Taper de 2 semanas (Bosquet 2007): volumen −40-60%, la
        // intensidad se mantiene con toques cortos.
        semanas.append(SemanaBase(numero: 11, entrenamientos: [
            umbral(2, minutos: 15),
            facil(4, km: 6),
            larga(7, km: 12),
        ]))
        semanas.append(SemanaBase(numero: 12, entrenamientos: [
            facil(2, km: 5),
            activacion(4),
            carrera(7, km: 21.1, nombre: "Media maratón"),
        ]))
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
            semanas.append(semana(numero, calidad: calidad,
                                  kmFacil: esDescarga ? 6 : 8,
                                  kmLarga: largas[numero - 1],
                                  finalMaraton: finalMaraton))
        }
        // Taper de 3 semanas (Bosquet 2007).
        semanas.append(SemanaBase(numero: 14, entrenamientos: [
            umbral(2, minutos: 18),
            facil(4, km: 7),
            larga(7, km: 20),
        ]))
        semanas.append(SemanaBase(numero: 15, entrenamientos: [
            umbral(2, minutos: 12),
            facil(4, km: 6),
            larga(7, km: 12),
        ]))
        semanas.append(SemanaBase(numero: 16, entrenamientos: [
            facil(2, km: 5),
            activacion(4),
            carrera(7, km: 42.195, nombre: "Maratón"),
        ]))
        return PlanBase(
            id: "maraton", version: 1, nombre: "Maratón",
            descripcion: "16 semanas: larga hasta 30 km con descargas cada 4ª semana, umbral semanal, finales a ritmo de maratón desde la semana 9 y taper de 3 semanas.",
            distanciaObjetivoKm: 42.195, semanasTotales: 16, diasPorSemana: 4,
            provisional: false, semanas: semanas)
    }
}
