//
//  SettingsView.swift
//  Dalle2
//
//  Created by Lukas Lozada on 12/2/25.
//


import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    private let sizeOptions = ["256x256", "512x512", "1024x1024"]
    private let countOptions = [1, 2, 3, 4, 5]  // max 5 shown (OpenAI API supports up to 10 images)
    private let appearanceOptions = AppAppearance.allCases
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Appearance")) {
                    Picker("Mode", selection: $settings.appearance) {
                        ForEach(appearanceOptions) { appearance in
                            Text(appearance.rawValue).tag(appearance)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }
                Section(header: Text("Image Gen Settings")) {
                    Picker("Image Size", selection: $settings.imageSize) {
                        ForEach(sizeOptions, id: \.self) { size in
                            Text(size)
                        }
                    }
                    Picker("Number of Images", selection: $settings.imageCount) {
                        ForEach(countOptions, id: \.self) { num in
                            Text("\(num)")
                        }
                    }
                }
                Section(footer: Text("NOTE: Dalle-2 is getting deprecated on 2026-05-12.")) {
                    EmptyView()
                }
                
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        PricingRow(font: .caption2, weight: .semibold,
                                   columns: ["MODEL", "QUALITY", "256 x 256", "512 x 512", "1024 x 1024"])
                        Divider()
                        PricingRow(font: .footnote, weight: .regular,
                                   columns: ["DALL·E 2", "Standard", "$0.016", "$0.018", "$0.02"])
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

private struct PricingRow: View {
    let font: Font
    let weight: Font.Weight
    let columns: [String]
    
    var body: some View {
        HStack {
            ForEach(columns.indices, id: \.self) { idx in
                Text(columns[idx])
                    .font(font.weight(weight))
                    .frame(maxWidth: .infinity, alignment: idx == 0 ? .leading : .center)
            }
        }
    }
}

#Preview {
    SettingsView()
}
