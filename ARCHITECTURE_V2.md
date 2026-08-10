# ARCHITECTURE_V2 — Maratonia como app de entrenamiento completa

Fecha: 2026-08-09 · Base: build 34 (RC1 + tareas de auto-pausa,
cumplimiento y Carrera Libre) · Estado: **DISEÑO — nada de esto está
implementado.**

---

## 1. Estado actual relevante

Análisis sobre el código real (los 20 archivos Swift fueron leídos y
auditados en las tres pasadas de NIGHT_AUDIT.md).

### Qué podemos REUTILIZAR tal cual (funciona y está endurecido)

| Pieza | Dónde | Nota |
|---|---|---|
| Motor de ejecución watch | `Reproductor`/`Avisador`/`Entrenamiento`/`EntrenadorRitmo` | Lifecycle completo: workout HK, GPS, ruta, pausa total/auto/solo-música, interrupciones, route change, recovery post-crash, ducking. Es el activo más valioso del repo. |
| Motor de ejecución iPhone | `CarreraCelu` | Gemelo funcional (sin FC). Ya ejecuta tramos, splits, avisos por km. |
| Auto-pausa | `AutoPausa` (Shared) | Lógica pura con doble confirmación + histéresis, testeada. |
| Cumplimiento v1 | `EstadoPlanWatch` + huella | Puente perfecto hacia identidad real (ver §8). |
| Historial | `CarrerasStore`/`CarrerasView` | Lee HealthKit por bundle, mapas, FC, fusión estable por `workout.uuid`. |
| Compartir | `TarjetaCompartir` + `TrazadoRuta` | Validado en campo por el usuario. Solo falta el logo (§15). |
| Sync de archivos | `Conectividad`/`ConectividadWatch` | transferFile con inventario y limpieza segura. |
| Respaldo | `CuentaStore` (CloudKit) | Privado, con guardas anti-pisado. |
| Infra de calidad | `Tests/`, `scripts/chequear_swift.py`, NIGHT_AUDIT | Se extiende, no se reemplaza. |

### Qué necesita EVOLUCIONAR

- **`Plan`**: hoy es a la vez (a) el workout (tramos), (b) la config de
  audio (pistas, avisos por tiempo), (c) la biblioteca de música. Debe
  partirse (§3, §11) — es LA deuda estructural.
- **Identidad**: `huellaEntrenamiento` (hash de contenido) fue un
  puente deliberado; la visión nueva exige IDs estables (§4).
- **Slot único en el watch**: el reloj conoce "el plan", no "el
  entrenamiento de hoy". Pasa a recibir una proyección (§10, §15.7).
- **`CorrerTab` iPhone**: ya es Carrera Libre; le falta "entrenamiento
  del día" (trivial una vez que exista calendario).

### Deuda del prototipo original

- Pistas como `[String]` de nombres de archivo (suficiente, documentado).
- `PlanStore` guarda un único plan sin fechas ni calendario.
- La pestaña "Reloj" como concepto de primer nivel (es plomería, no
  producto).
- Nada de esto bloquea la v2: se migra, no se reescribe (§8).

## 2. Problemas estructurales para la nueva visión

1. **Contenido = identidad**: dos planes con los mismos tramos son "el
   mismo" workout. Imposible tener calendario, reprogramación o dos
   martes iguales.
2. **Sin dimensión temporal**: no existe fecha, semana ni "hoy".
3. **Workout y audio acoplados** en `Plan`: no se puede decir "el
   entrenamiento del martes" sin arrastrar la playlist.
4. **Watch con estado propio de cumplimiento** (`EstadoPlanWatch`):
   correcto para v1 de un solo workout; con calendario, el iPhone debe
   ser el dueño y el watch un espejo.
5. **Sin baseline de rendimiento**: los ritmos son números absolutos
   escritos a mano o pegados de ChatGPT.

## 3. Modelo de dominio propuesto

Nombres en español, siguiendo el estilo del código. Separación central:
**QUÉ HAY QUE HACER** (plan → programado → definición) vs **QUÉ SE
HIZO** (sesión).

```
PlanBase (template versionado, en el bundle)
  └─ genera →
PlanUsuario (instancia snapshot, del usuario)
  └─ SemanaPlan [1..n]
       └─ EntrenamientoProgramado [0..n por semana]   ← "qué hay que hacer"
            └─ referencia → DefinicionEntrenamiento    ← "en qué consiste"

SesionRealizada                                        ← "qué se hizo"
  └─ vinculoProgramadoID: UUID?   (nil = Carrera Libre)
```

