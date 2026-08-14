// Maratonia Coach — backend. iPhone → Firebase Auth (ID token) → esta
// función → OpenAI. La API key vive como SECRET de Cloud Functions:
// jamás en el binario iOS, jamás en git.
//
// Seguridad y costos:
// - verifyIdToken en CADA request (sin token válido → 401);
// - rate limit por usuario/día (Firestore, transaccional);
// - idempotencia por requestID (cache 24 h: repetir un request no
//   quema tokens);
// - feature flags server-side (config/coach en Firestore): apagar el
//   Coach o cambiar de modelo sin tocar la app;
// - logging SIN contenido del usuario: uid, acción, tokens, latencia.

const { onRequest } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const admin = require("firebase-admin");
const OpenAI = require("openai");
const { Peticion, salidas } = require("./schemas");
const { esPro } = require("./entitlement");

admin.initializeApp();
const db = admin.firestore();
const OPENAI_API_KEY = defineSecret("OPENAI_API_KEY");

const DEFAULTS = {
  habilitado: true,
  modelo: "gpt-4o-mini",          // configurable server-side
  maxRequestsPorDia: 20,
  maxTokensSalida: 700,
};

async function flags() {
  try {
    const doc = await db.doc("config/coach").get();
    return { ...DEFAULTS, ...(doc.exists ? doc.data() : {}) };
  } catch { return DEFAULTS; }
}

/// Rate limit transaccional: contador por uid por día UTC.
async function permitido(uid, limite) {
  const hoy = new Date().toISOString().slice(0, 10);
  const ref = db.doc(`uso/${uid}-${hoy}`);
  return db.runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const usados = doc.exists ? doc.data().requests : 0;
    if (usados >= limite) return false;
    tx.set(ref, { requests: usados + 1, actualizado: new Date() }, { merge: true });
    return true;
  });
}

/// Devuelve el crédito cuando la consulta NO se llegó a responder. El
/// contador se incrementa ANTES de llamar a OpenAI (si no, dos pedidos
/// simultáneos pasan los dos), así que un fallo del proveedor le
/// gastaba al corredor una de sus consultas del día sin darle nada.
async function devolverCredito(uid) {
  const hoy = new Date().toISOString().slice(0, 10);
  const ref = db.doc(`uso/${uid}-${hoy}`);
  try {
    await db.runTransaction(async (tx) => {
      const doc = await tx.get(ref);
      const usados = doc.exists ? doc.data().requests : 0;
      tx.set(ref, { requests: Math.max(0, usados - 1), actualizado: new Date() },
             { merge: true });
    });
  } catch (error) {
    // Que falle la devolución no puede tumbar la respuesta al cliente.
    console.warn("credito-no-devuelto", { uid });
  }
}

const SISTEMA = `Sos el coach de Maratonia, una app de entrenamiento de running.

Cómo funciona esto: el motor determinístico de la app ya armó el plan y
ya detectó qué pasó (te lo pasa en "eventos"). Vos NO sos el motor de
entrenamiento: elegís entre alternativas válidas y las explicás. Todo lo
que propongas lo valida el motor después, una operación por vez, y el
corredor lo confirma. Lo que no valide, se descarta.

Reglas duras:
- Respondés SOLO con el JSON del schema pedido, en el idioma indicado.
- No inventás datos que no estén en el contexto. Si algo no está, no lo
  sabés: decilo en vez de estimarlo.
- Operaciones permitidas sobre sesiones EXISTENTES (por programadoID):
  mantener, reprogramar, reducir (factor < 1), convertir (a rodaje
  fácil) y omitir. NO existe aumentar carga ni crear sesiones nuevas.
- Si no hay nada que cambiar, devolvé "mantener" o una lista vacía. Es
  la respuesta CORRECTA en la mayoría de los casos: no inventes ajustes
  para justificar la respuesta.
- Una buena sesión aislada NUNCA habilita subir volumen ni intensidad.
- Los entrenamientos perdidos no se compensan: no apiles kilómetros ni
  muevas sesiones para "recuperar" lo que no se hizo.
- nuevoDia tiene que ser uno de los diasElegidos del corredor y nunca
  uno de diasImposibles, nunca una fecha pasada, y nunca después de la
  fecha de la carrera.
- La carrera objetivo no se mueve, no se acorta y no se omite.
- Si faseSemanaActual es "taper" o "semanaDeCarrera", solo podés
  mantener o reducir. Nada de agregar trabajo.
- NO inventes intensidades, porcentajes de esfuerzo, pulsaciones ni
  ritmos. El plan ya trae sus zonas y sus ritmos calculados contra la
  marca del corredor: hablá de la sesión en los términos en que viene
  descrita, no en números que no te dimos.
- Tono: directo, cercano, honesto. Nada de promesas médicas ni de
  diagnósticos: si hay una molestia declarada, proponé prudencia y
  sugerí consultar a un profesional, sin nombrar patologías.
- Si idioma es "es", escribí en VOSEO rioplatense, que es la voz de
  toda la app: "podés" y no "puedes", "tenés" y no "tienes", "hacé" y
  no "haz", "acordate" y no "acuérdate", "tu ritmo" y no "su ritmo".
  Nunca "tú" ni "usted". Si idioma es "en", inglés neutro.`;

