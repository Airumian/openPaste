import AppKit
import SwiftUI

struct PanelView: View {
    let store: ClipStore
    @Bindable var state: PanelState
    let onPaste: (Clip) -> Void
    let onDelete: (Clip) -> Void
    let onSwitchBoard: (UUID?) -> Void
    let onPin: (Clip, Pinboard) -> Void
    @FocusState private var focus: Field?
    @State private var boardName = ""
    @State private var dropTarget: UUID?
    @State private var clipTitleDraft = ""
    @Namespace private var glass
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
    private static func swatch(_ color: Color) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            NSColor(color).setFill()
            NSBezierPath(ovalIn: rect).fill()
            return true
        }
        image.isTemplate = false
        return image
    }

    /// A hidden panel renders nothing, so copies made while it's closed don't rebuild the card list.
    /// Transparent margin around the glass inside the panel window: keeps the 8 pt gap to the screen edges
    /// and leaves room for the glass shadow, which would otherwise be clipped into gray corner wedges.
    static let shadowRoom = EdgeInsets(top: 24, leading: 8, bottom: 8, trailing: 8)

    var body: some View {
        ZStack {  // stable container, so inserting the content runs its transition
            if state.isVisible {
                panelContent
                    .padding(Self.shadowRoom)
                    .transition(
                        reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity)
                    )
                    .onAppear { DispatchQueue.main.async { focus = .search } }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var panelContent: some View {
        let clips = state.visibleClips(store)
        return VStack(spacing: 14) {
            GlassGroup {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                        TextField("Поиск", text: $state.query)
                            .textFieldStyle(.plain)
                            .focused($focus, equals: .search)
                            .frame(width: 200)
                    }
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .liquidGlass(in: Capsule())

                    tab(
                        nil, title: "Буфер обмена",
                        icon: Image(systemName: "clock.arrow.circlepath"), tint: nil)
                    ForEach(Array(store.pinboards.enumerated()), id: \.element.id) { i, board in
                        if state.boardEditor == .rename(board.id) {
                            nameField
                        } else {
                            boardTab(board, index: i)
                        }
                    }
                    if state.boardEditor == .new {
                        nameField
                    } else {
                        Button {
                            boardName = ""
                            state.boardEditor = .new
                        } label: {
                            Image(systemName: "plus").frame(width: 30, height: 30)
                                .liquidGlass(in: Circle(), interactive: true)
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .help("Новый пинборд")
                    }
                }
            }

            if clips.isEmpty {
                Text(
                    !state.query.isEmpty
                        ? "Ничего не найдено"
                        : state.board == nil
                            ? "История пуста — скопируйте что-нибудь"
                            : "Пинборд пуст — перетащите сюда карточку, нажмите ⌘1…9 или правый клик → «Закрепить в»"
                )
                .foregroundStyle(.secondary)
                .frame(maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 16) {
                            ForEach(Array(clips.enumerated()), id: \.element.id) { i, clip in
                                card(clip, index: i)
                            }
                        }
                        .padding(.horizontal, 20)
                    }
                    .onChange(of: state.selection) { _, i in
                        guard clips.indices.contains(i) else { return }
                        withAnimation(.easeOut(duration: 0.15)) {
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
                            if n < 9 {
                                Button(board.name) { onPin(clip, board) }
                                    .keyboardShortcut(
                                        KeyEquivalent(Character("\(n + 1)")), modifiers: .command)
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

    private func boardTab(_ board: Pinboard, index i: Int) -> some View {
        let targeted = Binding(
            get: { dropTarget == board.id },
            set: { on in
                if on { dropTarget = board.id } else if dropTarget == board.id { dropTarget = nil }
            })
        return tab(
            board.id, title: board.name,
            icon: Image(systemName: "circle.fill").foregroundStyle(Self.color(of: board)),
            tint: Self.color(of: board)
        )
        .simultaneousGesture(TapGesture(count: 2).onEnded { startRename(board) })
        .overlay(
            Capsule().strokeBorder(Color.accentColor, lineWidth: 2).opacity(
                dropTarget == board.id ? 1 : 0)
        )
        .onDrop(of: [.item], isTargeted: targeted) { _ in
            defer { state.dragging = nil }
            guard let clip = state.dragging else { return false }  // drops from other apps are ignored
            onPin(clip, board)
            return true
        }
        .help(i < 9 ? "⌘\(i + 1) закрепляет выбранную карточку сюда" : "")
        .contextMenu {
            Button("Переименовать") { startRename(board) }
            Button("Сдвинуть влево") { store.movePinboard(board.id, by: -1) }
                .disabled(i == 0)
            Button("Сдвинуть вправо") { store.movePinboard(board.id, by: +1) }
                .disabled(i == store.pinboards.count - 1)
            Button("Удалить", role: .destructive) {
                if state.board == board.id { onSwitchBoard(nil) }
                store.deletePinboard(board)
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
                        Image(nsImage: Self.swatch(Self.boardColors[i].color))
                    }
                    .tag(i)
                }
            }
            .pickerStyle(.palette)
            .labelsHidden()
        }
    }

    private func startRename(_ board: Pinboard) {
        boardName = board.name
        state.boardEditor = .rename(board.id)
    }

    private var nameField: some View {
        TextField("Название", text: $boardName)
            .textFieldStyle(.plain)
            .focused($focus, equals: .boardName)
            .frame(width: 140)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .liquidGlass(in: Capsule())
            .onSubmit(commitBoardName)
    }

    /// The selected tab sits in a glass capsule that morphs between tabs on switch.
    private func tab(_ id: UUID?, title: String, icon: some View, tint: Color?) -> some View {
        Button {
            onSwitchBoard(id)
        } label: {
            let label = HStack(spacing: 6) {
                icon
                Text(title)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .contentShape(Capsule())

            if state.board == id {
                label
                    .liquidGlass(in: Capsule(), tint: tint?.opacity(0.35), interactive: true)
                    .liquidGlassID("selected-tab", in: glass)
            } else {
                label
            }
        }
        .buttonStyle(.plain)
    }

    private func commitBoardName() {
        let name = boardName.trimmingCharacters(in: .whitespaces)
        let editor = state.boardEditor
        state.boardEditor = nil
        guard !name.isEmpty else { return }
        switch editor {
        case .new: onSwitchBoard(store.addPinboard(name: name).id)
        case .rename(let id): store.renamePinboard(id, to: name)
        case nil: break
        }
    }
}

struct CardView: View {
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
        .frame(width: 230, height: 230)
        .background(clip.kind == .link ? Color(white: 0.13) : Color(white: 0.08))
        .clipShape(RoundedRectangle(cornerRadius: Self.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(selected ? Color.accentColor : .clear, lineWidth: 4)
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
        HStack(spacing: 6) {
            Text(footer)
                .lineLimit(clip.kind == .file ? 2 : 1).truncationMode(.middle)
                .frame(
                    maxWidth: .infinity,
                    alignment: [.link, .file].contains(clip.kind) ? .leading : .center)
            Image(systemName: "text.alignleft").font(.system(size: 10))
            Text("\(index)")
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
