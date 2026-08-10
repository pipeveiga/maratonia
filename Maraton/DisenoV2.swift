import SwiftUI
import UIKit

// Design System V2 — FUNDACIÓN (Fase C). No es un rediseño global:
// es el lenguaje visual compartido que las pantallas nuevas usan desde
// ahora, para que dejen de construirse a mano una por una. SwiftUI
// nativo, dark mode por colores semánticos del sistema, Dynamic Type
// por fuentes de texto estándar. El color tiene FUNCIÓN: acción
// (accent), estado (verde/naranja/amarillo/gris), tipo de
// entrenamiento (identidad de la tarjeta). Nada de gradientes porque sí.

/// Pluralización centralizada (basta de "1 pistas · 1 tramos").
/// Testeable y localizada por catálogo.
enum Plurales {
    static func pistas(_ n: Int) -> String {
        n == 1 ? String(localized: "1 pista") : String(localized: "\(n) pistas")
    }
    static func tramos(_ n: Int) -> String {
        n == 1 ? String(localized: "1 tramo") : String(localized: "\(n) tramos")
    }
    static func segmentos(_ n: Int) -> String {
        n == 1 ? String(localized: "1 segmento") : String(localized: "\(n) segmentos")
    }
    static func entrenamientos(_ n: Int) -> String {
        n == 1 ? String(localized: "1 entrenamiento") : String(localized: "\(n) entrenamientos")
    }
}

enum DV2 {

    // MARK: Identidad Maratonia (colores derivados del LOGO real:
    // azul profundo #002070-#003090, azur #0080E0-#00A0F0 y un acento
    // lima #606030 saturado). Tokens únicos — nada de hex repetidos
    // por pantalla. Los semánticos siguen siendo del sistema (verde/
    // naranja/rojo) para no perder significado nativo.
    enum Marca {
        /// PRIMARY — azur del logo: acciones, tint global, links.
        static let primario = Color("MaratoniaPrimario")
        /// SECONDARY — azul profundo del logo: titulares numéricos y
        /// el extremo oscuro del CTA de marca.
        static let profundo = Color("MaratoniaProfundo")
        /// ACCENT — "volt" deportivo refinado del oliva del logo
        /// (#606030 saturado hacia energía). REGLA DE USO: solo como
        /// RELLENO de chips/badges con texto oscuro encima o como
        /// glyph sobre superficie oscura — jamás texto volt sobre
        /// blanco (contraste insuficiente).
        static let energia = Color("MaratoniaLima")
    }

    /// BACKGROUND/SURFACE/TEXT: deliberadamente los del sistema — es
    /// lo que mantiene a Maratonia nativa y correcta en Light/Dark sin
    /// mantenimiento. Tokens con nombre para no repetir literales.
    enum Superficie {
        static let fondo = Color(.systemGroupedBackground)
        static let tarjeta = Color(.secondarySystemGroupedBackground)
        static let elevada = Color(.tertiarySystemGroupedBackground)
    }

    /// SUCCESS/WARNING/DESTRUCTIVE: system colors (superiores en
    /// accesibilidad y significado nativo).
    enum Semantico {
        static let exito = Color.green
        static let advertencia = Color.orange
        static let destructivo = Color.red
    }

    // Escala de espaciado única (basta de números mágicos por pantalla).
    enum Espacio {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    static let radioTarjeta: CGFloat = 16
    static let radioBoton: CGFloat = 14

    /// Identidad de color por tipo de entrenamiento (jerarquía visual
    /// del calendario y las tarjetas).
    static func color(de tipo: TipoEntrenamiento) -> Color {
        switch tipo {
        case .facil, .recuperacion: return .green
        case .largo: return .indigo
        case .tempo, .umbral: return .orange
        case .series: return .red
        case .ritmoCarrera: return .purple
        case .testEvaluacion: return .teal
        case .personalizado: return .blue
        }
    }

