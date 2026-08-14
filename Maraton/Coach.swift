import SwiftUI
import FirebaseAuth

// MARATONIA COACH (§B8-B16). Arquitectura real:
// iPhone → Firebase Auth (ID token) → backend Maratonia (functions/)
// → OpenAI. La API key vive SOLO como secret del backend.
//
// Principios duros:
// - El MOTOR determinístico manda: el Coach explica, propone y analiza,
//   pero toda mutación pasa por ValidadorDeCoach + confirmación del
//   usuario. GPT jamás escribe al Watch ni toca historial/IDs.
// - DTO mínimo: nada de rutas GPS, coordenadas ni HealthKit crudo.
// - Respuestas con schema estricto (Codable espejo del backend);
//   respuesta inválida → no se aplica nada.
// - Fallback: sin backend, sin internet, sin sesión o con rate limit,
//   la app entera sigue funcionando — el Coach solo desaparece o
//   muestra su error, nunca bloquea el entrenamiento.
// - Gate de runtime: sin MaratoniaBackendURL en Info.plist el Coach NO
//   aparece (cero botones muertos), igual que Google Sign-In.

// MARK: - DTO de contexto (privacidad por diseño)

struct ContextoCoach: Codable {
    struct BaselineDTO: Codable {
        var distanciaMetros: Double
        var segundos: Int
    }
    struct ProgramadoDTO: Codable {
        var programadoID: String
        var dia: String
        var nombre: String
        var tipo: String
        var km: Double?
    }
    struct SesionDTO: Codable {
        var fecha: String
        var tipo: String
        var km: Double?
        var ritmoSegKm: Int?
        var cumplida: Bool
        /// Esfuerzo percibido, si el corredor lo respondió.
        var sensacion: String?
    }

    /// Resumen AGREGADO de una ventana. Números, nunca muestras.
    struct VentanaDTO: Codable {
        var dias: Int
        var km: Double
        var salidas: Int
        var tiradaMasLargaKm: Double
        var mayorPausaDias: Int
    }

    /// Qué detectó el motor determinístico. La IA no tiene que
    /// adivinarlo: se lo decimos, y solo elige entre alternativas.
    struct EventoDTO: Codable {
        var tipo: String
        var severidad: String
        var programadoID: String?
        var detalle: String?
    }

    var idioma: String
    var objetivo: String
    var fechaCarrera: String?
    var diasElegidos: [Int]
    var diasImposibles: [Int]
    var baseline: BaselineDTO?
    var semanaActual: Int?
    var semanasTotales: Int?
    var faseSemanaActual: String?
    var cumplimientoPorciento: Double?
    var kmUltimas4Semanas: Double?
    var ventanas: [VentanaDTO]
    var eventos: [EventoDTO]
    var proximosEntrenamientos: [ProgramadoDTO]
    var ultimasSesiones: [SesionDTO]

