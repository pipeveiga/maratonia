# Maratón — audio y avisos de voz para corridas

App de dos partes:

- **iPhone**: importar MP3s, armar el plan de avisos, mandarlo al reloj.
- **Apple Watch**: reproducir la música y hablar los avisos, de forma autónoma, en segundo plano detrás de Runna.

Sin HealthKit, sin GPS, sin workout sessions: es solo una app de audio (background mode `audio`), para no pisar el tracking de Runna.

## Estado

- ✅ **Fase 1** — Proyecto base: dos targets, modelo compartido, background audio configurado en el watch.
- ⬜ Fase 2 — App iOS completa (importar MP3s, avisos, cronograma, persistencia)
- ⬜ Fase 3 — WatchConnectivity (plan + archivos al reloj)
- ⬜ Fase 4 — Reproducción en el reloj (cola, loop, Now Playing)
- ⬜ Fase 5 — Avisos (voz, ducking, háptico, notificaciones, pausa)
- ⬜ Fase 6 — Pulido

## Estructura

```
Maraton.xcodeproj        → el proyecto Xcode (abrí este archivo)
Shared/Modelos.swift     → modelo de datos (Plan, avisos), compartido por ambos targets
Maraton/                 → app de iPhone
Maraton Watch App/       → app del reloj (Info.plist tiene el background mode "audio")
```

## Cómo correrlo (Fase 1)

1. Cloná el repo en tu Mac y hacé doble click en `Maraton.xcodeproj`.
2. Arriba a la izquierda, al lado del botón ▶, está el **selector de scheme**. Elegí **Maraton** y como destino un **iPhone 15** (o similar) del simulador. Apretá ▶.
3. Cambiá el scheme a **Maraton Watch App** y como destino un **Apple Watch** del simulador. Apretá ▶.

Si Xcode se queja de firma ("Signing for … requires a development team"):
1. Click en **Maraton** (el ícono azul, arriba de todo en el panel izquierdo).
2. Pestaña **Signing & Capabilities**.
3. En **Team**, elegí tu Apple ID personal (si no aparece: Xcode → Settings → Accounts → "+" → agregá tu Apple ID).
4. Repetí para el target **Maraton Watch App** (lista de targets a la izquierda dentro de esa misma pantalla).

## Nota sobre bundle IDs

- iPhone: `com.pipeveiga.maraton`
- Watch: `com.pipeveiga.maraton.watchkitapp`

Si algún día los cambiás, también hay que actualizar `WKCompanionAppBundleIdentifier` en `Maraton Watch App/Info.plist` para que siga apuntando al bundle ID del iPhone.