    static func color(de estado: EstadoProgramado) -> Color {
        switch estado {
        case .programado: return .secondary
        case .vencido: return .orange
        case .parcial: return .yellow
        case .cumplido: return .green
        case .omitido: return .gray
        }
    }

    /// El ritmo de un segmento para la UI, incluida la resolución
    /// simbólica (Fase G): un ritmo pendiente NO es un error — se
    /// muestra con nombre propio y la promesa honesta de personalizarse
    /// cuando haya baseline + metodología.
    static func textoRitmo(de segmento: Segmento,
                           baseline: PerformanceBaseline? = nil) -> String {
        switch segmento.ritmo {
        case .libre:
            return String(localized: "libre")
        case .absoluto(let rapido, let lento):
            switch (rapido, lento) {
            case let (r?, l?): return "\(formatearRitmo(r))–\(formatearRitmo(l)) /km"
            case let (nil, l?): return String(localized: "\(formatearRitmo(l)) /km o mejor")
            case let (r?, nil): return String(localized: "sin pasar de \(formatearRitmo(r)) /km")
            default: return String(localized: "libre")
            }
        case .simbolico(let tipo):
            switch Metodologias.resolver(tipo, baseline: baseline) {
            case .resuelto(let rango, _):
                return "\(formatearRitmo(rango.minSegKm))–\(formatearRitmo(rango.maxSegKm)) /km"
            case .pendiente:
                return String(localized: "ritmo \(nombre(de: tipo).lowercased()) · a personalizar")
            }
        }
    }

    /// "3 km · ritmo umbral · a personalizar" — la meta y el ritmo de
    /// un segmento, con simbólicos sin resolver mostrados con dignidad.
    static func metaDeSegmento(_ segmento: Segmento) -> String {
        var partes: [String] = []
        if let km = segmento.distanciaKm {
            partes.append(km == km.rounded() ? "\(Int(km)) km" : String(format: "%.1f km", km))
        } else if let segundos = segmento.duracionSegundos {
            partes.append(duracionTexto(segundos))
        }
        // Comparación SEMÁNTICA (no contra el string "libre"): con la
        // app en inglés el texto es "open" y la comparación textual
        // agregaba "open" a cada segmento libre.
        let esLibre: Bool
        switch segmento.ritmo {
        case .libre: esLibre = true
        case .absoluto(nil, nil): esLibre = true
        default: esLibre = false
        }
        if !esLibre { partes.append(textoRitmo(de: segmento)) }
        return partes.joined(separator: " · ")
    }

    static func nombre(de tipo: TipoRitmo) -> String {
        switch tipo {
        case .facil: return String(localized: "Fácil")
        case .recuperacion: return String(localized: "Recuperación")
        case .maraton: return String(localized: "Maratón")
        case .umbral: return String(localized: "Umbral")
        case .intervalo: return String(localized: "Intervalo")
        case .repeticion: return String(localized: "Repetición")
        }
    }

    static func nombre(de tipo: TipoEntrenamiento) -> String {
        switch tipo {
        case .facil: return String(localized: "Fácil")
        case .recuperacion: return String(localized: "Recuperación")
        case .largo: return String(localized: "Larga")
        case .tempo: return String(localized: "Tempo")
        case .umbral: return String(localized: "Umbral")
        case .series: return String(localized: "Series")
        case .ritmoCarrera: return String(localized: "Ritmo de carrera")
        case .testEvaluacion: return String(localized: "Evaluación")
        case .personalizado: return String(localized: "Personalizado")
        }
    }
}

/// Formateo de FECHAS de cara al usuario — UN solo lugar (build 41).
///
/// El bug real: el bundle declaraba INGLÉS como único idioma
/// (developmentRegion/knownRegions), así que la localización resuelta
/// de la app era inglés y Locale.current adentro de la app formateaba
/// "Tuesday, 11 Aug" con toda la UI en español. La causa se arregló
/// declarando `es` en el proyecto; esto además centraliza los formatos
/// que Maratonia usa de verdad — nada de nombres de días hardcodeados
/// ni diccionarios: Foundation con el Locale correcto.
enum FormatoFecha {

