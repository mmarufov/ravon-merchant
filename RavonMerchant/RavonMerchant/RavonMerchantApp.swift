//
//  RavonMerchantApp.swift
//  RavonMerchant
//
//  Created by Muhammad Marufov on 3/17/26.
//

import SwiftUI
import Foundation
import RavonCore

@main
struct RavonMerchantApp: App {
    init() {
        // Must run synchronously — AuthService.shared (used by ContentView) preconditions on this.
        RavonCore.configure(
            supabaseURL: URL(string: "https://imcintoicxvmvzwpmxpr.supabase.co")!,
            supabaseAnonKey: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImltY2ludG9pY3h2bXZ6d3BteHByIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMzNjEzOTYsImV4cCI6MjA4ODkzNzM5Nn0.Zt6rf00A9zayGExH4ZRwcZJY5W7z09XqR1S9rkwB-M4"
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}
