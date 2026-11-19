import SwiftUI

struct SettingsView: View {
    let store: ClipStore
    @AppStorage(ClipStore.retentionKey) private var retention = ClipStore.defaultRetention
    @State private var confirmClear = false

    private let options = ClipStore.retentionOptions

    var body: some View {
        Form {
            Section("Сохранять историю") {
                VStack(spacing: 8) {
                    // No `step:` on purpose: stepped sliders lose the accent fill and round knob; rounding snaps instead.
                    Slider(
                        value: Binding(get: { Double(retention) }, set: { retention = Int($0.rounded()) }),
                        in: 0...Double(options.count - 1)
                    )
                    .labelsHidden()
                    HStack(spacing: 0) {
                        ForEach(options.indices, id: \.self) { i in
                            if i > 0 { Spacer(minLength: 0) }
                            Circle().fill(.tertiary).frame(width: 3, height: 3)
                        }
                    }
                    .padding(.horizontal, 9)  // align dots with the knob centre at both ends
                    HStack(spacing: 0) {
                        ForEach(options.indices, id: \.self) { i in
                            if i > 0 { Spacer(minLength: 4) }
                            Text(options[i].title)
                        }
                    }
                    .font(.callout)
                }
                .padding(.vertical, 4)

                HStack {
                    Spacer()
                    Button("Стереть историю…") { confirmClear = true }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: retention) { store.pruneExpired() }
        .confirmationDialog("Стереть всю историю?", isPresented: $confirmClear) {
            Button("Стереть", role: .destructive) { store.clear() }
        } message: {
            Text("Закреплённые в пинбордах карточки останутся. Это действие нельзя отменить.")
        }
    }
}
