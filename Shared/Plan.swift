import Foundation

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

/// Un tramo del plan de entrenamiento: una distancia con un rango de
/// ritmo objetivo (en segundos por km). ritmoMinSegKm es el límite
/// rápido (ej. 230 = 3:50/km) y ritmoMaxSegKm el lento (250 = 4:10/km).
/// Ambos nil = tramo a ritmo libre.
struct Tramo: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var nombre: String
    var kilometros: Double
    var ritmoMinSegKm: Int?
    var ritmoMaxSegKm: Int?

    var descripcion: String {
        let distancia = kilometros == kilometros.rounded()
            ? "\(Int(kilometros)) km"
            : String(format: "%.1f km", kilometros)
        switch (ritmoMinSegKm, ritmoMaxSegKm) {
        case let (rapido?, lento?):
            return "\(distancia) a \(formatearRitmo(rapido))–\(formatearRitmo(lento)) /km"
        case let (nil, lento?):
            return "\(distancia) a \(formatearRitmo(lento)) /km o mejor"
        case let (rapido?, nil):
            return "\(distancia) sin pasar de \(formatearRitmo(rapido)) /km"
        default:
            return "\(distancia) libre"
        }
    }
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
            .map { "\($0.nombre)|\($0.kilometros)|\($0.ritmoMinSegKm ?? -1)|\($0.ritmoMaxSegKm ?? -1)" }
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
