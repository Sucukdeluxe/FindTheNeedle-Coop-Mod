# Mod cooperativo para Find The Needle

Añade multijugador cooperativo a la demo de Find The Needle. Varios jugadores
cavan el mismo pajar, comparten el dinero y ven las construcciones de los demás.

La conexión va por la red de Steam, así que no hay que abrir puertos ni
intercambiar IPs. El anfitrión invita desde la lista de amigos de Steam.

Mod no oficial, sin relación con el desarrollador del juego. No incluye
archivos del juego, solo sus propios scripts y un modelo de jugador libre
(CC0). English: [README.md](README.md).

![Dos jugadores en el mismo patio](screenshots/coop.png)

## Requisitos

* Demo de Find The Needle (gratis en Steam), versión V26 o posterior
* Windows 64 bits
* La misma versión del mod en todas las máquinas
* Hay que abrir el juego desde Steam o las invitaciones no funcionan

## Instalación

No hay instalador que ejecutar: se copia una carpeta y se añaden dos líneas a
un archivo de texto.

1. Descarga el zip de [Releases](../../releases) y descomprímelo.
2. Copia la carpeta `mods` junto a `FindTheNeedle.exe`. En Steam: clic derecho
   en el juego, Administrar, Ver archivos locales.
3. Abre `override.cfg`, en esa misma carpeta, con cualquier editor de texto y
   añade:

   ```ini
   [autoload]
   MPMod="*mods/multiplayer/mp.gd"
   ```

   Si el archivo ya tiene una sección `[autoload]`, basta con la segunda línea.
4. Abre el juego desde Steam. En el menú principal hay una entrada MULTIPLAYER.

Si prefieres no tocar el archivo, `tools/install-helper.bat` (va suelto en
cada release) hace ese paso por ti. No viene dentro de la descarga porque
Nexus pone en cuarentena lo que lleva scripts.

Para desinstalar, borra esa línea y la carpeta `mods`, o ejecuta
`tools/uninstall-helper.bat`. No se escribe nada más fuera de ella.

Las actualizaciones del juego reemplazan `override.cfg`, así que hay que
añadir las líneas otra vez después de cada una.

## Jugar

Anfitrión: MULTIPLAYER, CREAR PARTIDA, INVITAR AMIGOS, y luego empieza o carga
una partida como siempre. Los demás entran aceptando la invitación de Steam. Si
tienen el juego cerrado, Steam lo abre y los mete dentro.

Queda un modo por IP directa en "Conexión por IP (avanzado)" como alternativa.

| Tecla | Acción |
|-------|--------|
| F2 | Panel de multijugador |
| Y | Chat |
| F8 | Resincronizar el mundo |
| F6 | Menú de pruebas |

F6 abre el menú de depuración que ya trae el juego: dinero, objetos, desbloqueos
y árbol de mejoras, más unos botones para quitar dinero. Sirve para montar una
partida o probar algo. El juego marca la partida que lo usa, así que deja de
contar para la clasificación.

## Qué se sincroniza

* El pajar. Todos cavan el mismo montón.
* Las construcciones, al colocarlas y al derribarlas.
* Dinero, deuda, paja vendida, agujas encontradas y colección.
* El árbol de mejoras.
* Las agujas destapadas. Las ve todo el mundo y solo se entregan una vez.
* Las cargas nuevas de paja, que resincronizan a todos los clientes.
* Posición, nombre y herramienta de cada jugador.
* Los objetos sueltos: cubos, sacos, fardos, manojos. Ves lo que los demás
  cogen, llevan, sueltan y lanzan, y puedes coger tú sus cosas.
* Lo que va montado en las cintas.
* La paja suelta del suelo, para que todos caven sobre el mismo desorden.
* Cómo se mueven las máquinas, su humo y sus luces, y sus ajustes.
* La paja y la aguja que llevas en la mano, dibujadas en el puño del granjero.

## Idiomas

