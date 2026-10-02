import Capacitor
import Photos
import UIKit

/// アプリ専用のネイティブ機能（写真への直接保存・Instagram への受け渡し・外部 URL を開く）。
/// ウェブ側からは `Capacitor.nativePromise('SquadXI', <method>, {...})` で呼び出す。
@objc(SquadXIPlugin)
public class SquadXIPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SquadXIPlugin"
    public let jsName = "SquadXI"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "saveImage", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "shareInstagram", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "openUrl", returnType: CAPPluginReturnPromise)
    ]

    /// 画像（base64）を写真アプリに保存する。
    @objc func saveImage(_ call: CAPPluginCall) {
        saveToPhotos(call) { _ in
            call.resolve()
        }
    }

    /// 画像を写真アプリに保存し、Instagram の新規投稿画面をその画像で開く。
    /// Instagram が入っていなければ保存だけ行い `opened: false` を返す。
    @objc func shareInstagram(_ call: CAPPluginCall) {
        saveToPhotos(call) { localIdentifier in
            DispatchQueue.main.async {
                guard let url = URL(string: "instagram://library?LocalIdentifier=\(localIdentifier)"),
                      UIApplication.shared.canOpenURL(url) else {
                    call.resolve(["opened": false])
                    return
                }
                UIApplication.shared.open(url, options: [:]) { opened in
                    call.resolve(["opened": opened])
                }
            }
        }
    }

    /// http(s) の URL を OS に渡して開く（X の投稿画面など。アプリが入っていればアプリで開く）。
    @objc func openUrl(_ call: CAPPluginCall) {
        guard let string = call.getString("url"),
              let url = URL(string: string),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http" else {
            call.reject("Invalid URL")
            return
        }
        DispatchQueue.main.async {
            UIApplication.shared.open(url, options: [:]) { opened in
                call.resolve(["opened": opened])
            }
        }
    }

    private func saveToPhotos(_ call: CAPPluginCall, completion: @escaping (String) -> Void) {
        guard let base64 = call.getString("data"),
              let data = Data(base64Encoded: base64),
              UIImage(data: data) != nil else {
            call.reject("Invalid image data")
            return
        }
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                call.reject("Photo library access denied", "PERMISSION_DENIED")
                return
            }
            let created = CreatedAsset()
            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetCreationRequest.forAsset()
                request.addResource(with: .photo, data: data, options: nil)
                created.localIdentifier = request.placeholderForCreatedAsset?.localIdentifier
            }, completionHandler: { success, error in
                if success, let localIdentifier = created.localIdentifier {
                    completion(localIdentifier)
                } else {
                    call.reject(error?.localizedDescription ?? "Could not save the image", "SAVE_FAILED")
                }
            })
        }
    }
}

/// 写真ライブラリの変更ブロックで作られた写真の ID を、完了ハンドラへ渡すための入れ物
private final class CreatedAsset {
    var localIdentifier: String?
}

/// squadxi.futbol のページに差し込むスクリプト。
/// 共有プレビューの「画像を保存」「Instagram」「X」を、iOS の共有シートを経由せずネイティブ処理につなぐ。
/// ウェブ側の作り（ボタン ID・navigator.share・a[download]・window.open）が変わって
/// 条件に合わなくなった場合は何もせず、これまでどおりウェブ側の処理が動く。
let squadXIBridgeScript = #"""
(function () {
  if (window.__squadxiNative) return;
  window.__squadxiNative = true;
  var cap = window.Capacitor;
  if (!cap || typeof cap.nativePromise !== 'function') return;

  function callNative(method, options) {
    return cap.nativePromise('SquadXI', method, options || {});
  }
  function blobToBase64(blob) {
    return new Promise(function (resolve, reject) {
      var reader = new FileReader();
      reader.onload = function () { resolve(String(reader.result).split(',')[1] || ''); };
      reader.onerror = function () { reject(reader.error); };
      reader.readAsDataURL(blob);
    });
  }
  function isEnglish() {
    try { return LANG === 'en'; } catch (e) { return document.documentElement.lang === 'en'; }
  }
  function say(key, ja, en) {
    var message = isEnglish() ? en : ja;
    try { if (key && typeof t === 'function') message = t(key); } catch (e) {}
    try { if (typeof toast === 'function') toast(message); } catch (e) {}
  }
  function reportError(error) {
    if (error && error.code === 'PERMISSION_DENIED') {
      say(null, '写真への保存が許可されていません。設定アプリ →「Squad XI」→「写真」で許可してください',
        'Saving to Photos is not allowed. Turn it on in Settings > Squad XI > Photos.');
    } else {
      say(null, '画像を保存できませんでした', 'Could not save the image');
    }
  }
  function saveBlob(blob, doneKey) {
    return blobToBase64(blob)
      .then(function (data) { return callNative('saveImage', { data: data }); })
      .then(function () { say(doneKey, '画像を保存しました', 'Image saved'); }, reportError);
  }

  // どのボタンが押されたかを記録する（キャプチャ段階なので、ウェブ側のハンドラより先に走る）
  var pending = null, pendingAt = 0;
  document.addEventListener('click', function (event) {
    var el = event.target && event.target.closest ? event.target.closest('#shDl,#shIG,#shX') : null;
    if (el) { pending = el.id; pendingAt = Date.now(); }
  }, true);
  function takePending() {
    var id = Date.now() - pendingAt < 3000 ? pending : null;
    pending = null;
    return id;
  }

  // 「画像を保存」「Instagram」は navigator.share({files:[画像]}) を呼ぶ → 共有シートの代わりにネイティブ処理
  if (typeof navigator.share === 'function') {
    var originalShare = navigator.share.bind(navigator);
    navigator.share = function (data) {
      var file = data && data.files && data.files.length === 1 ? data.files[0] : null;
      var button = takePending();
      if (file && /^image\//.test(file.type)) {
        if (button === 'shDl') return saveBlob(file, 'tstImgSaved');
        if (button === 'shIG') {
          return blobToBase64(file)
            .then(function (d) { return callNative('shareInstagram', { data: d }); })
            .then(function (result) {
              if (!result || !result.opened) say('tstImgSavedIG', '画像を保存しました。Instagramで投稿してください', 'Image saved. Post it on Instagram.');
            }, reportError);
        }
      }
      return originalShare(data);
    };
  }

  // 「X」は a[download] で画像を落としてから window.open で投稿画面を開く。
  // アプリ内では blob: を開けず画像が残らないため、写真に保存し、保存が終わってから X を開く
  var lastSave = null;
  var originalClick = HTMLAnchorElement.prototype.click;
  HTMLAnchorElement.prototype.click = function () {
    var href = this.href || '';
    if (this.download && /\.(png|jpe?g)$/i.test(this.download) && /^(blob|data):/.test(href)) {
      lastSave = fetch(href)
        .then(function (r) { return r.blob(); })
        .then(function (blob) { return saveBlob(blob, 'tstImgSavedX'); })
        .catch(function () {});
      return;
    }
    return originalClick.apply(this, arguments);
  };
  var originalOpen = window.open;
  window.open = function (url) {
    if (lastSave && /^https:\/\/(twitter|x)\.com\/intent\//.test(String(url))) {
      var saving = lastSave;
      lastSave = null;
      saving.then(function () { return callNative('openUrl', { url: String(url) }); }).catch(function () {});
      return null;
    }
    return originalOpen.apply(window, arguments);
  };
})();
"""#
