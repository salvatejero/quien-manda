# Mando TV

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
open SonyMando.xcodeproj          # o, desde la terminal:
xcodebuild test -project SonyMando.xcodeproj -scheme SonyMando \
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
| Conexión por IP manual + PSK / PIN | ✅ MVP (sin probar con TV real) |
| Cruceta, OK, Atrás, Inicio | ✅ MVP |
| Números 0–9 | ✅ MVP |
| Volumen ± / silencio / canal ± / entrada | ✅ MVP |
| Encender y apagar (`setPowerStatus`) | ✅ MVP |
| Diseño de iPad (escalado ×1,6) | ✅ MVP |
| Autodetección: Bonjour `_googlecast._tcp` + barrido de la subred /24 | ✅ probada con TV real (encontró "Tele") |
| Búsqueda por SSDP | ❌ descartada: necesita el entitlement de multicast y Bonjour + barrido ya lo cubren |
| TouchPad, teclado de texto, háptica configurable | ⏳ fase 2 |
| Historial, reconexión, Force Mode, onboarding | ⏳ fase 3 |
| Function Keys, Shortcuts de apps, varias TVs, estado de la TV | ⏳ fase 4 |
| Siri / App Intents, widgets, Centro de Control | ⏳ fase 6 |
| Apple Watch | ⏳ fase 7 |
| Temas, modo oscuro, "Invítame a un café" | ⏳ fase 8 |
| Idiomas | ⏳ fase 9 |

El plan completo está en [PLAN.md](PLAN.md).

## Privacidad
La app solo habla con tu TV en la red local. No recoge ningún dato.
