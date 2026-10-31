import Combine
import Foundation
import TypeCarrierCore

/// A draft belongs to one record until an explicit save or discard succeeds.
@MainActor
final class ReceivedRecordEditor: ObservableObject {
    @Published private(set) var recordID: UUID?
    @Published private(set) var targetRecord: CarrierRecord?
    @Published var draft = ""
    @Published private(set) var saveError: String?
    private var originalText = ""

    var hasChanges: Bool { recordID != nil && draft != originalText }

    func begin(_ record: CarrierRecord) {
        targetRecord = record
        recordID = record.id
        originalText = record.text
        draft = record.text
        saveError = nil
    }

    @discardableResult
    func save(persist: (UUID, String) -> Bool, failureMessage: () -> String) -> Bool {
        guard let recordID else { return true }
        if hasChanges, !persist(recordID, draft) {
            saveError = failureMessage()
            return false
        }
        discard()
        return true
    }

    func discard() {
        recordID = nil
        targetRecord = nil
        originalText = ""
        draft = ""
        saveError = nil
    }
}
