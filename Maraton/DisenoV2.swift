import SwiftUI

// Design System V2 — FUNDACIÓN (Fase C). No es un rediseño global:
// es el lenguaje visual compartido que las pantallas nuevas usan desde
// ahora, para que dejen de construirse a mano una por una. SwiftUI
// nativo, dark mode por colores semánticos del sistema, Dynamic Type
// por fuentes de texto estándar. El color tiene FUNCIÓN: acción
// (accent), estado (verde/naranja/amarillo/gris), tipo de
// entrenamiento (identidad de la tarjeta). Nada de gradientes porque sí.

enum DV2 {

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
            return "libre"
        case .absoluto(let rapido, let lento):
            switch (rapido, lento) {
            case let (r?, l?): return "\(formatearRitmo(r))–\(formatearRitmo(l)) /km"
            case let (nil, l?): return "\(formatearRitmo(l)) /km o mejor"
            case let (r?, nil): return "sin pasar de \(formatearRitmo(r)) /km"
            default: return "libre"
            }
        case .simbolico(let tipo):
            switch Metodologias.resolver(tipo, baseline: baseline) {
            case .resuelto(let rango, _):
                return "\(formatearRitmo(rango.minSegKm))–\(formatearRitmo(rango.maxSegKm)) /km"
            case .pendiente:
                return "ritmo \(nombre(de: tipo).lowercased()) · a personalizar"
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
        let ritmo = textoRitmo(de: segmento)
        if ritmo != "libre" { partes.append(ritmo) }
        return partes.joined(separator: " · ")
    }

    static func nombre(de tipo: TipoRitmo) -> String {
        switch tipo {
        case .facil: return "Fácil"
        case .recuperacion: return "Recuperación"
        case .maraton: return "Maratón"
        case .umbral: return "Umbral"
        case .intervalo: return "Intervalo"
        case .repeticion: return "Repetición"
        }
    }

    static func nombre(de tipo: TipoEntrenamiento) -> String {
        switch tipo {
        case .facil: return "Fácil"
        case .recuperacion: return "Recuperación"
        case .largo: return "Larga"
        case .tempo: return "Tempo"
        case .umbral: return "Umbral"
        case .series: return "Series"
        case .ritmoCarrera: return "Ritmo de carrera"
        case .testEvaluacion: return "Evaluación"
        case .personalizado: return "Personalizado"
        }
    }
}

/// Textos del objetivo deportivo — un solo lugar (los usaban Perfil,
/// Plan y onboarding por separado y ya estaban divergiendo).
enum TextosObjetivo {

    static func nombre(de objetivo: ObjetivoDeportivo) -> String {
        switch objetivo {
        case .primeros5K: return "Mis primeros 5K"
        case .mejorar5K: return "Mejorar mis 5K"
        case .diez: return "Correr 10K"
        case .mediaMaraton: return "Media maratón"
        case .maraton: return "Maratón"
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
            return "La fecha de tu carrera ya pasó — actualizala cuando quieras"
        case 0:
            return "¡Tu carrera es hoy!"
        case 1:
            return "Tu carrera es mañana"
        case 2...13:
            return "Faltan \(dias) días para tu carrera"
        default:
            let semanas = dias / 7
            return semanas == 1 ? "Falta 1 semana para tu carrera"
                                : "Faltan \(semanas) semanas para tu carrera"
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
struct EtiquetaBotonPrimarioV2: View {
    var titulo: String
    var icono: String = "play.fill"

    var body: some View {
        Label(titulo, systemImage: icono)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, DV2.Espacio.m)
            .background(Color.accentColor,
                        in: RoundedRectangle(cornerRadius: DV2.radioBoton))
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
                    Text(etiqueta)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .tracking(1)
                    Spacer()
                    ChipTipoV2(tipo: programado.definicion.tipo)
                }

                VStack(alignment: .leading, spacing: DV2.Espacio.xs) {
                    Text(programado.definicion.nombre)
                        .font(.title3.weight(.bold))
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
                                : "\(programado.definicion.segmentos.count) segmentos")
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
                    Button(action: alEmpezar) {
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
