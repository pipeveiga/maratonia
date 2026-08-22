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
    static func carreras(_ n: Int) -> String {
        n == 1 ? String(localized: "1 carrera") : String(localized: "\(n) carreras")
    }
    static func semanas(_ n: Int) -> String {
        n == 1 ? String(localized: "1 semana") : String(localized: "\(n) semanas")
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
        /// El filo de la tarjeta. En claro casi no se ve; en oscuro es
        /// lo único que separa una superficie de otra (ahí el fondo y
        /// la tarjeta están a dos puntos de luminancia).
        static let borde = Color(.separator).opacity(0.45)
    }

    /// TIPOGRAFÍA — la voz de Maratonia.
    ///
    /// `.rounded` para números y titulares: es lo que separa una app
    /// deportiva de un formulario. Siempre construida sobre un TEXT
    /// STYLE (`.title2`, `.headline`…) y nunca sobre un tamaño fijo, así
    /// que Dynamic Type sigue escalando todo — un `.system(size: 34)`
    /// se ve igual de grande para quien necesita el cuerpo al doble.
    enum Tipo {
        /// Titular de tarjeta: el nombre del entrenamiento, el objetivo.
        static let titulo = Font.system(.title2, design: .rounded).weight(.bold)
        static let tituloChico = Font.system(.headline, design: .rounded).weight(.bold)
        /// EL número: distancia, semanas, km/sem. Monoespaciado en los
        /// dígitos para que no bailen cuando cambian solos.
        static let numero = Font.system(.title3, design: .rounded)
            .weight(.semibold).monospacedDigit()
        /// El número protagonista (héroe, marcas grandes).
        static let numeroGrande = Font.system(.title, design: .rounded)
            .weight(.bold).monospacedDigit()
        /// La etiqueta que acompaña a un número. Va en mayúsculas por
        /// modificador (`.textCase`), nunca por `.uppercased()`: sobre
        /// un String eso rompe la traducción.
        static let etiqueta = Font.caption2.weight(.semibold)
        /// Sellos y badges: HOY, MAÑANA, CUANDO QUIERAS.
        static let sello = Font.caption.weight(.heavy)
    }

    /// ELEVACIÓN — una sola sombra para toda la app. Suave y baja: la
    /// tarjeta tiene que despegarse del fondo, no flotar.
    enum Sombra {
        static let color = Color.black.opacity(0.07)
        static let radio: CGFloat = 12
        static let y: CGFloat = 4
        /// La del CTA de marca: más marcada y teñida, porque es la
        /// única pieza de la pantalla que pide ser tocada.
        static let colorAccion = DV2.Marca.profundo.opacity(0.28)
    }

    /// El gradiente de marca (azur → azul profundo del logo). Vive acá y
    /// no repetido por pantalla: es la identidad, y la identidad no se
    /// escribe dos veces.
    static var gradienteMarca: LinearGradient {
        LinearGradient(colors: [Marca.primario, Marca.profundo],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// El mismo gradiente para superficies grandes, arrancando del azul
    /// profundo: sobre un área extensa el azur puro satura y se come el
    /// texto blanco.
    static var gradienteSuperficie: LinearGradient {
        LinearGradient(colors: [Marca.profundo, Marca.primario],
                       startPoint: .top, endPoint: .bottomTrailing)
    }

    /// RAMPA DE INTENSIDAD — el recorrido pintado por ritmo.
    ///
    /// Secuencial de UN SOLO TONO, claro → oscuro: el dato es magnitud
    /// (cuánto empujaste), no polaridad, y un arcoíris haría que dos
    /// tramos parecidos se vean de colores opuestos. Cálida a propósito:
    /// se lee como calor y no compite con el azul de la marca ni con el
    /// agua del mapa.
    ///
    /// Los pasos son monótonos en luminosidad (0.68 → 0.10), que es la
    /// regla real de una rampa secuencial. Como los extremos no llegan a
    /// 3:1 contra toda superficie posible, la línea SIEMPRE va con un
    /// casing debajo — ver `TrazoConCasing`.
    enum Intensidad {
        static let pasos: [Color] = [
            Color(red: 1.00, green: 0.82, blue: 0.54),   // #FFD08A
            Color(red: 0.98, green: 0.66, blue: 0.30),   // #FBA94C
            Color(red: 0.94, green: 0.48, blue: 0.16),   // #F07A28
            Color(red: 0.85, green: 0.31, blue: 0.06),   // #D8500F
            Color(red: 0.64, green: 0.17, blue: 0.02),   // #A32B06
        ]

        /// El color de un tramo. `intensidad` va de 0 (lo más lento de
        /// esa carrera) a 1 (lo más rápido).
        static func color(_ intensidad: Double) -> Color {
            let acotada = min(1, max(0, intensidad))
            let indice = Int((acotada * Double(pasos.count - 1)).rounded())
            return pasos[indice]
        }

        static var degradado: LinearGradient {
            LinearGradient(colors: pasos, startPoint: .leading, endPoint: .trailing)
        }
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

    static let radioTarjeta: CGFloat = 20
    static let radioBoton: CGFloat = 14

    /// La forma de la tarjeta — `.continuous`, que es la curva de iOS.
    /// Un `RoundedRectangle` normal a radio 20 se nota anguloso al lado
    /// de los controles del sistema.
    static var formaTarjeta: RoundedRectangle {
        RoundedRectangle(cornerRadius: radioTarjeta, style: .continuous)
    }

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
            case let (r?, l?): return Unidades.rangoDeRitmo(r, l)
            case let (nil, l?): return String(localized: "\(Unidades.ritmo(segundosPorKm: l)) o mejor")
            case let (r?, nil): return String(localized: "sin pasar de \(Unidades.ritmo(segundosPorKm: r))")
            default: return String(localized: "libre")
            }
        case .simbolico(let tipo):
            switch Metodologias.resolver(tipo, baseline: baseline) {
            case .resuelto(let rango, _):
                return Unidades.rangoDeRitmo(rango.minSegKm, rango.maxSegKm)
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
            partes.append(Unidades.distancia(km: km))
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
        case .mejorar10K: return String(localized: "Mejorar mis 10K")
        case .mediaMaraton: return String(localized: "Media maratón")
        case .mejorarMedia: return String(localized: "Mejorar mi media")
        case .mediaRendimiento: return String(localized: "Media · rendimiento")
        case .maraton: return String(localized: "Maratón")
        case .mejorarMaraton: return String(localized: "Mejorar mi maratón")
        case .maratonRendimiento: return String(localized: "Maratón · rendimiento")
        }
    }

    static func nombre(de distancia: DistanciaObjetivo) -> String {
        switch distancia {
        case .cinco: return String(localized: "5 km")
        case .diez: return String(localized: "10 km")
        case .media: return String(localized: "Media maratón")
        case .maraton: return String(localized: "Maratón")
        }
    }

    static func nombre(de intencion: IntencionObjetivo) -> String {
        switch intencion {
        case .completar: return String(localized: "Completarla")
        case .mejorar: return String(localized: "Mejorar mi marca")
        case .rendimiento: return String(localized: "Buscar mi techo")
        }
    }

    static func detalle(de intencion: IntencionObjetivo) -> String {
        switch intencion {
        case .completar: return String(localized: "Todavía no la corrí, o quiero terminarla entera y bien.")
        case .mejorar: return String(localized: "Ya la corro — ahora quiero bajar el tiempo.")
        case .rendimiento: return String(localized: "Máxima carga y especificidad. Necesita base real.")
        }
    }

    /// Distancia en metros de la carrera objetivo (para filtrar el
    /// catálogo y recomendar de forma determinística).
    static func distanciaMetros(de objetivo: ObjetivoDeportivo) -> Double {
        objetivo.distancia.metros
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
            // Acá solo se llega con 14 días o más, así que semanas >= 2
            // siempre: hasta 13 días la cuenta va en DÍAS (más preciso).
            let semanas = dias / 7
            return String(localized: "Faltan \(semanas) semanas para tu carrera")
        }
    }
}

