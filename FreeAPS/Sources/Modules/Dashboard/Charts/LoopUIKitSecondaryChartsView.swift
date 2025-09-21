import HealthKit
import LoopKit
import LoopKitUI
import SwiftCharts
import SwiftUI
import UIKit

// Individual chart wrappers to stack vertically

struct LoopUIKitIOBChartView: UIViewRepresentable {
    let iob: [IOBData]
    let timeRangeHours: Int

    func makeUIView(context _: Context) -> ChartContainerView { ChartContainerView() }
    func updateUIView(_ uiView: ChartContainerView, context _: Context) {
        let now = Date()
        let startDate = now.addingTimeInterval(-Double(timeRangeHours * 3600))
        let colors = ChartColorPalette(
            axisLine: .secondaryLabel,
            axisLabel: .secondaryLabel,
            grid: UIColor.secondaryLabel.withAlphaComponent(0.15),
            glucoseTint: .systemBlue,
            insulinTint: .systemOrange,
            carbTint: .systemGreen
        )
        let chart = IOBChart()
        // Fallback Y-range by providing a dummy 0 line via display range
        chart.setIOBValues(iob.map { InsulinValue(startDate: $0.date, value: $0.value.doubleValue) })
        var settings = ChartSettings()
        settings.top = 4
        settings.bottom = 0
        settings.trailing = 8
        settings.labelsToAxisSpacingX = 6
        settings.clipInnerFrame = false
        let mgr = ChartsManager(colors: colors, settings: settings, charts: [chart], traitCollection: UITraitCollection.current)
        mgr.startDate = startDate
        mgr.maxEndDate = now
        mgr.updateEndDate(now)
        mgr.prerender()
        // Локальный highlight для IOB
        let gr = UILongPressGestureRecognizer()
        gr.minimumPressDuration = 0
        mgr.gestureRecognizer = gr
        uiView.isUserInteractionEnabled = true
        uiView.addGestureRecognizer(gr)
        uiView.chartGenerator = { frame in mgr.chart(atIndex: 0, frame: frame)?.view }
        uiView.reloadChart()
    }
}

struct LoopUIKitDoseChartView: UIViewRepresentable {
    let delivery: [DeliveryEvent]
    let timeRangeHours: Int

    func makeUIView(context _: Context) -> ChartContainerView { ChartContainerView() }
    func updateUIView(_ uiView: ChartContainerView, context _: Context) {
        let now = Date()
        let startDate = now.addingTimeInterval(-Double(timeRangeHours * 3600))
        let colors = ChartColorPalette(
            axisLine: .secondaryLabel,
            axisLabel: .secondaryLabel,
            grid: UIColor.secondaryLabel.withAlphaComponent(0.15),
            glucoseTint: .systemBlue,
            insulinTint: .systemOrange,
            carbTint: .systemGreen
        )
        let chart = DoseChart()
        chart.doseEntries = delivery.map { e in
            switch e.type {
            case .bolus:
                return DoseEntry(type: .bolus, startDate: e.date, endDate: e.date, value: e.amount.doubleValue, unit: .units)
            case .tempBasal:
                return DoseEntry(
                    type: .tempBasal,
                    startDate: e.date,
                    endDate: e.date.addingTimeInterval(30 * 60),
                    value: e.amount.doubleValue,
                    unit: .unitsPerHour
                )
            case .basal:
                return DoseEntry(
                    type: .basal,
                    startDate: e.date,
                    endDate: e.date.addingTimeInterval(30 * 60),
                    value: e.amount.doubleValue,
                    unit: .unitsPerHour
                )
            }
        }
        var settings = ChartSettings()
        settings.top = 4
        settings.bottom = 0
        settings.trailing = 8
        settings.labelsToAxisSpacingX = 6
        settings.clipInnerFrame = false
        let mgr = ChartsManager(colors: colors, settings: settings, charts: [chart], traitCollection: UITraitCollection.current)
        mgr.startDate = startDate
        mgr.maxEndDate = now
        mgr.updateEndDate(now)
        mgr.prerender()
        let gr = UILongPressGestureRecognizer()
        gr.minimumPressDuration = 0
        mgr.gestureRecognizer = gr
        uiView.isUserInteractionEnabled = true
        uiView.addGestureRecognizer(gr)
        uiView.chartGenerator = { frame in mgr.chart(atIndex: 0, frame: frame)?.view }
        uiView.reloadChart()
    }
}

struct LoopUIKitCOBChartView: UIViewRepresentable {
    let cob: [COBData]
    let timeRangeHours: Int

    func makeUIView(context _: Context) -> ChartContainerView { ChartContainerView() }
    func updateUIView(_ uiView: ChartContainerView, context _: Context) {
        let now = Date()
        let startDate = now.addingTimeInterval(-Double(timeRangeHours * 3600))
        let colors = ChartColorPalette(
            axisLine: .secondaryLabel,
            axisLabel: .secondaryLabel,
            grid: UIColor.secondaryLabel.withAlphaComponent(0.15),
            glucoseTint: .systemBlue,
            insulinTint: .systemOrange,
            carbTint: .systemGreen
        )
        let chart = COBChart()
        chart.setCOBValues(cob.map { CarbValue(startDate: $0.date, value: $0.value.doubleValue) })
        var settings = ChartSettings()
        settings.top = 4
        settings.bottom = 0
        settings.trailing = 8
        settings.labelsToAxisSpacingX = 6
        settings.clipInnerFrame = false
        let mgr = ChartsManager(colors: colors, settings: settings, charts: [chart], traitCollection: UITraitCollection.current)
        mgr.startDate = startDate
        mgr.maxEndDate = now
        mgr.updateEndDate(now)
        mgr.prerender()
        let gr = UILongPressGestureRecognizer()
        gr.minimumPressDuration = 0
        mgr.gestureRecognizer = gr
        uiView.isUserInteractionEnabled = true
        uiView.addGestureRecognizer(gr)
        uiView.chartGenerator = { frame in mgr.chart(atIndex: 0, frame: frame)?.view }
        uiView.reloadChart()
    }
}
