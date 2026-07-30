import SwiftUI

/// Pantalla principal de la app iOS.
/// En la Fase 1 es solo una verificación de que el proyecto compila y de que
/// el modelo compartido funciona: muestra el cronograma expandido de un plan
/// de ejemplo. En la Fase 2 acá van las secciones reales (pistas y avisos).
struct ContentView: View {
    private let planDeEjemplo = Plan(
        nombre: "Plan de prueba",
        pistas: [],
        avisosFijos: [AvisoFijo(minuto: 90, texto: "Date vuelta y volvé")],
        avisosRepetidos: [AvisoRepetido(cadaMinutos: 20, desdeMinuto: 20, hastaMinuto: nil, texto: "Tomá agua")]
    )

    var body: some View {
        NavigationStack {
            List {
                Section("Fase 1 — proyecto funcionando") {
                    Label("Los dos targets compilan", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Label("Modelo compartido cargado", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }

                Section("Cronograma de ejemplo (horizonte: 100 min)") {
                    ForEach(planDeEjemplo.cronograma(horizonteMinutos: 100), id: \.self) { aviso in
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
