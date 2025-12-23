//
//  OpenAIService.swift
//  Dalle2
//
//  Created by Lukas Lozada on 12/2/25.
//

import Foundation
import UIKit

struct OpenAIService {
    
    // Paste your OPENAI_API_KEY below.
    static var apiKey: String = "OPENAI_API_KEY"
    static let generationURL = URL(string: "https://api.openai.com/v1/images/generations")!
    static let editURL = URL(string: "https://api.openai.com/v1/images/edits")!
    static let variationsURL = URL(string: "https://api.openai.com/v1/images/variations")!
    private static let jsonDecoder = JSONDecoder()
    
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
        
        if let imageData = baseImage.pngData() {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.png\"\r\n".data(using: .utf8)!)
            body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
            body.append(imageData)
            body.append("\r\n".data(using: .utf8)!)
        }
        if let maskData = maskImage.pngData() {
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
        
        guard let imageData = image.pngData() else {
            throw OpenAIServiceError.invalidImageData
        }
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"image.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)
        appendField(name: "n", value: "\(n)")
        appendField(name: "size", value: size)
        appendField(name: "model", value: model)
        appendField(name: "response_format", value: "url")
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body
        
        let data = try await sendJSONRequest(request)
        let response = try jsonDecoder.decode(ImageResponse.self, from: data)
        let images = try await images(from: response.data)
        guard !images.isEmpty else { throw OpenAIServiceError.invalidImageData }
        return images
    }
    
    private static func sendJSONRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard (200..<300).contains(httpResponse.statusCode) else {
            let message = try? jsonDecoder.decode(ErrorResponse.self, from: data).error.message
            throw OpenAIServiceError.invalidResponse(status: httpResponse.statusCode, message: message)
        }
        return data
    }
    
    private static func images(from items: [ImageResponse.DataItem]) async throws -> [UIImage] {
        var images: [UIImage] = []
        for item in items {
            if let urlString = item.url, let url = URL(string: urlString) {
                let (data, _) = try await URLSession.shared.data(from: url)
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
}
