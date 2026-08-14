import Foundation
import Combine
import FirebaseAuth
import FirebaseFirestore

// LA CAPA DE CUENTA: única puerta entre el dominio y la nube.
//
// Regla: ninguna vista llama a Firestore. Todo pasa por acá. Si mañana
// la nube cambia (o se va), lo que se toca es este archivo.
//
// Y regla dos, la que define el diseño: **la nube representa el dominio
// que ya existe**. No hay un `CloudPlan` ni un `CloudProfile` paralelos
// que haya que mantener en sincronía con `AlmacenV2`; hay DTOs finos
// que serializan lo mismo que ya se guarda en disco. Un modelo paralelo
// es una segunda fuente de verdad, y una segunda fuente de verdad es
// una divergencia esperando el momento.
//
// FORMA DEL ESQUEMA (bajo `users/{uid}`):
//
//   users/{uid}                  perfil, preferencias, objetivo, versión
//   users/{uid}/planes/{id}      un doc por PlanUsuario (con sus semanas)
//   users/{uid}/sesiones/{id}    un doc por RegistroSesion
//   users/{uid}/referencias/{id} marcas
//   users/{uid}/adaptaciones/{id}
//   users/{uid}/entitlement/pro  SOLO escribe el backend (Admin SDK)
//
// Por qué así: el perfil es chico y se lee entero en cada arranque, así
// que va en el documento raíz. Lo que CRECE sin techo —sesiones,
// adaptaciones— va en subcolecciones, un documento por entidad con su
// ID estable: así una carrera nueva es una escritura de un documento y
// no reescribir un array de mil elementos.
//
// LO QUE NO SUBE, nunca: coordenadas, rutas, samples de HealthKit,
// frecuencia cardíaca punto a punto, elevación punto a punto. HealthKit
// sigue siendo HealthKit. A la nube va lo que Maratonia necesita para
// reconstruir TU plan y TU progreso en otro teléfono: agregados.

// MARK: - Estado de sincronización

enum EstadoSync: Equatable {
    case inactivo
    case sincronizando
    /// Hay cambios locales esperando conexión. No es un error: es el
    /// modo normal de una app que se usa corriendo.
    case pendiente(Int)
    case error(String)
}

// MARK: - DTO del documento raíz

/// Lo que viaja del perfil. Es el dominio, no un modelo nuevo: cada
/// campo sale de `PerfilDeportivo` y vuelve a él.
struct DocumentoCuenta: Codable, Equatable {
    /// Sube ante cambios incompatibles. Un cliente que ve una versión
    /// mayor NO escribe encima: prefiere no tocar a corromper.
    static let versionActual = 1
    var version: Int = DocumentoCuenta.versionActual
    var perfil: PerfilDeportivo?
    var planActivoID: String?
    var actualizadoEl: Date = Date()
    /// Marca de la migración única del estado local (ver `migrarSiHaceFalta`).
    var migradoDesdeLocal: Bool = false
}

// MARK: - Repositorio

@MainActor
final class RepositorioCuenta: ObservableObject {

    @Published private(set) var estado: EstadoSync = .inactivo
    /// Último instante en que la nube y el disco quedaron iguales.
    @Published private(set) var ultimaSync: Date?

    private let almacen: AlmacenStore
    private var db: Firestore? { ServicioAuth.disponible ? Firestore.firestore() : nil }

    /// Cola de escrituras que no salieron. Vive en disco: cerrar la app
    /// sin conexión no puede perder que terminaste una carrera.
    private var pendientes: [OperacionPendiente] = []
    private let urlPendientes: URL

    init(almacen: AlmacenStore,
         urlPendientes: URL = PlanStore.urlDocumentos
            .appendingPathComponent("sync-pendiente.json")) {
        self.almacen = almacen
        self.urlPendientes = urlPendientes
        self.pendientes = Self.leerPendientes(urlPendientes)
        actualizarEstadoPendientes()
    }

    private var uid: String? { Auth.auth().currentUser?.uid }

    // MARK: Entrada (arranque / login)

