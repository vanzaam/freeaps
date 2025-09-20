import Foundation

final class FormatterCache {
    static let shared = FormatterCache()
    
    private let queue = DispatchQueue(label: "FormatterCache.queue", attributes: .concurrent)
    private var dateFormatters: [String: DateFormatter] = [:]
    private var numberFormatters: [String: NumberFormatter] = [:]
    
    private init() {}
    
    func dateFormatter(dateStyle: DateFormatter.Style = .none, timeStyle: DateFormatter.Style = .none, dateFormat: String? = nil, timeZone: TimeZone? = nil) -> DateFormatter {
        let key = "\(dateStyle.rawValue)-\(timeStyle.rawValue)-\(dateFormat ?? "")-\(timeZone?.identifier ?? "")"
        return queue.sync {
            if let formatter = dateFormatters[key] {
                return formatter
            }
            let formatter = DateFormatter()
            if dateStyle != .none { formatter.dateStyle = dateStyle }
            if timeStyle != .none { formatter.timeStyle = timeStyle }
            if let dateFormat = dateFormat { formatter.dateFormat = dateFormat }
            if let timeZone = timeZone { formatter.timeZone = timeZone }
            dateFormatters[key] = formatter
            return formatter
        }
    }
    
    func numberFormatter(numberStyle: NumberFormatter.Style = .none, maximumFractionDigits: Int = 0, minimumFractionDigits: Int = 0, minimumIntegerDigits: Int = 1, positivePrefix: String? = nil, roundingMode: NumberFormatter.RoundingMode = .halfUp, allowsFloats: Bool = true) -> NumberFormatter {
        let key = "\(numberStyle.rawValue)-\(maximumFractionDigits)-\(minimumFractionDigits)-\(minimumIntegerDigits)-\(positivePrefix ?? "")-\(roundingMode.rawValue)-\(allowsFloats)"
        return queue.sync {
            if let formatter = numberFormatters[key] {
                return formatter
            }
            let formatter = NumberFormatter()
            formatter.numberStyle = numberStyle
            formatter.maximumFractionDigits = maximumFractionDigits
            formatter.minimumFractionDigits = minimumFractionDigits
            formatter.minimumIntegerDigits = minimumIntegerDigits
            if let prefix = positivePrefix { formatter.positivePrefix = prefix }
            formatter.roundingMode = roundingMode
            formatter.allowsFloats = allowsFloats
            numberFormatters[key] = formatter
            return formatter
        }
    }
}
