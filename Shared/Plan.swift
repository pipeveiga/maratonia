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
            return "\(meta) libre"
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
