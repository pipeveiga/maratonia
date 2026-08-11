import Foundation
import AVFoundation

// Modelo de datos compartido entre la app iOS y la app watchOS.
// Este archivo pertenece a los dos targets: es el "idioma" común
// que viaja del teléfono al reloj vía WatchConnectivity.

struct Plan: Codable, Equatable {
    var nombre: String
    var pistas: [String]
    var avisosFijos: [AvisoFijo]
    var avisosRepetidos: [AvisoRepetido]

    /// Tramos con ritmo objetivo (opcional para que los planes guardados
    /// con versiones viejas sigan cargando sin problema).
    var tramos: [Tramo]? = nil

    /// Avisos por distancia recorrida (requieren el modo entrenamiento,
    /// que es el que mide los kilómetros). Opcional por la misma razón.
    var avisosKm: [AvisoKm]? = nil

    var tramosActivos: [Tramo] { tramos ?? [] }

    var avisosKmActivos: [AvisoKm] { avisosKm ?? [] }

    static let vacio = Plan(nombre: "Mi plan", pistas: [], avisosFijos: [], avisosRepetidos: [])
}

/// Un tramo del plan de entrenamiento. Su META es por distancia
/// (`kilometros`) O por tiempo activo (`duracionSegundos`): si
/// `duracionSegundos` tiene valor positivo, el tramo termina por
/// TIEMPO y `kilometros` se ignora — nunca se traduce "2 minutos" a
/// metros inventados. El rango de ritmo objetivo (segundos por km)
/// aplica igual a los dos: ritmoMinSegKm es el límite rápido (230 =
/// 3:50/km) y ritmoMaxSegKm el lento. Ambos nil = ritmo libre.
struct Tramo: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var nombre: String
    var kilometros: Double
    var ritmoMinSegKm: Int?
    var ritmoMaxSegKm: Int?

    /// Meta por tiempo (opcional para que los planes guardados por
    /// versiones viejas sigan decodificando).
    var duracionSegundos: Int? = nil

    var esPorTiempo: Bool { (duracionSegundos ?? 0) > 0 }

    /// "3 km" o "12 min" según la meta del tramo.
    var metaTexto: String {
        if esPorTiempo { return duracionTexto(duracionSegundos ?? 0) }
        return kilometros == kilometros.rounded()
            ? "\(Int(kilometros)) km"
            : String(format: "%.1f km", kilometros)
    }

    var descripcion: String {
        let meta = metaTexto
        switch (ritmoMinSegKm, ritmoMaxSegKm) {
        case let (rapido?, lento?):
            return "\(meta) a \(formatearRitmo(rapido))–\(formatearRitmo(lento)) /km"
        case let (nil, lento?):
            return "\(meta) a \(formatearRitmo(lento)) /km o mejor"
        case let (rapido?, nil):
            return "\(meta) sin pasar de \(formatearRitmo(rapido)) /km"
        default:
            return String(localized: "\(meta) libre")
        }
    }
}

/// 90 -> "1:30 min" · 120 -> "2 min" · 45 -> "45 s"
func duracionTexto(_ segundos: Int) -> String {
    if segundos < 60 { return "\(segundos) s" }
    if segundos % 60 == 0 { return "\(segundos / 60) min" }
    return "\(segundos / 60):" + String(format: "%02d", segundos % 60) + " min"
}

/// Un aviso disparado por distancia: suena al llegar a `kilometro`, y si
/// `cadaKm` tiene valor, vuelve a sonar cada esa cantidad de km.
struct AvisoKm: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var kilometro: Double
    var cadaKm: Double?
    var texto: String

    var descripcion: String {
        if let cada = cadaKm, cada > 0 {
            return "Cada \(kmTexto(cada)) km, desde el km \(kmTexto(kilometro))"
        }
        return "En el km \(kmTexto(kilometro))"
    }
}

