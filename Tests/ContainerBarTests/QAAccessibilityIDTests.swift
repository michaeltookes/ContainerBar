import Foundation
import Testing
@testable import ContainerBar
@testable import ContainerBarCore

/// Pure-helper coverage for the QA-hooks identifiers (CB-107, CB-056 pattern):
/// every helper-built identifier has one test, and container-scoped identifiers
/// share the card's slug for any name, including characters outside the slug
/// alphabet. No view hosting.
@MainActor
@Suite("QA accessibility identifiers")
struct QAAccessibilityIDTests {

    @Test("Fixed identifiers match the QA recipe contract")
    func fixedIdentifiers() {
        #expect(QAAccessibilityID.statusItem == "containerBarStatusItem")
        #expect(QAAccessibilityID.connectionStatus == "connectionStatus")
        #expect(QAAccessibilityID.logsPanelText == "logsPanelText")
        #expect(QAAccessibilityID.checkForUpdatesGeneral == "checkForUpdates-general")
        #expect(QAAccessibilityID.checkForUpdatesAbout == "checkForUpdates-about")
        #expect(QAAccessibilityID.autoCheckUpdatesToggle == "autoCheckUpdatesToggle")
        #expect(QAAccessibilityID.showStoppedToggle == "showStoppedToggle")
        #expect(QAAccessibilityID.addSectionButton == "addSectionButton")
    }

    @Test("Card identifier keeps the existing containerCard-<slug> form")
    func cardIdentifier() {
        #expect(QAAccessibilityID.containerCard("cbqa-target") == "containerCard-cbqa-target")
        #expect(QAAccessibilityID.containerCard("My Service") == "containerCard-my-service")
        #expect(QAAccessibilityID.containerCard("team/api") == "containerCard-team-api")
    }

    @Test("Stop identifier is containerStop-<slug>")
    func stopIdentifier() {
        #expect(QAAccessibilityID.containerStop("cbqa-target") == "containerStop-cbqa-target")
    }

    @Test("Start identifier is containerStart-<slug>")
    func startIdentifier() {
        #expect(QAAccessibilityID.containerStart("cbqa-stopped") == "containerStart-cbqa-stopped")
    }

    @Test("Logs-panel row identifier is logs-panel-container-<slug>, not the container id")
    func logsPanelRowIdentifier() {
        #expect(QAAccessibilityID.logsPanelRow("cbqa-logs") == "logs-panel-container-cbqa-logs")
    }

    @Test("Section row identifier is sectionRow-<slug>-<uuid>")
    func sectionRowIdentifier() throws {
        let id = try #require(UUID(uuidString: "F1A7E000-0000-4000-8000-000000000002"))
        #expect(
            QAAccessibilityID.sectionRow(name: "QA Fixtures", id: id) ==
                "sectionRow-qa-fixtures-f1a7e000-0000-4000-8000-000000000002"
        )
    }

    @Test(
        "Card, quick actions, and logs row share one slug for any name",
        arguments: ["cbqa_Odd.Name", "cbqa-target", "Web Server", "org/app:v2", "ÄPI Gateway"]
    )
    func slugIsSharedAcrossContainerIdentifiers(name: String) {
        let slug = QAAccessibilityID.containerSlug(name)
        #expect(!slug.isEmpty)
        #expect(QAAccessibilityID.containerCard(name) == "containerCard-\(slug)")
        #expect(QAAccessibilityID.containerStop(name) == "containerStop-\(slug)")
        #expect(QAAccessibilityID.containerStart(name) == "containerStart-\(slug)")
        #expect(QAAccessibilityID.logsPanelRow(name) == "logs-panel-container-\(slug)")
    }

    @Test("Odd-character names produce the documented slug")
    func oddNameSlug() {
        #expect(QAAccessibilityID.containerSlug("cbqa_Odd.Name") == "cbqa_odd.name")
    }

    @Test("connectionStatus label names the host when connected")
    func connectionStatusConnectedLabel() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "QA Runtime",
            isConnected: true,
            isRefreshing: false,
            connectionError: nil
        )
        #expect(presentation.accessibilityLabel == "Connected to QA Runtime")
    }

    @Test("connectionStatus label carries the error text when the runtime is unreachable")
    func connectionStatusErrorLabel() {
        let presentation = ConnectionStatusPresentation.make(
            hostName: "QA Runtime",
            isConnected: false,
            isRefreshing: false,
            connectionError: "  Connection refused  "
        )
        #expect(presentation.accessibilityLabel == "Connection failed for QA Runtime. Connection refused")
    }
}
