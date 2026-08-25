# SoundVision

**Surgery of Sound** es un prototipo nativo para Apple Vision Pro que convierte
una composición musical en un grafo 3D interactivo.

## Prototipo actual

- Ventana SwiftUI y `ImmersiveSpace` mixto.
- Núcleo Play con una única salida hacia el primer organismo sonoro.
- Manipulación 3D: posición y rotación controlan pitch, volumen, duración y efectos.
- Conexiones dirigidas libres con bifurcaciones simultáneas y loops acotados.
- Voces persistentes: cada organismo tiene su generador de audio vivo desde que
  nace, y reproducir consiste solo en publicarle tiempos de ataque.
- Scheduling sample-accurate mediante generadores mono, con la tasa real medida
  a partir de los propios timestamps del render.
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
consola. El primero será la única entrada desde Play; los siguientes aparecen
libres para que decidas cómo conectarlos entre sí.

## Cómo el espacio se convierte en música

El espacio 3D no es decorado: cada eje controla un parámetro distinto, y esa es
la idea central del proyecto.

| Eje | Parámetro |
|---|---|
| Vertical | **Nota.** La altura salta entre grados de una escala pentatónica menor, ~11 cm por nota. |
| Adelante · atrás | **Volumen.** Acercar un organismo lo hace sonar más presente. |
| Distancia horizontal entre dos organismos | **Duración.** El primero sostiene hasta que arranca el segundo. |
| Rotación X · Y · Z | **Reverb · delay · distorsión.** |

La afinación se cuantiza a propósito. Con semitonos continuos, un organismo podía
quedar a +7.3 semitonos y la pieza entera sonaba microtonal por muy buena que
fuese la síntesis. La pentatónica es la escala en la que casi cualquier
combinación suena bien junta, así que colocar organismos a ojo produce música.

**La síntesis es en tiempo real.** Mover un organismo mientras la música suena
cambia su afinación al instante, deslizándose hasta la nueva nota en vez de
saltar. Girarlo barre sus efectos en vivo. Una versión anterior horneaba cada
nota entera al pulsar Play, lo que hacía imposible por construcción que la mano
afectara a lo que ya estaba sonando: el sonido ya estaba escrito.

El motor vive en [RealtimeVoice.swift](SoundVision/Audio/RealtimeVoice.swift) y
respeta las reglas del hilo de audio: ni una asignación, ni un lock, ni una
llamada transcendental por muestra. Fases, línea de delay y tiempos de ataque
ocupan memoria reservada una sola vez, y los parámetros vivos cruzan desde el
hilo principal como escalares independientes que se leen una vez por bloque.

### Por qué Play sí suena

**La voz de un organismo vive mientras vive el organismo.** Se engancha a su
entidad en cuanto nace y desde ahí rinde siempre, aunque sea silencio; Play solo
publica tiempos de ataque en su agenda.

Antes las voces se creaban al pulsar Play y se destruían al detener. La línea de
tiempo se fechaba contra el reloj del sistema *antes* de engancharlas, así que
enganchar tenía que caber en el margen previsto. En el simulador cabía. En el
dispositivo, con el grafo de audio todavía frío, no siempre: los primeros
ataques quedaban en el pasado, el render los descartaba por estar fuera de
ventana y la reproducción entera podía transcurrir en silencio mientras las
animaciones seguían su curso, sin ningún error que lo explicara.

La agenda cruza al hilo de audio por [VoiceSchedule.swift](SoundVision/Audio/VoiceSchedule.swift):
cuatro losas fijas y un estado atómico que dice cuál está publicada. El hilo
principal rota la losa antes de publicar, de modo que una lectura en vuelo no ve
una agenda a medio escribir, y nada de esto reserva memoria ni toma un lock.
Detener no vacía la agenda: marca un instante de corte y la cola se desvanece en
12 ms, porque truncar la onda a mitad de ciclo se oye como un chasquido.

La app también configura y activa explícitamente su `AVAudioSession`. No lo
hacía, y la categoría por defecto es otra de las explicaciones clásicas de
"pulso Play, veo la animación y no oigo nada" en hardware real.

Cuando algo va mal, la pestaña **Reproducir** lo dice: cuántas voces hay
enganchadas, de qué reloj se fían, a qué tasa rinden, qué pico están sacando y
por qué salida. "No suena" tiene media docena de causas distintas y esa línea
las separa sin tener que quitarse el visor.

