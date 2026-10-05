import SwiftUI

/// Ayuda sobre los destinos que el corredor ve en esta versión.
/// Se consulta a demanda; no interrumpe la primera carrera.
struct TutorialView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DV2.Espacio.l) {
                    paginaTutorial(icono: "figure.run", titulo: "Hoy · Salí a correr",
                        texto: "Empezá tu entrenamiento de hoy o una carrera libre con el iPhone. En Audio y avisos configurás la voz y tu música. Si usás Apple Watch, entrá en Correr con Apple Watch para enviarle tu sesión.")
                    paginaTutorial(icono: "calendar", titulo: "Plan · Organizá tu semana",
                        texto: "Creá un plan con tu objetivo y tus días disponibles. Si ya tenés uno, el calendario se abre directamente: elegí una semana y tocá cualquier entrenamiento para ver sus detalles o cambiarlo de día.")
                    paginaTutorial(icono: "chart.bar.fill", titulo: "Progreso · Mirá lo que corriste",
                        texto: "En Resumen ves tus estadísticas. En Carreras encontrás el historial, los mapas y los parciales. Los datos se leen de Apple Health; si no aparecen, el historial te explica cómo revisar los permisos.")
                    paginaTutorial(icono: "person.crop.circle", titulo: "Perfil · Ajustá Maratonia",
                        texto: "Acá están tu cuenta, objetivo, unidades, audio, Apple Watch y respaldos. También podés recuperar carreras ocultas y volver a consultar esta ayuda.")
                }
                .padding()
            }
            .navigationTitle("Cómo usar Maratonia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Listo") { dismiss() }
                }
            }
        }
    }

    private func paginaTutorial(icono: String, titulo: LocalizedStringKey,
                                texto: LocalizedStringKey) -> some View {
        TarjetaV2 {
            VStack(alignment: .leading, spacing: DV2.Espacio.s) {
                Label(titulo, systemImage: icono)
                    .font(.title3.bold())
                    .foregroundStyle(DV2.Marca.primario)
                Text(texto)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
