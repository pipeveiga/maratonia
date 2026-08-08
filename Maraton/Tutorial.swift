import SwiftUI

// Tutorial de primera apertura: cuatro pantallas deslizables que explican
// el flujo completo (armar plan → enviar al reloj → correr). Se muestra
// solo la primera vez, y queda accesible desde la sección Ayuda.

struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var pagina = 0

    private static let ultimaPagina = 3

    var body: some View {
        TabView(selection: $pagina) {
            paginaTutorial(
                icono: "figure.run",
                titulo: "Bienvenido a Maratonia",
                texto: "Tu música, avisos por voz y un entrenador de ritmo — todo en tu Apple Watch, para correr sin llevar el teléfono.")
                .tag(0)
            paginaTutorial(
                icono: "slider.horizontal.3",
                titulo: "1 · Armá tu plan",
                texto: "En esta pantalla: importá tu música, creá avisos («tomá agua» cada 20 min) y elegí un plan de tramos sugerido — o armá el tuyo tocando «Agregar tramo».")
                .tag(1)
            paginaTutorial(
                icono: "applewatch.radiowaves.left.and.right",
                titulo: "2 · Mandalo al reloj",
                texto: "Tocá «Enviar al reloj», con el reloj en el cargador y con WiFi. La música tarda unos minutos; los ✓ verdes marcan lo que ya llegó.")
                .tag(2)
            paginaTutorial(
                icono: "play.circle.fill",
                titulo: "3 · A correr",
                texto: "En el reloj: Play y listo. Deslizá a los costados para sesión y música, hacia abajo para tu plan y parciales. La voz te avisa y te corrige el ritmo. Al terminar, la carrera queda en Salud con su mapa — y acá, en «Mis carreras».")
                .tag(3)
        }
        .tabViewStyle(.page)
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .safeAreaInset(edge: .bottom) {
            Button {
                if pagina < Self.ultimaPagina {
                    withAnimation { pagina += 1 }
                } else {
                    dismiss()
                }
            } label: {
                Text(pagina == Self.ultimaPagina ? "¡Empezar!" : "Siguiente")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .padding()
        }
    }

    private func paginaTutorial(icono: String, titulo: String, texto: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icono)
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(titulo)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text(texto)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
        .padding(24)
    }
}
