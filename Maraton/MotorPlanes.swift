import SwiftUI

// MOTOR DE PLANES (RC1, §28-43). Determinístico y testeable: de los
// inputs del corredor (objetivo, fecha, disponibilidad, baseline,
// experiencia) a un PlanUsuario snapshot real. SIN números mágicos
// deportivos: la ESTRUCTURA (selección, límites, calendario, roles,
// prioridades) es software; el CONTENIDO (progresiones, volúmenes)
// vive en arquetipos versionados con su metodología — y donde no hay
// contenido validado, el motor lo dice en vez de inventarlo.
//
// La IA futura se monta ARRIBA: propone CambioPropuesto, el motor
// valida, el usuario acepta. GPT jamás escribe el dominio directo.

// MARK: - Roles y semanas (estructura, no metodología)

/// El rol de una sesión dentro de la semana. Los arquetipos razonan
/// por ROLES con prioridad — la disponibilidad decide qué roles entran
/// (2 días ≠ "plan de 4 borrando filas").
enum RolSesion: Int, Codable, Comparable {
    case carrera = 0            // el día objetivo: nunca se recorta
    case tiradaLarga = 1
    case calidadPrincipal = 2
    case facil = 3
    case recuperacion = 4
    case calidadSecundaria = 5

    static func < (a: RolSesion, b: RolSesion) -> Bool { a.rawValue < b.rawValue }
}

/// Carácter de una semana dentro del plan (infraestructura §37: carga,
/// descarga, taper — el contenido lo declara cuando su metodología lo
/// define; nil = sin declarar, jamás se inventa).
enum TipoSemana: String, Codable {
    case carga, descarga, taper, semanaDeCarrera
}

// MARK: - Arquetipo

/// Un arquetipo VERSIONADO de plan: plantilla + límites explícitos.
/// PlanArquetipo + parámetros + baseline + fecha + disponibilidad →
/// PlanUsuario snapshot. Actualizar un arquetipo NUNCA toca planes ya
/// adoptados (son snapshots por valor).
struct PlanArquetipo: Identifiable {
    var id: String                    // "primeros-5k"
    var version: Int
    var objetivo: ObjetivoDeportivo
    var nombre: String

    /// Límites EXPLÍCITOS: fuera de esto el motor rechaza — nada de
    /// estirar/comprimir plantillas en silencio.
    var semanasMinimas: Int
    var semanasRecomendadas: Int
    var diasMinimos: Int
    var diasMaximos: Int

    /// ¿Conviene una referencia de rendimiento? (No la exige: el plan
    /// puede existir con ritmos simbólicos/libres sin resolver.)
    var recomiendaBaseline: Bool

    /// Contenido real (nil = arquetipo declarado SIN contenido
    /// validado todavía: el motor responde "sinContenido", no inventa).
    var contenido: PlanBase?

    /// Carácter declarado por semana (infra §37; hoy nil en el
    /// contenido provisional — llega con la metodología).
    var tiposDeSemana: [Int: TipoSemana] = [:]

    var listoParaProponer: Bool { contenido != nil }
    var planBaseID: String { "\(id)@\(version)" }
}

extension PlanArquetipo {
    /// Rol de una sesión del contenido. Tabla ESTRUCTURAL fija (no es
    /// metodología: es cómo se recorta por disponibilidad).
    static func rol(de tipo: TipoEntrenamiento) -> RolSesion {
        switch tipo {
        case .ritmoCarrera: return .carrera
        case .largo: return .tiradaLarga
        case .tempo, .umbral, .series, .testEvaluacion: return .calidadPrincipal
        case .recuperacion: return .recuperacion
        case .facil, .personalizado: return .facil
        }
    }
}

// MARK: - Biblioteca V1

