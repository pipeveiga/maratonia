import SwiftUI

// Pantalla principal de la app del reloj. En la Fase 1 solo verifica
// que el target watchOS compila y ve el modelo compartido.
// En fases siguientes acá van el botón de Play y el estado del plan.

struct ContentView: View {
    private let plan = Plan.vacio

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run")
                .font(.system(size: 36))
                .foregroundStyle(.tint)
            Text("Maratón")
                .font(.headline)
            Text("Fase 1 OK · plan “\(plan.nombre)”")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    ContentView()
}
