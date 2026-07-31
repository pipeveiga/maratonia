import Foundation
import AVFoundation
import UserNotifications
import WatchKit

// El sistema de avisos de la sesión. Tres canales por cada aviso:
// voz (AVSpeechSynthesizer en español), háptico, y notificación local
// (visible encima de Runna aunque no se escuche el audio).
//
// El chequeo lo dispara el Reproductor una vez por segundo con el tiempo
// real de carrera (que se congela en pausa). Cada aviso suena una sola
// vez; si dos caen en el mismo minuto, se hablan uno después del otro.
// El ducking es manual: se baja el volumen del propio AVAudioPlayer
// (nada de .duckOthers, que afecta a OTRAS apps, no a la propia).

final class Avisador: NSObject, ObservableObject {
    static let compartido = Avisador()

    @Published var proximoAviso: AvisoProgramado?

    /// true mientras hay voz sonando (el Reproductor lo usa para arrancar
    /// una pista nueva ya con el volumen bajo si justo coincide).
    private(set) var estaHablando = false

    private var cronograma: [AvisoProgramado] = []
    private var disparados: Set<Int> = []
    private var colaPorHablar: [String] = []
    private let sintetizador = AVSpeechSynthesizer()
    private var ajustarVolumen: ((Float, TimeInterval) -> Void)?

    private static let volumenBajo: Float = 0.15
    private static let horizonteMinutos = 12 * 60

    override private init() {
        super.init()
        sintetizador.delegate = self
        UNUserNotificationCenter.current().delegate = self
    }

    /// Voz en español: es-AR con fallback a es-MX y es-ES.
    static let vozEspanol: AVSpeechSynthesisVoice? =
        AVSpeechSynthesisVoice(language: "es-AR")
        ?? AVSpeechSynthesisVoice(language: "es-MX")
        ?? AVSpeechSynthesisVoice(language: "es-ES")

    static func pedirPermisoNotificaciones() {
        UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Ciclo de la sesión (lo llama el Reproductor)

    func iniciar(plan: Plan, ajustarVolumen: @escaping (Float, TimeInterval) -> Void) {
        cronograma = plan.cronograma(duracionMaximaMinutos: Self.horizonteMinutos)
        disparados = []
        colaPorHablar = []
        estaHablando = false
        self.ajustarVolumen = ajustarVolumen
        actualizarProximo()
        programarNotificaciones(desde: 0)
    }

    /// La pausa congela el cronograma: se cancelan las notificaciones
    /// pendientes (están agendadas por tiempo absoluto y quedarían
    /// desfasadas) y se reprograman al reanudar con los tiempos corridos.
    func pausar() {
        cancelarNotificaciones()
    }

    func reanudar(transcurrido: TimeInterval) {
        programarNotificaciones(desde: transcurrido)
    }

    func detener() {
        cancelarNotificaciones()
        sintetizador.stopSpeaking(at: .immediate)
        colaPorHablar = []
        estaHablando = false
        proximoAviso = nil
        ajustarVolumen = nil
        cronograma = []
        disparados = []
    }

    /// Una vez por segundo, con el tiempo real de carrera.
    func chequear(transcurrido: TimeInterval) {
        var huboNuevos = false
        for (indice, aviso) in cronograma.enumerated() where !disparados.contains(indice) {
            if transcurrido >= TimeInterval(aviso.minuto * 60) {
                disparados.insert(indice)
                colaPorHablar.append(aviso.texto)
                huboNuevos = true
            }
        }
        if huboNuevos {
            WKInterfaceDevice.current().play(.notification)
            if !estaHablando {
                hablarSiguiente()
            }
            actualizarProximo()
        }
    }

    /// Dispara la secuencia completa de un aviso ya mismo (háptico + duck +
    /// voz + volver el volumen). Para diagnosticar sin esperar al cronograma.
    func probar() {
        WKInterfaceDevice.current().play(.notification)
        colaPorHablar.append("Probando avisos: uno, dos, tres.")
        if !estaHablando {
            hablarSiguiente()
        }
    }

    // MARK: - Voz y ducking

    private func hablarSiguiente() {
        guard !colaPorHablar.isEmpty else { return }
        estaHablando = true
        ajustarVolumen?(Self.volumenBajo, 0.3)
        let utterance = AVSpeechUtterance(string: colaPorHablar.removeFirst())
        utterance.voice = Self.vozEspanol
        utterance.preUtteranceDelay = 0.4  // deja asentar el fade antes de hablar
        sintetizador.speak(utterance)
    }

    private func terminoDeHablar() {
        if !colaPorHablar.isEmpty {
            hablarSiguiente()  // el volumen ya está bajo; encadena el siguiente
        } else {
            estaHablando = false
            ajustarVolumen?(1.0, 0.8)
        }
    }

    private func actualizarProximo() {
        let siguiente = cronograma.enumerated()
            .first { !disparados.contains($0.offset) }?
            .element
        if proximoAviso != siguiente {
            proximoAviso = siguiente
        }
    }

    // MARK: - Notificaciones locales

    /// Agenda una notificación por cada aviso pendiente, con el tiempo que
    /// falta desde el momento actual de la carrera. Tope de 60: iOS ignora
    /// todo lo que pase de 64 pendientes.
    private func programarNotificaciones(desde transcurrido: TimeInterval) {
        let centro = UNUserNotificationCenter.current()
        centro.removeAllPendingNotificationRequests()
        var programadas = 0
        for (indice, aviso) in cronograma.enumerated() where !disparados.contains(indice) {
            let restante = TimeInterval(aviso.minuto * 60) - transcurrido
            guard restante > 1 else { continue }
            if programadas >= 60 { break }
            let contenido = UNMutableNotificationContent()
            contenido.title = "Maratón"
            contenido.body = aviso.texto
            let disparo = UNTimeIntervalNotificationTrigger(timeInterval: restante, repeats: false)
            centro.add(UNNotificationRequest(
                identifier: "aviso-\(indice)", content: contenido, trigger: disparo))
            programadas += 1
        }
    }

    private func cancelarNotificaciones() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}

extension Avisador: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.terminoDeHablar()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                           didCancel utterance: AVSpeechUtterance) {
        DispatchQueue.main.async {
            self.terminoDeHablar()
        }
    }
}

extension Avisador: UNUserNotificationCenterDelegate {
    /// Mostrar el banner aunque nuestra app esté al frente.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler:
                                @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner])
    }
}