/// 5.0 -> "5" · 7.5 -> "7.5" (String(format:) usa punto siempre)
func kmTexto(_ valor: Double) -> String {
    valor == valor.rounded() ? "\(Int(valor))" : String(format: "%.1f", valor)
}

/// 230 -> "3:50"
func formatearRitmo(_ segundosPorKm: Int) -> String {
    "\(segundosPorKm / 60):" + String(format: "%02d", segundosPorKm % 60)
}

// MARK: - Auto-pausa (lógica pura, compartida por reloj y celu)

/// Decisiones de auto-pausa con histéresis. La pausa exige que TODAS
/// las señales digan "parado": el avance congelado NO alcanza solo,
/// porque la distancia del sensor puede congelarse en movimiento (en
/// un vehículo el reloj no detecta braceo; un hipo del delegate hace
/// lo mismo) y el GPS puede perderse — y ninguna de esas dos cosas es
/// una detención real. La reanudación exige movimiento SOSTENIDO, no
/// una lectura aislada.
enum AutoPausa {

    /// ¿Frenó de verdad? Requiere: ventana completa (~10 s), GPS FRESCO
    /// (una señal vieja no es "parado": es señal vieja), avance del
    /// motor casi nulo, y que el GPS tampoco vea desplazamiento.
    static func debePausar(avanceMetros: Double,
                           ventanaSegundos: Double,
                           desplazamientoGPSMetros: Double?,
                           edadUltimoGPSSegundos: Double?) -> Bool {
        guard ventanaSegundos >= 9 else { return false }
        guard let edad = edadUltimoGPSSegundos, edad <= 5 else { return false }
        guard avanceMetros < 6 else { return false }
        if let gps = desplazamientoGPSMetros, gps >= 8 { return false }
        return true
    }

    /// Histéresis de la reanudación: hacen falta DOS lecturas que
    /// superen el umbral, separadas al menos 1,5 s. Una lectura que
    /// vuelve cerca del punto de pausa (< 60 % del umbral) desarma el
    /// candidato — el ruido alrededor del umbral no produce ping-pong.
    struct DetectorReanudacion {
        private var fechaPrimerMovimiento: Date?

        mutating func procesar(desplazamiento: Double, umbral: Double, fecha: Date) -> Bool {
            guard desplazamiento > umbral else {
                if desplazamiento < umbral * 0.6 {
                    fechaPrimerMovimiento = nil
                }
                return false
            }
            guard let primera = fechaPrimerMovimiento else {
                fechaPrimerMovimiento = fecha
                return false
            }
            if fecha.timeIntervalSince(primera) >= 1.5 {
                fechaPrimerMovimiento = nil
                return true
            }
            return false
        }

        mutating func reiniciar() {
            fechaPrimerMovimiento = nil
        }
    }

    /// ¿Corresponde evaluar reanudación AUTOMÁTICA? Solamente si la
    /// pausa vigente la produjo la auto-pausa: la pausa MANUAL es una
    /// orden del corredor y moverse no la levanta jamás (bug 1 de
    /// build 38: la regla queda en la capa compartida y testeable).
    static func puedeAutoReanudar(pausada: Bool, enPausaAutomatica: Bool) -> Bool {
        pausada && enPausaAutomatica
    }

    /// Decisión de reanudación durante la auto-pausa, con DOS caminos
    /// independientes (cualquiera reanuda):
    /// - DESPLAZAMIENTO sostenido desde el punto de pausa: el
    ///   DetectorReanudacion de siempre, mismos umbrales e histéresis;
    /// - VELOCIDAD GPS sostenida (Doppler, mucho menos ruidosa que la
    ///   posición): dos lecturas ≥ 0,9 m/s separadas ≥ 1,5 s.
    /// El segundo camino cubre el caso real de build 38: con precisión
    /// pobre el umbral de desplazamiento se infla (max(15, precisión))
    /// y un punto de referencia ruidoso podía dejar la sesión pausada
    /// para siempre aunque el corredor ya estuviera moviéndose.
    struct SupervisorReanudacion {
        private var detectorDesplazamiento = DetectorReanudacion()
        private var fechaPrimeraVelocidad: Date?

