//
//  ImageGeneratorView.swift
//  Dalle2
//
//  Created by Lukas Lozada on 12/2/25.
//

import SwiftUI
import UIKit

struct ImageGeneratorView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var promptText: String = ""
    @State private var generatedImages: [UIImage] = []
    @State private var selectedImageIndex: Int = 0
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var rotationAngle: Double = 0
    @State private var saveHelper: PhotoSaveHelper?
    
    var body: some View {
        NavigationView {
            VStack {
                // Display generated image(s) or loading/progress
                if isLoading {
                    VStack(spacing: 16) {
                        Image("openai-logo")
                            .renderingMode(.template)
                            .resizable()
                            .scaledToFit()
                            .foregroundColor(.primary)
                            .frame(width: 120, height: 120)
                            .rotationEffect(.degrees(rotationAngle))
                            .onAppear { startSpinner() }
                            .onChange(of: isLoading) { _, newValue in
                                if newValue {
                                    startSpinner()
                                } else {
                                    stopSpinner()
                                }
                            }
                        Text("Generating image...")
                    }
                    .padding()
                } else if !generatedImages.isEmpty {
                    VStack(spacing: 12) {
                        if let currentImage = generatedImages[safe: selectedImageIndex] {
                            Image(uiImage: currentImage)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 320)
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(Color(UIColor.secondarySystemBackground))
                                )
                                .shadow(radius: 6)
                        }
                        
                        if generatedImages.count > 1 {
                            Text("Image \(selectedImageIndex + 1) of \(generatedImages.count)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            
                            HStack {
                                Button {
                                    stepImage(direction: -1)
                                } label: {
                                    Label("Previous", systemImage: "chevron.left")
                                }
                                .disabled(selectedImageIndex == 0)
                                
                                Spacer()
                                
                                Button {
                                    stepImage(direction: 1)
                                } label: {
                                    Label("Next", systemImage: "chevron.right")
                                }
                                .disabled(selectedImageIndex >= generatedImages.count - 1)
                            }
                            .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal)
                    // Buttons for Save
                    HStack {
                        Button(action: saveCurrentImage) {
                            Label("Save Image", systemImage: "square.and.arrow.down")
                        }
                        .padding()
                    }
                }

                // Prompt input field
                TextField("Enter a prompt", text: $promptText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .padding(.horizontal)
                
                // Generate button
                Button(action: {
                    Task { await generateImage() }
                }) {
                    Text("Generate Image")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .disabled(promptText.trimmingCharacters(in: .whitespaces).isEmpty || isLoading)
                .padding(.horizontal)                
            }
            .navigationTitle("DALL-E 2")
            .alert(item: $errorMessage) { msg in
                Alert(title: Text("Notice"), message: Text(msg), dismissButton: .default(Text("OK")))
            }
        }
    }
    
    // Calls the OpenAIService to generate images based on the prompt
    func generateImage() async {
        errorMessage = nil
        isLoading = true
        settings.isGenerating = true
        startSpinner()
        defer {
            isLoading = false
            settings.isGenerating = false
            stopSpinner()
        }
        do {
            let images = try await OpenAIService.generateImages(prompt: promptText,
                                                                n: settings.imageCount,
                                                                size: settings.imageSize)
            generatedImages = images
            selectedImageIndex = 0  // reset selection to first image
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    // Saves the currently selected image to the Photo Library
    func saveCurrentImage() {
        guard !generatedImages.isEmpty else { return }
        let imageToSave = generatedImages[selectedImageIndex]
        let helper = PhotoSaveHelper { error in
            DispatchQueue.main.async {
                if let error {
                    errorMessage = "Could not save image: \(error.localizedDescription)"
                } else {
                    errorMessage = "Image saved to your Photo Library."
                }
                saveHelper = nil
            }
        }
        saveHelper = helper
        UIImageWriteToSavedPhotosAlbum(imageToSave, helper, #selector(PhotoSaveHelper.image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    // Simulates the loading animation without performing an API call.
    private func startSpinner() {
        rotationAngle = 0
        // Slow, continuous rotation
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            rotationAngle = 360
        }
    }
    
    private func stopSpinner() {
        withAnimation(.none) {
            rotationAngle = 0
        }
    }
    
    // Step through images.
    private func stepImage(direction: Int) {
        guard !generatedImages.isEmpty else { return }
        let newIndex = selectedImageIndex + direction
        selectedImageIndex = min(max(newIndex, 0), generatedImages.count - 1)
    }
}
