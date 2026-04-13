import SwiftUI
import PTCore
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
                        String(localized: "reader.dictionary.no_definition_title"),
                        systemImage: "book.closed",
                        description: Text(AppLocalization.format(
                            "reader.dictionary.no_definition_description_format",
                            "No installed dictionary contains a definition for \"%@\".",
                            term
                        ))
                    )
                }
            }
            .navigationTitle(term)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.done", action: onDismiss)
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
                String(localized: "reader.dictionary.unavailable_title"),
                systemImage: "book.closed",
                description: Text("reader.dictionary.unavailable_description")
            )
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.done", action: onDismiss)
                }
            }
        }
    }
}
#endif
