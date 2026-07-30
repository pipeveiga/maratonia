import SwiftUI

/// Punto de entrada de la app de iPhone. Solo declara cuál es la
/// primera pantalla; toda la lógica va a vivir en las vistas.
@main
struct MaratonApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
