import Foundation
import Combine

// UNIDADES — una sola capa para todo lo que se muestra, se tipea y se
// habla.
//
// REGLA DE ARQUITECTURA: el almacenamiento y el motor deportivo siguen
// SIEMPRE en unidades canónicas internas (metros, segundos por
// kilómetro, kilogramos, centímetros). La preferencia del corredor no
// toca el dominio: solo cambia cómo se presenta, cómo se pide y cómo se
// dice en voz alta.
//
// Consecuencias de esa regla, y son el punto:
//
// - Cambiar de km a millas NO regenera el plan ni escribe nada: el
//   mismo snapshot se lee en las dos unidades, igual que se lee en los
//   dos idiomas.
// - No hay datos convertidos duplicados en el disco. Un plan tiene la
//   distancia en km y punto; la milla se calcula al dibujarla.
// - Los planes ya adoptados no necesitan migración.
//
// El default sale de la región del sistema, pero es solo un default: el
// corredor lo elige en el onboarding y lo cambia cuando quiera desde
// Perfil.

/// El sistema de unidades que ve el corredor.
enum SistemaUnidades: String, Codable, Equatable, Hashable, CaseIterable {
    case metrico
    case imperial

    /// Cuántos metros tiene la unidad de distancia. Es el único número
    /// del que se derivan las conversiones de distancia y de ritmo.
    var metrosPorUnidad: Double {
        switch self {
        case .metrico: return 1000
        case .imperial: return 1609.344   // milla internacional, exacta
        }
    }

    var etiquetaDistancia: String {
        switch self {
        case .metrico: return String(localized: "km")
        case .imperial: return String(localized: "mi")
        }
    }

    /// El sufijo del ritmo: "/km" o "/mi".
    var etiquetaRitmo: String { "/" + etiquetaDistancia }

    var etiquetaPeso: String {
        switch self {
        case .metrico: return String(localized: "kg")
        case .imperial: return String(localized: "lb")
        }
    }

    var nombre: String {
        switch self {
        case .metrico: return String(localized: "Métrico")
        case .imperial: return String(localized: "Imperial")
        }
    }

    /// Lo que hay que leer para elegir sin pensar: las unidades reales.
    var ejemplo: String {
        switch self {
        case .metrico: return String(localized: "km · min/km · kg · cm")
        case .imperial: return String(localized: "mi · min/mi · lb · ft/in")
        }
    }

    /// El default para quien todavía no eligió, según la región del
    /// sistema. Se usa SOLO para preseleccionar: la preferencia real es
    /// la que el corredor confirma.
    ///
    /// Los tres países que no usan el sistema métrico para distancias
    /// cotidianas. `Locale.measurementSystem` de Foundation no alcanza:
    /// el Reino Unido reporta `.uk` (millas en la ruta, kilos en la
    /// balanza) y para correr usa millas, así que entra en imperial.
    static func segunRegion(_ locale: Locale = .current) -> SistemaUnidades {
        switch locale.measurementSystem {
        case .us, .uk: return .imperial
        default: return .metrico
        }
    }
}

/// La preferencia viva del proceso.
///
/// Es `ObservableObject` para que cambiarla redibuje la app entera: las
/// vistas raíz la observan y todo lo que cuelga de ellas se recalcula.
/// Sin eso, tocar el selector en Perfil dejaría media pantalla en las
/// unidades viejas hasta el próximo redibujo.
///
/// El respaldo en `UserDefaults` es de ESTE dispositivo. La fuente de
/// verdad del corredor es el perfil (viaja con sus datos y llega al
/// reloj en la proyección); acá se cachea para poder formatear sin
/// tener el almacén a mano — que es la situación de casi toda la UI.
final class PreferenciaUnidades: ObservableObject {
    static let compartida = PreferenciaUnidades()

    private static let clave = "maratonia.sistemaUnidades"

    @Published private(set) var sistema: SistemaUnidades

