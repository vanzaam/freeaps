import SwiftUI

struct COBDetailView: View {
    @ObservedObject var state: Home.StateModel

    private var numberFormatter: NumberFormatter {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.maximumFractionDigits = 1
        return f
    }

    private var historySeries: [(Date, Decimal)] { state.cobHistoryLast6h() }
    private var history24hSeries: [(Date, Decimal)] { state.cobHistory.map { ($0.date, $0.grams) } }

    private var forecastSeries: [(Date, Decimal)] { state.cobForecast6h() }

    // 6h forecast is drawn on the graph; no short 1h list anymore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("COB").font(.title2).bold()
                Spacer()
                Button(action: { state.showModal(for: nil) }) {
                    Image(systemName: "xmark.circle.fill").font(.title2)
                }
            }

            if let cob = state.suggestion?.cob {
                Text("Current: \(numberFormatter.string(from: cob as NSNumber) ?? "0") g")
                    .font(.headline)
            }

            // График прогноза (6h вперёд)
            Text("Forecast (6h)").font(.headline)
            COBMiniChart(samples: historySeries, forecast: forecastSeries, current: state.suggestion?.cob)
                .frame(height: 200)

            // Отдельный график фактического COB за 24 часа
            Text("History (24h)").font(.headline)
            COBHistoryChart(samples: state.cobHistory.map { ($0.date, $0.grams) })
                .frame(height: 200)

            Spacer()
        }
        .padding()
        .background(Color(UIColor.systemBackground))
    }
}

private struct COBMiniChart: View {
    let samples: [(Date, Decimal)]
    let forecast: [(Date, Decimal)]
    let current: Decimal?

    struct AxisMeta {
        let t0: TimeInterval
        let t1: TimeInterval
        let minV: Double
        let maxV: Double
    }

    func axisMeta() -> AxisMeta? {
        // Build axis over union of history and forecast (6h back + 6h forward)
        let firstHistory = samples.first?.0
        let lastHistory = samples.last?.0
        let firstForecast = forecast.first?.0
        let lastForecast = forecast.last?.0
        guard let startDate = [firstHistory, firstForecast].compactMap({ $0 }).min(by: { $0 < $1 }),
              let endDate = [lastHistory, lastForecast].compactMap({ $0 }).max(by: { $0 < $1 })
        else { return nil }

        let allVals = (samples + forecast).map { Double(truncating: $0.1 as NSNumber) }
        let minV = allVals.min() ?? 0
        let maxV = max(minV + 1, allVals.max() ?? (minV + 1))
        return AxisMeta(t0: startDate.timeIntervalSince1970, t1: endDate.timeIntervalSince1970, minV: minV, maxV: maxV)
    }

    func points(in size: CGSize, meta: AxisMeta) -> [CGPoint] {
        let dt = max(meta.t1 - meta.t0, 1)
        let dv = max(meta.maxV - meta.minV, 1)
        return samples.map { s in
            let xn = (s.0.timeIntervalSince1970 - meta.t0) / dt
            let yn = (Double(truncating: s.1 as NSNumber) - meta.minV) / dv
            let x = CGFloat(xn) * size.width
            let y = size.height - CGFloat(yn) * (size.height - 2)
            return CGPoint(x: x, y: y)
        }
    }

    func points(in size: CGSize, meta: AxisMeta, series: [(Date, Decimal)]) -> [CGPoint] {
        let dt = max(meta.t1 - meta.t0, 1)
        let dv = max(meta.maxV - meta.minV, 1)
        return series.map { s in
            let xn = (s.0.timeIntervalSince1970 - meta.t0) / dt
            let yn = (Double(truncating: s.1 as NSNumber) - meta.minV) / dv
            let x = CGFloat(xn) * size.width
            let y = size.height - CGFloat(yn) * (size.height - 2)
            return CGPoint(x: x, y: y)
        }
    }

