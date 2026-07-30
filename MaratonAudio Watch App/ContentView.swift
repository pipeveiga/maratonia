import SwiftUI

// Pantalla placeholder de la Fase 1 en el reloj.
// Verifica que el modelo compartido también compila en el target watchOS.
// En la Fase 4 esta pantalla se reemplaza por la app real.
struct ContentView: View {
    private let planDeEjemplo = Plan(
        nombre: "Plan de prueba",
        avisosFijos: [AvisoFijo(minuto: 90, texto: "Date vuelta")]
    )

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.green)
            Text("Fase 1 OK")
                .font(.headline)
            Text("\(planDeEjemplo.cronograma().count) aviso en el plan de ejemplo")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
