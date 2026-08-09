# Auditoría autónoma — 2026-08-09 (builds 30 → 31)

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

## Qué revisar manualmente (usuario)

1. Archivar el **build 31** y correr con auto-pausa activada: verificar
   "Pausa automática" al frenar y "Seguimos" al arrancar.
2. Probar una llamada entrante en plena carrera: la música debe volver.
3. Verificar que el aviso de zona suene solo en cambios sostenidos.
4. En el iPhone, mandar el plan y confirmar que "Plan encolado"
   desaparece solo.
