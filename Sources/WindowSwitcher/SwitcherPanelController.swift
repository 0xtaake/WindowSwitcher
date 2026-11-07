import AppKit

private final class WindowCardView: NSView {
    var onHover: (() -> Void)?
    var onSelect: (() -> Void)?
    // Set before the card enters the view hierarchy. AppKit then creates a
    // tracking area only when the view is attached and mouse control is enabled.
    var mouseControlsEnabled = true
    private var tracking: NSTrackingArea?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        mouseControlsEnabled
    }

    override func updateTrackingAreas() {
        if let tracking {
            removeTrackingArea(tracking)
            self.tracking = nil
        }

        guard mouseControlsEnabled else {
            super.updateTrackingAreas()
            return
        }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        tracking = area
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        guard mouseControlsEnabled else { return }
        onHover?()
    }

    override func mouseDown(with event: NSEvent) {
        guard mouseControlsEnabled else { return }
        onSelect?()
    }
}

final class SwitcherPanelController {
    private var panel: NSPanel?
    var onHoverSelection: ((Int) -> Void)?
    var onClickSelection: ((Int) -> Void)?

    func show(
        windows: [WindowInfo],
        selectedIndex: Int,
        thumbnails: [CGWindowID: NSImage],
        settings: AppSettings
    ) {
        guard !windows.isEmpty else { hide(); return }

        let maxVisible = 12
        let capacity = min(maxVisible, windows.count)
        let columns = settings.visualStyle == .list ? 1 : min(settings.columns, capacity)
        let startIndex = min(
            max(selectedIndex - capacity / 2, 0),
            max(windows.count - capacity, 0)
        )
        let endIndex = min(startIndex + capacity, windows.count)
        let visibleWindows = Array(windows[startIndex..<endIndex])
        let visibleSelectedIndex = selectedIndex - startIndex

        let screen: NSScreen?
        if settings.mouseControlEnabled {
            screen = screenForPointer() ?? NSScreen.main ?? NSScreen.screens.first
        } else {
            // With mouse control disabled, avoid using the pointer for either
            // selection or monitor placement. Prefer the main screen instead.
            screen = NSScreen.main ?? NSScreen.screens.first
        }
        let screenFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let cardWidth: CGFloat = settings.visualStyle == .list ? 490 : (columns == 2 ? 250 : 226)
        let cardHeight: CGFloat = cardHeight(for: settings.visualStyle)
        let rowCount = Int(ceil(Double(visibleWindows.count) / Double(columns)))
        let headerHeight: CGFloat = 66
        let footerHeight: CGFloat = 36
        let verticalPadding: CGFloat = 32
        let horizontalPadding: CGFloat = settings.visualStyle == .list ? 36 : 36
        let gridHeight = CGFloat(rowCount) * cardHeight + CGFloat(max(0, rowCount - 1)) * 10
        let panelWidth = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * 10 + horizontalPadding
        let requestedHeight = headerHeight + gridHeight + footerHeight + verticalPadding
        let panelHeight = min(requestedHeight, max(360, screenFrame.height - 48))

        let panel = makePanelIfNeeded()
        panel.setContentSize(NSSize(width: panelWidth, height: panelHeight))
        panel.contentView = makeContentView(
            size: NSSize(width: panelWidth, height: panelHeight),
            windows: visibleWindows,
            selectedIndex: visibleSelectedIndex,
            totalCount: windows.count,
            firstVisibleIndex: startIndex,
            columns: columns,
            cardWidth: cardWidth,
            thumbnails: thumbnails,
            style: settings.visualStyle,
            mouseControlsEnabled: settings.mouseControlEnabled
        )
        applyAppearance(settings.appearance, to: panel)

        let origin = NSPoint(x: screenFrame.midX - panelWidth / 2, y: screenFrame.midY - panelHeight / 2)
        panel.setFrameOrigin(origin)
        panel.alphaValue = 1
        panel.orderFrontRegardless()
        panel.displayIfNeeded()
    }

    func hide() { panel?.orderOut(nil) }

    private func cardHeight(for style: SwitcherVisualStyle) -> CGFloat {
        switch style {
        case .thumbnails: return 174
        case .icons: return 146
        case .list: return 66
        }
    }

