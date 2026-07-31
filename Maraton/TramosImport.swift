import SwiftUI

// Importador del plan de tramos desde JSON, pensado para pegar directo
// lo que arma ChatGPT. Formato esperado:
//
// {"tramos":[
//   {"nombre":"Calentamiento","km":2},
//   {"nombre":"Bloque","km":3,"ritmoMin":"3:50","ritmoMax":"4:10"},
//   {"nombre":"Vuelta a la calma","km":1.5,"ritmoMax":"6:00"}
// ]}
//
// "ritmoMin" es el límite rápido y "ritmoMax" el lento; los dos son
// opcionales (sin ninguno, el tramo es libre).

enum ErrorImportacionTramos: LocalizedError {
    case jsonInvalido
    case ritmoInvalido(String)

    var errorDescription: String? {
        switch self {
        case .jsonInvalido:
            return "El texto no es un JSON válido con la forma {\"tramos\":[...]}. Revisá que hayas copiado todo."
        case .ritmoInvalido(let texto):
            return "Ritmo inválido: «\(texto)». Usá minutos:segundos, ej. \"3:50\"."
        }
    }
}

func parsearTramos(desde texto: String) throws -> [Tramo] {
    struct TramoJSON: Codable {
        var nombre: String?
        var km: Double
        var ritmoMin: String?
        var ritmoMax: String?
    }
    struct PlanJSON: Codable {
        var tramos: [TramoJSON]
    }

    guard let datos = texto.data(using: .utf8),
          let plan = try? JSONDecoder().decode(PlanJSON.self, from: datos) else {
        throw ErrorImportacionTramos.jsonInvalido
    }
    return try plan.tramos.enumerated().map { indice, tramo in
        Tramo(nombre: tramo.nombre ?? "Tramo \(indice + 1)",
              kilometros: tramo.km,
              ritmoMinSegKm: try tramo.ritmoMin.map(parsearRitmo),
              ritmoMaxSegKm: try tramo.ritmoMax.map(parsearRitmo))
    }
}

func parsearRitmo(_ texto: String) throws -> Int {
    let partes = texto.split(separator: ":")
    guard partes.count == 2,
          let minutos = Int(partes[0]),
          let segundos = Int(partes[1]),
          segundos < 60, minutos >= 0, segundos >= 0 else {
        throw ErrorImportacionTramos.ritmoInvalido(texto)
    }
    return minutos * 60 + segundos
}

struct ImportadorTramos: View {
    @Environment(\.dismiss) private var dismiss
    @State private var texto = ""
    @State private var mensajeError: String?
    let alImportar: ([Tramo]) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $texto)
                        .frame(minHeight: 180)
                        .font(.system(.footnote, design: .monospaced))
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                } header: {
                    Text("Pegá acá el JSON")
                } footer: {
                    Text("""
                    Ejemplo:
                    {"tramos":[
                      {"nombre":"Calentamiento","km":2},
                      {"nombre":"Bloque","km":3,"ritmoMin":"3:50","ritmoMax":"4:10"}
                    ]}

                    Tip: pedile a ChatGPT «pasame el plan en este formato JSON» con el ejemplo.
                    """)
                    .font(.caption)
                }

                if let mensajeError {
                    Section {
                        Text(mensajeError)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Importar tramos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Importar") {
                        do {
                            let tramos = try parsearTramos(desde: texto)
                            alImportar(tramos)
                            dismiss()
                        } catch {
                            mensajeError = error.localizedDescription
                        }
                    }
                    .disabled(texto.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
