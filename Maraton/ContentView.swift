import SwiftUI

/// Pantalla provisoria de Fase 1. Muestra un plan de ejemplo y su cronograma
/// expandido, solo para verificar que el proyecto compila y que el modelo
/// compartido funciona. En Fase 2 esta pantalla se reemplaza por la real
/// (importar MP3s, armar avisos, enviar al reloj).
struct ContentView: View {
    private let planDeEjemplo = Plan(
        nombre: "Plan de ejemplo",
        pistas: [],
        avisosFijos: [AvisoFijo(minuto: 90, texto: "Date vuelta y volvé")],
        avisosRepetidos: [
            AvisoRepetido(cadaMinutos: 20, desdeMinuto: 20, hastaMinuto: 120, texto: "Tomá agua"),
            AvisoRepetido(cadaMinutos: 45, desdeMinuto: 45, hastaMinuto: 120, texto: "Comé un gel"),
        ]
    )

    var body: some View {
        NavigationStack {
            List {
                Section("Fase 1 — proyecto base") {
                    Text("Si ves esta pantalla, el target de iPhone compila y el modelo de datos compartido funciona.")
                        .font(.footnote)
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
            .navigationTitle("Maratón")
        }
    }
}

#Preview {
    ContentView()
}
