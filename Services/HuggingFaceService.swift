import Foundation
import SwiftData

// MARK: - Domain Types

enum FeedSource: String {
    case arxiv = "arxiv"
    case huggingFace = "huggingface"
}

enum HFTimePeriod: String, CaseIterable {
    case daily = "daily"
    case weekly = "weekly"
    case monthly = "monthly"

    var displayName: String {
        switch self {
        case .daily: return "今日"
        case .weekly: return "本周"
        case .monthly: return "本月"
        }
    }
}

// MARK: - Decodable Models

private struct HFDailyPaper: Decodable {
    let paper: HFPaperDetail
    let upvotes: Int
    let publishedAt: String?
    let summary: String?
    let title: String?

    private enum CodingKeys: String, CodingKey {
        case paper
        case upvotes
        case publishedAt
        case summary
        case title
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paper = try container.decode(HFPaperDetail.self, forKey: .paper)
        publishedAt = try container.decodeIfPresent(String.self, forKey: .publishedAt)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        title = try container.decodeIfPresent(String.self, forKey: .title)

        // Backward/forward compatible:
        // - Old shape: top-level "upvotes"
        // - Current shape: nested "paper.upvotes"
        upvotes = try container.decodeIfPresent(Int.self, forKey: .upvotes) ?? paper.upvotes ?? 0
    }

    struct HFPaperDetail: Decodable {
        let id: String
        let title: String
        let authors: [HFAuthor]
        let summary: String?
        let publishedAt: String?
        let upvotes: Int?

        struct HFAuthor: Decodable {
            let name: String
        }
    }
}

// MARK: - Service

@ModelActor
actor HuggingFaceService {
    private static let dailyPapersURL = "https://huggingface.co/api/daily_papers"

    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.waitsForConnectivity = true
        return URLSession(configuration: config)
    }()

    /// Fetches papers from HuggingFace Papers for the given time period,
    /// persists them to SwiftData, and returns their arXiv IDs in ranked order.
    func fetchPapers(period: HFTimePeriod) async throws -> [String] {
        switch period {
        case .daily:
            return try await fetchLatestAvailableDailyPapers(maxLookbackDays: 7)
        case .weekly:
            return try await fetchAggregatedPapers(dayCount: 7)
        case .monthly:
            return try await fetchAggregatedPapers(dayCount: 30)
        }
    }

    // MARK: - Private Fetch Methods

    private func fetchDailyPapers(for date: Date) async throws -> [String] {
        let url = Self.makeURL(for: date)
        let papers = try await Self.fetchRaw(from: url)
        return try savePapers(papers)
    }

    /// Daily feed can be empty on some dates (or around timezone boundaries).
    /// Try recent days and return the first non-empty batch.
    private func fetchLatestAvailableDailyPapers(maxLookbackDays: Int) async throws -> [String] {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        var lastError: Error?

        for offset in 0..<maxLookbackDays {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            do {
                let ids = try await fetchDailyPapers(for: date)
                if !ids.isEmpty { return ids }
            } catch {
                // Keep trying previous days; expose the last failure if all fail.
                lastError = error
            }
        }

        if let lastError { throw lastError }
        return []
    }

    /// Fetches papers across multiple days concurrently (in batches), deduplicates
    /// by arXiv ID, and returns them sorted by community upvotes descending.
    private func fetchAggregatedPapers(dayCount: Int) async throws -> [String] {
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()

        let urls: [URL] = (0..<dayCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            return Self.makeURL(for: date)
        }

        // Process in batches of 5 to avoid overwhelming the server
        let batchSize = 5
        var allPapers: [HFDailyPaper] = []

        for batchStart in stride(from: 0, to: urls.count, by: batchSize) {
            let batch = Array(urls[batchStart..<min(batchStart + batchSize, urls.count)])

            // Fetch batch concurrently; individual failures return empty (non-fatal)
            let batchPapers: [HFDailyPaper] = await withTaskGroup(of: [HFDailyPaper].self) { group in
                for url in batch {
                    group.addTask { (try? await Self.fetchRaw(from: url)) ?? [] }
                }
                var result: [HFDailyPaper] = []
                for await papers in group { result.append(contentsOf: papers) }
                return result
            }

            allPapers.append(contentsOf: batchPapers)
        }

        // Deduplicate by arXiv ID (keep entry with highest upvotes), sort descending
        let deduped = Dictionary(grouping: allPapers, by: \.paper.id)
            .values
            .compactMap { $0.max(by: { $0.upvotes < $1.upvotes }) }
            .sorted { $0.upvotes > $1.upvotes }

        return try savePapers(deduped)
    }

    // MARK: - Static Helpers (nonisolated — no actor state accessed)

    private static func fetchRaw(from url: URL) async throws -> [HFDailyPaper] {
        var request = URLRequest(url: url)
        request.setValue("PaperFlip/1.0 (iOS; mailto:paperflip@example.com)", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw HFServiceError.networkError
        }
        guard (200...299).contains(http.statusCode) else {
            throw HFServiceError.httpError(statusCode: http.statusCode)
        }

        do {
            return try JSONDecoder().decode([HFDailyPaper].self, from: data)
        } catch {
            print("⚠️ HF parse error for \(url): \(error)")
            throw HFServiceError.parseError
        }
    }

    private static func makeURL(for date: Date) -> URL {
        var components = URLComponents(string: dailyPapersURL)!
        components.queryItems = [URLQueryItem(name: "date", value: formatDate(date))]
        return components.url!
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    // MARK: - SwiftData Persistence

    private func savePapers(_ entries: [HFDailyPaper]) throws -> [String] {
        var arxivIds: [String] = []

        for entry in entries {
            let arxivId = entry.paper.id
            arxivIds.append(arxivId)

            let descriptor = FetchDescriptor<Paper>(
                predicate: #Predicate { $0.arxivId == arxivId }
            )
            if try modelContext.fetch(descriptor).isEmpty {
                let paper = Paper(
                    arxivId: arxivId,
                    title: entry.paper.title,
                    authors: entry.paper.authors.map(\.name),
                    publishedDate: parseISO(entry.paper.publishedAt ?? entry.publishedAt ?? "") ?? Date(),
                    categories: [],
                    abstractText: entry.paper.summary ?? "",
                    pdfURL: "https://arxiv.org/pdf/\(arxivId)"
                )
                modelContext.insert(paper)
            }
        }

        try modelContext.save()
        return arxivIds
    }

    private func parseISO(_ string: String) -> Date? {
        guard !string.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: string) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: string)
    }
}

// MARK: - Error

enum HFServiceError: Error, LocalizedError {
    case networkError
    case parseError
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .networkError:
            return "网络请求失败，请检查网络连接"
        case .parseError:
            return "解析 Hugging Face 数据失败"
        case .httpError(let code):
            return "Hugging Face 服务器返回错误（\(code)）"
        }
    }
}