/// LA superficie de tarjeta de Maratonia: fondo secundario del sistema,
/// filo de un pelo y una sombra baja.
///
/// Antes la tarjeta era un rectángulo plano del color del sistema. Sobre
/// el fondo agrupado eso da casi cero contraste —en oscuro directamente
/// ninguno— y la pantalla se leía como una lista de bloques del mismo
/// gris. El borde resuelve el modo oscuro y la sombra el claro; juntos
/// hacen que la tarjeta sea un objeto y no una zona.
///
/// Es un modificador y no dos structs para que `TarjetaV2` y `Tarjeta`
/// (que existen por historia) no puedan volver a divergir.
struct SuperficieTarjeta: ViewModifier {
    var relleno: CGFloat = DV2.Espacio.l

    func body(content: Content) -> some View {
        content
            .padding(relleno)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DV2.Superficie.tarjeta, in: DV2.formaTarjeta)
            .overlay(DV2.formaTarjeta.strokeBorder(DV2.Superficie.borde, lineWidth: 0.5))
            .shadow(color: DV2.Sombra.color, radius: DV2.Sombra.radio, y: DV2.Sombra.y)
    }
}

extension View {
    /// Convierte cualquier contenido en una tarjeta Maratonia.
    func superficieDeTarjeta(relleno: CGFloat = DV2.Espacio.l) -> some View {
        modifier(SuperficieTarjeta(relleno: relleno))
    }
}

