import AppKit
import BelugaUpdateCore
import CaptureCore
import CoreImage.CIFilterBuiltins
import Darwin
import RemoteSessionCore
import SwiftUI

@MainActor
final class BelugaMenuBarModel: ObservableObject {
    @Published private(set) var presentation = BelugaHostPresentation.starting
    @Published private(set) var hasStarted = false
    @Published var allowRemoteControl = false
    @Published var canShareAudio = false
    @Published var showingAudioShare = false
    private var expirationTask: Task<Void, Never>?
    private var didFinish = false
    var start: (() -> Bool)?

    func begin() {
        guard !hasStarted, let start, start() else { return }
        hasStarted = true
    }

    func apply(_ update: BelugaHostPresentation, now: Date = Date()) {
        guard !didFinish, update.revision > presentation.revision else { return }
        expirationTask?.cancel()
        presentation = update
        guard let invitation = update.invitation else { return }
        guard invitation.isValid(at: now) else {
            expire(revision: update.revision)
            return
        }
        let delay = invitation.expiresAt.timeIntervalSince(now)
        expirationTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.expire(revision: update.revision)
        }
    }

    func finished() {
        didFinish = true
        expirationTask?.cancel()
        expirationTask = nil
        presentation = BelugaHostPresentation(
            revision: presentation.revision, phase: .stopped,
            pairedPhoneName: presentation.pairedPhoneName, invitation: nil
        )
    }

    private func expire(revision: UInt64) {
        guard presentation.revision == revision, presentation.invitation != nil else { return }
        presentation = BelugaHostPresentation(
            revision: revision, phase: .invitationExpired,
            pairedPhoneName: nil, invitation: nil
        )
    }
}

/// AppKit owns the existing executable's event loop; all product content remains SwiftUI.
@MainActor
final class BelugaMenuBarApplication: NSObject, NSApplicationDelegate {
    private let model = BelugaMenuBarModel()
    private let updater = BelugaUpdateController()
    private let share = BelugaAudioShareModel()
    private let shareOwner = BelugaAudioShareOwnerGate()
    private var shareCoordinator: BelugaAudioShareCoordinator?
    private let runtimeArguments: [String]?
    private let endpoint: URL?
    private let runtime: @Sendable ([String], @escaping @Sendable (BelugaHostPresentation) -> Void,
                                   CaptureAdditionalMediaLifetime?)
        async -> Void
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var runtimeTask: Task<Void, Never>?
    private var explicitUserQuit = false

    init(arguments: [String]?, endpoint: URL?,
         runtime: @escaping @Sendable (
             [String], @escaping @Sendable (BelugaHostPresentation) -> Void,
             CaptureAdditionalMediaLifetime?
         ) async -> Void) {
        runtimeArguments = arguments
        self.endpoint = endpoint
        self.runtime = runtime
        super.init()
        model.start = { [weak self] in self?.startRuntime() ?? false }
        if let endpoint {
            let relay = BelugaAudioShareStatusRelay { [weak share] status, revision in
                Task { @MainActor in share?.apply(status, revision: revision) }
            }
            let owner = shareOwner
            let coordinator = BelugaAudioShareCoordinator(
                endpoint: endpoint, logger: ConsoleLogger(verbose: false),
                status: { relay.publish($0) }, ownerIsValid: { owner.isValid }
            )
            shareCoordinator = coordinator
            share.configure(start: { try await coordinator.start(ttlSeconds: $0) },
                            stop: { await coordinator.stop() },
                            revoke: { coordinator.revokeCapture() })
        }
    }

