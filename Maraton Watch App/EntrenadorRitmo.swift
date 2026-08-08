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

    /// Parciales por kilómetro ya anunciados, para la tabla "PARCIALES".
    @Published var parciales: [ParcialKm] = []

    private var tramos: [Tramo] = []
    private var indice = 0
    private var fechaInicioTramo: Date?
    private var fechaUltimaCorreccion: Date?
    private let margenSegKm = 5

    // Splits: anuncio de cada kilómetro cumplido con el parcial.
    private var ultimoKmAnunciado = 0
    private var tiempoAlUltimoKm: TimeInterval = 0

    // Avisos por distancia: para cada aviso, el próximo km donde suena.
    private var avisosKm: [AvisoKm] = []
    private var proximoDisparoKm: [UUID: Double] = [:]

    func iniciar(plan: Plan) {
        tramos = plan.tramosActivos
        indice = 0
        fechaInicioTramo = nil
        fechaUltimaCorreccion = nil
        tramoActual = tramos.first
        ultimoKmAnunciado = 0
        tiempoAlUltimoKm = 0
        tramosDelPlan = tramos
        indiceActual = 0
        parciales = []
        avisosKm = plan.avisosKmActivos
        proximoDisparoKm = Dictionary(uniqueKeysWithValues: avisosKm.map { ($0.id, $0.kilometro) })
    }

    func detener() {
        tramos = []
        tramoActual = nil
        fechaInicioTramo = nil
        ultimoKmAnunciado = 0
        tiempoAlUltimoKm = 0
        tramosDelPlan = []
        indiceActual = 0
        parciales = []
        avisosKm = []
        proximoDisparoKm = [:]
    }

    /// Lo llama Entrenamiento una vez por segundo. tiempoActivo es el del
    /// builder (descuenta pausas).
    func chequear(distanciaMetros: Double, ritmoActualSegKm: Int?, tiempoActivo: TimeInterval) {
        guard Reproductor.compartido.estado == .reproduciendo else { return }

        anunciarSplitSiCorresponde(distanciaMetros: distanciaMetros, tiempoActivo: tiempoActivo)
        dispararAvisosPorKm(kmActual: distanciaMetros / 1000)

        guard !tramos.isEmpty, indice < tramos.count else { return }

        // El anuncio del primer tramo sale acá (con la música ya sonando)
        // y no en iniciar(), donde el audio todavía se está activando.
        guard let inicioTramo = fechaInicioTramo else {
            fechaInicioTramo = Date()
            Avisador.compartido.anunciar(anuncio(de: tramos[indice], numero: indice + 1))
            return
        }

        // ¿Se completó el tramo actual?
        let finTramoMetros = tramos.prefix(indice + 1).reduce(0) { $0 + $1.kilometros * 1000 }
        if distanciaMetros >= finTramoMetros {
            indice += 1
            indiceActual = indice
            if indice < tramos.count {
                tramoActual = tramos[indice]
                fechaInicioTramo = Date()
                fechaUltimaCorreccion = nil
                Avisador.compartido.anunciar(anuncio(de: tramos[indice], numero: indice + 1))
            } else {
                tramoActual = nil
                Avisador.compartido.anunciar("Plan de tramos completado. ¡Bien ahí!")
            }
            return
        }

        // Corrección de ritmo, con todos los filtros.
        guard let ritmo = ritmoActualSegKm, let tramo = tramoActual else { return }
        guard Date().timeIntervalSince(inicioTramo) >= 45 else { return }
        if let ultima = fechaUltimaCorreccion, Date().timeIntervalSince(ultima) < 60 { return }

        if let rapido = tramo.ritmoMinSegKm, ritmo < rapido - margenSegKm {
            fechaUltimaCorreccion = Date()
            Avisador.compartido.anunciar(
                "Vas a \(ritmoParaHablar(ritmo)). Objetivo \(ritmoParaHablar(rapido)). Aflojá un poco.")
        } else if let lento = tramo.ritmoMaxSegKm, ritmo > lento + margenSegKm {
            fechaUltimaCorreccion = Date()
            Avisador.compartido.anunciar(
                "Vas a \(ritmoParaHablar(ritmo)). Objetivo \(ritmoParaHablar(lento)). Apurá un poco.")
        }
    }

    /// "Kilómetro 5: 4 12 el último." — una vez por km cumplido, con el
    /// parcial de ese kilómetro (tiempo activo, sin contar pausas).
    private func anunciarSplitSiCorresponde(distanciaMetros: Double, tiempoActivo: TimeInterval) {
        let km = Int(distanciaMetros / 1000)
        guard km > ultimoKmAnunciado, tiempoActivo > 0 else { return }
        let parcial = tiempoActivo - tiempoAlUltimoKm
        let kmsCubiertos = km - ultimoKmAnunciado  // por si se saltó un chequeo
        ultimoKmAnunciado = km
        tiempoAlUltimoKm = tiempoActivo
        guard kmsCubiertos == 1, parcial > 60, parcial < 30 * 60 else {
            Avisador.compartido.anunciar("Kilómetro \(km).")
            return
        }
        parciales.append(ParcialKm(km: km, segundos: Int(parcial)))
        Avisador.compartido.anunciar(
            "Kilómetro \(km): \(ritmoParaHablar(Int(parcial))) el último.")
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
        let km = tramo.kilometros == tramo.kilometros.rounded()
            ? "\(Int(tramo.kilometros))"
            : String(format: "%.1f", tramo.kilometros)
        var texto = "Tramo \(numero): \(tramo.nombre). \(km) kilómetros"
        switch (tramo.ritmoMinSegKm, tramo.ritmoMaxSegKm) {
        case let (rapido?, lento?):
            texto += ", entre \(ritmoParaHablar(rapido)) y \(ritmoParaHablar(lento)) por kilómetro."
        case let (nil, lento?):
            texto += ", a \(ritmoParaHablar(lento)) por kilómetro o mejor."
        case let (rapido?, nil):
            texto += ", sin pasar de \(ritmoParaHablar(rapido)) por kilómetro."
        default:
            texto += ", a ritmo libre."
        }
        return texto
    }
}
