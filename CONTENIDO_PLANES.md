# CONTENIDO_PLANES — Qué podemos publicar en serio (§29/§40)

## Benchmark (solo estructura de producto, cero contenido copiado)
Apps consolidadas (Runna y similares) estructuran por: categorías
(couch-to-5K / mejorar 5K / 10K / 21K / 42K), inputs (objetivo, fecha,
días/semana, baseline), duración variable con mínimos por categoría,
roles de sesión (long run, quality, easy/recovery), descarga y taper,
y ritmos personalizados desde una referencia. Ese ESQUEMA está
implementado completo en `MotorPlanes.swift`. El CONTENIDO de cada
celda es metodología deportiva y se trata como tal: versionado, con
fuente, o no existe.

## Estado por categoría (V1)

| Categoría | Arquetipo | Contenido | ¿Proponible? |
|---|---|---|---|
| Primeros 5K | `primeros-5k@2` · 6 sem · 2-3 días | PROVISIONAL real (caminata/trote progresivo, ritmos libres) | SÍ (etiquetado provisional) |
| Rumbo a 10K | `10k-continuo@2` · 8 sem · 2-3 días | PROVISIONAL real (rodajes + larga progresiva, ritmos libres) | SÍ (etiquetado provisional) |
| Mejorar 5K | `mejorar-5k@1` · 6-8+ sem · 3-5 días | **NO EXISTE** | NO — el motor responde "en camino" |
| Media maratón | `media-maraton@1` · 10-12+ sem · 3-5 días | **NO EXISTE** | NO — ídem |
| Maratón | `maraton@1` · 14-16+ sem · 3-5 días | **NO EXISTE** | NO — ídem |

**Regla dura aplicada:** ninguna categoría sin contenido validado se
marca lista ni se rellena con workouts inventados. La App Store NO
debe prometer 21K/42K en V1.

## Qué falta para completar cada categoría (trabajo DEPORTIVO, no de software)
1. **Mejorar 5K**: progresión de calidad (tempo/umbral/series) con
   fuente citable + rangos de volumen semanal + descarga. Requiere
   además metodología de ritmos (PaceMethodology) para que la calidad
   tenga sentido — sin ritmos resueltos, un plan de series es humo.
2. **Media maratón**: 10-12 semanas, larga progresiva con tope
   justificado, semanas de descarga, taper de 1-2 semanas. Puede
   existir una variante "completar" con ritmos libres (como el 10K)
   ANTES que la variante "con ritmos" — camino más corto a soportarla.
3. **Maratón**: ídem media con más exigencia de fuentes (larga máxima,
   taper de 2-3 semanas). Última en llegar.
4. Para las 5: definir `tiposDeSemana` (carga/descarga/taper) y
   volúmenes objetivo por semana — la infraestructura ya tiene los
   campos, esperan contenido con metodología versionada.

**Riesgo real declarado:** el contenido deportivo es EL bloqueante de
producto para prometer 21K/42K. No es código: son decisiones de
entrenamiento con fuentes, y llevan su tiempo de investigación.

## GPT futuro (§41) — punto exacto de integración
`CambioPropuesto` → `ValidadorDeCoach.validar(_:en:hoy:)` →
aceptación del usuario → mutación versionada del dominio. GPT podrá
explicar sesiones, proponer reprogramaciones (el motor valida rango y
estado), interpretar feedback y sugerir ajustes de volumen — pero
`ajustarVolumenSemana` se RECHAZA hasta que exista metodología
versionada que defina límites seguros, y nada de lo que proponga se
escribe al dominio o al Watch sin pasar por el validador + el usuario.
