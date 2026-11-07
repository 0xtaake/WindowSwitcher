import AppKit

/// AppKit-only preferences UI with a deliberately simple, constraint-based layout.
/// A segmented page selector is used instead of NSTabView because the latter's
/// content view was being compressed on some macOS/Command Line Tools builds.
final class SettingsViewController: NSViewController {
    private var draft: AppSettings
    private let onSave: (AppSettings) -> Void
    private let onCancel: () -> Void

    private let pageSelector = NSSegmentedControl(
        labels: ["Allgemein", "Fenster", "Tastatur"],
        trackingMode: .selectOne,
        target: nil,
        action: nil
    )
    private let pageHost = NSView()
    private var pages: [NSView] = []

    private let visualStylePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let appearancePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let columnsStepper = NSStepper(frame: .zero)
    private let columnsValue = NSTextField(labelWithString: "")
    private let mouseControlCheckbox = NSButton(
        checkboxWithTitle: "Maussteuerung aktivieren (Hover und Klick)",
        target: nil,
        action: nil
    )

    private let includeMinimizedCheckbox = NSButton(checkboxWithTitle: "Minimierte Fenster einschließen", target: nil, action: nil)
    private let includeHiddenCheckbox = NSButton(checkboxWithTitle: "Fenster ausgeblendeter Apps einschließen", target: nil, action: nil)
    private let includeOtherSpacesCheckbox = NSButton(checkboxWithTitle: "Fenster anderer Spaces einschließen", target: nil, action: nil)
    private let excludeCurrentApplicationCheckbox = NSButton(
        checkboxWithTitle: "Aktive Anwendung ausblenden",
        target: nil,
        action: nil
    )
    private let excludedIDsField = NSTextField(string: "")

    private let shortcutKeyPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let optionCheckbox = NSButton(checkboxWithTitle: "Option (⌥)", target: nil, action: nil)
    private let commandCheckbox = NSButton(checkboxWithTitle: "Command (⌘)", target: nil, action: nil)
    private let controlCheckbox = NSButton(checkboxWithTitle: "Control (⌃)", target: nil, action: nil)
    private let shortcutWarning = NSTextField(labelWithString: "")

    init(settings: AppSettings, onSave: @escaping (AppSettings) -> Void, onCancel: @escaping () -> Void) {
        self.draft = settings
        self.onSave = onSave
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        configureControls()

        let root = NSView(frame: NSRect(x: 0, y: 0, width: 800, height: 620))
        root.wantsLayer = true

        pageSelector.selectedSegment = 0
        pageSelector.segmentStyle = .rounded
        pageSelector.setWidth(150, forSegment: 0)
        pageSelector.setWidth(150, forSegment: 1)
        pageSelector.setWidth(150, forSegment: 2)
        pageSelector.target = self
        pageSelector.action = #selector(pageSelectionChanged)
        pageSelector.translatesAutoresizingMaskIntoConstraints = false

        pageHost.translatesAutoresizingMaskIntoConstraints = false

        pages = [makeGeneralView(), makeWindowsView(), makeKeyboardView()]
        for (index, page) in pages.enumerated() {
            page.translatesAutoresizingMaskIntoConstraints = false
            page.isHidden = index != 0
            pageHost.addSubview(page)
            NSLayoutConstraint.activate([
                page.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor),
                page.trailingAnchor.constraint(equalTo: pageHost.trailingAnchor),
                page.topAnchor.constraint(equalTo: pageHost.topAnchor),
                page.bottomAnchor.constraint(equalTo: pageHost.bottomAnchor)
            ])
        }