        /// Caminar decidido; el braceo parado no llega a esto.
        static let velocidadReanuda = 0.9
        /// Por debajo de esto, el candidato de velocidad se desarma.
        static let velocidadDesarma = 0.4

        /// - desplazamiento: distancia al punto de pausa (nil si el
        ///   punto de referencia todavía no existe — el camino de
        ///   velocidad funciona igual).
        /// - velocidad: m/s del GPS (nil si el fix no trae velocidad).
        mutating func procesar(desplazamiento: Double?, velocidad: Double?,
                               umbral: Double, fecha: Date) -> Bool {
            if let desplazamiento,
               detectorDesplazamiento.procesar(desplazamiento: desplazamiento,
                                               umbral: umbral, fecha: fecha) {
                return true
            }
            guard let velocidad, velocidad >= Self.velocidadReanuda else {
                if let velocidad, velocidad < Self.velocidadDesarma {
                    fechaPrimeraVelocidad = nil
                }
                return false
            }
            guard let primera = fechaPrimeraVelocidad else {
                fechaPrimeraVelocidad = fecha
                return false
            }
            if fecha.timeIntervalSince(primera) >= 1.5 {
                fechaPrimeraVelocidad = nil
                return true
            }
            return false
        }

        mutating func reiniciar() {
            detectorDesplazamiento.reiniciar()
            fechaPrimeraVelocidad = nil
        }
    }

    /// Vigilancia del GPS DURANTE la auto-pausa: la reanudación depende
    /// de que el GPS siga entregando, y Core Location puede frenar la
    /// entrega con el usuario quieto (throttling de estacionario). Si
    /// pasaron más de 10 s sin fix y más de 10 s desde el último
    /// empujón, hay que volver a pedir startUpdatingLocation(). Función
    /// pura: los motores le preguntan una vez por segundo.
    static func debeDespertarGPS(edadUltimaSenal: Double?,
                                 edadUltimoEmpujon: Double?) -> Bool {
        let senalVieja = edadUltimaSenal.map { $0 > 10 } ?? true
        let empujonViejo = edadUltimoEmpujon.map { $0 > 10 } ?? true
        return senalVieja && empujonViejo
    }
}

// MARK: - Cumplimiento del entrenamiento planificado

/// El "entrenamiento planificado" son los TRAMOS del plan. Su identidad
/// es esta huella de contenido: si el iPhone reenvía el mismo plan, la
/// huella no cambia (lo cumplido sigue cumplido); si el usuario edita
/// los tramos, cambia la huella y es un entrenamiento nuevo pendiente.
extension Plan {
    var huellaEntrenamiento: String? {
        let tramos = tramosActivos
        guard !tramos.isEmpty else { return nil }
        return tramos
            .map { tramo in
                let base = "\(tramo.nombre)|\(tramo.kilometros)|\(tramo.ritmoMinSegKm ?? -1)|\(tramo.ritmoMaxSegKm ?? -1)"
                // La duración se agrega SOLO si existe: las huellas de
                // planes por distancia no cambian (lo ya cumplido en el
                // reloj sigue cumplido tras actualizar la app).
                guard let duracion = tramo.duracionSegundos else { return base }
                return base + "|t\(duracion)"
            }
            .joined(separator: ";")
    }
}

enum EstadoEntrenamiento: Equatable {
    case sinEntrenamiento   // sin plan, o plan sin tramos
    case pendiente
    case cumplido
}

/// Estado del entrenamiento planificado para la pantalla del reloj.
/// "Cumplido" y "sin entrenamiento" se comportan igual en la Home
/// (Carrera libre primera), pero el plan y su historial siguen ahí.
func estadoDelEntrenamiento(plan: Plan?, huellaCumplida: String?) -> EstadoEntrenamiento {
    guard let plan, let huella = plan.huellaEntrenamiento else { return .sinEntrenamiento }
    return huella == huellaCumplida ? .cumplido : .pendiente
}

