# SoundVision · validación de fiabilidad y comodidad

Fecha: 10 de septiembre de 2026.

## Implementación

- Historial separado, transacciones de gestos, Deshacer/Rehacer y conservación
  del transporte durante ajustes sonoros. Ediciones sin cambios no consumen pasos.
- Distribución determinista para 32 organismos, con envolventes por timbre y
  espacio reservado para Play. Las posiciones existentes permanecen intactas.
- Volumen suavizado en el generador, incluido cero exacto y silencio independiente.
- Eventos de ataque separados del estado iluminado y origen temporal compartido
  por la agenda de audio, las ondas y la preescucha.
- Recuperación automática con copia anterior válida, guardado manual independiente
  y restauración de práctica, composición original e historial.
- Direcciones y tiempos contextuales, conexiones silenciadas visibles, anticipación
  del gesto, guía inicial, feedback específico en prácticas y texto adaptable.
- Reducir movimiento conserva selección y pulsos de material; elimina movimiento
  decorativo, ondas expansivas, partículas y deformación del campo Metal.
- Operaciones de entidades y sistemas visuales aisladas al actor principal. El
  callback de audio mantiene sus parámetros atómicos y memoria preasignada.

## Evidencia ejecutada

`Scripts/validate-core.sh`: **44 grupos PASS**. Compila archivos de producción y
ejecuta el renderizador; no utiliza un motor de audio simulado para declarar que
RealityKit funciona. Incluye los 24 timbres, ramas, convergencias, ciclos, edición
en vivo y nuevas regresiones:

- Un gesto → un Deshacer → un Rehacer, sin perder identidad ni reiniciar Play.
- Controles sin cambios, invalidación de Rehacer, silencio, candado, tempo y ciclos.
- 32 cuerpos grandes separados, borrado y reposición.
- Autoguardado tras un segundo, recuperación de lecciones e historial original,
  cierre durante un gesto, Play deliberadamente libre y archivos incompletos.
- Cero exacto, subir volumen conservando la agenda, silencio independiente y
  ausencia de transitorio al poner cero antes de Play.
- Inicio diferido compartido y ataques visuales distintos separados por menos
  de 280 ms.
- Coincidencia entre dirección anticipada y conexión efectiva, guía por acciones
  y mensajes que identifican la afinación incorrecta.

La app y el paquete XCTest compilan para visionOS Simulator. La app también
compila para el destino genérico Vision Pro sin firma. Ambas compilaciones usan
`SWIFT_STRICT_CONCURRENCY=complete` y no emiten advertencias del código del proyecto.
Las herramientas de Xcode sí emiten avisos de metadatos App Intents no utilizados
y bibliotecas XCTest ya firmadas.

## XCTest ejecutado en visionOS Simulator

Sí hay ejecución, y con resultado: **115 pruebas en visionOS 26.5 Simulator**
(`-parallel-testing-enabled NO`; con clonado en paralelo la preparación del
simulador tarda ~15 min antes del primer caso). Fallan **4 casos**, los mismos
antes y después del cambio de indicadores de efecto —comprobado ejecutando la
misma selección sobre un worktree en `HEAD`—, así que son deuda previa y no
regresiones:

| Caso | Qué mide | Por qué falla |
|---|---|---|
| `LayoutFitTests.testAxisTitlesFitTheirColumn` | Ancho de "Izquierda · Derecha" en la columna de 116 pt | Mide 112.26 pt y la prueba exige 109.04 (116 × 0.94) |
| `LayoutFitTests.testSpatialReadoutFitsItsFrame` | Etiqueta 3D en su marco de 0.58 m | "Hi-hat abie…" y "Piano eléct…" miden 0.5885 m |
| `MusicalMappingTests.testNotesEndSilentlyAndTonalOnesFadeIn` | Amplitud al inicio de la nota | 13–14 timbres superan el umbral de 0.05; el conjunto cambia entre ejecuciones, así que el umbral o la medida no son deterministas |
| `QualityRegressionTests.testPlacementBoundsContainEveryAnimatedBody` | Cuerpo animado dentro de su radio de colocación | `tom: accent` llega a 0.40 con radio 0.36; `fx: node-core` y `fragment-3` llegan a 0.46 con radio 0.44 |

Ninguno toca los faders, el indicador de efectos ni el gesto de precisión: esas
nueve pruebas de `SpatialEffectGizmoTests` pasan, incluido el despeje del pomo
frente al conector en los 24 timbres y en los dos extremos y el centro de su
recorrido.

## Límites

La revisión visual de la app y la interacción espacial no están aprobadas: los
cuatro casos anteriores siguen abiertos y los escenarios de hardware de
`DEVICE_TEST_CHECKLIST.md` —incluida la lectura real de los faders y de las
barras de efecto sobre el cuerpo— siguen pendientes de un Vision Pro físico.

No se ha medido HRTF, mezcla final, ergonomía ni rendimiento con RealityKit Trace
en un Vision Pro físico. Tampoco se ha firmado, instalado en hardware, publicado
ni distribuido esta versión.
