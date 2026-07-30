import SwiftUI

// Pantalla principal de la app iOS. En la Fase 1 solo muestra un plan
// de ejemplo y su cronograma expandido, para verificar que el modelo
// compartido compila y calcula bien. En la Fase 2 se reemplaza por la
// pantalla real de armado del plan.

struct ContentView: View {
    private let planDeEjemplo = Plan(
        nombre: "Plan de prueba",
        pistas: [],
        avisosFijos: [
            AvisoFijo(minuto: 90, texto: "Date vuelta y volvé"),
        ],
        avisosRepetidos: [
            AvisoRepetido(cadaMinutos: 20, desdeMinuto: 20, hastaMinuto: nil, texto: "Tomá agua"),
            AvisoRepetido(cadaMinutos: 45, desdeMinuto: 45, hastaMinuto: 135, texto: "Comé un gel"),
        ]
    )

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("Fase 1: proyecto y modelo de datos", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Section("Cronograma de ejemplo (2 h de carrera)") {
                    ForEach(planDeEjemplo.cronograma(duracionMaximaMinutos: 120)) { aviso in
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
