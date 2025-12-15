//
//  Dalle2App.swift
//  Dalle2
//
//  Created by Lukas Lozada on 12/2/25.
//

import SwiftUI

@main
struct MyApp: App {
    @StateObject var settings = AppSettings()
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
    }
}
