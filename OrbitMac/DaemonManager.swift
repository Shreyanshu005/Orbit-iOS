import Foundation
import Combine

class DaemonManager: ObservableObject {
    static let shared = DaemonManager()
    
    @Published var isRunning: Bool = false
    @Published var pairingCode: String = "------"
    @Published var logs: [String] = []
    
    private var process: Process?
    private var outputPipe: Pipe?
    
    private init() {}
    
    func startDaemon() {
        guard !isRunning else { return }
        
        // Find the daemon binary. We assume it's next to the .app or in a known location.
        // For development, we'll hardcode the path or use the user's term/orbitd path.
        let daemonPath = "/Users/shreyanshu/Desktop/term/orbitd/orbitd-bin"
        
        guard FileManager.default.fileExists(atPath: daemonPath) else {
            DispatchQueue.main.async {
                self.logs.append("Error: Cannot find orbitd-bin at \(daemonPath)")
            }
            return
        }
        
        // Ensure no zombie processes are left running
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killTask.arguments = ["-9", "orbitd-bin"]
        try? killTask.run()
        killTask.waitUntilExit()
        
        process = Process()
        process?.executableURL = URL(fileURLWithPath: daemonPath)
        process?.currentDirectoryURL = URL(fileURLWithPath: "/Users/shreyanshu/Desktop/term/orbitd")
        
        // Set environment variable to tell the daemon to use macOS GUI prompts
        var env = ProcessInfo.processInfo.environment
        env["ORBIT_GUI_MODE"] = "1"
        
        // Securely load the API key from the .env file instead of hardcoding
        let envFilePath = "/Users/shreyanshu/Desktop/term/orbitd/.env"
        if let envString = try? String(contentsOfFile: envFilePath, encoding: .utf8) {
            let lines = envString.components(separatedBy: .newlines)
            for line in lines {
                let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
                if parts.count == 2 {
                    env[parts[0].trimmingCharacters(in: .whitespaces)] = parts[1].trimmingCharacters(in: .whitespaces)
                }
            }
        }
        
        process?.environment = env
        
        outputPipe = Pipe()
        process?.standardOutput = outputPipe
        process?.standardError = outputPipe
        
        outputPipe?.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty { return }
            
            if let str = String(data: data, encoding: .utf8) {
                let lines = str.components(separatedBy: .newlines)
                for line in lines where !line.isEmpty {
                    DispatchQueue.main.async {
                        self?.logs.append(line)
                        if self?.logs.count ?? 0 > 50 {
                            self?.logs.removeFirst()
                        }
                        self?.parseLine(line)
                    }
                }
            }
        }
        
        do {
            try process?.run()
            DispatchQueue.main.async {
                self.isRunning = true
            }
            
            process?.terminationHandler = { [weak self] _ in
                DispatchQueue.main.async {
                    self?.isRunning = false
                    self?.pairingCode = "------"
                }
            }
        } catch {
            DispatchQueue.main.async {
                self.logs.append("Failed to start daemon: \(error.localizedDescription)")
            }
        }
    }
    
    func stopDaemon() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminate()
        
        // Ensure process is forcefully killed if it doesn't terminate cleanly
        let killTask = Process()
        killTask.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        killTask.arguments = ["-9", "orbitd-bin"]
        try? killTask.run()
        killTask.waitUntilExit()
        
        process = nil
        outputPipe = nil
        isRunning = false
        pairingCode = "------"
    }
    
    private func parseLine(_ line: String) {
        // Look for the pairing code pattern: "🔑 PAIRING CODE: 123456"
        if line.contains("PAIRING CODE:") {
            if let code = line.components(separatedBy: "PAIRING CODE: ").last?.trimmingCharacters(in: .whitespacesAndNewlines) {
                self.pairingCode = code
            }
        }
    }
}
