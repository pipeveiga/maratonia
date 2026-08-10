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
    @State private var experiencia: RespuestaExperiencia?
    @State private var diasPorSemana: Int?

    // Marca reciente (solo si experiencia == .marcaReciente).
    @State private var marcaDistanciaMetros: Double = 5000
    @State private var marcaHoras = 0
    @State private var marcaMinutos = 25
    @State private var marcaSegundos = 0
    @State private var marcaFecha = Date()

    // Fecha objetivo (opcional).
    @State private var tieneFechaObjetivo = false
    @State private var fechaObjetivo = Date().addingTimeInterval(90 * 24 * 3600)

    @State private var mostrandoPlanRecomendado = false

    private let totalPasos = 4

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
                    pasoExperiencia.tag(1)
                    pasoDisponibilidad.tag(2)
                    pasoFechaYResumen.tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut, value: paso)
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
            .navigationDestination(isPresented: $mostrandoPlanRecomendado) {
                if let base = planRecomendado {
                    PlanBaseDetalleView(almacen: almacen, base: base)
                }
            }
        }
        .interactiveDismissDisabled(false)
    }

    // MARK: Paso 1 — objetivo

    private var pasoObjetivo: some View {
        pantalla(titulo: "¿Qué querés lograr?",
                 subtitulo: "El plan se arma alrededor de esto.") {
            ForEach(ObjetivoDeportivo.allCases, id: \.self) { opcion in
                tarjetaOpcion(titulo: TextosObjetivo.nombre(de: opcion),
                              subtitulo: detalle(de: opcion),
                              icono: icono(de: opcion),
                              elegida: objetivo == opcion) {
                    objetivo = opcion
                    avanzar()
                }
            }
        }
    }

    // MARK: Paso 2 — experiencia

    private var pasoExperiencia: some View {
        pantalla(titulo: "¿Tenés una referencia de ritmo?",
                 subtitulo: "Sirve para que los ritmos del plan sean TUYOS, no genéricos.") {
            tarjetaOpcion(titulo: "Tengo una marca reciente",
                          subtitulo: "Una carrera o un esfuerzo medido de los últimos meses",
                          icono: "stopwatch.fill",
                          elegida: experiencia == .marcaReciente) {
                withAnimation { experiencia = .marcaReciente }
            }
            if experiencia == .marcaReciente {
                formularioMarca
            }
            tarjetaOpcion(titulo: "Prefiero hacer una prueba",
                          subtitulo: "Test de 5K: fuerte pero controlado, cuando quieras",
                          icono: "flag.checkered",
                          elegida: experiencia == .hacerTest) {
                experiencia = .hacerTest
                avanzar()
            }
            tarjetaOpcion(titulo: "Estoy empezando",
                          subtitulo: "Sin referencia — el plan arranca suave y aprende con vos",
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

    private var pasoDisponibilidad: some View {
        pantalla(titulo: "¿Cuántos días por semana podés correr?",
                 subtitulo: "Un plan honesto con tu semana real vale más que uno ambicioso que no cumplís.") {
            ForEach([2, 3, 4, 5], id: \.self) { dias in
                tarjetaOpcion(titulo: "\(dias) días",
                              subtitulo: subtituloDias(dias),
                              icono: "calendar",
                              elegida: diasPorSemana == dias) {
                    diasPorSemana = dias
                    avanzar()
                }
            }
        }
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
                                    diasPorSemana.map { "\($0) días por semana" } ?? "A definir")
                        filaResumen("flag.checkered", "Carrera",
                                    tieneFechaObjetivo
                                    ? FormatoFecha.media(fechaObjetivo)
                                    : "Sin fecha — se avanza por progresión")
                    }
                }
            }

            // Recomendación DETERMINÍSTICA del catálogo (por distancia
            // del objetivo). Sin plan compatible: se dice, no se inventa.
            if let base = planRecomendado {
                Button {
                    guardarPerfil()
                    mostrandoPlanRecomendado = true
                } label: {
                    EtiquetaBotonPrimarioV2(titulo: "Preparar mi plan",
                                            icono: "figure.run")
                }
                .buttonStyle(.plain)
                .disabled(objetivo == nil)
                Text("Para tu objetivo te recomendamos «\(base.nombre)»: \(base.semanasTotales) semanas, \(base.diasPorSemana) días por semana.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Guardar y cerrar") { terminar() }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .disabled(objetivo == nil)
            } else {
                Button {
                    terminar()
                } label: {
                    EtiquetaBotonPrimarioV2(titulo: "Listo", icono: "checkmark")
                }
                .buttonStyle(.plain)
                .disabled(objetivo == nil)
                if objetivo != nil {
                    Text("Todavía no hay un plan de esa distancia en el catálogo — está en camino. Tu perfil queda guardado y podés explorar los planes disponibles cuando quieras.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

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

    /// El plan del catálogo cuya distancia coincide con el objetivo.
    private var planRecomendado: PlanBase? {
        guard let objetivo else { return nil }
        let metros = TextosObjetivo.distanciaMetros(de: objetivo)
        return Catalogo.planesDisponibles().first {
            abs($0.distanciaObjetivoKm * 1000 - metros) <= 500
        }
    }

    // MARK: Cierre

    private var segundosDeMarca: Int {
        marcaHoras * 3600 + marcaMinutos * 60 + marcaSegundos
    }

    /// Guardar es idempotente: se llama tanto al cerrar como ANTES de
    /// saltar al plan recomendado — así el perfil no se pierde aunque
    /// el usuario adopte el plan y no vuelva a tocar "cerrar".
    private func guardarPerfil() {
        var perfil = almacen.almacen.perfilDeportivo
        perfil.objetivo = objetivo
        perfil.diasPorSemana = diasPorSemana
        perfil.fechaObjetivo = tieneFechaObjetivo ? DiaLocal(fecha: fechaObjetivo) : nil
        perfil.fechaOnboarding = Date()
        perfil.testPendiente = (experiencia == .hacerTest)

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

    private func avanzar() {
        withAnimation { paso = min(paso + 1, totalPasos - 1) }
    }

    // MARK: Piezas

    private func pantalla<Contenido: View>(titulo: String, subtitulo: String,
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

    private func detalle(de objetivo: ObjetivoDeportivo) -> String {
        switch objetivo {
        case .primeros5K: return "De cero a completar 5 km corriendo"
        case .mejorar5K: return "Ya los corrés — ahora, más rápido"
        case .diez: return "El siguiente escalón de distancia"
        case .mediaMaraton: return "21,1 km con una preparación seria"
        case .maraton: return "Los 42,2 km — el grande"
        }
    }

    private func icono(de objetivo: ObjetivoDeportivo) -> String {
        switch objetivo {
        case .primeros5K: return "figure.walk.motion"
        case .mejorar5K: return "bolt.fill"
        case .diez: return "figure.run"
        case .mediaMaraton: return "road.lanes"
        case .maraton: return "trophy.fill"
        }
    }

    private func subtituloDias(_ dias: Int) -> String {
        switch dias {
        case 2: return "Lo mínimo para progresar"
        case 3: return "El equilibrio clásico"
        case 4: return "Progreso sólido"
        default: return "Volumen alto — para semanas ordenadas"
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
