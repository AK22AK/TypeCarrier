import XCTest
@testable import TypeCarrierCore

final class DeviceNamePreferenceTests: XCTestCase {
    func testSystemNamePrefillAndWhitespaceEditsCannotCreateAnOverride() {
        var editor = DeviceNameEditState()
        editor.begin(effectiveName: "System Mac", hasCustomName: false)
        XCTAssertEqual(editor.draft, "System Mac")
        XCTAssertFalse(editor.canSave)
        editor.draft = "  System Mac \n"
        XCTAssertFalse(editor.canSave)
        XCTAssertNil(editor.savedName())
        editor.draft = " \n "
        XCTAssertFalse(editor.canSave)
        XCTAssertNil(editor.savedName())
    }

    func testChangedSaveTrimsAndBlankCustomSaveClearsExplicitly() {
        var editor = DeviceNameEditState()
        editor.begin(effectiveName: "Old", hasCustomName: true)
        editor.draft = " New "
        XCTAssertEqual(editor.savedName(), "New")
        XCTAssertFalse(editor.isEditing)
        editor.begin(effectiveName: "System Mac", hasCustomName: true)
        XCTAssertFalse(editor.canSave, "A custom name matching the system text keeps its source")
        editor.draft = " \n "
        XCTAssertEqual(editor.savedName(), "")
        XCTAssertFalse(editor.isEditing)
    }

    func testCancelAndReentryDiscardUnsavedDraft() {
        var editor = DeviceNameEditState()
        editor.begin(effectiveName: "Saved", hasCustomName: true)
        editor.draft = "Unsaved"
        editor.cancel()
        XCTAssertFalse(editor.isEditing)
        XCTAssertEqual(editor.draft, "")
        XCTAssertNil(editor.savedName())
        editor.begin(effectiveName: "Saved", hasCustomName: true)
        XCTAssertEqual(editor.draft, "Saved")
        XCTAssertFalse(editor.canSave)
    }

    func testSystemSelectionStaysPendingUntilSaveAndCancelDropsIt() {
        var editor = DeviceNameEditState()
        editor.begin(effectiveName: "Custom", hasCustomName: true)
        editor.selectSystemName("System Mac")
        XCTAssertTrue(editor.isEditing)
        XCTAssertEqual(editor.draft, "System Mac")
        XCTAssertEqual(editor.pendingSource, .system)
        XCTAssertTrue(editor.canSave)
        editor.cancel()
        XCTAssertNil(editor.savedName())
        editor.begin(effectiveName: "Custom", hasCustomName: true)
        XCTAssertEqual(editor.draft, "Custom")
        XCTAssertEqual(editor.pendingSource, .custom)
    }

    func testSameTextDifferentSourceCanSaveAndClearsOverride() {
        var editor = DeviceNameEditState()
        editor.begin(effectiveName: "System Mac", hasCustomName: true)
        editor.selectSystemName("System Mac")
        XCTAssertTrue(editor.canSave)
        XCTAssertEqual(editor.savedName(), "")
        editor.begin(effectiveName: "System Mac", hasCustomName: false)
        editor.selectSystemName("System Mac")
        XCTAssertFalse(editor.canSave)
    }

    func testEditingAfterSystemChoiceUsesFinalNormalizedText() {
        var editor = DeviceNameEditState()
        editor.begin(effectiveName: "Custom", hasCustomName: true)
        editor.selectSystemName("System")
        editor.draft = "  New Name  "
        XCTAssertEqual(editor.pendingSource, .custom)
        XCTAssertEqual(editor.savedName(), "New Name")
        editor.begin(effectiveName: "Custom", hasCustomName: true)
        editor.selectSystemName("System")
        editor.draft = "Other"
        editor.draft = " System "
        XCTAssertEqual(editor.pendingSource, .system)
        XCTAssertEqual(editor.savedName(), "")
    }

    func testTrimPersistenceAndResetLeaveOtherPreferencesUntouched() throws {
        let suite = "DeviceNameTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("stable-test-device", forKey: "identity")
        defaults.set("test-pairing-value", forKey: "pairing")
        let preference = DeviceNamePreference(defaults: defaults, key: "name")
        XCTAssertEqual(preference.save("  书房 Mac \n"), "书房 Mac")
        XCTAssertEqual(DeviceNamePreference(defaults: defaults, key: "name").customName, "书房 Mac")
        let longName = String(repeating: "完整名称🙂", count: 50)
        preference.save(longName)
        XCTAssertEqual(preference.customName, longName)
        preference.save(" \n ")
        XCTAssertNil(defaults.object(forKey: "name"))
        XCTAssertEqual(defaults.string(forKey: "identity"), "stable-test-device")
        XCTAssertEqual(defaults.string(forKey: "pairing"), "test-pairing-value")
    }

    func testSystemFallbackAndMacFallbackAreResolvedFromCurrentValues() {
        XCTAssertEqual(CarrierDeviceIdentity.preferredDisplayName(customName: "  ", systemName: " New Mac ", fallbackName: "TypeCarrier Mac"), "New Mac")
        XCTAssertEqual(CarrierDeviceIdentity.preferredDisplayName(customName: nil, systemName: " ", fallbackName: "TypeCarrier Mac"), "TypeCarrier Mac")
        XCTAssertEqual(CarrierDeviceIdentity.preferredDisplayName(customName: " Work ", systemName: "System"), "Work")
    }

    func testTransportAliasIsNonemptyAndDoesNotSplitUnicodeCharacters() {
        for name in ["", String(repeating: "书房🙂", count: 30), String(repeating: "👨‍👩‍👧‍👦", count: 8)] {
            let alias = CarrierDeviceIdentity.multipeerDisplayName(name)
            XCTAssertFalse(alias.isEmpty)
            XCTAssertLessThanOrEqual(alias.utf8.count, 63)
            XCTAssertTrue(name.isEmpty || name.hasPrefix(alias))
        }
    }

    func testDiscoveryUsesActualTXTEntryCapacityAndFallsBackSafely() throws {
        let limit = 255 - AndroidBonjourAdvertisement.macNameKey.utf8.count - 1
        let fits = String(repeating: "n", count: limit)
        XCTAssertEqual(AndroidBonjourAdvertisement.discoveryInfo(macID: "id", macName: fits, port: 17641)["macName"], fits)
        let oversized = String(repeating: "名", count: 100)
        let data = AndroidBonjourAdvertisement.txtRecordData(macID: "id", macName: oversized)
        let nameData = try XCTUnwrap(AndroidBonjourAdvertisement.txtRecordDictionary(from: data)["macName"])
        XCTAssertLessThanOrEqual(nameData.count + "macName=".utf8.count, 255)
        XCTAssertEqual(String(data: nameData, encoding: .utf8), CarrierDeviceIdentity.multipeerDisplayName(oversized))
        XCTAssertEqual(AndroidBonjourAdvertisement.discoveryInfo(macID: "id", macName: oversized, port: 17641)["macID"], "id")
    }
}
