# Maratón — audio + avisos para correr (iOS + watchOS)

App de audio para Apple Watch: reproduce tus MP3 durante una carrera larga y te
interrumpe a determinados minutos con avisos de voz ("tomá agua", "comé un gel").
Convive con Runna en segundo plano: **no** usa HealthKit, GPS ni workout sessions.

## Estado: Fase 1

- ✅ Proyecto Xcode con dos targets (iOS + watchOS)
- ✅ Modelo de datos compartido (`Shared/Plan.swift`)
- ✅ Background mode `audio` configurado en el target del reloj
- ⬜ Fase 2 — App iOS: importar MP3s, armar avisos, vista previa, persistencia
- ⬜ Fase 3 — WatchConnectivity (plan + archivos al reloj)
- ⬜ Fase 4 — Reproducción en el reloj (cola, loop, Now Playing)
- ⬜ Fase 5 — Avisos (voz, ducking, háptico, notificaciones, pausa)
- ⬜ Fase 6 — Pulido

## Estructura del proyecto

| Archivo | Qué hace |
|---|---|
| `Maraton.xcodeproj` | El proyecto Xcode: define los dos targets y su configuración. Se abre con doble click. |
| `Shared/Plan.swift` | Modelo de datos compartido: `Plan`, `AvisoFijo`, `AvisoRepetido`, y la función `cronograma()` que expande el plan a la lista de avisos concretos. Compila en los dos targets. |
| `Maraton/MaratonApp.swift` | Punto de entrada de la app iOS. |
| `Maraton/ContentView.swift` | Pantalla iOS de Fase 1: muestra un cronograma de ejemplo para verificar el modelo. Se reemplaza en Fase 2. |
| `Maraton Watch App/MaratonWatchApp.swift` | Punto de entrada de la app watchOS. |
| `Maraton Watch App/ContentView.swift` | Pantalla watch de Fase 1: placeholder de verificación. |

## Cómo abrirlo y correrlo (primera vez)

Necesitás un Mac con **Xcode 15 o más nuevo** (App Store → buscar "Xcode").

1. **Cloná el repo** (o bajate el ZIP desde GitHub) y hacé doble click en
   `Maraton.xcodeproj`.

2. **Firma (signing)** — solo hace falta para correr en dispositivos físicos,
   pero conviene dejarlo listo ya:
   - En la barra lateral izquierda, click en el primer ítem (ícono azul, "Maraton").
   - En la columna del medio, bajo **TARGETS**, click en **Maraton**.
   - Arriba, pestaña **Signing & Capabilities**.
   - En **Team**, elegí tu Apple ID. Si no aparece: Xcode → Settings → Accounts →
     botón "+" → agregá tu Apple ID, y volvé acá.
   - Repetí lo mismo para el target **Maraton Watch App**.
   - Si Xcode se queja de que el bundle identifier ya está en uso, cambiá
     `com.pipeveiga.maraton` por otro (ej. `com.pipeveiga.maraton2`) en **ambos**
     targets — en el watch tiene que quedar el mismo prefijo + `.watchkitapp`.

3. **Correr la app iOS en el simulador:**
   - Arriba en el medio hay un selector que dice `Maraton > ...`. Click en la
     parte izquierda (el *scheme*) y elegí **Maraton**. Click en la parte derecha
     y elegí un iPhone (ej. "iPhone 16").
   - Botón ▶ (arriba a la izquierda) o `Cmd + R`.
   - Tiene que abrir el simulador y mostrar "Fase 1: proyecto y modelo de datos"
     con un cronograma de ejemplo.

4. **Correr la app watch en el simulador:**
   - Mismo selector: scheme **Maraton Watch App**, destino un Apple Watch
     (ej. "Apple Watch SE (44mm)").
   - ▶ o `Cmd + R`. Tiene que mostrar "Fase 1 OK".

Si algo de esto falla, copiá el error tal cual (el texto rojo del panel de la
izquierda o del centro) y pegámelo.

## Cuándo probar en hardware real

- **Fases 1 y 2**: simulador alcanza.
- **Fase 3 en adelante: reloj y iPhone físicos.** `transferFile` /
  `transferUserInfo` de WatchConnectivity no funcionan de forma confiable entre
  simuladores, y todo lo de audio en background (muñeca baja, Runna al frente,
  auriculares Bluetooth) solo se puede verificar en el reloj de verdad.

## Decisiones de arquitectura (fijas)

- Sin `HKWorkoutSession`, sin HealthKit, sin GPS: Runna es el tracker.
- Background mode del watch: solo `audio` (`UIBackgroundModes = audio`).
- `WKRunsIndependentlyOfCompanionApp = YES`: el reloj funciona sin el iPhone.
- Avisos por tiempo transcurrido, nunca por distancia.
- Deployment: iOS 17 / watchOS 10.
