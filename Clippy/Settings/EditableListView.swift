import SwiftUI

/// A small add/remove string list backed by closures over AppSettings —
/// @AppStorage cannot bind string arrays, so this owns a local copy and
/// writes through on every change.
struct EditableListView: View {
    let title: String
    let placeholder: String
    let get: () -> [String]
    let set: ([String]) -> Void

    @State private var entries: [String] = []
    @State private var newEntry = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            ForEach(entries, id: \.self) { entry in
                HStack {
                    Text(entry)
                        .font(.system(size: 12, design: .monospaced))
                    Spacer()
                    Button {
                        entries.removeAll { $0 == entry }
                        set(entries)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField(placeholder, text: $newEntry)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(newEntry.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onAppear { entries = get() }
    }

    private func add() {
        let trimmed = newEntry.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !entries.contains(trimmed) else { return }
        entries.append(trimmed)
        set(entries)
        newEntry = ""
    }
}