    /// Construye el DTO desde el dominio. TODO lo que sale está acá a
    /// la vista — auditable en un solo lugar. Jamás GPS, coordenadas,
    /// FC cruda ni muestras de HealthKit: solo agregados.
    @MainActor
    static func desde(_ almacen: AlmacenV2, hoy: DiaLocal,
                      historial: [SesionMetrica] = [],
                      eventos: [EventoEntrenamiento] = [],
                      ahora: Date = Date()) -> ContextoCoach {
        let perfil = almacen.perfilDeportivo
        let referencia = almacen.referenciaVigente
        // Para convertir a distancia los bloques por tiempo del plan.
        let baselineCoach = PerformanceBaseline(referencia: referencia)
        let proximos = almacen.todosLosProgramados
            .filter { $0.resolucion == .pendiente && !(($0.dia ?? hoy) < hoy) }
            .sorted { ($0.dia ?? hoy) < ($1.dia ?? hoy) }
            .prefix(14)
            .map { programado in
                ProgramadoDTO(programadoID: programado.id.uuidString.lowercased(),
                              dia: Self.texto(programado.dia ?? hoy),
                              nombre: programado.definicion.nombre,
                              tipo: programado.definicion.tipo.rawValue,
                              km: (programado.definicion.volumenKm(baseline: baselineCoach) * 10).rounded() / 10)
            }

        let indiceSemana = almacen.planActivo.flatMap { plan in
            plan.semanas.firstIndex { semana in
                semana.programados.contains { ($0.dia?.lunesDeLaSemana()) == hoy.lunesDeLaSemana() }
            }
        }
        let (hechos, total) = CalculoProgreso.cumplimiento(almacen: almacen, hoy: hoy)

        // Las ÚLTIMAS SESIONES salen del calendario del plan (no de
        // HealthKit): tipo, km previstos y si se cumplió. El ritmo se
        // envía redondeado a seg/km — un agregado, no una muestra.
        let ultimas = almacen.todosLosProgramados
            .filter { $0.resolucion != .pendiente && $0.dia != nil && ($0.dia ?? hoy) <= hoy }
            .sorted { ($0.dia ?? hoy) > ($1.dia ?? hoy) }
            .prefix(10)
            .map { programado -> SesionDTO in
                let registro = programado.sesionVinculadaID.flatMap { id in
                    almacen.sesiones.first { $0.id == id }
                }
                return SesionDTO(fecha: Self.texto(programado.dia ?? hoy),
                                 tipo: programado.definicion.tipo.rawValue,
                                 km: (programado.definicion.volumenKm(baseline: baselineCoach) * 10).rounded() / 10,
                                 ritmoSegKm: nil,
                                 cumplida: programado.resolucion == .cumplido,
                                 sensacion: registro?.sensacion?.rawValue)
            }

        return ContextoCoach(
            idioma: FormatoFecha.locale.language.languageCode?.identifier == "en" ? "en" : "es",
            objetivo: perfil.objetivo?.rawValue ?? "sin-objetivo",
            fechaCarrera: perfil.fechaObjetivo.map(Self.texto),
            diasElegidos: perfil.diasElegidos ?? [],
            diasImposibles: perfil.preferencias?.diasImposibles ?? [],
            baseline: referencia.map { BaselineDTO(distanciaMetros: $0.distanciaMetros,
                                                   segundos: $0.segundos) },
            semanaActual: indiceSemana.map { $0 + 1 },
            semanasTotales: almacen.planActivo?.semanas.count,
            faseSemanaActual: indiceSemana
                .flatMap { almacen.planActivo?.semanas[$0].reglas?.fase?.rawValue },
            cumplimientoPorciento: total > 0
                ? (Double(hechos) / Double(total) * 100).rounded() : nil,
            kmUltimas4Semanas: historial.isEmpty ? nil
                : (ResumenHistorial.ventana(historial, dias: 28, hoy: ahora).km * 10).rounded() / 10,
            ventanas: historial.isEmpty ? [] : ResumenHistorial.ventanasEstandar.map { dias in
                let v = ResumenHistorial.ventana(historial, dias: dias, hoy: ahora)
                return VentanaDTO(dias: dias, km: (v.km * 10).rounded() / 10,
                                  salidas: v.salidas,
                                  tiradaMasLargaKm: (v.tiradaMasLargaKm * 10).rounded() / 10,
                                  mayorPausaDias: v.mayorPausaDias)
            },
            eventos: eventos.map(Self.dto),
            proximosEntrenamientos: Array(proximos),
            ultimasSesiones: Array(ultimas))
    }