/// La biblioteca de arquetipos de V1 (§40, CONTENIDO_PLANES.md):
/// - primeros-5k y 10k-continuo: contenido PROVISIONAL real (ritmos
///   libres, progresión conservadora) — proponibles.
/// - mejorar-5k, media-maraton, maraton: DECLARADOS con límites, SIN
///   contenido validado → el motor lo dice con honestidad.
enum BibliotecaArquetipos {
    static func v1() -> [PlanArquetipo] {
        let bases = Dictionary(uniqueKeysWithValues:
            Catalogo.planesDisponibles().map { ($0.id, $0) })
        return [
            PlanArquetipo(id: "primeros-5k", version: 2, objetivo: .primeros5K,
                          nombre: "Primeros 5K",
                          semanasMinimas: 6, semanasRecomendadas: 6,
                          diasMinimos: 2, diasMaximos: 3,
                          recomiendaBaseline: false,
                          contenido: bases["primeros-5k"]),
            PlanArquetipo(id: "10k-continuo", version: 2, objetivo: .diez,
                          nombre: "Rumbo a 10K",
                          semanasMinimas: 8, semanasRecomendadas: 8,
                          diasMinimos: 2, diasMaximos: 3,
                          recomiendaBaseline: false,
                          contenido: bases["10k-continuo"]),
            PlanArquetipo(id: "mejorar-5k", version: 1, objetivo: .mejorar5K,
                          nombre: "Mejorar mis 5K",
                          semanasMinimas: 8, semanasRecomendadas: 8,
                          diasMinimos: 3, diasMaximos: 5,
                          recomiendaBaseline: true,
                          contenido: ContenidoPlanes.mejorar5K()),
            PlanArquetipo(id: "media-maraton", version: 1, objetivo: .mediaMaraton,
                          nombre: "Media maratón",
                          semanasMinimas: 12, semanasRecomendadas: 12,
                          diasMinimos: 3, diasMaximos: 5,
                          recomiendaBaseline: true,
                          contenido: ContenidoPlanes.mediaMaraton()),
            PlanArquetipo(id: "maraton", version: 1, objetivo: .maraton,
                          nombre: "Maratón",
                          semanasMinimas: 16, semanasRecomendadas: 16,
                          diasMinimos: 3, diasMaximos: 5,
                          recomiendaBaseline: true,
                          contenido: ContenidoPlanes.maraton()),
        ]
    }
}

// MARK: - Pedido y resultado

/// Los inputs del corredor, con datos OBJETIVOS (nada de reducir a
/// "principiante/intermedio/avanzado").
struct PedidoDePlan {
    var objetivo: ObjetivoDeportivo
    var fechaObjetivo: DiaLocal?
    var diasPorSemana: Int
    /// Días CONCRETOS elegidos (1 = lunes … 7 = domingo). Si están,
    /// mandan: la cantidad efectiva es su cuenta y las sesiones caen
    /// SOLO en esos días. nil = perfil viejo → días del template.
    var diasConcretos: [Int]? = nil
    /// La referencia cruda vigente (test 5K, marca…), si existe.
    var referencia: ReferenciaRendimiento?
    /// true = el corredor decidió arrancar sin baseline aunque el
    /// arquetipo lo recomiende (el Test 5K nunca es obligatorio).
    var aceptaSinBaseline = false
    var hoy: DiaLocal
}

enum ResultadoPlanificacion {
    case propuesta(PropuestaPlan)
    /// El arquetipo recomienda baseline y no hay: ofrecer Test 5K
    /// (o arrancar sin referencia — decisión del corredor).
    case faltaBaseline(arquetipo: String)
    /// Quedan menos semanas que el mínimo del arquetipo: NO se genera
    /// un plan peligroso comprimido.
    case tiempoInsuficiente(semanasDisponibles: Int, semanasMinimas: Int)
    case diasInsuficientes(minimo: Int)
    /// El arquetipo existe pero su contenido todavía no está validado.
    case sinContenido(objetivo: ObjetivoDeportivo)
}

/// El plan propuesto ANTES de confirmar: resumen + PlanUsuario listo.
struct PropuestaPlan {
    var arquetipoID: String
    var version: Int
    var nombre: String
    var semanas: Int
    var sesionesPorSemana: Int
    var diasPedidos: Int
    var fechaInicio: DiaLocal
    var fechaCarrera: DiaLocal?
    var referenciaUsada: ReferenciaRendimiento?
    var kmPrimeraSemana: Double?
    var planUsuario: PlanUsuario
}

// MARK: - Motor

enum MotorPlanificacion {