    /// El idioma de la APP (localización resuelta del bundle) combinado
    /// con la región del usuario (reloj de 12/24 h, etc.). Si algún día
    /// Maratonia se localiza a otro idioma, esto lo sigue solo.
    static var locale: Locale {
        let idioma = Bundle.main.preferredLocalizations.first ?? "es"
        var componentes = Locale.Components(locale: .current)
        componentes.languageComponents = Locale.Language.Components(identifier: idioma)
        return Locale(components: componentes)
    }

    /// "martes, 11 ago" — Próximos, filas del calendario, hojas.
    static func corta(_ fecha: Date, locale: Locale = FormatoFecha.locale) -> String {
        fecha.formatted(Date.FormatStyle(locale: locale)
            .weekday(.wide).day().month(.abbreviated))
    }

    /// "martes, 11 de agosto" — detalle del entrenamiento.
    static func larga(_ fecha: Date, locale: Locale = FormatoFecha.locale) -> String {
        fecha.formatted(Date.FormatStyle(locale: locale)
            .weekday(.wide).day().month(.wide))
    }

    /// "9 ago 2026" — referencias, fechas sueltas con año.
    static func media(_ fecha: Date, locale: Locale = FormatoFecha.locale) -> String {
        fecha.formatted(Date.FormatStyle(locale: locale)
            .day().month(.abbreviated).year())
    }

    /// "9 de agosto de 2026" — la postal para compartir y encabezados.
    static func completa(_ fecha: Date, locale: Locale = FormatoFecha.locale) -> String {
        fecha.formatted(Date.FormatStyle(locale: locale)
            .day().month(.wide).year())
    }

    /// "21:54" (o "9:54 p. m." según la región del usuario).
    static func hora(_ fecha: Date, locale: Locale = FormatoFecha.locale) -> String {
        fecha.formatted(Date.FormatStyle(locale: locale).hour().minute())
    }

    /// "9 ago 2026 · 21:54" — carreras (sin el "at"/"a las").
    static func fechaYHora(_ fecha: Date, locale: Locale = FormatoFecha.locale) -> String {
        media(fecha, locale: locale) + " · " + hora(fecha, locale: locale)
    }

    /// "11 ago" — compactas ("era el 11 ago").
    static func diaYMes(_ fecha: Date, locale: Locale = FormatoFecha.locale) -> String {
        fecha.formatted(Date.FormatStyle(locale: locale)
            .day().month(.abbreviated))
    }

    /// "11/8" — etiquetas mínimas (barras de volumen).
    static func numerica(_ fecha: Date, locale: Locale = FormatoFecha.locale) -> String {
        fecha.formatted(Date.FormatStyle(locale: locale)
            .day().month(.defaultDigits))
    }

    /// "mar 11/8" — chips ultra compactos (tarjeta PRÓXIMO de Correr).
    static func diaCorto(_ fecha: Date, locale: Locale = FormatoFecha.locale) -> String {
        fecha.formatted(Date.FormatStyle(locale: locale).weekday(.abbreviated))
            + " " + numerica(fecha, locale: locale)
    }

    /// "martes" — para etiquetas de accesibilidad.
    static func diaDeSemana(_ fecha: Date, locale: Locale = FormatoFecha.locale) -> String {
        fecha.formatted(Date.FormatStyle(locale: locale).weekday(.wide))
    }
}

/// Textos del objetivo deportivo — un solo lugar (los usaban Perfil,
/// Plan y onboarding por separado y ya estaban divergiendo).
enum TextosObjetivo {

