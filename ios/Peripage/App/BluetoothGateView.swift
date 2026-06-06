import SwiftUI

struct BluetoothGateView: View {
    let error: BLEError

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                .font(.largeTitle).foregroundStyle(.tint)
            Text(title).font(.title2.bold())
            Text(message).multilineTextAlignment(.center).foregroundStyle(.secondary)
            Button("Open Settings") { openSettings() }
                .buttonStyle(.borderedProminent)
        }
        .padding(32)
    }

    private var title: String {
        switch error {
        case .bluetoothPoweredOff: return "Bluetooth is off"
        case .bluetoothUnauthorized: return "Bluetooth permission needed"
        case .bluetoothUnavailable: return "Bluetooth unavailable"
        default: return "Bluetooth error"
        }
    }
    private var message: String {
        switch error {
        case .bluetoothPoweredOff:
            return "Turn Bluetooth on in Settings, then come back to Peripage."
        case .bluetoothUnauthorized:
            return "Peripage needs Bluetooth access to talk to your printer."
        case .bluetoothUnavailable:
            return "Your device doesn't support Bluetooth Low Energy."
        default:
            return ""
        }
    }

    private func openSettings() {
        #if canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #elseif canImport(AppKit)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth") {
            NSWorkspace.shared.open(url)
        }
        #endif
    }
}
