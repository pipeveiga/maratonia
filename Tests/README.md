# Tests de Maratonia

Los archivos de esta carpeta están listos pero **todavía no conectados
al proyecto** (crear el target de tests requiere Xcode). Mientras tanto,
la misma lógica se valida con la simulación descripta en NIGHT_AUDIT.md.

## Conectarlos (una sola vez, en la Mac — 7 pasos)

1. Abrí `Maraton.xcodeproj` en Xcode.
2. Menú **File → New → Target…**
3. Buscá **Unit Testing Bundle** (pestaña iOS) → **Next**.
4. Product Name: `MaratonTests` · Target to be Tested: **Maraton** → **Finish**.
5. En el Finder, arrastrá `Tests/MaratonTests/LogicaDeportivaTests.swift`
   adentro del grupo **MaratonTests** que apareció en la barra lateral de
   Xcode. En el diálogo: destildá "Copy items if needed" y tildá SOLO el
   target **MaratonTests**.
6. Borrá el archivo `MaratonTests.swift` de ejemplo que creó Xcode.
7. Menú **Product → Test** (Cmd+U). Tienen que pasar todos.

## Qué cubren

- `zonaCardiaca` (Karvonen): caso real 150–160 ppm, límites de zona,
  datos corruptos (reposo ≥ máxima) sin crash.
- `Plan.cronograma`: expansión fijos+repetidos, orden fijo-primero,
  basura filtrada (minutos ≤ 0), `hastaMinuto`, plan vacío.
- Formatos: `formatearRitmo`, `ritmoParaHablar`, `kmTexto`.
- Importación de tramos: ritmos válidos/ inválidos, regresión de
  comillas curvas + fences de ChatGPT, y compatibilidad hacia atrás de
  `plan.json` sin tramos/avisosKm.

## Pendiente de agregar cuando haya harness

Lógica con estado que hoy vive en singletons con frameworks
(auto-pausa, anti-flapping de zonas, splits): para testearla haría
falta extraerla o inyectar relojes/ubicaciones falsas. Los casos ya
están diseñados en la simulación Python de NIGHT_AUDIT.md.
