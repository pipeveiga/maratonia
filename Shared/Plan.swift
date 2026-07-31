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

    var tramosActivos: [Tramo] { tramos ?? [] }

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

/// 230 -> "3:50"
func formatearRitmo(_ segundosPorKm: Int) -> String {
    "\(segundosPorKm / 60):" + String(format: "%02d", segundosPorKm % 60)
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
