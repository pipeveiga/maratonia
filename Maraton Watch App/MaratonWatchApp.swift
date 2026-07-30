import SwiftUI

// Punto de entrada de la app watchOS. Por ahora solo abre ContentView;
// en fases siguientes acá se van a inicializar WatchConnectivity,
// el reproductor de audio y el cronograma de avisos.

@main
struct MaratonWatchApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