    func run() {
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        application.delegate = self
        application.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(named: NSImage.Name("AppIcon"))
                ?? NSImage(contentsOf: Bundle.main.bundleURL
                    .appendingPathComponent("Contents/Resources/AppIcon.icns"))
            image?.size = NSSize(width: 19, height: 19)
            button.image = image
                ?? NSImage(systemSymbolName: "waveform", accessibilityDescription: "Beluga")
            button.toolTip = "Beluga"
            button.target = self
            button.action = #selector(togglePopover)
            button.setAccessibilityLabel("Beluga menu")
        }
        statusItem = item
        let panel = NSPopover()
        panel.behavior = .transient
        panel.contentViewController = NSHostingController(rootView: BelugaMenuBarView(
            model: model, updater: updater, share: share,
            hasEndpoint: endpoint != nil || runtimeArguments != nil,
            quit: { [weak self] in self?.quit() },
            startShare: { [weak self] in
                guard let self else { return }
                self.share.start(ownerIsValid: self.shareOwner.isValid,
                                 updateInProgress: self.updater.isUpdateInProgress)
            }
        ))
        popover = panel
        refreshUpdateAdmission()
        updater.menuDidBecomeReady()
        if runtimeArguments != nil {
            model.begin()
        } else {
            showPopover()
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard runtimeTask != nil else {
            return share.hasPendingOrActiveShare ? .terminateCancel : .terminateNow
        }
        guard explicitUserQuit else { return .terminateCancel }
        updater.updateAdmission(BelugaUpdateAdmission())
        // The existing signal supervisor owns route restoration and native teardown.
        Darwin.kill(Darwin.getpid(), SIGTERM)
        return .terminateCancel
    }

    private func startRuntime() -> Bool {
        guard runtimeTask == nil, !updater.isUpdateInProgress else { return false }
        updater.updateAdmission(BelugaUpdateAdmission())
        let arguments: [String]
        if let runtimeArguments {
            arguments = runtimeArguments
        } else if let endpoint {
            arguments = BelugaHostLaunchMode.normalDisplayArguments(
                executable: CommandLine.arguments[0], endpoint: endpoint,
                allowRemoteControl: model.allowRemoteControl
            )
        } else {
            return false
        }
        let sink: @Sendable (BelugaHostPresentation) -> Void = { [weak self] update in
            Task { @MainActor in
                self?.model.apply(update)
                self?.refreshUpdateAdmission()
            }
        }
        let additionalMedia = shareCoordinator.map { coordinator in
            CaptureAdditionalMediaLifetime(gate: shareOwner, becameOwned: { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    self.model.canShareAudio = self.shareOwner.isValid && !self.explicitUserQuit
                }
            }, shutdown: { await coordinator.stop() })
        }
        let runtime = runtime
        runtimeTask = Task { [weak self] in
            await runtime(arguments, sink, additionalMedia)
            self?.shareOwner.revoke()
            self?.model.canShareAudio = false
            self?.share.ownerStopped()
            self?.model.finished()
            self?.runtimeTask = nil
            self?.refreshUpdateAdmission()
            if self?.explicitUserQuit == true { NSApplication.shared.terminate(nil) }
        }
        return true
    }

    @objc private func togglePopover() {
        guard let popover else { return }
        if popover.isShown { popover.performClose(nil) } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
    }

    private func refreshUpdateAdmission() {
        updater.updateAdmission(BelugaUpdateAdmission(
            isInteractiveApplication: runtimeArguments == nil,
            hasActiveMedia: runtimeTask != nil,
            hasPendingPairing: model.presentation.phase == .inviting,
            hasAudioShares: share.hasPendingOrActiveShare,
            teardownComplete: runtimeTask == nil
        ))
    }

    private func quit() {
        explicitUserQuit = true
        shareOwner.revoke()
        model.canShareAudio = false
        updater.updateAdmission(BelugaUpdateAdmission())
        NSApplication.shared.terminate(nil)
    }
}

