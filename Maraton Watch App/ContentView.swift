import SwiftUI

/// Pantalla principal de la app watchOS.
/// En la Fase 1 solo confirma que la app abre y que el modelo compartido
/// también compila en el reloj. La pantalla real (Play, estado del plan)
/// llega en fases posteriores.
struct ContentView: View {
    private let plan = Plan(nombre: "Fase 1 OK")

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Maratón")
                .font(.headline)
            Text(plan.nombre)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