    static func dto(_ evento: EventoEntrenamiento) -> EventoDTO {
        let severidad: String
        switch evento.severidad {
        case .baja: severidad = "baja"
        case .media: severidad = "media"
        case .alta: severidad = "alta"
        }
        switch evento {
        case .sesionPerdida(let id):
            return EventoDTO(tipo: "sesion-perdida", severidad: severidad,
                             programadoID: id.uuidString.lowercased(), detalle: nil)
        case .sesionParcial(let id, let cumplimiento):
            return EventoDTO(tipo: "sesion-parcial", severidad: severidad,
                             programadoID: id.uuidString.lowercased(),
                             detalle: String(format: "%.0f%%", cumplimiento * 100))
        case .variasAusencias(let cantidad):
            return EventoDTO(tipo: "varias-ausencias", severidad: severidad,
                             programadoID: nil, detalle: "\(cantidad)")
        case .volumenSemanalBajo(let hecho, let previsto):
            return EventoDTO(tipo: "volumen-bajo", severidad: severidad, programadoID: nil,
                             detalle: String(localized: "\(Unidades.distancia(km: hecho, decimales: 0, conUnidad: false))/\(Unidades.distancia(km: previsto, decimales: 0))"))
        case .esfuerzoMuyAlto:
            return EventoDTO(tipo: "esfuerzo-muy-alto", severidad: severidad,
                             programadoID: nil, detalle: nil)
        case .molestiaReportada:
            // A propósito SIN detalle: una molestia declarada es una
            // bandera, no un dato clínico que se manda a un tercero.
            return EventoDTO(tipo: "molestia", severidad: severidad,
                             programadoID: nil, detalle: nil)
        case .fondoComprometido(let id):
            return EventoDTO(tipo: "fondo-comprometido", severidad: severidad,
                             programadoID: id.uuidString.lowercased(), detalle: nil)
        case .carreraLibreSignificativa(_, let km):
            return EventoDTO(tipo: "carrera-libre", severidad: severidad, programadoID: nil,
                             detalle: Unidades.distancia(km: km, decimales: 1))
        case .cambioDeDisponibilidad:
            return EventoDTO(tipo: "cambio-disponibilidad", severidad: severidad,
                             programadoID: nil, detalle: nil)
        case .pedidoDelUsuario:
            return EventoDTO(tipo: "pedido-usuario", severidad: severidad,
                             programadoID: nil, detalle: nil)
        case .cercaDeLaCarrera(let dias):
            return EventoDTO(tipo: "cerca-de-carrera", severidad: severidad,
                             programadoID: nil, detalle: "\(dias)")
        }
    }

    static func texto(_ dia: DiaLocal) -> String {
        String(format: "%04d-%02d-%02d", dia.anio, dia.mes, dia.dia)
    }

    static func dia(desde texto: String) -> DiaLocal? {
        let partes = texto.split(separator: "-").compactMap { Int($0) }
        guard partes.count == 3, (1...12).contains(partes[1]),
              (1...31).contains(partes[2]) else { return nil }
        return DiaLocal(anio: partes[0], mes: partes[1], dia: partes[2])
    }
}

// MARK: - Respuestas (espejo Codable de functions/schemas.js)

struct CoachWorkoutExplanation: Codable {
    var titulo: String
    var queEs: String
    var paraQueSirve: String
    var comoEncararlo: String
}

struct CoachWeekAdjustment: Codable {
    struct Cambio: Codable {
        /// "mantener" | "reprogramar" | "reducir" | "convertir" | "omitir"
        var tipo: String
        var programadoID: String
        var nuevoDia: String?
        /// Solo para "reducir": fracción de lo prescrito (0,5…0,95).
        var factor: Double?
    }
    var explicacion: String
    var cambios: [Cambio]

    /// Traducción ESTRICTA a CambioPropuesto: cualquier campo que no
    /// parsee descarta ESE cambio (nunca se interpreta texto libre).
    /// Un tipo desconocido se descarta entero — no se "adivina" a qué
    /// se parecía.
    var propuestas: [CambioPropuesto] {
        cambios.compactMap { cambio in
            guard let id = UUID(uuidString: cambio.programadoID) else { return nil }
            switch cambio.tipo {
            case "mantener":
                return .mantener(programadoID: id)
            case "omitir":
                return .omitir(programadoID: id)
            case "convertir":
                return .convertirEnFacil(programadoID: id)
            case "reducir":
                guard let factor = cambio.factor, factor > 0, factor < 1 else { return nil }
                return .reducir(programadoID: id, factor: factor)
            case "reprogramar":
                guard let texto = cambio.nuevoDia,
                      let dia = ContextoCoach.dia(desde: texto) else { return nil }
                return .reprogramar(programadoID: id, a: dia)
            default:
                return nil
            }
        }
    }