- **`DefinicionEntrenamiento`**: id, tipo (`facil`, `recuperacion`,
  `largo`, `tempo`, `umbral`, `series`, `ritmoCarrera`, `testEvaluacion`,
  `libre`), nombre, descripción, segmentos. **Segmento** = evolución de
  `Tramo`: `{ distanciaKm: Double? | duracionSegundos: Int?, ritmo:
  RitmoObjetivo }` donde `RitmoObjetivo` es `.libre`, `.absoluto(min,
  max)` (compat con hoy) o `.simbolico(TipoRitmo)` (resuelto contra el
  baseline, §6). Esto agrega los segmentos por TIEMPO que hoy faltan
  (recuperaciones de 2 min) — el motor `EntrenadorRitmo` avanza hoy
  solo por distancia; el avance por tiempo es la única extensión de
  motor requerida por la v2.
- **`EntrenamientoProgramado`**: id, definicionID, `dia: DiaLocal`,
  estado (§5), fechaOriginal (si fue reprogramado), sesionVinculadaID?.
- **`SesionRealizada`**: NO es una entidad nueva de almacenamiento
  pesado — es el `HKWorkout` (métricas, ruta, FC ya viven en Salud) más
  un registro liviano nuestro: `{ sesionID = HKWorkout.uuid,
  vinculoProgramadoID?, tipo }`. El vínculo se escribe además como
  **metadata del HKWorkout** (`HKMetadata` con clave propia
  `com.pipeveiga.maraton.programadoID`), así la evidencia viaja con
  Salud y sobrevive reinstalaciones.

## 4. Identidades y relaciones

| ID | Identifica | Formato | Estable ante |
|---|---|---|---|
| `planBaseID@version` | El template del catálogo | `"primeros-5k@2"` | Ediciones del template (nueva versión = nuevo string) |
| `planUsuarioID` | La instancia adoptada por el usuario | UUID | Todo: snapshot inmutable del template al adoptar |
| `programadoID` | Un entrenamiento en una fecha | UUID | Reprogramación (cambia `dia`, no el ID) |
| `definicionID` | El contenido de un entrenamiento | UUID | — (el contenido es inmutable dentro del PlanUsuario) |
| `sesionID` | Una salida realizada | `HKWorkout.uuid` | Ya lo usamos en `CarreraResumen.id` — cero invención |

La `huellaEntrenamiento` actual queda SOLO como puente de migración (§8)
y muere después.

## 5. Estados del entrenamiento programado

Mínimo necesario (menos es más):

- **`programado`** — pendiente.
- **`cumplido`** — existe sesión vinculada que lo satisface. Es
  *derivable* (¿tiene sesionVinculadaID?) pero se cachea por rendimiento;
  la evidencia es el vínculo, no el flag.
- **`omitido`** — el usuario lo marcó como "no lo voy a hacer" o el día
  pasó y arrancó la semana siguiente (política exacta: decisión D3).
- La **reprogramación NO es un estado**: es mutar `dia` conservando
  `fechaOriginal`. Un entrenamiento movido sigue `programado`.
- **`parcial` NO existe en v2.0**: la política actual (conservadora,
  ya en producción) es "todos los tramos = cumplido; menos = sigue
  programado". Una sesión incompleta puede quedar VINCULADA como
  evidencia sin marcar cumplido. Formalizar "parcial" es la decisión
  de producto D1.
- Carrera Libre: `vinculoProgramadoID = nil`. Jamás consume un
  programado automáticamente (invariante ya protegida en v1).

## 6. Ritmos: infraestructura vs metodología

- **`ReferenciaRendimiento`** (baseline): lista histórica de registros
  objetivos `{ fecha, fuente: test5K | carreraReal | marcaManual |
  estimacionInicial, distanciaMetros, segundos }`. NUNCA "nivel =
  intermedio": siempre datos crudos recalculables. Se guarda la lista
  completa (la evolución del baseline ES la feature de progreso §14).
- **Infraestructura** (software, nuestra): función pura
  `ritmo(tipo:baseline:metodologia:) -> RangoRitmo` + tests; los
  segmentos simbólicos se resuelven al MOSTRAR/ejecutar, nunca se
  persisten resueltos (si el baseline mejora, el plan futuro mejora).
