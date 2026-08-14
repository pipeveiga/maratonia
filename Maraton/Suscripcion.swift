import Foundation
import StoreKit

// MARATONIA PRO — una sola capa.
//
// Regla: ninguna vista habla con StoreKit. Las vistas preguntan
// `Entitlements.permite(...)` y listo. Sin esto, "¿es Pro?" termina
// escrito de veinticinco maneras distintas en veinticinco pantallas, y
// la vigésimo sexta se olvida.
//
// Y la regla que importa de verdad: **el entitlement que ve la app es
// para la UI, no para autorizar**. El backend revalida contra la
// transacción firmada por Apple antes de gastar un token. Un booleano
// que viaja desde el cliente no autoriza nada.

// MARK: - Qué es Pro

/// Los productos. Los IDs tienen que existir en App Store Connect con
/// exactamente estos identificadores.
enum ProductoPro: String, CaseIterable {
    case mensual = "maratonia.pro.monthly"
    case anual = "maratonia.pro.yearly"

    static var todos: [String] { allCases.map(\.rawValue) }
}

/// Lo que Pro habilita. Se pregunta por CAPACIDAD, no por producto: si
/// mañana cambia el empaquetado, cambia esta tabla y nada más.
enum CapacidadPro: String, CaseIterable {
    /// Mejorar 5K, Mejorar 10K, y todo 21K y 42K.
    case objetivosAvanzados
    case coach
    case adaptacionInteligente
}

/// Lo que se sabe de LA suscripción, con datos de StoreKit y de nadie
/// más. El nombre sale de `displayName` del producto: escribir "Anual"
/// en la app es mentirle al que compró el mensual.
struct DetallePro: Equatable {
    var productoID: String
    /// `Product.displayName`, tal cual lo devuelve App Store.
    var nombre: String?
    var vence: Date?
    /// Si no se renueva sola, la fecha de vencimiento es una fecha de
    /// FIN, y eso cambia por completo lo que hay que decirle al corredor.
    var renuevaSola: Bool = true
    var enPrueba: Bool = false
}

/// Cómo viene la renovación, en nuestros términos. Espejo mínimo de
/// `Product.SubscriptionInfo.RenewalState`, para que la decisión de qué
/// mostrar sea una función pura y testeable sin StoreKit.
enum RenovacionPro: Equatable {
    case suscrita
    case enGracia            // falló el cobro, Apple da período de gracia
    case reintentandoCobro   // falló el cobro y NO hay gracia
    case expirada
    case revocada            // reembolso o disputa
}

/// El estado del corredor.
///
/// Antes esto era `libre | pro`, y todo lo que no fuera pro se veía
/// igual: el que nunca compró, el que pidió el reembolso y —lo peor— el
/// que pagó pero tiene la tarjeta vencida veían el mismo paywall sin
/// una palabra de por qué. Un problema de cobro es lo único de esta
/// lista que el corredor puede arreglar, y era justo lo que no se le
/// decía.
enum EstadoPro: Equatable {
    case libre
    case activa(DetallePro)
    /// Falló el cobro pero Apple mantiene el acceso mientras reintenta.
    case gracia(DetallePro)
    /// Falló el cobro y ya no hay acceso.
    case problemaDeCobro(DetallePro)
    case expirada(DetallePro)
    case revocada(DetallePro)

    /// Acceso REAL. Período de gracia incluido: Apple sigue considerando
    /// suscrito al corredor, y quitarle el plan mientras se reintenta el
    /// cobro sería castigarlo por un problema de su banco.
    var esPro: Bool {
        switch self {
        case .activa, .gracia: return true
        case .libre, .problemaDeCobro, .expirada, .revocada: return false
        }
    }

    var detalle: DetallePro? {
        switch self {
        case .libre: return nil
        case .activa(let d), .gracia(let d), .problemaDeCobro(let d),
             .expirada(let d), .revocada(let d): return d
        }
    }

