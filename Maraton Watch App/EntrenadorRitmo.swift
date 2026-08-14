import Foundation

// El "entrenador" de ritmo: sigue el plan por tramos usando la distancia
// del entrenamiento y el ritmo suavizado, y habla por el mismo canal de
// los avisos (háptico + ducking + voz) cuando arranca un tramo nuevo o
// cuando vas fuera del rango objetivo.
//
// Filtros anti-molestia:
// - los primeros 45 s de cada tramo no opina (el ritmo se acomoda)
// - corrige como mucho una vez por minuto
// - con la música en pausa (semáforo) no opina
// - margen de 5 seg/km antes de considerar que estás afuera del rango

/// Un kilómetro cumplido con su tiempo parcial, para la tabla de la UI.
struct ParcialKm: Identifiable {
    let id = UUID()
    let km: Int
    let segundos: Int
}

final class EntrenadorRitmo: ObservableObject {
    static let compartido = EntrenadorRitmo()

    @Published var tramoActual: Tramo?

    /// El plan completo y por cuál tramo vas, para el panel "PLAN" de la
    /// pantalla de métricas (deslizando hacia abajo).
    @Published var tramosDelPlan: [Tramo] = []
    @Published var indiceActual = 0

    /// "1.24 / 3.0 km" o "1:12 / 2 min" del tramo EN CURSO. Lo refresca
    /// chequear() una vez por segundo; la UI lo muestra tal cual (antes
    /// la UI recalculaba con suma de prefijos, que no sirve con tramos
    /// por tiempo).
    @Published var textoProgresoTramo: String?

    /// Parciales por kilómetro ya anunciados, para la tabla "PARCIALES".
    @Published var parciales: [ParcialKm] = []

    /// Avance de tramos mixtos (distancia/tiempo): lógica pura en
    /// Shared, compartida con el motor del celu.
    private var progreso = ProgresoTramos(tramos: [])
    private var fechaInicioTramo: Date?
    private var fechaUltimaCorreccion: Date?

    // Splits: anuncio de cada kilómetro cumplido con el parcial.
    private var ultimoKmAnunciado = 0
    private var tiempoAlUltimoKm: TimeInterval = 0

    // Avisos por distancia: para cada aviso, el próximo km donde suena.
    private var avisosKm: [AvisoKm] = []
    private var proximoDisparoKm: [UUID: Double] = [:]

    /// Huella del entrenamiento con el que ARRANCÓ esta sesión: si el
    /// plan cambia en el iPhone a mitad de carrera, el cumplimiento se
    /// marca sobre lo que efectivamente corriste, no sobre lo nuevo.
    private var huellaSesion: String?

    func iniciar(plan: Plan) {
        huellaSesion = plan.huellaEntrenamiento
        progreso = ProgresoTramos(tramos: plan.tramosActivos)
        fechaInicioTramo = nil
        fechaUltimaCorreccion = nil
        supervisorCorreccion.reiniciar()
        tramoActual = progreso.tramoActual
        ultimoKmAnunciado = 0
        tiempoAlUltimoKm = 0
        tramosDelPlan = progreso.tramos
        indiceActual = 0
        textoProgresoTramo = nil
        parciales = []
        avisosKm = plan.avisosKmActivos
        proximoDisparoKm = Dictionary(uniqueKeysWithValues: avisosKm.map { ($0.id, $0.kilometro) })
    }

    /// Llamar ANTES de detener (detener borra el estado): si el plan de
    /// tramos se recorrió entero y la carrera se guarda, el
    /// entrenamiento queda CUMPLIDO. Carrera libre (0 tramos) o
    /// abandono a mitad de plan no marcan nada — criterio conservador.
    /// ¿Se recorrió la estructura ENTERA del plan de esta sesión? (D1:
    /// esto decide cumplido vs parcial en el iPhone). Consultarlo ANTES
    /// de detener() — detener borra el estado.
    var estructuraCompleta: Bool {
        debeMarcarCumplido(tramosTotales: tramosDelPlan.count,
                           indiceAlcanzado: indiceActual)
    }

    func marcarCumplimientoSiCorresponde() {
        guard estructuraCompleta, let huella = huellaSesion else { return }
        EstadoPlanWatch.compartido.marcarCumplida(huella: huella)
    }

    func detener() {
        huellaSesion = nil
        supervisorCorreccion.reiniciar()
        progreso = ProgresoTramos(tramos: [])
        tramoActual = nil
        fechaInicioTramo = nil
        ultimoKmAnunciado = 0
        tiempoAlUltimoKm = 0
        tramosDelPlan = []
        indiceActual = 0
        textoProgresoTramo = nil
        parciales = []
        avisosKm = []
        proximoDisparoKm = [:]
    }

    /// Progreso del tramo actual con la contabilidad REAL del avance
    /// (inicio del tramo según ProgresoTramos, no suma de prefijos).
    private func textoProgreso(distanciaMetros: Double, tiempoActivo: TimeInterval) -> String? {
        guard let tramo = progreso.tramoActual else { return nil }
        if tramo.esPorTiempo {
            let hecho = max(0, tiempoActivo - progreso.inicioTiempoActivo)
            let segundos = Int(hecho)
            return "\(segundos / 60):" + String(format: "%02d", segundos % 60)
                + " / \(duracionTexto(tramo.duracionSegundos ?? 0))"
        }
        let recorrido = max(0, distanciaMetros - progreso.inicioDistanciaMetros) / 1000
        return String(localized: "\(Unidades.distancia(km: recorrido, decimales: 2, conUnidad: false)) / \(Unidades.distancia(km: tramo.kilometros, decimales: 1))")
    }

