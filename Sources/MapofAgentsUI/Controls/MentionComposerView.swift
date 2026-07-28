import MapofAgentsCore
import Foundation
import SwiftUI

enum MentionComposerReturnAction: Equatable {
    case insertSelectedMention
    case submit
    case insertNewline
}

enum MentionComposerKeyboardPolicy {
    static func returnAction(
        shiftPressed: Bool,
        hasActiveMentionSuggestions: Bool
    ) -> MentionComposerReturnAction {
        if shiftPressed {
            return .insertNewline
        }
        if hasActiveMentionSuggestions {
            return .insertSelectedMention
        }
        return .submit
    }
}

struct MentionComposerView: View {
    @Binding var text: String
    @Bindable var runtimeStore: CodexRuntimeStore
    var placeholder: String
    var fileRoot: String?
    var extraCandidates: [MentionCandidate] = []
    var minLines: Int = 2
    var maxLines: Int = 5
    var isDisabled: Bool = false
    var usesLocalMentionCatalog: Bool = true
    var initiallyFocused: Bool = false
    var onSubmit: () -> Void = {}

    @State private var catalogCandidates: [MentionCandidate] = []
    @State private var selectedMentionIndex = 0
    @FocusState private var isEditorFocused: Bool
    @AccessibilityFocusState private var isEditorAccessibilityFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let activeMention {
                let candidates = visibleCandidates(for: activeMention)
                if !candidates.isEmpty {
                    MentionSuggestionPanel(
                        candidates: candidates,
                        selectedCandidateID: candidates.indices.contains(selectedMentionIndex)
                            ? candidates[selectedMentionIndex].id
                            : candidates.first?.id,
                        onSelect: insert
                    )
                }
            }

            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .focused($isEditorFocused)
                    .accessibilityFocused($isEditorAccessibilityFocused)
                    .accessibilityLabel(placeholder)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 7)
                    .frame(height: composerHeight)
                    .disabled(isDisabled)
                    .opacity(isDisabled ? 0.56 : 1)

                if text.isEmpty {
                    Text(placeholder)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 14)
                        .allowsHitTesting(false)
                }
            }
            .background(.background.opacity(0.62), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onKeyPress { keyPress in
                if let activeMention {
                    let candidates = visibleCandidates(for: activeMention)
                    if !candidates.isEmpty {
                        if keyPress.key == .downArrow {
                            selectedMentionIndex = (selectedMentionIndex + 1) % candidates.count
                            return .handled
                        }
                        if keyPress.key == .upArrow {
                            selectedMentionIndex = (selectedMentionIndex - 1 + candidates.count) % candidates.count
                            return .handled
                        }
                        if keyPress.key == .return,
                           MentionComposerKeyboardPolicy.returnAction(
                               shiftPressed: keyPress.modifiers.contains(.shift),
                               hasActiveMentionSuggestions: true
                           ) == .insertSelectedMention {
                            insert(candidates[min(selectedMentionIndex, candidates.count - 1)])
                            return .handled
                        }
                    }
                }

                guard keyPress.key == .return else {
                    return .ignored
                }

                switch MentionComposerKeyboardPolicy.returnAction(
                    shiftPressed: keyPress.modifiers.contains(.shift),
                    hasActiveMentionSuggestions: false
                ) {
                case .insertSelectedMention:
                    return .ignored
                case .submit:
                    onSubmit()
                    return .handled
                case .insertNewline:
                    return .ignored
                }
            }
            .animation(.snappy(duration: 0.16), value: composerHeight)
        }
        .task(id: catalogTaskKey) {
            await refreshCatalogs()
        }
        .onChange(of: activeMention?.query) { _, _ in
            selectedMentionIndex = 0
        }
        .onAppear {
            guard initiallyFocused else { return }
            Task { @MainActor in
                await Task.yield()
                isEditorFocused = true
                isEditorAccessibilityFocused = true
            }
        }
    }

    private var refreshKey: String {
        "\(usesLocalMentionCatalog ? "local" : "remote")::\(fileRoot ?? "")"
    }

    /// Query text is intentionally excluded: SwiftUI cancels the previous task
    /// when the root, connection, or mention mode changes, while each keystroke
    /// only filters the already-loaded catalog in memory.
    private var catalogTaskKey: String {
        let mentionMode = activeMention?.trigger == "@" ? "files" : "idle"
        return "\(refreshKey)::\(runtimeStore.connectionState.rawValue)::\(mentionMode)"
    }

    private var activeMention: ActiveMentionToken? {
        MentionTextParser.activeMention(in: text)
    }

    private var composerHeight: CGFloat {
        composerHeight(for: visibleLineCount)
    }

    private var visibleLineCount: Int {
        min(max(minLines, estimatedLineCount), maxLines)
    }

    private var estimatedLineCount: Int {
        guard !text.isEmpty else {
            return minLines
        }

        return text
            .split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { count, line in
                count + max(1, Int(ceil(Double(line.count) / 54.0)))
            }
    }

    private func composerHeight(for lines: Int) -> CGFloat {
        CGFloat(max(1, lines)) * 19 + 22
    }

    private func visibleCandidates(for mention: ActiveMentionToken) -> [MentionCandidate] {
        let runtimeCandidates = usesLocalMentionCatalog
            ? catalogCandidates.filter { $0.trigger == mention.trigger }
            : []
        let sourceCandidates = runtimeCandidates
            + extraCandidates.filter { $0.trigger == mention.trigger }
        let query = mention.query.trimmingCharacters(in: .whitespacesAndNewlines)

        let filtered: [MentionCandidate]
        if query.isEmpty {
            filtered = sourceCandidates
        } else {
            filtered = sourceCandidates.filter { candidate in
                candidate.label.localizedCaseInsensitiveContains(query)
                    || candidate.title.localizedCaseInsensitiveContains(query)
                    || candidate.subtitle.localizedCaseInsensitiveContains(query)
            }
        }

        return Array(
            filtered
                .sorted(by: mentionCandidateSort)
                .prefix(8)
        )
    }

    private func mentionCandidateSort(_ lhs: MentionCandidate, _ rhs: MentionCandidate) -> Bool {
        if lhs.kind != rhs.kind {
            return lhs.kind.displayPriority < rhs.kind.displayPriority
        }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    private func insert(_ candidate: MentionCandidate) {
        guard let activeMention else { return }
        text.replaceSubrange(activeMention.range, with: "\(candidate.insertionText) ")
        selectedMentionIndex = 0
        isEditorFocused = true
    }

    @MainActor
    private func refreshCatalogs() async {
        guard usesLocalMentionCatalog else {
            catalogCandidates = []
            return
        }
        let candidates = await runtimeStore.loadMentionCandidates(cwd: fileRoot)
        guard !Task.isCancelled else { return }
        catalogCandidates = candidates
    }
}

