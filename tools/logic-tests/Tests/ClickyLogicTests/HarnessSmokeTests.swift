import Testing

struct HarnessSmokeTests {
    @Test func harnessRuns() {
        #expect(1 + 1 == 2)
    }
}
