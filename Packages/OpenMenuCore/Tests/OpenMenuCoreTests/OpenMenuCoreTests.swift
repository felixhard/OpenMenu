import Testing
@testable import OpenMenuCore

@Test func bundlePrefixIsStable() {
    #expect(OpenMenu.bundleIDPrefix == "software.openmenu")
}
