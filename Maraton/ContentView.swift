import SwiftUI
import UniformTypeIdentifiers

// Pantalla única de la app iOS (Fase 2): pistas, avisos fijos, avisos
// repetidos, vista previa del cronograma y persistencia automática.
// El botón "Enviar al reloj" queda deshabilitado hasta la Fase 3.

struct ContentView: View {
    @StateObject private var store = PlanStore()
    @ObservedObject private var conectividad = Conectividad.compartida
    @State private var mostrandoImportador = false
    @State private var fijoEnEdicion: AvisoFijo?
    @State private var repetidoEnEdicion: AvisoRepetido?

    /// Horizonte de la vista previa del cronograma (solo afecta la vista,
    /// no el plan). Se recuerda entre aperturas de la app.
    @AppStorage("horizonteCronograma") private var horizonteMinutos = 120

    var body: some View {
        NavigationStack {
            List {
                seccionPistas
                seccionAvisosFijos
                seccionAvisosRepetidos
                seccionCronograma
                seccionEnvio
            }
            .navigationTitle("Maratón")
            .toolbar { EditButton() }
            .fileImporter(
                isPresented: $mostrandoImportador,
                allowedContentTypes: [.mp3, .audio],
                allowsMultipleSelection: true
            ) { resultado in
                if case .success(let urls) = resultado {
                    store.importar(urls: urls)
                }
            }
            .sheet(item: $fijoEnEdicion) { aviso in
                AvisoFijoEditor(aviso: aviso) { actualizado in
                    if let indice = store.plan.avisosFijos.firstIndex(where: { $0.id == actualizado.id }) {
                        store.plan.avisosFijos[indice] = actualizado
                    } else {
                        store.plan.avisosFijos.append(actualizado)
                    }
                }
            }
            .sheet(item: $repetidoEnEdicion) { aviso in
                AvisoRepetidoEditor(aviso: aviso) { actualizado in
                    if let indice = store.plan.avisosRepetidos.firstIndex(where: { $0.id == actualizado.id }) {
                        store.plan.avisosRepetidos[indice] = actualizado
                    } else {
                        store.plan.avisosRepetidos.append(actualizado)
                    }
                }
            }
        }
    }

    // MARK: - Pistas

    private var seccionPistas: some View {
        Section {
            TextField("Nombre del plan", text: $store.plan.nombre)
                .font(.headline)

            if store.plan.pistas.isEmpty {
                Text("Todavía no hay pistas. Importá tus MP3 para armar la cola.")
                    .foregroundStyle(.secondary)
            }

            ForEach(store.plan.pistas, id: \.self) { nombre in
                HStack {
                    Image(systemName: "music.note")
                        .foregroundStyle(.tint)
                    VStack(alignment: .leading) {
                        Text(nombre)
                            .lineLimit(1)
                        if let duracion = store.duraciones[nombre] {
                            Text(formatearDuracion(duracion))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Archivo no encontrado")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .onDelete { store.borrarPistas(en: $0) }
            .onMove { store.moverPistas(de: $0, a: $1) }

            Button {
                mostrandoImportador = true
            } label: {
                Label("Importar MP3", systemImage: "plus.circle.fill")
            }
        } header: {
            Text("Pistas")
        } footer: {
            if !store.plan.pistas.isEmpty {
                Text("Duración total: \(formatearDuracion(store.duracionTotal)) · Mantené apretado y arrastrá para reordenar (o usá Edit).")
            }
        }
    }

    // MARK: - Avisos fijos

    private var seccionAvisosFijos: some View {
        Section("Avisos fijos") {
            ForEach(store.plan.avisosFijos.sorted { $0.minuto < $1.minuto }) { aviso in
                Button {
                    fijoEnEdicion = aviso
                } label: {
                    HStack {
                        Text("min \(aviso.minuto)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        Text(aviso.texto)
                            .foregroundStyle(.primary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        store.plan.avisosFijos.removeAll { $0.id == aviso.id }
                    } label: {
                        Label("Borrar", systemImage: "trash")
                    }
                }
            }

            Button {
                fijoEnEdicion = AvisoFijo(minuto: 30, texto: "")
            } label: {
                Label("Agregar aviso fijo", systemImage: "plus.circle.fill")
            }
        }
    }

    // MARK: - Avisos repetidos

    private var seccionAvisosRepetidos: some View {
        Section("Avisos repetidos") {
            ForEach(store.plan.avisosRepetidos) { aviso in
                Button {
                    repetidoEnEdicion = aviso
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(aviso.texto)
                            .foregroundStyle(.primary)
                        Text(descripcion(de: aviso))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        store.plan.avisosRepetidos.removeAll { $0.id == aviso.id }
                    } label: {
                        Label("Borrar", systemImage: "trash")
                    }
                }
            }

            Button {
                repetidoEnEdicion = AvisoRepetido(cadaMinutos: 20, desdeMinuto: 20, hastaMinuto: nil, texto: "")
            } label: {
                Label("Agregar aviso repetido", systemImage: "plus.circle.fill")
            }
        }
    }

    private func descripcion(de aviso: AvisoRepetido) -> String {
        var texto = "Cada \(aviso.cadaMinutos) min, desde el min \(aviso.desdeMinuto)"
        if let hasta = aviso.hastaMinuto {
            texto += " hasta el min \(hasta)"
        } else {
            texto += ", sin límite"
        }
        return texto
    }

    // MARK: - Cronograma

    private var seccionCronograma: some View {
        Section {
            Stepper("Ver hasta el min \(horizonteMinutos)", value: $horizonteMinutos, in: 30...360, step: 15)

            let avisos = store.plan.cronograma(duracionMaximaMinutos: horizonteMinutos)
            if avisos.isEmpty {
                Text("Sin avisos por ahora. Agregá alguno arriba y acá vas a ver el plan expandido.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(avisos) { aviso in
                    HStack {
                        Text("min \(aviso.minuto)")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 70, alignment: .leading)
                        Text(aviso.texto)
                    }
                }
            }
        } header: {
            Text("Cronograma completo")
        } footer: {
            Text("Todos los avisos que van a sonar, en orden. El horizonte es solo para esta vista previa.")
        }
    }

    // MARK: - Envío al reloj

    private var seccionEnvio: some View {
        Section {
            if !conectividad.relojEmparejado {
                Label("No hay un Apple Watch emparejado con este iPhone.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else if !conectividad.appInstaladaEnReloj {
                Label("Instalá Maratón en el reloj (app Watch del iPhone → Maratón → Instalar) para poder enviar.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            Button {
                conectividad.enviar(plan: store.plan, urlDePista: store.urlDePista)
            } label: {
                Label("Enviar al reloj", systemImage: "applewatch.radiowaves.left.and.right")
            }

            if conectividad.planEncolado {
                Label("Plan encolado: llega al reloj apenas esté disponible.",
                      systemImage: "checkmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if let error = conectividad.mensajeError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            ForEach(store.plan.pistas, id: \.self) { nombre in
                HStack {
                    Text(nombre)
                        .lineLimit(1)
                    Spacer()
                    if conectividad.archivosEnReloj.contains(nombre) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if let progreso = conectividad.progresoEnvios[nombre] {
                        ProgressView(value: progreso)
                            .frame(width: 70)
                    } else {
                        Image(systemName: "circle.dashed")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }
        } header: {
            Text("Enviar al reloj")
        } footer: {
            Text("⚠️ La transferencia de MP3 es lenta: hacela con el reloj en el cargador y con WiFi. ✓ verde = ya está en el reloj (no se reenvía).")
        }
    }
}

#Preview {
    ContentView()
}
