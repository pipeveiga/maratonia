# Auditoría autónoma — 2026-08-09 (builds 30 → 32, estado: RC1)

> **Resumen ejecutivo (para quien abra esto en seis meses)**
> Tres pasadas sobre el código completo: auditoría (14 fixes),
> deep-audit multi-agente (23 fixes) y revisión adversarial del propio
> trabajo (3 defectos propios corregidos) + consolidación RC (2 efectos
> de segundo orden). Total: **42 correcciones reales**, 0 features.
> Los temas: pérdida de datos (iCloud/Salud/plan), estados colgados
> (audio, workout fantasma, recovery), carreras de callbacks tardíos, y
> honestidad de la UI ante fallos. Las invariantes que el RC protege y
> el checklist de validación física están en `CHECKLIST_RC1.md`. La
> lógica pura tiene tests en `Tests/` (target por crear, 7 pasos en
> `Tests/README.md`). Nada de esto está probado en hardware todavía:
> **build 32 = candidato, no estable**.

Sesión de auditoría profunda del repositorio completo: los 19 archivos
Swift de los tres targets (iOS, watchOS, Shared) y el `project.pbxproj`
se leyeron entero antes de tocar nada.

## Estado inicial

- **Build**: no hay Xcode en este entorno; la verificación de compilación
  real la hace el usuario en la Mac (Archive). Acá se validó: balance de
  llaves/paréntesis/corchetes por archivo (con strings y comentarios
  removidos) y parseo semántico completo del `project.pbxproj` (sintaxis
  NeXTSTEP, claves duplicadas, referencias colgadas) — todo OK antes y
  después de los cambios.
- **Tests**: el proyecto no tiene target de tests (ver "Pendientes").
  La lógica deportiva se validó con una simulación espejo en Python
  (zonas, auto-pausa, splits, cronograma) — todos los casos pasan.
- **Arquitectura**: iOS (PlanStore + pantallas por pestaña, CarreraCelu
  como motor de carrera en el teléfono), watchOS (Reproductor → Avisador
  → Entrenamiento → EntrenadorRitmo, singletons con cascada de
  pausa/reanudación), Shared (Plan + diseño). Unidades canónicas
  consistentes: metros (Double), segundos (TimeInterval / Int seg/km).
  Sin fechas persistidas ⇒ sin riesgo de timezone en datos propios;
  las fechas de carreras vienen de HealthKit (`Date` absoluta) y se
  muestran con `Calendar.current` — correcto.

## Problemas corregidos (por commit)

### A — Integridad de datos (P1)
1. **El plan vacío pisaba el respaldo de iCloud.** Tras reinstalar, la
   app arranca con `Plan.vacio`; el primer cambio disparaba `respaldar`
   con `savePolicy .allKeys`, destruyendo el respaldo bueno justo antes
   de poder restaurarlo. *Fix*: un plan sin contenido nunca se sube.
   (`Maraton/Cuenta.swift`)
2. **"¡Carrera guardada!" podía ser mentira.** `requestAuthorization`
   devuelve `ok == true` aunque el permiso de escritura esté negado
   (así funciona HealthKit); la sesión corría, el resumen decía
   "guardada" y `finishWorkout` fallaba en silencio. *Fix*: se chequea
   `sharingDenied` ANTES de correr (aviso con instrucciones exactas) y
   los errores de `endCollection`/`finishWorkout` se muestran. En el
   celu además se corrige `guardadaEnSalud` si el cierre falla.
   (`Entrenamiento.swift`, `CarreraTelefono.swift`)

### B — Lógica deportiva (P1/P2)
3. **Anti-flapping de zonas roto.** El contador de "20 s sostenidos en
   la zona nueva" sumaba segundos repartidos entre zonas distintas: un
   pulso oscilando Z3/Z4 podía anunciar una zona de 1 segundo. *Fix*:
   zona candidata única; cambiar de candidata reinicia el contador.
   Verificado por simulación: la oscilación permanente ya no anuncia.
4. **Auto-pausa podía quedar clavada para siempre.** Se disparaba con
   la distancia congelada sin exigir señal GPS; sin puntos (sin señal,
   o sin permiso en el celu) la reanudación automática era imposible
   → loop de pausa infinita. *Fix*: exige `puntosRuta > 0`.
