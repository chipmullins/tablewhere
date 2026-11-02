import SwiftUI
import SwiftData

/// Add or edit a home recipe: a name, plus an optional note and link.
struct RecipeForm: View {
    /// Nil to add a new one.
    var recipe: HomeRecipe?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var note = ""
    @State private var link = ""
    @State private var saveTaps = 0
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var linkIsBad: Bool {
        !link.trimmingCharacters(in: .whitespaces).isEmpty && HomeRecipe.link(from: link) == nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Chicken tacos", text: $name)
                        .focused($nameFocused)
                        .submitLabel(.next)
                } header: {
                    Text("What you make")
                }
                .listRowBackground(Theme.surface)

                Section {
                    TextField("Note, like “Mom’s recipe” (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                    TextField("Recipe link (optional)", text: $link)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text(linkIsBad ? "That doesn’t look like a web address." : "When the wheel lands on it, the link opens the recipe.")
                        .foregroundStyle(linkIsBad ? Theme.danger : Theme.muted)
                }
                .listRowBackground(Theme.surface)

                if let recipe {
                    Section {
                        Button("Delete meal", role: .destructive) { confirmDelete = true }
                            .confirmationDialog("Delete \(recipe.name)?", isPresented: $confirmDelete,
                                                titleVisibility: .visible) {
                                Button("Delete", role: .destructive) {
                                    context.delete(recipe)
                                    dismiss()
                                }
                            }
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.night)
            .navigationTitle(recipe == nil ? "Add a home meal" : "Edit meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .bold()
                        .disabled(trimmedName.isEmpty || linkIsBad)
                }
            }
            .sensoryFeedback(Haptic.commit, trigger: saveTaps)
            .onAppear {
                if let recipe {
                    name = recipe.name
                    note = recipe.note
                    link = recipe.link?.absoluteString ?? ""
                } else {
                    nameFocused = true
                }
            }
        }
        .presentationBackground(Theme.night)
    }

    private func save() {
        let cleanNote = String(note.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        let url = HomeRecipe.link(from: link)
        if let recipe {
            recipe.name = String(trimmedName.prefix(80))
            recipe.note = cleanNote
            recipe.link = url
        } else {
            context.insert(HomeRecipe(name: String(trimmedName.prefix(80)), note: cleanNote, link: url))
        }
        saveTaps += 1
        dismiss()
    }
}
