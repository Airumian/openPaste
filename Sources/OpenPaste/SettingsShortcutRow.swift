import SwiftUI

struct SettingsShortcutRow: View {
    let action: ShortcutAction
    let shortcuts: ShortcutStore
    let recorder: ShortcutRecorder
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(action.title)
                if let detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ZStack(alignment: .trailing) {
                Button {
                    recorder.start(action)
                } label: {
                    Text(recorder.action == action ? "Запись" : shortcuts[action]?.display ?? "Записать")
                        .font(.system(size: 13))
                        .foregroundStyle(shortcuts[action] == nil || recorder.action == action ? .secondary : .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 22)  // reserve equal space on both sides of the clear button
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Изменить сочетание: \(action.title)")
                .accessibilityValue(recorder.action == action ? "Запись" : shortcuts[action]?.display ?? "Не назначено")
                .help("Нажмите, затем введите сочетание. Esc — отмена.")

                if shortcuts[action] != nil {
                    Button {
                        recorder.stop()
                        shortcuts.set(nil, for: action)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 24)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Удалить сочетание: \(action.title)")
                    .help("Удалить сочетание")
                }
            }
                .frame(width: 120, height: 24)
                .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(recorder.action == action ? Color.blue : Color(nsColor: .separatorColor), lineWidth: 1)
                }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .contain)
    }
}
