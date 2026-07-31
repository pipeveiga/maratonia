# Maratón — audio + avisos + entrenador para correr (iOS + watchOS)

App para Apple Watch: reproduce tus MP3 durante la carrera, te interrumpe con
avisos de voz ("tomá agua", "comé un gel"), y opcionalmente registra la carrera
como entrenamiento (FC, distancia, ritmo) con un entrenador de voz que sigue tu
plan por tramos. El iPhone se usa solo antes de salir: cargar música y armar el plan.

Dos modos en el reloj (switch "Registrar carrera"):
- **Encendido**: la app es el tracker — HKWorkoutSession, FC en vivo, ritmo,
  tramos con corrección de voz, y la carrera se guarda en Salud/Fitness.
- **Apagado**: solo audio + avisos por tiempo, compatible con Runna u otro
  tracker (una sola workout session por vez en watchOS).

## Estado

- ✅ Fase 1 — Proyecto Xcode con dos targets, modelo compartido, background `audio`
- ✅ Fase 2 — App iOS: importar MP3s, armar avisos, vista previa del cronograma, persistencia
- ✅ Fase 3 — WatchConnectivity: plan + archivos al reloj, con progreso y confirmación
- ✅ Fase 4 — Reproducción en el reloj: cola con loop, pausa/siguiente, Now Playing, tiempo congelado en pausa
- ✅ Fase 5 — Avisos: voz es-AR (la música se frena mientras habla y sigue después), háptico, notificaciones locales reprogramadas en pausa/reanudar, cada aviso una sola vez
- ✅ Fase 6 — Pulido: pistas ilegibles se saltan, faltantes visibles, estados vacíos
- ✅ Fase 7 — Entrenamiento opcional: HKWorkoutSession + FC/distancia en vivo, guardado en Salud
- ✅ Fase 8 — Ritmo (pace) suavizado ~45 s desde la distancia del workout
- ✅ Fase 9 — Plan por tramos con rangos de ritmo + importador JSON (formato ChatGPT)
- ✅ Fase 10 — Entrenador de voz: anuncia tramos y corrige "apurá/aflojá" con filtros anti-molestia

## Formato JSON de tramos (para pedirle a ChatGPT)

```json
{"tramos":[
  {"nombre":"Calentamiento","km":2},
  {"nombre":"Bloque","km":3,"ritmoMin":"3:50","ritmoMax":"4:10"},
  {"nombre":"Vuelta a la calma","km":1.5,"ritmoMax":"6:00"}
]}
```

`ritmoMin` = límite rápido, `ritmoMax` = límite lento (min:seg por km); ambos
opcionales (sin ninguno = ritmo libre). Se pega en la app iOS: sección
"Tramos" → «Pegar plan de tramos (JSON)».

Prompt sugerido para guardar en ChatGPT: *"Cuando te pida el plan para mi app
del reloj, devolvémelo SOLO en ese formato JSON, sin texto extra."*

## Estructura del proyecto

| Archivo | Qué hace |
|---|---|
| `Maraton.xcodeproj` | El proyecto Xcode: dos targets y su configuración. |
| `Shared/Plan.swift` | Modelo compartido: `Plan`, `AvisoFijo`, `AvisoRepetido`, `Tramo`, expansión del cronograma y formato de ritmos. Compila en ambos targets. |
| `Maraton/MaratonApp.swift` | Punto de entrada de la app iOS. |
| `Maraton/ContentView.swift` | Pantalla única iOS: pistas, avisos, tramos, vista previa del cronograma y envío al reloj con progreso. |
| `Maraton/PlanStore.swift` | Estado central iOS: plan persistido como JSON en Documents, MP3s copiados a Documents/Pistas, duraciones. |
| `Maraton/AvisoEditores.swift` | Sheets de alta/edición de avisos fijos y repetidos, con validación. |
| `Maraton/TramosImport.swift` | Parser + pantalla para pegar el plan de tramos en JSON (formato ChatGPT). |
| `Maraton/Conectividad.swift` | Lado iPhone de WatchConnectivity: plan por `transferUserInfo`, MP3s por `transferFile`, progreso, no reenvía lo confirmado. |
| `Maraton Watch App/MaratonWatchApp.swift` | Punto de entrada watchOS; pide permiso de notificaciones al abrir. |
| `Maraton Watch App/ContentView.swift` | Lobby (plan, pistas listas, switch de modo, Play) y pantalla de reproducción (cronómetro, FC, km, ritmo, tramo, controles). |
| `Maraton Watch App/ConectividadWatch.swift` | Lado reloj: recibe y persiste plan y archivos (moviéndolos al instante), reporta inventario al iPhone. |
| `Maraton Watch App/Reproductor.swift` | Reproductor: sesión `.playback`/longForm, cola con loop, Now Playing + comandos remotos, cronómetro por reloj de sistema (pausa congela), frena/reanuda la música para la voz. |
| `Maraton Watch App/Avisador.swift` | Avisos: chequeo por segundo, voz es-AR→es-MX→es-ES, háptico, notificaciones locales reprogramables, cola secuencial; canal `anunciar()` para el entrenador. |
| `Maraton Watch App/Entrenamiento.swift` | HKWorkoutSession + builder: FC, distancia, calorías, ritmo suavizado; guarda la carrera en Salud al terminar. |
| `Maraton Watch App/EntrenadorRitmo.swift` | Entrenador: sigue tramos por distancia, anuncia cambios y corrige el ritmo con filtros (45 s de gracia, 1 corrección/min, margen 5 seg/km, mudo en pausa). |
| `*/[...].entitlements` | Permisos de HealthKit por target (los exige la firma). |

## Ciclo de desarrollo

1. Los cambios llegan por git a la rama `claude/running-audio-watchos-app-ltyxwy`.
2. En el Mac (remoto): Pull → Xcode → destino **Any iOS Device (arm64)** →
   **Product → Archive** → **Distribute App** (TestFlight). El build number va
   incrementado en cada tanda.
3. iPhone: actualizar desde TestFlight. Reloj: app Watch → verificar que se
   actualice (si no, desinstalar y reinstalar en el reloj).

## Probar en hardware real

Todo lo importante (audio en background, WatchConnectivity, FC, ritmo,
Bluetooth) solo se verifica en el reloj físico vía TestFlight. El simulador
sirve apenas para UI.

## Decisiones de arquitectura

- El reloj funciona autónomo (`WKRunsIndependentlyOfCompanionApp`), sin iPhone.
- Background mode del watch: `audio`. La sesión workout (modo entrenamiento)
  mantiene la app viva además del audio.
- Avisos "de cuidado" (agua/gel) por tiempo transcurrido; tramos y entrenador
  por distancia del workout. La pausa congela cronómetro y cronograma.
- Mientras el asistente habla, la música se pausa (no ducking) y sigue después.
- En modo solo-audio no se abre workout session: convive con Runna.
