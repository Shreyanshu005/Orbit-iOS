import SwiftUI

struct TerminalView: View {
    @State private var pairingCode: String = ""
    @State private var aiTaskInput: String = ""
    @State private var keyboardHeight: CGFloat = 0
    @ObservedObject var wsManager = WebSocketManager.shared
    
    var body: some View {
        ZStack {
            // Sleek dark background, explicitly avoiding the keyboard region
            Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea(.container, edges: .all)
            
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Circle()
                        .fill(wsManager.isConnected ? Color.green : Color.red)
                        .frame(width: 8, height: 8)
                        .shadow(color: wsManager.isConnected ? .green : .red, radius: 3)
                    
                    if !wsManager.isConnected {
                        TextField("6-Digit Code", text: $pairingCode)
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(6)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(6)
                            .frame(width: 120)
                            .keyboardType(.numberPad)
                    } else {
                        Text("Connected")
                            .font(.system(size: 14, weight: .semibold, design: .monospaced))
                            .foregroundColor(.green.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                        NotificationCenter.default.post(name: Notification.Name("HideKeyboard"), object: nil)
                    }) {
                        Image(systemName: "keyboard.chevron.compact.down")
                            .foregroundColor(.gray)
                            .padding(.trailing, 8)
                    }
                    
                    Button(action: {
                        wsManager.isConnected ? wsManager.disconnect() : wsManager.connect(pairingCode: pairingCode)
                    }) {
                        Image(systemName: wsManager.isConnected ? "network.badge.shield.half.filled" : "network")
                            .foregroundColor(wsManager.isConnected ? .green : .blue)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.4))
                
                // Real Terminal View
                SwiftTermView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                // AI Task Input
                if wsManager.isConnected && wsManager.isAuthenticated {
                    HStack {
                        TextField("Ask Orbit AI...", text: $aiTaskInput)
                            .font(.system(size: 14))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(8)
                        
                        Button(action: {
                            if !aiTaskInput.isEmpty {
                                wsManager.sendTask(aiTaskInput)
                                aiTaskInput = ""
                            }
                        }) {
                            Image(systemName: "paperplane.fill")
                                .foregroundColor(aiTaskInput.isEmpty ? .gray : .blue)
                                .padding(10)
                        }
                        .disabled(aiTaskInput.isEmpty)
                    }
                    .padding()
                    .background(Color.black.opacity(0.6))
                }
            }
            
            // AI Approval Card Overlay
            if let req = wsManager.pendingApprovals.first {
                Color.black.opacity(0.7).ignoresSafeArea()
                
                VStack(spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Orbit AI Proposed Task")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text(req.aiReasoning)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Text(req.proposedCommand)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(.green)
                            .padding(10)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(6)
                    }
                    .padding()
                    
                    HStack(spacing: 20) {
                        Button("Deny") {
                            wsManager.sendApprovalResponse(requestId: req.id, isApproved: false)
                        }
                        .foregroundColor(.red)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(Color.red.opacity(0.2))
                        .cornerRadius(8)
                        
                        Button("Approve") {
                            wsManager.sendApprovalResponse(requestId: req.id, isApproved: true)
                        }
                        .foregroundColor(.green)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 20)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(8)
                    }
                    .padding(.bottom)
                }
                .frame(width: 300)
                .background(Color(red: 0.1, green: 0.1, blue: 0.15))
                .cornerRadius(12)
                .shadow(radius: 20)
            }
        }
        .padding(.bottom, keyboardHeight)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .navigationBarHidden(true)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notification in
            if let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect {
                // If it's an external keyboard, the height might be small, so we use max(0, ...)
                // We also subtract safe area bottom insets so it doesn't double-pad on notch iPhones
                let window = UIApplication.shared.windows.first
                let bottomPadding = window?.safeAreaInsets.bottom ?? 0
                withAnimation(.easeOut(duration: 0.25)) {
                    self.keyboardHeight = max(0, keyboardFrame.height - bottomPadding)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            withAnimation(.easeOut(duration: 0.25)) {
                self.keyboardHeight = 0
            }
        }
    }
}

#Preview {
    TerminalView()
}
