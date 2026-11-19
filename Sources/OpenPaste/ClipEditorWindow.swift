import AppKit

@MainActor
final class ClipEditorWindow: NSWindow {
    private let editor = NSTextView()
    private let onSave: (String, Data?) throws -> Void
    private let onClose: () -> Void

    init(
        text: String, richText: Data?, onSave: @escaping (String, Data?) throws -> Void,
        onClose: @escaping () -> Void
    ) {
        self.onSave = onSave
        self.onClose = onClose
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 360),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        title = "Редактирование карточки"
        contentMinSize = NSSize(width: 340, height: 240)
        isReleasedWhenClosed = false

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.documentView = editor
        editor.isRichText = true
        editor.importsGraphics = false
        editor.allowsUndo = true
        editor.isVerticallyResizable = true
        editor.autoresizingMask = [.width]
        editor.textContainer?.widthTracksTextView = true
        editor.textContainerInset = NSSize(width: 10, height: 10)
        editor.backgroundColor = .textBackgroundColor
        editor.insertionPointColor = .textColor
        let font = NSFont.systemFont(ofSize: 15)
        editor.font = font
        let formatted = richText.flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }
        let content = NSMutableAttributedString(
            attributedString: formatted
                ?? NSAttributedString(string: text, attributes: [.font: font]))
        let range = NSRange(location: 0, length: content.length)
        content.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
        content.removeAttribute(.backgroundColor, range: range)
        editor.textStorage?.setAttributedString(content)
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        editor.typingAttributes[.foregroundColor] = NSColor.textColor

        let formats = NSStackView(views: [
            button("Жирный", icon: "bold", action: #selector(format(_:)), tag: 0),
            button("Курсив", icon: "italic", action: #selector(format(_:)), tag: 1),
            button("Подчёркнутый", icon: "underline", action: #selector(format(_:)), tag: 2),
            button("Зачёркнутый", icon: "strikethrough", action: #selector(format(_:)), tag: 3),
        ])
        formats.spacing = 4

        let cancel = button("Отменить", action: #selector(cancelEdit))
        cancel.keyEquivalent = "\u{1b}"
        cancel.keyEquivalentModifierMask = []
        let save = button("Сохранить", action: #selector(saveEdit))
        save.keyEquivalent = "\r"
        save.keyEquivalentModifierMask = [.command]
        save.bezelColor = .controlAccentColor
        let footer = NSStackView(views: [NSView(), cancel, save])
        footer.spacing = 8

        let stack = NSStackView(views: [formats, scroll, footer])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        contentView = stack
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: formats.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: stack.trailingAnchor, constant: -14),
            footer.widthAnchor.constraint(equalTo: scroll.widthAnchor),
        ])
        initialFirstResponder = editor
    }

    private func button(_ name: String, icon: String? = nil, action: Selector, tag: Int = 0)
        -> NSButton
    {
        let button = NSButton(title: name, target: self, action: action)
        if let icon {
            button.image = NSImage(systemSymbolName: icon, accessibilityDescription: name)
            button.imagePosition = .imageOnly
            button.toolTip = name
            button.setAccessibilityLabel(name)
        }
        button.tag = tag
        return button
    }

    @objc private func format(_ sender: NSButton) {
        let range = editor.selectedRange()
        let selection = editor.attributedString().attributedSubstring(from: range)
        let traits: NSFontTraitMask = sender.tag == 0 ? .boldFontMask : .italicFontMask
        let key: NSAttributedString.Key = sender.tag == 2 ? .underlineStyle : .strikethroughStyle
        let fonts = NSFontManager.shared
        let first =
            range.length == 0
            ? editor.typingAttributes : selection.attributes(at: 0, effectiveRange: nil)
        let firstFont = first[.font] as? NSFont ?? .systemFont(ofSize: 15)
        let enabled =
            sender.tag < 2
            ? fonts.traits(of: firstFont).contains(traits) : (first[key] as? Int ?? 0) != 0

        func updated(_ attributes: [NSAttributedString.Key: Any]) -> [NSAttributedString.Key: Any] {
            var attributes = attributes
            if sender.tag < 2 {
                let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: 15)
                attributes[.font] =
                    enabled
                    ? fonts.convert(font, toNotHaveTrait: traits)
                    : fonts.convert(font, toHaveTrait: traits)
            } else {
                attributes[key] = enabled ? nil : NSUnderlineStyle.single.rawValue
            }
            return attributes
        }

        if range.length == 0 {
            editor.typingAttributes = updated(first)
        } else {
            let formatted = NSMutableAttributedString(attributedString: selection)
            selection.enumerateAttributes(in: NSRange(location: 0, length: selection.length)) {
                attributes, run, _ in
                formatted.setAttributes(updated(attributes), range: run)
            }
            editor.insertText(formatted, replacementRange: range)
            editor.setSelectedRange(range)
        }
        makeFirstResponder(editor)
    }

    @objc private func saveEdit() {
        let text = NSMutableAttributedString(attributedString: editor.attributedString())
        let range = NSRange(location: 0, length: text.length)
        // The receiving app supplies its own text colors.
        text.removeAttribute(.foregroundColor, range: range)
        text.removeAttribute(.backgroundColor, range: range)
        var formatted = false
        text.enumerateAttributes(in: range) { attributes, _, stop in
            let font = attributes[.font] as? NSFont ?? .systemFont(ofSize: 15)
            let traits = NSFontManager.shared.traits(of: font)
            formatted =
                !traits.intersection([.boldFontMask, .italicFontMask]).isEmpty
                || (attributes[.underlineStyle] as? Int ?? 0) != 0
                || (attributes[.strikethroughStyle] as? Int ?? 0) != 0
            if formatted { stop.pointee = true }
        }
        do {
            let richText =
                formatted
                ? try text.data(
                    from: range,
                    documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]) : nil
            try onSave(text.string, richText)
            close()
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Не удалось сохранить карточку"
            alert.beginSheetModal(for: self)
        }
    }

    @objc private func cancelEdit() { close() }

    override func close() {
        super.close()
        onClose()
    }
}
