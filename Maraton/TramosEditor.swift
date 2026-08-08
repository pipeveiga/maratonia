import SwiftUI

// Editor manual de tramos (la vía principal para armar el plan, sin JSON)
// y los planes sugeridos listos para usar de un toque.

struct TramoEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var tramo: Tramo
    @State private var conRitmo: Bool
    @State private var ritmoRapidoTexto: String
    @State private var ritmoLentoTexto: String
    @State private var mensajeError: String?
    let alGuardar: (Tramo) -> Void

    init(tramo: Tramo, alGuardar: @escaping (Tramo) -> Void) {
        _tramo = State(initialValue: tramo)
        _conRitmo = State(initialValue: tramo.ritmoMinSegKm != nil || tramo.ritmoMaxSegKm != nil)
        _ritmoRapidoTexto = State(initialValue: tramo.ritmoMinSegKm.map(formatearRitmo) ?? "")
        _ritmoLentoTexto = State(initialValue: tramo.ritmoMaxSegKm.map(formatearRitmo) ?? "")
        self.alGuardar = alGuardar
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Tramo") {
                    TextField("Nombre (ej. Calentamiento)", text: $tramo.nombre)
                    HStack {
                        Text("Kilómetros")
                        Spacer()
                        TextField("3", value: $tramo.kilometros, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                }

                Section {
                    Toggle("Con ritmo objetivo", isOn: $conRitmo)
                    if conRitmo {
                        HStack {
                            Text("Más rápido")
                            Spacer()
                            TextField("3:50", text: $ritmoRapidoTexto)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                                .autocorrectionDisabled()
                        }
                        HStack {
                            Text("Más lento")
                            Spacer()
                            TextField("4:10", text: $ritmoLentoTexto)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 90)
                                .autocorrectionDisabled()
                        }
                    }
                } footer: {
                    Text(conRitmo
                         ? "En minutos:segundos por km (ej. 4:10). Podés completar uno solo de los dos límites."
                         : "Tramo libre: el entrenador no corrige el ritmo acá.")
                }

                if let mensajeError {
                    Section {
                        Text(mensajeError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Tramo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") { guardar() }
                        .disabled(tramo.kilometros <= 0)
                }
            }
        }
    }

    private func guardar() {
        do {
            let rapido = ritmoRapidoTexto.trimmingCharacters(in: .whitespaces)
            let lento = ritmoLentoTexto.trimmingCharacters(in: .whitespaces)
            tramo.ritmoMinSegKm = (conRitmo && !rapido.isEmpty) ? try parsearRitmo(rapido) : nil
            tramo.ritmoMaxSegKm = (conRitmo && !lento.isEmpty) ? try parsearRitmo(lento) : nil
            if tramo.nombre.trimmingCharacters(in: .whitespaces).isEmpty {
                tramo.nombre = "Tramo"
            }
            if let a = tramo.ritmoMinSegKm, let b = tramo.ritmoMaxSegKm, a > b {
                mensajeError = "El ritmo «más rápido» tiene que ser menor que el «más lento». Ej: 3:50 a 4:10."
                return
            }
            alGuardar(tramo)
            dismiss()
        } catch {
            mensajeError = error.localizedDescription
        }
    }
}

// MARK: - Planes sugeridos

/// Plantillas listas para elegir de un toque. Los ritmos son de
/// referencia (corredor recreativo): cada tramo se puede tocar y ajustar.
enum PlanesSugeridos {

    static var todos: [(nombre: String, tramos: [Tramo])] {
        [
            ("5K con bloque", [
                Tramo(nombre: "Calentamiento", kilometros: 1.5, ritmoMinSegKm: nil, ritmoMaxSegKm: nil),
                Tramo(nombre: "Bloque", kilometros: 3, ritmoMinSegKm: 300, ritmoMaxSegKm: 330),
                Tramo(nombre: "Vuelta a la calma", kilometros: 1, ritmoMinSegKm: nil, ritmoMaxSegKm: nil),
            ]),
            ("10K progresivo", [
                Tramo(nombre: "Calentamiento", kilometros: 2, ritmoMinSegKm: nil, ritmoMaxSegKm: nil),
                Tramo(nombre: "Ritmo cómodo", kilometros: 4, ritmoMinSegKm: 345, ritmoMaxSegKm: 375),
                Tramo(nombre: "Ritmo fuerte", kilometros: 3, ritmoMinSegKm: 315, ritmoMaxSegKm: 345),
                Tramo(nombre: "Vuelta a la calma", kilometros: 1, ritmoMinSegKm: nil, ritmoMaxSegKm: nil),
            ]),
            ("Series 5×1K", series5x1),
            ("Tirada larga 15K", [
                Tramo(nombre: "Arranque suave", kilometros: 2, ritmoMinSegKm: nil, ritmoMaxSegKm: nil),
                Tramo(nombre: "Rodaje", kilometros: 12, ritmoMinSegKm: 360, ritmoMaxSegKm: 400),
                Tramo(nombre: "Aflojar", kilometros: 1, ritmoMinSegKm: nil, ritmoMaxSegKm: nil),
            ]),
        ]
    }

    private static var series5x1: [Tramo] {
        var tramos = [Tramo(nombre: "Calentamiento", kilometros: 2, ritmoMinSegKm: nil, ritmoMaxSegKm: nil)]
        for numero in 1...5 {
            tramos.append(Tramo(nombre: "Serie \(numero)", kilometros: 1, ritmoMinSegKm: 285, ritmoMaxSegKm: 315))
            tramos.append(Tramo(nombre: "Trote suave", kilometros: 0.5, ritmoMinSegKm: nil, ritmoMaxSegKm: nil))
        }
        tramos.append(Tramo(nombre: "Vuelta a la calma", kilometros: 1, ritmoMinSegKm: nil, ritmoMaxSegKm: nil))
        return tramos
    }
}
