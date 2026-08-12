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

## Volumen planificado (HEURÍSTICA PROVISIONAL + estructura)

**El problema que resuelve.** Hasta el build 61 el volumen de una
sesión sumaba solo los segmentos que declaran distancia. Un
`umbral 32′` (1,5 km + 32 minutos + 1 km) contaba como **2,5 km**: los
32 minutos, más de 5 km reales, no existían para el motor. Eso
contaminaba el volumen semanal, el arranque conservador, las bandas del
validador, el detector de volumen bajo y lo que Progreso le muestra al
corredor.

**La regla, ahora única** (`CalculoVolumen`, un solo lugar):

- segmento con distancia → se suma tal cual;
- segmento medido en tiempo → se convierte con el ritmo de SU zona;
- un segmento con las dos metas cuenta **una sola vez**, por distancia
  (la misma prioridad que usa el motor para ejecutarlo).

**De dónde sale el ritmo de conversión**, en orden:

1. el ritmo ya resuelto del segmento (punto medio del rango) — es el
   caso normal, porque adoptar un plan resuelve los ritmos simbólicos;
2. la metodología contra el baseline real del corredor;
3. el **ritmo de referencia** — HEURÍSTICA PROVISIONAL: se corre
   `MetodologiaMaratoniaV1` sobre un corredor declarado (5 km en 30:00)
   y se usa el punto medio de cada zona. No son números inventados
   —comparten metodología con todo lo demás— pero tampoco son de este
   corredor. **Nunca se le muestran ni se usan como objetivo de
   ejecución: sirven solo para contabilizar.** El resultado se marca
   como estimado.

Devolver 0 cuando no se puede resolver el ritmo está descartado: es
exactamente el defecto que se está corrigiendo.

## Perfil del corredor y elegibilidad (DECISIÓN MARATONIA)

Los umbrales de abajo NO salen de un paper: son criterio de Maratonia,
declarado como tal. Su función no es aprobar o reprobar a nadie, sino
evitar vender un plan que no se sostiene.

**Por qué se abandonó la fórmula.** Hasta el build 61 el requisito era
`factor × distancia de la carrera`. Lineal en la distancia, cuando la
relación entre volumen de entrenamiento y distancia objetivo no lo es.
Producía dos absurdos simétricos: para *mejorar un 5K* pedía 15 km/sem
—la mitad de lo que el propio plan exige en su primera semana— y para
*maratón de rendimiento* pedía 4 × 42,195 = **168,8 km/semana**, para
un plan cuyo pico son 100. Y exigía una tirada larga previa de 33,8 km:
más de la que ese plan te va a hacer correr en 18 semanas.

**Tabla explícita, anclada al propio plan.** Cada requisito de volumen
queda por debajo del volumen de la primera semana del arquetipo que
habilita, y cada requisito de tirada larga en el orden de su primer
fondo. La idea es *"esto ya lo podés sostener el día uno"*, no *"ya sos
capaz de terminar"*.

| Objetivo | km/sem | Tirada larga | Días | Meses corriendo |
|---|---|---|---|---|
| Primeros 5K | — | — | 2 | — |
| Mejorar 5K | 18 | 6 | 3 | 3 |
| Primeros 10K | 10 | 4 | 2 | 1 |
| Mejorar 10K | 22 | 8 | 3 | 3 |
| Primera media | 28 | 10 | 4 | 4 |
| Mejorar media | 30 | 12 | 4 | 6 |
| Media rendimiento | 50 | 14 | 5 | 12 + marca |
| Primera maratón | 40 | 12 | 4 | 6 |
| Mejorar maratón | 48 | 16 | 4 | 9 |
| Maratón rendimiento | 65 | 18 | 5 | 12 + marca |

Un test de catálogo verifica esa coherencia contra el contenido real en
cada build, así que la tabla no puede volver a divergir del plan en
silencio.

Por encima de esos valores → **elegible**. Entre el 40 % y el 100 % →
**elegible conservador**. Por debajo del 40 % → **requiere fase base**,
con un objetivo puente sugerido (siempre hacia abajo).

Bloqueos que no se negocian: fecha imposible, días elegidos por debajo
del mínimo, y rendimiento sin marca de referencia o con lesión
declarada.

**Ausencia de datos ≠ sedentarismo.** Sin historial en Salud y sin
declaración, el veredicto es conservador — nunca un bloqueo.

## Frecuencia mínima (DECISIÓN MARATONIA)

**De media maratón para arriba, mínimo 4 días.** No es una preferencia:
con 3 días la tirada larga pasa del 50 % del volumen semanal y el plan
deja de ser un plan de media —es una tirada larga con dos
acompañantes—. Antes que fabricar una semana mal proporcionada, el
motor dice que esa frecuencia no alcanza para ese objetivo.

Los planes de rendimiento piden 5 días por la misma razón, y 5K/10K
siguen aceptando 2-3 porque a esos volúmenes la proporción no
representa un riesgo real.

## Arranque del plan (DECISIÓN MARATONIA)

