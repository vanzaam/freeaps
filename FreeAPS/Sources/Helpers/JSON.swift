import Foundation

@dynamicMemberLookup protocol JSON: Codable {
    var rawJSON: String { get }
    init?(from: String)
}

extension JSON {
    var rawJSON: RawJSON {
        String(data: try! JSONCoding.encoder.encode(self), encoding: .utf8)!
    }

    init?(from: String) {
        // Handle empty or null strings
        guard !from.isEmpty && from != "null" && from != "undefined" else {
            debug(.service, "JSON init from empty/null/undefined string")
            return nil
        }
        
        // Trim whitespace and check for valid JSON structure
        let trimmed = from.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            debug(.service, "JSON init from whitespace-only string")
            return nil
        }
        
        // Check for common malformed JSON patterns
        if trimmed.hasPrefix("{") && !trimmed.hasSuffix("}") {
            debug(.service, "JSON init from incomplete object: \(trimmed.prefix(100))...")
            return nil
        }
        
        if trimmed.hasPrefix("[") && !trimmed.hasSuffix("]") {
            debug(.service, "JSON init from incomplete array: \(trimmed.prefix(100))...")
            return nil
        }
        
        guard let data = trimmed.data(using: .utf8) else {
            debug(.service, "JSON init failed to convert string to data")
            return nil
        }

        do {
            let object = try JSONCoding.decoder.decode(Self.self, from: data)
            self = object
        } catch {
            // Log the actual JSON content for debugging (truncated)
            let preview = trimmed.count > 200 ? String(trimmed.prefix(200)) + "..." : trimmed
            warning(.service, "Cannot decode JSON (preview: \(preview))", error: error)
            return nil
        }
    }

    var dictionaryRepresentation: [String: Any]? {
        guard let data = rawJSON.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
        else {
            return nil
        }
        return dict
    }

    subscript(dynamicMember string: String) -> Any? {
        dictionaryRepresentation?[string]
    }
}

extension String: JSON {
    var rawJSON: String { self }
    init?(from: String) { self = from }
}

extension Double: JSON {}

extension Int: JSON {}

extension Bool: JSON {}

extension Decimal: JSON {}

extension Date: JSON {
    init?(from: String) {
        let dateFormatter = Formatter.iso8601withFractionalSeconds
        let string = from.replacingOccurrences(of: "\"", with: "")
        if let date = dateFormatter.date(from: string) {
            self = date
        } else {
            return nil
        }
    }
}

typealias RawJSON = String

extension RawJSON {
    static let null = "null"
    static let empty = ""
}

extension Array: JSON where Element: JSON {}
extension Dictionary: JSON where Key: JSON, Value: JSON {}

extension Dictionary where Key == String {
    var rawJSON: RawJSON? {
        guard let data = try? JSONSerialization.data(withJSONObject: self, options: .prettyPrinted) else { return nil }
        return RawJSON(data: data, encoding: .utf8)
    }
}

enum JSONCoding {
    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .customISO8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .customISO8601
        return decoder
    }
}
