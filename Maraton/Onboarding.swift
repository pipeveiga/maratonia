import SwiftUI

// Onboarding deportivo (Fase F): corto y concreto — objetivo,
// experiencia, disponibilidad y fecha objetivo opcional. NO es un
// interrogatorio: 4 pasos, ninguno obligatorio de más. Es ADITIVO por
// diseño: guarda perfil y (si hay) una marca cruda; jamás toca el plan,
// las sesiones ni el audio de un usuario existente.

/// Cómo respondió el paso "experiencia". Solo la opción A produce una
/// marca; B deja el test pendiente (se corre como entrenamiento real).
enum RespuestaExperiencia: Equatable {
    case marcaReciente
    case hacerTest
    case empezando
}

/// Por dónde se entra al onboarding. Reabrirlo desde "Decinos qué días
/// podés correr" y aterrizar en el paso 1 obligaba a recorrer todo de
/// nuevo para contestar UNA pregunta: el punto de entrada es parte del
/// pedido, no algo que el corredor tenga que navegar.
enum PuntoDeEntradaOnboarding {
    case principio
    case disponibilidad

    var paso: Int {
        switch self {
        case .principio: return 0
        case .disponibilidad: return 3
        }
    }
}

/// Lo que el onboarding YA SABE cuando se reabre.
///
/// El onboarding no es de un solo uso: se abre desde Perfil, desde
/// "Explorar planes" y desde la bienvenida. Nacía con todo el `@State`
/// vacío, así que reabrirlo y tocar "Guardar y cerrar" escribía ese
/// vacío encima del perfil guardado — la disponibilidad declarada, los
/// días concretos, el día de fondo y el test pendiente desaparecían sin
/// que nadie los hubiera cambiado. Es la misma mentira que inventar una
/// disponibilidad, en la otra dirección: borrar la que el corredor sí
/// dio.
///
/// Función pura del perfil guardado (y de la referencia vigente) para
/// que la regla se pueda testear sin instanciar la vista.
struct EstadoInicialOnboarding: Equatable {
    var objetivo: ObjetivoDeportivo?
    var diasPorSemana: Int?
    var diasElegidos: Set<Int>
    var diaPreferidoFondo: Int?
    var molestias: EstadoMolestias
    var tieneFechaObjetivo: Bool
    var fechaObjetivo: Date

    var experiencia: RespuestaExperiencia?
    var marcaDistanciaMetros: Double
    var marcaSegundos: Int
    var marcaFecha: Date

    var origenActividad: ActividadActual.Origen
    var diasActuales: Int
    var kmSemanales: Double
    var tiradaLarga: Double
    var mesesRegular: Int
    var volviendoDePausa: Bool

    /// Las distancias que el selector de marca sabe representar. Una
    /// referencia fuera de esta lista NO se precarga: dejaría el picker
    /// segmentado sin nada seleccionado y el formulario mostraría una
    /// marca distinta de la guardada.
    static let distanciasDelSelector: Set<Double> = [5000, 10000, 21097.5, 42195]

    init(perfil: PerfilDeportivo,
         referencia: ReferenciaRendimiento?,
         hoy: Date = Date()) {
        objetivo = perfil.objetivo
        // La MISMA regla que `disponibilidadDeclarada`: mandan los días
        // concretos. Precargar `diasPorSemana` crudo dejaría la cadencia
        // y los chips contradiciéndose en pantalla.
        diasPorSemana = perfil.disponibilidadDeclarada
        diasElegidos = Set(perfil.diasElegidos ?? [])
        diaPreferidoFondo = perfil.preferencias?.diaPreferidoFondo
        molestias = perfil.molestias ?? .ninguna
        tieneFechaObjetivo = perfil.fechaObjetivo != nil
        fechaObjetivo = perfil.fechaObjetivo?.fecha()
            ?? hoy.addingTimeInterval(90 * 24 * 3600)

        // La marca solo se precarga si la escribió el corredor a mano:
        // una referencia de test o de carrera real tiene otra `fuente` y
        // reescribirla como `.marcaManual` la duplicaría en el historial.
        let marcaManual = referencia.flatMap {
            $0.fuente == .marcaManual
                && Self.distanciasDelSelector.contains($0.distanciaMetros) ? $0 : nil
        }
        if perfil.testPendiente {
            experiencia = .hacerTest
        } else if marcaManual != nil {
            experiencia = .marcaReciente
        } else if referencia == nil, perfil.fechaOnboarding != nil {
            // Completó el onboarding y no dejó ninguna referencia: la
            // única respuesta que produce ese estado es "estoy empezando".
            experiencia = .empezando
        } else {
            experiencia = nil
        }
        marcaDistanciaMetros = marcaManual?.distanciaMetros ?? 5000
        marcaSegundos = marcaManual?.segundos ?? (25 * 60)
        marcaFecha = marcaManual?.fecha ?? hoy

        let actividad = perfil.actividad
        origenActividad = actividad?.origen ?? .declarado
        // Cada valor entra al rango de SU stepper: uno fuera de rango
        // deja el control mudo y el corredor no puede corregirlo.
        diasActuales = Self.acotado(Int(actividad?.diasPorSemana?.rounded() ?? 0), 0, 14)
        kmSemanales = Self.acotado(actividad?.kmSemanales ?? 0, 0, 200)
        tiradaLarga = Self.acotado(actividad?.tiradaLargaKm ?? 0, 0, 60)
        mesesRegular = Self.tramoDeMeses(actividad?.mesesCorriendoRegular)
        volviendoDePausa = actividad?.volviendoDePausa ?? false
    }

    private static func acotado<T: Comparable>(_ valor: T, _ minimo: T, _ maximo: T) -> T {
        min(max(valor, minimo), maximo)
    }

    /// El `tag` del selector "hace cuánto corrés seguido" que contiene
    /// ese número de meses. Los tags son los extremos de cada tramo, así
    /// que un valor cualquiera hay que ubicarlo, no compararlo.
    static func tramoDeMeses(_ meses: Int?) -> Int {
        guard let meses, meses > 0 else { return 0 }
        switch meses {
        case ..<3: return 2      // 1-3 meses
        case ..<6: return 4      // 3-6 meses
        case ..<12: return 9     // 6-12 meses
        default: return 18       // más de un año
        }
    }
}

struct OnboardingDeportivo: View {
    @ObservedObject var almacen: AlmacenStore
    @Environment(\.dismiss) private var dismiss

