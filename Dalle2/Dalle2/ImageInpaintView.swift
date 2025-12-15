//
//  ImageInpaintView.swift
//  Dalle2
//
//  Created by Lukas Lozada on 12/2/25.
//

import SwiftUI
import PhotosUI

private struct Notice: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

enum InpaintMode: String, CaseIterable, Identifiable {
    case inpaint = "Inpaint"
    case outpaint = "Outpaint"
    
    var id: String { rawValue }
}

struct ImageInpaintView: View {
    @State private var pickedPhotoItem: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var notice: Notice?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                if let image = selectedImage {
                    ImageInpaintEditor(baseImage: image, changeImageAction: { pickedPhotoItem = nil; selectedImage = nil })
                } else {
                    PhotosPicker(selection: $pickedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        Text("Import Image to Inpaint")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(UIColor.secondarySystemBackground))
                            .cornerRadius(12)
                    }
                    .padding(.horizontal)
                    .onChange(of: pickedPhotoItem) { _, newItem in
                        Task { await handlePickedPhoto(newItem) }
                    }
                    Spacer()
                }
            }
            .navigationTitle("Inpaint")
            .toolbar {
                if selectedImage != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Change Image") {
                            pickedPhotoItem = nil
                            selectedImage = nil
                        }
                    }
                }
            }
            .alert(item: $notice) { item in
                Alert(title: Text(item.title), message: Text(item.message), dismissButton: .default(Text("OK")))
            }
            .preferredColorScheme(nil)
        }
    }
    
    private func handlePickedPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        do {
            if let data = try await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                await MainActor.run {
                    selectedImage = image
                    notice = nil
                }
            } else {
                throw URLError(.badURL)
            }
        } catch {
            await MainActor.run {
                notice = Notice(title: "Error", message: "Could not load selected photo.")
            }
        }
    }
}

struct ImageInpaintEditor: View {
    let baseImage: UIImage  // image to edit (inpaint or Outpaint)
    var changeImageAction: () -> Void = {}
    @State private var editPrompt: String = ""
    @State private var editedImage: UIImage? = nil
    @State private var drawingStrokes: [[CGPoint]] = []   // completed strokes
    @State private var currentStroke: [CGPoint] = []      // stroke in progress
    @State private var canvasWidth: CGFloat = 0           // drawn image display size
    @State private var canvasHeight: CGFloat = 0
    @State private var isEditingImage: Bool = false
    @State private var spinnerAngle: Double = 0
    @State private var alertTitle: String = ""
    @State private var alertMessage: String = ""
    @State private var showingAlert: Bool = false
    @State private var saveHelper: PhotoSaveHelper?
    @State private var mode: InpaintMode = .inpaint
    @State private var contentScale: CGFloat = 1.0
    @State private var isPreviewingOutpaint: Bool = true
    private let strokeWidth: CGFloat = 20

    private var activeImage: UIImage {
        editedImage ?? baseImage
    }

    private var clampedContentScale: CGFloat {
        max(0.4, min(contentScale, 1.0))
    }
    
    private var hasMask: Bool {
        switch mode {
        case .inpaint:
            return !drawingStrokes.isEmpty || !currentStroke.isEmpty
        case .outpaint:
            return clampedContentScale < 0.999
        }
    }
    
