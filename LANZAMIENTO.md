# 📦 LANZAMIENTO — Checklist de envío a la App Store

Paso a paso, en orden, con los textos listos para copiar y pegar.
Los campos marcados **[VOS]** requieren un dato o una decisión tuya.

> Ficha completa en `APP_STORE.md` · Privacidad en `PRIVACIDAD.md`
> Este archivo es el ORDEN de ejecución; ese otro es el contenido.

---

## ⚠️ LEER PRIMERO — tres cosas que cambiaron y rompen el envío

La app que se sube HOY no es la que describían las versiones viejas de
este documento. Verificado en el código, no supuesto:

1. **La app EXIGE cuenta.** `PuertaDeEntrada` ofrece Apple, Google o
   email y **no tiene forma de saltear**. Por lo tanto:
   - **hace falta CUENTA DEMO** en las notas al revisor (guideline 2.1:
     sin credenciales, rechazo automático);
   - y hay riesgo real de **5.1.1(v)** — pedir registro para funciones
     que no lo necesitan. La justificación es la sincronización entre
     dispositivos, y conviene escribirla en las notas.
   - Existe `BienvenidaView` con `permiteSaltear: true`, pero **la
     puerta no la usa**: es código muerto y no es una salida.

2. **El Coach viaja ACTIVO.** `MaratoniaBackendURL` está puesto en el
   `Info.plist` (`us-central1-maratonia.cloudfunctions.net`), así que
   los datos salen del dispositivo hacia OpenAI. **App Privacy tiene que
   declararlo** (ver FASE 4). No es opcional ni "para más adelante".

3. **Hay suscripciones reales.** `maratonia.pro.monthly` y
   `maratonia.pro.yearly` vía StoreKit. Los dos productos tienen que
   EXISTIR en App Store Connect y enviarse **con** la versión (FASE 4b):
   un paywall que apunta a productos inexistentes se le muestra roto al
   revisor.

Lo que ya está bien y no hay que tocar: el paywall muestra **Términos,
Privacidad y el aviso de renovación automática**, que es la causa más
común de rechazo en apps con suscripción.

---

## FASE 0 — Antes de tocar App Store Connect

- [ ] Build 76 compila sin warnings (verificado: cero warnings en
      Release, `xcodebuild -destination generic/platform=iOS`)
- [ ] Los 590 tests iOS + 57 del backend en verde
- [ ] Recorrer las 5 pestañas en **español**
- [ ] Cambiar el iPhone a **inglés** y recorrerlas de nuevo.
      El build 67 rehízo el barrido: el catálogo del iPhone pasó de 636
      a 908 claves y el del reloj de 110 a 228, sin nada sin traducir.
      Incluye el CONTENIDO deportivo (nombres y descripciones de los
      entrenamientos), que ya no se congela en español dentro del plan:
      el snapshot guarda la clave semántica y el texto se arma al
      mostrarlo. Un plan adoptado con una build anterior también se ve
      traducido, sin migración.
      > Ojo con el mecanismo: `xcodebuild` NO sincroniza el
      > .xcstrings —eso lo hace Xcode compilando desde el IDE—, así que
      > si se agregan pantallas y solo se compila por línea de comandos,
      > el catálogo se queda viejo en silencio y el barrido se rompe de
      > nuevo sin que nadie lo note. La lista autoritativa son los
      > `.stringsdata` que emite el compilador en DerivedData.
- [ ] **Una carrera real con el Apple Watch** validando el ritmo en
      vivo (ver checklist física abajo)
- [ ] `https://maratonia.site/privacy/` y `/support/` cargando **[VOS]**
- [ ] Elegir unidades en el onboarding y cambiarlas después en Perfil:
      el plan NO se regenera y los números cambian en toda la app
      (build 68)
- [ ] Objetivo con fecha imposible (p. ej. maratón a 6 semanas): NO se
      arma el plan comprimido, y aparece **Empezar fase base** con el
      puente que el dominio define. Adoptarla deja el objetivo deseado
      pendiente, no lo reemplaza (build 69)