exports.coach = onRequest(
  { secrets: [OPENAI_API_KEY], region: "us-central1", cors: false,
    memory: "256MiB", timeoutSeconds: 60, maxInstances: 5 },
  async (req, res) => {
    const inicio = Date.now();
    if (req.method !== "POST") return res.status(405).json({ error: "method" });

    // ---- Auth: Firebase ID token, sin excepciones.
    const token = (req.headers.authorization || "").replace(/^Bearer /, "");
    let uid;
    try {
      uid = (await admin.auth().verifyIdToken(token)).uid;
    } catch {
      return res.status(401).json({ error: "no-auth" });
    }

    // ---- Flags server-side.
    const config = await flags();
    if (!config.habilitado) return res.status(503).json({ error: "coach-off" });

    // ---- ENTITLEMENT. Antes de mirar el payload y MUCHO antes de
    // llamar a OpenAI: el Coach es Pro y eso se decide acá, no en el
    // cliente. `req.body.jws` es la transacción firmada por Apple; si
    // no viene, vale lo último que el servidor haya verificado.
    if (!(await esPro(db, uid, req.body?.jws))) {
      console.warn("coach-sin-pro", { uid });
      return res.status(402).json({ error: "requiere-pro" });
    }

    // ---- Validación estricta de entrada.
    const parseo = Peticion.safeParse(req.body);
    if (!parseo.success) {
      console.warn("peticion-invalida", { uid });
      return res.status(400).json({ error: "schema" });
    }
    const peticion = parseo.data;

    // ---- Idempotencia: mismo requestID → misma respuesta, 0 tokens.
    const cacheRef = db.doc(`respuestas/${uid}-${peticion.requestID}`);
    const cacheada = await cacheRef.get();
    if (cacheada.exists) {
      return res.json(cacheada.data().respuesta);
    }

    // ---- Rate limit por usuario/día.
    if (!(await permitido(uid, config.maxRequestsPorDia))) {
      return res.status(429).json({ error: "rate-limit" });
    }

    // ---- OpenAI con salida estructurada estricta.
    const salida = salidas[peticion.accion];
    const openai = new OpenAI({ apiKey: OPENAI_API_KEY.value() });
    let respuesta;
    try {
      const completion = await openai.chat.completions.create({
        model: config.modelo,
        max_tokens: config.maxTokensSalida,
        response_format: { type: "json_schema", json_schema: salida },
        messages: [
          { role: "system", content: SISTEMA },
          { role: "user", content: JSON.stringify({
              accion: peticion.accion,
              detalle: peticion.detalle ?? null,
              programadoID: peticion.programadoID ?? null,
              contexto: peticion.contexto,
            }) },
        ],
      });
      const mensaje = completion.choices[0]?.message;
      // Con structured outputs el modelo todavía puede NEGARSE. En ese
      // caso `content` viene null y `refusal` trae el motivo: hay que
      // distinguirlo de un fallo de red, porque reintentar no ayuda.
      if (mensaje?.refusal) {
        console.warn("coach-rechazo", { uid, accion: peticion.accion });
        await devolverCredito(uid);
        return res.status(422).json({ error: "refusal" });
      }
      const texto = mensaje?.content;
      if (typeof texto !== "string" || texto.length === 0) {
        throw new Error("respuesta-vacia");
      }
      respuesta = JSON.parse(texto);   // el schema estricto ya lo garantiza
      console.log("coach-ok", {
        uid, accion: peticion.accion,
        tokens: completion.usage?.total_tokens ?? 0,
        ms: Date.now() - inicio,
      });
    } catch (error) {
      console.error("coach-fallo", { uid, accion: peticion.accion,
                                     tipo: error?.constructor?.name });
      // El corredor no gastó una consulta: no recibió ninguna.
      await devolverCredito(uid);
      return res.status(502).json({ error: "upstream" });
    }

    // Cache de idempotencia con TTL implícito (limpieza por Firestore
    // TTL policy sobre `expira` — ver DEPLOY.md).
    await cacheRef.set({
      respuesta,
      expira: new Date(Date.now() + 24 * 3600 * 1000),
    });
    return res.json(respuesta);
  });
