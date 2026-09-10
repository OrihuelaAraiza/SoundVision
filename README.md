# SoundVision

**Surgery of Sound** es un prototipo nativo para Apple Vision Pro que convierte
una composición musical en un grafo 3D interactivo.

## Prototipo actual

- Ventana SwiftUI y `ImmersiveSpace` mixto.
- Núcleo Play con una única salida hacia el primer organismo sonoro.
- Manipulación 3D: posición y rotación controlan pitch, volumen, duración y efectos.
- Conexiones dirigidas libres con bifurcaciones simultáneas: todas las salidas
  de un organismo conservan su propia voz y suenan en la misma vuelta.
- Play repite el patrón completo de forma continua y sample-accurate hasta que
  la persona pulsa Stop; los ciclos internos del grafo permanecen acotados.
- Voces persistentes: cada organismo tiene su generador de audio vivo desde que
  nace, y reproducir consiste solo en publicarle tiempos de ataque.
- Scheduling sample-accurate mediante generadores mono, con la tasa real medida
  a partir de los propios timestamps del render.
- RealityKit Spatial Audio por nodo: HRTF personalizado, seguimiento espacial,
  acústica ambiental y atenuación de distancia administrados por Apple.
- 24 timbres sintetizados localmente: Kick, Snare, Hi-hat, Clap, Bass, Pad, Lead, FX, Tom, Shaker, Campana, Marimba, Pluck, Órgano, Rimshot, Cencerro, Conga, Woodblock, Hi-hat abierto, Piano eléctrico, Flauta, Cuerdas, Metales y Sub bass.
- Catálogo con búsqueda, favoritos locales y familias de percusión, melodía y texturas.
- Aprendizaje musical con cuatro ejercicios comprobables y progreso local.
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

Play aparece a la izquierda del eje central de la ventana, con espacio libre
entre su zona de interacción y la consola al abrir el estudio.

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
3. Ejecuta el esquema `SoundVision` y elige **Nueva pista**, **Aprender música** o **Abrir demo espacial**.

El proyecto compila shaders Metal. Si una instalación nueva de Xcode no incluye
el componente, instálalo desde **Xcode > Settings > Components > Metal Toolchain**
o con `xcodebuild -downloadComponent MetalToolchain`.

Para una prueba guiada, pulsa **Abrir demo espacial**. La app carga cinco
fuentes distribuidas alrededor del usuario y muestra una guía paso a paso en la
consola.

Para componer desde cero, pulsa **Nueva pista** y usa **Añadir sonido** en la
consola. El primero será la única entrada desde Play; los siguientes aparecen
libres para que decidas cómo conectarlos entre sí.

Para añadir una rama libre, arrastra el conector entre ella y un nodo que ya
tenga ruta desde Play: se crea la salida desde la ruta hacia la rama, empieces
por cualquiera de los extremos. Entre dos nodos que ya tienen ruta, el gesto
conserva su dirección para permitir ciclos y convergencias. **Añadir salida**
en el inspector siempre conserva la dirección explícita que indica el menú.

Si Play quedó libre, puedes arrastrar desde Play hasta un nodo existente o
desde el conector de ese nodo hasta Play. Ambos gestos conectan el nodo sin
crear otro. El inspector también muestra **Conectar a Play** cuando no hay
entrada. Si la entrada está ocupada, hay que cortar esa conexión primero.

El motor espera a que cada entidad espacial esté activa antes de engancharle
audio y vuelve a comprobar las voces pendientes. Cada sesión publica las
agendas de todas sus ramas y activa sus controladores. Durante Play, la
recuperación de una voz detenida mantiene el reloj y las agendas de las otras;
un fallo persistente muestra el nombre del sonido afectado en la consola.

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

Cuando algo va mal, la pestaña **Estudio** lo dice: cuántas voces hay
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
también ofrece **Añadir salida** como alternativa precisa cuando la puntería
espacial no resulte cómoda.

### De dónde nace cada sonido

