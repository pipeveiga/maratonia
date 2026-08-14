import Foundation

// LOCALIZACIÓN DEL CONTENIDO DEPORTIVO.
//
// El problema que resuelve este archivo: los títulos y las descripciones
// de los entrenamientos nacían como literales en español dentro de
// `ContenidoPlanes`, viajaban por `EntrenamientoBase` y se CONGELABAN en
// el snapshot del plan al adoptarlo (`DefinicionEntrenamiento.nombre`).
// De ahí en más eran datos, no texto: ninguna capa de presentación podía
// traducirlos, así que con el teléfono en inglés la app mostraba
// "Rodaje medio" y "Tirada larga" para siempre — y cambiar de idioma no
// arreglaba nada, porque el español ya estaba escrito en el disco.
//
// La regla ahora: **el plan guarda QUÉ ES cada cosa, no cómo se llama**.
// Una sesión de umbral de 32 minutos se guarda como `.umbral(minutos: 32)`
// y el texto se arma al mostrarlo, en el idioma de ese momento. Cambiar
// el idioma del sistema no requiere recrear el plan, y el mismo snapshot
// se lee en español en el iPhone y en inglés en el reloj si así están
// configurados.
//
// Compatibilidad, en las dos direcciones:
//
// - **Hacia atrás**: los planes ya adoptados no tienen clave. Su texto
//   congelado se resuelve por `TextosLegado`, una tabla del español
//   conocido → texto localizado. Un plan de una build anterior se ve
//   traducido sin migrar nada ni tocar el disco.
// - **Hacia adelante**: la clave se guarda ADEMÁS del texto, nunca en su
//   lugar. Una build vieja leyendo un plan nuevo ignora la clave y usa
//   el string, que sigue estando. Y una clave futura desconocida
//   decodifica como nil en vez de tirar el archivo entero.
//
// Lo que NO se traduce: lo que escribió el corredor (entrenamientos
// personalizados, nombres de tramos propios). Eso no es contenido de
// Maratonia y se muestra tal cual lo tipeó.

// MARK: - Plan

/// Identidad de un arquetipo del catálogo. El nombre del plan también
/// se congelaba en `PlanUsuario.nombre` al adoptar.
enum ClavePlan: String, Codable, Equatable, Hashable, CaseIterable {
    case primeros5K
    case mejorar5K
    case rumboA10K
    case mejorar10K
    case mediaMaraton
    case mejorarMedia
    case mediaRendimiento
    case maraton
    case mejorarMaraton
    case maratonRendimiento

    /// El español ORIGINAL. Es lo que se CONGELA en el snapshot y la
    /// clave con la que `TextosLegado` rescata los planes viejos: si se
    /// guardara el nombre ya traducido, un plan adoptado con la app en
    /// inglés no se podría volver a resolver nunca.
    var nombreCanonico: String {
        switch self {
        case .primeros5K: return "Primeros 5K"
        case .mejorar5K: return "Mejorar mis 5K"
        case .rumboA10K: return "Rumbo a 10K"
        case .mejorar10K: return "Mejorar mis 10K"
        case .mediaMaraton: return "Media maratón"
        case .mejorarMedia: return "Mejorar mi media"
        case .mediaRendimiento: return "Media · rendimiento"
        case .maraton: return "Maratón"
        case .mejorarMaraton: return "Mejorar mi maratón"
        case .maratonRendimiento: return "Maratón · rendimiento"
        }
    }

    var nombre: String {
        switch self {
        case .primeros5K: return String(localized: "Primeros 5K")
        case .mejorar5K: return String(localized: "Mejorar mis 5K")
        case .rumboA10K: return String(localized: "Rumbo a 10K")
        case .mejorar10K: return String(localized: "Mejorar mis 10K")
        case .mediaMaraton: return String(localized: "Media maratón")
        case .mejorarMedia: return String(localized: "Mejorar mi media")
        case .mediaRendimiento: return String(localized: "Media · rendimiento")
        case .maraton: return String(localized: "Maratón")
        case .mejorarMaraton: return String(localized: "Mejorar mi maratón")
        case .maratonRendimiento: return String(localized: "Maratón · rendimiento")
        }
    }
}

