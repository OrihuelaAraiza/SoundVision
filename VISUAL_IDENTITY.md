# Identidad espacial de SoundVision

SoundVision no representa una canción como línea de tiempo: la representa como
un grafo musical tridimensional. Cada sonido es un organismo, las conexiones
definen el recorrido de reproducción y la geometría funciona como partitura.

## Gramática espacial

| Transformación | Parámetro musical |
|---|---|
| Distancia horizontal entre nodos | Duración antes de continuar por el grafo |
| Altura | Pitch, de grave a agudo |
| Profundidad respecto al usuario | Volumen, de lejano a cercano |
| Rotación X | Reverb |
| Rotación Y | Delay |
| Rotación Z | Distorsión |

Los rangos se centralizan en `SpatialParameterMapper`, de modo que puedan
calibrarse después de probarlos físicamente sin modificar gestos ni audio.

## Flujo de composición

1. La experiencia comienza con un único núcleo **Play**.
2. Arrastrar desde el núcleo extrae un nuevo organismo sonoro. Existe también
   un botón de respaldo para simulador y accesibilidad.
3. El nodo nace conectado al origen y se puede mover o rotar libremente.
4. Seleccionar **Conectar** en un nodo y después tocar otro crea una conexión
   dirigida adicional.
5. Play recorre el grafo desde el núcleo. Los ciclos se visitan una vez por
   sesión para evitar reproducción infinita accidental.

## Respuesta visual

- El hover privado de visionOS resalta automáticamente el objeto observado sin
  exponer a la app datos crudos de eye tracking.
- Un pinch selecciona el nodo y abre su inspector musical.
- El nodo que emite sonido brilla, escala y genera una onda.
- Su conexión se ilumina y el núcleo responde a la actividad total.
- Los nodos inactivos pierden saturación, movimiento y conexión visible.

## Arquitectura

- `SoundVisionMaterials` y `NodeVisualStyle`: lenguaje visual.
- `NodeEntityFactory` y `NodeAnimationSystem`: organismos e interacción.
- `TransportNodeFactory`: origen Play del grafo.
- `ConnectionLineSystem`: conexiones dirigidas dinámicas.
- `SpatialParameterMapper`: traducción geometría-sonido.
- `GraphTransport`: recorrido musical y prevención de ciclos.
- `AudioEngineManager`: pitch, reverb, delay y distorsión con AVAudioEngine.

La siguiente calibración debe hacerse en Vision Pro: sensibilidad del drag,
rangos cómodos de altura/profundidad, legibilidad del inspector y carga gráfica.
