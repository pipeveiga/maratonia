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
        /// "saturday". Canónico: que el modelo no tenga que deducir el
        /// día de la semana de una fecha ISO.
        var diaSemana: String
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

    /// EL ANCLA TEMPORAL. Sin esto el modelo recibe una lista de fechas
    /// ISO sin saber qué día es hoy, y no puede resolver "este sábado",
    /// "mañana" ni "la semana que viene". Fue la causa exacta de que el
    /// Coach dijera que no había sesión el sábado teniendo una.
    var hoy: String
    var diaSemanaHoy: String
    var zonaHoraria: String

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
                              diaSemana: (programado.dia ?? hoy).diaDeSemanaCanonico,
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
            hoy: Self.texto(hoy),
            diaSemanaHoy: hoy.diaDeSemanaCanonico,
            zonaHoraria: TimeZone.current.identifier,
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

struct CoachWeekAdjustment: Codable, Equatable {
    struct Cambio: Codable, Equatable {
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

/// EN QUÉ ESTADO QUEDÓ UNA PROPUESTA, como un solo valor.
///
/// Antes esto vivía como dos `if` independientes en la vista, y la
/// combinación "el Coach no propone cambios" (verde) + "el motor
/// rechazó todos los cambios" (naranja) aparecía junta: dos mensajes
/// que se contradicen, uno de ellos hablando de una validación que
/// nunca ocurrió porque no había nada que validar.
///
/// Los estados son excluyentes por construcción: la vista hace un
/// `switch` y muestra exactamente uno.
enum EstadoPropuesta: Equatable {
    /// A — el Coach no propuso ninguna operación que mute el plan.
    /// El motor no participó: no hay nada que rechazar.
    case sinCambiosNecesarios
    /// B — hay operaciones y el motor aceptó al menos una.
    /// `rechazadas` puede ser > 0: se aplican solo las válidas.
    case aplicable(validas: Int, rechazadas: Int)
    /// C — hubo operaciones, pero ninguna superó la validación.
    case rechazadaPorElMotor(propuestas: Int)
    /// Ya se aplicó.
    case aplicada(cantidad: Int)

    // D (error de backend/modelo) no es un estado de la propuesta: si el
    // Coach no respondió no hay propuesta. Se muestra aparte, y la
    // propuesta anterior se limpia antes de cada pedido para que un
    // error no conviva con un resultado viejo.

