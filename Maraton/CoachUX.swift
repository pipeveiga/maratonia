import SwiftUI

// EL COACH COMO HERRAMIENTA DE DECISIÓN, NO COMO CHAT.
//
// El problema que resuelve este archivo: la respuesta del Coach era
// correcta pero se leía como documentación. Explicaba que no había día
// válido, explicaba por qué, explicaba qué proponía, y dejaba todo como
// un bloque de texto corrido. El corredor tenía que LEER para poder
// DECIDIR.
//
// La regla acá es una sola: **mostrar primero, explicar después**.
//
// - Una línea de encabezado con lo que se detectó.
// - Una línea de subtexto, si hace falta.
// - Y enseguida las salidas, como cosas tocables.
// - El porqué largo existe, pero vive en un disclosure.
//
// Nada de esto amplía lo que el Coach puede hacer: las opciones que
// llegan acá ya pasaron por `ValidadorDeCoach`. Estos componentes solo
// deciden CÓMO se ven.

// MARK: - Flujo de chips

/// Chips que envuelven solos cuando no entran en el ancho. Es un
/// `Layout` y no un `HStack` con `ScrollView` porque los días de la
/// semana tienen que verse TODOS de una: si hay que scrollear
/// horizontalmente para descubrir que el jueves existe, la elección
/// dejó de ser rápida.
struct FlujoDeChips: Layout {
    var espacio: CGFloat = DV2.Espacio.s

    private struct Fila {
        var indices: [Int] = []
        var ancho: CGFloat = 0
        var alto: CGFloat = 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews,
                      cache: inout Void) -> CGSize {
        let disponible = proposal.width ?? .infinity
        let filas = acomodar(subviews, ancho: disponible)
        let alto = filas.reduce(0) { $0 + $1.alto }
            + CGFloat(max(0, filas.count - 1)) * espacio
        let ancho = disponible.isFinite ? disponible : (filas.map(\.ancho).max() ?? 0)
        return CGSize(width: ancho, height: alto)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout Void) {
        var y = bounds.minY
        for fila in acomodar(subviews, ancho: bounds.width) {
            var x = bounds.minX
            for indice in fila.indices {
                let tamano = subviews[indice].sizeThatFits(.unspecified)
                subviews[indice].place(at: CGPoint(x: x, y: y),
                                       anchor: .topLeading,
                                       proposal: ProposedViewSize(tamano))
                x += tamano.width + espacio
            }
            y += fila.alto + espacio
        }
    }

    private func acomodar(_ subviews: Subviews, ancho: CGFloat) -> [Fila] {
        var filas: [Fila] = []
        var actual = Fila()
        for indice in subviews.indices {
            let tamano = subviews[indice].sizeThatFits(.unspecified)
            let necesario = actual.indices.isEmpty ? tamano.width
                                                   : actual.ancho + espacio + tamano.width
            if !actual.indices.isEmpty && necesario > ancho {
                filas.append(actual)
                actual = Fila()
                actual.indices = [indice]
                actual.ancho = tamano.width
                actual.alto = tamano.height
            } else {
                actual.indices.append(indice)
                actual.ancho = necesario
                actual.alto = max(actual.alto, tamano.height)
            }
        }
        if !actual.indices.isEmpty { filas.append(actual) }
        return filas
    }
}

/// Una pastilla tocable. Es la unidad más chica de decisión del Coach:
/// una palabra y un toque.
struct ChipCoach: View {
    var texto: String
    var icono: String?
    /// El chip que el dominio prefiere. Se marca con el color de marca,
    /// no con tamaño: la jerarquía no puede depender de la longitud del
    /// texto.
    var destacado = false
    var accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: DV2.Espacio.xs) {
                if let icono {
                    Image(systemName: icono).font(.caption.weight(.semibold))
                }
                Text(texto)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(destacado ? Color.white : DV2.Marca.primario)
            .padding(.horizontal, DV2.Espacio.m)
            .padding(.vertical, DV2.Espacio.s)
            .background {
                if destacado {
                    Capsule().fill(DV2.gradienteMarca)
                } else {
                    Capsule().fill(DV2.Marca.primario.opacity(0.12))
                }
            }
            .overlay(
                Capsule().strokeBorder(
                    destacado ? Color.clear : DV2.Marca.primario.opacity(0.22),
                    lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(.isButton)
    }
}

/// CoachQuickChoices — la elección guiada. Se le pasa qué mostrar y qué
/// hacer al tocar; no sabe nada del dominio.
struct EleccionRapidaCoach<Elemento: Identifiable>: View {
    var titulo: String?
    var elementos: [Elemento]
    var etiqueta: (Elemento) -> String
    var icono: (Elemento) -> String? = { _ in nil }
    var destacado: (Elemento) -> Bool = { _ in false }
    var elegir: (Elemento) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DV2.Espacio.s) {
            if let titulo {
                Text(titulo)
                    .font(DV2.Tipo.tituloChico)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            FlujoDeChips {
                ForEach(elementos) { elemento in
                    ChipCoach(texto: etiqueta(elemento),
                              icono: icono(elemento),
                              destacado: destacado(elemento)) {
                        elegir(elemento)
                    }
                }
            }
        }
    }
}

// MARK: - Tarjetas

/// El tono de una respuesta del Coach. Define el color del ícono y del
/// borde — el color tiene función, no decora.
enum TonoCoach {
    case neutro
    case atencion
    case exito
    case limite

