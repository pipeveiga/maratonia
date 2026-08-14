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

## El catálogo de strings se queda viejo en silencio

`xcodebuild` no sincroniza el `.xcstrings`; eso lo hace Xcode al
compilar desde el IDE. Si se agregan pantallas y se compila solo por
línea de comandos, las claves nuevas nunca entran al catálogo y la app
se rompe en inglés sin que nadie lo note (fue exactamente lo que pasó
entre el build 58 y el 66: 144 claves).

Se puede cerrar con un chequeo de CI que compare los `.stringsdata` de
DerivedData contra el catálogo y falle si falta alguna. Mientras tanto,
está anotado en `LANZAMIENTO.md` como paso manual.
