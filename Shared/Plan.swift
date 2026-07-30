import Foundation

// Modelo de datos compartido entre la app iOS y la app watchOS.
// Este archivo pertenece a los dos targets: es el "idioma" común
// que viaja del teléfono al reloj vía WatchConnectivity.

struct Plan: Codable, Equatable {
    var nombre: String
    var pistas: [String]
    var avisosFijos: [AvisoFijo]
    var avisosRepetidos: [AvisoRepetido]

    static let vacio = Plan(nombre: "Mi plan", pistas: [], avisosFijos: [], avisosRepetidos: [])
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
