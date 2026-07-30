import SwiftUI

/// Punto de entrada de la app de iPhone. Por ahora solo abre ContentView;
/// en Fase 2 acá se va a crear el estado compartido del plan.
@main
struct MaratonApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
