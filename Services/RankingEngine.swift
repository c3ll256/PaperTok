import Foundation
import SwiftData

struct RankedPaper {
    let paper: Paper
    let score: Double
}

class RankingEngine {
    private let modelContext: ModelContext
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func rankPapers(_ papers: [Paper]) async throws -> [Paper] {
        var rankedPapers: [RankedPaper] = []
        
        for paper in papers {
            let score = try await calculateScore(for: paper)
            rankedPapers.append(RankedPaper(paper: paper, score: score))
        }
        
        // Sort by score descending
        rankedPapers.sort { $0.score > $1.score }
        
        return rankedPapers.map { $0.paper }
    }
    
    private func calculateScore(for paper: Paper) async throws -> Double {
        // Fetch user action for this paper
        let arxivId = paper.arxivId
        let actionDescriptor = FetchDescriptor<UserAction>(
            predicate: #Predicate { $0.arxivId == arxivId }
        )
        let userAction = try modelContext.fetch(actionDescriptor).first
        
        // Calculate components
        let freshnessScore = calculateFreshnessScore(publishedDate: paper.publishedDate)
        let userBehaviorScore = calculateUserBehaviorScore(action: userAction)
        let categoryRelevanceScore = try await calculateCategoryRelevance(categories: paper.categories)
        
        // Weighted combination
        let totalScore = (0.35 * freshnessScore) +
                        (0.40 * userBehaviorScore) +
                        (0.25 * categoryRelevanceScore)
        
        return totalScore
    }
    
    private func calculateFreshnessScore(publishedDate: Date) -> Double {
        let now = Date()
        let daysSincePublished = now.timeIntervalSince(publishedDate) / (24 * 60 * 60)
        
        // Exponential decay: papers lose half their freshness every 7 days
        let halfLife = 7.0
        let decayRate = log(2) / halfLife
        let score = exp(-decayRate * daysSincePublished)
        
        return max(0, min(1, score))
    }
    
    private func calculateUserBehaviorScore(action: UserAction?) -> Double {
        guard let action = action else {
            return 0.5 // Neutral score for unseen papers
        }
        
        var score = 0.5
        
        if action.isFavorited {
            score += 0.5
        }
        
        if action.isSkipped {
            score -= 0.3
        }
        
        if action.isRead {
            score += 0.2
        }
        
        // Dwell time bonus (normalize to 0-0.3 range)
        let dwellBonus = min(0.3, action.dwellTimeSeconds / 300.0) // 300s = 5min max
        score += dwellBonus
        
        return max(0, min(1, score))
    }
    
    private func calculateCategoryRelevance(categories: [String]) async throws -> Double {
        // Fetch user preferences
        let prefDescriptor = FetchDescriptor<UserPreference>(
            predicate: #Predicate { $0.id == "user_preference_singleton" }
        )
        
        guard let userPref = try modelContext.fetch(prefDescriptor).first else {
            return 0.5 // Neutral if no preferences set
        }
        
        let selectedCategories = Set(userPref.selectedCategories)
        let paperCategories = Set(categories)
        
        let intersection = selectedCategories.intersection(paperCategories)
        
        if selectedCategories.isEmpty {
            return 0.5
        }
        
        let relevanceRatio = Double(intersection.count) / Double(selectedCategories.count)
        return relevanceRatio
    }
}