// MARK: - Entrenamiento

// En los tres enums que siguen conviven DOS lecturas del mismo texto:
//
// - `nombreCanonico` / `descripcionCanonica`: el español original. Es lo
//   que se CONGELA en el snapshot. Adoptar un plan con el teléfono en
//   inglés no puede escribir inglés en el disco — el archivo quedaría
//   atado al idioma que tenía el corredor ese día, y la tabla de rescate
//   (que busca por español) no lo encontraría nunca más.
// - `nombre` / `descripcion`: el texto a MOSTRAR, en el idioma de ahora.
//
// Que las dos listas no se separen lo garantiza un test: corriendo en
// español tienen que dar exactamente lo mismo.

/// Qué ES una sesión del catálogo, con sus parámetros. De acá salen su
/// título y su descripción, en el idioma actual.
enum ClaveEntrenamiento: Equatable, Hashable {
    case rodajeSuave
    case rodajeMedio
    /// Mismo TÍTULO que `.rodajeMedio` pero la descripción del rodaje
    /// suave: son las primeras semanas de Media maratón, donde el lugar
    /// de la sesión de calidad lo ocupa un rodaje más largo y todavía no
    /// corresponde el discurso de "sumar tiempo en pie". Existe como
    /// caso propio para no cambiar el contenido al traducirlo.
    case rodajeMedioFacil
    case recuperacion
    case tiradaLarga
    case tiradaLargaConFinal
    case activacion
    case umbral(minutos: Int)
    case series(repeticiones: Int, minutos: Int)
    case ritmoObjetivo(distancia: DistanciaObjetivo, km: Int)
    case carrera(distancia: DistanciaObjetivo)

    var nombreCanonico: String {
        switch self {
        case .rodajeSuave: return "Rodaje suave"
        case .rodajeMedio, .rodajeMedioFacil: return "Rodaje medio"
        case .recuperacion: return "Recuperación"
        case .tiradaLarga, .tiradaLargaConFinal: return "Tirada larga"
        case .activacion: return "Activación"
        case .umbral(let minutos): return "Umbral \(minutos)′"
        case .series(let repeticiones, let minutos): return "\(repeticiones)×\(minutos)′ fuertes"
        case .ritmoObjetivo(let distancia, let km):
            switch distancia {
            case .cinco: return "Ritmo de 5K \(km) km"
            case .diez: return "Ritmo de 10K \(km) km"
            case .media: return "Ritmo de media \(km) km"
            case .maraton: return "Ritmo de maratón \(km) km"
            }
        case .carrera(let distancia):
            switch distancia {
            case .cinco: return "5K a fondo"
            case .diez: return "10K a fondo"
            case .media: return "Media maratón"
            case .maraton: return "Maratón"
            }
        }
    }

    var nombre: String {
        switch self {
        case .rodajeSuave: return String(localized: "Rodaje suave")
        case .rodajeMedio, .rodajeMedioFacil: return String(localized: "Rodaje medio")
        case .recuperacion: return String(localized: "Recuperación")
        case .tiradaLarga, .tiradaLargaConFinal: return String(localized: "Tirada larga")
        case .activacion: return String(localized: "Activación")
        case .umbral(let minutos): return String(localized: "Umbral \(minutos)′")
        case .series(let repeticiones, let minutos):
            return String(localized: "\(repeticiones)×\(minutos)′ fuertes")
        case .ritmoObjetivo(let distancia, let km):
            // La distancia del bloque va en la unidad del corredor; el
            // NOMBRE de la carrera (5K, media, maratón) no se convierte:
            // un 5K se llama 5K también en millas.
            let medida = Unidades.distancia(km: Double(km))
            switch distancia {
            case .cinco: return String(localized: "Ritmo de 5K \(medida)")
            case .diez: return String(localized: "Ritmo de 10K \(medida)")
            case .media: return String(localized: "Ritmo de media \(medida)")
            case .maraton: return String(localized: "Ritmo de maratón \(medida)")
            }
        case .carrera(let distancia):
            switch distancia {
            case .cinco: return String(localized: "5K a fondo")
            case .diez: return String(localized: "10K a fondo")
            case .media: return String(localized: "Media maratón")
            case .maraton: return String(localized: "Maratón")
            }
        }
    }

