import Foundation

// Manages a private Python venv with Meta's `meta-ads` CLI installed
// (~/Library/Application Support/Pacer/venv). The CLI needs Python ≥ 3.12.

enum SidecarError: LocalizedError {
    case pythonMissing
    case installFailed(String)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .pythonMissing:
            return "Python 3.12+ not found. Install it with `brew install python` and retry."
        case .installFailed(let s): return "Installing meta-ads failed: \(s)"
        case .commandFailed(let s): return s
        }
    }
}

final class Sidecar: @unchecked Sendable {
    static let shared = Sidecar()

    private let supportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MadMac", isDirectory: true)
    private var venvDir: URL { supportDir.appendingPathComponent("venv", isDirectory: true) }
    private var metaBin: URL { venvDir.appendingPathComponent("bin/meta") }

    var isInstalled: Bool { FileManager.default.isExecutableFile(atPath: metaBin.path) }

    private func findPython() -> String? {
        // meta-ads 1.0.1 ships compiled wheels for CPython 3.12/3.13 only, so
        // prefer those over a newer generic python3 (3.14 has no wheel).
        let candidates = [
            "/opt/homebrew/bin/python3.13", "/opt/homebrew/bin/python3.12",
            "/usr/local/bin/python3.13", "/usr/local/bin/python3.12",
            "/opt/homebrew/bin/python3", "/usr/local/bin/python3", "/usr/bin/python3",
        ]
        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            if let out = try? runProcess(path, ["-c", "import sys; print((3,12) <= sys.version_info < (3,14))"], env: [:]),
               out.trimmingCharacters(in: .whitespacesAndNewlines) == "True" {
                return path
            }
        }
        return nil
    }

    func ensureInstalled(progress: @escaping @Sendable (String) -> Void) async throws {
        if isInstalled { return }
        guard let python = findPython() else { throw SidecarError.pythonMissing }
        try FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)
        progress("Creating Python environment…")
        do {
            _ = try runProcess(python, ["-m", "venv", venvDir.path], env: [:])
            progress("Installing meta-ads CLI…")
            _ = try runProcess(venvDir.appendingPathComponent("bin/pip").path,
                               ["install", "--quiet", "meta-ads"], env: [:], timeout: 300)
        } catch {
            throw SidecarError.installFailed(error.localizedDescription)
        }
        guard isInstalled else { throw SidecarError.installFailed("meta executable missing after install") }
    }

    // Run `meta <args>` with credentials in the environment, return stdout.
    func meta(_ args: [String], credentials: Credentials) async throws -> String {
        try await ensureInstalled(progress: { _ in })
        let env = [
            "ACCESS_TOKEN": credentials.accessToken,
            "META_ACCESS_TOKEN": credentials.accessToken,
            "AD_ACCOUNT_ID": credentials.actId,
            "META_AD_ACCOUNT_ID": credentials.actId,
        ]
        let bin = metaBin.path
        let task = Task.detached { [weak self] () -> String in
            guard let self else { throw SidecarError.commandFailed("sidecar gone") }
            return try self.runProcess(bin, args, env: env, timeout: 120)
        }
        return try await task.value
    }

    @discardableResult
    private func runProcess(_ launchPath: String, _ args: [String],
                            env extra: [String: String], timeout: TimeInterval = 60) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = "\(venvDir.path)/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        for (k, v) in extra { env[k] = v }
        p.environment = env
        let out = Pipe(), err = Pipe()
        p.standardOutput = out
        p.standardError = err
        try p.run()

        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.05)
        }
        if p.isRunning {
            p.terminate()
            throw SidecarError.commandFailed("`\(launchPath.components(separatedBy: "/").last ?? "") \(args.prefix(3).joined(separator: " "))…` timed out")
        }
        let stdout = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard p.terminationStatus == 0 else {
            let msg = stderr.isEmpty ? stdout : stderr
            throw SidecarError.commandFailed(String(msg.suffix(500)))
        }
        return stdout
    }
}
