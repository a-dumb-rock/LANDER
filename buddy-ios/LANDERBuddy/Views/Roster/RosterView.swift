import SwiftUI

struct RosterView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingAddSheet = false
    @State private var editingAthlete: Athlete?
    
    var body: some View {
        NavigationStack {
            List {
                if appState.athletes.isEmpty {
                    ContentUnavailableView(
                        "No Athletes",
                        systemImage: "person.3",
                        description: Text("Add your first athlete to get started.")
                    )
                } else {
                    ForEach(appState.athletes.filter { $0.active }) { athlete in
                        AthleteRow(athlete: athlete)
                            .swipeActions(edge: .trailing) {
                                Button("Remove", role: .destructive) {
                                    Task { await removeAthlete(athlete) }
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button("Edit") {
                                    editingAthlete = athlete
                                }
                                .tint(.brand)
                            }
                    }
                }
            }
            .navigationTitle("Roster")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.brand)
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                AddAthleteSheet { name, number, position in
                    Task { await addAthlete(name: name, jerseyNumber: number, position: position) }
                }
            }
            .sheet(item: $editingAthlete) { athlete in
                EditAthleteSheet(athlete: athlete) { name, number, position in
                    Task { await updateAthlete(id: athlete.id, name: name, jerseyNumber: number, position: position) }
                }
            }
            .refreshable {
                await appState.refresh()
            }
        }
    }
    
    private func addAthlete(name: String, jerseyNumber: String, position: String) async {
        guard let teamId = appState.team?.id else { return }
        do {
            let athlete = try await SupabaseManager.shared.addAthlete(
                teamId: teamId, name: name, jerseyNumber: jerseyNumber, position: position
            )
            appState.athletes.append(athlete)
        } catch {
            appState.error = error.localizedDescription
        }
    }
    
    private func updateAthlete(id: UUID, name: String, jerseyNumber: String, position: String) async {
        do {
            try await SupabaseManager.shared.updateAthlete(id: id, name: name, jerseyNumber: jerseyNumber, position: position)
            if let index = appState.athletes.firstIndex(where: { $0.id == id }) {
                appState.athletes[index].name = name
                appState.athletes[index].jerseyNumber = jerseyNumber
                appState.athletes[index].position = position
            }
        } catch {
            appState.error = error.localizedDescription
        }
    }
    
    private func removeAthlete(_ athlete: Athlete) async {
        do {
            try await SupabaseManager.shared.deactivateAthlete(id: athlete.id)
            appState.athletes.removeAll { $0.id == athlete.id }
        } catch {
            appState.error = error.localizedDescription
        }
    }
}

struct AthleteRow: View {
    let athlete: Athlete
    
    var body: some View {
        HStack(spacing: 12) {
            Text("#\(athlete.jerseyNumber.isEmpty ? "—" : athlete.jerseyNumber)")
                .font(.caption.weight(.bold))
                .frame(width: 36, height: 36)
                .background(Color.brand.opacity(0.1))
                .foregroundColor(.brand)
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(athlete.name)
                    .font(.subheadline.weight(.semibold))
                Text(athlete.position.isEmpty ? "No position" : athlete.position)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Add/Edit Sheets

struct AddAthleteSheet: View {
    @Environment(\.dismiss) var dismiss
    @State private var name = ""
    @State private var jerseyNumber = ""
    @State private var position = ""
    let onSave: (String, String, String) -> Void
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Jersey #", text: $jerseyNumber)
                    .keyboardType(.numberPad)
                TextField("Position", text: $position)
            }
            .navigationTitle("Add Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onSave(name, jerseyNumber, position)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}

struct EditAthleteSheet: View {
    @Environment(\.dismiss) var dismiss
    let athlete: Athlete
    let onSave: (String, String, String) -> Void
    
    @State private var name: String
    @State private var jerseyNumber: String
    @State private var position: String
    
    init(athlete: Athlete, onSave: @escaping (String, String, String) -> Void) {
        self.athlete = athlete
        self.onSave = onSave
        _name = State(initialValue: athlete.name)
        _jerseyNumber = State(initialValue: athlete.jerseyNumber)
        _position = State(initialValue: athlete.position)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Jersey #", text: $jerseyNumber)
                    .keyboardType(.numberPad)
                TextField("Position", text: $position)
            }
            .navigationTitle("Edit Athlete")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, jerseyNumber, position)
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
}
