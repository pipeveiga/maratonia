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

    /// true = la música la pone otra app (Spotify del reloj); Maratonia
    /// solo corre cronómetro, avisos y entrenamiento. Requiere
    /// "Registrar carrera": sin música propia, el workout es lo que
    /// mantiene viva la app en segundo plano.
    @AppStorage("musicaExterna") private var musicaExterna = false

    @ObservedObject private var estadoPlan = EstadoPlanWatch.compartido

    @State private var cuentaRegresiva: Int?
    @State private var planPendiente: Plan?
    @State private var libreEnCuentaRegresiva = false
    @State private var programadoEnCuentaRegresiva: UUID?

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

    // El lobby es deliberadamente mínimo: nombre del plan, estado de la
    // música y un Play grande. Todo lo configurable vive en Ajustes
    // (engranaje arriba a la derecha) para que antes de correr no haya
    // que leer una pila de interruptores.
    private var lobby: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let resumen = entrenamiento.resumen {
                        vistaResumen(resumen)
                    }
                    // Fase E: si el iPhone proyectó un entrenamiento
                    // para HOY, ese es el protagonista (identidad por
                    // programadoID, no por huella). Sin proyección
                    // vigente, el reloj se comporta como siempre — un
                    // iPhone viejo no rompe nada.
                    if let hoy = conectividad.entrenamientoDeHoy(DiaLocal(fecha: Date())) {
                        vistaEntrenamientoHoy(hoy.id, hoy.definicion)
                    } else if let plan = conectividad.plan {
                        vistaPlan(plan)
                    } else {
                        vistaSinPlan
                    }
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Maratonia")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AjustesReloj()
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                }
            }
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
            if resumen.usoGPS {
                Label(resumen.puntosRuta > 0
                      ? "Recorrido: \(resumen.puntosRuta) puntos GPS"
                      : "Sin señal GPS: quedó sin recorrido",
                      systemImage: resumen.puntosRuta > 0 ? "map.fill" : "location.slash.fill")
                    .font(.footnote)
                    .foregroundStyle(resumen.puntosRuta > 0 ? Color.secondary : Color.orange)
                    .multilineTextAlignment(.center)
            }
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

    // El lobby va partido en bloques chicos a propósito: SwiftUI admite
    // como máximo 10 vistas por bloque y de una sola pieza quedaba al
    // borde de ese límite.

    /// Fase E — el entrenamiento de HOY proyectado por el iPhone:
    /// tipo, nombre, estructura, EMPEZAR grande y Carrera libre debajo.
    /// Al terminar, el resultado vuelve al iPhone con el programadoID.
    @ViewBuilder
    private func vistaEntrenamientoHoy(_ programadoID: UUID,
                                       _ definicion: DefinicionEntrenamiento) -> some View {
        let planAudio = conectividad.plan ?? .vacio
        VStack(spacing: 3) {
            Text("HOY")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.green)
                .tracking(1)
            Text(definicion.nombre)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(definicion.resumenEstructura)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if !definicion.descripcion.isEmpty {
                Text(definicion.descripcion)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }

        estadoDeMusica(planAudio)

        botonPlay(planParaDefinicion(definicion, audio: planAudio),
                  libre: false, titulo: "Entrenamiento",
                  programadoID: programadoID)

        Button {
            comenzarCuentaRegresiva(planAudio, libre: true)
        } label: {
            Label("Carrera libre", systemImage: "hare.fill")
                .font(.footnote)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)

        piePlan(planAudio)
    }

    /// El plan de la SESIÓN para un entrenamiento V2: los tramos salen
    /// de la definición (distancia y tiempo); música y avisos, de la
    /// configuración de audio que ya vive en el reloj.
    private func planParaDefinicion(_ definicion: DefinicionEntrenamiento,
                                    audio: Plan) -> Plan {
        var plan = audio
        plan.nombre = definicion.nombre
        let tramos = definicion.tramosEjecutables
        plan.tramos = tramos.isEmpty ? nil : tramos
        return plan
    }

    /// La Home SIEMPRE ofrece una acción para salir a correr:
    /// entrenamiento pendiente → Entrenamiento primero, Carrera libre
    /// segunda; cumplido o sin tramos → Carrera libre primera (el plan
    /// y su historial siguen existiendo).
    @ViewBuilder
    private func vistaPlan(_ plan: Plan) -> some View {
        let estado = estadoDelEntrenamiento(plan: plan,
                                            huellaCumplida: estadoPlan.huellaCumplida)
        cabecera(plan)
        if estado == .pendiente {
            botonPlay(plan, libre: false, titulo: "Entrenamiento")
            Button {
                comenzarCuentaRegresiva(plan, libre: true)
            } label: {
                Label("Carrera libre", systemImage: "hare.fill")
                    .font(.footnote)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else {
            botonPlay(plan, libre: true, titulo: "Carrera libre")
            if estado == .cumplido {
                Label("Entrenamiento cumplido", systemImage: "checkmark.seal.fill")
                    .font(.footnote)
                    .foregroundStyle(.green)
            }
        }
        piePlan(plan)
    }

    @ViewBuilder
    private func cabecera(_ plan: Plan) -> some View {
        Text(plan.nombre)
            .font(.headline)
            .multilineTextAlignment(.center)

        estadoDeMusica(plan)

        if let datos = datosDelPlan(plan) {
            Text(datos)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    /// Una sola línea de estado con color: reemplaza el viejo bloque de
    /// textos sobre pistas listas/faltantes.
    @ViewBuilder
    private func estadoDeMusica(_ plan: Plan) -> some View {
        let faltantes = conectividad.pistasFaltantes
        if musicaExterna {
            Label("Música de otra app", systemImage: "music.note.list")
                .font(.footnote)
                .foregroundStyle(.purple)
        } else if plan.pistas.isEmpty {
            Label("Sin música cargada", systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
        } else if faltantes.isEmpty {
            Label(plan.pistas.count == 1 ? "1 pista lista" : "\(plan.pistas.count) pistas listas",
                  systemImage: "checkmark.circle.fill")
                .font(.footnote)
                .foregroundStyle(.green)
        } else {
            Label("Faltan \(faltantes.count) de \(plan.pistas.count) pistas",
                  systemImage: "arrow.down.circle")
                .font(.footnote)
                .foregroundStyle(.orange)
        }
    }

    /// Play redondo grande, como la app Entrenamiento de Apple, con la
    /// etiqueta de qué arranca ("Entrenamiento" o "Carrera libre").
    @ViewBuilder
    private func botonPlay(_ plan: Plan, libre: Bool, titulo: String,
                           programadoID: UUID? = nil) -> some View {
        let listas = plan.pistas.count - conectividad.pistasFaltantes.count
        VStack(spacing: 4) {
            Button {
                comenzarCuentaRegresiva(plan, libre: libre, programadoID: programadoID)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 32, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(width: 76, height: 76)
                    .background(Circle().fill(Color.green.gradient))
            }
            .buttonStyle(.plain)
            // La carrera libre y el entrenamiento PROYECTADO nunca se
            // bloquean: sin música local arrancan igual, sin música
            // propia. Solo el entrenamiento V1 (de tramos manuales,
            // pensado alrededor de las pistas) espera su música.
            .disabled(!libre && programadoID == nil && !musicaExterna && listas == 0)
            Text(titulo)
                .font(.footnote.weight(.semibold))
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func piePlan(_ plan: Plan) -> some View {
        Label(resumenDeModo, systemImage: iconoDeModo)
            .font(.footnote)
            .foregroundStyle(.secondary)

        // El error de arranque va acá, pegado al Play: abajo de todo no
        // lo veía nadie.
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
    }

    /// Cómo va a arrancar la sesión, en cuatro palabras. El detalle y los
    /// cambios viven en Ajustes.
    private var resumenDeModo: String {
        if !modoEntrenamiento { return "Solo música y avisos" }
        return rutaGPS ? "Carrera con GPS" : "Carrera sin GPS"
    }

    private var iconoDeModo: String {
        if !modoEntrenamiento { return "music.note" }
        return rutaGPS ? "location.fill" : "heart.fill"
    }

    /// "12 avisos · 3 tramos": qué trae el plan, en una sola línea.
    /// El horizonte (12 h) es el mismo que usa el Avisador, para que el
    /// número mostrado coincida con lo que de verdad va a sonar.
    private func datosDelPlan(_ plan: Plan) -> String? {
        var partes: [String] = []
        let avisos = plan.cronograma(duracionMaximaMinutos: 12 * 60).count
            + plan.avisosKmActivos.count
        if avisos > 0 { partes.append(avisos == 1 ? "1 aviso" : "\(avisos) avisos") }
        if !plan.tramosActivos.isEmpty {
            let n = plan.tramosActivos.count
            partes.append(n == 1 ? "1 tramo" : "\(n) tramos")
        }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }

    // MARK: - Cuenta regresiva 3-2-1

    private func comenzarCuentaRegresiva(_ plan: Plan, libre: Bool,
                                         programadoID: UUID? = nil) {
        planPendiente = plan
        libreEnCuentaRegresiva = libre
        programadoEnCuentaRegresiva = programadoID
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
                    arrancar(plan, libre: libreEnCuentaRegresiva,
                             programadoID: programadoEnCuentaRegresiva)
                }
                planPendiente = nil
                programadoEnCuentaRegresiva = nil
            }
        }
    }

    /// La música y los avisos arrancan siempre primero: son el corazón de
    /// la app y no deben depender de que Salud o el GPS estén disponibles.
    /// El entrenamiento se engancha al callback de arranque REAL del
    /// audio: si el audio falla, no queda un workout fantasma grabando
    /// con la app de vuelta en el lobby y sin botón para pararlo.
    private func arrancar(_ plan: Plan, libre: Bool, programadoID: UUID? = nil) {
        // Carrera libre = la MISMA infraestructura (música, avisos, GPS,
        // Salud, auto-pausa, recovery) sin tramos: el entrenador de
        // ritmo no opina y el entrenamiento planificado NO se consume
        // (sin tramos no hay huella que marcar).
        var planSesion = plan
        if libre { planSesion.tramos = nil }

        let hayMusicaLocal = planSesion.pistas.contains { conectividad.archivosLocales.contains($0) }
        // Libre o programado sin música en el reloj: arrancan igual,
        // sin música propia (el workout mantiene viva la app).
        let externa = musicaExterna || ((libre || programadoID != nil) && !hayMusicaLocal)
        // "Registrar carrera" se respeta también en libre (convivencia
        // con Runna); se fuerza cuando no hay música propia (sin audio,
        // el workout mantiene viva la app) y SIEMPRE en un programado:
        // sin workout no hay HKWorkout.uuid ni resultado que devolver.
        let entrenar = modoEntrenamiento || (libre && !hayMusicaLocal) || programadoID != nil
        let conGPS = rutaGPS
        reproductor.iniciar(plan: planSesion, urlDe: conectividad.urlDePista,
                            musicaExterna: externa) {
            guard entrenar else { return }
            EntrenadorRitmo.compartido.iniciar(plan: planSesion)
            Entrenamiento.compartido.pedirPermisos(conGPS: conGPS) {
                Entrenamiento.compartido.iniciar(conGPS: conGPS, programadoID: programadoID)
            }
        }
    }

    /// Sin plan NO hay callejón sin salida: Carrera libre directa, con
    /// GPS, pulso y guardado en Salud.
    private var vistaSinPlan: some View {
        VStack(spacing: 8) {
            botonPlay(.vacio, libre: true, titulo: "Carrera libre")
            Text("GPS, pulso y guardado en Salud.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Text("Para música, avisos y tramos, mandá un plan desde el iPhone.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
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
        }
        .padding(.top, 6)
    }
}

struct PantallaReproduccion: View {
    @ObservedObject private var reproductor = Reproductor.compartido
    @ObservedObject private var avisador = Avisador.compartido
    @ObservedObject private var entrenamiento = Entrenamiento.compartido
    @ObservedObject private var entrenador = EntrenadorRitmo.compartido
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

    /// Botones redondos en grilla 2x2, como la app Entrenamiento de
    /// Apple: gesto conocido, dedos transpirados, cero lectura.
    private var paginaSesion: some View {
        ScrollView {
            VStack(spacing: 10) {
                Grid(horizontalSpacing: 14, verticalSpacing: 10) {
                    GridRow {
                        botonSesion(reproductor.estado == .reproduciendo ? "Pausar" : "Reanudar",
                                    icono: reproductor.estado == .reproduciendo ? "pause.fill" : "play.fill",
                                    color: reproductor.estado == .reproduciendo ? .orange : .green) {
                            reproductor.alternarPlayPausa()
                        }
                        botonSesion("Terminar", icono: "stop.fill", color: .red) {
                            confirmandoTerminar = true
                        }
                    }
                    GridRow {
                        botonSesion("Aviso", icono: "speaker.wave.2.fill", color: .blue) {
                            avisador.probar()
                        }
                        botonSesion("Cancelar", icono: "xmark", color: .gray) {
                            confirmandoCancelar = true
                        }
                    }
                }
                .padding(.top, 2)

                if reproductor.estado == .pausado {
                    Text("En pausa — todo congelado")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                } else {
                    Text("«Terminar» guarda la carrera en Salud.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 4)
        }
        .confirmationDialog("¿Terminar la sesión?", isPresented: $confirmandoTerminar) {
            Button("Terminar y guardar", role: .destructive) {
                // El cumplimiento del plan se decide ANTES de detener
                // (detener borra el estado del entrenador).
                EntrenadorRitmo.compartido.marcarCumplimientoSiCorresponde()
                Entrenamiento.compartido.estructuraCompletaAlGuardar =
                    EntrenadorRitmo.compartido.estructuraCompleta
                reproductor.detener()
                EntrenadorRitmo.compartido.detener()
                Entrenamiento.compartido.finalizar()
            }
            Button("Seguir", role: .cancel) {}
        } message: {
            Text("La carrera se guarda en Salud.")
        }
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
    }

    private func botonSesion(_ titulo: String, icono: String, color: Color,
                             accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            VStack(spacing: 4) {
                Image(systemName: icono)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(color.opacity(0.22)))
                Text(titulo)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
        }
        .buttonStyle(.plain)
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
                Text(esActual ? (entrenador.textoProgresoTramo ?? tramo.descripcion) : tramo.descripcion)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
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

    /// Mini reproductor: nombre de la pista protagonista y dos botones
    /// redondos (pausar solo la música / siguiente).
    private var paginaMusica: some View {
        ScrollView {
            VStack(spacing: 10) {
                if reproductor.modoMusicaExterna {
                    Image(systemName: "music.note.list")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .padding(.top, 14)
                    Text("La música la maneja otra app (Spotify). Usá sus controles o el Now Playing del reloj.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                } else {
                    Text("MÚSICA")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .tracking(1.2)

                    Text(reproductor.nombrePistaActual.isEmpty
                         ? "Sin pista"
                         : nombreLegible(reproductor.nombrePistaActual))
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)

                    HStack(spacing: 16) {
                        Button {
                            reproductor.alternarSoloMusica()
                        } label: {
                            Image(systemName: reproductor.musicaSilenciada ? "play.fill" : "pause.fill")
                                .font(.system(size: 24, weight: .bold))
                                .foregroundStyle(.black)
                                .frame(width: 62, height: 62)
                                .background(Circle().fill(
                                    reproductor.musicaSilenciada ? Color.green.gradient : Color.blue.gradient))
                        }
                        .buttonStyle(.plain)

                        Button {
                            reproductor.siguiente()
                        } label: {
                            Image(systemName: "forward.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .frame(width: 46, height: 46)
                                .background(Circle().fill(Color.white.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)

                    Text(reproductor.musicaSilenciada
                         ? "Música en pausa: avisos y entrenamiento siguen."
                         : "Pausa solo la música: avisos y entrenamiento siguen.")
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
            fc: Int(entrenamiento.frecuenciaCardiaca),
            reposo: entrenamiento.fcReposo ?? 60,
            fcMaxima: entrenamiento.fcMaxima)
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

    /// Presentación de la zona (el cálculo vive en zonaCardiaca, en
    /// Shared/Plan.swift — misma fórmula que el aviso hablado).
    static func zona(fc: Int, reposo: Int, fcMaxima: Int) -> (String, Color) {
        switch zonaCardiaca(fc: fc, reposo: reposo, maxima: fcMaxima) {
        case 1: return ("Z1", .blue)
        case 2: return ("Z2", .green)
        case 3: return ("Z3", .yellow)
        case 4: return ("Z4", .orange)
        case 5: return ("Z5", .red)
        default: return ("––", .gray)
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

        if entrenamiento.activo, entrenamiento.usaGPS, entrenamiento.puntosRuta == 0 {
            Label("GPS: buscando señal…", systemImage: "location.slash")
                .font(.footnote)
                .foregroundStyle(.orange)
        }

        if reproductor.estado == .pausado {
            Text(entrenamiento.enPausaAutomatica
                 ? "Pausa automática — al arrancar sigue solo"
                 : "En pausa — todo congelado")
                .font(.footnote)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        }

        if let error = entrenamiento.mensajeError {
            Text(error)
                .font(.footnote)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
        }
    }

}

// MARK: - Ajustes del reloj

/// Todo lo configurable de la sesión, fuera del lobby: una lista nativa
/// de watchOS con interruptores y una pantalla propia para la FC máxima.
struct AjustesReloj: View {
    @AppStorage("modoEntrenamiento") private var modoEntrenamiento = true
    @AppStorage("rutaGPS") private var rutaGPS = true
    @AppStorage("musicaExterna") private var musicaExterna = false
    @AppStorage("autoPausa") private var autoPausa = true
    @AppStorage("avisarZonas") private var avisarZonas = true

    var body: some View {
        List {
            Section {
                Toggle(isOn: $musicaExterna) {
                    Label("Música de otra app", systemImage: "music.note.list")
                }
                .tint(.purple)
                .onChange(of: musicaExterna) {
                    if musicaExterna {
                        modoEntrenamiento = true
                    }
                }
            } footer: {
                Text(musicaExterna
                     ? "Ponés la música con Spotify u otra app; Maratonia corre avisos y entrenamiento, y la voz baja el volumen al hablar."
                     : "Apagado: Maratonia reproduce las pistas que mandaste desde el iPhone.")
            }

            Section {
                Toggle(isOn: $modoEntrenamiento) {
                    Label("Registrar carrera", systemImage: "heart.fill")
                }
                .tint(.red)
                .disabled(musicaExterna)

                if modoEntrenamiento {
                    Toggle(isOn: $rutaGPS) {
                        Label("Ruta GPS", systemImage: "map.fill")
                    }
                    .tint(.blue)

                    Toggle(isOn: $autoPausa) {
                        Label("Auto-pausa", systemImage: "pause.circle.fill")
                    }
                    .tint(.orange)

                    Toggle(isOn: $avisarZonas) {
                        Label("Avisar zona de pulso", systemImage: "heart.text.square.fill")
                    }
                    .tint(.pink)
                }
            } footer: {
                Text(modoEntrenamiento
                     ? "Guarda FC, distancia y ruta en Salud. No uses Runna a la vez. Auto-pausa (requiere GPS): al frenar en un semáforo pausa todo y sigue sola. Las zonas se calculan solas con tu edad y tu FC en reposo de Salud."
                     : "Solo música y avisos: compatible con Runna u otro tracker.")
            }
        }
        .navigationTitle("Ajustes")
    }
}

#Preview {
    ContentView()
}
