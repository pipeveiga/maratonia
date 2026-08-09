# RC1 — Checklist de validación (build 32)

Estado: **RELEASE CANDIDATE 1 — congelado** (solo entran bug fixes
demostrables, regression tests y docs). Rama:
`claude/running-audio-watchos-app-ltyxwy`. Nada mergeado a `main`.

---

## Smoke Test — 5 minutos

| # | ACCIÓN | RESULTADO ESPERADO | SEÑAL DE ERROR |
|---|---|---|---|
| 1 | GitHub Desktop: Pull en la rama. Abrir `Maraton.xcodeproj`. | Abre sin diálogos. En la barra lateral aparece `CarreraTelefono.swift`. | "Damaged/parse error" → el pbxproj se rompió: no archivar, avisar. |
| 2 | Product → Build (Cmd+B) para el esquema **Maraton**. | Build Succeeded. | Errores de compilación → anotar el PRIMER error textual completo. |
| 3 | Cambiar esquema a **Maraton Watch App** → Cmd+B. | Build Succeeded. | Ídem. |
| 4 | Product → Archive (esquema Maraton, Any iOS Device). | Archive OK, Build = 32. | Falla de firma → Try Again en Signing; otra cosa → anotar. |
| 5 | Instalar por TestFlight en iPhone+reloj. Abrir ambas apps. | iPhone: 5 pestañas. Reloj: lobby con Play grande. | Crash al abrir → revisar rollback (tabla abajo). |

Si el smoke pasa, lo grave está intacto. Seguir con Full Validation
cuando haya 30 min.

## Full Validation — 20/30 minutos (con auriculares BT puestos)

| # | ACCIÓN | RESULTADO ESPERADO | SEÑAL DE ERROR |
|---|---|---|---|
| 1 | Reloj: engranaje → verificar toggles (Auto-pausa ON, Avisar zona ON, Ruta GPS ON). Volver y Play. | Cuenta 3-2-1, música arranca, pantalla de métricas. | Vuelve al lobby → leer el error rojo junto al Play. |
| 2 | Reloj: esperar el primer aviso o tocar "Aviso" (página izquierda). | La música SE PAUSA, habla, la música sigue sola. | Voz y música encimadas, o la música no vuelve. |
| 3 | Reloj: caminar 30 s y frenar en seco 15 s. | "Pausa automática" por voz; pantalla dice pausa automática. | No pausa (¿GPS con señal? ¿puntos > 0?), o pausa sin estar quieto. |
| 4 | Caminar 20 m. | "Seguimos" + todo reanuda solo. | No reanuda en ~30 s → tocar Reanudar manual (anotar). |
| 5 | Pausar manual (botón) y Reanudar (botón). | Cronómetro congela y sigue; sin dobles avisos. | Tiempo salta o avisos duplicados. |
| 6 | **Interrupción**: pedir a alguien que te llame en pleno aviso. Atender 10 s y colgar. | Al colgar, la música vuelve sola en ~2 s. | Música muerta → ES EL FIX 22/25: anotar exactamente qué sonaba al entrar la llamada. |
| 7 | Apagar los auriculares BT en plena música (reloj). | La sesión SE PAUSA sola (todo congelado). Reconectar y Reanudar. | Sigue "reproduciendo" sin audio. |
| 8 | Terminar y guardar. | Tarjeta "¡Carrera guardada!" con "Recorrido: N puntos GPS". | "Sin señal GPS" con GPS bueno, o error rojo de guardado. |
| 9 | Reloj: dar Play INMEDIATAMENTE de nuevo (corrida corta) y Cancelar sesión. | Arranca normal; cancelar descarta. | "Cerrando la sesión anterior…" persistente > 30 s. |
| 10 | iPhone: Mis carreras (esperar sync o tirar hacia abajo). Abrir el detalle y tirar para refrescar la lista con el detalle abierto. | Carrera con mapa; el detalle abierto NO se rompe. | "No encontré esta carrera" tras refresh (regresión del ID estable). |
| 11 | iPhone: pestaña Correr → Play (sin reloj, celu en mano). Caminar 2 min, bloquear pantalla 1 min, desbloquear. | Cronómetro correcto (no congelado); sin ráfaga de avisos viejos. | Tiempo mal, o lee 4 avisos seguidos. |
| 12 | Celu: terminar. Ver tarjeta y Mis carreras. | "¡Carrera guardada!" honesta; aparece en la lista. | Dice guardada y no está (permiso de Salud → fila de la app). |
| 13 | **Crash recovery** (reloj): arrancar carrera, dejarla corriendo, matar la app del reloj (mantener botón lateral → corona). Reabrir. | Aviso "recuperé el entrenamiento y lo guardé en Salud" + tarjeta. | Nada aparece y el Play queda bloqueado → ES EL FIX 18. |
| 14 | iPhone: Perfil → Restaurar desde iCloud. | Pide confirmación ANTES de pisar el plan. | Restaura sin preguntar. |
| 15 | Warnings del Archive: abrir el navegador de issues. | Los de siempre (ninguno nuevo en archivos tocados). | Warnings nuevos en Reproductor/Avisador/Entrenamiento/CarreraTelefono → anotarlos textuales. |
| 16 | Crear el target de tests (Tests/README.md, 7 pasos) → Cmd+U. | Todos los tests pasan. | Cualquier fallo: anotar el nombre del test. |