    /// Lo que corre al entrar con una cuenta. Decide, en este orden:
    ///
    /// 1. la nube está vacía y hay estado local → migración única;
    /// 2. la nube tiene estado y el disco no → restaurar;
    /// 3. los dos tienen algo → gana el más nuevo, sin pisar cambios
    ///    locales pendientes.
    ///
    /// Nunca borra el disco. Si algo falla, el corredor se queda con lo
    /// que tenía y la app sigue andando.
    func sincronizarAlEntrar() async {
        guard let uid, let db else { return }
        estado = .sincronizando
        do {
            let raiz = db.collection("users").document(uid)
            let doc = try await raiz.getDocument()
            let remoto = doc.exists ? try doc.data(as: DocumentoCuenta.self) : nil

            if remoto == nil || remoto?.perfil == nil {
                // La nube no sabe nada de este UID.
                if SesionApp.tienePerfil(almacen.almacen) {
                    try await migrarLocalAlaNube(uid: uid)
                }
            } else if let remoto {
                try await aplicarRemoto(remoto, uid: uid)
            }
            await vaciarPendientes()
            ultimaSync = Date()
            actualizarEstadoPendientes()
        } catch {
            // Sin nube seguimos con el disco: no es un error que valga
            // interrumpir a nadie.
            estado = .error(Self.mensaje(error))
        }
    }

    /// La migración de los testers y usuarios de builds anteriores:
    /// sube el estado local UNA vez y lo marca. Idempotente por el flag
    /// `migradoDesdeLocal` y por los IDs estables de cada entidad.
    private func migrarLocalAlaNube(uid: String) async throws {
        try await subirTodo(uid: uid, marcandoMigracion: true)
    }

    /// La nube manda cuando el disco no tiene nada propio que perder.
    private func aplicarRemoto(_ remoto: DocumentoCuenta, uid: String) async throws {
        guard remoto.version <= DocumentoCuenta.versionActual else {
            // Escrito por una build más nueva: no se toca.
            estado = .error(String(localized: "Esta versión de Maratonia es más vieja que tus datos. Actualizá la app."))
            return
        }
        let hayLocal = SesionApp.tienePerfil(almacen.almacen)
        let hayPendientes = !pendientes.isEmpty

        if hayLocal && hayPendientes {
            // Conservador: lo local tiene cambios sin subir. Se suben y
            // NO se pisa nada con lo remoto en esta pasada.
            try await subirTodo(uid: uid, marcandoMigracion: false)
            return
        }
        try await bajarTodo(remoto, uid: uid)
    }

    // MARK: Bajada

    private func bajarTodo(_ remoto: DocumentoCuenta, uid: String) async throws {
        guard let db else { return }
        let raiz = db.collection("users").document(uid)
        var local = almacen.almacen

        if let perfil = remoto.perfil { local.perfil = perfil }

        let planes = try await raiz.collection("planes").getDocuments()
        let decodificados = planes.documents.compactMap { try? $0.data(as: PlanUsuario.self) }
        if let activoID = remoto.planActivoID,
           let activo = decodificados.first(where: { $0.id.uuidString == activoID }) {
            local.planActivo = activo
            local.planesAnteriores = decodificados.filter { $0.id != activo.id }
        } else if !decodificados.isEmpty {
            local.planesAnteriores = decodificados
        }

        let sesiones = try await raiz.collection("sesiones").getDocuments()
        let bajadas = sesiones.documents.compactMap { try? $0.data(as: RegistroSesion.self) }
        // Unión por ID estable: una sesión que llegó desde dos
        // dispositivos es UNA sesión, no dos.
        local.sesiones = Self.unir(local.sesiones, bajadas, id: \.id)

        let referencias = try await raiz.collection("referencias").getDocuments()
        let marcas = referencias.documents.compactMap { try? $0.data(as: ReferenciaRendimiento.self) }
        local.referencias = Self.unir(local.referencias, marcas, id: \.id)

        let adaptaciones = try await raiz.collection("adaptaciones").getDocuments()
        let registros = adaptaciones.documents.compactMap { try? $0.data(as: RegistroAdaptacion.self) }
        if !registros.isEmpty {
            local.adaptaciones = Self.unir(local.historialAdaptaciones, registros, id: \.id)
        }

        local.activado = true
        almacen.almacen = local
    }

    /// Unión por ID: lo que ya está gana (puede tener cambios locales
    /// más nuevos), lo que falta se agrega.
    nonisolated static func unir<T, ID: Hashable>(_ locales: [T], _ remotos: [T],
                                      id: KeyPath<T, ID>) -> [T] {
        var resultado = locales
        let conocidos = Set(locales.map { $0[keyPath: id] })
        for remoto in remotos where !conocidos.contains(remoto[keyPath: id]) {
            resultado.append(remoto)
        }
        return resultado
    }

    // MARK: Subida

