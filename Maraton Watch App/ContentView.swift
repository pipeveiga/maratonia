import SwiftUI

// Pantalla principal del reloj (Fase 3): muestra el plan recibido, cuántas
// pistas están listas y cuáles faltan. El botón de Play se habilita en la
// Fase 4, cuando exista el reproductor.

struct ContentView: View {
    @ObservedObject private var conectividad = ConectividadWatch.compartida

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if let plan = conectividad.plan {
                    vistaPlan(plan)
                } else {
                    vistaSinPlan
                }
            }
            .padding(.horizontal, 4)
        }
    }

    @ViewBuilder
    private func vistaPlan(_ plan: Plan) -> some View {
        Text(plan.nombre)
            .font(.headline)

        let faltantes = conectividad.pistasFaltantes
        let listas = plan.pistas.count - faltantes.count

        Text("\(listas) de \(plan.pistas.count) pistas listas")
            .font(.footnote)
            .foregroundStyle(faltantes.isEmpty ? Color.green : Color.orange)

        if !faltantes.isEmpty {
            Text("Faltan: \(faltantes.joined(separator: ", "))")
                .font(.footnote)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }

        Button {
            // Fase 4: acá arranca la reproducción.
        } label: {
            Label("Play", systemImage: "play.fill")
                .font(.title3)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(true)

        Text("El Play se habilita en la Fase 4")
            .font(.footnote)
            .foregroundStyle(.secondary)

        Text("\(plan.cronograma(duracionMaximaMinutos: 360).count) avisos en el cronograma")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var vistaSinPlan: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Todavía no llegó ningún plan")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Mandalo desde la app del iPhone con «Enviar al reloj».")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.top, 10)
    }
}

#Preview {
    ContentView()
}
