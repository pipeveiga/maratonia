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

// NOTA: RolSesion, TipoSemana y Adaptabilidad se mudaron a
// Shared/DominioV2.swift — se PERSISTEN dentro del plan (prioridad y
// contrato de adaptación de cada sesión) y ese archivo es el que
// también compila el Watch. Acá quedó solo lo que es motor.

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
    /// Rol de una sesión del contenido. La tabla vive en el dominio
    /// (`RolSesion.para(_:)`) porque también se persiste en el plan;
    /// esto queda como alias para no romper llamadores.
    static func rol(de tipo: TipoEntrenamiento) -> RolSesion { .para(tipo) }
}

// MARK: - Biblioteca V1

/// El catálogo completo: los diez objetivos de §13, cada uno con su
/// arquetipo versionado, sus límites explícitos y su contenido real.
/// Nada copiado de planes de terceros — la metodología está citada en
/// METODOLOGIA.md y la estructura es de Maratonia.
///
/// Los `diasMinimos` de cada arquetipo tienen que coincidir con los
/// `RequisitosObjetivo` del evaluador de elegibilidad; hay un test que
/// lo verifica, porque divergir ahí produce el peor bug posible: la
/// app te deja elegir un objetivo y después no te genera nada.
enum BibliotecaArquetipos {
    static func v1() -> [PlanArquetipo] {
        let bases = Dictionary(uniqueKeysWithValues:
            Catalogo.planesDisponibles().map { ($0.id, $0) })
        return [
            // ---- 5K
            PlanArquetipo(id: "primeros-5k", version: 2, objetivo: .primeros5K,
                          nombre: "Primeros 5K",
                          semanasMinimas: 6, semanasRecomendadas: 6,
                          diasMinimos: 2, diasMaximos: 3,
                          recomiendaBaseline: false,
                          contenido: bases["primeros-5k"]),
            PlanArquetipo(id: "mejorar-5k", version: 1, objetivo: .mejorar5K,
                          nombre: "Mejorar mis 5K",
                          semanasMinimas: 8, semanasRecomendadas: 8,
                          diasMinimos: 3, diasMaximos: 5,
                          recomiendaBaseline: true,
                          contenido: ContenidoPlanes.mejorar5K()),
            // ---- 10K
            PlanArquetipo(id: "10k-continuo", version: 2, objetivo: .diez,
                          nombre: "Rumbo a 10K",
                          semanasMinimas: 8, semanasRecomendadas: 8,
                          diasMinimos: 2, diasMaximos: 3,
                          recomiendaBaseline: false,
                          contenido: bases["10k-continuo"]),
            PlanArquetipo(id: "mejorar-10k", version: 1, objetivo: .mejorar10K,
                          nombre: "Mejorar mis 10K",
                          semanasMinimas: 10, semanasRecomendadas: 10,
                          diasMinimos: 3, diasMaximos: 5,
                          recomiendaBaseline: true,
                          contenido: ContenidoPlanes.mejorar10K()),
            // ---- 21K
            PlanArquetipo(id: "media-maraton", version: 1, objetivo: .mediaMaraton,
                          nombre: "Media maratón",
                          semanasMinimas: 12, semanasRecomendadas: 12,
                          diasMinimos: 4, diasMaximos: 5,
                          recomiendaBaseline: true,
                          contenido: ContenidoPlanes.mediaMaraton()),
            PlanArquetipo(id: "mejorar-media", version: 1, objetivo: .mejorarMedia,
                          nombre: "Mejorar mi media",
                          semanasMinimas: 12, semanasRecomendadas: 12,
                          diasMinimos: 4, diasMaximos: 5,
                          recomiendaBaseline: true,
                          contenido: ContenidoPlanes.mejorarMedia()),
            PlanArquetipo(id: "media-rendimiento", version: 1, objetivo: .mediaRendimiento,
                          nombre: "Media · rendimiento",
                          semanasMinimas: 14, semanasRecomendadas: 14,
                          diasMinimos: 5, diasMaximos: 6,
                          recomiendaBaseline: true,
                          contenido: ContenidoPlanes.mediaRendimiento()),
            // ---- 42K
            PlanArquetipo(id: "maraton", version: 1, objetivo: .maraton,
                          nombre: "Maratón",
                          semanasMinimas: 16, semanasRecomendadas: 16,
                          diasMinimos: 4, diasMaximos: 5,
                          recomiendaBaseline: true,
                          contenido: ContenidoPlanes.maraton()),
            PlanArquetipo(id: "mejorar-maraton", version: 1, objetivo: .mejorarMaraton,
                          nombre: "Mejorar mi maratón",
                          semanasMinimas: 18, semanasRecomendadas: 18,
                          diasMinimos: 4, diasMaximos: 5,
                          recomiendaBaseline: true,
                          contenido: ContenidoPlanes.mejorarMaraton()),
            PlanArquetipo(id: "maraton-rendimiento", version: 1, objetivo: .maratonRendimiento,
                          nombre: "Maratón · rendimiento",
                          semanasMinimas: 18, semanasRecomendadas: 18,
                          diasMinimos: 5, diasMaximos: 6,
                          recomiendaBaseline: true,
                          contenido: ContenidoPlanes.maratonRendimiento()),
        ]
    }

