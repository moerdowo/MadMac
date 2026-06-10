import SwiftUI

// Debug helper: `Pacer.app/Contents/MacOS/Pacer --snapshot /tmp/dir` renders
// the key screens to PNG and exits. Used to verify the UI against the design
// without a live window capture.

@MainActor
enum SnapshotRunner {
    static private(set) var isActive = false

    static func runIfRequested() {
        guard let idx = CommandLine.arguments.firstIndex(of: "--snapshot") else { return }
        isActive = true
        let dir = CommandLine.arguments.count > idx + 1 ? CommandLine.arguments[idx + 1] : "/tmp/pacer_shots"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let prefs = Prefs()

        func shot(_ name: String, dark: Bool = false, configure: (AppState) -> Void) {
            let state = AppState()
            state.switchToSample()
            configure(state)
            let view = RootView()
                .environmentObject(state)
                .environmentObject(prefs)
                .environment(\.colorScheme, dark ? .dark : .light)
                .frame(width: 1320, height: 840)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
            }
        }

        prefs.dashLayout = .overview
        shot("01-performance-overview") { $0.section = .performance }
        prefs.dashLayout = .spotlight
        shot("02-performance-spotlight") { $0.section = .performance }
        prefs.dashLayout = .table
        shot("03-performance-table") { $0.section = .performance }
        prefs.dashLayout = .overview
        shot("04-campaigns") { $0.section = .campaigns }
        shot("05-review-sheet") { state in
            state.section = .campaigns
            if let c = state.campaigns.first {
                state.pending[c.id] = .paused
                if let ad = c.adsets.first?.ads.last {
                    state.pending[ad.id] = .active
                }
            }
            state.draft = DraftCampaign()
            state.reviewOpen = true
        }
        shot("06-create-wizard") { state in
            state.section = .campaigns
            state.createOpen = true
        }
        shot("07-drawer") { state in
            state.section = .campaigns
            state.drawerCampaignID = state.campaigns.first?.id
        }
        shot("08-diagnostics") { $0.section = .diagnostics }
        shot("09-catalog") { $0.section = .catalog }
        shot("10-datasets") { $0.section = .datasets }
        shot("11-dark-overview", dark: true) { $0.section = .performance }
        shot("12-dark-campaigns", dark: true) { $0.section = .campaigns }
        shot("13-connect", ) { state in
            state.section = .performance
            state.connectOpen = true
        }
        exit(0)
    }
}
