# DEPLOY del backend Maratonia Coach (Firebase Cloud Functions)

Requisitos: Node 20, `npm i -g firebase-tools`, proyecto Firebase
"Maratonia" ya creado (el mismo del Auth).

## Pasos exactos (una vez)

```bash
cd functions
npm install
firebase login
firebase use <PROJECT_ID>            # el ID del proyecto Maratonia

# 1. La API key de OpenAI como SECRET (jamás en git ni en la app):
firebase functions:secrets:set OPENAI_API_KEY
# (pega la key cuando la pida)

# 2. Habilitar Firestore (modo producción) en la consola de Firebase
#    — lo usan el rate limit, la idempotencia y los flags. SOLO el
#    backend lo usa; la app iOS NO enlaza Firestore.

# 3. Reglas de Firestore: nadie escribe desde clientes.
#    Consola → Firestore → Rules:
#      rules_version = '2';
#      service cloud.firestore {
#        match /databases/{database}/documents {
#          match /{document=**} { allow read, write: if false; }
#        }
#      }
#    (Cloud Functions usa el Admin SDK: las reglas no lo afectan.)

# 4. TTL para el cache de idempotencia:
#    Consola → Firestore → TTL → colección "respuestas", campo "expira".

# 5. Deploy:
firebase deploy --only functions
```

La URL queda como
`https://us-central1-<PROJECT_ID>.cloudfunctions.net/coach`.

## Conectar la app iOS

En `Maraton/Info.plist` agregar (cuando el backend esté desplegado):

```xml
<key>MaratoniaBackendURL</key>
<string>https://us-central1-<PROJECT_ID>.cloudfunctions.net</string>
```

Sin esa clave, el Coach NO aparece en la app (gate de runtime — cero
botones muertos). Con la clave, aparece solo para usuarios con sesión.

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
- Rate limit 20 req/usuario/día; idempotencia (repetir un request no
  quema tokens); contexto mínimo (DTO, no HealthKit crudo);
  `max_tokens` acotado. La app NUNCA llama al backend al abrir
  pantallas — solo por acción explícita del usuario.
