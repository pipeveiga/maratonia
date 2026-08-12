# METODOLOGIA — Fuentes deportivas de Maratonia v1

Regla dura: cada decisión metodológica declara FUENTE, VERSIÓN y QUÉ
RESPALDA. Lo que no tiene fuente publicable se marca CONSENSO (práctica
extendida de coaching sin paper único) y se usa con rangos amplios. No
se copian tablas propietarias (VDOT/Daniels, planes Runna, etc.) —
Runna y otras apps se miraron SOLO como benchmark de forma de producto.

## Fuentes citadas (metodología `maratonia@1`)

| # | Fuente | Qué decisión respalda |
|---|---|---|
| 1 | P. S. Riegel, "Athletic Records and Human Endurance", *American Scientist* 69(3), 1981 | Proyección de tiempos entre distancias: t2 = t1·(d2/d1)^1.06. El paper valida el modelo de 1500 m a maratón — ese rango completo se usa para DERIVAR ZONAS. (El predictor de marcas de la UI conserva su guarda más estricta de 1/4x-4x.) |
| 2 | O. Faude, W. Kindermann, T. Meyer, "Lactate Threshold Concepts", *Sports Medicine* 39(6), 2009 | El umbral de lactato corresponde a una intensidad sostenible ~45-60 min de carrera → ritmo de UMBRAL = ritmo de la distancia cuya proyección de Riegel da 60 min. |
| 3 | V. Billat & J. P. Koralsztein, "Significance of the velocity at VO2max...", *Sports Medicine* 22(2), 1996; V. Billat, "Interval Training for Performance", *Sports Medicine* 31(1), 2001 | vVO2max se sostiene ~4-8 min (≈ ritmo de carrera de 3-5 km) → INTERVALO = ritmo proyectado de 3000 m; REPETICIÓN = ritmo proyectado de 1500 m (esfuerzos por encima de vVO2max). |
| 4 | S. Seiler, "What is Best Practice for Training Intensity and Duration Distribution in Endurance Athletes?", *IJSPP* 5(3), 2010 | Distribución ~80/20: una sola sesión de calidad semanal en los arquetipos; el resto del volumen claramente fácil. También respalda que FÁCIL debe quedar bien por debajo del umbral. |
| 5 | L. Bosquet, J. Montpetit, D. Arvisais, I. Mujika, "Effects of Tapering on Performance: A Meta-Analysis", *Medicine & Science in Sports & Exercise* 39(8), 2007 | TAPER: reducción de volumen del 41-60% durante ~2 semanas manteniendo intensidad y frecuencia → taper de 2 semanas (media) y 3 (maratón) con bloques de umbral cortos hasta el final. |

## Decisiones CONSENSO (sin paper único; rangos amplios y declarados)

- **Fácil** = ritmo de maratón proyectado +45 a +90 s/km; **Recuperación** = +90 a +150 s/km. Coherentes con (4): claramente subumbral. Sin ancla numérica publicada única.
- **Descarga cada 4ª semana** (larga −25-30%): periodización clásica.
- **Progresión de la larga** ≤ +1-2 km/semana; **tope 30 km** (maratón) y **18 km** (media): control de carga.
- **Bandas de ejecución** (±5 a ±8 s/km sobre el ritmo central derivado): tolerancia práctica, no fisiología.

## Qué produce la metodología

`MetodologiaMaratoniaV1` (Shared/DominioV2.swift, id `maratonia@1`):
determinística y testeable. Entrada: una marca real (1500 m-42 km, 4′-4 h).
Salida: rangos seg/km para repetición/intervalo/umbral/maratón (fuentes
1-3) y fácil/recuperación (consenso). Referencia fuera de rango → la
zona queda SIMBÓLICA y el plan funciona igual (nunca bloquea).

## Duraciones de arquetipos

| Arquetipo | Semanas | Días | Respaldo |
|---|---|---|---|
| Primeros 5K | 6 | 2-3 | Progresión caminata/trote. No exige base previa: ESTE es el bloque base. |
| Mejorar 5K | 8 | 3-5 | Ventana suficiente para ciclo calidad+descarga+test. Benchmark de producto coincide (~8); adoptado como decisión Maratonia, no copiado. |
| Rumbo a 10K | 8 | 2-3 | Contenido continuo provisional; pendiente v3 con calidad. |
| Mejorar 10K | 10 | 3-5 | Umbral e intervalos alternados + larga a 16 km + taper 2 sem. |
| Media maratón | 12 | 3-5 | Progresión de larga 10→18 km a ≤2 km/sem con 2 descargas + taper 2 sem (fuente 5). |
| Mejorar media | 12 | 3-5 | Agrega bloques AL RITMO de media desde la semana 6; larga a 20 km. |
| Media · rendimiento | 14 | 5-6 | Dos calidades semanales + rodaje medio; larga a 22 km. Elegibilidad estricta. |
| Maratón | 16 | 3-5 | Progresión 12→30 km a ≤2 km/sem con 3 descargas + taper 3 sem (fuente 5). |
| Mejorar maratón | 18 | 4-5 | Larga a 32 km con finales a ritmo de maratón crecientes desde la sem. 7. |
| Maratón · rendimiento | 18 | 5-6 | Dos calidades + bloques largos a ritmo de maratón. Elegibilidad estricta. |

