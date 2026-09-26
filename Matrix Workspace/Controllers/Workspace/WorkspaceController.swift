import UIKit
import WebKit

@MainActor
final class WorkspaceController: UIViewController, WKNavigationDelegate, WKUIDelegate {
    private let bridge: MatrixWebBridge
    private let sessionId: UUID
    private var route = "/"
    private var active = true
    private var stopped = false
    private lazy var documents = WebDocumentService(presenter: self)
    private lazy var customView: WorkspaceView = {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WebDataStoreService.dataStore(for: sessionId)
        config.allowsInlineMediaPlayback = true
        config.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: "matrix")
        return WorkspaceView(configuration: config)
    }()

    init(auth: AuthService, calls: NativeCallCoordinator, server: ServerAddress, sessionId: UUID) {
        self.sessionId = sessionId
        bridge = MatrixWebBridge(server: server, auth: auth, calls: calls)
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
    override func loadView() { view = customView }
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Матрица"
        customView.webView.navigationDelegate = self
        customView.webView.uiDelegate = self
        customView.onRetry = { [weak self] in self?.open(route: self?.route ?? "/") }
        open(route: route)
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(true, animated: animated)
    }
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.setNavigationBarHidden(false, animated: animated)
    }
    func open(route: String) {
        guard !stopped else { return }
        self.route = route
        guard isViewLoaded else { return }
        customView.showError(nil)
        customView.webView.load(URLRequest(url: bridge.applicationURL(route: route)))
    }
    func setActive(_ active: Bool) {
        guard !stopped else { return }
        self.active = active
        guard isViewLoaded else { return }
        customView.webView.evaluateJavaScript("window.matrixNativeActive = \(active); window.dispatchEvent(new CustomEvent('matrix-native:active', {detail: \(active)}))", completionHandler: nil)
    }
    func stop() {
        guard !stopped else { return }
        stopped = true
        if isViewLoaded {
            customView.webView.stopLoading()
            customView.webView.configuration.userContentController.removeScriptMessageHandler(forName: "matrix", contentWorld: .page)
            documents.stop()
            customView.webView.navigationDelegate = nil
            customView.webView.uiDelegate = nil
            customView.webView.loadHTMLString("", baseURL: nil)
        }
        dismiss(animated: false)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { setActive(active) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { webView.reload() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { customView.showError("Не удалось открыть Матрицу. Проверьте соединение.") }
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if bridge.isLocalBlob(url), navigationAction.targetFrame?.isMainFrame != false {
            decisionHandler(.download)
            return
        }
        if navigationAction.targetFrame?.isMainFrame == false {
            decisionHandler(.allow)
        } else if bridge.isApplication(url) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
            if navigationAction.navigationType == .linkActivated,
                ["https", "mailto", "tel"].contains(url.scheme ?? "") {
                UIApplication.shared.open(url)
            } else if !bridge.isApplication(webView.url) {
                customView.showError("Не удалось открыть Матрицу: сервер перенаправил на адрес вне приложения.")
            }
        }
    }
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        documents.receive(download)
    }
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        documents.receive(download)
    }
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url, bridge.isApplication(url) { webView.load(navigationAction.request) }
        return nil
    }
    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        guard bridge.isApplication(frame.request.url) else { completionHandler(false); return }
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "Продолжить", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }
}
