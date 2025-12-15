//
//  AppSettings.swift
//  Dalle2
//
//  Created by Lukas Lozada on 12/2/25.
//

import Foundation
import SwiftUI
import Combine

enum AppAppearance: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var id: String { rawValue }
}

class AppSettings: ObservableObject {
    @Published var imageSize: String = "512x512"
    @Published var imageCount: Int = 1
    @Published var appearance: AppAppearance = .system
    @Published var isGenerating: Bool = false
}

extension AppAppearance {
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}
