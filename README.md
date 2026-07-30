# Maraton — audio + avisos de voz para correr (iOS + watchOS)

App para Apple Watch que reproduce tus MP3 durante una carrera larga y te
interrumpe a determinados minutos con avisos de voz ("tomá agua", "comé un
gel", "date vuelta"). Pensada para convivir en segundo plano con Runna:
**no usa HealthKit, ni GPS, ni workout sessions** — es solo audio, con
background mode `audio` en el reloj.

La app de iPhone sirve únicamente para preparar todo antes de salir:
importar los MP3, armar el plan de avisos y mandarlo al reloj.

## Requisitos

- **Xcode 16 o más nuevo** (el proyecto usa el formato de carpetas
  sincronizadas de Xcode 16 — versiones anteriores no lo abren).
- Simuladores de iOS y watchOS instalados (Xcode los ofrece descargar
  la primera vez).

## Cómo abrir y correr (Fase 1)

1. Cloná el repo y abrí `Maraton.xcodeproj` (doble click).
2. **Firma**: en la barra lateral izquierda, click en el ícono azul
   `Maraton` (arriba de todo). En el panel central, bajo TARGETS,
   seleccioná `Maraton` → pestaña **Signing & Capabilities** → en
   **Team**, elegí tu Apple ID (si no aparece: Xcode ▸ Settings ▸
   Accounts ▸ + ▸ Apple ID). Repetí lo mismo con el target
   `Maraton Watch App`.
3. **Correr en simulador de iPhone**: arriba a la izquierda, al lado del
   botón ▶, hay dos selectores: el *scheme* (elegí `Maraton`) y el
   destino (elegí un iPhone, ej. "iPhone 16"). Apretá ▶ o Cmd+R.
   Tiene que abrir una pantalla que dice "Maraton — Fase 1 OK".
4. **Correr en simulador de reloj**: cambiá el scheme a
   `Maraton Watch App`, elegí un Apple Watch como destino y ▶ de nuevo.
   Tiene que decir "Fase 1 OK".

## Estructura

- `Maraton/` — target de iOS (la app de iPhone).
- `Maraton Watch App/` — target de watchOS (la app del reloj).
- `Shared/` — código compartido entre ambos targets (el modelo de datos).
  Cualquier archivo que se agregue a estas carpetas entra solo al target,
  sin configurar nada.

## Fases

1. ✅ Proyecto con dos targets, modelo compartido, background mode `audio`.
2. App iOS: importar MP3, armar avisos, vista previa del cronograma, persistencia.
3. WatchConnectivity: plan y archivos viajan al reloj.
4. Reproducción en el reloj: cola, loop, controles, Now Playing.
5. Avisos: cronograma, voz, ducking manual, háptico, pausa que congela el tiempo.
6. Pulido: errores, archivos faltantes, estados vacíos.