    /// De inputs a propuesta, determinístico. La biblioteca se inyecta
    /// (tests); por defecto, la V1.
    static func proponer(_ pedido: PedidoDePlan,
                         biblioteca: [PlanArquetipo] = BibliotecaArquetipos.v1(),
                         calendario: Calendar = .current) -> ResultadoPlanificacion {
        guard let arquetipo = biblioteca.first(where: { $0.objetivo == pedido.objetivo }),
              arquetipo.listoParaProponer, let base = arquetipo.contenido else {
            return .sinContenido(objetivo: pedido.objetivo)
        }

        // Días concretos (si están) mandan sobre la cuenta abstracta.
        let diasConcretos = pedido.diasConcretos.map {
            Array(Set($0.filter { (1...7).contains($0) })).sorted()
        }
        let diasEfectivos = diasConcretos?.count ?? pedido.diasPorSemana

        guard diasEfectivos >= arquetipo.diasMinimos else {
            return .diasInsuficientes(minimo: arquetipo.diasMinimos)
        }

        if arquetipo.recomiendaBaseline, pedido.referencia == nil,
           !pedido.aceptaSinBaseline {
            return .faltaBaseline(arquetipo: arquetipo.id)
        }

        // ---- Calendario ----
        let semanas = base.semanasTotales
        let inicio: DiaLocal
        if let carrera = pedido.fechaObjetivo {
            // La carrera cae DENTRO de la última semana: el inicio es
            // el lunes de la semana de la carrera menos (N-1) semanas.
            // Si ese inicio ya pasó, el tiempo NO alcanza — jamás se
            // comprime un plan para fingir que alcanza.
            let lunesCarrera = carrera.lunesDeLaSemana(calendario: calendario)
            let candidato = lunesCarrera.sumando(dias: -(semanas - 1) * 7,
                                                 calendario: calendario)
            if candidato < pedido.hoy.lunesDeLaSemana(calendario: calendario) {
                let disponibles = semanasEntre(pedido.hoy, y: carrera,
                                               calendario: calendario)
                return .tiempoInsuficiente(semanasDisponibles: disponibles,
                                           semanasMinimas: arquetipo.semanasMinimas)
            }
            inicio = candidato
        } else {
            // Sin carrera: arranca ESTA semana (semana parcial inicial:
            // lo anterior a hoy se descarta después de instanciar).
            inicio = pedido.hoy.lunesDeLaSemana(calendario: calendario)
        }

        // ---- Disponibilidad: recorte por ROL, decidido acá y no en UI.
        var recortada = recortar(base, aDias: min(diasEfectivos,
                                                  arquetipo.diasMaximos))

        // ---- Días concretos: cada sesión cae SOLO en un día que el
        // corredor dijo que puede correr. El ORDEN relativo del template
        // (fácil→calidad→larga, con su separación) es metodología
        // versionada y se preserva; el motor solo lo mapea a los días
        // disponibles. La carrera objetivo se pinnea a su fecha después.
        if let dias = diasConcretos, !dias.isEmpty {
            recortada = distribuir(recortada, enDias: dias)
        }

        // ---- Snapshot (reusa la adopción probada del catálogo).
        var plan = recortada.adoptar(inicio: inicio, fechaAdopcion: Date(),
                                     calendario: calendario)
        plan.nombre = arquetipo.nombre
        plan.origen = .catalogo(planBaseID: arquetipo.planBaseID)
        plan.referenciaUsadaID = pedido.referencia?.id

        // ---- Ritmos: los segmentos SIMBÓLICOS se resuelven contra el
        // baseline con la metodología activa AL ADOPTAR (el snapshot
        // queda con rangos concretos y el Watch no cambia). Sin
        // baseline quedan simbólicos: el plan funciona igual.
        if let baseline = PerformanceBaseline(referencia: pedido.referencia) {
            for s in plan.semanas.indices {
                for p in plan.semanas[s].programados.indices {
                    for g in plan.semanas[s].programados[p].definicion.segmentos.indices {
                        if case .simbolico(let tipo) = plan.semanas[s].programados[p]
                            .definicion.segmentos[g].ritmo,
                           case .resuelto(let rango, _) = Metodologias.resolver(tipo, baseline: baseline) {
                            plan.semanas[s].programados[p].definicion.segmentos[g].ritmo =
                                .absoluto(minSegKm: rango.minSegKm, maxSegKm: rango.maxSegKm)
                        }
                    }
                }
            }
        }

        // Semana parcial inicial: los días ya pasados no se programan.
        if pedido.fechaObjetivo == nil {
            for s in plan.semanas.indices {
                plan.semanas[s].programados.removeAll {
                    ($0.dia ?? pedido.hoy) < pedido.hoy
                }
            }
        }

        // La carrera objetivo queda ALINEADA: la última sesión del plan
        // se corre al día exacto de la carrera y nada queda después.
        if let carrera = pedido.fechaObjetivo,
           let ultimaSemana = plan.semanas.indices.last {
            plan.semanas[ultimaSemana].programados.removeAll {
                ($0.dia ?? carrera) > carrera
            }
            if let ultima = plan.semanas[ultimaSemana].programados.indices.last {
                plan.semanas[ultimaSemana].programados[ultima].dia = carrera
            }
        }
        plan.semanas.removeAll { $0.programados.isEmpty }

        let primeraSemanaKm = plan.semanas.first?.programados
            .compactMap { $0.definicion.distanciaTotalKm }
            .reduce(0, +)

        return .propuesta(PropuestaPlan(
            arquetipoID: arquetipo.id,
            version: arquetipo.version,
            nombre: arquetipo.nombre,
            semanas: plan.semanas.count,
            sesionesPorSemana: recortada.semanas.first?.entrenamientos.count ?? 0,
            diasPedidos: diasEfectivos,
            fechaInicio: plan.semanas.first?.programados.compactMap(\.dia).min() ?? inicio,
            fechaCarrera: pedido.fechaObjetivo,
            referenciaUsada: pedido.referencia,
            kmPrimeraSemana: (primeraSemanaKm ?? 0) > 0 ? primeraSemanaKm : nil,
            planUsuario: plan))
    }

