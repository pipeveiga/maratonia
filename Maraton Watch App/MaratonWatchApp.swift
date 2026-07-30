import SwiftUI

/// Punto de entrada de la app del reloj. Por ahora solo abre ContentView;
/// el receptor de WatchConnectivity y el reproductor llegan en Fases 3 y 4.
@main
struct MaratonWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
