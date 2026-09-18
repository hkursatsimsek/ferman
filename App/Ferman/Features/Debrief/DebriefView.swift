import SwiftUI

/// SavaşSonrasıAnalizi (design brief §4.6). "Emirleri Düzelt" hands off to whichever screen owns
/// re-entering `RuleEditor` with this same army — not wired to `AppRouter` yet (Battle itself isn't a
/// route target either, F1.9's note). "Klibi Paylaş" stays disabled until `ClipRenderer` ships (D15,
/// F4.7); showing it now, inert, matches how `HomeView`'s unbuilt rows are handled.
struct DebriefView: View {
    @State var model: DebriefModel
    var onFixOrders: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(spacing: FermanSpacing.xl) {
                header
                ordersSection
            }
            .padding(FermanSpacing.md)
        }
        .safeAreaInset(edge: .bottom) {
            footer
        }
        .background(Color.ink)
    }

    private var header: some View {
        VStack(spacing: FermanSpacing.sm) {
            Text(model.title)
                .font(FermanFont.screenTitle())
                .tracking(FermanFont.Tracking.screenTitle)
                .foregroundStyle(Color.paper)
            Text(model.diagnosis)
                .font(FermanFont.body())
                .foregroundStyle(Color.paper.opacity(0.8))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, FermanSpacing.lg)
    }

    private var ordersSection: some View {
        VStack(alignment: .leading, spacing: FermanSpacing.lg) {
            Text(String(localized: "Emirlerin"))
                .font(FermanFont.chipLabel())
                .tracking(2)
                .foregroundStyle(Color.paper.opacity(0.5))
            ForEach(model.sections) { section in
                VStack(alignment: .leading, spacing: FermanSpacing.md - 2) {
                    if model.sections.count > 1 {
                        Text(section.displayName)
                            .font(FermanFont.tabSelected())
                            .foregroundStyle(Color.paper)
                    }
                    ForEach(section.rows) { row in
                        DebriefOrderRowView(row: row)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(spacing: FermanSpacing.sm) {
            Button(String(localized: "Emirleri Düzelt"), action: onFixOrders)
                .buttonStyle(FermanButton.Primary())
            Button(String(localized: "Klibi Paylaş")) {}
                .buttonStyle(FermanButton.Outline())
                .disabled(true)
        }
        .padding(FermanSpacing.md)
        .background(Color.ink)
    }
}

private struct DebriefOrderRowView: View {
    let row: DebriefOrderRow

    var body: some View {
        VStack(alignment: .leading, spacing: FermanSpacing.xs) {
            HStack(alignment: .top, spacing: FermanSpacing.sm) {
                Text("\(row.priority)")
                    .font(FermanFont.counter(size: 12))
                    .foregroundStyle(Color.paper.opacity(0.55))
                    // `minWidth`, not `width` — a hard width clips this at accessibility Dynamic Type sizes.
                    .frame(minWidth: 16, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.condition)
                        .font(FermanFont.orderCondition())
                        .foregroundStyle(Color.paper.opacity(0.85))
                    Text(row.action)
                        .font(FermanFont.orderAction())
                        .tracking(FermanFont.Tracking.orderAction)
                        .foregroundStyle(Color.paper)
                }
            }
            HStack(spacing: FermanSpacing.xs + 2) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.paper.opacity(0.1))
                        Capsule()
                            .fill(row.neverFired ? Color.alarm.opacity(0.5) : Color.brass)
                            .frame(width: proxy.size.width * row.fraction)
                    }
                }
                .frame(height: 4)
                .padding(.leading, 16 + FermanSpacing.sm)
                Text(String(localized: "\(row.fireCount) kez"))
                    .font(FermanFont.counter(size: 12))
                    .foregroundStyle(Color.paper.opacity(0.6))
                    .frame(minWidth: 48, alignment: .trailing)
            }
            if row.neverFired {
                Text(String(localized: "⚠ Bu emir hiç çalışmadı."))
                    .font(FermanFont.caption())
                    .foregroundStyle(Color.alarm)
                    .padding(.leading, 16 + FermanSpacing.sm)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