    /// Las que efectivamente cambian algo (para no mostrar una
    /// "propuesta" que es toda "mantener").
    var propuestasQueMutan: [CambioPropuesto] {
        propuestas.filter { $0.tipoDeAdaptacion != nil }
    }
}

struct CoachWorkoutAnalysis: Codable {
    var resumen: String
    var loBueno: String
    var aCuidar: String
}

struct CoachEstadoObjetivo: Codable {
    var veredicto: String
    var detalle: String
    var focoProximasSemanas: String
}

// MARK: - Servicio

@MainActor
final class ServicioCoach: ObservableObject {
    static let compartido = ServicioCoach()

    @Published var ocupado = false
    @Published var mensajeError: String?

    /// Gate de runtime: URL del backend en Info.plist + Firebase arriba.
    nonisolated static var urlBase: URL? {
        guard let texto = Bundle.main.object(forInfoDictionaryKey: "MaratoniaBackendURL") as? String,
              texto.hasPrefix("https://"), let url = URL(string: texto) else { return nil }
        return url
    }

    /// El ID token de Firebase del usuario actual, o nil. Lo usan el
    /// Coach y el borrado de cuenta: un solo lugar donde se pide.
    nonisolated static func tokenActual() async -> String? {
        guard let usuario = Auth.auth().currentUser else { return nil }
        return try? await withCheckedThrowingContinuation { continuacion in
            usuario.getIDToken { token, error in
                if let token { continuacion.resume(returning: token) }
                else { continuacion.resume(throwing: error ?? URLError(.userAuthenticationRequired)) }
            }
        }
    }

    nonisolated static var disponible: Bool {
        #if DEBUG
        // Mismo hook de QA que `pestanaInicial`: sin backend no hay
        // forma de ver la pantalla en el simulador. Solo enciende la
        // UI —las llamadas siguen fallando— y no existe en Release.
        if UserDefaults.standard.bool(forKey: "forzarCoach") { return true }
        #endif
        return urlBase != nil && ServicioAuth.disponible
    }

    private struct Peticion: Codable {
        var accion: String
        var requestID: String
        var contexto: ContextoCoach
        var detalle: String?
        var programadoID: String?
        /// La transacción FIRMADA POR APPLE. No es un "isPro": es el JWS
        /// que el backend verifica contra los certificados raíz de
        /// Apple antes de gastar un token. Que el cliente lo mande no
        /// autoriza nada — solo le da al servidor con qué verificar.
        var jws: String?
    }

    /// POST autenticado al backend, decodificando al tipo estricto.
    /// requestID nuevo por invocación (el backend cachea por si el
    /// usuario reintenta el MISMO envío tras un timeout — la UI reusa
    /// el ID en el retry).
    func pedir<Salida: Decodable>(_ tipo: Salida.Type, accion: String,
                                  contexto: ContextoCoach,
                                  detalle: String? = nil,
                                  programadoID: UUID? = nil,
                                  requestID: UUID = UUID()) async -> Salida? {
        guard let base = Self.urlBase,
              let usuario = Auth.auth().currentUser else {
            mensajeError = String(localized: "El Coach necesita sesión iniciada.")
            return nil
        }
        ocupado = true
        defer { ocupado = false }
        mensajeError = nil
        do {
            let token: String = try await withCheckedThrowingContinuation { continuacion in
                usuario.getIDToken { token, error in
                    if let token { continuacion.resume(returning: token) }
                    else { continuacion.resume(throwing: error ?? URLError(.userAuthenticationRequired)) }
                }
            }
            var solicitud = URLRequest(url: base.appendingPathComponent("coach"))
            solicitud.httpMethod = "POST"
            solicitud.timeoutInterval = 45
            solicitud.setValue("application/json", forHTTPHeaderField: "Content-Type")
            solicitud.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            let jws = await MainActor.run { TiendaPro.compartida.jwsVigente }
            solicitud.httpBody = try JSONEncoder().encode(Peticion(
                accion: accion, requestID: requestID.uuidString.lowercased(),
                contexto: contexto, detalle: detalle,
                programadoID: programadoID?.uuidString.lowercased(),
                jws: jws))
            let (datos, respuesta) = try await URLSession.shared.data(for: solicitud)
            guard let http = respuesta as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            switch http.statusCode {
            case 200:
                return try JSONDecoder().decode(Salida.self, from: datos)
            case 422:
                // El modelo se negó a responder. Reintentar no ayuda, y
                // no se le cobró la consulta al corredor.
                mensajeError = String(localized: "El Coach prefirió no responder eso. Probá preguntándolo de otra forma.")
            case 402:
                // El backend dijo que no es Pro. Es la palabra que vale:
                // el cliente puede creerse Pro y el servidor no.
                mensajeError = String(localized: "El Coach es parte de Maratonia Pro.")
            case 429:
                mensajeError = String(localized: "Llegaste al límite de consultas de hoy. El plan sigue igual — mañana el Coach vuelve.")
            case 503:
                mensajeError = String(localized: "El Coach está apagado por mantenimiento. Tu plan sigue funcionando normal.")
            default:
                mensajeError = String(localized: "El Coach no pudo responder. Tu plan no depende de él: seguí entrenando.")
            }
        } catch {
            mensajeError = String(localized: "Sin conexión con el Coach. Tu plan funciona igual sin internet.")
        }
        return nil
    }
}