    @State private var paso = 0
    @State private var objetivo: ObjetivoDeportivo?
    /// El objetivo se arma en dos preguntas cortas (§7) en vez de una
    /// lista de diez tarjetas.
    @State private var distancia: DistanciaObjetivo?
    @State private var intencion: IntencionObjetivo?
    @State private var experiencia: RespuestaExperiencia?
    @State private var diasPorSemana: Int?

    // ---- Actividad actual (paso 2). Lo que Salud detecta se propone;
    // lo que el corredor dice, manda.
    @StateObject private var lectorActividad = LectorProgreso()
    @State private var actividadDetectada: ActividadDetectada?
    @State private var corrigiendoActividad = false
    @State private var origenActividad: ActividadActual.Origen = .declarado
    @State private var diasActualesManual = 0
    @State private var kmSemanalesManual: Double = 0
    @State private var tiradaLargaManual: Double = 0
    @State private var mesesRegular = 0
    @State private var volviendoDePausa = false
    @State private var molestias: EstadoMolestias = .ninguna

    // ---- Preferencias de la semana (paso 4).
    @State private var diaPreferidoFondo: Int?
    /// Días concretos (1 = lunes … 7 = domingo). Sobrevive al ir y
    /// volver entre pasos (@State del flujo) y se persiste en el perfil.
    @State private var diasElegidos: Set<Int> = []

    // Marca reciente (solo si experiencia == .marcaReciente).
    @State private var marcaDistanciaMetros: Double = 5000
    @State private var marcaHoras = 0
    @State private var marcaMinutos = 25
    @State private var marcaSegundos = 0
    @State private var marcaFecha = Date()

    // Fecha objetivo (opcional).
    @State private var tieneFechaObjetivo = false
    @State private var fechaObjetivo = Date().addingTimeInterval(90 * 24 * 3600)

    /// El resultado del MOTOR de planes (§39): "Preparar mi plan" dejó
    /// de ser navegación — corre la planificación real.
    @State private var resultadoMotor: ResultadoPlanificacion?
    @State private var mostrandoPropuesta = false

    private let totalPasos = 5

    /// Se abre CON lo que el perfil ya sabe (`EstadoInicialOnboarding`).
    /// Reabrirlo es lo normal —desde Perfil, desde "Explorar planes"—, y
    /// un formulario en blanco encima de un perfil lleno no es un
    /// formulario nuevo: es la ruta más corta a borrar datos buenos.
    init(almacen: AlmacenStore, desde entrada: PuntoDeEntradaOnboarding = .principio) {
        _almacen = ObservedObject(wrappedValue: almacen)
        let inicial = EstadoInicialOnboarding(
            perfil: almacen.almacen.perfilDeportivo,
            referencia: almacen.almacen.referenciaVigente)

        _paso = State(initialValue: entrada.paso)
        _objetivo = State(initialValue: inicial.objetivo)
        _distancia = State(initialValue: inicial.objetivo?.distancia)
        _intencion = State(initialValue: inicial.objetivo?.intencion)
        _diasPorSemana = State(initialValue: inicial.diasPorSemana)
        _diasElegidos = State(initialValue: inicial.diasElegidos)
        _diaPreferidoFondo = State(initialValue: inicial.diaPreferidoFondo)
        _molestias = State(initialValue: inicial.molestias)
        _tieneFechaObjetivo = State(initialValue: inicial.tieneFechaObjetivo)
        _fechaObjetivo = State(initialValue: inicial.fechaObjetivo)

        _experiencia = State(initialValue: inicial.experiencia)
        _marcaDistanciaMetros = State(initialValue: inicial.marcaDistanciaMetros)
        _marcaHoras = State(initialValue: inicial.marcaSegundos / 3600)
        _marcaMinutos = State(initialValue: (inicial.marcaSegundos % 3600) / 60)
        _marcaSegundos = State(initialValue: inicial.marcaSegundos % 60)
        _marcaFecha = State(initialValue: inicial.marcaFecha)

        _origenActividad = State(initialValue: inicial.origenActividad)
        _diasActualesManual = State(initialValue: inicial.diasActuales)
        _kmSemanalesManual = State(initialValue: inicial.kmSemanales)
        _tiradaLargaManual = State(initialValue: inicial.tiradaLarga)
        _mesesRegular = State(initialValue: inicial.mesesRegular)
        _volviendoDePausa = State(initialValue: inicial.volviendoDePausa)

        referenciaGuardada = almacen.almacen.referenciaVigente
    }

    /// La referencia que ya estaba guardada al abrir. Sirve para no
    /// mostrar "A definir" en el resumen cuando existe una referencia
    /// real que el formulario de marca no sabe representar (un test, una
    /// carrera): el dato existe, y decir que no sería falso.
    private let referenciaGuardada: ReferenciaRendimiento?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progreso SIEMPRE visible: barra + "Paso X de 4".
                VStack(spacing: 4) {
                    ProgressView(value: Double(paso + 1), total: Double(totalPasos))
                        .tint(.accentColor)
                    Text("Paso \(paso + 1) de \(totalPasos)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(.horizontal)
                .padding(.top, DV2.Espacio.s)

                TabView(selection: $paso) {
                    pasoObjetivo.tag(0)
                    pasoActividad.tag(1)
                    pasoExperiencia.tag(2)
                    pasoDisponibilidad.tag(3)
                    pasoFechaYResumen.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: paso)
                .onAppear { lectorActividad.cargar(semanas: 8) }
                .onChange(of: lectorActividad.sesiones) { _, sesiones in
                    // La detección se recalcula sola cuando Salud
                    // responde; si el corredor ya tocó algo, no se pisa.
                    guard !corrigiendoActividad, origenActividad == .declarado else { return }
                    actividadDetectada = DeteccionActividad.detectar(sesiones, hoy: Date())
                }
            }
            .navigationTitle("Tu objetivo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Atrás NO pierde respuestas: todo el estado vive en la
                // vista y cada paso muestra lo ya elegido.
                ToolbarItem(placement: .topBarLeading) {
                    if paso > 0 {
                        Button {
                            withAnimation { paso -= 1 }
                        } label: {
                            Label("Atrás", systemImage: "chevron.backward")
                        }
                        .accessibilityLabel("Volver al paso anterior")
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Ahora no") { dismiss() }
                }
            }
            .navigationDestination(isPresented: $mostrandoPropuesta) {
                if let resultado = resultadoMotor {
                    PropuestaPlanView(almacen: almacen, resultado: resultado) {
                        dismiss()
                    }
                }
            }
        }
        .interactiveDismissDisabled(false)
    }

    // MARK: Paso 1 — objetivo (DISTANCIA + INTENCIÓN, no diez tarjetas)

