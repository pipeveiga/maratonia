# 🏃 Maratonia — App de running para Apple Watch + iPhone

**Asistente de carrera completo para Apple Watch**: reproduce tu música, te guía
por voz con un entrenador que sigue tu plan de tramos, registra la carrera
(frecuencia cardíaca, ritmo, GPS) y la guarda en Apple Salud con el recorrido
en el mapa. El iPhone es el centro de comando: cargás la música, armás el plan
de entrenamiento (con un formato JSON pensado para generarlo con ChatGPT) y
revisás el historial de carreras con mapa y métricas.

Pensada para correr **con el reloj solo** — sin iPhone encima — con auriculares
Bluetooth, incluso sin señal.

---

## ✨ Qué hace

### En el Apple Watch (la app principal)
- 🎵 **Música propia**: reproduce MP3s transferidos desde el iPhone, en cola con
  loop infinito, controles nativos (Now Playing) y pantalla apagada.
- 🎧 **Modo Spotify**: alternativamente, corré con la música de otra app — los
  avisos por voz le bajan el volumen (audio ducking) mientras hablan.
- 🗣️ **Avisos por voz en español**: "tomá agua", "comé un gel" — programados por
  tiempo (fijos o repetidos), con vibración y notificación local. La música se
  pausa mientras habla el asistente y sigue donde quedó.
- 🏋️ **Sesión de entrenamiento real** (HealthKit): FC en vivo, distancia,
  calorías, y guardado automático en Salud/Fitness al terminar.
- ⚡ **Entrenador de ritmo**: seguís un plan por tramos ("3 km a 3:50–4:10") y
  la voz te anuncia cada tramo y te corrige — "vas a 4:25, apurá un poco" — con
  filtros anti-molestia (suavizado de ritmo ~45 s, margen, máx. 1 corrección
  por minuto).
- 📢 **Splits por kilómetro**: "Kilómetro 5: 4:12 el último".
- 🚩 **Avisos por distancia**: "en el km 5" o "cada 3 km" — además de los por tiempo (usan la distancia del entrenamiento).
- ❤️ **Zonas de FC** (Z1–Z5) con colores, según tu FC máxima configurable.
- 🗺️ **Ruta GPS**: el recorrido queda dibujado en el mapa de Fitness.
- ⏸️ **Pausa total**: congela música, cronómetro, avisos, workout y GPS a la
  vez; las notificaciones pendientes se reprograman al reanudar.
- 📱 **UI de carrera en 3 páginas deslizables** (como la app Entrenamiento de
  Apple): sesión ← métricas → música. Ritmo con color semáforo (verde en
  rango / naranja afuera). Cuenta regresiva 3-2-1 con hápticos al arrancar.
- 🚫 **Cancelar sesión**: descarta el entrenamiento sin ensuciar el historial.
- 🤝 **Modo convivencia**: apagando "Registrar carrera", la app es solo audio y
  convive con otro tracker (Runna, Strava) — una sola workout session por vez
  en watchOS.

### En el iPhone (centro de comando)
- 📥 Importación de MP3s (file importer + security-scoped resources), cola
  reordenable con duraciones.
- ⏰ Editor de avisos fijos y repetidos con vista previa del cronograma
  expandido.
- 🧠 **Planes de tramos**: editor manual, planes sugeridos de un toque, y (en Avanzado) importación por JSON — formato diseñado para pedírselo a
  ChatGPT y pegarlo directo:
  ```json
  {"tramos":[
    {"nombre":"Calentamiento","km":2},
    {"nombre":"Bloque","km":3,"ritmoMin":"3:50","ritmoMax":"4:10"}
  ]}
  ```
- ⌚ **Envío al reloj** por WatchConnectivity con progreso por archivo y
  confirmación de qué tiene el reloj (no se reenvía lo que ya está).
- 🗺️ **"Mis carreras"**: historial leído de Salud con el recorrido dibujado en
  MapKit, ritmo promedio, FC y calorías por carrera.
- 💾 Persistencia automática de todo el plan.

---

## 🏗️ Arquitectura

Proyecto Xcode con **dos targets SwiftUI** (iOS 17+ / watchOS 10+) y un modelo
de datos compartido. Comunicación por WatchConnectivity; el reloj funciona de
forma 100 % autónoma una vez recibido el plan.

```
Shared/
  Plan.swift            Modelo Codable compartido: Plan, avisos, tramos,
                        expansión del cronograma, formato de ritmos
Maraton/ (iOS)
  PlanStore.swift       Estado + persistencia JSON + gestión de archivos MP3
  ContentView.swift     Pantalla única: pistas, avisos, tramos, cronograma, envío
  AvisoEditores.swift   Sheets de alta/edición con validación
  TramosImport.swift    Parser del JSON de tramos (con errores explicativos)
  Conectividad.swift    WatchConnectivity lado iPhone (transferUserInfo +
                        transferFile + inventario confirmado por el reloj)
  Carreras.swift        Historial: HKSampleQuery + HKWorkoutRouteQuery + MapKit
Maraton Watch App/ (watchOS)
  ConectividadWatch.swift  Recepción y persistencia de plan y archivos;
                           limpieza de MP3s huérfanos; reporte de inventario
  Reproductor.swift        Cola AVAudioPlayer con loop, Now Playing, tres tipos
                           de pausa (total / por voz / solo-música), cronómetro
                           con el reloj de sistema como fuente de verdad
  Avisador.swift           Cronograma de avisos, AVSpeechSynthesizer es-AR,
                           notificaciones locales reprogramables, ducking
  Entrenamiento.swift      HKWorkoutSession + HKLiveWorkoutBuilder, ritmo
                           suavizado, ruta GPS (HKWorkoutRouteBuilder),
                           pausa/descarte de workout, resumen final
  EntrenadorRitmo.swift    Seguimiento de tramos por distancia, correcciones
                           de ritmo por voz, splits por kilómetro
  ContentView.swift        Lobby + carrera en 3 páginas + cuenta regresiva
```

