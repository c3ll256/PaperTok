import Foundation
import SwiftData

private struct RankedPaperEntry {
    let arxivId: String
    let score: Double
}

@ModelActor
actor RankingEngine {
    
    /// Accepts arxivId strings, fetches papers from own context, ranks them,
    /// and returns arxivIds in ranked order.
    func rankPapers(_ arxivIds: [String]) async throws -> [String] {
        var entries: [RankedPaperEntry] = []
        
        for arxivId in arxivIds {
            // Fetch the paper from this actor's own ModelContext
            let descriptor = FetchDescriptor<Paper>(
                predicate: #Predicate { $0.arxivId == arxivId }
            )
            guard let paper = try modelContext.fetch(descriptor).first else {
                continue
            }
            
            let score = try await calculateScore(for: paper)
            entries.append(RankedPaperEntry(arxivId: arxivId, score: score))
        }
        
        // Sort by score descending
        entries.sort { $0.score > $1.score }
        
        return entries.map { $0.arxivId }
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