    var descripcionCanonica: String {
        switch self {
        case .rodajeSuave, .rodajeMedioFacil:
            return "Rodaje continuo cómodo: tenés que poder hablar."
        case .rodajeMedio:
            return "Rodaje más largo de lo habitual, todo cómodo: suma tiempo en pie sin la fatiga de una larga."
        case .recuperacion:
            return "Trote muy suave. Si el cuerpo pide caminar, se camina."
        case .tiradaLarga:
            return "La sesión que construye tu resistencia. Ritmo conversable de principio a fin."
        case .tiradaLargaConFinal:
            return "Larga con final a ritmo objetivo: los últimos kilómetros se corren a ritmo de maratón."
        case .activacion:
            return "Rodaje corto con 3 cambios de ritmo de 1′ para llegar despierto, no cansado."
        case .umbral:
            return "Bloque sostenido a ritmo de umbral: exigente pero controlado (~el ritmo que aguantarías 1 hora en carrera)."
        case .series:
            return "Intervalos a ritmo de 3-5K con trote de recuperación entre cada uno."
        case .ritmoObjetivo:
            return "Bloque continuo al ritmo que querés correr el día de la carrera. Sirve tanto para las piernas como para la cabeza."
        case .carrera:
            return "El día que preparaste. Salí conservador y cerrá fuerte."
        }
    }

    var descripcion: String {
        switch self {
        case .rodajeSuave, .rodajeMedioFacil:
            return String(localized: "Rodaje continuo cómodo: tenés que poder hablar.")
        case .rodajeMedio:
            return String(localized: "Rodaje más largo de lo habitual, todo cómodo: suma tiempo en pie sin la fatiga de una larga.")
        case .recuperacion:
            return String(localized: "Trote muy suave. Si el cuerpo pide caminar, se camina.")
        case .tiradaLarga:
            return String(localized: "La sesión que construye tu resistencia. Ritmo conversable de principio a fin.")
        case .tiradaLargaConFinal:
            return String(localized: "Larga con final a ritmo objetivo: los últimos kilómetros se corren a ritmo de maratón.")
        case .activacion:
            return String(localized: "Rodaje corto con 3 cambios de ritmo de 1′ para llegar despierto, no cansado.")
        case .umbral:
            return String(localized: "Bloque sostenido a ritmo de umbral: exigente pero controlado (~el ritmo que aguantarías 1 hora en carrera).")
        case .series:
            return String(localized: "Intervalos a ritmo de 3-5K con trote de recuperación entre cada uno.")
        case .ritmoObjetivo:
            return String(localized: "Bloque continuo al ritmo que querés correr el día de la carrera. Sirve tanto para las piernas como para la cabeza.")
        case .carrera:
            return String(localized: "El día que preparaste. Salí conservador y cerrá fuerte.")
        }
    }
}

// MARK: - Segmento

/// Qué ES un tramo dentro de una sesión. Viaja al reloj dentro de la
/// definición, así que el reloj lo muestra en SU idioma.
enum ClaveSegmento: Equatable, Hashable {
    case rodaje
    case rodajeMedio
    case troteSuave
    case largaComoda
    case finalRitmoMaraton
    case calentamiento
    case bloqueUmbral
    case vueltaALaCalma
    case trotePausa
    case alRitmoObjetivo
    case intervalo(numero: Int)
    case cambioDeRitmo(numero: Int)
    case carrera(distancia: DistanciaObjetivo)

