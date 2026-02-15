import SwiftUI
import SafariServices

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// A SwiftUI wrapper around `SFSafariViewController` for in-app web browsing.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = true
        
        let safari = SFSafariViewController(url: url, configuration: configuration)
        safari.preferredControlTintColor = .label
        return safari
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