    var enPrueba: Bool { detalle?.enPrueba ?? false }

    /// La decisión, pura: sin StoreKit, sin vistas, sin async.
    static func decidir(_ renovacion: RenovacionPro, detalle: DetallePro) -> EstadoPro {
        switch renovacion {
        case .suscrita: return .activa(detalle)
        case .enGracia: return .gracia(detalle)
        case .reintentandoCobro: return .problemaDeCobro(detalle)
        case .expirada: return .expirada(detalle)
        case .revocada: return .revocada(detalle)
        }
    }
}

// MARK: - Política de acceso

/// Qué objetivos son Pro. Vive en el dominio y no en la UI porque lo
/// consultan el catálogo, el motor de adopción y los tests.
enum PoliticaPro {

    /// FREE: empezar a correr y llegar a 10K. PRO: mejorar marcas y las
    /// distancias largas.
    static func requierePro(_ objetivo: ObjetivoDeportivo) -> Bool {
        switch objetivo {
        case .primeros5K, .diez:
            return false
        case .mejorar5K, .mejorar10K,
             .mediaMaraton, .mejorarMedia, .mediaRendimiento,
             .maraton, .mejorarMaraton, .maratonRendimiento:
            return true
        }
    }

    /// Adoptar un plan Pro exige Pro. Mirarlo, no: el catálogo se ve
    /// entero (ver `CatalogoView`), el límite está en adoptar.
    static func puedeAdoptar(_ objetivo: ObjetivoDeportivo, siendoPro esPro: Bool) -> Bool {
        !requierePro(objetivo) || esPro
    }

    /// Un plan YA adoptado no se toca cuando Pro expira: no se castiga
    /// destruyendo datos. Lo que se bloquea son las capacidades nuevas.
    static func conservaPlanAdoptado(siendoPro _: Bool) -> Bool { true }
}

/// EL punto de consulta. Las vistas usan esto y nada más.
@MainActor
enum Entitlements {
    static func permite(_ capacidad: CapacidadPro) -> Bool {
        switch capacidad {
        case .objetivosAvanzados, .coach, .adaptacionInteligente:
            return TiendaPro.compartida.estado.esPro
        }
    }

    static var esPro: Bool { TiendaPro.compartida.estado.esPro }
}

// MARK: - La tienda

@MainActor
final class TiendaPro: ObservableObject {

    static let compartida = TiendaPro()

    @Published private(set) var productos: [Product] = []
    @Published private(set) var estado: EstadoPro = .libre
    @Published private(set) var cargando = false
    @Published var mensaje: String?

    /// La transacción firmada por Apple, tal cual. Es lo que se manda
    /// al backend para que verifique la firma: no un booleano nuestro.
    @Published private(set) var jwsVigente: String?

