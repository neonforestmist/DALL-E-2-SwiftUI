//
//  VariationsView.swift
//  DALLE-2
//
//  Created by Lukas Lozada on 12/22/25.
//

import SwiftUI
import PhotosUI
import UIKit

struct VariationsView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var sourceImage: UIImage?
    @State private var variationImages: [UIImage] = []
    @State private var selectedVariationIndex: Int = 0
    @State private var variationCount: Int = 1
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var rotationAngle: Double = 0
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if sourceImage == nil {
                        PhotosPicker(selection: $pickedPhotoItem, matching: .images, photoLibrary: .shared()) {
                            Text("Import Image")
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(12)
                        }
                        .padding(.horizontal)
                        .onChange(of: pickedPhotoItem) { _, newItem in
                            Task { await handlePickedPhoto(newItem) }
                        }

                        Text("Import an image to create variations.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 16)
                    }

                    if !variationImages.isEmpty {
                        if let currentImage = variationImages[safe: selectedVariationIndex] {
                            Image(uiImage: currentImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 320)
                                .padding(.horizontal)
                        }

                        if variationImages.count > 1 {
                            Text("Variation \(selectedVariationIndex + 1) of \(variationImages.count)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)

                            HStack {
                                Button {
                                    stepVariation(direction: -1)
                                } label: {
                                    Label("Previous", systemImage: "chevron.left")
                                }
                                .disabled(selectedVariationIndex == 0)

                                Spacer()

                                Button {
                                    stepVariation(direction: 1)
                                } label: {
                                    HStack(spacing: 4) {
                                        Text("Next")
                                        Image(systemName: "chevron.right")
                                    }
                                }
                                .disabled(selectedVariationIndex >= variationImages.count - 1)
                            }
                            .padding(.horizontal)
                        }
                    } else if let sourceImage {
                        Image(uiImage: sourceImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 300, height: 300)
                            .clipped()
                            .cornerRadius(12)
                            .padding(.horizontal)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("How many variations should be included?")

                            Stepper("Variations: \(variationCount)", value: $variationCount, in: 1...4)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)

                        Button(action: {
                            Task { await generateVariations() }
                        }) {
                            Text("Generate Variations")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                        }
                        .disabled(isLoading)
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Variations")
            .toolbar {
                if sourceImage != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Change Image") {
                            pickedPhotoItem = nil
                            sourceImage = nil
                            variationImages = []
                            selectedVariationIndex = 0
                        }
                    }
                }
            }
            .onChange(of: isLoading) { _, newValue in
                if newValue {
                    startSpinner()
                } else {
                    stopSpinner()
                }
            }
            .alert(item: $errorMessage) { msg in
                Alert(title: Text("Notice"), message: Text(msg), dismissButton: .default(Text("OK")))
            }
            .overlay(alignment: .center) {
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.25)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            Image("openai-logo")
                                .renderingMode(.template)
                                .resizable()
                                .scaledToFit()
                                .foregroundStyle(.primary)
                                .frame(width: 90, height: 90)
                                .rotationEffect(.degrees(rotationAngle))
                                .onAppear { startSpinner() }
                            Text("Generating variations...")
                                .foregroundStyle(.primary)
                        }
                        .padding()
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(12)
                    }
                }
            }
        }
    }
    
    private func handlePickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let cropped = image.croppedToSquare()
                await MainActor.run {
                    sourceImage = cropped
                    variationImages = []
                    selectedVariationIndex = 0
                    errorMessage = nil
                }
            } else {
                throw URLError(.badURL)
            }
        } catch {
            await MainActor.run {
                errorMessage = "Could not load selected photo."
            }
        }
    }
    
    private func generateVariations() async {
        guard let sourceImage else { return }
        errorMessage = nil
        isLoading = true
        defer {
            isLoading = false
        }
        do {
            let images = try await OpenAIService.generateVariations(image: sourceImage,
                                                                    n: variationCount,
                                                                    size: settings.imageSize)
            variationImages = images
            selectedVariationIndex = 0
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private func startSpinner() {
        rotationAngle = 0
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
    }
    
    private func stopSpinner() {
        withAnimation(.none) {
            rotationAngle = 0
        }
    }
    
    private func stepVariation(direction: Int) {
        guard !variationImages.isEmpty else { return }
        let newIndex = selectedVariationIndex + direction
        selectedVariationIndex = min(max(newIndex, 0), variationImages.count - 1)
    }
}
