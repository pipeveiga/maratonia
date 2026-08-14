// CONTRATO iOS ↔ backend.
//
// El riesgo que estos tests cubren: el cliente arma el JSON con
// JSONEncoder de Swift y el backend lo valida con zod. Si las dos
// definiciones se separan, el Coach devuelve 400 para todo el mundo y
// no hay forma de enterarse hasta que está desplegado.
//
// El detalle que rompe: **Swift OMITE las claves de los opcionales que
// valen nil**, no las manda como null. Verificado:
//     struct E: Codable { var a: String; var b: String? }
//     JSONEncoder().encode(E(a: "x", b: nil))  →  {"a":"x"}
// Un `z.string().nullable()` exige la clave presente, así que rechaza
// ese payload. Por eso los campos que en Swift son opcionales tienen
// que ser `.nullish()` (ausente O null), no `.nullable()`.

const test = require("node:test");
const assert = require("node:assert");
const { Peticion, salidas } = require("../schemas");

/// Un contexto MÍNIMO, tal cual lo codifica Swift para el caso más
/// común que existe: corredor sin fecha de carrera, sin baseline, sin
/// plan activo y sin historial de Salud. Todos esos campos son
/// opcionales en Swift, así que sus claves NO VIENEN.
const contextoMinimoComoLoMandaSwift = {
  // El ANCLA TEMPORAL es obligatoria: sin ella el modelo no puede
  // resolver "este sábado" (ver el caso del 14/8/2026).
  hoy: "2026-08-14",
  diaSemanaHoy: "friday",
  zonaHoraria: "America/Argentina/Buenos_Aires",
  idioma: "es",
  objetivo: "maraton",
  diasElegidos: [2, 4, 6, 7],
  diasImposibles: [],
  ventanas: [],
  eventos: [],
  proximosEntrenamientos: [],
  ultimasSesiones: [],
  // AUSENTES a propósito: fechaCarrera, baseline, semanaActual,
  // semanasTotales, faseSemanaActual, cumplimientoPorciento,
  // kmUltimas4Semanas.
};

/// El contexto completo, con todos los opcionales presentes.
const contextoCompleto = {
  // El ANCLA TEMPORAL es obligatoria: sin ella el modelo no puede
  // resolver "este sábado" (ver el caso del 14/8/2026).
  hoy: "2026-08-14",
  diaSemanaHoy: "friday",
  zonaHoraria: "America/Argentina/Buenos_Aires",
  idioma: "es",
  objetivo: "maraton",
  fechaCarrera: "2026-11-15",
  diasElegidos: [2, 4, 6, 7],
  diasImposibles: [3],
  baseline: { distanciaMetros: 5000, segundos: 1470 },
  semanaActual: 5,
  semanasTotales: 16,
  faseSemanaActual: "construccion",
  cumplimientoPorciento: 82,
  kmUltimas4Semanas: 148.6,
  ventanas: [
    { dias: 7, km: 38.2, salidas: 4, tiradaMasLargaKm: 16, mayorPausaDias: 2 },
    { dias: 28, km: 148.6, salidas: 16, tiradaMasLargaKm: 22, mayorPausaDias: 3 },
    { dias: 42, km: 210.4, salidas: 23, tiradaMasLargaKm: 22, mayorPausaDias: 5 },
  ],
  eventos: [
    { tipo: "sesion-perdida", severidad: "baja",
      programadoID: "3f2504e0-4f89-41d3-9a0c-0305e82c3301", detalle: null },
    { tipo: "molestia", severidad: "alta", programadoID: null, detalle: null },
  ],
  proximosEntrenamientos: [
    { programadoID: "3f2504e0-4f89-41d3-9a0c-0305e82c3302", dia: "2026-08-18", diaSemana: "tuesday",
      nombre: "Umbral 28′", tipo: "umbral", km: 9.4 },
    { programadoID: "3f2504e0-4f89-41d3-9a0c-0305e82c3303", dia: "2026-08-23", diaSemana: "sunday",
      nombre: "Tirada larga", tipo: "largo", km: 22 },
  ],
  ultimasSesiones: [
    { fecha: "2026-08-13", tipo: "facil", km: 10, ritmoSegKm: 330,
      cumplida: true, sensacion: "bien" },
    { fecha: "2026-08-11", tipo: "series", km: 8.2, ritmoSegKm: null,
      cumplida: false, sensacion: null },
  ],
};

