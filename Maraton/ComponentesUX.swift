import SwiftUI

// COMPONENTES DE PRODUCTO (sprint de cierre 1.0).
//
// La app venía comunicando con párrafos: cada pantalla explicaba en
// prosa lo que podía mostrarse. El resultado se leía como un Settings
// con un motor deportivo atrás. Estas piezas existen para invertir eso:
// primero el estado y el número, la explicación solo si el corredor la
// pide.
//
// Reglas que siguen todas:
// - tokens DV2, nada de hex sueltos ni gradients decorativos;
// - System colors para lo semántico (verde/naranja/rojo), que es lo que
//   mantiene el significado nativo y la accesibilidad;
// - Dynamic Type sin recortes: nada de `.lineLimit(1)` sobre texto que
//   el corredor necesita leer;
// - VoiceOver: cada visual trae su equivalente hablado, porque un
//   gráfico sin etiqueta es peor que el párrafo que reemplazó;
// - Reduce Motion respetado.

// MARK: - Estado de un objetivo para ESTE corredor

/// El semáforo de la app: listo / se puede con arranque prudente /
/// primero base. Un chip, no un párrafo.
struct ChipEstado: View {
    enum Tono { case listo, prudente, base, neutro }
    var texto: String
    var tono: Tono
    var icono: String
    /// Compacto = solo icono + texto corto, para filas de lista.
    var compacto = false

    private var color: Color {
        switch tono {
        case .listo: return DV2.Semantico.exito
        case .prudente: return DV2.Marca.primario
        case .base: return DV2.Semantico.advertencia
        case .neutro: return .secondary
        }
    }

    var body: some View {
        Label {
            Text(texto)
        } icon: {
            Image(systemName: icono)
        }
        .font(compacto ? .caption2.weight(.semibold) : .subheadline.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, compacto ? DV2.Espacio.s : DV2.Espacio.m)
        .padding(.vertical, compacto ? 3 : 6)
        .background(color.opacity(0.12), in: Capsule())
    }
}

extension EstadoDeObjetivo {
    var chip: ChipEstado {
        switch nivel {
        case .listo:
            return ChipEstado(texto: String(localized: "Ideal para vos"),
                              tono: .listo, icono: "checkmark.circle.fill")
        case .conservador:
            return ChipEstado(texto: String(localized: "Arranque prudente"),
                              tono: .prudente, icono: "arrow.down.right.circle.fill")
        case .faltaBase:
            return ChipEstado(texto: String(localized: "Primero, base"),
                              tono: .base, icono: "figure.strengthtraining.functional")
        }
    }
}

// MARK: - Comparación "vos" contra "el plan"

/// Una barra con dos marcas: dónde estás y qué pide el plan. Reemplaza
/// tres filas de texto ("Volumen semanal: 43 km", "Tu actividad: 30
/// km", "Te faltan 13 km") por una lectura de medio segundo.
struct BarraComparativa: View {
    var titulo: String
    var tuyo: Double
    var pedido: Double
    var unidad: String
    /// Cuántos decimales muestra (0 para km redondos).
    var decimales: Int = 0

    private var alcanza: Bool { tuyo >= pedido }
    private var fraccion: Double {
        guard pedido > 0 else { return 1 }
        return min(1, max(0.04, tuyo / pedido))
    }
    private var color: Color {
        alcanza ? DV2.Semantico.exito : DV2.Marca.primario
    }
    private func medida(_ valor: Double) -> String {
        String(format: "%.\(decimales)f %@", valor, unidad)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DV2.Espacio.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(titulo)
                    .font(.subheadline.weight(.medium))
                Spacer(minLength: DV2.Espacio.s)
                Text(medida(tuyo))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(color)
                Text("/")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text(medida(pedido))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color(.tertiarySystemFill))
                    Capsule()
                        .fill(color)
                        .frame(width: geo.size.width * fraccion)
                }
            }
            .frame(height: 8)
            .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(titulo)
        .accessibilityValue(alcanza
            ? String(localized: "\(medida(tuyo)), alcanza los \(medida(pedido)) que pide el plan")
            : String(localized: "\(medida(tuyo)) de los \(medida(pedido)) que pide el plan"))
    }
}

/// La MISMA barra, para magnitudes de DISTANCIA. Existe para que el
/// llamador no tenga que saber en qué unidad está el corredor: recibe
/// kilómetros canónicos —que es lo que guarda el dominio— y convierte
/// adentro. Sin esto, cada pantalla que compara volúmenes tendría su
/// propia conversión, que es justo lo que la capa de unidades evita.
struct BarraComparativaDistancia: View {
    var titulo: String
    var tuyoKm: Double
    var pedidoKm: Double

