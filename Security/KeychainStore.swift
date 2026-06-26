import Foundation
import Security

enum LLMProvider: String, Codable, CaseIterable {
    case messages = "Anthropic-Compatible"
    case chatCompletions = "OpenAI-Compatible"
    case generateContent = "Gemini-Compatible"

    var displayName: String {
        switch self {
        case .messages:
            return "Messages Compatible"
        case .chatCompletions:
            return "OpenAI Compatible"
        case .generateContent:
            return "Generate Content Compatible"
        }
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        
        switch value {
        case "Anthropic", "Anthropic-Compatible":
            self = .messages
        case "OpenAI", "OpenAI-Compatible":
            self = .chatCompletions
        case "Google", "Gemini", "Gemini-Compatible":
            self = .generateContent
        default:
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unknown LLM provider: \(value)"
            )
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    
    /// Host / 可选前缀部分。用户在设置里只需要填这个。
    var defaultBaseURLPrefix: String {
        switch self {
        case .messages:
            return "https://your-messages-endpoint.example.com"
        case .chatCompletions:
            return "https://your-chat-completions-endpoint.example.com"
        case .generateContent:
            return "https://your-generate-content-endpoint.example.com"
        }
    }
    
    /// 按 provider 固定的 API 路径后缀，自动拼到 prefix 后面。
    var apiPathSuffix: String {
        switch self {
        case .messages:
            return "/v1/messages"
        case .chatCompletions:
            return "/v1/chat/completions"
        case .generateContent:
            return "/v1beta/models"
        }
    }
    
    /// 完整默认 URL，保留给 adapter / 其他保持向后兼容的地方使用。
    var defaultBaseURL: String {
        defaultBaseURLPrefix + apiPathSuffix
    }
    
    /// 把用户输入的 prefix 拼成完整的请求 URL。
    /// - 去掉结尾多余的 `/`
    /// - 如果用户直接粘了完整 URL（已经以 `apiPathSuffix` 结尾），则原样返回，避免重复拼接
    /// - 空输入则使用默认 prefix
    func assembledBaseURL(fromPrefix prefix: String) -> String {
        var normalized = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        while normalized.hasSuffix("/") {
            normalized.removeLast()
        }
        if normalized.isEmpty {
            normalized = defaultBaseURLPrefix
        }
        if normalized.hasSuffix(apiPathSuffix) {
            return normalized
        }
        return normalized + apiPathSuffix
    }
    
    /// 反向操作：从完整 URL 里剥出 prefix，便于回填输入框。
    func extractPrefix(fromFullBaseURL fullURL: String) -> String {
        let trimmed = fullURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix(apiPathSuffix) {
            return String(trimmed.dropLast(apiPathSuffix.count))
        }
        return trimmed
    }
    
    var defaultModel: String {
        switch self {
        case .messages:
            return "your-messages-model"
        case .chatCompletions:
            return "your-chat-completions-model"
        case .generateContent:
            return "your-generate-content-model"
        }
    }
}

struct APIConfiguration: Codable {
    var provider: LLMProvider
    var apiKey: String
    var baseURL: String
    var modelName: String
    var apiVersion: String?
}

class KeychainStore {
    static let shared = KeychainStore()
    
    private let service = "com.paperflip.api"
    private let account = "llm_config"
    
    private init() {}
    
    func saveConfiguration(_ config: APIConfiguration) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unhandledError(status: status)
        }
    }
    
    func loadConfiguration() throws -> APIConfiguration? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status != errSecItemNotFound else {
            return nil
        }
        
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unhandledError(status: status)
        }
        
        let decoder = JSONDecoder()
        return try decoder.decode(APIConfiguration.self, from: data)
    }
    
    func deleteConfiguration() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledError(status: status)
        }
    }
}

enum KeychainError: Error {
    case unhandledError(status: OSStatus)
    case noData
}