- **Metodología** (deporte, NO nuestra): una tabla de datos versionada
  en el bundle (`MetodologiaRitmos-v1.json`): para cada tipo de ritmo,
  el multiplicador/offset sobre el ritmo de referencia derivado del
  baseline. Candidata seria: tablas VDOT (Jack Daniels, *Daniels'
  Running Formula*) — estándar de la industria, publicadas, citables.
  **Decisión D4 del usuario**: adoptar VDOT vs tabla propia con
  asesoría. Ninguna fórmula inventada entra al código: el JSON lleva
  `fuente` y `version` adentro.

## 7. Source of truth (por dato)

| Dato | Autoritativo | Réplicas |
|---|---|---|
| PlanUsuario, calendario, estados | **iPhone** (JSON en Documents, como hoy `plan.json`) | iCloud (respaldo CKRecord), Watch (proyección) |
| Sesiones y métricas realizadas | **HealthKit** (ya lo es hoy) | UI de ambos |
| Vínculo sesión↔programado | **Metadata del HKWorkout** + espejo en iPhone | — |
| Cumplimiento | **Derivado** del vínculo; cache en iPhone | Watch (proyección) |
| Preferencias de ejecución (GPS, auto-pausa, zonas, música externa) | **Cada dispositivo** (UserDefaults, como hoy) | No se sincronizan (correcto: son del aparato) |
| Archivos de música | **iPhone** | Watch (réplica con inventario, como hoy) |
| Baseline / referencias | **iPhone** | iCloud |

Regla de oro: **un solo escritor por dato**. El watch nunca edita el
calendario; el iPhone nunca inventa sesiones.

## 8. Migración desde el modelo actual (sin perder nada)

1. `Plan` actual → al primer arranque de la versión nueva, el iPhone lo
   parte en: `ConfiguracionAudio` (pistas + avisos fijos/repetidos) y,
   si tiene tramos, un `PlanUsuario` "Plan personalizado" de 1 semana
   con 1 `EntrenamientoProgramado` sin fecha fija (o con fecha = hoy;
   decisión menor).
2. `huellaCumplida` del watch → si coincide con la huella del plan
   migrado, ese programado nace `cumplido`. Después la huella se
   ignora para siempre.
3. Carreras históricas: ya viven en HealthKit con `workout.uuid` — no
   migran, se releen. Sin vínculo (fueron pre-v2): aparecen como
   sesiones libres. Correcto y honesto.
4. Respaldo iCloud: el record `planActual` legacy se sigue LEYENDO
   (restauración) durante una versión puente; se escribe el formato
   nuevo bajo otro recordType (`PlanUsuario`), nunca pisando el viejo.
5. Watch viejo + iPhone nuevo: el iPhone sigue emitiendo el `Plan`
   legacy por WatchConnectivity durante la versión puente, además de
   la proyección nueva. El decode del watch ya tolera campos extra
   (campos opcionales, verificado por test).
6. Preferencias (UserDefaults): claves intactas, cero migración.

## 9. Arquitectura iPhone (el cerebro)

Tabs propuestos (evolución de los actuales, no big-bang):

| Nuevo | Origen | Contenido |
|---|---|---|
| **INICIO** | nuevo | "¿Qué tengo que hacer hoy?" (§ home abajo), próximos días, racha |
| **PLAN** | `PlanTab` | Calendario del PlanUsuario + catálogo (§12) + editor manual actual como "plan personalizado" |
| **CORRER** | `CorrerTab` | Entrenamiento de hoy (si hay) + Carrera Libre; motor `CarreraCelu` |
| **PROGRESO** | `CarrerasTab` | Historial actual + resumen semanal (ya existe) + evolución (§14) |
| **PERFIL** | `PerfilTab` | Cuenta, baseline, **audio/música** (§11), reloj (estado + envío, hoy pestaña propia), tutorial |

La pestaña "Reloj" desaparece como tab y se vuelve sección de PERFIL
(o de PLAN — decisión D5). Home de INICIO:

```
ENTRENAMIENTO DE HOY
Rodaje fácil · 8 km · 5:45–6:10 /km
[ EMPEZAR ]        ← lanza CORRER con ese programadoID
── próximo: jueves — Series 5×1K
── semana 3 de 8 · 2/3 cumplidos
```

