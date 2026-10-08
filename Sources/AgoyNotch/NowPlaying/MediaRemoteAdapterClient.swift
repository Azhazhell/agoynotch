//
//  MediaRemoteAdapterClient.swift
//  AgoyNotch
//
//  Runs the vendored mediaremote-adapter as a child process
//  (`/usr/bin/perl mediaremote-adapter.pl MediaRemoteAdapter.framework stream --debounce=100`)
//  and turns its JSON lines into `AdapterSnapshot`s. Since macOS 15.4 apps cannot read
//  MediaRemote directly; the Apple-signed perl binary still can, so the helper reports Now
//  Playing from every app (Music, Spotify, TV, browsers).
//
//  Foundation only (no AppKit, no app types), so the Linux harness can drive it with a fake
//  executable.
//
//  THREADING: all mutable state is confined to the private serial `queue`, which never
//  blocks on or waits for the main thread. Callbacks run on `queue`, one at a time.
//

import Foundation

final class MediaRemoteAdapterClient: @unchecked Sendable {

    struct Paths: Sendable {
        let executable: URL
        let script: URL
        let framework: URL
    }

    enum SetupError: Error {
        case notBundled
        case perlMissing
    }

    /// The helper files inside the built app (see `scripts/build-app.sh` `build_adapter`).
    static func bundledPaths(in bundle: Bundle = .main) throws -> Paths {
        guard let script = bundle.url(forResource: "mediaremote-adapter", withExtension: "pl"),
              let frameworks = bundle.privateFrameworksURL
        else { throw SetupError.notBundled }
        let framework = frameworks.appendingPathComponent("MediaRemoteAdapter.framework", isDirectory: true)
        guard FileManager.default.fileExists(atPath: framework.path) else { throw SetupError.notBundled }
        let perl = URL(fileURLWithPath: "/usr/bin/perl")
        guard FileManager.default.isExecutableFile(atPath: perl.path) else { throw SetupError.perlMissing }
        return Paths(executable: perl, script: script, framework: framework)
    }

    private let paths: Paths
    private let restartDelay: TimeInterval
    private let onSnapshot: @Sendable (AdapterSnapshot?) -> Void
    private let onStatus: @Sendable (AdapterStatus) -> Void
    private let queue = DispatchQueue(label: "com.agoynotch.mediaremote-adapter", qos: .userInitiated)

    // Queue-confined state.
    private var process: Process?
    private var stdoutHandle: FileHandle?
    private var stderrHandle: FileHandle?
    private var generation = 0
    private var stopped = true
    private var sawFirstMessage = false
    private var loggedDecodeFailure = false
    private var loggedOverflow = false
    private var lastStderrLine: String?
    private var state: [String: Any] = [:]
    private var lineBuffer = AdapterLineBuffer()
    private var lastSnapshot: AdapterSnapshot?
    private var restartPolicy = AdapterRestartPolicy()
    private var inflight: [ObjectIdentifier: Process] = [:]

    init(paths: Paths,
         restartDelay: TimeInterval = 2,
         onSnapshot: @escaping @Sendable (AdapterSnapshot?) -> Void,
         onStatus: @escaping @Sendable (AdapterStatus) -> Void) {
        self.paths = paths
        self.restartDelay = restartDelay
        self.onSnapshot = onSnapshot
        self.onStatus = onStatus
    }

    // MARK: - Lifecycle

    /// Starts the stream (idempotent).
    func start() {
        queue.async {
            if let p = self.process, p.isRunning { return }
            self.stopped = false
            self.launch()
        }
    }

    /// Stops the stream synchronously, so the child is signalled before
    /// `applicationWillTerminate` returns. Never called from `queue`.
    func stop() {
        queue.sync {
            stopped = true
            generation += 1
            stdoutHandle?.readabilityHandler = nil
            stderrHandle?.readabilityHandler = nil
            stdoutHandle = nil
            stderrHandle = nil
            if let p = process, p.isRunning { p.terminate() }
            process = nil
        }
    }

    /// PID of the running stream child (harness / DEBUG log only).
    var runningProcessIdentifier: Int32? {
        queue.sync { process.flatMap { $0.isRunning ? $0.processIdentifier : nil } }
    }

    // MARK: - Commands

    /// Fire-and-forget transport command; the stream reports the resulting state.
    func send(_ c: AdapterCommand) {
        queue.async {
            let p = Process()
            p.executableURL = self.paths.executable
            p.arguments = AdapterArguments.send(script: self.paths.script.path,
                                                framework: self.paths.framework.path, c)
            p.standardInput = FileHandle.nullDevice
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { [weak self] proc in
                let status = proc.terminationStatus
                let id = ObjectIdentifier(proc)
                guard let self else { return }
                self.queue.async {
                    self.inflight[id] = nil
                    if status != 0 { AgoyLog.write("Now Playing command \(c.rawValue) exited with status \(status)") }
                }
            }
            do { try p.run() } catch {
                AgoyLog.write("Now Playing command could not start: \(error.localizedDescription)")
                return
            }
            self.inflight[ObjectIdentifier(p)] = p
        }
    }

