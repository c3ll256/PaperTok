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
    
    func generateSummary(for paper: Paper) async throws -> PaperSummary {
        // Check if summary already exists
        let arxivId = paper.arxivId
        let descriptor = FetchDescriptor<PaperSummary>(
            predicate: #Predicate { $0.arxivId == arxivId }
        )
        
        if let existingSummary = try modelContext.fetch(descriptor).first {
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
        请严格按照以下结构输出，并控制总长度在 220~320 字：
        
        1) 这篇论文在解决什么问题（Problem）
        2) 它用了什么核心方法（Method）
        3) 最关键的实验结果和结论是什么（Result & Conclusion）
        4) 这篇论文为什么值得关注（Why it matters）
        5) 一句话总结（One-liner）
        6) Terms to Know（3-6 个核心术语）：
           每个术语按以下格式输出：
           - English Term Name（英文术语原文）
           - 中文翻译
           - 一句话解释（不超过 30 字，说明这个术语的通用含义）
           - 在本文里的具体含义（不超过 40 字，说明在这篇论文中的特定用法或意义）
        
        额外要求：
        - 不要使用营销语气，不要夸张
        - 不确定的信息要明确说"论文未明确说明"
        - 数字结果尽量保留原文量级或指标名
        - 术语要选择论文中最核心、最重要的概念
        """
        
        let userPrompt = """
        标题：\(paper.title)
        
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
        let summary = PaperSummary(
            arxivId: paper.arxivId,
            modelName: config.modelName,
            summaryText: response.content
        )
        
        // Parse sections from response
        let sections = parseSummarySections(from: response.content)
        summary.problem = sections["problem"]
        summary.method = sections["method"]
        summary.result = sections["result"]
        summary.whyItMatters = sections["whyItMatters"]
        summary.oneLiner = sections["oneLiner"]
        
        // Save to database
        modelContext.insert(summary)
        try modelContext.save()
        
        // Extract and save terminology
        try await extractTerminology(from: response.content, arxivId: paper.arxivId)
        
        return summary
    }
    
    private func parseSummarySections(from text: String) -> [String: String] {
        var sections: [String: String] = [:]
        
        // Simple regex-based parsing (can be improved)
        let lines = text.components(separatedBy: .newlines)
        var currentSection: String?
        var currentContent: [String] = []
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            
            if trimmed.contains("Problem") || trimmed.starts(with: "1)") {
                if let section = currentSection {
                    sections[section] = currentContent.joined(separator: "\n")
                }
                currentSection = "problem"
                currentContent = []
            } else if trimmed.contains("Method") || trimmed.starts(with: "2)") {
                if let section = currentSection {
                    sections[section] = currentContent.joined(separator: "\n")
                }
                currentSection = "method"
                currentContent = []
            } else if trimmed.contains("Result") || trimmed.starts(with: "3)") {
                if let section = currentSection {
                    sections[section] = currentContent.joined(separator: "\n")
                }
                currentSection = "result"
                currentContent = []
            } else if trimmed.contains("Why it matters") || trimmed.starts(with: "4)") {
                if let section = currentSection {
                    sections[section] = currentContent.joined(separator: "\n")
                }
                currentSection = "whyItMatters"
                currentContent = []
            } else if trimmed.contains("One-liner") || trimmed.starts(with: "5)") {
                if let section = currentSection {
                    sections[section] = currentContent.joined(separator: "\n")
                }
                currentSection = "oneLiner"
                currentContent = []
            } else if trimmed.contains("Terms to Know") || trimmed.starts(with: "6)") {
                if let section = currentSection {
                    sections[section] = currentContent.joined(separator: "\n")
                }
                break
            } else if !trimmed.isEmpty && currentSection != nil {
                currentContent.append(trimmed)
            }
        }
        
        if let section = currentSection {
            sections[section] = currentContent.joined(separator: "\n")
        }
        
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
