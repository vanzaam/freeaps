import Foundation
import JavaScriptCore

private let contextLock = NSRecursiveLock()

final class JavaScriptWorker {
    private let processQueue = DispatchQueue(label: "DispatchQueue.JavaScriptWorker")
    private let virtualMachine: JSVirtualMachine
    @SyncAccess(lock: contextLock) private var commonContext: JSContext? = nil

    init() {
        virtualMachine = processQueue.sync { JSVirtualMachine()! }
    }

    private func createContext() -> JSContext {
        let context = JSContext(virtualMachine: virtualMachine)!
        context.exceptionHandler = { _, exception in
            if let exc = exception, let error = exc.toString() {
                var location = ""
                if let file = exc.forProperty("sourceURL")?.toString(),
                   let line = exc.forProperty("line")?.toString()
                {
                    location = " (\(file):\(line))"
                }
                warning(.openAPS, "JavaScript Error: \(error)\(location)")
            }
        }
        let consoleLog: @convention(block) (String) -> Void = { message in
            debug(.openAPS, "JavaScript log: \(message)")
        }

        context.setObject(
            consoleLog,
            forKeyedSubscript: "_consoleLog" as NSString
        )
        return context
    }

    @discardableResult func evaluate(script: Script) -> JSValue! {
        evaluate(string: script.body)
    }

    private func evaluate(string: String) -> JSValue! {
        if Bundle.main.object(forInfoDictionaryKey: "USE_LOOP_ENGINE") as? String == "YES" {
            warning(.openAPS, "JavaScript evaluate skipped (USE_LOOP_ENGINE)")
            return nil
        }
        let ctx = commonContext ?? createContext()
        let result = ctx.evaluateScript(string)
        if let exc = ctx.exception, let error = exc.toString() {
            var location = ""
            if let file = exc.forProperty("sourceURL")?.toString(),
               let line = exc.forProperty("line")?.toString()
            {
                location = " (\(file):\(line))"
            }
            warning(.openAPS, "JavaScript Error: \(error)\(location)")
        }
        return result
    }

    private func json(for callable: String, args: String) -> RawJSON {
        let wrapped = """
        (function(){
            try {
                if (typeof \(callable) !== 'function') {
                    return JSON.stringify({ error: "Function \(callable) is not defined" }, null, 4);
                }
                return JSON.stringify(\(callable)(\(args)), null, 4);
            } catch (e) {
                return JSON.stringify({ error: String(e), stack: e && e.stack }, null, 4);
            }
        })();
        //# sourceURL=call:\(callable)
        """
        let result = evaluate(string: wrapped)
        guard let jsonString = result?.toString(), !jsonString.isEmpty else {
            warning(.openAPS, "JavaScript returned empty or null JSON for call: \(callable)")
            return "{}"
        }
        return jsonString
    }

    func call(function: String, with arguments: [JSON]) -> RawJSON {
        if Bundle.main.object(forInfoDictionaryKey: "USE_LOOP_ENGINE") as? String == "YES" {
            warning(.openAPS, "JavaScript call skipped (USE_LOOP_ENGINE)")
            return "{}"
        }
        // Sanitize empty JSON arguments to avoid constructs like function(a,,c) → SyntaxError: Unexpected token ','
        let joined = arguments
            .map { arg -> String in
                let s = arg.rawJSON.trimmingCharacters(in: .whitespacesAndNewlines)
                return s.isEmpty ? "null" : s
            }
            .joined(separator: ",")
        return json(for: function, args: joined)
    }

    func inCommonContext<Value>(execute: (JavaScriptWorker) -> Value) -> Value {
        commonContext = createContext()
        defer {
            commonContext = nil
        }
        return execute(self)
    }
}