    private func subirTodo(uid: String, marcandoMigracion: Bool) async throws {
        guard let db else { return }
        let raiz = db.collection("users").document(uid)
        let local = almacen.almacen
        let lote = db.batch()

        var doc = DocumentoCuenta(perfil: local.perfil,
                                  planActivoID: local.planActivo?.id.uuidString)
        doc.migradoDesdeLocal = marcandoMigracion
        try lote.setData(from: doc, forDocument: raiz, merge: true)

        for plan in ([local.planActivo].compactMap { $0 } + local.historialDePlanes) {
            try lote.setData(from: plan,
                             forDocument: raiz.collection("planes").document(plan.id.uuidString),
                             merge: true)
        }
        for sesion in local.sesiones {
            try lote.setData(from: sesion,
                             forDocument: raiz.collection("sesiones").document(sesion.id.uuidString),
                             merge: true)
        }
        for referencia in local.referencias {
            try lote.setData(from: referencia,
                             forDocument: raiz.collection("referencias").document(referencia.id.uuidString),
                             merge: true)
        }
        for adaptacion in local.historialAdaptaciones {
            try lote.setData(from: adaptacion,
                             forDocument: raiz.collection("adaptaciones").document(adaptacion.id.uuidString),
                             merge: true)
        }
        try await lote.commit()
    }

    // MARK: Cableado con el dominio

    private var observador: AnyCancellable?
    /// Foto de lo último que se encoló, para no reencolar lo mismo en
    /// cada `didSet` del almacén (que dispara ante cualquier cambio).
    private var ultimaFoto: Foto?

    private struct Foto: Equatable {
        var perfil: PerfilDeportivo?
        var planActivo: UUID?
        var planHuella: Int
        var sesiones: Set<UUID>
        var referencias: Set<UUID>
        var adaptaciones: Set<UUID>
    }

    /// Engancha el repositorio al dominio: cada cambio del almacén se
    /// traduce a operaciones pendientes. Es el ÚNICO lugar donde el
    /// dominio produce escrituras a la nube — las vistas no participan.
    static func conectar(_ repositorio: RepositorioCuenta, con almacen: AlmacenStore) {
        repositorio.observador = almacen.$almacen
            .receive(on: RunLoop.main)
            .sink { [weak repositorio] nuevo in
                repositorio?.registrarCambios(nuevo)
            }
    }

    private func registrarCambios(_ dominio: AlmacenV2) {
        let foto = Foto(
            perfil: dominio.perfil,
            planActivo: dominio.planActivo?.id,
            // El plan cambia por dentro (una sesión cumplida, una
            // adaptación) sin cambiar de ID: hace falta una huella del
            // contenido, no solo del identificador.
            planHuella: dominio.planActivo?.semanas.flatMap(\.programados)
                .map { "\($0.id)\($0.resolucion.rawValue)\($0.dia.map(String.init(describing:)) ?? "")" }
                .joined().hashValue ?? 0,
            sesiones: Set(dominio.sesiones.map(\.id)),
            referencias: Set(dominio.referencias.map(\.id)),
            adaptaciones: Set(dominio.historialAdaptaciones.map(\.id)))
        defer { ultimaFoto = foto }
        guard let anterior = ultimaFoto else { return }   // primera pasada: no encola
        guard foto != anterior else { return }

        if foto.perfil != anterior.perfil || foto.planActivo != anterior.planActivo {
            anotarCambio(.perfil())
        }
        if let plan = foto.planActivo,
           foto.planActivo != anterior.planActivo || foto.planHuella != anterior.planHuella {
            anotarCambio(.plan(plan))
        }
        for id in foto.sesiones.subtracting(anterior.sesiones) { anotarCambio(.sesion(id)) }
        for id in foto.referencias.subtracting(anterior.referencias) { anotarCambio(.referencia(id)) }
        for id in foto.adaptaciones.subtracting(anterior.adaptaciones) { anotarCambio(.adaptacion(id)) }
    }

    // MARK: Escrituras incrementales

    /// El dominio cambió: se anota y se intenta subir. Si no hay red,
    /// queda en la cola y la UI no se entera.
    func anotarCambio(_ operacion: OperacionPendiente) {
        pendientes.removeAll { $0.id == operacion.id }   // idempotente
        pendientes.append(operacion)
        guardarPendientes()
        actualizarEstadoPendientes()
        Task { await vaciarPendientes() }
    }