5. **Auto-reanudación exigía precisión GPS ≤ 20 m** — en zona urbana
   con mala señal no reanudaba nunca. *Fix*: acepta hasta 50 m con
   umbral dinámico `max(15 m, precisión)`.

### C — Robustez (P1/P2)
6. **Editar el plan en el iPhone en plena carrera mataba la música del
   reloj.** Al llegar el plan nuevo, `limpiarPistasHuerfanas` borraba
   los MP3 que estaban sonando. *Fix*: con sesión activa no se borra
   nada; la limpieza queda para la próxima entrega en reposo.
7. **"Plan encolado" quedaba prendido para siempre** en la pestaña
   Reloj. *Fix*: refleja `outstandingUserInfoTransfers` real.
8. **Sin manejo de interrupciones de audio** (llamada, Siri): al
   terminar la interrupción la música no volvía nunca, en reloj y celu.
   *Fix*: observer de `interruptionNotification` con `shouldResume`,
   respetando pausa/silencio manual/voz activa.

### D — Casos borde (P2)
9. **Celu: la música arrancaba encima de la voz** si una pista terminaba
   mientras el asistente hablaba. *Fix*: respeta `voz.isSpeaking`
   (+ `estado = .corriendo` se setea antes de arrancar la música para
   que el guard sea correcto).
10. **Estados residuales**: `enPausaAutomatica`/`ubicacionPausa` no se
    limpiaban al terminar una carrera en auto-pausa (reloj y celu).
11. **Mensaje engañoso en Mis carreras**: con lectura de Salud negada,
    HealthKit devuelve vacío sin error (por diseño de privacidad); el
    mensaje prometía que las carreras iban a aparecer. Ahora sugiere
    revisar los permisos.

### E — Recuperación tras crash (P2, era "pendiente")
12. **Carrera perdida si la app del reloj moría en plena corrida**
    (crash, batería, cierre forzado). Al relanzar, ahora se llama
    `recoverActiveWorkoutSession`: la sesión huérfana se cierra y lo
    registrado se guarda en Salud, con los números repuestos desde el
    builder para que el resumen no muestre ceros, y un aviso en el
    lobby. (`Entrenamiento.swift`, `MaratonWatchApp.swift`)
13. **Conteo de avisos del lobby del reloj** usaba horizonte 6 h cuando
    el Avisador programa 12 h: el número mostrado podía no coincidir
    con lo que iba a sonar. Unificado a 12 h.
14. **Falso positivo del validador sintáctico** (comilla impar en un
    comentario se comía llaves del conteo): reemplazado por un
    tokenizador real, ahora versionado en `scripts/chequear_swift.py`.

## Verificaciones ejecutadas

- Simulación Python de: zonas Karvonen (incluye el caso real 150–160
  ppm → Z2/Z3), anti-flapping (oscilación permanente, subida sostenida,
  pico fugaz), ventana de auto-pausa (corriendo 5:00/km, parado,
  caminando, sin GPS), guardias de splits (km salteado, parcial
  imposible), expansión del cronograma (fijos+repetidos, basura
  filtrada). **Todo pasa.**
- Balance sintáctico de todos los `.swift` tocados, en cada commit.
- Parseo semántico completo del `project.pbxproj` (77 objetos, sin
  claves duplicadas ni referencias colgadas).
- Grep de secretos (api keys, tokens, passwords): limpio.
- `git diff` revisado commit a commit; grupos lógicos separados.

## Pendientes (no tocados, con motivo)

| Problema | Severidad | Motivo / recomendación |
|---|---|---|
| Sin target de tests (XCTest) | P2 | Crear un target requiere editar el pbxproj a mano con riesgo alto y no se puede ejecutar en este entorno. Recomendado: crearlo desde Xcode en la Mac (File → New → Target → Unit Testing Bundle) y portar los casos de la simulación Python de este documento. |
| Celu sin música y sin permiso de GPS: en segundo plano los avisos por tiempo pueden no sonar (no hay audio ni location manteniendo viva la app) | P2 | Limitación de iOS. Mitigación futura: notificaciones locales como en el reloj. |
| Recuperación tras crash en el CELU (el reloj ya la tiene) | P3 | iOS no tiene `recoverActiveWorkoutSession`; con la app muerta, el HKWorkoutBuilder del teléfono se pierde. Mitigable persistiendo estado propio; beneficio menor (el modo principal es el reloj). |
| Ventanas de gracia de tramos (45 s) corren en reloj de pared durante pausas | P3 | Tras una pausa larga puede corregir apenas reanudás (mitigado: el ritmo tarda ~20 s en volver a existir). Cambiarlo a tiempo activo requiere plumbing; beneficio menor. |
| `ShareLink` renderiza la imagen dos veces por evaluación | P3 | Costo bajo (tarjeta chica). Cachear con @State si alguna vez molesta. |
| CloudKit `savePolicy .allKeys` pisa sin comparar | P3 | Un solo usuario + debounce 3 s lo hace aceptable. Si algún día hay multi-dispositivo simultáneo, pasar a changedTag. |

