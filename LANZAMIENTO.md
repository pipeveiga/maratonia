# 📦 LANZAMIENTO — Checklist de envío a la App Store

Paso a paso, en orden, con los textos listos para copiar y pegar.
Los campos marcados **[VOS]** requieren un dato o una decisión tuya.

> Ficha completa en `APP_STORE.md` · Privacidad en `PRIVACIDAD.md`
> Este archivo es el ORDEN de ejecución; ese otro es el contenido.

---

## FASE 0 — Antes de tocar App Store Connect

- [ ] Build 59 compila sin warnings en Xcode (Product → Build)
- [ ] Los 211 tests en verde (Product → Test)
- [ ] Recorrer las 5 pestañas en **español**
- [ ] Cambiar el iPhone a **inglés** y recorrerlas de nuevo (build 58
      cerró el barrido: no debería quedar nada en español)
- [ ] **Una carrera real con el Apple Watch** validando el ritmo en
      vivo (ver checklist física abajo)
- [ ] `https://maratonia.site/privacy/` y `/support/` cargando **[VOS]**

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

> Si el Coach NO se activa en V1 (backend sin desplegar), no declares
> nada de OpenAI: no viaja ningún dato. **[VOS: decidir]**
> Si algún día se activa, hay que volver acá y agregar
> *Other Usage Data*.

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
5. **Notas para el revisor**: copiar el bloque "Review notes" de
   `APP_STORE.md`. Lo importante que dice: la app funciona COMPLETA sin
   cuenta, así que **no hace falta cuenta demo**
6. Precio: **Gratis**
7. Disponibilidad: todos los países (o los que quieras) **[VOS]**
8. **Enviar para revisión**

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

---

## Riesgos declarados (que Apple no ve, pero vos sí deberías saber)

1. **Auto-resume de la auto-pausa**: sin validar. Mitigado — la
   auto-pausa viene APAGADA por defecto. Si la encendés, puede no
   reanudar sola.
2. **Coach**: solo aparece con el backend desplegado. Sin desplegar, la
   sección no existe (cero riesgo de botón muerto).
3. **Contenido deportivo**: los planes de 21K/42K tienen metodología
   citada (`METODOLOGIA.md`) pero **ningún corredor los completó
   todavía**. No los promociones como "probados".
4. **StoreKit**: deliberadamente fuera de V1. No hay compras.

---

## Después de enviar

- Apple suele responder en 24-48 h.
- Si rechazan: el motivo llega por App Store Connect. Los rechazos
  típicos para una app así son HealthKit (usos no declarados) o
  eliminación de cuenta (ya implementada, Perfil → Cuenta → Eliminar).
- Con la app aprobada, recién ahí tiene sentido pensar en el Coach, el
  free/pro y el resto.
