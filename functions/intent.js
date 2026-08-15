"use strict";

// LA PUERTA DE INTENCIÓN, DEL LADO DEL SERVIDOR.
//
// La app tiene la suya (Shared/IntencionCoach.swift) y es la que ahorra
// el viaje. Esta existe porque **el cliente no puede ser la única
// defensa**: un proxy, una build modificada o un request armado a mano
// se saltean cualquier gate de la app. Misma regla que con el
// entitlement — lo que protege plata o alcance se verifica acá.
//
// Es a propósito una copia CONSERVADORA de la del cliente: rechaza lo
// evidente y deja pasar lo dudoso. Si las dos discrepan, gana el
// modelo, que tiene su propia regla de alcance en el prompt. Lo que NO
// puede pasar es que algo obviamente ajeno llegue a OpenAI.

/// Raíces, no palabras: "corr" cubre correr, corro, corrí, corriendo.
const DEPORTE = [
  "corr", "rodaj", "entren", "plan", "sesion", "km", "kilometr", "ritmo",
  "tirad", "fondo", "serie", "umbral", "interval", "calentam", "trote",
  "carrera", "maraton", "media", "objetivo", "meta", "descans", "recuper",
  "volumen", "carga", "taper", "cuesta", "progres", "marca", "pulsac",
  "zapatill", "fuerza", "gimnas", "hidrat", "elong", "5k", "10k", "21k", "42k",
  "run", "train", "workout", "session", "pace", "mile", "tempo", "easy",
  "long", "warmup", "cooldown", "race", "goal", "rest", "recovery", "mileage",
];

const CUERPO = [
  "cansad", "agotad", "fatig", "pesad", "dolor", "duele", "doli", "molesti",
  "lesion", "lastim", "tiron", "contractur", "gemelo", "rodill", "tobill",
  "isquio", "cuadricep", "aquiles", "planta", "talon", "espalda", "cader",
  "ampoll", "enferm", "gripe", "resfri", "fiebre", "mareo", "durmi", "sueno",
  "tired", "sore", "pain", "hurt", "injur", "sick", "cramp",
];

const TIEMPO = [
  "hoy", "manana", "ayer", "semana", "finde", "mes", "dia",
  "lunes", "martes", "miercoles", "jueves", "viernes", "sabado", "domingo",
  "today", "tomorrow", "week", "monday", "tuesday", "wednesday", "thursday",
  "friday", "saturday", "sunday",
];

const OTRO_RUBRO = [
  "html", "css", "javascript", "typescript", "python", "swift", "codig",
  "code", "script", "json", "sql", "regex", "docker", "recet", "cocin",
  "torta", "chiste", "chist", "poema", "poesia", "cancion", "pelicul",
  "mundial", "futbol", "tenis", "presidente", "eleccion", "noticia",
  "clima", "horoscopo", "bitcoin", "dolar", "factura", "curriculum",
  "traduc", "ensayo", "monografia", "homework", "recipe", "joke", "poem",
  "translate", "essay", "invoice",
];

const INYECCION = [
  "ignora tus instruccion", "ignora las instruccion", "ignora tus reglas",
  "ignora todo", "ignora lo anterior", "olvida tus instruccion",
  "olvidate de tus instruccion", "olvida todo lo anterior", "system prompt",
  "prompt del sistema", "tus instrucciones son", "actua como si fueras",
  "hace de cuenta que sos", "a partir de ahora sos", "ignore previous",
  "ignore all previous", "ignore your instruction", "disregard previous",
  "you are now", "pretend you are", "jailbreak", "sin restricciones",
  "sin filtros",
];

const NEXOS = new Set(["x", "por", "mas", "menos", "entre", "dividido", "es",
                       "cuanto", "cuantos", "resultado", "suma", "resta", "veces"]);

/// Minúsculas, sin acentos, sin puntuación.
function tokenizar(texto) {
  if (typeof texto !== "string") return [];
  return texto
    .normalize("NFD").replace(/[̀-ͯ]/g, "")
    .toLowerCase()
    .split(/[^a-z0-9]+/)
    .filter(Boolean);
}

function hayRaiz(palabras, raices) {
  return palabras.some((p) => raices.some((r) => p.startsWith(r)));
}

function pareceCuenta(palabras) {
  const numeros = palabras.filter((p) => /^\d+$/.test(p)).length;
  if (numeros < 2) return false;
  return palabras.filter((p) => !/^\d+$/.test(p)).every((p) => NEXOS.has(p));
}

/// "dentro" | "fuera:otroRubro" | "fuera:inyeccion" | "fuera:vacio"
function clasificar(texto) {
  const palabras = tokenizar(texto);
  if (palabras.length === 0) return "fuera:vacio";
  const plano = palabras.join(" ");

  if (INYECCION.some((patron) => plano.includes(patron))) return "fuera:inyeccion";

  const dominio = hayRaiz(palabras, DEPORTE) || hayRaiz(palabras, CUERPO)
    || hayRaiz(palabras, TIEMPO);
  if (!dominio && hayRaiz(palabras, OTRO_RUBRO)) return "fuera:otroRubro";
  if (!dominio && pareceCuenta(palabras)) return "fuera:otroRubro";
  if (!dominio) return "fuera:otroRubro";
  return "dentro";
}

function estaFueraDeDominio(texto) {
  return clasificar(texto).startsWith("fuera");
}

module.exports = { clasificar, estaFueraDeDominio, tokenizar };
