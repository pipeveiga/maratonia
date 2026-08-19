# Estados del Coach (P1 UX)

Capturas de los estados principales del Coach después del pase a
"herramienta de decisión": encabezado en una línea, salidas tocables, y
el porqué plegado en un disclosure.

| Archivo | Estado | Qué se está mirando |
|---|---|---|
| `1-elegir-dia.png` | Hay días válidos | La pregunta ES el titular y se contesta con un toque. Un chip por día de la semana, más "Otro día" para escribirlo. |
| `2-sin-dia-libre.png` | No hay ningún día válido | El titular es la mala noticia en una línea. Cada salida es una tarjeta con su consecuencia; "Dejarlo como está" queda de secundario. |
| `3-fuera-de-dominio.png` | Consulta fuera del dominio | Una línea y tres chips que enrutan a la acción real (no rellenan texto a ciegas). |
| `4-propuesta.png` | Propuesta lista para confirmar | El titular es el cambio (`Mover X al lun 17`), el ANTES → DESPUÉS es una fila, y el párrafo del modelo vive en "Ver por qué". |
| `5-aplicado.png` | Aplicado | Confirmación de una línea. |

## Cómo se regeneran

Las produce `CapturasCoachTests` con `ImageRenderer`, contra el dominio
REAL: las opciones salen de `BuscadorDeAlternativas` y pasaron por
`ValidadorDeCoach`, así que no hay textos de mentira.

```
xcodebuild test -scheme Maraton \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.5' \
  -only-testing:MaratonTests/CapturasCoachTests \
  -parallel-testing-enabled NO \
  -testLanguage es -testRegion AR
```

`-parallel-testing-enabled NO` **no es opcional**: con clonado, los PNG
quedan en un simulador temporal que se destruye al terminar. La ruta de
salida se imprime al final del test (`tmp/coach-ux` del contenedor de la
app). Con `-testLanguage en` se revisa la traducción.

También hay un catálogo navegable en el simulador, con el motor real:

```
xcrun simctl launch <dispositivo> com.pipeveiga.maraton -verCoachConversacion 1
```