    private var pasoObjetivo: some View {
        pantalla(titulo: "¿Qué querés lograr?",
                 subtitulo: "Primero la distancia, después qué querés hacer con ella. El plan se arma alrededor de esto.") {
            EncabezadoSeccionV2(texto: "Distancia")
            ForEach(DistanciaObjetivo.allCases, id: \.self) { opcion in
                tarjetaOpcion(titulo: TextosObjetivo.nombre(de: opcion),
                              subtitulo: detalle(de: opcion),
                              icono: icono(de: opcion),
                              elegida: distancia == opcion) {
                    withAnimation {
                        if distancia != opcion { intencion = nil; objetivo = nil }
                        distancia = opcion
                    }
                }
            }

            if let distancia {
                EncabezadoSeccionV2(texto: "Tu meta con esa distancia")
                ForEach(distancia.intencionesPosibles, id: \.self) { opcion in
                    tarjetaOpcion(titulo: TextosObjetivo.nombre(de: opcion),
                                  subtitulo: TextosObjetivo.detalle(de: opcion),
                                  icono: icono(de: opcion),
                                  elegida: intencion == opcion) {
                        intencion = opcion
                        elegirObjetivo(distancia: distancia, intencion: opcion)
                    }
                }
            }
        }
    }

    /// Compone el objetivo y avanza. Lo que el corredor dijo sobre SU
    /// semana NO se toca: antes, cambiar de objetivo borraba en silencio
    /// una disponibilidad perfectamente válida solo porque el arquetipo
    /// nuevo no la soporta. La disponibilidad es un dato del corredor;
    /// que el objetivo no la banque es un veredicto que se explica
    /// (`CompatibilidadDisponibilidad`), no algo que se corrige por él.
    private func elegirObjetivo(distancia: DistanciaObjetivo, intencion: IntencionObjetivo) {
        guard let nuevo = ObjetivoDeportivo.combinando(distancia, intencion) else { return }
        objetivo = nuevo
        avanzar()
    }

    /// Cambiar de objetivo desde un aviso (la salida que ofrece el paso
    /// de disponibilidad cuando el elegido no entra con esos días).
    private func cambiarObjetivo(a nuevo: ObjetivoDeportivo) {
        withAnimation {
            objetivo = nuevo
            distancia = nuevo.distancia
            intencion = nuevo.intencion
        }
    }

    // MARK: Paso 2 — actividad actual (Salud manda cuando existe)

    private var pasoActividad: some View {
        pantalla(titulo: "¿Qué venís haciendo?",
                 subtitulo: "Es el dato que más cambia tu plan: define dónde arranca, no dónde termina.") {
            if let detectada = actividadDetectada, !corrigiendoActividad {
                tarjetaDetectada(detectada)
            } else {
                formularioActividad
            }

            EncabezadoSeccionV2(texto: "Molestias")
            ForEach(EstadoMolestias.allCases, id: \.self) { opcion in
                tarjetaOpcion(titulo: textoMolestia(opcion),
                              subtitulo: detalleMolestia(opcion),
                              icono: opcion == .ninguna ? "checkmark.seal" : "exclamationmark.triangle",
                              elegida: molestias == opcion) {
                    molestias = opcion
                }
            }
            // No promete que el arranque BAJE: si el plan ya entraba
            // bajo el techo, no hay nada que bajar y la promesa sería
            // falsa. Lo que sí garantiza el motor es el criterio.
            Text("Maratonia no diagnostica ni trata lesiones. Si marcás una molestia, el plan se vuelve más cauto con el arranque y con la progresión.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button { avanzar() } label: {
                EtiquetaBotonPrimarioV2(titulo: "Continuar", icono: "arrow.right")
            }
            .buttonStyle(.plain)
        }
    }

