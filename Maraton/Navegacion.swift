import SwiftUI

/// La misma interpretación del calendario para el inicio y las pruebas.
/// Un día sin sesión no significa que el usuario no tenga un plan.
enum EstadoDeHoy: Equatable {
    case libre, sinEntrenamiento, pendiente(UUID), resuelto(UUID)

    static func desde(_ almacen: AlmacenV2, hoy: DiaLocal) -> EstadoDeHoy {
        if let pendiente = almacen.entrenamientoDeHoy(hoy) {
            return .pendiente(pendiente.id)
        }
        if let resuelto = almacen.programadoDelDia(hoy) {
            return .resuelto(resuelto.id)
        }
        return almacen.planActivo == nil ? .libre : .sinEntrenamiento
    }
}

struct HoyTab: View {
    @ObservedObject var store: PlanStore
    @ObservedObject var almacen: AlmacenStore
    @Binding var pestana: Pestana
    @ObservedObject var identidad: IdentidadStore
    @ObservedObject private var carrera = CarreraCelu.compartida
    @Environment(\.scenePhase) private var scenePhase
    @State private var fechaVisible = Date()

    private var hoy: DiaLocal { DiaLocal(fecha: fechaVisible) }
    private var estado: EstadoDeHoy { .desde(almacen.almacen, hoy: hoy) }