    var nombreCanonico: String {
        switch self {
        case .rodaje: return "Rodaje"
        case .rodajeMedio: return "Rodaje medio"
        case .troteSuave: return "Trote suave"
        case .largaComoda: return "Larga cómoda"
        case .finalRitmoMaraton: return "Final a ritmo de maratón"
        case .calentamiento: return "Calentamiento"
        case .bloqueUmbral: return "Bloque umbral"
        case .vueltaALaCalma: return "Vuelta a la calma"
        case .trotePausa: return "Trote de pausa"
        case .alRitmoObjetivo: return "Al ritmo objetivo"
        case .intervalo(let numero): return "Intervalo \(numero)"
        case .cambioDeRitmo(let numero): return "Cambio de ritmo \(numero)"
        case .carrera(let distancia):
            switch distancia {
            case .cinco: return "5K a fondo"
            case .diez: return "10K a fondo"
            case .media: return "Media maratón"
            case .maraton: return "Maratón"
            }
        }
    }

    var nombre: String {
        switch self {
        case .rodaje: return String(localized: "Rodaje")
        case .rodajeMedio: return String(localized: "Rodaje medio")
        case .troteSuave: return String(localized: "Trote suave")
        case .largaComoda: return String(localized: "Larga cómoda")
        case .finalRitmoMaraton: return String(localized: "Final a ritmo de maratón")
        case .calentamiento: return String(localized: "Calentamiento")
        case .bloqueUmbral: return String(localized: "Bloque umbral")
        case .vueltaALaCalma: return String(localized: "Vuelta a la calma")
        case .trotePausa: return String(localized: "Trote de pausa")
        case .alRitmoObjetivo: return String(localized: "Al ritmo objetivo")
        case .intervalo(let numero): return String(localized: "Intervalo \(numero)")
        case .cambioDeRitmo(let numero): return String(localized: "Cambio de ritmo \(numero)")
        case .carrera(let distancia):
            switch distancia {
            case .cinco: return String(localized: "5K a fondo")
            case .diez: return String(localized: "10K a fondo")
            case .media: return String(localized: "Media maratón")
            case .maraton: return String(localized: "Maratón")
            }
        }
    }
}

// MARK: - Codable por TOKEN

// Las dos claves con parámetros se guardan como un string compacto
// ("umbral:32", "series:6x3") y no con el Codable sintetizado de enums
// con asociados, que produce un objeto anidado por caso. Razones:
// el JSON del plan queda legible, el catálogo embebido puede declarar
// una clave con un solo campo, y —lo importante— **una clave que esta
// build no conoce se puede ignorar en vez de romper la decodificación
// del almacén entero**.

private enum Token {
    static func partes(_ texto: String) -> [String] { texto.split(separator: ":").map(String.init) }
}

extension ClaveEntrenamiento: Codable {
    var token: String {
        switch self {
        case .rodajeSuave: return "rodajeSuave"
        case .rodajeMedio: return "rodajeMedio"
        case .rodajeMedioFacil: return "rodajeMedioFacil"
        case .recuperacion: return "recuperacion"
        case .tiradaLarga: return "tiradaLarga"
        case .tiradaLargaConFinal: return "tiradaLargaConFinal"
        case .activacion: return "activacion"
        case .umbral(let minutos): return "umbral:\(minutos)"
        case .series(let repeticiones, let minutos): return "series:\(repeticiones):\(minutos)"
        case .ritmoObjetivo(let distancia, let km): return "ritmoObjetivo:\(distancia.rawValue):\(km)"
        case .carrera(let distancia): return "carrera:\(distancia.rawValue)"
        }
    }

    /// nil = token que esta build no sabe leer. El llamador cae al texto
    /// guardado, que sigue estando en el archivo.
    init?(token: String) {
        let p = Token.partes(token)
        switch p.first {
        case "rodajeSuave": self = .rodajeSuave
        case "rodajeMedio": self = .rodajeMedio
        case "rodajeMedioFacil": self = .rodajeMedioFacil
        case "recuperacion": self = .recuperacion
        case "tiradaLarga": self = .tiradaLarga
        case "tiradaLargaConFinal": self = .tiradaLargaConFinal
        case "activacion": self = .activacion
        case "umbral":
            guard p.count == 2, let m = Int(p[1]) else { return nil }
            self = .umbral(minutos: m)
        case "series":
            guard p.count == 3, let r = Int(p[1]), let m = Int(p[2]) else { return nil }
            self = .series(repeticiones: r, minutos: m)
        case "ritmoObjetivo":
            guard p.count == 3, let d = DistanciaObjetivo(rawValue: p[1]), let km = Int(p[2])
            else { return nil }
            self = .ritmoObjetivo(distancia: d, km: km)
        case "carrera":
            guard p.count == 2, let d = DistanciaObjetivo(rawValue: p[1]) else { return nil }
            self = .carrera(distancia: d)
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let token = try decoder.singleValueContainer().decode(String.self)
        guard let clave = ClaveEntrenamiento(token: token) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "clave desconocida: \(token)"))
        }
        self = clave
    }

    func encode(to encoder: Encoder) throws {
        var contenedor = encoder.singleValueContainer()
        try contenedor.encode(token)
    }
}

