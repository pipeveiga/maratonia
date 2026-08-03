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
    @State private var mostrandoImportadorTramos = false

    /// Horizonte de la vista previa del cronograma (solo afecta la vista,
    /// no el plan). Se recuerda entre aperturas de la app.
    @AppStorage("horizonteCronograma") private var horizonteMinutos = 120

    var body: some View {
        NavigationStack {
            List {
                seccionResumenPlan
                seccionPistas
                seccionAvisosFijos
                seccionAvisosRepetidos
                seccionTramos
                seccionCronograma
                seccionEnvio
                seccionCarreras
            }
            .navigationTitle("Maratonia")
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
            .sheet(isPresented: $mostrandoImportadorTramos) {
                ImportadorTramos { tramos in
                    store.plan.tramos = tramos
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

    // MARK: - Resumen del plan (cabecera)

    private var seccionResumenPlan: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Nombre del plan", text: $store.plan.nombre)
                    .font(.title3.bold())
                HStack(spacing: 0) {
                    estadistica("music.note", "\(store.plan.pistas.count)", "pistas")
                    estadistica("clock.fill", formatearDuracion(store.duracionTotal), "música")
                    estadistica("bell.fill", "\(store.plan.cronograma(duracionMaximaMinutos: horizonteMinutos).count)", "avisos")
                    estadistica("speedometer", "\(store.plan.tramosActivos.count)", "tramos")
                }
            }
            .padding(.vertical, 4)
        }
    }

    /// Mini-estadística de la cabecera: ícono + valor + nombre.
    private func estadistica(_ icono: String, _ valor: String, _ nombre: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: icono)
                    .font(.caption2)
                    .foregroundStyle(.tint)
                Text(valor)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Text(nombre)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pistas

    private var seccionPistas: some View {
        Section {
            if store.plan.pistas.isEmpty {
                Text("Todavía no hay pistas. Importá tus MP3 para armar la cola.")
                    .foregroundStyle(.secondary)
            }

            ForEach(store.plan.pistas, id: \.self) { nombre in
                HStack(spacing: 10) {
                    IconoAjuste(sistema: "music.note", color: .blue)
                    Text(nombreSinExtension(nombre))
                        .lineLimit(1)
                    Spacer()
                    if let duracion = store.duraciones[nombre] {
                        Text(formatearDuracion(duracion))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    } else {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
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
        Section {
            ForEach(store.plan.avisosFijos.sorted { $0.minuto < $1.minuto }) { aviso in
                Button {
                    fijoEnEdicion = aviso
                } label: {
                    HStack(spacing: 10) {
                        InsigniaMinuto(minuto: aviso.minuto)
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
        } header: {
            Text("Avisos fijos")
        }
    }

    // MARK: - Avisos repetidos

    private var seccionAvisosRepetidos: some View {
        Section {
            ForEach(store.plan.avisosRepetidos) { aviso in
                Button {
                    repetidoEnEdicion = aviso
                } label: {
                    HStack(spacing: 10) {
                        IconoAjuste(sistema: "repeat", color: .purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(aviso.texto)
                                .foregroundStyle(.primary)
                            Text(descripcion(de: aviso))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
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
        } header: {
            Text("Avisos repetidos")
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

    // MARK: - Tramos con ritmo objetivo

    private var seccionTramos: some View {
        Section {
            ForEach(store.plan.tramosActivos) { tramo in
                HStack(spacing: 10) {
                    IconoAjuste(sistema: "speedometer", color: .green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(tramo.nombre)
                        Text(tramo.descripcion)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        store.plan.tramos?.removeAll { $0.id == tramo.id }
                    } label: {
                        Label("Borrar", systemImage: "trash")
                    }
                }
            }

            Button {
                mostrandoImportadorTramos = true
            } label: {
                Label("Pegar plan de tramos (JSON)", systemImage: "doc.on.clipboard")
            }
        } header: {
            Text("Tramos con ritmo objetivo")
        } footer: {
            Text("El reloj anuncia cada tramo y te avisa por voz si vas más rápido o más lento que el rango. Necesita «Registrar carrera» activado en el reloj.")
        }
    }

    // MARK: - Historial de carreras

    private var seccionCarreras: some View {
        Section {
            NavigationLink {
                CarrerasView()
            } label: {
                HStack(spacing: 10) {
                    IconoAjuste(sistema: "map.fill", color: .teal)
                    Text("Mis carreras")
                }
            }
        } footer: {
            Text("Historial con recorrido en el mapa, ritmo y FC de las carreras registradas con el reloj.")
        }
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
                    HStack(spacing: 10) {
                        InsigniaMinuto(minuto: aviso.minuto)
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
                Label("Instalá Maratonia en el reloj (app Watch del iPhone → Maratonia → Instalar) para poder enviar.",
                      systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }

            Button {
                conectividad.enviar(plan: store.plan, urlDePista: store.urlDePista)
            } label: {
                Label("Enviar al reloj", systemImage: "applewatch.radiowaves.left.and.right")
            }
            .disabled(store.plan.pistas.isEmpty
                      && store.plan.avisosFijos.isEmpty
                      && store.plan.avisosRepetidos.isEmpty)

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
