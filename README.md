# Maratón — audio + avisos de voz para correr (iOS + watchOS)

App para Apple Watch que reproduce tus MP3 durante una carrera y te interrumpe
a determinados minutos con avisos de voz ("tomá agua", "comé un gel", "date vuelta"),
funcionando **en segundo plano** mientras Runna trackea la carrera al frente.
Los canales de aviso son tres: voz, háptico y notificación local (visible
encima de Runna).

**Sin HealthKit, sin workout session, sin GPS.** Es solo una app de audio
(background mode `audio`), así que convive con cualquier tracker. Nada depende
de que la pantalla de la app sea visible ni de pantalla siempre encendida
(SE 2 no la tiene).

---

## Estado: Fase 1 ✅ (esperando tu prueba)

- [x] **Fase 1** — Proyecto con dos targets, modelo compartido, background `audio`
- [ ] **Fase 2** — App iOS: importar MP3s, armar avisos, cronograma, persistencia
- [ ] **Fase 3** — WatchConnectivity: plan y archivos al reloj
- [ ] **Fase 4** — Reproducción en el reloj: cola, loop, controles, Now Playing
- [ ] **Fase 5** — Avisos: voz, ducking, háptico, notificaciones locales, pausa que congela el cronograma
- [ ] **Fase 6** — Pulido

---

## Qué hace cada archivo

| Archivo | Qué es |
|---|---|
| `Maraton.xcodeproj/` | El proyecto Xcode. Define los dos targets (iOS y Watch), qué carpeta compila cada uno, y que la app del reloj viaja adentro de la de iOS. No lo edites a mano. |
| `Shared/Modelos.swift` | El modelo de datos (`Plan`, `AvisoFijo`, `AvisoRepetido`). Compila en **los dos** targets: es el idioma común entre iPhone y reloj. |
| `iOS/MaratonApp.swift` | Punto de entrada de la app iOS (declara cuál es la primera pantalla). |
| `iOS/ContentView.swift` | Pantalla de la app iOS. En Fase 1 es solo una pantalla de verificación; en Fase 2 va la de verdad. |
| `Watch/MaratonWatchApp.swift` | Punto de entrada de la app del reloj. |
| `Watch/ContentView.swift` | Pantalla de la app del reloj (por ahora, de verificación). |
| `Config/MaratonWatch-Info.plist` | Configuración clave del reloj: **`UIBackgroundModes = audio`** (esto es lo que permite que siga sonando con Runna al frente y la pantalla apagada) y el vínculo con la app iOS compañera. |

El proyecto usa "carpetas sincronizadas" de Xcode 16: todo archivo que aparezca
en `iOS/`, `Watch/` o `Shared/` entra solo al proyecto. En las próximas fases
vas a hacer `git pull`, abrir Xcode, y los archivos nuevos ya van a estar —
sin agregar nada a mano.

---

## Qué necesitás

- Una Mac con **Xcode 16 o más nuevo** (gratis, en el App Store de la Mac; pesa mucho, dejalo bajando).
- Para el simulador **no hace falta** cuenta de desarrollador ni configurar firma.

## Cómo abrir y correr (paso a paso)

### 1. Bajar el código

En la app **Terminal** de la Mac, pegá esto y Enter:

```
git clone -b claude/running-audio-watchos-app-hz36lk https://github.com/pipeveiga/maraton.git
```

(Si no tenés `git`, la Mac te va a ofrecer instalar las "Command Line Tools": aceptá y repetí el comando.)

### 2. Abrir el proyecto

- Abrí la carpeta `maraton` que se creó (está en tu carpeta de usuario) y hacé
  **doble click en `Maraton.xcodeproj`**. Se abre Xcode.
- Si Xcode pregunta si confiás en el proyecto, decile que sí.

### 3. Correr la app iOS en el simulador

- Arriba a la izquierda, al lado del botón ▶️, hay dos selectores:
  el **scheme** (qué app correr) y el **destino** (dónde).
