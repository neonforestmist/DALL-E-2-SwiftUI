//
//  ContentView.swift
//  Dalle2
//
//  Created by Lukas Lozada on 12/2/25.
//

import SwiftUI
import UIKit

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    
    var body: some View {
        TabView {
            ImageGeneratorView()
                .tabItem {
                    GenerateTabIcon(isSpinning: settings.isGenerating)
                }
            ImageCropperView()
                .tabItem {
                    Image(systemName: "crop")
                    Text("Resize")
                }
            ImageInpaintView()
                .tabItem {
                    Image(systemName: "paintbrush.fill")
                    Text("Inpaint")
                }
            SettingsView()
                .tabItem {
                    Image(systemName: "gearshape")
                    Text("Settings")
                }
        }
        .preferredColorScheme(settings.appearance.colorScheme)
    }
}

extension String: Identifiable {
    public var id: String { self }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
}

private struct GenerateTabIcon: View {
    let isSpinning: Bool
    private static let iconSize: CGFloat = 24
    private static let iconImage: UIImage = {
        guard let base = UIImage(named: "openai-logo")?.withRenderingMode(.alwaysTemplate) else {
            return UIImage()
        }
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: iconSize, height: iconSize))
        return renderer.image { _ in
            base.draw(in: CGRect(origin: .zero, size: CGSize(width: iconSize, height: iconSize)))
        }
    }()
    
    var body: some View {
        Label {
            Text("Generate")
        } icon: {
            Image(uiImage: Self.iconImage)
                .rotationEffect(Angle.degrees(isSpinning ? 360 : 0))
                .animation(isSpinning ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default,
                           value: isSpinning)
        }
    }
}
