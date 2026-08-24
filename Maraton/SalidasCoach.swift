import SwiftUI

// LAS SALIDAS DEL COACH, DONDE EL CORREDOR YA ESTÁ MIRANDO.
//
// Vive en su propio archivo y no en AlternativasCoach.swift por una
// razón concreta: allá el `import SwiftUI` está adentro de un `#if
// DEBUG` (lo trajo el catálogo de previews). Con eso, una vista puesta
// al final de ese archivo COMPILA en simulador y falla al archivar con
// "cannot find type 'View' in scope" — que es exactamente lo que pasó.

// MARK: - Las salidas, donde el corredor las necesita

/// Qué hacer con UNA sesión que no se puede hacer ese día, desplegado
/// dentro de su propia pantalla.
///
/// Antes esto vivía en una pantalla aparte llamada "Coach": había que
/// saber que existía, llegar hasta ella y volver a elegir de una lista
/// la sesión que ya tenías enfrente. La inteligencia servía; el lugar
/// no. Acá el corredor ya está mirando la sesión de la que habla.
///
/// Todo local: `BuscadorDeAlternativas` calcula con el MISMO validador
/// que decide al aplicar, así que no hay red, ni espera, ni una opción
/// que se ofrezca y después no funcione.
struct SalidasDelEntrenamiento: View {
    @ObservedObject var almacen: AlmacenStore
    let programadoID: UUID
    var alAplicar: () -> Void

    @State private var aplicado: String?

    private var hoy: DiaLocal { DiaLocal(fecha: Date()) }

    private var opciones: [OpcionDeCoach] {
        BuscadorDeAlternativas.paraPreguntar(
            BuscadorDeAlternativas.opciones(para: programadoID, en: almacen.almacen, hoy: hoy))
    }

    private var dias: [OpcionDeCoach] { opciones.filter { $0.dia != nil } }

    /// Las que cambian la sesión sin moverla. "Mantener" queda afuera:
    /// no cambiar ya es cerrar esto.
    private var otras: [OpcionDeCoach] {
        opciones.filter { $0.dia == nil && $0.cambio.tipoDeAdaptacion != nil }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DV2.Espacio.m) {
            if let aplicado {
                Label(aplicado, systemImage: "checkmark.circle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DV2.Semantico.exito)
            } else {
                if !dias.isEmpty {
                    Text("Movela a…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    FlujoDeChips {
                        ForEach(dias) { opcion in
                            Button { aplicar(opcion) } label: {
                                VStack(spacing: 1) {
                                    Text(opcion.etiquetaCorta())
                                        .font(.subheadline.weight(.semibold))
                                    // Decir cuál es un día prestado: no
                                    // es lo mismo correr un día antes
                                    // que estrenar un día que no corrés.
                                    if opcion.detalle != String(localized: "Está libre") {
                                        Text("no habitual")
                                            .font(.system(size: 9, weight: .semibold))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .foregroundStyle(DV2.Marca.primario)
                                .padding(.horizontal, DV2.Espacio.m)
                                .padding(.vertical, DV2.Espacio.s)
                                .background(DV2.Marca.primario.opacity(0.10), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                if !otras.isEmpty {
                    Text(dias.isEmpty ? "No hay otro día libre. Podés…" : "O si preferís…")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    ForEach(otras) { opcion in
                        Button { aplicar(opcion) } label: {
                            HStack(spacing: DV2.Espacio.s) {
                                Image(systemName: opcion.icono)
                                    .font(.footnote)
                                    .foregroundStyle(DV2.Marca.primario)
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(opcion.titulo)
                                        .font(.subheadline)
                                        .foregroundStyle(.primary)
                                    if let detalle = opcion.detalle {
                                        Text(detalle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                            }
                            .padding(.vertical, DV2.Espacio.s)
                            .padding(.horizontal, DV2.Espacio.m)
                            .background(DV2.Superficie.elevada,
                                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                if dias.isEmpty && otras.isEmpty {
                    Text("Esta sesión no se puede mover ni acortar.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Se aplica por el ÚNICO aplicador, que revalida y deja rastro en
    /// el historial de adaptaciones. Sin atajos: lo que confirma el
    /// corredor pasa por donde pasa todo lo demás.
    private func aplicar(_ opcion: OpcionDeCoach) {
        guard ValidadorDeCoach.validar(opcion.cambio, en: almacen.almacen,
                                       hoy: hoy, origen: .corredor).permitido else { return }
        AplicadorAdaptacion.aplicar([opcion.cambio], a: &almacen.almacen,
                                    hoy: hoy, origen: .coach, motivo: opcion.titulo,
                                    pedidoPorElCorredor: true)
        withAnimation { aplicado = opcion.titulo }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { alAplicar() }
    }
}

/// "¿Por qué me toca esto?", dentro del entrenamiento del que habla.
///
/// De las tres cosas que hacía la pantalla Coach, esta es la única que
/// necesita el modelo: mover una sesión lo resuelve el buscador local, y
/// "cómo vengo" es la pregunta de Progreso. Explicar para qué sirve una
/// sesión dentro de un plan, no.
struct PorQueEsteEntrenamiento: View {
    @ObservedObject var almacen: AlmacenStore
    let programado: EntrenamientoProgramado
    @ObservedObject private var coach = ServicioCoach.compartido
    @State private var explicacion: CoachWorkoutExplanation?

    var body: some View {
        if ServicioCoach.disponible {
            if let e = explicacion {
                VStack(alignment: .leading, spacing: DV2.Espacio.s) {
                    Text(e.queEs)
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(e.paraQueSirve, systemImage: "target")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Label(e.comoEncararlo, systemImage: "figure.run")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, DV2.Espacio.xs)
            } else {
                Button {
                    Task { explicacion = await pedir() }
                } label: {
                    HStack {
                        Label("¿Por qué me toca esto?", systemImage: "questionmark.circle")
                        Spacer()
                        if coach.ocupado { ProgressView() }
                    }
                    .contentShape(Rectangle())
                }
                .disabled(coach.ocupado)
            }
        }
    }

    /// `@MainActor`: arma el contexto con `ContextoCoach.desde`, que
    /// está aislado al actor principal, y después escribe `@State`.
    /// DEVUELVE en vez de asignar: escribir el `@State` desde adentro
    /// de una función async del View compila en Debug y lo rechaza el
    /// archive (módulo completo) con "self is immutable". Separar el
    /// cálculo de la escritura lo deja válido en los dos.
    @MainActor
    private func pedir() async -> CoachWorkoutExplanation? {
        let hoy = DiaLocal(fecha: Date())
        let eventos = DetectorEventos.detectar(EntradaDeteccion(
            hoy: hoy, almacen: almacen.almacen, analisis: nil,
            kmSemanaActual: nil, pedidoExplicito: true))
        let contexto = ContextoCoach.desde(almacen.almacen, hoy: hoy,
                                           historial: [], eventos: eventos)
        return await coach.pedir(CoachWorkoutExplanation.self,
                                 accion: "explicar", contexto: contexto,
                                 detalle: programado.definicion.nombre,
                                 programadoID: programado.id)
    }
}