Variantes más cortas: NO soportadas — el motor responde
"tiempo insuficiente" antes que comprimir una progresión.

## Fases del bloque (§15)

Cada semana declara su fase y su PROPÓSITO, para que el corredor pueda
leer por qué esa semana es como es. El reparto es ESTRUCTURAL (no
metodología): descarga y pico mandan; del resto, el primer ~30 % es
`base`, hasta ~65 % `construccion`, y lo que queda `especifica`. El
taper y la semana de carrera los declara el contenido.

## Perfil del corredor y elegibilidad (DECISIÓN MARATONIA)

Los umbrales de abajo NO salen de un paper: son criterio de Maratonia,
declarado como tal. Su función no es aprobar o reprobar a nadie, sino
evitar vender un plan que no se sostiene.

**Requisitos "cómodos"** de un objetivo, derivados de la DISTANCIA de
la carrera (`d` = km de la carrera) y no de números sueltos:

| Intención | Volumen semanal | Tirada larga reciente | Días | Meses corriendo |
|---|---|---|---|---|
| Completar (5K) | — | — | 2 | — |
| Completar (10K/21K/42K) | 1,5 · d | 0,45 · d | 2-3 | 1 / 3 / 6 |
| Mejorar | 3 · d | 0,6 · d | 3-4 | 3 / 6 / 9 |
| Rendimiento | 4 · d | 0,8 · d | 5 | 12 + marca real |

Por encima de esos valores → **elegible**. Entre el 40 % y el 100 % →
**elegible conservador** (se genera el plan y se explican los motivos).
Por debajo del 40 % → **requiere fase base**, con un objetivo puente
sugerido (siempre hacia abajo, nunca hacia arriba).

Bloqueos que no se negocian: fecha imposible (menos semanas que el
mínimo del arquetipo), días elegidos por debajo del mínimo, y
rendimiento sin marca de referencia o con lesión declarada.

**Ausencia de datos ≠ sedentarismo.** Sin historial en Salud y sin
declaración, el veredicto es conservador — nunca un bloqueo.

## Arranque del plan (DECISIÓN MARATONIA)

La primera semana del plan **no puede superar en más de un 20 % el
volumen que el corredor viene haciendo**. Si el template pide más, las
tres primeras semanas se atenúan con una rampa lineal hasta volver al
plan completo. Nunca escala hacia arriba y nunca toca la carrera
objetivo. Piso de la atenuación: 50 % — si hiciera falta recortar más,
el problema es de elegibilidad y no de arranque.

Deliberadamente NO se usa "la regla del 10 % semanal": no tiene
respaldo sólido y trata igual a quien corre 10 km/semana y a quien
corre 90. Esto es un techo de ENTRADA, aplicado una sola vez.

## Adaptación (§36-§41)

- **Reducir es flexible; aumentar prácticamente no existe.** El Coach
  no puede subir carga: el validador rechaza cualquier factor ≥ 1.
- **Una buena sesión aislada no habilita nada.** "Muy bien" no es un
  evento; solo el extremo alto ("muy exigido") pide atención.
- **Los entrenamientos perdidos no se compensan.** Nunca se apilan
  kilómetros ni se mueven sesiones para "recuperar" lo no hecho.
- **Tolerancia de volumen semanal**: −25 % / +5 % sobre lo que la
  semana prescribe. Asimétrica a propósito.
- **Contrato de adaptabilidad por rol**: la carrera objetivo es
  intocable; la tirada larga se mueve y se acorta (hasta 60 %) pero no
  se convierte; las calidades se convierten a rodaje fácil; fácil y
  recuperación son lo primero que se sacrifica.
- **Recuperación mínima**: una sesión exigente no puede quedar pegada
  a otra exigente — hace falta un día de por medio.

## Distribución semanal (arquitectura vs metodología)

- La SEPARACIÓN de sesiones exigentes vive en el ORDEN del template
  (contenido versionado): calidad a mitad de semana, larga al final.
- El motor (`MotorPlanificacion.distribuir`) solo MAPEA ese orden a los
  días concretos que el corredor eligió — jamás inventa carga ni
  programa en días no disponibles. Si hay más días que sesiones, elige
  el subconjunto mejor repartido incluyendo siempre el último día
  (donde el template pone la larga/carrera).
- El **día de la tirada larga** lo elige el corredor. Sin preferencia,
  queda donde lo puso el template; la app NO fuerza domingo.

## Distribución semanal (arquitectura vs metodología)

- La SEPARACIÓN de sesiones exigentes vive en el ORDEN del template
  (contenido versionado): calidad a mitad de semana, larga al final.
- El motor (`MotorPlanificacion.distribuir`) solo MAPEA ese orden a los
  días concretos que el corredor eligió — jamás inventa carga ni
  programa en días no disponibles. Si hay más días que sesiones, elige
  el subconjunto mejor repartido incluyendo siempre el último día
  (donde el template pone la larga/carrera).
