import Foundation

protocol AdsBackend {
    var isLive: Bool { get }
    func loadSnapshot() async throws -> AccountSnapshot
    func apply(_ plan: ChangePlan) async throws -> ApplyReport
    func pages() async throws -> [PageInfo]
    func accounts() async throws -> [AccountInfo]
    /// Per-ad 14-day performance for the Analyst (capped for rate limits).
    func adPerformance() async throws -> [AdPerf]
}

// Sample mode: AppState mutates its local copy after a (always-successful) apply.
struct SampleBackend: AdsBackend {
    var isLive: Bool { false }

    func loadSnapshot() async throws -> AccountSnapshot { SampleData.snapshot }

    func apply(_ plan: ChangePlan) async throws -> ApplyReport {
        try await Task.sleep(for: .milliseconds(600))   // feel the launch
        return ApplyReport()
    }

    func pages() async throws -> [PageInfo] {
        [PageInfo(id: "108880123456", name: "Lumio Skincare", category: "Beauty brand")]
    }

    func accounts() async throws -> [AccountInfo] {
        [AccountInfo(id: SampleData.account.accountId, name: SampleData.account.name, currency: "IDR")]
    }

    func adPerformance() async throws -> [AdPerf] { SampleData.adPerf() }
}
