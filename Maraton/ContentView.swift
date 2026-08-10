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
            PerfilTab(store: store, almacen: almacen, mostrandoTutorial: $mostrandoTutorial)
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
                .tag(Pestana.perfil)
        }
        .sheet(isPresented: $mostrandoTutorial) {
            TutorialView()
        }
        .sheet(isPresented: $mostrandoOnboarding) {
            OnboardingDeportivo(almacen: almacen)
        }
        .onAppear {
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

// MARK: - Pestaña Plan

struct PlanTab: View {
    @ObservedObject var store: PlanStore
    @ObservedObject var almacen: AlmacenStore
    @Binding var pestana: Pestana
    @AppStorage("horizonteCronograma") private var horizonteMinutos = 120

    // Edición EXPLÍCITA del nombre (lápiz → editar → Guardar/Cancelar):
    // el título tocable que abría el teclado de sorpresa era mala UX.
    @State private var editandoNombre = false
    @State private var nombreBorrador = ""
    @FocusState private var nombreEnfocado: Bool

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

                // El entrenamiento de HOY como acción principal de la
                // app, no como una fila más del calendario.
                if let hoy = almacen.almacen.entrenamientoDeHoy(DiaLocal(fecha: Date())) {
                    Section {
                        TarjetaEntrenamientoV2(programado: hoy) {
                            LanzadorSesion.iniciar(definicion: hoy.definicion,
                                                   programadoID: hoy.id,
                                                   store: store, almacen: almacen)
                            pestana = .correr
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                seccionCabecera

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
                }

                // La configuración de la SESIÓN (música, avisos, tramos
                // manuales) baja de jerarquía: una sola entrada. El
                // protagonismo del Plan es HOY + calendario + explorar.
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

    private func guardarNombre() {
        let limpio = nombreBorrador.trimmingCharacters(in: .whitespaces)
        if !limpio.isEmpty {
            store.plan.nombre = limpio
        }
        editandoNombre = false
        nombreEnfocado = false
    }

    /// Tarjeta hero con degradado de marca: el nombre del plan editable
    /// y sus números, como portada de la app.
    private var seccionCabecera: some View {
        Section {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("TU ENTRENAMIENTO", systemImage: "figure.run")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.85))
                    Spacer()
                    if !editandoNombre {
                        Button {
                            nombreBorrador = store.plan.nombre
                            editandoNombre = true
                            nombreEnfocado = true
                        } label: {
                            Image(systemName: "pencil.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .buttonStyle(.plain)
                    }
                }
                if editandoNombre {
                    TextField("Nombre del plan", text: $nombreBorrador)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                        .tint(.white)
                        .focused($nombreEnfocado)
                        .submitLabel(.done)
                        .onSubmit(guardarNombre)
                    HStack(spacing: 12) {
                        Button("Guardar", action: guardarNombre)
                            .buttonStyle(.borderedProminent)
                            .tint(.white.opacity(0.3))
                        Button("Cancelar") {
                            editandoNombre = false
                            nombreEnfocado = false
                        }
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                } else {
                    Text(store.plan.nombre)
                        .font(.title2.bold())
                        .foregroundStyle(.white)
                }
                HStack(spacing: 0) {
                    estadistica("music.note", "\(store.plan.pistas.count)", "pistas")
                    estadistica("clock.fill", formatearDuracion(store.duracionTotal), "música")
                    estadistica("bell.fill", "\(store.plan.cronograma(duracionMaximaMinutos: horizonteMinutos).count)", "avisos")
                    estadistica("speedometer", "\(store.plan.tramosActivos.count)", "tramos")
                }
            }
            .padding(18)
            .background(
                LinearGradient(colors: [Color.accentColor, .teal],
                               startPoint: .topLeading, endPoint: .bottomTrailing))
            .listRowInsets(EdgeInsets())
        }
    }

    private func estadistica(_ icono: String, _ valor: String, _ nombre: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icono)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.8))
                Text(valor)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(nombre)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.75))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func filaNavegacion(icono: String, color: Color, titulo: String, subtitulo: String) -> some View {
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

    private var subtituloCalendario: String {
        let hoy = DiaLocal(fecha: Date())
        if let deHoy = almacen.almacen.entrenamientoDeHoy(hoy) {
            return "Hoy: \(deHoy.definicion.nombre)"
        }
        let vencidos = almacen.almacen.vencidos(hoy).count
        if vencidos > 0 {
            return vencidos == 1 ? "1 entrenamiento vencido" : "\(vencidos) entrenamientos vencidos"
        }
        return "Hoy no hay entrenamiento programado"
    }

    private var subtituloCatalogo: String {
        almacen.almacen.planActivo == nil
            ? "Elegí un plan de 5K o 10K"
            : "Cambiar de plan (el actual se archiva)"
    }

    private var subtituloConfiguracion: String {
        var partes: [String] = []
        if !store.plan.pistas.isEmpty { partes.append("\(store.plan.pistas.count) pistas") }
        let avisos = store.plan.avisosFijos.count + store.plan.avisosRepetidos.count
            + store.plan.avisosKmActivos.count
        if avisos > 0 { partes.append("\(avisos) avisos") }
        if !store.plan.tramosActivos.isEmpty {
            partes.append("\(store.plan.tramosActivos.count) tramos")
        }
        return partes.isEmpty ? "Música, avisos por voz y tramos manuales"
                              : partes.joined(separator: " · ")
    }

}

// MARK: - Configuración del entrenamiento (legacy, un nivel abajo)

