# CONTENIDO_PLANES — Estado real del catálogo (§29/§40 + sprint final)

## Estado por categoría

| Categoría | Arquetipo | Contenido | ¿Proponible? |
|---|---|---|---|
| Primeros 5K | `primeros-5k@2` · 6 sem · 2-3 días | PROVISIONAL real (caminata/trote, ritmos libres) | SÍ |
| Rumbo a 10K | `10k-continuo@2` · 8 sem · 2-3 días | PROVISIONAL real (rodajes + larga, ritmos libres) | SÍ |
| Mejorar 5K | `mejorar-5k@1` · 8 sem · 3-5 días | **v1 con metodología** (umbral/intervalos alternados, descarga sem 4, test final) | SÍ |
| Media maratón | `media-maraton@1` · 12 sem · 3-5 días | **v1 con metodología** (larga 10→18 km, descargas 4/8, taper 2 sem) | SÍ |
| Maratón | `maraton@1` · 16 sem · 3-5 días | **v1 con metodología** (larga 12→30 km, descargas 4/8/12, finales a ritmo maratón, taper 3 sem) | SÍ |

Fuentes y principios: **METODOLOGIA.md** (Riegel 1981; Faude 2009;
Billat 1996/2001; Seiler 2010; Bosquet 2007 + consensos declarados).
Generación: `Maraton/ContenidoPlanes.swift` — progresiones DECLARATIVAS
(cada número sale de una regla explícita), zonas SIMBÓLICAS resueltas
por `MetodologiaMaratoniaV1` contra el baseline al adoptar.

## Días concretos y distribución

- El corredor elige DÍAS de la semana (L-D) en el onboarding; se
  guardan en `PerfilDeportivo.diasElegidos` (1 = lunes … 7 = domingo).
- `MotorPlanificacion.distribuir` mapea el orden del template a esos
  días: sesiones SOLO en días disponibles, larga al último día, carrera
  objetivo pineada a su fecha real aunque no sea día habitual.
- La separación de sesiones exigentes es CONTENIDO (orden del template
  versionado), no una regla inventada del motor.

## Pendiente honesto

- `10k-continuo` v3 con calidad y 10 semanas (hoy corre la v2 provisional).
- Validación física de los arquetipos nuevos por corredores reales —
  la metodología está citada y testeada, pero ningún plan se declara
  "probado en la calle" hasta que lo esté.
- Variantes "completar" vs "con ritmos" para media/maratón.

## GPT (§41) — punto de integración

`CambioPropuesto` → `ValidadorDeCoach.validar` → usuario → dominio.
`ajustarVolumenSemana` sigue RECHAZADO hasta metodología de ajuste de
volumen versionada. Nada escribe al Watch sin pasar por el validador.
