//
//  ImageResizeView.swift
//  Dalle2
//
//  Created by Lukas Lozada on 12/2/25.
//

import SwiftUI
import PhotosUI

struct ImageCropperView: View {
    private enum SquareSize: Int, CaseIterable, Identifiable {
        case small = 256
        case medium = 512
        case large = 1024
        
        var id: Int { rawValue }
        var label: String { "\(rawValue)x\(rawValue)" }
    }
    
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var originalImage: UIImage?
    @State private var resizedImage: UIImage?
    @State private var selectedSize: SquareSize = .medium
    @State private var isProcessing = false
    @State private var alertItem: AlertItem?
    @State private var saveHelper: PhotoSaveHelper?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    PhotosPicker(selection: $pickedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        Text(originalImage == nil ? "Import Image" : "Change Image")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .onChange(of: pickedPhotoItem) { _, newItem in
                        Task { await handlePickedPhoto(newItem) }
                    }
                    
                    if let preview = resizedImage ?? originalImage {
                        ZStack {
                            Rectangle()
                                .fill(Color.black)
                                .frame(height: 320)
                                .cornerRadius(12)
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFit()
                                .frame(height: 300)
                                .padding(8)
                                .cornerRadius(8)
                        }
                        .padding(.horizontal)
                    } else {
                        Text("Pick an image to resize for use of inpainting.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Output Size")
                            .font(.headline)
                        Picker("Output Size", selection: $selectedSize) {
                            ForEach(SquareSize.allCases) { size in
                                Text(size.label).tag(size)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .padding(.horizontal)
                    
                    HStack(spacing: 16) {
                        Button {
                            Task { await resizeImage() }
                        } label: {
                            Label("Resize", systemImage: "arrow.up.left.and.arrow.down.right")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(originalImage == nil || isProcessing)
                        
                        Button {
                            saveResizedImage()
                        } label: {
                            Label("Save", systemImage: "square.and.arrow.down")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .disabled(resizedImage == nil)
                    }
                    .padding(.horizontal)
                    
                    if isProcessing {
                        ProgressView("Processing...")
                            .padding(.top, 8)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Resize")
            .alert(item: $alertItem) { item in
                Alert(
                    title: Text(item.title),
                    message: Text(item.message),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }
    
    private func handlePickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    originalImage = image
                    resizedImage = nil
                }
            } else {
                throw URLError(.badURL)
            }
        } catch {
            await MainActor.run {
                alertItem = AlertItem(title: "Error", message: "Could not load selected photo.")
            }
        }
    }
    
    private func resizeImage() async {
        guard let originalImage else { return }
        guard !isProcessing else { return }
        
        isProcessing = true
        let targetSide = selectedSize.rawValue
        
        DispatchQueue.global(qos: .userInitiated).async {
            let normalized = originalImage.normalizedImage()
            let result = normalized.resizedToSquareCanvas(side: targetSide)
            DispatchQueue.main.async {
                resizedImage = result
                isProcessing = false
                alertItem = AlertItem(
                    title: "Image Resized",
                    message: "Output set to \(targetSide)x\(targetSide) pixels."
                )
            }
        }
    }
    
    private func saveResizedImage() {
        guard let resizedImage else {
            alertItem = AlertItem(title: "Error", message: "Please resize an image first.")
            return
        }
        let helper = PhotoSaveHelper { error in
            if let error {
                alertItem = AlertItem(title: "Error", message: "Could not save image: \(error.localizedDescription)")
            } else {
                alertItem = AlertItem(title: "Saved", message: "Image saved to your Photo Library.")
            }
            saveHelper = nil
        }
        saveHelper = helper
        UIImageWriteToSavedPhotosAlbum(resizedImage, helper, #selector(PhotoSaveHelper.image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
}

// helpers
private struct AlertItem: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

private extension UIImage {
    
    // Returns an orientation-corrected copy.
    func normalizedImage() -> UIImage {
        if imageOrientation == .up {
            return self
        }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
    
    // Resizes the image to fill a square canvas (no bars) while preserving aspect ratio; excess is clipped.
    func resizedToSquareCanvas(side: Int) -> UIImage {
        let targetSide = CGFloat(side)
        let targetSize = CGSize(width: targetSide, height: targetSide)
        // Work in pixel space to avoid Retina scaling changing the output dimensions.
        let sourceWidth = cgImage.map { CGFloat($0.width) } ?? size.width * scale
        let sourceHeight = cgImage.map { CGFloat($0.height) } ?? size.height * scale
        let aspectWidth = targetSize.width / sourceWidth
        let aspectHeight = targetSize.height / sourceHeight
        // Use the larger scale to cover the square fully (no borders), then center and crop.
        let scaleFactor = max(aspectWidth, aspectHeight)
        let newSize = CGSize(width: sourceWidth * scaleFactor, height: sourceHeight * scaleFactor)
        let origin = CGPoint(x: (targetSize.width - newSize.width) / 2,
                             y: (targetSize.height - newSize.height) / 2)
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1 // ensure exact pixel output (1 point = 1 pixel)
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: origin, size: newSize))
        }
    }
}

#Preview {
    ImageCropperView()
}
