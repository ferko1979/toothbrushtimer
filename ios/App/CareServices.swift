import AVFoundation
import BrushCore
import LocalAuthentication
import SwiftUI
import UIKit

/// Face ID / Touch ID / passcode (LocalAuthentication).
enum DeviceAuth {
    static var available: Bool {
        var err: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &err)
    }

    /// Calls back with true when the owner was verified, or when the device has no passcode at all.
    static func authenticate(reason: String, _ done: @escaping (Bool) -> Void) {
        let ctx = LAContext()
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthentication, error: &err) else { done(true); return }
        ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, _ in
            DispatchQueue.main.async { done(ok) }
        }
    }
}

/// App lock and parent lock state. Locks again when the app leaves the foreground.
final class AppLock: ObservableObject {
    static let shared = AppLock()
    @Published var unlocked = false
    @Published var parentUnlocked = false

    func lock() {
        unlocked = false
        parentUnlocked = false
    }
}

/// Dentist report as an A4 PDF in the temporary directory.
enum ReportPDF {
    static func write(_ report: DentistReport) -> URL? {
        let page = CGRect(x: 0, y: 0, width: 595, height: 842)
        let margin: CGFloat = 48
        let width = page.width - 2 * margin
        let renderer = UIGraphicsPDFRenderer(bounds: page)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fogapolasi-jelentes.pdf")
        let title: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 20), .foregroundColor: UIColor.black]
        let head: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 14),
                                                   .foregroundColor: UIColor(red: 0.118, green: 0.608, blue: 0.722, alpha: 1)]
        let body: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkText]
        let muted: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray]
        do {
            try renderer.writePDF(to: url) { ctx in
                var y = margin
                ctx.beginPage()
                func draw(_ text: String, _ attrs: [NSAttributedString.Key: Any], indent: CGFloat = 0, after: CGFloat = 4) {
                    let s = NSAttributedString(string: text, attributes: attrs)
                    let h = ceil(s.boundingRect(with: CGSize(width: width - indent, height: .greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
                    if y + h > page.height - margin { ctx.beginPage(); y = margin }
                    s.draw(with: CGRect(x: margin + indent, y: y, width: width - indent, height: h),
                           options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
                    y += h + after
                }
                draw(report.title, title)
                draw(report.subtitle, muted, after: 16)
                for sec in report.sections {
                    draw(sec.title, head, after: 6)
                    for l in sec.lines { draw("•  " + l, body, indent: 8) }
                    y += 10
                }
                draw("Készült a Fogmosás appal. A tünetek a felhasználó saját jelölései, nem orvosi diagnózis.", muted)
            }
            return url
        } catch {
            return nil
        }
    }
}

/// "Megnézem a weben": encrypt a snapshot to the web page's key and post it to the relay.
enum WebShare {
    /// Adult profile: the whole family; a child: only that child.
    static func snapshotJSON(model: AppModel) throws -> Data {
        let active = model.activeProfile
        let profiles = active.child ? [active] : model.data.profiles
        let snaps = profiles.map {
            WebLink.profileSnapshot($0, records: model.records(for: $0.id), care: model.care(for: $0.id), today: Date(),
                                    flossTracked: model.settings.isOn("floss_tracking"), coach: model.coach)
        }
        return try WebLink.snapshotJSON(WebLink.snapshot(snaps, now: Date(), locale: model.settings.locale))
    }

    /// Calls back with nil on success, or a message for the user.
    static func send(_ pairing: WebLink.Pairing, json: Data, _ done: @escaping (String?) -> Void) {
        let env: Data
        do { env = try WebLink.seal(webPublicKey: pairing.webPublicKey, sid: pairing.sid, plaintext: json) } catch {
            done("A QR-kód hibás. Kérj új kódot a weboldalon."); return
        }
        var req = URLRequest(url: pairing.uploadURL, timeoutInterval: 15)
        req.httpMethod = "POST"
        req.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        req.httpBody = Data(WebLink.b64(env).utf8)
        URLSession.shared.dataTask(with: req) { _, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let msg: String?
            if err != nil { msg = "Nem sikerült elérni a weboldalt. Ellenőrizd az internetkapcsolatot." }
            else if code == 204 || code == 200 { msg = nil }
            else if code == 409 { msg = "Ezt a kódot már felhasználtad. Kérj új kódot a weboldalon." }
            else { msg = "A szerver hibát jelzett (\(code))." }
            DispatchQueue.main.async { done(msg) }
        }.resume()
    }
}

/// Camera QR scanner (AVFoundation metadata output).
struct QRScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerController {
        let c = ScannerController()
        c.onCode = onCode
        return c
    }

    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}

    final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var done = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else { return }
            session.addInput(input)
            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else { return }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.qr]
            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(layer)
            preview = layer
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)
            let s = session
            DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            let s = session
            DispatchQueue.global(qos: .userInitiated).async { s.stopRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !done, let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject, let s = obj.stringValue else { return }
            done = true
            onCode?(s)
        }
    }
}

/// Share sheet for a file (the PDF report).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