Ejecutar desde iPhone ya funciona (CarreraCelu tiene pausa, auto-pausa,
tramos, guardado); "EMPEZAR hoy" = pasarle la definición del día y el
`programadoID` para el vínculo al guardar. **No hay motor nuevo.**

## 10. Arquitectura Watch (el compañero)

- Home: exactamente la de build 34 (pendiente → Entrenamiento +
  Carrera libre; si no → Carrera libre) — la v2 solo cambia QUÉ recibe:
  en vez de "el plan", una **ProyeccionDia** `{ programadoID,
  definicion, configAudio }` vía applicationContext (idempotente,
  last-writer-wins, correcto para una proyección).
- Al terminar: el watch manda `{ programadoID, hkUUID }` por
  transferUserInfo (cola persistente, como el plan hoy) y el iPhone
  registra el vínculo. Fallback offline: el watch escribe además la
  metadata en el HKWorkout — el iPhone la lee de Salud aunque el
  mensaje se pierda (doble vía, una sola verdad final: la metadata).
- El watch NO administra planes, catálogo ni calendario. Ajustes de
  ejecución locales se quedan (GPS, auto-pausa, zonas, música externa).

## 11. Rol futuro del audio

Estado deseado: audio = configuración de la sesión, no identidad de la
app. Modos: sin música propia / música local / música externa / solo
avisos — **los cuatro ya funcionan en los motores** (verificado en las
tareas de Carrera Libre y modoSoloAvisos). El acople que queda es de
MODELO y UI, no de motor:

- Acoplado hoy: `Plan` lleva pistas+avisos; la pestaña Plan del iPhone
  muestra Música como parte del entrenamiento; `Reproductor.iniciar`
  recibe el Plan entero.
- Desacople incremental (sin refactor grande):
  1. (Fase A) `ConfiguracionAudio` como struct separada; `Plan` legacy
     se convierte en un adaptador computado `(definicion, audio)`.
  2. (Fase B+) los motores reciben `(DefinicionEntrenamiento,
     ConfiguracionAudio)`; firma nueva con adaptador del viejo — un
     cambio de firma, no de lógica.
  3. (UI) Música migra de PLAN a PERFIL→"Música y avisos"; los avisos
     por tiempo ("tomá agua cada 20") son audio; los avisos por KM y
     los tramos son entrenamiento. Línea divisoria explícita.

## 12. Catálogo de planes

- `PlanBase` en el bundle como JSON versionado:
  `Recursos/Planes/primeros-5k@1.json` con metadata (nombre, distancia
  objetivo, nivel recomendado, semanas, días/semana soportados
  [3,4,5], descripción) y las semanas con definiciones que usan ritmos
  SIMBÓLICOS.
- Adoptar = **snapshot completo** a `PlanUsuario` (con `planBaseID@v`
  como procedencia). Actualizar la app con `@2` jamás toca instancias
  `@1` en curso. "Hay una versión nueva del plan" = feature futura
  opcional, nunca automática.
- Experiencia: Explorar → filtrar por objetivo/nivel/días → vista
  previa de semanas → elegir fecha de inicio (o de carrera, contando
  hacia atrás) → se instancia el calendario.
- El editor manual actual (tramos + JSON de ChatGPT) se conserva como
  "Plan personalizado" — mismo `PlanUsuario`, origen distinto.

## 13. Evaluación inicial

Onboarding (una pantalla, cuatro caminos, todos producen
`ReferenciaRendimiento`):

1. **Test 5K guiado**: un `DefinicionEntrenamiento` tipo
   `testEvaluacion` (calent. + 5K a fondo controlado + vuelta a la
   calma); al guardar la sesión, el tiempo del bloque central crea la
   referencia con fuente `test5K`.
2. **Marca reciente**: cargar distancia+tiempo a mano (fuente
   `carreraReal` o `marcaManual`).
3. **Estimación suave** para principiantes: sin test a fondo; caminata/
   trote de evaluación liviana o directamente arrancar el plan
   "Primeros 5K" SIN baseline (los planes para principiantes absolutos
   pueden definirse por esfuerzo percibido, no por ritmo — decisión
   metodológica D4).
4. **Empezar sin test**: explícitamente permitido; el test queda
   sugerido como primer entrenamiento opcional.

## 14. Historial y progreso

