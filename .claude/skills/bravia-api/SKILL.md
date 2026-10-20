---
name: bravia-api
description: Referencia del protocolo de control IP de las TVs Sony BRAVIA (JSON-RPC /sony/*, IRCC SOAP, autenticación por PSK o PIN, SSDP y WOL). Cárgala antes de tocar Sources/TV.swift o de añadir cualquier orden a la TV.
---

# Protocolo BRAVIA

Fuentes: la documentación pública de Sony "BRAVIA Professional Displays — IP Control /
REST API" (pro-bravia.sony.net).

## Transporte
- HTTP en el puerto 80, sin TLS. En el Info.plist hacen falta `NSAllowsLocalNetworking`
  y `NSLocalNetworkUsageDescription`.
- JSON-RPC: `POST http://<ip>/sony/<servicio>` con el cuerpo
  `{"method": "...", "params": [...], "id": 1, "version": "1.0"}`.
- Si va bien, devuelve `{"result": [...], "id": 1}`; si falla, `{"error": [código, "mensaje"], "id": 1}`.
  Un error puede llegar con HTTP 200, así que hay que mirar siempre la clave `error`.

## Autenticación (una de las dos)
- **PSK**: se envía la cabecera `X-Auth-PSK: <clave>` en todas las peticiones, JSON y SOAP.
- **PIN**: `POST /sony/accessControl` con `actRegister` y estos params:
  `[{"clientid": "<app>:<uuid>", "nickname": "<nombre>", "level": "private"}, [{"value": "yes", "function": "WOL"}]]`.
  - Sin `Authorization` → la TV responde **401** y muestra un PIN de 4 dígitos.
  - Se repite con `Authorization: Basic base64(":" + pin)` → 200 y cookie `auth`.
    URLSession la guarda y la reenvía sola; caduca y se renueva con otro `actRegister`.
  - El `clientid` tiene que ser estable (se guarda un UUID en UserDefaults), porque
    si cambia se pide otro PIN.

## Servicios y métodos útiles
| Servicio | Método | Notas |
|---|---|---|
| system | `getRemoteControllerInfo` | `result = [{bundled,type}, [{name, value}]]`: nombre de tecla → código IRCC. **Varía según el modelo**, así que se lee de la TV y no se hardcodea. |
| system | `getPowerStatus` / `setPowerStatus` | `{"status":"active"\|"standby"}` / `[{"status": true}]`. Es la única forma de encender: IRCC no responde en standby. |
| system | `getSystemInformation`, `getInterfaceInformation`, `getLEDIndicatorStatus`, `setLEDIndicatorStatus`, `getPowerSavingMode`, `setPowerSavingMode`, `getWolMode`, `setWolMode`, `requestReboot` | Estado de la TV, ajustes y reinicio |
| audio | `getVolumeInformation`, `setAudioVolume` (v1.0/1.2), `setAudioMute` | `setAudioVolume [{"target":"speaker","volume":"+1"}]` |
| avContent | `getPlayingContentInfo`, `getCurrentExternalInputsStatus` (v1.0/1.1), `setPlayContent` | Entradas HDMI: `uri` `extInput:hdmi?port=1` |
| appControl | `getApplicationList`, `setActiveApp`, `getTextForm` / `setTextForm` (v1.1 cifrado) | Shortcuts de apps y entrada de texto |
| encryption | `getPublicKey` | Para `setTextForm` v1.1 |
| videoScreen | — | Sin usar todavía |

## IRCC (teclas)
`POST /sony/ircc` con estas cabeceras:
- `SOAPACTION: "urn:schemas-sony-com:service:IRCC:1#X_SendIRCC"` (con las comillas)
- `Content-Type: text/xml; charset=UTF-8`

El cuerpo es un sobre SOAP con `<IRCCCode>…</IRCCCode>`; está en `TV.soap(_:)`.

Nombres habituales: `Up Down Left Right Confirm Return Home Input Mute VolumeUp VolumeDown ChannelUp ChannelDown Num0…Num9 Options Display Guide (EPG) Hdmi1…Hdmi4 Netflix ActionMenu Play Pause Stop Forward Rewind Prev Next TvPower PowerOff`.

## Descubrimiento (SSDP)
UDP multicast a `239.255.255.250:1900`:
```
M-SEARCH * HTTP/1.1
HOST: 239.255.255.250:1900
MAN: "ssdp:discover"
MX: 2
ST: urn:schemas-sony-com:service:ScalarWebAPI:1
```
Se toma la IP de `LOCATION`. Necesita el entitlement `com.apple.developer.networking.multicast`
(hay que pedírselo a Apple). Hasta tenerlo, la IP se introduce a mano.

## Wake-on-LAN
Paquete mágico UDP de 6×`FF` + 16× la MAC, enviado a broadcast en el puerto 9. La
MAC sale de `getSystemInformation` (`macAddr`) y hay que guardarla mientras la TV
está encendida. En la mayoría de modelos, con "Remote start" activado basta con `setPowerStatus`.

## Trampas conocidas
- Una IP que cambia por DHCP rompe la sesión. La app de referencia ofrece reconectar
  si encuentra la TV en otra IP.
- Algunas series no tienen ciertas teclas. Por eso existen la pantalla de diagnóstico
  y el "Force Mode" de la referencia.
- En standby, sin "Remote start", la TV no responde a nada: hay que mostrar un error claro.
