import SwiftUI

/// Pantalla principal de la app del reloj. Placeholder de la Fase 1:
/// usa el modelo compartido para verificar que compila también en
/// watchOS. En fases siguientes acá va el botón de Play y el estado
/// del plan recibido desde el iPhone.
struct ContentView: View {
    private let planDemo = Plan(nombre: "Plan de prueba")

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run")
                .font(.system(size: 32))
                .foregroundStyle(.tint)
            Text("Maraton")
                .font(.headline)
            Text("Fase 1 OK")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
