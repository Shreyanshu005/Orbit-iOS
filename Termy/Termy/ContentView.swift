//
//  ContentView.swift
//  Termy
//
//  Created by Shreyanshu on 09/06/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var wsManager = WebSocketManager.shared
    
    // Customize TabBar appearance for dark mode sleekness
    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.08, green: 0.08, blue: 0.1, alpha: 1.0)
        
        let itemAppearance = UITabBarItemAppearance()
        itemAppearance.normal.iconColor = .darkGray
        itemAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.darkGray]
        itemAppearance.selected.iconColor = .systemBlue
        itemAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemBlue]
        
        appearance.stackedLayoutAppearance = itemAppearance
        
        UITabBar.appearance().standardAppearance = appearance
        if #available(iOS 15.0, *) {
            UITabBar.appearance().scrollEdgeAppearance = appearance
        }
    }
    
    var body: some View {
        TabView {
            TerminalView()
                .tabItem {
                    Label("Terminal", systemImage: "terminal")
                }
            
            AIApprovalView()
                .tabItem {
                    Label("Inbox", systemImage: "tray.fill")
                }
                // Add badge if there are pending approvals
                .badge(wsManager.pendingApprovals.isEmpty ? 0 : wsManager.pendingApprovals.count)
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
        }
        // Force dark mode globally for the sleek modern aesthetic
        .preferredColorScheme(.dark)
        // Connect to WebSocket when the app launches (using placeholder connection for UI)
        .onAppear {
            if !wsManager.isConnected {
                wsManager.connect()
            }
        }
    }
}

#Preview {
    ContentView()
}