    /// true = el corredor lo eligió de verdad. false = todavía es el
    /// default por región, y el onboarding tiene que preguntar.
    @Published private(set) var elegidaPorElCorredor: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, locale: Locale = .current) {
        self.defaults = defaults
        if let crudo = defaults.string(forKey: Self.clave),
           let guardada = SistemaUnidades(rawValue: crudo) {
            sistema = guardada
            elegidaPorElCorredor = true
        } else {
            // Sin preferencia guardada: default determinístico por
            // región. NO se escribe — que no esté guardada es
            // justamente lo que distingue "no eligió" de "eligió".
            sistema = .segunRegion(locale)
            elegidaPorElCorredor = false
        }
    }

    /// La eligió el corredor (onboarding o Perfil).
    func elegir(_ nuevo: SistemaUnidades) {
        defaults.set(nuevo.rawValue, forKey: Self.clave)
        elegidaPorElCorredor = true
        if sistema != nuevo { sistema = nuevo }
    }

    /// Adoptar lo que dice el perfil guardado (o lo que llegó del
    /// iPhone, en el reloj). No marca elección: refleja una que ya se
    /// hizo en otro lado.
    func adoptarDelPerfil(_ guardado: SistemaUnidades?) {
        guard let guardado else { return }
        defaults.set(guardado.rawValue, forKey: Self.clave)
        elegidaPorElCorredor = true
        if sistema != guardado { sistema = guardado }
    }
}

/// EL formateador. Todo lo que la app muestra, pide o dice en unidades
/// pasa por acá — no hay conversiones sueltas en las vistas.
///
/// Todas las funciones toman el sistema como parámetro con default al
/// vigente: las vistas escriben `Unidades.distancia(km: 7)` y los tests
/// pasan el sistema explícito sin tocar estado global.
enum Unidades {

    static var actual: SistemaUnidades { PreferenciaUnidades.compartida.sistema }

    // MARK: Conversión (canónico ↔ mostrable)

    /// Kilómetros canónicos → la unidad del corredor.
    static func distanciaMostrable(km: Double, sistema: SistemaUnidades = actual) -> Double {
        km * 1000 / sistema.metrosPorUnidad
    }

    /// Lo que el corredor tipeó → kilómetros canónicos.
    static func kmDesde(_ mostrable: Double, sistema: SistemaUnidades = actual) -> Double {
        mostrable * sistema.metrosPorUnidad / 1000
    }

    /// Segundos por km canónicos → segundos por la unidad del corredor.
    /// Un ritmo es tiempo POR distancia: se multiplica, no se divide.
    static func ritmoMostrable(segundosPorKm: Int, sistema: SistemaUnidades = actual) -> Int {
        Int((Double(segundosPorKm) * sistema.metrosPorUnidad / 1000).rounded())
    }

    static func ritmoCanonico(segundosPorUnidad: Int, sistema: SistemaUnidades = actual) -> Int {
        Int((Double(segundosPorUnidad) * 1000 / sistema.metrosPorUnidad).rounded())
    }

    static let libraEnKg = 0.453_592_37
    static let pulgadaEnCm = 2.54

    static func pesoMostrable(kg: Double, sistema: SistemaUnidades = actual) -> Double {
        sistema == .imperial ? kg / libraEnKg : kg
    }

    static func kgDesde(_ mostrable: Double, sistema: SistemaUnidades = actual) -> Double {
        sistema == .imperial ? mostrable * libraEnKg : mostrable
    }

    /// Centímetros → pies y pulgadas. Las pulgadas se redondean, y si
    /// llegan a 12 suben un pie: 182,9 cm es 6′0″, no 5′12″.
    static func alturaImperial(cm: Double) -> (pies: Int, pulgadas: Int) {
        let totalPulgadas = (cm / pulgadaEnCm).rounded()
        var pies = Int(totalPulgadas) / 12
        var pulgadas = Int(totalPulgadas) % 12
        if pulgadas == 12 { pies += 1; pulgadas = 0 }
        return (pies, pulgadas)
    }

    static func cmDesde(pies: Int, pulgadas: Int) -> Double {
        (Double(pies) * 12 + Double(pulgadas)) * pulgadaEnCm
    }

    // MARK: Formateo

