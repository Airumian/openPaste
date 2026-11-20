import SwiftUI

struct HistorySettingsView: View {
    let store: ClipStore
    @AppStorage(ClipStore.retentionKey) private var retention = ClipStore.defaultRetention
    @State private var confirmClear = false

    private let options = ClipStore.retentionOptions

    private var retentionSelection: Binding<Double> {
        Binding(get: { Double(retention) }, set: { retention = Int($0.rounded()) })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Сохранять историю")
                .font(.system(size: 13, weight: .semibold))
                .padding(.horizontal, SettingsLayout.cardInset)
                .accessibilityAddTraits(.isHeader)

            SettingsCard {
                VStack(spacing: 4) {
                    // Keep the continuous slider's accent fill and round knob; round the stored value instead.
                    Slider(value: retentionSelection, in: 0...Double(options.count - 1)) {
                        Text("Сохранять историю")
                    }
                    .labelsHidden()
                    .accessibilityValue(options[min(max(retention, 0), options.count - 1)].title)

                    HStack(spacing: 0) {
                        ForEach(options.indices, id: \.self) { i in
                            if i > 0 { Spacer(minLength: 0) }
                            Circle().fill(.tertiary).frame(width: 3, height: 3)
                        }
                    }
                    .padding(.horizontal, 9)
                    .accessibilityHidden(true)

                    HStack(spacing: 0) {
                        ForEach(options.indices, id: \.self) { i in
                            if i > 0 { Spacer(minLength: 4) }
                            Text(options[i].title)
                        }
                    }
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                }
                .padding(.vertical, 10)

                Divider()

                HStack(spacing: 12) {
                    Text("В истории: \(store.clips.filter { $0.pinboardID == nil }.count)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button {
                        confirmClear = true
                    } label: {
                        Text("Стереть историю…")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 4)
                            .background(
                                Color(nsColor: .quaternaryLabelColor),
                                in: .rect(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .confirmationDialog("Стереть всю историю?", isPresented: $confirmClear) {
                        Button("Стереть", role: .destructive, action: store.clear)
                        Button("Отмена", role: .cancel) {}
                    } message: {
                        Text(
                            "Закреплённые в пинбордах карточки останутся. Это действие нельзя отменить."
                        )
                    }
                }
                .padding(.vertical, 10)
            }
        }
        .onChange(of: retention) { store.pruneExpired() }
    }
}
