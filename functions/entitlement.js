"use strict";

// ENTITLEMENT PRO, DEL LADO DEL SERVIDOR.
//
// La regla que justifica todo este archivo: **la app nunca puede decir
// "soy Pro" y que el backend le crea**. Un booleano que viaja desde el
// cliente lo escribe cualquiera con un proxy.
//
// Lo que sí viaja es la TRANSACCIÓN FIRMADA POR APPLE (el JWS que da
// StoreKit 2). El backend verifica esa firma contra los certificados
// raíz de Apple —que son públicos y están en `certs/`— y recién
// entonces decide. No hace falta ninguna clave privada nuestra para
// esto: la App Store Server API (Issuer ID + Key ID + .p8) hace falta
// para CONSULTARLE cosas a Apple, no para verificar lo que Apple ya
// firmó.
//
// El resultado se guarda en `users/{uid}/entitlement/pro`, escrito solo
// con el Admin SDK. Las reglas de Firestore le prohíben al cliente
// escribir ahí, así que ese documento es la memoria confiable de quién
// es Pro entre requests.

const fs = require("fs");
const path = require("path");
const admin = require("firebase-admin");
const { SignedDataVerifier, Environment } = require("@apple/app-store-server-library");

const BUNDLE_ID = "com.pipeveiga.maraton";

/// Los productos que otorgan Pro. Si mañana hay más, se agregan acá y
/// en `ProductoPro` del cliente — nunca solo en el cliente.
const PRODUCTOS_PRO = new Set([
  "maratonia.pro.monthly",
  "maratonia.pro.yearly",
]);

function rootCAs() {
  const dir = path.join(__dirname, "certs");
  return fs.readdirSync(dir)
    .filter((n) => n.endsWith(".cer"))
    .map((n) => fs.readFileSync(path.join(dir, n)));
}

// El Apple ID NUMÉRICO de la app en App Store Connect. La librería de
// Apple lo exige para verificar transacciones de PRODUCCIÓN (no para
// sandbox). No es un secreto —es público en la ficha de la App Store—,
// pero todavía no existe: la app no está creada en ASC.
//
// Mientras no esté, el verificador de producción no se construye y una
// transacción de producción NO verifica. Eso es fallar CERRADO: nadie
// entra de más. Sandbox (que es lo que usa TestFlight) funciona igual,
// así que se puede probar todo el circuito hoy.
const APP_APPLE_ID = process.env.APP_APPLE_ID
  ? Number(process.env.APP_APPLE_ID) : null;

let verificadores = null;
function obtenerVerificadores() {
  if (verificadores) return verificadores;
  const caes = rootCAs();
  const lista = [new SignedDataVerifier(caes, true, Environment.SANDBOX, BUNDLE_ID)];
  if (APP_APPLE_ID) {
    lista.unshift(new SignedDataVerifier(
      caes, true, Environment.PRODUCTION, BUNDLE_ID, APP_APPLE_ID));
  } else {
    console.warn("entitlement-sin-app-apple-id",
                 { efecto: "solo se verifican transacciones de sandbox" });
  }
  verificadores = lista;
  return verificadores;
}

/// Verifica el JWS y devuelve la transacción decodificada, o null.
/// Se prueba contra los dos entornos porque el cliente no nos dice —y
/// no debería decirnos— en cuál está.
async function verificarTransaccion(jws) {
  if (typeof jws !== "string" || jws.length === 0 || jws.length > 8192) return null;
  for (const verificador of obtenerVerificadores()) {
    try {
      return await verificador.verifyAndDecodeTransaction(jws);
    } catch {
      // Firma inválida para ESE entorno: se prueba el otro.
    }
  }
  return null;
}

/// ¿Esta transacción, ya verificada, otorga Pro AHORA?
function otorgaPro(transaccion, ahora = Date.now()) {
  if (!transaccion) return false;
  if (transaccion.bundleId !== BUNDLE_ID) return false;
  if (!PRODUCTOS_PRO.has(transaccion.productId)) return false;
  // Reembolsada o revocada por Apple.
  if (transaccion.revocationDate) return false;
  // Las suscripciones traen vencimiento; si falta, no se asume vigente.
  if (typeof transaccion.expiresDate !== "number") return false;
  return transaccion.expiresDate > ahora;
}

/// Guarda el veredicto. Documento escrito SOLO por el backend.
async function guardar(db, uid, transaccion) {
  await db.doc(`users/${uid}/entitlement/pro`).set({
    pro: true,
    productId: transaccion.productId,
    expiresDate: transaccion.expiresDate,
    // El ID original de la suscripción: sirve para reconocerla entre
    // renovaciones sin volver a pedirle nada al cliente.
    originalTransactionId: transaccion.originalTransactionId ?? null,
    verificadoEl: Date.now(),
  }, { merge: true });
}

/// Lo último que el servidor verificó para este UID. Es lo que permite
/// que el corredor use el Coach sin tener que mandar el JWS en cada
/// request (y sin que el backend tenga que creerle nada nuevo).
async function entitlementGuardado(db, uid, ahora = Date.now()) {
  try {
    const doc = await db.doc(`users/${uid}/entitlement/pro`).get();
    if (!doc.exists) return false;
    const datos = doc.data();
    return datos.pro === true && typeof datos.expiresDate === "number"
      && datos.expiresDate > ahora;
  } catch {
    return false;
  }
}

/// LA función que usa el endpoint. Devuelve true solo si este UID es Pro
/// de verdad: o porque acaba de mandar una transacción firmada válida, o
/// porque el servidor ya la verificó antes y sigue vigente.
///
/// Nunca mira un campo del body que diga "isPro".
async function esPro(db, uid, jws, ahora = Date.now()) {
  if (jws) {
    const transaccion = await verificarTransaccion(jws);
    if (otorgaPro(transaccion, ahora)) {
      await guardar(db, uid, transaccion);
      return true;
    }
    // Un JWS presente pero inválido/vencido no descarta lo ya guardado:
    // puede ser una transacción vieja que el cliente mandó de más.
  }
  return entitlementGuardado(db, uid, ahora);
}

module.exports = {
  BUNDLE_ID,
  PRODUCTOS_PRO,
  verificarTransaccion,
  otorgaPro,
  entitlementGuardado,
  esPro,
};
