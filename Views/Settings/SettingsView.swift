import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("hasConfiguredAPI") private var hasConfiguredAPI = false
    @State private var selectedProvider: LLMProvider = .anthropic
    @State private var apiKey: String = ""
    @State private var baseURL: String = ""
    @State private var modelName: String = ""
    @State private var showTestResult = false
    @State private var testResultMessage = ""
    @State private var isTestingConnection = false
    @State private var showCategorySelection = false
    
    let onDismiss: (() -> Void)?
    
    init(onDismiss: (() -> Void)? = nil) {
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    
                    // Paper Categories Section
                    VStack(alignment: .leading, spacing: 16) {
                        Text("论文范围")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                            .padding(.horizontal, 24)
                        
                        Button(action: {
                            showCategorySelection = true
                        }) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("选择感兴趣的领域")
                                        .font(AppTheme.Typography.headline)
                                        .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                                    
                                    Text("调整你想看到的论文类型")
                                        .font(.system(size: 14))
                                        .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                                }
                                
                                Spacer()
                                
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme))
                            }
                            .padding(16)
                            .background(AppTheme.Colors.surfacePrimary(for: colorScheme))
                            .clipShape(.rect(cornerRadius: AppTheme.CornerRadius.card))
                            .overlay(
                                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card)
                                    .stroke(AppTheme.Colors.border(for: colorScheme), lineWidth: 1)
                            )
                        }
                        .buttonStyle(PlainButtonStyle())
                        .padding(.horizontal, 24)
                    }
                    
                    Divider()
                        .padding(.horizontal, 24)
                    
                    VStack(alignment: .leading, spacing: 24) {
                        Text("API 配置")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                        
                        // Provider selection
                        VStack(alignment: .leading, spacing: 12) {
                            Text("API 提供商")
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                            
                            Picker("Provider", selection: $selectedProvider) {
                                ForEach(LLMProvider.allCases, id: \.self) { provider in
                                    Text(provider.rawValue)
                                        .tag(provider)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onAppear {
                                configureSegmentedControl()
                            }
                            .onChange(of: selectedProvider) { _, newValue in
                                updateDefaults(for: newValue)
                            }
                        }
                        
                        // API Key
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key")
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                            
                            SecureField("输入你的 API Key", text: $apiKey, prompt: Text("输入你的 API Key").foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme)))
                                .textFieldStyle(CustomTextFieldStyle())
                            
                            Text("密钥仅保存在本地设备，不会上传到任何服务器")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                        }
                        
                        // Base URL
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Base URL")
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                            
                            TextField("API 端点地址", text: $baseURL, prompt: Text("API 端点地址").foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme)))
                                .textFieldStyle(CustomTextFieldStyle())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .keyboardType(.URL)
                            
                            Text("默认值：\(selectedProvider.defaultBaseURL)")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                        }
                        
                        // Model Name
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Model Name")
                                .font(AppTheme.Typography.headline)
                                .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                            
                            TextField("模型名称", text: $modelName, prompt: Text("模型名称").foregroundStyle(AppTheme.Colors.textTertiary(for: colorScheme)))
                                .textFieldStyle(CustomTextFieldStyle())
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                            
                            Text("默认值：\(selectedProvider.defaultModel)")
                                .font(AppTheme.Typography.caption)
                                .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Test connection button
                    VStack(spacing: 12) {
                        Button(action: testConnection) {
                            HStack {
                                if isTestingConnection {
                                    ProgressView()
                                        .tint(AppTheme.Colors.textInverted(for: colorScheme))
                                } else {
                                    Text("测试连接")
                                        .font(AppTheme.Typography.headline)
                                }
                            }
                            .foregroundStyle(apiKey.isEmpty ? AppTheme.Colors.textPrimary(for: colorScheme) : AppTheme.Colors.textInverted(for: colorScheme))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(apiKey.isEmpty ? AppTheme.Colors.surfaceSecondary(for: colorScheme) : AppTheme.Colors.textPrimary(for: colorScheme))
                            .clipShape(.capsule)
                            .modifier(GlassEffectModifier())
                        }
                        .disabled(apiKey.isEmpty || isTestingConnection)
                        
                        if showTestResult {
                            Text(testResultMessage)
                                .font(AppTheme.Typography.body)
                                .foregroundStyle(testResultMessage.contains("成功") ? AppTheme.Colors.accentGreen(for: colorScheme) : AppTheme.Colors.destructive(for: colorScheme))
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Save button
                    Button(action: saveConfiguration) {
                        Text("保存配置")
                            .font(AppTheme.Typography.headline)
                            .foregroundStyle(apiKey.isEmpty ? AppTheme.Colors.textPrimary(for: colorScheme) : AppTheme.Colors.textInverted(for: colorScheme))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(apiKey.isEmpty ? AppTheme.Colors.surfaceSecondary(for: colorScheme) : AppTheme.Colors.textPrimary(for: colorScheme))
                            .clipShape(.capsule)
                            .modifier(GlassEffectModifier())
                    }
                    .disabled(apiKey.isEmpty)
                    .padding(.horizontal, 24)
                    
                    // Disclaimer
                    VStack(spacing: 8) {
                        Text("关于费用")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                        
                        Text("使用 AI 摘要功能会消耗你的 API 配额。每篇论文摘要约消耗 1000-2000 tokens。费用由你与 API 提供商直接结算，PaperTok 不收取任何额外费用。")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.vertical, 20)
                    
                    // Privacy notice
                    VStack(spacing: 8) {
                        Text("隐私与安全")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
                        
                        Text("你的 API 密钥仅保存在本地设备的 Keychain 中，不会上传到任何服务器。PaperTok 不收集、存储或传输你的密钥信息。")
                            .font(AppTheme.Typography.caption)
                            .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .padding(.vertical, 20)
                }
                .padding(.bottom, 40)
            }
            .background(AppTheme.Colors.background(for: colorScheme))
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                        onDismiss?()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                    }
                }
            }
            .task {
                loadExistingConfiguration()
            }
            .sheet(isPresented: $showCategorySelection) {
                CategorySelectionView(modelContext: modelContext)
            }
        }
    }
    
    private func configureSegmentedControl() {
        // Configure segmented control appearance - using system default colors
        UISegmentedControl.appearance().selectedSegmentTintColor = nil // Use system default
        UISegmentedControl.appearance().setTitleTextAttributes([
            .foregroundColor: UIColor.label,
            .font: UIFont.systemFont(ofSize: 15, weight: .medium)
        ], for: .selected)
        UISegmentedControl.appearance().setTitleTextAttributes([
            .foregroundColor: UIColor.secondaryLabel,
            .font: UIFont.systemFont(ofSize: 15, weight: .regular)
        ], for: .normal)
    }
    
    private func updateDefaults(for provider: LLMProvider) {
        if baseURL.isEmpty || baseURL == LLMProvider.allCases.first(where: { $0 != provider })?.defaultBaseURL {
            baseURL = provider.defaultBaseURL
        }
        if modelName.isEmpty || modelName == LLMProvider.allCases.first(where: { $0 != provider })?.defaultModel {
            modelName = provider.defaultModel
        }
    }
    
    private func loadExistingConfiguration() {
        if let config = try? KeychainStore.shared.loadConfiguration() {
            selectedProvider = config.provider
            apiKey = config.apiKey
            baseURL = config.baseURL
            modelName = config.modelName
        } else {
            updateDefaults(for: selectedProvider)
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        showTestResult = false
        
        print("[Settings] Starting connection test...")
        
        Task {
            do {
                let config = APIConfiguration(
                    provider: selectedProvider,
                    apiKey: apiKey,
                    baseURL: baseURL.isEmpty ? selectedProvider.defaultBaseURL : baseURL,
                    modelName: modelName.isEmpty ? selectedProvider.defaultModel : modelName,
                    apiVersion: nil
                )
                
                print("[Settings] Config - Provider: \(config.provider.rawValue), BaseURL: \(config.baseURL), Model: \(config.modelName)")
                
                let adapter = LLMProviderAdapter(config: config)
                let request = LLMRequest(
                    systemPrompt: "You are a helpful assistant.",
                    userPrompt: "Say 'Hello' in Chinese.",
                    temperature: 0.3,
                    maxTokens: 50
                )
                
                print("[Settings] Sending test request...")
                
                // Add timeout protection (20 seconds total)
                let response = try await withTimeout(seconds: 20) {
                    try await adapter.generateCompletion(request: request)
                }
                
                print("[Settings] Received response: \(response.content.prefix(50))...")
                
                print("[Settings] Connection test successful!")
                
                await MainActor.run {
                    testResultMessage = "✓ 连接成功"
                    showTestResult = true
                    isTestingConnection = false
                }
            } catch is CancellationError {
                print("[Settings] Connection test cancelled")
                await MainActor.run {
                    testResultMessage = "✗ 请求已取消"
                    showTestResult = true
                    isTestingConnection = false
                }
            } catch LLMError.timeout {
                print("[Settings] Connection test timeout")
                await MainActor.run {
                    testResultMessage = "✗ 请求超时（20秒）\n可能原因：\n• 网络连接慢或不稳定\n• Base URL 无法访问\n• API Key 无效导致服务器无响应"
                    showTestResult = true
                    isTestingConnection = false
                }
            } catch LLMError.authenticationFailed {
                print("[Settings] Authentication failed")
                await MainActor.run {
                    testResultMessage = "✗ 认证失败，请检查 API Key"
                    showTestResult = true
                    isTestingConnection = false
                }
            } catch LLMError.rateLimitExceeded {
                print("[Settings] Rate limit exceeded")
                await MainActor.run {
                    testResultMessage = "✗ 请求频率超限，请稍后再试"
                    showTestResult = true
                    isTestingConnection = false
                }
            } catch LLMError.insufficientBalance {
                print("[Settings] Insufficient balance")
                await MainActor.run {
                    testResultMessage = "✗ 账户余额不足"
                    showTestResult = true
                    isTestingConnection = false
                }
            } catch LLMError.networkError(let underlyingError) {
                print("[Settings] Network error: \(underlyingError)")
                if let urlError = underlyingError as? URLError {
                    await MainActor.run {
                        let message: String
                        switch urlError.code {
                        case .notConnectedToInternet:
                            message = "✗ 无网络连接"
                        case .timedOut:
                            message = "✗ 请求超时（15秒）\n可能原因：\n• 网络连接慢\n• Base URL 无法访问\n• 需要使用代理"
                        case .cannotFindHost, .cannotConnectToHost:
                            message = "✗ 无法连接到服务器\n请检查：\n• Base URL 是否正确\n• 网络连接是否正常\n• 是否需要代理"
                        case .badURL:
                            message = "✗ URL 格式错误\n请检查 Base URL 格式"
                        default:
                            message = "✗ 网络错误：\(urlError.localizedDescription)"
                        }
                        testResultMessage = message
                        showTestResult = true
                        isTestingConnection = false
                    }
                } else {
                    await MainActor.run {
                        testResultMessage = "✗ 网络错误：\(underlyingError.localizedDescription)"
                        showTestResult = true
                        isTestingConnection = false
                    }
                }
            } catch let error as URLError {
                print("[Settings] URL error: \(error)")
                await MainActor.run {
                    let message: String
                    switch error.code {
                    case .notConnectedToInternet:
                        message = "✗ 无网络连接"
                    case .timedOut:
                        message = "✗ 请求超时（15秒）\n可能原因：\n• 网络连接慢\n• Base URL 无法访问\n• 需要使用代理"
                    case .cannotFindHost, .cannotConnectToHost:
                        message = "✗ 无法连接到服务器\n请检查：\n• Base URL 是否正确\n• 网络连接是否正常\n• 是否需要代理"
                    case .badURL:
                        message = "✗ URL 格式错误\n请检查 Base URL 格式"
                    default:
                        message = "✗ 网络错误：\(error.localizedDescription)"
                    }
                    testResultMessage = message
                    showTestResult = true
                    isTestingConnection = false
                }
            } catch {
                print("[Settings] Connection test failed with error: \(error)")
                await MainActor.run {
                    testResultMessage = "✗ 连接失败：\(error.localizedDescription)"
                    showTestResult = true
                    isTestingConnection = false
                }
            }
        }
    }
    
    // Helper function for timeout
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw LLMError.timeout
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    private func saveConfiguration() {
        let config = APIConfiguration(
            provider: selectedProvider,
            apiKey: apiKey,
            baseURL: baseURL.isEmpty ? selectedProvider.defaultBaseURL : baseURL,
            modelName: modelName.isEmpty ? selectedProvider.defaultModel : modelName,
            apiVersion: nil
        )
        
        do {
            try KeychainStore.shared.saveConfiguration(config)
            hasConfiguredAPI = true
            dismiss()
            onDismiss?()
        } catch {
            testResultMessage = "保存失败：\(error.localizedDescription)"
            showTestResult = true
        }
    }
}