### Decisiones técnicas destacadas

- **El tiempo nunca se acumula con timers**: la fuente de verdad es el reloj de
  sistema (fecha de reanudación + acumulado), así los avisos no se corren ni en
  carreras de 3+ horas. El `Timer` de 1 s solo refresca UI y dispara chequeos.
- **La pausa congela todo el sistema de forma consistente**: cronómetro,
  cronograma, `HKWorkoutSession` (pause/resume), GPS y notificaciones locales
  (canceladas y reprogramadas con los tiempos corridos).
- **Tres canales por aviso** (voz + háptico + notificación local): la app corre
  en segundo plano detrás de otras, y el aviso llega igual.
- **Ducking correcto según el dueño del audio**: música propia → se pausa el
  player propio; música de otra app → sesión `.duckOthers` que se libera con
  `notifyOthersOnDeactivation`.
- **Ritmo suavizado en ventana de ~45 s** con margen y cooldown para que el
  entrenador de voz no moleste con el ruido natural del GPS de muñeca.
- **Transferencias resilientes**: el plan viaja por `transferUserInfo` (se
  encola offline), los MP3 por `transferFile`; el reloj reporta su inventario
  vía `updateApplicationContext` y el iPhone no reenvía lo confirmado.
- **Background modes de watchOS bien declarados** (`WKBackgroundModes`: audio,
  location, workout-processing) y activación defensiva del GPS en background
  (verificación del Info.plist antes de habilitarlo).

### Frameworks y tecnologías

`Swift` · `SwiftUI` · `HealthKit` (workout session, live builder, rutas,
queries estadísticas) · `AVFoundation` (AVAudioPlayer, AVSpeechSynthesizer,
sesiones de audio long-form y ducking) · `WatchConnectivity` · `CoreLocation` ·
`MapKit` · `UserNotifications` · `MediaPlayer` (Now Playing / remote commands) ·
`WatchKit` (hápticos) · distribución por `TestFlight`

---

## 🔨 Cómo se desarrolló

- **Desarrollo iterativo por fases** (12+ entregas incrementales), cada una
  compilable y probable: proyecto base → app iPhone → conectividad →
  reproducción → avisos → entrenamiento → GPS/tramos → pulido y UX.
- **Probado en hardware real** (Apple Watch SE 2 + iPhone) vía **TestFlight**,
  con ciclo continuo build → prueba de campo → ajuste. Nada del dominio
  (audio en background, WatchConnectivity, sensores) es verificable en
  simulador.
- **Toolchain remota**: desarrollo con control de versiones en Git/GitHub y
  compilación en un Mac en la nube (MacinCloud) con Xcode.
- **Desarrollo asistido por IA** (pair programming con Claude): diseño de
  arquitectura, implementación y debugging guiado por logs y pruebas de campo;
  el plan de entrenamiento se genera con ChatGPT mediante un contrato JSON.

## 🗺️ Roadmap

- Modo "día de carrera": proyección de tiempo de llegada, hitos, comparación
  contra objetivo.
- Avisos por zona de FC por voz.
- Biblioteca de planes en el iPhone.
- Análisis post-carrera con IA (API de OpenAI) sobre las métricas de Salud.

## 🚀 Build

1. Clonar y abrir `Maraton.xcodeproj` (Xcode 15+).
2. Firmar ambos targets con tu equipo (Signing & Capabilities).
3. Correr en simulador, o `Product → Archive` para distribuir por TestFlight.

## 🌐 Web pública (maratonia.site)

El sitio es estático y se genera. **No se editan los archivos de `web/`**:
son salida del generador y se pisan en cada build.

```
templates/            plantillas bilingües (el texto en español, y el inglés
                      en atributos data-en)
scripts/seo.config.mjs  títulos, descripciones y rutas de cada página
scripts/build-web.mjs   genera web/ + sitemap.xml + robots.txt
scripts/check-seo.mjs   verifica la salida antes de publicar
web/                  sitio generado, es lo que se publica
```

```bash
npm run build:web    # regenera el sitio desde templates/
npm run check:seo    # títulos, canonical, hreflang, JSON-LD, links rotos
npm run build:og     # regenera las imágenes para compartir (necesita Playwright)
```

Cada página existe **una vez por idioma y con URL propia**
(`/support/` y `/en/support/`), que es lo que permite que Google indexe y
posicione las dos versiones. Antes el idioma se cambiaba con JavaScript
sobre la misma URL: el buscador solo podía quedarse con una versión y, al
renderizar con `Accept-Language: en`, se quedaba con la equivocada. Las
versiones se declaran entre sí con `hreflang`.

Si agregás una página, va en `templates/` y en la lista `PAGES` de
`scripts/seo.config.mjs`; el sitemap, los `hreflang` y el JSON-LD salen
solos de ahí.

---

*Proyecto personal de Felipe Veiga.*
