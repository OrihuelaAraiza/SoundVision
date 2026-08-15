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
- Cajón de ocho instrumentos: toque para añadir o drag & drop para colocar.
- Flujo explícito para alternar entre **Demo espacial** y **Nueva pista**.
- Paneles RealityKit a distancia cómoda, anclados a la cabeza para permanecer
  visibles, con asas independientes, ajuste **Más cerca / Más lejos** y
  recuperación mediante **Recentrar menús**.
- Ventana de **Controles movibles** que puede recolocarse físicamente con la
  barra de ventana de visionOS cuando el usuario cambia de orientación.

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

Para una prueba guiada, pulsa **Abrir demo**. La app cargará cinco
fuentes distribuidas alrededor del usuario y abrirá una guía paso a paso dentro
del espacio inmersivo.

Para componer desde cero, pulsa **Nueva pista**. El cajón **Sonidos** aparece a
la izquierda: toca un instrumento para añadirlo en una posición segura o
arrástralo y suéltalo sobre el lienzo para decidir su posición inicial.

Cada panel tiene una zona visible **MOVER**. Mantén el pinch sobre ella y mueve
la mano para acomodarlo. Usa **Más cerca / Más lejos** para ajustar la distancia
del conjunto o el icono de mira para recuperar la distribución inicial.

Si aun así algún panel queda fuera del campo de visión, pulsa **Controles movibles**
desde la ventana principal o el icono de ventana en la barra de transporte.
Después toma la barra inferior que proporciona visionOS y coloca la ventana
frente a ti. Desde ahí puedes reproducir, cambiar de modo, añadir sonidos y
operar el nodo seleccionado.

El simulador valida la escena y la interacción básica. La percepción espacial,
ergonomía, audio y comodidad deben validarse también en un Apple Vision Pro real.
