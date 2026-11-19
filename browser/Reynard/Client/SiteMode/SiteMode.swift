//
//  SiteMode.swift
//  Reynard
//
//  Site mode for MacStatusBar&Dock web apps. Added in the MacStatusBarAndDock-WebApps fork.
//

import Foundation
import GeckoView
import UIKit

/// Site mode turns the app into one website's own app when its Info.plist has a
/// `SiteMode` dictionary:
///
///     <key>SiteMode</key>
///     <dict>
///         <key>StartURL</key>
///         <string>https://example.com/app</string>
///         <key>Scope</key>
///         <array>
///             <string>https://example.com/</string>
///             <string>https://*.example.com/</string>
///         </array>
///     </dict>
///
/// `Scope` is optional; without it the scope is the start URL's origin. Each entry is a URL
/// prefix: same scheme, host and port, and a path that starts with the entry's path.
/// `*.` before a host also matches its subdomains. The app's name comes from the bundle
/// (CFBundleDisplayName) and its icon from the bundle's icon keys.
///
/// Without the key the app is the normal browser and nothing here changes its behaviour.
///
/// SiteMode is nonisolated so that string lookups on any thread can use the app's name.
nonisolated struct SiteMode {
    static let current = SiteMode(infoDictionary: Bundle.main.infoDictionary)

    static var isEnabled: Bool {
        return current != nil
    }

    nonisolated struct ScopeRule: Equatable {
        let scheme: String
        let host: String
        private(set) var includesSubdomains: Bool
        let port: Int
        private(set) var pathPrefix: String

        init?(_ value: String) {
            var value = value.trimmingCharacters(in: .whitespacesAndNewlines)
            var includesSubdomains = false
            if let range = value.range(of: "://*.") {
                value.replaceSubrange(range, with: "://")
                includesSubdomains = true
            }
            guard let components = URLComponents(string: value),
                  let scheme = components.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  let host = components.host?.lowercased(),
                  !host.isEmpty else {
                return nil
            }
            self.scheme = scheme
            self.host = host
            self.includesSubdomains = includesSubdomains
            self.port = components.port ?? SiteMode.defaultPort(for: scheme)
            self.pathPrefix = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
        }

        func contains(_ components: URLComponents) -> Bool {
            guard let scheme = components.scheme?.lowercased(),
                  scheme == self.scheme,
                  let host = components.host?.lowercased(),
                  (components.port ?? SiteMode.defaultPort(for: scheme)) == port else {
                return false
            }
            guard host == self.host || (includesSubdomains && host.hasSuffix("." + self.host)) else {
                return false
            }
            let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
            return path.hasPrefix(pathPrefix)
        }
        
        /// The whole origin of this rule's host.
        var origin: ScopeRule {
            var rule = self
            rule.includesSubdomains = false
            rule.pathPrefix = "/"
            return rule
        }
    }

    /// What site mode does with a top-level load.
    nonisolated enum Navigation: Equatable {
        /// Load it in the app.
        case stay
        /// Open it in the browser and do not load it here.
        case openOutside(URL)
    }

    /// Where a top-level load happens.
    nonisolated enum Place: Equatable {
        /// The site's own window.
        case site
        /// A window the site opened, shown over the site.
        case window
        /// A window the site just opened, at the first load it was opened for.
        case newWindow
    }

    let startURL: URL
    let scope: [ScopeRule]
    let appName: String

    init?(infoDictionary: [String: Any]?) {
        guard let siteMode = infoDictionary?["SiteMode"] as? [String: Any],
              let startValue = siteMode["StartURL"] as? String,
              let startURL = URL(string: startValue),
              URLUtils.isWebURL(startURL),
              let startOrigin = ScopeRule(startURL.absoluteString) else {
            return nil
        }

        let startComponents = URLComponents(url: startURL, resolvingAgainstBaseURL: false)
        var scope = (siteMode["Scope"] as? [String] ?? []).compactMap(ScopeRule.init)
        if scope.isEmpty || !scope.contains(where: { startComponents.map($0.contains) == true }) {
            // The start page is always inside the app.
            scope.append(startOrigin.origin)
        }

        self.startURL = startURL
        self.scope = scope
        self.appName = (infoDictionary?["CFBundleDisplayName"] as? String)
        ?? (infoDictionary?["CFBundleName"] as? String)
        ?? startURL.host
        ?? ""
    }

    // MARK: - Scope

    func contains(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return scope.contains { $0.contains(components) }
    }

    func contains(_ value: String?) -> Bool {
        guard let value, let url = URL(string: value) else {
            return false
        }
        return contains(url)
    }

    /// Decides a top-level load. Returns nil for URLs that are not http, https or about, which
    /// keep Reynard's own handling (mailto:, tel:, other apps' schemes).
    ///
    /// - about: pages stay: a site opens a blank window and then fills it in (sign-in windows).
    /// - Every new window the site asks for opens in the app. Gecko asks the same way for
    ///   window.open() and for a link with target="_blank", so the window's first load decides
    ///   (`Place.newWindow`).
    /// - Links opened in the background (Command-click) open outside: there are no tabs here.
    /// - Pages inside the scope stay.
    /// - Sign-in requests (OAuth 2.0, OpenID Connect, SAML, WS-Federation) stay, so a site that
    ///   sends the whole page to its identity provider still signs in.
    /// - Everything inside a window the site opened stays, so sign-in windows can move between
    ///   hosts and report back to the page that opened them.
    /// - A new window whose first load is a link the person followed to another site was opened
    ///   by a link with target="_blank": it opens outside. A window the site opened by script
    ///   (window.open(), a sign-in window) does not start with a followed link, so it stays.
    /// - In the app's own window, only a link the person follows from one of the site's pages
    ///   opens outside. Redirects and scripted navigations stay.
    func navigation(for request: LoadRequest, in place: Place, pageURL: String?) -> Navigation? {
        guard let url = URL(string: request.uri) else {
            return nil
        }
        if url.scheme?.lowercased() == "about" {
            return .stay
        }
        guard URLUtils.isWebURL(url) else {
            return nil
        }
        switch request.target {
        case .background:
            return .openOutside(url)
        case .new:
            return .stay
        case .current:
            break
        }
        if contains(url) || Self.isSignInRequest(url) {
            return .stay
        }

        // Reynard's engine marks a link the person followed (not a redirect, not a script).
        let isFollowedLink = request.isUserInitiatedNavigation && !request.isRedirect
        switch place {
        case .window:
            return .stay
        case .newWindow:
            return isFollowedLink ? .openOutside(url) : .stay
        case .site:
            guard isFollowedLink else {
                return .stay
            }
            return contains(request.triggerUri ?? pageURL) ? .openOutside(url) : .stay
        }
    }

    static func isSignInRequest(_ url: URL) -> Bool {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return false
        }
        return items.contains { item in
            switch item.name {
            case "client_id", "SAMLRequest":
                return true
            case "wa":
                return item.value == "wsignin1.0"
            default:
                return false
            }
        }
    }

    // MARK: - Leaving The Site

    /// Opens the URL in Reynard when it is installed, else in the system's default browser.
    @MainActor
    func openOutside(_ url: URL) {
        guard !Self.bundleClaims(scheme: "reynard"),
              let encodedURL = url.absoluteString.addingPercentEncoding(
                withAllowedCharacters: CharacterSet(charactersIn: "-._~").union(.alphanumerics)
              ),
              let reynardURL = URL(string: "reynard://open?url=\(encodedURL)") else {
            Self.openInDefaultBrowser(url)
            return
        }

        UIApplication.shared.open(reynardURL, options: [:]) { opened in
            if !opened {
                Self.openInDefaultBrowser(url)
            }
        }
    }

    @MainActor
    private static func openInDefaultBrowser(_ url: URL) {
        // A site app must not claim web URLs; if it does, never hand a link back to itself.
        guard let scheme = url.scheme, !bundleClaims(scheme: scheme) else {
            return
        }
        UIApplication.shared.open(url, options: [:], completionHandler: nil)
    }

    private static func bundleClaims(scheme: String) -> Bool {
        let urlTypes = Bundle.main.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String: Any]] ?? []
        return urlTypes.contains { urlType in
            let schemes = urlType["CFBundleURLSchemes"] as? [String] ?? []
            return schemes.contains { $0.caseInsensitiveCompare(scheme) == .orderedSame }
        }
    }

    // MARK: - Name

    /// Puts the app's own name in place of "Reynard" in a user-visible string.
    static func appNamed(_ text: String) -> String {
        guard let current else {
            return text
        }
        return text
            .replacingOccurrences(of: "Reynard Browser", with: current.appName)
            .replacingOccurrences(of: "Reynard", with: current.appName)
    }

    // MARK: - Helpers

    fileprivate static func defaultPort(for scheme: String) -> Int {
        return scheme == "http" ? 80 : 443
    }
}
