import AppKit
import BelugaUpdateCore
import CaptureCore
import CoreImage.CIFilterBuiltins
import Darwin
import RemoteSessionCore
import SwiftUI

enum BelugaMenuReleasePolicy {
    static let offersBrowserAudioSharing = false
}

@MainActor
final class BelugaMenuBarModel: ObservableObject {
    @Published private(set) var presentation = BelugaHostPresentation.starting
    @Published private(set) var hasStarted = false
    @Published var allowRemoteControl = false
    @Published private(set) var hostOwnsAudioForSharing = false
    @Published private(set) var showingAudioShare = false
    @Published private(set) var isChangingPhone = false
    @Published private(set) var phoneChangeMessage: String?
    @Published private(set) var isRequestingMediaHandoff = false
    @Published private(set) var mediaHandoffMessage: String?
    private var mediaHandoffTask: Task<Void, Never>?
    private var mediaHandoffRequestID: UUID?
    private var expirationTask: Task<Void, Never>?
    private var phoneCommands: BelugaPhoneCatalogCommands?
    private var phoneCommandTask: Task<Void, Never>?
    private var phoneCommandID: UUID?
    private var didFinish = false
    var start: (() -> Bool)?

    var offersAudioSharing: Bool { BelugaMenuReleasePolicy.offersBrowserAudioSharing }

    var canShareAudio: Bool {
        offersAudioSharing && !didFinish && hasStarted && hostOwnsAudioForSharing
    }

    func updateAudioShareOwnership(_ ownsAudio: Bool) {
        hostOwnsAudioForSharing = !didFinish && ownsAudio
        if !canShareAudio { dismissAudioShare() }
    }

    @discardableResult
    func presentAudioShare() -> Bool {
        guard canShareAudio else { return false }
        showingAudioShare = true
        return true
    }

    func dismissAudioShare() {
        showingAudioShare = false
    }

    func begin() {
        guard !hasStarted, let start, start() else { return }
        hasStarted = true
    }

    func apply(_ update: BelugaHostPresentation, now: Date = Date()) {
        guard !didFinish, update.revision > presentation.revision else { return }
        if update.connectedMediaTarget != presentation.connectedMediaTarget {
            retireMediaHandoffRequest()
        }
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
        updateAudioShareOwnership(false)
        retireMediaHandoffRequest()
        phoneCommands = nil
        phoneCommandID = nil
        phoneCommandTask?.cancel()
        phoneCommandTask = nil
        isChangingPhone = false
        phoneChangeMessage = nil
        expirationTask?.cancel()
        expirationTask = nil
        presentation = BelugaHostPresentation(
            revision: presentation.revision, phase: .stopped,
            pairedPhoneName: presentation.pairedPhoneName, invitation: nil
        )
    }

    var canChangePhone: Bool {
        !didFinish && hasStarted && !isChangingPhone && phoneCommands != nil
            && presentation.phones.action != nil
    }

    func installPhoneCommands(_ commands: BelugaPhoneCatalogCommands) {
        guard !didFinish else { return }
        phoneCommands = commands
    }

    var canMoveMedia: Bool {
        !didFinish && hasStarted && !isChangingPhone && !isRequestingMediaHandoff
            && presentation.phase == .sessionPrepared
            && presentation.connectedMediaTarget != nil && phoneCommands?.moveMedia != nil
    }

