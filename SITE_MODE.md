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

The default scope is narrow on purpose. Whoever writes the keys should usually give the site and its subdomains, for example `https://example.com/` and `https://*.example.com/` for a start URL on `www.example.com`, so that the site's own sign-in, file and media hosts stay in the app (see Known limits).

## What changes in site mode

- **No browser interface.** No address bar, toolbars, tabs, tab overview, sidebar or homepage. The page fills the window below the status bar.
- **Standalone display mode.** Pages see `display-mode: standalone`, as for an installed web app.
- **Links.**
  - Pages in scope load in the app.
  - A link the person follows from the site to another site opens in Reynard when it is installed (`reynard://open?url=`), otherwise in the default browser. So do links opened in the background (Command-click).
  - Redirects and scripted navigations stay in the app, so sign-in flows that pass through an identity provider work. Sign-in requests (OAuth 2.0, OpenID Connect, SAML, WS-Federation) also stay.
  - Every window the site opens with `window.open()` (a sign-in window, a payment window, or a blank window it fills in) opens in the app, over the site, and keeps every page it loads.
  - A link with `target="_blank"` also opens a window first, because the engine asks for both kinds of window the same way. The window's first load decides: when it is a link the person followed to another site, the link opens in the browser and the window closes again, so the window can show for a moment.
  - A window that calls `window.close()` closes and the site shows again. The site's own page cannot close the app. When it calls `window.close()`, the engine has already marked its window closed and would drop every message posted to it, so the site opens again at its start page in a new session. A page that closes itself again within 10 seconds of that stays as it is.
  - Other URL schemes (`mailto:`, `tel:`, other apps) work as in Reynard.
- **A slim bar** appears only while a window over the site (a popup the site opened, or a tab an add-on opened) or a page outside the scope is showing. It names the page's host. Its button closes that window, or goes back to the start page.
- **Library and Settings.** The Library shows Downloads and Settings only, as a sheet (there is no sidebar on iPad either). Its links open in the browser, About links to this fork's source, and clearing open tabs returns to the start page.
- **Menus and keyboard shortcuts** are the site's: Print, Open in Browser, Copy Link, Downloads and Settings; Back, Forward and Home; Reload and zoom. Browser commands (tabs, address bar, history and bookmark lists, reader, sidebar, Find in Page, Find Selection) are removed. Link and image menus offer Open Link in Browser and Open Image in Browser, and link previews are off. Links on error pages open in the browser.
- **No reload loop.** When a page's content process is killed, Reynard reloads the page. In site mode the third kill of one page's process within 30 seconds shows Page Stopped Working with Try Again instead.
- **The updater is off.** A site app never checks for or offers Reynard updates.
- **Its own name.** Text that would name Reynard shows the app's `CFBundleDisplayName` instead, including untitled print jobs and data exports. Credit lines that name Minh Ton keep Reynard's name. Settings call the website mode Desktop or Mobile, not Firefox.

## Known limits

Site mode decides from what the engine reports about each load:

- The engine marks no form post. A form on the site that posts to another site when the person clicks (for example a sign-in form that posts to a single sign-on host, or a 3-D Secure "Continue" button) counts as a followed link. It opens in the browser as a plain page load (GET), without the form data. Put such hosts in `Scope`.
- The engine marks no download either. A file link on another host (a CDN, for example) counts as a followed link and downloads in the browser, not in the app. Put the host in `Scope` to keep its downloads in the app.
- A link with `target="_blank"` that goes to an address inside the scope and is then redirected to another site (a link redirector) opens in a window over the site, not in the browser. Open in Browser in the File menu sends it there.

## What a site app bundle needs

- Its own `CFBundleIdentifier`, `CFBundleDisplayName` and icons. Set both `CFBundleIcons` and `CFBundleIcons~ipad` to the site's own icon files, with no `CFBundleIconName` in either. Reynard's build has `CFBundleIconName` (Reynard's icon in the asset catalog) under both keys, and on iPad `CFBundleIcons~ipad` is the one used.
- `PlugIns/Reynard Helper.appex` with the bundle ID `<app ID>.Helper`. The folder name is fixed in the engine.
- No `CFBundleURLTypes` and no `OpenIn.appex`, so the site app never claims web links or appears in share sheets.
- No `UIRequiresFullScreen`, so the app can be used in windows.
- `UTImportedTypeDeclarations` (Firefox Add-on Package) can be removed: a site app does not install add-ons from files.
- The same entitlements as Reynard's TrollStore build, with the app's own `application-identifier`.
- On a Dopamine jailbreak, the app and its Helper signed with `jb.pmap_cs.custom_trust` set to `PMAP_CS_APP_STORE`, as TrollStore Lite signs apps. Without it they run as first-party binaries, and iPadOS 18.5 kills the Helper (`EXC_GUARD` in `thread_set_exception_ports`) when a page uses WebAssembly. The engine's own binaries can stay as the release signs them.
- When the app is removed: iPadOS keeps each Helper crash report twice, in `/var/mobile/Library/Logs/CrashReporter` and in `/private/var/containers/Shared/SystemGroup/systemgroup.com.apple.osanalytics/DiagnosticReports`, named after the Helper's executable. The remover can delete the app's own reports by that name in both folders.

## Building

Site mode builds like Reynard (see Building in the README). `tools/sitemode/` also builds the app layer against the engine of an official Reynard release, without building Gecko. The source must be at that release's commit (`engine.lock`).

1. `tools/development/build-idevice.sh`, as for Reynard.
2. `tools/sitemode/stage-engine.sh` downloads the release's TrollStore package named in `engine.lock`, checks its sha256 and stages its engine and the two Gecko headers the app layer needs.
3. `tools/release/build-app.sh --no-signing` and `tools/release/create-ipa.sh --trollstore`, as for Reynard.
4. `tools/sitemode/check-build.sh` compares the result with the official package: libraries, engine symbols, entitlements and version.
5. `tools/sitemode/collect-app-layer.sh` packs the app layer without the engine.
