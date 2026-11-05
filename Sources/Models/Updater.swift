import AppKit
import CryptoKit

/// Installs a release over the running app: downloads `MacMonitor.zip`, checks it against
/// `MacMonitor.zip.sha256`, checks the app inside, swaps it in and relaunches. MacMonitor is not
/// notarized, so the signature only shows that the app is intact, not who built it.
/// Stays off the main actor so it can be tested before the app starts, without any window.
enum Updater {
    enum Failure: Error {
        case missingFiles
        case http(Int)
        case unreadableChecksum
        case checksumMismatch
        case unpackFailed
        case wrongApp
        case badSignature
        case notWritable(folder: String, reason: String)
    }

    /// False when the app sits where this user cannot write: installed by another user, a standard
    /// account, a translocated or read-only copy. The update is then offered as a download page.
    static var canReplaceApp: Bool {
        let fm = FileManager.default
        let app = Bundle.main.bundleURL
        return app.pathExtension == "app" && fm.isWritableFile(atPath: app.path)
            && fm.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    /// On return the new app is in place; the old one keeps running until `relaunch()`
    static func install(_ release: UpdateChecker.Release) async throws {
        guard let archive = release.archive, let checksum = release.checksum else { throw Failure.missingFiles }
        let (checksumFile, checksumResponse) = try await URLSession.shared.data(from: checksum)
        try requireSuccess(checksumResponse)
        guard let expected = UpdateChecker.parseChecksum(String(decoding: checksumFile, as: UTF8.self)) else {
            throw Failure.unreadableChecksum
        }
        let (downloaded, response) = try await URLSession.shared.download(from: archive)
        try requireSuccess(response)
        try Task.checkCancellation()

        let fm = FileManager.default
        let current = Bundle.main.bundleURL
        // Next to the app, on the same volume, so the swap is a rename and not a copy
        let base = (try? fm.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                appropriateFor: current, create: true)) ?? fm.temporaryDirectory
        let work = base.appendingPathComponent("MacMonitor-update-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer {
            try? fm.removeItem(at: work)
            if base != fm.temporaryDirectory { try? fm.removeItem(at: base) }
        }
        let zip = work.appendingPathComponent(UpdateChecker.archiveName)
        try fm.moveItem(at: downloaded, to: zip)

        let app = try verified(zip, expected: expected, version: release.version, in: work)
        try Task.checkCancellation()
        do {
            _ = try fm.replaceItemAt(current, withItemAt: app)
        } catch {
            throw Failure.notWritable(folder: current.deletingLastPathComponent().path, reason: error.localizedDescription)
        }
    }

    private static func requireSuccess(_ response: URLResponse) throws {
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw Failure.http(http.statusCode) }
    }

    /// Unpacks the zip and returns the app inside it, ready to install
    private static func verified(_ zip: URL, expected: String, version: String, in work: URL) throws -> URL {
        let digest = SHA256.hash(data: try Data(contentsOf: zip, options: .mappedIfSafe))
        guard digest.map({ String(format: "%02x", $0) }).joined() == expected else { throw Failure.checksumMismatch }

        let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) else { throw Failure.unpackFailed }
        // The zip holds a MacMonitor folder with the app and the license text
        let app = unpacked.appendingPathComponent("MacMonitor/MacMonitor.app", isDirectory: true)
        guard let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == version else {
            throw Failure.wrongApp
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) else { throw Failure.badSignature }
        // The user has just approved this update; macOS need not ask again
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = arguments
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// Leaves a small shell job that opens the new app once this one has quit, then quits.
    /// Quitting normally writes out the pending battery samples.
    @MainActor
    static func relaunch() {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                       Bundle.main.bundleURL.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    #if DEBUG
    /// MACMONITOR_UPDATE_TEST=1: checks and installs without a window, prints the result and
    /// exits. Runs before the app starts, so nothing appears on screen.
    static func runSelfTestIfRequested() {
        guard ProcessInfo.processInfo.environment["MACMONITOR_UPDATE_TEST"] != nil else { return }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let result: String
            switch await UpdateChecker.check() {
            case .newer(let release):
                do {
                    try await install(release)
                    result = "installed \(release.version)\nwhatsNew: \(UpdateChecker.whatsNew(in: release.notes, turkish: false))"
                } catch {
                    result = "refused \(release.version): \(error)"
                }
            case .upToDate(let version): result = "upToDate \(version)"
            case .failed(let reason): result = "failed: \(reason)"
            }
            FileHandle.standardError.write(Data("update test: \(result)\n".utf8))
            done.signal()
        }
        done.wait()
        exit(0)
    }
    #endif
}