/// Las cuatro pantallas de siempre (música, avisos, tramos manuales,
/// cronograma), intactas pero un nivel abajo del Plan: la configuración
/// de la SESIÓN no compite con el calendario del entrenamiento.
struct ConfiguracionEntrenamientoScreen: View {
    @ObservedObject var store: PlanStore

    var body: some View {
        List {
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
                                   titulo: String, subtitulo: String) -> some View {
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
            ? "Importá tus MP3"
            : "\(store.plan.pistas.count) pistas · \(formatearDuracion(store.duracionTotal))"
    }

    private var subtituloAvisos: String {
        let total = store.plan.avisosFijos.count
            + store.plan.avisosRepetidos.count
            + store.plan.avisosKmActivos.count
        return total == 0 ? "«Tomá agua», «comé un gel»…" : "\(total) avisos configurados"
    }

    private var subtituloTramos: String {
        store.plan.tramosActivos.isEmpty
            ? "Armá bloques con objetivo de ritmo"
            : "\(store.plan.tramosActivos.count) tramos con objetivo"
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
        var texto = "Cada \(aviso.cadaMinutos) min, desde el min \(aviso.desdeMinuto)"
        if let hasta = aviso.hastaMinuto {
            texto += " hasta el min \(hasta)"
        } else {
            texto += ", sin límite"
        }
        return texto
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
    @ObservedObject private var cuenta = CuentaStore.compartida
    @Binding var mostrandoTutorial: Bool
    @State private var confirmandoRestaurar = false
    @State private var mostrandoOnboarding = false

    var body: some View {
        NavigationStack {
            List {
                seccionObjetivo

                Section {
                    HStack(spacing: 10) {
                        IconoAjuste(sistema: "person.crop.circle.fill", color: .blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(textoCuenta)
                            if let fecha = cuenta.ultimoRespaldo {
                                Text("Último respaldo: \(fecha.formatted(date: .omitted, time: .shortened))")
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
                } header: {
                    Text("Cuenta")
                } footer: {
                    Text("Tu plan se respalda automáticamente en tu iCloud privado — sin registro ni contraseñas. Al reinstalar o cambiar de teléfono: «Restaurar plan».")
                }

                Section("Apple Watch") {
                    NavigationLink {
                        RelojTab(store: store)
                    } label: {
                        HStack(spacing: 10) {
                            IconoAjuste(sistema: "applewatch", color: .black)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Reloj")
                                Text("Enviar plan y música, estado de la conexión")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
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

    /// El corredor y su meta: objetivo, disponibilidad, fecha, plan
    /// activo y referencia vigente (Fase F). Todo opcional: sin
    /// onboarding la sección invita a hacerlo, nada se rompe.
    @ViewBuilder
    private var seccionObjetivo: some View {
        let perfil = almacen.almacen.perfilDeportivo
        Section("Tu objetivo") {
            if let objetivo = perfil.objetivo {
                HStack(spacing: 10) {
                    IconoAjuste(sistema: "target", color: .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(nombreObjetivo(objetivo))
                        Text(subtituloPerfil(perfil))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let referencia = almacen.almacen.referenciaVigente {
                    HStack(spacing: 10) {
                        IconoAjuste(sistema: "stopwatch.fill", color: .teal)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Referencia: \(textoReferencia(referencia))")
                            Text(origenReferencia(referencia))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let equivalencias = textoEquivalencias(referencia) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(equivalencias)
                                .font(.footnote)
                            Text("Tiempos equivalentes estimados (fórmula de Riegel, \(Riegel.fuente)).")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if perfil.testPendiente {
                    Label("Test 5K pendiente — está en la pestaña Correr",
                          systemImage: "flag.checkered")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if let plan = almacen.almacen.planActivo {
                    HStack(spacing: 10) {
                        IconoAjuste(sistema: "calendar", color: .green)
                        Text("Plan activo: \(plan.nombre)")
                    }
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
                            Text("2 minutos: meta, experiencia y disponibilidad")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func nombreObjetivo(_ objetivo: ObjetivoDeportivo) -> String {
        switch objetivo {
        case .primeros5K: return "Mis primeros 5K"
        case .mejorar5K: return "Mejorar mis 5K"
        case .diez: return "Correr 10K"
        case .mediaMaraton: return "Media maratón"
        case .maraton: return "Maratón"
        }
    }

    private func subtituloPerfil(_ perfil: PerfilDeportivo) -> String {
        var partes: [String] = []
        if let dias = perfil.diasPorSemana { partes.append("\(dias) días/semana") }
        if let fecha = perfil.fechaObjetivo?.fecha() {
            partes.append("carrera el \(fecha.formatted(date: .abbreviated, time: .omitted))")
        }
        return partes.isEmpty ? "Sin más datos" : partes.joined(separator: " · ")
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
        let fecha = referencia.fecha.formatted(date: .abbreviated, time: .omitted)
        switch referencia.fuente {
        case .test5K: return "Test 5K · \(fecha)"
        case .carreraReal: return "Carrera real · \(fecha)"
        case .marcaManual: return "Marca ingresada · \(fecha)"
        case .estimacionInicial: return "Estimación inicial · \(fecha)"
        }
    }

    private var textoCuenta: String {
        switch cuenta.estado {
        case .verificando: return "Verificando tu iCloud…"
        case .conectada: return "Conectado con tu iCloud"
        case .sinSesion: return "Sin sesión de iCloud (activala en Ajustes → tu nombre)"
        case .problema(let detalle): return detalle
        }
    }
}

#Preview {
    ContentView()
}