/// Contenedor de tarjeta estándar.
struct TarjetaV2<Contenido: View>: View {
    @ViewBuilder var contenido: Contenido

    var body: some View {
        contenido.superficieDeTarjeta()
    }
}

/// Etiqueta del botón de acción principal (se usa dentro de Button).
/// EL botón de Maratonia: azur → azul profundo del logo. Es el ÚNICO
/// gradiente de la app (identidad concentrada en la acción principal,
/// no decoración repartida). Blanco sobre azul: contraste AA en ambos
/// modos.
struct EtiquetaBotonPrimarioV2: View {
    var titulo: LocalizedStringKey
    var icono: String = "play.fill"

    var body: some View {
        Label(titulo, systemImage: icono)
            .font(DV2.Tipo.tituloChico)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DV2.Espacio.m + 2)
            .background(DV2.gradienteMarca,
                        in: RoundedRectangle(cornerRadius: DV2.radioBoton,
                                             style: .continuous))
            .shadow(color: DV2.Sombra.colorAccion, radius: 10, y: 4)
    }
}

/// El CTA cuando el fondo YA es el gradiente de marca (tarjeta
/// protagonista). Ahí el botón azul desaparece dentro de la tarjeta: se
/// invierte a sólido blanco con el texto en azul profundo, que sobre el
/// gradiente es la pieza de mayor contraste de toda la pantalla.
struct EtiquetaBotonInvertidoV2: View {
    var titulo: LocalizedStringKey
    var icono: String = "play.fill"

    var body: some View {
        Label(titulo, systemImage: icono)
            .font(DV2.Tipo.tituloChico)
            .foregroundStyle(DV2.Marca.profundo)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DV2.Espacio.m + 2)
            .background(.white,
                        in: RoundedRectangle(cornerRadius: DV2.radioBoton,
                                             style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
    }
}

/// Encabezado de sección fuera de List (para pantallas de tarjetas).
struct EncabezadoSeccionV2: View {
    var texto: LocalizedStringKey

