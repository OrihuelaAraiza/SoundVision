# SoundVision

**Surgery of Sound** es un prototipo nativo para Apple Vision Pro que convierte
una composición musical en un grafo 3D interactivo.

## Prototipo actual

- Ventana SwiftUI y `ImmersiveSpace` mixto.
- Núcleo Play desde el que se extraen y conectan organismos sonoros.
- Manipulación 3D: posición y rotación controlan pitch, volumen, duración y efectos.
- Conexiones dirigidas libres con reproducción visual del grafo.
- Ocho timbres sintetizados localmente con `AVAudioEngine` (sin assets externos).
- Guardado y carga de la composición como JSON local.
- Pruebas unitarias para el patrón, timing y persistencia.
- Identidad visual modular generada por código: nodos compuestos, núcleo
  reactivo, conexiones y ondas.

La dirección artística y sus decisiones están documentadas en
[`VISUAL_IDENTITY.md`](VISUAL_IDENTITY.md).

## Ejecutar

1. Abre `SoundVision.xcodeproj` en Xcode 26 o posterior.
2. Selecciona un destino Apple Vision Pro (simulador o dispositivo).
3. Ejecuta el esquema `SoundVision` y pulsa **Iniciar sesión**.

El simulador valida la escena y la interacción básica. La percepción espacial,
ergonomía, audio y comodidad deben validarse también en un Apple Vision Pro real.