/// El plan queda cumplido SOLO si se recorrieron todos los tramos y se
/// guardó la carrera. Carrera libre (0 tramos) o abandono a mitad no
/// marcan nada — criterio conservador y explícito.
func debeMarcarCumplido(tramosTotales: Int, indiceAlcanzado: Int) -> Bool {
    tramosTotales > 0 && indiceAlcanzado >= tramosTotales
}

// MARK: - Avance de tramos (lógica pura, compartida por los dos motores)

/// Sigue un plan de tramos MIXTOS (por distancia y por tiempo) a partir
/// de la distancia total y el TIEMPO ACTIVO (sin pausas) de la sesión.
/// Los dos motores (reloj y celu) la alimentan una vez por segundo y
/// reaccionan a los eventos; acá no hay Date(), ni audio, ni UI.
///
/// Contabilidad de límites:
/// - Un tramo por DISTANCIA termina exactamente en
///   `inicioDistancia + metros`: el excedente del tick cuenta para el
///   tramo siguiente (misma semántica que la suma de prefijos vieja).
/// - Un tramo por TIEMPO termina exactamente en
///   `inicioTiempo + duración`: el excedente de tiempo pasa al
///   siguiente.
/// - El punto de arranque de la OTRA magnitud (el tiempo al cerrar un
///   tramo por distancia, la distancia al cerrar uno por tiempo) se
///   toma del tick en que se detectó el cruce: con ticks de ~1 s el
///   error es despreciable y no se inventan interpolaciones.
struct ProgresoTramos: Equatable {

    enum Evento: Equatable {
        /// Arrancó el tramo `indice` (anunciarlo, resetear filtros).
        case cambioTramo(indice: Int)
        /// Se recorrió el plan entero.
        case planCompletado
    }

    private(set) var tramos: [Tramo]
    private(set) var indice = 0
    private(set) var inicioDistanciaMetros: Double = 0
    private(set) var inicioTiempoActivo: Double = 0

    init(tramos: [Tramo]) {
        self.tramos = tramos
    }

    var tramoActual: Tramo? { indice < tramos.count ? tramos[indice] : nil }
    var terminado: Bool { !tramos.isEmpty && indice >= tramos.count }

    /// Un tick del motor. Puede cerrar VARIOS tramos (tramos muy cortos
    /// dentro de un mismo tick); devuelve los eventos en orden.
    mutating func avanzar(distanciaMetros: Double, tiempoActivo: Double) -> [Evento] {
        var eventos: [Evento] = []
        while let tramo = tramoActual {
            if tramo.esPorTiempo {
                let fin = inicioTiempoActivo + Double(tramo.duracionSegundos ?? 0)
                guard tiempoActivo >= fin else { break }
                inicioTiempoActivo = fin
                inicioDistanciaMetros = distanciaMetros
            } else {
                // Un tramo por distancia con 0 km no puede sostenerse:
                // se cierra en el primer tick (el while avanza igual).
                let fin = inicioDistanciaMetros + max(0, tramo.kilometros) * 1000
                guard distanciaMetros >= fin else { break }
                inicioDistanciaMetros = fin
                inicioTiempoActivo = tiempoActivo
            }
            indice += 1
            eventos.append(indice < tramos.count
                           ? .cambioTramo(indice: indice)
                           : .planCompletado)
        }
        return eventos
    }