- [ ] Plan → **Ver plan completo**: se ven TODAS las semanas del bloque
      desde el día 1, con descargas, taper y carrera objetivo
- [ ] **Instalación limpia pide cuenta primero** (build 70). Con cuenta
      nueva: onboarding. Con cuenta existente en otro dispositivo:
      aparece TU plan sin pasar por onboarding
- [ ] **Cerrar sesión y entrar con otra cuenta**: no queda a la vista
      ningún dato de la anterior
- [ ] **Modo avión**: abrir el plan, correr, guardar. Al volver la
      conexión, sincroniza sin pedir nada
- [ ] **Sandbox de compras** (Ajustes → App Store → cuenta sandbox):
      comprar anual con los 7 días de prueba, restaurar, y verificar
      que un plan 21K/42K se puede adoptar recién con Pro
- [ ] **Coach con cuenta Free**: el backend responde 402 y NO llama a
      OpenAI (verificable en los logs de Functions)
- [ ] **El recorrido pintado** (build 76): abrir una carrera con GPS y
      mirar el mapa. El ritmo va de ámbar claro (lento) a rojo oscuro
      (rápido); si hay desnivel medido aparece el selector
      **Ritmo / Desnivel**, y ahí azul es bajada, gris llano y rojo
      subida. Señal de error: la carrera entera de un solo color, o el
      llano lleno de color.
      > Sin verificación visual todavía: se subió sin poder probarlo con
      > una carrera real (en el simulador no se puede inyectar una ruta
      > en Salud). La lógica sí tiene 13 tests.
- [ ] **La postal**: compartir una carrera y ver que el recorrido salga
      con el degradado, la leyenda LENTO→RÁPIDO y el contexto del plan
      ("Larga · Semana 3 de 8"). Sin plan detrás no muestra contexto, y
      está bien.
- [ ] **El km más rápido** aparece marcado en Splits y en el gráfico

Si algo de esto falla, no sigas: se arregla antes.

---

## FASE 1 — Crear la app en App Store Connect

appstoreconnect.apple.com → Apps → **+** → Nueva app

| Campo | Valor |
|---|---|
| Plataformas | iOS |
| Nombre | `Maratonia` |
| Idioma principal | Español (México) o Español (España) **[VOS]** |
| Bundle ID | `com.pipeveiga.maraton` |
| SKU | `maratonia-001` |
| Acceso de usuario | Acceso completo |

> Si el nombre "Maratonia" estuviera tomado, App Store Connect te avisa
> ahí mismo. Alternativa: `Maratonia: Entrenamiento` **[VOS]**.

---

## FASE 2 — Ficha (pestaña "Información de la app")

**Subtítulo (30 máx.)**
```
Tu plan para 5K a maratón
```

**Categoría**: Salud y forma física · Secundaria: Deportes

**Derechos de autor**: `2026 Felipe Veiga`

**URLs**
```
Privacy Policy URL:  https://maratonia.site/privacy/
Support URL:         https://maratonia.site/support/
Marketing URL:       https://maratonia.site
```

---

## FASE 3 — Versión 1.0 (español)

**Promotional text**
```
Planes honestos de 5K a maratón, con tu Apple Watch y tus días reales
de entrenamiento.
```

**Descripción**: copiar el bloque "Descripción ES" de `APP_STORE.md`.

**Keywords (100 caracteres, sin espacios tras las comas)**
```
correr,running,5k,10k,maraton,media,plan,entrenar,ritmo,watch,gps,coach
```

**Novedades de esta versión** (primera versión)
```
Primera versión de Maratonia.
```

Después agregá la localización **inglés (EE. UU.)** con los bloques EN
de `APP_STORE.md` (subtítulo, descripción, keywords, promotional).

---

## FASE 4 — App Privacy

Apple entiende por "recolectar" **transmitir el dato fuera del
dispositivo**. Usarlo en el teléfono y dejarlo ahí no cuenta.

Primera pregunta del asistente — *"¿Recolectás datos de esta app?"* →
**Sí** (por el login). Después marcar únicamente:

