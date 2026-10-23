# Quién Manda

Mando a distancia gratuito para TVs Sony BRAVIA (Android TV / Google TV de 2016 en
adelante), para iPhone e iPad. No tiene anuncios ni rastreo y no tiene funciones de pago.

## Requisitos
- Xcode 27 o posterior y [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- iOS/iPadOS 18 o posterior.
- La TV y el iPhone en la misma Wi-Fi. En la TV: **Ajustes → Red → Red doméstica →
  Control IP → Autenticación** con "Normal y clave precompartida" (o solo "Normal" para usar PIN).

## Compilar y probar
```sh
xcodegen generate
open QuienManda.xcodeproj          # o, desde la terminal:
xcodebuild test -project QuienManda.xcodeproj -scheme QuienManda \
  -destination 'platform=iOS Simulator,name=iPhone Air'
```

## Uso
1. Toca tu TV en "TVs en tu red". Si no aparece, escribe su IP (está en **Ajustes → Red → Estado de la red**).
2. Si configuraste una Pre-Shared Key en la TV, ponla aquí. Si no, deja el campo
   vacío, pulsa "Conectar" y escribe el PIN que aparece en la TV.
3. La app recuerda la IP y vuelve a conectarse sola al abrirla.

## Estado

| Funcionalidad | Estado |
|---|---|
| Conexión por IP manual + PSK / PIN | ✅ PIN probado con TV real (BRAVIA 4K UR3); PSK incorrecta se detecta al conectar |
| Cruceta, OK, Atrás, Inicio | ✅ MVP |
| Números 0–9 (cada tecla va directa a la tele, sin panel de canal ni «Ir») y botón TV también en Mando | ✅ simulador |
| Volumen ± / silencio / canal ± / entrada | ✅ MVP |
| Encender y apagar (`setPowerStatus`) | ✅ MVP |
| Diseño de iPad (escalado ×1,6) | ✅ MVP |
| Autodetección: Bonjour `_googlecast._tcp` + barrido de la subred /24 | ✅ probada con TV real (encontró "Tele") |
| UI del arquetipo: páginas Mando/Números/Atajos, panel de Apps, Configuración, «Busca tu tele» y PIN, colores de la marca (claro/oscuro) | ✅ probada con TV real |
| Panel de Apps con las apps instaladas en la TV (icono de la propia TV, ordenar arrastrando) | ✅ probado con TV real |
| Dos columnas en pantalla ancha (iPhone Duo abierto, iPad horizontal) | ✅ simulador |
| Modo demo sin TV (`-screen`, `-page`, `-sheet`, `-fail <código>`) | ✅ |
| Errores en un toast que sube desde abajo, con texto claro en vez del código (401, 40005, sin red…) | ✅ simulador |
| Identidad: icono (oscuro y tintado), splash y 27 iconos propios de `resources/quien-manda` | ✅ simulador |
| Varias teles guardadas: «Mis teles» (icono ☰ en «Busca tu tele») para cambiar, renombrar u olvidar (borra IP, PSK y cookie del llavero) | ✅ simulador; falta probar con TV real |
| Bug: tras un rato en segundo plano las teclas fallaban («La tele no responde» / «no admite esta orden»). Se reintenta una vez si la conexión keep-alive llega muerta (-1005); fallos de red en el log (`category:tv`) | ✅ probado con TV real |
| Reconexión directa al mando con la cookie del PIN guardada en el llavero | 🧪 falta probar con TV real |
| Búsqueda por SSDP | ❌ descartada: necesita el entitlement de multicast y Bonjour + barrido ya lo cubren |
| TouchPad, teclado de texto, háptica configurable | ⏳ fase 2 |
| Historial, reconexión, Force Mode, onboarding | ⏳ fase 3 |
| Function Keys, Shortcuts de apps, estado de la TV | ⏳ fase 4 |
| Siri / App Intents, widgets, Centro de Control | ⏳ fase 6 |
| Apple Watch | ⏳ fase 7 |
| Modo oscuro (sigue al sistema) | ✅ |
| "Invítame a un café": 3 consumibles StoreKit 2 en Configuración (`Tests/Cafe.storekit` para probar en local) | ✅ simulador; faltan los productos en App Store Connect |
| Temas | ⏳ fase 8 |
| Idiomas | ✅ es, en, pt, ca, gl, eu (String Catalog) |

El plan completo está en [PLAN.md](PLAN.md).

## Privacidad
La app solo habla con tu TV en la red local. No recoge ningún dato.
