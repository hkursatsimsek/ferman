import FermanCore
import SwiftUI

/// SavaşSonrasıAnalizi (design brief §4.6) — a diagnosis, not a victory screen. Everything on it can
/// take the player back into the battle: the diagnosis sentence and any point of the tape replay that
/// moment (the simulation is deterministic, so the replay is the battle). "Klibi Paylaş" returns with
/// `ClipRenderer` (D15, F4.7); an inert button would only look unfinished.
struct DebriefView: View {
    @State var model: DebriefModel
    var onFixOrders: () -> Void = {}
    var onReview: (Int32) -> Void = { _ in }
    /// `nil` when there's no next front to go to, or the battle was lost.
    var onNextFront: (() -> Void)?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: FermanSpacing.xl) {
                header
                DebriefTapeView(tape: model.tape, moment: model.momentTick, onSelect: onReview)
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
        HStack(alignment: .top, spacing: FermanSpacing.md) {
            VStack(alignment: .leading, spacing: FermanSpacing.sm) {
                Text(model.title)
                    .font(FermanFont.screenTitle())
                    .tracking(FermanFont.Tracking.screenTitle)
                    .foregroundStyle(Color.paper)
                Text(model.diagnosis)
                    .font(FermanFont.body())
                    .foregroundStyle(Color.paper.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                if let moment = model.momentTick {
                    Button {
                        onReview(moment)
                    } label: {
                        Label(String(localized: "O anı izle"), systemImage: "play.fill")
                    }
                    .buttonStyle(FermanButton.Chip())
                }
            }
            Spacer(minLength: 0)
            tablePhotograph
        }
        .padding(.top, FermanSpacing.lg)
    }

    /// The table as the battle left it, pinned up like a photograph: who stands, who fell, where.
    private var tablePhotograph: some View {
        BattleSceneView(config: model.config, timeline: model.timeline, clock: model.finalClock)
            .frame(width: 88, height: 150)
            .allowsHitTesting(false)
            .padding(4)
            .background(Color.paper)
            .rotationEffect(.degrees(2))
            .shadow(color: .black.opacity(0.45), radius: 6, y: 4)
            .accessibilityHidden(true)
    }

    private var ordersSection: some View {
        VStack(alignment: .leading, spacing: FermanSpacing.lg) {
            Text(String(localized: "Emirlerin"))
                .font(FermanFont.chipLabel())
                .tracking(2)
                .foregroundStyle(Color.paper.opacity(0.6))
            ForEach(model.sections) { section in
                VStack(alignment: .leading, spacing: FermanSpacing.md - 2) {
                    if model.sections.count > 1 {
                        HStack(spacing: FermanSpacing.xs) {
                            UnitToken(type: section.unitType, size: .chip)
                            Text(section.displayName)
                                .font(FermanFont.tabSelected())
                                .foregroundStyle(Color.paper)
                        }
                    }
                    ForEach(section.rows) { row in
                        DebriefOrderRowView(row: row)
                    }
                    if let note = section.note {
                        Text(note)
                            .font(FermanFont.caption())
                            .italic()
                            .foregroundStyle(Color.paper.opacity(0.7))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footer: some View {
        VStack(spacing: FermanSpacing.sm) {
            if let onNextFront, model.isVictory {
                Button(String(localized: "Sonraki Cephe"), action: onNextFront)
                    .buttonStyle(FermanButton.Primary())
                Button(String(localized: "Emirleri Düzelt"), action: onFixOrders)
                    .buttonStyle(FermanButton.Outline())
            } else {
                Button(String(localized: "Emirleri Düzelt"), action: onFixOrders)
                    .buttonStyle(FermanButton.Primary())
            }
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
                    .foregroundStyle(Color.paper.opacity(0.6))
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
                // The orders that fired are counted in spark (brief §3.2): this was your logic working.
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.paper.opacity(0.1))
                        Capsule()
                            .fill(Color.spark)
                            .frame(width: proxy.size.width * row.fraction)
                    }
                }
                .frame(height: 5)
                .padding(.leading, 16 + FermanSpacing.sm)
                Text(String(localized: "\(row.fireCount) kez"))
                    .font(FermanFont.counter(size: 12))
                    .foregroundStyle(row.fireCount > 0 ? Color.spark : Color.paper.opacity(0.6))
                    .frame(minWidth: 48, alignment: .trailing)
            }
            if row.neverFired {
                // The most valuable line on the screen (brief §4.6): standing out, never accusing.
                HStack(spacing: FermanSpacing.sm) {
                    Rectangle().fill(Color.alarm).frame(width: 2)
                    Text(String(localized: "Bu emir hiç çalışmadı."))
                        .font(FermanFont.caption())
                        .foregroundStyle(Color.paper)
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 16 + FermanSpacing.sm)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// The battle along one line (Faz 1.5 G11): a tally stroke in spark where the player's orders took
/// hold, a cross where one of their figures fell, a brass mark on the diagnosis's moment, second marks
/// every ten seconds. Touch anywhere on it to watch that moment.
private struct DebriefTapeView: View {
    let tape: DebriefTape
    let moment: Int32?
    var onSelect: (Int32) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: FermanSpacing.xs) {
            Canvas { context, size in
                let ruler = size.height * 0.5
                let x = { (tick: Int32) in CGFloat(tick) / CGFloat(tape.length) * size.width }

                context.fill(Path(CGRect(x: 0, y: ruler, width: size.width, height: 1)), with: .color(.paper.opacity(0.3)))
                let seconds = Int(tape.length) / BattleConfig.ticksPerSecond
                for second in stride(from: 0, through: seconds, by: 10) {
                    let position = x(Int32(second * BattleConfig.ticksPerSecond))
                    context.fill(
                        Path(CGRect(x: position, y: ruler - 3, width: 1, height: 7)), with: .color(.paper.opacity(0.35)))
                }
                for tick in tape.orderTicks {
                    context.fill(
                        Path(CGRect(x: x(tick), y: ruler - 12, width: 1.2, height: 10)),
                        with: .color(.spark.opacity(0.85)))
                }
                for tick in tape.lossTicks {
                    let center = CGPoint(x: x(tick), y: ruler + 9)
                    var cross = Path()
                    cross.move(to: CGPoint(x: center.x - 3, y: center.y - 3))
                    cross.addLine(to: CGPoint(x: center.x + 3, y: center.y + 3))
                    cross.move(to: CGPoint(x: center.x + 3, y: center.y - 3))
                    cross.addLine(to: CGPoint(x: center.x - 3, y: center.y + 3))
                    context.stroke(cross, with: .color(.paper.opacity(0.8)), lineWidth: 1.2)
                }
                if let moment {
                    let position = x(moment)
                    var marker = Path()
                    marker.move(to: CGPoint(x: position, y: ruler + 2))
                    marker.addLine(to: CGPoint(x: position - 5, y: size.height))
                    marker.addLine(to: CGPoint(x: position + 5, y: size.height))
                    marker.closeSubpath()
                    context.fill(marker, with: .color(.brass))
                }
            }
            .frame(height: 44)
            .contentShape(Rectangle())
            .gesture(
                SpatialTapGesture().onEnded { tap in
                    // The tape spans the view's width; a touch picks the tick under it.
                    onSelect(Int32(tap.location.x / max(tapeWidth, 1) * CGFloat(tape.length)))
                }
            )
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { tapeWidth = $0 }

            HStack(spacing: FermanSpacing.md) {
                legend(color: .spark, text: String(localized: "emir"))
                legend(color: .paper.opacity(0.8), text: String(localized: "kayıp"), isCross: true)
                Spacer()
                Text(String(localized: "\(Int(tape.length) / BattleConfig.ticksPerSecond) sn"))
                    .font(FermanFont.counter(size: 11))
                    .foregroundStyle(Color.paper.opacity(0.6))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Savaşın zaman şeridi"))
        .accessibilityValue(String(localized: "\(tape.orderTicks.count) emir, \(tape.lossTicks.count) kayıp"))
        .accessibilityAction(named: Text("O anı izle")) {
            onSelect(moment ?? 0)
        }
    }

    @State private var tapeWidth: CGFloat = 1

    private func legend(color: Color, text: String, isCross: Bool = false) -> some View {
        HStack(spacing: 4) {
            if isCross {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(color)
            } else {
                Rectangle().fill(color).frame(width: 1.5, height: 9)
            }
            Text(text)
                .font(FermanFont.caption())
                .foregroundStyle(Color.paper.opacity(0.7))
        }
    }
}
