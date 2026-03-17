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
        Task { @MainActor in
            RavonCore.configure(
                supabaseURL: URL(string: "https://imcintoicxvmvzwpmxpr.supabase.co")!,
                supabaseAnonKey: "YOUR_SUPABASE_ANON_KEY"
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
