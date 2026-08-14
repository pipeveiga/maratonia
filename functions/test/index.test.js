"use strict";

// EL TEST QUE FALTABA: que index.js CARGUE.
//
// El resto de la suite probaba schemas y entitlement, y ninguno cargaba
// el módulo del endpoint. Resultado: un backtick escrito dentro del
// prompt SISTEMA —que es un template literal— lo cortó al medio y dejó
// index.js con un error de sintaxis. Los 36 tests pasaron igual. Lo
// encontró el deploy, que es el peor lugar donde encontrarlo.

const { test } = require("node:test");
const assert = require("node:assert");
const fs = require("fs");
const path = require("path");

const FUENTE = fs.readFileSync(path.join(__dirname, "..", "index.js"), "utf8");

test("index.js se puede cargar", () => {
  // Sin admin.initializeApp() real no se puede require() acá, así que
  // se compila: alcanza para que un error de sintaxis no llegue nunca
  // más a un deploy.
  assert.doesNotThrow(() => new (require("vm").Script)(FUENTE, { filename: "index.js" }));
});

test("el prompt SISTEMA está entero y no se cortó", () => {
  const modulo = { exports: {} };
  // Se extrae el literal sin ejecutar el módulo.
  const desde = FUENTE.indexOf("const SISTEMA = `");
  const hasta = FUENTE.indexOf("\n`;", desde);
  assert.ok(desde > 0 && hasta > desde, "no se encontró el literal de SISTEMA");
  const prompt = FUENTE.slice(desde, hasta);
  assert.ok(!prompt.includes("`", "const SISTEMA = `".length),
    "hay un backtick adentro del prompt: corta el template literal");
  // Y las secciones que tienen que estar.
  for (const seccion of ["Reglas duras:", "FECHAS", "PEDIDOS EXPLÍCITOS"]) {
    assert.ok(prompt.includes(seccion), `falta la sección ${seccion}`);
  }
});

test("el endpoint exporta lo que espera Firebase", () => {
  assert.ok(/exports\.coach\s*=/.test(FUENTE));
  assert.ok(/exports\.borrarCuenta\s*=/.test(FUENTE));
});
