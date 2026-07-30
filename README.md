# Maratón — audio para corridas (iOS + watchOS)

App para Apple Watch que reproduce MP3s propios durante una carrera y a determinados
minutos interrumpe con avisos de voz ("tomá agua", "comé un gel"). El iPhone se usa
solo antes de salir, para cargar archivos y armar el plan. El reloj funciona autónomo,
en segundo plano, conviviendo con la app de tracking (Runna).

**Restricción de arquitectura:** esta app NO abre `HKWorkoutSession` ni usa HealthKit
ni GPS. Es solo audio (background mode `audio`, `AVAudioSession .playback`), para no
pisar la sesión de entrenamiento de Runna. Todos los avisos son por tiempo, nunca
por distancia.

## Estructura

| Carpeta / archivo | Qué es |
|---|---|
| `Maraton.xcodeproj` | El proyecto Xcode (dos targets: iPhone y Watch) |
| `Shared/Modelos.swift` | Modelo de datos (`Plan`, avisos) compartido por ambos targets |
| `Maraton/` | App de iPhone (importar MP3s, armar plan, enviar al reloj) |
| `Maraton Watch App/` | App del reloj (recibir, reproducir, avisar) |
| `Maraton Watch App/Info.plist` | Declara el background mode `audio` y que el reloj corre sin iPhone |

## Cómo abrirlo y correrlo (Fase 1)

1. Cloná el repo y hacé doble clic en `Maraton.xcodeproj`.
2. **Firma** (necesario incluso para el simulador en algunos casos, e imprescindible
   para el reloj físico): en la barra lateral izquierda clic en el ícono azul
   "Maraton" (raíz del proyecto) → pestaña **Signing & Capabilities** → elegí tu
   **Team** (tu Apple ID). Repetilo para los dos targets: `Maraton` y
   `Maraton Watch App` (se eligen en la columna TARGETS de esa misma pantalla).
   - Si Xcode se queja del bundle identifier, cambiá `com.pipeveiga.maraton` por
     algo único tuyo — pero cambialo en los DOS targets (el del reloj debe ser
     el mismo con `.watchkitapp` al final) **y** en
     `Maraton Watch App/Info.plist` → `WKCompanionAppBundleIdentifier`.
3. **Correr la app de iPhone:** arriba a la izquierda, al lado del botón ▶, hay un
   selector de esquema. Elegí **Maraton** y a la derecha un simulador de iPhone
   (ej. "iPhone 15"). Apretá ▶.
4. **Correr la app del reloj:** en el mismo selector elegí **Maraton Watch App**
   y un simulador de Apple Watch. Apretá ▶.

## Plan de fases

- [x] **Fase 1** — Proyecto con dos targets, modelo compartido, background `audio`
- [ ] **Fase 2** — App iOS completa (importar, avisos, cronograma, persistencia)
- [ ] **Fase 3** — WatchConnectivity (plan + archivos al reloj)
- [ ] **Fase 4** — Reproducción en el reloj (cola, loop, Now Playing)
- [ ] **Fase 5** — Avisos (voz, ducking manual, háptico, notificaciones, pausa)
- [ ] **Fase 6** — Pulido

**Prueba en reloj físico:** desde la **Fase 3** conviene probar en el hardware real
(la transferencia de archivos por WatchConnectivity no se comporta igual en el
simulador), y desde la **Fase 4** es obligatorio: audio en background, Bluetooth y
convivencia con Runna no se pueden verificar en el simulador.
