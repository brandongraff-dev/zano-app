import Testing
@testable import Core

@Test func coreVersionIsSet() {
    #expect(!ZanoCore.version.isEmpty)
}
