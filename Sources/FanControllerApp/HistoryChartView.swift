import Charts
import FanControllerCore
import SwiftUI

struct HistoryChartView: View {
    let history: [SensorSnapshot]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("10 MINUTES")
                    .font(.caption2.weight(.bold))
                    .tracking(1.1)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("온도 °C")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if history.contains(where: { $0.maximumTemperature != nil }) {
                Chart(history, id: \.timestamp) { item in
                    if let temperature = item.maximumTemperature {
                        AreaMark(
                            x: .value("시간", item.timestamp),
                            yStart: .value("기준", 30),
                            yEnd: .value("온도", temperature)
                        )
                        .foregroundStyle(
                            LinearGradient(
                                colors: [
                                    Color.orange.opacity(0.28),
                                    Color.orange.opacity(0.01),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        LineMark(
                            x: .value("시간", item.timestamp),
                            y: .value("온도", temperature)
                        )
                        .foregroundStyle(.orange)
                        .lineStyle(
                            StrokeStyle(
                                lineWidth: 2,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                    }
                }
                .chartYScale(domain: 30...110)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .leading, values: [40, 70, 100])
                }
                .frame(height: 116)
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "chart.xyaxis.line")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("기록 대기 중")
                        .font(.callout.weight(.semibold))
                    Text("센서 연결 후 1초마다 기록됩니다.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 116)
            }
        }
        .padding(12)
        .background(
            Color.primary.opacity(0.035),
            in: RoundedRectangle(cornerRadius: 13)
        )
    }
}
