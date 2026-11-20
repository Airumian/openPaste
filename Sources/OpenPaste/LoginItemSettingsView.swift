import ServiceManagement
import SwiftUI

struct LoginItemSettingsView: View {
    @State private var status = SMAppService.mainApp.status
    @State private var errorMessage: String?

    var body: some View {
        SettingsCard {
            VStack(alignment: .leading, spacing: 6) {
                Toggle(
                    isOn: Binding(
                        get: { status == .enabled || status == .requiresApproval },
                        set: setLaunchAtLogin
                    )
                ) {
                    Text("Открывать при входе в систему")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                if status == .requiresApproval {
                    Text("Разрешите автозапуск OpenPaste в системных настройках.")
                        .foregroundStyle(.secondary)
                    Button("Открыть объекты входа") {
                        SMAppService.openSystemSettingsLoginItems()
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .padding(.vertical, 10)
        }
        .onAppear { status = SMAppService.mainApp.status }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
            _ in
            status = SMAppService.mainApp.status
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        errorMessage = nil
        defer { status = service.status }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            errorMessage = "Не удалось изменить автозапуск. \(error.localizedDescription)"
        }
    }
}
