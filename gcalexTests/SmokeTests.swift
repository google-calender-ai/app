import Testing
@testable import gcalex

struct SmokeTests {
    @Test @MainActor func rootViewBuilds() {
        _ = RootView()
    }
}
