import SwiftUI

struct CurrentGlucoseView: View {
    let recentGlucose: BloodGlucose?
    let delta: Int?
    let units: GlucoseUnits
    let alarm: GlucoseAlarm?

    private var glucoseFormatter: NumberFormatter {
        units == .mmolL
            ? FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 1, maxFractionDigits: 1)
            : FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 0, maxFractionDigits: 0)
    }

    private var deltaFormatter: NumberFormatter {
        FormatterCache.numberFormatter(style: .decimal, minFractionDigits: 0, maxFractionDigits: 2, positivePrefix: "+")
    }

    private var dateFormatter: DateFormatter { FormatterCache.dateFormatter(timeStyle: .short) }

    var body: some View {
        VStack(alignment: .center, spacing: 6) {
            HStack(spacing: 8) {
                Text(
                    recentGlucose?.glucose
                        .map {
                            glucoseFormatter
                                .string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)! }
                        ?? "--"
                )
                .font(.system(size: 24, weight: .bold))
                .fixedSize()
                .foregroundColor(alarm == nil ? .primary : .loopRed)
                image.padding(.bottom, 2)

            }.padding(.leading, 4)
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(
                    recentGlucose.map { dateFormatter.string(from: $0.dateString) } ?? "--"
                ).font(.caption2).foregroundColor(.secondary)
                Text(
                    delta
                        .map { deltaFormatter.string(from: Double(units == .mmolL ? $0.asMmolL : Decimal($0)) as NSNumber)!
                        } ??
                        "--"

                ).font(.system(size: 12, weight: .bold))
            }
        }
    }

    var image: Image {
        guard let direction = recentGlucose?.direction else {
            return Image(systemName: "arrow.left.and.right")
        }

        switch direction {
        case .doubleUp,
             .singleUp,
             .tripleUp:
            return Image(systemName: "arrow.up")
        case .fortyFiveUp:
            return Image(systemName: "arrow.up.right")
        case .flat:
            return Image(systemName: "arrow.forward")
        case .fortyFiveDown:
            return Image(systemName: "arrow.down.forward")
        case .doubleDown,
             .singleDown,
             .tripleDown:
            return Image(systemName: "arrow.down")

        case .none,
             .notComputable,
             .rateOutOfRange:
            return Image(systemName: "arrow.left.and.right")
        }
    }
}
