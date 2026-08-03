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
// Mientras el asistente habla, la música se FRENA (no se baja) y sigue
// de donde quedó al terminar — sin tocar el estado de la sesión.

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

    func iniciar(plan: Plan) {
        cronograma = plan.cronograma(duracionMaximaMinutos: Self.horizonteMinutos)
        disparados = []
        colaPorHablar = []
        estaHablando = false
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

    /// Canal general para hablar con la secuencia completa de un aviso
    /// (háptico + ducking + voz + restaurar volumen). Lo usan el botón de
    /// prueba y el entrenador de ritmo.
    func anunciar(_ texto: String) {
        WKInterfaceDevice.current().play(.notification)
        colaPorHablar.append(texto)
        if !estaHablando {
            hablarSiguiente()
        }
    }

    /// Aviso de prueba inmediato, para diagnosticar sin esperar al cronograma.
    func probar() {
        anunciar("Probando avisos: uno, dos, tres.")
    }

    // MARK: - Voz y ducking

    private func hablarSiguiente() {
        guard !colaPorHablar.isEmpty else { return }
        estaHablando = true
        if Reproductor.compartido.modoMusicaExterna {
            // La música es de otra app (Spotify): activamos una sesión que
            // le baja el volumen (.duckOthers) mientras dura la voz.
            let sesion = AVAudioSession.sharedInstance()
            try? sesion.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
            try? sesion.setActive(true)
        } else {
            Reproductor.compartido.silenciarParaVoz()
        }
        let utterance = AVSpeechUtterance(string: colaPorHablar.removeFirst())
        utterance.voice = Self.vozEspanol
        utterance.preUtteranceDelay = 0.3  // pequeño respiro tras frenar la música
        sintetizador.speak(utterance)
    }

    private func terminoDeHablar() {
        if !colaPorHablar.isEmpty {
            hablarSiguiente()  // la música ya está frenada; encadena el siguiente
        } else {
            estaHablando = false
            if Reproductor.compartido.modoMusicaExterna {
                // Soltar la sesión avisando: Spotify recupera su volumen.
                try? AVAudioSession.sharedInstance().setActive(
                    false, options: .notifyOthersOnDeactivation)
            } else {
                Reproductor.compartido.reanudarTrasVoz()
            }
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
            contenido.title = "Maratonia"
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
