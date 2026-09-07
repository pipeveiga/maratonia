const test = require('node:test');
const assert = require('node:assert/strict');
const { Peticion } = require('../schemas');
// Generado con JSONEncoder y las declaraciones reales de ContextoCoach
// en Maraton/Coach.swift: los Optional nil no aparecen en el objeto.
const contextoSwift = require('./fixtures/contexto-swift-sin-opcionales.json');

function peticion() {
  return {
    accion: 'estado', requestID: '22222222-2222-4222-8222-222222222222',
    contexto: structuredClone(contextoSwift),
  };
}

test('acepta el JSON de Swift sin opcionales en contexto y objetos anidados', () => {
  const resultado = Peticion.safeParse(peticion());
  assert.equal(resultado.success, true, JSON.stringify(resultado.error?.issues));
});

test('conserva compatibilidad con opcionales enviados como null', () => {
  const entrada = peticion();
  Object.assign(entrada.contexto, {
    fechaCarrera: null, baseline: null, semanaActual: null, semanasTotales: null,
    faseSemanaActual: null, cumplimientoPorciento: null, kmUltimas4Semanas: null,
  });
  Object.assign(entrada.contexto.ultimasSesiones[0], { km: null, ritmoSegKm: null, sensacion: null });
  Object.assign(entrada.contexto.eventos[0], { programadoID: null, detalle: null });
  entrada.contexto.proximosEntrenamientos[0].km = null;
  assert.equal(Peticion.safeParse(entrada).success, true);
});

test('los opcionales presentes siguen validando tipo, rango y UUID', () => {
  for (const modificar of [
    p => p.contexto.baseline = { distanciaMetros: -1, segundos: 600 },
    p => p.contexto.semanaActual = '1',
    p => p.contexto.cumplimientoPorciento = 101,
    p => p.contexto.ultimasSesiones[0].sensacion = 'inventada',
    p => p.contexto.eventos[0].programadoID = 'invalido',
    p => p.contexto.proximosEntrenamientos[0].km = -1,
  ]) {
    const entrada = peticion();
    modificar(entrada);
    assert.equal(Peticion.safeParse(entrada).success, false);
  }
});

test('no flexibiliza campos obligatorios', () => {
  for (const modificar of [
    p => delete p.contexto.idioma,
    p => delete p.contexto.eventos,
    p => delete p.contexto.ultimasSesiones[0].cumplida,
    p => delete p.contexto.proximosEntrenamientos[0].programadoID,
  ]) {
    const entrada = peticion();
    modificar(entrada);
    assert.equal(Peticion.safeParse(entrada).success, false);
  }
});

test('sigue rechazando GPS y datos desconocidos en cualquier nivel', () => {
  for (const modificar of [
    p => p.coordenadas = [],
    p => p.contexto.rutaGPS = [],
    p => p.contexto.ultimasSesiones[0].latitud = 1,
    p => p.contexto.eventos[0].muestras = [],
  ]) {
    const entrada = peticion();
    modificar(entrada);
    assert.equal(Peticion.safeParse(entrada).success, false);
  }
});
