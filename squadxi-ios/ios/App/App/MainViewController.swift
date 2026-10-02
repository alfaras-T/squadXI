import Capacitor
import UIKit
import WebKit

/// Main.storyboard の画面。Capacitor の標準画面に、アプリ専用のプラグインとスクリプトを足す。
class MainViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(SquadXIPlugin())
        // Capacitor は webViewConfiguration(for:) の後に userContentController を差し替えるため、ここで追加する
        webView?.configuration.userContentController.addUserScript(
            WKUserScript(source: squadXIBridgeScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        )
    }
}