    /// Fracción 0...1 recorrida del tramo actual, para barras de
    /// progreso. nil sin tramo actual o con meta inválida.
    func progresoTramoActual(distanciaMetros: Double, tiempoActivo: Double) -> Double? {
        guard let tramo = tramoActual else { return nil }
        let hecho: Double
        let meta: Double
        if tramo.esPorTiempo {
            hecho = tiempoActivo - inicioTiempoActivo
            meta = Double(tramo.duracionSegundos ?? 0)
        } else {
            hecho = distanciaMetros - inicioDistanciaMetros
            meta = tramo.kilometros * 1000
        }
        guard meta > 0 else { return nil }
        return min(1, max(0, hecho / meta))
    }

    /// "faltan 400 m" / "faltan 1:20" del tramo actual, para la UI.
    func restanteTramoActual(distanciaMetros: Double, tiempoActivo: Double) -> String? {
        guard let tramo = tramoActual else { return nil }
        if tramo.esPorTiempo {
            let falta = max(0, inicioTiempoActivo + Double(tramo.duracionSegundos ?? 0) - tiempoActivo)
            let segundos = Int(falta.rounded())
            return "faltan \(segundos / 60):" + String(format: "%02d", segundos % 60)
        }
        let falta = max(0, inicioDistanciaMetros + tramo.kilometros * 1000 - distanciaMetros)
        if falta >= 1000 {
            return String(format: "faltan %.1f km", falta / 1000)
        }
        return "faltan \(Int(falta.rounded())) m"
    }
}

/// Zona cardíaca 1...5 por reserva (Karvonen): dónde está `fc` en el
/// camino entre la FC de reposo y la máxima. 0 = datos inválidos.
/// ÚNICA fuente de la fórmula: la usan el aviso hablado y la celda de
/// métricas del reloj — antes estaba duplicada y podían divergir.
func zonaCardiaca(fc: Int, reposo: Int, maxima: Int) -> Int {
    guard fc > 0, maxima > reposo else { return 0 }
    let reserva = Double(fc - reposo) / Double(maxima - reposo)
    switch reserva {
    case ..<0.6: return 1
    case ..<0.7: return 2
    case ..<0.8: return 3
    case ..<0.9: return 4
    default: return 5
    }
}

/// 230 -> "3 50", para que la voz lo lea natural.
func ritmoParaHablar(_ segundosPorKm: Int) -> String {
    "\(segundosPorKm / 60) \(String(format: "%02d", segundosPorKm % 60))"
}

// MARK: - Calidad de métricas (RC1)

/// Reglas de CALIDAD para métricas derivadas, en un solo lugar.
/// Separación deliberada: el HISTORIAL cuenta todo (una salida de
/// 200 m sigue sumando kilómetros a la semana y nada se borra de
/// Salud); las MARCAS y los ritmos MOSTRADOS exigen muestras
/// suficientes. No es ciencia deportiva: son pisos de sanidad para no
/// mostrar jamás un "0:15/km" salido de una sesión de prueba.
enum MetricasSesion {

    /// Ritmo en seg/km con TODOS los guards: división por cero, NaN,
    /// infinito, distancia insuficiente y ritmos físicamente absurdos
    /// (más rápido que 2:00/km o más lento que 20:00/km es error de
    /// sensor, no una carrera). nil = "sin ritmo fiable" — la UI
    /// muestra un guion, nunca un número absurdo.
    static func ritmoSegKm(metros: Double, segundos: Double,
                           metrosMinimos: Double = 500) -> Int? {
        guard metros.isFinite, segundos.isFinite,
              metros >= metrosMinimos, segundos > 0 else { return nil }
        let ritmo = segundos / metros * 1000
        guard ritmo.isFinite, ritmo >= 120, ritmo <= 1200 else { return nil }
        return Int(ritmo.rounded())
    }

    /// ¿La sesión puede producir MARCAS (mejor ritmo, salida más
    /// larga)? Conservador: al menos 1 km, al menos 5 minutos y un
    /// ritmo plausible sostenido (2:30–15:00 /km). Ante la duda, no
    /// hay marca — "sin marca fiable" gana siempre a un récord falso.
    static func elegibleParaMarcas(metros: Double, segundos: Double) -> Bool {
        guard metros.isFinite, segundos.isFinite,
              metros >= 1000, segundos >= 300 else { return false }
        let ritmo = segundos / metros * 1000
        return ritmo >= 150 && ritmo <= 900
    }
}

