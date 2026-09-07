# Revisión de ingeniería — 2026-09-06

## Mapa del proyecto revisado

- Dos apps SwiftUI (iPhone y watchOS), con dominio compartido en `Shared`.
  El iPhone administra calendario, perfil, catálogo, adaptación y cuenta;
  el reloj ejecuta sesiones sin teléfono. Los motores de carrera separados
  coordinan GPS, audio, avisos, tramos y HealthKit.
- `PlanStore` conserva el plan/audio legacy en JSON; `AlmacenStore` mantiene
  el dominio V2, migración, planes archivados y vínculos con sesiones.
  CloudKit respalda el plan legacy. El reloj persiste plan y proyección en
  JSON y cumplimiento local en UserDefaults.
- WatchConnectivity transmite la proyección del día por applicationContext,
  planes/resultados por transferUserInfo y música por transferFile. Los
  resultados se deduplican por identidad del workout en el dominio.
- HealthKit conserva carreras y rutas: live builder en watchOS, builder
  explícito en iPhone; el historial consulta Salud y conserva UUIDs estables.
- Planes: catálogo y generación local, baseline de rendimiento, segmentos
  por distancia/tiempo y ritmos resueltos. La adaptación valida propuestas
  antes de aplicarlas. Firebase autentica el backend Coach; las operaciones
  propuestas por IA no escriben directamente el dominio.
- Tests: cuatro archivos XCTest realmente conectados; README y documentos
  de arquitectura/auditorías históricas describían etapas anteriores.
  No hay workflow de CI en el repositorio.

## Problema seleccionado y evidencia

La auto-pausa congela registro, cronómetro, música y avisos; una decisión
incorrecta afecta toda la carrera. Es una corrección acotada, compartida
por ambos dispositivos y verificable sin migrar datos.

Antes del cambio, los dos `locationManager(_:didUpdateLocations:)` usaban
`Date()` para renovar `fechaUltimaSenalPausa` y alimentar el supervisor de
reanudación. El reloj también guardaba `Date()` en `ubicacionesRecientes`;
el iPhone asignaba `Date()` a `fechaUltimoGPS`. Ninguno distinguía un fix
cacheado de una medición nueva. La fecha real está en `CLLocation.timestamp`.

Además, `AutoPausa.SupervisorReanudacion` sólo exigía separación mínima
entre candidatos: velocidad 1,2 m/s en t=0 y t=20 reanudaba, incluso sin
ninguna señal durante esos 20 segundos. Esa secuencia se reprodujo contra
el código original y dejó de reanudar con la corrección.

## Solución y compatibilidad

`FiltroSenalGPS` acepta para decisiones en vivo únicamente mediciones con
precisión válida, edad entre 0 y 5 segundos, fecha estrictamente creciente
y posteriores al inicio de la fase actual (inicio, pausa o reanudación).
Los motores usan timestamps medidos y reinician el filtro al cambiar de
fase. Un callback viejo no renueva la vigilancia del GPS.

El supervisor ignora fechas repetidas/invertidas y reinicia ambos candidatos
si pasan más de 5 segundos entre señales. Conserva los umbrales existentes
de velocidad, desplazamiento e histéresis de 1,5 segundos.

No cambian JSON, IDs, migraciones, contratos de WatchConnectivity ni
permisos. Los puntos que se guardan en la ruta conservan el tratamiento
anterior: el filtro nuevo sólo decide auto-pausa y reanudación.

## Validación

- Suite completa en iPhone 17 Pro, iOS Simulator 26.5, Xcode 26.6: 403 tests pasaron, 0 fallos y 0 omitidos.
- Ocho tests nuevos de regresión GPS, además de los existentes de pausa,
  reanudación, estimación de ritmo y compatibilidad.
- Compilación de las apps iPhone/watchOS durante la ejecución de la suite.
- Reproducción aislada con el enum original: reanuda incorrectamente tras
  20 segundos sin señal; con el enum corregido no reanuda.
- Revisión del diff, `git diff --check` y chequeo de los 37 archivos Swift.
- El primer intento, sin firma, cayó en `CKContainer` antes de XCTest.
  Repetir con firma normal del simulador resolvió el fallo sin alterar
  código de producto ni saltear pruebas.

## Riesgo residual y prueba física

Con GPS muy intermitente, la reanudación puede tardar más porque requiere
nueva evidencia sostenida. El simulador no valida cadencia real de sensores.

En ambos dispositivos, con auto-pausa activada:

1. Correr más de 30 segundos, detenerse unos 10 segundos y volver a caminar
   o correr: verificar pausa y reanudación de cronómetro, música y avisos.
2. Durante auto-pausa perder GPS brevemente y recuperarlo: no debería decir
   «Seguimos» por una única señal; debe reanudar con movimiento sostenido.
3. Pausar manualmente y moverse: debe seguir pausado hasta tocar Reanudar.
4. Terminar y revisar tiempo activo, distancia y mapa en Salud; repetir una
   sesión con auto-pausa desactivada.

## Segunda revisión — 2026-09-07

Se amplió esta misma propuesta sobre main sin nuevos cambios remotos. Se
revisaron persistencia, sincronización, cierre HealthKit, UI de confirmación,
contrato del Coach y las pruebas. Los cambios nuevos son:

### Recuperación del dominio y errores visibles

Evidencia: `PlanStore.migrarADominioV2SiHaceFalta` interpretaba un V2 ilegible
como ausencia y lo reemplazaba desde legacy. `AlmacenStore.cargarConCutover`
repetía esa decisión y `escribir` silenciaba errores con `try?`.