extension ClaveSegmento: Codable {
    var token: String {
        switch self {
        case .rodaje: return "rodaje"
        case .rodajeMedio: return "rodajeMedio"
        case .troteSuave: return "troteSuave"
        case .largaComoda: return "largaComoda"
        case .finalRitmoMaraton: return "finalRitmoMaraton"
        case .calentamiento: return "calentamiento"
        case .bloqueUmbral: return "bloqueUmbral"
        case .vueltaALaCalma: return "vueltaALaCalma"
        case .trotePausa: return "trotePausa"
        case .alRitmoObjetivo: return "alRitmoObjetivo"
        case .intervalo(let numero): return "intervalo:\(numero)"
        case .cambioDeRitmo(let numero): return "cambioDeRitmo:\(numero)"
        case .carrera(let distancia): return "carrera:\(distancia.rawValue)"
        }
    }

    init?(token: String) {
        let p = Token.partes(token)
        switch p.first {
        case "rodaje": self = .rodaje
        case "rodajeMedio": self = .rodajeMedio
        case "troteSuave": self = .troteSuave
        case "largaComoda": self = .largaComoda
        case "finalRitmoMaraton": self = .finalRitmoMaraton
        case "calentamiento": self = .calentamiento
        case "bloqueUmbral": self = .bloqueUmbral
        case "vueltaALaCalma": self = .vueltaALaCalma
        case "trotePausa": self = .trotePausa
        case "alRitmoObjetivo": self = .alRitmoObjetivo
        case "intervalo":
            guard p.count == 2, let n = Int(p[1]) else { return nil }
            self = .intervalo(numero: n)
        case "cambioDeRitmo":
            guard p.count == 2, let n = Int(p[1]) else { return nil }
            self = .cambioDeRitmo(numero: n)
        case "carrera":
            guard p.count == 2, let d = DistanciaObjetivo(rawValue: p[1]) else { return nil }
            self = .carrera(distancia: d)
        default: return nil
        }
    }

    init(from decoder: Decoder) throws {
        let token = try decoder.singleValueContainer().decode(String.self)
        guard let clave = ClaveSegmento(token: token) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "clave desconocida: \(token)"))
        }
        self = clave
    }

    func encode(to encoder: Encoder) throws {
        var contenedor = encoder.singleValueContainer()
        try contenedor.encode(token)
    }
}

// MARK: - Compatibilidad con el texto ya congelado

/// El puente para todo lo que YA está escrito en español en el disco:
/// los planes adoptados antes de que existieran las claves y el
/// contenido provisional del catálogo V1, que todavía vive como JSON
/// embebido y no declara claves.
///
/// No es la fuente de verdad de nada: es una tabla de rescate. Lo que no
/// está acá se devuelve tal cual, que es lo correcto para el
/// entrenamiento que se armó el corredor.
enum TextosLegado {

    /// El título de una sesión, traducido si Maratonia lo escribió.
    static func entrenamiento(_ texto: String) -> String {
        titulos[texto] ?? texto
    }

    /// La descripción de una sesión, traducida si Maratonia la escribió.
    static func descripcion(_ texto: String) -> String {
        descripciones[texto] ?? texto
    }

    /// El nombre de un tramo, traducido si Maratonia lo escribió. Los
    /// numerados ("Intervalo 3") no entran en una tabla fija y se
    /// reconocen por forma.
    static func segmento(_ texto: String) -> String {
        tramos[texto] ?? segmentoNumerado(texto) ?? texto
    }

