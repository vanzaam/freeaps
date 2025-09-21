import Foundation

struct Script {
    let name: String
    let body: String

    init(name: String) {
        self.name = name
        let raw = try! String(contentsOf: Bundle.main.url(forResource: "javascript/\(name)", withExtension: "")!)
        body = raw + "\n//# sourceURL=\(name)"
    }

    init(name: String, body: String) {
        self.name = name
        self.body = body + "\n//# sourceURL=\(name)"
    }
}
