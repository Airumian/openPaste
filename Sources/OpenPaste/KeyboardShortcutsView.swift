import SwiftUI

struct KeyboardShortcutsView: View {
    let shortcuts: ShortcutStore
    @State private var recorder: ShortcutRecorder
    @State private var confirmReset = false

    init(shortcuts: ShortcutStore) {
        self.shortcuts = shortcuts
        _recorder = State(initialValue: ShortcutRecorder(shortcuts: shortcuts))
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { shortcuts.errorMessage != nil }, set: { if !$0 { shortcuts.errorMessage = nil } }
        )
    }

    private var modifierSelection: Binding<PinboardModifier> {
        Binding(get: { shortcuts.pinboardModifier }, set: { shortcuts.setPinboardModifier($0) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ShortcutGroupView(actions: [.togglePanel], shortcuts: shortcuts, recorder: recorder)
            ShortcutGroupView(
                actions: [.nextBoard, .previousBoard], shortcuts: shortcuts, recorder: recorder)

            SettingsCard {
                HStack(spacing: 8) {
                    Text("Закрепить в пинборде")
                    Spacer(minLength: 0)
                    Picker("Модификатор для закрепления", selection: modifierSelection) {
                        ForEach(PinboardModifier.allCases) { modifier in
                            Text(modifier.title).tag(modifier)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                    if shortcuts.pinboardModifier != .disabled { Text("+ 1…9") }
                }
                .frame(height: 36)
            }

            ShortcutGroupView(
                actions: [
                    .previousClip, .nextClip, .extendPrevious, .extendNext, .selectAll, .paste,
                    .edit, .search, .tabToCards, .close,
                ], shortcuts: shortcuts,
                recorder: recorder)
            ShortcutGroupView(
                actions: [.delete, .deleteWithoutSearch, .undoDelete], shortcuts: shortcuts,
                recorder: recorder)

            HStack {
                Spacer(minLength: 0)
                Button {
                    confirmReset = true
                } label: {
                    Text("Сбросить сочетания по умолчанию…")
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(
                            Color(nsColor: .quaternaryLabelColor), in: .rect(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .confirmationDialog("Сбросить сочетания клавиш?", isPresented: $confirmReset) {
                    Button("Сбросить") {
                        recorder.stop()
                        shortcuts.reset()
                    }
                    Button("Отмена", role: .cancel) {}
                } message: {
                    Text("Все сочетания вернутся к стандартным значениям.")
                }
            }

            Text(
                recorder.action == nil
                    ? "Нажмите на сочетание, чтобы изменить его. Команды карточек работают при открытой панели."
                    : "Запись. Esc — отмена."
            )
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, SettingsLayout.cardInset)
        }
        .onDisappear { recorder.stop() }
        .alert("Сочетание недоступно", isPresented: errorPresented) {
            Button("OK", role: .cancel) { shortcuts.errorMessage = nil }
        } message: {
            Text(shortcuts.errorMessage ?? "")
        }
    }
}
