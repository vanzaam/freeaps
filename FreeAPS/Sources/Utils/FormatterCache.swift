import Foundation

/// Lightweight cache for DateFormatter/NumberFormatter.
/// Thread-safe via a serial queue. Returns shared instances keyed by settings.
enum FormatterCache {
    private static var dateFormatters: [String: DateFormatter] = [:]
    private static var numberFormatters: [String: NumberFormatter] = [:]
    private static let queue = DispatchQueue(label: "freeaps.formatterCache")

    static func dateFormatter(
        dateStyle: DateFormatter.Style = .none,
        timeStyle: DateFormatter.Style = .none,
        locale: Locale = .current
    ) -> DateFormatter {
        let key = "d:\(dateStyle.rawValue)-t:\(timeStyle.rawValue)-l:\(locale.identifier)"
        return queue.sync {
            if let cached = dateFormatters[key] { return cached }
            let f = DateFormatter()
            f.locale = locale
            f.dateStyle = dateStyle
            f.timeStyle = timeStyle
            dateFormatters[key] = f
            return f
        }
    }

    static func dateFormatter(
        format: String,
        locale: Locale = .current
    ) -> DateFormatter {
        let key = "f:\(format)-l:\(locale.identifier)"
        return queue.sync {
            if let cached = dateFormatters[key] { return cached }
            let f = DateFormatter()
            f.locale = locale
            f.dateFormat = format
            dateFormatters[key] = f
            return f
        }
    }

    static func numberFormatter(
        style: NumberFormatter.Style = .decimal,
        minFractionDigits: Int = 0,
        maxFractionDigits: Int = 0,
        positivePrefix: String? = nil,
        locale: Locale = .current
    ) -> NumberFormatter {
        let key =
            "s:\(style.rawValue)-min:\(minFractionDigits)-max:\(maxFractionDigits)-pp:\(positivePrefix ?? "-")-l:\(locale.identifier)"
        return queue.sync {
            if let cached = numberFormatters[key] { return cached }
            let f = NumberFormatter()
            f.locale = locale
            f.numberStyle = style
            f.minimumFractionDigits = minFractionDigits
            f.maximumFractionDigits = maxFractionDigits
            if let pp = positivePrefix { f.positivePrefix = pp }
            f.roundingMode = .halfUp
            numberFormatters[key] = f
            return f
        }
    }
}
