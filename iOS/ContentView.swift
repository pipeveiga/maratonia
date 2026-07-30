import SwiftUI

// Pantalla principal de la app iOS. Por ahora (Fase 1) es solo una
// pantalla de verificación: muestra que el proyecto compila y que el
// modelo compartido (Plan) está accesible desde este target.
// En la Fase 2 acá va la pantalla real: pistas, avisos y cronograma.

struct ContentView: View {
    private let plan = Plan.vacio

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.run")
                .font(.system(size: 60))
                .foregroundStyle(.tint)
            Text("Maratón — Fase 1")
                .font(.title2.bold())
            Text("Proyecto configurado. Plan cargado: “\(plan.nombre)” con \(plan.pistas.count) pistas.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
}

#Preview {
    ContentView()
}