    /// Recorte por disponibilidad: en cada semana quedan las `dias`
    /// sesiones de MAYOR prioridad de rol (carrera > larga > calidad >
    /// fácil > recuperación), conservando el orden de días.
    static func recortar(_ base: PlanBase, aDias dias: Int) -> PlanBase {
        var resultado = base
        resultado.semanas = base.semanas.map { semana in
            var recortadaSemana = semana
            let ordenadas = semana.entrenamientos.enumerated().sorted {
                let rolA = PlanArquetipo.rol(de: $0.element.tipo)
                let rolB = PlanArquetipo.rol(de: $1.element.tipo)
                return rolA == rolB ? $0.offset < $1.offset : rolA < rolB
            }
            let elegidas = ordenadas.prefix(dias).map(\.offset).sorted()
            recortadaSemana.entrenamientos = elegidas.map { semana.entrenamientos[$0] }
            return recortadaSemana
        }
        return resultado
    }

    /// Reasigna el día de semana de cada sesión a los días ELEGIDOS
    /// (1 = lunes … 7 = domingo), preservando el orden relativo del
    /// template. Si hay más días disponibles que sesiones, se eligen
    /// los mejor repartidos INCLUYENDO el último (la larga/carrera va
    /// al final de la semana en todos los templates — eso es contenido
    /// del arquetipo, no una regla del motor). Determinístico; jamás
    /// duplica fechas (los días elegidos son únicos y las sesiones por
    /// semana nunca superan su cuenta tras el recorte).
    static func distribuir(_ base: PlanBase, enDias diasElegidos: [Int]) -> PlanBase {
        let dias = Array(Set(diasElegidos.filter { (1...7).contains($0) })).sorted()
        guard !dias.isEmpty else { return base }
        var resultado = base
        resultado.semanas = base.semanas.map { semana in
            var nueva = semana
            // Orden del template = metodología (separación de sesiones
            // exigentes decidida por el contenido versionado).
            let ordenadas = semana.entrenamientos.sorted { $0.diaDeSemana < $1.diaDeSemana }
            let k = min(ordenadas.count, dias.count)
            guard k > 0 else { return nueva }
            // Subconjunto repartido de índices, siempre con el último.
            let indices: [Int] = k == 1
                ? [dias.count - 1]
                : (0..<k).map { Int((Double($0) * Double(dias.count - 1) / Double(k - 1)).rounded()) }
            nueva.entrenamientos = zip(ordenadas.prefix(k), indices).map { sesion, indice in
                var asignada = sesion
                asignada.diaDeSemana = dias[indice]
                return asignada
            }
            return nueva
        }
        return resultado
    }

