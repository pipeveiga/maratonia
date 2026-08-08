import Foundation
import AVFoundation
import SwiftUI

// Estado central de la app iOS: tiene el Plan en memoria, lo guarda en disco
// ante cada cambio, y maneja los archivos MP3 (importar, borrar, duración).
// El plan se guarda como JSON en Documents/plan.json y las pistas en
// Documents/Pistas/. Al abrir la app se recupera todo.

final class PlanStore: ObservableObject {

    @Published var plan: Plan {
        didSet { guardar() }
    }

    /// Duración en segundos de cada pista, por nombre de archivo.
    @Published var duraciones: [String: TimeInterval] = [:]

    private static var urlDocumentos: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var urlPlan: URL {
        urlDocumentos.appendingPathComponent("plan.json")
    }

    static var urlCarpetaPistas: URL {
        urlDocumentos.appendingPathComponent("Pistas", isDirectory: true)
    }

    init() {
        if let datos = try? Data(contentsOf: Self.urlPlan),
           let cargado = try? JSONDecoder().decode(Plan.self, from: datos) {
            plan = cargado
        } else {
            plan = .vacio
        }
        try? FileManager.default.createDirectory(
            at: Self.urlCarpetaPistas, withIntermediateDirectories: true)
        recalcularDuraciones()
    }

    private func guardar() {
        if let datos = try? JSONEncoder().encode(plan) {
            try? datos.write(to: Self.urlPlan, options: .atomic)
        }
        // Respaldo en el iCloud del usuario (con demora anti-tipeo).
        CuentaStore.compartida.respaldarConDemora(plan)
    }

    // MARK: - Pistas

    func urlDePista(_ nombre: String) -> URL {
        Self.urlCarpetaPistas.appendingPathComponent(nombre)
    }

    func pistaExiste(_ nombre: String) -> Bool {
        FileManager.default.fileExists(atPath: urlDePista(nombre).path)
    }

    var duracionTotal: TimeInterval {
        plan.pistas.compactMap { duraciones[$0] }.reduce(0, +)
    }

    /// Copia los archivos elegidos en el picker a Documents/Pistas y los
    /// agrega al final de la cola. El URL del picker es temporal y con
    /// permiso restringido: hay que abrirlo con security scope y copiarlo ya.
    func importar(urls: [URL]) {
        for url in urls {
            let conAcceso = url.startAccessingSecurityScopedResource()
            defer { if conAcceso { url.stopAccessingSecurityScopedResource() } }

            var nombre = url.lastPathComponent
            var destino = urlDePista(nombre)
            var intento = 2
            while FileManager.default.fileExists(atPath: destino.path) {
                let base = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension
                nombre = "\(base)-\(intento).\(ext)"
                destino = urlDePista(nombre)
                intento += 1
            }

            do {
                try FileManager.default.copyItem(at: url, to: destino)
                plan.pistas.append(nombre)
                duraciones[nombre] = duracion(de: destino)
            } catch {
                // Si la copia falla, la pista no se agrega; no hay nada que limpiar.
            }
        }
    }

    func borrarPistas(en offsets: IndexSet) {
        for indice in offsets {
            let nombre = plan.pistas[indice]
            try? FileManager.default.removeItem(at: urlDePista(nombre))
            duraciones[nombre] = nil
        }
        plan.pistas.remove(atOffsets: offsets)
    }

    func moverPistas(de origen: IndexSet, a destino: Int) {
        plan.pistas.move(fromOffsets: origen, toOffset: destino)
    }

    private func duracion(de url: URL) -> TimeInterval? {
        (try? AVAudioPlayer(contentsOf: url))?.duration
    }

    private func recalcularDuraciones() {
        for nombre in plan.pistas {
            duraciones[nombre] = duracion(de: urlDePista(nombre))
        }
    }
}

/// "3:25" o "1:02:15" para las duraciones de pistas y de la cola.
func formatearDuracion(_ segundos: TimeInterval) -> String {
    let total = Int(segundos.rounded())
    let horas = total / 3600
    let minutos = (total % 3600) / 60
    let resto = total % 60
    if horas > 0 {
        return String(format: "%d:%02d:%02d", horas, minutos, resto)
    }
    return String(format: "%d:%02d", minutos, resto)
}
