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
                    Text(cual == .anual ? "Anual" : "Mensual")
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
