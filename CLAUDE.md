# CLAUDE.md — ¡Quién manda! (control de TVs Sony BRAVIA)

App iOS/iPadOS gratuita para controlar TVs Sony BRAVIA por la red local. No tiene
anuncios, no rastrea y no cobra nada; lo único de pago es un "Invítame a un café"
opcional. El plan completo y el análisis de la app de referencia están en `PLAN.md`,
y el estado de cada funcionalidad en `README.md`.

## Reglas del proyecto
- **SwiftUI, iOS 18+, un solo target universal.** El iPad es la misma UI escalada
  (`horizontalSizeClass == .regular` → ×1,6). No se hacen vistas aparte para iPad.
- **Sin dependencias de terceros.** Solo `URLSession`, `Network.framework` y StoreKit 2.
  Nada de SDKs de anuncios, analítica ni crash reporting.
- **No se copia nada** de otras apps, ni código ni recursos.
  Solo se usa la API pública de Sony.
- **El nombre visible no puede llevar "Sony" ni "BRAVIA"** (App Store, guía 5.2.1).
- **Lo que se paga en la app de referencia es gratis aquí.** El café es una propina
  consumible y no desbloquea nada.
- Textos de la UI en español por ahora. Cuando llegue la fase 9 se pasan a un String Catalog.

## Estructura
- `Sources/TV.swift`: cliente BRAVIA (JSON-RPC `/sony/*`, IRCC SOAP y autenticación por PSK o PIN).
- `Sources/App.swift`: `RootView` (conexión) y `RemoteView` (mando).
- `Tests/TVTests.swift`: XCTest de la lógica de formato (parseo de códigos y SOAP).
- `project.yml`: xcodegen. **No se edita `SonyMando.xcodeproj` a mano**; tras tocar
  `project.yml` se ejecuta `xcodegen generate`.

## Comandos
Están en la skill `build` (`.claude/skills/build/SKILL.md`). Resumen:
```sh
xcodegen generate
xcodebuild test -project SonyMando.xcodeproj -scheme SonyMando -destination 'platform=iOS Simulator,name=iPhone Air'
```

## Protocolo BRAVIA
Antes de tocar `TV.swift` hay que cargar la skill `bravia-api`, que tiene los
endpoints, la autenticación, los formatos y las trampas conocidas.

## Modelos y subagentes (para abaratar)
- **Sonnet**: agente `ios-dev`, para funcionalidades bien especificadas en el PLAN.
- **Haiku**: agente `git-ops`, para todo lo de git y `gh` (commit, push, issues y PRs).
  El principal decide qué se commitea y escribe el mensaje.
- **Opus** (el principal): diseño nuevo, bugs de red o de autenticación cuya causa
  no se conoce y revisión.

## Flujo
- Cada funcionalidad nueva lleva antes una issue `enhancement` y cada bug una issue
  `bug` (con `gh`, a través de `git-ops`). Los commits la referencian con `#N`.
- **Git flow:** `main` es la rama de las releases y `develop` la de integración.
  Cada trabajo va en `feature/<nombre>`, que sale de `develop`
  (`git flow feature start <nombre>`). Para cerrarla **no** se usa
  `git flow feature finish`: la versión instalada (git-flow 0.4.1) hace fast-forward
  si la rama tiene un solo commit. Se cierra con
  `git checkout develop && git merge --no-ff feature/<nombre> && git branch -d feature/<nombre>`. Los bugs urgentes van en `hotfix/*`
  y las versiones en `release/x.y.z`, con tag en `main`. Nunca se commitea
  directamente en `main` ni en `develop`.
- **El repo es público.** Nunca se commitean secretos, `.env`, certificados ni
  perfiles (ya están en `.gitignore`). El `DEVELOPMENT_TEAM` va en un xcconfig local
  que no se sube. Se añade con `git add <ficheros>` concretos y se revisa el diff
  staged antes de cada commit.
- El autor de los commits es el email noreply de GitHub, configurado solo en este repo.
- **Sin remoto hasta tener el MVP terminado** (probado en una TV real). Hasta
  entonces no hay push ni issues de GitHub, y las features y bugs se apuntan en
  el "Estado" del README. Al publicar: `gh repo create --public` y se abren las
  issues de lo ya hecho, citando sus commits.
- Al terminar una funcionalidad: tests en verde y una línea actualizada en el
  "Estado" del README.
- Cada lógica no trivial lleva un test pequeño en `Tests/`. La UI se prueba a mano
  en el simulador o en el dispositivo.
