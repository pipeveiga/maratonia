import SwiftUI
import UniformTypeIdentifiers

// La app iPhone en 4 pestañas: Plan (armar el entrenamiento), Reloj
// (enviar y estado), Carreras (historial con mapas) y Perfil (cuenta y
// ayuda). Cada parte del plan tiene su propia pantalla — nada de una
// sola lista infinita.

struct ContentView: View {
    @StateObject private var store = PlanStore()
    @State private var mostrandoTutorial = false

    /// El tutorial se abre solo la primera vez que se abre la app.
    @AppStorage("vioTutorial") private var vioTutorial = false

    var body: some View {
        TabView {
            PlanTab(store: store)
                .tabItem { Label("Plan", systemImage: "slider.horizontal.3") }
            RelojTab(store: store)
                .tabItem { Label("Reloj", systemImage: "applewatch") }
            CarrerasTab()
                .tabItem { Label("Carreras", systemImage: "map.fill") }
            PerfilTab(store: store, mostrandoTutorial: $mostrandoTutorial)
                .tabItem { Label("Perfil", systemImage: "person.crop.circle") }
        }
        .sheet(isPresented: $mostrandoTutorial) {
            TutorialView()
        }
        .onAppear {
            if !vioTutorial {
                vioTutorial = true
                mostrandoTutorial = true
            }
        }
    }
}

// MARK: - Pestaña Plan

struct PlanTab: View {
    @ObservedObject var store: PlanStore
    @AppStorage("horizonteCronograma") private var horizonteMinutos = 120

    var body: some View {
        NavigationStack {
            List {
                seccionCabecera

                Section("Armá tu entrenamiento") {
                    NavigationLink {
                        MusicaScreen(store: store)
                    } label: {
                        filaNavegacion(icono: "music.note", color: .blue,
                                       titulo: "Música", subtitulo: subtituloMusica)
                    }
                    NavigationLink {
                        AvisosScreen(store: store)
                    } label: {
                        filaNavegacion(icono: "bell.fill", color: .orange,
                                       titulo: "Avisos por voz", subtitulo: subtituloAvisos)
                    }
                    NavigationLink {
                        TramosScreen(store: store)
                    } label: {
                        filaNavegacion(icono: "speedometer", color: .green,
                                       titulo: "Tramos y ritmo", subtitulo: subtituloTramos)
                    }
                    NavigationLink {
                        CronogramaScreen(store: store)
                    } label: {
                        filaNavegacion(icono: "clock.fill", color: .teal,
                                       titulo: "Cronograma", subtitulo: "Todos los avisos, en orden")
                    }
                }
            }
            .navigationTitle("Maratonia")
        }
    }

    private var seccionCabecera: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Nombre del plan", text: $store.plan.nombre)
                    .font(.title3.bold())
                HStack(spacing: 0) {
                    estadistica("music.note", "\(store.plan.pistas.count)", "pistas")
                    estadistica("clock.fill", formatearDuracion(store.duracionTotal), "música")
                    estadistica("bell.fill", "\(store.plan.cronograma(duracionMaximaMinutos: horizonteMinutos).count)", "avisos")
                    estadistica("speedometer", "\(store.plan.tramosActivos.count)", "tramos")
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func estadistica(_ icono: String, _ valor: String, _ nombre: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icono)
                    .font(.caption2)
                    .foregroundStyle(.tint)
                Text(valor)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(nombre)
                .font(.caption2)
                .foregroundStyle(.secondary)
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

    private var subtituloMusica: String {
        store.plan.pistas.isEmpty
            ? "Importá tus MP3"
            : "\(store.plan.pistas.count) pistas · \(formatearDuracion(store.duracionTotal))"
    }

    private var subtituloAvisos: String {
        let total = store.plan.avisosFijos.count + store.plan.avisosRepetidos.count
        return total == 0 ? "«Tomá agua», «comé un gel»…" : "\(total) avisos configurados"
    }

    private var subtituloTramos: String {
        store.plan.tramosActivos.isEmpty
            ? "Elegí un plan sugerido o armá el tuyo"
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
                    Text("Todavía no hay pistas. Importá tus MP3 para armar la cola.")
                        .foregroundStyle(.secondary)
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
        }
        .navigationTitle("Avisos por voz")
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

            Section("Todos los avisos, en orden") {
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
        }
        .navigationTitle("Cronograma")
    }
}

// MARK: - Pestaña Reloj

struct RelojTab: View {
    @ObservedObject var store: PlanStore
    @ObservedObject private var conectividad = Conectividad.compartida

    var body: some View {
        NavigationStack {
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
                    }
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
    }

    private func filaEstado(_ texto: String, ok: Bool) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(ok ? Color.green : Color.orange)
                .frame(width: 10, height: 10)
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
    @ObservedObject private var cuenta = CuentaStore.compartida
    @Binding var mostrandoTutorial: Bool

    var body: some View {
        NavigationStack {
            List {
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
                        cuenta.restaurar { plan in
                            if let plan {
                                store.plan = plan
                            }
                        }
                    } label: {
                        Label("Restaurar plan desde iCloud", systemImage: "icloud.and.arrow.down")
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