/// La meta del tramo para la voz: "5 kilómetros" / "2 minutos" /
/// "2 minutos y 30 segundos". Compartida por los dos motores y
/// localizada (el catálogo de cada target trae las claves).
func metaParaHablar(_ tramo: Tramo) -> String {
    if tramo.esPorTiempo {
        let total = tramo.duracionSegundos ?? 0
        let minutos = total / 60
        let segundos = total % 60
        if minutos == 0 { return String(localized: "\(segundos) segundos") }
        if segundos == 0 {
            return minutos == 1 ? String(localized: "1 minuto")
                                : String(localized: "\(minutos) minutos")
        }
        return minutos == 1
            ? String(localized: "1 minuto y \(segundos) segundos")
            : String(localized: "\(minutos) minutos y \(segundos) segundos")
    }
    let km = tramo.kilometros == tramo.kilometros.rounded()
        ? "\(Int(tramo.kilometros))"
        : String(format: "%.1f", tramo.kilometros)
    return km == "1" ? String(localized: "1 kilómetro")
                     : String(localized: "\(km) kilómetros")
}

/// El anuncio hablado de un tramo, compartido por los dos motores
/// (estaba duplicado) y localizado: "Tramo 2: Bloque. 3 kilómetros,
/// entre 4 50 y 5 10 por kilómetro."
func anuncioDeTramo(_ tramo: Tramo, numero: Int) -> String {
    let sufijo: String
    switch (tramo.ritmoMinSegKm, tramo.ritmoMaxSegKm) {
    case let (rapido?, lento?):
        sufijo = String(localized: ", entre \(ritmoParaHablar(rapido)) y \(ritmoParaHablar(lento)) por kilómetro.")
    case let (nil, lento?):
        sufijo = String(localized: ", a \(ritmoParaHablar(lento)) por kilómetro o mejor.")
    case let (rapido?, nil):
        sufijo = String(localized: ", sin pasar de \(ritmoParaHablar(rapido)) por kilómetro.")
    default:
        sufijo = String(localized: ", a ritmo libre.")
    }
    let detalle = metaParaHablar(tramo) + sufijo
    return String(localized: "Tramo \(numero): \(tramo.nombre). \(detalle)")
}

/// La voz sintetizada sigue el IDIOMA DE LA APP (la localización
/// resuelta del bundle), no un español fijo: con la app en inglés, la
/// voz habla inglés. Compartida por los dos motores.
func vozDeLaApp() -> AVSpeechSynthesisVoice? {
    let idioma = Bundle.main.preferredLocalizations.first ?? "es"
    let candidatos = idioma.hasPrefix("en")
        ? ["en-US", "en-GB", "en-AU"]
        : ["es-AR", "es-MX", "es-ES"]
    for codigo in candidatos {
        if let voz = AVSpeechSynthesisVoice(language: codigo) { return voz }
    }
    return AVSpeechSynthesisVoice(language: idioma)
}

struct AvisoFijo: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var minuto: Int
    var texto: String
}

struct AvisoRepetido: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var cadaMinutos: Int
    var desdeMinuto: Int
    var hastaMinuto: Int?
    var texto: String
}

/// Un aviso ya "resuelto" a un minuto concreto. No se persiste:
/// se calcula expandiendo el plan (fijos + repetidos).
struct AvisoProgramado: Identifiable, Hashable {
    let id = UUID()
    var minuto: Int
    var texto: String
}

