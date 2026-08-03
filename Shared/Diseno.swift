import SwiftUI
import Foundation

// Sistema de diseño mínimo compartido entre iPhone y reloj.
// Una sola fuente para radios, insignias y celdas: si mañana cambia el
// estilo, se toca acá y las dos apps se mueven juntas.

enum Diseno {
    static let radioTarjeta: CGFloat = 12
    static let radioInsignia: CGFloat = 7
}

/// Insignia de minuto ("min 20"): reemplaza el texto gris suelto en las
/// listas de avisos y el cronograma. Ancho fijo para que la columna de
/// minutos quede alineada.
struct InsigniaMinuto: View {
    let minuto: Int

    var body: some View {
        Text("min \(minuto)")
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .frame(minWidth: 62)
            .background(Color.accentColor.opacity(0.15),
                        in: RoundedRectangle(cornerRadius: Diseno.radioInsignia))
            .foregroundStyle(Color.accentColor)
    }
}

/// Ícono estilo Ajustes de Apple: símbolo blanco sobre cuadradito de
/// color. Da identidad visual a cada tipo de fila sin ruido.
struct IconoAjuste: View {
    let sistema: String
    let color: Color

    var body: some View {
        Image(systemName: sistema)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 28, height: 28)
            .background(color, in: RoundedRectangle(cornerRadius: Diseno.radioInsignia))
    }
}

/// "Cancion.mp3" -> "Cancion", para mostrar nombres de pista limpios.
func nombreSinExtension(_ nombreArchivo: String) -> String {
    (nombreArchivo as NSString).deletingPathExtension
}
