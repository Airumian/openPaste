import SwiftUI

struct SettingsView: View {
    let store: ClipStore
    let shortcuts: ShortcutStore
    @State private var selection = SettingsSection.general

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ForEach(SettingsSection.allCases) { section in
                    Button {
                        selection = section
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: section.symbol)
                                .font(.system(size: 20))
                                .frame(width: 20)
                                .foregroundStyle(selection == section ? Color.white : Color.blue)
                            Text(section.rawValue)
                                .font(.system(size: 13))
                                .fontWeight(selection == section ? .semibold : .regular)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .frame(height: 32)
                        .foregroundStyle(selection == section ? Color.white : Color.primary)
                        .background(selection == section ? Color.blue : .clear,
                                    in: .rect(cornerRadius: 8))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == section ? .isSelected : [])
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, SettingsLayout.headerHeight)
            .frame(width: SettingsLayout.sidebarWidth - 1)  // include the divider in the sidebar width
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)

            Divider()

            VStack(alignment: .leading, spacing: 0) {
                Text(selection.rawValue)
                    .font(.system(size: 15, weight: .semibold))
                    .padding(.horizontal, 30)
                    .frame(height: SettingsLayout.headerHeight, alignment: .leading)
                    .accessibilityAddTraits(.isHeader)

                ScrollView {
                    Group {
                        switch selection {
                        case .general:
                            HistorySettingsView(store: store)
                        case .shortcuts:
                            KeyboardShortcutsView(shortcuts: shortcuts)
                        }
                    }
                    .padding(.horizontal, SettingsLayout.contentInset)
                    .padding(.bottom, SettingsLayout.contentInset)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .scrollBounceBehavior(.basedOnSize)
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .font(.system(size: 13))
        .tint(.blue)
        .frame(width: SettingsLayout.windowSize.width)
        .ignoresSafeArea()
    }
}
