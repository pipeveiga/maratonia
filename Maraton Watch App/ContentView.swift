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

    /// FC máxima para calcular las zonas (Z1–Z5). Ajustable en el lobby.
    @AppStorage("fcMaxima") private var fcMaxima = 190

    /// true = la música la pone otra app (Spotify del reloj); Maratón
    /// solo corre cronómetro, avisos y entrenamiento. Requiere
    /// "Registrar carrera": sin música propia, el workout es lo que
    /// mantiene viva la app en segundo plano.
    @AppStorage("musicaExterna") private var musicaExterna = false

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
        .disabled(!musicaExterna && listas == 0)
    }

    @ViewBuilder
    private func controles(_ plan: Plan) -> some View {
        Toggle(isOn: $musicaExterna) {
            Label("Música de otra app", systemImage: "music.note.list")
                .font(.footnote)
        }
        .onChange(of: musicaExterna) {
            if musicaExterna {
                modoEntrenamiento = true
            }
        }

        Toggle(isOn: $modoEntrenamiento) {
            Label("Registrar carrera", systemImage: "heart.fill")
                .font(.footnote)
        }
        .tint(.red)
        .disabled(musicaExterna)

        if modoEntrenamiento {
            Toggle(isOn: $rutaGPS) {
                Label("Ruta GPS", systemImage: "map.fill")
                    .font(.footnote)
            }

            Stepper("FC máx: \(fcMaxima)", value: $fcMaxima, in: 120...220, step: 5)
                .font(.footnote)
        }

        Text(textoDeModo)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
    }

    private var textoDeModo: String {
        if musicaExterna {
            return "Ponés la música con Spotify u otra app; Maratón corre avisos y entrenamiento, y la voz le baja el volumen al hablar."
        }
        return modoEntrenamiento
            ? "Con FC y guardado en Salud. No uses Runna a la vez."
            : "Solo audio: compatible con Runna u otro tracker."
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
        reproductor.iniciar(plan: plan, urlDe: conectividad.urlDePista,
                            musicaExterna: musicaExterna)
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
    @AppStorage("fcMaxima") private var fcMaxima = 190
    @State private var confirmandoTerminar = false
    @State private var confirmandoCancelar = false

    /// Tres páginas deslizables, como la app Entrenamiento de Apple:
    /// ← Sesión (pausar todo / terminar) · Métricas · Música (solo música) →
    @State private var pagina = 1

    var body: some View {
        TabView(selection: $pagina) {
            paginaSesion.tag(0)
            paginaMetricas.tag(1)
            paginaMusica.tag(2)
        }
        .tabViewStyle(.page)
    }

    // MARK: - Página izquierda: la sesión entera

    private var paginaSesion: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Sesión")
                    .font(.headline)

                Button {
                    reproductor.alternarPlayPausa()
                } label: {
                    Label(reproductor.estado == .reproduciendo ? "Pausar todo" : "Reanudar",
                          systemImage: reproductor.estado == .reproduciendo ? "pause.fill" : "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(reproductor.estado == .reproduciendo ? .orange : .green)

                Button {
                    avisador.probar()
                } label: {
                    Label("Probar aviso", systemImage: "speaker.wave.2.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    confirmandoTerminar = true
                } label: {
                    Label("Terminar y guardar", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .confirmationDialog("¿Terminar la sesión?", isPresented: $confirmandoTerminar) {
                    Button("Terminar y guardar", role: .destructive) {
                        reproductor.detener()
                        EntrenadorRitmo.compartido.detener()
                        Entrenamiento.compartido.finalizar()
                    }
                    Button("Seguir", role: .cancel) {}
                } message: {
                    Text("La carrera se guarda en Salud.")
                }

                Button {
                    confirmandoCancelar = true
                } label: {
                    Label("Cancelar sesión", systemImage: "xmark")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .confirmationDialog("¿Cancelar la sesión?", isPresented: $confirmandoCancelar) {
                    Button("Descartar todo", role: .destructive) {
                        reproductor.detener()
                        EntrenadorRitmo.compartido.detener()
                        Entrenamiento.compartido.cancelar()
                    }
                    Button("Seguir", role: .cancel) {}
                } message: {
                    Text("El entrenamiento NO se guarda en Salud. No se puede deshacer.")
                }

                Text("Pausar todo congela música, avisos y entrenamiento.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Página central: métricas

    private var paginaMetricas: some View {
        ScrollView {
            VStack(spacing: 6) {
                if entrenamiento.activo {
                    metricasDeCarrera
                } else {
                    cronometroGrande
                }
                infoSecundaria
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Página derecha: solo la música

    private var paginaMusica: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("Música")
                    .font(.headline)

                if reproductor.modoMusicaExterna {
                    Image(systemName: "music.note.list")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("La música la maneja otra app (Spotify). Usá sus controles o el Now Playing del reloj.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text(nombreLegible(reproductor.nombrePistaActual))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)

                    Button {
                        reproductor.alternarSoloMusica()
                    } label: {
                        Label(reproductor.musicaSilenciada ? "Reanudar música" : "Pausar música",
                              systemImage: reproductor.musicaSilenciada ? "speaker.fill" : "speaker.slash.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(reproductor.musicaSilenciada ? .green : .blue)

                    Button {
                        reproductor.siguiente()
                    } label: {
                        Label("Siguiente pista", systemImage: "forward.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Text("Frena solo la música: el entrenamiento y los avisos siguen.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Modo entrenamiento: ritmo, distancia y zona al frente

    @ViewBuilder
    private var metricasDeCarrera: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(entrenamiento.ritmoActualSegKm.map(formatearRitmo) ?? "–:––")
                .font(.system(size: 44, weight: .bold, design: .rounded))
                .monospacedDigit()
            Text("/km")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }

        HStack(spacing: 8) {
            Text(String(format: "%.2f km", entrenamiento.distanciaMetros / 1000))
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
            etiquetaZona
        }

        HStack(spacing: 10) {
            Label(formatearTiempo(reproductor.tiempoTranscurrido), systemImage: "stopwatch")
            Label("\(Int(entrenamiento.frecuenciaCardiaca))", systemImage: "heart.fill")
                .foregroundStyle(.red)
        }
        .font(.footnote)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }

    /// Pastilla de zona de FC (Z1 suave … Z5 máximo), por % de tu FC máxima.
    private var etiquetaZona: some View {
        let (nombre, color) = Self.zona(
            fc: Int(entrenamiento.frecuenciaCardiaca), fcMaxima: fcMaxima)
        return Text(nombre)
            .font(.footnote.weight(.bold))
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.25), in: Capsule())
            .foregroundStyle(color)
    }

    static func zona(fc: Int, fcMaxima: Int) -> (String, Color) {
        guard fc > 0, fcMaxima > 0 else { return ("––", .gray) }
        switch Double(fc) / Double(fcMaxima) {
        case ..<0.6: return ("Z1", .blue)
        case ..<0.7: return ("Z2", .green)
        case ..<0.8: return ("Z3", .yellow)
        case ..<0.9: return ("Z4", .orange)
        default: return ("Z5", .red)
        }
    }

    // MARK: - Modo solo audio: el cronómetro sigue de protagonista

    private var cronometroGrande: some View {
        Text(formatearTiempo(reproductor.tiempoTranscurrido))
            .font(.system(size: 40, weight: .semibold, design: .rounded))
            .monospacedDigit()
    }

    // MARK: - Secundario y controles

    @ViewBuilder
    private var infoSecundaria: some View {
        if !reproductor.nombrePistaActual.isEmpty {
            Text(nombreLegible(reproductor.nombrePistaActual))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }

        if let tramo = entrenador.tramoActual {
            Text("\(tramo.nombre): \(tramo.descripcion)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }

        if let proximo = avisador.proximoAviso {
            let faltan = max(0, proximo.minuto - Int(reproductor.tiempoTranscurrido / 60))
            Text("Próximo: «\(proximo.texto)» en \(faltan) min")
                .font(.footnote)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }

        if reproductor.estado == .pausado {
            Text("En pausa — todo congelado")
                .font(.footnote)
                .foregroundStyle(.orange)
        }

        if let error = entrenamiento.mensajeError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

}

#Preview {
    ContentView()
}
