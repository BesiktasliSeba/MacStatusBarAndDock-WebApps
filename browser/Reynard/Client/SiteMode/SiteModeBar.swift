//
//  SiteModeBar.swift
//  Reynard
//
//  Site mode for MacStatusBar&Dock web apps. Added in the MacStatusBarAndDock-WebApps fork.
//

import UIKit

/// The only browser chrome in site mode. It shows while the app displays a window the site
/// opened (a sign-in window, for example) or a page outside the site, and stays hidden
/// otherwise. It names the page's host, and its button closes that window or goes back to the
/// site's start page.
final class SiteModeBar: UIView {
    enum Mode: Equatable {
        case hidden
        case popup(host: String)
        case outside(host: String)
    }

    private enum UX {
        static let height: CGFloat = 40
        static let buttonSide: CGFloat = 40
    }

    var onClose: (() -> Void)?
    private(set) var mode: Mode = .hidden

    private let closeButton = UIButton(type: .system)
    private let hostLabel = UILabel()
    private let separator = UIView()
    private lazy var heightConstraint = heightAnchor.constraint(equalToConstant: 0)

    override init(frame: CGRect) {
        super.init(frame: frame)
        translatesAutoresizingMaskIntoConstraints = false
        backgroundColor = .secondarySystemBackground
        clipsToBounds = true
        isHidden = true

        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        hostLabel.translatesAutoresizingMaskIntoConstraints = false
        hostLabel.font = .preferredFont(forTextStyle: .footnote)
        hostLabel.adjustsFontForContentSizeCategory = true
        hostLabel.textColor = .secondaryLabel
        hostLabel.textAlignment = .center
        hostLabel.lineBreakMode = .byTruncatingMiddle

        separator.translatesAutoresizingMaskIntoConstraints = false
        separator.backgroundColor = .separator

        addSubview(closeButton)
        addSubview(hostLabel)
        addSubview(separator)

        NSLayoutConstraint.activate([
            heightConstraint,
            closeButton.leadingAnchor.constraint(equalTo: layoutMarginsGuide.leadingAnchor),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            closeButton.widthAnchor.constraint(equalToConstant: UX.buttonSide),
            closeButton.heightAnchor.constraint(equalToConstant: UX.buttonSide),
            hostLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            hostLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            hostLabel.leadingAnchor.constraint(greaterThanOrEqualTo: closeButton.trailingAnchor, constant: 8),
            hostLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutMarginsGuide.trailingAnchor, constant: -UX.buttonSide - 8),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: bottomAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setMode(_ mode: Mode) {
        guard mode != self.mode else {
            return
        }
        self.mode = mode

        switch mode {
        case .hidden:
            hostLabel.text = nil
        case .popup(let host):
            hostLabel.text = host
            closeButton.accessibilityLabel = NSLocalizedString("Close", comment: "")
        case .outside(let host):
            hostLabel.text = host
            closeButton.accessibilityLabel = String(
                format: NSLocalizedString("Back to %@", comment: "Site mode: return to the web app's start page"),
                SiteMode.current?.appName ?? ""
            )
        }
        isHidden = mode == .hidden
        heightConstraint.constant = mode == .hidden ? 0 : UX.height
    }

    @objc private func closeTapped() {
        onClose?()
    }
}
