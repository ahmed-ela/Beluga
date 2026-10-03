import SwiftUI
import WebKit
import WebRTCTransport

@MainActor
final class YouTubeHandoffPlayer: NSObject, ObservableObject, Identifiable {
    nonisolated let request: YouTubeHandoffRequest
    nonisolated var id: UUID { request.operationID }
    @Published private(set) var phase: YouTubeHandoffPhase = .preparing
    @Published private(set) var macPauseStatus: YouTubeHandoffMacPauseStatus = .notRequested
    var statusText: String { phase.statusText(macPause: macPauseStatus) }
    private var operation: YouTubeHandoffOperation
    private let eventHandler: @MainActor (YouTubeHandoffPlayerEvent) -> Void
    private let now: @MainActor () -> Double
    private let htmlDocument: @MainActor (YouTubeHandoffRequest, UUID, String) -> String
    let playbackAuthorization = WebRTCControlAuthorization()
    private let stopMedia: @MainActor (WKWebView, @escaping @MainActor () -> Void) -> Void
    private var cleanupHandlers: [@MainActor () -> Void] = []
    private var closingWebView: WKWebView?
    private var cleanupStarted = false
    private(set) var cleanupCompleted = false
    private var presented = false
    private var sceneIsActive = false
    // Retain until exact stop acknowledgement even if SwiftUI removes the representable.
    private var webView: YouTubeHandoffWebView?
    private var ownedNavigation: WKNavigation?
    private var baseURL: URL?
    private var pollTask: Task<Void, Never>?
    private var hasCreatedWebView = false
    private static let handlerName = "belugaYouTubeHandoff"

    init(request: YouTubeHandoffRequest,
         now: @escaping @MainActor () -> Double = { ProcessInfo.processInfo.systemUptime },
         htmlDocument: (@MainActor (YouTubeHandoffRequest, UUID, String) -> String)? = nil,
         stopMedia: (@MainActor (WKWebView, @escaping @MainActor () -> Void) -> Void)? = nil,
         eventHandler: @escaping @MainActor (YouTubeHandoffPlayerEvent) -> Void) {
        self.request = request; self.now = now; self.eventHandler = eventHandler
        self.htmlDocument = htmlDocument ?? Self.html
        self.stopMedia = stopMedia ?? { view, completion in
            // Retain the exact view and serialize the two acknowledgements. Enqueuing either
            // API is not proof that media has stopped. No timeout may restore the audio lease.
            view.setAllMediaPlaybackSuspended(true) {
                view.pauseAllMediaPlayback { completion() }
            }
        }
        operation = YouTubeHandoffOperation(request: request, now: now())
        super.init()
    }

    func isCurrent(_ evidence: YouTubePhonePlaybackEvidence) -> Bool {
        synchronizeVisibility()
        let result = operation.isCurrent(evidence, now: now())
        publish(nil)
        return result
    }

    func beginMacPause(using evidence: YouTubePhonePlaybackEvidence) -> Bool {
        synchronizeVisibility()
        let result = operation.beginMacPause(using: evidence, now: now())
        publish(nil)
        return result
    }

    func receiveMacPauseCompletion(_ completion: WebRTCMediaHandoffCompletion) {
        synchronizeVisibility()
        publish(operation.completeMacPause(operationID: completion.id, result: completion.result, now: now()))
    }

    func setPresentation(isPresented: Bool, sceneIsActive: Bool) {
        presented = isPresented; self.sceneIsActive = sceneIsActive
        synchronizeVisibility()
    }

    func dismiss() { terminate(.dismissed) }
    func replace() { terminate(.replaced) }

    func afterMediaStopped(_ completion: @escaping @MainActor () -> Void) {
        if cleanupCompleted { completion() } else { cleanupHandlers.append(completion) }
    }

