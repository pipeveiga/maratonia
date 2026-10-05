# Tests de Maratonia

`MaratonTests` y `MaratonUITests` están conectados al proyecto y al esquema
compartido `Maraton`. En Xcode: seleccionar el esquema, un simulador iPhone y
**Product → Test** (Cmd+U). No hay que crear targets manualmente.

## Ejecutarlos

En una Mac con Xcode y el simulador correspondiente instalado:

```sh
xcodebuild test -project Maraton.xcodeproj -scheme Maraton \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5' \
  -parallel-testing-enabled NO CODE_SIGNING_ALLOWED=NO
```

La configuración del runner vive en `.github/workflows/ios.yml`. Compila
Release para iPhone y Apple Watch, ejecuta ambos targets de tests y conserva
el `.xcresult` y las capturas como artefactos de GitHub Actions.

## Qué cubren

- Dominio deportivo: volumen, calendarios, perfiles, planes, adaptaciones,
  migraciones, internacionalización y vínculo con sesiones guardadas.
- Inicio: instalación nueva, plan futuro, sesión pendiente o resuelta,
  archivo de un plan y conservación del historial.
- Persistencia: dos generaciones válidas, recuperación con evidencia del
  archivo corrupto, errores de lectura/escritura, versiones futuras,
  reintento e idempotencia de resultados pendientes del reloj.
- Auto-pausa: timestamps GPS medidos, señales viejas o duplicadas, precisión,
  saltos temporales y pausa manual; cierre de sesión por identidad.
- Cuentas: separación entre UIDs, regreso a la cuenta original, bloqueo de
  asociación con datos ajenos y cierre seguro ante fallas de sincronización.
- Cola remota: confirmación pendiente, falla y reapertura, edición concurrente
  y cambio de UID durante el envío, con un escritor inyectado sin red.
- UI: Hoy → Plan → creación → Progreso → carreras; calendario de plan activo;
  validación del onboarding sin saltos por swipe; recorrido en inglés.

Los recorridos de UI usan un almacén temporal y argumentos de lanzamiento
que sólo funcionan en builds Debug del simulador. No necesitan una cuenta
personal, ni autorizaciones de Salud, Firebase o una compra.

Backend (Node 20):

```sh
cd functions
npm ci --ignore-scripts
node --test test/*.test.js
```

## Verificación en dispositivos

El simulador no verifica GPS con pantalla bloqueada, autorizaciones reales de
Salud, audio bajo interrupciones ni guardado de workouts en Apple Watch.
Los casos concretos para la siguiente prueba física están en `UX_AUDIT.md`.