    func smoothedPath(_ pts: [CGPoint]) -> Path {
        var path = Path()
        guard pts.count > 1 else { return path }
        path.move(to: pts[0])
        // Catmull-Rom to Cubic Bezier smoothing
        let s: CGFloat = 0.5
        for i in 0 ..< pts.count - 1 {
            let p0 = i > 0 ? pts[i - 1] : pts[i]
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = (i + 2 < pts.count) ? pts[i + 2] : p2
            let cp1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6 * s, y: p1.y + (p2.y - p0.y) / 6 * s)
            let cp2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6 * s, y: p2.y - (p3.y - p1.y) / 6 * s)
            path.addCurve(to: p2, control1: cp1, control2: cp2)
        }
        return path
    }

    @State private var hoverX: CGFloat? = nil

    private func resampleTo5m(_ series: [(Date, Decimal)]) -> [(Date, Decimal)] {
        guard series.count > 1 else { return series }
        var out: [(Date, Decimal)] = []
        for i in 0 ..< series.count - 1 {
            let a = series[i]
            let b = series[i + 1]
            out.append(a)
            let delta = b.0.timeIntervalSince(a.0)
            if delta <= 0 { continue }
            let steps = Int(delta / 300.0)
            if steps > 1 {
                let va = a.1
                let vb = b.1
                for s in 1 ..< steps {
                    let t = Date(timeInterval: Double(s * 300), since: a.0)
                    // линейная интерполяция между двумя точками истории
                    let frac = Decimal(Double(s) / Double(steps))
                    let v = va + (vb - va) * frac
                    out.append((t, v))
                }
            }
        }
        out.append(series.last!)
        return out
    }

    private func chartContent(meta: AxisMeta, size: CGSize) -> some View {
        ZStack {
            // Background threshold bands (low/mid/high)
            let thirds: [Color] = [Color.green.opacity(0.08), Color.yellow.opacity(0.08), Color.red.opacity(0.08)]
            ForEach(0 ..< 3, id: \.self) { i in
                let yTop = size.height * CGFloat(1 - Double(i + 1) / 3)
                let bandHeight = size.height / 3
                Path { p in
                    p.addRect(CGRect(x: 0, y: yTop, width: size.width, height: bandHeight))
                }.fill(thirds[i])
            }

            // Horizontal grid lines (min/mid/max)
            let yValues: [Double] = [meta.minV, (meta.minV + meta.maxV) / 2, meta.maxV]
            ForEach(0 ..< yValues.count, id: \.self) { i in
                let v = yValues[i]
                let yn = (v - meta.minV) / max(meta.maxV - meta.minV, 1)
                let y = size.height - CGFloat(yn) * (size.height - 2)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: size.width, y: y))
                }
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                Text(String(Int(v)))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .position(x: 18, y: y - 8)
            }

            // Smoothed history line (separate layer)
            let history = resampleTo5m(samples)
            let histPts = points(in: size, meta: meta, series: history)
            if histPts.count > 1 {
                smoothedPath(histPts)
                    .stroke(Color.loopYellow, lineWidth: 2)
            }
            // History point markers каждый 5 мин
            ForEach(0 ..< histPts.count, id: \.self) { i in
                let p = histPts[i]
                Path { path in
                    path.addEllipse(in: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
                }
                .fill(Color.loopYellow.opacity(0.9))
            }

            // Forecast dashed line
            if !forecast.isEmpty {
                let fpts = points(in: size, meta: meta, series: forecast)
                if fpts.count > 1 {
                    smoothedPath(fpts)
                        .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [6, 6]))
                        .foregroundColor(Color.loopYellow.opacity(0.8))
                }
            }

            // Time axis ticks (7 ticks over 12h window)
            let tickCount = 7
            ForEach(0 ..< tickCount, id: \.self) { i in
                let t = meta.t0 + (meta.t1 - meta.t0) * Double(i) / Double(tickCount - 1)
                let x = CGFloat((t - meta.t0) / max(meta.t1 - meta.t0, 1)) * size.width
                Path { p in
                    p.move(to: CGPoint(x: x, y: size.height))
                    p.addLine(to: CGPoint(x: x, y: size.height - 6))
                }
                .stroke(Color.gray.opacity(0.4), lineWidth: 1)
                let label = Date(timeIntervalSince1970: t)
                Text(label, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .position(x: x, y: size.height - 12)
            }

            // Interaction overlay: hover value at fixed label
            let allSeriesHistory: [(Date, Decimal, Bool)] = samples.map { item in (item.0, item.1, false) }
            let allSeriesForecast: [(Date, Decimal, Bool)] = forecast.map { item in (item.0, item.1, true) }
            let allSeries: [(Date, Decimal, Bool)] = allSeriesHistory + allSeriesForecast
            let df = FormatterCache.dateFormatter(timeStyle: .short)
            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            hoverX = max(0, min(size.width, value.location.x))
                        }
                        .onEnded { _ in }
                )

            if let x = hoverX {
                // Vertical marker line
                Path { p in
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: size.height))
                }
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1)

                // Find nearest timestamp
                let targetT = meta.t0 + Double(x / size.width) * (meta.t1 - meta.t0)
                let nearest = allSeries.min { a, b in
                    let da = abs(a.0.timeIntervalSince1970 - targetT)
                    let db = abs(b.0.timeIntervalSince1970 - targetT)
                    return da < db
                }
                if let sel = nearest {
                    let grams = Double(truncating: sel.1 as NSNumber)
                    let label = df.string(from: sel.0) + "  " + String(Int(grams)) + " g"
                    // Fixed label in top-left
                    Text(label)
                        .font(.caption)
                        .padding(6)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.6)))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding([.top, .leading], 8)
                }
            }
        }
    }

    private struct COBHistoryChartInner: View {
        let samples: [(Date, Decimal)]

        func axisMeta() -> AxisMeta? {
            guard let first = samples.first?.0, let last = samples.last?.0 else { return nil }
            let vals = samples.map { Double(truncating: $0.1 as NSNumber) }
            let minV = vals.min() ?? 0
            let maxV = max(minV + 1, vals.max() ?? (minV + 1))
            return AxisMeta(t0: first.timeIntervalSince1970, t1: last.timeIntervalSince1970, minV: minV, maxV: maxV)
        }

        func points(in size: CGSize, meta: AxisMeta) -> [CGPoint] {
            let dt = max(meta.t1 - meta.t0, 1)
            let dv = max(meta.maxV - meta.minV, 1)
            return samples.map { s in
                let xn = (s.0.timeIntervalSince1970 - meta.t0) / dt
                let yn = (Double(truncating: s.1 as NSNumber) - meta.minV) / dv
                return CGPoint(x: CGFloat(xn) * size.width, y: size.height - CGFloat(yn) * (size.height - 2))
            }
        }

        func path(_ pts: [CGPoint]) -> Path {
            var p = Path()
            guard let first = pts.first else { return p }
            p.move(to: first)
            for i in 1 ..< pts.count { p.addLine(to: pts[i]) }
            return p
        }

        var body: some View {
            GeometryReader { geo in
                let size = geo.size
                if let meta = axisMeta() {
                    let pts = points(in: size, meta: meta)
                    ZStack {
                        // grid
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: size.height / 2))
                            p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                        }
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)

                        path(pts).stroke(Color.loopYellow, lineWidth: 2)
                    }
                } else {
                    Text("No data").foregroundColor(.secondary)
                }
            }
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            if let meta = axisMeta() {
                chartContent(meta: meta, size: size)
            } else {
                Text("No data")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// Top-level history chart (24h) used by COBDetailView
private struct COBHistoryChart: View {
    struct AxisMeta {
        let t0: TimeInterval
        let t1: TimeInterval
        let minV: Double
        let maxV: Double
    }

    let samples: [(Date, Decimal)]

    func axisMeta() -> AxisMeta? {
        guard let first = samples.first?.0, let last = samples.last?.0 else { return nil }
        let vals = samples.map { Double(truncating: $0.1 as NSNumber) }
        let minV = vals.min() ?? 0
        let maxV = max(minV + 1, vals.max() ?? (minV + 1))
        return AxisMeta(t0: first.timeIntervalSince1970, t1: last.timeIntervalSince1970, minV: minV, maxV: maxV)
    }

    func points(in size: CGSize, meta: AxisMeta) -> [CGPoint] {
        let dt = max(meta.t1 - meta.t0, 1)
        let dv = max(meta.maxV - meta.minV, 1)
        return samples.map { s in
            let xn = (s.0.timeIntervalSince1970 - meta.t0) / dt
            let yn = (Double(truncating: s.1 as NSNumber) - meta.minV) / dv
            return CGPoint(x: CGFloat(xn) * size.width, y: size.height - CGFloat(yn) * (size.height - 2))
        }
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Group {
                if let meta = axisMeta() {
                    let pts = points(in: size, meta: meta)
                    ZStack {
                        // grid midline
                        Path { p in
                            p.move(to: CGPoint(x: 0, y: size.height / 2))
                            p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                        }
                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)

                        // history line (build outside result builder)
                        let historyPath: Path = {
                            var path = Path()
                            if let first = pts.first {
                                path.move(to: first)
                                for i in 1 ..< pts.count { path.addLine(to: pts[i]) }
                            }
                            return path
                        }()
                        historyPath.stroke(Color.loopYellow, lineWidth: 2)
                    }
                } else {
                    Text("No data").foregroundColor(.secondary)
                }
            }
        }
    }
}