    @discardableResult
    func moveMedia(to target: BelugaConnectedPhoneMediaTarget) -> Task<Void, Never>? {
        guard canMoveMedia, target == presentation.connectedMediaTarget,
              let move = phoneCommands?.moveMedia else { return nil }
        let requestID = UUID()
        mediaHandoffRequestID = requestID
        isRequestingMediaHandoff = true
        mediaHandoffMessage = nil
        let task = Task { [weak self] in
            guard let self, !Task.isCancelled, self.mediaHandoffRequestID == requestID,
                  self.presentation.connectedMediaTarget == target else { return }
            var sent = false
            do { _ = try await move(target); sent = true } catch { }
            guard !Task.isCancelled, !self.didFinish, self.mediaHandoffRequestID == requestID,
                  self.presentation.connectedMediaTarget == target else { return }
            self.mediaHandoffRequestID = nil
            self.mediaHandoffTask = nil
            self.isRequestingMediaHandoff = false
            self.mediaHandoffMessage = sent
                ? "Handoff requested. Open Beluga on the phone and tap Play if asked. Check the phone for confirmation."
                : "Handoff unavailable. Keep a supported YouTube video playing and Beluga open on the connected phone, then try again."
        }
        mediaHandoffTask = task
        return task
    }

    private func retireMediaHandoffRequest() {
        mediaHandoffTask?.cancel()
        mediaHandoffTask = nil
        mediaHandoffRequestID = nil
        isRequestingMediaHandoff = false
        mediaHandoffMessage = nil
    }

    @discardableResult
    func changePhone(_ command: BelugaPhoneCatalogCommand,
                     ticket: WorldwidePhoneCatalogAction) -> Task<Void, Never>? {
        guard !didFinish else { return nil }
        guard canChangePhone, ticket == presentation.phones.action, let phoneCommands else {
            phoneChangeMessage = "Phone list changed or a connection is active. Try again when ready."
            return nil
        }
        switch command {
        case .pairAnother:
            guard presentation.phones.canAddPhone else { return nil }
        case .select(let id):
            guard id == nil || presentation.phones.items.contains(where: { $0.id == id }) else { return nil }
        case .forget(let id):
            guard presentation.phones.items.contains(where: { $0.id == id }) else { return nil }
        }
        let operation = UUID()
        phoneCommandID = operation
        isChangingPhone = true
        phoneChangeMessage = nil
        let task = Task { [weak self] in
            var succeeded = false
            do {
                try Task.checkCancellation()
                try await phoneCommands.perform(command, ticket)
                succeeded = true
            } catch { }
            guard let self, !self.didFinish, self.phoneCommandID == operation else { return }
            self.phoneCommandID = nil
            self.phoneCommandTask = nil
            self.isChangingPhone = false
            if !succeeded {
                self.phoneChangeMessage = "Phone change was not applied. Wait until the current connection is idle, then try again."
            }
        }
        phoneCommandTask = task
        return task
    }