## Ideas futuras (no bugs)

Plan semanal (calendario), Live Activity/Dynamic Island y complicación
del reloj (requieren targets nuevos — hacerlo con Xcode), FC desde
AirPods Pro 3 en modo celu, análisis post-carrera, inglés, modo día de
carrera, recuperación de sesión tras crash.

## Deep Audit — Pass 2

Segunda pasada enfocada en estado, secuencia temporal, concurrencia,
audio y persistencia. Complementada con una revisión multi-agente en
paralelo (6 lentes) con verificación adversarial de cada hallazgo.

### Corregido en Pass 2

15. **`CarreraResumen.id` inestable (P2)**: era `UUID()` nuevo en cada
    consulta a Salud; con el pull-to-refresh agregado ayer, refrescar
    con el detalle abierto rompía la pantalla ("No encontré esta
    carrera"). Ahora `id = workout.uuid` (estable entre recargas).
16. **Fórmula de zonas duplicada (P2)**: existía en dos lugares (aviso
    hablado y celda de métricas) — riesgo real de divergencia. Extraída
    a `zonaCardiaca()` en `Shared/Plan.swift` (archivo ya compartido
    por ambos targets: cero riesgo de pbxproj) y ahora testeable.
17. **Persistencia del plan sin voz (P1)**: `guardar()` con `try?` mudo
    → disco lleno = perder el plan al cerrar la app sin aviso;
    `plan.json` corrupto → arranque vacío en silencio, pisando la
    evidencia. Ahora: error visible en la pestaña Plan; el archivo
    corrupto se preserva como `plan-corrupto.json` y el aviso apunta a
    «Restaurar desde iCloud».
18. **Recovery post-crash colgable (P1, bug propio de Pass 1)**: si el
    crash ocurría justo después de que la sesión pasara a `.ended`, el
    delegate `didChangeTo` no re-dispara; `finalizar()` esperaba un
    evento que no llega, `activo` quedaba `true` y el guard
    `sesion == nil` bloqueaba TODOS los Play futuros. El cierre se
    extrajo a `cerrarYGuardar()` y la recuperación lo invoca directo
    cuando la sesión recuperada ya está terminada. En el peor caso
    (colección ya cerrada) muestra el error y LIMPIA el estado.
19. Comentario engañoso de `kmTexto` (decía coma decimal; produce punto).

### Corregido en Pass 2 — tanda de la revisión multi-agente

Los 6 buscadores paralelos entregaron 47 hallazgos crudos; la fase de
verificación adversarial no pudo correr (límite de sesión), así que
cada hallazgo aplicado fue confirmado a mano contra el código por el
agente principal antes de tocar nada. Los aplicados (build 32):

20. **Workout fantasma (P1, reloj)**: si el audio fallaba al arrancar,
    el entrenamiento arrancaba igual y quedaba grabando sin UI para
    pararlo. El entrenamiento ahora se engancha a un callback que solo
    dispara con el audio arrancado de verdad.
21. **Builder pisado (P1, celu)**: el completion tardío de
    `finishWorkout` de una carrera anulaba el builder de la siguiente
    (no se guardaba) y podía atarle la ruta equivocada. Identidad
    comparada + capturas locales de routeBuilder/puntos.
22. **Reactivación long-form síncrona (P1, reloj)**: tras una llamada,
    `setActive(true)` síncrono no es válido para sesiones long-form en
    watchOS — la música no volvía. Ahora usa `activate(options:)`
    asíncrona con re-chequeo de vigencia del estado.
23. **Spotify duckeado para siempre (P1, reloj)**: Terminar durante un
    aviso en modo música externa dejaba la sesión `.duckOthers` activa.
    `Avisador.detener()` la suelta él mismo.
24. **`preparando` clavado (P2, reloj)** si `setCategory` tiraba, y
    completion de activación zombie (selector BT abierto minutos) que
    podía resetear una sesión nueva: guard de vigencia + reset en modo
    externa y en detener().
25. **`estaHablando` colgado por interrupción (P2, ambos)**: una
    llamada que PAUSA la frase (ni didFinish ni didCancel) dejaba voz y
    música muertas el resto de la corrida. Observer de `.began` corta
    la frase; el didCancel resultante limpia todo. En el celu faltaba
    además el delegate `didCancel` entero.
26. **Delegates fuera de main (P2, ambos)**: HealthKit (didChangeTo /
    didCollectDataOf) y los delegates de audio/voz del celu leían y
    mutaban estado compartido en colas internas. Todos con hop a main.
27. **Música encima de la voz (P2, ambos)**: `reanudar()` (y el toggle
    de música del celu) arrancaban el player con la voz sonando.
28. **Avisos con el cronómetro congelado (P2, reloj)**: pausar en medio
    de dos avisos encadenados seguía hablando el resto de la cola; la
    pausa ahora la vacía. Y el aviso de prueba del lobby se corta al
    arrancar la sesión (desincronizaba `estaHablando`).
29. **Respaldo iCloud descartado en silencio (P2)**: el estado de la
    cuenta se verificaba UNA vez por proceso; si iCloud llegaba tarde,
    ningún respaldo subía nunca y sin aviso. Se re-verifica en cada
    intento y el descarte deja mensaje visible.
30. **"No hay respaldo" falso (P3)**: un respaldo existente pero
    ilegible se reportaba como inexistente.
31. **Distancia negada muda (P2, celu)**: se puede permitir
    "Entrenamientos" y negar "Distancia" — el workout se guardaba con
    0 km sin aviso. El error de `builder.add` ahora se muestra.
32. **Eventos de pausa pre-builder (P3, celu)**: pausas hechas antes de
    responder el diálogo de permisos se perdían (Salud contaba la pausa
    como tiempo activo). Se acumulan y vuelcan al crear el builder.
33. **Ráfaga de avisos tras suspensión (P3, celu)**: al volver de un
    background largo, todos los avisos vencidos sonaban en cadena; con
    más de dos, ahora suena solo el más reciente.
34. **Spotify muerto con plan sin pistas (P3, celu)**: la sesión
    `.playback` exclusiva cortaba la música de otra app aunque no
    hubiera nada propio que reproducir. Sin pistas, la sesión se activa
    por frase con ducking y se suelta al terminar.
35. **Auriculares BT caídos (P3, ambos)**: el reloj pausa todo
    coherentemente; el celu silencia la música y corta la voz (antes
    seguía a todo volumen por el parlante en la calle).
36. **Mis carreras (P3)**: consultas concurrentes coalescadas, fusión
    que preserva rutas/FC ya cargadas (antes cada refresh reseteaba los
    detalles y relanzaba todas las queries), y errores del route query
    ya no dejan el spinner "Cargando recorrido…" eterno.
37. **Importar MP3 fallido ahora avisa (P3)** (típico: archivo en
    iCloud Drive sin descargar) y la lectura fallida de plan.json se
    distingue de "no existe" (preserva evidencia + mensaje).

### Hallazgos evaluados y NO aplicados (con motivo)

- *Race botón Reanudar vs auto-reanudación GPS* (ventana sub-segundo,
  autocorregible en pantalla): mitigación posible con debounce; costo
  UX de ignorar taps > beneficio. Documentado.
- *Debounce de zona por ticks vs timestamps*: los ticks solo corren con
  la sesión activa, así que descuentan pausas — comportamiento deseado;
  timestamps contarían el tiempo pausado. Se mantiene por diseño.
- *Reintentos automáticos de transferencias WCSession*: el reenvío
  manual ("Enviar al reloj") ya re-encola solo lo faltante; un retry
  automático sin límites puede comerse la batería. Pendiente diseño.
- *Persistir flag de respaldo pendiente (debounce de 3 s vs force-quit)*:
  requiere reconciliación al arranque; anotado como mejora 1.1.

### Escenarios trazados a mano (sin hallazgos nuevos)

- **Normal** (play → pausa → reanudar → terminar): cascada de pausa
  única vía `Reproductor` con guards (`estado == .reproduciendo` /
  `!pausado`) — dobles pausas imposibles; el tiempo es SIEMPRE
  timestamps (`acumuladoPrevio + fechaReanudacion`), ningún contador
  de ticks; los 4 timers del proyecto (UI del reloj, muestras, tick
  del celu, progreso de envíos) se invalidan antes de recrearse y al
  terminar.
- **Auto-pausa** (correr → parar → caminar → correr): trigger con
  triple guard (GPS con puntos + 10 s ventana + >30 s de sesión);
  resume por un único camino (el branch de GPS exige
  `enPausaAutomatica && pausado` y `Reproductor.reanudar` tiene guard
  de estado) — duplicados imposibles; dos updates de ubicación
  seguidos: el segundo encuentra `enPausaAutomatica == false`.
- **Interrupción de audio**: reloj y celu observan `.ended` +
  `shouldResume` con guards de pausa/silencio/voz; en música externa
  el reloj NO toca nada (Spotify se recupera solo) — correcto.
- **Crash/kill**: reloj recupera y guarda (fix 12+18). Celu: iOS no
  tiene API de recuperación de `HKWorkoutBuilder` — pérdida documentada
  como pendiente P3.
- **Hilos**: WCSession (hilo secundario) → todas las mutaciones
  @Published van con `DispatchQueue.main.async`; HealthKit delegates →
  ídem; CLLocationManager creado en main → callbacks en main;
  AVSpeech/AVAudioPlayer delegates → despachados a main donde mutan
  estado. Sin escrituras de @Published fuera de main detectadas.

### Modelo de entrenamiento — capacidades y límites (documentado, no código)

- **Representable hoy**: secuencias arbitrarias de segmentos por
  DISTANCIA con rango de ritmo opcional (incluye series expandidas,
  p. ej. 5×1K se modela como 11 tramos — funciona, aunque editar series
  largas es tedioso).
- **NO representable**: segmentos por TIEMPO ("2 min de recuperación",
  "15 min easy") — solo aproximables por distancia; segmentos por zona
  de FC; estructura de repetición de primera clase (N × bloque).
  Diseño de extensión compatible ya pensado: `Tramo.duracionSegundos:
  Int?` como alternativa a `kilometros` + avance por tiempo activo en
  los dos entrenadores. NO implementado a ciegas: cambia el motor de
  avance y necesita prueba en carrera real.
- **Plan semanal**: inexistente por diseño actual (Plan = una sesión);
  es la feature grande ya priorizada en el backlog. Regla para cuando
  se construya: días como componentes de fecha LOCALES (nunca
  `YYYY-MM-DD` interpretado UTC), historial de carreras inmutable (hoy
  se cumple: vive en HealthKit y el plan no lo toca).

### Bloqueado por entorno (documentado, no detiene nada)

- Ejecutar XCTest (target por crear — `Tests/README.md`, 7 pasos).
- Probar en hardware: llamada real, desconexión de BT (route change:
  watchOS pausa solo con longForm; no se agregó auto-play a ciegas
  para no sonar por parlante en la calle), crash recovery físico,
  auto-pausa en semáforo real.

## Adversarial Review — Pass 3

Revisión adversarial del diff completo de la sesión (18 archivos,
~1.180 líneas) como reviewer externo hostil: ataques de estado, de
secuencia, de concurrencia, de tiempo y de cálculo contra MI propio
código. Metodología: cada cambio de la sesión re-derivado desde cero y
atacado con secuencias de eventos (doble pausa, callbacks tardíos,
interrupciones encadenadas, kill a mitad de guardado).

### Defectos propios encontrados y corregidos

1. **MAJOR — regresión del colapso de avisos (celu, introducida en
   Pass 2)**: el "anti-ráfaga tras suspensión" descartaba avisos
   LEGÍTIMOS cuando el corredor configuró 3+ avisos en el mismo minuto
   (fijo + repetidos alineados): sonaba solo el último. *Final
   approach*: se descartan únicamente los vencidos de minutos YA
   pasados; los del minuto en curso suenan todos. Verificado por
   simulación con ambos escenarios.
2. **MINOR — mensaje falso de iCloud (introducido en Pass 2)**:
   `respaldar` acusaba "no hay sesión de iCloud activa" también durante
   `.verificando` (arranque en frío + edición rápida). Ahora el estado
   en verificación se salta en silencio (el próximo cambio reintenta,
   y `verificar()` ya corre en cada intento).
3. **NIT — código muerto**: `PlanStore.pistaExiste` sin ningún
   llamador (previo a la sesión). Eliminado.

### Ataques que NO encontraron defecto (los importantes)

- *Terminar en modo solo-avisos con la voz sonando*: el `didCancel`
  diferido llega con `modoSoloAvisos` ya reseteado, pero
  `detenerComponentes` ya soltó la sesión de audio él mismo — sin fuga.
- *Play nuevo antes del completion de guardado del anterior (celu)*:
  la comparación de identidad del builder y las capturas locales de
  ruta/puntos aíslan cada carrera; secuencia trazada dos veces.
- *`.began` de interrupción con música propia*: el `play()` del
  didCancel durante la interrupción es no-op del sistema; la vuelta
  real la hace el `.ended` con `shouldResume`. Benigno.
- *Doble `.ended` de HKWorkoutSession / cerrarYGuardar re-entrante*:
  el segundo endCollection erroría y limpia igual — sin doble guardado.
- *Cascada de auto-pausa vs comandos del Now Playing*: todos los
  caminos pasan por los guards de estado del Reproductor; no existe
  secuencia que produzca doble pausa o doble "Seguimos".
- *Reserva cardíaca negativa (FC < reposo)*: cae en Z1 por diseño del
  switch; sin NaN ni crash (el assert adversarial que "falló" era una
  expectativa mía equivocada, no el código).
- *Tests*: re-leídos contra la implementación — fallarían ante el bug
  que protegen (límites de zona en 0.6 exacto, orden fijo-primero,
  comillas curvas) y no están acoplados a detalles internos.

### Riesgos aceptados y documentados (no solucionables acá)

- `consultaEnCurso` de Mis carreras quedaría trabado si HealthKit no
  llamara nunca el callback (no observado en la práctica; el reinicio
  de la app lo limpia).
- `mensajeProblema` de una importación fallida persiste hasta el
  próximo problema o reinicio (banner informativo, no bloqueante).
- Todo el trabajo de audio/interrupciones/recovery de esta sesión
  necesita el Archive + prueba física para considerarse validado.

## Consolidación RC1 — interacciones entre fixes

Revisión de cómo interactúan los fixes de la sesión entre sí (no
individualmente). Dos efectos de segundo orden encontrados y corregidos:

38. **El guard de identidad silenciaba errores de guardado**: si la
    corrida siguiente ya había arrancado, el error de `finishWorkout`
    de la anterior no se reportaba (guard antes del reporte). El error
    ahora se muestra SIEMPRE; solo el estado queda protegido por el
    guard. Una corrida perdida no puede ser invisible.
39. **Contaminación entre corridas (celu)**: `iniciar()` no reseteaba
    `builder`/`routeBuilder`; con la cadena de guardado anterior
    colgada, una pausa de la corrida nueva le metía eventos al builder
    viejo. `iniciar()` ahora los resetea (el completion viejo trabaja
    sobre sus capturas locales).

Además: la regla de drenaje de avisos se extrajo a función pura
(`CarreraCelu.avisosParaAnunciar`) con 5 regression tests — protege el
bug MAJOR de la revisión adversarial.

Interacciones auditadas SIN defecto: recovery × Play nuevo, route
change × auto-pausa, interrupción × auto-pausa × voz, cascada de pausa
× Now Playing, `detener` × didCancel diferido en modo solo-avisos,
`didFailWithError` × música en curso (sigue sola: filosofía
música-primero). Riesgo residual documentado: auto-pausa disparada
DURANTE una llamada podría dejar `estaHablando` colgado si el
sintetizador nunca responde (probabilidad baja; requiere prueba física).

## Qué revisar manualmente (usuario)

1. Archivar el **build 31** y correr con auto-pausa activada: verificar
   "Pausa automática" al frenar y "Seguimos" al arrancar.
2. Probar una llamada entrante en plena carrera: la música debe volver.
3. Verificar que el aviso de zona suene solo en cambios sostenidos.
4. En el iPhone, mandar el plan y confirmar que "Plan encolado"
   desaparece solo.
