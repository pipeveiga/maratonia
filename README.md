# Maratón — audio + avisos para correr (iOS + watchOS)

App de audio para Apple Watch: reproduce tus MP3 durante una carrera larga y te
interrumpe a determinados minutos con avisos de voz ("tomá agua", "comé un gel").
Convive con Runna en segundo plano: **no** usa HealthKit, GPS ni workout sessions.

## Estado: Fase 3

- ✅ Fase 1 — Proyecto Xcode con dos targets, modelo compartido, background `audio`
- ✅ Fase 2 — App iOS: importar MP3s, armar avisos, vista previa del cronograma, persistencia
- ✅ Fase 3 — WatchConnectivity: plan + archivos al reloj, con progreso y confirmación
- ✅ Fase 4 — Reproducción en el reloj: cola con loop, pausa/siguiente, Now Playing, tiempo congelado en pausa
- ⬜ Fase 4 — Reproducción en el reloj (cola, loop, Now Playing)
- ⬜ Fase 5 — Avisos (voz, ducking, háptico, notificaciones, pausa)
- ⬜ Fase 6 — Pulido

## Estructura del proyecto

| Archivo | Qué hace |
|---|---|
| `Maraton.xcodeproj` | El proyecto Xcode: define los dos targets y su configuración. Se abre con doble click. |
| `Shared/Plan.swift` | Modelo de datos compartido: `Plan`, `AvisoFijo`, `AvisoRepetido`, y la función `cronograma()` que expande el plan a la lista de avisos concretos. Compila en los dos targets. |
| `Maraton/MaratonApp.swift` | Punto de entrada de la app iOS. |
| `Maraton/ContentView.swift` | Pantalla única de la app iOS: pistas (importar/reordenar/borrar), avisos fijos y repetidos, vista previa del cronograma y botón de envío (deshabilitado hasta Fase 3). |
| `Maraton/PlanStore.swift` | Estado central de la app iOS: guarda el plan como JSON en Documents ante cada cambio, copia los MP3 importados a Documents/Pistas y calcula duraciones. |
| `Maraton/AvisoEditores.swift` | Las dos pantallas (sheets) para crear/editar avisos fijos y repetidos, con validación. |
| `Maraton/Conectividad.swift` | Lado iPhone de WatchConnectivity: envía el plan (`transferUserInfo`) y los MP3 (`transferFile`), muestra progreso y no reenvía lo que el reloj ya confirmó tener. |
| `Maraton Watch App/ConectividadWatch.swift` | Lado reloj: recibe plan y archivos (moviéndolos a Documents al instante), los persiste, y le reporta al iPhone qué archivos tiene. |
| `Maraton Watch App/Reproductor.swift` | El reproductor: AVAudioSession `.playback`/longForm, cola de AVAudioPlayer encadenada con loop, comandos remotos + Now Playing, tiempo de sesión basado en el reloj del sistema (la pausa lo congela). |
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

## Cómo probar la Fase 2 (en el simulador de iPhone)

1. Scheme **Maraton** + un iPhone → ▶.
2. Para tener un MP3 dentro del simulador: abrí **Safari del iPhone simulado**,
   buscá cualquier MP3 de prueba (por ej. en archive.org) y descargalo.
   Queda en la app **Archivos** del simulador, carpeta Descargas.
3. En Maratón: **Importar MP3** → navegá a Descargas → elegí el archivo.
   Tiene que aparecer en la lista con su duración.
4. Agregá avisos fijos y repetidos, mirá el cronograma expandido abajo.
5. **Cerrá la app del todo y volvé a abrirla**: el plan y las pistas tienen
   que seguir ahí (persistencia).

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
