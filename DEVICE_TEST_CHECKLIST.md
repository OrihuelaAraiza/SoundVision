# Prueba física de SoundVision

## Antes de empezar

- Usa un espacio despejado y permanece sentado o de pie en un punto estable.
- Ajusta el volumen del sistema a un nivel cómodo, nunca al máximo de inicio.
- En `Signing & Capabilities`, selecciona tu Developer Team y deja activado
  `Automatically manage signing`. Si Xcode indica que el identificador ya está
  registrado, cambia `com.soundvision.app` por uno asociado a tu equipo.
- Ejecuta `SoundVision` en configuración Debug sobre Apple Vision Pro.
- En la ventana principal pulsa **Abrir demo**.
- La escena debe mostrar cinco nodos y abrir la guía `PRUEBA EN VISION PRO`.

## Recorrido de 10 minutos

### 0. Consola por pestañas

1. La consola tiene tres pestañas: **Reproducir**, **Sonidos** y **Nodo**.
   Confirma que en cada una **todo cabe sin tener que desplazar**.
2. Selecciona un organismo y ve a **Nodo**: debe mostrar su inspector. Sin
   selección, debe explicar cómo seleccionar uno en vez de quedarse en blanco.
3. **Mientras arrastras un nodo con una mano**, pulsa botones y cambia de
   pestaña con la otra: la consola debe seguir respondiendo a la primera.

### 1. Altura, consola y cambio de modo

1. Confirma que Play y los nodos aparecen aproximadamente a la altura del torso,
   no sobre el suelo.
2. Coloca la ventana de la consola donde te resulte cómoda con la barra inferior
   de visionOS. **Gira 90° y camina un par de pasos**: la ventana debe quedarse
   donde la pusiste, no seguirte la cabeza.
3. Confirma que todos los botones de la consola se pueden mirar y pulsar sin que
   el panel se mueva mientras los miras.
4. En la demo pulsa **Nueva pista** y confirma el diálogo: **el diálogo debe
   aparecer**. Después todos los nodos de prueba deben desaparecer.
5. En **Añadir sonido** toca `Kick` y confirma que aparece un nodo seleccionado
   y conectado a Play.
6. Tira del núcleo Play dentro del espacio y suelta: debe extraerse un organismo
   nuevo en el punto donde soltaste.
7. Selecciona un nodo y pulsa la papelera: el diálogo de borrado debe aparecer y
   confirmar debe eliminar nodo y conexiones.
8. Alterna diez veces entre **Demo** y **Nueva pista**. Cada cambio debe
   completar sin conservar nodos viejos, congelar controles ni dejar audio activo.
9. Cierra el espacio con la corona digital: la ventana debe volver al lanzador,
   no quedarse mostrando la consola.

Registra: altura cómoda, claridad de los controles y cualquier diálogo que no
llegue a presentarse.

### 1. Localización inicial

1. Pulsa **Reproducir**.
2. **Confirma que suena algo.** Si no, mira la consola: un aviso naranja dirá si
   las voces no llegaron a engancharse o si están conectadas pero mudas. Anota
   cuál de los dos aparece — distinguen dos causas muy distintas.
3. Confirma que **la primera nota suena** y no se pierde: el ataque inicial debe
   oírse completo, no entrar a medias.
3. Confirma que las cintas alrededor de Play aceleran y ondulan sin saltos, y
   que la animación de reposo es fluida y no a tirones.
3. Confirma que aparecen partículas luminosas alrededor del núcleo y del nodo activo.
4. Confirma un Kick frontal y un FX detrás de la cabeza al inicio.
5. Gira lentamente la cabeza 45 grados a cada lado.
6. El sonido debe permanecer fijado a los nodos, no seguir la cabeza.

Registra: claridad frontal/posterior, estabilidad al girar y cualquier salto.

### 2. Izquierda y derecha

1. Selecciona `Bass izquierdo` y pulsa **Escuchar desde aquí**.
2. Selecciona `Hi-hat derecho` y repite.
3. Compara precisión lateral, volumen y distancia percibida.

Registra: cuál fuente se localiza mejor y si alguna parece estar dentro de la cabeza.

### 3. Altura y profundidad

1. **Afinación.** Sube un nodo poco a poco: la nota debe **saltar de grado en
   grado**, no deslizarse, y el inspector debe mostrar el nombre (La4, Do5…).
   Coloca cuatro o cinco nodos a alturas cualesquiera y reproduce: deben sonar
   afinados entre sí, sin ninguna nota que chirríe.
2. **Duración por distancia.** Separa dos nodos tonales (Pad, Bass, Lead): el
   primero debe **sostener** más. Júntalos: debe quedar staccato. Repite con
   Kick o Hi-hat: su golpe **no** debe alargarse.
3. Arrástralo hacia abajo; su pitch debe bajar.
3. Acércalo y aléjalo; volumen y distancia acústica deben cambiar suavemente.
4. Pulsa **Escuchar desde aquí** después de cada posición.