    var body: some View {
        BarraComparativa(titulo: titulo,
                         tuyo: Unidades.distanciaMostrable(km: tuyoKm),
                         pedido: Unidades.distanciaMostrable(km: pedidoKm),
                         unidad: Unidades.actual.etiquetaDistancia)
    }
}

// MARK: - Métrica suelta

/// Un número grande con su etiqueta. La unidad de construcción del
/// resumen del corredor.
struct Metrica: View {
    var valor: String
    var etiqueta: String
    var icono: String?
    var color: Color = .primary
    var alineacion: HorizontalAlignment = .leading

    var body: some View {
        VStack(alignment: alineacion, spacing: 2) {
            HStack(spacing: DV2.Espacio.xs) {
                if let icono {
                    Image(systemName: icono)
                        .font(.caption)
                        .foregroundStyle(color)
                }
                Text(valor)
                    .font(DV2.Tipo.numero)
                    .foregroundStyle(color)
            }
            Text(etiqueta)
                .font(DV2.Tipo.etiqueta)
                .tracking(0.6)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
        }
        .frame(maxWidth: .infinity, alignment: alineacion == .leading ? .leading : .center)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tarjeta

/// Superficie de tarjeta consistente. Existe para poder salir de
/// `List`/`Form` sin que cada pantalla invente su propio fondo.
struct Tarjeta<Contenido: View>: View {
    var relleno: CGFloat = DV2.Espacio.l
    @ViewBuilder var contenido: Contenido

    var body: some View {
        // La MISMA superficie que TarjetaV2 (`SuperficieTarjeta`): dos
        // contenedores de tarjeta ya existían por historia, y cada uno
        // con su fondo era la vía directa a que la app tuviera dos
        // tarjetas distintas según qué pantalla la dibujó.
        contenido.superficieDeTarjeta(relleno: relleno)
    }
}

// MARK: - Estado vacío

/// Lo que se ve cuando TODAVÍA no hay nada. Existe porque una pantalla
/// vacía con las cajas de siempre a cero no se lee como "recién
/// empezás": se lee como rota. Un icono, una frase y —si hay algo que
/// hacer— la acción. Nunca un párrafo explicando la ausencia.
struct EstadoVacio: View {
    var icono: String
    var titulo: String
    var detalle: String
    var accion: (texto: String, hacer: () -> Void)?

    var body: some View {
        Tarjeta {
            VStack(spacing: DV2.Espacio.m) {
                Image(systemName: icono)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .foregroundStyle(DV2.Marca.primario.opacity(0.55))
                VStack(spacing: DV2.Espacio.xs) {
                    Text(titulo)
                        .font(DV2.Tipo.tituloChico)
                        .multilineTextAlignment(.center)
                    Text(detalle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let accion {
                    Button(action: accion.hacer) {
                        EtiquetaBotonPrimarioV2(titulo: LocalizedStringKey(accion.texto),
                                                icono: "arrow.right")
                    }
                    .buttonStyle(.plain)
                    .padding(.top, DV2.Espacio.xs)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DV2.Espacio.m)
        }
    }
}

// MARK: - Disclosure progresivo

/// "Ver requisitos", "Cómo se calcula", "Cómo funciona este plan". Lo
/// técnico existe y es accesible, pero no ocupa la pantalla principal.
struct Detalle<Contenido: View>: View {
    var titulo: String
    var icono: String = "chevron.down"
    @State private var abierto = false
    @ViewBuilder var contenido: Contenido

    var body: some View {
        VStack(alignment: .leading, spacing: DV2.Espacio.m) {
            Button {
                withAnimation(.snappy(duration: 0.22)) { abierto.toggle() }
            } label: {
                HStack(spacing: DV2.Espacio.xs) {
                    Text(titulo)
                        .font(.subheadline.weight(.medium))
                    Image(systemName: icono)
                        .font(.caption2.weight(.bold))
                        .rotationEffect(.degrees(abierto ? 180 : 0))
                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(DV2.Marca.primario)
            .accessibilityHint(abierto
                ? String(localized: "Tocá para ocultar")
                : String(localized: "Tocá para ver más"))

            if abierto { contenido }
        }
    }
}

// MARK: - Viabilidad de una fecha

/// Lo que la pantalla de fecha tiene que responder en vivo: ¿alcanza el
/// tiempo? Se calcula con las MISMAS reglas del motor —semanas mínimas
/// del arquetipo— así que no puede decir una cosa y el motor otra.
struct Viabilidad {
    var semanasDisponibles: Int
    var semanasNecesarias: Int
    var alcanza: Bool { semanasDisponibles >= semanasNecesarias }
    var faltan: Int { max(0, semanasNecesarias - semanasDisponibles) }

    init?(objetivo: ObjetivoDeportivo?, fecha: DiaLocal?, hoy: DiaLocal,
          calendario: Calendar = .current,
          biblioteca: [PlanArquetipo] = BibliotecaArquetipos.v1()) {
        guard let objetivo, let fecha,
              let arquetipo = biblioteca.first(where: { $0.objetivo == objetivo })
        else { return nil }
        semanasDisponibles = MotorPlanificacion.semanasEntre(hoy, y: fecha,
                                                             calendario: calendario)
        semanasNecesarias = arquetipo.semanasMinimas
    }
}

/// El estado de la fecha, en vivo, sin párrafos.
struct EstadoDeFecha: View {
    var viabilidad: Viabilidad

    var body: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                HStack(spacing: DV2.Espacio.xl) {
                    Metrica(valor: "\(viabilidad.semanasDisponibles)",
                            etiqueta: String(localized: "Disponibles"),
                            color: viabilidad.alcanza ? .primary : DV2.Semantico.advertencia)
                    Metrica(valor: "\(viabilidad.semanasNecesarias)",
                            etiqueta: String(localized: "Necesita el plan"))
                }
                Divider()
                if viabilidad.alcanza {
                    ChipEstado(texto: String(localized: "La fecha da"),
                               tono: .listo, icono: "checkmark.circle.fill")
                } else {
                    ChipEstado(
                        texto: String(localized: "Faltan \(viabilidad.faltan) semanas"),
                        tono: .base, icono: "exclamationmark.triangle.fill")
                }
            }
        }
    }
}

// MARK: - "No llegamos": el objetivo elegido no produjo plan

/// La pantalla que faltaba. Antes el motor decía que no y esa respuesta
/// moría ahí: el perfil quedaba con el objetivo puesto y la app mostraba
/// la cuenta regresiva de una carrera sin plan detrás.
///
/// No es un error ni un reto: es un desvío con salidas concretas.
struct AvisoSinPlan: View {
    var motivo: MotivoSinPlan
    var objetivo: ObjetivoDeportivo?
    var puente: ObjetivoDeportivo?
    /// Qué hacer con cada acción. La vista no decide nada.
    var alElegir: (AccionSinPlan) -> Void

    private var titulo: String {
        switch motivo {
        case .fechaDemasiadoCerca:
            return String(localized: "No llegamos con un plan seguro para esa fecha")
        case .diasInsuficientes:
            return String(localized: "Ese objetivo necesita más días por semana")
        case .faltaBase:
            return String(localized: "Todavía no: primero hay que construir base")
        case .faltaReferencia:
            return String(localized: "Falta una referencia de ritmo")
        case .sinContenido:
            return String(localized: "Ese plan está en camino")
        }
    }

    private var explicacion: String {
        switch motivo {
        case .fechaDemasiadoCerca:
            return String(localized: "Comprimir el plan sería venderte semanas que no se sostienen.")
        case .diasInsuficientes:
            return String(localized: "Con menos días la tirada larga domina la semana y deja de ser ese plan.")
        case .faltaBase:
            return String(localized: "No es un “no”: es un “todavía no”.")
        case .faltaReferencia:
            return String(localized: "Con una marca reciente los ritmos salen personalizados.")
        case .sinContenido:
            return String(localized: "No vamos a inventar contenido deportivo para llenar la pantalla.")
        }
    }

    var body: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: DV2.Espacio.l) {
                VStack(alignment: .leading, spacing: DV2.Espacio.s) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.title2)
                        .foregroundStyle(DV2.Semantico.advertencia)
                    Text(titulo)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(explicacion)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: DV2.Espacio.s) {
                    ForEach(Array(motivo.accionesSugeridas.enumerated()), id: \.offset) { indice, accion in
                        botón(accion, principal: indice == 0)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func botón(_ accion: AccionSinPlan, principal: Bool) -> some View {
        // El puente solo se ofrece si el dominio realmente lo define.
        if accion != .objetivoPuente || puente != nil {
            Button {
                alElegir(accion)
            } label: {
                Label(texto(de: accion), systemImage: icono(de: accion))
                    .font(.subheadline.weight(principal ? .semibold : .regular))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, DV2.Espacio.s)
            }
            .buttonStyle(.borderedProminent)
            .tint(principal ? DV2.Marca.primario : Color(.tertiarySystemFill))
            .foregroundStyle(principal ? Color.white : Color.primary)
        }
    }

    private func texto(de accion: AccionSinPlan) -> String {
        switch accion {
        case .cambiarFecha: return String(localized: "Elegir otra fecha")
        case .cambiarObjetivo: return String(localized: "Elegir otro objetivo")
        case .ajustarDisponibilidad: return String(localized: "Ajustar mis días")
        case .hacerTest: return String(localized: "Hacer el Test 5K")
        case .objetivoPuente:
            guard let puente else { return String(localized: "Empezar por otro objetivo") }
            return String(localized: "Empezar por \(TextosObjetivo.nombre(de: puente))")
        }
    }

    private func icono(de accion: AccionSinPlan) -> String {
        switch accion {
        case .cambiarFecha: return "calendar"
        case .cambiarObjetivo: return "flag.checkered"
        case .ajustarDisponibilidad: return "calendar.badge.clock"
        case .hacerTest: return "stopwatch"
        case .objetivoPuente: return "arrow.turn.down.right"
        }
    }
}

// MARK: - Resumen del corredor

/// El encabezado del perfil: quién sos como corredor, en números.
/// Reemplaza seis filas de `LabeledContent` por una lectura.
struct ResumenCorredor: View {
    var objetivo: ObjetivoDeportivo?
    var fecha: DiaLocal?
    var kmSemanales: Double?
    var dias: Int?
    var tiradaLarga: Double?
    var tienePlan: Bool
    var motivoSinPlan: MotivoSinPlan?

    private var fechaCorta: String? {
        guard let fecha, let d = fecha.fecha() else { return nil }
        return FormatoFecha.corta(d).uppercased()
    }

    var body: some View {
        Tarjeta {
            VStack(alignment: .leading, spacing: DV2.Espacio.l) {
                VStack(alignment: .leading, spacing: DV2.Espacio.xs) {
                    Text(objetivo.map { TextosObjetivo.nombre(de: $0).uppercased() }
                         ?? String(localized: "SIN OBJETIVO"))
                        .font(DV2.Tipo.titulo)
                        .foregroundStyle(DV2.Marca.profundo)
                        .fixedSize(horizontal: false, vertical: true)
                    if let fechaCorta {
                        Text(fechaCorta)
                            .font(.subheadline.weight(.medium).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    // El estado manda sobre la cuenta regresiva: sin
                    // plan no se muestran semanas que no existen.
                    if let motivoSinPlan {
                        ChipEstado(texto: textoPendiente(motivoSinPlan),
                                   tono: .base,
                                   icono: "exclamationmark.triangle.fill",
                                   compacto: true)
                    } else if !tienePlan && objetivo != nil {
                        ChipEstado(texto: String(localized: "Sin plan todavía"),
                                   tono: .neutro, icono: "circle.dashed", compacto: true)
                    }
                }

                if kmSemanales != nil || dias != nil || tiradaLarga != nil {
                    Divider()
                    HStack(alignment: .top, spacing: DV2.Espacio.m) {
                        if let kmSemanales {
                            Metrica(valor: String(format: "%.0f", kmSemanales),
                                    etiqueta: String(localized: "\(Unidades.actual.etiquetaDistancia)/sem"),
                                    alineacion: .center)
                        }
                        if let dias {
                            Metrica(valor: "\(dias)",
                                    etiqueta: String(localized: "días"),
                                    alineacion: .center)
                        }
                        if let tiradaLarga {
                            Metrica(valor: String(format: "%.0f", tiradaLarga),
                                    etiqueta: String(localized: "larga"),
                                    alineacion: .center)
                        }
                    }
                }
            }
        }
    }

    private func textoPendiente(_ motivo: MotivoSinPlan) -> String {
        switch motivo {
        case .fechaDemasiadoCerca: return String(localized: "La fecha no da")
        case .diasInsuficientes: return String(localized: "Faltan días")
        case .faltaBase: return String(localized: "Falta base")
        case .faltaReferencia: return String(localized: "Falta tu ritmo")
        case .sinContenido: return String(localized: "Plan en camino")
        }
    }
}
