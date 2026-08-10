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

## Para el formulario App Privacy (App Store Connect)
- Health & Fitness: SÍ se usa, vinculado al usuario, solo
  funcionalidad de la app, NO tracking, NO se comparte con terceros.
- Location: SÍ (ruta del mapa), solo funcionalidad, NO tracking.
- Contact info (email address): solo si crea cuenta — se recolecta,
  vinculado a la identidad, propósito App Functionality; no
  marketing, no tracking.
- Identifiers (User ID): SÍ si crea cuenta (UID de Firebase +
  subject IDs de Apple/Google), App Functionality, no tracking.
- Tracking (ATT): NO. Sin publicidad, sin data brokers, sin SDKs de
  analytics en este build (FirebaseAuth no es Firebase Analytics).
