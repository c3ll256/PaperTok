import Foundation
import SwiftData

struct ArxivQuery {
    let categories: [String]
    let maxResults: Int
    let sortBy: String // "submittedDate", "lastUpdatedDate", "relevance"
    let sortOrder: String // "descending", "ascending"
}

class ArxivService {
    private let baseURL = "https://export.arxiv.org/api/query"
    private let modelContext: ModelContext
    private let maxRetries = 3
    private let baseDelay: UInt64 = 3_000_000_000 // 3 seconds in nanoseconds
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }
    
    func fetchPapers(query: ArxivQuery) async throws -> [Paper] {
        // Validate categories
        guard !query.categories.isEmpty else {
            print("❌ No categories selected")
            throw ArxivError.invalidQuery
        }
        
        // Try with retries for rate limiting
        for attempt in 0..<maxRetries {
            do {
                return try await fetchPapersInternal(query: query, attempt: attempt)
            } catch ArxivError.rateLimited {
                if attempt < maxRetries - 1 {
                    let delay = baseDelay * UInt64(pow(2.0, Double(attempt)))
                    print("⏳ Rate limited. Waiting \(delay / 1_000_000_000) seconds before retry \(attempt + 1)/\(maxRetries)...")
                    try await Task.sleep(nanoseconds: delay)
                } else {
                    throw ArxivError.rateLimited
                }
            }
        }
        
        throw ArxivError.networkError
    }
    
    private func fetchPapersInternal(query: ArxivQuery, attempt: Int) async throws -> [Paper] {
        // Build search query
        let categoryQuery = query.categories.map { "cat:\($0)" }.joined(separator: " OR ")
        
        var components = URLComponents(string: baseURL)!
        components.queryItems = [
            URLQueryItem(name: "search_query", value: categoryQuery),
            URLQueryItem(name: "max_results", value: "\(query.maxResults)"),
            URLQueryItem(name: "sortBy", value: query.sortBy),
            URLQueryItem(name: "sortOrder", value: query.sortOrder)
        ]
        
        guard let url = components.url else {
            print("❌ Failed to construct URL from components")
            throw ArxivError.invalidURL
        }
        
        print("📡 Fetching from URL (attempt \(attempt + 1)): \(url.absoluteString)")
        
        // Create a custom URLRequest with proper headers
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("PaperTok/1.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 30
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ Invalid response type")
            throw ArxivError.networkError
        }
        
        print("📊 HTTP Status Code: \(httpResponse.statusCode)")
        
        // Check for rate limiting (429 status code or "Rate exceeded" in body)
        if httpResponse.statusCode == 429 {
            print("❌ ArXiv API rate limit exceeded (429)")
            throw ArxivError.rateLimited
        }
        
        if let responseString = String(data: data, encoding: .utf8) {
            if responseString.contains("Rate exceeded") || responseString.contains("retry") {
                print("❌ ArXiv API rate limit exceeded (message in body)")
                throw ArxivError.rateLimited
            }
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            print("❌ HTTP Error: \(httpResponse.statusCode)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("Response body: \(responseString.prefix(500))")
            }
            throw ArxivError.httpError(statusCode: httpResponse.statusCode, message: "HTTP request failed")
        }
        
        print("✅ Received \(data.count) bytes of data")
        
        let papers = try parseArxivXML(data: data)
        
        // Save to local database
        for paper in papers {
            // Check if paper already exists
            let arxivId = paper.arxivId
            let descriptor = FetchDescriptor<Paper>(
                predicate: #Predicate { $0.arxivId == arxivId }
            )
            
            if try modelContext.fetch(descriptor).isEmpty {
                modelContext.insert(paper)
            }
        }
        
        try modelContext.save()
        
        return papers
    }
    
    private func parseArxivXML(data: Data) throws -> [Paper] {
        let parser = ArxivXMLParser()
        return try parser.parse(data: data)
    }
}

enum ArxivError: Error, LocalizedError {
    case invalidURL
    case networkError
    case parseError
    case httpError(statusCode: Int, message: String)
    case invalidQuery
    case rateLimited
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid ArXiv API URL"
        case .networkError:
            return "Network request failed. Please check your internet connection."
        case .parseError:
            return "Failed to parse ArXiv response"
        case .httpError(let statusCode, let message):
            return "HTTP Error \(statusCode): \(message)"
        case .invalidQuery:
            return "Please select at least one research category in settings"
        case .rateLimited:
            return "ArXiv API rate limit exceeded. Please wait a few seconds and try again."
        }
    }
}

// MARK: - XML Parser

class ArxivXMLParser: NSObject, XMLParserDelegate {
    private var papers: [Paper] = []
    private var currentElement = ""
    private var currentValue = ""
    
    // Current entry data
    private var currentId = ""
    private var currentTitle = ""
    private var currentAuthors: [String] = []
    private var currentPublished = ""
    private var currentCategories: [String] = []
    private var currentAbstract = ""
    private var currentPdfURL = ""
    
    func parse(data: Data) throws -> [Paper] {
        let parser = XMLParser(data: data)
        parser.delegate = self
        
        guard parser.parse() else {
            throw ArxivError.parseError
        }
        
        return papers
    }
    
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        currentElement = elementName
        currentValue = ""
        
        if elementName == "entry" {
            // Reset current entry data
            currentId = ""
            currentTitle = ""
            currentAuthors = []
            currentPublished = ""
            currentCategories = []
            currentAbstract = ""
            currentPdfURL = ""
        }
        
        if elementName == "link" {
            if let title = attributeDict["title"], title == "pdf",
               let href = attributeDict["href"] {
                currentPdfURL = href
            }
        }
        
        if elementName == "category" {
            if let term = attributeDict["term"] {
                currentCategories.append(term)
            }
        }
    }
    
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        currentValue += string
    }
    
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let trimmed = currentValue.trimmingCharacters(in: .whitespacesAndNewlines)
        
        switch elementName {
        case "id":
            if currentId.isEmpty {
                currentId = extractArxivId(from: trimmed)
            }
        case "title":
            if currentTitle.isEmpty {
                currentTitle = trimmed
            }
        case "name":
            if currentElement == "name" {
                currentAuthors.append(trimmed)
            }
        case "published":
            currentPublished = trimmed
        case "summary":
            currentAbstract = trimmed
        case "entry":
            // Create Paper object
            if !currentId.isEmpty,
               let publishedDate = parseDate(currentPublished) {
                let paper = Paper(
                    arxivId: currentId,
                    title: currentTitle,
                    authors: currentAuthors,
                    publishedDate: publishedDate,
                    categories: currentCategories,
                    abstractText: currentAbstract,
                    pdfURL: currentPdfURL
                )
                papers.append(paper)
            }
        default:
            break
        }
        
        currentElement = ""
    }
    
    private func extractArxivId(from urlString: String) -> String {
        // Extract ID from URL like "http://arxiv.org/abs/2401.12345v1"
        let components = urlString.components(separatedBy: "/")
        if let last = components.last {
            // Remove version suffix (e.g., "v1")
            return last.replacingOccurrences(of: #"v\d+$"#, with: "", options: .regularExpression)
        }
        return urlString
    }
    
    private func parseDate(_ dateString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: dateString)
    }
}