    /// Semanas calendario COMPLETAS entre dos días (para el mensaje de
    /// tiempo insuficiente).
    static func semanasEntre(_ desde: DiaLocal, y hasta: DiaLocal,
                             calendario: Calendar = .current) -> Int {
        guard let inicio = desde.lunesDeLaSemana(calendario: calendario)
                .fecha(calendario: calendario),
              let fin = hasta.lunesDeLaSemana(calendario: calendario)
                .fecha(calendario: calendario),
              let dias = calendario.dateComponents([.day], from: inicio, to: fin).day
        else { return 0 }
        return max(0, dias / 7 + 1)
    }
}

// MARK: - Coach futuro (interfaces, SIN implementación de IA — §41)

/// Lo ÚNICO que un coach (GPT u otro) podrá proponer. El coach no
/// escribe el dominio ni el Watch: propone, el MOTOR valida, el
/// USUARIO acepta, y recién ahí se aplica versionado.
enum CambioPropuesto {
    case reprogramar(programadoID: UUID, a: DiaLocal)
    case omitir(programadoID: UUID)
    /// Requiere metodología versionada: hoy el validador lo rechaza.
    case ajustarVolumenSemana(numero: Int, factor: Double)
}

struct ValidacionDeCambio {
    var permitido: Bool
    var motivo: String?
}

enum ValidadorDeCoach {
    /// Reglas del motor sobre cualquier propuesta externa. Determinista
    /// y conservador: lo que no puede validarse, se rechaza.
    static func validar(_ cambio: CambioPropuesto, en almacen: AlmacenV2,
                        hoy: DiaLocal) -> ValidacionDeCambio {
        switch cambio {
        case .reprogramar(let id, let dia):
            guard let programado = almacen.todosLosProgramados.first(where: { $0.id == id }),
                  programado.resolucion == .pendiente else {
                return ValidacionDeCambio(permitido: false,
                                          motivo: "Solo se reprograman pendientes.")
            }
            guard !(dia < hoy) else {
                return ValidacionDeCambio(permitido: false,
                                          motivo: "No se reprograma hacia el pasado.")
            }
            return ValidacionDeCambio(permitido: true, motivo: nil)
        case .omitir(let id):
            let existe = almacen.todosLosProgramados.contains {
                $0.id == id && $0.resolucion == .pendiente
            }
            return ValidacionDeCambio(permitido: existe,
                                      motivo: existe ? nil : "Solo se omiten pendientes.")
        case .ajustarVolumenSemana:
            return ValidacionDeCambio(
                permitido: false,
                motivo: "Ajustar volumen requiere metodología versionada (pendiente).")
        }
    }
}

// MARK: - UI: propuesta de plan ("Preparar mi plan" de verdad)

struct PropuestaPlanView: View {
    @ObservedObject var almacen: AlmacenStore
    let resultado: ResultadoPlanificacion
    /// Cierra TODO el onboarding al adoptar.
    var alTerminar: () -> Void

    var body: some View {
        switch resultado {
        case .propuesta(let propuesta):
            vistaPropuesta(propuesta)
        case .faltaBaseline:
            vistaFaltaBaseline
        case .tiempoInsuficiente(let disponibles, let minimas):
            vistaMensaje(
                icono: "hourglass.badge.exclamationmark", color: .orange,
                titulo: String(localized: "El tiempo no alcanza"),
                texto: String(localized: "Quedan \(disponibles) semanas y este plan necesita al menos \(minimas). Comprimirlo sería riesgoso — mejor elegir otra fecha u otro objetivo."))
        case .diasInsuficientes(let minimo):
            vistaMensaje(
                icono: "calendar.badge.exclamationmark", color: .orange,
                titulo: String(localized: "Faltan días de entrenamiento"),
                texto: String(localized: "Este plan necesita al menos \(minimo) días por semana."))
        case .sinContenido(let objetivo):
            vistaMensaje(
                icono: "hammer", color: .secondary,
                titulo: String(localized: "Ese plan está en camino"),
                texto: String(localized: "El contenido de \(TextosObjetivo.nombre(de: objetivo)) todavía no está listo — no vamos a inventarlo. Tu perfil queda guardado; mientras tanto podés usar los planes de 5K y 10K."))
        }
    }

