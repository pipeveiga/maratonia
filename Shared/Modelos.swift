import Foundation

// Modelo de datos compartido entre la app iOS y la app watchOS.
// Este archivo pertenece a los dos targets: cualquier cambio acá
// afecta a ambas apps por igual, y por eso el plan que arma el iPhone
// se puede decodificar tal cual en el reloj.

/// Un plan de carrera: las pistas a reproducir (en orden) y los avisos de voz.
struct Plan: Codable, Equatable {
    var nombre: String
    /// Nombres de archivo de los MP3, en orden de reproducción.
    var pistas: [String]
    var avisosFijos: [AvisoFijo]
    var avisosRepetidos: [AvisoRepetido]

    static let vacio = Plan(nombre: "Mi plan", pistas: [], avisosFijos: [], avisosRepetidos: [])
}

/// Aviso que suena una sola vez, en un minuto puntual de la carrera.
/// Ejemplo: minuto 90, "Date vuelta y volvé".
struct AvisoFijo: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var minuto: Int
    var texto: String
}

/// Aviso que se repite cada N minutos dentro de un rango.
/// Ejemplo: cada 20, desde el 20, sin fin, "Tomá agua".
struct AvisoRepetido: Codable, Equatable, Identifiable, Hashable {
    var id = UUID()
    var cadaMinutos: Int
    var desdeMinuto: Int
    /// nil = se repite hasta el final de la sesión.
    var hastaMinuto: Int?
    var texto: String
}