    // MARK: - Stream (on queue)

    private func launch() {
        generation += 1
        let gen = generation
        sawFirstMessage = false
        loggedDecodeFailure = false
        lastStderrLine = nil
        onStatus(.starting)

        let p = Process()
        let out = Pipe()
        let err = Pipe()
        p.executableURL = paths.executable
        p.arguments = AdapterArguments.stream(script: paths.script.path, framework: paths.framework.path)
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = out
        p.standardError = err

        out.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            guard let self else { return }
            self.queue.async { self.consume(d, gen) }
        }
        err.fileHandleForReading.readabilityHandler = { [weak self] h in
            let d = h.availableData
            if d.isEmpty { h.readabilityHandler = nil; return }
            guard let self else { return }
            self.queue.async { self.consumeStderr(d, gen) }
        }
        p.terminationHandler = { [weak self] p in
            let status = p.terminationStatus
            let normalExit = (p.terminationReason == .exit)
            guard let self else { return }
            self.queue.async { self.handleExit(status: status, normalExit: normalExit, gen: gen) }
        }

        stdoutHandle = out.fileHandleForReading
        stderrHandle = err.fileHandleForReading

        do { try Self.runWithEmptySignalMask(p) } catch {
            process = nil
            out.fileHandleForReading.readabilityHandler = nil
            err.fileHandleForReading.readabilityHandler = nil
            stdoutHandle = nil
            stderrHandle = nil
            onSnapshot(nil)
            onStatus(.failed("could not start helper: \(error.localizedDescription)"))
            AgoyLog.write("Now Playing helper could not start: \(error.localizedDescription)")
            return                                    // no retry
        }
        process = p
    }

    /// Spawns `p` with an empty signal mask on the calling thread, so the child does not
    /// inherit the dispatch worker thread's blocked signals (seen with swift-corelibs
    /// Foundation): `stop()`'s SIGTERM must reach the helper. The mask is restored after.
    private static func runWithEmptySignalMask(_ p: Process) throws {
        var empty = sigset_t()
        var old = sigset_t()
        sigemptyset(&empty)
        pthread_sigmask(SIG_SETMASK, &empty, &old)
        defer { pthread_sigmask(SIG_SETMASK, &old, nil) }
        try p.run()
    }

    private func consume(_ data: Data, _ gen: Int) {
        guard gen == generation else { return }
        let lines = lineBuffer.append(data)
        if lineBuffer.didOverflow && !loggedOverflow {
            loggedOverflow = true
            AgoyLog.write("Now Playing helper sent a line over \(lineBuffer.maxBytes) bytes; dropped it")
        }
        for line in lines {
            guard let message = AdapterStreamMessage.decode(line) else {
                if !loggedDecodeFailure {
                    loggedDecodeFailure = true
                    AgoyLog.write("Now Playing helper sent an undecodable line (\(line.count) bytes)")
                }
                continue
            }
            state = AdapterState.apply(message, to: state)
            if !sawFirstMessage {
                sawFirstMessage = true
                onStatus(.running)
            }
            let snap = AdapterState.snapshot(from: state)
            if snap != lastSnapshot {
                lastSnapshot = snap
                onSnapshot(snap)
            }
        }
    }

    private func consumeStderr(_ data: Data, _ gen: Int) {
        guard gen == generation else { return }
        let text = String(decoding: data, as: UTF8.self)
        for raw in text.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            #if DEBUG
            print("[AgoyNotch] helper stderr: \(line)")
            #endif
            if !line.isEmpty { lastStderrLine = String(line.prefix(200)) }
        }
    }

    private func handleExit(status: Int32, normalExit: Bool, gen: Int) {
        guard gen == generation, !stopped else { return }

        // Drain stderr first: the decisive line ("Failed to load framework…") can reach the
        // queue after this exit hop.
        if normalExit && status != 0, let h = stderrHandle {
            h.readabilityHandler = nil
            if let rest = try? h.readToEnd(), !rest.isEmpty { consumeStderr(rest, gen) }
        }

        generation += 1
        stdoutHandle?.readabilityHandler = nil
        stderrHandle?.readabilityHandler = nil
        process = nil
        stdoutHandle = nil
        stderrHandle = nil
        state = [:]
        lineBuffer = AdapterLineBuffer()
        lastSnapshot = nil
        onSnapshot(nil)

        if normalExit && status != 0 {
            var reason = "helper exited with status \(status)"
            if let lastStderrLine { reason += ": \(lastStderrLine)" }
            onStatus(.failed(reason))
            AgoyLog.write("Now Playing \(reason)")
            return                                    // fatal: upstream says not to re-invoke
        }

        if restartPolicy.allowRestart(at: Date()) {
            AgoyLog.write("Now Playing helper stopped (status \(status)); restarting in \(restartDelay) s")
            queue.asyncAfter(deadline: .now() + restartDelay) { [weak self] in
                guard let self, !self.stopped, self.process == nil else { return }
                self.launch()
            }
        } else {
            onStatus(.failed("helper keeps stopping"))
            AgoyLog.write("Now Playing helper keeps stopping; giving up")
        }
    }
}
