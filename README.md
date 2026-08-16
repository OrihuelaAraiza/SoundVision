# SoundVision

**Surgery of Sound** es un prototipo nativo para Apple Vision Pro que convierte
una composición musical en un grafo 3D interactivo.

## Prototipo actual

- Ventana SwiftUI y `ImmersiveSpace` mixto.
- Núcleo Play desde el que se extraen y conectan organismos sonoros.
- Manipulación 3D: posición y rotación controlan pitch, volumen, duración y efectos.
- Conexiones dirigidas libres con bifurcaciones simultáneas y loops acotados.
- Scheduling sample-accurate mediante generadores mono a 48 kHz.
- RealityKit Spatial Audio por nodo: HRTF personalizado, seguimiento espacial,
  acústica ambiental y atenuación de distancia administrados por Apple.
- Ocho timbres sintetizados localmente (sin muestras de audio externas).
- Guardado y carga de la composición como JSON local.
- Pruebas unitarias para el patrón, timing, bifurcaciones, ciclos y persistencia.
- Identidad visual modular: nodos compuestos, núcleo reactivo, conexiones y ondas.
- Campo orbital `LowLevelMesh` deformado por un kernel Metal en tiempo real.
- Partículas RealityKit con atlas original animado, ligadas a selección y audio.
- Animación a la tasa de refresco de RealityKit mediante `System`, no a la
  cadencia de un `TimelineView`.

## Arquitectura de la interfaz

El espacio inmersivo contiene **solo** la escultura sonora y sus gestos. Todos
los controles viven en la ventana principal, que se convierte en la consola del
estudio al entrar. Es una ventana normal de visionOS: el sistema le da su barra
de movimiento, la persona la coloca donde quiera y ahí se queda.

Una versión anterior anclaba los paneles a la cabeza con `AnchorEntity(.head)`.
Eso los volvía inusables —seguían el giro de la cabeza, así que nunca podías
mirarlos de frente— y obligó a inventar asas **MOVER**, ajustes de distancia y
un botón de **Recentrar**. Nada de eso hace falta con una ventana del sistema, y
además los diálogos de confirmación solo se presentan desde una ventana: dentro
de un `ImmersiveSpace` no aparecían nunca.

La dirección artística y sus decisiones están documentadas en
[`VISUAL_IDENTITY.md`](VISUAL_IDENTITY.md).

La sesión de validación en hardware está preparada en
[`DEVICE_TEST_CHECKLIST.md`](DEVICE_TEST_CHECKLIST.md).

## Ejecutar

1. Abre `SoundVision.xcodeproj` en Xcode 26 o posterior.
2. Selecciona un destino Apple Vision Pro (simulador o dispositivo).
3. Ejecuta el esquema `SoundVision` y pulsa **Iniciar sesión**.

El proyecto compila shaders Metal. Si una instalación nueva de Xcode no incluye
el componente, instálalo desde **Xcode > Settings > Components > Metal Toolchain**
o con `xcodebuild -downloadComponent MetalToolchain`.

Para una prueba guiada, pulsa **Abrir demo espacial**. La app carga cinco
fuentes distribuidas alrededor del usuario y muestra una guía paso a paso en la
consola.

Para componer desde cero, pulsa **Nueva pista** y usa **Añadir sonido** en la
consola. También puedes tirar del núcleo Play dentro del espacio para extraer un
organismo nuevo en el punto donde sueltes.

Dentro del espacio inmersivo, el pinch selecciona un nodo, arrastrarlo lo mueve
(conservando el punto de agarre) y girarlo con dos manos ajusta reverb, delay y
distorsión. Si la consola te estorba, muévela con la barra inferior que le da
visionOS o ciérrala; la escultura sigue funcionando.

El simulador valida la escena y la interacción básica. La percepción espacial,
ergonomía, audio y comodidad deben validarse también en un Apple Vision Pro real.
