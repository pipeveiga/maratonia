import SwiftUI

// Pantalla principal del reloj. Si no hay sesión en curso muestra el
// "lobby" (plan recibido, pistas listas, botón grande de Play); con la
// sesión andando muestra la pantalla de reproducción. Esta última es
// deliberadamente simple: durante la carrera Runna está al frente.

struct ContentView: View {
    @ObservedObject private var conectividad = ConectividadWatch.compartida
    @ObservedObject private var reproductor = Reproductor.compartido
    @ObservedObject private var entrenamiento = Entrenamiento.compartido

    /// true = al dar Play también arranca una sesión de entrenamiento
    /// (FC, distancia, se guarda en Salud). false = solo audio, para
    /// convivir con Runna u otro tracker.
    @AppStorage("modoEntrenamiento") private var modoEntrenamiento = true

    /// Ruta GPS para el mapa. Separado del resto porque es lo que más
    /// batería consume y lo primero que conviene apagar si algo falla.
    @AppStorage("rutaGPS") private var rutaGPS = true

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

    // El lobby va partido en tres bloques chicos a propósito: SwiftUI
    // admite como máximo 10 vistas por bloque y de una sola pieza quedaba
    // al borde de ese límite.

    @ViewBuilder
    private func vistaPlan(_ plan: Plan) -> some View {
        cabecera(plan)
        controles(plan)
        resumen(plan)
    }

    @ViewBuilder
    private func cabecera(_ plan: Plan) -> some View {
        let faltantes = conectividad.pistasFaltantes
        let listas = plan.pistas.count - faltantes.count

        Text(plan.nombre)
            .font(.headline)

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
            arrancar(plan)
        } label: {
            Label("Play", systemImage: "play.fill")
                .font(.title3)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(listas == 0)
    }

    @ViewBuilder
    private func controles(_ plan: Plan) -> some View {
        Toggle(isOn: $modoEntrenamiento) {
            Label("Registrar carrera", systemImage: "heart.fill")
                .font(.footnote)
        }
        .tint(.red)

        if modoEntrenamiento {
            Toggle(isOn: $rutaGPS) {
                Label("Ruta GPS", systemImage: "map.fill")
                    .font(.footnote)
            }
        }

        Text(modoEntrenamiento
             ? "Con FC y guardado en Salud. No uses Runna a la vez."
             : "Solo audio: compatible con Runna u otro tracker.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    @ViewBuilder
    private func resumen(_ plan: Plan) -> some View {
        if let error = reproductor.mensajeError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }

        if let error = entrenamiento.mensajeError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }

        Text("\(plan.cronograma(duracionMaximaMinutos: 360).count) avisos en el cronograma")
            .font(.footnote)
            .foregroundStyle(.secondary)

        if !plan.tramosActivos.isEmpty {
            Text("\(plan.tramosActivos.count) tramos con ritmo objetivo")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// La música y los avisos arrancan siempre primero: son el corazón de
    /// la app y no deben depender de que Salud o el GPS estén disponibles.
    /// El entrenamiento se suma después y, si falla, queda el error a la
    /// vista sin cortar la sesión.
    private func arrancar(_ plan: Plan) {
        reproductor.iniciar(plan: plan, urlDe: conectividad.urlDePista)
        guard modoEntrenamiento else { return }
        EntrenadorRitmo.compartido.iniciar(plan: plan)
        Entrenamiento.compartido.pedirPermisos(conGPS: rutaGPS) {
            Entrenamiento.compartido.iniciar(conGPS: rutaGPS)
        }
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
    @ObservedObject private var entrenamiento = Entrenamiento.compartido
    @ObservedObject private var entrenador = EntrenadorRitmo.compartido
    @State private var confirmandoTerminar = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(formatearTiempo(reproductor.tiempoTranscurrido))
                .font(.system(size: 38, weight: .semibold, design: .rounded))
                .monospacedDigit()

            Text(nombreLegible(reproductor.nombrePistaActual))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if entrenamiento.activo {
                HStack(spacing: 12) {
                    Label("\(Int(entrenamiento.frecuenciaCardiaca))",
                          systemImage: "heart.fill")
                        .foregroundStyle(.red)
                    Label(String(format: "%.2f km", entrenamiento.distanciaMetros / 1000),
                          systemImage: "figure.run")
                }
                .font(.footnote)
                .monospacedDigit()

                if let ritmo = entrenamiento.ritmoActualSegKm {
                    Text("Ritmo \(formatearRitmo(ritmo)) /km")
                        .font(.footnote)
                        .monospacedDigit()
                }

                if let tramo = entrenador.tramoActual {
                    Text("\(tramo.nombre): \(tramo.descripcion)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }

            if let errorEntrenamiento = entrenamiento.mensajeError {
                Text(errorEntrenamiento)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

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
                    EntrenadorRitmo.compartido.detener()
                    Entrenamiento.compartido.finalizar()
                }
                Button("Seguir", role: .cancel) {}
            }
            }
            .padding(.horizontal, 4)
        }
    }
}

#Preview {
    ContentView()
}
