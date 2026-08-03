import Foundation
import AVFoundation
import MediaPlayer

// El reproductor del reloj. Encadena los MP3 de la cola con
// AVAudioPlayerDelegate, vuelve a la primera pista al terminar la última
// (loop infinito: nada de silencio en el km 30), y publica la sesión en
// MPNowPlayingInfoCenter para que funcionen los controles nativos del
// reloj sin abrir la app.
//
// El tiempo transcurrido NO se acumula con un Timer: la fuente de verdad
// es el reloj del sistema (fecha de reanudación + acumulado previo).
// El Timer de 1 s solo refresca la UI. La pausa congela el tiempo.

final class Reproductor: NSObject, ObservableObject {
    static let compartido = Reproductor()

    enum Estado {
        case detenido, reproduciendo, pausado
    }

    @Published var estado: Estado = .detenido
    @Published var nombrePistaActual = ""
    @Published var tiempoTranscurrido: TimeInterval = 0
    @Published var mensajeError: String?

    /// Pausa manual de SOLO la música (página Música): el cronómetro,
    /// los avisos y el entrenamiento siguen corriendo normalmente.
    @Published var musicaSilenciada = false

    private var pistas: [String] = []
    private var urlDe: ((String) -> URL)?
    private var indice = 0
    private var player: AVAudioPlayer?
    private var intentosFallidos = 0

    private var fechaReanudacion: Date?
    private var acumuladoPrevio: TimeInterval = 0
    private var timerUI: Timer?

    /// Tiempo de carrera real: lo acumulado antes de la última pausa más
    /// lo corrido desde la última reanudación. Congelado durante la pausa.
    var transcurridoActual: TimeInterval {
        acumuladoPrevio + (fechaReanudacion.map { Date().timeIntervalSince($0) } ?? 0)
    }

    // MARK: - Control

    func iniciar(plan: Plan, urlDe: @escaping (String) -> URL) {
        let disponibles = plan.pistas.filter {
            FileManager.default.fileExists(atPath: urlDe($0).path)
        }
        guard !disponibles.isEmpty else {
            mensajeError = "No hay ninguna pista en el reloj todavía."
            return
        }
        pistas = disponibles
        self.urlDe = urlDe
        indice = 0
        intentosFallidos = 0
        acumuladoPrevio = 0
        fechaReanudacion = nil
        mensajeError = nil

        let sesion = AVAudioSession.sharedInstance()
        do {
            try sesion.setCategory(.playback, mode: .default, policy: .longFormAudio, options: [])
        } catch {
            mensajeError = "No pude configurar el audio: \(error.localizedDescription)"
            return
        }

        // En watchOS la activación es asíncrona: si no hay auriculares
        // Bluetooth conectados, el sistema muestra el selector para elegirlos.
        sesion.activate(options: []) { [weak self] exito, error in
            DispatchQueue.main.async {
                guard let self else { return }
                guard exito else {
                    self.mensajeError = "No se activó el audio: \(error?.localizedDescription ?? "conectá los auriculares")"
                    return
                }
                self.configurarComandosRemotos()
                Avisador.compartido.iniciar(plan: plan)
                self.fechaReanudacion = Date()
                self.estado = .reproduciendo
                self.reproducirPistaActual()
                self.iniciarTimerUI()
            }
        }
    }

    func alternarPlayPausa() {
        switch estado {
        case .reproduciendo: pausar()
        case .pausado: reanudar()
        case .detenido: break
        }
    }

    func pausar() {
        guard estado == .reproduciendo else { return }
        player?.pause()
        if let fecha = fechaReanudacion {
            acumuladoPrevio += Date().timeIntervalSince(fecha)
        }
        fechaReanudacion = nil
        estado = .pausado
        tiempoTranscurrido = transcurridoActual
        Avisador.compartido.pausar()
        Entrenamiento.compartido.pausar()  // congela también el workout
        actualizarNowPlaying()
    }

    func reanudar() {
        guard estado == .pausado else { return }
        if !musicaSilenciada {
            player?.play()
        }
        fechaReanudacion = Date()
        estado = .reproduciendo
        Avisador.compartido.reanudar(transcurrido: transcurridoActual)
        Entrenamiento.compartido.reanudar()
        actualizarNowPlaying()
    }

    func siguiente() {
        guard estado != .detenido else { return }
        avanzarPista()
    }

    /// Frena SOLO la música mientras habla el asistente. No toca el estado
    /// de la sesión: el cronómetro, los avisos y el tracking siguen.
    func silenciarParaVoz() {
        guard estado == .reproduciendo else { return }
        player?.pause()
    }

