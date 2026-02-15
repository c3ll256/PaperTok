import Foundation
import SwiftData

class SummaryService {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func regenerateSummary(for paper: Paper) async throws -> PaperSummary {
        // Delete existing summary
        let arxivId = paper.arxivId
        let summaryDescriptor = FetchDescriptor<PaperSummary>(
            predicate: #Predicate { $0.arxivId == arxivId }
        )
        if let existingSummary = try? modelContext.fetch(summaryDescriptor).first {
            modelContext.delete(existingSummary)
        }
        
        // Delete existing terms
        let termsDescriptor = FetchDescriptor<TermGlossaryItem>(
            predicate: #Predicate { $0.arxivId == arxivId }
        )
        if let existingTerms = try? modelContext.fetch(termsDescriptor) {
            for term in existingTerms {
                modelContext.delete(term)
            }
        }
        
        try modelContext.save()
        
        // Generate fresh summary
        return try await generateSummary(for: paper)
    }
    
    /// Quick title-only translation. Creates or updates PaperSummary with just the Chinese title
    /// so the UI can show it immediately while the full analysis runs.
    func translateTitle(for paper: Paper) async throws -> PaperSummary {
        let arxivId = paper.arxivId
        let descriptor = FetchDescriptor<PaperSummary>(
            predicate: #Predicate { $0.arxivId == arxivId }
        )
        
        // If summary already has a Chinese title, return it
        if let existing = try? modelContext.fetch(descriptor).first, existing.titleChinese != nil {
            return existing
        }
        
        guard let config = try KeychainStore.shared.loadConfiguration() else {
            throw LLMError.invalidConfiguration
        }
        
        let adapter = LLMProviderAdapter(config: config)
        
        let request = LLMRequest(
            systemPrompt: "你是一个学术论文标题翻译助手。请将英文论文标题翻译成准确、通顺的中文。只输出翻译结果，不要任何额外内容。",
            userPrompt: paper.title,
            temperature: 0.1,
            maxTokens: 200
        )
        
        let response = try await adapter.generateCompletion(request: request)
        let chineseTitle = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Create or update summary with just the title
        if let existing = try? modelContext.fetch(descriptor).first {
            existing.titleChinese = chineseTitle
            existing.updatedAt = Date()
            try modelContext.save()
            return existing
        } else {
            let summary = PaperSummary(
                arxivId: paper.arxivId,
                modelName: config.modelName,
                summaryText: ""
            )
            summary.titleChinese = chineseTitle
            modelContext.insert(summary)
            try modelContext.save()
            return summary
        }
    }
    
    func generateSummary(for paper: Paper) async throws -> PaperSummary {
        // Check if a full summary already exists (has problem field filled)
        let arxivId = paper.arxivId
        let descriptor = FetchDescriptor<PaperSummary>(
            predicate: #Predicate { $0.arxivId == arxivId }
        )
        
        if let existingSummary = try modelContext.fetch(descriptor).first,
           existingSummary.problem != nil {
            // Full summary already generated
            return existingSummary
        }
        
        // Load API configuration
        guard let config = try KeychainStore.shared.loadConfiguration() else {
            throw LLMError.invalidConfiguration
        }
        
        let adapter = LLMProviderAdapter(config: config)
        
        let systemPrompt = """
        我是一名拥有初中生智力的博士生，请你用中文输出，尽量通俗易懂、短句表达。
        专业名词请在中文后面加括号英文（例如：注意力机制（Attention Mechanism））。
        请严格按照以下结构输出：
        
        0) 标题中文翻译（Title Chinese）：将论文标题翻译成中文，要求准确、通顺
        1) 发布机构（Institutions）：根据作者信息中提取发布机构/大学名称，多个机构用顿号分隔。如果无法确定，直接留空不写
        2) 这篇论文在解决什么问题（Problem）
        3) 它用了什么核心方法（Method）
        4) 最关键的实验结果和结论是什么（Result & Conclusion）
        5) 一句话总结（One-liner）
        6) Terms to Know（3-6 个核心术语）：
           每个术语按以下格式输出：
           - English Term Name（英文术语原文）
           - 中文翻译
           - 一句话解释（不超过 30 字，说明这个术语的通用含义）
           - 在本文里的具体含义（不超过 40 字，说明在这篇论文中的特定用法或意义）
        
        额外要求：
        - 不要使用 Markdown 格式（不要用 **加粗**、# 标题、- 列表等），使用纯文本
        - 不要使用营销语气，不要夸张
        - 数字结果尽量保留原文量级或指标名
        - 术语要选择论文中最核心、最重要的概念
        """
        
        let authorsText = paper.authors.joined(separator: ", ")
        let userPrompt = """
        标题：\(paper.title)
        作者：\(authorsText)
        
        摘要：
        \(paper.abstractText)
        """
        
        let request = LLMRequest(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            temperature: 0.3,
            maxTokens: 2000
        )
        
        let response = try await adapter.generateCompletion(request: request)
        
        // Parse structured output
        let sections = parseSummarySections(from: response.content)
        
        // Reuse existing partial summary (title-only) or create new
        let summary: PaperSummary
        if let existing = try? modelContext.fetch(descriptor).first {
            summary = existing
            summary.summaryText = response.content
            summary.modelName = config.modelName
        } else {
            summary = PaperSummary(
                arxivId: paper.arxivId,
                modelName: config.modelName,
                summaryText: response.content
            )
            modelContext.insert(summary)
        }
        
        summary.titleChinese = sections["titleChinese"]
        summary.institutions = sections["institutions"]
        summary.problem = sections["problem"]
        summary.method = sections["method"]
        summary.result = sections["result"]
        summary.oneLiner = sections["oneLiner"]
        summary.updatedAt = Date()
        
        // Save to database
        try modelContext.save()
        
        // Extract and save terminology
        try await extractTerminology(from: response.content, arxivId: paper.arxivId)
        
        return summary
    }
    