    /// Lo llama Entrenamiento una vez por segundo. tiempoActivo es el del
    /// builder (descuenta pausas).
    func chequear(distanciaMetros: Double, ritmoActualSegKm: Int?, tiempoActivo: TimeInterval) {
        guard Reproductor.compartido.estado == .reproduciendo else { return }

        anunciarSplitSiCorresponde(distanciaMetros: distanciaMetros, tiempoActivo: tiempoActivo)
        dispararAvisosPorKm(kmActual: distanciaMetros / 1000)

        guard !progreso.tramos.isEmpty, !progreso.terminado else { return }

        textoProgresoTramo = textoProgreso(distanciaMetros: distanciaMetros,
                                           tiempoActivo: tiempoActivo)

        // El anuncio del primer tramo sale acá (con la música ya sonando)
        // y no en iniciar(), donde el audio todavía se está activando.
        guard let inicioTramo = fechaInicioTramo else {
            fechaInicioTramo = Date()
            Avisador.compartido.anunciar(anuncio(de: progreso.tramos[progreso.indice],
                                                 numero: progreso.indice + 1))
            return
        }

        // ¿Se completó el tramo actual? (un tick puede cerrar varios)
        let eventos = progreso.avanzar(distanciaMetros: distanciaMetros, tiempoActivo: tiempoActivo)
        if !eventos.isEmpty {
            indiceActual = progreso.indice
            tramoActual = progreso.tramoActual
            for evento in eventos {
                switch evento {
                case .cambioTramo(let nuevo):
                    fechaInicioTramo = Date()
                    fechaUltimaCorreccion = nil
                    Avisador.compartido.anunciar(anuncio(de: progreso.tramos[nuevo], numero: nuevo + 1))
                case .planCompletado:
                    Avisador.compartido.anunciar(String(localized: "Plan de tramos completado. ¡Bien ahí!"))
                }
            }
            return
        }

        // Corrección de ritmo, con todos los filtros. Build 54: además
        // de warm-up + 1/min + margen, la desviación debe SOSTENERSE
        // (varios ticks seguidos en la misma dirección) — una lectura
        // suelta jamás genera un "aflojá"/"apurá".
        guard let tramo = tramoActual else {
            supervisorCorreccion.reiniciar()
            return
        }
        let ahora = Date()
        let decision = supervisorCorreccion.evaluar(
            ritmoSegKm: ritmoActualSegKm,
            minSegKm: tramo.ritmoMinSegKm, maxSegKm: tramo.ritmoMaxSegKm,
            segundosEnTramo: ahora.timeIntervalSince(inicioTramo),
            segundosDesdeUltima: fechaUltimaCorreccion.map { ahora.timeIntervalSince($0) })

        switch decision {
        case .callar:
            return
        case .aflojar(let objetivo):
            fechaUltimaCorreccion = ahora
            Avisador.compartido.anunciar(String(localized:
                "Vas a \(ritmoParaHablar(ritmoActualSegKm ?? objetivo)). Objetivo \(ritmoParaHablar(objetivo)). Aflojá un poco."))
        case .apurar(let objetivo):
            fechaUltimaCorreccion = ahora
            Avisador.compartido.anunciar(String(localized:
                "Vas a \(ritmoParaHablar(ritmoActualSegKm ?? objetivo)). Objetivo \(ritmoParaHablar(objetivo)). Apurá un poco."))
        }
    }

    /// La decisión de cuándo corregir vive en Shared (pura y testeable).
    private var supervisorCorreccion = SupervisorCorreccionRitmo()

    /// "Kilómetro 5: 4 12 el último." — una vez por km cumplido, con el
    /// parcial de ese kilómetro (tiempo activo, sin contar pausas).
    private func anunciarSplitSiCorresponde(distanciaMetros: Double, tiempoActivo: TimeInterval) {
        // El hito es la unidad del corredor (ver la voz del iPhone).
        let porHito = Unidades.metrosPorHito()
        let hito = Int(distanciaMetros / porHito)
        guard hito > ultimoKmAnunciado, tiempoActivo > 0 else { return }
        let parcial = tiempoActivo - tiempoAlUltimoKm
        let cubiertos = hito - ultimoKmAnunciado  // por si se saltó un chequeo
        ultimoKmAnunciado = hito
        tiempoAlUltimoKm = tiempoActivo
        let nombre = Unidades.hitoHablado(numero: hito)
        guard cubiertos == 1, parcial > 60, parcial < 30 * 60 else {
            Avisador.compartido.anunciar(String(localized: "\(nombre)."))
            return
        }
        parciales.append(ParcialKm(km: hito, segundos: Int(parcial)))
        let segPorKm = Unidades.ritmoCanonico(segundosPorUnidad: Int(parcial))
        Avisador.compartido.anunciar(String(localized:
            "\(nombre): \(ritmoParaHablar(segPorKm)) el último."))
    }

    /// Avisos configurados por distancia ("en el km 5", "cada 3 km"):
    /// cada uno guarda su próximo punto de disparo; los repetidos lo
    /// corren hacia adelante al sonar, los únicos se apagan.
    private func dispararAvisosPorKm(kmActual: Double) {
        for aviso in avisosKm {
            guard let objetivo = proximoDisparoKm[aviso.id], kmActual >= objetivo else { continue }
            if let cada = aviso.cadaKm, cada > 0 {
                proximoDisparoKm[aviso.id] = objetivo + cada
            } else {
                proximoDisparoKm[aviso.id] = nil
            }
            Avisador.compartido.anunciar(aviso.texto)
        }
    }

    private func anuncio(de tramo: Tramo, numero: Int) -> String {
        anuncioDeTramo(tramo, numero: numero)
    }
}
