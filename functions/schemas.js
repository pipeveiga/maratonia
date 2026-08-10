// Schemas ESTRICTOS del Coach. El dominio del iPhone solo acepta JSON
// que valide acá Y en los Codable del cliente — texto libre jamás muta
// nada. Espejo exacto de los modelos Swift (Maraton/Coach.swift).
const { z } = require("zod");

// ---- DTO de ENTRADA (lo mínimo; nunca rutas GPS ni HealthKit crudo) --

const SesionResumida = z.object({
  fecha: z.string().max(10),              // "2026-08-10" (día local)
  tipo: z.string().max(30),
  km: z.number().min(0).max(500).nullable(),
  ritmoSegKm: z.number().int().min(120).max(1200).nullable(),
  cumplida: z.boolean(),
}).strict();

const ContextoCoach = z.object({
  idioma: z.enum(["es", "en"]),
  objetivo: z.string().max(30),
  fechaCarrera: z.string().max(10).nullable(),
  diasElegidos: z.array(z.number().int().min(1).max(7)).max(7),
  baseline: z.object({
    distanciaMetros: z.number().min(1500).max(42195),
    segundos: z.number().int().min(240).max(14400),
  }).strict().nullable(),
  semanaActual: z.number().int().min(1).max(60).nullable(),
  semanasTotales: z.number().int().min(1).max(60).nullable(),
  cumplimientoPorciento: z.number().min(0).max(100).nullable(),
  kmUltimas4Semanas: z.number().min(0).max(1000).nullable(),
  proximosEntrenamientos: z.array(z.object({
    programadoID: z.string().uuid(),
    dia: z.string().max(10),
    nombre: z.string().max(80),
    tipo: z.string().max(30),
    km: z.number().min(0).max(100).nullable(),
  }).strict()).max(14),
  ultimasSesiones: z.array(SesionResumida).max(10),
}).strict();

const Peticion = z.object({
  accion: z.enum(["explicar", "reorganizar", "analizar", "estado"]),
  requestID: z.string().uuid(),           // idempotencia
  contexto: ContextoCoach,
  // explicar: el entrenamiento puntual; reorganizar: el motivo del
  // cambio ("no puedo correr el jueves"); analizar: la sesión.
  detalle: z.string().max(500).optional(),
  programadoID: z.string().uuid().optional(),
}).strict();

// ---- Schemas de SALIDA (structured outputs de OpenAI) ---------------

const salidaExplicacion = {
  name: "CoachWorkoutExplanation",
  strict: true,
  schema: {
    type: "object", additionalProperties: false,
    required: ["titulo", "queEs", "paraQueSirve", "comoEncararlo"],
    properties: {
      titulo: { type: "string", maxLength: 80 },
      queEs: { type: "string", maxLength: 500 },
      paraQueSirve: { type: "string", maxLength: 500 },
      comoEncararlo: { type: "string", maxLength: 500 },
    },
  },
};

// Los cambios que puede proponer son EXACTAMENTE los que el validador
// del iPhone acepta: reprogramar u omitir. Nada de crear carga.
const salidaAjuste = {
  name: "CoachWeekAdjustment",
  strict: true,
  schema: {
    type: "object", additionalProperties: false,
    required: ["explicacion", "cambios"],
    properties: {
      explicacion: { type: "string", maxLength: 600 },
      cambios: {
        type: "array", maxItems: 7,
        items: {
          type: "object", additionalProperties: false,
          required: ["tipo", "programadoID", "nuevoDia"],
          properties: {
            tipo: { type: "string", enum: ["reprogramar", "omitir"] },
            programadoID: { type: "string" },
            // Para "omitir" va null.
            nuevoDia: { type: ["string", "null"] },
          },
        },
      },
    },
  },
};

const salidaAnalisis = {
  name: "CoachWorkoutAnalysis",
  strict: true,
  schema: {
    type: "object", additionalProperties: false,
    required: ["resumen", "loBueno", "aCuidar"],
    properties: {
      resumen: { type: "string", maxLength: 600 },
      loBueno: { type: "string", maxLength: 400 },
      aCuidar: { type: "string", maxLength: 400 },
    },
  },
};

const salidaEstado = {
  name: "CoachEstadoObjetivo",
  strict: true,
  schema: {
    type: "object", additionalProperties: false,
    required: ["veredicto", "detalle", "focoProximasSemanas"],
    properties: {
      veredicto: { type: "string", maxLength: 120 },
      detalle: { type: "string", maxLength: 600 },
      focoProximasSemanas: { type: "string", maxLength: 400 },
    },
  },
};

const salidas = {
  explicar: salidaExplicacion,
  reorganizar: salidaAjuste,
  analizar: salidaAnalisis,
  estado: salidaEstado,
};

module.exports = { Peticion, salidas };
