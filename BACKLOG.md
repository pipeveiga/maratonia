# Backlog

Lo que se decidió NO hacer ahora, con el motivo. No es una lista de
deseos: cada punto es algo que se encontró trabajando, se evaluó y se
dejó para después a propósito.

## ~~Contenido deportivo en inglés~~ — CERRADO en el build 67

Estaba acá como decisión de producto pendiente y se resolvió como
problema de dominio: el plan guarda ahora QUÉ ES cada sesión
(`ClaveEntrenamiento`, `ClaveSegmento`, `ClavePlan`) y el texto se arma
al mostrarlo. Los planes ya adoptados se rescatan por `TextosLegado` sin
migrar nada. Ver `Shared/TextosDeportivos.swift`.

Lo que queda de esa familia, y es chico: el contenido PROVISIONAL del
catálogo V1 (Primeros 5K y Rumbo a 10K) sigue siendo JSON embebido sin
claves y depende de la tabla de rescate. Funciona y hay un test que
verifica que cada uno de sus textos esté en la tabla, pero el día que se
reemplace ese contenido provisional conviene que nazca con claves como
el resto en vez de agrandar la tabla.

## Onboarding: "estoy empezando" se infiere, no se guarda

`EstadoInicialOnboarding` reconstruye la respuesta del paso de
experiencia desde el perfil: con onboarding hecho y ninguna referencia,
asume `.empezando`. Es la única respuesta que produce ese estado, así
que la inferencia es correcta hoy — pero es una inferencia, no un dato.
Si algún día hay otra forma de terminar sin referencia, deja de valer.
Lo correcto sería guardar la respuesta en el perfil. No corre apuro:
equivocarse acá solo cambia qué tarjeta aparece preseleccionada.

## Carreras no se puede verificar en el simulador

La pestaña pide autorización de HealthKit al abrirse y `simctl privacy`
no sabe conceder `health` (soporta calendar, location, motion,
photos… no Health). El diálogo del sistema tapa la vista y no hay forma
de aceptarlo por línea de comandos, así que Carreras es la única
pantalla del sprint visual que quedó sin captura.

Se cierra de dos maneras: a mano en el simulador una vez (la
autorización queda pegada al contenedor), o con un test de UI que toque
el botón. Mientras tanto, cualquier cambio ahí se verifica en el
dispositivo.

## Pendientes del megasprint de cuenta + Pro

Lo que quedó fuera de este sprint, ordenado por lo que más importa:

- **App Check** (§15): evaluado, no integrado. El backend ya exige
  Firebase ID token, rate limit por UID e idempotencia, así que el
  agujero que cerraría App Check es el de un atacante con una cuenta
  válida quemando su propia cuota. Conviene observar métricas antes de
  poner enforcement y arriesgar bloquear TestFlight.
- **Tests de StoreKit con StoreKit Testing** (§47): la configuración
  local (`Maratonia.storekit`) está y el `TiendaPro` es testeable, pero
  falta el plan de pruebas de Xcode que ejercite compra/trial/restore/
  expiración/revocación contra el simulador.
- **E2E de dos dispositivos** (§40): la lógica de unión por ID estable
  y la cola tienen tests unitarios; el recorrido real
  (A adopta → B instala → mismo plan) necesita dos dispositivos y una
  cuenta real.
- ~~Borrado de cuenta cloud~~ — CERRADO en el build 70 (Cloud Function
  `borrarCuenta` con `recursiveDelete`).
- ~~Revisión de PRIVACIDAD.md~~ — CERRADO en el build 70. Lo que queda
  es cargar la ficha de App Privacy en App Store Connect con la tabla
  actualizada: ahora hay que declarar **Health & Fitness** y
  **Purchases** además de email y User ID.

## El catálogo de strings se queda viejo en silencio

`xcodebuild` no sincroniza el `.xcstrings`; eso lo hace Xcode al
compilar desde el IDE. Si se agregan pantallas y se compila solo por
línea de comandos, las claves nuevas nunca entran al catálogo y la app
se rompe en inglés sin que nadie lo note (fue exactamente lo que pasó
entre el build 58 y el 66: 144 claves).

Se puede cerrar con un chequeo de CI que compare los `.stringsdata` de
DerivedData contra el catálogo y falle si falta alguna. Mientras tanto,
está anotado en `LANZAMIENTO.md` como paso manual.

## Modos de fondo: la carrera desde el teléfono se corta con la pantalla bloqueada

`UIBackgroundModes` no existe en el Info.plist, así que
`allowsBackgroundLocationUpdates` queda en false (bien guardado: sin el
modo declarado, ponerlo en true aborta el proceso) y `AVAudioSession` no
tiene modo de fondo. Consecuencia real: en una carrera desde el iPhone,
con la pantalla bloqueada se dejan de recibir ubicaciones y se cortan los
avisos por voz.

Detectado revisando el camino de arranque del build 71. NO se toca en
este sprint: agregar `location` y `audio` cambia las capabilities del
target y la ficha de App Store (Apple pregunta por el uso de ubicación en
fondo), y eso no se mete a último momento antes de una subida.

Qué hay que hacer: declarar los dos modos, agregar
`NSLocationAlwaysAndWhenInUseUsageDescription`, y validar una carrera
larga con la pantalla apagada antes de publicarlo.
