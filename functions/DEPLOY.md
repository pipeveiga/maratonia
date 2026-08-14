# DEPLOY del backend Maratonia Coach (Firebase Cloud Functions)

Arquitectura: iPhone → Firebase Auth (ID token) → Cloud Function
`coach` → OpenAI. **La API key vive SOLO como secret de Cloud
Functions: jamás en el binario iOS, jamás en git.**

## Estado actual

Ya está hecho y versionado:

- `functions/index.js` — auth por ID token, rate limit transaccional,
  idempotencia por `requestID`, flags server-side, devolución del
  crédito cuando el proveedor falla, logging sin contenido del usuario.
- `functions/schemas.js` — validación estricta de entrada (zod) y
  structured outputs de salida.
- `functions/test/contrato.test.js` — 12 tests del contrato con iOS.
  Corren solos con `npm test` y **se ejecutan como `predeploy`**: un
  deploy con el contrato roto no sale.
- `firebase.json`, `.firebaserc` (proyecto `maratonia`),
  `firestore.rules` (nadie escribe desde clientes),
  `firestore.indexes.json`.
- `npm install` hecho; `package-lock.json` versionado.
- `firebase-tools` instalado en esta Mac (15.27.0).

Del lado iOS: `Maraton/Coach.swift` con el DTO mínimo, el gate de
runtime y la traducción estricta a `CambioPropuesto`; los cambios pasan
por `ValidadorDeCoach` y los confirma el corredor. Cubierto por
`ContratoCoachTests` en la suite de iOS.

## Lo que falta (necesita credenciales del dueño de la cuenta)

### 1. Iniciar sesión en Firebase

```bash
firebase login
```

Abre el navegador y pide la cuenta de Google del proyecto (con 2FA si
está activo). No se puede automatizar.

Verificar después: `firebase login:list` y `firebase projects:list`
tienen que mostrar `maratonia`.

### 2. Cargar la API key de OpenAI como secret

```bash
cd functions
firebase functions:secrets:set OPENAI_API_KEY
# pega la key cuando la pida — no queda en el historial del shell
```

La key se saca de platform.openai.com. **No la pegues en ningún
archivo del repo, ni en Info.plist, ni en un `.env`** (están todos
ignorados por git, pero el lugar correcto es el secret).

### 3. Habilitar Firestore

Consola de Firebase → Firestore Database → crear en **modo
producción**, región `us-central1` (la misma que la función).

Lo usan el rate limit (`uso/`), la idempotencia (`respuestas/`) y los
flags (`config/coach`). La app iOS **no** enlaza el SDK de Firestore.

### 4. TTL del cache de idempotencia

Consola → Firestore → TTL → colección `respuestas`, campo `expira`.
Sin esto el cache crece para siempre (no rompe nada, solo acumula).

### 5. Deploy

```bash
firebase deploy --only firestore:rules,functions
```

El `predeploy` corre `npm test` primero. La URL queda en
`https://us-central1-maratonia.cloudfunctions.net/coach`.

### 6. Encender el Coach en la app

En `Maraton/Info.plist`:

```xml
<key>MaratoniaBackendURL</key>
<string>https://us-central1-maratonia.cloudfunctions.net</string>
```

Sin esa clave el Coach **no aparece** (gate de runtime — cero botones
muertos). Con la clave, aparece solo para usuarios con sesión iniciada.
Este paso va en su propio commit, después de probar el backend.

## Probar antes de encenderlo en la app

Con sesión iniciada en la app se puede sacar un ID token, o generar uno
de prueba desde la consola. Después:

```bash
curl -X POST https://us-central1-maratonia.cloudfunctions.net/coach \
  -H "Authorization: Bearer <ID_TOKEN>" \
  -H "Content-Type: application/json" \
  -d @functions/test/peticion-ejemplo.json
```

Respuestas esperadas: `200` con el JSON del schema, `401` sin token,
`400` si el payload no valida, `429` pasado el límite diario, `503` con
el Coach apagado por flag.

## Flags server-side (sin tocar la app)

Documento Firestore `config/coach`:

```
habilitado: true|false        # apagar el Coach al instante
modelo: "gpt-4o-mini"         # cambiar modelo sin release
maxRequestsPorDia: 20         # presupuesto por usuario
maxTokensSalida: 700
```

## Costos

- `gpt-4o-mini` por defecto (barato); modelo configurable server-side.
- Rate limit 20 req/usuario/día, y el crédito se devuelve si la
  consulta falla.
- Idempotencia: repetir un request no quema tokens.
- Contexto mínimo (DTO agregado, nunca HealthKit crudo ni GPS).
- `max_tokens` acotado.
- La app NUNCA llama al backend al abrir pantallas: solo por acción
  explícita del corredor.

## Desplegado el 14/8/2026 (build 70)

Proyecto `maratonia`, región us-central1.

- `coach` — actualizada. Ahora exige entitlement Pro ANTES del payload y
  mucho antes de OpenAI. Sin Pro devuelve 402 y no gasta un token.
- `borrarCuenta` — nueva. Borra `users/{uid}` con `recursiveDelete`
  (borrar el documento NO borra las subcolecciones), más los contadores
  de uso y la cache del Coach de esa persona.
- Reglas de Firestore desplegadas: cerrado por defecto, autorización por
  `request.auth.uid` contra el UID del path.

Verificado contra los endpoints desplegados: sin token → 401; token
inválido → 401; GET a `borrarCuenta` → 405.

`APP_APPLE_ID` (6796521566) va versionado en `entitlement.js`: es
público, no es un secreto. `OPENAI_API_KEY` sigue siendo secret de
Cloud Functions.