- Historial: lo actual (HealthKit + fusión por uuid) + el vínculo:
  cada carrera muestra si fue "Entrenamiento: Series 5×1K (semana 3)"
  o "Carrera libre".
- Progreso derivable sin persistir derivados: km/semana y ritmo (ya
  existe), consistencia = cumplidos/programados por semana (del
  calendario), mejores marcas y evolución del test = de la lista de
  `ReferenciaRendimiento` + sesiones. Solo se cachea lo que la UI
  necesite rápido, recalculable siempre.

## 15. Branding del resumen compartible (pendiente, NO implementado)

- **Asset correcto**: `Maraton/Assets.xcassets/AppIcon.appiconset/icon1024.png`
  (1024×1024, RGB sin alfa — es el logo del usuario ya centrado). El
  original crudo es `logo.jpg` en la raíz del repo. El AppIcon NO es
  accesible por `Image(named:)` de forma confiable → crear un imageset
  nuevo: `Maraton/Assets.xcassets/LogoMaratonia.imageset/` con una
  copia de `icon1024.png` y su `Contents.json` (idiom universal, single
  scale) — se puede hacer a mano en el repo, sin Xcode.
- **Cambio exacto en `TarjetaCompartir`** (cuando se implemente):
  ```swift
  HStack(spacing: 8) {
      Image("LogoMaratonia")
          .resizable().scaledToFit()
          .frame(width: 22, height: 22)
          .clipShape(RoundedRectangle(cornerRadius: 5))
      Label("Maratonia", systemImage: "figure.run")  // → Text("Maratonia")
  }
  ```
  reemplazando el `Label` actual (el ícono SF `figure.run` pasa a ser
  redundante → `Text`). Proporción: cuadrado fijo 22 pt, `scaledToFit`.
  Resolución: 1024 px a 22 pt × escala 3 (66 px) sobra nitidez.
  Legibilidad en la variante transparente: el logo tiene fondo propio
  (sin alfa), la esquina redondeada lo encapsula como sticker y la
  sombra existente (`sombra`) ya se aplica al contenedor. Export:
  `ImageRenderer` toma assets del bundle sin trabajo extra; verificar
  en el PNG sin fondo que el logo no “flote” sin contraste — si
  molesta, borde de 1 pt blanco al 30 %.

## 16. Roadmap por fases (cada una: implementar → compilar → probar → commit)

El orden difiere del sugerido: "Correr desde iPhone" ya existe en un
80 % (motor completo); lo que no existe es el TIEMPO (calendario). Sin
calendario no hay "hoy", y sin "hoy" ni el Home ni Correr-desde-iPhone
tienen qué mostrar. Por eso el dominio y el calendario van primero.

- **FASE A — Dominio + IDs + migración** (solo modelo y persistencia,
  cero UI): entidades de §3, adaptador Plan legacy, migración §8,
  tests de todo. *Riesgo bajo, desbloquea todo.*
- **FASE B — Catálogo mínimo + calendario**: 1-2 PlanBase reales en
  JSON (Primeros 5K, 10K), adopción con snapshot, pestaña PLAN muestra
  el calendario, reprogramar (mover de día) y omitir. Ritmos absolutos
  todavía (sin baseline).
- **FASE C — INICIO + vínculo sesión↔programado**: Home "hoy",
  cumplimiento por sesión vinculada (reemplaza huella), metadata en
  HKWorkout, historial muestra el vínculo.
- **FASE D — Correr el entrenamiento del día desde iPhone**:
  `CarreraCelu` recibe (definición, audio, programadoID). Extensión
  del motor: segmentos por TIEMPO (única pieza de motor nueva).
- **FASE E — Watch a proyección del día**: ProyeccionDia +
  vuelta `{programadoID, hkUUID}`; retirar EstadoPlanWatch/huella.
- **FASE F — Evaluación inicial** (§13) + `ReferenciaRendimiento`.
- **FASE G — Ritmos personalizados** (§6): simbólicos + metodología
  versionada (requiere decisión D4).
- **FASE H — Progreso** (§14).
- **FASE I — Adaptación del plan** (futuro lejano; recién acá).
- Transversal, en cualquier momento: §15 (logo en la tarjeta — 20
  minutos), mover Música a PERFIL (§11 paso UI).

## 17. Riesgos

1. **Migración con dispositivos desincronizados** (iPhone v2 + watch
   v1 y viceversa): mitigado con la versión puente (§8.5), pero es EL
   punto a probar físico en cada fase.