    var color: Color {
        switch self {
        case .neutro:   return DV2.Marca.primario
        case .atencion: return DV2.Semantico.advertencia
        case .exito:    return DV2.Semantico.exito
        case .limite:   return .secondary
        }
    }
}

/// CoachDecisionCard — encabezado breve, subtexto corto, y las salidas.
///
/// El orden importa y es el del producto: primero QUÉ pasó (una línea),
/// después QUÉ se puede hacer (tocable), y al final —solo si el
/// corredor lo pide— POR QUÉ.
struct TarjetaDecisionCoach<Contenido: View>: View {
    var icono: String
    var titulo: String
    var subtitulo: String?
    /// El porqué completo. Va en disclosure: existe, pero no ocupa la
    /// pantalla.
    var detalle: String?
    var tono: TonoCoach = .neutro
    @ViewBuilder var contenido: Contenido

    var body: some View {
        TarjetaV2 {
            VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                HStack(alignment: .top, spacing: DV2.Espacio.m) {
                    Image(systemName: icono)
                        .font(.title2)
                        .foregroundStyle(tono.color)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(titulo)
                            .font(DV2.Tipo.tituloChico)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        if let subtitulo {
                            Text(subtitulo)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                contenido

                if let detalle {
                    Detalle(titulo: String(localized: "Ver por qué")) {
                        Text(detalle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

/// CoachOptionCard — una salida, como cosa tocable.
///
/// `destacada` es para cuando el dominio dejó UNA sola salida real: ahí
/// deja de ser una fila de lista y pasa a ser el CTA de la tarjeta.
struct TarjetaOpcionCoach: View {
    var icono: String
    var titulo: String
    var subtitulo: String?
    var destacada = false
    var accion: () -> Void

    var body: some View {
        Button(action: accion) {
            HStack(spacing: DV2.Espacio.m) {
                Image(systemName: icono)
                    .font(.headline)
                    .foregroundStyle(destacada ? Color.white : DV2.Marca.primario)
                    .frame(width: 26)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(destacada ? Color.white : .primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitulo {
                        Text(subtitulo)
                            .font(.caption)
                            .foregroundStyle(destacada ? Color.white.opacity(0.85)
                                                       : Color.secondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(destacada ? Color.white.opacity(0.9)
                                               : Color.secondary.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(DV2.Espacio.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if destacada {
                    RoundedRectangle(cornerRadius: DV2.radioBoton, style: .continuous)
                        .fill(DV2.gradienteMarca)
                        .shadow(color: DV2.Sombra.colorAccion, radius: 10, y: 4)
                } else {
                    RoundedRectangle(cornerRadius: DV2.radioBoton, style: .continuous)
                        .fill(DV2.Superficie.fondo)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: DV2.radioBoton, style: .continuous)
                    .strokeBorder(destacada ? Color.clear : DV2.Superficie.borde,
                                  lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

/// CoachResultCard — "esto propongo" / "esto quedó". Mismo esqueleto que
/// la de decisión, pero con estado: el ícono y el color los decide el
/// resultado, no quien la llama.
struct TarjetaResultadoCoach<Contenido: View>: View {
    enum Estado {
        case propuesta
        case aplicado
        case sinCambios
        case rechazado

        var icono: String {
            switch self {
            case .propuesta:   return "wand.and.stars"
            case .aplicado:    return "checkmark.circle.fill"
            case .sinCambios:  return "checkmark.seal"
            case .rechazado:   return "exclamationmark.triangle.fill"
            }
        }

        var tono: TonoCoach {
            switch self {
            case .propuesta:  return .neutro
            case .aplicado:   return .exito
            case .sinCambios: return .exito
            case .rechazado:  return .atencion
            }
        }
    }

    var estado: Estado
    var titulo: String
    var subtitulo: String?
    var detalle: String?
    @ViewBuilder var contenido: Contenido

    var body: some View {
        TarjetaDecisionCoach(icono: estado.icono, titulo: titulo,
                             subtitulo: subtitulo, detalle: detalle,
                             tono: estado.tono) {
            contenido
        }
    }
}

/// ANTES → DESPUÉS en una línea. Reemplaza al párrafo que describía el
/// cambio con palabras: un cambio de día es una flecha, no una oración.
struct FilaCambioCoach: View {
    var nombre: String
    var antes: String?
    var despues: String
    var rechazo: String?

    var body: some View {
        VStack(alignment: .leading, spacing: DV2.Espacio.xs) {
            Text(nombre)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
            HStack(spacing: DV2.Espacio.s) {
                if let antes {
                    Text(antes)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .strikethrough(rechazo == nil, color: .secondary)
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(despues)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(rechazo == nil ? DV2.Marca.primario
                                                    : Color.secondary)
            }
            if let rechazo {
                Label(rechazo, systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(DV2.Semantico.destructivo)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(DV2.Espacio.m)
        .background(DV2.Superficie.fondo,
                    in: RoundedRectangle(cornerRadius: DV2.radioBoton, style: .continuous))
    }
}

/// El CTA secundario del Coach: "dejalo como está", "probar otra cosa".
/// Existe para que el primario pueda ser uno solo y evidente.
struct BotonSecundarioCoach: View {
    var titulo: String
    var icono: String
    var accion: () -> Void

    var body: some View {
        Button(action: accion) {
            Label(titulo, systemImage: icono)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(DV2.Marca.primario)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DV2.Espacio.m)
                .background(DV2.Marca.primario.opacity(0.10),
                            in: RoundedRectangle(cornerRadius: DV2.radioBoton,
                                                 style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
