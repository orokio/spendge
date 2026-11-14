import SwiftUI
import UIKit

/// 系统分享面板：导出文件、分享图片都用它。
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    var onFinish: (Bool) -> Void = { _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        // 分享面板关掉后回调：用户真的存/发出去了才提示
        controller.completionWithItemsHandler = { _, completed, _, _ in
            onFinish(completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
