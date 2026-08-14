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

    /// Contenido PROPIO para una frecuencia concreta, cuando recortar
    /// el contenido general no produce un plan sano a esa frecuencia.
    /// Hoy solo lo usa Mejorar 5K en 3 días: con una sola sesión fácil
    /// acompañando, el fondo de 12 km deja la semana con la larga en el
    /// 47-48 %, y bajarlo con un techo automático da una progresión
    /// jaggeada. La variante propia baja el pico a 11 km, monótona, con
    /// las sesiones de calidad idénticas.
    var contenidoPorDias: [Int: PlanBase] = [:]

    /// El contenido que le corresponde a esta frecuencia. Sin variante
    /// declarada, el general (que después se recorta).
    func contenido(para dias: Int) -> PlanBase? {
        contenidoPorDias[dias] ?? contenido
    }

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
            PlanArquetipo(id: "mejorar-5k", version: 2, objetivo: .mejorar5K,
                          nombre: "Mejorar mis 5K",
                          semanasMinimas: 8, semanasRecomendadas: 8,
                          diasMinimos: 3, diasMaximos: 5,
                          recomiendaBaseline: true,
                          contenido: ContenidoPlanes.mejorar5K(),
                          contenidoPorDias: [3: ContenidoPlanes.mejorar5KTresDias()]),
            // ---- 10K
            PlanArquetipo(id: "10k-continuo", version: 2, objetivo: .diez,
                          nombre: "Rumbo a 10K",
                          semanasMinimas: 8, semanasRecomendadas: 8,
                          diasMinimos: 2, diasMaximos: 3,
                          recomiendaBaseline: false,
                          contenido: bases["10k-continuo"]),
            // 4 días MÍNIMO (antes 3). Con 3 sesiones queda una sola
            // fácil acompañando al fondo, y las dos reglas ya
            // declaradas se cruzan: "larga ≤ 45 % de la semana" y
            // "ninguna fácil > 60 % de la larga" implican, con una sola
            // fácil, que la larga no puede pasar de 1,61× el volumen de
            // la sesión de calidad. Para este plan eso topa el fondo en
            // ~13 km y rompe 5 de las 8 semanas de construcción;
            // forzarlo con un techo automático produce una progresión
            // que ni siquiera es monótona (13,0 → 12,9 → 14,6). La base
            // aeróbica hasta 16 km es lo que este plan ES —"para bajar
            // en 10K hace falta base aeróbica, no solo series"—, así que
            // antes que servir una versión que no la construye, el
            // motor dice que 3 días no alcanzan y ofrece Rumbo a 10K,
            // que sí acepta 2-3 días. Ver METODOLOGIA.md.
            PlanArquetipo(id: "mejorar-10k", version: 1, objetivo: .mejorar10K,
                          nombre: "Mejorar mis 10K",
                          semanasMinimas: 10, semanasRecomendadas: 10,
                          diasMinimos: 4, diasMaximos: 5,
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
            PlanArquetipo(id: "maraton", version: 2, objetivo: .maraton,
                          nombre: "Maratón",
                          semanasMinimas: 16, semanasRecomendadas: 16,
                          diasMinimos: 4, diasMaximos: 5,
                          recomiendaBaseline: true,
                          contenido: ContenidoPlanes.maraton()),
            PlanArquetipo(id: "mejorar-maraton", version: 2, objetivo: .mejorarMaraton,
                          nombre: "Mejorar mi maratón",
                          semanasMinimas: 18, semanasRecomendadas: 18,
                          diasMinimos: 4, diasMaximos: 5,
                          recomiendaBaseline: true,
                          contenido: ContenidoPlanes.mejorarMaraton()),
            PlanArquetipo(id: "maraton-rendimiento", version: 2, objetivo: .maratonRendimiento,
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
    /// Si el techo de entrada se pudo cumplir, y con cuánto margen.
    /// El plan se propone igual cuando NO se cumple: el desvío se
    /// reporta, no se esconde ni bloquea. Ver `DiagnosticoArranque`.
    var arranque: DiagnosticoArranque = .sinVolumenPrevio
}

/// Qué pasó con el techo de entrada al atenuar el arranque.
///
/// Existe porque `ajustarArranque` NO siempre puede cumplir el techo.
/// El factor tiene un piso (`factorArranqueMinimo`) y los segmentos
/// tienen el suyo (1 km, y los bloques por tiempo no se escalan): si
/// esos pisos se agotan antes de llegar al techo, la primera semana
/// queda POR ENCIMA de lo que se le prometió al corredor. Eso pasaba
/// ya, pero se devolvía con exactamente la misma forma que un ajuste
/// exitoso — un `Double` — y el llamador no tenía manera de
/// distinguirlos. El desvío existía y era invisible.
///
/// Este tipo NO cambia ninguna regla deportiva ni decide nada: solo
/// hace decible lo que el cálculo ya sabía.
enum DiagnosticoArranque: Equatable {
    /// No había volumen previo con el cual medir (o el plan no declara
    /// volumen). No hay techo: no hay nada que cumplir ni que
    /// incumplir, y esto NO es lo mismo que haberlo cumplido.
    case sinVolumenPrevio
    /// El template ya entraba bajo el techo por sí solo: no hizo falta
    /// atenuar nada.
    case noHizoFalta(permitidoKm: Double, resultanteKm: Double)
    /// Se atenuó y se encontró un factor que deja la primera semana
    /// bajo el techo.
    case dentroDelTecho(permitidoKm: Double, resultanteKm: Double)
    /// Los pisos se agotaron antes que el techo: la primera semana
    /// queda por encima de lo permitido. No es un error del cálculo —
    /// es que este plan no se puede achicar tanto para este corredor.
    /// El plan se conserva igual; lo que no se hace es mentir sobre él.
    case excedeElTecho(permitidoKm: Double, resultanteKm: Double)

    /// Cuántos km por encima del techo quedó la primera semana.
    var excesoKm: Double {
        guard case .excedeElTecho(let permitido, let resultante) = self else { return 0 }
        return max(0, resultante - permitido)
    }

    /// `false` SOLO cuando había un techo y NO se cumplió. Sin techo
    /// contra el cual medir no se afirma nada: ver `hayTecho`.
    var cumpleElTecho: Bool {
        if case .excedeElTecho = self { return false }
        return true
    }

    /// Si hubo un techo contra el cual medir. `cumpleElTecho` sobre un
    /// diagnóstico sin techo es vacío, no una afirmación de éxito.
    var hayTecho: Bool {
        if case .sinVolumenPrevio = self { return false }
        return true
    }

    /// El techo que se le prometió al corredor, si hubo uno.
    var permitidoKm: Double? {
        switch self {
        case .sinVolumenPrevio: return nil
        case .noHizoFalta(let p, _), .dentroDelTecho(let p, _), .excedeElTecho(let p, _):
            return p
        }
    }

    /// Lo que la primera semana mide de verdad, si se pudo medir.
    var resultanteKm: Double? {
        switch self {
        case .sinVolumenPrevio: return nil
        case .noHizoFalta(_, let r), .dentroDelTecho(_, let r), .excedeElTecho(_, let r):
            return r
        }
    }
}

/// Lo que devuelve `ajustarArranque`: el plan atenuado, el factor y —
/// la parte nueva — si ese factor alcanzó para cumplir el techo.
struct ResultadoArranque {
    var base: PlanBase
    var factor: Double
    var diagnostico: DiagnosticoArranque
}

// MARK: - Motor

enum MotorPlanificacion {

    /// De inputs a propuesta, determinístico. La biblioteca se inyecta
    /// (tests); por defecto, la V1.
    static func proponer(_ pedido: PedidoDePlan,
                         biblioteca: [PlanArquetipo] = BibliotecaArquetipos.v1(),
                         calendario: Calendar = .current) -> ResultadoPlanificacion {
        guard let arquetipo = biblioteca.first(where: { $0.objetivo == pedido.objetivo }),
              arquetipo.listoParaProponer else {
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

        // ---- La VARIANTE REAL, antes de evaluar nada. El corredor no
        // se mide contra un template abstracto sino contra el plan que
        // va a recibir: con 4 días la semana 1 de Mejorar 10K son 30 km
        // y con 5 son 36, y eso cambia qué base hace falta para
        // sostenerla. Recortar es una función pura de (contenido, días)
        // y no lee el veredicto, así que no hay ciclo: primero se arma
        // la variante, después se juzga, y recién al final se atenúa el
        // arranque (que sí depende del veredicto).
        guard let base = arquetipo.contenido(para: diasEfectivos) else {
            return .sinContenido(objetivo: pedido.objetivo)
        }
        var recortada = recortar(base, aDias: min(diasEfectivos,
                                                  arquetipo.diasMaximos))

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
            volviendoDePausa: pedido.actividad?.volviendoDePausa ?? false,
            kmSemana1DelPlan: recortada.semanas.first.map { volumenSemanaBase($0) }))

        // ¿El plan se genera en su variante conservadora? El veredicto
        // lo dice para `.elegibleConservador`, pero NO para quien cruzó
        // la puerta de `requiereFaseBase` aceptando arrancar
        // conservador: ese es justamente el que menos base tiene.
        var arranqueConservador = veredicto.esConservador

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
            // Aceptó arrancar conservador tras leer la advertencia: el
            // plan tiene que SERLO. Antes recibía el techo permisivo
            // (1,2 en vez de 1,0) y la rampa corta (3 semanas en vez de
            // 5) — el trato MÁS agresivo para el corredor con MENOS
            // base, exactamente al revés de lo que el flag promete.
            arranqueConservador = true
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
                                     conservador: arranqueConservador,
                                     baseline: PerformanceBaseline(referencia: pedido.referencia))
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
            factorArranque: factorArranque,
            arranque: ajuste.diagnostico))
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
    ///
    /// El techo se mide contra el BASELINE REAL del corredor cuando
    /// existe. Los bloques por tiempo se convierten a km con un ritmo,
    /// y usar el genérico hacía que el techo se evaluara para un
    /// corredor que no es este: un umbral de 18′ son más km para quien
    /// corre rápido que para quien corre lento, así que el mismo plan
    /// pesa distinto según quién lo corra. Sin referencia se cae al
    /// ritmo de referencia, que es lo único disponible.
    ///
    /// Y el factor se BUSCA contra el volumen que va a quedar, no se
    /// deduce como `permitido / kmPrimera`: escalar solo mueve los
    /// segmentos por DISTANCIA. Los bloques por tiempo (un umbral de
    /// 18′ dura 18′), el piso de 1 km por segmento y el tope de
    /// duración no responden al factor, así que la regla de tres
    /// prometía un techo que la semana resultante no cumplía — el
    /// arranque de Mejorar 10K contra 20 km/semana daba 25,4 km, un
    /// +27 % donde el contrato dice +20 %.
    static func ajustarArranque(_ base: PlanBase, kmSemanalesActuales: Double?,
                                conservador: Bool = false,
                                baseline: PerformanceBaseline? = nil) -> ResultadoArranque {
        let sinMedida = ResultadoArranque(base: base, factor: 1,
                                          diagnostico: .sinVolumenPrevio)
        guard let actuales = kmSemanalesActuales, actuales > 0,
              let primera = base.semanas.first else { return sinMedida }
        let volumenTemplate = volumenSemanaBase(primera, baseline: baseline)
        guard volumenTemplate > 0 else { return sinMedida }

        let techo = conservador ? factorEntradaConservador : factorEntradaMaximo
        let rampa = conservador ? semanasDeRampaConservador : semanasDeRampa
        let permitido = actuales * techo

        let factor: Double
        let alcanzaElTecho: Bool
        switch factorDeArranque(primera, permitido: permitido, baseline: baseline) {
        case .noHaceFalta:
            return ResultadoArranque(
                base: base, factor: 1,
                diagnostico: .noHizoFalta(permitidoKm: permitido,
                                          resultanteKm: volumenTemplate))
        case .encontrado(let f):
            factor = f; alcanzaElTecho = true
        case .pisoInsuficiente(let piso):
            // El plan igual se atenúa todo lo que se puede: dejarlo sin
            // tocar sería peor. Lo que cambia es que ahora se DICE.
            factor = piso; alcanzaElTecho = false
        }

        var resultado = base
        resultado.semanas = base.semanas.map { semana in
            let indice = semana.numero - 1
            guard indice >= 0, indice < rampa else { return semana }
            // Rampa lineal: semana 1 = factor, y de ahí a 1 en
            // `rampa` semanas.
            let avance = Double(indice) / Double(rampa)
            return escalarDistancias(semana, factor: factor + (1 - factor) * avance)
        }

        // Se mide la semana que REALMENTE quedó, no una reconstrucción:
        // si la rampa cambiara, el diagnóstico la sigue sin retocarse.
        let resultante = resultado.semanas.first
            .map { volumenSemanaBase($0, baseline: baseline) } ?? 0
        return ResultadoArranque(
            base: resultado, factor: factor,
            diagnostico: alcanzaElTecho
                ? .dentroDelTecho(permitidoKm: permitido, resultanteKm: resultante)
                : .excedeElTecho(permitidoKm: permitido, resultanteKm: resultante))
    }

    /// Resultado de buscar el factor de arranque. Los tres casos son
    /// distintos y antes dos de ellos volvían como el mismo `Double`.
    private enum BusquedaDeArranque {
        /// El techo ya se cumple sin tocar nada.
        case noHaceFalta
        /// El mayor factor que deja la semana dentro del techo.
        case encontrado(Double)
        /// Ni siquiera `factorArranqueMinimo` alcanza. Trae el piso,
        /// que es lo que se aplica igual, pero por otro camino para
        /// que el llamador no pueda confundirlo con un éxito.
        case pisoInsuficiente(Double)
    }

    /// El MAYOR factor que deja la semana dentro del techo. El volumen
    /// es monótono no decreciente en el factor (cada segmento crece o
    /// se queda en su piso), así que la bisección es exacta y
    /// determinística.
    ///
    /// Si ni siquiera `factorArranqueMinimo` alcanza, el piso se aplica
    /// igual — por debajo el plan deja de ser el plan — pero vuelve
    /// como `.pisoInsuficiente`. Chequearlo por adelantado no cambia el
    /// factor resultante: si el piso ya excede el permitido, la
    /// monotonía garantiza que TODA la bisección deja `bajo` clavado en
    /// el piso. Lo que cambia es que deja de ser indistinguible de un
    /// ajuste que sí cumplió.
    private static func factorDeArranque(_ semana: SemanaBase, permitido: Double,
                                         baseline: PerformanceBaseline?) -> BusquedaDeArranque {
        guard volumenSemanaBase(semana, baseline: baseline) > permitido else {
            return .noHaceFalta
        }
        guard volumenSemanaBase(escalarDistancias(semana, factor: factorArranqueMinimo),
                                baseline: baseline) <= permitido else {
            return .pisoInsuficiente(factorArranqueMinimo)
        }
        var bajo = factorArranqueMinimo
        var alto = 1.0
        for _ in 0..<30 {
            let medio = (bajo + alto) / 2
            if volumenSemanaBase(escalarDistancias(semana, factor: medio),
                                 baseline: baseline) > permitido {
                alto = medio
            } else {
                bajo = medio
            }
        }
        return .encontrado(bajo)
    }

    /// Escala los segmentos por DISTANCIA de la semana. Los bloques por
    /// tiempo no se tocan y la carrera objetivo jamás se escala.
    private static func escalarDistancias(_ semana: SemanaBase,
                                          factor: Double) -> SemanaBase {
        var nueva = semana
        nueva.entrenamientos = semana.entrenamientos.map { entrenamiento in
            guard entrenamiento.tipo != .ritmoCarrera else { return entrenamiento }
            var ajustado = entrenamiento
            ajustado.segmentos = entrenamiento.segmentos.map { segmento in
                guard let km = segmento.distanciaKm else { return segmento }
                var nuevoSegmento = segmento
                nuevoSegmento.distanciaKm = max(1, (km * factor * 10).rounded() / 10)
                return nuevoSegmento
            }
            return ajustado
        }
        return nueva
    }

    /// Volumen de la semana, sesión por sesión: el tope de duración es
    /// por sesión y aplanar la semana lo haría desaparecer.
    static func volumenSemanaBase(_ semana: SemanaBase,
                                  baseline: PerformanceBaseline? = nil) -> Double {
        semana.entrenamientos.reduce(0.0) { $0 + volumenBase($1, baseline: baseline) }
    }

    /// Cuánto puede crecer una sesión fácil al absorber el volumen de
    /// otra que se eliminó. DECISIÓN MARATONIA: 1,6× su distancia
    /// original. Sin tope, un corredor de 3 días terminaba con un
    /// "rodaje suave" de 21 km.
    static let topeAbsorcion = 1.6

    /// GUARDRAIL DE DISEÑO MARATONIA (no es una constante fisiológica y
    /// no hay literatura que fije este número): una sesión fácil que
    /// recibe volumen redistribuido no puede pasar del 60 % de la
    /// tirada larga de SU semana.
    ///
    /// Existe porque `topeAbsorcion` es proporcional al tamaño de cada
    /// sesión, así que el reparto se concentraba justamente en la
    /// fácil que ya era la más grande. El resultado era una segunda
    /// tirada larga sin declarar: Primera Maratón con 4 días producía
    /// un "Rodaje medio" de 20,4 km (2 h 42, y 2 h 56 para el corredor
    /// lento) al lado de un fondo de 23,1 km, y en la SEMANA 1 de seis
    /// combinaciones la sesión fácil terminaba siendo más larga que la
    /// propia tirada larga —hasta el 128 %—, con lo cual la semana se
    /// quedaba sin sesión más larga.
    ///
    /// El tope limita el CRECIMIENTO, nunca el tamaño: una sesión que
    /// el contenido diseñó larga a propósito (el rodaje medio de los
    /// planes de maratón) conserva su distancia y simplemente no
    /// absorbe. La tirada larga, la calidad y la carrera objetivo no
    /// entran acá: no absorben volumen en ningún caso.
    static let topeSegundaLarga = 0.60

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
            // El guardrail se mide contra la tirada larga de ESTA
            // semana, no contra la del plan: en las semanas iniciales
            // la larga todavía es corta y es justo ahí donde el reparto
            // la superaba.
            nueva.entrenamientos = redistribuir(huerfano, en: nueva.entrenamientos,
                                                largaDeLaSemana: largaDe(nueva))
            return nueva
        }
        return resultado
    }

    /// Qué sesiones pueden crecer para absorber volumen ajeno.
    private static func esAbsorbente(_ tipo: TipoEntrenamiento) -> Bool {
        let rol = RolSesion.para(tipo)
        return rol == .facil || rol == .recuperacion
    }

    /// Con el TOPE aplicado: una sesión que ya llega a su techo de
    /// duración no tiene capacidad libre para absorber nada, y lo que
    /// se le asignara se evaporaría igual al calcular el volumen.
    private static func volumenBase(_ entrenamiento: EntrenamientoBase,
                                    baseline: PerformanceBaseline? = nil) -> Double {
        CalculoVolumen.volumen(entrenamiento.segmentos.map {
            CalculoVolumen.Entrada(distanciaKm: $0.distanciaKm,
                                   duracionSegundos: $0.duracionSegundos,
                                   ritmo: $0.ritmo)
        }, tope: entrenamiento.topeDuracionSegundos, baseline: baseline).totalKm
    }

    /// La tirada larga de una semana, con la que se mide el guardrail.
    /// 0 = la semana no tiene una (semana de carrera, o planes que
    /// todavía no la declaran): entonces solo rige `topeAbsorcion`.
    private static func largaDe(_ semana: SemanaBase) -> Double {
        semana.entrenamientos.filter { $0.tipo == .largo }
            .map { volumenBase($0) }.max() ?? 0
    }

    /// Reparte `huerfano` km entre las sesiones absorbentes, en
    /// proporción a la capacidad de cada una y sin pasar el tope. Lo que
    /// no entra se pierde: es la señal correcta de que esa frecuencia no
    /// alcanza para ese plan, y el invariante de catálogo la detecta.
    ///
    /// La capacidad de cada sesión es la distancia entre lo que YA mide
    /// y su techo, y el techo es el menor entre `topeAbsorcion` (1,6×
    /// lo suyo) y `topeSegundaLarga` (60 % del fondo de la semana). Si
    /// una sesión ya viene por encima de ese 60 % porque el contenido
    /// la diseñó así, su capacidad es CERO — no se la achica, no crece.
    private static func redistribuir(_ huerfano: Double,
                                     en entrenamientos: [EntrenamientoBase],
                                     largaDeLaSemana: Double) -> [EntrenamientoBase] {
        let indices = entrenamientos.indices.filter {
            esAbsorbente(entrenamientos[$0].tipo)
                && entrenamientos[$0].segmentos.contains { $0.distanciaKm != nil }
        }
        guard !indices.isEmpty else { return entrenamientos }
        let capacidades = indices.map { indice -> Double in
            let propio = volumenBase(entrenamientos[indice])
            var techo = propio * topeAbsorcion
            if largaDeLaSemana > 0 {
                techo = min(techo, topeSegundaLarga * largaDeLaSemana)
            }
            return max(0, techo - propio)
        }
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
                // El arranque se atenuó, pero no siempre alcanza: hay
                // planes que no pueden bajar hasta el volumen del
                // corredor sin dejar de ser ese plan. Prometer "adaptado
                // a tu volumen actual" en ese caso es falso, y es
                // justamente el corredor con menos base el que lo lee.
                if propuesta.factorArranque < 1 {
                    if propuesta.arranque.cumpleElTecho {
                        Label(String(localized: "Arranque adaptado a tu volumen actual: las primeras semanas empiezan más abajo y suben hasta el plan completo."),
                              systemImage: "arrow.down.right.circle")
                            .font(.footnote)
                            .foregroundStyle(DV2.Marca.primario)
                    } else {
                        Label(String(localized: "Las primeras semanas ya empiezan lo más abajo que permite este plan, y aun así piden más de lo que venís haciendo. Arrancá con calma y adaptá las sesiones que te queden largas."),
                              systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
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