    static func arquetipo(para objetivo: ObjetivoDeportivo) -> PlanArquetipo? {
        v1().first { $0.objetivo == objetivo }
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

    // ---- Motor adaptativo: contexto del corredor. Todo opcional —
    // sin nada de esto el motor se comporta exactamente como antes.

    /// Ventana de 42 días calculada desde Salud.
    var historial: ResumenVentana? = nil
    /// Lo que el corredor declaró (o confirmó) sobre su actividad.
    var actividad: ActividadActual? = nil
    var molestias: EstadoMolestias = .ninguna
    var preferencias: PreferenciasSemana? = nil
    /// Saltear la puerta de elegibilidad porque el corredor insistió
    /// tras leer la advertencia. NUNCA saltea los bloqueos duros
    /// (fecha imposible, días insuficientes): esos no son opinables.
    var aceptaConservador = false
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
    /// El objetivo no se sostiene con lo que el corredor trae hoy.
    /// Trae los motivos y, si existe, por dónde empezar en su lugar.
    case requiereBase(motivos: [MotivoElegibilidad],
                      puente: ObjetivoDeportivo?)
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

    /// Cómo salió la evaluación de elegibilidad. `.elegible` es lo
    /// normal; `.elegibleConservador` significa que el arranque se
    /// bajó y el corredor merece saber por qué.
    var veredicto: VeredictoElegibilidad = .elegible
    /// Factor con el que se atenuó el arranque (1 = sin atenuar).
    var factorArranque: Double = 1
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
        // Los días declarados IMPOSIBLES se descartan siempre: son una
        // restricción del corredor, no una preferencia negociable.
        let imposibles = Set(pedido.preferencias?.diasImposibles ?? [])
        let diasConcretos = pedido.diasConcretos.map { crudos in
            Array(Set(crudos.filter { (1...7).contains($0) && !imposibles.contains($0) })).sorted()
        }
        let diasEfectivos = diasConcretos?.count ?? pedido.diasPorSemana

        guard diasEfectivos >= arquetipo.diasMinimos else {
            return .diasInsuficientes(minimo: arquetipo.diasMinimos)
        }

        if arquetipo.recomiendaBaseline, pedido.referencia == nil,
           !pedido.aceptaSinBaseline {
            return .faltaBaseline(arquetipo: arquetipo.id)
        }

        // ---- Elegibilidad: ¿este objetivo se sostiene con lo que el
        // corredor trae? Determinístico y explicable (§12). No es un
        // filtro moral: solo evita vender un plan que no se aguanta.
        let semanasDisponibles = pedido.fechaObjetivo.map {
            semanasEntre(pedido.hoy, y: $0, calendario: calendario)
        }
        let veredicto = EvaluadorElegibilidad.evaluar(EntradaElegibilidad(
            objetivo: pedido.objetivo,
            semanasDisponibles: semanasDisponibles,
            semanasMinimasDelPlan: arquetipo.semanasMinimas,
            diasElegidos: diasEfectivos,
            historial: pedido.historial,
            actividadDeclarada: pedido.actividad,
            tieneBaseline: pedido.referencia != nil,
            molestias: pedido.molestias,
            mesesCorriendoRegular: pedido.actividad?.mesesCorriendoRegular,
            volviendoDePausa: pedido.actividad?.volviendoDePausa ?? false))

        switch veredicto {
        case .fechaDemasiadoCerca(let disponibles, let minimas):
            return .tiempoInsuficiente(semanasDisponibles: disponibles,
                                       semanasMinimas: minimas)
        case .frecuenciaInsuficiente(_, let minimo):
            return .diasInsuficientes(minimo: minimo)
        case .requiereFaseBase(let motivos):
            guard pedido.aceptaConservador else {
                return .requiereBase(
                    motivos: motivos,
                    puente: EvaluadorElegibilidad.objetivoPuente(para: pedido.objetivo))
            }
        case .elegible, .elegibleConservador:
            break
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
            recortada = distribuir(recortada, enDias: dias,
                                   diaFondo: pedido.preferencias?.diaPreferidoFondo)
        }

        // ---- Arranque conservador: el plan empieza DONDE ESTÁ el
        // corredor, no donde el template asume que está.
        // "Conservador" no es una etiqueta: baja el techo de entrada y
        // alarga la rampa. La diferencia es real y testeable.
        let ajuste = ajustarArranque(recortada,
                                     kmSemanalesActuales: volumenActual(pedido),
                                     conservador: veredicto.esConservador)
        recortada = ajuste.base
        let factorArranque = ajuste.factor

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

        let baselineVolumen = PerformanceBaseline(referencia: pedido.referencia)
        let primeraSemanaKm = plan.semanas.first?
            .kmPrescritos(baseline: baselineVolumen)

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
            planUsuario: plan,
            veredicto: veredicto,
            factorArranque: factorArranque))
    }

    /// El volumen semanal REAL del corredor: gana lo medido en Salud
    /// sobre lo declarado (§4). nil = no sabemos, y entonces el
    /// arranque no se toca (no inventamos un punto de partida).
    static func volumenActual(_ pedido: PedidoDePlan) -> Double? {
        if let historial = pedido.historial, !historial.estaVacia {
            return historial.kmPorSemana
        }
        return pedido.actividad?.kmSemanales
    }

    /// Cuánto puede subir la primera semana respecto de lo que el
    /// corredor viene haciendo. DECISIÓN MARATONIA (METODOLOGIA.md):
    /// +20 % sobre el volumen actual. No es la "regla del 10 %"
    /// universal — que no tiene respaldo sólido y no distingue a quien
    /// corre 10 km/semana de quien corre 90 — sino un techo de ENTRADA
    /// al plan, aplicado una sola vez.
    static let factorEntradaMaximo = 1.2
    /// El MISMO techo cuando la elegibilidad dio "conservador": la
    /// primera semana no puede superar lo que el corredor ya hace.
    /// Esto es lo que hace que "conservador" signifique algo — antes
    /// era una etiqueta que se mostraba y no cambiaba una sola línea
    /// del plan generado, mientras el onboarding prometía que "el plan
    /// arranca más prudente".
    static let factorEntradaConservador = 1.0
    /// Piso: por debajo de esto el plan ya no es el plan. Si hace falta
    /// recortar más, el problema es de elegibilidad, no de arranque.
    static let factorArranqueMinimo = 0.5
    /// En cuántas semanas se vuelve al volumen del template.
    static let semanasDeRampa = 3
    /// Conservador sube más despacio: una semana más de rampa.
    static let semanasDeRampaConservador = 5

    /// Atenúa las primeras semanas para que el salto de entrada sea
    /// razonable, y vuelve al template con una rampa lineal. NUNCA
    /// escala hacia arriba (§40) ni toca la carrera objetivo.
    ///
    /// El volumen de la primera semana se mide con `CalculoVolumen`,
    /// no sumando distancias declaradas: si no, el techo de entrada se
    /// calculaba contra un número que ignoraba las sesiones de calidad
    /// y la atenuación salía mal por varios kilómetros.
    static func ajustarArranque(_ base: PlanBase, kmSemanalesActuales: Double?,
                                conservador: Bool = false)
        -> (base: PlanBase, factor: Double) {
        guard let actuales = kmSemanalesActuales, actuales > 0,
              let primera = base.semanas.first else { return (base, 1) }
        let kmPrimera = CalculoVolumen.volumen(
            primera.entrenamientos.flatMap(\.segmentos).map {
                CalculoVolumen.Entrada(distanciaKm: $0.distanciaKm,
                                       duracionSegundos: $0.duracionSegundos,
                                       ritmo: $0.ritmo)
            }).totalKm
        guard kmPrimera > 0 else { return (base, 1) }

        let techo = conservador ? factorEntradaConservador : factorEntradaMaximo
        let rampa = conservador ? semanasDeRampaConservador : semanasDeRampa
        let permitido = actuales * techo
        guard kmPrimera > permitido else { return (base, 1) }
        let factor = max(factorArranqueMinimo, permitido / kmPrimera)

        var resultado = base
        resultado.semanas = base.semanas.map { semana in
            let indice = semana.numero - 1
            guard indice >= 0, indice < rampa else { return semana }
            // Rampa lineal: semana 1 = factor, y de ahí a 1 en
            // `rampa` semanas.
            let avance = Double(indice) / Double(rampa)
            let factorSemana = factor + (1 - factor) * avance
            var nueva = semana
            nueva.entrenamientos = semana.entrenamientos.map { entrenamiento in
                // La carrera objetivo jamás se escala.
                guard entrenamiento.tipo != .ritmoCarrera else { return entrenamiento }
                var ajustado = entrenamiento
                ajustado.segmentos = entrenamiento.segmentos.map { segmento in
                    guard let km = segmento.distanciaKm else { return segmento }
                    var nuevoSegmento = segmento
                    nuevoSegmento.distanciaKm = max(1, (km * factorSemana * 10).rounded() / 10)
                    return nuevoSegmento
                }
                return ajustado
            }
            return nueva
        }
        return (resultado, factor)
    }

    /// Cuánto puede crecer una sesión fácil al absorber el volumen de
    /// otra que se eliminó. DECISIÓN MARATONIA: 1,6× su distancia
    /// original. Sin tope, un corredor de 3 días terminaba con un
    /// "rodaje suave" de 21 km.
    static let topeAbsorcion = 1.6

    /// Recorte por disponibilidad: en cada semana quedan las `dias`
    /// sesiones de MAYOR prioridad de rol (carrera > larga > calidad >
    /// fácil > recuperación), conservando el orden de días.
    ///
    /// Y —esto es lo que cambió— el volumen FÁCIL de las sesiones
    /// eliminadas se REDISTRIBUYE entre las fáciles que quedan, en vez
    /// de tirarse. Antes, recortar de 5 a 3 días no achicaba la tirada
    /// larga pero sí borraba dos rodajes enteros: la larga pasaba de
    /// ocupar el 51 % de la semana a ocupar el 66 %, y el corredor con
    /// menos disponibilidad —normalmente el menos entrenado— recibía la
    /// semana peor proporcionada. La redistribución hace que la
    /// proporción deje de depender de cuántos días marcaste.
    ///
    /// Qué NO absorbe volumen: la tirada larga (crecería sin control),
    /// las sesiones de calidad (su carga es intensidad, no distancia) y
    /// la carrera objetivo.
    static func recortar(_ base: PlanBase, aDias dias: Int) -> PlanBase {
        var resultado = base
        resultado.semanas = base.semanas.map { semana in
            var nueva = semana
            let ordenadas = semana.entrenamientos.enumerated().sorted {
                let rolA = PlanArquetipo.rol(de: $0.element.tipo)
                let rolB = PlanArquetipo.rol(de: $1.element.tipo)
                return rolA == rolB ? $0.offset < $1.offset : rolA < rolB
            }
            let elegidas = Set(ordenadas.prefix(dias).map(\.offset))
            guard elegidas.count < semana.entrenamientos.count else { return nueva }

            // Volumen fácil que se pierde con el recorte.
            let huerfano = semana.entrenamientos.enumerated()
                .filter { !elegidas.contains($0.offset) && esAbsorbente($0.element.tipo) }
                .reduce(0.0) { $0 + volumenBase($1.element) }

            nueva.entrenamientos = elegidas.sorted().map { semana.entrenamientos[$0] }
            guard huerfano > 0 else { return nueva }
            nueva.entrenamientos = redistribuir(huerfano, en: nueva.entrenamientos)
            return nueva
        }
        return resultado
    }

    /// Qué sesiones pueden crecer para absorber volumen ajeno.
    private static func esAbsorbente(_ tipo: TipoEntrenamiento) -> Bool {
        let rol = RolSesion.para(tipo)
        return rol == .facil || rol == .recuperacion
    }

    private static func volumenBase(_ entrenamiento: EntrenamientoBase) -> Double {
        CalculoVolumen.volumen(entrenamiento.segmentos.map {
            CalculoVolumen.Entrada(distanciaKm: $0.distanciaKm,
                                   duracionSegundos: $0.duracionSegundos,
                                   ritmo: $0.ritmo)
        }).totalKm
    }

    /// Reparte `huerfano` km entre las sesiones absorbentes, en
    /// proporción a la capacidad de cada una y sin pasar el tope. Lo que
    /// no entra se pierde: es la señal correcta de que esa frecuencia no
    /// alcanza para ese plan, y el invariante de catálogo la detecta.
    private static func redistribuir(_ huerfano: Double,
                                     en entrenamientos: [EntrenamientoBase]) -> [EntrenamientoBase] {
        let indices = entrenamientos.indices.filter {
            esAbsorbente(entrenamientos[$0].tipo)
                && entrenamientos[$0].segmentos.contains { $0.distanciaKm != nil }
        }
        guard !indices.isEmpty else { return entrenamientos }
        let capacidades = indices.map { volumenBase(entrenamientos[$0]) * (topeAbsorcion - 1) }
        let capacidadTotal = capacidades.reduce(0, +)
        guard capacidadTotal > 0 else { return entrenamientos }
        let reparto = min(huerfano, capacidadTotal)

        var resultado = entrenamientos
        for (indice, capacidad) in zip(indices, capacidades) {
            let extra = reparto * (capacidad / capacidadTotal)
            let kmDeclarados = resultado[indice].segmentos.compactMap(\.distanciaKm).reduce(0, +)
            guard kmDeclarados > 0, extra > 0 else { continue }
            let factor = (kmDeclarados + extra) / kmDeclarados
            for g in resultado[indice].segmentos.indices {
                if let km = resultado[indice].segmentos[g].distanciaKm {
                    resultado[indice].segmentos[g].distanciaKm = (km * factor * 10).rounded() / 10
                }
            }
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
    /// `diaFondo`: el día que el corredor prefiere para la tirada larga
    /// (1 = lunes … 7 = domingo). Si es uno de sus días elegidos, la
    /// larga se INTERCAMBIA con lo que hubiera caído ahí — nunca se
    /// duplica un día ni se pierde una sesión. Sin preferencia, la
    /// larga queda donde la puso el template (el último día de la
    /// semana), que NO es lo mismo que forzar domingo (§9).
    static func distribuir(_ base: PlanBase, enDias diasElegidos: [Int],
                           diaFondo: Int? = nil) -> PlanBase {
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
            var asignadas = zip(ordenadas.prefix(k), indices).map { sesion, indice -> EntrenamientoBase in
                var asignada = sesion
                asignada.diaDeSemana = dias[indice]
                return asignada
            }
            if let preferido = diaFondo, dias.contains(preferido),
               let larga = asignadas.firstIndex(where: { $0.tipo == .largo }),
               asignadas[larga].diaDeSemana != preferido {
                let diaDeLaLarga = asignadas[larga].diaDeSemana
                if let ocupante = asignadas.firstIndex(where: { $0.diaDeSemana == preferido }) {
                    asignadas[ocupante].diaDeSemana = diaDeLaLarga
                }
                asignadas[larga].diaDeSemana = preferido
            }
            nueva.entrenamientos = asignadas.sorted { $0.diaDeSemana < $1.diaDeSemana }
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

// NOTA: CambioPropuesto, ValidacionDeCambio y ValidadorDeCoach viven
// ahora en Adaptacion.swift, con el juego completo de operaciones
// (mantener / mover / reducir / convertir / omitir) y el validador
// determinístico entero. Acá quedó solo la generación del plan.

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
        case .requiereBase(let motivos, let puente):
            vistaRequiereBase(motivos: motivos, puente: puente)
        }
    }

    /// El "todavía no" honesto: explica QUÉ falta (nunca califica al
    /// corredor) y ofrece por dónde empezar. El objetivo queda
    /// guardado — nadie le está diciendo que no puede.
    private func vistaRequiereBase(motivos: [MotivoElegibilidad],
                                   puente: ObjetivoDeportivo?) -> some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: DV2.Espacio.s) {
                    Label(String(localized: "Falta base para ese objetivo"),
                          systemImage: "figure.strengthtraining.functional")
                        .font(.headline)
                        .foregroundStyle(.orange)
                    Text("No es un “no”: es un “todavía no”. Armar ese plan ahora sería venderte semanas que no se sostienen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Section(String(localized: "Por qué")) {
                ForEach(motivos, id: \.self) { motivo in
                    Label(motivo.texto, systemImage: "circle.fill")
                        .font(.footnote)
                        .labelStyle(.titleAndIcon)
                }
            }
            if let puente {
                Section {
                    Text("Un buen punto de partida es **\(TextosObjetivo.nombre(de: puente))**. Cuando lo completes, este objetivo va a estar a tiro.")
                        .font(.subheadline)
                }
            }
            Section {
                Button(String(localized: "Entendido")) { alTerminar() }
            } footer: {
                Text("Tu objetivo queda guardado en el perfil. Podés volver a intentarlo cuando quieras.")
            }
        }
        .navigationTitle(Text("Tu plan"))
        .navigationBarTitleDisplayMode(.inline)
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
                if propuesta.factorArranque < 1 {
                    Label(String(localized: "Arranque adaptado a tu volumen actual: las primeras semanas empiezan más abajo y suben hasta el plan completo."),
                          systemImage: "arrow.down.right.circle")
                        .font(.footnote)
                        .foregroundStyle(DV2.Marca.primario)
                }
            } footer: {
                Text("Al confirmar, tu plan actual (si existe) queda archivado con su historial.")
            }
            if !propuesta.veredicto.motivos.isEmpty {
                Section(String(localized: "A tener en cuenta")) {
                    ForEach(propuesta.veredicto.motivos, id: \.self) { motivo in
                        Text(motivo.texto)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section {
                Button {
                    almacen.almacen.adoptarPlan(propuesta.planUsuario)
                    alTerminar()
                } label: {
                    EtiquetaBotonPrimarioV2(titulo: "Confirmar plan",
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
