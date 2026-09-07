import Foundation

/// Dos generaciones locales del dominio completo. La copia anterior se
/// escribe antes de reemplazar el principal; sólo contiene JSON validado.
/// No es un respaldo externo: desinstalar la app elimina ambas copias.
final class PersistenciaAlmacen {
    struct Carga {
        var almacen: AlmacenV2
        var recuperada = false
        var necesitaGuardar = false
    }

    enum Problema: LocalizedError {
        case versionNoCompatible
        case sinCopiaLegible

        var errorDescription: String? {
            switch self {
            case .versionNoCompatible:
                return String(localized: "Estos datos requieren otra versión de Maratonia. Actualizá la app. Los archivos originales están protegidos.")
            case .sinCopiaLegible:
                return String(localized: "No pude leer tus datos ni una copia local válida. Conservé los archivos originales; no reinstales la app. Podés reintentar la lectura.")
            }
        }
    }

    let url: URL
    var urlCopia: URL { Self.urlCopia(de: url) }
    private var principalPreservado = false

    init(url: URL) { self.url = url }

    static func urlCopia(de url: URL) -> URL {
        url.deletingPathExtension().appendingPathExtension("backup.json")
    }

    private struct Cabecera: Decodable { var versionEsquema: Int }

    static func decodificar(_ datos: Data) throws -> AlmacenV2 {
        let version = try JSONDecoder().decode(Cabecera.self, from: datos).versionEsquema
        guard version == AlmacenV2().versionEsquema else {
            throw Problema.versionNoCompatible
        }
        return try JSONDecoder().decode(AlmacenV2.self, from: datos)
    }

    /// Sólo ENOENT es instalación nueva. Permisos, protección de datos y
    /// otros errores de lectura se propagan; no habilitan una migración.
    private func leerSiExiste(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch CocoaError.fileReadNoSuchFile { return nil }
    }

    func cargar(urlLegacy: URL, fecha: Date) throws -> Carga {
        principalPreservado = false
        let principal = try leerSiExiste(url)
        if let principal {
            do {
                var almacen = try Self.decodificar(principal)
                let activar = !almacen.activado
                almacen.activado = true
                return Carga(almacen: almacen, necesitaGuardar: activar)
            } catch let error as Problema {
                // Nunca recuperar una copia antigua sobre un esquema futuro.
                throw error
            } catch is DecodingError {
                // JSON truncado o inválido: sólo una copia válida permite seguir.
            }
        }

        if let copia = try leerSiExiste(urlCopia) {
            let almacen: AlmacenV2
            do { almacen = try Self.decodificar(copia) }
            catch let error as Problema { throw error }
            catch { throw Problema.sinCopiaLegible }
            if let principal {
                let evidencia = url.deletingPathExtension()
                    .appendingPathExtension("corrupto-\(UUID().uuidString).json")
                try principal.write(to: evidencia, options: .atomic)
                principalPreservado = true
            }
            var recuperado = almacen
            recuperado.activado = true
            return Carga(almacen: recuperado, recuperada: true, necesitaGuardar: true)
        }
        guard principal == nil else { throw Problema.sinCopiaLegible }

        let legacy = try leerSiExiste(urlLegacy).map {
            try JSONDecoder().decode(Plan.self, from: $0)
        }
        var nuevo = legacy.map {
            MigracionV2.migrar(planV1: $0, huellaCumplida: nil, fecha: fecha)
        } ?? AlmacenV2()
        nuevo.activado = true
        return Carga(almacen: nuevo, necesitaGuardar: true)
    }

    func guardar(_ almacen: AlmacenV2) throws {
        let nuevos = try JSONEncoder().encode(almacen)
        _ = try Self.decodificar(nuevos)
        if let anteriores = try leerSiExiste(url) {
            if !principalPreservado {
                _ = try Self.decodificar(anteriores)
                try anteriores.write(to: urlCopia, options: .atomic)
            }
        } else if try leerSiExiste(urlCopia) == nil {
            // La primera escritura también deja una copia recuperable.
            try nuevos.write(to: urlCopia, options: .atomic)
        }
        try nuevos.write(to: url, options: .atomic)
        principalPreservado = false
    }
}
