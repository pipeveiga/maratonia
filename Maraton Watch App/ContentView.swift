import SwiftUI

/// Pantalla principal del reloj. En la Fase 1 solo confirma que la app
/// arranca y que ve el modelo compartido. Más adelante acá van el botón
/// de Play y el estado del plan.
struct ContentView: View {
    private let plan = Plan.vacio

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "figure.run")
                .font(.largeTitle)
            Text("Maratón")
                .font(.headline)
            Text("Fase 1: base OK")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text("Plan: \(plan.nombre)")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