Registra: rango cómodo, cambios demasiado bruscos y límites difíciles de alcanzar.

### 4. Rotación y efectos

1. Rota `Pad alto y lejano` alrededor de X para probar reverb.
2. Rota `FX posterior` alrededor de Y/Z para delay y distorsión.
3. Observa el porcentaje en el inspector y escucha el nodo individualmente.

Registra: control, latencia, efecto mínimo útil y punto donde pierde claridad.

### 5. Composición e interacción

1. **Conectar tirando del hilo.** Tira del punto luminoso bajo un organismo:
   debe salir un hilo que sigue tu mano. Acércalo a otro organismo y confirma
   que **el destino se ilumina antes de soltar**. Suelta y comprueba la línea.
2. Repite soltando el hilo en el vacío: no debe crearse nada y debe avisarte.
3. Comprueba que el punto de conexión se distingue del cuerpo: arrastrar el
   cuerpo debe **mover** el organismo, no trazar hilo. Prueba especialmente con
   `Pad` y `Lead`, cuyos cuerpos son los más grandes.
3a. **Arranque del arrastre.** Empieza a mover un nodo despacio: debe salir
   siguiendo la mano desde el primer instante, **sin pegar un salto inicial**.
3d. **Tocar sigue seleccionando.** Haz un pinch limpio sobre un nodo: debe
   seleccionarse. Ahora muévelo de verdad y suéltalo: debe quedar
   **seleccionado**, no deseleccionado por el gesto.
3f. **Síntesis en vivo.** Con la música **sonando**, arrastra un organismo tonal
   (Pad, Bass, Lead) hacia arriba: su nota debe subir **mientras suena**,
   deslizándose hasta la nueva altura sin chasquidos. Acércalo y aléjalo: el
   volumen debe seguir la mano. Gíralo: reverb, delay y distorsión deben
   moverse en vivo. Nada de esto debe esperar a la siguiente reproducción.
3e. **Play sin congelón.** Con ocho organismos bien separados (notas largas),
   pulsa Reproducir: no debe haber pausa perceptible entre el toque y el sonido.
3b. **Fluidez al arrastrar.** Mueve un nodo sin soltar durante varios segundos:
   debe seguir la mano sin tirones. Mientras tanto, pulsa un botón de la consola
   con la otra mano: debe responder a la primera.
3c. Si aun así no consigues moverlo con la mano, usa los sliders de **Posición**
   del inspector y anótalo: significa que el arrastre 3D sigue fallando.
4. **Cortar.** Haz pinch sobre una conexión: debe desaparecer al instante.
   Pulsa **Deshacer** en la consola y confirma que vuelve.
5. Deshaz varias veces seguidas (corte, nodo añadido, demo cargada). Cada paso
   debe revertir **una sola acción**: añadir un nodo y su conexión automática
   cuenta como una.
6. Añade ocho nodos, borra dos del medio y añade tres más: **ninguno debe
   aparecer encima de otro**.
7. Haz pinch sobre el nodo ya seleccionado: debe soltarse la selección.
8. **Ordenar sin desafinar.** Activa **Sonido fijo** en un nodo: debe aparecer un
   pedestal bajo él. Muévelo por todo el espacio y confirma que pitch, volumen y
   duración **no cambian** en el inspector. Desactívalo y confirma que vuelve a
   afinarse al moverlo. Acomoda toda la composición con los candados puestos y
   comprueba que suena exactamente igual que antes de ordenarla.
8. Reproduce, detén, vuelve a reproducir y cambia tempo/loops cuando esté detenido.
9. Selecciona un nodo detenido: debe mostrar pocas partículas. Al escucharlo,
   la emisión debe intensificarse y después desaparecer sin quedar residuos.

Registra: hilos que no enganchan, conexiones difíciles de tocar, y si el radio
de enganche resulta demasiado corto o demasiado goloso.

## Criterio de salida

La prueba es satisfactoria si:

- frente, atrás, izquierda, derecha, altura y distancia se distinguen;
- el audio permanece anclado al mover la cabeza;
- Play/Stop puede repetirse sin silencio, duplicación ni sonidos residuales;
- pinch, drag y rotación funcionan sin selecciones accidentales frecuentes;
- los menús pueden moverse, recentrarse y recuperarse con la ventana flotante;
- brillo y ondas coinciden perceptualmente con cada ataque;
- partículas no ocultan nodos, texto ni conexiones y el campo Metal permanece fluido;
- no hay parpadeos, cintas colapsadas ni partículas cuadradas con borde visible;
- al menos ocho nodos pueden moverse y reproducirse sin pausas visibles frecuentes;
- no aparecen clipping, fatiga o picos de volumen incómodos.

## Datos que conviene anotar

- Modelo y versión de visionOS.
- Salida utilizada: Audio Pods, AirPods u otra ruta.
- Volumen aproximado del sistema.
- Nodo, posición y gesto que produjo el problema.
- Si el problema se repite después de detener y volver a reproducir.
- Si la degradación aparece con un número concreto de nodos o ramas concurrentes.