    var body: some View {
        // .uppercased() sobre un String rompía la traducción: el
        // mayusculeo va como modificador, no sobre el texto.
        Text(texto)
            .textCase(.uppercase)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Métrica compacta: valor protagonista y título chico.
/// titulo va como LocalizedStringKey: Text(unString) NO traduce —
/// solo el literal tipado como clave pasa por el catálogo. `valor`
/// sí es String: son números ya formateados.
struct MetricaV2: View {
    var titulo: LocalizedStringKey
    var valor: String
    /// La métrica va sobre el gradiente de marca (tarjeta protagonista):
    /// el color secundario del sistema es ilegible ahí.
    var sobreOscuro = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(valor)
                .font(DV2.Tipo.numero)
                .foregroundStyle(sobreOscuro ? AnyShapeStyle(Color.white)
                                             : AnyShapeStyle(HierarchicalShapeStyle.primary))
            Text(titulo)
                .font(DV2.Tipo.etiqueta)
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(sobreOscuro ? AnyShapeStyle(Color.white.opacity(0.72))
                                             : AnyShapeStyle(HierarchicalShapeStyle.secondary))
        }
    }
}

/// Pastilla de tipo de entrenamiento (color con función de identidad).
struct ChipTipoV2: View {
    var tipo: TipoEntrenamiento
    /// Sobre el gradiente de marca el color del tipo pierde legibilidad
    /// (un índigo o un morado sobre azul profundo no se leen), así que
    /// ahí la identidad la lleva el texto blanco sobre vidrio.
    var sobreOscuro = false

    var body: some View {
        Text(DV2.nombre(de: tipo))
            .font(.caption.weight(.semibold))
            .foregroundStyle(sobreOscuro ? Color.white : DV2.color(de: tipo))
            .padding(.horizontal, DV2.Espacio.s)
            .padding(.vertical, 3)
            .background(sobreOscuro ? Color.white.opacity(0.18)
                                    : DV2.color(de: tipo).opacity(0.14),
                        in: Capsule())
    }
}

/// LA tarjeta de entrenamiento: el "qué tengo que hacer hoy" como
/// acción principal de Maratonia — tipo, nombre, estructura, distancia
/// prevista, estado y EMPEZAR.
struct TarjetaEntrenamientoV2: View {
    let programado: EntrenamientoProgramado
    // String YA localizado (no LocalizedStringKey): `Text(unString)`
    // usa la sobrecarga que NO traduce, así que el default tiene que
    // venir traducido de origen. Con `"HOY"` pelado, el sello salía en
    // español con toda la app en inglés.
    var etiqueta: String = String(localized: "HOY")
    /// true = además de los números, la lista de segmentos (la pestaña
    /// Correr la muestra; el calendario no, para no saturar).
    var mostrarEstructura = false
    var alEmpezar: (() -> Void)?

    private var estado: EstadoProgramado {
        programado.estado(hoy: DiaLocal(fecha: Date()))
    }

