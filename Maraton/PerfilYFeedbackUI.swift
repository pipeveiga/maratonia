import SwiftUI

// Dos pantallas chicas que cierran el loop del motor adaptativo:
//
// 1. FeedbackSesionView — la única pregunta subjetiva que hace la app,
//    justo después de guardar una carrera. Un toque y listo; se puede
//    ignorar entera. Es lo que convierte "corrí 8 km" en "corrí 8 km y
//    me costó muchísimo", que es una diferencia que ningún sensor ve.
//
// 2. DatosBasicosView — edad, sexo, altura, peso. Viven en Perfil y NO
//    en el onboarding a propósito: son contexto opcional (§2) y meterlos
//    en el alta convertiría el onboarding en un interrogatorio.
//
// Ninguna de las dos bloquea nada: sin responder, la app funciona igual.

// MARK: - Feedback post-carrera (§33)

struct FeedbackSesionView: View {
    @ObservedObject var almacen: AlmacenStore
    let sesionID: UUID
    /// Lo que el motor determinístico ya sabe de esta sesión. Se usa
    /// para el encabezado y para decidir si hay algo que proponer.
    let analisis: AnalisisPostCarrera
    var alCerrar: () -> Void

    @State private var sensacion: SensacionEsfuerzo?
    @State private var conMolestia = false
    @State private var propuesta: [CambioPropuesto] = []
    @State private var evaluado = false

