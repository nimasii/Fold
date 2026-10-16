import Foundation

/// Ephemeral (foreground) transfers intentionally reject EVERY redirect. Apple's background
/// sessions always follow redirects and cannot enforce this app's cookie/origin boundary.
nonisolated final class OfflineTransferDelegate: NSObject, URLSessionDownloadDelegate {
    let disk: OfflineDiskStore
    @MainActor weak var owner: OfflineLibrary?
    init(disk: OfflineDiskStore) { self.disk = disk }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        let description = downloadTask.taskDescription
        Task { @MainActor [weak self] in self?.owner?.progress(description, bytes: totalBytesWritten, total: totalBytesExpectedToWrite) }
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let description = downloadTask.taskDescription
        let response = downloadTask.response as? HTTPURLResponse
        do {
            let staged = try disk.stage(location)
            Task { @MainActor [weak self, disk] in
                guard let owner = self?.owner else { disk.discard(staged); return }
                owner.finish(description, response: response, staged: staged)
            }
        } catch {
            Task { @MainActor [weak self] in self?.owner?.fail(description, failure: .storage) }
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let description = task.taskDescription
        let code = (error as NSError).code
        let failure: OfflineFailure = [NSURLErrorCannotWriteToFile, NSURLErrorCannotCreateFile].contains(code) ? .storage : .network
        Task { @MainActor [weak self] in self?.owner?.fail(description, failure: failure) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust
                          ? .performDefaultHandling : .cancelAuthenticationChallenge, nil)
    }
}