    private func parseSummarySections(from text: String) -> [String: String] {
        var sections: [String: String] = [:]
        
        // Simple regex-based parsing
        let lines = text.components(separatedBy: .newlines)
        var currentSection: String?
        var currentContent: [String] = []
        
        /// Helper: extract inline content after the first colon (：or :)
        func extractAfterColon(_ line: String) -> String? {
            if let colonRange = line.range(of: "：") ?? line.range(of: ":") {
                let afterColon = String(line[colonRange.upperBound...]).trimmingCharacters(in: .whitespaces)
                return afterColon.isEmpty ? nil : afterColon
            }
            return nil
        }
        
        /// Helper: flush current section
        func flushSection() {
            if let section = currentSection {
                let value = currentContent.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                if !value.isEmpty {
                    // Strip any residual Markdown bold markers
                    sections[section] = value
                        .replacingOccurrences(of: "**", with: "")
                        .replacingOccurrences(of: "__", with: "")
                }
            }
        }
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.contains("Title Chinese") || trimmed.contains("标题中文翻译") || trimmed.starts(with: "0)") {
                flushSection()
                currentSection = "titleChinese"
                currentContent = []
                if let inline = extractAfterColon(trimmed) { currentContent.append(inline) }
            } else if trimmed.contains("Institutions") || trimmed.contains("发布机构") || trimmed.starts(with: "1)") {
                flushSection()
                currentSection = "institutions"
                currentContent = []
                if let inline = extractAfterColon(trimmed) { currentContent.append(inline) }
            } else if trimmed.contains("Problem") || trimmed.contains("解决什么问题") || trimmed.starts(with: "2)") {
                flushSection()
                currentSection = "problem"
                currentContent = []
            } else if trimmed.contains("Method") || trimmed.contains("核心方法") || trimmed.starts(with: "3)") {
                flushSection()
                currentSection = "method"
                currentContent = []
            } else if trimmed.contains("Result") || trimmed.contains("实验结果") || trimmed.starts(with: "4)") {
                flushSection()
                currentSection = "result"
                currentContent = []
            } else if trimmed.contains("One-liner") || trimmed.contains("一句话总结") || trimmed.starts(with: "5)") {
                flushSection()
                currentSection = "oneLiner"
                currentContent = []
            } else if trimmed.contains("Terms to Know") || trimmed.starts(with: "6)") {
                flushSection()
                break
            } else if !trimmed.isEmpty && currentSection != nil {
                currentContent.append(trimmed)
            }
        }
        
        flushSection()
        
        return sections
    }
    
    private func extractTerminology(from text: String, arxivId: String) async throws {
        // Extract terminology section
        guard let termsSection = text.components(separatedBy: "Terms to Know").last else {
            return
        }
        
        let lines = termsSection.components(separatedBy: .newlines)
        var currentEnglish: String?
        var currentChinese: String?
        var currentExplanation: String?
        var currentContext: String?
        var lineIndex = 0
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            // Skip empty lines
            if trimmed.isEmpty {
                continue
            }
            
            // Remove leading "- " if present
            let content = trimmed.replacingOccurrences(of: "^- ", with: "", options: .regularExpression)
            
            // Detect if this is a new term (contains English characters and possibly parentheses)
            let hasEnglishLetters = content.rangeOfCharacter(from: CharacterSet.letters) != nil
            let startsWithCapital = content.first?.isUppercase ?? false
            
            if startsWithCapital && hasEnglishLetters && currentEnglish == nil {
                // This is the English term (first line of a new term)
                currentEnglish = content.replacingOccurrences(of: "（", with: "").replacingOccurrences(of: "）", with: "")
                lineIndex = 0
            } else if currentEnglish != nil && lineIndex == 0 {
                // This is the Chinese translation (second line)
                currentChinese = content
                lineIndex = 1
            } else if currentChinese != nil && lineIndex == 1 {
                // This is the explanation (third line)
                currentExplanation = content
                lineIndex = 2
            } else if currentExplanation != nil && lineIndex == 2 {
                // This is the context meaning (fourth line)
                currentContext = content
                
                // Save the complete term
                if let english = currentEnglish, let chinese = currentChinese, let explanation = currentExplanation, let context = currentContext {
                    let glossaryItem = TermGlossaryItem(
                        arxivId: arxivId,
                        termChinese: chinese,
                        termEnglish: english,
                        explanation: explanation,
                        contextMeaning: context
                    )
                    modelContext.insert(glossaryItem)
                }
                
                // Reset for next term
                currentEnglish = nil
                currentChinese = nil
                currentExplanation = nil
                currentContext = nil
                lineIndex = 0
            }
        }
        
        // Save last term if incomplete but has minimum data
        if let english = currentEnglish, let chinese = currentChinese, let explanation = currentExplanation {
            let glossaryItem = TermGlossaryItem(
                arxivId: arxivId,
                termChinese: chinese,
                termEnglish: english,
                explanation: explanation,
                contextMeaning: currentContext ?? ""
            )
            modelContext.insert(glossaryItem)
        }
        
        try modelContext.save()
    }
}