    /// La distancia de una sesión, un plan o una carrera.
    /// `decimales: nil` = decide sola (entero si es redondo, un decimal
    /// si no), que es como se venía mostrando en métrico.
    static func distancia(km: Double, decimales: Int? = nil, conUnidad: Bool = true,
                          sistema: SistemaUnidades = actual) -> String {
        let valor = distanciaMostrable(km: km, sistema: sistema)
        let texto: String
        if let decimales {
            texto = String(format: "%.\(decimales)f", valor)
        } else if (valor - valor.rounded()).magnitude < 0.05 {
            texto = "\(Int(valor.rounded()))"
        } else {
            texto = String(format: "%.1f", valor)
        }
        return conUnidad ? "\(texto) \(sistema.etiquetaDistancia)" : texto
    }

    /// El ritmo: "5:30 /km" o "8:51 /mi".
    static func ritmo(segundosPorKm: Int, conUnidad: Bool = true,
                      sistema: SistemaUnidades = actual) -> String {
        let porUnidad = ritmoMostrable(segundosPorKm: segundosPorKm, sistema: sistema)
        let texto = "\(porUnidad / 60):" + String(format: "%02d", porUnidad % 60)
        return conUnidad ? "\(texto) \(sistema.etiquetaRitmo)" : texto
    }

    /// Un rango de ritmos con UNA sola etiqueta al final.
    static func rangoDeRitmo(_ rapidoSegKm: Int, _ lentoSegKm: Int,
                             sistema: SistemaUnidades = actual) -> String {
        let a = ritmo(segundosPorKm: rapidoSegKm, conUnidad: false, sistema: sistema)
        let b = ritmo(segundosPorKm: lentoSegKm, conUnidad: false, sistema: sistema)
        return "\(a)–\(b) \(sistema.etiquetaRitmo)"
    }

    static func peso(kg: Double, sistema: SistemaUnidades = actual) -> String {
        "\(Int(pesoMostrable(kg: kg, sistema: sistema).rounded())) \(sistema.etiquetaPeso)"
    }

    /// "178 cm" o "5′10″".
    static func altura(cm: Double, sistema: SistemaUnidades = actual) -> String {
        guard sistema == .imperial else { return String(localized: "\(Int(cm.rounded())) cm") }
        let (pies, pulgadas) = alturaImperial(cm: cm)
        return "\(pies)′\(pulgadas)″"
    }

    /// El volumen semanal: "43 km/sem" o "27 mi/wk".
    static func volumenSemanal(km: Double, sistema: SistemaUnidades = actual) -> String {
        let valor = distanciaMostrable(km: km, sistema: sistema)
        return String(localized: "\(Int(valor.rounded())) \(sistema.etiquetaDistancia)/sem")
    }

    // MARK: Voz
    //
    // La voz NO lee el texto de la pantalla: dice números sueltos y
    // tiene que sonar natural. "Kilómetro 5" en imperial es "Mile 5", y
    // el ritmo hablado no lleva el "/mi" (nadie dice "barra milla").

    /// "Kilómetro 5" / "Mile 5" — el hito de distancia recién cumplido.
    static func hitoHablado(numero: Int, sistema: SistemaUnidades = actual) -> String {
        switch sistema {
        case .metrico: return String(localized: "Kilómetro \(numero)")
        case .imperial: return String(localized: "Milla \(numero)")
        }
    }

    /// El ritmo dicho en voz alta: "4 12" (min y seg separados para que
    /// el sintetizador no lo lea como una hora). Los segundos van con
    /// cero adelante —"5 05", no "5 5"— porque así es como se dice un
    /// ritmo: "cinco cero cinco".
    static func ritmoHablado(segundosPorKm: Int, sistema: SistemaUnidades = actual) -> String {
        let porUnidad = ritmoMostrable(segundosPorKm: segundosPorKm, sistema: sistema)
        return "\(porUnidad / 60) " + String(format: "%02d", porUnidad % 60)
    }

    /// Cada cuántos METROS canónicos cae un hito de distancia. Es lo que
    /// hace que los splits y los avisos por distancia sean POR MILLA de
    /// verdad, y no un kilómetro con otra etiqueta encima.
    static func metrosPorHito(sistema: SistemaUnidades = actual) -> Double {
        sistema.metrosPorUnidad
    }
}