2. **Fechas**: todo el calendario debe ser DÍA LOCAL (`DateComponents`
   año/mes/día, `Calendar.current`), jamás `Date` interpretado UTC —
   la regla ya está escrita en NIGHT_AUDIT; el calendario es el primer
   código que la pone a prueba de verdad.
3. **Scope creep del catálogo**: escribir planes de entrenamiento
   reales es trabajo DEPORTIVO, no de software. Fase B con 1-2 planes
   sencillos y honestos; crecer después.
4. **Metodología sin fuente** (D4): si se postea "tu ritmo umbral es X"
   sin metodología citable, es humo peligroso. Bloqueante para Fase G,
   no antes.
5. **Doble motor iPhone/watch**: ya existen y comparten lo puro
   (AutoPausa, zonas, Plan). Unificarlos del todo NO es objetivo v2:
   la duplicación restante es deliberada (frameworks distintos:
   HKWorkoutSession vs HKWorkoutBuilder).

## 18. Decisiones de producto — RESUELTAS (aprobación 2026-08-09)

- **D1 — Parcial es estado real**: estructura completa cumplida →
  `cumplido`; iniciada sin completar → `parcial` (conserva sesión,
  vínculo y datos); no iniciada → programado/vencido/omitido. Sin
  reglas mágicas de porcentaje salvo metodología futura explícita.
- **D2 — Carrera libre puede contar, NUNCA automáticamente**: al
  terminar una libre con un programado compatible pendiente se OFRECE
  vincular la sesión existente (sin duplicar nada en Salud). La
  arquitectura lo soporta desde Fase A (`AlmacenV2.vincular`); la
  oferta de UI y la heurística de compatibilidad son fases futuras.
- **D3 — `overdue` (vencido) existe desde Fase A y es DERIVADO**: se
  calcula de la fecha, nunca se persiste — cero mutaciones silenciosas
  por paso del tiempo. Un vencido se puede hacer (→ cumplido/parcial
  vía vínculo), reprogramar u omitir explícitamente. No hay "7 días →
  skipped automático".
- **D4 — VDOT/Daniels como primera metodología**, con arquitectura
  multi-metodología versionada (`metodologiaID@version`), ritmos
  simbólicos en las definiciones y baseline siempre en datos crudos
  (VDOT = derivado recalculable). Implementación recién en Fase G,
  precedida de investigación de fuentes/licencias/límites. No se
  copian tablas propietarias.
- **D5 — Reloj vive en PERFIL** (dispositivos/preferencias/cuenta).
- **D6 — JSON + CloudKit se mantienen**; no se migra a SwiftData. Una
  sola cosa cambia por vez: dominio ahora, persistencia jamás en V2.
- **`rescheduled` NO es estado** (análisis aceptado): reprogramar =
  mutar `dia` conservando `diaOriginal`; el programado sigue
  `pendiente`. Preserva la historia sin estados contradictorios.
- **Refinamiento de §11**: los avisos por KM quedan en
  `ConfiguracionAudio` (son recordatorios del corredor, valen también
  en Carrera Libre); los TRAMOS/segmentos son entrenamiento.

## 20. Fase B — IMPLEMENTADA (build 36) · pendiente compilar el 36

Catálogo de 2 PlanBase provisionales (JSON embebido + Codable),
adopción por snapshot con fechas DiaLocal determinísticas, consultas
de dominio (entrenamientoDeHoy/próximos/vencidos), historial de planes
archivados, CUTOVER orden-independiente e idempotente (AlmacenStore:
`activado = true` en el primer arranque; la migración de ensayo ya no
toca el archivo), y UI mínima en PLAN (Calendario con 5 estados +
Explorar planes con confirmación de reemplazo). **Qué ve el watch
hasta Fase E**: exactamente lo mismo que hoy — plan.json legacy
(tramos+audio) vía WatchConnectivity; el calendario V2 vive solo en el
iPhone; el cumplimiento del watch sigue por huella V1. Adoptar un plan
del catálogo NO cambia lo que el reloj recibe (limitación conocida y
aceptada hasta Fase E).

