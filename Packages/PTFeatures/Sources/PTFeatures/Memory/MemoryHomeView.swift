import SwiftUI
import PTAIServices
import PTUI

public struct MemoryHomeView: View {
    @State private var viewModel: MemoryHomeViewModel

    public init(directory: URL) {
        _viewModel = State(initialValue: MemoryHomeViewModel(service: MemoryWorkflowService(directory: directory)))
    }

    public var body: some View {
        @Bindable var bindableViewModel = viewModel

        return VStack(spacing: 0) {
            header

            if let error = viewModel.errorMessage, error.isEmpty == false {
                errorBanner(error)
            }

            Picker("ai.memory", selection: $bindableViewModel.selectedSection) {
                Text("memory.section.review").tag(MemoryHomeViewModel.Section.review)
                Text("memory.section.documents").tag(MemoryHomeViewModel.Section.documents)
                Text("memory.section.search").tag(MemoryHomeViewModel.Section.search)
                Text("memory.section.capture").tag(MemoryHomeViewModel.Section.capture)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)

            Group {
                switch viewModel.selectedSection {
                case .review:
                    reviewSection
                case .documents:
                    documentsSection
                case .search:
                    searchSection
                case .capture:
                    captureSection
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Morandi.background)
        .navigationTitle(String(localized: "ai.memory"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.selectedCandidateStatus) { _, _ in
            Task { await viewModel.reloadCandidates() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("memory.header.title")
                .font(AppTypography.title2.weight(.semibold))
                .foregroundStyle(Morandi.primaryText)
            Text("memory.header.subtitle")
                .font(AppTypography.body)
                .foregroundStyle(Morandi.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, AppSpacing.md)
        .padding(.top, AppSpacing.md)
    }

    private func errorBanner(_ error: String) -> some View {
        HStack(spacing: AppSpacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
            Text(error)
                .font(AppTypography.caption)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                viewModel.errorMessage = nil
            } label: {
                Image(systemName: "xmark")
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, AppSpacing.md)
        .padding(.vertical, AppSpacing.sm)
        .background(Morandi.destructive)
    }

    private var reviewSection: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                statusFilter

                if viewModel.candidates.isEmpty {
                    emptyCard(
                        titleKey: "memory.empty.review.title",
                        subtitleKey: "memory.empty.review.subtitle"
                    )
                } else {
                    ForEach(viewModel.candidates) { candidate in
                        candidateCard(candidate)
                    }
                }
            }
            .padding(AppSpacing.md)
        }
    }

    private var statusFilter: some View {
        HStack(spacing: AppSpacing.sm) {
            filterChip("memory.filter.pending", value: .pending)
            filterChip("memory.filter.applied", value: .applied)
            filterChip("memory.filter.dismissed", value: .dismissed)
        }
    }

    private func filterChip(_ titleKey: String, value: MemoryCandidateStatus) -> some View {
        Button {
            viewModel.selectedCandidateStatus = value
        } label: {
            Text(LocalizedStringKey(titleKey))
                .font(AppTypography.caption.weight(.semibold))
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.xs)
                .background(
                    Capsule()
                        .fill(viewModel.selectedCandidateStatus == value ? Morandi.accent.opacity(0.18) : Morandi.cardBackground)
                )
                .foregroundStyle(viewModel.selectedCandidateStatus == value ? Morandi.accent : Morandi.secondaryText)
        }
        .buttonStyle(.plain)
    }

    private func candidateCard(_ candidate: MemoryCandidate) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.sm) {
            Text(candidate.summary)
                .font(AppTypography.body.weight(.semibold))
                .foregroundStyle(Morandi.primaryText)

            Text(candidate.effectiveDisplayText)
                .font(AppTypography.body)
                .foregroundStyle(Morandi.primaryText)

            if candidate.effectiveSourcePointer.isEmpty == false {
                Label(candidate.effectiveSourcePointer, systemImage: "point.bottomleft.forward.to.point.topright.scurvepath")
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
            }

            if let rationale = candidate.rationale, rationale.isEmpty == false {
                Text(rationale)
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.secondaryText)
            }

