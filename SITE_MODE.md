# Site mode

Site mode turns this app into one website's own app, for the web apps of the MacStatusBar&Dock jailbreak tweak. Each web app is a copy of the app with its own name, icon, bundle ID and data, and a `SiteMode` dictionary in its `Info.plist`. Without that dictionary the app is Reynard, unchanged.

## Info.plist keys

```xml
<key>SiteMode</key>
<dict>
    <key>StartURL</key>
    <string>https://example.com/app</string>
    <key>Scope</key>
    <array>
        <string>https://example.com/</string>
        <string>https://*.example.com/</string>
    </array>
</dict>
```

- `StartURL` (required): an http or https URL. The app opens it at every launch.
- `Scope` (optional): URL prefixes that belong to the app. A URL is in scope when its scheme, host and port match an entry and its path starts with the entry's path. `*.` before a host also matches its subdomains. Without `Scope`, the scope is the start URL's origin. The start URL's origin is always in scope.

## What changes in site mode

- **No browser interface.** No address bar, toolbars, tabs, tab overview, sidebar or homepage. The page fills the window below the status bar.
- **Standalone display mode.** Pages see `display-mode: standalone`, as for an installed web app.
- **Links.**
  - Pages in scope load in the app.
  - A link the person follows from the site to another site opens in Reynard when it is installed (`reynard://open?url=`), otherwise in the default browser. So do links opened as new tabs (`target="_blank"`) or in the background.
  - Redirects and scripted navigations stay in the app, so sign-in flows that pass through an identity provider work. Sign-in requests (OAuth 2.0, OpenID Connect, SAML, WS-Federation) also stay.
  - Popup windows the site opens (`window.open()` with window features, or a blank window it fills in, for example a sign-in window) stay in the app, shown over the site, together with every page they load.
  - Other URL schemes (`mailto:`, `tel:`, other apps) work as in Reynard.
- **A slim bar** appears only while a window over the site (a popup the site opened, or a tab an add-on opened) or a page outside the scope is showing. It names the page's host. Its button closes that window, or goes back to the start page.
- **Library and Settings.** The Library shows Downloads and Settings only. Its links open in the browser, About links to this fork's source, and clearing open tabs returns to the start page.
- **Menus and keyboard shortcuts** are the site's: Print, Open in Browser, Copy Link, Downloads and Settings; Back, Forward and Home; Reload and zoom. Browser commands (tabs, address bar, history and bookmark lists, reader, sidebar, Find in Page) are removed. In link menus, Open Link in New Tab opens the browser and link previews are off.
- **The updater is off.** A site app never checks for or offers Reynard updates.
- **Its own name.** Text that would name Reynard shows the app's `CFBundleDisplayName` instead.

## What a site app bundle needs

- Its own `CFBundleIdentifier`, `CFBundleDisplayName` and icons. Use `CFBundleIcons` with the site's own icon files, and no `CFBundleIconName` (that one points at Reynard's icon in the asset catalog).
- `PlugIns/Reynard Helper.appex` with the bundle ID `<app ID>.Helper`. The folder name is fixed in the engine.
- No `CFBundleURLTypes` and no `OpenIn.appex`, so the site app never claims web links or appears in share sheets.
- No `UIRequiresFullScreen`, so the app can be used in windows.
- The same entitlements as Reynard's TrollStore build, with the app's own `application-identifier`.

## Building

Site mode builds like Reynard (see Building in the README). `tools/sitemode/` also builds the app layer against the engine of an official Reynard release, without building Gecko. The source must be at that release's commit (`engine.lock`).

1. `tools/development/build-idevice.sh`, as for Reynard.
2. `tools/sitemode/stage-engine.sh` downloads the release's TrollStore package named in `engine.lock`, checks its sha256 and stages its engine and the two Gecko headers the app layer needs.
3. `tools/release/build-app.sh --no-signing` and `tools/release/create-ipa.sh --trollstore`, as for Reynard.
4. `tools/sitemode/check-build.sh` compares the result with the official package: libraries, engine symbols, entitlements and version.
5. `tools/sitemode/collect-app-layer.sh` packs the app layer without the engine.
