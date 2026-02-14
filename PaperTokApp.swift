import SwiftUI
import SwiftData

@main
struct PaperTokApp: App {
    let modelContainer: ModelContainer
    
    init() {
        do {
            let schema = Schema([
                Paper.self,
                PaperSummary.self,
                TermGlossaryItem.self,
                UserAction.self,
                UserPreference.self
            ])
            
            // Local storage only
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            
            modelContainer = try ModelContainer(
                for: schema,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not initialize ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(modelContainer)
    }
}
