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

## Duraciones de arquetipos (v1)

| Arquetipo | Semanas | Respaldo |
|---|---|---|
| Mejorar 5K | 8 | Ventana suficiente para ciclo calidad+descarga+test. Benchmark de producto coincide (~8); adoptado como decisión Maratonia, no copiado. |
| Rumbo a 10K | 8 (provisional) | Contenido continuo provisional previo; pendiente v3 con calidad. |
| Media maratón | 12 | Progresión de larga 10→18 km a ≤2 km/sem con 2 descargas + taper 2 sem (fuente 5). |
| Maratón | 16 | Progresión 12→30 km a ≤2 km/sem con 3 descargas + taper 3 sem (fuente 5). |

Variantes más cortas: NO soportadas en v1 — el motor responde
"tiempo insuficiente" antes que comprimir una progresión.

## Distribución semanal (arquitectura vs metodología)

- La SEPARACIÓN de sesiones exigentes vive en el ORDEN del template
  (contenido versionado): calidad a mitad de semana, larga al final.
- El motor (`MotorPlanificacion.distribuir`) solo MAPEA ese orden a los
  días concretos que el corredor eligió — jamás inventa carga ni
  programa en días no disponibles. Si hay más días que sesiones, elige
  el subconjunto mejor repartido incluyendo siempre el último día
  (donde el template pone la larga/carrera).
