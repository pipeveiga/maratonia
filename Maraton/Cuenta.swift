import Foundation
import CloudKit
import SwiftUI

// "Tu cuenta Maratonia", versión 1: tu propio iCloud (CloudKit).
// Sin registro ni contraseñas — el iPhone ya sabe quién sos. El plan se
// respalda en la base de datos PRIVADA de tu iCloud (el desarrollador no
// puede verla) y se restaura al reinstalar o cambiar de teléfono.
//
// El login multi-proveedor (Google / email y contraseña) está
// planificado sobre Firebase: ver CUENTAS.md — requiere configuración
// externa en la consola de Firebase antes de poder cablearse.

final class CuentaStore: ObservableObject {
    static let compartida = CuentaStore()

    enum Estado {
        case verificando
        case conectada
        case sinSesion
        case problema(String)
    }

    @Published var estado: Estado = .verificando
    @Published var ultimoRespaldo: Date?
    @Published var mensaje: String?

    private let contenedor = CKContainer(identifier: "iCloud.com.pipeveiga.maraton")
    private static let idRegistro = CKRecord.ID(recordName: "planActual")
    private var trabajoPendiente: DispatchWorkItem?

    private init() {
        verificar()
    }

    func verificar() {
        contenedor.accountStatus { [weak self] estadoCuenta, _ in
            DispatchQueue.main.async {
                switch estadoCuenta {
                case .available:
                    self?.estado = .conectada
                case .noAccount:
                    self?.estado = .sinSesion
                default:
                    self?.estado = .problema("iCloud no disponible en este momento")
                }
            }
        }
    }

    /// Respaldo con espera de 3 s: PlanStore lo llama en cada cambio y
    /// así no bombardeamos iCloud mientras el usuario tipea.
    func respaldarConDemora(_ plan: Plan) {
        // Re-verificar la cuenta en cada intento: antes se chequeaba UNA
        // vez por vida del proceso, y si iCloud llegó tarde (o volvió),
        // los respaldos se descartaban en silencio para siempre.
        verificar()
        trabajoPendiente?.cancel()
        let trabajo = DispatchWorkItem { [weak self] in
            self?.respaldar(plan)
        }
        trabajoPendiente = trabajo
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: trabajo)
    }

    /// Sube el plan a la base privada del iCloud del usuario.
    private func respaldar(_ plan: Plan) {
        // Un plan sin contenido NUNCA pisa el respaldo: tras reinstalar,
        // la app arranca con el plan vacío y el primer cambio dispararía
        // un respaldo que destruiría justo lo que se quiere restaurar.
        let esVacio = plan.pistas.isEmpty
            && plan.avisosFijos.isEmpty
            && plan.avisosRepetidos.isEmpty
            && plan.tramosActivos.isEmpty
            && plan.avisosKmActivos.isEmpty
        guard !esVacio else { return }

        switch estado {
        case .conectada:
            break
        case .verificando:
            // Aún resolviendo la cuenta: no acusar "sin iCloud" en falso.
            // El próximo cambio del plan reintenta (verificar ya corre
            // en cada respaldarConDemora).
            return
        default:
            // Que se sepa: antes el respaldo se descartaba mudo.
            mensaje = "El plan no se está respaldando: no hay sesión de iCloud activa."
            return
        }
        guard let datos = try? JSONEncoder().encode(plan),
              let json = String(data: datos, encoding: .utf8) else { return }

        let registro = CKRecord(recordType: "Plan", recordID: Self.idRegistro)
        registro["json"] = json as CKRecordValue

        let operacion = CKModifyRecordsOperation(recordsToSave: [registro])
        operacion.savePolicy = .allKeys  // pisa la versión anterior
        operacion.modifyRecordsResultBlock = { [weak self] resultado in
            DispatchQueue.main.async {
                switch resultado {
                case .success:
                    self?.ultimoRespaldo = Date()
                    self?.mensaje = nil
                case .failure(let error):
                    self?.mensaje = "Respaldo: \(error.localizedDescription)"
                }
            }
        }
        contenedor.privateCloudDatabase.add(operacion)
    }

    /// Borra el respaldo propio de Maratonia en el iCloud del usuario
    /// (parte de "Eliminar cuenta"). No toca nada más del iCloud.
    func borrarRespaldo() {
        contenedor.privateCloudDatabase.delete(withRecordID: Self.idRegistro) { [weak self] _, error in
            DispatchQueue.main.async {
                // "No existe" también es éxito: no había nada que borrar.
                if let error, (error as? CKError)?.code != .unknownItem {
                    self?.mensaje = "No pude borrar el respaldo de iCloud: \(error.localizedDescription)"
                }
            }
        }
    }

    /// Baja el último plan respaldado (reinstalación / teléfono nuevo).
    func restaurar(alTerminar: @escaping (Plan?) -> Void) {
        contenedor.privateCloudDatabase.fetch(withRecordID: Self.idRegistro) { [weak self] registro, error in
            DispatchQueue.main.async {
                guard let json = registro?["json"] as? String else {
                    self?.mensaje = error != nil
                        ? "Restaurar: \(error!.localizedDescription)"
                        : "No hay ningún plan respaldado todavía."
                    alTerminar(nil)
                    return
                }
                guard let datos = json.data(using: .utf8),
                      let plan = try? JSONDecoder().decode(Plan.self, from: datos) else {
                    // El respaldo EXISTE pero no se entiende: decirlo tal
                    // cual, no "no hay respaldo" (mentira desesperante).
                    self?.mensaje = "Hay un respaldo pero no lo puedo leer con esta versión de la app. Actualizá Maratonia e intentá de nuevo."
                    alTerminar(nil)
                    return
                }
                self?.mensaje = nil
                alTerminar(plan)
            }
        }
    }
}
