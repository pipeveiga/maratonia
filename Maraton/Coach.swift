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
    }

    var idioma: String
    var objetivo: String
    var fechaCarrera: String?
    var diasElegidos: [Int]
    var baseline: BaselineDTO?
    var semanaActual: Int?
    var semanasTotales: Int?
    var cumplimientoPorciento: Double?
    var kmUltimas4Semanas: Double?
    var proximosEntrenamientos: [ProgramadoDTO]
    var ultimasSesiones: [SesionDTO]

    /// Construye el DTO desde el dominio. TODO lo que sale está acá a
    /// la vista — auditable en un solo lugar. Jamás GPS ni FC cruda.
    @MainActor
    static func desde(_ almacen: AlmacenV2, hoy: DiaLocal) -> ContextoCoach {
        let perfil = almacen.perfilDeportivo
        let referencia = almacen.referenciaVigente
        let proximos = almacen.todosLosProgramados
            .filter { $0.resolucion == .pendiente && !(($0.dia ?? hoy) < hoy) }
            .sorted { ($0.dia ?? hoy) < ($1.dia ?? hoy) }
            .prefix(14)
            .map { programado in
                ProgramadoDTO(programadoID: programado.id.uuidString.lowercased(),
                              dia: Self.texto(programado.dia ?? hoy),
                              nombre: programado.definicion.nombre,
                              tipo: programado.definicion.tipo.rawValue,
                              km: programado.definicion.distanciaTotalKm)
            }
        return ContextoCoach(
            idioma: FormatoFecha.locale.language.languageCode?.identifier == "en" ? "en" : "es",
            objetivo: perfil.objetivo?.rawValue ?? "sin-objetivo",
            fechaCarrera: perfil.fechaObjetivo.map(Self.texto),
            diasElegidos: perfil.diasElegidos ?? [],
            baseline: referencia.map { BaselineDTO(distanciaMetros: $0.distanciaMetros,
                                                   segundos: $0.segundos) },
            semanaActual: almacen.planActivo.flatMap { plan in
                plan.semanas.firstIndex { semana in
                    semana.programados.contains { ($0.dia?.lunesDeLaSemana()) == hoy.lunesDeLaSemana() }
                }.map { $0 + 1 }
            },
            semanasTotales: almacen.planActivo?.semanas.count,
            cumplimientoPorciento: nil,
            kmUltimas4Semanas: nil,
            proximosEntrenamientos: Array(proximos),
            ultimasSesiones: [])
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
        var tipo: String            // "reprogramar" | "omitir"
        var programadoID: String
        var nuevoDia: String?
    }
    var explicacion: String
    var cambios: [Cambio]

    /// Traducción ESTRICTA a CambioPropuesto: cualquier campo que no
    /// parsee descarta ESE cambio (nunca se interpreta texto libre).
    var propuestas: [CambioPropuesto] {
        cambios.compactMap { cambio in
            guard let id = UUID(uuidString: cambio.programadoID) else { return nil }
            switch cambio.tipo {
            case "omitir":
                return .omitir(programadoID: id)
            case "reprogramar":
                guard let texto = cambio.nuevoDia,
                      let dia = ContextoCoach.dia(desde: texto) else { return nil }
                return .reprogramar(programadoID: id, a: dia)
            default:
                return nil
            }
        }
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

    nonisolated static var disponible: Bool {
        urlBase != nil && ServicioAuth.disponible
    }

    private struct Peticion: Codable {
        var accion: String
        var requestID: String
        var contexto: ContextoCoach
        var detalle: String?
        var programadoID: String?
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
            solicitud.httpBody = try JSONEncoder().encode(Peticion(
                accion: accion, requestID: requestID.uuidString.lowercased(),
                contexto: contexto, detalle: detalle,
                programadoID: programadoID?.uuidString.lowercased()))
            let (datos, respuesta) = try await URLSession.shared.data(for: solicitud)
            guard let http = respuesta as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            switch http.statusCode {
            case 200:
                return try JSONDecoder().decode(Salida.self, from: datos)
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

    @State private var explicacion: CoachWorkoutExplanation?
    @State private var ajuste: CoachWeekAdjustment?
    @State private var estado: CoachEstadoObjetivo?
    @State private var motivoCambio = ""
    @State private var aplicado = false

    private var hoy: DiaLocal { DiaLocal(fecha: Date()) }

    var body: some View {
        List {
            Section {
                Text("El Coach explica y propone; tu plan lo decide el motor de Maratonia y lo confirmás vos. Nada cambia sin tu OK.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Preguntale al Coach") {
                Button {
                    Task { await explicarProximo() }
                } label: {
                    Label("Explicame mi próximo entrenamiento", systemImage: "questionmark.circle")
                }
                .disabled(servicio.ocupado || proximoPendiente == nil)

                Button {
                    Task { await pedirEstado() }
                } label: {
                    Label("¿Cómo vengo para mi objetivo?", systemImage: "chart.line.uptrend.xyaxis")
                }
                .disabled(servicio.ocupado)
            }

            Section("Reorganizar mi semana") {
                TextField("Contale qué pasó (ej.: no puedo correr el jueves)", text: $motivoCambio, axis: .vertical)
                Button {
                    Task { await pedirReorganizacion() }
                } label: {
                    Label("Proponer cambios", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(servicio.ocupado || motivoCambio.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if servicio.ocupado {
                Section { ProgressView().frame(maxWidth: .infinity) }
            }
            if let mensaje = servicio.mensajeError {
                Section { Text(mensaje).font(.footnote).foregroundStyle(.orange) }
            }

            if let explicacion {
                Section(explicacion.titulo) {
                    Text(explicacion.queEs)
                    Text(explicacion.paraQueSirve).foregroundStyle(.secondary)
                    Text(explicacion.comoEncararlo).font(.footnote)
                }
            }

            if let estado {
                Section(estado.veredicto) {
                    Text(estado.detalle)
                    Text(estado.focoProximasSemanas).font(.footnote).foregroundStyle(.secondary)
                }
            }

            if let ajuste {
                seccionPropuesta(ajuste)
            }
        }
        .navigationTitle("Maratonia Coach")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// ANTES vs PROPUESTO, con la validación del motor a la vista, y
    /// "Aplicar cambios" que ejecuta SOLO lo validado.
    @ViewBuilder
    private func seccionPropuesta(_ ajuste: CoachWeekAdjustment) -> some View {
        Section("Propuesta del Coach") {
            Text(ajuste.explicacion).font(.footnote)
            ForEach(Array(ajuste.propuestas.enumerated()), id: \.offset) { _, cambio in
                filaCambio(cambio)
            }
            if aplicado {
                Label("Cambios aplicados", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button {
                    aplicar(ajuste)
                } label: {
                    Label("Aplicar cambios", systemImage: "checkmark.circle")
                        .font(.headline)
                }
                .disabled(cambiosValidos(ajuste).isEmpty)
                if cambiosValidos(ajuste).isEmpty {
                    Text("El motor rechazó todos los cambios propuestos — no se aplica nada.")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func filaCambio(_ cambio: CambioPropuesto) -> some View {
        let validacion = ValidadorDeCoach.validar(cambio, en: almacen.almacen, hoy: hoy)
        return VStack(alignment: .leading, spacing: 4) {
            switch cambio {
            case .reprogramar(let id, let dia):
                let nombre = nombreDe(id)
                Text("\(nombre): \(textoDia(diaDe(id))) → \(textoDia(dia))")
                    .font(.subheadline)
            case .omitir(let id):
                Text("Omitir: \(nombreDe(id))").font(.subheadline)
            case .ajustarVolumenSemana:
                Text("Ajuste de volumen").font(.subheadline)
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

    private func contexto() -> ContextoCoach {
        ContextoCoach.desde(almacen.almacen, hoy: hoy)
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
                                      accion: "reorganizar", contexto: contexto(),
                                      detalle: motivoCambio)
    }

    private func cambiosValidos(_ ajuste: CoachWeekAdjustment) -> [CambioPropuesto] {
        ajuste.propuestas.filter {
            ValidadorDeCoach.validar($0, en: almacen.almacen, hoy: hoy).permitido
        }
    }

    /// La mutación REAL: motor manda, usuario confirmó, se aplica solo
    /// lo validado — y por las APIs existentes del dominio.
    private func aplicar(_ ajuste: CoachWeekAdjustment) {
        for cambio in cambiosValidos(ajuste) {
            switch cambio {
            case .reprogramar(let id, let dia):
                _ = almacen.almacen.reprogramar(programadoID: id, a: dia)
            case .omitir(let id):
                _ = almacen.almacen.omitir(programadoID: id)
            case .ajustarVolumenSemana:
                break   // el validador ya lo rechazó
            }
        }
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
