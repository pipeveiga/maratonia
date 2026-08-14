import SwiftUI
import UniformTypeIdentifiers

// La app iPhone en 4 pestañas: Plan (armar el entrenamiento), Reloj
// (enviar y estado), Carreras (historial con mapas) y Perfil (cuenta y
// ayuda). Cada parte del plan tiene su propia pantalla — nada de una
// sola lista infinita.

enum Pestana: Hashable {
    case plan, correr, progreso, carreras, perfil
}

struct ContentView: View {
    @StateObject private var store = PlanStore()
    // Se declara DESPUÉS de PlanStore a propósito: PlanStore corre la
    // migración de ensayo primero y AlmacenStore hace el cutover sobre
    // el ensayo fresco (aunque ambos órdenes son seguros).
    @StateObject private var almacen = AlmacenStore()
    @State private var mostrandoTutorial = false

    /// Selección programática: EMPEZAR desde Plan te lleva a Correr,
    /// donde ya está el motor andando.
    @State private var pestana: Pestana = .plan

    /// El tutorial se abre solo la primera vez que se abre la app.
    @AppStorage("vioTutorial") private var vioTutorial = false

    /// El onboarding deportivo se OFRECE una sola vez (después queda en
    /// Perfil, nunca insiste).
    @AppStorage("ofrecioOnboarding") private var ofrecioOnboarding = false
    @State private var mostrandoOnboarding = false

    /// Identidad Maratonia (RC1): la bienvenida con cuenta OPCIONAL se
    /// muestra una única vez y SOLO en instalaciones limpias — un
    /// usuario con datos jamás la ve (su cuenta vive en Perfil).
    @AppStorage("vioBienvenida") private var vioBienvenida = false
    @State private var mostrandoBienvenida = false
    @StateObject private var identidad = IdentidadStore()

    var body: some View {
        TabView(selection: $pestana) {
            PlanTab(store: store, almacen: almacen, pestana: $pestana)
                .tabItem { Label("Plan", systemImage: "slider.horizontal.3") }
                .tag(Pestana.plan)
            CorrerTab(store: store, almacen: almacen)
                .tabItem { Label("Correr", systemImage: "figure.run") }
                .tag(Pestana.correr)
            // El Reloj dejó de ser pestaña (decisión D5): vive en
            // Perfil. Su lugar lo ocupa PROGRESO — correr, ver cómo
            // venís, correr de nuevo.
            ProgresoTab(almacen: almacen)
                .tabItem { Label("Progreso", systemImage: "chart.bar.fill") }
                .tag(Pestana.progreso)
            CarrerasTab()
                .tabItem { Label("Carreras", systemImage: "map.fill") }
                .tag(Pestana.carreras)
            PerfilTab(store: store, almacen: almacen, identidad: identidad,
                      mostrandoTutorial: $mostrandoTutorial)
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
                .tag(Pestana.perfil)
        }
        .sheet(isPresented: $mostrandoTutorial) {
            TutorialView()
        }
        .sheet(isPresented: $mostrandoOnboarding) {
            OnboardingDeportivo(almacen: almacen)
        }
        .fullScreenCover(isPresented: $mostrandoBienvenida) {
            BienvenidaView(identidad: identidad) {
                mostrandoBienvenida = false
                ofrecerOnboardingSiCorresponde()
            }
        }
        .onAppear {
            // Cableado cuenta ↔ dominio: crear cuenta asocia los datos
            // existentes al userID (migración sin duplicados).
            IdentidadStore.conectar(identidad, con: almacen)
            identidad.verificarRevocacionApple()
            if ofrecerBienvenidaSiCorresponde() { return }
            if !vioTutorial {
                vioTutorial = true
                mostrandoTutorial = true
            } else {
                ofrecerOnboardingSiCorresponde()
            }
        }
        .onChange(of: mostrandoTutorial) { _, abierto in
            if !abierto { ofrecerOnboardingSiCorresponde() }
        }
    }

    /// Bienvenida (cuenta opcional): una sola vez, SOLO instalación
    /// limpia — sin plan, sin sesiones, sin referencias y sin cuenta.
    private func ofrecerBienvenidaSiCorresponde() -> Bool {
        guard !vioBienvenida else { return false }
        vioBienvenida = true
        let dominio = almacen.almacen
        guard identidad.cuenta == nil,
              dominio.planActivo == nil,
              dominio.sesiones.isEmpty,
              dominio.referencias.isEmpty,
              store.plan.pistas.isEmpty else { return false }
        // El usuario nuevo entra por bienvenida → onboarding deportivo;
        // el tutorial legacy de audio queda disponible en Perfil →
        // Ayuda (mostrarlo TAMBIÉN en el segundo arranque era ruido).
        vioTutorial = true
        mostrandoBienvenida = true
        return true
    }

    /// El onboarding se OFRECE solo (una única vez) a quien no tiene
    /// nada: sin perfil, sin plan, sin sesiones, sin referencias. Un
    /// usuario existente jamás lo ve sin pedirlo (no destructivo);
    /// siempre queda disponible en Perfil.
    private func ofrecerOnboardingSiCorresponde() {
        guard !ofrecioOnboarding else { return }
        let dominio = almacen.almacen
        guard dominio.perfilDeportivo.fechaOnboarding == nil,
              dominio.planActivo == nil,
              dominio.sesiones.isEmpty,
              dominio.referencias.isEmpty else {
            ofrecioOnboarding = true
            return
        }
        ofrecioOnboarding = true
        mostrandoOnboarding = true
    }
}

