# 📦 Paquete de lanzamiento — App Store

Todo lo que hay que cargar en App Store Connect, listo para copiar y pegar.

## Ficha del App Store

**Nombre**: Maratonia

**Subtítulo** (máx. 30 caracteres):
`Corré con tu propio entrenador`

**Categoría**: Salud y forma física (secundaria: Deportes)

**Descripción**:

```
Tu música, tus avisos y un entrenador de ritmo — todo en tu Apple Watch,
para correr sin llevar el teléfono.

ARMÁ TU PLAN EN EL IPHONE
• Importá tu música y ordenala como quieras
• Creá avisos por voz a los minutos que vos definas: "tomá agua",
  "comé un gel", "date vuelta"
• Elegí un plan de entrenamiento sugerido o armá el tuyo por tramos,
  con rango de ritmo objetivo (ej. 3 km entre 5:00 y 5:30)

CORRÉ CON EL RELOJ SOLO
• Play y listo: la música suena, los avisos llegan por voz, vibración
  y notificación — la música se pausa mientras te habla y sigue después
• El entrenador te anuncia cada tramo y te corrige en el momento:
  "vas a 5:45, apurá un poco"
• Splits por kilómetro cantados, pulso en vivo y zonas cardíacas
• ¿Preferís Spotify? Modo "música de otra app": los avisos le bajan
  el volumen mientras hablan

TODO QUEDA REGISTRADO
• Tu carrera se guarda en Apple Salud con frecuencia cardíaca,
  calorías y el recorrido dibujado en el mapa
• Revisá tu historial completo en el iPhone: mapa, ritmo promedio,
  FC y parciales

PENSADA PARA CORRER DE VERDAD
• Funciona sin señal y sin iPhone encima
• La pausa congela todo de un toque: música, avisos, entrenamiento y GPS
• Sin cuentas, sin publicidad, sin servidores: tus datos no salen
  de tus dispositivos
```

**Palabras clave** (máx. 100 caracteres):
`correr,running,maraton,entrenador,ritmo,pace,avisos,musica,reloj,entrenamiento,carrera,splits`

**URL de soporte**: la página del repositorio o un perfil público
(ej. `https://github.com/pipeveiga`) — debe existir antes del envío.

**URL de política de privacidad**: publicar el contenido de `PRIVACIDAD.md`
en una página pública (GitHub Pages, Notion público o similar) y pegar acá
esa URL. **Obligatoria** por usar HealthKit y ubicación.

## Formulario "App Privacy" (privacidad de datos)

- **¿Recolectás datos de esta app?** → **No** ("Data Not Collected").
  Justificación: la app no tiene servidores; salud y ubicación se procesan
  en el dispositivo y se guardan en Apple Salud del usuario. Nada se envía
  al desarrollador ni a terceros.

## Clasificación por edad

Cuestionario: todo "No" → resultado 4+.

## Notas para el revisor (App Review Notes)

```
Maratonia es una app de running para Apple Watch con companion de iPhone.

Para probar el flujo completo hace falta un Apple Watch pareado:
1. En el iPhone: importar un MP3 (o usar solo avisos), crear un aviso
   y/o elegir un plan sugerido, tocar "Enviar al reloj".
2. En el watch: tocar Play. La música/avisos funcionan en background
   (background mode audio). Con "Registrar carrera" activado se inicia
   una HKWorkoutSession (por eso los permisos de HealthKit) y con
   "Ruta GPS" se usa CoreLocation para dibujar el recorrido en el mapa
   del entrenamiento (por eso el permiso de ubicación).
3. La app no requiere cuenta, no tiene compras ni publicidad, y no
   envía datos fuera del dispositivo.
```

## Capturas de pantalla (pendiente — sacarlas de dispositivos reales)

- iPhone (6,9" — el tuyo sirve): 1) pantalla principal con plan armado,
  2) "Mis carreras" con el mapa, 3) editor de tramos, 4) tutorial.
- Apple Watch: 1) métricas en carrera (ritmo/zona), 2) lobby con Play,
  3) panel PLAN. (Captura en el watch: corona + botón lateral a la vez;
  aparecen en Fotos del iPhone.)

## Checklist del día del envío

1. [ ] Publicar PRIVACIDAD.md en una URL pública y cargarla en App Information
2. [ ] Nombre "Maratonia" + subtítulo + descripción + keywords cargados
3. [ ] Capturas de iPhone y Watch subidas
4. [ ] App Privacy: "Data Not Collected"
5. [ ] Clasificación por edad completada (4+)
6. [ ] Build final seleccionado en la versión 1.0
7. [ ] Notas para el revisor pegadas
8. [ ] Precio: Gratis · Disponibilidad: todos los países (o los que quieras)
9. [ ] "Submit for Review" 🚀
