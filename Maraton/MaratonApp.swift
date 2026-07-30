import SwiftUI

// Punto de entrada de la app iOS. Por ahora solo abre ContentView;
// en fases siguientes acá se van a inicializar la persistencia
// y la sesión de WatchConnectivity.

@main
struct MaratonApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