            if candidate.tags.isEmpty == false {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppSpacing.xs) {
                        ForEach(candidate.tags, id: \.self) { tag in
                            Text(tag)
                                .font(AppTypography.caption2)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Capsule().fill(Morandi.sage.opacity(0.18)))
                                .foregroundStyle(Morandi.sage)
                        }
                    }
                }
            }

            HStack(spacing: AppSpacing.sm) {
                Text(targetTitle(candidate.effectiveTargetDoc))
                    .font(AppTypography.caption)
                    .foregroundStyle(Morandi.tertiaryText)
                Spacer()

                if candidate.status == .pending {
                    Button("memory.action.save_daily") {
                        Task { await viewModel.applyCandidate(candidate.id, target: .daily) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Morandi.accent)

                    Button("memory.action.save_long_term") {
                        Task { await viewModel.applyCandidate(candidate.id, target: .longTerm) }
                    }
                    .buttonStyle(.bordered)

                    Button("memory.action.dismiss") {
                        Task { await viewModel.dismissCandidate(candidate.id) }
                    }
                    .buttonStyle(.bordered)
                } else {
                    Text(statusTitle(candidate.status))
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(Morandi.secondaryText)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                .fill(Morandi.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                        .strokeBorder(Morandi.divider, lineWidth: 0.5)
                )
        )
    }

    private var documentsSection: some View {
        VStack(spacing: AppSpacing.sm) {
            HStack(spacing: AppSpacing.sm) {
                Button("ai.create_today_memory") {
                    Task { await viewModel.createTodayDocument() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Morandi.accent)

                Button("common.save") {
                    Task { await viewModel.saveSelectedDocument() }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.selectedDocumentName == nil)

                Spacer()
            }
            .padding(.horizontal, AppSpacing.md)

            if viewModel.documents.isEmpty {
                emptyCard(
                    titleKey: "memory.empty.documents.title",
                    subtitleKey: "memory.empty.documents.subtitle"
                )
                .padding(.horizontal, AppSpacing.md)
            } else {
                HSplitOrVStack {
                    List(selection: Binding(
                        get: { viewModel.selectedDocumentName },
                        set: { newValue in
                            guard let newValue else { return }
                            Task { await viewModel.selectDocument(newValue) }
                        }
                    )) {
                        ForEach(viewModel.documents) { document in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(document.displayTitle())
                                    .font(AppTypography.caption.weight(.semibold))
                                    .foregroundStyle(Morandi.primaryText)
                                Text(document.preview)
                                    .font(AppTypography.caption2)
                                    .foregroundStyle(Morandi.secondaryText)
                                    .lineLimit(2)
                            }
                            .tag(document.name)
                        }
                    }
                    .listStyle(.plain)
                    .frame(minWidth: 200)

                    TextEditor(text: Binding(
                        get: { viewModel.selectedDocumentContent },
                        set: { viewModel.selectedDocumentContent = $0 }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .padding(AppSpacing.sm)
                    .scrollContentBackground(.hidden)
                    .background(Morandi.cardBackground)
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.bottom, AppSpacing.md)
            }
        }
    }

    private var searchSection: some View {
        VStack(spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(Morandi.tertiaryText)
                TextField(String(localized: "memory.search.placeholder"), text: Binding(
                    get: { viewModel.searchText },
                    set: { viewModel.searchText = $0 }
                ))
                .textFieldStyle(.plain)

                Button("common.search") {
                    Task { await viewModel.runSearch() }
                }
                .buttonStyle(.bordered)
            }
            .padding(AppSpacing.sm)
            .background(Morandi.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadiusSmall))
            .padding(.horizontal, AppSpacing.md)

            if viewModel.searchResults.isEmpty {
                emptyCard(
                    titleKey: "memory.empty.search.title",
                    subtitleKey: "memory.empty.search.subtitle"
                )
                .padding(.horizontal, AppSpacing.md)
            } else {
                ScrollView {
                    VStack(spacing: AppSpacing.sm) {
                        ForEach(Array(viewModel.searchResults.enumerated()), id: \.offset) { _, result in
                            Button {
                                let name = URL(fileURLWithPath: result.path).lastPathComponent
                                viewModel.selectedSection = .documents
                                Task { await viewModel.selectDocument(name) }
                            } label: {
                                VStack(alignment: .leading, spacing: AppSpacing.xs) {
                                    Text(result.displayTitle())
                                        .font(AppTypography.body.weight(.semibold))
                                        .foregroundStyle(Morandi.primaryText)
                                    Text(result.snippet.replacingOccurrences(of: "<b>", with: "").replacingOccurrences(of: "</b>", with: ""))
                                        .font(AppTypography.caption)
                                        .foregroundStyle(Morandi.secondaryText)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    if result.date.isEmpty == false {
                                        Text(result.date)
                                            .font(AppTypography.caption2)
                                            .foregroundStyle(Morandi.tertiaryText)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(AppSpacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                                        .fill(Morandi.cardBackground)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.bottom, AppSpacing.md)
                }
            }
        }
    }

    private var captureSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            Text("memory.capture.description")
                .font(AppTypography.body)
                .foregroundStyle(Morandi.secondaryText)

            TextEditor(text: Binding(
                get: { viewModel.captureText },
                set: { viewModel.captureText = $0 }
            ))
            .frame(minHeight: 220)
            .padding(AppSpacing.sm)
            .scrollContentBackground(.hidden)
            .background(Morandi.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cornerRadius))

            Picker("memory.capture.target", selection: Binding(
                get: { viewModel.captureTarget },
                set: { viewModel.captureTarget = $0 }
            )) {
                Text("memory.target.daily").tag(MemoryDocTarget.daily)
                Text("memory.target.long_term").tag(MemoryDocTarget.longTerm)
            }
            .pickerStyle(.segmented)

            HStack(spacing: AppSpacing.sm) {
                Button("memory.action.add_to_inbox") {
                    Task { await viewModel.saveCapture(addToInbox: true, target: viewModel.captureTarget) }
                }
                .buttonStyle(.bordered)

                Button("memory.action.save_now") {
                    Task { await viewModel.saveCapture(addToInbox: false, target: viewModel.captureTarget) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Morandi.accent)

                Spacer()
            }
        }
        .padding(AppSpacing.md)
    }

    private func emptyCard(titleKey: String, subtitleKey: String) -> some View {
        VStack(spacing: AppSpacing.sm) {
            Spacer(minLength: AppSpacing.xl)
            Image(systemName: "brain.head.profile")
                .font(.system(size: 36))
                .foregroundStyle(Morandi.tertiaryText)
            Text(LocalizedStringKey(titleKey))
                .font(AppTypography.title3)
                .foregroundStyle(Morandi.primaryText)
            Text(LocalizedStringKey(subtitleKey))
                .font(AppTypography.body)
                .foregroundStyle(Morandi.secondaryText)
                .multilineTextAlignment(.center)
            Spacer(minLength: AppSpacing.xl)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: AppSpacing.cornerRadius)
                .fill(Morandi.cardBackground)
        )
    }

    private func targetTitle(_ target: MemoryDocTarget) -> String {
        switch target {
        case .daily:
            return String(localized: "memory.target.daily")
        case .longTerm:
            return String(localized: "memory.target.long_term")
        }
    }

    private func statusTitle(_ status: MemoryCandidateStatus) -> String {
        switch status {
        case .pending:
            return String(localized: "memory.filter.pending")
        case .applied:
            return String(localized: "memory.filter.applied")
        case .dismissed:
            return String(localized: "memory.filter.dismissed")
        }
    }
}
