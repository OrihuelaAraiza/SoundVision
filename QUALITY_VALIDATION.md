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

## Límites

La compilación del paquete **no equivale a ejecución de XCTest**. El primer
intento quedó detenido preparando recursos del simulador, que mostró pantalla
negra. La revisión visual de la app y la interacción espacial no están aprobadas.
Un segundo intento con `test-without-building` se interrumpió tras 120 segundos
sin registrar casos ejecutados ni producir un paquete de resultados legible.

Las pruebas `QualityRegressionTests` añaden comprobaciones de geometría RealityKit,
ondas, conexiones silenciadas, reducción de movimiento, historial y recuperación.
Su ejecución en un runtime operativo sigue pendiente, junto con los escenarios
de hardware de `DEVICE_TEST_CHECKLIST.md`.

No se ha medido HRTF, mezcla final, ergonomía ni rendimiento con RealityKit Trace
en un Vision Pro físico. Tampoco se ha firmado, instalado en hardware, publicado
ni distribuido esta versión.