const peticion = (contexto, extra = {}) => ({
  accion: "reorganizar",
  requestID: "3f2504e0-4f89-41d3-9a0c-0305e82c3300",
  contexto,
  ...extra,
});

// ---- Entrada -------------------------------------------------------

test("acepta el contexto mínimo que manda Swift (opcionales ausentes)", () => {
  const r = Peticion.safeParse(peticion(contextoMinimoComoLoMandaSwift));
  assert.ok(r.success,
    "un corredor sin fecha de carrera, sin baseline y sin plan tiene que " +
    "poder usar el Coach. Errores: " + JSON.stringify(r.error?.issues));
});

test("acepta el contexto completo", () => {
  const r = Peticion.safeParse(peticion(contextoCompleto));
  assert.ok(r.success, JSON.stringify(r.error?.issues));
});

test("acepta null explícito además de la clave ausente", () => {
  const conNulls = { ...contextoMinimoComoLoMandaSwift,
                     fechaCarrera: null, baseline: null, semanaActual: null,
                     semanasTotales: null, faseSemanaActual: null,
                     cumplimientoPorciento: null, kmUltimas4Semanas: null };
  assert.ok(Peticion.safeParse(peticion(conNulls)).success);
});

test("acepta las cuatro acciones y ninguna más", () => {
  for (const accion of ["explicar", "reorganizar", "analizar", "estado"]) {
    assert.ok(Peticion.safeParse(peticion(contextoCompleto, { accion })).success, accion);
  }
  assert.ok(!Peticion.safeParse(peticion(contextoCompleto, { accion: "aumentar" })).success);
});

test("acepta los rawValue reales de Swift para sensacion", () => {
  // SensacionEsfuerzo: case muyBien, bien, exigido, muyExigido
  for (const sensacion of ["muyBien", "bien", "exigido", "muyExigido"]) {
    const contexto = { ...contextoCompleto,
      ultimasSesiones: [{ fecha: "2026-08-13", tipo: "facil", km: 10,
                          ritmoSegKm: null, cumplida: true, sensacion }] };
    assert.ok(Peticion.safeParse(peticion(contexto)).success, sensacion);
  }
});

// ---- Lo que tiene que RECHAZAR -------------------------------------

test("rechaza una clave desconocida en el contexto", () => {
  const r = Peticion.safeParse(peticion({ ...contextoCompleto, rutaGPS: [[1, 2]] }));
  assert.ok(!r.success, "strict() tiene que frenar cualquier campo que no declaramos");
});

test("rechaza una clave desconocida en una sesión", () => {
  const contexto = { ...contextoCompleto,
    ultimasSesiones: [{ fecha: "2026-08-13", tipo: "facil", km: 10, ritmoSegKm: null,
                        cumplida: true, sensacion: null, frecuenciaCardiaca: 165 }] };
  assert.ok(!Peticion.safeParse(peticion(contexto)).success,
    "la FC cruda no puede entrar ni por accidente");
});

test("rechaza requestID que no sea uuid", () => {
  assert.ok(!Peticion.safeParse(
    peticion(contextoCompleto, { requestID: "abc" })).success);
});

test("rechaza valores fuera de rango", () => {
  const fuera = { ...contextoCompleto, cumplimientoPorciento: 250 };
  assert.ok(!Peticion.safeParse(peticion(fuera)).success);
  const diaInvalido = { ...contextoCompleto, diasElegidos: [0, 9] };
  assert.ok(!Peticion.safeParse(peticion(diaInvalido)).success);
});

test("rechaza un detalle desmedido", () => {
  assert.ok(!Peticion.safeParse(
    peticion(contextoCompleto, { detalle: "x".repeat(501) })).success);
});

// ---- Salidas -------------------------------------------------------