| Categoría | Dato | Vinculado | Propósito | Tracking |
|---|---|---|---|---|
| Contact Info | Email Address | Sí | App Functionality | No |
| Identifiers | User ID | Sí | App Functionality | No |

**NO marcar** Health & Fitness ni Location: los workouts y la ruta GPS
viven en HealthKit y nunca salen del dispositivo. Tampoco el respaldo
iCloud, que es el iCloud privado del usuario.

**Tracking (ATT)**: NO. Sin publicidad, sin data brokers, sin analytics.

### El Coach — YA NO ES OPCIONAL DECLARARLO

Las versiones viejas de este documento decían "si el Coach no se activa,
no declares nada de OpenAI". **Se activó**: `MaratoniaBackendURL` está en
el `Info.plist`, así que el contexto de entrenamiento (objetivo, días,
volumen, eventos detectados) sale del dispositivo hacia el backend y de
ahí a OpenAI. Hay que agregar:

| Categoría | Dato | Vinculado | Propósito | Tracking |
|---|---|---|---|---|
| Other Data | Other Usage Data | Sí | App Functionality | No |

Lo que SIGUE sin declararse, y con razón: el backend **no puede** recibir
una ruta GPS ni un latido — el `.strict()` del schema los rechaza, y hay
tests que lo prueban. Se manda el resumen numérico, no las muestras.

---

## FASE 4b — Suscripciones (obligatorio ANTES de enviar)

La app trae StoreKit y un paywall. Los dos productos tienen que existir
en App Store Connect, tener precio, y **adjuntarse a la versión 1.0** en
la sección "In-App Purchases and Subscriptions" — si no, el revisor ve
un paywall vacío y es rechazo.

| Product ID | Tipo | Precio |
|---|---|---|
| `maratonia.pro.monthly` | Suscripción auto-renovable, 1 mes | **[VOS]** |
| `maratonia.pro.yearly` | Suscripción auto-renovable, 1 año | **[VOS]** |

Los dos van en el MISMO grupo de suscripción (así el usuario puede
cambiar de plan sin comprar dos veces). El anual tiene **7 días de
prueba** — configurarlo como *Introductory Offer → Free Trial*.

Cada producto necesita nombre y descripción de display; Apple los revisa
como contenido. Y la ficha de la app pide un **Privacy Policy URL** y
unos términos (EULA): ya están en `https://maratonia.site/privacy/` y
`/terms/`, y el paywall los enlaza.

Qué habilita Pro, para escribir la descripción: objetivos avanzados
(Mejorar 5K/10K y todo 21K/42K), el Coach, y la adaptación del plan.

---

## FASE 5 — Screenshots

Obligatorios: **6.7"** (iPhone 15/16/17 Pro Max) y **6.5"**.
Opcional pero recomendado: Apple Watch.

Los 6 encuadres y su copy ES/EN están en `APP_STORE.md`. Capturalos del
dispositivo real con datos de verdad — no del simulador vacío. **[VOS]**

---

## FASE 6 — Build y envío

1. Xcode → Product → **Archive**
2. Distribute App → App Store Connect → Upload
3. Esperar el procesamiento (~10-30 min) y que no llegue mail de Apple
   con warnings
4. En la versión 1.0, seleccionar el build
5. **Notas para el revisor**. El bloque de `APP_STORE.md` está
   DESACTUALIZADO: dice que la app funciona completa sin cuenta y que no
   hace falta cuenta demo, y las dos cosas son falsas hoy. Tiene que
   decir, como mínimo:
   - **Cuenta demo** con email y contraseña que el revisor pueda usar
     (crearla con "Continuar con email" y anotarla acá) **[VOS]**
   - Por qué se pide cuenta: el plan y el progreso se sincronizan entre
     iPhone y Apple Watch y sobreviven a cambiar de teléfono
   - Cómo probar Pro: cuenta sandbox de App Store, comprar el anual
   - HealthKit: lectura de workouts/FC, escritura del workout al
     terminar. Location: la ruta del mapa durante la carrera
   - Eliminación de cuenta: Perfil → Cuenta Maratonia → Eliminar cuenta
