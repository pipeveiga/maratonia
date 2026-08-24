# Prompt para continuar Maratonia en otra sesión

Copiá TODO lo que está entre las líneas de guiones y pegalo como primer
mensaje.

---

Trabajo en Maratonia, una app de running para iPhone + Apple Watch
(SwiftUI, iOS 26 / watchOS 26). El repo está en
`~/Documents/GitHub/maratonia`. Estamos por enviar la versión 1.0 a la
App Store.

## Dónde está todo

- Rama de trabajo: `rc/build74`, que sale de
  `claude/running-audio-watchos-app-ltyxwy`. **Esa es la línea de
  desarrollo real de la app**, NO `main` — `main` tiene solo la web y
  está 40+ commits atrás. Si trabajás sobre `main` vas a estar tocando
  una app vieja.
- Build actual: **84**, ya subido a TestFlight.
- 601 tests iOS + 57 del backend, todos en verde.
- `main` tiene 6 commits locales sin pushear (un merge de arreglos de
  localización). La rama de la app sí está sincronizada con GitHub.

## Documentos que ya existen y hay que leer antes de tocar nada

- `LANZAMIENTO.md` — el checklist de envío, en orden. Empieza con un
  bloque "⚠️ LEER PRIMERO" con tres cosas que rompen el envío.
- `PARA_PEGAR.md` — todo el texto de App Store Connect ya redactado:
  notas al revisor, App Privacy fila por fila, descripciones de las
  suscripciones.
- `scripts/subir.sh` — compila, firma y sube a TestFlight en un comando:
  `./scripts/subir.sh 85`

## Con qué contás

Corrés en la Mac de Felipe, con todo abierto: Xcode 26.6 con los
simuladores instalados, el repo, la sesión de App Store Connect en el
navegador y la API key configurada. O sea que podés compilar, correr los
tests, sacar screenshots del simulador y subir builds vos mismo.

## Lo que queda pendiente

1. **Cargar la ficha en App Store Connect.** Con el navegador abierto lo
   podés hacer: ficha ES/EN, screenshots, productos de suscripción,
   seleccionar el build. Todo el texto está en `PARA_PEGAR.md`.

   **DOS COSAS NO LAS TOQUES SIN FELIPE:**

   - **El formulario de App Privacy.** Es una declaración legal a su
     nombre sobre qué datos recolecta la app. Mostrale las tres filas
     que van (están en `PARA_PEGAR.md`) y que las marque él.
   - **El botón "Enviar para revisión".** Preparalo todo, mostrale qué
     quedó cargado, y que lo apriete él. Enviar es irreversible y sale a
     nombre suyo.

   Si aparece un pedido de doble factor, pedíselo — no lo esquives.

2. **Verificar la cuenta demo** `apple@prueba.com` / `Apple1976`: se creó
   cuando el botón "Confirmar plan" estaba roto, así que puede haber
   quedado sin plan adoptado. Un revisor que entra y ve la app vacía no
   puede evaluar nada. Se verifica entrando con esa cuenta en el
   iPhone de Felipe, o creándola de nuevo desde el simulador.

3. **Screenshots de Progreso y Carreras con historial real** — necesitan
   carreras guardadas en HealthKit. En el simulador no se pueden
   inyectar; salen del teléfono de Felipe. Los tres que ya existen (Hoy,
   Progreso y Perfil, a 1320×2868) están en
   `~/Desktop/Maratonia-screenshots/`.

4. **Pushear `main`** — 6 commits locales. Requiere que Felipe tenga
   credenciales de GitHub cargadas; si `git push` falla con "could not
   read Username", pedíselo y que lo haga desde GitHub Desktop.

## Cosas que descubrí a los golpes y te van a ahorrar horas

**Compilá siempre para Release antes de dar algo por bueno.**
`xcodebuild build -destination 'generic/platform=iOS'`. El simulador
(Debug) es MUCHO más permisivo: pasé dos cosas que compilaban en
simulador y explotaban al archivar.

**`Maraton/AlternativasCoach.swift` tiene `import SwiftUI` adentro de un
`#if DEBUG`** (lo trajo un catálogo de previews). Si agregás una vista al
final de ese archivo, compila en simulador y falla al archivar con
"cannot find type 'View' in scope". Las vistas nuevas van a
`Maraton/SalidasCoach.swift`, que tiene su propio import.

**El simulador necesita datos para que se vea algo.** Hay una forma de
poblarlo: escribir un `dominio-v2.json` en
`$(xcrun simctl get_app_container <UDID> com.pipeveiga.maraton data)/Documents/`.
El almacén DEBE tener `activado = true` o se descarta en silencio y la
app arranca en onboarding.

**Para ver la app sin crear cuentas en el Firebase real**: borrá
`GoogleService-Info.plist` del bundle instalado en el simulador. La app
detecta que no hay Firebase y saltea el login (es una decisión
deliberada del código, no un truco).

**Subir a TestFlight**: usar `scripts/subir.sh`. NO uses
`-exportArchive` con `destination: upload` — la sesión de Apple ID en
Xcode se cae seguido y falla con "Failed to Use Accounts". El script
firma con el certificado local y sube con una API key de App Store
Connect (rol **Admin**; con App Manager no alcanza, no puede crear
perfiles de aprovisionamiento).

## Cómo trabajar

- **Verificá antes de afirmar.** Si decís que algo anda, tiene que estar
  compilado, testeado y —si es visual— mirado. Si no lo pudiste ver,
  decilo.
- Los commits del repo están escritos en castellano rioplatense,
  explicando POR QUÉ y no qué. Seguí ese estilo.
- Los comentarios del código también: explican decisiones y trampas, no
  repiten lo que el código dice.
- Antes de agregar un componente, buscá si ya existe. Este proyecto tiene
  bastante código bueno sin usar — dos veces reescribí algo que ya
  estaba.

## Lo último, y va en serio

Esta app la usa Felipe para correr de verdad, y ya perdió una carrera por
un bug. No des nada por bueno sin verificarlo: compilado, testeado y —si
es visual— mirado con una captura. Si algo no lo pudiste comprobar,
decilo con todas las letras en vez de darlo por hecho.

Empezá leyendo `LANZAMIENTO.md` y decime qué encontrás.

---
