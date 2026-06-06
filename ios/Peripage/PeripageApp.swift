import SwiftUI

@main
struct PeripageApp: App {
    @State private var printer = PrinterClient()
    @State private var queue: PrintQueue

    init() {
        let p = PrinterClient()
        _printer = State(initialValue: p)
        _queue = State(initialValue: PrintQueue(printer: p))
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                rootView
            }
            .environment(printer)
            .environment(queue)
        }
        #if os(macOS)
        .defaultSize(width: 540, height: 640)
        .windowResizability(.contentMinSize)
        #endif
    }

    @ViewBuilder
    private var rootView: some View {
        if case .error(let e) = printer.state, isBluetoothFatal(e) {
            BluetoothGateView(error: e)
        } else {
            HomeView()
        }
    }

    private func isBluetoothFatal(_ e: BLEError) -> Bool {
        switch e {
        case .bluetoothPoweredOff, .bluetoothUnauthorized, .bluetoothUnavailable: return true
        default: return false
        }
    }
}