**Validación**: build 35 (Fase A) COMPILADO, archivado, subido a
TestFlight y en uso en dispositivo — condición previa satisfecha; el
Codable del dominio V2 quedó probado en binario real. Pendiente: (a)
compilar/archivar el build 36 (Fase B: PlanV2.swift + UI), (b) crear
el target de tests (Tests/README.md) y correr DominioV2Tests. Fase B
se declara estable cuando (a) pase.

## 21. Fase C — IMPLEMENTADA (build 37)

Circuito completo por primera vez: programado → EMPEZAR (Plan o
Correr) → motor iPhone → HKWorkout guardado → vínculo por
HKWorkout.uuid + metadata `com.pipeveiga.maraton.programadoID` →
cumplido/parcial (D1: estructura = todos los tramos ejecutables
recorridos, misma regla que el reloj) → calendario refrescado al
instante. El vínculo solo se emite con el workout real en mano: si
Salud falla, el programado queda pendiente (cumplido fantasma
imposible por construcción; no hay nada que reintentar porque sin
HKWorkout no existe sesión). Carrera libre pasa por el mismo
LanzadorSesion con vínculo nil; la oferta "¿contar esta carrera?"
(D2) tiene la arquitectura lista (vincular) y la UI/heurística de
candidato queda para una fase posterior — nunca automática. Design
System V2 fundacional en `DisenoV2.swift` (tokens DV2 + TarjetaV2 +
botón primario + métricas + TarjetaEntrenamientoV2), aplicado SOLO a
lo nuevo. **Destino de PLAN (§12, documentado, no ejecutado)**: la
pestaña debe terminar priorizando hoy/semana/objetivo/calendario;
Música/Avisos/Tramos manuales/Cronograma bajan a "configuración del
entrenamiento" (hoy siguen donde están; la migración visual global
llega con el contenido definitivo estable). Watch: sin cambios,
sigue V1 hasta Fase E.

## 19. Fase A — IMPLEMENTADA (build 35)

`Shared/DominioV2.swift` (ambos targets): DiaLocal, Definicion/
Segmento/RitmoObjetivo, EntrenamientoProgramado (estados D1/D3,
reprogramar, omitir), PlanUsuario/SemanaPlan (snapshot), RegistroSesion
(id = HKWorkout.uuid, vínculo único por construcción), Configuracion-
Audio, ReferenciaRendimiento, AlmacenV2 (vincular/registrarSesionLibre,
`activado`) y MigracionV2. `PlanStore` materializa `dominio-v2.json`
como ENSAYO regenerable en cada arranque; con `activado == true`
(cutover de Fase B) se vuelve fuente de verdad intocable. La
`huellaEntrenamiento` queda como puente de migración del lado del
reloj y **muere en Fase E** (cuando el watch pase a ProyeccionDia y
resuelva su huella local contra el programado migrado). Tests:
`Tests/MaratonTests/DominioV2Tests.swift` (18 casos). Ninguna pantalla
ni motor consume V2 todavía. **VALIDADA: build 35 compilado, archivado,
en TestFlight y funcionando en dispositivo.**

## 20. Fases D y E — IMPLEMENTADAS (post build 37)

**Fase D.** `ProgresoTramos` (Shared/Plan.swift): máquina PURA de avance
de tramos mixtos —por distancia y por TIEMPO ACTIVO— compartida por los
dos motores (reemplazó las dos sumas de prefijos duplicadas). `Tramo`
ganó `duracionSegundos` (opcional, retrocompatible; huella V1 idéntica
para tramos por distancia). `tramosEjecutables` ya ejecuta segmentos por
duración (con ambas metas gana la distancia; sin meta, no ejecutable).
Pestaña Correr V2: entrenamiento de hoy protagonista con estructura y
EMPEZAR; Carrera Libre principal cuando no hay nada pendiente, con el
próximo programado como contexto. Durante la carrera: tarjeta del tramo
en curso (x/n, progreso, barra) + siguiente tramo.

**Fase E.** Protocolo en Shared: `ProyeccionDia` (iPhone→reloj por
applicationContext: gana la última, sobrevive offline; vigencia = mismo
día local + versión conocida) y `ResultadoSesionWatch` (reloj→iPhone por
transferUserInfo: cola confiable; receptor idempotente). El iPhone
re-proyecta HOY en cada mutación del almacén (funnel del didSet), al
activar la sesión WC y al cambiar el estado del reloj. El reloj: Home
con "HOY" desde la proyección (identidad por programadoID), corre la
definición (tramos por distancia y tiempo), estampa el programadoID como
metadata del HKWorkout, y devuelve el resultado SOLO con el workout real
guardado. Recuperación post-crash conserva el programadoID persistido
(resultado sale como parcial). Reglas del receptor (`AlmacenStore.
procesar`): programado desconocido o resuelto por OTRA sesión → la
evidencia se registra como carrera libre, jamás se pisa un vínculo ni se
tira una sesión; duplicados = no-op (validado con fuzzing de 30k
corridas de eventos desordenados/duplicados).