    /// El nombre de un plan, traducido si Maratonia lo escribió.
    static func plan(_ texto: String) -> String {
        planes[texto] ?? texto
    }

    // ---- Cobertura. Las usa el test que verifica que NINGÚN texto del
    // catálogo dependa de un string congelado: "traduce" y "está en la
    // tabla" no son lo mismo —un texto ausente se devuelve tal cual, que
    // se ve idéntico en español y es justo lo que hay que detectar.

    static func conoceEntrenamiento(_ texto: String) -> Bool { titulos[texto] != nil }
    static func conoceDescripcion(_ texto: String) -> Bool { descripciones[texto] != nil }
    static func conoceSegmento(_ texto: String) -> Bool {
        tramos[texto] != nil || segmentoNumerado(texto) != nil
    }

    // ---- Tablas. La CLAVE es el español congelado tal cual quedó en el
    // disco; el valor, el texto localizado de hoy. Los títulos que ya
    // tienen `ClaveEntrenamiento` se resuelven por ahí y no necesitan
    // entrada, pero están igual: un plan adoptado con la build anterior
    // los tiene guardados como string y no trae clave.

    private static var planes: [String: String] {
        var tabla: [String: String] = [:]
        for clave in ClavePlan.allCases { tabla[clave.nombreCanonico] = clave.nombre }
        return tabla
    }

    /// La descripción de un plan del catálogo V1. No se persiste en el
    /// plan adoptado, así que alcanza con traducirla al leer el JSON.
    static func descripcionDePlan(_ texto: String) -> String {
        descripcionesDePlan[texto] ?? texto
    }

    private static var descripcionesDePlan: [String: String] {
        [
            "De cero a correr 5 km de corrido, alternando caminata y trote con progresión suave. Ritmos libres: la regla es poder hablar mientras trotás. Contenido provisional.":
                String(localized: "De cero a correr 5 km de corrido, alternando caminata y trote con progresión suave. Ritmos libres: la regla es poder hablar mientras trotás. Contenido provisional."),
            "Para quien ya corre ~5 km y quiere llegar a 10 de corrido. Tres salidas por semana, progresión suave y ritmos libres. Contenido provisional.":
                String(localized: "Para quien ya corre ~5 km y quiere llegar a 10 de corrido. Tres salidas por semana, progresión suave y ritmos libres. Contenido provisional."),
        ]
    }

    private static var titulos: [String: String] {
        [
            // Contenido declarativo (planes adoptados sin clave).
            "Rodaje suave": String(localized: "Rodaje suave"),
            "Rodaje medio": String(localized: "Rodaje medio"),
            "Recuperación": String(localized: "Recuperación"),
            "Tirada larga": String(localized: "Tirada larga"),
            "Activación": String(localized: "Activación"),
            "5K a fondo": String(localized: "5K a fondo"),
            "10K a fondo": String(localized: "10K a fondo"),
            "Media maratón": String(localized: "Media maratón"),
            "Maratón": String(localized: "Maratón"),
            // Catálogo V1 provisional (JSON embebido).
            "Caminata y trote 1": String(localized: "Caminata y trote 1"),
            "Caminata y trote 2": String(localized: "Caminata y trote 2"),
            "Caminata y trote largo": String(localized: "Caminata y trote largo"),
            "Trote con pausas 1": String(localized: "Trote con pausas 1"),
            "Trote con pausas 2": String(localized: "Trote con pausas 2"),
            "Trote 5 y 1": String(localized: "Trote 5 y 1"),
            "Trote 8 y 1": String(localized: "Trote 8 y 1"),
            "Trote corrido": String(localized: "Trote corrido"),
            "Trote corrido corto": String(localized: "Trote corrido corto"),
            "Salida larga": String(localized: "Salida larga"),
            "Larga": String(localized: "Larga"),
            "Larga grande": String(localized: "Larga grande"),
            "Rodaje": String(localized: "Rodaje"),
            "Rodaje corto": String(localized: "Rodaje corto"),
            "Rodaje con final animado": String(localized: "Rodaje con final animado"),
            "Ensayo casi 5K": String(localized: "Ensayo casi 5K"),
            "Casi corrido": String(localized: "Casi corrido"),
            "Corrido": String(localized: "Corrido"),
            "Suave": String(localized: "Suave"),
            "5K corrido": String(localized: "5K corrido"),
            "10K corrido": String(localized: "10K corrido"),
            "Final animado": String(localized: "Final animado"),
            "¡Tus primeros 5K!": String(localized: "¡Tus primeros 5K!"),
            "¡Tus 10K!": String(localized: "¡Tus 10K!"),
        ]
    }

