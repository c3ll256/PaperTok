import Foundation
import Security

enum LLMProvider: String, Codable, CaseIterable {
    case anthropic = "Anthropic"
    case openai = "OpenAI"
    case google = "Google"
    
    var defaultBaseURL: String {
        switch self {
        case .anthropic:
            return "https://api.anthropic.com/v1/messages"
        case .openai:
            return "https://api.openai.com/v1/chat/completions"
        case .google:
            return "https://generativelanguage.googleapis.com/v1beta/models"
        }
    }
    
    var defaultModel: String {
        switch self {
        case .anthropic:
            return "claude-haiku-4-5"
        case .openai:
            return "gpt-5.2"
        case .google:
            return "gemini-3-flash-preview"
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
    
    private let service = "com.papertok.api"
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
