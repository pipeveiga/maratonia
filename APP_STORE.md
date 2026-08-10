# APP_STORE — Material para App Store Connect (V1)

Campos marcados **[DECISIÓN FELIPE]** requieren tu elección o un dato
que solo vos tenés. Nada inventado.

## Ficha

| Campo | ES | EN |
|---|---|---|
| Nombre | Maratonia — Entrenamiento de running | Maratonia — Run Training |
| Subtítulo (30) | Tu plan para 5K a maratón | Your 5K-to-marathon plan |
| Categoría | Salud y forma física (secundaria: Deportes) | Health & Fitness (Sports) |
| Keywords (100) | correr,running,5k,10k,maraton,media,plan,entrenar,ritmo,watch,gps,coach | run,running,5k,10k,marathon,half,plan,training,pace,watch,gps,coach |
| Promotional text | Planes honestos de 5K a maratón, con tu Apple Watch y tus días reales de entrenamiento. | Honest 5K-to-marathon plans, built around your Apple Watch and the days you can actually run. |

## Descripción ES

Maratonia arma tu plan de entrenamiento alrededor de TU semana: elegís
objetivo (primeros 5K, mejorar 5K, 10K, media maratón o maratón), tu
fecha de carrera y los días exactos en que podés correr — y el plan cae
solo en esos días, con tirada larga, calidad y rodajes fáciles bien
repartidos.

- Corré con el Apple Watch: GPS, ritmo, zonas de frecuencia cardíaca y
  avisos por voz, con tu música.
- Ritmos personalizados desde una marca real (test 5K o carrera
  reciente), con metodología documentada — sin números mágicos.
- Todo queda en Apple Health: tus entrenamientos son tuyos.
- Progreso honesto: historial completo, y marcas solo de sesiones
  fiables.
- Reprogramá u omití sesiones sin culpa: el calendario se adapta.
- Cuenta opcional (Apple, Google o email) — la app completa funciona
  sin registrarte.

Sin publicidad. Sin vender datos. Tus rutas GPS jamás salen de tu
dispositivo.

## Description EN

Maratonia builds your training plan around YOUR week: pick a goal
(first 5K, faster 5K, 10K, half or full marathon), your race date and
the exact days you can run — workouts land only on those days, with
long runs, quality and easy runs sensibly spread out.

- Run with Apple Watch: GPS, pace, heart-rate zones and voice cues,
  with your music.
- Personalized paces from a real result (5K test or recent race), with
  documented methodology — no magic numbers.
- Everything lives in Apple Health: your workouts are yours.
- Honest progress: full history, personal bests only from reliable
  sessions.
- Reschedule or skip guilt-free: the calendar adapts.
- Optional account (Apple, Google or email) — the full app works
  without signing up.

No ads. No data selling. Your GPS routes never leave your device.

## Review notes (para el revisor de Apple)

- La app funciona COMPLETA sin cuenta (guideline 5.1.1: el login es
  opcional). Para probar login: Sign in with Apple con cualquier
  Apple ID, o crear cuenta email con cualquier correo.
- **No hace falta cuenta demo**: no hay contenido bloqueado por login.
- HealthKit: lectura de workouts/FC para historial y progreso;
  escritura del workout al terminar una carrera. Location: ruta del
  mapa durante la carrera.
- Eliminación de cuenta: Perfil → Cuenta Maratonia → Eliminar cuenta
  (borra la identidad de Firebase y el respaldo iCloud; cumple 5.1.1(v)).
- El watchOS app corre entrenamientos de forma independiente.

## App Privacy (formulario)

Ver PRIVACIDAD.md — resumen: Health & Fitness (funcionalidad, sin
tracking), Location (funcionalidad), Contact Info email + User ID (solo
con cuenta, funcionalidad), sin ATT, sin analytics. Si el Coach se
activa en V1: "Other Usage Data" (resúmenes de entrenamiento) enviados
al backend propio + OpenAI como service provider, solo funcionalidad.

## URLs

- Support URL: https://maratonia.site/support/ **[DECISIÓN FELIPE:
  confirmar dominio y hosting]**
- Privacy Policy URL: https://maratonia.site/privacy/
- Terms URL (opcional): https://maratonia.site/terms/
- Marketing URL (opcional): https://maratonia.site

Archivos listos en `web/` (ES+EN, estáticos, sin dependencia externa).

## Estrategia de screenshots (6.7" y 6.1" iPhone + Watch)

No se generan assets finales sin capturas reales. Orden y copy:

| # | Pantalla real a capturar | Copy ES | Copy EN |
|---|---|---|---|
| 1 | Plan tab con semana actual | Tu plan, en tus días | Your plan, on your days |
| 2 | Detalle del entrenamiento de hoy | Cada sesión, explicada | Every session, explained |
| 3 | Watch en carrera (métricas) | Corré con tu Watch | Run with your Watch |
| 4 | Progreso (historial + marcas) | Progreso honesto | Honest progress |
| 5 | Onboarding selector de días | Elegís qué días corrés | You choose your run days |
| 6 | Coach (si queda activo en V1) | Un coach que propone, vos decidís | A coach that proposes, you decide |

Capturas: simulador iPhone 15 Pro Max (6.7") y 15 Pro (6.1") con datos
reales de prueba; Watch Series 9 45mm. Marco/fondo: definir con
capturas en mano.

## Free / Pro (preparación, NO activo en V1)

- V1 se publica GRATIS completa. Coach queda para usuarios con sesión
  cuando el backend esté desplegado; el flag server-side permite
  apagarlo sin release.
- StoreKit 2 NO se incluye en V1 a propósito: un paywall sin productos
  configurados en App Store Connect sería un botón muerto. Cuando se
  decida el precio de Pro: crear el producto en ASC, agregar la capa
  StoreKit 2 y gatear el Coach con la entitlement (el gate de UI ya
  existe y es un solo punto).
- Nunca serán Pro: carrera libre, historial, HealthKit, el plan básico
  ya adoptado.

## Checklist de configuración que queda de tu lado

1. App Store Connect: crear la app (bundle com.pipeveiga.maraton),
   cargar ficha ES/EN de arriba, App Privacy según PRIVACIDAD.md.
2. Subir `web/` a maratonia.site (o el hosting que elijas) y verificar
   las 3 URLs.
3. Screenshots reales según la tabla.
4. Backend Coach (opcional para V1): functions/DEPLOY.md.
5. Build final: Archive del build vigente y enviar a revisión.