test("hay un schema de salida por acción", () => {
  assert.deepStrictEqual(Object.keys(salidas).sort(),
                         ["analizar", "estado", "explicar", "reorganizar"]);
  for (const [accion, schema] of Object.entries(salidas)) {
    assert.strictEqual(schema.strict, true, accion);
    assert.strictEqual(schema.schema.additionalProperties, false, accion);
  }
});

test("las operaciones son exactamente las cinco que valida el motor", () => {
  const tipos = salidas.reorganizar.schema.properties.cambios
    .items.properties.tipo.enum;
  assert.deepStrictEqual([...tipos].sort(),
    ["convertir", "mantener", "omitir", "reducir", "reprogramar"]);
  // Lo que NO puede existir: subir carga o inventar sesiones. Eso lo
  // decide el motor determinístico, nunca el modelo.
  for (const prohibida of ["aumentar", "crear", "reemplazar", "agregar"]) {
    assert.ok(!tipos.includes(prohibida), prohibida);
  }
});

// ---- El ancla temporal es obligatoria (caso del 14/8/2026)

test("sin ancla temporal el contexto NO pasa", () => {
  // Es lo que hacía que el Coach dijera "no hay sesiones el sábado"
  // teniendo una el sábado 15: recibía fechas ISO sueltas y ningún
  // punto de referencia. Ahora el contrato lo exige.
  for (const falta of ["hoy", "diaSemanaHoy", "zonaHoraria"]) {
    const contexto = { ...contextoCompleto };
    delete contexto[falta];
    const r = Peticion.safeParse(peticion(contexto));
    assert.equal(r.success, false, `debería faltar: ${falta}`);
  }
});

test("cada próximo entrenamiento trae su día de la semana", () => {
  const contexto = {
    ...contextoCompleto,
    proximosEntrenamientos: [{
      programadoID: "3f2504e0-4f89-41d3-9a0c-0305e82c3302",
      dia: "2026-08-15", nombre: "Rodaje suave", tipo: "facil", km: 6,
      // sin diaSemana
    }],
  };
  assert.equal(Peticion.safeParse(peticion(contexto)).success, false);
});

test("un día de la semana inventado no pasa", () => {
  const contexto = { ...contextoCompleto, diaSemanaHoy: "sabado" };
  assert.equal(Peticion.safeParse(peticion(contexto)).success, false);
});

test("EL CASO REPORTADO: viernes 14/8/2026 con sesión el sábado 15", () => {
  // Contexto exacto del reporte físico. Lo que se verifica acá es que
  // el contrato TRANSPORTA lo necesario para resolver "este sábado":
  // hoy es viernes, y hay una sesión cuyo diaSemana es saturday.
  const contexto = {
    ...contextoCompleto,
    hoy: "2026-08-14",
    diaSemanaHoy: "friday",
    proximosEntrenamientos: [
      { programadoID: "3f2504e0-4f89-41d3-9a0c-0305e82c3311", dia: "2026-08-15",
        diaSemana: "saturday", nombre: "Rodaje suave", tipo: "facil", km: 6 },
      { programadoID: "3f2504e0-4f89-41d3-9a0c-0305e82c3312", dia: "2026-08-16",
        diaSemana: "sunday", nombre: "Tirada larga", tipo: "largo", km: 10 },
      { programadoID: "3f2504e0-4f89-41d3-9a0c-0305e82c3313", dia: "2026-08-18",
        diaSemana: "tuesday", nombre: "Rodaje medio", tipo: "facil", km: 7 },
    ],
  };
  const r = Peticion.safeParse(peticion(contexto, {
    accion: "reorganizar", detalle: "No quiero correr este sábado",
  }));
  assert.equal(r.success, true);
  const sabados = r.data.contexto.proximosEntrenamientos
    .filter((p) => p.diaSemana === "saturday");
  assert.equal(sabados.length, 1, "el sábado 15 tiene que estar en el contexto");
  assert.equal(sabados[0].dia, "2026-08-15");
  assert.equal(sabados[0].nombre, "Rodaje suave");
});
