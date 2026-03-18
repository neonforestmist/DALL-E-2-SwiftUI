//
//  DotEnv.swift
//  Dalle2
//
//  Created by Lukas Lozada on 3/17/26.
//

import Foundation

struct DotEnv {

    private static var values: [String: String] = {
        // Navigate from this source file up to the project root where .env lives
        let sourceFile = URL(fileURLWithPath: #filePath)
        let projectRoot = sourceFile
            .deletingLastPathComponent() // Dalle2/
            .deletingLastPathComponent() // Dalle2/
            .deletingLastPathComponent() // project root
        let envURL = projectRoot.appendingPathComponent(".env")
        guard let contents = try? String(contentsOf: envURL, encoding: .utf8) else {
            print("[DotEnv] .env file not found at \(envURL.path)")
            return [:]
        }
        return parse(contents)
    }()

    static func get(_ key: String) -> String? {
        values[key]
    }

    private static func parse(_ contents: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = String(parts[0]).trimmingCharacters(in: .whitespaces)
            var value = String(parts[1]).trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            result[key] = value
        }
        return result
    }
}
