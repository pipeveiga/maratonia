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
- **Nunca**: contraseñas ni tokens de sesión de terceros.

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

## CLOUD MARATONIA (backend propio)
- **Hoy: NO EXISTE.** No hay servidores de Maratonia; ningún dato
  sale del dispositivo/iCloud/Salud del usuario.
- Cuando exista (Firebase Auth para Google/email): SOLO identidad de
  autenticación (subject IDs, email de login). El dominio deportivo y
  HealthKit siguen donde están; subir perfil/plan será una decisión
  futura explícita, no un efecto del login.

## Para el formulario App Privacy (App Store Connect)
- Health & Fitness: SÍ se usa, vinculado al usuario, solo
  funcionalidad de la app, NO tracking, NO se comparte con terceros.
- Location: SÍ (ruta del mapa), solo funcionalidad, NO tracking.
- Contact info (email): solo si crea cuenta; identificación, no
  marketing, no tracking.
- Tracking (ATT): NO. Sin publicidad, sin data brokers, sin SDKs de
  analytics en este build.