/// Fila de navegación con ícono de color, título y subtítulo.
///
/// Vive a nivel de ARCHIVO y no dentro de `PlanTab` porque la usan dos
/// pestañas distintas (Plan y Perfil). Estaba declarada `private` dentro
/// de `PlanTab` y `PerfilTab` la llamaba igual: eso no compila, un
/// miembro privado no cruza el borde del tipo. `private` a nivel de
/// archivo alcanza — las dos pestañas viven acá.
///
/// - titulo: literal → LocalizedStringKey (se traduce).
/// - subtitulo: String YA localizado por quien lo arma (son propiedades
///   computadas con `String(localized:)`).
private func filaNavegacion(icono: String, color: Color,
                            titulo: LocalizedStringKey,
                            subtitulo: String) -> some View {
    HStack(spacing: 12) {
        IconoAjuste(sistema: icono, color: color)
        VStack(alignment: .leading, spacing: 2) {
            Text(titulo)
            Text(subtitulo)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
    .padding(.vertical, 2)
}

// MARK: - Pestaña Plan

struct PlanTab: View {
    @ObservedObject var store: PlanStore
    @ObservedObject var almacen: AlmacenStore
    @Binding var pestana: Pestana
    @State private var confirmandoQuitarPlan = false

    private var hoy: DiaLocal { DiaLocal(fecha: Date()) }

    // El Plan responde tres preguntas, en este orden: ¿qué me toca HOY?
    // ¿cómo viene MI SEMANA? ¿qué SIGUE? Después el objetivo, el
    // calendario completo y — al final — la configuración de la sesión.
    var body: some View {
        NavigationStack {
            List {
                if let problema = store.mensajeProblema {
                    Section {
                        Label(problema, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                if almacen.almacen.planActivo == nil {
                    Section {
                        ContentUnavailableView {
                            Label("Sin plan activo", systemImage: "figure.run.square.stack")
                        } description: {
                            // Con objetivo ya elegido, el texto genérico
                            // ("elegí un objetivo") mandaba a hacer algo
                            // que ya estaba hecho.
                            if let objetivo = almacen.almacen.perfilDeportivo.objetivo {
                                Text("\(TextosObjetivo.nombre(de: objetivo)) — te falta el plan.")
                            } else {
                                Text("Elegí tu objetivo y armamos el plan.")
                            }
                        } actions: {
                            NavigationLink("Explorar planes") {
                                CatalogoView(almacen: almacen)
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .listRowBackground(Color.clear)
                    }
                }

                seccionHoy
                seccionSemana
                seccionProximos
                seccionObjetivo

                Section("Plan de entrenamiento") {
                    if almacen.almacen.planActivo != nil {
                        NavigationLink {
                            CalendarioView(almacen: almacen)
                        } label: {
                            filaNavegacion(icono: "calendar", color: .green,
                                           titulo: "Calendario", subtitulo: subtituloCalendario)
                        }
                    }
                    NavigationLink {
                        CatalogoView(almacen: almacen)
                    } label: {
                        filaNavegacion(icono: "sparkles", color: .purple,
                                       titulo: "Explorar planes", subtitulo: subtituloCatalogo)
                    }
                    if almacen.almacen.planActivo != nil {
                        Button(role: .destructive) {
                            confirmandoQuitarPlan = true
                        } label: {
                            Label("Quitar plan", systemImage: "minus.circle")
                        }
                        .confirmationDialog("¿Quitar el plan actual?",
                                            isPresented: $confirmandoQuitarPlan,
                                            titleVisibility: .visible) {
                            Button("Quitar plan (queda archivado)", role: .destructive) {
                                almacen.almacen.abandonarPlan()
                            }
                            Button("Cancelar", role: .cancel) {}
                        } message: {
                            Text("Se archiva: no se borra nada.")
                        }
                    }
                }

                // La configuración de la SESIÓN (música, avisos, tramos
                // manuales) es lo último: acompaña, no protagoniza.
                Section("Configuración del entrenamiento") {
                    NavigationLink {
                        ConfiguracionEntrenamientoScreen(store: store)
                    } label: {
                        filaNavegacion(icono: "slider.horizontal.3", color: .blue,
                                       titulo: "Audio, avisos y tramos",
                                       subtitulo: subtituloConfiguracion)
                    }
                }
            }
            .navigationTitle("Maratonia")
            .scrollDismissesKeyboard(.immediately)
        }
    }

    /// HOY con UNA SOLA interpretación del dominio: pendiente se ofrece
    /// (EMPEZAR), resuelto se muestra como resultado (cumplido/parcial/
    /// omitido), y "descanso" SOLO cuando de verdad no hubo nada.
    @ViewBuilder
    private var seccionHoy: some View {
        if let pendiente = almacen.almacen.entrenamientoDeHoy(hoy) {
            Section {
                TarjetaEntrenamientoV2(programado: pendiente) {
                    LanzadorSesion.iniciar(definicion: pendiente.definicion,
                                           programadoID: pendiente.id,
                                           store: store, almacen: almacen)
                    pestana = .correr
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        } else if let resuelto = almacen.almacen.programadoDelDia(hoy) {
            Section {
                NavigationLink {
                    DetalleEntrenamientoView(almacen: almacen, store: store,
                                             pestana: $pestana,
                                             programadoID: resuelto.id)
                } label: {
                    TarjetaEntrenamientoV2(programado: resuelto)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var seccionSemana: some View {
        if almacen.almacen.planActivo != nil,
           almacen.almacen.semanaActual(hoy: hoy).contains(where: { $0.programado != nil }) {
            Section {
                SemanaActualV2(almacen: almacen, store: store, pestana: $pestana)
            } header: {
                HStack {
                    Text("Tu semana")
                    Spacer()
                    Text(progresoDeSemana)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
    }

    private var progresoDeSemana: String {
        let programados = almacen.almacen.semanaActual(hoy: hoy).compactMap(\.programado)
        let hechos = programados.filter {
            $0.resolucion == .cumplido || $0.resolucion == .parcial
        }.count
        return String(localized: "\(hechos) de \(programados.count)")
    }

    @ViewBuilder
    private var seccionProximos: some View {
        let proximos = almacen.almacen.proximosEntrenamientos(despuesDe: hoy, maximo: 3)
        if !proximos.isEmpty {
            Section("Próximos") {
                ForEach(proximos) { programado in
                    NavigationLink {
                        DetalleEntrenamientoView(almacen: almacen, store: store,
                                                 pestana: $pestana,
                                                 programadoID: programado.id)
                    } label: {
                        HStack(spacing: 12) {
                            // Fila deportiva: el tipo como bloque de
                            // color con su inicial de día, no un punto.
                            VStack(spacing: 0) {
                                if let fecha = programado.dia?.fecha() {
                                    Text(FormatoFecha.diaYMes(fecha).prefix(6))
                                        .font(.caption2.weight(.bold))
                                }
                            }
                            .frame(width: 52, height: 40)
                            .background(DV2.color(de: programado.definicion.tipo).opacity(0.15),
                                        in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(DV2.color(de: programado.definicion.tipo))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(programado.definicion.nombre)
                                    .font(.subheadline.weight(.semibold))
                                // Los km ya tienen jerarquía propia a
                                // la derecha: acá va lo complementario.
                                Text(programado.definicion.descripcion.isEmpty
                                     ? Plurales.segmentos(programado.definicion.segmentos.count)
                                     : programado.definicion.descripcion)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if let km = programado.definicion.distanciaPrescritaKm {
                                Text(km == km.rounded()
                                     ? "\(Int(km)) km"
                                     : String(format: "%.1f km", km))
                                    .font(.subheadline.weight(.bold))
                                    .monospacedDigit()
                                    .foregroundStyle(DV2.Marca.profundo)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    /// El objetivo con countdown en semanas — motivación, nunca presión.
    ///
    /// Lleva encabezado propio y es tocable a propósito: sin eso la fila
    /// se leía como "un plan" (misma forma que las filas de abajo) y
    /// aparecía justo debajo de "Sin plan activo", que es la
    /// contradicción exacta que reportó el uso real. El objetivo es del
    /// PERFIL y sobrevive a quitar el plan — eso es correcto, pero hay
    /// que decirlo.
    @ViewBuilder
    private var seccionObjetivo: some View {
        let perfil = almacen.almacen.perfilDeportivo
        if let objetivo = perfil.objetivo {
            // El objetivo que NO pudo convertirse en plan no se muestra
            // como si lo fuera. Antes salía con cuenta regresiva —
            // "Faltan 5 semanas para tu carrera"— sin nada detrás.
            if let motivo = perfil.objetivoSinPlan, almacen.almacen.planActivo == nil {
                Section {
                    AvisoSinPlan(
                        motivo: motivo, objetivo: objetivo,
                        puente: EvaluadorElegibilidad.objetivoPuente(para: objetivo)
                    ) { _ in pestana = .perfil }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }
            } else {
                Section {
                    Button {
                        pestana = .perfil
                    } label: {
                        HStack(spacing: 12) {
                            IconoAjuste(sistema: "flag.checkered", color: .red)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(TextosObjetivo.nombre(de: objetivo))
                                // La cuenta regresiva SOLO con plan: es
                                // la promesa de que hay algo detrás.
                                if almacen.almacen.planActivo != nil,
                                   let cuenta = TextosObjetivo.cuentaRegresiva(
                                    hasta: perfil.fechaObjetivo, hoy: hoy) {
                                    Text(cuenta)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                } else if almacen.almacen.planActivo == nil {
                                    Text("Sin plan todavía")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } header: {
                    Text("Tu objetivo")
                }
            }
        }
    }

    /// Una sola interpretación de HOY (bug de build 39: Correr decía
    /// "parcial" y Plan decía "no hay entrenamiento").
    private var subtituloCalendario: String {
        if let deHoy = almacen.almacen.programadoDelDia(hoy) {
            switch deHoy.resolucion {
            case .pendiente: return String(localized: "Hoy: \(deHoy.definicion.nombre)")
            case .cumplido: return String(localized: "Hoy: \(deHoy.definicion.nombre) — cumplido")
            case .parcial: return String(localized: "Hoy: \(deHoy.definicion.nombre) — parcial")
            case .omitido: return String(localized: "Hoy: \(deHoy.definicion.nombre) — omitido")
            }
        }
        let vencidos = almacen.almacen.vencidos(hoy).count
        if vencidos > 0 {
            return vencidos == 1
                ? String(localized: "1 entrenamiento vencido")
                : String(localized: "\(vencidos) entrenamientos vencidos")
        }
        return String(localized: "Hoy: descanso")
    }

    private var subtituloCatalogo: String {
        almacen.almacen.planActivo == nil
            ? String(localized: "Elegí un plan de 5K o 10K")
            : String(localized: "Cambiar de plan (el actual se archiva)")
    }

    private var subtituloConfiguracion: String {
        var partes: [String] = []
        if !store.plan.pistas.isEmpty { partes.append(Plurales.pistas(store.plan.pistas.count)) }
        let avisos = store.plan.avisosFijos.count + store.plan.avisosRepetidos.count
            + store.plan.avisosKmActivos.count
        if avisos > 0 { partes.append(String(localized: "\(avisos) avisos")) }
        if !store.plan.tramosActivos.isEmpty {
            partes.append(Plurales.tramos(store.plan.tramosActivos.count))
        }
        return partes.isEmpty
            ? String(localized: "Música, avisos por voz y tramos manuales")
            : partes.joined(separator: " · ")
    }

}

// MARK: - Configuración del entrenamiento (legacy, un nivel abajo)

/// Las cuatro pantallas de siempre (música, avisos, tramos manuales,
/// cronograma), intactas pero un nivel abajo del Plan: la configuración
/// de la SESIÓN no compite con el calendario del entrenamiento.
struct ConfiguracionEntrenamientoScreen: View {
    @ObservedObject var store: PlanStore
    @State private var editandoNombre = false
    @State private var nombreBorrador = ""

    var body: some View {
        List {
            Section {
                HStack {
                    LabeledContent("Nombre", value: store.plan.nombre)
                    Button {
                        nombreBorrador = store.plan.nombre
                        editandoNombre = true
                    } label: {
                        Image(systemName: "pencil.circle.fill")
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Editar el nombre del plan")
                }
            } footer: {
                Text("El nombre que ves en el reloj al mandar el plan.")
            }
            .alert("Nombre del plan", isPresented: $editandoNombre) {
                TextField("Nombre", text: $nombreBorrador)
                Button("Guardar") {
                    let limpio = nombreBorrador.trimmingCharacters(in: .whitespaces)
                    if !limpio.isEmpty { store.plan.nombre = limpio }
                }
                Button("Cancelar", role: .cancel) {}
            }

            Section("Audio de la sesión") {
                NavigationLink {
                    MusicaScreen(store: store)
                } label: {
                    filaConfiguracion(icono: "music.note", color: .blue,
                                      titulo: "Música", subtitulo: subtituloMusica)
                }
                NavigationLink {
                    AvisosScreen(store: store)
                } label: {
                    filaConfiguracion(icono: "bell.fill", color: .orange,
                                      titulo: "Avisos por voz", subtitulo: subtituloAvisos)
                }
                NavigationLink {
                    CronogramaScreen(store: store)
                } label: {
                    filaConfiguracion(icono: "clock.fill", color: .teal,
                                      titulo: "Cronograma", subtitulo: "Todos los avisos, en orden")
                }
            }
            Section {
                NavigationLink {
                    TramosScreen(store: store)
                } label: {
                    filaConfiguracion(icono: "speedometer", color: .green,
                                      titulo: "Tramos manuales", subtitulo: subtituloTramos)
                }
            } footer: {
                Text("Los tramos manuales aplican a la Carrera Libre. Los entrenamientos del plan traen su propia estructura.")
            }
        }
        .navigationTitle("Configuración")
    }

    private func filaConfiguracion(icono: String, color: Color,
                                   titulo: LocalizedStringKey,
                                   subtitulo: String) -> some View {
        HStack(spacing: 12) {
            IconoAjuste(sistema: icono, color: color)
            VStack(alignment: .leading, spacing: 2) {
                Text(titulo)
                Text(subtitulo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtituloMusica: String {
        store.plan.pistas.isEmpty
            ? String(localized: "Importá tus MP3")
            : "\(Plurales.pistas(store.plan.pistas.count)) · \(formatearDuracion(store.duracionTotal))"
    }

    private var subtituloAvisos: String {
        let total = store.plan.avisosFijos.count
            + store.plan.avisosRepetidos.count
            + store.plan.avisosKmActivos.count
        return total == 0
            ? String(localized: "«Tomá agua», «comé un gel»…")
            : String(localized: "\(total) avisos configurados")
    }

    private var subtituloTramos: String {
        store.plan.tramosActivos.isEmpty
            ? String(localized: "Armá bloques con objetivo de ritmo")
            : String(localized: "\(Plurales.tramos(store.plan.tramosActivos.count)) con objetivo")
    }
}

// MARK: - Pantalla Música

struct MusicaScreen: View {
    @ObservedObject var store: PlanStore
    @State private var mostrandoImportador = false

    var body: some View {
        List {
            Section {
                if store.plan.pistas.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "music.note.list")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("Importá tus MP3 para armar la cola de la carrera.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }

                ForEach(store.plan.pistas, id: \.self) { nombre in
                    HStack(spacing: 10) {
                        IconoAjuste(sistema: "music.note", color: .blue)
                        Text(nombreSinExtension(nombre))
                            .lineLimit(1)
                        Spacer()
                        if let duracion = store.duraciones[nombre] {
                            Text(formatearDuracion(duracion))
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        } else {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
                .onDelete { store.borrarPistas(en: $0) }
                .onMove { store.moverPistas(de: $0, a: $1) }

                Button {
                    mostrandoImportador = true
                } label: {
                    Label("Importar MP3", systemImage: "plus.circle.fill")
                }
            } footer: {
                if !store.plan.pistas.isEmpty {
                    Text("Duración total: \(formatearDuracion(store.duracionTotal)) · Mantené apretado y arrastrá para reordenar.")
                }
            }
        }
        .navigationTitle("Música")
        .toolbar { EditButton() }
        .fileImporter(
            isPresented: $mostrandoImportador,
            allowedContentTypes: [.mp3, .audio],
            allowsMultipleSelection: true
        ) { resultado in
            if case .success(let urls) = resultado {
                store.importar(urls: urls)
            }
        }
    }
}

// MARK: - Pantalla Avisos

struct AvisosScreen: View {
    @ObservedObject var store: PlanStore
    @State private var fijoEnEdicion: AvisoFijo?
    @State private var repetidoEnEdicion: AvisoRepetido?
    @State private var kmEnEdicion: AvisoKm?

    var body: some View {
        List {
            Section {
                ForEach(store.plan.avisosFijos.sorted { $0.minuto < $1.minuto }) { aviso in
                    Button {
                        fijoEnEdicion = aviso
                    } label: {
                        HStack(spacing: 10) {
                            InsigniaMinuto(minuto: aviso.minuto)
                            Text(aviso.texto)
                                .foregroundStyle(.primary)
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.plan.avisosFijos.removeAll { $0.id == aviso.id }
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                }
                Button {
                    fijoEnEdicion = AvisoFijo(minuto: 30, texto: "")
                } label: {
                    Label("Agregar aviso fijo", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("En un minuto puntual")
            }

            Section {
                ForEach(store.plan.avisosRepetidos) { aviso in
                    Button {
                        repetidoEnEdicion = aviso
                    } label: {
                        HStack(spacing: 10) {
                            IconoAjuste(sistema: "repeat", color: .purple)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(aviso.texto)
                                    .foregroundStyle(.primary)
                                Text(descripcion(de: aviso))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.plan.avisosRepetidos.removeAll { $0.id == aviso.id }
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                }
                Button {
                    repetidoEnEdicion = AvisoRepetido(cadaMinutos: 20, desdeMinuto: 20, hastaMinuto: nil, texto: "")
                } label: {
                    Label("Agregar aviso repetido", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Repetidos")
            } footer: {
                Text("Cada aviso llega por voz, vibración y notificación. La música se pausa mientras habla y sigue después.")
            }

            Section {
                ForEach(store.plan.avisosKmActivos) { aviso in
                    Button {
                        kmEnEdicion = aviso
                    } label: {
                        HStack(spacing: 10) {
                            IconoAjuste(sistema: "flag.checkered", color: .teal)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(aviso.texto)
                                    .foregroundStyle(.primary)
                                Text(aviso.descripcion)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.plan.avisosKm?.removeAll { $0.id == aviso.id }
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                }
                Button {
                    kmEnEdicion = AvisoKm(kilometro: 5, cadaKm: nil, texto: "")
                } label: {
                    Label("Agregar aviso por km", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Por kilómetro")
            } footer: {
                Text("Suenan según la distancia recorrida — necesitan «Registrar carrera» activado en el reloj.")
            }
        }
        .navigationTitle("Avisos por voz")
        .sheet(item: $kmEnEdicion) { aviso in
            AvisoKmEditor(aviso: aviso) { actualizado in
                if var avisos = store.plan.avisosKm,
                   let indice = avisos.firstIndex(where: { $0.id == actualizado.id }) {
                    avisos[indice] = actualizado
                    store.plan.avisosKm = avisos
                } else {
                    store.plan.avisosKm = (store.plan.avisosKm ?? []) + [actualizado]
                }
            }
        }
        .sheet(item: $fijoEnEdicion) { aviso in
            AvisoFijoEditor(aviso: aviso) { actualizado in
                if let indice = store.plan.avisosFijos.firstIndex(where: { $0.id == actualizado.id }) {
                    store.plan.avisosFijos[indice] = actualizado
                } else {
                    store.plan.avisosFijos.append(actualizado)
                }
            }
        }
        .sheet(item: $repetidoEnEdicion) { aviso in
            AvisoRepetidoEditor(aviso: aviso) { actualizado in
                if let indice = store.plan.avisosRepetidos.firstIndex(where: { $0.id == actualizado.id }) {
                    store.plan.avisosRepetidos[indice] = actualizado
                } else {
                    store.plan.avisosRepetidos.append(actualizado)
                }
            }
        }
    }

    private func descripcion(de aviso: AvisoRepetido) -> String {
        // Las tres partes se localizan ENTERAS y no por pedazos: en otro
        // idioma el orden de la frase cambia, y concatenar fragmentos
        // traducidos produce oraciones que no existen.
        if let hasta = aviso.hastaMinuto {
            return String(localized: "Cada \(aviso.cadaMinutos) min, desde el min \(aviso.desdeMinuto) hasta el min \(hasta)")
        }
        return String(localized: "Cada \(aviso.cadaMinutos) min, desde el min \(aviso.desdeMinuto), sin límite")
    }
}

// MARK: - Pantalla Tramos

struct TramosScreen: View {
    @ObservedObject var store: PlanStore
    @State private var tramoEnEdicion: Tramo?
    @State private var mostrandoImportadorTramos = false

    var body: some View {
        List {
            Section {
                ForEach(store.plan.tramosActivos) { tramo in
                    Button {
                        tramoEnEdicion = tramo
                    } label: {
                        HStack(spacing: 10) {
                            IconoAjuste(sistema: "speedometer", color: .green)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(tramo.nombre)
                                    .foregroundStyle(.primary)
                                Text(tramo.descripcion)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .swipeActions {
                        Button(role: .destructive) {
                            store.plan.tramos?.removeAll { $0.id == tramo.id }
                        } label: {
                            Label("Borrar", systemImage: "trash")
                        }
                    }
                }

                Button {
                    tramoEnEdicion = Tramo(nombre: "", kilometros: 3, ritmoMinSegKm: nil, ritmoMaxSegKm: nil)
                } label: {
                    Label("Agregar tramo", systemImage: "plus.circle.fill")
                }

                Menu {
                    ForEach(PlanesSugeridos.todos, id: \.nombre) { plan in
                        Button(plan.nombre) {
                            store.plan.tramos = plan.tramos
                        }
                    }
                } label: {
                    Label("Usar un plan sugerido", systemImage: "sparkles")
                }
            } footer: {
                Text("Tocá un tramo para editarlo. Los planes sugeridos traen ritmos de referencia: ajustalos a los tuyos. El reloj anuncia cada tramo y corrige por voz (requiere «Registrar carrera»).")
            }

            Section {
                DisclosureGroup("Avanzado") {
                    Button {
                        mostrandoImportadorTramos = true
                    } label: {
                        Label("Pegar plan (JSON de ChatGPT)", systemImage: "doc.on.clipboard")
                            .font(.callout)
                    }
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Tramos y ritmo")
        .sheet(item: $tramoEnEdicion) { tramo in
            TramoEditor(tramo: tramo) { actualizado in
                if var tramos = store.plan.tramos,
                   let indice = tramos.firstIndex(where: { $0.id == actualizado.id }) {
                    tramos[indice] = actualizado
                    store.plan.tramos = tramos
                } else {
                    store.plan.tramos = (store.plan.tramos ?? []) + [actualizado]
                }
            }
        }
        .sheet(isPresented: $mostrandoImportadorTramos) {
            ImportadorTramos { tramos in
                store.plan.tramos = tramos
            }
        }
    }
}

// MARK: - Pantalla Cronograma

struct CronogramaScreen: View {
    @ObservedObject var store: PlanStore
    @AppStorage("horizonteCronograma") private var horizonteMinutos = 120

    var body: some View {
        List {
            Section {
                Stepper("Ver hasta el min \(horizonteMinutos)", value: $horizonteMinutos, in: 30...360, step: 15)
            } footer: {
                Text("El horizonte es solo para esta vista previa.")
            }

            Section("Por tiempo, en orden") {
                let avisos = store.plan.cronograma(duracionMaximaMinutos: horizonteMinutos)
                if avisos.isEmpty {
                    Text("Sin avisos por ahora. Agregalos en «Avisos por voz».")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(avisos) { aviso in
                        HStack(spacing: 10) {
                            InsigniaMinuto(minuto: aviso.minuto)
                            Text(aviso.texto)
                        }
                    }
                }
            }

            if !store.plan.avisosKmActivos.isEmpty {
                Section("Por kilómetro (con «Registrar carrera»)") {
                    ForEach(store.plan.avisosKmActivos) { aviso in
                        HStack(spacing: 10) {
                            Chip(texto: "km \(kmTexto(aviso.kilometro))")
                            VStack(alignment: .leading, spacing: 1) {
                                Text(aviso.texto)
                                if aviso.cadaKm != nil {
                                    Text(aviso.descripcion)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Cronograma")
    }
}

// MARK: - Pestaña Reloj

// Ya no es pestaña: se navega desde Perfil (decisión D5), así que la
// NavigationStack la pone el padre.
struct RelojTab: View {
    @ObservedObject var store: PlanStore
    @ObservedObject private var conectividad = Conectividad.compartida

    var body: some View {
        List {
                Section {
                    filaEstado("Reloj emparejado", ok: conectividad.relojEmparejado)
                    filaEstado("Maratonia instalada en el reloj", ok: conectividad.appInstaladaEnReloj)
                } header: {
                    Text("Estado")
                } footer: {
                    if !conectividad.appInstaladaEnReloj {
                        Text("Instalala desde la app Watch del iPhone → Maratonia → Instalar.")
                    }
                }

                Section {
                    Button {
                        conectividad.enviar(plan: store.plan, urlDePista: store.urlDePista)
                    } label: {
                        Label("Enviar al reloj", systemImage: "applewatch.radiowaves.left.and.right")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                    .disabled(store.plan.pistas.isEmpty
                              && store.plan.avisosFijos.isEmpty
                              && store.plan.avisosRepetidos.isEmpty
                              && store.plan.tramosActivos.isEmpty)

                    if conectividad.planEncolado {
                        Label("Plan encolado: llega al reloj apenas esté disponible.",
                              systemImage: "checkmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    if let error = conectividad.mensajeError {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("⚠️ La transferencia de música es lenta: hacela con el reloj en el cargador y con WiFi.")
                }

                Section("Música en el reloj") {
                    if store.plan.pistas.isEmpty {
                        Text("Sin pistas en el plan todavía.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.plan.pistas, id: \.self) { nombre in
                        HStack {
                            Text(nombreSinExtension(nombre))
                                .lineLimit(1)
                            Spacer()
                            if conectividad.archivosEnReloj.contains(nombre) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if let progreso = conectividad.progresoEnvios[nombre] {
                                ProgressView(value: progreso)
                                    .frame(width: 70)
                            } else {
                                Image(systemName: "circle.dashed")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.callout)
                    }
                }
        }
        .navigationTitle("Reloj")
    }

    private func filaEstado(_ texto: String, ok: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(ok ? Color.green : Color.orange)
            Text(texto)
            Spacer()
            Text(ok ? "Sí" : "No")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Pestaña Carreras

struct CarrerasTab: View {
    var body: some View {
        NavigationStack {
            CarrerasView()
        }
    }
}

// MARK: - Pestaña Perfil

struct PerfilTab: View {
    @ObservedObject var store: PlanStore
    @ObservedObject var almacen: AlmacenStore
    @ObservedObject var identidad: IdentidadStore
    @ObservedObject private var cuenta = CuentaStore.compartida
    @ObservedObject private var conectividad = Conectividad.compartida
    @Binding var mostrandoTutorial: Bool
    @State private var confirmandoRestaurar = false
    @State private var mostrandoOnboarding = false

    // Orden con intención: primero EL CORREDOR (objetivo, plan,
    // referencia, disponibilidad, carrera), después el hardware
    // (Watch), después la infraestructura (iCloud) y al final la ayuda.
    var body: some View {
        NavigationStack {
            List {
                seccionObjetivo

                SeccionCuentaMaratonia(identidad: identidad, cuentaCloud: cuenta)

                // Maratonia Coach: solo con backend configurado
                // (MaratoniaBackendURL en Info.plist) y sesión iniciada
                // — sin eso no aparece, cero botones muertos.
                if ServicioCoach.disponible && identidad.haySesion {
                    Section("Coach") {
                        NavigationLink {
                            CoachView(almacen: almacen)
                        } label: {
                            HStack(spacing: 10) {
                                IconoAjuste(sistema: "figure.run.circle.fill", color: .purple)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Maratonia Coach")
                                    Text("Explicaciones y ajustes sobre tu plan")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("Dispositivos") {
                    NavigationLink {
                        RelojTab(store: store)
                    } label: {
                        HStack(spacing: 10) {
                            IconoAjuste(sistema: "applewatch", color: .black)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Apple Watch")
                                // Estado REAL de WCSession — no texto
                                // genérico (isPaired/isWatchAppInstalled
                                // ya vivían en Conectividad).
                                Text(estadoDelReloj)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Circle()
                                .fill(conectividad.relojEmparejado && conectividad.appInstaladaEnReloj
                                      ? DV2.Semantico.exito : Color(.systemGray3))
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                        }
                    }
                }

                Section {
                    HStack(spacing: 10) {
                        IconoAjuste(sistema: "icloud.fill", color: .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(textoCuenta)
                            if let fecha = cuenta.ultimoRespaldo {
                                Text("Último respaldo: \(FormatoFecha.hora(fecha))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    Button {
                        confirmandoRestaurar = true
                    } label: {
                        Label("Restaurar plan desde iCloud", systemImage: "icloud.and.arrow.down")
                    }
                    .confirmationDialog(
                        "¿Restaurar desde iCloud?",
                        isPresented: $confirmandoRestaurar,
                        titleVisibility: .visible
                    ) {
                        Button("Reemplazar mi plan actual", role: .destructive) {
                            cuenta.restaurar { plan in
                                if let plan {
                                    store.plan = plan
                                }
                            }
                        }
                        Button("Cancelar", role: .cancel) {}
                    } message: {
                        Text("El plan de este teléfono se reemplaza por el último respaldo de iCloud. No se puede deshacer.")
                    }

                    if let mensaje = cuenta.mensaje {
                        Text(mensaje)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    NavigationLink {
                        CarrerasOcultasView()
                    } label: {
                        HStack(spacing: 10) {
                            IconoAjuste(sistema: "eye.slash", color: .orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Carreras ocultas")
                                Text("Restaurar carreras que ocultaste")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } header: {
                    Text("Datos y sincronización")
                } footer: {
                    Text("Tu plan se respalda de forma privada en tu iCloud, independiente de tu Cuenta Maratonia.")
                }

                Section("Ayuda") {
                    Button {
                        mostrandoTutorial = true
                    } label: {
                        HStack(spacing: 10) {
                            IconoAjuste(sistema: "questionmark", color: .gray)
                            Text("Cómo usar Maratonia")
                                .foregroundStyle(.primary)
                        }
                    }
                }

                Section {
                } footer: {
                    Text("Maratonia — hecha para correr. 🏃")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .navigationTitle("Perfil")
            .sheet(isPresented: $mostrandoOnboarding) {
                OnboardingDeportivo(almacen: almacen)
            }
        }
    }

    private var estadoDelReloj: String {
        if !conectividad.relojEmparejado {
            return String(localized: "Sin reloj emparejado")
        }
        if !conectividad.appInstaladaEnReloj {
            return String(localized: "Instalá Maratonia en el reloj")
        }
        return String(localized: "Conectado — enviar plan y música")
    }

    /// El corredor y su meta: objetivo, plan activo, referencia,
    /// disponibilidad y fecha, en filas propias (Fase F/build 40).
    /// Todo opcional: sin onboarding la sección invita, nada se rompe.
    @ViewBuilder
    private var seccionObjetivo: some View {
        let perfil = almacen.almacen.perfilDeportivo
        Section {
            if perfil.objetivo != nil {
                // El corredor en números, no en seis filas de etiquetas.
                ResumenCorredor(
                    objetivo: perfil.objetivo,
                    fecha: perfil.fechaObjetivo,
                    kmSemanales: perfil.actividad?.kmSemanales,
                    dias: perfil.diasElegidos?.count ?? perfil.diasPorSemana,
                    tiradaLarga: perfil.actividad?.tiradaLargaKm,
                    tienePlan: almacen.almacen.planActivo != nil,
                    motivoSinPlan: almacen.almacen.planActivo == nil
                        ? perfil.objetivoSinPlan : nil)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: DV2.Espacio.m, trailing: 0))
                    .listRowBackground(Color.clear)

                if let motivo = perfil.objetivoSinPlan, almacen.almacen.planActivo == nil,
                   let objetivo = perfil.objetivo {
                    AvisoSinPlan(
                        motivo: motivo, objetivo: objetivo,
                        puente: EvaluadorElegibilidad.objetivoPuente(para: objetivo)
                    ) { _ in mostrandoOnboarding = true }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: DV2.Espacio.m, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                if let plan = almacen.almacen.planActivo {
                    LabeledContent("Plan activo", value: plan.nombre)
                }
                // La referencia de ritmo, con su equivalencia detrás de
                // un toque: la fórmula de Riegel y su cita no tienen por
                // qué dominar la pantalla de todos los días.
                if let referencia = almacen.almacen.referenciaVigente {
                    LabeledContent("Tu ritmo", value: textoReferencia(referencia))
                    if let equivalencias = textoEquivalencias(referencia) {
                        Detalle(titulo: String(localized: "Cómo se calcula")) {
                            VStack(alignment: .leading, spacing: DV2.Espacio.xs) {
                                Text(equivalencias)
                                    .font(.footnote)
                                Text(origenReferencia(referencia))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                Text("Tiempos equivalentes estimados (fórmula de Riegel, \(Riegel.fuente)).")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                } else if perfil.testPendiente {
                    Label("Test 5K pendiente — está en Correr",
                          systemImage: "flag.checkered")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button("Cambiar objetivo") { mostrandoOnboarding = true }
            } else {
                Button {
                    mostrandoOnboarding = true
                } label: {
                    HStack(spacing: 10) {
                        IconoAjuste(sistema: "target", color: .red)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Elegí tu objetivo")
                                .foregroundStyle(.primary)
                            Text("2 minutos: meta, actividad actual y disponibilidad")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }

        Section("Tu perfil") {
            NavigationLink {
                DatosBasicosView(almacen: almacen)
            } label: {
                filaNavegacion(icono: "person.text.rectangle", color: .gray,
                               titulo: "Datos básicos",
                               subtitulo: subtituloDatosBasicos)
            }
            NavigationLink {
                HistorialAdaptacionesView(almacen: almacen)
            } label: {
                filaNavegacion(icono: "clock.arrow.circlepath", color: .brown,
                               titulo: "Ajustes del plan",
                               subtitulo: subtituloAdaptaciones)
            }
        }
    }

    private func nombreObjetivo(_ objetivo: ObjetivoDeportivo) -> String {
        TextosObjetivo.nombre(de: objetivo)
    }

    private func textoActividad(_ actividad: ActividadActual) -> String {
        var partes: [String] = []
        if let km = actividad.kmSemanales {
            partes.append(String(format: "%.0f km/sem", km))
        }
        if let dias = actividad.diasPorSemana {
            partes.append(String(format: "%.0f días", dias))
        }
        if let larga = actividad.tiradaLargaKm {
            partes.append(String(format: "larga %.0f km", larga))
        }
        return partes.isEmpty ? String(localized: "Sin cargar") : partes.joined(separator: " · ")
    }

    /// De dónde salió el dato importa: no es lo mismo un número que el
    /// corredor confirmó que uno que la app dedujo sola.
    private func origenActividad(_ origen: ActividadActual.Origen) -> String {
        switch origen {
        case .declarado: return String(localized: "Lo cargaste vos")
        case .detectadoSalud: return String(localized: "Detectado en Salud, sin confirmar")
        case .confirmado: return String(localized: "Detectado en Salud y confirmado por vos")
        case .corregido: return String(localized: "Detectado en Salud y corregido por vos")
        }
    }

    private var subtituloDatosBasicos: String {
        let datos = almacen.almacen.perfilDeportivo.datosBasicos ?? DatosBasicos()
        if let edad = datos.edad(a: DiaLocal(fecha: Date())) {
            return String(localized: "\(edad) años · opcional, solo contexto")
        }
        return String(localized: "Edad, sexo, altura y peso — todo opcional")
    }

    private var subtituloAdaptaciones: String {
        let total = almacen.almacen.historialAdaptaciones.count
        return total == 0
            ? String(localized: "Sin ajustes todavía")
            : String(localized: "\(total) cambios registrados")
    }

    private func textoReferencia(_ referencia: ReferenciaRendimiento) -> String {
        let distancia: String
        switch referencia.distanciaMetros {
        case 5000: distancia = "5K"
        case 10000: distancia = "10K"
        case 21097.5: distancia = "21K"
        case 42195: distancia = "42K"
        default: distancia = String(format: "%.1f km", referencia.distanciaMetros / 1000)
        }
        return "\(distancia) en \(formatearDuracion(TimeInterval(referencia.segundos)))"
    }

    /// "10K ≈ 52:07 · 21K ≈ 1:55:30" — solo distancias DISTINTAS a la
    /// de la referencia y dentro del rango donde Riegel tiene sentido.
    private func textoEquivalencias(_ referencia: ReferenciaRendimiento) -> String? {
        let objetivos: [(String, Double)] = [("5K", 5000), ("10K", 10000), ("21K", 21097.5)]
        let partes = objetivos.compactMap { nombre, metros -> String? in
            guard abs(metros - referencia.distanciaMetros) > 1,
                  let segundos = Riegel.tiempoEquivalente(segundos: referencia.segundos,
                                                          deMetros: referencia.distanciaMetros,
                                                          aMetros: metros) else { return nil }
            return "\(nombre) ≈ \(formatearDuracion(TimeInterval(segundos)))"
        }
        return partes.isEmpty ? nil : partes.joined(separator: " · ")
    }

    private func origenReferencia(_ referencia: ReferenciaRendimiento) -> String {
        let fecha = FormatoFecha.media(referencia.fecha)
        switch referencia.fuente {
        case .test5K: return String(localized: "Test 5K · \(fecha)")
        case .carreraReal: return String(localized: "Carrera real · \(fecha)")
        case .marcaManual: return String(localized: "Marca ingresada · \(fecha)")
        case .estimacionInicial: return String(localized: "Estimación inicial · \(fecha)")
        }
    }

    private var textoCuenta: String {
        switch cuenta.estado {
        case .verificando: return String(localized: "Verificando tu iCloud…")
        case .conectada: return String(localized: "Conectado con tu iCloud")
        case .sinSesion: return String(localized: "Sin sesión de iCloud (activala en Ajustes → tu nombre)")
        case .problema(let detalle): return detalle
        }
    }
}

#Preview {
    ContentView()
}
