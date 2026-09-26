import QuickLook
import WebKit

@MainActor
final class WebDocumentService: NSObject, WKDownloadDelegate, QLPreviewControllerDataSource, QLPreviewControllerDelegate {
    private weak var presenter: UIViewController?
    private var downloads: [ObjectIdentifier: (WKDownload, URL)] = [:]
    private var preview: URL?
    private var stopped = false

    init(presenter: UIViewController) { self.presenter = presenter }

    func receive(_ download: WKDownload) {
        if stopped { download.cancel { _ in }; return }
        download.delegate = self
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void) {
        guard !stopped else { completionHandler(nil); return }
        do {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let name = (suggestedFilename as NSString).lastPathComponent
            let safeName = name.isEmpty || name == "." || name == ".." ? "document" : name
            let file = directory.appendingPathComponent(safeName)
            downloads[ObjectIdentifier(download)] = (download, file)
            completionHandler(file)
        } catch { completionHandler(nil) }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let (_, file) = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        guard let presenter, presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil,
            preview == nil else { remove(file); return }
        preview = file
        let controller = QLPreviewController()
        controller.dataSource = self
        controller.delegate = self
        presenter.present(controller, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let (_, file) = downloads.removeValue(forKey: ObjectIdentifier(download)) { remove(file) }
    }
    func download(_ download: WKDownload, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void) { decisionHandler(.cancel) }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { preview == nil ? 0 : 1 }
    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { preview! as NSURL }
    func previewControllerDidDismiss(_ controller: QLPreviewController) {
        if let preview { remove(preview) }
        preview = nil
    }
    func stop() {
        stopped = true
        for (_, (download, file)) in downloads { download.cancel { _ in }; remove(file) }
        downloads.removeAll()
        if let preview { remove(preview) }
        preview = nil
    }
    private func remove(_ file: URL) { try? FileManager.default.removeItem(at: file.deletingLastPathComponent()) }
}
