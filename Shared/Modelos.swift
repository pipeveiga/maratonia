import Foundation

/// El plan completo de una carrera: qué pistas suenan y qué avisos
/// de voz se disparan a qué minuto. Se arma en el iPhone, viaja al
/// reloj por WatchConnectivity y se guarda en disco en ambos lados.
struct Plan: Codable, Equatable {
    var nombre: String
    /// Nombres de archivo de los MP3, en orden de reproducción.
    var pistas: [String]
    var avisosFijos: [AvisoFijo]
    var avisosRepetidos: [AvisoRepetido]

    init(nombre: String = "Mi plan",
         pistas: [String] = [],
         avisosFijos: [AvisoFijo] = [],
         avisosRepetidos: [AvisoRepetido] = []) {
        self.nombre = nombre
        self.pistas = pistas
        self.avisosFijos = avisosFijos
        self.avisosRepetidos = avisosRepetidos
    }
}

/// Un aviso que suena una sola vez, en un minuto puntual de la carrera.
/// Ejemplo: minuto 90, "Date vuelta y volvé".
struct AvisoFijo: Codable, Equatable, Identifiable {
    var id = UUID()
    var minuto: Int
    var texto: String
}

/// Un aviso que se repite cada tanto. Ejemplo: cada 20 minutos,
/// desde el minuto 20, "Tomá agua". Si `hastaMinuto` es nil, se
/// repite hasta el final de la sesión.
struct AvisoRepetido: Codable, Equatable, Identifiable {
    var id = UUID()
    var cadaMinutos: Int
    var desdeMinuto: Int
    var hastaMinuto: Int?
    var texto: String
}
