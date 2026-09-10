# Prueba física de SoundVision

## Gizmo de efectos en los nodos

- [ ] Seleccionar un nodo con pinch: aparecen Reverb, Delay, Distorsión y
      Volumen, cada uno con nombre, color, pista con graduaciones y porcentaje.
- [ ] Agarrar cada pomo sin desplazarlo: no debe saltar el valor. Arrastrar arriba
      aumenta y abajo reduce. Probar 0 %, 100 % y volver desde ambos extremos.
- [ ] El pomo y su barra deben **recorrer la pista** con el valor, no quedarse
      quietos: comprobar que los cuatro niveles se leen de lejos sin mirar el número.
- [ ] Precisión: mover la mano muy despacio debe avanzar de 1 en 1 %, sin saltos
      de tres o cuatro; un barrido rápido debe seguir cruzando todo el rango de
      una pasada. Soltar siempre en un porcentaje entero.
- [ ] Durante Play, variar cada efecto y escuchar el cambio sin reiniciar el
      patrón ni cambiar los otros efectos, la posición, afinación o conexiones.
- [ ] Soltar entre dos porcentajes y comprobar que el mezclador y el gizmo
      coinciden. Un solo Deshacer debe recuperar el valor anterior al arrastre.
- [ ] Cambiar un efecto desde el mezclador: su dial espacial se actualiza.
      Guardar/cargar y comprobar que ambos controles conservan el mismo valor.
- [ ] Girar el organismo: los faders permanecen legibles **y los valores no
      cambian** —girar solo orienta—. Mover el cuerpo: el gizmo lo acompaña.
      Tirar del conector: sigue creando hilos.
- [ ] Barras sobre el cuerpo: aparecen al subir reverb, delay o distorsión, con
      el color del efecto, y desaparecen al volver a 0 %. Deben quedarse quietas
      y de frente mientras el organismo respira, gira o recibe un ataque, y no
      taparse con la etiqueta de nota/volumen del nodo seleccionado.
- [ ] Tocar de nuevo el cuerpo o seleccionar otro: desaparecen los controles del
      anterior. Borrar el nodo durante una edición no debe afectar a otro sonido.
- [ ] Probar Pad, Lead y un nodo muteado, con el sonido fijo y con varias ramas
      reproduciéndose. Revisar separación, alcance de la pinza y fluidez con el visor.

## Regresión: ramas, reconexión y separación de Play

- [ ] Abrir **Crear una composición**: Play queda a la izquierda de la ventana.
      Pulsar y desplazar el menú sin activar ni arrastrar Play accidentalmente.
- [ ] Crear Kick, Campana y Woodblock. Unir Kick → Campana, y después arrastrar
      desde Woodblock hacia Kick. Ambas conexiones deben salir de Kick. Fijar
      las dos a 1 beat: deben oírse ambas ramas juntas en cada una de tres vueltas.
- [ ] Repetir con **Añadir salida** desde Kick hacia cada rama. Silenciar cada
      rama por separado para distinguirlas y confirmar que la otra sigue sonando.
- [ ] Cortar la conexión de Play y arrastrarlo hacia un nodo existente: debe
      conectarlo, sin cambiar el número de nodos. Deshacer y repetir desde el
      conector del nodo hacia Play. Repetir con **Conectar a Play** en Nodo.
- [ ] Con Play ocupado, repetir ambos gestos hacia otro nodo: debe conservarse
      la entrada actual y mostrarse el aviso de entrada ocupada.
- [ ] Soltar un hilo sobre el cuerpo y sobre el conector de un nodo rotado.
      El resaltado debe anticipar el destino y desaparecer al soltar en vacío.
- [ ] Crear y conectar ramas después de entrar en el estudio; repetir Play y
      Stop, y comprobar que ninguna voz queda muda al volver a reproducir.

La prueba directa de `Scripts/validate-core.sh` cubre el recorrido desde los
gestos resueltos hasta las muestras de cada rama, tres vueltas, Stop y la
decisión de recuperar una voz detenida. No sustituye la escucha espacial ni
los gestos con las manos en Vision Pro.

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

1. La consola tiene cuatro pestañas: **Estudio**, **Sonidos**, **Nodo** y **Aprender**.
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
   y conectado a Play. Toca ahora `Bass`: debe aparecer **sin conexión**. En el
   inspector de `Kick`, usa **Añadir salida → Bass** (o arrastra su punto
   luminoso hasta Bass) y confirma la línea. Añade un tercero: también debe
   aparecer libre y Play debe conservar **una sola salida**.
6. Con la entrada de Play ya ocupada, tira del núcleo dentro del espacio y
   suelta: **no** debe crear otro organismo ni otra salida; debe explicar que el
   resto de la composición se conecta entre organismos.
