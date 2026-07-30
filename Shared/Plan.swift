import Foundation

// Modelo de datos compartido entre la app iOS y la app watchOS.
// Este archivo pertenece a los dos targets (target membership doble).

/// Un plan de carrera: la cola de pistas y los avisos de voz.
struct Plan: Codable, Equatable {
    var nombre: String
    /// Nombres de archivo de los MP3, en orden de reproducción.
    var pistas: [String]
    var avisosFijos: [AvisoFijo]
    var avisosRepetidos: [AvisoRepetido]

    init(
        nombre: String = "Mi plan",
        pistas: [String] = [],
        avisosFijos: [AvisoFijo] = [],
        avisosRepetidos: [AvisoRepetido] = []
    ) {
        self.nombre = nombre
        self.pistas = pistas
        self.avisosFijos = avisosFijos
        self.avisosRepetidos = avisosRepetidos
    }
}

/// Aviso que suena una sola vez, en un minuto puntual.
struct AvisoFijo: Codable, Equatable, Identifiable {
    var id: UUID
    var minuto: Int
    var texto: String

    init(id: UUID = UUID(), minuto: Int, texto: String) {
        self.id = id
        self.minuto = minuto
        self.texto = texto
    }
}

/// Aviso que se repite cada N minutos dentro de una ventana.
struct AvisoRepetido: Codable, Equatable, Identifiable {
    var id: UUID
    var cadaMinutos: Int
    var desdeMinuto: Int
    /// nil = se repite hasta el final de la sesión.
    var hastaMinuto: Int?
    var texto: String

    init(id: UUID = UUID(), cadaMinutos: Int, desdeMinuto: Int, hastaMinuto: Int? = nil, texto: String) {
        self.id = id
        self.cadaMinutos = cadaMinutos
        self.desdeMinuto = desdeMinuto
        self.hastaMinuto = hastaMinuto
        self.texto = texto
    }
}

/// Un aviso ya expandido del cronograma: en qué minuto exacto suena.
struct AvisoProgramado: Identifiable {
    let id = UUID()
    let minuto: Int
    let texto: String
}

extension Plan {
    /// Expande fijos y repetidos en la lista completa y ordenada de avisos.
    /// Los repetidos sin `hastaMinuto` se expanden hasta `duracionTotalMinutos`.
    /// Si dos avisos caen en el mismo minuto quedan uno tras otro, en orden
    /// estable (primero los fijos, después los repetidos, en el orden del plan).
    func cronograma(duracionTotalMinutos: Int = 300) -> [AvisoProgramado] {
        var crudos: [(minuto: Int, texto: String)] = avisosFijos
            .map { ($0.minuto, $0.texto) }

        for repetido in avisosRepetidos {
            guard repetido.cadaMinutos > 0 else { continue }
            let limite = repetido.hastaMinuto ?? duracionTotalMinutos
            var minuto = repetido.desdeMinuto
            while minuto <= limite {
                crudos.append((minuto, repetido.texto))
                minuto += repetido.cadaMinutos
            }
        }

        return crudos
            .enumerated()
            .sorted { ($0.element.minuto, $0.offset) < ($1.element.minuto, $1.offset) }
            .map { AvisoProgramado(minuto: $0.element.minuto, texto: $0.element.texto) }
    }
}
