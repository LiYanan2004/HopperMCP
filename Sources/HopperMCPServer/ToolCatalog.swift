import Foundation

struct ToolCatalog {
    let tools: [[String: Any]]
    private let definitions: [String: [String: Any]]
    private let documentation: [String: Any]

    init() throws {
        tools = try JSONSerialization.jsonObject(with: EmbeddedCatalog.tools) as! [[String: Any]]
        definitions = Dictionary(uniqueKeysWithValues: tools.map { ($0["name"] as! String, $0) })
        documentation = try JSONSerialization.jsonObject(with: EmbeddedCatalog.documentation) as! [String: Any]
    }

    func validate(name: String, arguments: [String: Any]) throws {
        guard let definition = definitions[name] else { throw RPCFailure(code: -32602, message: "Unknown tool: \(name)") }
        let schema = definition["inputSchema"] as? [String: Any] ?? [:]
        for required in schema["required"] as? [String] ?? [] where arguments[required] == nil {
            throw RPCFailure(code: -32602, message: "Missing argument: \(required)")
        }
        let properties = schema["properties"] as? [String: [String: Any]] ?? [:]
        for (key, value) in arguments {
            guard let property = properties[key] else { throw RPCFailure(code: -32602, message: "Unknown argument: \(key)") }
            guard let type = property["type"] as? String else { continue }
            let valid: Bool
            switch type {
            case "string": valid = value is String
            case "object": valid = value is [String: Any]
            case "array": valid = value is [Any]
            case "integer": valid = (value as? NSNumber).map { !isBoolean($0) && $0.doubleValue.isFinite && $0.doubleValue.rounded() == $0.doubleValue } ?? false
            case "number": valid = (value as? NSNumber).map { !isBoolean($0) && $0.doubleValue.isFinite } ?? false
            case "boolean": valid = (value as? NSNumber).map(isBoolean) ?? false
            default: valid = true
            }
            if !valid { throw RPCFailure(code: -32602, message: "\(key) must be \(type)") }
        }
    }

    func documentation(arguments: [String: Any]) throws -> Any {
        let category = arguments["category"] as? String ?? "native"
        guard let entries = documentation[category] as? [[String: Any]] else {
            throw BridgeFailure.operation("category must be native, python, or constants")
        }
        let pattern = arguments["pattern"] as? String ?? ".*"
        let expression = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
        let filtered = try entries.filter { entry in
            let text = String(data: try JSONSerialization.data(withJSONObject: entry), encoding: .utf8)!
            return expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
        }
        let offset = (arguments["offset"] as? NSNumber)?.intValue ?? 0
        let limit = (arguments["limit"] as? NSNumber)?.intValue ?? 50
        guard offset >= 0, (1...500).contains(limit) else { throw BridgeFailure.operation("Use a nonnegative offset and a limit from 1 to 500") }
        let page = Array(filtered.dropFirst(offset).prefix(limit))
        return ["category": category, "total": filtered.count, "offset": offset, "entries": page]
    }

    private func isBoolean(_ number: NSNumber) -> Bool {
        CFGetTypeID(number) == CFBooleanGetTypeID()
    }
}