6. Precio: **Gratis con compras dentro de la app** (no "Gratis" a secas)
7. Adjuntar los dos productos de FASE 4b a esta versión
8. Disponibilidad: todos los países (o los que quieras) **[VOS]**
9. **Enviar para revisión**

---

## Checklist de la carrera de validación (Apple Watch solo)

Lo que hay que mirar en la corrida antes de enviar:

- [ ] **Ritmo actual estable** a ritmo constante — sin saltar ±30 s/km
      sin motivo
- [ ] **Cero valores absurdos** (nada de 2:00/km). Si el GPS se
      degrada, el número queda quieto y después pasa a `--:--`: eso es
      correcto, no un fallo
- [ ] Acelerar 15-20 s a propósito → el número sigue la tendencia en
      ~10 s
- [ ] El coach solo corrige con desvío **real y sostenido**
- [ ] Pausa manual → reanudar: el ritmo tarda ~15 s en volver (warm-up
      esperado)
- [ ] Avisos por km y cambios de tramo, normales
- [ ] Al terminar: distancia/tiempo/ritmo promedio **coinciden con la
      app Fitness de Apple**
- [ ] En el iPhone, abrir esa carrera: **splits, ritmo por km, FC y
      elevación** (probar también con una carrera vieja)
- [ ] **El recorrido pintado por ritmo** y, si hubo desnivel, el
      selector Ritmo/Desnivel (build 76 — sin verificar visualmente
      todavía)
- [ ] **Compartir la carrera** y mirar la postal como la va a ver
      alguien en redes: degradado, leyenda y contexto del plan
- [ ] Una carrera VIEJA (de antes del build 76) sigue abriendo bien: no
      tiene ritmo por punto guardado y el recorrido se pinta liso, que
      es el comportamiento correcto

---

## Riesgos declarados (que Apple no ve, pero vos sí deberías saber)

0. **Guideline 5.1.1(v) — cuenta obligatoria.** Es el riesgo más alto de
   rechazo de todo el envío. La app no deja pasar sin cuenta, y correr
   con un plan es algo que técnicamente funcionaría en local. Si Apple
   objeta, hay dos salidas y conviene tenerlas pensadas ANTES: volver a
   habilitar el salteo (el código de `BienvenidaView` ya existe y toma
   `permiteSaltear: true`), o argumentar la sincronización entre iPhone
   y Watch. La primera es cuestión de horas; la segunda puede costar una
   ronda entera de revisión.

1. **Auto-resume de la auto-pausa**: sin validar. Mitigado — la
   auto-pausa viene APAGADA por defecto. Si la encendés, puede no
   reanudar sola.
2. **Coach**: DESPLEGADO y activo en el build. Los riesgos ahora son
   los de una función con costo por uso en producción: el rate limit por
   usuario/día y el gate de Pro (402 para Free) son lo único entre un
   bug y una factura de OpenAI. Mirar los logs de Functions después de
   los primeros días.
3. **Contenido deportivo**: los planes de 21K/42K tienen metodología
   citada (`METODOLOGIA.md`) pero **ningún corredor los completó
   todavía**. No los promociones como "probados".
4. **StoreKit**: ACTIVO, con dos suscripciones auto-renovables. Sin los
   productos creados en App Store Connect el paywall se ve vacío — ver
   FASE 4b. Y una suscripción mal configurada no se arregla con un build
   nuevo: se arregla en la consola, pero recién en la próxima revisión.
5. **El mapa de calor del recorrido** (build 76) se subió sin
   verificación visual con datos reales: en el simulador no se puede
   inyectar una ruta en Salud. La lógica tiene 13 tests; lo que no está
   probado es cómo se ve sobre Apple Maps.

---

## Después de enviar

- Apple suele responder en 24-48 h.
- Si rechazan: el motivo llega por App Store Connect. Los rechazos
  típicos para una app así son HealthKit (usos no declarados) o
  eliminación de cuenta (ya implementada, Perfil → Cuenta → Eliminar).
- Con la app aprobada, recién ahí tiene sentido pensar en el Coach, el
  free/pro y el resto.
