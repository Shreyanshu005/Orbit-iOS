import SwiftUI
import Combine
import SwiftTerm

struct SwiftTermView: UIViewRepresentable {
    @ObservedObject var wsManager = WebSocketManager.shared
    
    func makeUIView(context: Context) -> SwiftTerm.TerminalView {
        let tv = SwiftTerm.TerminalView()
        tv.terminalDelegate = context.coordinator
        
        // Fix SwiftTerm rendering artifacts by explicitly setting opaque backgrounds
        let bgColor = UIColor(red: 0.05, green: 0.05, blue: 0.07, alpha: 1.0)
        tv.backgroundColor = bgColor
        tv.nativeBackgroundColor = bgColor
        tv.nativeForegroundColor = UIColor.white
        tv.isOpaque = true
        
        
        // Subscribe to PTY data from WebSocket
        context.coordinator.cancellable = wsManager.ptyDataPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak tv] data in
                let array = [UInt8](data)
                // Use the underlying terminal to feed bytes
                tv?.feed(byteArray: array[...])
            }
            
        NotificationCenter.default.addObserver(forName: Notification.Name("HideKeyboard"), object: nil, queue: .main) { [weak tv] _ in
            tv?.resignFirstResponder()
        }
        
        return tv
    }
    
    func updateUIView(_ uiView: SwiftTerm.TerminalView, context: Context) {
        // No dynamic update needed for now
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, TerminalViewDelegate {
        var parent: SwiftTermView
        var cancellable: AnyCancellable?
        
        init(_ parent: SwiftTermView) {
            self.parent = parent
        }
        
        func sizeChanged(source: SwiftTerm.TerminalView, newCols: Int, newRows: Int) { 
            parent.wsManager.sendResize(cols: newCols, rows: newRows)
        }
        
        func setTerminalTitle(source: SwiftTerm.TerminalView, title: String) { }
        func hostCurrentDirectoryUpdate(source: SwiftTerm.TerminalView, directory: String?) { }
        
        func send(source: SwiftTerm.TerminalView, data: ArraySlice<UInt8>) {
            let bytes = Data(data)
            parent.wsManager.sendPtyData(bytes)
        }
        
        func scrolled(source: SwiftTerm.TerminalView, position: Double) { }
        
        // Additional methods required by newer SwiftTerm versions
        func requestOpenLink(source: SwiftTerm.TerminalView, link: String, params: [String : String]) { }
        func clipboardCopy(source: SwiftTerm.TerminalView, content: Data) { }
        func rangeChanged(source: SwiftTerm.TerminalView, startY: Int, endY: Int) { }
    }
}
