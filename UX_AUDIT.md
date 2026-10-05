# Recorrido y confiabilidad — 5 de octubre de 2026

Problema observado: un corredor nuevo dice «Me cuesta recorrer la app».
Desde el 9 de agosto ya estaba planteado que Maratonia debía servir a otras
personas, con sus propias cuentas y preferencias. El objetivo de esta entrega
es que una persona encuentre su entrenamiento, su plan y sus carreras sin
conocer la implementación ni la configuración personal del creador.

## Línea de trabajo

La base es `claude/running-audio-watchos-app-ltyxwy`, build 84. `main` contiene
una versión anterior. Este cambio no debe integrarse sobre `main` sin antes
resolver esa divergencia. PR: https://github.com/pipeveiga/maratonia/pull/5.

Se adaptan las correcciones de GPS, persistencia y cierre de workouts de
PR #4 a la aplicación actual. Las correcciones de opcionales del backend
de ese PR ya existían en esta base; no se reemplaza su esquema ni sus fixtures.

## Destinos previsibles

| Pestaña | Pregunta que responde | Acción principal |
| --- | --- | --- |
| Hoy | ¿Qué corro hoy? | Entrenamiento del día o carrera libre |
| Plan | ¿Cómo está organizada mi preparación? | Calendario activo o crear un plan |
| Progreso | ¿Qué corrí y cómo vengo? | Resumen y carreras |
| Perfil | ¿Cómo lo ajusto a mí? | Cuenta, preferencias, audio y avisos |

Hoy deja de mezclar calendario completo, catálogo y borrado de planes.
Plan tiene un destino propio y abre directamente el calendario si ya existe
un plan. Un banner permite volver a la carrera en curso desde otra pestaña.
Los textos y la ayuda describen estos destinos y el uso desde el iPhone.

El onboarding sólo avanza con sus acciones explícitas: deslizar ya no evita
la validación. Apple Health se solicita cuando la persona elige usar sus
carreras, con una explicación del propósito.

La referencia de organización es la guía pública de Runna:
https://support.runna.com/en/articles/10473504-your-quick-guide-to-navigating-the-runna-app.
Se aplica la claridad de destinos; no se copian sus recursos ni su marca.

## Protección de las carreras y del historial

- `UIBackgroundModes` declara `location` y `audio`; el motor activa las
  actualizaciones en segundo plano y su indicador. Falta verificar una
  carrera física con iPhone bloqueado; compilar no demuestra continuidad GPS.
- La auto-pausa evalúa la fecha de medición GPS, rechaza señales viejas,
  futuras o repetidas y corta la continuidad al perder señal.
- El dominio guarda el principal y una generación válida anterior. Si
  recupera una copia, conserva el archivo corrupto e informa al usuario.
  Si no hay copia legible, bloquea la carga y permite reintentar; nunca
  convierte corrupción o un esquema futuro en una instalación vacía.
- Una escritura fallida conserva cambios en memoria y muestra un reintento.
  La proyección al reloj y la sincronización de cambios esperan la escritura
  local confirmada. Son copias locales: desinstalar borra ambas.
- Apple Watch comunica una sesión cumplida sólo si Salud devuelve un
  workout guardado. El cierre tiene identidad para evitar dobles callbacks;
  errores de guardado y de ruta se muestran con su resultado real.
- Las cuentas Firebase con UIDs distintos ya no comparten la identidad
  local, aun con el mismo email. Los datos conservados de A bloquean su
  asociación con B; volver a A permite recuperarlos sin migrarlos a B.
- Cerrar sesión prepara la caché antes de desconectar Firebase. Una cola
  pendiente o un error de disco conserva la sesión y permite reintentar.
  La limpieza local no genera una escritura de perfil vacío en la nube.
- La cola de sincronización conserva el UID dueño de cada operación, procesa
  escrituras en serie y sólo las quita después del ACK del servidor. Las
  ediciones que llegan durante un envío se conservan. El botón de cierre no
  espera una conexión ausente indefinidamente.

Referencia de segundo plano:
https://developer.apple.com/documentation/corelocation/cllocationmanager/allowsbackgroundlocationupdates.

Confirmación de escrituras Firestore:
https://firebase.google.com/docs/reference/swift/firebasefirestore/api/reference/Classes/DocumentReference.

## Evidencia automatizada

El esquema compartido ejecuta los tests de dominio y cuatro recorridos UI
sin depender de la cuenta del creador. GitHub Actions compila iPhone y Watch
en Release, ejecuta los tests en iPhone 17 Pro y guarda resultados/capturas.
La configuración exacta y los comandos están en `Tests/README.md`.

Backend: 57/57 pruebas pasaron con Node 20 el 5 de octubre. El resultado
nativo de cada commit está en los checks del PR; no sustituir una ejecución
del commit final por una compilación de una versión anterior.

## Prueba física antes de distribuir

1. Instalación nueva y cuenta distinta de la del creador: completar acceso,
   crear un plan propio y recorrer las cuatro pestañas sin explicación externa.
2. iPhone: carrera de al menos 15 minutos, pantalla bloqueada, comprobar GPS,
   distancia, avisos, pausa manual/automática y carrera visible en Salud.
3. Apple Watch sin el teléfono cerca: correr, terminar, comprobar el workout
   en Salud y que una sola sesión llegue al historial al reconectar.
4. Denegar permisos de Salud y ubicación por separado; comprobar mensajes,
   acceso a Ajustes y ausencia de confirmaciones de guardado inventadas.
5. Interrupción de audio y pérdida de señal GPS; confirmar que las señales
   viejas no disparen reanudación y que se mantenga el control de la sesión.
6. Reabrir después de terminar o interrumpir una carrera; comprobar identidad,
   recuperación y conservación de calendario, preferencias y sesiones.
7. Dos cuentas Firebase en el mismo teléfono: cerrar A con y sin cambios
   pendientes, entrar con B y volver a A; comprobar aislamiento del perfil,
   planes y cola remota. Validar el caso de una cuenta revocada.

Los cambios son reviewables en el PR. No se ha publicado una nueva build en
TestFlight ni se ha validado hardware desde este entorno.