7. Selecciona un nodo y pulsa la papelera: el diálogo de borrado debe aparecer y
   confirmar debe eliminar nodo y conexiones.
8. Alterna diez veces entre **Demo** y **Nueva pista**. Cada cambio debe
   completar sin conservar nodos viejos, congelar controles ni dejar audio activo.
9. Cierra el espacio con la corona digital: la ventana debe volver al lanzador,
   no quedarse mostrando la consola.

Registra: altura cómoda, claridad de los controles y cualquier diálogo que no
llegue a presentarse.

### 1. Localización inicial

0. **Ondas.** Con la música sonando, cada organismo que entra debe **emitir una
   onda que se expande y se desvanece**, no un parpadeo. En un pasaje rápido
   deben verse varias en el aire a la vez.
0b. **Resaltado al mirar.** Mira un organismo sin tocarlo: debe encenderse con
   **su propio color**. Mira otro: el primero debe apagarse.
0c. **Etiqueta.** Sin selección, el espacio no debe tener texto flotando. Haz
   pinch sobre un organismo: solo entonces aparece su lectura, y solo la suya.
1. Pulsa **Reproducir**.
2. **Confirma que suena algo.** Si no, la pestaña **Reproducir** trae dos líneas
   que hay que anotar tal cual:
   - Un aviso naranja, si lo hay: dirá si el sistema negó la sesión de audio, si
     ninguna voz llegó a engancharse, si están enganchadas pero el sistema no les
     pide muestras, o si rinden sin sacar nivel. Son cuatro causas distintas.
   - La línea gris de diagnóstico: `N voces · reloj · tasa · pico · salida`.
     Con música sonando, el pico **no** debe decir `silencio`, y la salida debe
     ser la que estés usando de verdad. Anótala completa.
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

### 4. Efectos y orientación

1. Selecciona `Pad alto y lejano` y sube su fader de reverb.
2. Selecciona `FX posterior` y sube delay y distorsión.
3. Observa el porcentaje en el inspector, la barra sobre el cuerpo y escucha el
   nodo individualmente.
4. Gira los dos organismos con dos manos: deben orientarse sin que su sonido ni
   sus barras se muevan.

Registra: control, latencia, efecto mínimo útil, punto donde pierde claridad y
si el 1 % es alcanzable con la mano en el aire.

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
3g. **Encadenar por decisión explícita.** Añade tres sonidos: solo el primero
   debe salir de Play y los otros dos deben nacer libres. Conecta primero →
   segundo → tercero, mediante los hilos o **Añadir salida**. Reproduce y
   confirma que entran uno tras otro, no todos a la vez.
3h. **Organismo incomunicado.** Corta la conexión que une una rama con Play y
   selecciona un organismo de esa rama: el inspector debe avisar en naranja de
   que Play no llega hasta ahí. Si Play conserva su entrada, reconecta la rama
   desde un organismo alcanzable; no debe ofrecer una segunda salida de Play.
   Si cortaste la propia entrada y Play quedó libre, **Convertir en entrada de
   Play** debe rescatar exactamente un organismo.
3i. **Bifurcación completa.** Conecta primero → segundo y primero → tercero.
   Pulsa Reproducir: segundo y tercero deben sonar en la misma vuelta; ninguno
   puede reemplazar ni silenciar al otro.
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
8. Reproduce y deja pasar al menos tres vueltas completas: el patrón debe
   reiniciarse por sí mismo y seguir sonando hasta pulsar **Detener**. Vuelve a
   reproducir y cambia tempo/vueltas internas cuando esté detenido. **La segunda
   reproducción debe sonar igual que la primera**, y al detener el corte debe
   apagarse limpio, sin chasquido.
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

- La línea de diagnóstico de audio completa, sonando y en reposo.
- Modelo y versión de visionOS.
- Salida utilizada: Audio Pods, AirPods u otra ruta.
- Volumen aproximado del sistema.
- Nodo, posición y gesto que produjo el problema.
- Si el problema se repite después de detener y volver a reproducir.
- Si la degradación aparece con un número concreto de nodos o ramas concurrentes.


## Sonidos, conexiones y aprendizaje

- [ ] En Sonidos, recorrer las tres familias y buscar Campana, Marimba y Órgano.
      Añadir y escuchar los seis timbres nuevos; distinguirlos al mismo volumen.
- [ ] Un origen con dos salidas fijas a 1 beat: ambas fuentes se oyen juntas.
      Cambiar una a 2 beats: comprobar el orden y la vista de ataques.
- [ ] Dos ramas que convergen: un ataque si coinciden; dos si sus tiempos difieren.
      Probar un ciclo, un nodo muteado intermedio y varias vueltas completas.