        let cancelButton = NSButton(title: "Abbrechen", target: self, action: #selector(cancelSettings))
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"

        let saveButton = NSButton(title: "Speichern", target: self, action: #selector(saveSettings))
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        let spacer = NSView()
        let buttonRow = NSStackView(views: [spacer, cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.alignment = .centerY
        buttonRow.distribution = .fill
        buttonRow.spacing = 10
        buttonRow.translatesAutoresizingMaskIntoConstraints = false

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(pageSelector)
        root.addSubview(pageHost)
        root.addSubview(divider)
        root.addSubview(buttonRow)

        NSLayoutConstraint.activate([
            pageSelector.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 22),
            pageSelector.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),
            pageSelector.heightAnchor.constraint(equalToConstant: 30),

            pageHost.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            pageHost.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            pageHost.topAnchor.constraint(equalTo: pageSelector.bottomAnchor, constant: 14),
            pageHost.bottomAnchor.constraint(equalTo: divider.topAnchor, constant: -12),

            divider.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: buttonRow.topAnchor, constant: -10),

            buttonRow.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 18),
            buttonRow.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -18),
            buttonRow.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -14),
            buttonRow.heightAnchor.constraint(equalToConstant: 36)
        ])

        preferredContentSize = NSSize(width: 800, height: 620)
        self.view = root
    }

    private func configureControls() {
        visualStylePopup.addItems(withTitles: SwitcherVisualStyle.allCases.map(\.title))
        visualStylePopup.selectItem(withTitle: draft.visualStyle.title)
        visualStylePopup.widthAnchor.constraint(equalToConstant: 250).isActive = true

        appearancePopup.addItems(withTitles: ["System", "Hell", "Dunkel"])
        appearancePopup.selectItem(withTitle: appearanceTitle(for: draft.appearance))
        appearancePopup.widthAnchor.constraint(equalToConstant: 250).isActive = true

        columnsStepper.minValue = 2
        columnsStepper.maxValue = 5
        columnsStepper.increment = 1
        columnsStepper.integerValue = draft.columns
        columnsValue.stringValue = "\(draft.columns) Spalten"
        columnsStepper.target = self
        columnsStepper.action = #selector(columnsChanged)

        mouseControlCheckbox.state = draft.mouseControlEnabled ? .on : .off

        includeMinimizedCheckbox.state = draft.includeMinimizedWindows ? .on : .off
        includeHiddenCheckbox.state = draft.includeHiddenApplications ? .on : .off
        includeOtherSpacesCheckbox.state = draft.includeWindowsOnOtherSpaces ? .on : .off
        excludeCurrentApplicationCheckbox.state = draft.excludeCurrentApplicationFromSwitcher ? .on : .off
        excludedIDsField.stringValue = draft.excludedBundleIdentifiers.joined(separator: ", ")
        excludedIDsField.placeholderString = "com.apple.finder, com.apple.Terminal"
        excludedIDsField.widthAnchor.constraint(equalToConstant: 690).isActive = true

        shortcutKeyPopup.addItems(withTitles: ShortcutKey.allCases.map(\.title))
        shortcutKeyPopup.selectItem(withTitle: draft.shortcutKey.title)
        shortcutKeyPopup.widthAnchor.constraint(equalToConstant: 250).isActive = true
        optionCheckbox.state = draft.shortcutUsesOption ? .on : .off
        commandCheckbox.state = draft.shortcutUsesCommand ? .on : .off
        controlCheckbox.state = draft.shortcutUsesControl ? .on : .off
        updateShortcutWarning()
        optionCheckbox.target = self
        optionCheckbox.action = #selector(modifierChanged)
        commandCheckbox.target = self
        commandCheckbox.action = #selector(modifierChanged)
        controlCheckbox.target = self
        controlCheckbox.action = #selector(modifierChanged)
    }

    private func makeGeneralView() -> NSView {
        let styleRow = labeledRow("Ansicht", control: visualStylePopup)
        let appearanceRow = labeledRow("Erscheinungsbild", control: appearancePopup)
        let columnsControls = NSStackView(views: [columnsStepper, columnsValue])
        columnsControls.orientation = .horizontal
        columnsControls.alignment = .centerY
        columnsControls.spacing = 8
        let columnsRow = labeledRow("Kachelraster", control: columnsControls)
        let spacesHelp = wrappingLabel("Fenster anderer Spaces werden nach Möglichkeit anhand der macOS-Fensterliste erkannt. Eine eindeutige Space-ID stellt macOS über diese öffentliche Schnittstelle nicht bereit.", width: 690)
        let mouseHelp = wrappingLabel("Wenn deaktiviert, reagieren die Fensterkarten weder auf Mausbewegungen noch auf Mausklicks. Die Navigation mit Tastatur und Tastenkombinationen bleibt vollständig verfügbar.", width: 690)
        return makePage([
            sectionLabel("Darstellung"), styleRow, appearanceRow, columnsRow,
            NSBox.separator(),
            sectionLabel("Maussteuerung"), mouseControlCheckbox, mouseHelp,
            spacesHelp
        ])
    }

    private func makeWindowsView() -> NSView {
        let exclusionsHint = wrappingLabel("Bundle-Identifier der auszuschließenden Apps, durch Kommas getrennt. Die Änderung wird beim Speichern übernommen.", width: 690)
        let activeApplicationHint = wrappingLabel(
            "Alle Fenster der Anwendung, die beim Öffnen von Option + Tab im Vordergrund ist, werden ausgeblendet. Die Erkennung nutzt Prozess-ID und Bundle-ID statt AXWindowNumber – wichtig für Brave und andere Chromium-Browser.",
            width: 690
        )
        return makePage([
            sectionLabel("Welche Fenster anzeigen?"),
            includeMinimizedCheckbox,
            includeHiddenCheckbox,
            includeOtherSpacesCheckbox,
            NSBox.separator(),
            sectionLabel("Aktuelle Anwendung"),
            excludeCurrentApplicationCheckbox,
            activeApplicationHint,
            NSBox.separator(),
            sectionLabel("Ausnahmen"),
            exclusionsHint,
            excludedIDsField
        ])
    }

    private func makeKeyboardView() -> NSView {
        let keyRow = labeledRow("Taste", control: shortcutKeyPopup)
        let note = wrappingLabel("Shift (⇧) bleibt für die Navigation rückwärts reserviert. Mindestens eine Zusatztaste muss aktiviert sein.", width: 690)
        return makePage([
            sectionLabel("Globale Tastenkombination"),
            keyRow,
            optionCheckbox,
            commandCheckbox,
            controlCheckbox,
            shortcutWarning,
            note
        ])
    }

    private func makePage(_ arrangedViews: [NSView]) -> NSView {
        let page = NSView(frame: NSRect(x: 0, y: 0, width: 760, height: 480))
        let stack = NSStackView(views: arrangedViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.distribution = .fill
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        page.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: page.leadingAnchor, constant: 22),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: page.trailingAnchor, constant: -22),
            stack.topAnchor.constraint(equalTo: page.topAnchor, constant: 22),
            stack.widthAnchor.constraint(equalTo: page.widthAnchor, constant: -44),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: page.bottomAnchor, constant: -20)
        ])
        return page
    }

    private func labeledRow(_ title: String, control: NSView) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13)
        label.widthAnchor.constraint(equalToConstant: 150).isActive = true
        label.setContentHuggingPriority(.required, for: .horizontal)

        let row = NSStackView(views: [label, control])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.distribution = .fill
        row.spacing = 16
        return row
    }

    private func sectionLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 14, weight: .semibold)
        return label
    }

    private func wrappingLabel(_ text: String, width: CGFloat) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.widthAnchor.constraint(equalToConstant: width).isActive = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    private func appearanceTitle(for value: String) -> String {
        switch value {
        case "light": return "Hell"
        case "dark": return "Dunkel"
        default: return "System"
        }
    }

    @objc private func pageSelectionChanged() {
        let selected = pageSelector.selectedSegment
        guard pages.indices.contains(selected) else { return }
        for (index, page) in pages.enumerated() { page.isHidden = index != selected }
    }

    @objc private func columnsChanged() {
        columnsValue.stringValue = "\(columnsStepper.integerValue) Spalten"
    }

    @objc private func modifierChanged() { updateShortcutWarning() }

    private func updateShortcutWarning() {
        let valid = optionCheckbox.state == .on || commandCheckbox.state == .on || controlCheckbox.state == .on
        shortcutWarning.stringValue = valid ? "" : "⚠ Bitte mindestens eine Zusatztaste auswählen."
        shortcutWarning.textColor = .systemOrange
    }

    @objc private func cancelSettings() { onCancel() }

    @objc private func saveSettings() {
        var result = draft
        if let styleTitle = visualStylePopup.selectedItem?.title,
           let style = SwitcherVisualStyle.allCases.first(where: { $0.title == styleTitle }) {
            result.visualStyle = style
        }
        switch appearancePopup.titleOfSelectedItem ?? "System" {
        case "Hell": result.appearance = "light"
        case "Dunkel": result.appearance = "dark"
        default: result.appearance = "system"
        }
        result.columns = min(max(columnsStepper.integerValue, 2), 5)
        result.mouseControlEnabled = mouseControlCheckbox.state == .on
        result.includeMinimizedWindows = includeMinimizedCheckbox.state == .on
        result.includeHiddenApplications = includeHiddenCheckbox.state == .on
        result.includeWindowsOnOtherSpaces = includeOtherSpacesCheckbox.state == .on
        result.excludeCurrentApplicationFromSwitcher = excludeCurrentApplicationCheckbox.state == .on
        result.excludedBundleIdentifiers = excludedIDsField.stringValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        if let keyTitle = shortcutKeyPopup.selectedItem?.title,
           let key = ShortcutKey.allCases.first(where: { $0.title == keyTitle }) {
            result.shortcutKey = key
        }
        result.shortcutUsesOption = optionCheckbox.state == .on
        result.shortcutUsesCommand = commandCheckbox.state == .on
        result.shortcutUsesControl = controlCheckbox.state == .on

        guard result.hasValidShortcut else {
            updateShortcutWarning()
            pageSelector.selectedSegment = 2
            pageSelectionChanged()
            return
        }
        onSave(result)
    }
}

private extension NSBox {
    static func separator() -> NSBox {
        let box = NSBox()
        box.boxType = .separator
        return box
    }
}
