import SwiftUI
import PhotosUI

struct NewEntryView: View {
    @Binding var isPresented: Bool
    var onSaveComplete: () -> Void
    
    @State private var title = ""
    @State private var content = ""
    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var isSaving = false
    @State private var errorMessage = ""
    
    // AI Analysis States
    @State private var isAnalyzing = false
    @State private var sentimentResult: String? = nil
    @State private var aiSummaryResult: String? = nil
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Title")) {
                    TextField("Enter entry title", text: $title)
                }
                
                Section(header: Text("Content")) {
                    TextEditor(text: $content)
                        .frame(minHeight: 150)
                    
                    HStack {
                        Button(action: analyzeContent) {
                            if isAnalyzing {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Analyzing...")
                                }
                            } else {
                                HStack(spacing: 8) {
                                    Image(systemName: "sparkles")
                                    Text("Analyze with AI")
                                }
                            }
                        }
                        .disabled(isAnalyzing || content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        
                        Spacer()
                        
                        if let sentiment = sentimentResult {
                            Text(sentiment)
                                .font(.caption)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(sentimentColor(sentiment: sentiment))
                                .cornerRadius(12)
                        }
                    }
                    .padding(.vertical, 4)
                    
                    if let summary = aiSummaryResult {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AI SUMMARY")
                                .font(.caption2)
                                .fontWeight(.semibold)
                                .foregroundColor(.secondary)
                            
                            Text(summary)
                                .font(.footnote)
                                .foregroundColor(.primary)
                        }
                        .padding(.top, 4)
                    }
                }
                
                Section(header: Text("Photo (Optional)")) {
                    PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                        HStack {
                            Image(systemName: "photo.on.rectangle")
                            Text(selectedImage == nil ? "Select Photo" : "Change Photo")
                        }
                    }
                    .onChange(of: selectedItem) { newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                await MainActor.run {
                                    self.selectedImage = uiImage
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
                    }
                }
                
                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .disabled(isSaving)
            .overlay {
                if isSaving {
                    ZStack {
                        Color(.systemBackground).opacity(0.8)
                        VStack(spacing: 12) {
                            ProgressView()
                                .scaleEffect(1.5)
                            Text("Saving entry & uploading image...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") {
                        isPresented = false
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
    
    private func analyzeContent() {
        isAnalyzing = true
        errorMessage = ""
        
        Task { @MainActor in
            do {
                let result = try await JournalRepository.shared.analyzeJournalContent(text: content)
                self.sentimentResult = result.sentiment
                self.aiSummaryResult = result.aiSummary
            } catch {
                errorMessage = error.localizedDescription
            }
            isAnalyzing = false
        }
    }
    
    private func sentimentColor(sentiment: String) -> Color {
        switch sentiment {
        case "Positive":
            return .green
        case "Negative":
            return .red
        default:
            return .gray
        }
    }
    
    private func saveEntry() {
        isSaving = true
        errorMessage = ""
        
        Task { @MainActor in
            do {
                if let selectedImage = selectedImage,
                   let imageData = selectedImage.jpegData(compressionQuality: 0.8) {
                    // Upload photo and create entry
                    try await JournalRepository.shared.uploadPhotoAndCreateEntry(
                        title: title,
                        content: content,
                        imageData: imageData
                    )
                } else {
                    // Create entry without photo
                    try await JournalRepository.shared.insertEntry(
                        title: title,
                        content: content
                    )
                }
                onSaveComplete()
                isPresented = false
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