    private func vistaPropuesta(_ propuesta: PropuestaPlan) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DV2.Espacio.s) {
                    Text("TU PLAN PROPUESTO")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Color.accentColor)
                        .tracking(1)
                    Text(propuesta.nombre)
                        .font(.title2.bold())
                }
            }
            Section {
                LabeledContent(String(localized: "Duración"),
                               value: String(localized: "\(propuesta.semanas) semanas"))
                LabeledContent(String(localized: "Sesiones por semana"),
                               value: "\(propuesta.sesionesPorSemana)")
                if propuesta.sesionesPorSemana < propuesta.diasPedidos {
                    Text("Este plan usa \(propuesta.sesionesPorSemana) de tus \(propuesta.diasPedidos) días — los demás quedan de descanso.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if let fecha = propuesta.fechaInicio.fecha() {
                    LabeledContent(String(localized: "Empieza"),
                                   value: FormatoFecha.corta(fecha))
                }
                if let carrera = propuesta.fechaCarrera?.fecha() {
                    LabeledContent(String(localized: "Tu carrera"),
                                   value: FormatoFecha.media(carrera))
                }
                if let km = propuesta.kmPrimeraSemana {
                    LabeledContent(String(localized: "Primera semana"),
                                   value: String(format: "≈ %.0f km", km))
                }
                if let referencia = propuesta.referenciaUsada {
                    LabeledContent(String(localized: "Referencia"),
                                   value: String(format: "%.1f km · %@",
                                                 referencia.distanciaMetros / 1000,
                                                 formatearDuracion(TimeInterval(referencia.segundos))))
                } else {
                    Text("Sin referencia de ritmo: las sesiones van a ritmo libre y se personalizan cuando tengas una (Test 5K o marca).")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } footer: {
                Text("Al confirmar, tu plan actual (si existe) queda archivado con su historial.")
            }
            Section {
                Button {
                    almacen.almacen.adoptarPlan(propuesta.planUsuario)
                    alTerminar()
                } label: {
                    EtiquetaBotonPrimarioV2(titulo: String(localized: "Confirmar plan"),
                                            icono: "checkmark")
                }
                .buttonStyle(.plain)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
        }
        .navigationTitle(Text("Tu plan"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var vistaFaltaBaseline: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DV2.Espacio.s) {
                    Text("Para personalizar este plan conviene una referencia de ritmo.")
                        .font(.headline)
                    Text("Podés correr el Test 5K cuando quieras (5 km fuerte pero controlado) o empezar sin referencia — el plan existe igual, con ritmos libres.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button {
                    var perfil = almacen.almacen.perfilDeportivo
                    perfil.testPendiente = true
                    almacen.almacen.perfil = perfil
                    alTerminar()
                } label: {
                    Label(String(localized: "Hacer el Test 5K primero"),
                          systemImage: "flag.checkered")
                }
                Button {
                    alTerminar()
                } label: {
                    Label(String(localized: "Decidir más tarde"), systemImage: "clock")
                }
            } footer: {
                Text("El test queda disponible en la pestaña Correr. Cuando lo termines, volvé a «Preparar mi plan».")
            }
        }
        .navigationTitle(Text("Referencia"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func vistaMensaje(icono: String, color: Color,
                              titulo: String, texto: String) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DV2.Espacio.m) {
                    Label(titulo, systemImage: icono)
                        .font(.headline)
                        .foregroundStyle(color)
                    Text(texto)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Button(String(localized: "Entendido")) { alTerminar() }
            }
        }
        .navigationTitle(Text("Tu plan"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