extension Plan {
    /// Expande los avisos fijos y repetidos en la lista completa y ordenada
    /// de avisos concretos. Es la fuente única del cronograma: la usa la
    /// vista previa en el iPhone y el reproductor en el reloj.
    /// Si un fijo y un repetido caen en el mismo minuto, el fijo va primero.
    func cronograma(duracionMaximaMinutos: Int = 6 * 60) -> [AvisoProgramado] {
        var avisos: [(minuto: Int, prioridad: Int, texto: String)] = []

        for aviso in avisosFijos where aviso.minuto > 0 {
            avisos.append((aviso.minuto, 0, aviso.texto))
        }

        for aviso in avisosRepetidos where aviso.cadaMinutos > 0 && aviso.desdeMinuto > 0 {
            let limite = min(aviso.hastaMinuto ?? duracionMaximaMinutos, duracionMaximaMinutos)
            var minuto = aviso.desdeMinuto
            while minuto <= limite {
                avisos.append((minuto, 1, aviso.texto))
                minuto += aviso.cadaMinutos
            }
        }

        return avisos
            .sorted { ($0.minuto, $0.prioridad) < ($1.minuto, $1.prioridad) }
            .map { AvisoProgramado(minuto: $0.minuto, texto: $0.texto) }
    }
}

// MARK: - Estimador de ritmo EN VIVO (build 54)

/// CAUSA RAÍZ del ritmo inestable (prueba física de 11 km): el ritmo
/// actual se calculaba sobre la distancia ACUMULADA del builder de
/// HealthKit muestreada 1 vez/segundo en una ventana fija de 45 s.
/// HealthKit entrega la distancia EN RÁFAGAS (escalera): entre ráfagas
/// la distancia se congela y al llegar el lote salta de golpe. Con la
/// ventana fija eso produce (a) oscilación 6:50↔6:20 por efecto borde
/// (los escalones entran y salen de la ventana) y (b) el 2:00/km: tras
/// un congelamiento largo, el lote de recuperación entero cae dentro
/// de la ventana y el delta gigante se divide por 45 s.
///
/// Este estimador es determinístico y NO depende de CLLocation:
/// procesa (tiempo, distancia acumulada) y publica un ritmo estable.
/// Claves del diseño:
/// - Un tick SIN avance no es información de ritmo (es HealthKit
///   respirando): no ensucia la ventana.
/// - Cada avance se pondera por el tiempo REAL desde el último avance:
///   un lote de recuperación tras N s congelados se convierte solo en
///   su promedio verdadero (150 m tras 60 s = 6:40/km, no 2:00/km).
/// - Ventana móvil de avances + EMA moderada: estable en ritmo
///   constante, reactiva en pocos segundos ante cambios reales.
/// - Sin datos fiables: stale breve conservando el último valor y
///   después nil (--:-- honesto), jamás un ritmo inventado.
struct EstimadorRitmoLive {

    /// Parámetros CENTRALIZADOS (nada de números mágicos sueltos).
    struct Parametros {
        /// Ventana de avances sobre la que se promedia (equilibrio
        /// estabilidad/reactividad; 30 s no arruina intervalos).
        var ventanaSegundos: TimeInterval = 30
        /// Mínimos para publicar (warm-up): evita ritmos de 3 metros.
        var minimoSegundos: TimeInterval = 12
        var minimoMetros: Double = 15
        /// Suavizado exponencial del valor publicado (0.35 ≈ el 63 %
        /// del cambio real visible en ~2-3 actualizaciones).
        var alfa: Double = 0.35
        /// Velocidad humana máxima aceptada como muestra coherente
        /// (12.5 m/s ≈ 1:20/km: sanity extremo, ÚLTIMA defensa — el
        /// mecanismo principal es la ponderación temporal).
        var velocidadMaxima: Double = 12.5
        /// Sin avances: cuánto se conserva el último valor (stale) y
        /// cuándo se pasa a nil (--:--).
        var staleSegundos: TimeInterval = 10
        var caducidadSegundos: TimeInterval = 20
    }

    var parametros = Parametros()