    private var escucha: Task<Void, Never>?
    private let defaults: UserDefaults
    private static let claveCache = "maratonia.pro.estadoCache"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Caché SOLO para que la UI no parpadee en el arranque. No
        // autoriza nada: en cuanto StoreKit responde, manda StoreKit.
        if defaults.bool(forKey: Self.claveCache) {
            estado = .activa(DetallePro(productoID: "", nombre: nil, vence: nil))
        }
    }

    /// Arranca la escucha de transacciones. Se llama una vez, al inicio:
    /// StoreKit puede entregar una compra hecha en otro dispositivo, una
    /// renovación o una revocación en cualquier momento.
    func empezar() {
        guard escucha == nil else { return }
        escucha = Task(priority: .background) { [weak self] in
            for await actualizacion in Transaction.updates {
                await self?.procesar(actualizacion)
            }
        }
        Task {
            await cargarProductos()
            await refrescarEntitlement()
        }
    }

    func cargarProductos() async {
        cargando = true
        defer { cargando = false }
        do {
            let cargados = try await Product.products(for: ProductoPro.todos)
            // Anual primero: es la opción destacada.
            productos = cargados.sorted { a, b in
                (a.id == ProductoPro.anual.rawValue ? 0 : 1)
                    < (b.id == ProductoPro.anual.rawValue ? 0 : 1)
            }
        } catch {
            mensaje = String(localized: "No pudimos cargar los precios. Probá de nuevo en un rato.")
        }
    }

    /// La verdad del entitlement en el dispositivo: lo que Apple dice
    /// AHORA. Dos fuentes, y las dos hacen falta:
    ///
    /// - `currentEntitlements` da lo que está VIGENTE y, sobre todo, el
    ///   JWS firmado — lo único que el backend acepta como prueba.
    /// - El estado de renovación del grupo de suscripción da lo que NO
    ///   está vigente y por qué: vencida, revocada, o con un problema de
    ///   cobro. Sin esto, esos tres casos eran indistinguibles de "nunca
    ///   compró nada".
    func refrescarEntitlement() async {
        var jws: String?
        var vigente: DetallePro?

        for await resultado in Transaction.currentEntitlements {
            guard case .verified(let transaccion) = resultado,
                  ProductoPro.todos.contains(transaccion.productID) else { continue }
            if transaccion.revocationDate != nil { continue }
            if let vence = transaccion.expirationDate, vence < Date() { continue }
            vigente = DetallePro(
                productoID: transaccion.productID,
                nombre: producto(desdeID: transaccion.productID)?.displayName,
                vence: transaccion.expirationDate,
                enPrueba: Self.esPrueba(transaccion))
            jws = resultado.jwsRepresentation
        }

        let porRenovacion = await estadoPorRenovacion(vigente: vigente)
        aplicar(porRenovacion ?? (vigente.map { EstadoPro.activa($0) } ?? .libre), jws: jws)
    }

    /// `offer` es de iOS 17.2; el deployment target es menor. El tipo de
    /// oferta solo decora el texto, así que se resuelve con la API
    /// disponible y sin bloquear nada.
    private static func esPrueba(_ transaccion: Transaction) -> Bool {
        if #available(iOS 17.2, *) { return transaccion.offer?.type == .introductory }
        return transaccion.offerType == .introductory
    }

    /// El estado del GRUPO de suscripción. nil = no se pudo consultar
    /// (productos sin cargar, sin red): en ese caso manda lo vigente, que
    /// es el comportamiento anterior. Nunca se inventa un estado peor del
    /// que se puede probar.
    private func estadoPorRenovacion(vigente: DetallePro?) async -> EstadoPro? {
        guard let alguno = productos.first(where: { $0.subscription != nil }) else { return nil }
        guard let estados = try? await alguno.subscription?.status, !estados.isEmpty else { return nil }

        // El grupo puede traer varias (upgrade/downgrade en curso). Se
        // toma la que da acceso si hay alguna; si no, la más informativa.
        let ordenadas = estados.sorted { Self.prioridad($0.state) < Self.prioridad($1.state) }
        guard let elegido = ordenadas.first,
              case .verified(let transaccion) = elegido.transaction else { return nil }
        guard ProductoPro.todos.contains(transaccion.productID) else { return nil }

        var renuevaSola = true
        if case .verified(let renovacion) = elegido.renewalInfo {
            renuevaSola = renovacion.willAutoRenew
        }

        let detalle = DetallePro(
            productoID: transaccion.productID,
            nombre: producto(desdeID: transaccion.productID)?.displayName,
            vence: vigente?.vence ?? transaccion.expirationDate,
            renuevaSola: renuevaSola,
            enPrueba: vigente?.enPrueba ?? Self.esPrueba(transaccion))

        guard let renovacion = Self.renovacion(desde: elegido.state) else { return nil }
        return EstadoPro.decidir(renovacion, detalle: detalle)
    }

    /// Primero los estados con acceso: si el corredor tiene acceso por
    /// alguna, esa es su realidad.
    private static func prioridad(_ estado: Product.SubscriptionInfo.RenewalState) -> Int {
        switch estado {
        case .subscribed: return 0
        case .inGracePeriod: return 1
        case .inBillingRetryPeriod: return 2
        case .revoked: return 3
        case .expired: return 4
        default: return 5
        }
    }

    private static func renovacion(desde estado: Product.SubscriptionInfo.RenewalState) -> RenovacionPro? {
        switch estado {
        case .subscribed: return .suscrita
        case .inGracePeriod: return .enGracia
        case .inBillingRetryPeriod: return .reintentandoCobro
        case .expired: return .expirada
        case .revoked: return .revocada
        // Un estado que esta versión no conoce NO se interpreta: se
        // devuelve nil y manda lo vigente, que es verificable.
        default: return nil
        }
    }

    private func producto(desdeID id: String) -> Product? {
        productos.first { $0.id == id }
    }

    private func aplicar(_ nuevo: EstadoPro, jws: String?) {
        if estado != nuevo { estado = nuevo }
        jwsVigente = jws
        defaults.set(nuevo.esPro, forKey: Self.claveCache)
    }

    private func procesar(_ resultado: VerificationResult<Transaction>) async {
        guard case .verified(let transaccion) = resultado else { return }
        await transaccion.finish()
        await refrescarEntitlement()
    }

    // MARK: Comprar / restaurar

    enum ResultadoCompra: Equatable {
        case comprado
        case cancelado
        case pendiente
        case fallo(String)
    }

    func comprar(_ producto: Product) async -> ResultadoCompra {
        do {
            switch try await producto.purchase() {
            case .success(let verificacion):
                guard case .verified(let transaccion) = verificacion else {
                    return .fallo(String(localized: "No pudimos verificar la compra con App Store."))
                }
                await transaccion.finish()
                await refrescarEntitlement()
                return .comprado
            case .userCancelled:
                return .cancelado
            case .pending:
                // Ask to Buy, SCA: la compra puede aprobarse después.
                return .pendiente
            @unknown default:
                return .fallo(String(localized: "App Store devolvió algo que no sabemos leer."))
            }
        } catch {
            return .fallo(String(localized: "No se pudo completar la compra."))
        }
    }

    /// Restaurar es obligatorio y tiene que decir la verdad: si no había
    /// nada que restaurar, se dice, no se finge éxito.
    enum ResultadoRestaurar: Equatable { case restaurado, sinCompras, fallo(String) }

    func restaurar() async -> ResultadoRestaurar {
        do {
            try await AppStore.sync()
            await refrescarEntitlement()
            return estado.esPro ? .restaurado : .sinCompras
        } catch {
            return .fallo(String(localized: "No se pudo contactar a App Store."))
        }
    }

    // MARK: Precios (siempre de StoreKit, nunca hardcodeados)

    func producto(_ cual: ProductoPro) -> Product? {
        productos.first { $0.id == cual.rawValue }
    }

    /// El precio localizado tal cual lo da App Store.
    func precio(_ cual: ProductoPro) -> String? {
        producto(cual)?.displayPrice
    }

    /// El equivalente mensual del anual, calculado sobre el precio REAL
    /// del storefront. Nada de "$4.17" hardcodeado: en otro país el
    /// anual vale otra cosa y esa cuenta sería mentira.
    func mensualEquivalenteDelAnual() -> String? {
        guard let anual = producto(.anual) else { return nil }
        let porMes = anual.price / 12
        return anual.priceFormatStyle.format(porMes)
    }

    /// La prueba gratuita que declara el producto, si tiene.
    func diasDePrueba(_ cual: ProductoPro) -> Int? {
        guard let oferta = producto(cual)?.subscription?.introductoryOffer,
              oferta.paymentMode == .freeTrial else { return nil }
        let periodo = oferta.period
        switch periodo.unit {
        case .day: return periodo.value
        case .week: return periodo.value * 7
        case .month: return periodo.value * 30
        case .year: return periodo.value * 365
        @unknown default: return nil
        }
    }
}
