import SwiftUI

// Pantalla principal del reloj. Si no hay sesión en curso muestra el
// "lobby" (plan recibido, pistas listas, botón grande de Play); con la
// sesión andando muestra la pantalla de reproducción. Esta última es
// deliberadamente simple: durante la carrera Runna está al frente.

struct ContentView: View {
    @ObservedObject private var conectividad = ConectividadWatch.compartida
    @ObservedObject private var reproductor = Reproductor.compartido

    var body: some View {
        if reproductor.estado == .detenido {
            lobby
        } else {
            PantallaReproduccion()
        }
    }

    private var lobby: some View {
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
            reproductor.iniciar(plan: plan, urlDe: conectividad.urlDePista)
        } label: {
            Label("Play", systemImage: "play.fill")
                .font(.title3)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(listas == 0)

        if let error = reproductor.mensajeError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }

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

struct PantallaReproduccion: View {
    @ObservedObject private var reproductor = Reproductor.compartido
    @ObservedObject private var avisador = Avisador.compartido
    @State private var confirmandoTerminar = false

    var body: some View {
        VStack(spacing: 8) {
            Text(formatearTiempo(reproductor.tiempoTranscurrido))
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()

            Text(nombreLegible(reproductor.nombrePistaActual))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let proximo = avisador.proximoAviso {
                let faltan = max(0, proximo.minuto - Int(reproductor.tiempoTranscurrido / 60))
                Text("Próximo: «\(proximo.texto)» en \(faltan) min")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            } else {
                Text("No quedan avisos")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if reproductor.estado == .pausado {
                Text("En pausa — el tiempo está congelado")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button {
                    reproductor.alternarPlayPausa()
                } label: {
                    Image(systemName: reproductor.estado == .reproduciendo ? "pause.fill" : "play.fill")
                        .font(.title3)
                }
                .buttonStyle(.bordered)

                Button {
                    reproductor.siguiente()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.title3)
                }
                .buttonStyle(.bordered)
            }

            Button {
                avisador.probar()
            } label: {
                Label("Probar aviso", systemImage: "speaker.wave.2.fill")
                    .font(.footnote)
            }
            .buttonStyle(.bordered)

            Button("Terminar", role: .destructive) {
                confirmandoTerminar = true
            }
            .font(.footnote)
            .confirmationDialog("¿Terminar la sesión?", isPresented: $confirmandoTerminar) {
                Button("Terminar", role: .destructive) {
                    reproductor.detener()
                }
                Button("Seguir", role: .cancel) {}
            }
        }
        .padding(.horizontal, 4)
    }
}

#Preview {
    ContentView()
}