**Retiro de `huellaEntrenamiento` / `EstadoPlanWatch`** (progresivo):
la Home del reloj YA no usa huella cuando hay proyección vigente con
entrenamiento. La huella sigue viva SOLO como respaldo para: (a) iPhone
viejo + reloj nuevo (sin proyección), y (b) el plan V1 manual con tramos
cuando hoy no hay programado V2. Se puede BORRAR (EstadoPlanWatch,
huellaEntrenamiento, estadoDelEntrenamiento y marcarCumplimientoSi-
Corresponde) cuando: (1) la proyección esté validada en dispositivo
físico, (2) el flujo Tramos manuales se ejecute vía definiciones V2
(reorganización del Plan), y (3) no queden usuarios con app iPhone
pre-Fase E (hoy: un solo usuario — condición trivial).

## 21. Fases F, G-infra y Progreso — IMPLEMENTADAS (build 38)

**Fase F.** `PerfilDeportivo` (opcional en AlmacenV2 — retrocompatible),
onboarding de 4 pasos NO destructivo (se ofrece una única vez y solo a
quien no tiene nada; siempre en Perfil), marcas crudas como
`ReferenciaRendimiento` (idempotencia por contenido; `referenciaVigente`
= la más reciente), Test 5K como entrenamiento real cuyo tiempo es el
ACTIVO al completar la estructura (evento planCompletado).

**Fase G (solo infraestructura).** `PerformanceBaseline` (derivado con
linaje, nunca persistido), protocolo `MetodologiaRitmos` (id versionado
+ fuente pública OBLIGATORIA), `Metodologias.resolver` como único punto
de resolución con `.pendiente` como estado digno de UI. SIN metodología
activa: VDOT/Daniels no se copia y no se inventan números. Riegel
(fórmula pública citada, 1981) SOLO para equivalencias de tiempos de
carrera en Perfil, con rechazo fuera de 0.25x–4x.

**Progreso v1.** Pestaña nueva (reemplaza al Reloj, que pasó a Perfil,
decisión D5): resumen semanal, volumen 8 semanas, consistencia (racha +
cumplimiento hechos/vencidos — el pendiente de HOY no cuenta como
deuda), destacados. Todo recalculado al vuelo desde Salud y el
calendario V2; cero derivados persistidos, cero métricas fisiológicas
inventadas. Plan reorganizado: música/avisos/tramos/cronograma bajo
"Configuración del entrenamiento".

## 22. Build 39 — saneamiento post-prueba física de build 38

Circuito Watch V2 VALIDADO EN DISPOSITIVO (proyección → correr →
HKWorkout → resultado → vínculo → parcial en calendario). Tres fixes:

1. **Auto-resume**: la reanudación dependía de un stream de GPS que
   nadie vigilaba (Core Location frena la entrega con el usuario
   quieto) y de un umbral de desplazamiento inflable por mala
   precisión. Ahora: `SupervisorReanudacion` (desplazamiento sostenido
   O velocidad Doppler sostenida ≥ 0,9 m/s ×2 lecturas), vigilante
   `debeDespertarGPS` (empujón cada 10 s sin fix) y regla compartida
   `puedeAutoReanudar` (la pausa MANUAL jamás se auto-reanuda).
2. **Estado post-entrenamiento en el reloj**: `ProyeccionDia` lleva
   también el RESULTADO de hoy (resolucionDeHoy/nombreDeHoy/tipoDeHoy,
   opcionales, retrocompatibles); la Home muestra ✓/◐ con Carrera
   libre, con respaldo LOCAL mientras el resultado viaja. Decisión
   pura en `entrenamientoOfrecible`/`resultadoDeHoy` (Shared): un
   programadoID corrido no se vuelve a ofrecer.
3. **Layout del lobby del reloj**: título inline (barra compacta con
   material del sistema) — el Play ya no atraviesa el encabezado.
