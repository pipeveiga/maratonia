import SwiftUI

// Onboarding deportivo (Fase F): corto y concreto — objetivo,
// experiencia, disponibilidad y fecha objetivo opcional. NO es un
// interrogatorio: 4 pasos, ninguno obligatorio de más. Es ADITIVO por
// diseño: guarda perfil y (si hay) una marca cruda; jamás toca el plan,
// las sesiones ni el audio de un usuario existente.

/// Cómo respondió el paso "experiencia". Solo la opción A produce una
/// marca; B deja el test pendiente (se corre como entrenamiento real).
private enum RespuestaExperiencia: Equatable {
    case marcaReciente
    case hacerTest
    case empezando
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

    /// Compone el objetivo y limpia lo que dejó de ser válido. Volver
    /// atrás y cambiar de objetivo no puede dejar pegada una cadencia
    /// que el arquetipo nuevo no soporta.
    private func elegirObjetivo(distancia: DistanciaObjetivo, intencion: IntencionObjetivo) {
        guard let nuevo = ObjetivoDeportivo.combinando(distancia, intencion) else { return }
        let cambio = objetivo != nuevo
        objetivo = nuevo
        if cambio, let actual = diasPorSemana, !cadenciasPosibles.contains(actual) {
            diasPorSemana = nil
            diasElegidos = []
        }
        avanzar()
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
            Text("Maratonia no diagnostica ni trata lesiones. Si marcás una molestia, el plan arranca más abajo y sube más despacio.")
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
                    Text("No tenemos historial suficiente en Salud — eso no dice nada de vos, solo que no lo sabemos. Contanos y listo.")
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
                          subtitulo: String(localized: "Sin referencia — el plan arranca suave y aprende con vos"),
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

    /// Cadencias ofrecidas: SOLO las que el arquetipo del objetivo
    /// elegido soporta de verdad. Antes se ofrecía 2-5 fijo y "Primeros
    /// 5K" (máximo 3 sesiones por semana) dejaba elegir 5 — dos días
    /// quedaban vacíos sin decirlo.
    private var cadenciasPosibles: [Int] {
        guard let objetivo,
              let arq = BibliotecaArquetipos.v1().first(where: { $0.objetivo == objetivo })
        else { return [2, 3, 4, 5] }
        return Array(arq.diasMinimos...max(arq.diasMinimos, arq.diasMaximos))
    }

    private var pasoDisponibilidad: some View {
        pantalla(titulo: "¿Qué días podés correr?",
                 subtitulo: "Un plan honesto con tu semana real vale más que uno ambicioso que no cumplís. Los entrenamientos caen SOLO en los días que marques.") {
            ForEach(cadenciasPosibles, id: \.self) { dias in
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
                            .foregroundStyle(diasElegidos.count == cantidad ? .secondary : .orange)
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

            // "PREPARAR MI PLAN" corre el MOTOR real (§39): guarda el
            // perfil, arma el pedido y muestra la propuesta (o el
            // motivo honesto por el que no hay plan).
            Button {
                prepararMiPlan()
            } label: {
                EtiquetaBotonPrimarioV2(titulo: "Preparar mi plan",
                                        icono: "figure.run")
            }
            .buttonStyle(.plain)
            .disabled(objetivo == nil)
            Button("Guardar y cerrar") { terminar() }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .disabled(objetivo == nil)

            if objetivo == nil {
                Text("Falta elegir el objetivo (paso 1).")
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
            return "\(nombreDistancia(marcaDistanciaMetros)) en \(formatearDuracion(TimeInterval(segundosDeMarca)))"
        case .hacerTest:
            return "Test 5K pendiente"
        case .empezando:
            return "Arrancando de cero"
        case nil:
            return "A definir"
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
        if diaPreferidoFondo != nil {
            perfil.preferencias = PreferenciasSemana(
                diaPreferidoFondo: diaPreferidoFondo,
                diasImposibles: perfil.preferencias?.diasImposibles)
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

    private func terminar() {
        guardarPerfil()
        dismiss()
    }

    /// El flujo real de §39: perfil guardado → pedido → motor →
    /// propuesta navegable. La referencia sale de lo recién guardado
    /// (la marca del paso 2 ya quedó registrada como referencia).
    private func prepararMiPlan(aceptaConservador: Bool = false) {
        guard let objetivo else { return }
        guardarPerfil()
        resultadoMotor = MotorPlanificacion.proponer(
            pedido(objetivo, aceptaConservador: aceptaConservador))
        mostrandoPropuesta = true
    }

    /// El pedido completo: objetivo, fecha, disponibilidad, referencia
    /// Y el contexto real del corredor (historial de Salud, actividad
    /// declarada, molestias, preferencias). Sin ese contexto el motor
    /// no puede evaluar elegibilidad ni ajustar el arranque.
    private func pedido(_ objetivo: ObjetivoDeportivo,
                        aceptaConservador: Bool) -> PedidoDePlan {
        PedidoDePlan(
            objetivo: objetivo,
            fechaObjetivo: tieneFechaObjetivo ? DiaLocal(fecha: fechaObjetivo) : nil,
            diasPorSemana: diasElegidos.isEmpty ? (diasPorSemana ?? 3) : diasElegidos.count,
            diasConcretos: diasElegidos.isEmpty ? nil : diasElegidos.sorted(),
            referencia: almacen.almacen.referenciaVigente,
            hoy: DiaLocal(fecha: Date()),
            historial: ResumenHistorial.ventana(lectorActividad.sesiones,
                                                dias: DeteccionActividad.diasVentana,
                                                hoy: Date()),
            actividad: actividadDelPerfil,
            molestias: molestias,
            preferencias: diaPreferidoFondo.map {
                PreferenciasSemana(diaPreferidoFondo: $0, diasImposibles: nil)
            },
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
                Text("5 km fuerte pero controlado. Tu tiempo se vuelve la referencia para personalizar los ritmos del plan.")
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
