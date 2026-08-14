# Backlog

Lo que se decidió NO hacer ahora, con el motivo. No es una lista de
deseos: cada punto es algo que se encontró trabajando, se evaluó y se
dejó para después a propósito.

## Contenido deportivo en inglés — decisión de producto **[VOS]**

Con el teléfono en inglés, la UI está entera en inglés desde el build 67,
pero los entrenamientos siguen en español: "Rodaje medio", "Tirada
larga", "Rodaje continuo cómodo: tenés que poder hablar".

No es un bug de localización: esos textos salen del catálogo de planes
(`ContenidoPlanes.swift`) y se **congelan en el snapshot** del plan al
adoptarlo. Traducirlos implica (a) traducir el catálogo deportivo y (b)
decidir qué pasa con los planes YA adoptados, que tienen el texto
español guardado adentro. Un usuario que cambia el idioma del teléfono a
mitad de un plan no debería ver su plan cambiar de idioma sesión por
sesión, ni quedarse con el viejo para siempre sin poder actualizarlo.

Hay que decidirlo antes de ofrecer la app en inglés, no después.

## Onboarding: "estoy empezando" se infiere, no se guarda

`EstadoInicialOnboarding` reconstruye la respuesta del paso de
experiencia desde el perfil: con onboarding hecho y ninguna referencia,
asume `.empezando`. Es la única respuesta que produce ese estado, así
que la inferencia es correcta hoy — pero es una inferencia, no un dato.
Si algún día hay otra forma de terminar sin referencia, deja de valer.
Lo correcto sería guardar la respuesta en el perfil. No corre apuro:
equivocarse acá solo cambia qué tarjeta aparece preseleccionada.

## El catálogo de strings se queda viejo en silencio

`xcodebuild` no sincroniza el `.xcstrings`; eso lo hace Xcode al
compilar desde el IDE. Si se agregan pantallas y se compila solo por
línea de comandos, las claves nuevas nunca entran al catálogo y la app
se rompe en inglés sin que nadie lo note (fue exactamente lo que pasó
entre el build 58 y el 66: 144 claves).

Se puede cerrar con un chequeo de CI que compare los `.stringsdata` de
DerivedData contra el catálogo y falle si falta alguna. Mientras tanto,
está anotado en `LANZAMIENTO.md` como paso manual.
