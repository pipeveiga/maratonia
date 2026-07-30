import SwiftUI

/// Pantalla principal de iPhone. En la Fase 1 es solo una vista de prueba
/// que demuestra que el modelo compartido compila y que la expansión del
/// cronograma funciona. En la Fase 2 acá va el editor real del plan.
struct ContentView: View {
    private let planDePrueba = Plan(
        nombre: "Plan de prueba",
        pistas: [],
        avisosFijos: [
            AvisoFijo(minuto: 45, texto: "Comé un gel"),
            AvisoFijo(minuto: 90, texto: "Date vuelta y volvé"),
        ],
        avisosRepetidos: [
            AvisoRepetido(cadaMinutos: 20, desdeMinuto: 20, hastaMinuto: nil, texto: "Tomá agua")
        ]
    )

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Fase 1: proyecto base funcionando", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Text("Esta pantalla es provisoria. Abajo se ve un plan de ejemplo expandido a su cronograma, para verificar que el modelo de datos compartido funciona.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Cronograma de ejemplo (hasta min 120)") {
                    ForEach(planDePrueba.cronograma(hastaMinuto: 120)) { aviso in
                        HStack {
                            Text("min \(aviso.minuto)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .leading)
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
