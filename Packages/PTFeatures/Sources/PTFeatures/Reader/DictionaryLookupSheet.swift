import SwiftUI
import PTUI

#if canImport(UIKit)
import UIKit

/// SwiftUI wrapper around `UIReferenceLibraryViewController` that
/// surfaces the system dictionary for the supplied term.
struct DictionaryLookupView: UIViewControllerRepresentable {
    let term: String

    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController {
        UIReferenceLibraryViewController(term: term)
    }

    func updateUIViewController(_ uiViewController: UIReferenceLibraryViewController, context: Context) {}
}

/// Sheet that presents the system dictionary lookup for a selected
/// word or phrase. If the system has no definition installed, an
/// install prompt from the OS is shown automatically.
struct DictionaryLookupSheet: View {
    let term: String
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm: term) {
                    DictionaryLookupView(term: term)
                        .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "No Definition",
                        systemImage: "book.closed",
                        description: Text("No installed dictionary contains a definition for \"\(term)\".")
                    )
                }
            }
            .navigationTitle(term)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                        .foregroundStyle(Morandi.accent)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
#else
struct DictionaryLookupSheet: View {
    let term: String
    let onDismiss: () -> Void
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Unavailable",
                systemImage: "book.closed",
                description: Text("Dictionary lookup is only supported on iOS.")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }
}
#endif
