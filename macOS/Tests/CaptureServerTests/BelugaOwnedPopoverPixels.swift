import AppKit
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit
@preconcurrency import Vision

// Test-only compositor capture. Run only in the fresh, externally supervised XCTest process.
@MainActor
@available(macOS 15.2, *)
enum BelugaOwnedPopoverPixels {
    struct Evidence {
        let image: CGImage
        let ocrImage: CGImage
        let ocrPixelScale: Int
        let windowID: CGWindowID
        let processID: pid_t
        let width: Int
        let height: Int
        let opaquePixels: Int
        let visiblePixels: Int
        let luminanceRange: Int
        let exactTextOccurrences: [String: Int]
    }

    enum Refusal: Error {
        case invalidOwnedWindow, foregroundChanged, invalidFilter
        case ambiguousWindow, wrongProcess, invalidDimensions
        case bitmapConversion, transparentOrUniformPixels
        case invalidTextExpectation, unprovenText
        case deadlineExpired
    }

    static func capture(_ window: NSWindow, expectedTexts: [String],
                        within: Duration = .seconds(3)) async throws -> Evidence {
        let clock = ContinuousClock(), deadline = clock.now.advanced(by: within)
        guard within > .zero, within <= .seconds(5),
              !expectedTexts.isEmpty, expectedTexts.count <= 4,
              expectedTexts.allSatisfy({ !$0.isEmpty && $0.utf8.count <= 256 }),
              Set(expectedTexts).count == expectedTexts.count else {
            throw Refusal.invalidTextExpectation
        }
        guard let foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier,
              foreground > 0 else { throw Refusal.foregroundChanged }
        let processID = ProcessInfo.processInfo.processIdentifier
        let number = window.windowNumber
        let identity = ObjectIdentifier(window)
        try fence(window, identity: identity, number: number, foreground: foreground)

        // This is intentionally not SCShareableContent.current, a picker, or a display capture.
        let inventory = try await bounded(deadline, phase: .ownedInventory, operation: {
            try await SCShareableContent.currentProcess
        })
        try fence(window, identity: identity, number: number, foreground: foreground)
        let matches = inventory.windows.filter { $0.windowID == CGWindowID(number) }
        guard matches.count == 1 else { throw Refusal.ambiguousWindow }
        let owned = matches[0]
        guard owned.owningApplication?.processID == processID else {
            throw Refusal.wrongProcess
        }
        guard owned.isOnScreen, owned.frame.width.isFinite, owned.frame.height.isFinite,
              owned.frame.width > 0, owned.frame.height > 0 else {
            throw Refusal.invalidOwnedWindow
        }
        let filter = SCContentFilter(desktopIndependentWindow: owned)
        guard filter.style == .window, filter.includedWindows.count == 1,
              filter.includedWindows[0].windowID == owned.windowID,
              filter.includedWindows[0].owningApplication?.processID == processID,
              filter.includedDisplays.isEmpty,
              filter.pointPixelScale.isFinite, filter.pointPixelScale >= 1,
              filter.pointPixelScale <= 4 else { throw Refusal.invalidFilter }
        let width = try dimension(filter.contentRect.width, scale: filter.pointPixelScale)
        let height = try dimension(filter.contentRect.height, scale: filter.pointPixelScale)
        guard width * height <= 4_194_304 else { throw Refusal.invalidDimensions }
        let configuration = SCStreamConfiguration()
        configuration.width = width
        configuration.height = height
        configuration.pixelFormat = kCVPixelFormatType_32BGRA
        configuration.captureDynamicRange = .SDR
        configuration.capturesAudio = false
        configuration.captureMicrophone = false
        configuration.excludesCurrentProcessAudio = true
        configuration.showsCursor = false
        configuration.showMouseClicks = false
        configuration.includeChildWindows = false
        configuration.ignoreShadowsSingleWindow = true
        configuration.capturesShadowsOnly = false
        configuration.shouldBeOpaque = false
        configuration.ignoreGlobalClipSingleWindow = false
        configuration.scalesToFit = false
        configuration.preservesAspectRatio = true
        configuration.colorSpaceName = CGColorSpace.sRGB
        let image = try await bounded(deadline, phase: .windowImage, operation: {
            try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                       configuration: configuration)
        })
        try fence(window, identity: identity, number: number, foreground: foreground)
        guard image.width == width, image.height == height else {
            throw Refusal.invalidDimensions
        }
        let pixels = try summarize(image)
        // One transparent arrow/corner is normal. A clear or flat paint surface is not.
        guard pixels.visible >= width * height / 2,
              pixels.opaque >= width * height / 2,
              pixels.maximum - pixels.minimum >= 24 else {
            throw Refusal.transparentOrUniformPixels
        }
        guard clock.now < deadline else { throw Refusal.deadlineExpired }
        // Offline recognition cannot extend the admission deadline for the captured pixels.
        let recognitionDeadline = clock.now.advanced(by: .seconds(20))
        let ocrImage = try magnifyForOCR(image)
        guard clock.now < recognitionDeadline else { throw Refusal.deadlineExpired }
        let lines = try await bounded(recognitionDeadline, phase: .windowOCR,
                                      operation: { try await recognize(ocrImage) })
        try fence(window, identity: identity, number: number, foreground: foreground)
        let counts: [String: Int]
        do { counts = try exactOccurrences(expectedTexts, in: lines) }
        catch {
            retainTextRefusal(image, lines: lines, expected: expectedTexts, windowID: owned.windowID)
            throw error
        }
        guard clock.now < recognitionDeadline else { throw Refusal.deadlineExpired }
        return Evidence(image: image, ocrImage: ocrImage, ocrPixelScale: 3,
            windowID: owned.windowID, processID: processID,
            width: width, height: height, opaquePixels: pixels.opaque,
            visiblePixels: pixels.visible, luminanceRange: pixels.maximum - pixels.minimum,
            exactTextOccurrences: counts)
    }

    private static func fence(_ window: NSWindow, identity: ObjectIdentifier,
                              number: Int, foreground: pid_t) throws {
        guard Thread.isMainThread, NSApplication.shared.isRunning,
              ObjectIdentifier(window) == identity, number > 0,
              window.windowNumber == number, NSApplication.shared.windows.contains(where: { $0 === window }),
              window.isVisible, !window.isKeyWindow, !window.isMainWindow,
              window.occlusionState.contains(.visible), window.frame.width > 0,
              window.frame.height > 0,
              NSScreen.screens.contains(where: { $0.visibleFrame.contains(window.frame) }) else {
            throw Refusal.invalidOwnedWindow
        }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == foreground else {
            throw Refusal.foregroundChanged
        }
    }

    private static func dimension(_ points: CGFloat, scale: Float) throws -> Int {
        let raw = Double(points) * Double(scale)
        guard raw.isFinite, raw >= 32, raw <= 2048 else { throw Refusal.invalidDimensions }
        return Int(raw.rounded(.up))
    }

    private struct PixelSummary {
        var opaque = 0, visible = 0, minimum = 255, maximum = 0
    }

    private static func summarize(_ image: CGImage) throws -> PixelSummary {
        let width = image.width, height = image.height, row = width * 4
        var bytes = [UInt8](repeating: 0, count: row * height)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
            throw Refusal.bitmapConversion
        }
        return try bytes.withUnsafeMutableBytes { storage in
            guard let context = CGContext(data: storage.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: row, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw Refusal.bitmapConversion
            }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let values = storage.bindMemory(to: UInt8.self)
            var summary = PixelSummary()
            for offset in stride(from: 0, to: values.count, by: 4) {
                let alpha = Int(values[offset + 3])
                if alpha >= 250 { summary.opaque += 1 }
                guard alpha >= 16 else { continue }
                summary.visible += 1
                // Consider only nearly opaque pixels: premultiplied translucency is not contrast.
                guard alpha >= 250 else { continue }
                let luminance = (54 * Int(values[offset]) + 183 * Int(values[offset + 1])
                    + 19 * Int(values[offset + 2])) / 256
                summary.minimum = min(summary.minimum, luminance)
                summary.maximum = max(summary.maximum, luminance)
            }
            return summary
        }
    }

    private struct RecognizedLine: Sendable {
        let text: String
        let top: Double
        let left: Double
        let bottom: Double
    }

    private static func magnifyForOCR(_ image: CGImage) throws -> CGImage {
        // One fixed, calibrated integer replication; no scale search or semantic correction.
        guard image.width > 0, image.height > 0,
              image.width <= 2048 / 3, image.height <= 2048 / 3 else { throw Refusal.invalidDimensions }
        let width = image.width * 3, height = image.height * 3
        guard width * height <= 4_194_304,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw Refusal.bitmapConversion
        }
        context.interpolationQuality = .none
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let result = context.makeImage(), result.width == width, result.height == height else {
            throw Refusal.bitmapConversion
        }
        return result
    }

    private static func retainTextRefusal(_ image: CGImage, lines: [RecognizedLine],
                                         expected: [String], windowID: CGWindowID) {
        guard let directory = ProcessInfo.processInfo.environment["BELUGA_RENDERED_MENU_DIAGNOSTIC_DIR"] else { return }
        do {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("owned-window-text-refusal-\(windowID)")
            let bitmap = NSBitmapImageRep(cgImage: image)
            guard let png = bitmap.representation(using: .png, properties: [:]) else {
                throw Refusal.bitmapConversion
            }
            try png.write(to: url.appendingPathExtension("png"), options: .withoutOverwriting)
            let report: [String: Any] = ["expected": expected, "windowID": windowID,
                "width": image.width, "height": image.height,
                "recognized": lines.map { ["text": $0.text, "top": $0.top,
                                           "left": $0.left, "bottom": $0.bottom] as [String: Any] }]
            try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
                .write(to: url.appendingPathExtension("json"), options: .withoutOverwriting)
            FileHandle.standardOutput.write(Data("ACTUAL_POPOVER_TEXT_REFUSAL window=\(windowID) retained=true\n".utf8))
        } catch {
            FileHandle.standardOutput.write(Data("ACTUAL_POPOVER_TEXT_REFUSAL window=\(windowID) retained=false\n".utf8))
        }
    }

    private static func recognize(_ image: CGImage) async throws -> [RecognizedLine] {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue(label: "beluga.rendered-menu.owned-window-ocr", qos: .userInitiated).async {
                do {
                    let request = VNRecognizeTextRequest()
                    request.revision = VNRecognizeTextRequestRevision3
                    request.recognitionLevel = .accurate
                    request.recognitionLanguages = ["en-US"]
                    request.usesLanguageCorrection = false
                    request.automaticallyDetectsLanguage = false
                    request.customWords = []
                    request.minimumTextHeight = 0.008
                    try VNImageRequestHandler(cgImage: image, orientation: .up).perform([request])
                    let observations = request.results ?? []
                    guard observations.count <= 128 else { throw Refusal.unprovenText }
                    let lines = try observations.map { observation -> RecognizedLine in
                        guard let candidate = observation.topCandidates(1).first,
                              candidate.confidence >= 0.80,
                              candidate.string.utf8.count <= 1024 else { throw Refusal.unprovenText }
                        let frame = observation.boundingBox
                        guard frame.minX.isFinite, frame.minY.isFinite,
                              frame.maxX.isFinite, frame.maxY.isFinite,
                              frame.width > 0, frame.height > 0,
                              CGRect(x: 0, y: 0, width: 1, height: 1).contains(frame) else {
                            throw Refusal.unprovenText
                        }
                        return RecognizedLine(text: candidate.string, top: Double(1 - frame.maxY),
                            left: Double(frame.minX), bottom: Double(1 - frame.minY))
                    }
                    continuation.resume(returning: lines.sorted {
                        if $0.top != $1.top { return $0.top < $1.top }
                        if $0.left != $1.left { return $0.left < $1.left }
                        if $0.bottom != $1.bottom { return $0.bottom < $1.bottom }
                        return $0.text < $1.text
                    })
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    private enum MatcherControlFailure: Error {
        case unexpectedCounts, acceptedRefusalFixture(String)
    }

    // Fixture-only controls of the same private matcher used by captured pixels.
    // No capture, OCR, geometry, confidence or expected-text policy is replaced.
    static func verifyExactOccurrencesControls() throws -> (accepted: Int, refused: Int) {
        let expected = "Waiting for confirmed phone-session readiness."
        let exact = RecognizedLine(text: expected, top: 0.20, left: 0.10, bottom: 0.24)
        let first = RecognizedLine(text: "Waiting   for confirmed",
            top: 0.20, left: 0.10, bottom: 0.24)
        let second = RecognizedLine(text: "\tphone-session   readiness. \n",
            top: 0.25, left: 0.12, bottom: 0.29)
        let positives: [[RecognizedLine]] = [[exact], [first, second]]
        var accepted = 0
        for lines in positives {
            let counts = try exactOccurrences([expected], in: lines)
            guard counts == [expected: 1] else { throw MatcherControlFailure.unexpectedCounts }
            accepted += 1
        }
        let negatives: [(String, [RecognizedLine])] = [
            ("missing", []),
            ("duplicated", [
                exact,
                RecognizedLine(text: expected, top: 0.35, left: 0.10, bottom: 0.39)
            ]),
            ("wrong-word", [
                RecognizedLine(text: "Walting for confirmed phone-session readiness.",
                    top: 0.20, left: 0.10, bottom: 0.24)
            ]),
            ("misaligned-left-wrap", [
                first,
                RecognizedLine(text: second.text, top: 0.25, left: 0.20, bottom: 0.29)
            ]),
            ("misaligned-gap-wrap", [
                first,
                RecognizedLine(text: second.text, top: 0.30, left: 0.12, bottom: 0.34)
            ])
        ]
        var refused = 0
        for (name, lines) in negatives {
            do {
                _ = try exactOccurrences([expected], in: lines)
            } catch Refusal.unprovenText {
                refused += 1
                continue
            }
            throw MatcherControlFailure.acceptedRefusalFixture(name)
        }
        guard accepted == 2, refused == 5 else { throw MatcherControlFailure.unexpectedCounts }
        return (accepted: accepted, refused: refused)
    }

    private static func exactOccurrences(_ texts: [String], in lines: [RecognizedLine]) throws -> [String: Int] {
        func spaces(_ value: String) -> String { value.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        var counts: [String: Int] = [:]
        for text in texts {
            let expected = spaces(text)
            var matches = 0
            for start in lines.indices {
                var joined = ""
                for end in start..<min(start + 4, lines.count) {
                    if end > start {
                        guard abs(lines[end].left - lines[start].left) <= 0.04,
                              lines[end].top - lines[end - 1].bottom <= 0.025 else { break }
                    }
                    joined += (joined.isEmpty ? "" : " ") + spaces(lines[end].text)
                    if joined == expected { matches += 1 }
                    if joined.utf8.count >= expected.utf8.count { break }
                }
            }
            guard matches == 1 else { throw Refusal.unprovenText }
            counts[text] = matches
        }
        return counts
    }

    @MainActor
    private final class Pending<Value> {
        var continuation: CheckedContinuation<Value, Error>?
        var watchdog: Task<Void, Never>?
        var worker: Task<Void, Never>?
        func finish(_ result: sending Result<Value, Error>, before deadline: ContinuousClock.Instant) {
            guard let continuation else { return }
            self.continuation = nil
            watchdog?.cancel()
            continuation.resume(with: ContinuousClock.now < deadline
                ? result : .failure(Refusal.deadlineExpired))
        }
    }

    private enum Phase: String {
        case ownedInventory = "owned-inventory", windowImage = "window-image", windowOCR = "window-ocr"
    }

    private static func trace(_ phase: Phase, event: String, deadline: ContinuousClock.Instant) {
        let remaining = ContinuousClock.now.duration(to: deadline).components
        let milliseconds = Int((Double(remaining.seconds) * 1_000
            + Double(remaining.attoseconds) / 1_000_000_000_000_000).rounded(.towardZero))
        let line = "ACTUAL_POPOVER_NATIVE_PHASE phase=\(phase.rawValue) event=\(event) remaining_ms=\(milliseconds) mainThread=\(Thread.isMainThread) appRunning=\(NSApplication.shared.isRunning)\n"
        FileHandle.standardOutput.write(Data(line.utf8))
    }

    private static func bounded<Value>(_ deadline: ContinuousClock.Instant, phase: Phase,
        operation: @escaping @MainActor () async throws -> Value) async throws -> Value {
        trace(phase, event: "before-submit", deadline: deadline)
        guard ContinuousClock.now < deadline else {
            fatalError("Owned rendered XCTest deadline expired before native submission")
        }
        let pending = Pending<Value>()
        let outcome: Result<Value, Error>
        do {
            let value: Value = try await withCheckedThrowingContinuation { continuation in
                pending.continuation = continuation
                pending.watchdog = Task { @MainActor in
                    do { try await ContinuousClock().sleep(until: deadline) }
                    catch { return }
                    guard pending.continuation != nil else { return }
                    trace(phase, event: "watchdog-expired", deadline: deadline)
                    // No API promises joined cancellation of these callbacks. Never reuse this process.
                    fatalError("Owned rendered XCTest deadline expired with unresolved native work")
                }
                pending.worker = Task { @MainActor in
                    do {
                        trace(phase, event: "native-submit", deadline: deadline)
                        let value = try await operation()
                        trace(phase, event: "callback-success", deadline: deadline)
                        pending.finish(.success(value), before: deadline)
                    } catch {
                        trace(phase, event: "callback-error", deadline: deadline)
                        pending.finish(.failure(error), before: deadline)
                    }
                }
            }
            outcome = .success(value)
        } catch { outcome = .failure(error) }
        // Completed native work and its cancelled watchdog must both settle before reuse.
        await pending.worker?.value
        await pending.watchdog?.value
        pending.worker = nil
        pending.watchdog = nil
        return try outcome.get()
    }
}
