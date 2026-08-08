import SwiftUI

// Las dos pantallas (sheets) para crear o editar avisos.
// Reciben el aviso inicial, editan una copia local, y al tocar Guardar
// se lo devuelven a ContentView, que decide si es nuevo o una edición.

struct AvisoFijoEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var aviso: AvisoFijo
    let alGuardar: (AvisoFijo) -> Void

    private var esValido: Bool {
        aviso.minuto > 0 && !aviso.texto.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("¿En qué minuto?") {
                    HStack {
                        Text("Minuto")
                        Spacer()
                        TextField("90", value: $aviso.minuto, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Stepper("Ajustar", value: $aviso.minuto, in: 1...600)
                }
                Section("¿Qué tiene que decir?") {
                    TextField("Date vuelta y volvé", text: $aviso.texto, axis: .vertical)
                }
            }
            .navigationTitle("Aviso fijo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        alGuardar(aviso)
                        dismiss()
                    }
                    .disabled(!esValido)
                }
            }
        }
    }
}

struct AvisoKmEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var aviso: AvisoKm
    @State private var repite: Bool
    @State private var cada: Double
    let alGuardar: (AvisoKm) -> Void

    init(aviso: AvisoKm, alGuardar: @escaping (AvisoKm) -> Void) {
        _aviso = State(initialValue: aviso)
        _repite = State(initialValue: aviso.cadaKm != nil)
        _cada = State(initialValue: aviso.cadaKm ?? 3)
        self.alGuardar = alGuardar
    }

    private var esValido: Bool {
        aviso.kilometro > 0
            && !aviso.texto.trimmingCharacters(in: .whitespaces).isEmpty
            && (!repite || cada > 0)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("En el kilómetro")
                        Spacer()
                        TextField("5", value: $aviso.kilometro, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Toggle("Repetir", isOn: $repite)
                    if repite {
                        HStack {
                            Text("Cada (km)")
                            Spacer()
                            TextField("3", value: $cada, format: .number)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                } footer: {
                    Text("Los avisos por kilómetro usan la distancia del entrenamiento: necesitan «Registrar carrera» activado en el reloj.")
                }
                Section("¿Qué tiene que decir?") {
                    TextField("Mitad de carrera", text: $aviso.texto, axis: .vertical)
                }
            }
            .navigationTitle("Aviso por km")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        aviso.cadaKm = repite ? cada : nil
                        alGuardar(aviso)
                        dismiss()
                    }
                    .disabled(!esValido)
                }
            }
        }
    }
}

struct AvisoRepetidoEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var aviso: AvisoRepetido
    @State private var tieneLimite: Bool
    @State private var hasta: Int
    let alGuardar: (AvisoRepetido) -> Void

    init(aviso: AvisoRepetido, alGuardar: @escaping (AvisoRepetido) -> Void) {
        _aviso = State(initialValue: aviso)
        _tieneLimite = State(initialValue: aviso.hastaMinuto != nil)
        _hasta = State(initialValue: aviso.hastaMinuto ?? 120)
        self.alGuardar = alGuardar
    }

    private var esValido: Bool {
        aviso.cadaMinutos > 0
            && aviso.desdeMinuto > 0
            && !aviso.texto.trimmingCharacters(in: .whitespaces).isEmpty
            && (!tieneLimite || hasta >= aviso.desdeMinuto)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Cada (minutos)")
                        Spacer()
                        TextField("20", value: $aviso.cadaMinutos, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    HStack {
                        Text("Desde el minuto")
                        Spacer()
                        TextField("20", value: $aviso.desdeMinuto, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    Toggle("Con minuto límite", isOn: $tieneLimite)
                    if tieneLimite {
                        HStack {
                            Text("Hasta el minuto")
                            Spacer()
                            TextField("120", value: $hasta, format: .number)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 80)
                        }
                    }
                } header: {
                    Text("Frecuencia")
                } footer: {
                    if !tieneLimite {
                        Text("Sin límite: suena hasta que pares la sesión.")
                    }
                }
                Section("¿Qué tiene que decir?") {
                    TextField("Tomá agua", text: $aviso.texto, axis: .vertical)
                }
            }
            .navigationTitle("Aviso repetido")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancelar") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Guardar") {
                        aviso.hastaMinuto = tieneLimite ? hasta : nil
                        alGuardar(aviso)
                        dismiss()
                    }
                    .disabled(!esValido)
                }
            }
        }
    }
}
