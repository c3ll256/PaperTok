import Foundation

enum LLMError: Error {
    case invalidConfiguration
    case networkError(Error)
    case apiError(statusCode: Int, message: String)
    case invalidResponse
    case rateLimitExceeded
    case insufficientBalance
    case authenticationFailed
    case timeout
    case cancelled
}

extension LLMError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "配置无效"
        case .networkError(let error):
            return "网络错误: \(error.localizedDescription)"
        case .apiError(let statusCode, let message):
            return "API 错误 (\(statusCode)): \(message)"
        case .invalidResponse:
            return "无效的响应格式"
        case .rateLimitExceeded:
            return "请求频率超限"
        case .insufficientBalance:
            return "账户余额不足"
        case .authenticationFailed:
            return "认证失败"
        case .timeout:
            return "请求超时"
        case .cancelled:
            return "请求已取消"
        }
    }
}

struct LLMRequest {
    let systemPrompt: String
    let userPrompt: String
    let temperature: Double
    let maxTokens: Int
}

struct LLMResponse {
    let content: String
    let model: String
    let usage: TokenUsage?
}

struct TokenUsage {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int
}

class LLMProviderAdapter {
    private let config: APIConfiguration
    private let session: URLSession
    
    init(config: APIConfiguration) {
        self.config = config
        
        // Configure URLSession with timeout
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 15.0 // 15 seconds timeout
        configuration.timeoutIntervalForResource = 30.0
        self.session = URLSession(configuration: configuration)
    }
    
    func generateCompletion(request: LLMRequest) async throws -> LLMResponse {
        switch config.provider {
        case .anthropic:
            return try await callAnthropic(request: request)
        case .openai:
            return try await callOpenAI(request: request)
        case .google:
            return try await callGoogle(request: request)
        }
    }
    
    // MARK: - Anthropic
    
    private func callAnthropic(request: LLMRequest) async throws -> LLMResponse {
        guard let url = URL(string: config.baseURL) else {
            throw LLMError.invalidConfiguration
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue(config.apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        
        let body: [String: Any] = [
            "model": config.modelName,
            "max_tokens": request.maxTokens,
            "temperature": request.temperature,
            "system": request.systemPrompt,
            "messages": [
                ["role": "user", "content": request.userPrompt]
            ]
        ]
        
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("[LLM] Calling Anthropic API: \(config.baseURL)")
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            print("[LLM] Network error: \(error)")
            throw LLMError.networkError(error)
        } catch {
            print("[LLM] Unexpected error: \(error)")
            throw LLMError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        try handleHTTPError(statusCode: httpResponse.statusCode, data: data)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let content = json?["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw LLMError.invalidResponse
        }
        
        let usage = (json?["usage"] as? [String: Any]).map { usageDict in
            TokenUsage(
                promptTokens: usageDict["input_tokens"] as? Int ?? 0,
                completionTokens: usageDict["output_tokens"] as? Int ?? 0,
                totalTokens: (usageDict["input_tokens"] as? Int ?? 0) + (usageDict["output_tokens"] as? Int ?? 0)
            )
        }
        
        return LLMResponse(content: text, model: config.modelName, usage: usage)
    }
    
    // MARK: - OpenAI
    
    private func callOpenAI(request: LLMRequest) async throws -> LLMResponse {
        guard let url = URL(string: config.baseURL) else {
            throw LLMError.invalidConfiguration
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
        
        let body: [String: Any] = [
            "model": config.modelName,
            "temperature": request.temperature,
            "max_tokens": request.maxTokens,
            "messages": [
                ["role": "system", "content": request.systemPrompt],
                ["role": "user", "content": request.userPrompt]
            ]
        ]
        
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("[LLM] Calling OpenAI API: \(config.baseURL)")
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            print("[LLM] Network error: \(error)")
            throw LLMError.networkError(error)
        } catch {
            print("[LLM] Unexpected error: \(error)")
            throw LLMError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        try handleHTTPError(statusCode: httpResponse.statusCode, data: data)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let choices = json?["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw LLMError.invalidResponse
        }
        
        let usage = (json?["usage"] as? [String: Any]).map { usageDict in
            TokenUsage(
                promptTokens: usageDict["prompt_tokens"] as? Int ?? 0,
                completionTokens: usageDict["completion_tokens"] as? Int ?? 0,
                totalTokens: usageDict["total_tokens"] as? Int ?? 0
            )
        }
        
        return LLMResponse(content: content, model: config.modelName, usage: usage)
    }
    
    // MARK: - Google
    
    private func callGoogle(request: LLMRequest) async throws -> LLMResponse {
        let urlString = "\(config.baseURL)/\(config.modelName):generateContent?key=\(config.apiKey)"
        guard let url = URL(string: urlString) else {
            throw LLMError.invalidConfiguration
        }
        
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "contents": [
                [
                    "parts": [
                        ["text": "\(request.systemPrompt)\n\n\(request.userPrompt)"]
                    ]
                ]
            ],
            "generationConfig": [
                "temperature": request.temperature,
                "maxOutputTokens": request.maxTokens
            ]
        ]
        
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        print("[LLM] Calling Google API: \(urlString)")
        
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch let error as URLError {
            print("[LLM] Network error: \(error)")
            throw LLMError.networkError(error)
        } catch {
            print("[LLM] Unexpected error: \(error)")
            throw LLMError.networkError(error)
        }
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.invalidResponse
        }
        
        try handleHTTPError(statusCode: httpResponse.statusCode, data: data)
        
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let candidates = json?["candidates"] as? [[String: Any]],
              let content = candidates.first?["content"] as? [String: Any],
              let parts = content["parts"] as? [[String: Any]],
              let text = parts.first?["text"] as? String else {
            throw LLMError.invalidResponse
        }
        
        let usage = (json?["usageMetadata"] as? [String: Any]).map { usageDict in
            TokenUsage(
                promptTokens: usageDict["promptTokenCount"] as? Int ?? 0,
                completionTokens: usageDict["candidatesTokenCount"] as? Int ?? 0,
                totalTokens: usageDict["totalTokenCount"] as? Int ?? 0
            )
        }
        
        return LLMResponse(content: text, model: config.modelName, usage: usage)
    }
    
    // MARK: - Error Handling
    
    private func handleHTTPError(statusCode: Int, data: Data) throws {
        guard (200...299).contains(statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            
            switch statusCode {
            case 401:
                throw LLMError.authenticationFailed
            case 429:
                throw LLMError.rateLimitExceeded
            case 402, 403 where errorMessage.contains("balance") || errorMessage.contains("quota"):
                throw LLMError.insufficientBalance
            default:
                throw LLMError.apiError(statusCode: statusCode, message: errorMessage)
            }
        }
    }
}
