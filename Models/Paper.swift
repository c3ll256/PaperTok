import Foundation
import SwiftData

@Model
final class Paper {
    var arxivId: String = ""
    var title: String = ""
    var authors: [String] = []
    var publishedDate: Date = Date()
    var categories: [String] = []
    var abstractText: String = ""
    var pdfURL: String = ""
    var createdAt: Date = Date()
    
    init(arxivId: String, title: String, authors: [String], publishedDate: Date, categories: [String], abstractText: String, pdfURL: String) {
        self.arxivId = arxivId
        self.title = title
        self.authors = authors
        self.publishedDate = publishedDate
        self.categories = categories
        self.abstractText = abstractText
        self.pdfURL = pdfURL
        self.createdAt = Date()
    }
}

@Model
final class PaperSummary {
    var id: String = UUID().uuidString
    var arxivId: String = ""
    var modelName: String = ""
    var summaryText: String = ""
    var problem: String?
    var method: String?
    var result: String?
    var whyItMatters: String?
    var oneLiner: String?
    var updatedAt: Date = Date()
    
    init(arxivId: String, modelName: String, summaryText: String) {
        self.id = UUID().uuidString
        self.arxivId = arxivId
        self.modelName = modelName
        self.summaryText = summaryText
        self.updatedAt = Date()
    }
}

@Model
final class TermGlossaryItem {
    var id: String = UUID().uuidString
    var arxivId: String = ""
    var termChinese: String = ""
    var termEnglish: String = ""
    var explanation: String = ""
    var contextMeaning: String = ""
    var weight: Double = 1.0
    var updatedAt: Date = Date()
    
    init(arxivId: String, termChinese: String, termEnglish: String, explanation: String, contextMeaning: String, weight: Double = 1.0) {
        self.id = UUID().uuidString
        self.arxivId = arxivId
        self.termChinese = termChinese
        self.termEnglish = termEnglish
        self.explanation = explanation
        self.contextMeaning = contextMeaning
        self.weight = weight
        self.updatedAt = Date()
    }
}
