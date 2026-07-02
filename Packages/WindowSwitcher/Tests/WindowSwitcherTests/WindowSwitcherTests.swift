import Testing
@testable import WindowSwitcher

@Test func displayTitleFallsBackToAppName() {
    let info = WindowInfo(id: 1, pid: 1, appName: "Safari", bundleID: nil,
                          title: "", bounds: .zero, icon: nil, isMinimized: false)
    #expect(info.displayTitle == "Safari")
}

@Test func displayTitlePrefersTitleWhenPresent() {
    let info = WindowInfo(id: 1, pid: 1, appName: "Safari", bundleID: nil,
                          title: "Apple", bounds: .zero, icon: nil, isMinimized: false)
    #expect(info.displayTitle == "Apple")
}
