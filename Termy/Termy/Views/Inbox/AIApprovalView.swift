import SwiftUI

struct AIApprovalView: View {
    @ObservedObject var wsManager = WebSocketManager.shared
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.08, green: 0.08, blue: 0.1).ignoresSafeArea()
                
                if wsManager.pendingApprovals.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.shield")
                            .font(.system(size: 60))
                            .foregroundColor(.green.opacity(0.8))
                        Text("No pending approvals")
                            .font(.headline)
                            .foregroundColor(.white.opacity(0.8))
                        Text("Your AI agent is quiet right now.")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(wsManager.pendingApprovals) { request in
                                ApprovalCard(request: request)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("AI Inbox")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.08, green: 0.08, blue: 0.1), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

struct ApprovalCard: View {
    let request: AIApprovalRequest
    @ObservedObject var wsManager = WebSocketManager.shared
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Action Required")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                Spacer()
                Text("Just now")
                    .font(.caption)
                    .foregroundColor(.gray)
            }
            
            Divider().background(Color.gray.opacity(0.3))
            
            // Context
            VStack(alignment: .leading, spacing: 6) {
                Text("Reasoning")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
                Text(request.aiReasoning)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            // Proposed Command
            VStack(alignment: .leading, spacing: 6) {
                Text("Proposed Command")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.gray)
                
                Text(request.proposedCommand)
                    .font(.system(size: 13, design: .monospaced))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(6)
                    .foregroundColor(.red)
            }
            
            // CWD
            HStack {
                Image(systemName: "folder")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(request.cwd)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
            .padding(.top, 4)
            
            // Action Buttons
            HStack(spacing: 12) {
                Button(action: {
                    withAnimation { wsManager.sendApprovalResponse(requestId: request.id, isApproved: false) }
                }) {
                    Text("Deny")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.1))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
                
                Button(action: {
                    withAnimation { wsManager.sendApprovalResponse(requestId: request.id, isApproved: true) }
                }) {
                    Text("Approve")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(8)
                }
            }
            .padding(.top, 8)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(red: 0.12, green: 0.12, blue: 0.15))
                .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 5)
        )
        // Sleek border
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

#Preview {
    AIApprovalView()
}
