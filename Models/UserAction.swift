import Foundation
import SwiftData

@Model
final class UserAction {
    var id: String = UUID().uuidString
    var arxivId: String = ""
    var isFavorited: Bool = false
    var isRead: Bool = false
    var isSkipped: Bool = false
    var dwellTimeSeconds: Double = 0
    var updatedAt: Date = Date()
    
    init(arxivId: String, isFavorited: Bool = false, isRead: Bool = false, isSkipped: Bool = false, dwellTimeSeconds: Double = 0) {
        self.id = UUID().uuidString
        self.arxivId = arxivId
        self.isFavorited = isFavorited
        self.isRead = isRead
        self.isSkipped = isSkipped
        self.dwellTimeSeconds = dwellTimeSeconds
        self.updatedAt = Date()
    }
}

@Model
final class UserPreference {
    var id: String = "user_preference_singleton"
    var selectedCategories: [String] = []
    var sortPreference: String = "hotness"
    var summaryLengthPreference: String = "medium"
    var updatedAt: Date = Date()
    
    init(selectedCategories: [String] = [], sortPreference: String = "hotness", summaryLengthPreference: String = "medium") {
        self.id = "user_preference_singleton"
        self.selectedCategories = selectedCategories
        self.sortPreference = sortPreference
        self.summaryLengthPreference = summaryLengthPreference
        self.updatedAt = Date()
    }
}
