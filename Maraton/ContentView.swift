import SwiftUI
import UniformTypeIdentifiers

// La app iPhone en 4 pestañas: Plan (armar el entrenamiento), Reloj
// (enviar y estado), Carreras (historial con mapas) y Perfil (cuenta y
// ayuda). Cada parte del plan tiene su propia pantalla — nada de una
// sola lista infinita.

enum Pestana: Hashable {
    case plan, correr, progreso, carreras, perfil

    #if DEBUG
    /// Pestaña inicial por argumento de lanzamiento. SOLO en DEBUG y
    /// solo para poder capturar cada pantalla desde el simulador: no hay
    /// forma de tocar la barra de pestañas por línea de comandos, y sin
    /// esto el sprint visual se verifica de memoria.
    /// Uso: `xcrun simctl launch <dev> <bundle> -pestanaInicial progreso`
    static var deArgumentos: Pestana? {
        switch UserDefaults.standard.string(forKey: "pestanaInicial") {
        case "plan": return .plan
        case "correr": return .correr
        case "progreso": return .progreso
        case "carreras": return .carreras
        case "perfil": return .perfil
        default: return nil
        }
    }
    #endif
}

/// EL PORTERO. Lo único que decide qué se ve primero.
///
/// Antes esta decisión estaba repartida entre tres `onAppear` y dos
/// `@AppStorage` ("vioBienvenida", "ofrecioOnboarding"): la app abría,
/// armaba un plan y recién después ofrecía cuenta. Ahora la cuenta va
/// primero porque la cuenta es la que sabe qué datos son tuyos.
struct ContentView: View {
    // Sin valor por defecto: los construye `init()` UNA vez y los
    // comparte. Un inicializador de propiedad acá sería código muerto
    // —el init lo pisa— y la próxima persona que lo lea va a creer que
    // hay dos formas de construirlos.
    @StateObject private var store: PlanStore
    @StateObject private var almacen: AlmacenStore
    @StateObject private var identidad: IdentidadStore
    @StateObject private var sesion: SesionApp
    @StateObject private var repositorio: RepositorioCuenta

    init() {
        let store = PlanStore()
        let almacen = AlmacenStore()
        let identidad = IdentidadStore()
        _store = StateObject(wrappedValue: store)
        _almacen = StateObject(wrappedValue: almacen)
        _identidad = StateObject(wrappedValue: identidad)
        _sesion = StateObject(wrappedValue: SesionApp(almacen: almacen, identidad: identidad))
        _repositorio = StateObject(wrappedValue: RepositorioCuenta(almacen: almacen))
    }

    var body: some View {
        Group {
            #if DEBUG
            // Catálogo de estados de suscripción. NO saltea la puerta de
            // entrada de la app: reemplaza la raíz por una pantalla que
            // no lee un solo dato del corredor. Compilado fuera de
            // Release, igual que `pestanaInicial`.
            if CatalogoEstadosPro.pedido {
                CatalogoEstadosPro()
            } else if CatalogoConversacionCoach.pedido {
                CatalogoConversacionCoach()
            } else {
                raiz
            }
            #else
            raiz
            #endif
        }
        .task {
            IdentidadStore.conectar(identidad, con: almacen)
            identidad.verificarRevocacionApple()
            // StoreKit escucha desde el arranque: una compra hecha en
            // otro dispositivo, una renovación o una revocación pueden
            // llegar en cualquier momento.
            TiendaPro.compartida.empezar()
            sesion.reevaluar()
            await sesion.restaurar(con: repositorio)
        }
        .onChange(of: identidad.haySesion) { _, hay in
            Task {
                if hay { await sesion.restaurar(con: repositorio) }
                else { await repositorio.limpiarParaLogout(); sesion.reevaluar() }
            }
        }
    }

    @ViewBuilder
    private var raiz: some View {
        Group {
            switch sesion.estado {
            case .resolviendo:
                DV2.Superficie.fondo.ignoresSafeArea()
            case .necesitaAuth:
                PuertaDeEntrada(identidad: identidad)
            case .restaurando:
                // El aviso solo si de verdad tarda: en el caso normal
                // la app aparece y listo.
                if sesion.restauracionLenta { RestaurandoView() }
                else { DV2.Superficie.fondo.ignoresSafeArea() }
            case .necesitaOnboarding:
                OnboardingDeportivo(almacen: almacen)
                    .interactiveDismissDisabled()
                    .onDisappear { sesion.onboardingCompletado() }
            case .lista:
                AppPrincipal(store: store, almacen: almacen, identidad: identidad,
                             repositorio: repositorio)
            }
        }
    }
}