- Scheme: elegí **Maraton**. Destino: elegí un **iPhone** cualquiera de la lista de simuladores.
- Apretá **▶️** (o Cmd+R). La primera compilación tarda. Tiene que abrirse un
  iPhone simulado con la pantalla "Maratón — Fase 1".

### 4. Correr la app del reloj en el simulador

- Cambiá el scheme a **MaratonWatch**. Destino: elegí un **Apple Watch** de la lista.
- **▶️** de nuevo. Tiene que abrirse un reloj simulado con "Maratón / Fase 1 OK".

### 5. Verificar el background mode (opcional, para quedarte tranquilo)

- En el panel izquierdo de Xcode, click en el primer ítem (el proyecto **Maraton**, ícono azul).
- En la columna TARGETS elegí **MaratonWatch**, pestaña **Info**.
- Tiene que aparecer **Background Modes** con el ítem `audio`. Ya viene configurado; no hay que tocar nada.

### Si algo falla

Pegame el error tal cual (texto completo) y lo arreglo.

---

## Git en tu Mac (alquilada en la nube)

El repo ya vive en GitHub (`pipeveiga/maraton`), así que el trabajo **ya
sobrevive** a que se resetee la máquina: lo que está pusheado no se pierde.
Al clonar con el comando del paso 1, el remoto queda conectado solo — no hay
que configurar nada más.

Comandos útiles desde la carpeta `maraton` en Terminal:

```
git pull                  # traer lo último (cada vez que yo te avise que pusheé una fase)
git status                # ver si tocaste algo localmente
git push                  # subir cambios tuyos (si los hubiera)
```

Si alguna vez la Mac se resetea, simplemente volvés a clonar (paso 1) y seguís.
Si por algún motivo el remoto no estuviera conectado:

```
git remote add origin https://github.com/pipeveiga/maraton.git
git push -u origin claude/running-audio-watchos-app-hz36lk
```

Cada fase queda como un commit con mensaje descriptivo, así se puede volver a
una fase que funcionaba sin leer código.

---

## Checklist de pruebas (en reloj físico)

- [ ] El audio no se corta con la muñeca baja o la pantalla apagada
- [ ] El aviso se entiende por encima de la música
- [ ] **La app sigue sonando y avisando con Runna al frente, no solo con la app en pantalla** (la prueba que importa)
- [ ] Las notificaciones locales aparecen encima de Runna
- [ ] Pausar y reanudar deja los avisos alineados con el tiempo real de carrera
- [ ] Todo funciona con el iPhone apagado y lejos, con auriculares Bluetooth emparejados directo al reloj
- [ ] Batería: una tirada de 4–5 horas con GPS de Runna + audio Bluetooth en simultáneo, antes de una carrera de verdad

---

## ¿Cuándo probar en el reloj físico?

- **Ahora (Fase 1), una vez, para destrabar la firma**: correr en un reloj real
  requiere agregar tu Apple ID en Xcode (Settings → Accounts) y elegir el Team
  en Signing & Capabilities de ambos targets. Conviene pelear con eso ahora,
  con una app trivial, y no en la Fase 5. Es opcional pero recomendado.
- **En serio, desde la Fase 4**: audio en background, muñeca baja, auriculares
  Bluetooth y convivencia con Runna **no se pueden probar en el simulador**.
  Desde la Fase 4 cada prueba importante va en el reloj.

---

## Decisiones tomadas (avisame si querés cambiar alguna)

- Nombre de la app: **Maratón** (target iOS `Maraton`, target reloj `MaratonWatch`).
- Bundle IDs: `com.pipeveiga.maraton` y `com.pipeveiga.maraton.watchkitapp`.
- Requiere Xcode 16+ (usa el formato moderno de proyecto, que evita que tengas
  que agregar archivos a targets a mano en cada fase).
- Deployment: iOS 17 / watchOS 10, como pediste.