    /// La propuesta calculada desde Salud: confirmar o corregir. Nunca
    /// se guarda como verdad sin que el corredor la mire (§4).
    private func tarjetaDetectada(_ detectada: ActividadDetectada) -> some View {
        TarjetaV2 {
            VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                EncabezadoSeccionV2(texto: "Lo que vimos en Salud")
                Text("Unas \(String(format: "%.1f", detectada.diasPorSemana)) salidas por semana y ~\(String(format: "%.0f", detectada.kmSemanales)) km semanales, con una salida más larga de \(String(format: "%.1f", detectada.tiradaLargaKm)) km.")
                    .font(.subheadline)
                Text("Calculado sobre \(Plurales.carreras(detectada.salidasConsideradas)) de las últimas 6 semanas.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: DV2.Espacio.m) {
                    Button {
                        aplicarDetectada(detectada, origen: .confirmado)
                        avanzar()
                    } label: {
                        EtiquetaBotonPrimarioV2(titulo: "Sí, representa mi actividad",
                                                icono: "checkmark")
                    }
                    .buttonStyle(.plain)
                }
                Button("Corregir a mano") {
                    withAnimation {
                        aplicarDetectada(detectada, origen: .corregido)
                        corrigiendoActividad = true
                    }
                }
                .font(.footnote)
            }
        }
    }

    private var formularioActividad: some View {
        TarjetaV2 {
            VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                EncabezadoSeccionV2(texto: "Tu actividad de hoy")
                if actividadDetectada == nil {
                    Text("Sin historial en Salud. Contanos vos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Stepper("Salidas por semana: \(diasActualesManual)",
                        value: $diasActualesManual, in: 0...14)
                Stepper("Kilómetros por semana: \(Int(kmSemanalesManual))",
                        value: $kmSemanalesManual, in: 0...200, step: 5)
                Stepper("Salida más larga: \(String(format: "%.0f", tiradaLargaManual)) km",
                        value: $tiradaLargaManual, in: 0...60, step: 1)
                Picker("Hace cuánto corrés seguido", selection: $mesesRegular) {
                    Text("Recién empiezo").tag(0)
                    Text("1-3 meses").tag(2)
                    Text("3-6 meses").tag(4)
                    Text("6-12 meses").tag(9)
                    Text("Más de un año").tag(18)
                }
                Toggle("Vuelvo después de una pausa larga", isOn: $volviendoDePausa)
            }
        }
    }

    private func aplicarDetectada(_ detectada: ActividadDetectada,
                                  origen: ActividadActual.Origen) {
        diasActualesManual = Int(detectada.diasPorSemana.rounded())
        kmSemanalesManual = (detectada.kmSemanales / 5).rounded() * 5
        tiradaLargaManual = detectada.tiradaLargaKm.rounded()
        origenActividad = origen
    }

    private func textoMolestia(_ estado: EstadoMolestias) -> String {
        switch estado {
        case .ninguna: return String(localized: "Ninguna, estoy bien")
        case .molestiaLeve: return String(localized: "Una molestia leve")
        case .lesionReciente: return String(localized: "Una lesión reciente")
        case .enRecuperacion: return String(localized: "Estoy en recuperación")
        }
    }

    private func detalleMolestia(_ estado: EstadoMolestias) -> String {
        switch estado {
        case .ninguna: return String(localized: "Sin nada que me limite para correr")
        case .molestiaLeve: return String(localized: "Molesta, pero puedo correr")
        case .lesionReciente: return String(localized: "Me hizo dejar de correr en el último tiempo")
        case .enRecuperacion: return String(localized: "Estoy volviendo con indicación de alguien")
        }
    }

    // MARK: Paso 2 — experiencia

    private var pasoExperiencia: some View {
        pantalla(titulo: "¿Tenés una referencia de ritmo?",
                 subtitulo: "Sirve para que los ritmos del plan sean TUYOS, no genéricos.") {
            tarjetaOpcion(titulo: String(localized: "Tengo una marca reciente"),
                          subtitulo: String(localized: "Una carrera o un esfuerzo medido de los últimos meses"),
                          icono: "stopwatch.fill",
                          elegida: experiencia == .marcaReciente) {
                withAnimation { experiencia = .marcaReciente }
            }
            if experiencia == .marcaReciente {
                formularioMarca
            }
            tarjetaOpcion(titulo: String(localized: "Prefiero hacer una prueba"),
                          subtitulo: String(localized: "Test de 5K: fuerte pero controlado, cuando quieras"),
                          icono: "flag.checkered",
                          elegida: experiencia == .hacerTest) {
                experiencia = .hacerTest
                avanzar()
            }
            tarjetaOpcion(titulo: String(localized: "Estoy empezando"),
                          // "Arranca suave" no lo garantiza el motor:
                          // sin referencia lo que cambia son los
                          // ritmos, no el volumen de entrada.
                          subtitulo: String(localized: "Sin referencia — las sesiones van a ritmo libre hasta que tengas una marca"),
                          icono: "leaf.fill",
                          elegida: experiencia == .empezando) {
                experiencia = .empezando
                avanzar()
            }
        }
    }

    private var formularioMarca: some View {
        TarjetaV2 {
            VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                EncabezadoSeccionV2(texto: "Tu marca")
                Picker("Distancia", selection: $marcaDistanciaMetros) {
                    Text("5K").tag(5000.0)
                    Text("10K").tag(10000.0)
                    Text("21K").tag(21097.5)
                    Text("42K").tag(42195.0)
                }
                .pickerStyle(.segmented)

                HStack(spacing: 0) {
                    Picker("Horas", selection: $marcaHoras) {
                        ForEach(0..<7) { Text("\($0) h").tag($0) }
                    }
                    Picker("Minutos", selection: $marcaMinutos) {
                        ForEach(0..<60) { Text("\($0) min").tag($0) }
                    }
                    Picker("Segundos", selection: $marcaSegundos) {
                        ForEach(0..<60) { Text("\($0) s").tag($0) }
                    }
                }
                .pickerStyle(.wheel)
                .frame(height: 96)

                DatePicker("Fue el", selection: $marcaFecha,
                           in: ...Date(), displayedComponents: .date)

                Button {
                    avanzar()
                } label: {
                    EtiquetaBotonPrimarioV2(titulo: "Guardar marca", icono: "checkmark")
                }
                .buttonStyle(.plain)
                .disabled(segundosDeMarca == 0)
            }
        }
    }

    // MARK: Paso 3 — disponibilidad

    /// Lo que el corredor puede DECLARAR: el rango que la app soporta
    /// (hoy 2-6), igual para todos los objetivos.
    ///
    /// Antes esta lista se filtraba con `diasMinimos...diasMaximos` del
    /// arquetipo elegido, y por eso "Maratón" ofrecía solo 4 y 5: la
    /// pantalla preguntaba por la semana del corredor y aceptaba
    /// únicamente las respuestas que le convenían al plan. Quien corre 3
    /// días no podía decirlo — tenía que mentir para seguir. La
    /// compatibilidad se evalúa DESPUÉS, en `compatibilidad`.
    private var opcionesDeDisponibilidad: [Int] {
        DisponibilidadCorredor.opciones()
    }

    /// La disponibilidad que el corredor declaró, con la misma regla que
    /// usan `guardarPerfil` y el pedido al motor: mandan los días
    /// concretos si los marcó.
    private var disponibilidadDeclarada: Int? {
        diasElegidos.isEmpty ? diasPorSemana : diasElegidos.count
    }

    /// Cómo le queda al objetivo elegido la disponibilidad declarada.
    /// nil = todavía falta un dato de los dos; no hay nada que juzgar.
    private var compatibilidad: CompatibilidadDisponibilidad? {
        guard let objetivo, let dias = disponibilidadDeclarada else { return nil }
        return DisponibilidadCorredor.evaluar(dias: dias, objetivo: objetivo)
    }

    private var pasoDisponibilidad: some View {
        pantalla(titulo: "¿Qué días podés correr?",
                 subtitulo: "Decinos tu semana REAL, no la que te gustaría tener. Los entrenamientos caen SOLO en los días que marques.") {
            ForEach(opcionesDeDisponibilidad, id: \.self) { dias in
                tarjetaOpcion(titulo: String(localized: "\(dias) días"),
                              subtitulo: subtituloDias(dias),
                              icono: "calendar",
                              elegida: diasPorSemana == dias) {
                    diasPorSemana = dias
                    // Propuesta inicial repartida para esa cantidad; el
                    // corredor la ajusta tocando los días.
                    diasElegidos = Set(Self.diasSugeridos(para: dias))
                }
            }

            if let cantidad = disponibilidadDeclarada, let compatibilidad {
                avisoCompatibilidad(compatibilidad, disponibilidad: cantidad,
                                    ofreceFecha: false)
            }

            if let cantidad = diasPorSemana {
                TarjetaV2 {
                    VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                        EncabezadoSeccionV2(texto: "Tus días")
                        HStack(spacing: DV2.Espacio.s) {
                            ForEach(1...7, id: \.self) { dia in
                                chipDia(dia, tope: cantidad)
                            }
                        }
                        // El contador dice CUÁNTOS FALTAN contra la
                        // cadencia elegida: "7 días marcados" con la
                        // tarjeta "3 días" seleccionada era una
                        // contradicción en pantalla.
                        Text("\(diasElegidos.count) de \(cantidad) días marcados")
                            .font(.footnote)
                            // `Color.` explícito en las DOS ramas: sin
                            // eso, `.secondary` resuelve por la extensión
                            // de ShapeStyle donde Self == HierarchicalShapeStyle
                            // y `.orange` por la de Self == Color, y el
                            // ternario se queda sin un único tipo posible.
                            .foregroundStyle(diasElegidos.count == cantidad
                                             ? Color.secondary : Color.orange)
                    }
                }
                // Día de fondo: la app NO fuerza domingo (§9). Si el
                // corredor no elige, la larga queda donde la puso el
                // template — el último día de sus días elegidos.
                if diasElegidos.count == cantidad {
                    TarjetaV2 {
                        VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                            EncabezadoSeccionV2(texto: "Día de la tirada larga")
                            Text("Opcional. Es la sesión que más tiempo te lleva: elegí el día que te queda cómodo.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            HStack(spacing: DV2.Espacio.s) {
                                ForEach(diasElegidos.sorted(), id: \.self) { dia in
                                    chipFondo(dia)
                                }
                            }
                        }
                    }
                }

                Button {
                    avanzar()
                } label: {
                    EtiquetaBotonPrimarioV2(titulo: "Continuar", icono: "arrow.right")
                }
                .buttonStyle(.plain)
                .disabled(diasElegidos.count != cantidad)
                if diasElegidos.count < cantidad {
                    Text("Marcá \(cantidad) días, o elegí otra cantidad arriba.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    /// Lo que hay que decir sobre la disponibilidad YA declarada. Nunca
    /// la cambia ni la esconde: describe y ofrece salidas.
    ///
    /// `ofreceFecha` = estamos en el paso donde la fecha se puede tocar
    /// (el resumen). En el paso de disponibilidad la fecha todavía no se
    /// eligió, así que ofrecerla ahí sería mandar al corredor a un
    /// control que no existe.
    @ViewBuilder
    private func avisoCompatibilidad(_ compatibilidad: CompatibilidadDisponibilidad,
                                     disponibilidad: Int,
                                     ofreceFecha: Bool) -> some View {
        switch compatibilidad {
        case .sinPlan:
            EmptyView()

        case .alcanza(let sesiones, let variantePropia):
            if sesiones < disponibilidad || variantePropia {
                TarjetaV2 {
                    VStack(alignment: .leading, spacing: DV2.Espacio.s) {
                        EncabezadoSeccionV2(texto: "Cómo entra en tu semana")
                        if sesiones < disponibilidad {
                            // Tener MÁS días de los que el plan usa no es
                            // un problema — pero callarlo sí lo sería.
                            Text("Marcaste \(disponibilidad) días y este plan entrena \(sesiones): los otros \(disponibilidad - sesiones) quedan de descanso. Tu disponibilidad se guarda como la declaraste.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        if variantePropia {
                            Text("Hay una versión de este plan escrita para \(sesiones) días: es la que vas a recibir, no un recorte de la de más días.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

        case .noAlcanza(let minimo, let alternativas):
            TarjetaV2 {
                VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                    Label(String(localized: "Con \(disponibilidad) días, ese objetivo no entra"),
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("\(objetivo.map(TextosObjetivo.nombre(de:)) ?? String(localized: "Ese objetivo")) necesita al menos \(minimo) días por semana. Con menos, la tirada larga pasa a dominar la semana y el plan deja de ser ese plan: preferimos decírtelo antes que armarte algo que no se sostiene.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Tus \(disponibilidad) días quedan como los marcaste. Podés:")
                        .font(.footnote.weight(.semibold))

                    Button {
                        // Subir la disponibilidad es una decisión DEL
                        // corredor: el botón la propone, no la aplica sola.
                        diasPorSemana = minimo
                        diasElegidos = Set(Self.diasSugeridos(para: minimo))
                    } label: {
                        Label(String(localized: "Marcar \(minimo) días"),
                              systemImage: "calendar.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DV2.Espacio.s)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DV2.Marca.primario)

                    ForEach(alternativas, id: \.self) { alternativa in
                        Button {
                            cambiarObjetivo(a: alternativa)
                        } label: {
                            Label(String(localized: "Cambiar a \(TextosObjetivo.nombre(de: alternativa))"),
                                  systemImage: "flag.checkered")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DV2.Espacio.s)
                        }
                        .buttonStyle(.bordered)
                    }

                    Button {
                        withAnimation { paso = 0 }
                    } label: {
                        Label(String(localized: "Elegir otro objetivo"),
                              systemImage: "arrow.turn.up.left")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, DV2.Espacio.s)
                    }
                    .buttonStyle(.bordered)

                    if ofreceFecha {
                        Button {
                            withAnimation { tieneFechaObjetivo = true }
                        } label: {
                            Label(String(localized: "Revisar la fecha"),
                                  systemImage: "calendar")
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, DV2.Espacio.s)
                        }
                        .buttonStyle(.bordered)
                    } else {
                        Text("La fecha se elige en el paso siguiente: si movés el objetivo, el plan que entre puede necesitar otras semanas.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    /// Chip de un día (1 = lunes … 7 = domingo), con inicial localizada
    /// y nombre completo para VoiceOver.
    /// `tope` = la cadencia elegida arriba. Llegado al tope, los días
    /// sin marcar se apagan: marcar 7 con "3 días" seleccionado dejaba
    /// 4 días que el plan nunca iba a usar (el motor reparte tantas
    /// sesiones como tiene la semana del template, no una por día).
    /// Sacar días siempre se puede — es el camino para cambiar de idea.
    private func chipDia(_ dia: Int, tope: Int) -> some View {
        let elegido = diasElegidos.contains(dia)
        let bloqueado = !elegido && diasElegidos.count >= tope
        return Button {
            if elegido { diasElegidos.remove(dia) } else { diasElegidos.insert(dia) }
        } label: {
            Text(Self.inicialDia(dia))
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .background(elegido ? Color.accentColor
                                    : Color(.secondarySystemGroupedBackground),
                            in: Circle())
                .foregroundStyle(elegido ? Color.white
                                 : (bloqueado ? Color.secondary : Color.primary))
                .opacity(bloqueado ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .disabled(bloqueado)
        .accessibilityLabel(Self.nombreDia(dia))
        .accessibilityHint(bloqueado
                           ? Text("Ya marcaste \(tope) días. Sacá uno para elegir este.")
                           : Text(verbatim: ""))
        .accessibilityAddTraits(elegido ? .isSelected : [])
    }

    /// Chip para elegir el día de la tirada larga entre los días ya
    /// marcados. Tocar el elegido lo desmarca (volver a "sin
    /// preferencia" tiene que ser posible).
    private func chipFondo(_ dia: Int) -> some View {
        let elegido = diaPreferidoFondo == dia
        return Button {
            diaPreferidoFondo = elegido ? nil : dia
        } label: {
            Text(Self.inicialDia(dia))
                .font(.subheadline.weight(.bold))
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(elegido ? DV2.Marca.profundo
                                    : Color(.secondarySystemGroupedBackground),
                            in: Capsule())
                .foregroundStyle(elegido ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Self.nombreDia(dia))
        .accessibilityAddTraits(elegido ? .isSelected : [])
    }

    /// Reparto inicial por cantidad (el corredor lo ajusta): calidad y
    /// larga separadas, larga hacia el fin de semana — coincide con el
    /// orden de los templates.
    static func diasSugeridos(para cantidad: Int) -> [Int] {
        switch cantidad {
        case ..<2: return [2, 6]
        case 2: return [2, 6]              // martes y sábado
        case 3: return [2, 4, 6]           // martes, jueves, sábado
        case 4: return [2, 4, 6, 7]        // + domingo
        case 5: return [1, 2, 4, 6, 7]     // + lunes
        case 6: return [1, 2, 4, 5, 6, 7]  // descanso el miércoles
        default: return [1, 2, 3, 4, 5, 6, 7]
        }
    }

    /// Inicial del día en el idioma de la app (L M X J V S D en
    /// español), desde el calendario del sistema — sin hardcodear
    /// nombres. Nuestro 1 = lunes; los símbolos van domingo-primero.
    static func inicialDia(_ dia: Int) -> String {
        var calendario = Calendar.current
        calendario.locale = FormatoFecha.locale
        let simbolos = calendario.veryShortWeekdaySymbols
        return simbolos[dia % 7]   // 1(lun)→índice 1 … 7(dom)→0
    }

    static func nombreDia(_ dia: Int) -> String {
        var calendario = Calendar.current
        calendario.locale = FormatoFecha.locale
        return calendario.weekdaySymbols[dia % 7].capitalized
    }

    // MARK: Paso 4 — fecha objetivo + cierre

    /// Sin fecha declarada no hay nada que juzgar: el plan avanza por
    /// progresión y cualquier duración es válida.
    private var viabilidad: Viabilidad? {
        guard tieneFechaObjetivo else { return nil }
        return Viabilidad(objetivo: objetivo, fecha: DiaLocal(fecha: fechaObjetivo),
                          hoy: DiaLocal(fecha: Date()))
    }

    /// Qué le falta al motor para poder armar algo. nil = están los dos
    /// datos que no se pueden suponer: objetivo y disponibilidad.
    private var faltaParaElPlan: String? {
        if objetivo == nil { return String(localized: "Falta elegir el objetivo (paso 1).") }
        if disponibilidadDeclarada == nil {
            return String(localized: "Falta decir qué días podés correr (paso 4): el plan entero se arma con ese dato y no lo vamos a suponer.")
        }
        return nil
    }

    private var pasoFechaYResumen: some View {
        pantalla(titulo: "¿Corrés con fecha?",
                 subtitulo: "Si tenés una carrera marcada en el calendario, el plan apunta ahí. Si no, se avanza por progresión.") {
            TarjetaV2 {
                VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                    Toggle("Tengo una carrera objetivo", isOn: $tieneFechaObjetivo.animation())
                    if tieneFechaObjetivo {
                        DatePicker("Fecha", selection: $fechaObjetivo,
                                   in: Date()..., displayedComponents: .date)
                    }
                }
            }

            if objetivo != nil {
                TarjetaV2 {
                    VStack(alignment: .leading, spacing: DV2.Espacio.s) {
                        EncabezadoSeccionV2(texto: "Tu punto de partida")
                        filaResumen("target", "Objetivo",
                                    objetivo.map(TextosObjetivo.nombre(de:)) ?? "—")
                        filaResumen("stopwatch", "Referencia", textoReferencia)
                        filaResumen("calendar", "Disponibilidad",
                                    diasElegidos.isEmpty
                                    ? (diasPorSemana.map { "\($0) días por semana" } ?? "A definir")
                                    : diasElegidos.sorted().map(Self.inicialDia).joined(separator: " · "))
                        filaResumen("flag.checkered", "Carrera",
                                    tieneFechaObjetivo
                                    ? FormatoFecha.media(fechaObjetivo)
                                    : "Sin fecha — se avanza por progresión")
                    }
                }
            }

            // El veredicto sobre la disponibilidad viaja hasta el cierre:
            // acá conviven las TRES palancas (días, fecha y objetivo), así
            // que es donde el corredor puede elegir cuál mover. Solo lo
            // que NO entra: repetir en el resumen los días de descanso ya
            // explicados en el paso 3 sería ruido.
            if let compatibilidad, !compatibilidad.alcanzaLaDisponibilidad,
               let cantidad = disponibilidadDeclarada {
                avisoCompatibilidad(compatibilidad, disponibilidad: cantidad,
                                    ofreceFecha: true)
            }

            // La viabilidad de la fecha, EN VIVO y con las mismas
            // semanas mínimas que usa el motor. Antes el corredor se
            // enteraba recién al final, después de "Preparar mi plan".
            if let viabilidad {
                EstadoDeFecha(viabilidad: viabilidad)
            }

            // "PREPARAR MI PLAN" corre el MOTOR real (§39): guarda el
            // perfil, arma el pedido y muestra la propuesta (o el
            // motivo honesto por el que no hay plan).
            //
            // Cuando la fecha NO da, el botón principal deja de ser
            // "Preparar mi plan": ofrecer como acción primaria algo que
            // el motor va a rechazar es empujar al corredor a un
            // callejón que ya sabemos que no tiene salida.
            if let viabilidad, !viabilidad.alcanza {
                Button {
                    // Volver al selector de fecha es la salida real.
                    withAnimation { tieneFechaObjetivo = true }
                } label: {
                    EtiquetaBotonPrimarioV2(titulo: "Elegir otra fecha",
                                            icono: "calendar")
                }
                .buttonStyle(.plain)
                Button("Ver igual qué me propone") { prepararMiPlan() }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            } else {
                Button {
                    prepararMiPlan()
                } label: {
                    EtiquetaBotonPrimarioV2(titulo: "Preparar mi plan",
                                            icono: "figure.run")
                }
                .buttonStyle(.plain)
                .disabled(faltaParaElPlan != nil)
            }
            // Guardar y cerrar pide MENOS: un perfil a medio llenar es
            // un estado válido. Lo que no se puede es armar un plan con
            // datos que el corredor no dio.
            Button("Guardar y cerrar") { terminar() }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .disabled(objetivo == nil)

            if let falta = faltaParaElPlan {
                Text(falta)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func filaResumen(_ icono: String, _ titulo: String, _ valor: String) -> some View {
        HStack(spacing: DV2.Espacio.s) {
            Image(systemName: icono)
                .font(.footnote)
                .foregroundStyle(Color.accentColor)
                .frame(width: 18)
            Text(titulo)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer()
            Text(valor)
                .font(.footnote.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }

    private var textoReferencia: String {
        switch experiencia {
        case .marcaReciente:
            return String(localized: "\(nombreDistancia(marcaDistanciaMetros)) en \(formatearDuracion(TimeInterval(segundosDeMarca)))")
        case .hacerTest:
            return String(localized: "Test 5K pendiente")
        case .empezando:
            return String(localized: "Arrancando de cero")
        case nil:
            // Sin respuesta en este paso puede haber igual una referencia
            // guardada de antes (un test, una carrera). Existe y manda
            // sobre los ritmos: decir "A definir" sería negarla.
            guard let referencia = referenciaGuardada else { return String(localized: "A definir") }
            return String(localized: "\(nombreDistancia(referencia.distanciaMetros)) en \(formatearDuracion(TimeInterval(referencia.segundos)))")
        }
    }


    // MARK: Cierre

    private var segundosDeMarca: Int {
        marcaHoras * 3600 + marcaMinutos * 60 + marcaSegundos
    }

    /// Guardar es idempotente: se llama tanto al cerrar como ANTES de
    /// saltar al plan recomendado — así el perfil no se pierde aunque
    /// el usuario adopte el plan y no vuelva a tocar "cerrar".
    /// Lo que el corredor dice que viene haciendo, con su origen: si
    /// confirmó lo detectado en Salud, queda marcado como confirmado;
    /// si lo tocó, como corregido. El origen importa para saber cuánto
    /// confiar en el dato.
    private var actividadDelPerfil: ActividadActual? {
        let hayAlgo = diasActualesManual > 0 || kmSemanalesManual > 0
            || tiradaLargaManual > 0 || mesesRegular > 0 || volviendoDePausa
        guard hayAlgo else { return nil }
        return ActividadActual(
            origen: corrigiendoActividad ? .corregido : origenActividad,
            fecha: Date(),
            diasPorSemana: diasActualesManual > 0 ? Double(diasActualesManual) : nil,
            kmSemanales: kmSemanalesManual > 0 ? kmSemanalesManual : nil,
            minutosSemanales: nil,
            tiradaLargaKm: tiradaLargaManual > 0 ? tiradaLargaManual : nil,
            mesesCorriendoRegular: mesesRegular > 0 ? mesesRegular : nil,
            volviendoDePausa: volviendoDePausa,
            otrosDeportes: nil)
    }

    private func guardarPerfil() {
        var perfil = almacen.almacen.perfilDeportivo
        // Lo que el motor evaluó la última vez. Si algo de esto cambia,
        // su veredicto deja de hablar de este corredor.
        let objetivoPrevio = perfil.objetivo
        let fechaPrevia = perfil.fechaObjetivo
        let disponibilidadPrevia = perfil.disponibilidadDeclarada

        perfil.objetivo = objetivo
        perfil.diasPorSemana = diasElegidos.isEmpty ? diasPorSemana : diasElegidos.count
        perfil.diasElegidos = diasElegidos.isEmpty ? nil : diasElegidos.sorted()
        perfil.fechaObjetivo = tieneFechaObjetivo ? DiaLocal(fecha: fechaObjetivo) : nil
        perfil.fechaOnboarding = Date()
        perfil.testPendiente = (experiencia == .hacerTest)
        // Los datos básicos NO se piden acá a propósito: son contexto
        // opcional (§2) y el onboarding no es un interrogatorio. Se
        // editan en Perfil cuando el corredor quiera.
        if let actividad = actividadDelPerfil { perfil.actividad = actividad }
        perfil.molestias = molestias
        // Se escribe SIEMPRE, no solo cuando hay día de fondo: con el
        // `if`, desmarcar el día elegido (tocarlo de nuevo, que la
        // pantalla ofrece explícitamente) no borraba nada y el perfil se
        // quedaba con el anterior. Volver a "sin preferencia" tiene que
        // llegar al disco. Los días imposibles no se tocan acá: los
        // edita otra pantalla.
        perfil.preferencias = preferenciasDelPerfil(perfil.preferencias)

        // El veredicto del motor pertenece a los datos que lo
        // produjeron. Cambiar el objetivo, la fecha o la disponibilidad
        // y conservar el motivo dejaba la app explicando por qué NO hay
        // plan con un argumento sobre un pedido que ya no existe.
        if perfil.objetivo != objetivoPrevio
            || perfil.fechaObjetivo != fechaPrevia
            || perfil.disponibilidadDeclarada != disponibilidadPrevia {
            perfil.objetivoSinPlan = nil
        }

        var marca: ReferenciaRendimiento?
        if experiencia == .marcaReciente, segundosDeMarca > 0 {
            marca = ReferenciaRendimiento(fecha: marcaFecha,
                                          fuente: .marcaManual,
                                          distanciaMetros: marcaDistanciaMetros,
                                          segundos: segundosDeMarca)
        }
        almacen.guardarOnboarding(perfil, marca: marca)
    }

    /// El día de fondo elegido acá MÁS los días imposibles que el perfil
    /// ya traía (se editan en otra pantalla, así que el onboarding los
    /// transporta sin opinar). nil cuando no hay nada que declarar: "sin
    /// preferencias" es un estado real, no un registro vacío.
    private func preferenciasDelPerfil(_ guardadas: PreferenciasSemana?) -> PreferenciasSemana? {
        let imposibles = guardadas?.diasImposibles
        guard diaPreferidoFondo != nil || !(imposibles ?? []).isEmpty else { return nil }
        return PreferenciasSemana(diaPreferidoFondo: diaPreferidoFondo,
                                  diasImposibles: imposibles)
    }

    private func terminar() {
        guardarPerfil()
        dismiss()
    }

    /// El flujo real de §39: perfil guardado → pedido → motor →
    /// propuesta navegable. La referencia sale de lo recién guardado
    /// (la marca del paso 2 ya quedó registrada como referencia).
    private func prepararMiPlan(aceptaConservador: Bool = false) {
        // Sin objetivo o sin disponibilidad NO se arma nada: antes, si
        // el corredor se salteaba el paso 3, el pedido salía con 3 días
        // inventados y el plan quedaba calculado sobre una semana que
        // nadie declaró. La pantalla dice qué falta y lleva ahí.
        guard let objetivo else { return withAnimation { paso = 0 } }
        guard disponibilidadDeclarada != nil else {
            return withAnimation { paso = 3 }
        }
        guardarPerfil()
        let resultado = MotorPlanificacion.proponer(
            pedido(objetivo, aceptaConservador: aceptaConservador))
        // El motor ya dijo si se puede o no; el perfil tiene que
        // ENTERARSE. Antes esta respuesta moría en la pantalla: el
        // perfil quedaba con el objetivo y la fecha puestos, y la app
        // mostraba la cuenta regresiva de una carrera para la que no
        // existía ningún plan.
        almacen.almacen.perfil?.objetivoSinPlan = resultado.motivoSinPlan
        resultadoMotor = resultado
        mostrandoPropuesta = true
    }

    /// El pedido completo: objetivo, fecha, disponibilidad, referencia
    /// Y el contexto real del corredor (historial de Salud, actividad
    /// declarada, molestias, preferencias). Sin ese contexto el motor
    /// no puede evaluar elegibilidad ni ajustar el arranque.
    ///
    /// La disponibilidad ya viene garantizada por `prepararMiPlan`: acá
    /// no hay número de relleno posible.
    private func pedido(_ objetivo: ObjetivoDeportivo,
                        aceptaConservador: Bool) -> PedidoDePlan {
        PedidoDePlan(
            objetivo: objetivo,
            fechaObjetivo: tieneFechaObjetivo ? DiaLocal(fecha: fechaObjetivo) : nil,
            diasPorSemana: disponibilidadDeclarada ?? diasElegidos.count,
            diasConcretos: diasElegidos.isEmpty ? nil : diasElegidos.sorted(),
            referencia: almacen.almacen.referenciaVigente,
            hoy: DiaLocal(fecha: Date()),
            historial: ResumenHistorial.ventana(lectorActividad.sesiones,
                                                dias: DeteccionActividad.diasVentana,
                                                hoy: Date()),
            actividad: actividadDelPerfil,
            molestias: molestias,
            // Los días imposibles viajan con el pedido: el motor los usa
            // para no programar ahí (`MotorPlanificacion`), y mandarlos
            // en `nil` hacía que el plan armado en el onboarding cayera
            // en días que el corredor ya había declarado inviables.
            preferencias: preferenciasDelPerfil(almacen.almacen.perfilDeportivo.preferencias),
            aceptaConservador: aceptaConservador)
    }

    private func avanzar() {
        withAnimation { paso = min(paso + 1, totalPasos - 1) }
    }

    // MARK: Piezas

    /// titulo/subtitulo son LocalizedStringKey y NO String: con String,
    /// `Text(titulo)` no traduce nada — las claves estaban en el
    /// catálogo con su versión en inglés y jamás se usaban. Todos los
    /// llamadores pasan literales, así que el cambio es directo.
    private func pantalla<Contenido: View>(titulo: LocalizedStringKey,
                                           subtitulo: LocalizedStringKey,
                                           @ViewBuilder contenido: () -> Contenido) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                Text(titulo)
                    .font(.title2.bold())
                Text(subtitulo)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, DV2.Espacio.xs)
                contenido()
            }
            .padding()
        }
        .scrollDismissesKeyboard(.immediately)
    }

    private func tarjetaOpcion(titulo: String, subtitulo: String, icono: String,
                               elegida: Bool, accion: @escaping () -> Void) -> some View {
        Button(action: accion) {
            HStack(spacing: DV2.Espacio.m) {
                Image(systemName: icono)
                    .font(.title3)
                    .foregroundStyle(elegida ? Color.white : Color.accentColor)
                    .frame(width: 40, height: 40)
                    .background(elegida ? Color.accentColor : Color.accentColor.opacity(0.12),
                                in: RoundedRectangle(cornerRadius: DV2.radioBoton))
                VStack(alignment: .leading, spacing: 2) {
                    Text(titulo)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(subtitulo)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                if elegida {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(DV2.Espacio.m)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: DV2.radioTarjeta))
            .overlay(RoundedRectangle(cornerRadius: DV2.radioTarjeta)
                .strokeBorder(elegida ? Color.accentColor : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
    }

    // MARK: Textos

    private func detalle(de distancia: DistanciaObjetivo) -> String {
        switch distancia {
        case .cinco: return String(localized: "La puerta de entrada. Se puede desde cero.")
        case .diez: return String(localized: "El siguiente escalón de distancia.")
        case .media: return String(localized: "21,1 km con una preparación seria.")
        case .maraton: return String(localized: "Los 42,2 km — el grande.")
        }
    }

    private func icono(de distancia: DistanciaObjetivo) -> String {
        switch distancia {
        case .cinco: return "figure.walk.motion"
        case .diez: return "figure.run"
        case .media: return "road.lanes"
        case .maraton: return "trophy.fill"
        }
    }

    private func icono(de intencion: IntencionObjetivo) -> String {
        switch intencion {
        case .completar: return "flag.checkered"
        case .mejorar: return "bolt.fill"
        case .rendimiento: return "chart.line.uptrend.xyaxis"
        }
    }

    private func subtituloDias(_ dias: Int) -> String {
        switch dias {
        case 2: return String(localized: "Lo mínimo para progresar")
        case 3: return String(localized: "El equilibrio clásico")
        case 4: return String(localized: "Progreso sólido")
        case 5: return String(localized: "Volumen alto — para semanas ordenadas")
        default: return String(localized: "Carga de rendimiento — pide base real")
        }
    }

    private func nombreDistancia(_ metros: Double) -> String {
        switch metros {
        case 5000: return "5K"
        case 10000: return "10K"
        case 21097.5: return "21K"
        case 42195: return "42K"
        default: return String(format: "%.1f km", metros / 1000)
        }
    }
}

// MARK: - Tarjeta "Test 5K pendiente" (la ve la pestaña Correr)

/// El test elegido en el onboarding, listo para correr cuando el
/// corredor quiera — nunca lo fuerza.
struct TarjetaTest5K: View {
    var alEmpezar: () -> Void

    var body: some View {
        TarjetaV2 {
            VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                HStack {
                    Text("CUANDO QUIERAS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.teal)
                        .tracking(1)
                    Spacer()
                    ChipTipoV2(tipo: .testEvaluacion)
                }
                Text("Test 5K")
                    .font(.title3.weight(.bold))
                Text("5 km fuerte pero controlado. De ahí salen tus ritmos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button(action: alEmpezar) {
                    EtiquetaBotonPrimarioV2(titulo: "Hacer el test")
                }
                .buttonStyle(.plain)
            }
        }
    }
}
