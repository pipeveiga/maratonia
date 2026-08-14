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
- **Qué NO guarda**: el plan ni el progreso. Eso vive en Firestore
  bajo el UID (ver la sección siguiente); Firebase Auth es solo el
  login.
- SDKs enlazados: FirebaseAuth, **FirebaseFirestore** y GoogleSignIn,
  únicamente en la app iOS (el Watch no los enlaza). **Sin** Analytics,
  Crashlytics, Messaging ni Remote Config.
- "Eliminar cuenta" borra el usuario en Firebase (`delete()`), revoca
  el token de Apple cuando hay código fresco, y recién después borra
  la cuenta local y el respaldo iCloud propio.
- Con "Ocultar mi correo" de Apple, Firebase solo ve la dirección
  relay de Apple, nunca el email real.

## FIRESTORE — LA CUENTA DEL CORREDOR (desde el build 70)

Maratonia pasó a ser **account-first**: la cuenta es la fuente de
verdad y el dispositivo es caché. Eso cambió qué sale del teléfono, y
esta sección dice exactamente qué.

**Qué SUBE, bajo `users/{uid}`:**
- **Perfil deportivo**: objetivo, intención, fecha de carrera, días
  disponibles y días imposibles, actividad DECLARADA por el corredor
  (km/semana, salidas, tirada larga, meses corriendo), bandera de
  molestias, sistema de unidades y preferencias de la semana.
- **Datos básicos, si los cargó**: fecha de nacimiento, sexo, altura y
  peso. Son opcionales y siguen siéndolo; lo que cambió es que ahora
  viajan con la cuenta para poder restaurarlos en otro dispositivo.
- **Planes**: el snapshot completo (semanas, sesiones programadas,
  ritmos, fases). Es CONTENIDO de Maratonia con las fechas del
  corredor, no una medición suya.
- **Registro de sesiones**: identificador del workout, fecha, con qué
  entrenamiento se vinculó, sensación declarada y bandera de molestia.
  **Sin distancia, sin duración, sin ritmo, sin frecuencia cardíaca.**
- **Referencias de rendimiento**: distancia y tiempo de una marca
  (la que el corredor cargó a mano o midió con el Test 5K).
- **Historial de adaptaciones**: qué sesión cambió, cómo y por qué.

**Qué NO sube, nunca:** coordenadas, rutas, altimetría, frecuencia
cardíaca, muestras de HealthKit, ni ninguna serie de datos. HealthKit
sigue siendo HealthKit: la app lo lee para mostrar progreso y escribe
sus workouts ahí, y eso no se copia a ningún servidor.

**Aislamiento**: las reglas de Firestore autorizan por
`request.auth.uid` contra el UID del path — nunca por un campo del
documento. Un usuario no puede leer ni escribir los datos de otro.

**Entitlement Pro**: `users/{uid}/entitlement/pro` lo escribe SOLO el
backend, después de verificar la transacción firmada por Apple. El
cliente puede leerlo pero no modificarlo.

**Borrar cuenta** elimina `users/{uid}` con todas sus subcolecciones
(Cloud Function con Admin SDK: borrar un documento no borra sus
subcolecciones), más los contadores de uso y la cache del Coach de esa
persona. Si ese borrado falla, la cuenta NO se elimina y se avisa: es
preferible reintentar a creer que los datos ya no están.

## COMPRAS (StoreKit / App Store)

- Maratonia Pro se compra con **StoreKit 2**. El pago lo procesa Apple:
  la app nunca ve ni guarda datos de tarjeta.
- Lo que la app manda a su backend es la **transacción firmada por
  Apple** (JWS), para verificarla del lado del servidor. No contiene
  datos de pago; contiene identificador de producto, fechas y un
  identificador de transacción de Apple.
- No hay SDK de terceros de analítica de compras.

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
| Workouts, FC, distancia medida, calorías | No — viven en HealthKit | **No** |
| Location / ruta GPS | No — vive dentro del workout | **No** |
| Respaldo iCloud (`Plan` de audio) | No — es el iCloud privado del usuario | **No** |
| Contact Info → **Email Address** | Sí — Firebase Auth, solo si crea cuenta | **Sí** |
| Identifiers → **User ID** | Sí — UID de Firebase / subject IDs | **Sí** |
| Health & Fitness → **Fitness** | Sí — perfil deportivo y registro de sesiones a Firestore | **Sí** |
| Health & Fitness → **Health** | Sí, SOLO si el corredor los carga — fecha de nacimiento, sexo, altura, peso | **Sí** |
| Purchases | Sí — la transacción firmada por Apple al backend propio | **Sí** |

Para todos los que se declaran: *Linked to the user* = **Sí**,
*Used for tracking* = **No**, *Purpose* = **App Functionality**
(nada de marketing, analytics ni personalización de anuncios).

> **Esto cambió en el build 70** y es el cambio de privacidad más
> importante del ciclo. Antes el dominio deportivo no salía del
> teléfono y solo se declaraban email y User ID. Ahora Maratonia es
> account-first: el perfil, el plan y el progreso viven en la cuenta
> para que el corredor los recupere en cualquier dispositivo, y eso es
> "collect" según la definición de Apple aunque el destino sea nuestro
> propio backend. Lo que sigue sin salir es lo medido por HealthKit:
> distancias, ritmos, frecuencia cardíaca y rutas.

- **Tracking (ATT)**: NO. Sin publicidad, sin data brokers, sin SDKs
  de analytics en este build (FirebaseAuth no es Firebase Analytics).
- La cuenta dejó de ser opcional para USAR la app con plan: el arranque
  pide identidad. Sin Firebase configurado la app funciona local, pero
  esa no es la configuración de producción, así que se declara todo.
- **Si el Coach se activa** (backend desplegado), hay que VOLVER a este
  formulario y agregar *Other Usage Data* → los resúmenes de
  entrenamiento del DTO viajan al backend propio y a OpenAI como
  service provider; propósito App Functionality, sin tracking.
- Declarar de más no es "más seguro": pinta una etiqueta de privacidad
  peor de la que la app merece, y no arregla nada si algún día la
  arquitectura cambiara. La regla es que el formulario describa lo que
  el binario realmente hace.