    var body: some View {
        if carrera.estado != .detenida {
            PantallaCarreraCelu(carrera: carrera)
        } else {
            NavigationStack {
                List {
                    if let problema = store.mensajeProblema {
                        Section {
                            Label(problema, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    entrenamientoDeHoy
                    Section {
                        TarjetaCarreraLibre(store: store, almacen: almacen,
                                           protagonista: almacen.almacen.entrenamientoDeHoy(hoy) == nil)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Section {
                        Button {
                            pestana = .plan
                        } label: {
                            Label(almacen.almacen.planActivo == nil
                                  ? String(localized: "Crear mi plan") : String(localized: "Ver mi plan"),
                                  systemImage: "calendar")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                        }
                        .accessibilityIdentifier("abrirMiPlan")
                    } footer: {
                        Text("En Plan encontrás tu calendario y los entrenamientos que vienen.")
                    }
                    Section("Antes de salir") {
                        NavigationLink {
                            ConfiguracionEntrenamientoScreen(store: store)
                        } label: {
                            Label("Audio y avisos", systemImage: "speaker.wave.2")
                        }
                        NavigationLink {
                            RelojTab(store: store)
                        } label: {
                            Label("Correr con Apple Watch", systemImage: "applewatch")
                        }
                    }
                }
                .navigationTitle("Hoy")
                .scrollDismissesKeyboard(.immediately)
                .onAppear { fechaVisible = Date() }
                .onChange(of: scenePhase) { _, fase in
                    if fase == .active { fechaVisible = Date() }
                }
            }
        }
    }

    @ViewBuilder
    private var entrenamientoDeHoy: some View {
        switch estado {
        case .pendiente(let id), .resuelto(let id):
            if let programado = almacen.almacen.todosLosProgramados.first(where: { $0.id == id }) {
                Section("Tu entrenamiento de hoy") {
                    if programado.resolucion == .pendiente {
                        TarjetaEntrenamientoV2(programado: programado) {
                            LanzadorSesion.iniciar(definicion: programado.definicion,
                                                   programadoID: id, store: store, almacen: almacen)
                        }
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                    NavigationLink {
                        DetalleEntrenamientoView(almacen: almacen, store: store,
                                                 pestana: $pestana, programadoID: id)
                    } label: {
                        if programado.resolucion == .pendiente {
                            Label("Ver detalles del entrenamiento", systemImage: "list.bullet.rectangle")
                        } else {
                            TarjetaEntrenamientoV2(programado: programado)
                        }
                    }
                    .accessibilityIdentifier("detalleDeHoy")
                }
            }
        case .sinEntrenamiento:
            Section {
                Label("Hoy no hay entrenamiento programado", systemImage: "calendar")
                    .font(.headline)
                    .padding(.vertical, 4)
            } footer: {
                Text("Podés consultar tu próxima sesión en Plan o registrar una carrera libre.")
            }
        case .libre:
            // La acción para quien recién llega es correr. La invitación
            // a armar un plan viene después y nunca tapa ese botón.
            EmptyView()
        }
    }
}

struct PlanTab: View {
    @ObservedObject var store: PlanStore
    @ObservedObject var almacen: AlmacenStore
    @Binding var pestana: Pestana
    @State private var mostrandoOnboarding = false

    var body: some View {
        NavigationStack {
            Group {
                if almacen.almacen.planActivo != nil {
                    // El calendario es la raíz: no hace falta buscarlo
                    // al final de una lista y abrir otra pantalla.
                    CalendarioView(almacen: almacen, store: store, pestana: $pestana,
                                   esRaiz: true)
                } else {
                    ScrollView {
                        VStack(spacing: DV2.Espacio.l) {
                            EstadoVacio(
                                icono: "calendar",
                                titulo: String(localized: "Tu plan empieza acá"),
                                detalle: String(localized: "Elegí tu objetivo, contanos cuánto corrés y qué días tenés disponibles. Vas a revisar el plan antes de confirmarlo."),
                                accion: (texto: String(localized: "Crear mi plan"),
                                         hacer: { mostrandoOnboarding = true }))
                                .accessibilityIdentifier("planVacio")
                            objetivoPendiente
                            NavigationLink {
                                CatalogoView(almacen: almacen)
                            } label: {
                                Label("Explorar planes", systemImage: "sparkles")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            Text("También podés correr sin plan desde Hoy.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding()
                    }
                    .navigationTitle("Plan")
                }
            }
            .sheet(isPresented: $mostrandoOnboarding) {
                OnboardingDeportivo(almacen: almacen)
            }
        }
    }

    @ViewBuilder
    private var objetivoPendiente: some View {
        let perfil = almacen.almacen.perfilDeportivo
        if let objetivo = perfil.objetivo, let motivo = perfil.objetivoSinPlan {
            let fase = FaseBase.disponible(almacen.almacen)
            AvisoSinPlan(
                motivo: motivo, objetivo: objetivo,
                puente: EvaluadorElegibilidad.objetivoPuente(para: objetivo),
                alElegir: { accion in
                    if accion == .empezarFaseBase, let fase {
                        almacen.almacen.adoptarPlan(fase.planUsuario, esFaseBase: true)
                    } else {
                        mostrandoOnboarding = true
                    }
                },
                faseBase: fase?.nombre)
        } else if let objetivo = perfil.objetivo {
            Text("Tu objetivo: \(TextosObjetivo.nombre(de: objetivo))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

enum SeccionProgreso: String, CaseIterable {
    case resumen, carreras
}

/// Fixture aislado para pruebas de navegación. Solo puede activarse en
/// un simulador DEBUG; en Release y en teléfonos reales siempre es false.
/// No inicia sesión, no consulta Salud y no sincroniza con el reloj.
enum EscenarioNavegacionQA {
    static var activo: Bool {
        #if DEBUG && targetEnvironment(simulator)
        return UserDefaults.standard.bool(forKey: "pruebaNavegacion")
        #else
        return false
        #endif
    }

    static func almacen() -> AlmacenStore {
        let carpeta = FileManager.default.temporaryDirectory
            .appendingPathComponent("navegacion-qa-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
        let almacen = AlmacenStore(url: carpeta.appendingPathComponent("dominio.json"),
                                   urlLegacy: carpeta.appendingPathComponent("legacy.json"),
                                   conectadoAlReloj: false)
        #if DEBUG && targetEnvironment(simulator)
        if UserDefaults.standard.bool(forKey: "pruebaNavegacionConPlan") {
            let hoy = DiaLocal(fecha: Date())
            let programado = EntrenamientoProgramado(
                definicion: DefinicionEntrenamiento(
                    tipo: .facil, nombre: "Rodaje fácil",
                    segmentos: [Segmento(nombre: "Rodaje", distanciaKm: 5)]),
                dia: hoy)
            almacen.almacen.planActivo = PlanUsuario(
                nombre: "Mi primer 5K", fechaAdopcion: Date(),
                semanas: [SemanaPlan(numero: 1, programados: [programado])])
        }
        #endif
        return almacen
    }
}
