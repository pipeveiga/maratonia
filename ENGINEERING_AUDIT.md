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

## Deuda que queda fuera de este cambio

- Persistencia V2 usa `try?` y puede reconstruir desde legacy ante un archivo
  ilegible; falta recuperación explícita y reporte de errores.
- Cierre HealthKit del reloj accede a builders compartidos desde callbacks;
  conviene aislar cada cierre por identidad y hacerlo idempotente.
- Motores con singletons y efectos de plataforma dificultan pruebas de
  integración de callbacks, audio y recuperación. No hay tests watchOS propios.
- El respaldo CloudKit sigue centrado en el plan legacy; no cubre todo el V2.

Estos hallazgos requieren cambios y pruebas específicos; no se consideran
resueltos por la corrección de auto-pausa.