Play es una entrada, no un distribuidor: solo puede iniciar un organismo. El
primero que añadas se conecta automáticamente; todos los siguientes aparecen
libres. La persona construye la frase enlazándolos con el hilo espacial o con
**Añadir salida** en el inspector. Seleccionar un organismo nunca crea ni
cambia conexiones por su cuenta.

Un organismo al que Play no llega por ningún camino no suena. El inspector lo
avisa en naranja y pide unirlo desde una rama alcanzable. Solo cuando Play quedó
sin entrada —por ejemplo, tras cortar esa conexión— permite convertir un
organismo en la nueva entrada; nunca crea un segundo inicio.

La consola tiene cuatro pestañas: **Estudio**, **Sonidos**, **Nodo** y
**Aprender**. Reproducir/Detener y el estado permanecen al pie de todas ellas.
El inspector permite elegir un nodo por nombre, editar entradas y salidas,
afinar notas y desplegar los controles de posición y efectos cuando se necesitan.

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


## Conexiones múltiples y orden musical

Play conserva una única entrada. Cada organismo admite varias entradas y varias
salidas. En **Nodo → Conexiones**, el menú de tiempo de cada salida permite
seleccionar un retraso musical fijo (de ¼ a 32 beats) o volver a **Según distancia**.
Los tiempos fijos se guardan en JSON y permanecen iguales al mover los nodos.

- El destino entra cuando transcurre el retraso de su conexión desde el ataque del origen.
- Dos salidas de 1 beat suenan juntas. Salidas de 1 y 2 beats suenan en ese orden.
- Dos rutas al mismo nodo en el mismo instante producen un único ataque.
- Si esas rutas llegan en instantes distintos, el nodo vuelve a sonar en cada llegada.
- Un nodo muteado mantiene el paso del pulso hacia sus destinos.
- Los ciclos internos recorren cada arista como máximo las veces configuradas por camino.
  El patrón completo sigue repitiéndose hasta Detener o una edición de conexiones/eliminación.

**Estudio → Ver orden de reproducción** muestra los ataques por beat, incluidos
los nodos en silencio. El beat 0 es la entrada; una vuelta termina un beat después
del último ataque. La afinación, volumen, reverb, delay y distorsión cambian en
vivo, también al mover o girar organismos. Añadir un nodo libre o deshacer un
ajuste sonoro tampoco corta Play. Conectar o eliminar nodos sí detiene el recorrido.

Los cambios de tiempo por distancia o por el menú se preparan para el próximo
Play: el loop actual conserva sus ataques y reloj, mientras la duración sostenida
del sonido responde al ajuste. El aviso inferior lo indica. La vista de orden
permite comparar **En reproducción** y **Próximo Play**. Fija los sonidos y tiempos
si solo quieres ordenar el espacio sin alterar la composición.

La planificación usa una cola de prioridad y cuenta hasta 512 ataques únicos.
También acota el trabajo de expansión del grafo. Si una composición supera esos
límites, Play pide reducir los ciclos en vez de reproducir silenciosamente una
parte del grafo. Los duplicados de una convergencia no consumen el límite de ataques.

## Aprender música

**Aprender** ofrece cuatro prácticas de unos tres minutos: pulso regular,
melodía La–Do–Mi, acorde de La menor y convergencia de dos ramas. Cada práctica
incluye explicación, reto, escena editable y comprobación de los tiempos/notas
resultantes. Primero se inicia la reproducción; después se comprueba el ejercicio.
La comprobación verifica la configuración musical, no que la persona haya oído el audio.

Al entrar se reserva en memoria la composición actual, tempo, ciclos, selección e
historial. **Terminar** los recupera, incluso después de cambiar de lección. El
progreso se guarda localmente con AppStorage. La reserva temporal dura la sesión;
conviene guardar la composición antes de cerrar la app. Las prácticas no sobrescriben
el archivo de composición guardada.

## Validación del núcleo sin simulador

Ejecuta `Scripts/validate-core.sh` en macOS con Xcode. Compila los archivos reales
de producción y ejecuta el callback de audio para todos los timbres: primer ataque,
repetición, muestras finitas y Stop. También comprueba convergencias, orden estable,
ciclos acotados, ejercicios, persistencia, tiempos fijos, restauración de la
composición y su historial. No sustituye las pruebas de interacción, HRTF ni
rendimiento del espacio inmersivo en Vision Pro.