    private var avances: [(t: TimeInterval, dt: TimeInterval, dd: Double)] = []
    private var ultimoTiempo: TimeInterval?
    private var ultimaDistancia: Double?
    private var ultimoTiempoConAvance: TimeInterval?
    private var suavizado: Double?

    /// El ritmo publicado (seg/km). nil = sin dato fiable (--:--).
    private(set) var ritmoSegKm: Int?
    /// false = el valor publicado quedó viejo (sin avances recientes):
    /// se muestra pero NO debe alimentar correcciones del coach.
    private(set) var esConfiable = false

    mutating func reiniciar() {
        avances = []
        ultimoTiempo = nil
        ultimaDistancia = nil
        ultimoTiempoConAvance = nil
        suavizado = nil
        ritmoSegKm = nil
        esConfiable = false
    }

    /// Procesa un tick (1/s aprox) con la distancia ACUMULADA del
    /// builder. Devuelve el ritmo publicado.
    @discardableResult
    mutating func procesar(tiempo: TimeInterval, distanciaAcumulada: Double) -> Int? {
        // Timestamps duplicados o hacia atrás: tick inválido, ignorar.
        if let previo = ultimoTiempo, tiempo <= previo {
            return ritmoSegKm
        }
        guard let distanciaPrevia = ultimaDistancia else {
            // Primera muestra: solo siembra.
            ultimoTiempo = tiempo
            ultimaDistancia = distanciaAcumulada
            ultimoTiempoConAvance = tiempo
            return nil
        }
        ultimoTiempo = tiempo

        let delta = distanciaAcumulada - distanciaPrevia
        if delta < 0 {
            // Distancia acumulada retrocedió (reinicio externo): estado
            // seguro, re-sembrar.
            reiniciar()
            ultimoTiempo = tiempo
            ultimaDistancia = distanciaAcumulada
            ultimoTiempoConAvance = tiempo
            return nil
        }

        if delta == 0 {
            // Tick sin avance: HealthKit entre ráfagas o corredor
            // detenido. No es muestra de ritmo. Solo se degrada el
            // estado publicado con el tiempo.
            let sinAvance = tiempo - (ultimoTiempoConAvance ?? tiempo)
            if sinAvance > parametros.caducidadSegundos {
                ritmoSegKm = nil
                esConfiable = false
                suavizado = nil
                avances = []
            } else if sinAvance > parametros.staleSegundos {
                esConfiable = false   // se muestra, pero no acciona
            }
            return ritmoSegKm
        }

        // Avance real: ponderado por el tiempo desde el ÚLTIMO avance
        // (la corrección clave: un lote de recuperación se promedia
        // sobre todo el período congelado).
        let dtEfectivo = tiempo - (ultimoTiempoConAvance ?? tiempo)
        ultimaDistancia = distanciaAcumulada
        guard dtEfectivo > 0 else { return ritmoSegKm }
        let velocidad = delta / dtEfectivo
        // Sanity extremo (última defensa, no mecanismo principal):
        // una velocidad imposible es una muestra espacial incoherente.
        guard velocidad <= parametros.velocidadMaxima else {
            return ritmoSegKm
        }
        ultimoTiempoConAvance = tiempo

        avances.append((t: tiempo, dt: dtEfectivo, dd: delta))
        avances.removeAll { tiempo - $0.t > parametros.ventanaSegundos }

        let segundos = avances.reduce(0) { $0 + $1.dt }
        let metros = avances.reduce(0) { $0 + $1.dd }
        guard segundos >= parametros.minimoSegundos,
              metros >= parametros.minimoMetros else {
            return ritmoSegKm
        }

        let crudo = segundos / metros * 1000
        let nuevo = suavizado.map { parametros.alfa * crudo + (1 - parametros.alfa) * $0 } ?? crudo
        suavizado = nuevo
        ritmoSegKm = Int(nuevo.rounded())
        esConfiable = true
        return ritmoSegKm
    }
}
