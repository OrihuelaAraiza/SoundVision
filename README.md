# SoundVision

**Surgery of Sound** es un prototipo nativo para Apple Vision Pro que convierte
un secuenciador musical en una escultura 3D interactiva.

## Prototipo actual

- Ventana SwiftUI y `ImmersiveSpace` mixto.
- Aro de 16 pasos y ocho nodos RealityKit diferenciados por forma y color.
- Activación por tap/pinch, play/pausa, BPM de 70 a 160 y pulso visual.
- Ocho timbres sintetizados localmente con `AVAudioEngine` (sin assets externos).
- Guardado y carga de la composición como JSON local.
- Pruebas unitarias para el patrón, timing y persistencia.
- Identidad visual modular generada por código: nodos compuestos, núcleo
  reactivo, conexiones, ondas e interpolación del pulso.

La dirección artística y sus decisiones están documentadas en
[`VISUAL_IDENTITY.md`](VISUAL_IDENTITY.md).

## Ejecutar

1. Abre `SoundVision.xcodeproj` en Xcode 26 o posterior.
2. Selecciona un destino Apple Vision Pro (simulador o dispositivo).
3. Ejecuta el esquema `SoundVision` y pulsa **Iniciar sesión**.

El simulador valida la escena y la interacción básica. La percepción espacial,
ergonomía, audio y comodidad deben validarse también en un Apple Vision Pro real.