La primera semana **no puede superar en más de un 20 % el volumen que
el corredor viene haciendo** (y en modo conservador, **no puede
superarlo en absoluto**). Si el template pide más, las primeras semanas
se atenúan con una rampa lineal —3 semanas en modo normal, 5 en
conservador— hasta volver al plan completo. Nunca escala hacia arriba y
nunca toca la carrera objetivo. Piso: 50 %.

El volumen de esa primera semana se mide con `CalculoVolumen`: medirlo
sumando solo distancias declaradas hacía que el techo de entrada se
calculara contra un número que ignoraba las sesiones de calidad.

**Qué significa "conservador".** Antes era una etiqueta que se mostraba
sin cambiar una sola línea del plan, mientras el onboarding prometía
que "el plan arranca más prudente". Ahora baja el techo de entrada de
1,2× a 1,0× y alarga la rampa de 3 a 5 semanas. La diferencia es real
y hay tests que la miden.

Deliberadamente NO se usa "la regla del 10 % semanal": no tiene
respaldo sólido y trata igual a quien corre 10 km/semana y a quien
corre 90. Esto es un techo de ENTRADA, aplicado una sola vez. La
EVIDENCIA disponible apunta además a que el total semanal es la unidad
menos informativa: lo que predice lesión es el salto de la sesión
individual respecto de la más larga de los 30 días previos.

## Composición de la semana al recortar días (DECISIÓN MARATONIA)

**Tope de proporción: la tirada larga no supera el 45 % del volumen de
una semana de construcción** (no aplica a taper ni a semana de carrera,
donde una larga proporcionalmente alta es lo correcto, ni a semanas de
menos de 25 km, donde la proporción no significa nada). El consenso de
entrenamiento ubica la larga en 30-35 %; 45 % es el techo que el
catálogo actual sostiene sin reescribir progresiones de fondo que sí
pasaron la auditoría de saltos de sesión. **Es una mejora por etapas,
no el estado final.**

**Redistribución al recortar.** Recortar de 5 a 3 días no achicaba la
tirada larga pero borraba dos rodajes enteros: la larga pasaba de
ocupar el 51 % de la semana a ocupar el 66 %, y el corredor con menos
disponibilidad —normalmente el menos entrenado— recibía la semana peor
proporcionada. Ahora el volumen fácil de las sesiones eliminadas se
reparte entre las fáciles que quedan, con tope de 1,6× por sesión para
que un "rodaje suave" no se convierta en una segunda larga. Lo que no
entra se pierde: es la señal correcta de que esa frecuencia no alcanza,
y el invariante de catálogo la detecta.

Nunca absorben volumen: la tirada larga, las sesiones de calidad ni la
carrera objetivo.

## Adaptación (§36-§41)

- **Reducir es flexible; aumentar prácticamente no existe.** El Coach
  no puede subir carga: el validador rechaza cualquier factor ≥ 1.
  Reducir escala TODOS los segmentos, incluidos los medidos en tiempo:
  antes un factor 0,8 sobre un `umbral 32′` recortaba medio kilómetro
  de calentamiento y dejaba el bloque duro entero.
- **Convertir a fácil conserva el VOLUMEN**, no la distancia declarada.
  Convertir un `umbral 32′` producía antes un rodaje de 2,5 km: un
  cuarto del trabajo original.
- **Una buena sesión aislada no habilita nada.** "Muy bien" no es un
  evento.
- **Una MALA sesión aislada tampoco cambia el plan** (DECISIÓN
  MARATONIA). Sentirse "muy exigido" después de un umbral de 32 minutos
  es la respuesta normal a un umbral de 32 minutos: si eso degradara la
  próxima calidad, un corredor honesto perdería todo el trabajo de
  calidad del plan, sesión tras sesión. Hace falta una **segunda señal
  coherente** en 14 días: otra sesión marcada exigida, o que esta misma
  haya quedado por debajo del 80 % de lo prescrito. El historial de
  sensaciones —que se guardaba y no se leía— es lo que aporta esa
  memoria. Mismo principio que el corrector de ritmo del reloj, que ya
  exige una racha antes de opinar.
  Excepciones que NO esperan confirmación: **molestia declarada**,
  pedido explícito del corredor y cambio de disponibilidad.
- **Perder una sesión suelta se registra, no reescribe la semana.**
  Solo un patrón (2 o más en 14 días) amerita adaptación.

## Taper como barrera determinística (estructura)

La regla del taper existía **solo en el prompt del backend**: es decir,
no existía. Un modelo de lenguaje no puede ser la garantía de
seguridad. Ahora el validador lee la fase REAL del plan
(`ReglasSemana.fase`) y en taper o semana de carrera:

- **mover** está prohibido — reorganizar la recuperación es justo lo
  que el taper protege;
- **convertir** está prohibido — la evidencia del taper es explícita en
  MANTENER la intensidad mientras baja el volumen (Bosquet 2007), y
  convertir una calidad en rodaje fácil hace lo contrario;
- **reducir y omitir** siguen permitidos: bajar carga nunca compromete
  un taper.

Si el plan no declara fase (planes adoptados antes de este cambio,
catálogo de principiante), la regla **no opina**: nunca infiere un
taper que nadie declaró.
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