struct AppPrincipal: View {
    @ObservedObject var store: PlanStore
    @ObservedObject var almacen: AlmacenStore
    @ObservedObject var identidad: IdentidadStore
    @ObservedObject var repositorio: RepositorioCuenta

    @State private var mostrandoTutorial = false

    /// Selección programática: EMPEZAR desde Plan te lleva a Correr,
    /// donde ya está el motor andando.
    #if DEBUG
    @State private var pestana: Pestana = Pestana.deArgumentos ?? .plan
    #else
    @State private var pestana: Pestana = .plan
    #endif

    /// El tutorial de audio queda disponible en Perfil → Ayuda. Ya no
    /// se abre solo: el arranque lo decide el portero.
    @State private var mostrandoOnboarding = false

    /// Observar la preferencia acá arriba es lo que hace que cambiar de
    /// unidades redibuje TODA la app de una vez. Sin esto, el selector
    /// de Perfil dejaría medias pantallas en la unidad vieja hasta el
    /// próximo refresco.
    @ObservedObject private var unidades = PreferenciaUnidades.compartida

    var body: some View {
        TabView(selection: $pestana) {
            PlanTab(store: store, almacen: almacen, pestana: $pestana,
                    identidad: identidad)
                .tabItem { Label("Plan", systemImage: "slider.horizontal.3") }
                .tag(Pestana.plan)
            CorrerTab(store: store, almacen: almacen)
                .tabItem { Label("Correr", systemImage: "figure.run") }
                .tag(Pestana.correr)
            // El Reloj dejó de ser pestaña (decisión D5): vive en
            // Perfil. Su lugar lo ocupa PROGRESO — correr, ver cómo
            // venís, correr de nuevo.
            ProgresoTab(almacen: almacen, irACorrer: { pestana = .correr })
                .tabItem { Label("Progreso", systemImage: "chart.bar.fill") }
                .tag(Pestana.progreso)
            CarrerasTab(pestana: $pestana)
                .tabItem { Label("Carreras", systemImage: "map.fill") }
                .tag(Pestana.carreras)
            PerfilTab(store: store, almacen: almacen, identidad: identidad,
                      repositorio: repositorio,
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
        .task {
            // El portero ya resolvió identidad y restauración: acá solo
            // queda cablear cuenta ↔ dominio y subir lo que cambie.
            RepositorioCuenta.conectar(repositorio, con: almacen)
        }
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
    /// Solo para saber si el Coach se puede ofrecer (necesita sesión).
    @ObservedObject var identidad: IdentidadStore
    @State private var confirmandoQuitarPlan = false

    #if DEBUG
    /// Abre el plan completo al arrancar. Igual que `pestanaInicial`:
    /// solo en DEBUG y solo para poder capturar la pantalla, porque el
    /// simulador no tiene forma de tocar un NavigationLink.
    /// Uso: `-abrirPlanCompleto 1`
    @State private var abrirPlanCompletoQA =
        UserDefaults.standard.bool(forKey: "abrirPlanCompleto")
    @State private var abrirRelojQA = UserDefaults.standard.bool(forKey: "abrirReloj")
    @State private var abrirCoachQA = UserDefaults.standard.bool(forKey: "abrirCoach")
    #endif

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
                seccionCoach
                seccionProximos
                seccionObjetivo

                Section("Plan de entrenamiento") {
                    if almacen.almacen.planActivo != nil {
                        NavigationLink {
                            CalendarioView(almacen: almacen, store: store, pestana: $pestana)
                        } label: {
                            filaNavegacion(icono: "calendar", color: .green,
                                           titulo: "Ver plan completo",
                                           subtitulo: subtituloCalendario)
                        }
                    }
                    NavigationLink {
                        CatalogoView(almacen: almacen)
                    } label: {
                        filaNavegacion(icono: "sparkles", color: .purple,
                                       titulo: "Explorar planes", subtitulo: subtituloCatalogo)
                    }
                }

                // Eliminar el plan es una acción propia, no una fila
                // perdida entre las de navegar: quien la busca la busca
                // por sí misma. El pie dice qué pasa de verdad — se
                // archiva, con su historial— sin esconderlo en el
                // diálogo de confirmación.
                if almacen.almacen.planActivo != nil {
                    Section {
                        Button(role: .destructive) {
                            confirmandoQuitarPlan = true
                        } label: {
                            Label("Eliminar plan", systemImage: "trash")
                        }
                        .confirmationDialog("¿Eliminar el plan actual?",
                                            isPresented: $confirmandoQuitarPlan,
                                            titleVisibility: .visible) {
                            Button("Eliminar plan", role: .destructive) {
                                almacen.almacen.abandonarPlan()
                            }
                            Button("Cancelar", role: .cancel) {}
                        } message: {
                            Text("Queda archivado con su historial. Tus carreras y tus marcas no se tocan.")
                        }
                    } footer: {
                        Text("Quedás sin plan: HOY queda libre y el reloj vuelve a Carrera Libre. Podés adoptar otro cuando quieras.")
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
            #if DEBUG
            // Igual que el plan completo: destino programático solo para
            // capturar la pantalla del reloj desde el simulador.
            .navigationDestination(isPresented: $abrirRelojQA) {
                RelojTab(store: store)
            }
            .navigationDestination(isPresented: $abrirCoachQA) {
                CoachView(almacen: almacen)
            }
            #endif
            #if DEBUG
            // Destino programático SOLO para poder capturar el plan
            // completo desde el simulador (no hay forma de tocar un
            // NavigationLink por línea de comandos). No existe en Release.
            .navigationDestination(isPresented: $abrirPlanCompletoQA) {
                CalendarioView(almacen: almacen, store: store, pestana: $pestana)
            }
            #endif
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
                                Text(Unidades.distancia(km: km))
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

    /// El Coach, en el inicio y no escondido en Perfil. Una tarjeta
    /// compacta con UNA pregunta concreta —la de hoy—, no un menú: el
    /// resto de lo que sabe hacer está adentro.
    ///
    /// Solo aparece con backend configurado y sesión iniciada: sin eso
    /// no existe, cero botones muertos.
    /// La sesión también se puede forzar en DEBUG: sin cuenta iniciada
    /// el Coach no aparece ni con el backend encendido, y para capturar
    /// la pantalla hacen falta las dos cosas.
    private var coachOfrecible: Bool {
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "forzarCoach") { return true }
        #endif
        return ServicioCoach.disponible && identidad.haySesion
    }

    @ViewBuilder
    private var seccionCoach: some View {
        if coachOfrecible {
            Section {
                NavigationLink {
                    CoachView(almacen: almacen)
                } label: {
                    HStack(spacing: DV2.Espacio.m) {
                        Image(systemName: "figure.run.circle.fill")
                            .font(.title2)
                            .foregroundStyle(DV2.Marca.primario)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Preguntale al Coach")
                                .font(.subheadline.weight(.semibold))
                            Text(almacen.almacen.entrenamientoDeHoy(hoy) != nil
                                 ? String(localized: "Por qué te toca esto hoy, o reorganizá tu semana")
                                 : String(localized: "Cómo venís para tu objetivo"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 2)
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
                let fase = FaseBase.disponible(almacen.almacen)
                Section {
                    AvisoSinPlan(
                        motivo: motivo, objetivo: objetivo,
                        puente: EvaluadorElegibilidad.objetivoPuente(para: objetivo),
                        alElegir: { accion in
                            // Empezar la fase base ADOPTA un plan real y
                            // conserva el objetivo deseado pendiente: no
                            // reemplaza el sueño, lo acerca.
                            if accion == .empezarFaseBase, let fase {
                                almacen.almacen.adoptarPlan(fase.planUsuario,
                                                            esFaseBase: true)
                            } else {
                                pestana = .perfil
                            }
                        },
                        faseBase: fase?.nombre)
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
                                if FaseBase.esFaseBase(almacen.almacen) {
                                    // Hay plan, pero NO es el de este
                                    // objetivo: la cuenta regresiva
                                    // sería una promesa falsa. Se dice
                                    // qué se está corriendo y qué no.
                                    Label("Estás en fase base — este plan no apunta a esa fecha",
                                          systemImage: "arrow.turn.up.right")
                                        .font(.caption)
                                        .foregroundStyle(DV2.Marca.primario)
                                } else if almacen.almacen.planActivo != nil,
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
    /// La fila del calendario habla del PLAN, no del día: lo de hoy ya
    /// está arriba, en la tarjeta protagonista. Acá lo útil es cuánto
    /// dura el bloque y en qué parte va.
    private var subtituloCalendario: String {
        guard let plan = almacen.almacen.planActivo, !plan.semanas.isEmpty else {
            return String(localized: "Todas las semanas del plan")
        }
        let total = plan.semanas.count
        guard let actual = plan.numeroDeSemana(hoy: hoy) else {
            return String(localized: "\(Plurales.semanas(total)) en total")
        }
        return String(localized: "Semana \(actual) de \(total)")
    }

    private var subtituloCatalogo: String {
        almacen.almacen.planActivo == nil
            ? String(localized: "De 5K a maratón, con tus días")
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
                        // El CTA del sistema de diseño: ya viene centrado
                        // y con la identidad. Con `.borderedProminent` el
                        // Label quedaba pegado a la izquierda dentro del
                        // ancho completo.
                        EtiquetaBotonPrimarioV2(
                            titulo: "Enviar al reloj",
                            icono: "applewatch.radiowaves.left.and.right")
                    }
                    .buttonStyle(.plain)
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
    @Binding var pestana: Pestana

    var body: some View {
        NavigationStack {
            CarrerasView(irACorrer: { pestana = .correr })
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
    var repositorio: RepositorioCuenta?
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

                SeccionPro()

                SeccionCuentaMaratonia(identidad: identidad, cuentaCloud: cuenta,
                                       repositorio: repositorio)

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
                let planActivo = almacen.almacen.planActivo
                ResumenCorredor(
                    objetivo: perfil.objetivo,
                    fecha: perfil.fechaObjetivo,
                    nombrePlan: planActivo?.nombre,
                    semanaActual: planActivo?.numeroDeSemana(hoy: DiaLocal(fecha: Date())),
                    semanasTotales: planActivo?.semanas.count,
                    kmSemanales: perfil.actividad?.kmSemanales,
                    dias: perfil.diasElegidos?.count ?? perfil.diasPorSemana,
                    tiradaLarga: perfil.actividad?.tiradaLargaKm,
                    tienePlan: planActivo != nil,
                    motivoSinPlan: planActivo == nil ? perfil.objetivoSinPlan : nil)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: DV2.Espacio.m, trailing: 0))
                    .listRowBackground(Color.clear)

                if let motivo = perfil.objetivoSinPlan, almacen.almacen.planActivo == nil,
                   let objetivo = perfil.objetivo {
                    let fase = FaseBase.disponible(almacen.almacen)
                    AvisoSinPlan(
                        motivo: motivo, objetivo: objetivo,
                        puente: EvaluadorElegibilidad.objetivoPuente(para: objetivo),
                        alElegir: { accion in
                            if accion == .empezarFaseBase, let fase {
                                almacen.almacen.adoptarPlan(fase.planUsuario,
                                                            esFaseBase: true)
                            } else {
                                mostrandoOnboarding = true
                            }
                        },
                        faseBase: fase?.nombre)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: DV2.Espacio.m, trailing: 0))
                    .listRowBackground(Color.clear)
                }

                // Cambiar de unidades NO regenera el plan ni reescribe
                // nada del dominio: el plan se guarda en km y se dibuja
                // en lo que el corredor elija.
                // Una fila, no tres cosas apiladas: la etiqueta y el
                // valor. El ejemplo de unidades ("km · min/km · kg")
                // vive en el onboarding, que es donde hay que ELEGIR;
                // acá el corredor ya sabe lo que eligió.
                Picker("Unidades", selection: Binding(
                    get: { PreferenciaUnidades.compartida.sistema },
                    set: { nuevo in
                        PreferenciaUnidades.compartida.elegir(nuevo)
                        almacen.almacen.perfil?.sistemaUnidades = nuevo
                    })) {
                    ForEach(SistemaUnidades.allCases, id: \.self) { opcion in
                        Text(opcion.nombre).tag(opcion)
                    }
                }
                .pickerStyle(.menu)
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
            partes.append(Unidades.volumenSemanal(km: km))
        }
        if let dias = actividad.diasPorSemana {
            partes.append(String(localized: "\(Int(dias.rounded())) días"))
        }
        if let larga = actividad.tiradaLargaKm {
            partes.append(String(localized: "larga \(Unidades.distancia(km: larga, decimales: 0))"))
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
        default: distancia = Unidades.distancia(km: referencia.distanciaMetros / 1000, decimales: 1)
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
