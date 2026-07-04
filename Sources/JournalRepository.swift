import Foundation
import Supabase

struct JournalEntry: Codable, Identifiable {
    var id: UUID
    var userId: UUID
    var title: String
    var content: String
    var imageUrl: String?
    var createdAt: Date
    
    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case content
        case imageUrl = "image_url"
        case createdAt = "created_at"
    }
    
    // Memberwise initializer
    init(id: UUID, userId: UUID, title: String, content: String, imageUrl: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.userId = userId
        self.title = title
        self.content = content
        self.imageUrl = imageUrl
        self.createdAt = createdAt
    }
    
    // Custom Decoder to handle ISO8601 date formats returned by PostgREST and Realtime
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        userId = try container.decode(UUID.self, forKey: .userId)
        title = try container.decode(String.self, forKey: .title)
        content = try container.decode(String.self, forKey: .content)
        imageUrl = try container.decodeIfPresent(String.self, forKey: .imageUrl)
        
        let dateString = try container.decode(String.self, forKey: .createdAt)
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]
        
        let fractionalFormatter = ISO8601DateFormatter()
        fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        
        // Custom lenient date formatter in case database returns timezone formats like "+00" or spaces
        let customFormatter = DateFormatter()
        customFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSSSSZ"
        
        let customFormatter2 = DateFormatter()
        customFormatter2.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSZZZZZ"
        
        let customFormatter3 = DateFormatter()
        customFormatter3.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZ"
        
        if let date = isoFormatter.date(from: dateString) ??
                      fractionalFormatter.date(from: dateString) ??
                      customFormatter.date(from: dateString) ??
                      customFormatter2.date(from: dateString) ??
                      customFormatter3.date(from: dateString) {
            createdAt = date
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .createdAt,
                in: container,
                debugDescription: "Date string \(dateString) does not match expected format."
            )
        }
    }
    
    // Custom Encoder to output ISO8601 date string for Supabase database operations
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(userId, forKey: .userId)
        try container.encode(title, forKey: .title)
        try container.encode(content, forKey: .content)
        try container.encodeIfPresent(imageUrl, forKey: .imageUrl)
        
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateString = isoFormatter.string(from: createdAt)
        try container.encode(dateString, forKey: .createdAt)
    }
}

@MainActor
final class JournalRepository: ObservableObject {
    static let shared = JournalRepository()
    
    @Published var entries: [JournalEntry] = []
    
    private var realtimeChannel: RealtimeChannelV2? = nil
    
    private init() {}
    
    /// Inserts a new journal entry automatically mapping it to the current authenticated user's ID.
    func insertEntry(title: String, content: String, imageUrl: String? = nil) async throws {
        let currentSession = try await SupabaseManager.shared.client.auth.session
        let userId = currentSession.user.id
        
        let entry = JournalEntry(
            id: UUID(),
            userId: userId,
            title: title,
            content: content,
            imageUrl: imageUrl,
            createdAt: Date()
        )
        
        do {
            try await SupabaseManager.shared.client
                .from("journal_entries")
                .insert(entry)
                .execute()
        } catch {
            throw NSError(
                domain: "JournalRepository",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Database insert failed: \(error.localizedDescription)"]
            )
        }
    }
    
    /// Fetches all journal entries for the current authenticated user.
    @discardableResult
    func fetchMyEntries() async throws -> [JournalEntry] {
        do {
            let fetched: [JournalEntry] = try await SupabaseManager.shared.client
                .from("journal_entries")
                .select()
                .execute()
                .value
            
            self.entries = fetched
            return fetched
        } catch {
            throw NSError(
                domain: "JournalRepository",
                code: 3,
                userInfo: [NSLocalizedDescriptionKey: "Fetch entries failed: \(error.localizedDescription)"]
            )
        }
    }
    