    func makeWebView() -> YouTubeHandoffWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        let view = YouTubeHandoffWebView(frame: .zero, configuration: configuration)
        view.isOpaque = true
        view.backgroundColor = .black
        view.scrollView.isScrollEnabled = false
        guard !hasCreatedWebView, !operation.isTerminal,
              let bundle = Bundle.main.bundleIdentifier?.lowercased(),
              Self.validBundleHost(bundle),
              let base = URL(string: "https://" + bundle + "/") else {
            terminate(.invalidRequest)
            return view
        }
        hasCreatedWebView = true; webView = view; baseURL = base
        view.onGeometryOrWindowChange = { [weak self] in self?.synchronizeVisibility() }
        configuration.userContentController.add(YouTubeHandoffMessageHandler(owner: self),
                                                name: Self.handlerName)
        view.navigationDelegate = self
        view.uiDelegate = self
        ownedNavigation = view.loadHTMLString(htmlDocument(request, operation.pageID, "https://" + bundle), baseURL: base)
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
                guard let self else { return }
                self.synchronizeVisibility()
                self.publish(self.operation.poll(now: self.now()))
                self.updatePageTimeline()
                if self.operation.isTerminal { return }
            }
        }
        return view
    }

    func dismantle(_ view: YouTubeHandoffWebView) {
        guard webView === view else { return }
        terminate(.dismissed)
    }

    private func synchronizeVisibility() {
        let visible = presented && sceneIsActive && webView?.window != nil
            && (webView?.bounds.width ?? 0) >= 200 && (webView?.bounds.height ?? 0) >= 200
            && webView?.isHidden == false && (webView?.alpha ?? 0) > 0
        let changed = visible != operation.isVisible
        publish(operation.visibilityChanged(visible, now: now()))
        guard !operation.isTerminal, changed else { return }
        updatePageVisibility()
    }

    private func updatePageVisibility() {
        updatePageTimeline()
        webView?.evaluateJavaScript("if (typeof window.belugaHandoffVisibility === 'function') { window.belugaHandoffVisibility(\(operation.isVisible ? "true" : "false")); }", completionHandler: nil)
    }

    private func updatePageTimeline() {
        guard !operation.isTerminal, operation.phase != .localPlayback else { return }
        let position = request.expectedPosition(at: now())
        guard position.isFinite else { return }
        webView?.evaluateJavaScript("if (typeof window.belugaHandoffTimeline === 'function') { window.belugaHandoffTimeline(\(position)); }", completionHandler: nil)
    }

    fileprivate func receive(_ message: WKScriptMessage) {
        guard let view = webView, message.webView === view,
              message.name == Self.handlerName, ownedNavigation != nil,
              message.frameInfo.isMainFrame, let base = baseURL,
              message.frameInfo.securityOrigin.protocol == "https",
              message.frameInfo.securityOrigin.host == base.host,
              [0, 443].contains(message.frameInfo.securityOrigin.port),
              message.frameInfo.request.url == base else { return }
        synchronizeVisibility()
        guard !operation.isTerminal else { return }
        guard let decoded = YouTubeHandoffBridgeMessage(body: message.body) else {
            terminate(.invalidBridge); return
        }
        publish(operation.receive(decoded, now: now()))
    }

    private func terminate(_ reason: YouTubeHandoffFailure) { publish(operation.fail(reason)) }

    private func publish(_ event: YouTubeHandoffPlayerEvent?) {
        if operation.isTerminal || operation.phase == .localPlayback
            || operation.evidence.map({ !operation.isCurrent($0, now: now()) }) == true {
            playbackAuthorization.revoke()
        }
        macPauseStatus = operation.macPauseStatus
        phase = operation.phase
        if operation.isTerminal { closeWebView() }
        if let event { eventHandler(event) }
    }

    private func closeWebView() {
        pollTask?.cancel(); pollTask = nil
        guard !cleanupStarted else { return }
        cleanupStarted = true
        guard let view = webView else { finishCleanup(); return }
        closingWebView = view
        webView = nil; ownedNavigation = nil
        view.onGeometryOrWindowChange = nil
        view.configuration.userContentController.removeScriptMessageHandler(forName: Self.handlerName)
        view.configuration.userContentController.removeAllUserScripts()
        view.navigationDelegate = nil; view.uiDelegate = nil
        view.isHidden = true
        view.stopLoading()
        stopMedia(view) { [self, view] in
            guard closingWebView === view else { return }
            view.loadHTMLString("<!doctype html><html><body></body></html>", baseURL: nil)
            closingWebView = nil
            finishCleanup()
        }
    }

    private func finishCleanup() {
        guard !cleanupCompleted else { return }
        cleanupCompleted = true
        let handlers = cleanupHandlers; cleanupHandlers.removeAll()
        for handler in handlers { handler() }
    }

    private static func validBundleHost(_ value: String) -> Bool {
        value.utf8.count <= 253 && value.split(separator: ".", omittingEmptySubsequences: false).count >= 2
            && value.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
                !label.isEmpty && label.utf8.count <= 63 && label.first != "-" && label.last != "-"
                    && label.utf8.allSatisfy { (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }
            }
    }

    // Uses only validated ASCII IDs and finite numbers; no source URL or arbitrary HTML enters.
    private static func html(request: YouTubeHandoffRequest, pageID: UUID, origin: String) -> String {
        """
        <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;background:black;width:100%;height:100%}#player{width:100%;height:100%;min-width:200px;min-height:200px}</style>
        </head><body><div id="player"></div><script>
        (() => {
          'use strict';
          const operation='\(request.operationID.uuidString.lowercased())';
          const page='\(pageID.uuidString.lowercased())', expected='\(request.videoID)';
          const position=\(request.positionSeconds), rate=\(request.playbackRate);
          let player=null, ready=false, visible=false, retired=false, sequence=0;
          let anchor=null, anchorTime=0, aligned=false;
          window.belugaHandoffTimeline=value=>{
            if(retired || !Number.isFinite(value) || value<position) return;
            const first=anchor===null;
            anchor=value; anchorTime=performance.now();
            if(first) start();
          };
          function target(){return anchor===null?null:anchor+(performance.now()-anchorTime)/1000*rate;}
          function currentVideo() {
            if(!ready) return expected;
            try { const u=new URL(player.getVideoUrl()); const ids=u.searchParams.getAll('v');
              return u.protocol==='https:' && u.hostname==='www.youtube.com' && u.pathname==='/watch'
                && ids.length===1 && /^[A-Za-z0-9_-]{11}$/.test(ids[0]) ? ids[0] : ''; }
            catch (_) { return ''; }
          }
          function emit(kind, extra) {
            if(retired || sequence>=4294967295) return;
            const message=Object.assign({kind,operation,page,video:currentVideo(),sequence:++sequence},extra||{});
            window.webkit.messageHandlers.belugaYouTubeHandoff.postMessage(message);
          }
          function sample() {
            if(!ready || !visible || retired || document.visibilityState==='hidden') return;
            emit('sample',{state:player.getPlayerState(),position:player.getCurrentTime(),
              duration:player.getDuration(),rate:player.getPlaybackRate()});
          }
          function start() {
            if(!ready || !visible || retired || document.visibilityState==='hidden') return;
            const rates=player.getAvailablePlaybackRates();
            if(!rates.some(r=>Math.abs(r-rate)<0.01)) { emit('unsupportedRate'); player.pauseVideo(); return; }
            const current=target(); if(current===null) return;
            player.seekTo(current,true); player.setPlaybackRate(rate); player.playVideo();
          }
          window.belugaHandoffVisibility=value=>{
            if(retired || visible===value) return;
            visible=value===true;
            if(visible) start(); else if(ready) player.pauseVideo();
          };
          window.onYouTubeIframeAPIReady=()=>{
            if(retired) return;
            player=new YT.Player('player',{width:'100%',height:'100%',videoId:expected,
              playerVars:{playsinline:1,controls:1,autoplay:0,origin:'\(origin)'},
              events:{onReady:()=>{ready=true;player.cueVideoById({videoId:expected,startSeconds:position});emit('ready');start();},
                onStateChange:()=>{
                  if(!aligned && visible && player.getPlayerState()===1) {
                    const current=target(); if(current===null) return;
                    aligned=true; player.seekTo(current,true);
                  }
                  sample();
                },onPlaybackRateChange:()=>sample(),
                onAutoplayBlocked:()=>emit('blocked'),onError:()=>emit('error')}});
          };
          const timer=setInterval(sample,250);
          function retire(){if(retired)return;emit('error');retired=true;visible=false;clearInterval(timer);if(player)player.destroy();}
          document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='hidden')retire();});
          window.addEventListener('pagehide',retire);
          const api=document.createElement('script');api.src='https://www.youtube.com/iframe_api';
          api.onerror=()=>emit('error');document.head.appendChild(api);
        })();
        </script></body></html>
        """
    }
}

