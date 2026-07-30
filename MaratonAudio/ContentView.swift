import SwiftUI

// Pantalla placeholder de la Fase 1.
// Muestra un plan de ejemplo y su cronograma expandido para verificar
// que el modelo compartido compila y funciona en el target iOS.
// En la Fase 2 esta pantalla se reemplaza por la app real.
struct ContentView: View {
    private let planDeEjemplo = Plan(
        nombre: "Plan de prueba",
        pistas: ["ejemplo.mp3"],
        avisosFijos: [AvisoFijo(minuto: 90, texto: "Date vuelta y volvé")],
        avisosRepetidos: [AvisoRepetido(cadaMinutos: 20, desdeMinuto: 20, hastaMinuto: 100, texto: "Tomá agua")]
    )

    var body: some View {
        NavigationStack {
            List {
                Section("Fase 1 — proyecto base") {
                    Label("iOS compila y corre", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                Section("Cronograma del plan de ejemplo") {
                    ForEach(planDeEjemplo.cronograma()) { aviso in
                        HStack {
                            Text("min \(aviso.minuto)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(aviso.texto)
                        }
                    }
                }
            }
            .navigationTitle("MaratonAudio")
        }
    }
}

#Preview {
    ContentView()
}