    static func nombre(de objetivo: ObjetivoDeportivo) -> String {
        switch objetivo {
        case .primeros5K: return String(localized: "Mis primeros 5K")
        case .mejorar5K: return String(localized: "Mejorar mis 5K")
        case .diez: return String(localized: "Correr 10K")
        case .mediaMaraton: return String(localized: "Media maratón")
        case .maraton: return String(localized: "Maratón")
        }
    }

    /// Distancia en metros de la carrera objetivo (para filtrar el
    /// catálogo y recomendar de forma determinística).
    static func distanciaMetros(de objetivo: ObjetivoDeportivo) -> Double {
        switch objetivo {
        case .primeros5K, .mejorar5K: return 5000
        case .diez: return 10000
        case .mediaMaraton: return 21097.5
        case .maraton: return 42195
        }
    }

    /// "Faltan 14 semanas para tu carrera" — motivación con días
    /// calendario reales, jamás presión. nil = sin fecha objetivo.
    static func cuentaRegresiva(hasta fechaObjetivo: DiaLocal?, hoy: DiaLocal,
                                calendario: Calendar = .current) -> String? {
        guard let objetivo = fechaObjetivo,
              let desde = hoy.fecha(calendario: calendario),
              let hasta = objetivo.fecha(calendario: calendario),
              let dias = calendario.dateComponents([.day], from: desde, to: hasta).day
        else { return nil }
        switch dias {
        case ..<0:
            return String(localized: "La fecha de tu carrera ya pasó — actualizala cuando quieras")
        case 0:
            return String(localized: "¡Tu carrera es hoy!")
        case 1:
            return String(localized: "Tu carrera es mañana")
        case 2...13:
            return String(localized: "Faltan \(dias) días para tu carrera")
        default:
            let semanas = dias / 7
            return semanas == 1 ? String(localized: "Falta 1 semana para tu carrera")
                                : String(localized: "Faltan \(semanas) semanas para tu carrera")
        }
    }
}

/// Contenedor de tarjeta estándar: fondo secundario del sistema
/// (perfecto en claro y oscuro), radio y padding únicos.
struct TarjetaV2<Contenido: View>: View {
    @ViewBuilder var contenido: Contenido

    var body: some View {
        contenido
            .padding(DV2.Espacio.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: DV2.radioTarjeta))
    }
}

/// Etiqueta del botón de acción principal (se usa dentro de Button).
/// EL botón de Maratonia: azur → azul profundo del logo. Es el ÚNICO
/// gradiente de la app (identidad concentrada en la acción principal,
/// no decoración repartida). Blanco sobre azul: contraste AA en ambos
/// modos.
struct EtiquetaBotonPrimarioV2: View {
    var titulo: String
    var icono: String = "play.fill"

    var body: some View {
        Label(titulo, systemImage: icono)
            .font(.headline.weight(.bold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DV2.Espacio.m)
            .background(
                LinearGradient(colors: [DV2.Marca.primario, DV2.Marca.profundo],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: DV2.radioBoton))
            .shadow(color: DV2.Marca.profundo.opacity(0.25), radius: 6, y: 3)
    }
}

/// Encabezado de sección fuera de List (para pantallas de tarjetas).
struct EncabezadoSeccionV2: View {
    var texto: String

