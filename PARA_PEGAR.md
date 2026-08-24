# 📋 Para pegar en App Store Connect

Todo lo que hay que escribir en la consola, ya redactado. Copiá y pegá.
Lo que dice **[VOS]** es una decisión o un dato que solo tenés vos.

> Este archivo es el TEXTO. El ORDEN de ejecución está en
> `LANZAMIENTO.md`.

---

## 1. Notas para el revisor (App Review Information → Notes)

⚠️ Reemplaza al bloque de `APP_STORE.md`, que quedó viejo: decía que la
app funciona sin cuenta y que no hace falta cuenta demo. Las dos cosas
son falsas hoy, y ese error solo se descubre cuando Apple rechaza.

```
CUENTA DE PRUEBA
Email: apple@prueba.com
Contraseña: Apple1976

Se entra desde la primera pantalla con "Continuar con email".
La cuenta ya tiene un plan adoptado: la app se ve con contenido.

POR QUÉ LA APP PIDE CUENTA
El plan de entrenamiento y el progreso se sincronizan entre el iPhone y
el Apple Watch, y sobreviven al cambio de dispositivo. La cuenta es la
identidad de esos datos: sin ella no hay forma de que el mismo plan
aparezca en los dos aparatos ni de recuperarlo al reinstalar. También
ofrecemos Sign in with Apple, y la cuenta se puede eliminar desde
Perfil → Cuenta Maratonia → Eliminar cuenta.

CÓMO PROBAR LAS SUSCRIPCIONES
Con una cuenta sandbox de App Store: Perfil → Maratonia Pro → Conocer
Maratonia Pro. El anual tiene 7 días de prueba. Pro habilita los planes
de 21K y 42K, el Coach y la adaptación del plan; el resto de la app
(planes de 5K y 10K, carrera libre, historial, Apple Watch) es gratis.

APPLE WATCH
La app del reloj corre los entrenamientos de forma independiente: el
iPhone no necesita estar cerca. Reproduce música transferida, guía por
voz y registra la sesión en HealthKit.

HEALTHKIT
- Lectura: entrenamientos y frecuencia cardíaca, para el historial y el
  progreso.
- Escritura: el entrenamiento al terminar una carrera, con su ruta.
Sin permisos de Salud la app avisa y sigue funcionando; no se bloquea
ninguna pantalla.

UBICACIÓN
Solo durante una carrera activa, para medir distancia y dibujar el
recorrido. La ruta se guarda en HealthKit y no sale del dispositivo.

COACH (opcional, requiere Pro)
Manda a un backend propio un resumen NUMÉRICO del entrenamiento
(objetivo, días disponibles, volumen semanal, eventos detectados) para
generar explicaciones y sugerencias con un modelo de lenguaje. No viaja
ninguna ruta GPS ni ninguna muestra de frecuencia cardíaca: el esquema
del backend las rechaza.
```

---

## 2. App Privacy (el formulario)

Primera pregunta — *"¿Recolectás datos de esta app?"* → **Sí**

Marcar EXACTAMENTE estas tres filas y ninguna más:

| Categoría | Dato | ¿Vinculado al usuario? | Propósito | ¿Tracking? |
|---|---|---|---|---|
| Contact Info | Email Address | Sí | App Functionality | No |
| Identifiers | User ID | Sí | App Functionality | No |
| Other Data | Other Usage Data | Sí | App Functionality | No |

**Por qué esas tres y no más:**

- *Email* y *User ID*: por el login (Firebase Auth).
- *Other Usage Data*: por el Coach. El resumen de entrenamiento sale del
  dispositivo hacia el backend propio y de ahí a OpenAI. **Esta fila es
  obligatoria** — las versiones viejas de la documentación decían que el
  Coach no estaba desplegado, y sí lo está.

**Lo que NO se marca, y el argumento si Apple pregunta:**

- **Health & Fitness**: los entrenamientos viven en HealthKit, en el
  dispositivo. Apple entiende por "recolectar" transmitir el dato fuera
  del dispositivo, y no se transmite.
- **Location**: la ruta GPS se guarda dentro del workout de HealthKit.
  Nunca se sube.
- **El respaldo iCloud**: es el iCloud privado del propio usuario. No es
  recolección.

**Tracking (ATT)**: **No**. Sin publicidad, sin data brokers, sin
analytics de terceros.

---

## 3. Descripción de los productos de suscripción

Cada producto necesita nombre y descripción de display; Apple los revisa
como contenido.

**`maratonia.pro.yearly` — Maratonia Pro (anual)**
```
Nombre: Maratonia Pro — Anual
Descripción: Planes de 21K y 42K, un coach que explica cada sesión y un
plan que se adapta a tu semana real. Incluye 7 días de prueba.
```

**`maratonia.pro.monthly` — Maratonia Pro (mensual)**
```
Nombre: Maratonia Pro — Mensual
Descripción: Planes de 21K y 42K, un coach que explica cada sesión y un
plan que se adapta a tu semana real.
```

**Grupo de suscripción**: los dos en el MISMO grupo, para que se pueda
cambiar de plan sin comprar dos veces. Nombre sugerido: `Maratonia Pro`.

---

## 4. Copy de los screenshots

El orden importa: el primero es el que se ve sin deslizar.

| # | Pantalla | Copy ES | Copy EN |
|---|---|---|---|
| 1 | Plan con la semana | Tu plan, en tus días | Your plan, on your days |
| 2 | Carrera en el Watch | Corré con el reloj solo | Just you and your Watch |
| 3 | Recorrido pintado | Mirá dónde apretaste | See where you pushed |
| 4 | Progreso | Progreso honesto | Honest progress |
| 5 | Detalle del entrenamiento | Cada sesión, explicada | Every session, explained |
| 6 | Onboarding de días | Vos elegís qué días corrés | You choose your run days |

---

## 5. Decisiones tomadas

- **Idioma principal**: Español (México)
- **Disponibilidad**: todos los países
- **Cuenta demo**: `apple@prueba.com` / `Apple1976`

- [ ] **[VOS]** Verificar que esa cuenta tenga un PLAN ADOPTADO antes de
      enviar. Si el revisor entra y ve la app vacía, no puede evaluar
      nada — y la cuenta se creó justo cuando "Confirmar plan" estaba
      roto, así que puede haber quedado sin plan.
