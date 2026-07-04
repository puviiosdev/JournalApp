import SwiftUI
import Supabase
import PhotosUI

struct MainJournalListView: View {
    @StateObject private var repository = JournalRepository.shared
    @State private var isLoading = false
    @State private var isShowingAddEntry = false
    @State private var selectedEntry: JournalEntry? = nil
    @State private var alertMessage = ""
    @State private var showAlert = false
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading entries...")
                } else if repository.entries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "book.closed.fill")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                        
                        Text("No Entries Yet")
                            .font(.title3)
                            .fontWeight(.semibold)
                        
                        Text("Tap the '+' button to write your first journal entry.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                } else {
                    List {
                        ForEach(repository.entries) { entry in
                            Button(action: {
                                selectedEntry = entry
                            }) {
                                HStack(spacing: 12) {
                                    if let imageUrlString = entry.imageUrl,
                                       let imageUrl = URL(string: imageUrlString) {
                                        AsyncImage(url: imageUrl) { image in
                                            image
                                                .resizable()
                                                .scaledToFill()
                                        } placeholder: {
                                            Color.gray.opacity(0.1)
                                        }
                                        .frame(width: 60, height: 60)
                                        .cornerRadius(8)
                                        .clipped()
                                    }
                                    
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(entry.title)
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text(entry.content)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                            .multilineTextAlignment(.leading)
                                        
                                        Text(entry.createdAt, style: .date)
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        .onDelete(perform: deleteEntries)
                    }
                }
            }
            .navigationTitle("My Journal")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out") {
                        performSignOut()
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        isShowingAddEntry = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isShowingAddEntry) {
                NewEntryView(isPresented: $isShowingAddEntry) {
                    Task {
                        await fetchEntries()
                    }
                }
            }
            .sheet(item: $selectedEntry) { entry in
                EditEntryView(entry: entry) { title, content, newImageData in
                    if let newImageData = newImageData {
                        try await JournalRepository.shared.uploadPhotoAndUpdateEntry(
                            id: entry.id,
                            title: title,
                            content: content,
                            imageData: newImageData
                        )
                    } else {
                        try await JournalRepository.shared.updateEntry(
                            id: entry.id,
                            title: title,
                            content: content,
                            imageUrl: entry.imageUrl
                        )
                    }
                    await fetchEntries()
                }
            }
            .alert(isPresented: $showAlert) {
                Alert(title: Text("Journal Alert"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
            }
            .task {
                await fetchEntries()
                await repository.observeRealtimeChanges()
            }
        }
    }
    
    private func fetchEntries() async {
        isLoading = true
        do {
            try await repository.fetchMyEntries()
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
        isLoading = false
    }
    
    private func deleteEntries(at offsets: IndexSet) {
        let entriesToDelete = offsets.map { repository.entries[$0] }
        
        // Optimistically remove from UI
        repository.entries.remove(atOffsets: offsets)
        
        Task {
            do {
                for entry in entriesToDelete {
                    try await JournalRepository.shared.deleteEntry(id: entry.id)
                }
            } catch {
                alertMessage = error.localizedDescription
                showAlert = true
                // Re-fetch to sync UI if deletion failed
                await fetchEntries()
            }
        }
    }
    
    private func performSignOut() {
        Task { @MainActor in
            do {
                try await SupabaseManager.shared.client.auth.signOut()
                AuthService.shared.isAuthenticated = false
            } catch {
                alertMessage = error.localizedDescription
                showAlert = true
            }
        }
    }
}

struct EditEntryView: View {
    let entry: JournalEntry
    @Environment(\.dismiss) var dismiss
    var onSave: (String, String, Data?) async throws -> Void
    
    @State private var title: String
    @State private var content: String
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var existingImageUrl: String? = nil
    @State private var isSaving = false
    @State private var errorMessage = ""
    
    init(entry: JournalEntry, onSave: @escaping (String, String, Data?) async throws -> Void) {
        self.entry = entry
        self.onSave = onSave
        _title = State(initialValue: entry.title)
        _content = State(initialValue: entry.content)
        _existingImageUrl = State(initialValue: entry.imageUrl)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Title")) {
                    TextField("Enter entry title", text: $title)
                }
                
                Section(header: Text("Content")) {
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                }
                
                Section(header: Text("Photo")) {
                    PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text(selectedImage == nil && existingImageUrl == nil ? "Select Photo" : "Change Photo")
                        }
                    }
                    .onChange(of: selectedItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                await MainActor.run {
                                    self.selectedImage = uiImage
                                    self.existingImageUrl = nil // Clear existing photo preview since we picked a new one
                                }
                            }
                        }
                    }
                    
                    if let selectedImage = selectedImage {
                        Image(uiImage: selectedImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .cornerRadius(8)
                            .padding(.vertical, 4)
                    } else if let imageUrlString = existingImageUrl,
                              let imageUrl = URL(string: imageUrlString) {
                        AsyncImage(url: imageUrl) { image in
                            image
                                .resizable()
                                .scaledToFit()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(maxHeight: 200)
                        .cornerRadius(8)
                        .padding(.vertical, 4)
                    }
                }
                
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Edit Entry")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    ZStack {
                        Color(.systemBackground).opacity(0.8)
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Saving changes...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        saveEntry()
                    }
                    .disabled(isSaving || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveEntry() {
        isSaving = true
        errorMessage = ""
        
        Task { @MainActor in
            do {
                let newImageData = selectedImage?.jpegData(compressionQuality: 0.8)
                try await onSave(title, content, newImageData)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
