enum ShortcutAction: String, CaseIterable, Identifiable {
    case togglePanel, nextBoard, previousBoard, previousClip, nextClip, paste, close
    case delete, deleteWithoutSearch, undoDelete, search
    case extendPrevious, extendNext, selectAll, tabToCards

    var id: Self { self }

    var title: String {
        switch self {
        case .togglePanel: "Открыть / закрыть OpenPaste"
        case .nextBoard: "Следующий пинборд"
        case .previousBoard: "Предыдущий пинборд"
        case .previousClip: "Предыдущая карточка"
        case .nextClip: "Следующая карточка"
        case .paste: "Вставить выбранную карточку"
        case .close: "Закрыть панель"
        case .delete: "Удалить карточку"
        case .deleteWithoutSearch: "Удалить карточку без поиска"
        case .undoDelete: "Вернуть удалённую карточку"
        case .search: "Поиск"
        case .extendPrevious: "Добавить предыдущую карточку"
        case .extendNext: "Добавить следующую карточку"
        case .selectAll: "Выделить все карточки"
        case .tabToCards: "Из поиска к карточкам"
        }
    }

    var defaultShortcut: AppShortcut {
        switch self {
        case .togglePanel: AppShortcut(keyCode: 9, flags: [.command, .shift], keyLabel: "V")
        case .nextBoard: AppShortcut(keyCode: 124, flags: .command, keyLabel: "→")
        case .previousBoard: AppShortcut(keyCode: 123, flags: .command, keyLabel: "←")
        case .previousClip: AppShortcut(keyCode: 123, keyLabel: "←")
        case .nextClip: AppShortcut(keyCode: 124, keyLabel: "→")
        case .paste: AppShortcut(keyCode: 36, keyLabel: "↩")
        case .close: AppShortcut(keyCode: 53, keyLabel: "Esc")
        case .delete: AppShortcut(keyCode: 51, flags: .command, keyLabel: "⌫")
        case .deleteWithoutSearch: AppShortcut(keyCode: 51, keyLabel: "⌫")
        case .undoDelete: AppShortcut(keyCode: 6, flags: .command, keyLabel: "Z")
        case .search: AppShortcut(keyCode: 3, flags: .command, keyLabel: "F")
        case .extendPrevious: AppShortcut(keyCode: 123, flags: .shift, keyLabel: "←")
        case .extendNext: AppShortcut(keyCode: 124, flags: .shift, keyLabel: "→")
        case .selectAll: AppShortcut(keyCode: 0, flags: .command, keyLabel: "A")
        case .tabToCards: AppShortcut(keyCode: 48, keyLabel: "⇥")
        }
    }
}