La interfaz sigue el idioma que tenga puesto el juego. Están incluidos inglés,
español, alemán, francés, italiano, checo, polaco, ruso, turco, japonés,
coreano y chino, en `mp_i18n.gd`. Cualquier otro cae en inglés. Los nombres de
las herramientas no los traduce el mod: salen de las traducciones del propio
juego, así que se leen igual que en el resto de la interfaz.

## Limitaciones conocidas

* Las máquinas funcionan solo en el anfitrión, para que la misma paja no se
  cuente dos veces. Los demás las ven moverse, echar humo y encender luces, y
  sus ajustes coinciden, pero el trabajo lo hace una sola máquina.
* La carga de pala y horca se muestra con un modelo visual.
* Las herramientas y el dinero se comparten. El anfitrión valida las compras y la construcción.
* Solo guarda el anfitrión. Los clientes no escriben en sus partidas.
* La tabla de clasificación online se desactiva con el mod cargado.
* Las compras y la construcción esperan confirmación del anfitrión; se rechazan si cambia el precio o no hay fondos.
* Quién tiene una aguja suelta es común; dónde está tirada puede variar un
  poco entre jugadores hasta que alguien la coge.

## Problemas

No aparece MULTIPLAYER: el juego se actualizó y reemplazó `override.cfg`.
Añade las dos líneas otra vez.

"Steam no disponible": el juego se abrió desde el .exe en vez de desde Steam.

Un amigo no puede entrar: comprobad que los dos tenéis la misma versión del
mod. El panel la indica.

Las construcciones se reconcilian automáticamente. F8 solicita además una reconciliación manual.

El juego se cierra de golpe: manda el último registro de fallo de
`%APPDATA%\Godot\app_userdata\Haystack Incremental\crashes\` junto con
`mp_trace.log` de la carpeta de arriba (o `mp_trace.prev.log` si ya has vuelto
a abrir el juego). Solo apunta qué mensajes recibió el mod y cuándo, para ver
qué se estaba haciendo cuando se cerró.

Cualquier otra cosa: abre un [issue](../../issues) con el registro de
`%APPDATA%\Godot\app_userdata\Haystack Incremental\logs\`.

## Cómo funciona

La demo viene en un único `.pck` de Godot cifrado, que el mod no toca.

Godot lee `override.cfg` al arrancar. El instalador registra ahí `mp.gd` como
autoload, así que el mod son unos cuantos `.gd` fuera del juego.

La demo no trae la API de Steam, así que el mod carga la GDExtension de
[GodotSteam](https://godotsteam.com) en caliente con
`GDExtensionManager.load_extension()` e inicia Steam con el appid de la demo.
De ahí salen las salas, las invitaciones y `SteamMultiplayerPeer`.

Para que alguien entre, el anfitrión serializa su mundo con el mismo formato
que usa el juego para guardar, lo envía comprimido y el cliente lo carga con el
cargador del propio juego en un hueco aparte.

A partir de ahí la sincronización es incremental. El pajar es un mapa de
alturas y cada jugador envía los vértices que ha cambiado. Las construcciones
se comparan con el `to_array()` del juego y se recrean con su propio cargador.
El dinero y los contadores viajan como incrementos, con el anfitrión de
árbitro.

Todo se aplica recorriendo el árbol de escena en vivo y llamando a los métodos
del propio juego.

## Estructura del repositorio

```
mods/multiplayer/     lo que va en la release
  mp.gd               sesión, salas, RPCs
  mp_world.gd         sincronización (pajar, construcciones, estado, agujas)
  mp_steam.gd         carga de GodotSteam, salas, invitaciones
  mp_ui.gd            panel, chat, avisos
  mp_avatar.gd        las figuras de los otros jugadores
  mp_i18n.gd          textos de la interfaz por idioma
  tool_poses.cfg      herramientas colocadas a mano (opcional, de tool_poser)
  models/             modelo del granjero (CC0)
  steam/              GodotSteam GDExtension (compilado)
