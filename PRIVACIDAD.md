# PRIVACIDAD — Qué dato vive dónde (base para Privacy Policy y App Privacy)

## LOCAL (Documents del dispositivo)
- `plan.json`: configuración de audio legacy (pistas, avisos, tramos).
- `dominio-v2.json`: plan de entrenamiento, calendario, estados,
  perfil deportivo (objetivo/días/fecha), referencias de rendimiento,
  registro de sesiones (IDs y vínculos — NO métricas) y `usuarioID`.
- `cuenta.json`: cuenta Maratonia (userID, nombre opcional,
  proveedores vinculados con su subject ID y email informativo).
- MP3s del usuario (y su copia en el reloj).
- UserDefaults: preferencias de UI y estado menor (tutorial visto,
  auto-pausa on/off, completados locales del reloj).
- **Nunca**: contraseñas ni tokens de terceros en archivos de la app.
  (La sesión de Firebase la maneja su SDK en el Keychain del sistema,
  como cualquier app con login — Maratonia no la toca.)

## APPLE HEALTH (HealthKit — el dispositivo del usuario)
- Los WORKOUTS con distancia, ruta GPS, FC, calorías y la metadata
  `programadoID`. Es la fuente autoritativa de "lo corrido".
- Maratonia LEE workouts para Progreso/Carreras y ESCRIBE los propios.
- **Jamás sale del ecosistema Salud del usuario. Jamás se sube a
  servidores por existir un login.** Borrarlo es del usuario, desde
  la app Salud (la app lo explica al eliminar cuenta).

## ICLOUD PRIVADO DEL USUARIO (CloudKit private database)
- Respaldo del plan de audio (`Plan` como JSON, registro "planActual").
- Es el iCloud DEL USUARIO: Maratonia no puede leerlo de otros
  usuarios ni verlo desde afuera. "Eliminar cuenta" lo borra.

## FIREBASE AUTHENTICATION (Google Cloud — SOLO identidad)
- **Qué guarda**: la cuenta de autenticación — email de login,
  proveedores vinculados (Apple/Google/email), UID de Firebase y el
  hash de la contraseña si usa email (la contraseña NUNCA pasa por
  código de Maratonia ni se guarda en el dispositivo).
- **Qué NO guarda**: plan de entrenamiento, calendario, progreso,
  carreras, métricas, nada de HealthKit. El dominio deportivo vive en
  el dispositivo y el iCloud privado del usuario; Firebase es SOLO el
  login. Subir perfil/plan a un backend sería una decisión futura
  explícita, no un efecto del login.
- SDKs enlazados: FirebaseAuth y GoogleSignIn, únicamente en la app
  iOS (el Watch no los enlaza). **Sin** Analytics, Firestore,
  Crashlytics, Messaging ni Remote Config.
- "Eliminar cuenta" borra el usuario en Firebase (`delete()`), revoca
  el token de Apple cuando hay código fresco, y recién después borra
  la cuenta local y el respaldo iCloud propio.
- Con "Ocultar mi correo" de Apple, Firebase solo ve la dirección
  relay de Apple, nunca el email real.

## BACKEND MARATONIA (Cloud Functions — solo Maratonia Coach)
- **Existe solo si el usuario usa el Coach** (acción explícita; sin
  backend configurado la sección ni aparece). Autenticado con Firebase.
- **Qué recibe**: el DTO de `ContextoCoach` — objetivo, fecha de
  carrera, días elegidos y días imposibles, baseline (distancia+tiempo),
  semana y fase actual del plan, cumplimiento, resumen del plan y de
  sesiones (fecha/tipo/km/cumplida/sensación), **ventanas agregadas**
  de 7/28/42 días (km, salidas, tirada más larga, mayor pausa) y los
  **eventos** que el detector determinístico ya concluyó (tipo,
  severidad, ID del entrenamiento afectado).
- **Qué NO recibe jamás**: rutas GPS, coordenadas, altimetría,
  frecuencia cardíaca, muestras de HealthKit, el UUID de los workouts
  de Salud, contactos, ni nada del Watch. Todo lo que viaja es
  AGREGADO: sumas y conteos, nunca la serie de datos.
- Una molestia declarada viaja como **bandera** (`tipo: "molestia"`)
  sin detalle: es una señal para el plan, no un dato clínico que se le
  manda a un tercero.
- **Dos tests automatizados** lo verifican: uno serializa el DTO con
  datos reales y falla si aparece cualquier término prohibido; otro
  comprueba que el identificador de sesión de Salud nunca se incluye.
- Datos biométricos (edad, sexo, altura, peso): **no se envían**. Son
  contexto local y nada más.
- Guarda: contadores de uso por usuario/día (rate limit) y cache de
  respuestas por 24 h (idempotencia), en Firestore del proyecto —
  inaccesible desde clientes (reglas: deny all).

## OPENAI (procesador del Coach)
- El backend reenvía a OpenAI SOLO el DTO anterior + la pregunta del
  usuario, para generar la respuesta estructurada del Coach.
- La API key es secret del backend: jamás está en la app ni en git.
- Sin Coach no hay ningún dato hacia OpenAI. El plan de entrenamiento
  se genera SIEMPRE en el dispositivo con el motor determinístico.

## Para el formulario App Privacy (App Store Connect)

Apple define **"collect"** como *transmitir el dato fuera del
dispositivo*. Usar un dato en el dispositivo y dejarlo ahí NO es
recolectarlo. Con ese criterio, Maratonia declara solo esto:

| Dato | ¿Sale del dispositivo? | ¿Se declara? |
|---|---|---|
| Health & Fitness (workouts, FC, distancia) | No — vive en HealthKit | **No** |
| Location / ruta GPS | No — vive dentro del workout | **No** |
| Respaldo iCloud (`Plan`) | No — es el iCloud privado del usuario | **No** |
| Contact Info → **Email Address** | Sí — Firebase Auth, solo si crea cuenta | **Sí** |
| Identifiers → **User ID** | Sí — UID de Firebase / subject IDs | **Sí** |

Para los dos que sí se declaran: *Linked to the user* = **Sí**,
*Used for tracking* = **No**, *Purpose* = **App Functionality**
(nada de marketing, analytics ni personalización de anuncios).

- **Tracking (ATT)**: NO. Sin publicidad, sin data brokers, sin SDKs
  de analytics en este build (FirebaseAuth no es Firebase Analytics).
- Si la cuenta es opcional y el usuario nunca la crea, ni siquiera esos
  dos datos salen. Se declaran igual porque la capacidad existe.
- **Si el Coach se activa** (backend desplegado), hay que VOLVER a este
  formulario y agregar *Other Usage Data* → los resúmenes de
  entrenamiento del DTO viajan al backend propio y a OpenAI como
  service provider; propósito App Functionality, sin tracking.
- Declarar de más no es "más seguro": pinta una etiqueta de privacidad
  peor de la que la app merece, y no arregla nada si algún día la
  arquitectura cambiara. La regla es que el formulario describa lo que
  el binario realmente hace.
