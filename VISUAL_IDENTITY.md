# Identidad visual de SoundVision

La escena sigue una idea simple: cada sonido es un organismo y la mezcla es su
centro de energía. Toda la identidad se genera con primitivas de RealityKit,
materiales y comportamiento; no usa modelos ni texturas externas.

## Lenguaje visual

- **Estructura:** aro instrumental de 16 pasos con marcas principales en 0, 4,
  8 y 12, conectado a un núcleo de mezcla multicapa.
- **Jerarquía:** el aro y las conexiones usan tonos fríos y baja opacidad; los
  colores de instrumentos aparecen solo como acentos.
- **Estado:** un nodo inactivo pierde saturación, brillo, tamaño, conexión e
  idle. Un nodo activo recupera su color y movimiento.
- **Trigger:** el disparo produce flash, cambio de escala, onda expansiva,
  refuerzo de la conexión y respuesta del núcleo.
- **Selección:** una envolvente tenue identifica el nodo recién manipulado sin
  añadir un panel 3D dominante.

## Personalidades

| Nodo | Geometría | Movimiento |
|---|---|---|
| Kick | Esfera pesada y disco inferior | Impacto corto y amplio |
| Snare | Núcleo angular y placas laterales | Apertura seca |
| Hi-hat | Dos discos delgados | Cierre rápido y flotación ágil |
| Clap | Dos placas y punto de contacto | Las placas chocan al sonar |
| Bass | Prisma con corazón interior | Respiración lenta y pesada |
| Pad | Dos esferas translúcidas | Deriva ambiental amplia |
| Lead | Cristal vertical y haz central | Oscilación direccional |
| FX | Núcleo inclinado con fragmentos | Rotación irregular |

## Arquitectura

- `SoundVisionMaterials`: paleta y familias de materiales.
- `NodeVisualStyle`: parámetros cinéticos por tipo de sonido.
- `NodeEntityFactory`: jerarquías geométricas e interacción.
- `NodeAnimationSystem`: estado, idle y personalidad en ejecución.
- `SequencerRing` y `PulseIndicator`: lectura temporal.
- `WaveformVisualizer`: onda breve de cada trigger.
- `ConnectionLineSystem`: relación informativa nodo-núcleo.
- `CentralCoreSystem`: representación reactiva de la mezcla.

El siguiente paso visual debe basarse en pruebas dentro del visor: revisar
distancias, transparencia, contraste, comodidad y carga gráfica antes de añadir
partículas o shaders más complejos.
