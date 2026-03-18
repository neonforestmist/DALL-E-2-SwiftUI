//
//  OpenAIService.swift
//  Dalle2
//
//  Created by Lukas Lozada on 12/2/25.
//

import Foundation
import UIKit

struct OpenAIService {
    
    static var apiKey: String = DotEnv.get("OPENAI_API_KEY") ?? ""
    static let generationURL = URL(string: "https://api.openai.com/v1/images/generations")!
    static let editURL = URL(string: "https://api.openai.com/v1/images/edits")!
    static let variationsURL = URL(string: "https://api.openai.com/v1/images/variations")!
    private static let jsonDecoder = JSONDecoder()
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        return URLSession(configuration: config)
    }()
    
    enum OpenAIServiceError: LocalizedError {
        case missingAPIKey
        case invalidResponse(status: Int, message: String?)
        case invalidImageData
        
        var errorDescription: String? {
            switch self {
            case .missingAPIKey:
                return "OpenAI API key is missing. Update apiKey variable with your key."
            case let .invalidResponse(status, message):
                if let message, !message.isEmpty {
                    return "OpenAI returned status \(status): \(message)"
                }
                if status >= 500 {
                    return "OpenAI's servers are temporarily unavailable. Please try again in a moment."
                }
                return "OpenAI returned an unexpected response (status \(status))."
            case .invalidImageData:
                return "Received image data in an unexpected format."
            }
        }
    }
    
    private struct ImageResponse: Decodable {
        struct DataItem: Decodable {
            let url: String?
            let b64_json: String?
        }
        let data: [DataItem]
    }
    
    private struct ErrorResponse: Decodable {
        struct Detail: Decodable {
            let message: String
        }
        let error: Detail
    }
    
    static func generateImages(prompt: String, n: Int, size: String, model: String = "dall-e-2") async throws -> [UIImage] {
        guard apiKeyIsConfigured else { throw OpenAIServiceError.missingAPIKey }
        var request = URLRequest(url: generationURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: Any] = [
            "prompt": prompt,
            "n": n,
            "size": size,
            "model": model,
            "response_format": "url"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let data = try await sendJSONRequest(request)
        let response = try jsonDecoder.decode(ImageResponse.self, from: data)
        let images = try await images(from: response.data)
        guard !images.isEmpty else { throw OpenAIServiceError.invalidImageData }
        return images
    }
    
    static func editImage(baseImage: UIImage, maskImage: UIImage, prompt: String, size: String, model: String = "dall-e-2") async throws -> UIImage {
        guard apiKeyIsConfigured else { throw OpenAIServiceError.missingAPIKey }
        let boundary = UUID().uuidString
        var request = URLRequest(url: editURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        
        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }
        
        let targetSide = parseSide(from: size)
        let resizedBase = resizeToExactSquare(baseImage, side: targetSide)
        let resizedMask = resizeToExactSquare(maskImage, side: targetSide)

        if let imageData = resizedBase.pngData() {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.png\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }
        if let maskData = resizedMask.pngData() {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"mask\"; filename=\"mask.png\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
            body.append(maskData)
            body.append("\r\n".data(using: .utf8)!)
        }
        appendField(name: "prompt", value: prompt)
        appendField(name: "size", value: size)
        appendField(name: "model", value: model)
        appendField(name: "response_format", value: "url")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let data = try await sendJSONRequest(request)
        let response = try jsonDecoder.decode(ImageResponse.self, from: data)
        guard let edited = try await images(from: response.data).first else {
            throw OpenAIServiceError.invalidImageData
        }
        return edited
    }

    static func generateVariations(image: UIImage, n: Int, size: String, model: String = "dall-e-2") async throws -> [UIImage] {
        guard apiKeyIsConfigured else { throw OpenAIServiceError.missingAPIKey }

        // Resize image to exactly match the requested output size
        let targetSide = parseSide(from: size)
        let squareImage = resizeToExactSquare(image, side: targetSide)

        let boundary = UUID().uuidString
        var request = URLRequest(url: variationsURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()

        func appendField(name: String, value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append(value.data(using: .utf8)!)
            body.append("\r\n".data(using: .utf8)!)
        }

        guard let imageData = squareImage.pngData() else {
            throw OpenAIServiceError.invalidImageData
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        appendField(name: "n", value: "\(n)")
        appendField(name: "size", value: size)
        appendField(name: "response_format", value: "url")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let data = try await sendJSONRequest(request)
        let response = try jsonDecoder.decode(ImageResponse.self, from: data)
        let images = try await images(from: response.data)
        guard !images.isEmpty else { throw OpenAIServiceError.invalidImageData }
        return images
    }
    
    private static func sendJSONRequest(_ request: URLRequest, maxRetries: Int = 2) async throws -> Data {
        var lastError: Error?
        for attempt in 0...maxRetries {
            if attempt > 0 {
                try await Task.sleep(nanoseconds: UInt64(attempt) * 2_000_000_000) // 2s, 4s
            }
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if (200..<300).contains(httpResponse.statusCode) {
                return data
            }
            // Log the raw response for debugging
            if let responseBody = String(data: data, encoding: .utf8) {
                print("[OpenAI] Status \(httpResponse.statusCode) response: \(responseBody)")
            }
            let message = try? jsonDecoder.decode(ErrorResponse.self, from: data).error.message
            let error = OpenAIServiceError.invalidResponse(status: httpResponse.statusCode, message: message)
            // Only retry on server errors (5xx)
            if httpResponse.statusCode >= 500 && attempt < maxRetries {
                lastError = error
                continue
            }
            throw error
        }
        throw lastError ?? URLError(.badServerResponse)
    }
    
    private static func images(from items: [ImageResponse.DataItem]) async throws -> [UIImage] {
        var images: [UIImage] = []
        for item in items {
            if let urlString = item.url, let url = URL(string: urlString) {
                let (data, _) = try await session.data(from: url)
                if let image = UIImage(data: data) {
                    images.append(image)
                }
            } else if let b64 = item.b64_json,
                      let data = Data(base64Encoded: b64),
                      let image = UIImage(data: data) {
                images.append(image)
            }
        }
        return images
    }
    
    private static var apiKeyIsConfigured: Bool {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty
    }

    private static func parseSide(from size: String) -> Int {
        // "512x512" -> 512
        if let side = Int(size.components(separatedBy: "x").first ?? "") {
            return side
        }
        return 512
    }

    private static func resizeToExactSquare(_ image: UIImage, side: Int) -> UIImage {
        let targetSize = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }

    private static func downscaleIfNeeded(_ image: UIImage) -> UIImage {
        let maxSide: CGFloat = 1024
        let w = image.size.width
        let h = image.size.height
        guard w > maxSide || h > maxSide else { return image }
        let scale = maxSide / max(w, h)
        let newSize = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
