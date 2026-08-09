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

    /// Problemas de persistencia que el usuario TIENE que ver (plan
    /// ilegible al arrancar, guardado fallando): antes eran try? mudos y
    /// se podía perder el plan entero sin ningún aviso.
    @Published var mensajeProblema: String?

    private static var urlDocumentos: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private static var urlPlan: URL {
        urlDocumentos.appendingPathComponent("plan.json")
    }

    /// El plan legacy V1, expuesto para el cutover de AlmacenStore
    /// (read-only desde afuera: nadie más escribe este archivo).
    static var urlPlanLegacy: URL { urlPlan }

    static var urlCarpetaPistas: URL {
        urlDocumentos.appendingPathComponent("Pistas", isDirectory: true)
    }

    init() {
        // Distinguir "no existe" (primera apertura) de "existe pero no
        // se puede leer/decodificar" (I/O o corrupción): el segundo caso
        // preserva el archivo y avisa — antes se colapsaban y una falla
        // de lectura arrancaba vacío en silencio.
        let existia = FileManager.default.fileExists(atPath: Self.urlPlan.path)
        if let datos = try? Data(contentsOf: Self.urlPlan),
           let cargado = try? JSONDecoder().decode(Plan.self, from: datos) {
            plan = cargado
        } else if !existia {
            plan = .vacio
        } else {
            // plan.json existe pero no se puede leer: preservarlo con
            // otro nombre (evidencia recuperable) en vez de dejarlo
            // para que el próximo guardado lo pise, y avisar. Antes
            // esto arrancaba con plan vacío en silencio total.
            plan = .vacio
            let copia = Self.urlDocumentos.appendingPathComponent("plan-corrupto.json")
            try? FileManager.default.removeItem(at: copia)
            try? FileManager.default.moveItem(at: Self.urlPlan, to: copia)
            mensajeProblema = "No pude leer el plan guardado en este teléfono (quedó una copia como plan-corrupto.json). Podés recuperarlo con «Restaurar plan desde iCloud» en Perfil."
        }
        try? FileManager.default.createDirectory(
            at: Self.urlCarpetaPistas, withIntermediateDirectories: true)
        recalcularDuraciones()
        // Fase A del dominio V2: materializar el almacén nuevo como
        // ensayo regenerable. La app sigue corriendo sobre el Plan
        // legacy; nada lo consume hasta el cutover de Fase B.
        Self.migrarADominioV2SiHaceFalta(planV1: plan, en: Self.urlDominioV2)
    }

    static var urlDominioV2: URL {
        urlDocumentos.appendingPathComponent("dominio-v2.json")
    }

    /// Idempotente y segura: un almacén ACTIVADO (fuente de verdad
    /// desde Fase B) no se toca jamás; mientras no esté activado es un
    /// ensayo que se regenera desde el legacy para no quedar viejo.
    /// La huella cumplida vive en el reloj (no acá): el programado
    /// migrado nace pendiente; el puente de huella se resuelve en
    /// Fase E del lado del watch.
    static func migrarADominioV2SiHaceFalta(planV1: Plan, en url: URL, fecha: Date = Date()) {
        if let datos = try? Data(contentsOf: url),
           let existente = try? JSONDecoder().decode(AlmacenV2.self, from: datos),
           existente.activado {
            return
        }
        let almacen = MigracionV2.migrar(planV1: planV1, huellaCumplida: nil, fecha: fecha)
        if let datos = try? JSONEncoder().encode(almacen) {
            try? datos.write(to: url, options: .atomic)
        }
    }

    private func guardar() {
        do {
            let datos = try JSONEncoder().encode(plan)
            try datos.write(to: Self.urlPlan, options: .atomic)
        } catch {
            // Disco lleno o similar: si esto falla mudo, el usuario
            // edita durante días y lo pierde todo al cerrar la app.
            mensajeProblema = "No pude guardar el plan en el teléfono: \(error.localizedDescription)"
        }
        // Respaldo en el iCloud del usuario (con demora anti-tipeo).
        CuentaStore.compartida.respaldarConDemora(plan)
    }

    // MARK: - Pistas

    func urlDePista(_ nombre: String) -> URL {
        Self.urlCarpetaPistas.appendingPathComponent(nombre)
    }

    var duracionTotal: TimeInterval {
        plan.pistas.compactMap { duraciones[$0] }.reduce(0, +)
    }

    /// Copia los archivos elegidos en el picker a Documents/Pistas y los
    /// agrega al final de la cola. El URL del picker es temporal y con
    /// permiso restringido: hay que abrirlo con security scope y copiarlo ya.
    func importar(urls: [URL]) {
        var fallidas: [String] = []
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
                // Copia fallida (típico: MP3 en iCloud Drive sin
                // descargar, o disco lleno): la pista no se agrega, y
                // ahora SE AVISA — antes desaparecía en silencio.
                fallidas.append(url.lastPathComponent)
            }
        }
        if !fallidas.isEmpty {
            mensajeProblema = "No pude importar: \(fallidas.joined(separator: ", ")). Si están en iCloud Drive, abrilas primero en la app Archivos para descargarlas."
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
