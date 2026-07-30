# Maratón

App de audio para carreras largas: reproduce tus MP3 en el Apple Watch (sin
iPhone) y te interrumpe a determinados minutos con avisos de voz ("tomá agua",
"comé un gel", "date vuelta"). Diseñada para convivir con otra app de tracking
(Runna): no usa HealthKit, no abre workout sessions, no usa GPS. Solo audio,
con background mode `audio` en el reloj.

## Estructura

- `Maraton.xcodeproj` — proyecto Xcode con los dos targets.
- `Maraton/` — app iOS: importar MP3s, armar el plan de avisos, enviarlo al reloj.
- `Maraton Watch App/` — app watchOS: reproduce y ejecuta el plan de forma autónoma.
- `Shared/Plan.swift` — modelo de datos compartido entre ambos targets.

## Cómo abrir

1. Cloná el repo y abrí `Maraton.xcodeproj` con Xcode 15 o superior.
2. Para correr en simulador no hace falta configurar firma.
3. Para correr en dispositivos: seleccioná tu equipo (Apple ID personal) en
   **Signing & Capabilities** de ambos targets.

## Estado

- [x] Fase 1 — proyecto, targets, modelo compartido, background audio
- [ ] Fase 2 — app iOS completa (importar MP3s, avisos, cronograma, persistencia)
- [ ] Fase 3 — WatchConnectivity (plan + archivos al reloj)
- [ ] Fase 4 — reproducción en el reloj (cola, loop, Now Playing)
- [ ] Fase 5 — avisos (voz, ducking, háptico, notificaciones, pausa)
- [ ] Fase 6 — pulido
