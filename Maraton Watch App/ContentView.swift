import SwiftUI

// Pantalla principal de la app watchOS. En la Fase 1 solo verifica que
// el modelo compartido también compila en el reloj. Se reemplaza por la
// pantalla real (plan cargado + botón de Play) en fases siguientes.

struct ContentView: View {
    private let planDeEjemplo = Plan(
        nombre: "Plan de prueba",
        pistas: [],
        avisosFijos: [AvisoFijo(minuto: 90, texto: "Date vuelta y volvé")],
        avisosRepetidos: [AvisoRepetido(cadaMinutos: 20, desdeMinuto: 20, hastaMinuto: nil, texto: "Tomá agua")]
    )

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "figure.run")
                .font(.largeTitle)
            Text("Maratón")
                .font(.headline)
            Text("Fase 1 OK — \(planDeEjemplo.cronograma(duracionMaximaMinutos: 120).count) avisos de ejemplo")
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
