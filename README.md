# MaratonAudio

App de audio para corridas largas: reproduce tus MP3 en el Apple Watch (sin iPhone) y te interrumpe con avisos de voz por tiempo ("tomá agua", "comé un gel", "date vuelta"). Convive con Runna en segundo plano: **no usa HealthKit, ni GPS, ni workout sessions** — es solo audio, como Spotify conviviendo con Strava.

## Estructura del proyecto

```
MaratonAudio.xcodeproj      → el proyecto Xcode (dos targets)
MaratonAudio/               → código de la app iOS
MaratonAudio Watch App/     → código de la app watchOS
Shared/                     → código compartido entre ambas (modelo de datos)
```

- `Shared/Plan.swift` — el modelo: `Plan`, `AvisoFijo`, `AvisoRepetido`, todos `Codable` para poder guardarlos y mandarlos al reloj. Incluye `cronograma()`, que expande fijos + repetidos en la lista minuto a minuto.
- `MaratonAudio/MaratonAudioApp.swift` y `ContentView.swift` — entrada y pantalla placeholder de la app iOS (Fase 1).
- `MaratonAudio Watch App/MaratonAudioWatchApp.swift` y `ContentView.swift` — lo mismo para el reloj.
- `MaratonAudio Watch App/Info.plist` — configuración del reloj: app watchOS moderna, funciona sin el iPhone presente, y **background mode `audio`** (la clave para que siga sonando detrás de Runna).

El proyecto usa "carpetas sincronizadas" de Xcode 16: cualquier archivo nuevo que aparezca en esas carpetas (por ejemplo al bajar una fase nueva con `git pull`) se suma solo al proyecto, sin tocar nada.

## Requisitos

- Mac con **Xcode 16 o más nuevo** (App Store → buscar "Xcode").
- Una Apple ID (la tuya normal sirve; no hace falta cuenta paga de desarrollador para probar en tus dispositivos).

## Cómo abrirlo la primera vez

1. Cloná o descargá este repo en tu Mac.
2. Doble click en `MaratonAudio.xcodeproj`.
3. **Firma (una sola vez):**
   - En la barra lateral izquierda, click en el primer ítem (el ícono azul "MaratonAudio").
   - En el panel central, bajo **TARGETS**, seleccioná **MaratonAudio** → pestaña **Signing & Capabilities** → en **Team**, elegí tu Apple ID (si no aparece: Xcode → Settings → Accounts → botón "+" → agregá tu Apple ID).
   - Repetí lo mismo para el target **MaratonAudio Watch App**.
4. **Correr la app iOS en el simulador:** arriba a la izquierda, al lado del botón ▶, click donde dice el nombre del scheme → elegí **MaratonAudio** → a la derecha elegí un simulador de iPhone → botón ▶ (o Cmd+R).
5. **Correr la app del reloj:** mismo lugar → elegí el scheme **MaratonAudio Watch App** → elegí un simulador de Apple Watch → ▶.

Si Xcode se queja de los bundle identifiers, decímelo con el error exacto.

## Fases

- [x] **Fase 1** — Proyecto con dos targets, modelo compartido, background audio configurado. Compila y abre en ambos simuladores.
- [ ] **Fase 2** — App iOS completa: importar MP3s, armar avisos, vista previa del cronograma, persistencia.
- [ ] **Fase 3** — WatchConnectivity: plan y archivos viajan al reloj.
- [ ] **Fase 4** — Reproducción en el reloj: cola, loop, controles, Now Playing. *(Desde acá conviene probar en el reloj físico.)*
- [ ] **Fase 5** — Avisos: cronograma, voz, ducking, háptico, notificaciones, pausa que congela el tiempo.
- [ ] **Fase 6** — Pulido: errores, archivos faltantes, estados vacíos.