private struct MentionSuggestionPanel: View {
    var candidates: [MentionCandidate]
    var selectedCandidateID: String?
    var onSelect: (MentionCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(candidates) { candidate in
                Button {
                    onSelect(candidate)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: systemImage(for: candidate.kind))
                            .foregroundStyle(color(for: candidate.kind))
                            .frame(width: 18)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)

                            Text(candidate.subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                    .background(
                        candidate.id == selectedCandidateID
                            ? Color.accentColor.opacity(0.14)
                            : Color.clear,
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(candidate.title), \(candidate.subtitle)")
                .accessibilityValue(candidate.id == selectedCandidateID ? "Selected" : "")
            }
        }
        .padding(4)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(.quaternary, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 6)
    }

    private func systemImage(for kind: MentionKind) -> String {
        switch kind {
        case .skill:
            return "sparkles"
        case .plugin:
            return "puzzlepiece.extension"
        case .file:
            return "doc.text"
        case .folder:
            return "folder"
        case .thread:
            return "bubble.left.and.bubble.right"
        }
    }

    private func color(for kind: MentionKind) -> Color {
        switch kind {
        case .skill:
            return .purple
        case .plugin:
            return .blue
        case .file:
            return .secondary
        case .folder:
            return .yellow
        case .thread:
            return .green
        }
    }
}

private struct ActiveMentionToken {
    var trigger: String
    var query: String
    var range: Range<String.Index>
}

private enum MentionTextParser {
    static func activeMention(in text: String) -> ActiveMentionToken? {
        guard let triggerIndex = text.indices.last(where: { text[$0] == "$" || text[$0] == "@" }) else {
            return nil
        }

        if triggerIndex > text.startIndex {
            let previousIndex = text.index(before: triggerIndex)
            guard isTokenBoundary(text[previousIndex]) else {
                return nil
            }
        }

        let queryStart = text.index(after: triggerIndex)
        let query = String(text[queryStart...])
        guard query.allSatisfy(isAllowedMentionQueryCharacter) else {
            return nil
        }

        return ActiveMentionToken(
            trigger: String(text[triggerIndex]),
            query: query,
            range: triggerIndex..<text.endIndex
        )
    }

    private static func isTokenBoundary(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private static func isAllowedMentionQueryCharacter(_ character: Character) -> Bool {
        if isTokenBoundary(character) {
            return false
        }
        return !["[", "]", "(", ")", "<", ">"].contains(character)
    }
}

private extension MentionKind {
    var displayPriority: Int {
        switch self {
        case .plugin:
            return 0
        case .thread:
            return 1
        case .folder:
            return 2
        case .file:
            return 3
        case .skill:
            return 4
        }
    }
}
