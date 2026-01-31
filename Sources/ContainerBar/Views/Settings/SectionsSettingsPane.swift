import SwiftUI

/// Settings pane for managing container sections
struct SectionsSettingsPane: View {
    @Environment(SettingsStore.self) private var settings
    @State private var selectedSectionId: UUID?
    @State private var showingAddSection = false
    @State private var showingEditSection = false
    @State private var sectionToEdit: ContainerSection?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            Text("Organize containers into custom sections based on matching rules.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // Sections list
            GroupBox {
                if settings.sections.isEmpty {
                    emptyState
                } else {
                    sectionsList
                }
            }

            // Add button
            HStack {
                Button {
                    showingAddSection = true
                } label: {
                    Label("Add Section", systemImage: "plus")
                }

                Spacer()

                if !settings.sections.isEmpty {
                    Text("\(settings.sections.count) section(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showingAddSection) {
            SectionEditorSheet(mode: .add)
        }
        .sheet(item: $sectionToEdit) { section in
            SectionEditorSheet(mode: .edit(section))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)

            Text("No sections defined")
                .font(.headline)

            Text("Add sections to organize your containers.\nContainers not matching any section will appear in \"Other\".")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var sectionsList: some View {
        List(selection: $selectedSectionId) {
            ForEach(settings.sections) { section in
                SectionRow(section: section) {
                    sectionToEdit = section
                } onDelete: {
                    settings.removeSection(id: section.id)
                }
            }
            .onMove { source, destination in
                settings.moveSection(from: source, to: destination)
            }
        }
        .listStyle(.bordered(alternatesRowBackgrounds: true))
        .frame(minHeight: 200)
    }
}

/// Row for displaying a section in the list
struct SectionRow: View {
    let section: ContainerSection
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(section.name)
                    .font(.body)

                if section.matchRules.isEmpty {
                    Text("No matching rules")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else {
                    Text("\(section.matchRules.count) rule(s)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if isHovered {
                HStack(spacing: 8) {
                    Button {
                        onEdit()
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .help("Edit section")

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete section")
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

/// Sheet for adding or editing a section
struct SectionEditorSheet: View {
    enum Mode {
        case add
        case edit(ContainerSection)

        var title: String {
            switch self {
            case .add: return "Add Section"
            case .edit: return "Edit Section"
            }
        }
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(SettingsStore.self) private var settings

    let mode: Mode

    @State private var name: String = ""
    @State private var matchRules: [ContainerSection.MatchRule] = []
    @State private var showingAddRule = false

    init(mode: Mode) {
        self.mode = mode
        if case .edit(let section) = mode {
            _name = State(initialValue: section.name)
            _matchRules = State(initialValue: section.matchRules)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(mode.title)
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Content
            Form {
                Section("Section Name") {
                    TextField("Name", text: $name)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Matching Rules") {
                    if matchRules.isEmpty {
                        Text("No rules defined. Add rules to match containers to this section.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach($matchRules) { $rule in
                            MatchRuleRow(rule: $rule) {
                                matchRules.removeAll { $0.id == rule.id }
                            }
                        }
                    }

                    Button {
                        matchRules.append(ContainerSection.MatchRule(
                            type: .containerNameContains,
                            pattern: ""
                        ))
                    } label: {
                        Label("Add Rule", systemImage: "plus")
                    }
                }
            }
            .formStyle(.grouped)
            .frame(minHeight: 300)

            Divider()

            // Footer buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveSection()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding()
        }
        .frame(width: 450, height: 450)
    }

    private func saveSection() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard !trimmedName.isEmpty else { return }

        // Filter out rules with empty patterns
        let validRules = matchRules.filter { !$0.pattern.trimmingCharacters(in: .whitespaces).isEmpty }

        switch mode {
        case .add:
            let section = ContainerSection(name: trimmedName, matchRules: validRules)
            settings.addSection(section)
        case .edit(let existing):
            var updated = existing
            updated.name = trimmedName
            updated.matchRules = validRules
            settings.updateSection(updated)
        }
    }
}

/// Row for editing a match rule
struct MatchRuleRow: View {
    @Binding var rule: ContainerSection.MatchRule
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $rule.type) {
                ForEach(ContainerSection.MatchType.allCases, id: \.self) { type in
                    Text(type.description).tag(type)
                }
            }
            .labelsHidden()
            .frame(width: 180)

            TextField("Pattern", text: $rule.pattern)
                .textFieldStyle(.roundedBorder)

            Button {
                onDelete()
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
    }
}

#if DEBUG
#Preview {
    SectionsSettingsPane()
        .environment(SettingsStore())
        .frame(width: 500, height: 400)
}
#endif
