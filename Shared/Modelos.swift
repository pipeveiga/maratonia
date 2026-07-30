import Foundation

/// Un plan de carrera: la cola de pistas (nombres de archivo MP3, en orden)
/// y los avisos de voz que van a interrumpir la música.
struct Plan: Codable, Equatable {
    var nombre: String
    var pistas: [String]
    var avisosFijos: [AvisoFijo]
    var avisosRepetidos: [AvisoRepetido]

    static let vacio = Plan(nombre: "Mi plan", pistas: [], avisosFijos: [], avisosRepetidos: [])
}

/// Aviso que suena una sola vez, en un minuto puntual.
/// Ej.: minuto 90, "Date vuelta y volvé".
struct AvisoFijo: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var minuto: Int
    var texto: String
}

/// Aviso que se repite cada N minutos dentro de una ventana.
/// Ej.: cada 20, desde el 20, "Tomá agua". hastaMinuto nil = hasta el final.
struct AvisoRepetido: Codable, Equatable, Identifiable {
    var id: UUID = UUID()
    var cadaMinutos: Int
    var desdeMinuto: Int
    var hastaMinuto: Int?
    var texto: String
}

/// Un aviso ya resuelto a un minuto concreto: el resultado de expandir
/// los fijos y los repetidos en un cronograma lineal.
struct AvisoProgramado: Identifiable {
    let id = UUID()
    let minuto: Int
    let texto: String
}

extension Plan {
    /// Expande los avisos fijos y repetidos en una lista concreta ordenada por minuto.
    /// `limite` acota los repetidos sin fin (hastaMinuto == nil); los fijos se
    /// incluyen siempre, aunque caigan después del límite.
    /// Si dos avisos caen en el mismo minuto quedan uno después del otro,
    /// primero los fijos, y se reproducen en ese orden.
    func cronograma(hastaMinuto limite: Int) -> [AvisoProgramado] {
        var crudos: [(minuto: Int, prioridad: Int, texto: String)] = []

        for aviso in avisosFijos {
            crudos.append((aviso.minuto, 0, aviso.texto))
        }
        for aviso in avisosRepetidos where aviso.cadaMinutos > 0 {
            let fin = min(aviso.hastaMinuto ?? limite, limite)
            var minuto = aviso.desdeMinuto
            while minuto <= fin {
                crudos.append((minuto, 1, aviso.texto))
                minuto += aviso.cadaMinutos
            }
        }

        return crudos.enumerated()
            .sorted { a, b in
                (a.element.minuto, a.element.prioridad, a.offset)
                    < (b.element.minuto, b.element.prioridad, b.offset)
            }
            .map { AvisoProgramado(minuto: $0.element.minuto, texto: $0.element.texto) }
    }
}