    /// La decisión, pura y sin UI: se puede testear sin motor ni vista.
    static func decidir(operaciones: Int, validas: Int, aplicado: Bool) -> EstadoPropuesta {
        if aplicado { return .aplicada(cantidad: validas) }
        guard operaciones > 0 else { return .sinCambiosNecesarios }
        guard validas > 0 else { return .rechazadaPorElMotor(propuestas: operaciones) }
        return .aplicable(validas: validas, rechazadas: operaciones - validas)
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
    /// El backend rechazó la consulta por estar fuera del dominio. Es
    /// distinto de un error: no hay nada que reintentar ni que arreglar.
    /// Existe porque la puerta del servidor es la que vale — la de la
    /// app ahorra el viaje, pero un request armado a mano se la saltea.
    @Published private(set) var rechazadaFueraDeDominio = false

    /// Gate de runtime: URL del backend en Info.plist + Firebase arriba.
    nonisolated static var urlBase: URL? {
        guard let texto = Bundle.main.object(forInfoDictionaryKey: "MaratoniaBackendURL") as? String,
              texto.hasPrefix("https://"), let url = URL(string: texto) else { return nil }
        return url
    }

    /// El ID token de Firebase del usuario actual, o nil. Lo usan el
    /// Coach y el borrado de cuenta: un solo lugar donde se pide.
    nonisolated static func tokenActual() async -> String? {
        // Sin Firebase configurado, `Auth.auth()` aborta el proceso.
        guard ServicioAuth.disponible,
              let usuario = Auth.auth().currentUser else { return nil }
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
        rechazadaFueraDeDominio = false
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
                // Dos motivos distintos con el mismo código: la puerta
                // de intención del backend, o el modelo negándose. El
                // primero no es un error y no se muestra como tal.
                if motivo(en: datos) == "fuera-de-dominio" {
                    rechazadaFueraDeDominio = true
                } else {
                    // Reintentar no ayuda, y no se le cobró la consulta.
                    mensajeError = String(localized: "El Coach prefirió no responder eso. Probá preguntándolo de otra forma.")
                }
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

    /// El campo `error` del cuerpo, si vino. Sin él, dos rechazos muy
    /// distintos se leerían igual.
    private func motivo(en datos: Data) -> String? {
        (try? JSONSerialization.jsonObject(with: datos) as? [String: Any])?["error"] as? String
    }
}

// MARK: - UI


// MARK: - Las tarjetas del flujo conversacional

/// Lo que se puede pedir cuando el corredor no sabe qué pedir. Cada una
/// enruta a la acción REAL que le corresponde: "¿cómo vengo?" no puede
/// terminar entrando por el endpoint de reprogramar solo porque se
/// escribió en el mismo campo.
enum SugerenciaCoach: String, Identifiable, CaseIterable {
    case reprogramar
    case explicar
    case estado

    var id: String { rawValue }

    var texto: String {
        switch self {
        case .reprogramar: return String(localized: "No puedo correr el sábado")
        case .explicar:    return String(localized: "¿Por qué me toca fondo?")
        case .estado:      return String(localized: "¿Cómo vengo para mi objetivo?")
        }
    }

    var icono: String {
        switch self {
        case .reprogramar: return "calendar"
        case .explicar:    return "questionmark.circle"
        case .estado:      return "chart.line.uptrend.xyaxis"
        }
    }
}

/// El "no" acotado. Es una respuesta completa: no se disculpa, no
/// intenta ayudar con otra cosa y no deja al corredor pensando que
/// preguntó mal algo del plan.
///
/// Antes eran tres párrafos —el límite, la aclaración de inyección y un
/// ejemplo— y el ejemplo era texto muerto: decía qué escribir en vez de
/// dejar escribirlo. Ahora es una línea y tres chips que SÍ hacen algo.
struct TarjetaFueraDeDominio: View {
    let motivo: MotivoFueraDeDominio
    var sugerir: ((SugerenciaCoach) -> Void)?

    var body: some View {
        TarjetaDecisionCoach(
            icono: "figure.run.circle",
            titulo: String(localized: "Solo puedo ayudarte con tu entrenamiento"),
            subtitulo: motivo == .inyeccion
                ? String(localized: "Tampoco puedo cambiar mis instrucciones")
                : nil,
            tono: .limite) {
            if let sugerir {
                EleccionRapidaCoach(
                    titulo: String(localized: "Probá con"),
                    elementos: SugerenciaCoach.allCases,
                    etiqueta: { $0.texto },
                    icono: { $0.icono },
                    elegir: sugerir)
            }
        }
    }
}

/// LA PREGUNTA. Cada opción ya pasó por el motor: tocar cualquiera de
/// estas no puede terminar en "rechazado".
///
/// Dos formas según lo que sobrevivió, y la diferencia no es estética:
///
/// - hay días → chips. "¿Cuándo sí podés correr?" se contesta con un
///   toque, y los días entran todos en dos renglones.
/// - no hay días → tarjetas de opción. Ahí cada salida tiene una
///   consecuencia distinta (perder la sesión no es lo mismo que
///   acortarla) y necesita su subtítulo.
struct TarjetaAclaracionCoach: View {
    let aclaracion: AclaracionCoach
    var elegir: (OpcionDeCoach) -> Void
    /// "Otro día": devuelve el foco al campo para escribirlo.
    var otroDia: (() -> Void)?

    /// Un chip de la fila de días. El caso `nil` es "Otro día".
    private struct Eleccion: Identifiable {
        var id: String
        var etiqueta: String
        var icono: String?
        var opcion: OpcionDeCoach?
    }

    private var dias: [OpcionDeCoach] {
        aclaracion.opciones.filter { $0.dia != nil }
    }

    /// Las que cambian algo de verdad. "Mantener" no es una alternativa
    /// deportiva: es el botón de salida, y va abajo y en secundario.
    private var accionables: [OpcionDeCoach] {
        aclaracion.opciones.filter { $0.dia == nil && $0.cambio.tipoDeAdaptacion != nil }
    }

    private var mantener: OpcionDeCoach? {
        aclaracion.opciones.first { if case .mantener = $0.cambio { return true }
                                    else { return false } }
    }

    private var elecciones: [Eleccion] {
        var salida = dias.map {
            Eleccion(id: $0.id, etiqueta: $0.etiquetaCorta(), icono: nil, opcion: $0)
        }
        if otroDia != nil {
            salida.append(Eleccion(id: "otro-dia",
                                   etiqueta: String(localized: "Otro día"),
                                   icono: "pencil", opcion: nil))
        }
        return salida
    }

    var body: some View {
        TarjetaDecisionCoach(
            icono: dias.isEmpty ? "calendar.badge.exclamationmark" : "calendar",
            titulo: aclaracion.titulo,
            subtitulo: aclaracion.subtitulo,
            detalle: aclaracion.detalle,
            tono: dias.isEmpty ? .atencion : .neutro) {

            VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                if !dias.isEmpty {
                    EleccionRapidaCoach(
                        elementos: elecciones,
                        etiqueta: { $0.etiqueta },
                        icono: { $0.icono },
                        elegir: { eleccion in
                            if let opcion = eleccion.opcion { elegir(opcion) }
                            else { otroDia?() }
                        })
                }

                if !accionables.isEmpty {
                    VStack(spacing: DV2.Espacio.s) {
                        ForEach(accionables) { opcion in
                            // Una sola salida real: deja de ser una fila
                            // de lista y pasa a ser EL botón.
                            TarjetaOpcionCoach(icono: opcion.icono,
                                               titulo: opcion.titulo,
                                               subtitulo: opcion.detalle,
                                               destacada: accionables.count == 1) {
                                elegir(opcion)
                            }
                        }
                    }
                }

                if let mantener {
                    BotonSecundarioCoach(titulo: mantener.titulo,
                                         icono: "equal.circle") {
                        elegir(mantener)
                    }
                }
            }
        }
    }
}
