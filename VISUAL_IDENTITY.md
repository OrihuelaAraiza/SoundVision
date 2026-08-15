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
   un cajón visible de instrumentos: tocar añade al centro y arrastrar permite
   elegir la posición inicial. El gesto desde Play se conserva como atajo.
3. El nodo nace conectado al origen y se puede mover o rotar libremente.
4. Seleccionar **Conectar** en un nodo y después tocar otro crea una conexión
   dirigida adicional.
5. Play agenda el grafo completo contra el reloj de audio. Todas las conexiones
   salientes se reproducen simultáneamente y sus voces se mezclan.
6. Los ciclos son musicales: el control **Loops** permite entre una y ocho
   vueltas por conexión, con un límite global de seguridad para grafos grandes.

## Respuesta visual

- El hover privado de visionOS resalta automáticamente el objeto observado sin
  exponer a la app datos crudos de eye tracking.
- Cada nodo muestra un readout espacial breve con nombre, pitch y volumen; la
  mirada lo enfatiza junto al organismo sin convertirse en estado observable.
- Un pinch selecciona el nodo y abre su inspector musical.
- El nodo que emite sonido brilla, escala y genera una onda.
- La selección activa motas sutiles; un ataque aumenta densidad, tamaño y giro.
- Su conexión se ilumina y el núcleo responde a la actividad total.
- Tres cintas orbitales alrededor de Play se deforman en GPU según reproducción
  y cantidad de voces, creando una firma visual continua sin video precocinado.
- Los nodos inactivos pierden saturación, movimiento y conexión visible.

## Arquitectura

- `SoundVisionMaterials` y `NodeVisualStyle`: lenguaje visual.
- `NodeEntityFactory` y `NodeAnimationSystem`: organismos e interacción.
- `TransportNodeFactory`: origen Play del grafo.
- `SpatialSceneLayout`: altura física del lienzo y mapeo del drop 2D al grafo 3D.
- `ConnectionLineSystem`: conexiones dirigidas dinámicas.
- `ParticleEffectSystem`: emisores RealityKit y atlas animado 4 × 4.
- `MetalEnergyFieldSystem` + `EnergyRibbons.metal`: `LowLevelMesh` y deformación GPU.
- `SpatialParameterMapper`: traducción geometría-sonido.
- `GraphTransport`: timeline concurrente, bifurcaciones y loops acotados.
- `AudioEngineManager`: fuentes RealityKit Spatial Audio ligadas a las entidades,
  generadores mono a 48 kHz y scheduling compartido por host time.

## Campo sonoro

- Cada organismo es también una fuente acústica 3D en su posición visual real.
- RealityKit resuelve HRTF personalizado, movimiento de cabeza, distancia y
  respuesta acústica del entorno.
- Pitch se sintetiza directamente a la frecuencia solicitada; delay y
  distorsión se procesan en el generador, y reverb usa el envío espacial nativo.
- Todas las fuentes parten de una señal mono para evitar artefactos antes de la
  espacialización, siguiendo la recomendación de Apple.

La siguiente calibración debe hacerse en Vision Pro: sensibilidad del drag,
rangos cómodos de altura/profundidad, legibilidad del inspector, tamaño aparente
de partículas y estabilidad de frame time con bifurcaciones activas.