### Resultado de validación · 7 de septiembre de 2026

- Compilación de la app y bundle de pruebas para simulador: correcta.
- Compilación genérica para Vision Pro, sin firma: correcta.
- Arnés ejecutado sobre código de producción: 14 timbres, repetición y Stop;
  convergencias, límites y orden; cuatro lecciones; guardado/carga; tiempos fijos;
  restauración de composición e historial; máximo de 32 voces y registro de notas.
- XCTest en visionOS 26.5 no llegó a ejecutar los casos; se interrumpió el intento
  al permanecer bloqueado el runtime. visionOS 2.5 también permaneció en negro
  y no completó la instalación. No se considera validada la interfaz en simulador.
- Pendientes en Vision Pro: mezcla/HRTF real, gestos, comodidad y fluidez con
  escenas densas. La compilación conserva advertencias de aislamiento de actor
  de RealityKit bajo comprobación estricta de concurrencia; el proyecto usa Swift 5.


## Edición en vivo e interfaz · 9 de septiembre de 2026

En **Nodo** ahora hay un mezclador con afinación y sliders de volumen, reverb,
delay y distorsión. Se pueden usar durante Play; el candado solo evita que la
posición vuelva a mapear pitch/volumen/tiempo. Afinar manualmente ya no activa el
candado por sorpresa. El mute conserva la agenda de la voz y aplica un fundido
corto; desmutear recupera el sonido incluso si el nodo empezó inactivo.

La ventana tiene una identidad compartida de superficies oscuras, cian y violeta,
una portada espacial, tarjetas de timbres con ilustraciones de onda, favoritos,
resumen de sesión y transporte fijo. El menú superior reúne guardar, cargar,
demo y nueva composición. La preescucha aislada está disponible al detener la
pista para evitar que un toque corte accidentalmente la mezcla.

Se redujeron las publicaciones de estado durante movimiento/rotación, se agrupan
las actualizaciones de conexiones y se omite reconstruir agendas y componentes
visuales que no han cambiado. Las ondas de las tarjetas son ilustraciones estáticas,
no medidores de audio ni animaciones ejecutándose mientras se hace scroll.

`Scripts/validate-core.sh` incluye comprobaciones de los 24 renderizadores y
regresiones de edición en vivo, mute/desmute, continuidad de sesión, deshacer y
entrada de tiempos en el siguiente Play. La revisión de fluidez y espacialización
con el visor sigue siendo una comprobación distinta de este arnés.

Validación actual, incluida la corrección de ramas y reconexión de Play:
- Compilación final para simulador (`build-for-testing`) y Vision Pro sin firma:
  correctas con comprobación estricta de concurrencia.
- El arnés ejecutado pasó para los 24 timbres, edición en vivo, mute/desmute,
  continuidad del transporte, deshacer, añadir un nodo libre durante Play,
  conexiones múltiples y las cuatro lecciones. La regresión adicional ejecuta
  el callback de cada rama durante tres vueltas, comprueba simultaneidad,
  convergencia y Stop, reconexión a Play en ambos sentidos y recuperación por voz.
- XCTest ejecutó **73 casos, 0 fallos y 0 omitidos** en visionOS Simulator 26.5:
  `ConnectionGraphTests`, `SoundVisionTests`, `LearningAndRoutingTests`,
  `SpatialVoiceRendererTests`, `VoiceRenderHealthTests` y `LiveEditingTests`.
- Se instaló y abrió la app en el simulador; la portada se mostró correctamente.
  La herramienta de interacción devolvió `noWindowsAvailable` al intentar pulsar
  dentro de la pantalla simulada, por lo que no se completó la revisión del estudio.
- Pendientes en Vision Pro: separación cómoda de Play y consola, gestos con las
  manos, mezcla espacial y fluidez. Usar `DEVICE_TEST_CHECKLIST.md`.