dev/mp_test.gd        arnés de pruebas, no se distribuye
dev/mp_sync_test.gd   comprobaciones de sincronización a dos, no se distribuye
dev/avatar_calib.gd   ajuste en vivo de la altura del avatar, no se distribuye
dev/tool_poser.gd     colocar a mano las herramientas del granjero, no se distribuye
dev/tool_poser.bat    abre el juego con el posicionador
dev/models/           herramientas para preparar el modelo
docs/                 textos de la página de Nexus
```

No hay nada que compilar. Editas un archivo y reinicias el juego.

Los otros jugadores son un granjero animado,
`mods/multiplayer/models/farmer.glb`, que se carga al vuelo con
`GLTFDocument`. El peto y la banda del sombrero toman el color del jugador, la
cabeza sigue hacia donde mira, las piernas se doblan al agacharse y la
animación (Idle_Neutral, Walk, Run) sigue su velocidad. Si falta el archivo o no carga,
aparece una figura antigua hecha de formas básicas. El `.glb` es el original
del pack recortado a esas tres animaciones con `dev/models/slim_glb.py`, que lo
deja de 1,3 MB en 500 KB.

Los modelos de herramienta cuelgan de la mano del avatar. Cada uno se escala a
su largo real (`TOOL_LENGTHS`) por su eje más largo y se gira para que la parte
útil apunte lejos de la mano. Con `flip_tool` en un avatar se gira 180 grados,
útil al probar un modelo nuevo. Si una herramienta tiene entrada en
`tool_poses.cfg`, se usan la posición, el giro y el largo guardados en su lugar.

Para usar el arnés de pruebas, copia `dev/mp_test.gd` junto a `mp.gd` y arranca
el juego con `MP_TEST_AVATAR=user://saves/slot_1.dat`, y `MP_TEST_TOOL=1` para
la pala. Coloca dos muñecos con esa herramienta, uno de ellos girado, y guarda
una captura.

`dev/mp_sync_test.gd` arranca un anfitrión y un invitado en el mismo PC por la
conexión IP y comprueba que el pajar, el dinero, las misiones, la tecnología,
las agujas y los edificios coinciden. Cópialo junto a `mp.gd` como
`mp_test.gd`; cómo arrancar los dos está al principio del archivo.

`dev/avatar_calib.gd` te pone delante un granjero que copia hacia dónde miras
y si te agachas, para ajustar `MODEL_HEIGHT` y `CROUCH_DROP` con las flechas y
guardarlos con F9. Cómo activarlo está al principio del archivo.

`dev/tool_poser.gd` cambia el menú principal por un escenario vacío con un
granjero que sostiene la herramienta que elijas (1-6). Arrastra el gizmo de
mover (W) o girar (E) sobre la herramienta, o usa los deslizadores de la
derecha, y mira cómo queda al mirar arriba y abajo, al andar, al agacharse o
dando vueltas. La cámara orbita, se desplaza y vuela como en el editor de
Godot. Con C pasas a una pose opcional de agachado, para las herramientas que
deban ir distintas al agacharse; si no tienen, usan la de pie. F9 escribe
`tool_poses.cfg` en la carpeta del mod. Las teclas están al
principio del archivo. `dev/tool_poser.bat` abre el juego con ella y deja
`override.cfg` como estaba al cerrarlo.

La 7 es la carretilla. El gizmo la mueve y la gira desde los pies del granjero,
que agarra los dos mangos mientras tanto. Los agarres salen del modelo; si no
quedan bien, haz clic en un punto blanco (o pulsa G) y arrástralo. Se guarda en
`[wheelbarrow]` del mismo archivo, y si no está el mod usa su pose por defecto.

## Créditos

Mod de AleDev11. Find The Needle, de
[FindTheNeedleDev](https://x.com/haydeveloper).
Modelo del granjero del [Ultimate Modular Men Pack](https://quaternius.com/packs/ultimatemodularcharacters.html),
de Quaternius, CC0. [GodotSteam](https://godotsteam.com) es MIT. El SDK de
Steamworks es de Valve.

Licencia MIT, ver [LICENSE](LICENSE).
