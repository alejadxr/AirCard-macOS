# AirCard macOS

Port nativo para macOS del flujo de personalización de tarjetas de Apple Wallet
de [AirCard-Windows](https://github.com/Lumid-Off/AirCard-Windows). La interfaz
y la orquestación están escritas en Swift 6.2 y usan Swift Concurrency para la
detección del iPhone, preparación de imágenes y escritura atómica.

> Estado: probado con un iPhone18,3 en iOS 27.2 (build 24B5084k). La detección
> de hash de tarjetas también soporta iOS 18 (incluido 18.7.8). El proyecto usa
> APIs privadas de Apple y es experimental; no es una herramienta oficial.

## Idioma

La app incluye español y portugués de Brasil (`pt-BR`). Para cambiar solo
AirCard, abre **Ajustes del Sistema → General → Idioma y región → Aplicaciones**,
añade AirCard y selecciona **Português (Brasil)**; luego cierra y vuelve a abrir
la app. También seguirá el idioma preferido de macOS si no configuras uno por
app.

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
Apple Books una vez antes del primer flash. Pulsa “Detectar desde Wallet”, abre
Apple Wallet y toca la tarjeta: aparece en la lista, se vincula sola (con
“Seguir la última tarjeta que abra” activo) y queda guardada para la próxima
vez. Puedes renombrar, copiar u olvidar cada tarjeta desde su menú, o pegar el
hash manualmente en “Pegar hash manualmente”. Después elige una imagen, añade uno o varios overlays PNG
transparentes si quieres, y pulsa “Aplicar skin”. Los overlays se combinan en
el orden mostrado y se incluyen en todas las variantes que recibe Wallet. Al
terminar, cierra y abre Wallet en el iPhone.

El flujo conserva/restaura los archivos temporales de Books y limpia los
artefactos generados. Solo se escriben los assets de la tarjeta seleccionada y
se intentan invalidar sus cachés.

## Estudio de tarjeta

La app se organiza con un menú lateral: iPhone, Estudio de tarjeta, Teclado de
código, las tarjetas detectadas y Actividad.

El estudio trabaja con un documento de capas (`.aircardskin`) que se renderiza
con Core Image y shaders Metal compilados en tiempo de ejecución (no hace falta
Xcode ni el Metal Toolchain). La misma función genera la previsualización y los
archivos que se escriben en Wallet.

- Capas: imagen, color, degradado lineal/radial/cónico, mesh gradient,
  holográfico, metal cepillado, brillo, grano, patrón (líneas, puntos,
  cuadrícula, fibra de carbono, guilloché, ondas) y texto.
- Cada capa tiene opacidad y modo de mezcla (multiplicar, trama, superponer,
  luz suave, sobreexponer, etc.). Ajustes globales de color, viñeta, bloom,
  desenfoque y nitidez.
- Estilos listos: Titanio, Holo, Aurora, Carbono, Guilloché, Vidrio,
  Atardecer y Noir. Los que usan foto conservan la tuya.
- Arrastra la tarjeta para inclinarla y ver cómo se mueven los reflejos. Como
  Wallet recibe una imagen fija, la “Inclinación” decide en qué ángulo quedan
  congelados al exportar.
- “Zonas de Wallet” marca la franja aproximada que se ve en la pila de tarjetas.
- Deshacer/rehacer, guardar/abrir `.aircardskin`, arrastrar imágenes al lienzo.
- Cada skin aplicado se guarda en
  `~/Library/Application Support/AirCard/Cards/<hash>/` con miniatura, los 11
  archivos, el `.aircardskin` y las imágenes originales. La barra lateral muestra
  esa miniatura y la vista de cada tarjeta permite “Guardar respaldo…” o
  reabrir el diseño.

## Alcance actual

- Port funcional inicial de Wallet card skin.
- Detección nativa de iPhones emparejados.
- Detección de hash desde syslog compatible con iOS 18 (registros separados por
  NUL, líneas partidas entre lecturas, rutas `Passes/Cards/…`, `uniqueID = …`)
  y filtro de falsos positivos (UUID, assets del sistema, hashes de prueba).
- Lista persistente de tarjetas detectadas con nombre, última vez vista y
  selección con un clic.
- Preparación a 1536×969 y 1024×646 PNG, más PDF, conservando los bordes de la imagen.
- Overlays PNG múltiples con transparencia, reordenamiento y previsualización antes del flash.
- Flash por batch y limpieza/restauración de Books.
- Artwork de tarjetas Apple Pay mediante los nombres canónicos `cardBackgroundCombined`, `diffuse`, `background` y `strip` en 3x, 2x y PDF.
- El color de los números de una tarjeta Apple Pay lo decide iOS/el emisor; Wallet no reconoce sufijos `--white` / `--black` para estos assets.
- Icono de aplicación multicapa `AirCardIcon.icon`, compilado por Xcode 26.2 a `Assets.car` y `AirCardIcon.icns` para el bundle Swift Package.
- Recoloración y flash de temas `.passthm` para TelephonyUI-8/9/10.
- Generación de variantes de teclado `--white`, `--black`, `--white-bold` y `--black-bold`.
- Nombres de teclas por idioma (`<idioma>-<dígito>-<letras>--white.png`) para
  English, Russian, Ukrainian, Japanese o Universal, casilla “Texto en negrita”
  y marcador `_big` que necesitan iOS 16–18.
- Caché “Auto”: iOS 18+ → `TelephonyUI-10`, iOS 16–17 → `TelephonyUI-9`,
  anteriores → `TelephonyUI-8`.
- Timeout de AirTraffic de `max(60, archivos × 2)` s; si el iPhone está
  bloqueado falla con un mensaje claro en lugar de quedarse esperando.
- Descarga de lo que se va a escribir: “Descargar assets…” (imagen original +
  11 archivos de Wallet) y “Descargar .passthm…” (teclas recoloreadas con sus
  nombres finales).

## Limitaciones

- **No se puede leer el artwork actual de una tarjeta.** AFC solo expone
  `/var/mobile/Media`; la carpeta de Wallet (`/var/mobile/Library/Passes/Cards/…`)
  queda fuera, y el enlace de AirTraffic solo sirve para escribir. Ya se probó
  leer `pass.json` por ese enlace y las tarjetas Apple Pay no lo exponen
  (ver `c8ce025`).
- Por lo mismo, **no hay respaldo del diseño original de Apple/del emisor** ni
  miniatura real de cada tarjeta. “Descargar assets…” guarda solo lo que tú
  elegiste y lo que la app escribe.
- Para volver al diseño original, quita la tarjeta de Wallet y vuelve a
  añadirla; Wallet descarga de nuevo los assets del emisor.
- Los efectos que se mueven con el giroscopio (brillo o degradados) los dibuja
  iOS; no conocemos ningún asset del `.pkpass` que los active o configure. El
  artwork que se escribe es una imagen estática.

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

Además de conservar el nombre original, la variante elegida en la interfaz se
escribe como `--white` o `--black`; si la imagen es `-bold`, se usa
`--white-bold` o `--black-bold` respectivamente.

Para tarjetas Apple Pay, iOS dibuja los números y normalmente decide su color
internamente; el port original tampoco modifica `pass.json`, solo reemplaza el
artwork y limpia las cachés de Wallet. La build actual escribe además los
assets canónicos `diffuse`, `background` y `strip`, siguiendo el port iOS
relacionado, porque algunas variantes de Wallet pueden leer esos nombres en
lugar de `cardBackgroundCombined`.

La interfaz incluye ahora una ruta experimental separada para el texto de los
números: primero intenta leer `pass.json` y luego puede cambiar únicamente
`foregroundColor`. Esto no utiliza `.passthm` ni overlays. Apple documenta
`foregroundColor` para el texto de los campos de un pass normal, pero una tarjeta
Apple Pay puede mantener su color verde o ignorar el cambio si iOS valida la
firma del paquete.