extension YouTubeHandoffPlayer: WKNavigationDelegate, WKUIDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
        guard self.webView === webView, !operation.isTerminal else { decisionHandler(.cancel); return }
        let url = navigationAction.request.url
        if navigationAction.targetFrame?.isMainFrame == true {
            let allowed = url == baseURL && navigationAction.navigationType == .other
            decisionHandler(allowed ? .allow : .cancel)
            if !allowed { terminate(.playerUnavailable) }
        } else {
            let allowed = navigationAction.targetFrame != nil && (url?.absoluteString == "about:blank"
                || (url?.scheme == "https" && url?.host == "www.youtube.com"
                    && url?.path == "/embed/" + request.videoID))
            decisionHandler(allowed ? .allow : .cancel)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard self.webView === webView, navigation === ownedNavigation else { return }
        synchronizeVisibility()
        // The first layout may precede the page script. Replay current visibility after load,
        // even when native visibility itself did not change in that interval.
        if !operation.isTerminal { updatePageVisibility() }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        guard self.webView === webView, navigation === ownedNavigation else { return }
        terminate(.playerUnavailable)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard self.webView === webView, navigation === ownedNavigation else { return }
        terminate(.playerUnavailable)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard self.webView === webView else { return }
        terminate(.playerUnavailable)
    }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? { nil }
}

@MainActor
private final class YouTubeHandoffMessageHandler: NSObject, WKScriptMessageHandler {
    weak var owner: YouTubeHandoffPlayer?
    init(owner: YouTubeHandoffPlayer) { self.owner = owner }
    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        owner?.receive(message)
    }
}

@MainActor
final class YouTubeHandoffWebView: WKWebView {
    var onGeometryOrWindowChange: (() -> Void)?
    override func didMoveToWindow() { super.didMoveToWindow(); onGeometryOrWindowChange?() }
    override func layoutSubviews() { super.layoutSubviews(); onGeometryOrWindowChange?() }
}
