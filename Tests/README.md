# Tests de Maratonia

El target `MaratonTests` ya está conectado al proyecto y contiene cuatro
archivos de XCTest: lógica deportiva, dominio V2, motor adaptativo y
calibración deportiva.

## Ejecutar

En Xcode, seleccioná el esquema **Maraton**, un simulador iPhone y
**Product → Test** (Cmd+U). Desde la terminal:

```sh
xcodebuild test -project Maraton.xcodeproj -scheme Maraton \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

Usá el nombre o ID de un simulador disponible en tu Mac (`xcrun simctl list
devices available`). Si hay nombres duplicados, especificá `id=UUID`.
Conservá la firma normal del simulador: `CODE_SIGNING_ALLOWED=NO` elimina
los entitlements de iCloud y la app anfitriona puede caer al crear
`CKContainer`, antes de ejecutar XCTest.

Para ejecutar únicamente la regresión de frescura GPS:

```sh
xcodebuild test -project Maraton.xcodeproj -scheme Maraton \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:MaratonTests/FrescuraGPSAutoPausaTests
```

## Cobertura y límites

Los tests cubren modelos y compatibilidad JSON, calendario y cumplimiento,
planes y calibración, adaptación, importación, zonas, ritmos, tramos,
avisos y decisiones de auto-pausa/reanudación. La regresión GPS verifica
frescura real, duplicados, orden temporal, cambios de fase y pérdida de señal.

El simulador compila ambos targets, pero los tests de auto-pausa ejercitan
la lógica compartida. La entrega real de Core Location, música, pausas de
HealthKit, WatchConnectivity y recuperación de sesiones requieren pruebas
en iPhone y Apple Watch físicos. Ver `ENGINEERING_AUDIT.md`.

## Nuevas regresiones de estabilidad

`PersistenciaAlmacenTests` usa directorios temporales para probar recuperación,
protección de archivos y reintentos. `ControlCierreSesionTests` comprueba que
los callbacks viejos o duplicados no afecten otra sesión.

El backend tiene pruebas de contrato sin llamadas a servicios externos:

```sh
cd functions
npm install
npm test
```

El fixture de `functions/test/fixtures/` fue generado con JSONEncoder usando
las declaraciones de ContextoCoach de Swift; cubre la omisión de Optional nil.
