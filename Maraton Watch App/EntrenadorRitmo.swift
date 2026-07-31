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

final class EntrenadorRitmo: ObservableObject {
    static let compartido = EntrenadorRitmo()

    @Published var tramoActual: Tramo?

    private var tramos: [Tramo] = []
    private var indice = 0
    private var fechaInicioTramo: Date?
    private var fechaUltimaCorreccion: Date?
    private let margenSegKm = 5

    func iniciar(plan: Plan) {
        tramos = plan.tramosActivos
        indice = 0
        fechaInicioTramo = nil
        fechaUltimaCorreccion = nil
        tramoActual = tramos.first
    }

    func detener() {
        tramos = []
        tramoActual = nil
        fechaInicioTramo = nil
    }

    /// Lo llama Entrenamiento una vez por segundo.
    func chequear(distanciaMetros: Double, ritmoActualSegKm: Int?) {
        guard !tramos.isEmpty, indice < tramos.count else { return }
        guard Reproductor.compartido.estado == .reproduciendo else { return }

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
