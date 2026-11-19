enum SettingsSection: String, CaseIterable, Identifiable {
    case general = "Основные"
    case shortcuts = "Сочетания клавиш"

    var id: Self { self }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "keyboard"
        }
    }
}
