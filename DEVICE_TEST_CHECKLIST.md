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

### 0. Altura, consola y cambio de modo

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
2. Confirma que **la primera nota suena** y no se pierde: el ataque inicial debe
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

1. Selecciona un nodo y arrástralo hacia arriba; su pitch debe subir.
2. Arrástralo hacia abajo; su pitch debe bajar.
3. Acércalo y aléjalo; volumen y distancia acústica deben cambiar suavemente.
4. Pulsa **Escuchar desde aquí** después de cada posición.

Registra: rango cómodo, cambios demasiado bruscos y límites difíciles de alcanzar.

### 4. Rotación y efectos

1. Rota `Pad alto y lejano` alrededor de X para probar reverb.
2. Rota `FX posterior` alrededor de Y/Z para delay y distorsión.
3. Observa el porcentaje en el inspector y escucha el nodo individualmente.

Registra: control, latencia, efecto mínimo útil y punto donde pierde claridad.

### 5. Composición e interacción

1. En un nodo pulsa **Conectar** y después selecciona otro nodo.
2. Confirma que aparece la línea y el mensaje `Conexión creada`.
3. Reproduce, detén, vuelve a reproducir y cambia tempo/loops cuando esté detenido.
4. Crea un nodo desde **Extraer nodo**, muévelo y elimínalo desde el inspector.
5. Selecciona un nodo detenido: debe mostrar pocas partículas. Al escucharlo,
   la emisión debe intensificarse y después desaparecer sin quedar residuos.

Registra: gestos fallidos, controles difíciles de alcanzar y desincronización visual.

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
