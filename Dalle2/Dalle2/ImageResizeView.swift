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
    @State private var cropOffset: CGSize = .zero      // current drag translation
    @State private var committedOffset: CGSize = .zero  // offset from previous drags
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if originalImage == nil {
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

                        Text("Pick an image to resize for use of inpainting.")
                            .foregroundStyle(.secondary)
                            .padding(.top, 40)
                    }

                    if let preview = resizedImage ?? originalImage {
                        let aspect = preview.size.width / preview.size.height
                        let isWide = aspect > 1
                        let imgW: CGFloat = isWide ? 300 * aspect : 300
                        let imgH: CGFloat = isWide ? 300 : 300 / aspect
                        let maxDragX = max((imgW - 300) / 2, 0)
                        let maxDragY = max((imgH - 300) / 2, 0)
                        let totalOffsetW = committedOffset.width + cropOffset.width
                        let totalOffsetH = committedOffset.height + cropOffset.height
                        let clampedX = min(max(totalOffsetW, -maxDragX), maxDragX)
                        let clampedY = min(max(totalOffsetH, -maxDragY), maxDragY)

                        ZStack {
                            Image(uiImage: preview)
                                .resizable()
                                .scaledToFill()
                                .frame(width: imgW, height: imgH)
                                .offset(x: clampedX, y: clampedY)
                        }
                        .frame(width: 300, height: 300)
                        .clipped()
                        .cornerRadius(12)
                        .contentShape(Rectangle())
                        .gesture(
                            resizedImage == nil ?
                            DragGesture()
                                .onChanged { value in
                                    cropOffset = value.translation
                                }
                                .onEnded { value in
                                    let newW = committedOffset.width + value.translation.width
                                    let newH = committedOffset.height + value.translation.height
                                    committedOffset = CGSize(
                                        width: min(max(newW, -maxDragX), maxDragX),
                                        height: min(max(newH, -maxDragY), maxDragY)
                                    )
                                    cropOffset = .zero
                                }
                            : nil
                        )
                        .padding(.horizontal)
                    }

                    if originalImage != nil {
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
                            .disabled(isProcessing)

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
                }
                .padding(.vertical)
            }
            .navigationTitle("Resize")
            .toolbar {
                if originalImage != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        PhotosPicker(selection: $pickedPhotoItem, matching: .images, photoLibrary: .shared()) {
                            Text("Change Image")
                        }
                        .onChange(of: pickedPhotoItem) { _, newItem in
                            Task { await handlePickedPhoto(newItem) }
                        }
                    }
                }
            }
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
                    cropOffset = .zero
                    committedOffset = .zero
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
        let offset = committedOffset

        DispatchQueue.global(qos: .userInitiated).async {
            let normalized = originalImage.normalizedImage()

            // Convert the drag offset from preview coordinates to normalized (-1...1)
            let aspect = normalized.size.width / normalized.size.height
            let isWide = aspect > 1
            let previewW: CGFloat = isWide ? 300 * aspect : 300
            let previewH: CGFloat = isWide ? 300 : 300 / aspect
            let maxDragX = max((previewW - 300) / 2, 0)
            let maxDragY = max((previewH - 300) / 2, 0)
            let normX: CGFloat = maxDragX > 0 ? offset.width / maxDragX : 0  // -1 to 1
            let normY: CGFloat = maxDragY > 0 ? offset.height / maxDragY : 0

            let result = normalized.resizedToSquareCanvas(side: targetSide, normalizedOffsetX: normX, normalizedOffsetY: normY)
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
    
    // Resizes the image to fill a square canvas while preserving aspect ratio.
    // normalizedOffsetX/Y: -1...1 where 0 = centered, -1 = shifted fully left/up, 1 = shifted fully right/down.
    func resizedToSquareCanvas(side: Int, normalizedOffsetX: CGFloat = 0, normalizedOffsetY: CGFloat = 0) -> UIImage {
        let targetSide = CGFloat(side)
        let targetSize = CGSize(width: targetSide, height: targetSide)
        let sourceWidth = cgImage.map { CGFloat($0.width) } ?? size.width * scale
        let sourceHeight = cgImage.map { CGFloat($0.height) } ?? size.height * scale
        let aspectWidth = targetSize.width / sourceWidth
        let aspectHeight = targetSize.height / sourceHeight
        let scaleFactor = max(aspectWidth, aspectHeight)
        let newSize = CGSize(width: sourceWidth * scaleFactor, height: sourceHeight * scaleFactor)
        // Center origin, then shift by normalized offset
        let centerX = (targetSize.width - newSize.width) / 2
        let centerY = (targetSize.height - newSize.height) / 2
        let origin = CGPoint(
            x: centerX + normalizedOffsetX * centerX,
            y: centerY + normalizedOffsetY * centerY
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: origin, size: newSize))
        }
    }
}

#Preview {
    ImageCropperView()
}
