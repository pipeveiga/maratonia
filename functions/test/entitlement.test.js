"use strict";

const { test } = require("node:test");
const assert = require("node:assert");

const {
  BUNDLE_ID, PRODUCTOS_PRO, otorgaPro, verificarTransaccion,
  entitlementGuardado, esPro,
} = require("../entitlement");

const AHORA = 1_760_000_000_000;
const FUTURO = AHORA + 30 * 24 * 3600 * 1000;
const PASADO = AHORA - 24 * 3600 * 1000;

function transaccion(extra = {}) {
  return {
    bundleId: BUNDLE_ID,
    productId: "maratonia.pro.yearly",
    expiresDate: FUTURO,
    originalTransactionId: "1000000",
    ...extra,
  };
}

/// Firestore de mentira: lo justo para probar la lógica sin red.
function db(documentos = {}) {
  return {
    escrituras: [],
    doc(ruta) {
      const self = this;
      return {
        async get() {
          const datos = documentos[ruta];
          return { exists: datos !== undefined, data: () => datos };
        },
        async set(datos) {
          self.escrituras.push({ ruta, datos });
          documentos[ruta] = { ...(documentos[ruta] ?? {}), ...datos };
        },
      };
    },
  };
}

// ---- Qué otorga Pro

test("una transacción vigente de un producto Pro otorga Pro", () => {
  assert.equal(otorgaPro(transaccion(), AHORA), true);
});

test("una transacción VENCIDA no otorga Pro", () => {
  assert.equal(otorgaPro(transaccion({ expiresDate: PASADO }), AHORA), false);
});

test("una transacción REVOCADA no otorga Pro", () => {
  // Reembolso o disputa: Apple la revoca y deja de valer, aunque no
  // haya vencido.
  assert.equal(
    otorgaPro(transaccion({ revocationDate: PASADO }), AHORA), false);
});

test("un producto que no es nuestro no otorga Pro", () => {
  assert.equal(otorgaPro(transaccion({ productId: "otra.app.pro" }), AHORA), false);
});

test("una transacción de OTRO bundle no otorga Pro", () => {
  // Sin este control, una suscripción comprada en cualquier otra app
  // firmada por Apple serviría para entrar al Coach.
  assert.equal(otorgaPro(transaccion({ bundleId: "com.otra.app" }), AHORA), false);
});

test("sin vencimiento no se asume vigente", () => {
  const sinFecha = transaccion();
  delete sinFecha.expiresDate;
  assert.equal(otorgaPro(sinFecha, AHORA), false);
});

test("los dos productos declarados otorgan Pro", () => {
  for (const productId of PRODUCTOS_PRO) {
    assert.equal(otorgaPro(transaccion({ productId }), AHORA), true, productId);
  }
});

// ---- Verificación de la firma

test("un JWS inventado NO verifica", async () => {
  // El caso adversarial central: alguien arma un token que dice lo que
  // quiere. Sin la firma de Apple no pasa.
  const falso = Buffer.from(JSON.stringify({ alg: "none" })).toString("base64url")
    + "." + Buffer.from(JSON.stringify(transaccion())).toString("base64url")
    + ".firma";
  assert.equal(await verificarTransaccion(falso), null);
});

test("basura como JWS no rompe ni pasa", async () => {
  for (const entrada of ["", "x", null, undefined, 42, {}, "a".repeat(9000)]) {
    assert.equal(await verificarTransaccion(entrada), null);
  }
});

// ---- El entitlement guardado

test("sin documento guardado no es Pro", async () => {
  assert.equal(await entitlementGuardado(db(), "uid-1", AHORA), false);
});

test("el entitlement guardado vale hasta que vence", async () => {
  const base = db({
    "users/uid-1/entitlement/pro": { pro: true, expiresDate: FUTURO },
    "users/uid-2/entitlement/pro": { pro: true, expiresDate: PASADO },
  });
  assert.equal(await entitlementGuardado(base, "uid-1", AHORA), true);
  assert.equal(await entitlementGuardado(base, "uid-2", AHORA), false);
});

// ---- La función que usa el endpoint

test("un UID sin nada NO es Pro aunque mande un jws falso", async () => {
  const base = db();
  const falso = "no.es.un.jws";
  assert.equal(await esPro(base, "uid-1", falso, AHORA), false);
  assert.equal(base.escrituras.length, 0, "no se guarda nada de un jws inválido");
});

test("un jws inválido NO borra un entitlement ya verificado", async () => {
  // El cliente puede mandar una transacción vieja de más; eso no puede
  // costarle el Pro que el servidor ya verificó.
  const base = db({ "users/uid-1/entitlement/pro": { pro: true, expiresDate: FUTURO } });
  assert.equal(await esPro(base, "uid-1", "basura", AHORA), true);
});

test("el entitlement guardado alcanza sin mandar jws", async () => {
  const base = db({ "users/uid-1/entitlement/pro": { pro: true, expiresDate: FUTURO } });
  assert.equal(await esPro(base, "uid-1", undefined, AHORA), true);
});

test("un entitlement vencido deja de valer sin necesidad de que nadie lo borre", async () => {
  const base = db({ "users/uid-1/entitlement/pro": { pro: true, expiresDate: PASADO } });
  assert.equal(await esPro(base, "uid-1", undefined, AHORA), false);
});

test("el UID del path es el único que decide: el body no participa", async () => {
  // uid-2 es Pro; uid-1 no. Que el cuerpo diga lo que diga, `esPro`
  // solo recibe el uid que salió de verifyIdToken.
  const base = db({ "users/uid-2/entitlement/pro": { pro: true, expiresDate: FUTURO } });
  assert.equal(await esPro(base, "uid-1", undefined, AHORA), false);
  assert.equal(await esPro(base, "uid-2", undefined, AHORA), true);
});

// ---- Configuración de producción (§27)

test("el Apple ID de la app está configurado y es el real", () => {
  const { APP_APPLE_ID } = require("../entitlement");
  assert.equal(APP_APPLE_ID, 6796521566);
});

test("se construyen los DOS verificadores: producción y sandbox", () => {
  // Con el Apple ID puesto, producción entra. Sin él quedaba solo
  // sandbox y toda transacción de producción fallaba — cerrado, pero
  // inservible para la App Store.
  const { obtenerVerificadores } = require("../entitlement");
  const verificadores = obtenerVerificadores();
  assert.equal(verificadores.length, 2,
    "producción + sandbox: TestFlight usa sandbox y la App Store producción");
});

test("una transacción de producción falsa NO pasa por tener el Apple ID", async () => {
  // Tener configurado producción no relaja nada: la firma sigue siendo
  // lo único que decide.
  const falso = Buffer.from(JSON.stringify({ alg: "ES256" })).toString("base64url")
    + "." + Buffer.from(JSON.stringify({
        bundleId: BUNDLE_ID, productId: "maratonia.pro.yearly",
        expiresDate: FUTURO, appAppleId: 6796521566,
      })).toString("base64url")
    + ".firma-inventada";
  assert.equal(await verificarTransaccion(falso), null);
});

test("los productos declarados son EXACTAMENTE los de App Store Connect", () => {
  // Si estos IDs se separan de los de ASC, las compras dejan de
  // reconocerse y el corredor paga sin recibir nada.
  assert.deepEqual([...PRODUCTOS_PRO].sort(),
                   ["maratonia.pro.monthly", "maratonia.pro.yearly"]);
});
