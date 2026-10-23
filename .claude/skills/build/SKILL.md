---
name: build
description: Generar el proyecto con xcodegen, compilar, pasar los tests y lanzar Quién Manda en el simulador de iPhone o iPad. Úsala para compilar, probar, ejecutar o hacer capturas de la app.
---

# Compilar, probar y ejecutar Quién Manda

Todo se ejecuta desde la raíz del repo. Después de tocar `project.yml`, o de
añadir o quitar ficheros en `Sources/` o `Tests/`, hay que volver a generar el proyecto.

```sh
xcodegen generate -q
```

## Tests (criterio de terminado)
```sh
xcodebuild test -project QuienManda.xcodeproj -scheme QuienManda \
  -destination 'platform=iOS Simulator,name=iPhone Air' 2>&1 \
  | grep -E "error:|warning:|Test Case.*(passed|failed)|TEST (SUCCEEDED|FAILED)"
```
No uses `-quiet` sin el grep: oculta el resultado de los tests.

## Ejecutar en el simulador
```sh
xcodebuild build -project QuienManda.xcodeproj -scheme QuienManda \
  -destination 'platform=iOS Simulator,name=iPhone Air' -derivedDataPath build -quiet
xcrun simctl boot "iPhone Air" 2>/dev/null; open -a Simulator
xcrun simctl install booted build/Build/Products/Debug-iphonesimulator/QuienManda.app
xcrun simctl launch booted es.julia.angela.app.quienmanda
xcrun simctl io booted screenshot /tmp/mando.png
```
Para el iPad, cambia el destino a `iPad Pro 11-inch (M5)`.

## Limitaciones
- Sin una TV real solo se ve la pantalla de conexión. El simulador sí llega a la
  red local, así que con una TV en la misma Wi-Fi funciona.
- SSDP (multicast) no funciona en un dispositivo hasta tener el entitlement
  `com.apple.developer.networking.multicast`.
