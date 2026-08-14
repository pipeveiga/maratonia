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

/// El estado del corredor. `vence` nil = no se sabe (o es indefinido);
/// lo que manda para bloquear es `esPro`.
enum EstadoPro: Equatable {
    case libre
    case pro(vence: Date?, enPrueba: Bool)

    var esPro: Bool {
        if case .pro = self { return true }
        return false
    }

    var enPrueba: Bool {
        if case .pro(_, let prueba) = self { return prueba }
        return false
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
            estado = .pro(vence: nil, enPrueba: false)
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
    /// que está vigente AHORA.
    func refrescarEntitlement() async {
        var vigente: EstadoPro = .libre
        var jws: String?
        for await resultado in Transaction.currentEntitlements {
            guard case .verified(let transaccion) = resultado,
                  ProductoPro.todos.contains(transaccion.productID) else { continue }
            // Revocada por Apple (reembolso, disputa): no es Pro.
            if transaccion.revocationDate != nil { continue }
            if let vence = transaccion.expirationDate, vence < Date() { continue }
            // `offer` es de iOS 17.2; el deployment target es menor.
            // El tipo de oferta solo decora el texto de la UI, así que
            // se resuelve con la API disponible y sin bloquear nada.
            let enPrueba: Bool
            if #available(iOS 17.2, *) {
                enPrueba = transaccion.offer?.type == .introductory
            } else {
                enPrueba = transaccion.offerType == .introductory
            }
            vigente = .pro(vence: transaccion.expirationDate, enPrueba: enPrueba)
            jws = resultado.jwsRepresentation
        }
        aplicar(vigente, jws: jws)
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
