import HealthKit
import LoopKit
import LoopKitUI
import SwiftCharts
import SwiftUI
import UIKit

/// Reuses LoopKitUI PredictedGlucoseChart with SwiftCharts highlight/tooltip handling
struct LoopUIKitGlucoseChartView: UIViewRepresentable {
    let glucose: [GlucoseReading]
    let predicted: [PredictedGlucose]
    let timeRangeHours: Int
    var useMmolL: Bool = true
    var lowThreshold: Decimal? = nil
    var highThreshold: Decimal? = nil

    func makeUIView(context _: Context) -> ChartContainerView {
        let view = ChartContainerView()
        configure(view: view)
        return view
    }

    func updateUIView(_ uiView: ChartContainerView, context _: Context) {
        configure(view: uiView)
        uiView.reloadChart()
    }

    // MARK: - Private

    private func configure(view: ChartContainerView) {
        let now = Date()
        let startDate = now.addingTimeInterval(-Double(timeRangeHours * 3600))

        // Colors to match Loop style
        let colors = ChartColorPalette(
            axisLine: .secondaryLabel,
            axisLabel: .secondaryLabel,
            grid: UIColor.secondaryLabel.withAlphaComponent(0.15),
            glucoseTint: .systemBlue,
            insulinTint: .systemOrange,
            carbTint: .systemGreen
        )

        // Build chart provider with target range fill (как в Loop)
        let predictedChart = PredictedGlucoseChart()
        predictedChart.glucoseUnit = useMmolL ? .millimolesPerLiter : .milligramsPerDeciliter
        // Basic daily target 80-120 mg/dL across day for визуальный паритет; позже возьмём из профиля
        if let lo = lowThreshold, let hi = highThreshold {
            let unit = useMmolL ? HKUnit.millimolesPerLiter : .milligramsPerDeciliter
            if let schedule = GlucoseRangeSchedule(
                unit: unit,
                dailyItems: [RepeatingScheduleValue(
                    startTime: .hours(0),
                    value: DoubleRange(minValue: lo.doubleValue, maxValue: hi.doubleValue)
                )]
            ) {
                predictedChart.targetGlucoseSchedule = schedule
            }
        }
        // Fallback Y-range to avoid empty axis when нет данных (как в Loop)
        let unit = useMmolL ? HKUnit.millimolesPerLiter : .milligramsPerDeciliter
        let low = HKQuantity(unit: unit, doubleValue: lowThreshold?.doubleValue ?? (useMmolL ? 3.9 : 70))
        let high = HKQuantity(unit: unit, doubleValue: highThreshold?.doubleValue ?? (useMmolL ? 10.0 : 180))
        predictedChart.glucoseDisplayRange = low ... high

        // Convert app data -> LoopKit GlucoseValue
        let glucoseValues: [GlucoseValue] = glucose.map { item in
            SimpleGlucoseValue(
                startDate: item.date,
                quantity: HKQuantity(unit: unit, doubleValue: item.value.doubleValue)
            )
        }
        let predictedValues: [GlucoseValue] = predicted.map { item in
            PredictedGlucoseValue(
                startDate: item.date,
                quantity: HKQuantity(unit: unit, doubleValue: item.value.doubleValue)
            )
        }

        // Prepare chart points using public setters
        predictedChart.setGlucoseValues(glucoseValues)
        predictedChart.setPredictedGlucoseValues(predictedValues)

        // Charts manager
        // Chart settings compatible with Loop charts
        var settings = ChartSettings()
        settings.top = 12
        settings.bottom = 0
        settings.trailing = 8
        settings.labelsToAxisSpacingX = 6
        settings.clipInnerFrame = false
        let manager = ChartsManager(
            colors: colors,
            settings: settings,
            charts: [predictedChart],
            traitCollection: UITraitCollection.current
        )
        manager.startDate = startDate
        manager.maxEndDate = now
        manager.updateEndDate(now)
        // Prepare X axis and caches before asking for chart
        manager.prerender()

        // Локальный highlight внутри графика (как в Loop)
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0
        manager.gestureRecognizer = recognizer
        view.isUserInteractionEnabled = true
        view.addGestureRecognizer(recognizer)

        // Supply generator (rebuilds chart for current frame)
        view.chartGenerator = { frame in
            manager.chart(atIndex: 0, frame: frame)?.view
        }
    }
}
