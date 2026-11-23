# Aliaro iOS — contexto para Claude

Contexto común (producto, Supabase, reglas, docs): `../CLAUDE.md`. Este repo es la **fuente de verdad** de textos y comportamiento; Android se alinea con él.

## Básico
- Repo `devaro95/Aliaro`. SwiftUI + SwiftData, iOS 17+. Versión actual en `project.pbxproj` (`MARKETING_VERSION` / `CURRENT_PROJECT_VERSION`).
- Bundle ids: `com.devaro.aliaro` (Release → Supabase prod) y `com.devaro.aliaro.dev` (Debug → Aliaro-Dev). Widgets: `…aliaro.widgets` / `…aliaro.dev.widgets`. App Group `group.com.devaro.aliaro[.dev]`.
- Entorno Supabase elegido con `#if DEBUG` en `Aliaro/Core/SupabaseConfig.swift` (no Info.plist).
- Paquetes SPM: supabase-swift, firebase-ios-sdk, facebook-ios-sdk (Meta Ads).

## Proyecto Xcode
- `Aliaro.xcodeproj/project.pbxproj` **se genera** con `python3 gen_pbxproj.py`. Nunca editarlo a mano.
- Volver a ejecutarlo al añadir, borrar o mover ficheros en `Aliaro/`, `AliaroShared/` o `AliaroWidgets/`. Conserva el equipo y las versiones del pbxproj anterior.
- Targets: `Aliaro` (app) y `AliaroWidgetsExtension`. `AliaroShared/` se compila en ambos (snapshot del widget + App Group).
- Desde Windows no se puede compilar: los cambios se verifican compilando en el Mac de Varo.

## Estructura (`Aliaro/`)
- `Core/`: sesión (`AuthSession`, `FamilySession`, `FamilyService`), sincronización (`DataSync`, `RemoteSync`), `Supabase*`, premium (`PremiumManager`, `PremiumConfig`, `PremiumFeature`, `SubscriptionManager` con StoreKit 2), push (`PushNotificationManager`), `ForceUpdate`, `Analytics`, `MetaAds`, invitaciones (`InviteLink`, `PendingInvite`), `WidgetSnapshotWriter` y `DebugMockData`.
- `Models/`: modelos SwiftData, uno por entidad sincronizada con Supabase.
- `Features/<Feature>/`: `<X>Screen.swift` y sheets `Add<X>Sheet.swift`. Las features son Auth, Board (tablón), Economia, FamilyCalendar, Home, HouseTasks, Onboarding, People (cuenta, permisos, notificaciones, feedback), Places, Premium (paywall, force update), Recipes, Reminders, ShoppingList, Splash, WeeklyMenu, Wifi, WorldMap y Debug.
- `DesignSystem/`: componentes `ALI*` (colores, tipografía, iconos, componentes).
- `Navigation/`: `AppTab`, `MainTabContainer`, `ALIBottomBar`.
- `Localizable.xcstrings`: catálogo de textos con clave en inglés y traducción `es`. Android genera sus strings desde aquí, así que **todo texto nuevo va al catálogo** con su traducción.
- Menú Debug: se abre agitando el móvil y puede desbloquear premium hasta reiniciar.

## Otras cosas en el repo (no son la app)
- `src/`, `public/`, `package.json`, `app-store-screenshots.json`: editor Next.js de capturas de tienda. Su `README.md` es de este editor, no de la app.
- `Screenshots/`: capturas.
- `Claude outputs/`: material suelto (textos de App Store, plantillas de email, iconos, AASA web).
- `_to_delete/`: ficheros antiguos pendientes de borrar.
- `todo.md`: copia antigua; la lista viva está en `../docs/claude/todo.md`.

## Flujo git
- git-flow: `feature/<nombre>` desde `develop` → merge a `develop`. Las versiones salen de `release/x.y.z` y los arreglos urgentes de `hotfix/…`, ambos hacia `master`.
- Un commit por feature con descripción en español. Al portar algo de Android, decirlo en el mensaje.
