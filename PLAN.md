# Plan de desarrollo — mando para TV Sony BRAVIA (iPhone + iPad)

App 100 % gratuita, sin anuncios ni rastreo, con todo lo que la app de referencia
cobra, y un "Invítame a un café" opcional.

**Estado (2026-10-20):** el MVP está hecho, aunque sin probar con una TV real.
Incluye conexión por IP con PSK o PIN, cruceta, números, volumen, canal y
encender/apagar, y se adapta al iPad. El detalle está en `README.md` → Estado.

## 1. Qué hace la app de referencia

### Protocolo (todo público y documentado por Sony)
- **Descubrimiento:** SSDP `M-SEARCH` (`ssdp:discover`), más IP manual e historial de IPs.
- **Autenticación:** PIN de 4 dígitos (`/sony/accessControl` → `actRegister`, con cookie
  `auth` que se refresca) o Pre-Shared Key (cabecera `X-Auth-PSK`).
- **Teclas:** IRCC por SOAP (`urn:schemas-sony-com:service:IRCC:1#X_SendIRCC`), con
  los códigos sacados de `getRemoteControllerInfo`.
- **API REST JSON-RPC** (`/sony/system`, `/sony/audio`, `/sony/avContent`, `/sony/appControl`,
  `/sony/videoScreen`, `/sony/encryption`):
  `getPowerStatus/setPowerStatus`, `getSystemInformation`, `getInterfaceInformation`,
  `getVolumeInformation/setAudioVolume/setAudioMute`, `getPlayingContentInfo`,
  `getCurrentExternalInputsStatus`, `getApplicationList/setActiveApp`,
  `getTextForm/setTextForm`, `getLEDIndicatorStatus/setLEDIndicatorStatus`,
  `getPowerSavingMode/setPowerSavingMode`, `getWolMode/setWolMode`, `requestReboot`.

### Funciones gratuitas en la app de referencia
D-Pad y TouchPad por gestos, volumen y canales (lado configurable), Input/Options,
teclado numérico, entrada de texto, conexión (SSDP, IP manual, PIN, PSK, historial,
reconexión automática, "Force Mode"), háptica, pantalla siempre encendida, modo
claro/oscuro, idiomas, diagnóstico (envío por email), información del sistema,
reiniciar la TV, LED, onboarding.

### Funciones de pago (las de PRO/Premium) → en la nuestra, gratis
| De pago allí | Cómo hacerlo aquí |
|---|---|
| Function Keys (todas las teclas IRCC, personalizables) | Rejilla con los códigos de `getRemoteControllerInfo`, que el usuario puede reordenar |
| Shortcuts (abrir apps de la TV, sincronizar, reordenar, ocultar) | `getApplicationList` + `setActiveApp`, con lista editable |
| Varias TVs | Lista de TVs guardadas y selector |
| Siri: encender/apagar, subir/bajar volumen con paso configurable, HDMI 1–4, abrir app 1–4 | App Intents + App Shortcuts (sin las intents antiguas de SiriKit) |
| Temas de color | Paleta de acentos en SwiftUI |
| Estado de la TV | Panel con encendido, entrada, volumen, contenido en reproducción y red |
| Apple Watch | App de watchOS que manda las órdenes a través del iPhone con WatchConnectivity |
| Widgets | Widgets interactivos (WidgetKit + AppIntent) y controles del Centro de Control (iOS 18) |
| Sin anuncios | No hay anuncios |

### Lo que se quita
AdMob, AppLovin, Facebook Audience Network, Vungle, Firebase (Analytics, Crashlytics,
Remote Config, A/B), ATT y SKAdNetwork, anuncios con recompensa, avisos para valorar
la app, el muro de pago y el aviso de notificaciones. En total, unos 11 frameworks
menos y nada de rastreo. La ficha de privacidad queda en "Datos no recopilados".

## 2. Decisiones técnicas (las más simples que funcionan)

- **SwiftUI**, iOS 18+ y **un solo target universal**. El iPad usa la misma UI, con
  un factor de escala que se lee de `horizontalSizeClass` (botones y fuentes más
  grandes) y, en horizontal, una columna lateral con Shortcuts y Function Keys.
  No hay una app aparte para iPad.
- **Sin dependencias de terceros.** `URLSession` para la API REST y el SOAP,
  `Network.framework` para SSDP (UDP multicast) y Wake-on-LAN, `HTTPCookieStorage`
  compartido con App Group para el widget, el watch y los intents, StoreKit 2 para
  el café y `@AppStorage` y `Codable` para la configuración.