// MARK: - UI

struct CoachView: View {
    @ObservedObject var almacen: AlmacenStore
    @ObservedObject private var servicio = ServicioCoach.compartido
    /// Las ventanas agregadas del DTO salen de acá. Solo lectura.
    @StateObject private var lector = LectorProgreso()

    @State private var explicacion: CoachWorkoutExplanation?
    @State private var ajuste: CoachWeekAdjustment?
    @State private var estado: CoachEstadoObjetivo?
    @State private var motivoCambio = ""
    @State private var aplicado = false

    private var hoy: DiaLocal { DiaLocal(fecha: Date()) }

    var body: some View {
        ScrollView {
            VStack(spacing: DV2.Espacio.l) {
                // Lo que se puede PEDIR, como tarjetas tocables: el
                // Coach era una lista de filas grises que se leía como
                // un menú de ajustes, no como algo con lo que hablar.
                accion(icono: "questionmark.circle.fill",
                       titulo: String(localized: "Explicame lo de hoy"),
                       detalle: proximoPendiente.map { $0.definicion.nombre }
                           ?? String(localized: "No tenés nada pendiente"),
                       habilitada: !servicio.ocupado && proximoPendiente != nil) {
                    Task { await explicarProximo() }
                }

                accion(icono: "chart.line.uptrend.xyaxis",
                       titulo: String(localized: "¿Cómo vengo?"),
                       detalle: String(localized: "Tu progreso contra el objetivo"),
                       habilitada: !servicio.ocupado) {
                    Task { await pedirEstado() }
                }

                TarjetaV2 {
                    VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                        EncabezadoSeccionV2(texto: "Reorganizar mi semana")
                        TextField("Contale qué pasó (ej.: no puedo correr el jueves)",
                                  text: $motivoCambio, axis: .vertical)
                            .font(.subheadline)
                            .lineLimit(1...4)
                        Button {
                            Task { await pedirReorganizacion() }
                        } label: {
                            EtiquetaBotonPrimarioV2(titulo: "Proponer cambios",
                                                    icono: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.plain)
                        .opacity(puedeReorganizar ? 1 : 0.4)
                        .disabled(!puedeReorganizar)
                    }
                }

                if servicio.ocupado {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, DV2.Espacio.m)
                }
                if let mensaje = servicio.mensajeError {
                    TarjetaV2 {
                        Label(mensaje, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(DV2.Semantico.advertencia)
                    }
                }

                if let explicacion { tarjetaExplicacion(explicacion) }
                if let estado { tarjetaEstado(estado) }
                if let ajuste { seccionPropuesta(ajuste) }

                // El límite, al final y en una línea: es una aclaración,
                // no la portada. Antes era lo primero que se leía.
                Text("El Coach explica y propone. Tu plan lo decide el motor de Maratonia y lo confirmás vos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, DV2.Espacio.s)
            }
            .padding()
        }
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { lector.cargar(semanas: 8) }
    }

    private var puedeReorganizar: Bool {
        !servicio.ocupado && !motivoCambio.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Una cosa que el Coach puede hacer, como tarjeta tocable.
    private func accion(icono: String, titulo: String, detalle: String,
                        habilitada: Bool, hacer: @escaping () -> Void) -> some View {
        Button(action: hacer) {
            TarjetaV2 {
                HStack(spacing: DV2.Espacio.m) {
                    Image(systemName: icono)
                        .font(.title2)
                        .foregroundStyle(DV2.Marca.primario)
                        .frame(width: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(titulo)
                            .font(DV2.Tipo.tituloChico)
                            .foregroundStyle(.primary)
                        Text(detalle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .opacity(habilitada ? 1 : 0.45)
        .disabled(!habilitada)
    }

    private func tarjetaExplicacion(_ e: CoachWorkoutExplanation) -> some View {
        TarjetaV2 {
            VStack(alignment: .leading, spacing: DV2.Espacio.s) {
                EncabezadoSeccionV2(texto: "Tu próximo entrenamiento")
                Text(e.titulo)
                    .font(DV2.Tipo.titulo)
                    .foregroundStyle(DV2.Marca.profundo)
                Text(e.queEs).font(.subheadline)
                Text(e.paraQueSirve).font(.subheadline).foregroundStyle(.secondary)
                Divider()
                Label(e.comoEncararlo, systemImage: "lightbulb")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func tarjetaEstado(_ e: CoachEstadoObjetivo) -> some View {
        TarjetaV2 {
            VStack(alignment: .leading, spacing: DV2.Espacio.s) {
                EncabezadoSeccionV2(texto: "Cómo venís")
                Text(e.veredicto)
                    .font(DV2.Tipo.titulo)
                    .foregroundStyle(DV2.Marca.profundo)
                    .fixedSize(horizontal: false, vertical: true)
                Text(e.detalle).font(.subheadline)
                Divider()
                Label(e.focoProximasSemanas, systemImage: "target")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// ANTES vs PROPUESTO, con la validación del motor a la vista, y
    /// "Aplicar cambios" que ejecuta SOLO lo validado.
    @ViewBuilder
    private func seccionPropuesta(_ ajuste: CoachWeekAdjustment) -> some View {
        TarjetaV2 {
            VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                EncabezadoSeccionV2(texto: "Propuesta del Coach")
                Text(ajuste.explicacion)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: DV2.Espacio.s) {
                    ForEach(Array(ajuste.propuestas.enumerated()), id: \.offset) { _, cambio in
                        filaCambio(cambio)
                    }
                }
                if ajuste.propuestasQueMutan.isEmpty {
                    Label("El Coach no propone cambios: tu plan sigue según lo previsto.",
                          systemImage: "checkmark.seal")
                        .font(.footnote)
                        .foregroundStyle(DV2.Semantico.exito)
                }
                if aplicado {
                    Label("Cambios aplicados", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(DV2.Semantico.exito)
                } else if cambiosValidos(ajuste).isEmpty {
                    Label("El motor rechazó todos los cambios — no se aplica nada.",
                          systemImage: "xmark.octagon")
                        .font(.footnote)
                        .foregroundStyle(DV2.Semantico.advertencia)
                } else {
                    Button {
                        aplicar(ajuste)
                    } label: {
                        EtiquetaBotonPrimarioV2(titulo: "Aplicar cambios",
                                                icono: "checkmark")
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// ANTES → PROPUESTO, con el veredicto del motor a la vista. Un
    /// cambio rechazado se muestra igual (transparencia): el corredor
    /// ve qué pidió el Coach y por qué el motor lo frenó.
    private func filaCambio(_ cambio: CambioPropuesto) -> some View {
        let validacion = ValidadorDeCoach.validar(cambio, en: almacen.almacen, hoy: hoy)
        return VStack(alignment: .leading, spacing: 4) {
            switch cambio {
            case .mantener(let id):
                Label(String(localized: "Sin cambios: \(nombreDe(id))"),
                      systemImage: "equal.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .reprogramar(let id, let dia):
                Text("\(nombreDe(id)): \(textoDia(diaDe(id))) → \(textoDia(dia))")
                    .font(.subheadline)
            case .reducir(let id, let factor):
                Text("\(nombreDe(id)): acortar a \(Int((factor * 100).rounded())) %")
                    .font(.subheadline)
            case .convertirEnFacil(let id):
                Text("\(nombreDe(id)): pasar a rodaje fácil")
                    .font(.subheadline)
            case .omitir(let id):
                Text("Omitir: \(nombreDe(id))").font(.subheadline)
            }
            if !validacion.permitido {
                Label(validacion.motivo ?? String(localized: "Rechazado por el motor."),
                      systemImage: "xmark.octagon")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    // MARK: acciones

    private var proximoPendiente: EntrenamientoProgramado? {
        almacen.almacen.todosLosProgramados
            .filter { $0.resolucion == .pendiente && !(($0.dia ?? hoy) < hoy) }
            .sorted { ($0.dia ?? hoy) < ($1.dia ?? hoy) }
            .first
    }

    /// El contexto que viaja: dominio + ventanas agregadas de Salud +
    /// lo que el detector determinístico ya concluyó. Decirle a la IA
    /// qué pasó (en vez de que lo deduzca) es lo que la mantiene
    /// eligiendo entre alternativas válidas y no inventando.
    private func contexto(pedidoExplicito: Bool = false) -> ContextoCoach {
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoy, almacen: almacen.almacen, analisis: nil,
            kmSemanaActual: nil, pedidoExplicito: pedidoExplicito))
        return ContextoCoach.desde(almacen.almacen, hoy: hoy,
                                   historial: lector.sesiones, eventos: eventos)
    }

    private func explicarProximo() async {
        guard let proximo = proximoPendiente else { return }
        ajuste = nil; estado = nil
        explicacion = await servicio.pedir(CoachWorkoutExplanation.self,
                                           accion: "explicar", contexto: contexto(),
                                           detalle: proximo.definicion.nombre,
                                           programadoID: proximo.id)
    }

    private func pedirEstado() async {
        ajuste = nil; explicacion = nil
        estado = await servicio.pedir(CoachEstadoObjetivo.self,
                                      accion: "estado", contexto: contexto())
    }

    private func pedirReorganizacion() async {
        explicacion = nil; estado = nil; aplicado = false
        ajuste = await servicio.pedir(CoachWeekAdjustment.self,
                                      accion: "reorganizar",
                                      contexto: contexto(pedidoExplicito: true),
                                      detalle: motivoCambio)
    }

    private func cambiosValidos(_ ajuste: CoachWeekAdjustment) -> [CambioPropuesto] {
        ValidadorDeCoach.validas(ajuste.propuestasQueMutan, en: almacen.almacen, hoy: hoy)
    }

    /// La mutación REAL: motor manda, usuario confirmó, se aplica solo
    /// lo validado — y por el ÚNICO aplicador, que revalida y deja
    /// rastro en el historial de adaptaciones.
    private func aplicar(_ ajuste: CoachWeekAdjustment) {
        AplicadorAdaptacion.aplicar(cambiosValidos(ajuste), a: &almacen.almacen,
                                    hoy: hoy, origen: .coach,
                                    motivo: ajuste.explicacion)
        aplicado = true
    }

    // MARK: helpers de presentación

    private func nombreDe(_ id: UUID) -> String {
        almacen.almacen.todosLosProgramados.first { $0.id == id }?
            .definicion.nombre ?? String(localized: "Entrenamiento")
    }

    private func diaDe(_ id: UUID) -> DiaLocal? {
        almacen.almacen.todosLosProgramados.first { $0.id == id }?.dia
    }

    private func textoDia(_ dia: DiaLocal?) -> String {
        guard let dia, let fecha = dia.fecha() else { return "—" }
        return FormatoFecha.diaYMes(fecha)
    }
}
