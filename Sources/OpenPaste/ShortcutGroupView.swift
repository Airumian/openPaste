import SwiftUI

struct ShortcutGroupView: View {
    let actions: [ShortcutAction]
    let shortcuts: ShortcutStore
    let recorder: ShortcutRecorder

    var body: some View {
        SettingsCard {
            ForEach(actions) { action in
                if action != actions.first { Divider() }
                SettingsShortcutRow(
                    action: action, shortcuts: shortcuts, recorder: recorder,
                    detail: action == .deleteWithoutSearch ? "Когда поиск закрыт" : nil)
            }
        }
    }
}
