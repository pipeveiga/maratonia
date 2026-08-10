import SwiftUI

// Punto de entrada de la app iOS. Configura Firebase (si el
// GoogleService-Info.plist está presente) ANTES de montar la UI:
// ServicioAuth.configurar() es idempotente y no hace nada si falta
// la configuración externa — la app funciona igual sin cuenta.

@main
struct MaratonApp: App {
    init() {
        ServicioAuth.configurar()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    // Callback de Google Sign-In (esquema
                    // com.googleusercontent.apps.*). Otras URLs se ignoran.
                    ServicioAuth.manejarURL(url)
                }
        }
    }
}
