import SwiftUI

/// Pantalla provisoria de Fase 1 en el reloj: solo confirma que el target
/// watchOS compila y que ve el modelo compartido. La pantalla real
/// (Play, tiempo transcurrido, próximo aviso) llega en Fases 4 y 5.
struct ContentView: View {
    private let planVacio = Plan()

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run")
                .font(.largeTitle)
            Text("Maratón")
                .font(.headline)
            Text("Fase 1: \(planVacio.pistas.count) pistas")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ContentView()
}