    private func applyAppearance(_ mode: String, to panel: NSPanel) {
        switch mode {
        case "light": panel.appearance = NSAppearance(named: .aqua)
        case "dark": panel.appearance = NSAppearance(named: .darkAqua)
        default: panel.appearance = nil
        }
    }

    private func screenForPointer() -> NSScreen? {
        let point = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(point, $0.frame, false) }
    }

    private func makePanelIfNeeded() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 620),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.becomesKeyOnlyIfNeeded = true
        self.panel = panel
        return panel
    }

    private func makeContentView(
        size: NSSize,
        windows: [WindowInfo],
        selectedIndex: Int,
        totalCount: Int,
        firstVisibleIndex: Int,
        columns: Int,
        cardWidth: CGFloat,
        thumbnails: [CGWindowID: NSImage],
        style: SwitcherVisualStyle,
        mouseControlsEnabled: Bool
    ) -> NSView {
        let effectView = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 20
        effectView.layer?.masksToBounds = true

        let rootStack = NSStackView()
        rootStack.orientation = .vertical
        rootStack.alignment = .centerX
        rootStack.distribution = .fill
        rootStack.spacing = 10
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let heading = NSTextField(labelWithString: "Fenster")
        heading.font = .systemFont(ofSize: 20, weight: .semibold)
        let subtitleText = mouseControlsEnabled
            ? "Hotkey wechseln · Shift rückwärts · loslassen zum Öffnen · Hover/Klick auswählen"
            : "Hotkey wechseln · Shift rückwärts · loslassen zum Öffnen · Maussteuerung deaktiviert"
        let subtitle = NSTextField(labelWithString: subtitleText)
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        let header = NSStackView(views: [heading, subtitle])
        header.orientation = .vertical
        header.alignment = .centerX
        header.spacing = 4
        rootStack.addArrangedSubview(header)

        for rowStart in stride(from: 0, to: windows.count, by: columns) {
            let rowEnd = min(rowStart + columns, windows.count)
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.distribution = .fillEqually
            row.spacing = 10

            for index in rowStart..<rowEnd {
                let window = windows[index]
                let globalIndex = firstVisibleIndex + index
                let card = makeCard(
                    for: window,
                    selected: index == selectedIndex,
                    thumbnail: thumbnails[window.id],
                    width: cardWidth,
                    height: cardHeight(for: style),
                    style: style,
                    mouseControlsEnabled: mouseControlsEnabled,
                    onHover: { [weak self] in self?.onHoverSelection?(globalIndex) },
                    onSelect: { [weak self] in self?.onClickSelection?(globalIndex) }
                )
                row.addArrangedSubview(card)
            }
            rootStack.addArrangedSubview(row)
        }

        let rangeText = totalCount > windows.count
            ? "Fenster \(firstVisibleIndex + 1)–\(firstVisibleIndex + windows.count) von \(totalCount)"
            : "\(totalCount) Fenster"
        let footer = NSTextField(labelWithString: rangeText)
        footer.font = .systemFont(ofSize: 10)
        footer.textColor = .secondaryLabelColor
        rootStack.addArrangedSubview(footer)

        effectView.addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: effectView.leadingAnchor, constant: 18),
            rootStack.trailingAnchor.constraint(equalTo: effectView.trailingAnchor, constant: -18),
            rootStack.topAnchor.constraint(equalTo: effectView.topAnchor, constant: 16),
            rootStack.bottomAnchor.constraint(lessThanOrEqualTo: effectView.bottomAnchor, constant: -16)
        ])
        return effectView
    }

    private func makeCard(
        for window: WindowInfo,
        selected: Bool,
        thumbnail: NSImage?,
        width: CGFloat,
        height: CGFloat,
        style: SwitcherVisualStyle,
        mouseControlsEnabled: Bool,
        onHover: @escaping () -> Void,
        onSelect: @escaping () -> Void
    ) -> NSView {
        let card = WindowCardView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        card.mouseControlsEnabled = mouseControlsEnabled
        card.onHover = mouseControlsEnabled ? onHover : nil
        card.onSelect = mouseControlsEnabled ? onSelect : nil
        card.wantsLayer = true
        card.layer?.cornerRadius = 12
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.78).cgColor
        card.layer?.borderWidth = selected ? 2.5 : 1
        card.layer?.borderColor = selected ? NSColor.controlAccentColor.cgColor : NSColor.separatorColor.withAlphaComponent(0.7).cgColor
        card.translatesAutoresizingMaskIntoConstraints = false
        card.widthAnchor.constraint(equalToConstant: width).isActive = true
        card.heightAnchor.constraint(equalToConstant: height).isActive = true

        let appIcon = NSImageView()
        appIcon.image = window.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)
        appIcon.imageScaling = .scaleProportionallyDown
        appIcon.translatesAutoresizingMaskIntoConstraints = false

        let appLabel = NSTextField(labelWithString: window.appName)
        appLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        appLabel.lineBreakMode = .byTruncatingTail
        let titleLabel = NSTextField(labelWithString: window.title)
        titleLabel.font = .systemFont(ofSize: 10)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.lineBreakMode = .byTruncatingTail

        var labelViews: [NSView] = [appLabel, titleLabel]
        if let status = window.statusLabel {
            let stateLabel = NSTextField(labelWithString: status)
            stateLabel.font = .systemFont(ofSize: 9, weight: .medium)
            stateLabel.textColor = .tertiaryLabelColor
            labelViews.append(stateLabel)
        }
        let labels = NSStackView(views: labelViews)
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        if style == .list {
            appIcon.widthAnchor.constraint(equalToConstant: 34).isActive = true
            appIcon.heightAnchor.constraint(equalToConstant: 34).isActive = true
            let info = NSStackView(views: [appIcon, labels])
            info.orientation = .horizontal
            info.alignment = .centerY
            info.spacing = 10
            info.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(info)
            NSLayoutConstraint.activate([
                info.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 12),
                info.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -12),
                info.centerYAnchor.constraint(equalTo: card.centerYAnchor)
            ])
        } else {
            let preview = NSView()
            preview.wantsLayer = true
            preview.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.16).cgColor
            preview.translatesAutoresizingMaskIntoConstraints = false
            preview.heightAnchor.constraint(equalToConstant: style == .thumbnails ? 112 : 86).isActive = true

            if style == .thumbnails, let thumbnail {
                let imageView = NSImageView()
                imageView.image = thumbnail
                imageView.imageScaling = .scaleProportionallyUpOrDown
                imageView.translatesAutoresizingMaskIntoConstraints = false
                preview.addSubview(imageView)
                NSLayoutConstraint.activate([
                    imageView.leadingAnchor.constraint(equalTo: preview.leadingAnchor, constant: 4),
                    imageView.trailingAnchor.constraint(equalTo: preview.trailingAnchor, constant: -4),
                    imageView.topAnchor.constraint(equalTo: preview.topAnchor, constant: 4),
                    imageView.bottomAnchor.constraint(equalTo: preview.bottomAnchor, constant: -4)
                ])
            } else {
                let iconView = NSImageView()
                iconView.image = window.icon ?? NSImage(systemSymbolName: "macwindow", accessibilityDescription: nil)
                iconView.imageScaling = .scaleProportionallyDown
                iconView.translatesAutoresizingMaskIntoConstraints = false
                preview.addSubview(iconView)
                let dimension: CGFloat = style == .icons ? 58 : 42
                NSLayoutConstraint.activate([
                    iconView.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
                    iconView.centerYAnchor.constraint(equalTo: preview.centerYAnchor),
                    iconView.widthAnchor.constraint(equalToConstant: dimension),
                    iconView.heightAnchor.constraint(equalToConstant: dimension)
                ])
            }

            appIcon.widthAnchor.constraint(equalToConstant: 23).isActive = true
            appIcon.heightAnchor.constraint(equalToConstant: 23).isActive = true
            let info = NSStackView(views: [appIcon, labels])
            info.orientation = .horizontal
            info.alignment = .centerY
            info.spacing = 8
            info.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(preview)
            card.addSubview(info)
            NSLayoutConstraint.activate([
                preview.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 8),
                preview.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -8),
                preview.topAnchor.constraint(equalTo: card.topAnchor, constant: 8),
                info.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 10),
                info.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -10),
                info.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 6),
                info.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -6)
            ])
        }
        return card
    }
}
