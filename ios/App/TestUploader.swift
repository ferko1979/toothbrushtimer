import BrushCore
import Foundation

/// Test mode: every recording, timeline and remark goes up to the DentHub-Brush server on its own
/// (web/testupload.mjs; from there to Google Drive). What is up is listed in recordings/.uploaded
/// ("name:size"), so a remark edited later goes up again. Without network it waits for the next try
/// (after a recording, a remark, opening the app, or "Feltöltés most"). Same as TestUploader.kt.
final class TestUploader: ObservableObject {
    static let shared = TestUploader()
    @Published private(set) var status = ""
    private var running = false

    func uploadPending(model: AppModel) {
        guard let code = model.data.testerCode, model.settings.isOn("test_recording", platform: .ios), !running else { return }
        running = true
        let host = (model.data.denthubHost ?? TestAccess.defaultHost).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let dir = AppModel.recordingsDir
        DispatchQueue.global(qos: .utility).async {
            let message = self.run(dir: dir, host: host, code: code)
            DispatchQueue.main.async { self.status = message; self.running = false }
        }
    }

    private func set(_ s: String) { DispatchQueue.main.async { self.status = s } }

    private func run(dir: URL, host: String, code: String) -> String {
        let list = dir.appendingPathComponent(".uploaded")
        var done = Set(((try? String(contentsOf: list, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init))
        let todo = TestAccess.pending(in: dir, uploaded: done)
        if todo.isEmpty { return tr("✓ Minden felvétel feltöltve.") }
        let device = deviceId(dir)
        for (i, f) in todo.enumerated() {
            set(tr("Feltöltés: {0} / {1}…", i + 1, todo.count))
            guard let url = URL(string: host + "/api/test-upload/" + f.lastPathComponent) else { return "" }
            var req = URLRequest(url: url, timeoutInterval: 60)
            req.httpMethod = "POST"
            req.setValue(code, forHTTPHeaderField: "X-Tester-Code")
            req.setValue(device, forHTTPHeaderField: "X-Tester-Device")
            req.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let sem = DispatchSemaphore(value: 0)
            var rc = 0
            URLSession.shared.uploadTask(with: req, fromFile: f) { _, resp, _ in
                rc = (resp as? HTTPURLResponse)?.statusCode ?? 0
                sem.signal()
            }.resume()
            sem.wait()
            if rc == 0 { return tr("Nincs kapcsolat a szerverrel, később újra próbálom.") }
            if rc == 401 { return tr("A szerver nem fogadta el a tesztelői jelszót.") }
            if !(200..<300).contains(rc) { return tr("Feltöltés sikertelen ({0}), később újra próbálom.", rc) }
            done.insert(TestAccess.key(f))
            try? done.joined(separator: "\n").write(to: list, atomically: true, encoding: .utf8)
        }
        return tr("✓ {0} fájl feltöltve.", todo.count)
    }

    /// A random id per install, so the recordings of one phone stay together.
    private func deviceId(_ dir: URL) -> String {
        let f = dir.appendingPathComponent(".device")
        if let s = try? String(contentsOf: f, encoding: .utf8), !s.isEmpty { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        let id = "ios-" + UUID().uuidString.prefix(8).lowercased()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? id.write(to: f, atomically: true, encoding: .utf8)
        return id
    }
}