Ahora `PersistenciaAlmacen` distingue ausencia, corrupción, errores de lectura
y versiones no compatibles. Guarda una generación anterior del dominio
completo antes de reemplazar el principal. Recupera esa copia si corresponde,
preserva el JSON dañado y lo comunica en pantalla. Sin copia válida o con un
esquema incompatible protege los originales, bloquea las ediciones y ofrece
reintentar la lectura. Una escritura fallida conserva el estado en memoria,
muestra el problema y permite reintentar sin volver a cargar datos antiguos.
Las proyecciones al reloj sólo salen con el estado guardado.

Nueve pruebas nuevas ejercitan corrupción, ambas generaciones, falta del
principal, errores de lectura/escritura, reintentos, protección de esquemas
futuros, resultados pendientes y fallos de codificación. La migración
existente mantiene sus pruebas y conserva IDs y formatos JSON.

### Guardado del reloj ligado al resultado real

Evidencia: el resumen decía «¡Carrera guardada!» antes de `finishWorkout`;
el botón Terminar marcaba el plan legacy cumplido antes de la confirmación.
Además, el cierre consultaba `self.builder`/`self.routeBuilder` desde callbacks
y un segundo evento ended podía iniciar otro cierre.

El cierre captura builder, ruta e identidad de la sesión; un control compartido
impide dobles cierres y limpiezas de sesiones nuevas por callbacks viejos.
Los delegates de sesión y estadísticas verifican identidad. El estado visible
distingue guardando, guardada y sin guardar. El cumplimiento legacy sólo se
marca con un workout real; los resultados V2 también conservan esa regla.
Los fallos de colección, resultado nulo y ruta se comunican. La recuperación
ya no afirma éxito antes de recibirlo y los finales externos apagan el GPS.

Cuatro pruebas nuevas cubren cierre duplicado, recovery más ended, eventos
ajenos y un completion viejo que llega después de iniciar otra sesión.
Prueban el control compartido utilizado por watchOS; no simulan HealthKit.

### Consultas válidas al Coach

Evidencia: `ContextoCoach` usa Codable sintetizado, que omite Optional nil.
`functions/schemas.js` exigía presencia con `.nullable()` en esos campos;
la petición legítima fallaba antes de llamar al proveedor. El fixture nuevo
se generó con JSONEncoder a partir de las declaraciones reales del DTO Swift.

El esquema acepta ausencia o null exclusivamente en los opcionales del DTO.
Mantiene campos obligatorios, límites, UUIDs y rechazo de propiedades extra.
La prueba del JSON Swift falla contra el esquema anterior y pasa con el nuevo.
Cinco pruebas de Node validan compatibilidad, límites y exclusión de GPS.
No se desplegó el backend: el cambio queda revisable en el repositorio.

## Validación y límites de la segunda revisión

- Suite completa de la app en Xcode 26.6 / iOS Simulator 26.5, incluyendo
  compilación de iPhone y watchOS: 416 tests aprobados, 0 fallos, 0 omitidos.
- `npm test` del backend: 5 pruebas aprobadas. Se usó Zod 3.23.8 en una
  instalación temporal; no se llamó a Firebase ni al proveedor de IA.
- Revisión del diff, sintaxis de los 38 archivos Swift y `git diff --check`.
- Verificación visual en un simulador nuevo con un archivo sintético truncado:
  el original se conservó y se mostró el aviso con «Reintentar lectura» y
  las ediciones bloqueadas. No se usaron datos de un corredor real.
- Las pruebas de plataforma siguen requiriendo iPhone y Apple Watch físicos.

## Qué probar manualmente ahora

1. En una instalación de prueba, editar calendario, cerrar y reabrir; comprobar
   plan, sesiones y referencias. Ante recuperación, verificar el aviso y los
   últimos cambios (la copia contiene la generación anterior).
2. En el reloj, terminar y esperar «Carrera guardada»; comprobar el workout
   y mapa en Salud y el cumplimiento en el iPhone. Probar descarte, dos carreras
   seguidas y guardado con permiso de Salud denegado.
3. Con el backend corregido desplegado, consultar al Coach sin fecha de carrera,
   sin baseline y sin feedback subjetivo; las peticiones deben ser válidas.
4. Repetir los escenarios de auto-pausa de la primera revisión.

## Deuda y riesgos pendientes

- La copia nueva es local y de una generación: no cubre pérdida del teléfono,
  desinstalación ni corrupción simultánea de las dos copias. El respaldo
  CloudKit sigue centrado en el plan legacy y no cubre todo V2.
- Si falla la escritura, los cambios más recientes permanecen sólo en memoria
  hasta reintentar. El aviso pide mantener la app abierta. Los resultados del
  reloj recibidos durante una lectura bloqueada se retienen en memoria hasta
  recuperarla; falta una bandeja persistente con confirmación de recepción.
- El inicio HealthKit todavía tiene operaciones asíncronas sin tratamiento
  exhaustivo de errores; recuperación y cadencia de sensores necesitan campo.
- Los motores siguen siendo singletons con efectos de plataforma; no hay
  tests de integración propios del target watchOS ni workflow de CI.
- El backend conserva trabajo pendiente en idempotencia concurrente y manejo
  de errores de Firestore. La corrección de esquema no cambia esos mecanismos.

Esta revisión resuelve los defectos descritos; no certifica que el repositorio
entero esté libre de errores.
