import Foundation

/// Un plan de carrera: la cola de pistas (nombres de archivo MP3, en orden)
/// y los avisos de voz que van a interrumpir la música.
/// Este archivo pertenece a los DOS targets (iOS y watchOS): es el "idioma común"
/// que viaja del teléfono al reloj por WatchConnectivity, por eso es Codable.
struct Plan: Codable, Equatable {
    var nombre: String
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
/// Ej.: minuto 90, "Date vuelta y volvé".
struct AvisoFijo: Codable, Equatable, Identifiable {
    var id = UUID()
    var minuto: Int
    var texto: String
}

/// Un aviso que se repite cada N minutos dentro de una ventana.
/// Ej.: cada 20, desde el 20, hasta el final: "Tomá agua".
/// `hastaMinuto` en nil significa "hasta el final de la sesión".
struct AvisoRepetido: Codable, Equatable, Identifiable {
    var id = UUID()
    var cadaMinutos: Int
    var desdeMinuto: Int
    var hastaMinuto: Int?
    var texto: String
}

/// Un aviso ya "resuelto" a un minuto concreto. Es lo que se ve en la vista
/// previa del cronograma (iOS) y lo que el reloj usa para disparar voz,
/// háptico y notificación durante la carrera.
struct AvisoProgramado: Equatable, Identifiable {
    var id: String { "\(minuto)|\(texto)" }
    let minuto: Int
    let texto: String
}

extension Plan {
    /// Expande fijos + repetidos en la lista completa de avisos, ordenada por minuto.
    /// Los repetidos sin `hastaMinuto` se acotan con `horizonteMinutos`
    /// (tope de duración de la sesión; el valor definitivo se decide en Fase 2/5).
    /// Si un fijo y un repetido caen en el mismo minuto, quedan uno detrás del otro
    /// (los fijos primero); el reproductor los dirá en secuencia, nunca encimados.
    func cronograma(horizonteMinutos: Int = 360) -> [AvisoProgramado] {
        var resultado: [(orden: Int, aviso: AvisoProgramado)] = []

        for fijo in avisosFijos {
            resultado.append((0, AvisoProgramado(minuto: fijo.minuto, texto: fijo.texto)))
        }
        for repetido in avisosRepetidos where repetido.cadaMinutos > 0 {
            let fin = min(repetido.hastaMinuto ?? horizonteMinutos, horizonteMinutos)
            var minuto = repetido.desdeMinuto
            while minuto <= fin {
                resultado.append((1, AvisoProgramado(minuto: minuto, texto: repetido.texto)))
                minuto += repetido.cadaMinutos
            }
        }

        return resultado
            .sorted { a, b in
                a.aviso.minuto != b.aviso.minuto
                    ? a.aviso.minuto < b.aviso.minuto
                    : a.orden < b.orden
            }
            .map(\.aviso)
    }
}
