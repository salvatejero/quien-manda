# Quién Manda — paquete de diseño

App de mando a distancia de tele para iPhone, de Salva Tejero Software Company.
Este paquete reúne el diseño del prototipo, el icono, la iconografía y la documentación para quien lo programe.

Prototipo interactivo (privado hasta que lo compartas):
https://claude.ai/artifact/CqFaUrB6HNNHb8wM2oZ84S

## Qué hay dentro

```
quien-manda/
├── README.md                      Este archivo
├── docs/
│   ├── especificacion.md          Pantallas, flujo, comportamientos, sistema visual y notas técnicas
│   └── app-store.md               Borrador de textos para la ficha de la App Store
├── icono/
│   ├── svg/                       Icono en vectorial: oscuro, claro y tinte, con y sin cara
│   └── png/                       Maestros de 1024 × 1024 (sin transparencia) y tamaños sueltos
├── iconos-ui/                     27 iconos de interfaz en SVG (24 px, trazo de 2 px, currentColor)
├── marca/
│   └── tokens.json                Tokens de la marca Salva Tejero Software Company
└── diseno/                        Fuente de las piezas del lienzo de diseño
    ├── Main.dc.html               Prototipo del mando (todas las pantallas)
    ├── Splash.dc.html             Pantalla de inicio
    ├── Icono.dc.html              Icono de la app (tres variantes y cara opcional)
    ├── Iconografia.dc.html        Hoja de iconografía y tamaños
    └── canvas.json                Disposición de las piezas en el lienzo
```

## Cómo usarlo

- **Icono**: los PNG de `icono/png/` ya están sin canal alfa, listos para subir a la App Store. `icono-oscuro-1024.png` es el principal.
- **Iconos de interfaz**: cada SVG usa `currentColor`, así que toman el color del texto donde los pongas.
- **Carpeta `diseno/`**: los archivos `.dc.html` son la fuente del lienzo de diseño y necesitan su motor para abrirse. Si los abres sueltos en el navegador no se verán bien. Para verlos y editarlos usa el enlace del prototipo de arriba.
- **Programarlo**: empieza por `docs/especificacion.md`.

## Pendiente de confirmar

- El nombre «Quién Manda» lo has comprobado tú en las tiendas; conviene revisar también marca (OEPM y EUIPO) y dominios.
- No se incluye el logo de la empresa; solo su texto y la barra verde.
- Los logos oficiales de las apps de streaming no están incluidos: el panel usa monogramas.
- Las teles descubiertas, sus IP y el PIN de error (0000) son datos de ejemplo del prototipo.
