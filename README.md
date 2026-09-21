# AirCard macOS

Port nativo para macOS del flujo de personalización de tarjetas de Apple Wallet
de [AirCard-Windows](https://github.com/Lumid-Off/AirCard-Windows). La interfaz
y la orquestación están escritas en Swift 6.2 y usan Swift Concurrency para la
detección del iPhone, preparación de imágenes y escritura atómica.

> Estado: probado con un iPhone18,3 en iOS 27.2 (build 24B5084k). El proyecto
> usa APIs privadas de Apple y es experimental; no es una herramienta oficial.

## Ejecutar

Desde esta carpeta:

```sh
chmod +x Scripts/build_helpers.sh
Scripts/build_helpers.sh
swift run
```

Para generar una aplicación universal que puedas abrir con doble clic:

```sh
chmod +x Scripts/build_app.sh
Scripts/build_app.sh
open build/AirCardMac.app
```

Para generar también un instalador `.dmg`:

```sh
chmod +x Scripts/build_dmg.sh
Scripts/build_dmg.sh
open build/AirCardMac.dmg
```

El DMG contiene la aplicación universal `AirCardMac.app` para Apple Silicon e
Intel.

Conecta un iPhone emparejado por USB, desbloquéalo y pulsa “Confiar”. Abre
Apple Books una vez antes del primer flash. Pulsa “Escanear desde Wallet”, abre
Apple Wallet y toca la tarjeta; el hash se rellenará solo. También puedes pegar
el hash manualmente. Después elige una imagen y pulsa “Aplicar skin”. Al
terminar, cierra y abre Wallet en el iPhone.

El flujo conserva/restaura los archivos temporales de Books y limpia los
artefactos generados. Solo se escriben los assets de la tarjeta seleccionada y
se intentan invalidar sus cachés.

## Alcance actual

- Port funcional inicial de Wallet card skin.
- Detección nativa de iPhones emparejados.
- Preparación a 1536×969 PNG/PDF conservando los bordes de la imagen.
- Flash por batch y limpieza/restauración de Books.
- Cambio de color del texto de la tarjeta mediante `foregroundColor` y `labelColor` de `pass.json`.
- Recoloración y flash de temas `.passthm` para TelephonyUI-8/9/10.

## Sobre el color de los números

El repositorio original también soporta paquetes `.passthm` para el teclado de
código de iOS. Los números no son texto recoloreable: son imágenes rasterizadas
que se copian a cachés de `TelephonyUI` con nombres como:

```text
en-2-A B C--white.png
en-2-A B C--white-bold.png
```

Por tanto, para cambiar el color hay que recolorear o regenerar los PNG de las
teclas y después escribir las variantes correspondientes en
`/var/mobile/Library/Caches/TelephonyUI-10` (o `-9`/`-8`, según iOS). La variante
`-bold` es la que usa iOS cuando está activo “Texto en negrita”.

En la app: elige un `.passthm`, selecciona el color, verifica la previsualización
y pulsa “Aplicar color al teclado”. El port conserva los nombres y variantes del
paquete, convierte JPG/JPEG a PNG y hace la escritura por lotes con fallback
individual. Después bloquea el iPhone para que TelephonyUI recargue la caché.

Para cambiar los números y etiquetas de una tarjeta de Wallet no necesitas un
`.passthm`: selecciona el color en la sección de Artwork y pulsa “Aplicar skin”.
La app conserva el `pass.json` original y solo actualiza sus colores de texto.