    var body: some View {
        VStack {
            if mode == .inpaint {
                Text("Draw on the image to mark areas to edit.")
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Zoom out to fill in areas for outpainting.")
                    .padding(.horizontal)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Picker("Mode", selection: $mode) {
                ForEach(InpaintMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: mode) { _, newValue in
                isPreviewingOutpaint = (newValue == .outpaint)
            }
            
            squareCanvas
                .frame(width: 320, height: 320)
                .padding(.horizontal)
            
            if mode == .outpaint {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Zoom Out Scale")
                    Slider(value: $contentScale, in: 0.4...1.0, step: 0.05)
                    Text("Zoom out and then enter a prompt to fill the canvas with something new.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal)
            }
            
            TextField("Describe your edit", text: $editPrompt)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()
            
            HStack {
                Button {
                    clearMask()
                } label: {
                    Label("Clear", systemImage: "trash")
                }
                .padding()
                
                Button("Apply Edit") {
                    Task { await applyEdit() }
                }
                .disabled(isEditingImage || editPrompt.trimmingCharacters(in: .whitespaces).isEmpty || !hasMask)
                .padding()
                
                Button {
                    saveEditedImage()
                } label: {
                    Label("Save", systemImage: "square.and.arrow.down")
                }
                .disabled(editedImage == nil)
                .padding()
            }
        }
        .alert(alertTitle, isPresented: $showingAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .padding()
        .onChange(of: isEditingImage) { _, newValue in
            if newValue {
                startSpinner()
            } else {
                stopSpinner()
            }
        }
        .onChange(of: contentScale) { _, _ in
            if mode == .outpaint {
                isPreviewingOutpaint = true
            }
        }
        .overlay(alignment: .center) {
            if isEditingImage {
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
                            .rotationEffect(.degrees(spinnerAngle))
                            .onAppear { startSpinner() }
                        Text("Applying edit...")
                            .foregroundStyle(.primary)
                    }
                    .padding()
                    .background(Color(UIColor.systemBackground))
                    .cornerRadius(12)
                }
            }
        }
    }
    
    // Square canvas for drawing/inpainting or Outpaint.
    private var squareCanvas: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let displaySize = fittedImageSize(for: CGSize(width: side, height: side))
            let contentRect = self.contentRect(in: displaySize)
            let shouldPreviewOutpaint = mode == .outpaint && (isPreviewingOutpaint || isEditingImage)
            let displayScale: CGFloat = shouldPreviewOutpaint ? clampedContentScale : 1.0
            
            ZStack {
                let displayImage: UIImage = activeImage
                Image(uiImage: displayImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: displaySize.width, height: displaySize.height)
                    .scaleEffect(displayScale)
                
                if mode == .outpaint && shouldPreviewOutpaint {
                    EvenOddShape(innerRect: contentRect)
                        .fill(Color(.systemBackground).opacity(0.25), style: FillStyle(eoFill: true))
                        .frame(width: displaySize.width, height: displaySize.height)
                } else {
                    Path { path in
                        for stroke in drawingStrokes {
                            guard !stroke.isEmpty else { continue }
                            path.move(to: stroke[0])
                            for point in stroke.dropFirst() {
                                path.addLine(to: point)
                            }
                        }
                        
                        if !currentStroke.isEmpty {
                            path.move(to: currentStroke[0])
                            for point in currentStroke.dropFirst() {
                                path.addLine(to: point)
                            }
                        }
                    }
                    .stroke(Color.accentColor.opacity(0.7),
                            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round, lineJoin: .round))
                    .frame(width: displaySize.width, height: displaySize.height)
                    
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: displaySize.width, height: displaySize.height)
                        .contentShape(Rectangle())
                        .gesture(DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let point = value.location
                                if point.x >= 0 && point.x <= displaySize.width && point.y >= 0 && point.y <= displaySize.height {
                                    currentStroke.append(point)
                                }
                            }
                            .onEnded { _ in
                                if !currentStroke.isEmpty {
                                    drawingStrokes.append(currentStroke)
                                    currentStroke = []
                                }
                            }
                        )
                }
            }
            .frame(width: side, height: side)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .onAppear {
                updateCanvasSizeIfNeeded(displaySize)
            }
            .onChange(of: editedImage) { _, _ in
                updateCanvasSizeIfNeeded(displaySize)
            }
            .onChange(of: geo.size) { _, newSize in
                let newSide = min(newSize.width, newSize.height)
                updateCanvasSizeIfNeeded(fittedImageSize(for: CGSize(width: newSide, height: newSide)))
            }
        }
        .border(Color.gray)
    }
    
    private func contentRect(in displaySize: CGSize) -> CGRect {
        let scale = clampedContentScale
        let width = displaySize.width * scale
        let height = displaySize.height * scale
        let origin = CGPoint(x: (displaySize.width - width) / 2, y: (displaySize.height - height) / 2)
        return CGRect(origin: origin, size: CGSize(width: width, height: height))
    }
    
    private func preparedBaseImage() -> UIImage {
        let sourceImage = activeImage
        guard mode == .outpaint else { return sourceImage }
        let scale = clampedContentScale
        let targetSize = sourceImage.size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            UIColor.clear.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            let drawWidth = targetSize.width * scale
            let drawHeight = targetSize.height * scale
            let origin = CGPoint(x: (targetSize.width - drawWidth) / 2, y: (targetSize.height - drawHeight) / 2)
            sourceImage.draw(in: CGRect(origin: origin, size: CGSize(width: drawWidth, height: drawHeight)))
        }
    }
    
    // Calls OpenAI to perform image editing (inpainting) with the mask
    func applyEdit() async {
        guard !isEditingImage else { return }
        guard hasMask else {
            showAlert(title: "Error", message: "Draw on the image (or scale down) to mark areas to edit before applying.")
            return
        }
        isEditingImage = true
        showingAlert = false
        do {
            let preparedBase = preparedBaseImage()
            let maskImage = generateMaskImage(for: preparedBase.size)
            
            let sizeOption = "\(Int(preparedBase.size.width))x\(Int(preparedBase.size.height))"
            let resultImage = try await OpenAIService.editImage(baseImage: preparedBase,
                                                                maskImage: maskImage,
                                                                prompt: editPrompt,
                                                                size: sizeOption)
            editedImage = resultImage
            if mode == .outpaint {
                isPreviewingOutpaint = false
            }
            clearMask()
        } catch {
            showAlert(title: "Error", message: "Failed to edit image: \(error.localizedDescription)")
        }
        isEditingImage = false
    }

    private func saveEditedImage() {
        guard let editedImage else { return }
        let helper = PhotoSaveHelper { error in
            DispatchQueue.main.async {
                if let error {
                    showAlert(title: "Error", message: "Could not save image: \(error.localizedDescription)")
                } else {
                    showAlert(title: "Saved", message: "Image saved to your Photo Library.")
                }
                saveHelper = nil
            }
        }
        saveHelper = helper
        UIImageWriteToSavedPhotosAlbum(editedImage, helper, #selector(PhotoSaveHelper.image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    // Create a mask image for inpaint or Outpaint.
    func generateMaskImage(for size: CGSize) -> UIImage {
        let width = Int(size.width)
        let height = Int(size.height)
        
        UIGraphicsBeginImageContextWithOptions(CGSize(width: width, height: height), false, 1.0)
        guard let ctx = UIGraphicsGetCurrentContext() else { return baseImage }
        ctx.setFillColor(UIColor.white.cgColor)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        switch mode {
        case .outpaint:
            ctx.setBlendMode(.clear)
            let scale = clampedContentScale
            let drawWidth = CGFloat(width) * scale
            let drawHeight = CGFloat(height) * scale
            let insetX = (CGFloat(width) - drawWidth) / 2
            let insetY = (CGFloat(height) - drawHeight) / 2
            // Clear outside the content rect (area to fill)
            ctx.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: insetY))
            ctx.fill(CGRect(x: 0, y: CGFloat(height) - insetY, width: CGFloat(width), height: insetY))
            ctx.fill(CGRect(x: 0, y: insetY, width: insetX, height: drawHeight))
            ctx.fill(CGRect(x: CGFloat(width) - insetX, y: insetY, width: insetX, height: drawHeight))
        case .inpaint:
            ctx.setStrokeColor(UIColor.clear.cgColor)
            let strokeWidthPx = strokeWidth * (CGFloat(width) / (canvasWidth == 0 ? CGFloat(width) : canvasWidth))
            ctx.setLineWidth(strokeWidthPx)
            ctx.setLineCap(.round)
            ctx.setBlendMode(.clear)
            
            let xRatio = canvasWidth > 0 ? CGFloat(width) / canvasWidth : 1.0
            let yRatio = canvasHeight > 0 ? CGFloat(height) / canvasHeight : 1.0
            
            for stroke in drawingStrokes {
                guard !stroke.isEmpty else { continue }
                ctx.beginPath()
                ctx.move(to: CGPoint(x: stroke[0].x * xRatio, y: stroke[0].y * yRatio))
                for point in stroke.dropFirst() {
                    ctx.addLine(to: CGPoint(x: point.x * xRatio, y: point.y * yRatio))
                }
                ctx.strokePath()
            }
            if !currentStroke.isEmpty {
                ctx.beginPath()
                ctx.move(to: CGPoint(x: currentStroke[0].x * xRatio, y: currentStroke[0].y * yRatio))
                for point in currentStroke.dropFirst() {
                    ctx.addLine(to: CGPoint(x: point.x * xRatio, y: point.y * yRatio))
                }
                ctx.strokePath()
            }
        }
        
        let maskImg = UIGraphicsGetImageFromCurrentImageContext() ?? UIImage()
        UIGraphicsEndImageContext()
        return maskImg
    }
    
    private func clearMask() {
        drawingStrokes.removeAll()
        currentStroke.removeAll()
    }
    
    private func fittedImageSize(for containerSize: CGSize) -> CGSize {
        let imgSize = activeImage.size
        guard imgSize.width > 0, imgSize.height > 0 else {
            return .zero
        }
        let aspect = imgSize.width / imgSize.height
        var displayWidth = containerSize.width
        var displayHeight = containerSize.width / aspect
        if displayHeight > containerSize.height {
            displayHeight = containerSize.height
            displayWidth = displayHeight * aspect
        }
        return CGSize(width: displayWidth, height: displayHeight)
    }
    
    private func updateCanvasSizeIfNeeded(_ newSize: CGSize) {
        if canvasWidth != newSize.width || canvasHeight != newSize.height {
            canvasWidth = newSize.width
            canvasHeight = newSize.height
        }
    }
    
    private func startSpinner() {
        spinnerAngle = 0
        withAnimation(.linear(duration: 3).repeatForever(autoreverses: false)) {
            spinnerAngle = 360
        }
    }
    
    private func stopSpinner() {
        withAnimation(.none) {
            spinnerAngle = 0
        }
    }
    
    private func showAlert(title: String, message: String) {
        alertTitle = title
        alertMessage = message
        showingAlert = true
    }
}

private struct EvenOddShape: Shape {
    let innerRect: CGRect
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addRect(rect)
        path.addRect(innerRect)
        return path
    }
}

#Preview {
    ImageInpaintView()
}