- **Módulos:** un paquete Swift local `BraviaCore` (protocolo, sin UI) que usan la
  app, los widgets, los intents y el watch. Fuera de eso, todo va en el target de la app.
- **Entitlement de multicast:** para SSDP hace falta
  `com.apple.developer.networking.multicast`, que se **solicita a Apple** (tarda días).
  Hay que pedirlo el primer día. Mientras tanto se usa la IP manual.
- **Nombre:** no usar "Sony" ni "BRAVIA" en el nombre de la app, porque es motivo de
  rechazo (guía 5.2.1). En la descripción, "Compatible con TVs Sony BRAVIA".
- **Código y recursos propios:** se implementa a partir de la documentación pública
  de Sony (BRAVIA IP Control / REST API). No se copia nada de otras apps.

## 3. "Invítame a un café"

Hacerlo con **StoreKit 2 y 3 productos consumibles** (café, café con bollo y
desayuno), sin desbloquear nada. Apple exige IAP para las propinas digitales dentro
de la app (guía 3.1.1). Con el Small Business Program, Apple se queda el 15 %.
Va en Ajustes y en "Acerca de", sin popups. Un enlace externo (Ko-fi o Buy Me a
Coffee) solo se puede usar en el escaparate de EE. UU., así que no compensa al principio.

## 4. Fases y modelo de Claude para cada una (para abaratar)

Regla general: **Sonnet 5.5** (`claude-sonnet-5-5`) para el grueso del trabajo,
**Haiku 5.5** (`claude-haiku-5-5`) para lo mecánico y **Opus 5.5** (`claude-opus-5-5`)
solo para diseñar al principio o para un bug cuya causa no se conoce. Esfuerzo bajo o
medio por defecto, `/clear` entre fases y un CLAUDE.md corto con las decisiones de la §2.

| # | Fase | Modelo | Por qué |
|---|---|---|---|
| 0 | Esqueleto Xcode, App Group, pedir el entitlement de multicast, git y issues | Haiku 5.5 | Mecánico |
| 1 | `BraviaCore`: cliente JSON-RPC, IRCC SOAP, autenticación PIN y PSK con cookie, SSDP, WOL | **Opus 5.5** para el diseño y un primer corte, después Sonnet 5.5 | Es la base de todo y la red tiene casos difíciles |
| 2 | Pantalla del mando (D-Pad, TouchPad, volumen y canales, numérico, texto, háptica) | Sonnet 5.5 | UI bien especificada |
| 3 | Conexión y onboarding (búsqueda, IP, PIN, PSK, historial, reconexión, Force Mode) | Sonnet 5.5 | |
| 4 | Pro gratis: Function Keys, Shortcuts, varias TVs, estado y sistema (LED, reinicio, ahorro de energía) | Sonnet 5.5 | |
| 5 | Adaptación a iPad (escala y columna lateral) | Sonnet 5.5 | |
| 6 | App Intents/Siri, widgets y controles del Centro de Control | Sonnet 5.5 | Mucho código repetitivo, pero hace falta criterio |
| 7 | App del Apple Watch (WatchConnectivity) | Sonnet 5.5 | |
| 8 | Temas, modo oscuro y café (StoreKit 2) | Sonnet 5.5 (el café), Haiku 5.5 (los temas) | |
| 9 | Localización (es, en, ja, zh, de, fr, it, ru, tr) con String Catalog | Haiku 5.5 | Traducción mecánica |
| 10 | Diagnóstico por email, ficha de la App Store, privacidad y capturas | Haiku 5.5 | |
| — | Bug de red o de autenticación que no se entiende con una TV real | Opus 5.5 | Solo cuando la causa es desconocida |

Se estima que alrededor del 75 % del trabajo cae en Sonnet, el 15 % en Haiku y el 10 %
en Opus. Lo que más ahorra es tener la §1 escrita: así los modelos baratos no tienen
que investigar el protocolo.

## 5. Pruebas
- Una prueba por pieza no trivial de `BraviaCore`: que el JSON-RPC y el SOAP se
  construyan bien, que la respuesta SSDP se parsee y que el paquete WOL sea correcto.
  Con XCTest y respuestas grabadas.
- Pruebas en una TV real: Android TV / Google TV de 2016 en adelante, con PIN y con PSK.
- Siri, widgets y watch, a mano.

## 6. Pendiente de decidir
- Nombre de la app.
- Precios de los cafés (por ejemplo 0,99 €, 2,99 € y 4,99 €).
- Si el Apple Watch entra en la v1 o en la v1.1.