    /// La tarjeta que se puede EMPEZAR ahora mismo es el protagonista de
    /// la pantalla y se dibuja sobre el gradiente de marca. El resto —lo
    /// ya cumplido, lo que viene mañana— es contexto y va en superficie
    /// normal.
    ///
    /// La regla se deriva del dominio en vez de pedirse por parámetro:
    /// coincide EXACTAMENTE con cuándo aparece el botón "Empezar", así
    /// que no puede haber una tarjeta destacada sin acción ni una acción
    /// sin destacar.
    private var esProtagonista: Bool {
        alEmpezar != nil && (estado == .programado || estado == .vencido)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DV2.Espacio.m) {
            HStack {
                // El sello: sobre el gradiente va en blanco sobre vidrio;
                // en la tarjeta normal, relleno suave del primario.
                Text(etiqueta)
                    .font(DV2.Tipo.sello)
                    .tracking(1.5)
                    .foregroundStyle(esProtagonista ? Color.white : DV2.Marca.primario)
                    .padding(.horizontal, DV2.Espacio.s)
                    .padding(.vertical, 3)
                    .background(esProtagonista ? Color.white.opacity(0.2)
                                               : DV2.Marca.primario.opacity(0.15),
                                in: Capsule())
                Spacer()
                ChipTipoV2(tipo: programado.definicion.tipo,
                           sobreOscuro: esProtagonista)
            }

            VStack(alignment: .leading, spacing: DV2.Espacio.xs) {
                Text(programado.definicion.nombre)
                    .font(esProtagonista ? DV2.Tipo.numeroGrande : DV2.Tipo.titulo)
                    .foregroundStyle(esProtagonista ? Color.white : DV2.Marca.profundo)
                    .fixedSize(horizontal: false, vertical: true)
                if !programado.definicion.descripcion.isEmpty {
                    Text(programado.definicion.descripcion)
                        .font(.subheadline)
                        .foregroundStyle(esProtagonista
                                         ? AnyShapeStyle(Color.white.opacity(0.8))
                                         : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: DV2.Espacio.xl) {
                if let km = programado.definicion.distanciaPrescritaKm {
                    MetricaV2(titulo: "distancia",
                              valor: Unidades.distancia(km: km),
                              sobreOscuro: esProtagonista)
                }
                if let segundos = programado.definicion.duracionPorTiempoSegundos {
                    MetricaV2(titulo: "por tiempo", valor: duracionTexto(segundos),
                              sobreOscuro: esProtagonista)
                }
                MetricaV2(titulo: "estructura",
                          // `Plurales` YA resuelve el singular y además localiza: el
                          // ternario con `"1 segmento"` pelado se saltaba el
                          // catálogo y dejaba esa palabra en español con la app
                          // en inglés.
                          valor: Plurales.segmentos(programado.definicion.segmentos.count),
                          sobreOscuro: esProtagonista)
                if estado != .programado {
                    MetricaV2(titulo: "estado", valor: nombreDeEstado,
                              sobreOscuro: esProtagonista)
                }
            }

            if mostrarEstructura, programado.definicion.segmentos.count > 1 {
                VStack(alignment: .leading, spacing: DV2.Espacio.xs) {
                    ForEach(Array(programado.definicion.segmentos.enumerated()),
                            id: \.element.id) { indice, segmento in
                        HStack(spacing: DV2.Espacio.s) {
                            Text("\(indice + 1)")
                                .font(.caption2.weight(.bold))
                                .frame(width: 16)
                                .foregroundStyle(esProtagonista
                                                 ? AnyShapeStyle(Color.white.opacity(0.6))
                                                 : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                            Text(segmento.nombre)
                                .font(.caption)
                                .lineLimit(1)
                                .foregroundStyle(esProtagonista ? Color.white : Color.primary)
                            Spacer()
                            Text(metaDeSegmento(segmento))
                                .font(.caption)
                                .foregroundStyle(esProtagonista
                                                 ? AnyShapeStyle(Color.white.opacity(0.72))
                                                 : AnyShapeStyle(HierarchicalShapeStyle.secondary))
                        }
                    }
                }
                .padding(DV2.Espacio.m)
                .background(esProtagonista
                            ? AnyShapeStyle(Color.white.opacity(0.12))
                            : AnyShapeStyle(Color(.tertiarySystemGroupedBackground)),
                            in: RoundedRectangle(cornerRadius: DV2.radioBoton,
                                                 style: .continuous))
            }

            if let alEmpezar, estado == .programado || estado == .vencido {
                Button {
                    // Haptic: arrancar un entrenamiento es EL
                    // momento de la app.
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    alEmpezar()
                } label: {
                    EtiquetaBotonInvertidoV2(titulo: "Empezar")
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
        .padding(DV2.Espacio.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if esProtagonista {
                DV2.gradienteSuperficie.clipShape(DV2.formaTarjeta)
            } else {
                DV2.Superficie.tarjeta.clipShape(DV2.formaTarjeta)
            }
        }
        .overlay(DV2.formaTarjeta.strokeBorder(
            esProtagonista ? Color.white.opacity(0.14) : DV2.Superficie.borde,
            lineWidth: 0.5))
        .shadow(color: esProtagonista ? DV2.Sombra.colorAccion : DV2.Sombra.color,
                radius: esProtagonista ? 18 : DV2.Sombra.radio,
                y: esProtagonista ? 8 : DV2.Sombra.y)
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