    private var hoy: DiaLocal { DiaLocal(fecha: Date()) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: DV2.Espacio.xs) {
                        Text(resumen)
                            .font(.headline)
                        if let cumplimiento = analisis.cumplimiento {
                            Text("\(Int((cumplimiento * 100).rounded())) % de lo previsto")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // `Section(titulo) { } footer: { }` NO existe en
                // SwiftUI: los inits son (titulo, content),
                // (content, header, footer), (content, footer) y
                // (content, header). El título va como `header:`.
                Section {
                    ForEach(SensacionEsfuerzo.allCases, id: \.self) { opcion in
                        Button {
                            sensacion = opcion
                            guardar()
                        } label: {
                            HStack {
                                Text(opcion.texto)
                                Spacer()
                                if sensacion == opcion {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text("¿Cómo te sentiste?")
                } footer: {
                    Text("Opcional. Nadie te va a insistir con esto.")
                }

                Section {
                    Toggle("Tuve alguna molestia", isOn: $conMolestia)
                        .onChange(of: conMolestia) { _, _ in guardar() }
                } footer: {
                    Text("Es una señal para que el plan vaya más prudente, no un diagnóstico.")
                }

                if evaluado { seccionVeredicto }

                Section {
                    Button("Listo") { alCerrar() }
                        .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("Tu carrera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Ahora no") { alCerrar() }
                }
            }
        }
    }

    /// El caso NORMAL tiene que ser el silencio (§35): la mayoría de
    /// las carreras terminan en "tu plan sigue según lo previsto".
    @ViewBuilder
    private var seccionVeredicto: some View {
        if propuesta.isEmpty {
            Section {
                Label("Buen entrenamiento. Tu preparación sigue según lo previsto.",
                      systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .font(.subheadline)
            }
        } else {
            Section {
                ForEach(Array(propuesta.enumerated()), id: \.offset) { _, cambio in
                    filaPropuesta(cambio)
                }
                Button {
                    AplicadorAdaptacion.aplicar(
                        propuesta, a: &almacen.almacen, hoy: hoy, origen: .motor,
                        motivo: motivoDelAjuste)
                    propuesta = []
                } label: {
                    Label("Aplicar el ajuste", systemImage: "checkmark.circle")
                }
                Button("Dejar el plan como está", role: .cancel) { propuesta = [] }
            } header: {
                Text("Ajuste sugerido")
            } footer: {
                Text(motivoDelAjuste)
            }
        }
    }

    private func filaPropuesta(_ cambio: CambioPropuesto) -> some View {
        let programado = almacen.almacen.todosLosProgramados
            .first { $0.id == cambio.programadoID }
        return VStack(alignment: .leading, spacing: 4) {
            if let programado {
                Text("ANTES: \(AplicadorAdaptacion.descripcion(programado))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            switch cambio {
            case .convertirEnFacil:
                Text("PROPUESTO: el mismo tiempo en pie, sin la carga de intensidad")
                    .font(.subheadline)
            case .reducir(_, let factor):
                Text("PROPUESTO: acortarla al \(Int((factor * 100).rounded())) %")
                    .font(.subheadline)
            case .reprogramar(_, let dia):
                Text("PROPUESTO: moverla al \(textoDia(dia))")
                    .font(.subheadline)
            case .omitir:
                Text("PROPUESTO: saltarla").font(.subheadline)
            case .mantener:
                Text("PROPUESTO: dejarla igual").font(.subheadline)
            }
        }
    }

    private var motivoDelAjuste: String {
        if analisis.conMolestia || conMolestia {
            return String(localized: "Declaraste una molestia: la próxima sesión exigente va más suave.")
        }
        return String(localized: "La sesión anterior resultó más exigente de lo previsto.")
    }

    private var resumen: String {
        let km = Unidades.distancia(km: analisis.km, decimales: 2)
        guard let ritmo = analisis.ritmoSegKm else { return km }
        return String(localized: "\(km) · \(Unidades.ritmo(segundosPorKm: ritmo))")
    }

    private func textoDia(_ dia: DiaLocal) -> String {
        guard let fecha = dia.fecha() else { return "—" }
        return FormatoFecha.diaYMes(fecha)
    }

    /// Guarda el feedback y corre el detector. Todo local: sin backend,
    /// sin internet y sin IA — el fallback ES el camino principal.
    private func guardar() {
        almacen.almacen.registrarSensacion(sesionID: sesionID, sensacion: sensacion,
                                           conMolestia: conMolestia)
        var actualizado = analisis
        actualizado.sensacion = sensacion
        actualizado.conMolestia = conMolestia
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoy, almacen: almacen.almacen, analisis: actualizado,
            kmSemanaActual: nil))
        propuesta = DetectorEventos.ameritaIA(eventos)
            ? PropuestaLocal.proponer(para: eventos, en: almacen.almacen, hoy: hoy)
            : []
        evaluado = true
    }
}

// MARK: - Datos básicos (contexto opcional, editable en Perfil)

struct DatosBasicosView: View {
    @ObservedObject var almacen: AlmacenStore

    @State private var tieneFecha = false
    @State private var fechaNacimiento = Date()
    @State private var sexo: Sexo = .prefiereNoDecir
    @State private var altura: Double = 0
    @State private var peso: Double = 0
    @State private var cargado = false

    var body: some View {
        List {
            Section {
                Text("Nada de esto es obligatorio y nada de esto define tu plan. Tu rendimiento real y tu historial pesan mucho más — esto es solo contexto.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Edad") {
                Toggle("Cargar mi fecha de nacimiento", isOn: $tieneFecha)
                if tieneFecha {
                    DatePicker("Nací el", selection: $fechaNacimiento,
                               in: ...Date(), displayedComponents: .date)
                }
            }

            Section("Sexo") {
                Picker("Sexo", selection: $sexo) {
                    Text("Prefiero no decirlo").tag(Sexo.prefiereNoDecir)
                    Text("Femenino").tag(Sexo.femenino)
                    Text("Masculino").tag(Sexo.masculino)
                    Text("Otro").tag(Sexo.otro)
                }
            }

            Section("Medidas") {
                // Etiqueta armada con String(localized:) y NO con un
                // ternario de literales: un ternario en posición de
                // LocalizedStringKey resuelve distinto según el
                // contexto y es justo el patrón que rompe traducciones.
                // El ESTADO sigue en cm y kg canónicos; lo que cambia
                // con la preferencia es el paso y el texto. Así el dato
                // guardado no depende de en qué unidad se lo tipeó.
                Stepper(textoAltura) { ajustar(&altura, paso: pasoAltura, tope: 230) }
                    onDecrement: { ajustar(&altura, paso: -pasoAltura, tope: 230) }
                Stepper(textoPeso) { ajustar(&peso, paso: pasoPeso, tope: 200) }
                    onDecrement: { ajustar(&peso, paso: -pasoPeso, tope: 200) }
            }

            Section {
                Button("Guardar") { guardar() }
                    .frame(maxWidth: .infinity)
            } footer: {
                Text("Se guardan solo en tu dispositivo, como el resto de tu perfil.")
            }
        }
        .navigationTitle("Datos básicos")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: cargar)
    }

    /// Un paso del stepper, en unidades CANÓNICAS: 1 cm o 1 pulgada,
    /// 1 kg o 1 libra. En imperial, subir de a un centímetro sería
    /// invisible en pantalla (5′10″ no cambia) y el control se sentiría
    /// roto.
    private var pasoAltura: Double {
        Unidades.actual == .imperial ? Unidades.pulgadaEnCm : 1
    }

    private var pasoPeso: Double {
        Unidades.actual == .imperial ? Unidades.libraEnKg : 1
    }

    private func ajustar(_ valor: inout Double, paso: Double, tope: Double) {
        valor = min(tope, max(0, valor + paso))
    }

    private var textoAltura: String {
        altura > 0 ? String(localized: "Altura: \(Unidades.altura(cm: altura))")
                   : String(localized: "Altura: sin cargar")
    }

    private var textoPeso: String {
        peso > 0 ? String(localized: "Peso: \(Unidades.peso(kg: peso))")
                 : String(localized: "Peso: sin cargar")
    }

    private func cargar() {
        guard !cargado else { return }
        cargado = true
        let datos = almacen.almacen.perfilDeportivo.datosBasicos ?? DatosBasicos()
        if let nacimiento = datos.fechaNacimiento, let fecha = nacimiento.fecha() {
            tieneFecha = true
            fechaNacimiento = fecha
        }
        sexo = datos.sexo ?? .prefiereNoDecir
        altura = datos.alturaCm ?? 0
        peso = datos.pesoKg ?? 0
    }

    private func guardar() {
        var perfil = almacen.almacen.perfilDeportivo
        perfil.datosBasicos = DatosBasicos(
            fechaNacimiento: tieneFecha ? DiaLocal(fecha: fechaNacimiento) : nil,
            sexo: sexo,
            alturaCm: altura > 0 ? altura : nil,
            pesoKg: peso > 0 ? peso : nil)
        almacen.almacen.perfil = perfil
    }
}

// MARK: - Historial de adaptaciones (§44)

struct HistorialAdaptacionesView: View {
    @ObservedObject var almacen: AlmacenStore

    var body: some View {
        List {
            if almacen.almacen.historialAdaptaciones.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Sin ajustes todavía", systemImage: "clock.arrow.circlepath")
                    } description: {
                        Text("Cuando el plan se adapte a algo que te pasó, el cambio queda anotado acá.")
                    }
                }
            }
            ForEach(almacen.almacen.historialAdaptaciones.reversed()) { registro in
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(registro.antes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .strikethrough()
                        Text(registro.despues)
                            .font(.subheadline.weight(.medium))
                        Text(registro.motivo)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("\(FormatoFecha.corta(registro.fecha)) · \(textoOrigen(registro.origen))")
                }
            }
        }
        .navigationTitle("Ajustes del plan")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func textoOrigen(_ origen: RegistroAdaptacion.Origen) -> String {
        switch origen {
        case .motor: return String(localized: "Motor de Maratonia")
        case .coach: return String(localized: "Maratonia Coach")
        case .usuario: return String(localized: "Vos")
        }
    }
}
