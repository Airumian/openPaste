import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PanelView: View {
    let store: ClipStore
    let shortcuts: ShortcutStore
    @Bindable var state: PanelState
    let onPaste: (Clip) -> Void
    let onDelete: (Clip) -> Void
    let onSwitchBoard: (UUID?) -> Void
    let onPin: (Clip, Pinboard) -> Void
    let onSettings: () -> Void
    @FocusState private var focus: Field?
    @State private var boardName = ""
    @State private var dropTarget: UUID?
    @State private var clipTitleDraft = ""
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Field { case search, boardName }
    static let boardColors: [(name: String, color: Color)] = [
        ("Оранжевый", .orange), ("Зелёный", .green), ("Синий", .blue), ("Розовый", .pink),
        ("Фиолетовый", .purple), ("Жёлтый", .yellow), ("Красный", .red), ("Серый", .gray),
    ]
    /// Order of the swatch row in the menu; indices stay stable so saved pinboards keep their color.
    private static let paletteOrder = [6, 0, 5, 1, 2, 4, 3, 7]

    static func color(of board: Pinboard) -> Color {
        boardColors[board.color % boardColors.count].color
    }

    /// Menus render SF Symbols as monochrome templates, so color swatches are drawn as plain images.
    /// The palette menu scales the image up, so the dot is drawn inset to land at Finder-tag size;
    /// the selected color gets a ring, since the default selection effect is off (.custom).
    private static func swatch(_ color: Color, selected: Bool) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 3, dy: 3)).fill()
            if selected {
                // Dark halo around the selected dot, as in the Finder-style tag picker.
                let ring = NSBezierPath(ovalIn: rect.insetBy(dx: 1.25, dy: 1.25))
                ring.lineWidth = 2.5
                NSColor.black.withAlphaComponent(0.75).setStroke()
                ring.stroke()
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    /// A hidden panel renders nothing, so copies made while it's closed don't rebuild the card list.
    /// Transparent margin around the glass inside the panel window: keeps the 8 pt gap to the screen edges
    /// and leaves room for the glass shadow, which would otherwise be clipped into gray corner wedges.
    static let shadowRoom = EdgeInsets(top: 0, leading: 8, bottom: 8, trailing: 8)  // window 332 pt, as in Paste

    var body: some View {
        ZStack {  // stable container, so inserting the content runs its transition
            if state.isVisible {
                panelContent
                    .padding(Self.shadowRoom)
                    .transition(
                        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .onAppear {
                        DispatchQueue.main.async { focus = .search }
                    }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panelContent: some View {
        let clips = state.visibleClips(store)
        return VStack(spacing: 8) {
            HStack(spacing: 10) {
                // Mirrors the "⋯" button so the header group stays centered.
                Color.clear.frame(width: 34, height: 34)
                ZStack {
                    if searchMode {
                        // Search mode, as in Paste: a wide field dead-center, tabs shrink to icons on its right.
                        HStack(spacing: 0) {
                            Color.clear.frame(maxWidth: .infinity)
                            Color.clear.frame(width: Self.searchFieldWidth + 24)
                            ScrollView(.horizontal) { compactTabs }
                                .scrollIndicators(.hidden)
                                .frame(maxWidth: .infinity)
                        }
                    } else {
                        // Fits: one centered group, nothing scrolls. Too many pinboards: search and "+" stay pinned
                        // to the edges and only the tabs between them scroll.
                        ViewThatFits(in: .horizontal) {
                            headerRow(scrolling: false) { tabsRow }
                            headerRow(scrolling: true) {
                                ScrollViewReader { proxy in
                                    ScrollView(.horizontal) { tabsRow.padding(.horizontal, 4) }
                                        .scrollIndicators(.hidden)
                                        .onChange(of: state.board) { _, board in
                                            withAnimation(reduceMotion ? nil : .default) {
                                                proxy.scrollTo(
                                                    board?.uuidString ?? "history", anchor: .center)
                                            }
                                        }
                                        .onChange(of: state.boardEditor) { _, editor in
                                            if editor == .new {
                                                withAnimation(reduceMotion ? nil : .default) {
                                                    proxy.scrollTo("new", anchor: .trailing)
                                                }
                                            }
                                        }
                                }
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)  // fills the row, so "⋯" sits at the right edge
                // One persistent field over both layouts: typing right after opening lands in it,
                // and switching layouts never loses the caret.
                .overlay { searchField }
                moreMenu
            }
            .padding(.horizontal, 20)
            .frame(height: 36)

            if clips.isEmpty {
                Text(
                    !state.query.isEmpty
                        ? "Ничего не найдено"
                        : state.board == nil ? "История пуста" : "Пинборд пуст"
                )
                .font(.system(size: 22))  // large and quiet, as in Paste
                .foregroundStyle(.tertiary)
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal) {
                        LazyHStack(spacing: 24) {
                            ForEach(Array(clips.enumerated()), id: \.element.id) { i, clip in
                                card(clip, index: i)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .scrollIndicators(.hidden)
                    .onChange(of: state.selection) { _, i in
                        guard clips.indices.contains(i) else { return }
                        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) {
                            proxy.scrollTo(clips[i].id, anchor: .center)
                        }
                    }
                    .onChange(of: state.shownAt) { _, _ in
                        if let first = clips.first { proxy.scrollTo(first.id, anchor: .leading) }
                    }
                    .onChange(of: state.board) { _, _ in
                        if let first = clips.first { proxy.scrollTo(first.id, anchor: .leading) }
                    }
                }
            }
        }
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .liquidGlass(in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .onChange(of: state.query) { _, _ in state.selection = 0 }
        .onChange(of: state.shownAt) { _, _ in focus = .search }
        .onChange(of: state.boardEditor) { _, editor in focus = editor == nil ? .search : .boardName
        }
    }

    private func card(_ clip: Clip, index i: Int) -> some View {
        CardView(
            clip: clip, index: i + 1, selected: i == state.selection,
            now: state.shownAt,
            thumbnail: [.image, .file].contains(clip.kind) ? store.thumbnail(clip) : nil,
            titleDraft: state.renamingClip == clip.id ? $clipTitleDraft : nil,
            onCommitTitle: {
                store.rename(clip, to: clipTitleDraft)
                state.renamingClip = nil
            }
        )
        .id(clip.id)
        // Single click selects at once; a sequential double-tap gesture would delay it by the double-click interval.
        .onTapGesture { state.selection = i }
        .simultaneousGesture(TapGesture(count: 2).onEnded { onPaste(clip) })
        // Tap gestures are invisible to VoiceOver: expose the card as a button whose default action pastes.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onPaste(clip) }
        .accessibilityAction(named: "Удалить") { onDelete(clip) }
        .onDrag {
            state.dragging = clip
            // Real content, so the card can also be dropped into other apps.
            if let file = clip.files.first, let provider = NSItemProvider(contentsOf: file) {
                return provider
            }
            if let text = store.fullText(clip) { return NSItemProvider(object: text as NSString) }
            if let url = store.imageURL(clip), let provider = NSItemProvider(contentsOf: url) {
                return provider
            }
            return NSItemProvider()
        }
        .contextMenu {
            Button("Вставить") { onPaste(clip) }
            Button("Переименовать") {
                clipTitleDraft = clip.title ?? CardView.defaultTitle(clip)
                state.selection = i
                state.renamingClip = clip.id
            }
            if !store.pinboards.isEmpty {
                Menu("Закрепить в") {
                    ForEach(Array(store.pinboards.enumerated()), id: \.element.id) { n, board in
                        if board.id != clip.pinboardID {
                            if n < 9, shortcuts.pinboardModifier != .disabled {
                                Button(board.name) { onPin(clip, board) }
                                    .keyboardShortcut(
                                        KeyEquivalent(Character("\(n + 1)")),
                                        modifiers: shortcuts.pinboardModifier.eventModifiers)
                            } else {
                                Button(board.name) { onPin(clip, board) }
                            }
                        }
                    }
                }
            }
            Button(clip.pinboardID == nil ? "Удалить" : "Открепить", role: .destructive) {
                onDelete(clip)
            }
        }
    }

    private func boardTab(_ board: Pinboard, index i: Int, compact: Bool = false) -> some View {
        let targeted = Binding(
            get: { dropTarget == board.id },
            set: { on in
                if on { dropTarget = board.id } else if dropTarget == board.id { dropTarget = nil }
            })
        return tab(
            board.id, title: board.name,
            icon: Circle().fill(Self.color(of: board)).frame(width: 12, height: 12),
            compact: compact
        )
        .simultaneousGesture(TapGesture(count: 2).onEnded { startRename(board) })
        .overlay(
            Capsule().strokeBorder(Color.accentColor, lineWidth: 2).opacity(
                dropTarget == board.id ? 1 : 0)
        )
        .onDrag {
            state.dragging = nil
            let provider = NSItemProvider()
            provider.suggestedName = board.id.uuidString
            provider.registerDataRepresentation(
                forTypeIdentifier: Self.pinboardDropType.identifier, visibility: .ownProcess
            ) { completion in
                completion(Data(), nil)
                return nil
            }
            return provider
        }
        .onDrop(of: [.item, Self.pinboardDropType], isTargeted: targeted) { providers in
            if let provider = providers.first(where: {
                $0.hasItemConformingToTypeIdentifier(Self.pinboardDropType.identifier)
            }) {
                guard let name = provider.suggestedName, let source = UUID(uuidString: name),
                    let from = store.pinboards.firstIndex(where: { $0.id == source }),
                    let to = store.pinboards.firstIndex(where: { $0.id == board.id })
                else { return false }
                withAnimation(tabAnimation) { store.movePinboard(source, by: to - from) }
                return true
            }
            defer { state.dragging = nil }
            guard let clip = state.dragging else { return false }  // drops from other apps are ignored
            onPin(clip, board)
            return true
        }
        .help(
            i < 9 && shortcuts.pinboardModifier != .disabled
                ? "\(shortcuts.pinboardModifier.symbol)\(i + 1) закрепляет выбранную карточку сюда"
                : ""
        )
        .contextMenu {
            Button("Переименовать") { startRename(board) }
            Button("Сдвинуть влево") {
                withAnimation(tabAnimation) { store.movePinboard(board.id, by: -1) }
            }
            .disabled(i == 0)
            Button("Сдвинуть вправо") {
                withAnimation(tabAnimation) { store.movePinboard(board.id, by: +1) }
            }
            .disabled(i == store.pinboards.count - 1)
            Button("Удалить", role: .destructive) {
                if state.board == board.id { onSwitchBoard(nil) }
                // Animated, so the tabs to the right slide left into the gap instead of jumping.
                withAnimation(tabAnimation) { store.deletePinboard(board) }
            }
            Divider()
            // .palette renders the options as one row of swatches, like Finder tags.
            Picker(
                "Цвет",
                selection: Binding(
                    get: { board.color % Self.boardColors.count },
                    set: { store.setPinboardColor(board.id, to: $0) })
            ) {
                ForEach(Self.paletteOrder, id: \.self) { i in
                    Label {
                        Text(Self.boardColors[i].name)
                    } icon: {
                        Image(
                            nsImage: Self.swatch(
                                Self.boardColors[i].color,
                                selected: i == board.color % Self.boardColors.count))
                    }
                    .tag(i)
                }
            }
            .pickerStyle(.palette)
            .paletteSelectionEffect(.custom)
            .labelsHidden()
        }
    }

    /// Dividers appear only in the scrolling layout, where they mark where the tabs scroll under.
    private func headerRow(scrolling: Bool, @ViewBuilder tabs: () -> some View) -> some View {
        HStack(spacing: 10) {
            magnifierButton
            if scrolling { Divider().frame(height: 20) }
            tabs()
            if scrolling { Divider().frame(height: 20) }
            Button(action: startNewBoard) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(HoverIconStyle())
            .help("Новый пинборд")
            .accessibilityLabel("Новый пинборд")
        }
    }

    private var tabsRow: some View {
        GlassGroup {
            HStack(spacing: 10) {
                tab(nil, title: "Буфер обмена", icon: Image(systemName: "clock.arrow.circlepath"))
                    .id("history")
                ForEach(Array(store.pinboards.enumerated()), id: \.element.id) { i, board in
                    Group {
                        if state.boardEditor == .rename(board.id) {
                            nameField(color: Self.color(of: board))
                        } else {
                            boardTab(board, index: i)
                        }
                    }
                    .id(board.id.uuidString)
                }
                if state.boardEditor == .new {
                    // Same color addPinboard will assign, so the dot doesn't change on Enter.
                    nameField(
                        color: Self.boardColors[store.pinboards.count % Self.boardColors.count]
                            .color
                    )
                    .id("new")
                }
            }
        }
    }

    /// "+" while a name field is open commits that pinboard first, so "+ + +" quickly makes several.
    private func startNewBoard() {
        let wasEditing = state.boardEditor != nil
        if wasEditing { commitBoardName() }
        let open = {
            boardName = "Без названия"  // prefilled and selected: type to replace, or just press Enter
            // Animated like removal in reverse: the field slides in from the right, "+" glides along.
            withAnimation(tabAnimation) { state.boardEditor = .new }
        }
        // Reopen on the next tick so the editor goes nil → .new and the field refocuses with its text selected.
        if wasEditing { DispatchQueue.main.async(execute: open) } else { open() }
    }

    private func startRename(_ board: Pinboard) {
        boardName = board.name
        state.boardEditor = .rename(board.id)
    }

    private func nameField(color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 12, height: 12)
            TextField("Название", text: $boardName)
                .textFieldStyle(.plain)
                .font(Self.tabTitleFont)
                .focused($focus, equals: .boardName)
                .frame(width: 120)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .liquidGlass(in: Capsule())
        .onSubmit(commitBoardName)
    }

    private var tabAnimation: Animation? { reduceMotion ? nil : .smooth(duration: 0.3) }
    private static let tabTitleFont = Font.system(size: 13)
    private static let pinboardDropType = UTType(
        exportedAs: "dev.openpaste.pinboard-order", conformingTo: .data)

    private var searchMode: Bool { state.searchExpanded || !state.query.isEmpty }
    private static let searchFieldWidth: CGFloat = 360

    /// The app has no menu bar icon, so settings and quit live here.
    private var moreMenu: some View {
        Menu {
            Button("Настройки…", action: onSettings).keyboardShortcut(",")
            Divider()
            Button("Завершить OpenPaste") { NSApp.terminate(nil) }.keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(HoverIconStyle())
        .fixedSize()
        .help("Ещё")
        .accessibilityLabel("Ещё")
    }

    private var magnifierButton: some View {
        Button {
            state.searchExpanded = true
            focus = .search
        } label: {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
        }
        .buttonStyle(HoverIconStyle())
        .help("Поиск")
        .accessibilityLabel("Поиск")
    }

    /// Collapsed to an invisible 1 pt sliver outside search mode; it still holds keyboard focus,
    /// so the first typed letter already searches and switches the header into search mode.
    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Поиск", text: $state.query)
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
        }
        .padding(.horizontal, 12)
        .frame(width: searchMode ? Self.searchFieldWidth : 1, height: 32)
        .clipped()
        .background(Capsule().fill(.quaternary))
        .overlay(
            Capsule().strokeBorder(
                Color.accentColor.opacity(focus == .search ? 0.9 : 0), lineWidth: 2)
        )
        .opacity(searchMode ? 1 : 0)
        .allowsHitTesting(searchMode)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: searchMode)
    }

    /// Tabs reduced to their icons while searching: the clock for history, color dots for pinboards.
    private var compactTabs: some View {
        GlassGroup {
            HStack(spacing: 4) {
                tab(
                    nil, title: "Буфер обмена", icon: Image(systemName: "clock.arrow.circlepath"),
                    compact: true)
                ForEach(Array(store.pinboards.enumerated()), id: \.element.id) { i, board in
                    boardTab(board, index: i, compact: true)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func tab(_ id: UUID?, title: String, icon: some View, compact: Bool = false)
        -> some View
    {
        Button {
            onSwitchBoard(id)
        } label: {
            HStack(spacing: 7) {
                icon
                if !compact {
                    Text(title).font(Self.tabTitleFont)
                }
            }
            .padding(.horizontal, compact ? 9 : 14).padding(.vertical, 8)
            .contentShape(Capsule())
            .background(Capsule().fill(.white.opacity(state.board == id ? 0.1 : 0)))
            .animation(nil, value: state.board)
        }
        .buttonStyle(HoverIconStyle(shape: AnyShape(Capsule()), showsHover: state.board != id))
        .accessibilityLabel(title)  // compact tabs show only an icon
    }

    private func commitBoardName() {
        let name = boardName.trimmingCharacters(in: .whitespaces)
        let editor = state.boardEditor
        withAnimation(tabAnimation) {
            state.boardEditor = nil
            guard !name.isEmpty else { return }
            switch editor {
            case .new: onSwitchBoard(store.addPinboard(name: name).id)
            case .rename(let id): store.renamePinboard(id, to: name)
            case nil: break
            }
        }
    }
}

struct CardView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let clip: Clip
    let index: Int
    let selected: Bool
    let now: Date
    let thumbnail: NSImage?
    /// Non-nil while this card's title is being edited inline.
    var titleDraft: Binding<String>? = nil
    var onCommitTitle: () -> Void = {}
    @FocusState private var titleFocused: Bool

    private static let radius: CGFloat = 18
    private static let relative: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        let app = AppStyle.style(for: clip.appBundleID)
        VStack(alignment: .leading, spacing: 0) {
            header(app)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            footerBar
        }
        .frame(width: 232, height: 232)
        .background(clip.kind == .link ? Color(white: 0.13) : Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(
            // Ring sits outside the card, as in Paste: 240 pt outer edge around a 232 pt card.
            RoundedRectangle(cornerRadius: Self.radius + 4, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 4)
                .padding(-4)
                .opacity(selected ? 1 : 0)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: selected)
        )
        .environment(\.colorScheme, .dark)
    }

    /// App-colored strip; the icon is oversized and pushed into the corner so the card's rounding crops it.
    private func header(_ app: (icon: NSImage?, color: Color)) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if let draft = titleDraft {
                TextField("Название", text: draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15, weight: .semibold))
                    .focused($titleFocused)
                    .onSubmit(onCommitTitle)
                    .onAppear { titleFocused = true }
                    .padding(.trailing, 56)  // keep clear of the app icon in the corner
            } else {
                Text(clip.title ?? Self.defaultTitle(clip))
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .padding(.trailing, 56)
            }
            Text(Self.relative.localizedString(for: clip.date, relativeTo: now))
                .font(.system(size: 11.5))
                .opacity(0.85)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 50, maxHeight: 50, alignment: .leading)
        .background(app.color)
        .overlay(alignment: .topTrailing) {
            if let icon = app.icon {
                Image(nsImage: icon).resizable()
                    .frame(width: 60, height: 60)
                    .offset(x: 7, y: -4)
            }
        }
        .clipped()
    }

    @ViewBuilder private var content: some View {
        switch clip.kind {
        case .image:
            if let image = thumbnail {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            }
        case .file:
            if let image = thumbnail {
                Image(nsImage: image).resizable().scaledToFit()
                    .shadow(color: .black.opacity(0.4), radius: 6, y: 2)
                    .padding(.horizontal, 28).padding(.vertical, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .link:
            Image(systemName: "safari").font(.system(size: 34, weight: .light)).foregroundStyle(
                .tertiary
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .text:
            Text(String((clip.text ?? "").prefix(600)))
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(8)
                .padding(.horizontal, 12).padding(.top, 10)
        }
    }

    private var footerBar: some View {
        let centered = ![.link, .file].contains(clip.kind)
        let badge = HStack(spacing: 6) {
            Image(systemName: "text.alignleft").font(.system(size: 10))
            Text("\(index)")
        }
        return HStack(spacing: 6) {
            // Invisible twin of the badge, so centered text is centered on the card, not beside the badge.
            if centered { badge.hidden() }
            Text(footer)
                .lineLimit(clip.kind == .file ? 2 : 1).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: centered ? .center : .leading)
            badge
        }
        .font(.system(size: 12))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12).padding(.bottom, 9)
    }

    static func defaultTitle(_ clip: Clip) -> String {
        switch clip.kind {
        case .text: "Текст"
        case .link: "Ссылка"
        case .image: "Изображение"
        case .file: clip.files.count > 1 ? "Файлы · \(clip.files.count)" : "Файл"
        }
    }

    private var footer: String {
        switch clip.kind {
        case .text: Format.characters(clip.textLength ?? clip.text?.count ?? 0)
        case .link: Format.linkLabel(clip.text ?? "")
        case .image: ""
        case .file: clip.files.first?.path ?? ""
        }
    }
}

/// Header buttons (magnifier, "+", tabs): a soft gray shape appears under them on hover, as in Paste.
private struct HoverIconStyle: ButtonStyle {
    var shape = AnyShape(Circle())
    var showsHover = true

    func makeBody(configuration: Configuration) -> some View {
        HoverBody(configuration: configuration, shape: shape, showsHover: showsHover)
    }

    private struct HoverBody: View {
        let configuration: Configuration
        let shape: AnyShape
        let showsHover: Bool
        @State private var hovering = false
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .background(
                    shape.fill(.quaternary).opacity(hovering && isEnabled && showsHover ? 1 : 0)
                )
                .opacity(configuration.isPressed ? 0.6 : 1)
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }
    }
}
