//
//  PersonNameSettingsTests.swift
//  RelayTests
//
//  RELAY-10 — Configurable per-person display names persisted to App-Group
//  UserDefaults. Every mutation must fire the injected `WidgetRefreshing`
//  so the widget extension picks up the change on its next reload cycle.
//

import XCTest
@testable import Relay

final class PersonNameSettingsTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "PersonNameSettingsTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    // MARK: - Defaults

    func test_nameA_isEmptyString_byDefault() {
        let sut = PersonNameSettings(defaults: defaults, widgetRefresher: SpyWidgetRefresher())
        XCTAssertEqual(sut.nameA, "")
    }

    func test_nameB_isEmptyString_byDefault() {
        let sut = PersonNameSettings(defaults: defaults, widgetRefresher: SpyWidgetRefresher())
        XCTAssertEqual(sut.nameB, "")
    }

    // MARK: - Persistence

    func test_settingNameA_persistsToDefaults() {
        let sut = PersonNameSettings(defaults: defaults, widgetRefresher: SpyWidgetRefresher())
        sut.nameA = "Casey"
        let fresh = PersonNameSettings(defaults: defaults, widgetRefresher: SpyWidgetRefresher())
        XCTAssertEqual(fresh.nameA, "Casey")
    }

    func test_settingNameB_persistsToDefaults() {
        let sut = PersonNameSettings(defaults: defaults, widgetRefresher: SpyWidgetRefresher())
        sut.nameB = "Avery"
        let fresh = PersonNameSettings(defaults: defaults, widgetRefresher: SpyWidgetRefresher())
        XCTAssertEqual(fresh.nameB, "Avery")
    }

    // MARK: - Widget refresh contract

    func test_settingNameA_firesWidgetRefresh() {
        let spy = SpyWidgetRefresher()
        let sut = PersonNameSettings(defaults: defaults, widgetRefresher: spy)
        sut.nameA = "Casey"
        XCTAssertEqual(spy.refreshCount, 1)
    }

    func test_settingNameB_firesWidgetRefresh() {
        let spy = SpyWidgetRefresher()
        let sut = PersonNameSettings(defaults: defaults, widgetRefresher: spy)
        sut.nameB = "Avery"
        XCTAssertEqual(spy.refreshCount, 1)
    }

    func test_settingSameValue_stillFiresRefresh() {
        // The widget refresh is cheap; iOS rate-limits widget reloads anyway.
        // Simpler to always fire than to compare prev/new.
        let spy = SpyWidgetRefresher()
        let sut = PersonNameSettings(defaults: defaults, widgetRefresher: spy)
        sut.nameA = "Casey"
        sut.nameA = "Casey"
        XCTAssertEqual(spy.refreshCount, 2)
    }

    // MARK: - displayName(for:) lookup

    func test_displayName_returnsPersonAPlaceholder_whenNameAEmpty() {
        let sut = PersonNameSettings(defaults: defaults, widgetRefresher: SpyWidgetRefresher())
        XCTAssertEqual(sut.displayName(for: .personA), "Person A")
    }

    func test_displayName_returnsPersonBPlaceholder_whenNameBEmpty() {
        let sut = PersonNameSettings(defaults: defaults, widgetRefresher: SpyWidgetRefresher())
        XCTAssertEqual(sut.displayName(for: .personB), "Person B")
    }

    func test_displayName_returnsConfiguredName_whenNameASet() {
        let sut = PersonNameSettings(defaults: defaults, widgetRefresher: SpyWidgetRefresher())
        sut.nameA = "Casey"
        XCTAssertEqual(sut.displayName(for: .personA), "Casey")
    }

    func test_displayName_returnsConfiguredName_whenNameBSet() {
        let sut = PersonNameSettings(defaults: defaults, widgetRefresher: SpyWidgetRefresher())
        sut.nameB = "Avery"
        XCTAssertEqual(sut.displayName(for: .personB), "Avery")
    }
}
