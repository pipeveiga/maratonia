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

## Lo que queda pendiente

1. **El envío en App Store Connect** — esto NO lo podés hacer vos: es
   una web con Apple ID y doble factor. Lo hace Felipe a mano siguiendo
   `LANZAMIENTO.md` + `PARA_PEGAR.md`. Si te pide ayuda con esto,
   explicale los pasos; no intentes automatizarlo.
2. **Verificar la cuenta demo** `apple@prueba.com` / `Apple1976`: se creó
   cuando el botón "Confirmar plan" estaba roto, así que puede haber
   quedado sin plan adoptado. Un revisor que entra y ve la app vacía no
   puede evaluar nada.
3. **Screenshots de Progreso y Carreras con historial real** — necesitan
   carreras guardadas en HealthKit. En el simulador no se pueden
   inyectar; salen del teléfono de Felipe.

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

Empezá leyendo `LANZAMIENTO.md` y decime en qué me podés ayudar.

---
