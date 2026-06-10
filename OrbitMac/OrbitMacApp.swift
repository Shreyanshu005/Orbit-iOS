import SwiftUI
import AppKit

@main
struct OrbitMacApp: App {
    @StateObject private var daemonManager = DaemonManager.shared
    
    var body: some Scene {
        MenuBarExtra("Orbit", systemImage: daemonManager.isRunning ? "network.badge.shield.half.filled" : "network") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Circle()
                        .fill(daemonManager.isRunning ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                        .shadow(color: daemonManager.isRunning ? .green : .red, radius: 2)
                    
                    Text(daemonManager.isRunning ? "Orbit is Active" : "Orbit is Stopped")
                        .font(.headline)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.top, 10)
                
                Divider()
                
                if daemonManager.isRunning {
                    HStack {
                        Text("Pairing Code:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(daemonManager.pairingCode)
                            .font(.system(.title3, design: .monospaced))
                            .bold()
                    }
                    .padding(.horizontal)
                    
                    Divider()
                }
                
                if let lastLog = daemonManager.logs.last {
                    Text(lastLog)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.gray)
                        .padding(.horizontal)
                        .lineLimit(2)
                    
                    Divider()
                }
                
                Button(action: {
                    if daemonManager.isRunning {
                        daemonManager.stopDaemon()
                    } else {
                        daemonManager.startDaemon()
                    }
                }) {
                    Text(daemonManager.isRunning ? "Stop Orbit" : "Start Orbit")
                        .frame(maxWidth: .infinity)
                }
                .keyboardShortcut("s", modifiers: .command)
                .padding(.horizontal)
                
                Divider()
                
                Button("Quit Orbit") {
                    daemonManager.stopDaemon()
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            .frame(width: 250)
        }
        .menuBarExtraStyle(.window) // Uses a SwiftUI View popover instead of a native menu
    }
}
