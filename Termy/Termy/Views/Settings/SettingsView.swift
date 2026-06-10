import SwiftUI

struct SettingsView: View {
    @ObservedObject var wsManager = WebSocketManager.shared
    
    var body: some View {
        NavigationView {
            ZStack {
                Color(red: 0.05, green: 0.05, blue: 0.07).ignoresSafeArea()
                
                Form {

                    Section(header: Text("Connection Status").foregroundColor(.gray)) {
                        HStack {
                            Text("Status")
                                .foregroundColor(.white)
                            Spacer()
                            Text(wsManager.isConnected ? "Connected" : "Disconnected")
                                .foregroundColor(wsManager.isConnected ? .green : .red)
                                .fontWeight(.bold)
                        }
                        
                        Button(action: {
                            if wsManager.isConnected {
                                wsManager.disconnect()
                            } else {
                                wsManager.connect()
                            }
                        }) {
                            Text(wsManager.isConnected ? "Disconnect" : "Connect")
                                .frame(maxWidth: .infinity, alignment: .center)
                                .foregroundColor(wsManager.isConnected ? .red : .blue)
                        }
                    }
                    .listRowBackground(Color(red: 0.12, green: 0.12, blue: 0.15))
                    
                    Section(header: Text("About").foregroundColor(.gray)) {
                        HStack {
                            Text("Version")
                                .foregroundColor(.white)
                            Spacer()
                            Text("1.0.0-alpha")
                                .foregroundColor(.gray)
                        }
                    }
                    .listRowBackground(Color(red: 0.12, green: 0.12, blue: 0.15))
                }
                .scrollContentBackground(.hidden) // Hides default iOS form background
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(Color(red: 0.05, green: 0.05, blue: 0.07), for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }
}

#Preview {
    SettingsView()
}
