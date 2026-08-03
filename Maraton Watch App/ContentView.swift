import SwiftUI
import WatchKit

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

    @State private var cuentaRegresiva: Int?
    @State private var planPendiente: Plan?

    var body: some View {
        if let numero = cuentaRegresiva {
            ZStack {
                LinearGradient(colors: [.green.opacity(0.4), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                Text("\(numero)")
                    .font(.system(size: 80, weight: .bold, design: .rounded))
                    .foregroundStyle(.green)
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
            }
        } else if reproductor.preparando {
            VStack(spacing: 8) {
                ProgressView()
                Text("Activando audio…")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } else if reproductor.estado == .detenido {
            lobby
        } else {
            PantallaReproduccion()
        }
    }

    private var lobby: some View {
        ScrollView {
            VStack(spacing: 10) {
                Label("Maratón", systemImage: "figure.run")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)

                if let resumen = entrenamiento.resumen {
                    vistaResumen(resumen)
                }
                if let plan = conectividad.plan {
                    vistaPlan(plan)
                } else {
                    vistaSinPlan
                }
            }
            .padding(.horizontal, 4)
        }
    }

    /// Tarjeta con los números de la carrera recién guardada.
    private func vistaResumen(_ resumen: ResumenCarrera) -> some View {
        VStack(spacing: 3) {
            Text("¡Carrera guardada!")
                .font(.headline)
            Text(formatearTiempo(resumen.duracion))
                .font(.title3)
                .monospacedDigit()
            Text(String(format: "%.2f km", resumen.distanciaMetros / 1000))
                .monospacedDigit()
            if let ritmo = resumen.ritmoPromedioSegKm {
                Text("Ritmo \(formatearRitmo(ritmo)) /km")
                    .font(.footnote)
            }
            HStack(spacing: 10) {
                if let fc = resumen.fcPromedio {
                    Label("\(fc)", systemImage: "heart.fill")
                        .foregroundStyle(.red)
                }
                Label("\(Int(resumen.calorias)) kcal", systemImage: "flame.fill")
                    .foregroundStyle(.orange)
            }
            .font(.footnote)
            Text("Mapa y detalles: «Mis carreras» en el iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Listo") {
                entrenamiento.resumen = nil
            }
            .buttonStyle(.bordered)
        }
        .padding(8)
        .frame(maxWidth: .infinity)
        .background(Color.green.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
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
            comenzarCuentaRegresiva(plan)
        } label: {
            Label("Play", systemImage: "play.fill")
                .font(.title3)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(!musicaExterna && listas == 0)

        // El error de arranque va acá arriba, pegado al Play: abajo de
        // todo no lo veía nadie.
        if let error = reproductor.mensajeError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Cuenta regresiva 3-2-1

    private func comenzarCuentaRegresiva(_ plan: Plan) {
        planPendiente = plan
        cuentaRegresiva = 3
        WKInterfaceDevice.current().play(.start)
        programarTick()
    }

    private func programarTick() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            guard let actual = cuentaRegresiva else { return }
            if actual > 1 {
                cuentaRegresiva = actual - 1
                WKInterfaceDevice.current().play(.click)
                programarTick()
            } else {
                cuentaRegresiva = nil
                WKInterfaceDevice.current().play(.success)
                if let plan = planPendiente {
                    arrancar(plan)
                }
                planPendiente = nil
            }
        }
    }

    private func controles(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
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
        .padding(10)
        .background(Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: Diseno.radioTarjeta))
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
                panelPlan
                panelParciales
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Paneles al deslizar hacia abajo

    /// El plan completo con progreso: ✓ tramos cumplidos, ▶ el actual
    /// (con los km que llevás dentro de él), y los pendientes.
    @ViewBuilder
    private var panelPlan: some View {
        if !entrenador.tramosDelPlan.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("PLAN")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                ForEach(Array(entrenador.tramosDelPlan.enumerated()), id: \.element.id) { indice, tramo in
                    filaTramo(indice: indice, tramo: tramo)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: Diseno.radioTarjeta))
        }
    }

    private func filaTramo(indice: Int, tramo: Tramo) -> some View {
        let esActual = indice == entrenador.indiceActual && entrenador.tramoActual != nil
        return HStack(spacing: 6) {
            Image(systemName: indice < entrenador.indiceActual
                  ? "checkmark.circle.fill"
                  : (esActual ? "arrowtriangle.right.circle.fill" : "circle"))
                .font(.system(size: 12))
                .foregroundStyle(indice < entrenador.indiceActual
                                 ? Color.green
                                 : (esActual ? Color.accentColor : Color.secondary))
            VStack(alignment: .leading, spacing: 0) {
                Text(tramo.nombre)
                    .font(.footnote.weight(esActual ? .semibold : .regular))
                    .lineLimit(1)
                Text(esActual ? progresoDelTramo(indice, tramo) : tramo.descripcion)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }

    /// "1.24 / 3.0 km" del tramo en curso.
    private func progresoDelTramo(_ indice: Int, _ tramo: Tramo) -> String {
        let inicioMetros = entrenador.tramosDelPlan.prefix(indice)
            .reduce(0.0) { $0 + $1.kilometros * 1000 }
        let recorrido = max(0, entrenamiento.distanciaMetros - inicioMetros) / 1000
        return String(format: "%.2f / %.1f km", recorrido, tramo.kilometros)
    }

    @ViewBuilder
    private var panelParciales: some View {
        if !entrenador.parciales.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("PARCIALES")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(1)
                ForEach(entrenador.parciales) { parcial in
                    HStack {
                        Text("Km \(parcial.km)")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatearRitmo(parcial.segundos))
                            .monospacedDigit()
                    }
                    .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(Color.white.opacity(0.06),
                        in: RoundedRectangle(cornerRadius: Diseno.radioTarjeta))
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

    private var metricasDeCarrera: some View {
        VStack(spacing: 8) {
            // El ritmo es el héroe: número gigante con semáforo de color.
            VStack(spacing: 0) {
                Text(entrenamiento.ritmoActualSegKm.map(formatearRitmo) ?? "–:––")
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(colorDeRitmo)
                Text("RITMO /KM")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .tracking(1.2)
            }

            Grid(horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    celdaMetrica("DISTANCIA",
                                 String(format: "%.2f", entrenamiento.distanciaMetros / 1000),
                                 color: .primary)
                    celdaZona
                }
                GridRow {
                    celdaMetrica("TIEMPO",
                                 formatearTiempo(reproductor.tiempoTranscurrido),
                                 color: .primary)
                    celdaMetrica("PULSO",
                                 "\(Int(entrenamiento.frecuenciaCardiaca))",
                                 color: .red)
                }
            }
        }
    }

    private func celdaMetrica(_ titulo: String, _ valor: String, color: Color) -> some View {
        VStack(spacing: 1) {
            Text(valor)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(titulo)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private var celdaZona: some View {
        let (nombre, color) = Self.zona(
            fc: Int(entrenamiento.frecuenciaCardiaca), fcMaxima: fcMaxima)
        return VStack(spacing: 1) {
            Text(nombre)
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(color)
            Text("ZONA")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(color.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    /// Semáforo del ritmo: verde si vas dentro del rango del tramo,
    /// naranja si estás afuera, blanco si el tramo es libre o no hay tramo.
    private var colorDeRitmo: Color {
        guard let ritmo = entrenamiento.ritmoActualSegKm,
              let tramo = entrenador.tramoActual,
              tramo.ritmoMinSegKm != nil || tramo.ritmoMaxSegKm != nil else {
            return .primary
        }
        if let rapido = tramo.ritmoMinSegKm, ritmo < rapido - 5 { return .orange }
        if let lento = tramo.ritmoMaxSegKm, ritmo > lento + 5 { return .orange }
        return .green
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