    /// La contraparte: al terminar la voz, la música sigue de donde quedó
    /// (salvo que vos la hayas silenciado a mano desde la página Música).
    func reanudarTrasVoz() {
        guard estado == .reproduciendo, !musicaSilenciada else { return }
        player?.play()
    }

    /// Botón de la página Música: pausa/reanuda la música sola, sin tocar
    /// cronómetro, avisos ni entrenamiento.
    func alternarSoloMusica() {
        guard estado != .detenido else { return }
        if musicaSilenciada {
            musicaSilenciada = false
            if estado == .reproduciendo && !Avisador.compartido.estaHablando {
                player?.play()
            }
        } else {
            musicaSilenciada = true
            player?.pause()
        }
        actualizarNowPlaying()
    }

    func detener() {
        Avisador.compartido.detener()
        player?.stop()
        player = nil
        timerUI?.invalidate()
        timerUI = nil
        fechaReanudacion = nil
        acumuladoPrevio = 0
        tiempoTranscurrido = 0
        nombrePistaActual = ""
        musicaSilenciada = false
        estado = .detenido
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: - Cola

    private func reproducirPistaActual() {
        guard let urlDe, !pistas.isEmpty else { return }
        let nombre = pistas[indice]
        do {
            let nuevo = try AVAudioPlayer(contentsOf: urlDe(nombre))
            nuevo.delegate = self
            nuevo.play()
            // En pausa, con el asistente hablando, o con la música
            // silenciada a mano, la pista queda lista pero frenada.
            if estado == .pausado || Avisador.compartido.estaHablando || musicaSilenciada {
                nuevo.pause()
            }
            player = nuevo
            nombrePistaActual = nombre
            intentosFallidos = 0
            actualizarNowPlaying()
        } catch {
            // Pista ilegible: saltarla para no frenar la corrida. Si fallan
            // todas, frenar del todo en vez de ciclar infinitamente.
            intentosFallidos += 1
            if intentosFallidos < pistas.count {
                avanzarPista()
            } else {
                mensajeError = "Ninguna pista se pudo reproducir."
                detener()
            }
        }
    }

    private func avanzarPista() {
        indice = (indice + 1) % pistas.count  // al terminar la última, vuelve a la primera
        reproducirPistaActual()
    }

    // MARK: - UI y Now Playing

    private func iniciarTimerUI() {
        timerUI?.invalidate()
        timerUI = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.tiempoTranscurrido = self.transcurridoActual
                if self.estado == .reproduciendo {
                    Avisador.compartido.chequear(transcurrido: self.transcurridoActual)
                }
            }
        }
    }

    private func configurarComandosRemotos() {
        let centro = MPRemoteCommandCenter.shared()
        centro.playCommand.removeTarget(nil)
        centro.pauseCommand.removeTarget(nil)
        centro.togglePlayPauseCommand.removeTarget(nil)
        centro.nextTrackCommand.removeTarget(nil)

        centro.playCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.reanudar() }
            return .success
        }
        centro.pauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.pausar() }
            return .success
        }
        centro.togglePlayPauseCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.alternarPlayPausa() }
            return .success
        }
        centro.nextTrackCommand.addTarget { [weak self] _ in
            DispatchQueue.main.async { self?.siguiente() }
            return .success
        }
    }

    private func actualizarNowPlaying() {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: nombreLegible(nombrePistaActual),
            MPMediaItemPropertyArtist: "Maratón",
            MPNowPlayingInfoPropertyPlaybackRate: estado == .reproduciendo ? 1.0 : 0.0,
        ]
        if let player {
            info[MPMediaItemPropertyPlaybackDuration] = player.duration
            info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}

extension Reproductor: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        DispatchQueue.main.async {
            guard self.estado != .detenido else { return }
            self.avanzarPista()
        }
    }
}

/// "Cancion.mp3" -> "Cancion"
func nombreLegible(_ nombreArchivo: String) -> String {
    (nombreArchivo as NSString).deletingPathExtension
}

/// "45:07" o "2:05:33" para el tiempo transcurrido.
func formatearTiempo(_ segundos: TimeInterval) -> String {
    let total = Int(segundos)
    let horas = total / 3600
    let minutos = (total % 3600) / 60
    let resto = total % 60
    if horas > 0 {
        return String(format: "%d:%02d:%02d", horas, minutos, resto)
    }
    return String(format: "%d:%02d", minutos, resto)
}