## Tests manuales que NO tienen sustituto automatizable

- Interrupción de llamada real (pasos 6): AVAudioSession no se mockea.
- Auto-pausa con GPS real (pasos 3-4): umbrales dependen de señal.
- Crash recovery físico (paso 13).
- Spotify + modo música externa: correr con Spotify del reloj, terminar
  durante un aviso → el volumen de Spotify debe recuperarse (fix 23).

## Rollback plan (commits de la sesión, del más nuevo al más viejo)

| Commit | Objetivo | Riesgo | Depende de |
|---|---|---|---|
| (HEAD) RC1 | Consolidación: aislamiento entre corridas (celu), error de guardado nunca silenciado, regla de drenaje extraída + tests | Bajo | 4172d8e |
| `4172d8e` | Adversarial: regla de drenaje de avisos, mensaje iCloud en verificando | Bajo | 6b76662 |
| `6b76662` | 18 fixes multi-agente (audio/interrupciones/ruta/Salud/Carreras) | **Medio-alto** (audio del reloj: reactivación async, observers nuevos) | 70c406d |
| `70c406d` | Workout fantasma, builder pisado, didCancel, duck de Spotify | Medio | aa98642 |
| `aa1525c` | Confirmación de restaurar + docs | Nulo | — |
| `aa98642` | IDs estables, zonaCardiaca única, persistencia con voz, recovery blindado | Bajo-medio | 70424a6 (build 31) |

Cómo revertir una categoría: `git revert <commit>` (NUNCA reset).
Si falla **audio del reloj** en los pasos 2/6/7 → sospechar `6b76662` y
`70c406d`. Si falla **guardado en Salud** → `70c406d` y el HEAD. Si
falla **Mis carreras** → `aa98642` (IDs) y `6b76662` (fusión).

## Invariantes que este RC protege (y dónde)

1. Un solo workout activo — guard `sesion == nil` + mensaje (reloj);
   guard `estado == .detenida` (celu).
2. Finalizar idempotente — `cerrarYGuardar` tolera repetición; celu
   `terminar` con guard de estado.
3. Callbacks tardíos no tocan la corrida siguiente — identidad de
   builder + capturas locales + `iniciar` resetea builders (celu).
4. Un fallo de audio nunca deja un workout invisible — el entrenamiento
   arranca solo desde el callback de audio real (reloj).
5. La voz nunca deja la música duckeada/pausada para siempre —
   didFinish+didCancel+detener+interrupción .began cubren los 4 finales.
6. El tiempo NUNCA es conteo de ticks — timestamps en ambos motores
   (excepción deliberada: el debounce de zona cuenta ticks activos
   porque así descuenta pausas).
7. Ninguna falla de persistencia es muda — plan (banner), Salud
   (mensaje + resumen honesto), iCloud (mensaje en Perfil).