    func vaciarPendientes() async {
        guard let uid, db != nil, !pendientes.isEmpty else { return }
        var quedan: [OperacionPendiente] = []
        for operacion in pendientes {
            do { try await aplicar(operacion, uid: uid) }
            catch { quedan.append(operacion) }
        }
        pendientes = quedan
        guardarPendientes()
        actualizarEstadoPendientes()
        if quedan.isEmpty { ultimaSync = Date() }
    }

    private func aplicar(_ operacion: OperacionPendiente, uid: String) async throws {
        guard let db else { return }
        let raiz = db.collection("users").document(uid)
        let local = almacen.almacen
        switch operacion.tipo {
        case .perfil:
            let doc = DocumentoCuenta(perfil: local.perfil,
                                      planActivoID: local.planActivo?.id.uuidString)
            try raiz.setData(from: doc, merge: true)
        case .plan:
            guard let plan = ([local.planActivo].compactMap { $0 } + local.historialDePlanes)
                .first(where: { $0.id.uuidString == operacion.entidadID }) else { return }
            try raiz.collection("planes").document(plan.id.uuidString)
                .setData(from: plan, merge: true)
            let doc = DocumentoCuenta(perfil: local.perfil,
                                      planActivoID: local.planActivo?.id.uuidString)
            try raiz.setData(from: doc, merge: true)
        case .sesion:
            guard let sesion = local.sesiones
                .first(where: { $0.id.uuidString == operacion.entidadID }) else { return }
            try raiz.collection("sesiones").document(sesion.id.uuidString)
                .setData(from: sesion, merge: true)
        case .referencia:
            guard let referencia = local.referencias
                .first(where: { $0.id.uuidString == operacion.entidadID }) else { return }
            try raiz.collection("referencias").document(referencia.id.uuidString)
                .setData(from: referencia, merge: true)
        case .adaptacion:
            guard let adaptacion = local.historialAdaptaciones
                .first(where: { $0.id.uuidString == operacion.entidadID }) else { return }
            try raiz.collection("adaptaciones").document(adaptacion.id.uuidString)
                .setData(from: adaptacion, merge: true)
        }
    }

    // MARK: Logout

    /// Cerrar sesión no puede dejar los datos de A a la vista de B. Se
    /// limpia la caché de la cuenta; HealthKit no se toca (no es
    /// nuestro) y la cola pendiente se descarta con su cuenta.
    func limpiarParaLogout() {
        pendientes = []
        guardarPendientes()
        estado = .inactivo
        ultimaSync = nil
    }

    // MARK: Cola en disco

    private func guardarPendientes() {
        if let datos = try? JSONEncoder().encode(pendientes) {
            try? datos.write(to: urlPendientes, options: .atomic)
        }
    }

    private static func leerPendientes(_ url: URL) -> [OperacionPendiente] {
        guard let datos = try? Data(contentsOf: url),
              let cola = try? JSONDecoder().decode([OperacionPendiente].self, from: datos)
        else { return [] }
        return cola
    }

    private func actualizarEstadoPendientes() {
        if case .error = estado { return }
        estado = pendientes.isEmpty ? .inactivo : .pendiente(pendientes.count)
    }

    private static func mensaje(_ error: Error) -> String {
        String(localized: "No se pudo sincronizar ahora. Tus datos están guardados en el teléfono.")
    }
}

/// Una escritura que espera conexión. Se identifica por (tipo, entidad)
/// para que repetir el mismo cambio no encole dos veces: la cola es un
/// conjunto de "esto quedó distinto", no un log de eventos.
struct OperacionPendiente: Codable, Equatable, Identifiable {
    enum Tipo: String, Codable { case perfil, plan, sesion, referencia, adaptacion }

    var tipo: Tipo
    var entidadID: String
    var creadaEl: Date = Date()

    var id: String { "\(tipo.rawValue):\(entidadID)" }

    static func perfil() -> OperacionPendiente {
        OperacionPendiente(tipo: .perfil, entidadID: "perfil")
    }
    static func plan(_ id: UUID) -> OperacionPendiente {
        OperacionPendiente(tipo: .plan, entidadID: id.uuidString)
    }
    static func sesion(_ id: UUID) -> OperacionPendiente {
        OperacionPendiente(tipo: .sesion, entidadID: id.uuidString)
    }
    static func referencia(_ id: UUID) -> OperacionPendiente {
        OperacionPendiente(tipo: .referencia, entidadID: id.uuidString)
    }
    static func adaptacion(_ id: UUID) -> OperacionPendiente {
        OperacionPendiente(tipo: .adaptacion, entidadID: id.uuidString)
    }
}
