import Foundation

protocol AdsBackend {
    var isLive: Bool { get }
    func loadSnapshot() async throws -> AccountSnapshot
    func apply(changes: [StagedChange], draft: DraftCampaign?, launchLive: Bool) async throws
}

// Sample mode: AppState mutates its local copy after a (always-successful) apply.
struct SampleBackend: AdsBackend {
    var isLive: Bool { false }

    func loadSnapshot() async throws -> AccountSnapshot { SampleData.snapshot }

    func apply(changes: [StagedChange], draft: DraftCampaign?, launchLive: Bool) async throws {
        try await Task.sleep(for: .milliseconds(600))   // feel the launch
    }
}
