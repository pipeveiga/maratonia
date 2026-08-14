import SwiftUI
import StoreKit

// EL PAYWALL.
//
// Tres beneficios, dos precios y un botón. Nada de treinta bullets ni
// de contadores falsos: si el producto no se explica en una pantalla,
// el problema no se arregla con más texto.
//
// Todos los números salen de StoreKit y se muestran con el formato del
// storefront del corredor. No hay un solo precio escrito en el código:
// en otro país el anual vale otra cosa, y "aprox. $4.17/mes" calculado
// sobre un precio que no es el suyo es mentira.

struct PaywallPro: View {
    @ObservedObject private var tienda = TiendaPro.compartida
    @Environment(\.dismiss) private var dismiss

    /// Qué lo disparó, para que el encabezado hable de eso.
    var motivo: MotivoPaywall = .general
    @State private var elegido: ProductoPro = .anual
    @State private var procesando = false
    @State private var aviso: String?

    enum MotivoPaywall {
        case general
        case objetivo(ObjetivoDeportivo)
        case coach

        var titulo: String {
            switch self {
            case .general: return String(localized: "Maratonia Pro")
            case .objetivo(let objetivo):
                return String(localized: "\(TextosObjetivo.nombre(de: objetivo)) es parte de Pro")
            case .coach: return String(localized: "El Coach es parte de Pro")
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DV2.Espacio.xl) {
                    encabezado
                    beneficios
                    if tienda.productos.isEmpty {
                        sinProductos
                    } else {
                        opciones
                        cta
                    }
                    piePolitico
                }
                .padding()
            }
            .background(DV2.Superficie.fondo)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Ahora no") { dismiss() }
                }
            }
            .task { if tienda.productos.isEmpty { await tienda.cargarProductos() } }
            .alert(aviso ?? "", isPresented: Binding(
                get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
                Button("Entendido", role: .cancel) {}
            }
        }
    }

    // MARK: Partes

    private var encabezado: some View {
        VStack(spacing: DV2.Espacio.s) {
            Image(systemName: "figure.run.circle.fill")
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .foregroundStyle(DV2.Marca.primario)
            Text(motivo.titulo)
                .font(DV2.Tipo.titulo)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Tu plan no se limita a decirte qué correr. Se adapta con vos.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DV2.Espacio.m)
    }

    private var beneficios: some View {
        VStack(spacing: DV2.Espacio.m) {
            beneficio("target", String(localized: "Todos los objetivos"),
                      String(localized: "De mejorar tus 5K al maratón"))
            beneficio("arrow.triangle.2.circlepath", String(localized: "Ajustes del plan"),
                      String(localized: "Tu semana se reorganiza con vos"))
            beneficio("bubble.left.and.text.bubble.right", String(localized: "Coach IA"),
                      String(localized: "Te explica por qué te toca cada sesión"))
        }
    }

    private func beneficio(_ icono: String, _ titulo: String, _ detalle: String) -> some View {
        HStack(spacing: DV2.Espacio.m) {
            Image(systemName: icono)
                .font(.title3)
                .foregroundStyle(DV2.Marca.primario)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(titulo).font(.subheadline.weight(.semibold))
                Text(detalle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var opciones: some View {
        VStack(spacing: DV2.Espacio.m) {
            if tienda.producto(.anual) != nil {
                opcion(.anual, destacada: true)
            }
            if tienda.producto(.mensual) != nil {
                opcion(.mensual, destacada: false)
            }
        }
    }

    private func opcion(_ cual: ProductoPro, destacada: Bool) -> some View {
        let elegida = elegido == cual
        return Button {
            elegido = cual
        } label: {
            VStack(alignment: .leading, spacing: DV2.Espacio.xs) {
                HStack {
                    // El nombre lo pone App Store: si mañana el producto
                    // se llama distinto, la app no queda mintiendo.
                    Text(tienda.producto(cual)?.displayName
                         ?? (cual == .anual ? String(localized: "Anual")
                                            : String(localized: "Mensual")))
                        .font(DV2.Tipo.tituloChico)
                    Spacer()
                    if destacada {
                        Text("MEJOR VALOR")
                            .font(.caption2.weight(.heavy))
                            .tracking(0.8)
                            .foregroundStyle(.white)
                            .padding(.horizontal, DV2.Espacio.s)
                            .padding(.vertical, 3)
                            .background(DV2.Marca.primario, in: Capsule())
                    }
                }
                // El precio, tal cual lo devuelve el storefront.
                Text(tienda.precio(cual) ?? "—")
                    .font(DV2.Tipo.numeroGrande)
                if cual == .anual {
                    if let porMes = tienda.mensualEquivalenteDelAnual() {
                        Text("aprox. \(porMes) por mes")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let dias = tienda.diasDePrueba(.anual) {
                        Label("\(dias) días gratis", systemImage: "gift")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(DV2.Semantico.exito)
                    }
                }
            }
            .superficieDeTarjeta()
            .overlay(DV2.formaTarjeta.strokeBorder(
                elegida ? DV2.Marca.primario : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
    }

    private var cta: some View {
        VStack(spacing: DV2.Espacio.s) {
            Button {
                Task { await comprar() }
            } label: {
                EtiquetaBotonPrimarioV2(titulo: textoCTA, icono: "arrow.right")
            }
            .buttonStyle(.plain)
            .disabled(procesando)
            .opacity(procesando ? 0.5 : 1)

            Button("Restaurar compras") { Task { await restaurar() } }
                .font(.footnote.weight(.semibold))
                .disabled(procesando)
        }
    }

    private var textoCTA: LocalizedStringKey {
        tienda.diasDePrueba(elegido) != nil ? "Probar Pro gratis" : "Suscribirme"
    }

    private var sinProductos: some View {
        Tarjeta {
            VStack(spacing: DV2.Espacio.s) {
                if tienda.cargando {
                    ProgressView()
                } else {
                    Text("No pudimos cargar los precios ahora.")
                        .font(.subheadline)
                    Button("Reintentar") { Task { await tienda.cargarProductos() } }
                        .font(.footnote.weight(.semibold))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var piePolitico: some View {
        VStack(spacing: DV2.Espacio.xs) {
            Text("La suscripción se renueva sola hasta que la cancelés, desde Ajustes de tu Apple ID.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: DV2.Espacio.xs) {
                Link(String(localized: "Términos"),
                     destination: URL(string: "https://maratonia.site/terms/")!)
                Text("·")
                Link(String(localized: "Privacidad"),
                     destination: URL(string: "https://maratonia.site/privacy/")!)
            }
            .font(.caption2)
        }
        .padding(.top, DV2.Espacio.s)
    }

    // MARK: Acciones

    private func comprar() async {
        guard let producto = tienda.producto(elegido) else { return }
        procesando = true
        defer { procesando = false }
        switch await tienda.comprar(producto) {
        case .comprado:
            dismiss()
        case .cancelado:
            break                                  // no se avisa nada: la canceló
        case .pendiente:
            aviso = String(localized: "La compra quedó pendiente de aprobación. Te avisamos cuando se confirme.")
        case .fallo(let motivo):
            aviso = motivo
        }
    }

    private func restaurar() async {
        procesando = true
        defer { procesando = false }
        switch await tienda.restaurar() {
        case .restaurado:
            dismiss()
        case .sinCompras:
            aviso = String(localized: "No encontramos compras para restaurar con este Apple ID.")
        case .fallo(let motivo):
            aviso = motivo
        }
    }
}

/// La insignia PRO del catálogo. Discreta: el plan se ve, se explora y
/// se entiende; el límite aparece al adoptar.
struct InsigniaPro: View {
    var body: some View {
        Text("PRO")
            .font(.caption2.weight(.heavy))
            .tracking(0.8)
            .foregroundStyle(DV2.Marca.primario)
            .padding(.horizontal, DV2.Espacio.s)
            .padding(.vertical, 2)
            .background(DV2.Marca.primario.opacity(0.14), in: Capsule())
            .accessibilityLabel(Text("Requiere Maratonia Pro"))
    }
}

/// La sección Pro de Perfil. Separada de CORREDOR y de CUENTA: son tres
/// cosas distintas y mezclarlas es lo que convierte a Perfil en un
/// Settings.
struct SeccionPro: View {
    @ObservedObject private var tienda = TiendaPro.compartida
    @State private var mostrandoPaywall = false
    @State private var aviso: String?

    /// La URL nativa de gestión de suscripciones. No se inventa ninguna.
    private static let gestionar = URL(string: "https://apps.apple.com/account/subscriptions")!

    var body: some View {
        Section("Maratonia Pro") {
            // Una fila compacta: icono, qué sos, y una línea que dice lo
            // que hay que saber. Antes eran tres filas de `LabeledContent`
            // con un hueco enorme y sin decir nada útil cuando algo
            // fallaba.
            FilaEstadoPro(estado: tienda.estado)

            accionPrincipal

            // Restaurar solo se ofrece cuando puede servir de algo: con
            // Pro activo no tiene sentido y era ruido.
            if !tienda.estado.esPro {
                Button("Restaurar compras") {
                    Task {
                        switch await tienda.restaurar() {
                        case .restaurado: aviso = String(localized: "Listo: Pro restaurado.")
                        case .sinCompras: aviso = String(localized: "No encontramos compras para restaurar con este Apple ID.")
                        case .fallo(let motivo): aviso = motivo
                        }
                    }
                }
                .font(.footnote)
            }
        }
        .sheet(isPresented: $mostrandoPaywall) { PaywallPro() }
        .alert(aviso ?? "", isPresented: Binding(
            get: { aviso != nil }, set: { if !$0 { aviso = nil } })) {
            Button("Entendido", role: .cancel) {}
        }
    }

    /// Qué acción corresponde en cada estado. Un problema de cobro se
    /// arregla en App Store, no comprando de nuevo: mandarlo al paywall
    /// sería hacerle pagar dos veces.
    @ViewBuilder
    private var accionPrincipal: some View {
        switch tienda.estado {
        case .activa, .gracia, .problemaDeCobro:
            Link(destination: Self.gestionar) {
                Label(tienda.estado.esPro
                      ? String(localized: "Gestionar suscripción")
                      : String(localized: "Actualizar forma de pago"),
                      systemImage: "creditcard")
            }
        case .libre, .expirada, .revocada:
            Button {
                mostrandoPaywall = true
            } label: {
                Label(tienda.estado == .libre
                      ? String(localized: "Conocer Maratonia Pro")
                      : String(localized: "Volver a suscribirme"),
                      systemImage: "sparkles")
            }
        }
    }

}

/// LA TARJETA. Una fila compacta: icono, en qué estás, y una línea que
/// dice lo que hace falta saber. Antes eran tres filas de
/// `LabeledContent` con un hueco enorme, y cuando algo fallaba —cobro
/// rechazado, reembolso, vencimiento— no decían absolutamente nada.
struct FilaEstadoPro: View {
    let estado: EstadoPro

    struct Presentacion: Equatable {
        var icono: String
        var color: Color
        var titulo: String
        var detalle: String
    }

    /// La decisión de qué decir en cada estado. `static` y sin
    /// dependencias: se puede ver entera sin StoreKit ni sesión.
    static func presentacion(de estado: EstadoPro) -> Presentacion {
        let plan = nombreDelPlan(estado.detalle)

        switch estado {
        case .libre:
            return Presentacion(
                icono: "sparkles", color: DV2.Marca.primario,
                titulo: String(localized: "Maratonia Pro"),
                detalle: String(localized: "Todos los objetivos, ajustes del plan y el Coach."))

        case .activa(let detalle):
            if detalle.enPrueba {
                return Presentacion(
                    icono: "gift.fill", color: DV2.Semantico.exito,
                    titulo: String(localized: "Prueba gratis"),
                    detalle: detalle.vence.map {
                        String(localized: "El \(FormatoFecha.media($0)) empieza a cobrarse \(plan).")
                    } ?? String(localized: "Estás probando \(plan)."))
            }
            if !detalle.renuevaSola {
                return Presentacion(
                    icono: "clock.badge.exclamationmark", color: DV2.Semantico.advertencia,
                    titulo: String(localized: "Activo hasta el final del período"),
                    detalle: detalle.vence.map {
                        String(localized: "Cancelaste la renovación: tenés Pro hasta el \(FormatoFecha.media($0)).")
                    } ?? String(localized: "Cancelaste la renovación automática."))
            }
            return Presentacion(
                icono: "checkmark.seal.fill", color: DV2.Semantico.exito,
                titulo: plan,
                detalle: detalle.vence.map {
                    String(localized: "Se renueva el \(FormatoFecha.media($0)).")
                } ?? String(localized: "Suscripción activa."))

        case .gracia(let detalle):
            return Presentacion(
                icono: "exclamationmark.triangle.fill", color: DV2.Semantico.advertencia,
                titulo: String(localized: "Problema con el cobro"),
                detalle: detalle.vence.map {
                    String(localized: "App Store no pudo cobrar \(plan). Seguís con Pro hasta el \(FormatoFecha.media($0)): actualizá tu forma de pago.")
                } ?? String(localized: "App Store no pudo cobrar \(plan). Seguís con Pro por ahora: actualizá tu forma de pago."))

        case .problemaDeCobro:
            return Presentacion(
                icono: "creditcard.trianglebadge.exclamationmark", color: DV2.Semantico.destructivo,
                titulo: String(localized: "No se pudo cobrar la renovación"),
                detalle: String(localized: "Pro está pausado hasta que se resuelva el pago. Tu plan y tu historial siguen intactos."))

        case .expirada(let detalle):
            return Presentacion(
                icono: "clock.arrow.circlepath", color: .secondary,
                titulo: String(localized: "Suscripción vencida"),
                detalle: detalle.vence.map {
                    String(localized: "\(plan) venció el \(FormatoFecha.media($0)). Tu plan y tu historial siguen acá.")
                } ?? String(localized: "\(plan) venció. Tu plan y tu historial siguen acá."))

        case .revocada:
            return Presentacion(
                icono: "arrow.uturn.backward.circle.fill", color: .secondary,
                titulo: String(localized: "Suscripción reembolsada"),
                detalle: String(localized: "App Store cerró esta suscripción. Tu plan y tu historial siguen acá."))
        }
    }

    /// El nombre del plan viene de StoreKit. Si todavía no cargó, se dice
    /// "tu suscripción" — nunca "anual": el que compró el mensual no
    /// tiene por qué leer que tiene un anual.
    static func nombreDelPlan(_ detalle: DetallePro?) -> String {
        if let nombre = detalle?.nombre, !nombre.isEmpty { return nombre }
        return String(localized: "tu suscripción")
    }

    var body: some View {
        let p = Self.presentacion(de: estado)
        return HStack(spacing: DV2.Espacio.m) {
            Image(systemName: p.icono)
                .font(.title2)
                .foregroundStyle(p.color)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(p.titulo)
                    .font(.subheadline.weight(.semibold))
                Text(p.detalle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
/// CATÁLOGO DE ESTADOS (solo DEBUG, igual que `pestanaInicial`).
///
/// Los cinco estados de una suscripción son casi imposibles de provocar
/// a demanda: hay que hacer que a alguien le rebote la tarjeta, pedir un
/// reembolso o esperar a que venza. Sin esto se verifican de memoria, y
/// de memoria fue como quedó una tarjeta que no decía nada cuando algo
/// fallaba.
///
/// Uso: `xcrun simctl launch <dev> <bundle> -verEstadosPro 1`
struct CatalogoEstadosPro: View {
    static var pedido: Bool { UserDefaults.standard.bool(forKey: "verEstadosPro") }

    private static let vence = Calendar.current.date(byAdding: .day, value: 12, to: Date())

    private static var anual: DetallePro {
        DetallePro(productoID: ProductoPro.anual.rawValue,
                   nombre: "Maratonia Pro Anual", vence: vence)
    }
    private static var mensual: DetallePro {
        DetallePro(productoID: ProductoPro.mensual.rawValue,
                   nombre: "Maratonia Pro Mensual", vence: vence)
    }

    private var casos: [(String, EstadoPro)] {
        var prueba = Self.anual;  prueba.enPrueba = true
        var cancelada = Self.anual; cancelada.renuevaSola = false
        return [
            ("Sin Pro", .libre),
            ("En prueba", .activa(prueba)),
            ("Activa", .activa(Self.mensual)),
            ("Activa, cancelada", .activa(cancelada)),
            ("Período de gracia", .gracia(Self.anual)),
            ("Reintento de cobro", .problemaDeCobro(Self.anual)),
            ("Vencida", .expirada(Self.anual)),
            ("Reembolsada", .revocada(Self.mensual)),
        ]
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(casos, id: \.0) { titulo, estado in
                    // El acceso va en el encabezado para que las ocho
                    // tarjetas entren en una pantalla y se comparen de
                    // un vistazo.
                    Section("\(titulo)  ·  Pro: \(estado.esPro ? "sí" : "no")") {
                        FilaEstadoPro(estado: estado)
                    }
                }
            }
            .navigationTitle("Estados Pro")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
#endif