private struct BelugaMenuBarView: View {
    @ObservedObject var model: BelugaMenuBarModel
    @ObservedObject var updater: BelugaUpdateController
    @ObservedObject var share: BelugaAudioShareModel
    let hasEndpoint: Bool
    let quit: () -> Void
    let startShare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Beluga").font(.title2.bold())
            Text(versionLabel).font(.caption).foregroundStyle(.secondary)
            if !model.hasStarted {
                Text("Stream this Mac to your iPhone using secure QR pairing.")
                Toggle("Allow remote keyboard and pointer control", isOn: $model.allowRemoteControl)
                Text("Uses your normal Mac display. Audio sharing never needs remote-control permission.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Start Beluga on this Mac") { model.begin() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!hasEndpoint || updater.isUpdateInProgress)
                if !hasEndpoint {
                    Text("This build has no valid secure rendezvous configuration.")
                        .foregroundStyle(.red)
                }
            } else {
                Text(model.presentation.phase.title)
                if let phone = model.presentation.pairedPhoneName {
                    Text("Paired iPhone: \(phone)").font(.caption)
                }
                if let invitation = model.presentation.invitation {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        if invitation.isValid(at: context.date) {
                            invitationView(invitation, now: context.date)
                        }
                    }
                }
                if model.presentation.phase == .sessionPrepared {
                    Text("Session negotiation is not proof of playing audio or a visible screen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            Button("Share audio link…") { model.showingAudioShare = true }
                .disabled(!model.canShareAudio || updater.isUpdateInProgress)
            if !model.canShareAudio {
                Text("Start this Mac’s Beluga host before sharing audio.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button("Check for Updates…") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
            Text(updater.statusText).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Screen Recording settings") { openPrivacy("Privacy_ScreenCapture") }
                Button("Accessibility settings") { openPrivacy("Privacy_Accessibility") }
            }.font(.caption)
            Button("Quit Beluga", action: quit)
        }
        .padding(18).frame(width: 360)
        .sheet(isPresented: $model.showingAudioShare) {
            BelugaAudioShareView(model: share, canStart: model.canShareAudio
                && !updater.isUpdateInProgress, start: startShare,
                close: { model.showingAudioShare = false })
        }
    }

    private func invitationView(_ invitation: BelugaPairingInvitation, now: Date) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan in Beluga on your iPhone")
            if let image = pairingImage(invitation.code) {
                Image(nsImage: image).resizable().interpolation(.none)
                    .frame(width: 220, height: 220).accessibilityLabel("One-time secure pairing QR code")
            }
            Text(invitation.code.exportedCode).font(.system(.caption, design: .monospaced))
                .lineLimit(nil).fixedSize(horizontal: false, vertical: true)
            Text("One-time invitation · \(max(0, Int(invitation.expiresAt.timeIntervalSince(now)))) seconds left")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func pairingImage(_ invitation: RemoteInvitationCode) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(RemotePairingQRCode(invitation: invitation).exportedPayload.utf8)
        filter.correctionLevel = "M"
        guard let image = filter.outputImage,
              let pixels = CIContext().createCGImage(image, from: image.extent) else { return nil }
        return NSImage(cgImage: pixels, size: NSSize(width: pixels.width, height: pixels.height))
    }

    private func openPrivacy(_ pane: String) {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") else { return }
        NSWorkspace.shared.open(url)
    }

    private var versionLabel: String {
        guard let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String else {
            return "Development build"
        }
        return "Version \(version) (\(build))"
    }
}

private struct BelugaAudioShareView: View {
    @ObservedObject var model: BelugaAudioShareModel
    let canStart: Bool
    let start: () -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Share this Mac’s audio").font(.title2.bold())
            Text("All system audio is shared. Anyone with the link can listen, forward it, or record it. No microphone, screen, or remote control is shared.")
                .font(.callout)
            if let url = model.url, let expiry = model.expiresAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(max(0, Int(expiry.timeIntervalSince(context.date)))) seconds remaining")
                        .monospacedDigit()
                }
                Text(url.absoluteString).font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled).lineLimit(4)
                Button("Copy private link") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.absoluteString, forType: .string)
                }
            } else {
                Picker("Link valid for", selection: $model.durationMinutes) {
                    ForEach([5, 15, 30, 60, 120], id: \.self) { minutes in
                        Text("\(minutes) minutes").tag(minutes)
                    }
                }.disabled(model.isWorking || model.isQuarantined)
                Button("Create private link", action: start)
                    .buttonStyle(.borderedProminent)
                    .disabled(!canStart || model.hasPendingOrActiveShare)
            }
            Text(model.statusText).font(.caption).foregroundStyle(.secondary)
            HStack {
                if model.hasPendingOrActiveShare {
                    Button("End share for everyone") { model.stop() }
                        .disabled(model.isQuarantined)
                }
                Spacer()
                Button("Done", action: close)
            }
        }.padding(20).frame(width: 440)
    }
}