- [ ] Guardar tiempos fijos y ciclos; cargar, mover nodos y comprobar que se conservan.
- [ ] Completar las cuatro prácticas desde una composición propia. Probar un
      resultado incorrecto y después el correcto; terminar y verificar que regresan
      notas, conexiones, tempo, selección e historial. Reiniciar la app y comprobar
      el progreso guardado de las lecciones.
- [ ] Probar controles de transporte desde todas las pestañas, selección por
      nombre, menús de tiempos, deshacer y preescucha completa de sonidos largos.
- [ ] Reabrir el estudio con Continuar composición. Cancelar una apertura y
      comprobar que la composición no se borra.
- [ ] Evaluar lectura, scroll, alcance de controles y fluidez con 14 y 32 nodos;
      comprobar volumen mezclado, localización, oclusión y comodidad con el visor.


## Regresión de edición en vivo · septiembre 2026

- [ ] Reproducir una cadena conectada; mover un nodo arriba/abajo y cerca/lejos.
      Deben cambiar tono y volumen sin detener ni reiniciar el loop.
- [ ] Usar los cuatro sliders de Nodo y los cuatro faders espaciales; oír reverb,
      delay, distorsión y volumen mientras continúa la pista. Deshacer un ajuste
      sin cortar Play. Girar el cuerpo no debe alterar ninguno de los cuatro.
- [ ] Iniciar con un nodo intermedio muteado; activarlo durante Play, volver a
      mutearlo y comprobar que todos los destinos siguen su ritmo.
- [ ] Cambiar una distancia o tiempo fijo; comparar En reproducción / Próximo
      Play. Detener y reproducir: ahora deben aplicarse los nuevos tiempos.
- [ ] Añadir un timbre durante Play: nace libre y el resto continúa sonando.
- [ ] Escuchar los 10 timbres nuevos, guardar favoritos, filtrar y reiniciar para
      verificar que los favoritos persisten. Revisar etiquetas largas en el espacio.
- [ ] Revisar portada, biblioteca, mezclador y prácticas en una ventana pequeña,
      con texto ampliado y con 24–32 nodos. Confirmar lectura, scroll y respuesta
      de sliders/gestos; la compilación por sí sola no valida su fluidez.


## Fiabilidad, recuperación y comodidad · 10 septiembre 2026

- [ ] Crear → mover → Deshacer → Rehacer: conservar el mismo nodo y restaurar
      posición, afinación, volumen y tiempos. Repetir con giro y cuatro faders.
      Tocar sin modificar no consume historial. Cancelar un gesto también debe
      dejar el último valor coherente y un solo paso de historial.
- [ ] Silencio, sonido fijo, tempo y ciclos tienen Deshacer/Rehacer; ajustes
      sonoros conservan Play. Una edición nueva invalida Rehacer.
- [ ] Añadir 8, 16 y 32 organismos; revisar separación, acceso al conector y
      lectura de los cuatro faders. Con varios efectos encendidos, comprobar que
      las barras de un cuerpo no se confunden con las del vecino. Borrar y añadir
      de nuevo sin superponer cuerpos.
- [ ] Llevar Volumen a 0 % durante Play: oír silencio; subirlo sin reiniciar el
      recorrido. Repetir con silencio activado: subir volumen no debe desmutear.
- [ ] Crear dos ataques del mismo nodo separados por ¼ beat a 180 BPM: comprobar
      dos ondas. Repetir Play/Stop y observar el primer ataque tras una carga lenta.
- [ ] Cambiar una salida a tiempo fijo, abrir Orden y mover el nodo: comparar
      En reproducción y Próximo Play; al reiniciar se aplica el nuevo recorrido.
- [ ] Silenciar un nodo intermedio: conexión atenuada visible y ruta conservada.
      Seleccionar el origen para ver tiempos; cambiar selección para ocultarlos.
- [ ] Trazar desde una rama libre hacia una alcanzable: el mensaje debe anticipar
      la dirección efectiva. Probar duplicados y Play ocupado.
- [ ] Esperar el estado Sesión recuperable, cerrar el proceso y volver a abrir:
      recuperar nodos, tiempos e historial. Repetir dentro de una práctica, salir
      de ella y comprobar que vuelve la composición original. El guardado manual
      conserva la versión elegida explícitamente.
- [ ] Completar y ocultar la guía; volver a abrirla desde el menú. Provocar una
      nota incorrecta en una práctica y usar Ir a este sonido para corregirla.
- [ ] Ventana pequeña y texto ampliado: revisar encabezado, biblioteca, transporte,
      inspector y mensajes. Con Reducir movimiento, comprobar selección visible,
      ausencia de ondas/partículas/flotación y controles de efecto operativos.
- [ ] En Instruments → RealityKit Trace, registrar interacción y Play con 8, 16
      y 32 nodos durante tres minutos. Anotar pausas, frames tardíos y consumo.
      Validar localización, mezcla y comodidad en el Vision Pro físico.