    private static var descripciones: [String: String] {
        [
            // Contenido declarativo (planes adoptados sin clave).
            "Rodaje continuo cómodo: tenés que poder hablar.":
                String(localized: "Rodaje continuo cómodo: tenés que poder hablar."),
            "Rodaje más largo de lo habitual, todo cómodo: suma tiempo en pie sin la fatiga de una larga.":
                String(localized: "Rodaje más largo de lo habitual, todo cómodo: suma tiempo en pie sin la fatiga de una larga."),
            "Trote muy suave. Si el cuerpo pide caminar, se camina.":
                String(localized: "Trote muy suave. Si el cuerpo pide caminar, se camina."),
            "La sesión que construye tu resistencia. Ritmo conversable de principio a fin.":
                String(localized: "La sesión que construye tu resistencia. Ritmo conversable de principio a fin."),
            "Larga con final a ritmo objetivo: los últimos kilómetros se corren a ritmo de maratón.":
                String(localized: "Larga con final a ritmo objetivo: los últimos kilómetros se corren a ritmo de maratón."),
            "Bloque sostenido a ritmo de umbral: exigente pero controlado (~el ritmo que aguantarías 1 hora en carrera).":
                String(localized: "Bloque sostenido a ritmo de umbral: exigente pero controlado (~el ritmo que aguantarías 1 hora en carrera)."),
            "Intervalos a ritmo de 3-5K con trote de recuperación entre cada uno.":
                String(localized: "Intervalos a ritmo de 3-5K con trote de recuperación entre cada uno."),
            "El día que preparaste. Salí conservador y cerrá fuerte.":
                String(localized: "El día que preparaste. Salí conservador y cerrá fuerte."),
            "Rodaje corto con 3 cambios de ritmo de 1′ para llegar despierto, no cansado.":
                String(localized: "Rodaje corto con 3 cambios de ritmo de 1′ para llegar despierto, no cansado."),
            "Bloque continuo al ritmo que querés correr el día de la carrera. Sirve tanto para las piernas como para la cabeza.":
                String(localized: "Bloque continuo al ritmo que querés correr el día de la carrera. Sirve tanto para las piernas como para la cabeza."),
            // Catálogo V1 provisional (JSON embebido).
            "Alterná 1 min de trote y 2 de caminata.":
                String(localized: "Alterná 1 min de trote y 2 de caminata."),
            "2 min de trote, 1 de caminata.": String(localized: "2 min de trote, 1 de caminata."),
            "5 min de trote, 1 de caminata.": String(localized: "5 min de trote, 1 de caminata."),
            "8 min de trote, 1 de caminata.": String(localized: "8 min de trote, 1 de caminata."),
            "Mismo juego, un poco más de distancia.":
                String(localized: "Mismo juego, un poco más de distancia."),
            "Tranquilo, caminá cuando lo necesites.":
                String(localized: "Tranquilo, caminá cuando lo necesites."),
            "Trotá de corrido; caminá solo si hace falta.":
                String(localized: "Trotá de corrido; caminá solo si hace falta."),
            "De corrido, ritmo de charla.": String(localized: "De corrido, ritmo de charla."),
            "Ritmo de charla.": String(localized: "Ritmo de charla."),
            "Sumá distancia sin apuro.": String(localized: "Sumá distancia sin apuro."),
            "Sumamos un poco.": String(localized: "Sumamos un poco."),
            "La más larga hasta ahora.": String(localized: "La más larga hasta ahora."),
            "La más larga del plan.": String(localized: "La más larga del plan."),
            "Cerca de la distancia objetivo.": String(localized: "Cerca de la distancia objetivo."),
            "Descarga: piernas frescas.": String(localized: "Descarga: piernas frescas."),
            "Semana amable: recuperar también entrena.":
                String(localized: "Semana amable: recuperar también entrena."),
            "Soltar piernas.": String(localized: "Soltar piernas."),
            "Cómodo.": String(localized: "Cómodo."),
            "Constante.": String(localized: "Constante."),
            "Paso firme.": String(localized: "Paso firme."),
            "Tranquila y constante.": String(localized: "Tranquila y constante."),
            "Igual que la anterior.": String(localized: "Igual que la anterior."),
            "Ya casi.": String(localized: "Ya casi."),
            "Cortito y fácil antes del objetivo.":
                String(localized: "Cortito y fácil antes del objetivo."),
            "Últimos ajustes, sin exigirte.": String(localized: "Últimos ajustes, sin exigirte."),
            "Último ensayo con chispa.": String(localized: "Último ensayo con chispa."),
            "Últimos 1,5 km más vivos.": String(localized: "Últimos 1,5 km más vivos."),
            "El último kilómetro un toque más vivo, sin ahogarte.":
                String(localized: "El último kilómetro un toque más vivo, sin ahogarte."),
            "El día: 5 km de corrido, a tu ritmo.":
                String(localized: "El día: 5 km de corrido, a tu ritmo."),
            "El día: 10 km de corrido, administrate.":
                String(localized: "El día: 10 km de corrido, administrate."),
        ]
    }