    private func expire(revision: UInt64) {
        guard presentation.revision == revision, presentation.invitation != nil else { return }
        presentation = BelugaHostPresentation(
            revision: revision, phase: .invitationExpired,
            pairedPhoneName: nil, invitation: nil, phones: presentation.phones
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
                                   CaptureAdditionalMediaLifetime?,
                                   @escaping @Sendable (BelugaPhoneCatalogCommands) -> Void)
        async -> Void
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var runtimeTask: Task<Void, Never>?
    private var explicitUserQuit = false

    init(arguments: [String]?, endpoint: URL?,
         runtime: @escaping @Sendable (
             [String], @escaping @Sendable (BelugaHostPresentation) -> Void,
             CaptureAdditionalMediaLifetime?,
             @escaping @Sendable (BelugaPhoneCatalogCommands) -> Void
         ) async -> Void) {
        runtimeArguments = arguments
        self.endpoint = endpoint
        self.runtime = runtime
        super.init()
        model.start = { [weak self] in self?.startRuntime() ?? false }
        if BelugaMenuReleasePolicy.offersBrowserAudioSharing, let endpoint {
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
                guard let self, self.model.canShareAudio else { return }
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
                    self.model.updateAudioShareOwnership(self.shareOwner.isValid && !self.explicitUserQuit)
                }
            }, shutdown: { await coordinator.stop() })
        }
        let runtime = runtime
        runtimeTask = Task { [weak self] in
            await runtime(arguments, sink, additionalMedia) { [weak self] commands in
                Task { @MainActor in self?.model.installPhoneCommands(commands) }
            }
            self?.shareOwner.revoke()
            self?.model.updateAudioShareOwnership(false)
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
        model.updateAudioShareOwnership(false)
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
    @State private var phoneToForget: BelugaPairedPhonePresentation?
    @State private var forgetTicket: WorldwidePhoneCatalogAction?
    @State private var confirmsForget = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Beluga").font(.title2.bold())
            Text(versionLabel).font(.caption).foregroundStyle(.secondary)
            if !model.hasStarted {
                Text("Stream this Mac to your phone using secure QR pairing.")
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
                    Text("Selected phone: \(phone)").font(.caption)
                }
                phoneControls
                if let target = model.presentation.connectedMediaTarget {
                    Button("Move media to phone") { model.moveMedia(to: target) }
                        .disabled(!model.canMoveMedia || updater.isUpdateInProgress)
                    if model.isRequestingMediaHandoff {
                        Text("Requesting playback on the phone…").font(.caption)
                    }
                    if let message = model.mediaHandoffMessage {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
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
            if model.offersAudioSharing {
                Button("Share audio link…") { model.presentAudioShare() }
                    .disabled(!model.canShareAudio || updater.isUpdateInProgress)
                if !model.canShareAudio {
                    Text("Start this Mac’s Beluga host before sharing audio.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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
        .confirmationDialog("Forget this phone?", isPresented: $confirmsForget, titleVisibility: .visible) {
            Button("Forget phone", role: .destructive) {
                if let phoneToForget, let forgetTicket {
                    model.changePhone(.forget(phoneToForget.id), ticket: forgetTicket)
                }
                phoneToForget = nil
                forgetTicket = nil
            }
            Button("Cancel", role: .cancel) { phoneToForget = nil; forgetTicket = nil }
        } message: {
            Text("Remove \(phoneToForget?.label ?? "this phone") from this Mac? Other saved phones are kept. Pair it again to reconnect.")
        }
        .sheet(isPresented: Binding(get: {
            model.offersAudioSharing && model.showingAudioShare
        }, set: { presented in
            if !presented { model.dismissAudioShare() }
        })) {
            BelugaAudioShareView(model: share, canStart: model.canShareAudio
                && !updater.isUpdateInProgress, start: startShare,
                close: { model.dismissAudioShare() })
        }
    }

    private var phoneControls: some View {
        let catalog = model.presentation.phones
        return VStack(alignment: .leading, spacing: 8) {
            Menu("Saved phones (\(catalog.items.count))") {
                ForEach(catalog.items) { phone in
                    Button {
                        if let ticket = catalog.action {
                            model.changePhone(.select(phone.id), ticket: ticket)
                        }
                    } label: {
                        Text(phone.label + (phone.needsPairingRecovery ? " — finish pairing" : ""))
                    }
                    .disabled(catalog.selectedPhoneID == phone.id)
                }
                Divider()
                Button("No phone selected") {
                    if let ticket = catalog.action {
                        model.changePhone(.select(nil), ticket: ticket)
                    }
                }.disabled(catalog.selectedPhoneID == nil)
            }.disabled(!model.canChangePhone)
            Button(catalog.items.isEmpty ? "Pair a phone…" : "Pair another phone…") {
                if let ticket = catalog.action {
                    model.changePhone(.pairAnother, ticket: ticket)
                }
            }.disabled(!model.canChangePhone || !catalog.canAddPhone)
            if !catalog.items.isEmpty {
                Menu("Forget a saved phone…") {
                    ForEach(catalog.items) { phone in
                        Button(phone.label, role: .destructive) {
                            phoneToForget = phone
                            forgetTicket = catalog.action
                            confirmsForget = true
                        }
                    }
                }.disabled(!model.canChangePhone)
            }
            if model.isChangingPhone {
                Text("Updating phone selection…").font(.caption)
            } else if catalog.action == nil {
                Text("Phone changes wait until the phone session is idle. Active connections are never disconnected here.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let message = model.phoneChangeMessage {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
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