    /// Updates an existing journal entry by its ID.
    func updateEntry(id: UUID, title: String, content: String, imageUrl: String? = nil) async throws {
        var updateData: [String: String?] = [
            "title": title,
            "content": content
        ]
        if let imageUrl = imageUrl {
            updateData["image_url"] = imageUrl
        }
        
        do {
            try await SupabaseManager.shared.client
                .from("journal_entries")
                .update(updateData)
                .eq("id", value: id)
                .execute()
        } catch {
            throw NSError(
                domain: "JournalRepository",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: "Database update failed: \(error.localizedDescription)"]
            )
        }
    }
    
    /// Deletes a journal entry by its ID.
    func deleteEntry(id: UUID) async throws {
        try await SupabaseManager.shared.client
            .from("journal_entries")
            .delete()
            .eq("id", value: id)
            .execute()
    }
    
    /// Uploads an image to the 'journal_photos' bucket and creates a journal entry referencing it.
    func uploadPhotoAndCreateEntry(title: String, content: String, imageData: Data) async throws {
        let currentSession = try await SupabaseManager.shared.client.auth.session
        let userId = currentSession.user.id
        
        // Generate a unique path/filename
        let fileExtension = "jpg"
        let fileName = "\(userId.uuidString)/\(UUID().uuidString).\(fileExtension)"
        
        // Upload the image data
        do {
            try await SupabaseManager.shared.client.storage
                .from("journal_photos")
                .upload(
                    fileName,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg")
                )
        } catch {
            throw NSError(
                domain: "JournalRepository",
                code: 5,
                userInfo: [NSLocalizedDescriptionKey: "Storage upload failed: \(error.localizedDescription)"]
            )
        }
        
        // Get the public URL of the uploaded photo
        let publicURL: URL
        do {
            publicURL = try SupabaseManager.shared.client.storage
                .from("journal_photos")
                .getPublicURL(path: fileName)
        } catch {
            throw NSError(
                domain: "JournalRepository",
                code: 6,
                userInfo: [NSLocalizedDescriptionKey: "Get public URL failed: \(error.localizedDescription)"]
            )
        }
        
        // Create and insert the journal entry with the image URL
        try await insertEntry(title: title, content: content, imageUrl: publicURL.absoluteString)
    }
    
    /// Uploads a new photo to the storage bucket and updates the existing entry with the new URL.
    func uploadPhotoAndUpdateEntry(id: UUID, title: String, content: String, imageData: Data) async throws {
        let currentSession = try await SupabaseManager.shared.client.auth.session
        let userId = currentSession.user.id
        
        // Generate a unique path/filename
        let fileExtension = "jpg"
        let fileName = "\(userId.uuidString)/\(UUID().uuidString).\(fileExtension)"
        
        // Upload the new image data
        do {
            try await SupabaseManager.shared.client.storage
                .from("journal_photos")
                .upload(
                    fileName,
                    data: imageData,
                    options: FileOptions(contentType: "image/jpeg")
                )
        } catch {
            throw NSError(
                domain: "JournalRepository",
                code: 7,
                userInfo: [NSLocalizedDescriptionKey: "Storage update upload failed: \(error.localizedDescription)"]
            )
        }
        
        // Get the public URL of the uploaded photo
        let publicURL: URL
        do {
            publicURL = try SupabaseManager.shared.client.storage
                .from("journal_photos")
                .getPublicURL(path: fileName)
        } catch {
            throw NSError(
                domain: "JournalRepository",
                code: 8,
                userInfo: [NSLocalizedDescriptionKey: "Get update public URL failed: \(error.localizedDescription)"]
            )
        }
        
        // Update the entry with new details and the new image URL
        try await updateEntry(id: id, title: title, content: content, imageUrl: publicURL.absoluteString)
    }
    
    /// Invokes the 'analyze-sentiment' Edge Function to analyze a journal entry's text content.
    func analyzeJournalContent(text: String) async throws -> (sentiment: String, aiSummary: String) {
        struct SentimentAnalysisResponse: Decodable {
            let sentiment: String
            let aiSummary: String
            
            enum CodingKeys: String, CodingKey {
                case sentiment
                case aiSummary = "ai_summary"
            }
        }
        
        let response = try await SupabaseManager.shared.client.functions.invoke(
            "analyze-sentiment",
            options: FunctionInvokeOptions(
                body: ["text": text]
            ),
            decode: { data, _ in
                if let rawString = String(data: data, encoding: .utf8) {
                    NSLog("Edge Function Raw Response: %@", rawString)
                } else {
                    NSLog("Edge Function Response could not be converted to UTF-8 String")
                }
                do {
                    return try JSONDecoder().decode(SentimentAnalysisResponse.self, from: data)
                } catch {
                    NSLog("Edge Function Decode Error: %@", error.localizedDescription)
                    throw error
                }
            }
        )
        return (response.sentiment, response.aiSummary)
    }
    
    /// Subscribes to the Supabase Realtime channel to listen to newly inserted journal entries live.
    func observeRealtimeChanges() async {
        guard realtimeChannel == nil else { return } // Avoid duplicate subscriptions
        
        let client = SupabaseManager.shared.client
        let channel = client.realtimeV2.channel("journal_entries_changes")
        self.realtimeChannel = channel
        
        let insertions = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "journal_entries"
        )
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            
            let isoFormatter = ISO8601DateFormatter()
            isoFormatter.formatOptions = [.withInternetDateTime]
            
            let fractionalFormatter = ISO8601DateFormatter()
            fractionalFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            
            if let date = isoFormatter.date(from: dateString) ?? fractionalFormatter.date(from: dateString) {
                return date
            }
            
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(dateString)")
        }
        
        await channel.subscribe()
        
        Task { [weak self] in
            for await change in insertions {
                do {
                    let newEntry = try change.decodeRecord(as: JournalEntry.self, decoder: decoder)
                    
                    // Verify if this entry belongs to the currently logged in user
                    let currentSession = try? await SupabaseManager.shared.client.auth.session
                    if let userId = currentSession?.user.id, newEntry.userId == userId {
                        await MainActor.run {
                            // Append if it doesn't already exist in the list
                            if let self = self, !self.entries.contains(where: { $0.id == newEntry.id }) {
                                self.entries.append(newEntry)
                            }
                        }
                    }
                } catch {
                    print("Error decoding realtime insert: \(error)")
                }
            }
        }
    }
}