    private static var tramos: [String: String] {
        [
            // Contenido declarativo (planes adoptados sin clave).
            "Rodaje": String(localized: "Rodaje"),
            "Rodaje medio": String(localized: "Rodaje medio"),
            "Trote suave": String(localized: "Trote suave"),
            "Larga cómoda": String(localized: "Larga cómoda"),
            "Final a ritmo de maratón": String(localized: "Final a ritmo de maratón"),
            "Calentamiento": String(localized: "Calentamiento"),
            "Bloque umbral": String(localized: "Bloque umbral"),
            "Vuelta a la calma": String(localized: "Vuelta a la calma"),
            "Trote de pausa": String(localized: "Trote de pausa"),
            "Al ritmo objetivo": String(localized: "Al ritmo objetivo"),
            "5K a fondo": String(localized: "5K a fondo"),
            "10K a fondo": String(localized: "10K a fondo"),
            "Media maratón": String(localized: "Media maratón"),
            "Maratón": String(localized: "Maratón"),
            // Catálogo V1 provisional (JSON embebido).
            "Alternado": String(localized: "Alternado"),
            "Alternado suave": String(localized: "Alternado suave"),
            "Alternado largo": String(localized: "Alternado largo"),
            "Corrido": String(localized: "Corrido"),
            "Casi corrido": String(localized: "Casi corrido"),
            "Suave": String(localized: "Suave"),
            "Larga": String(localized: "Larga"),
            "Final animado": String(localized: "Final animado"),
            "5K corrido": String(localized: "5K corrido"),
            "10K corrido": String(localized: "10K corrido"),
        ]
    }

    /// Los numerados del contenido declarativo ("Intervalo 3", "Cambio
    /// de ritmo 2") no entran en una tabla fija: se reconocen por forma.
    /// Solo se usan para planes SIN clave — los nuevos ya traen
    /// `.intervalo(numero:)`.
    static func segmentoNumerado(_ texto: String) -> String? {
        for (prefijo, armar) in [("Intervalo ", { (n: Int) in ClaveSegmento.intervalo(numero: n) }),
                                 ("Cambio de ritmo ", { ClaveSegmento.cambioDeRitmo(numero: $0) })] {
            guard texto.hasPrefix(prefijo) else { continue }
            guard let numero = Int(texto.dropFirst(prefijo.count)) else { continue }
            return armar(numero).nombre
        }
        return nil
    }
}