    var body: some View {
        Text(texto.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Métrica compacta: valor protagonista y título chico.
struct MetricaV2: View {
    var titulo: String
    var valor: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valor)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(titulo)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

/// Pastilla de tipo de entrenamiento (color con función de identidad).
struct ChipTipoV2: View {
    var tipo: TipoEntrenamiento

    var body: some View {
        Text(DV2.nombre(de: tipo))
            .font(.caption.weight(.semibold))
            .foregroundStyle(DV2.color(de: tipo))
            .padding(.horizontal, DV2.Espacio.s)
            .padding(.vertical, 3)
            .background(DV2.color(de: tipo).opacity(0.14), in: Capsule())
    }
}

/// LA tarjeta de entrenamiento: el "qué tengo que hacer hoy" como
/// acción principal de Maratonia — tipo, nombre, estructura, distancia
/// prevista, estado y EMPEZAR.
struct TarjetaEntrenamientoV2: View {
    let programado: EntrenamientoProgramado
    var etiqueta: String = "HOY"
    /// true = además de los números, la lista de segmentos (la pestaña
    /// Correr la muestra; el calendario no, para no saturar).
    var mostrarEstructura = false
    var alEmpezar: (() -> Void)?

    private var estado: EstadoProgramado {
        programado.estado(hoy: DiaLocal(fecha: Date()))
    }

    var body: some View {
        TarjetaV2 {
            VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                HStack {
                    // El sello de HOY: volt de marca como RELLENO con
                    // texto oscuro (regla de uso de Marca.energia).
                    Text(etiqueta)
                        .font(.caption.weight(.heavy))
                        .tracking(1.5)
                        .foregroundStyle(.black.opacity(0.8))
                        .padding(.horizontal, DV2.Espacio.s)
                        .padding(.vertical, 3)
                        .background(DV2.Marca.energia, in: Capsule())
                    Spacer()
                    ChipTipoV2(tipo: programado.definicion.tipo)
                }

                VStack(alignment: .leading, spacing: DV2.Espacio.xs) {
                    Text(programado.definicion.nombre)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DV2.Marca.profundo)
                    if !programado.definicion.descripcion.isEmpty {
                        Text(programado.definicion.descripcion)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: DV2.Espacio.xl) {
                    if let km = programado.definicion.distanciaTotalKm {
                        MetricaV2(titulo: "distancia",
                                  valor: km == km.rounded()
                                    ? "\(Int(km)) km"
                                    : String(format: "%.1f km", km))
                    }
                    if let segundos = programado.definicion.duracionPorTiempoSegundos {
                        MetricaV2(titulo: "por tiempo", valor: duracionTexto(segundos))
                    }
                    MetricaV2(titulo: "estructura",
                              valor: programado.definicion.segmentos.count == 1
                                ? "1 segmento"
                                : Plurales.segmentos(programado.definicion.segmentos.count))
                    if estado != .programado {
                        MetricaV2(titulo: "estado", valor: nombreDeEstado)
                    }
                }

                if mostrarEstructura, programado.definicion.segmentos.count > 1 {
                    VStack(alignment: .leading, spacing: DV2.Espacio.xs) {
                        ForEach(Array(programado.definicion.segmentos.enumerated()),
                                id: \.element.id) { indice, segmento in
                            HStack(spacing: DV2.Espacio.s) {
                                Text("\(indice + 1)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 16)
                                Text(segmento.nombre)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(metaDeSegmento(segmento))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(DV2.Espacio.m)
                    .background(Color(.tertiarySystemGroupedBackground),
                                in: RoundedRectangle(cornerRadius: DV2.radioBoton))
                }

                if let alEmpezar, estado == .programado || estado == .vencido {
                    Button {
                        // Haptic: arrancar un entrenamiento es EL
                        // momento de la app.
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        alEmpezar()
                    } label: {
                        EtiquetaBotonPrimarioV2(titulo: "Empezar")
                    }
                    .buttonStyle(.plain)
                } else if estado == .cumplido {
                    Label("Cumplido", systemImage: "checkmark.seal.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                } else if estado == .parcial {
                    Label("Parcial — la sesión quedó guardada", systemImage: "circle.bottomhalf.filled")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.yellow)
                }
            }
        }
    }

    private func metaDeSegmento(_ segmento: Segmento) -> String {
        DV2.metaDeSegmento(segmento)
    }

    private var nombreDeEstado: String {
        switch estado {
        case .programado: return "programado"
        case .vencido: return "vencido"
        case .parcial: return "parcial"
        case .cumplido: return "cumplido"
        case .omitido: return "omitido"
        }
    }
}