struct CustomTextFieldStyle: TextFieldStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .foregroundStyle(AppTheme.Colors.textPrimary(for: colorScheme))
            .tint(AppTheme.Colors.textPrimary(for: colorScheme))
            .padding(16)
            .background(AppTheme.Colors.surfaceSecondary(for: colorScheme))
            .clipShape(.rect(cornerRadius: AppTheme.CornerRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.CornerRadius.card)
                    .stroke(AppTheme.Colors.border(for: colorScheme), lineWidth: 1)
            )
    }
}

struct CategorySelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    let modelContext: ModelContext
    
    @State private var selectedCategories: Set<String> = []
    
    let availableCategories = [
        ("cs.AI", "人工智能", "Artificial Intelligence"),
        ("cs.CL", "计算语言学", "Computation and Language"),
        ("cs.CV", "计算机视觉", "Computer Vision"),
        ("cs.LG", "机器学习", "Machine Learning"),
        ("cs.NE", "神经网络", "Neural and Evolutionary Computing"),
        ("stat.ML", "统计机器学习", "Machine Learning (Statistics)"),
        ("cs.CR", "密码学", "Cryptography and Security"),
        ("cs.DB", "数据库", "Databases"),
        ("cs.DC", "分布式计算", "Distributed Computing"),
        ("cs.IR", "信息检索", "Information Retrieval")
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Header
                VStack(alignment: .leading, spacing: 16) {
                    Text("选择你感兴趣的领域")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(AppTheme.Colors.textPrimary(for: colorScheme))
                        .padding(.horizontal, 24)
                    
                    Text("至少选择一个领域")
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.Colors.textSecondary(for: colorScheme))
                        .padding(.horizontal, 24)
                }
                .padding(.top, 20)
                .padding(.bottom, 16)
                
                // Category list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(availableCategories, id: \.0) { category in
                            CategoryCard(
                                code: category.0,
                                chinese: category.1,
                                english: category.2,
                                isSelected: selectedCategories.contains(category.0)
                            ) {
                                toggleCategory(category.0)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 100)
                }
                
                // Save button
                VStack(spacing: 0) {
                    Divider()
                    
                    Button(action: savePreferences) {
                        Text("保存")
                            .font(AppTheme.Typography.headline)
                            .foregroundColor(selectedCategories.isEmpty ? AppTheme.Colors.textPrimary(for: colorScheme) : AppTheme.Colors.textInverted(for: colorScheme))
                            .frame(maxWidth: .infinity)
                            .frame(height: 54)
                            .background(selectedCategories.isEmpty ? AppTheme.Colors.surfaceSecondary(for: colorScheme) : AppTheme.Colors.textPrimary(for: colorScheme))
                            .clipShape(.capsule)
                            .modifier(GlassEffectModifier())
                    }
                    .disabled(selectedCategories.isEmpty)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
                .background(AppTheme.Colors.background(for: colorScheme))
            }
            .background(AppTheme.Colors.background(for: colorScheme))
            .navigationTitle("论文范围")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppTheme.Colors.textSecondary(for: colorScheme))
                    }
                }
            }
            .task {
                loadCurrentPreferences()
            }
        }
    }
    
    private func loadCurrentPreferences() {
        let descriptor = FetchDescriptor<UserPreference>()
        if let preference = try? modelContext.fetch(descriptor).first {
            selectedCategories = Set(preference.selectedCategories)
        }
    }
    
    private func toggleCategory(_ code: String) {
        if selectedCategories.contains(code) {
            selectedCategories.remove(code)
        } else {
            selectedCategories.insert(code)
        }
    }
    
    private func savePreferences() {
        let descriptor = FetchDescriptor<UserPreference>()
        
        if let preference = try? modelContext.fetch(descriptor).first {
            preference.selectedCategories = Array(selectedCategories)
            preference.updatedAt = Date()
        } else {
            let preference = UserPreference(selectedCategories: Array(selectedCategories))
            modelContext.insert(preference)
        }
        
        try? modelContext.save()
        dismiss()
    }
}
