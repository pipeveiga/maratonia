import Foundation

/// Un aviso que suena una sola vez, en un minuto exacto de la carrera.
/// Ejemplo: minuto 90, "Date vuelta y volvé".
struct AvisoFijo: Codable, Equatable, Hashable, Identifiable {
    var id = UUID()
    var minuto: Int
    var texto: String
}

/// Un aviso que se repite cada N minutos dentro de un rango.
/// Ejemplo: cada 20, desde el 20, "Tomá agua".
/// `hastaMinuto` en nil significa "hasta el final de la sesión".
struct AvisoRepetido: Codable, Equatable, Hashable, Identifiable {
    var id = UUID()
    var cadaMinutos: Int
    var desdeMinuto: Int
    var hastaMinuto: Int?
    var texto: String
}

/// Una entrada del cronograma ya expandido: "en el minuto X, decir Y".
/// No se guarda en disco; se calcula a partir del Plan.
struct AvisoProgramado: Equatable, Hashable {
    let minuto: Int
    let texto: String
}

/// El plan completo que se arma en el iPhone y se ejecuta en el reloj.
/// `pistas` son nombres de archivo MP3, en orden de reproducción.
struct Plan: Codable, Equatable {
    var nombre: String = "Mi plan"
    var pistas: [String] = []
    var avisosFijos: [AvisoFijo] = []
    var avisosRepetidos: [AvisoRepetido] = []

    /// Expande fijos + repetidos en una lista ordenada de avisos concretos.
    ///
    /// `horizonteMinutos` limita hasta dónde expandir los repetidos que no
    /// tienen tope (`hastaMinuto == nil`): en el iPhone conviene pasar la
    /// duración total de la cola de pistas; en el reloj, la duración máxima
    /// esperable de la carrera.
    ///
    /// Si dos avisos caen en el mismo minuto quedan ambos en la lista, en
    /// orden estable; el reproductor los dice uno después del otro.
    func cronograma(horizonteMinutos: Int) -> [AvisoProgramado] {
        var resultado: [AvisoProgramado] = avisosFijos
            .filter { $0.minuto <= horizonteMinutos }
            .map { AvisoProgramado(minuto: $0.minuto, texto: $0.texto) }

        for aviso in avisosRepetidos where aviso.cadaMinutos > 0 {
            let tope = min(aviso.hastaMinuto ?? horizonteMinutos, horizonteMinutos)
            var minuto = aviso.desdeMinuto
            while minuto <= tope {
                resultado.append(AvisoProgramado(minuto: minuto, texto: aviso.texto))
                minuto += aviso.cadaMinutos
            }
        }

        // sorted(by:) de Swift no garantiza orden estable entre iguales,
        // así que desempatamos por posición original.
        return resultado.enumerated()
            .sorted { ($0.element.minuto, $0.offset) < ($1.element.minuto, $1.offset) }
            .map(\.element)
    }
}
