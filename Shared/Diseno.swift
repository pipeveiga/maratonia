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

/// Pastillita de dato ("5,2 km" · "28:30"): para filas de listas.
struct Chip: View {
    let texto: String

    var body: some View {
        Text(texto)
            .font(.caption.weight(.medium))
            .monospacedDigit()
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.secondary.opacity(0.15), in: Capsule())
    }
}

/// Ficha de estadística (título chico de color + valor grande), para
/// grillas de métricas como el detalle de una carrera.
struct TarjetaEstadistica: View {
    let titulo: LocalizedStringKey
    let valor: String
    let icono: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(titulo, systemImage: icono)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(color)
            Text(valor)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Diseno.radioTarjeta))
    }
}