La distancia horizontal gobierna las dos caras del tiempo: cuándo entra el
siguiente organismo y cuánto sostiene el anterior. Separar dos organismos alarga
la nota; juntarlos la vuelve staccato. Los percusivos son la excepción: un golpe
es un golpe y no se estira por alejarlo.

## Qué ves cuando suena

Cada ataque lanza una **onda que se expande y se desvanece**, y varias conviven:
en un pasaje rápido se ven salir una tras otra. Antes era una sola esfera que
aparecía y desaparecía de golpe, lo que se leía como parpadeo y no como sonido
emitido.

Mirar un organismo lo **enciende con su propio color** en vez del resaltado
genérico del sistema. Conviene saber por qué funciona así: **visionOS nunca le
dice a la app hacia dónde miras**. Es una garantía de privacidad, no una API que
falte. El resaltado lo dibuja el sistema por su cuenta, fuera del proceso de la
app, que jamás se entera.

Por eso la información del organismo aparece al **seleccionarlo** con un pinch,
no al mirarlo: mostrar texto requiere que la app sepa qué estás mirando, y no
puede. La etiqueta permanece oculta el resto del tiempo — ocho etiquetas a la
vez llenaban el espacio de texto que nadie leía. Revelarla con la mirada sin
romper esa garantía es posible con `HoverEffectComponent(.shader(...))`, donde
la GPU reacciona al hover por su cuenta, pero exige materiales ShaderGraph
authorizados en Reality Composer Pro; queda pendiente.

## Gestos

Todo lo que construye la música se hace con las manos, dentro del espacio:

| Gesto | Resultado |
|---|---|
| Pinch sobre un organismo | Lo selecciona. Repetirlo lo suelta. |
| Arrastrar su cuerpo | Lo mueve: altura → pitch, profundidad → volumen. |
| Arrastrarlo con **sonido fijo** | Solo lo recoloca, sin tocar su sonido. |
| **Tirar del punto luminoso de abajo** | **Traza un hilo. Suéltalo sobre otro organismo para conectarlos.** |
| Pinch sobre una conexión | La corta. |
| Girar con dos manos | Reverb, delay y distorsión. |
| Pinch sobre el núcleo Play | Reproduce o detiene. |
| Tirar del núcleo Play | Extrae el primer organismo solo si Play aún no tiene entrada. |

Conectar no requiere entrar en un modo: se tira de un hilo y se suelta donde
quieras. Mientras está en el aire, el destino candidato se ilumina. El inspector
también ofrece **Conectar hacia…** como alternativa precisa cuando la puntería
espacial no resulte cómoda.

### De dónde nace cada sonido

Play es una entrada, no un distribuidor: solo puede iniciar un organismo. El
primero que añadas se conecta automáticamente; todos los siguientes aparecen
libres. La persona construye la frase enlazándolos con el hilo espacial o con
**Conectar hacia…** en el inspector. Seleccionar un organismo nunca crea ni
cambia conexiones por su cuenta.

Un organismo al que Play no llega por ningún camino no suena. El inspector lo
avisa en naranja y pide unirlo desde una rama alcanzable. Solo cuando Play quedó
sin entrada —por ejemplo, tras cortar esa conexión— permite convertir un
organismo en la nueva entrada; nunca crea un segundo inicio.

La consola se organiza en tres pestañas —**Reproducir**, **Sonidos** y
**Nodo**— para que cada pantalla quepa entera. En una sola columna con scroll,
entre botones y sliders de ancho completo casi no quedaba zona neutra donde
agarrar para desplazarla.

Si arrastrar con la mano se te resiste, la pestaña **Nodo** tiene sliders de
posición por eje. Es la vía exacta para ordenar el grafo sin pelearse con la puntería a
un metro de distancia.

### Ordenar sin desafinar

La posición controla el sonido, lo que hacía imposible acomodar el grafo sin
rehacer la composición: cualquier intento de ordenar desafinaba. Cada organismo
tiene ahora un candado de **sonido fijo** en el inspector. Cerrado, moverlo solo
lo recoloca —pitch, volumen y la duración de sus conexiones quedan congelados— y
aparece un pedestal bajo el organismo para que se vea cuáles están fijos.

Ninguna acción destructiva pide confirmación. En su lugar, la consola mantiene
**Deshacer** disponible con el nombre de lo último que hiciste, así que cortar
una conexión o vaciar el lienzo nunca es un callejón sin salida.

Si la consola te estorba, muévela con la barra inferior que le da visionOS o
ciérrala; la escultura sigue funcionando.

El simulador valida la escena y la interacción básica. La percepción espacial,
ergonomía, audio y comodidad deben validarse también en un Apple Vision Pro real.
