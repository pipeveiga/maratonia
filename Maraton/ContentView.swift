import SwiftUI

/// Pantalla principal de la app de iPhone. Por ahora es un placeholder
/// que arma un plan de ejemplo con el modelo compartido, para verificar
/// que todo compila y que el modelo es visible desde este target.
/// En la Fase 2 se reemplaza por la pantalla real (pistas, avisos, envío).
struct ContentView: View {
    private let planDemo = Plan(
        nombre: "Plan de prueba",
        pistas: [],
        avisosFijos: [
            AvisoFijo(minuto: 90, texto: "Date vuelta y volvé")
        ],
        avisosRepetidos: [
            AvisoRepetido(cadaMinutos: 20, desdeMinuto: 20, hastaMinuto: nil, texto: "Tomá agua")
        ]
    )

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("Maraton — Fase 1 OK")
                .font(.title2)
                .bold()
            Text("Plan de ejemplo: “\(planDemo.nombre)”")
            Text("\(planDemo.avisosFijos.count) aviso fijo, \(planDemo.avisosRepetidos.count) repetido")
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
