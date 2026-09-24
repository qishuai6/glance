import Foundation
import QuickLookUI

// Quick Look 预览扩展入口：按空格键时由 QuickLookUIService 加载本进程。
final class PreviewProvider: QLPreviewProvider, QLPreviewingController {
    func providePreview(for request: QLFilePreviewRequest,
                        completionHandler: @escaping (QLPreviewReply?, (any Error)?) -> Void) {
        let url = request.fileURL
        let reply = QLPreviewReply(dataOfContentType: .html,
                                   contentSize: CGSize(width: 860, height: 640)) { _ in
            let html = RendererHub.render(url: url)
            return Data(html.utf8)
        }
        completionHandler(reply, nil)
    }
}
