import SwiftUI

// MARK: - Scoreboard palette (dark, high contrast, readable in sun and under lights)

enum Board {
    static let bg        = Color(red: 0.035, green: 0.075, blue: 0.060)
    static let panel     = Color(red: 0.070, green: 0.130, blue: 0.105)
    static let panelHi   = Color(red: 0.100, green: 0.175, blue: 0.140)
    static let line      = Color.white.opacity(0.10)
    static let text      = Color.white
    static let dim       = Color.white.opacity(0.62)
    static let gold      = Color(red: 0.93, green: 0.80, blue: 0.45)
    static let pitch     = Color(red: 0.20, green: 0.78, blue: 0.48)
    static let rain      = Color(red: 0.38, green: 0.68, blue: 0.95)
    static let stop      = Color(red: 0.93, green: 0.33, blue: 0.27)
}

// MARK: - Root of the match-day experience

struct MatchDayView: View {
    @EnvironmentObject var ms: MatchState
    @State private var showWorking = false
    @State private var showShare = false

    var body: some View {
        VStack(spacing: 0) {
            PhasePicker(phase: $ms.matchPhase)
                .padding(.horizontal, 16).padding(.bottom, 10)
            ScrollView {
                VStack(spacing: 14) {
                    switch ms.matchPhase {
                    case .before:  BeforePlayPanel()
                    case .first:   FirstInningsPanel()
                    case .second:  SecondInningsPanel()
                    case .summary: SummaryPanel(showShare: $showShare)
                    }
                    Button { showWorking = true } label: {
                        Label("Show working (Appendix J sheets)", systemImage: "list.number")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Board.dim)
                            .frame(maxWidth: .infinity).padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 16).padding(.bottom, 30)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Board.bg.ignoresSafeArea())
        .sheet(isPresented: $showWorking) { WorkingSheet().environmentObject(ms) }
        .sheet(isPresented: $showShare) { ShareSheet(items: [ms.generateSummary()]) }
    }
}

// MARK: - Phase picker

struct PhasePicker: View {
    @Binding var phase: MatchPhase
    var body: some View {
        HStack(spacing: 6) {
            ForEach(MatchPhase.allCases, id: \.self) { p in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { phase = p }
                    Haptic.light()
                } label: {
                    Text(p.rawValue)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(phase == p ? Board.bg : Board.text)
                        .background(phase == p ? Board.gold : Board.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(phase == p ? .isSelected : [])
            }
        }
    }
}

// MARK: - Building blocks

/// The figures an umpire announces, in scoreboard type.
struct AnswerBoard: View {
    let caption: String
    let headline: String
    let headlineUnit: String
    let rows: [(String, String)]
    var note: String? = nil
    var tint: Color = Board.gold

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(caption.uppercased())
                .font(.caption.weight(.heavy)).tracking(1.2)
                .foregroundStyle(tint)
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(headline)
                    .font(.system(size: 84, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Board.text)
                    .minimumScaleFactor(0.5).lineLimit(1)
                Text(headlineUnit)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Board.dim)
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                      alignment: .leading, spacing: 10) {
                ForEach(rows.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rows[i].0)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Board.dim)
                        Text(rows[i].1)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(Board.text)
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(Board.panelHi)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
            if let note {
                Text(note).font(.footnote).foregroundStyle(Board.dim)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Board.panel)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Board.line))
    }
}

struct BigActionButton: View {
    let title: String
    let systemImage: String
    let color: Color
    var foreground: Color = .white
    let action: () -> Void
    var body: some View {
        Button {
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .frame(maxWidth: .infinity, minHeight: 64)
                .foregroundStyle(foreground)
                .background(color)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct BoardSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(.caption.weight(.heavy)).tracking(1.2)
                .foregroundStyle(Board.dim)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Board.panel)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

struct BoardTimeRow: View {
    let label: String
    @Binding var time: Date
    var body: some View {
        HStack {
            Text(label).font(.body.weight(.semibold)).foregroundStyle(Board.text)
            Spacer()
            DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .environment(\.colorScheme, .dark)
        }
    }
}

struct BlockingBanner: View {
    let warnings: [ValidationWarning]
    var body: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(warnings) { w in
                    Label(w.message, systemImage: "exclamationmark.octagon.fill")
                        .font(.callout.weight(.semibold))
                }
            }
            .foregroundStyle(.white)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Board.stop)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}

struct RulesFooter: View {
    @EnvironmentObject var ms: MatchState
    let overs: Int
    var body: some View {
        BoardSection(title: "Bowlers and fielding") {
            Text(ms.rules.bowlingRestrictionText(for: overs))
                .font(.body.weight(.semibold)).foregroundStyle(Board.text)
            PowerplayDisplay(competition: ms.competition, rules: ms.rules, overs: overs)
                .foregroundStyle(Board.text)
            let minimum = ms.isFinal ? ms.rules.minValidOversFinal : ms.rules.minValidOvers
            if overs < minimum {
                Label("Below the \(minimum)-over minimum for a result", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.bold)).foregroundStyle(Board.stop)
            }
            if ms.competition.isInternational {
                Text("ICC: DLS targets are not calculated by this app.")
                    .font(.footnote).foregroundStyle(Board.dim)
            }
        }
    }
}

// MARK: - Before play

struct BeforePlayPanel: View {
    @EnvironmentObject var ms: MatchState
    @State private var firstBall = Date()

    private var plan: EqualOversPlan { ms.firstInningsPlan }
    private var lateBy: Int { TU.minBetween(ms.gameStartTime, ms.LS_actualStart) }

    var body: some View {
        VStack(spacing: 14) {
            AnswerBoard(
                caption: lateBy > 0 ? "If play starts at \(TU.shortTime(ms.LS_actualStart))" : "Full match",
                headline: "\(plan.oversPerTeam)", headlineUnit: "overs a side",
                rows: [("Innings break", "\(TU.minBetween(plan.firstCessation, plan.secondStart)) min"),
                       ("1st innings ends", TU.shortTime(plan.firstCessation)),
                       ("2nd innings starts", TU.shortTime(plan.secondStart)),
                       ("Match ends", TU.shortTime(plan.secondCessation))],
                note: lateBy > 0 ? "Late start: \(lateBy) min lost." : nil)

            BoardSection(title: "Start of play") {
                BoardTimeRow(label: "Scheduled start", time: $ms.gameStartTime)
                BoardTimeRow(label: "Expected first ball", time: Binding(
                    get: { ms.LS_actualStart },
                    set: { ms.LS_actualStart = max($0, ms.gameStartTime); ms.updateIntervalIfNeeded() }))
                if let latest = ms.latestPermissibleStart {
                    HStack {
                        Text("Latest first ball (5 overs a side)").foregroundStyle(Board.dim)
                        Spacer()
                        Text(TU.shortTime(latest)).font(.headline.monospacedDigit())
                            .foregroundStyle(ms.LS_actualStart > latest ? Board.stop : Board.gold)
                    }
                    .font(.subheadline)
                }
            }

            BigActionButton(title: "First ball bowled now", systemImage: "figure.cricket", color: Board.pitch,
                            foreground: Board.bg) {
                ms.recordFirstBall(at: Date())
                Haptic.success()
            }
            Button("Record first ball at the expected time instead") {
                ms.recordFirstBall(at: ms.LS_actualStart)
                Haptic.success()
            }
            .font(.callout.weight(.semibold)).foregroundStyle(Board.gold)

            RulesFooter(overs: plan.oversPerTeam)
        }
    }
}

// MARK: - Stoppage calculator (shared by both innings)
// Used after the umpires come off: enter when play stopped and a proposed restart, read the overs,
// and record the stoppage once play actually restarts.

struct StoppageControl: View {
    @EnvironmentObject var ms: MatchState
    @State private var stoppedAt = StoppageControl.nowToMinute()
    @State private var restartAt = TU.addMin(StoppageControl.nowToMinute(), 30)
    @State private var message: String?
    @State private var recorded = false

    static func nowToMinute() -> Date {
        Calendar.current.dateInterval(of: .minute, for: Date())?.start ?? Date()
    }
    /// A restart clock time earlier than the stop time is the next day (after midnight).
    private var restart: Date { restartAt <= stoppedAt ? TU.addMin(restartAt, 24 * 60) : restartAt }
    private var minutesOff: Int { TU.minBetween(stoppedAt, restart) }

    var body: some View {
        VStack(spacing: 12) {
            BoardSection(title: "Rain stoppage") {
                BoardTimeRow(label: "Play stopped at", time: $stoppedAt)
                BoardTimeRow(label: "Restart at", time: $restartAt)
                HStack {
                    Text("Time off").foregroundStyle(Board.dim)
                    Spacer()
                    Text("\(minutesOff) min").font(.headline.monospacedDigit()).foregroundStyle(Board.rain)
                }
                result
            }
            startByTable
            BigActionButton(title: "Record stoppage (play restarted)", systemImage: "checkmark.circle.fill",
                            color: Board.pitch, foreground: Board.bg) {
                message = ms.recordStoppage(from: stoppedAt, to: restart)
                if message == nil {
                    Haptic.success(); recorded = true
                    stoppedAt = StoppageControl.nowToMinute()
                    restartAt = TU.addMin(stoppedAt, 30)
                } else { Haptic.warning() }
            }
            if let message {
                Text(message).font(.callout.weight(.semibold)).foregroundStyle(Board.stop)
            } else if recorded {
                Text("Stoppage recorded. The board above shows the revised match.")
                    .font(.callout).foregroundStyle(Board.pitch)
            }
        }
        .onAppear {
            // A stoppage started with the earlier live button is carried into the form.
            if let open = ms.openStoppageStart { stoppedAt = open; ms.cancelOpenStoppage() }
        }
        .onChange(of: stoppedAt) { _, _ in recorded = false; message = nil }
        .onChange(of: restartAt) { _, _ in recorded = false; message = nil }
    }

    @ViewBuilder private var result: some View {
        if ms.matchPhase == .second, let w = ms.secondInningsPreview(stoppedAt: stoppedAt, resumingAt: restart) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Restart at \(TU.shortTime(restart)):").font(.subheadline).foregroundStyle(Board.dim)
                Text("\(w.revisedOvers) overs in this innings").font(.system(.title, design: .rounded).weight(.heavy))
                    .foregroundStyle(Board.gold)
                Text("\(w.oversLost) overs lost · innings ends \(TU.shortTime(w.revisedCessation))")
                    .font(.headline).foregroundStyle(Board.text)
            }
        } else if let p = ms.firstInningsPreview(stoppedAt: stoppedAt, resumingAt: restart) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Restart at \(TU.shortTime(restart)):").font(.subheadline).foregroundStyle(Board.dim)
                Text("\(p.oversPerTeam) overs a side").font(.system(.title, design: .rounded).weight(.heavy))
                    .foregroundStyle(Board.gold)
                Text("1st innings ends \(TU.shortTime(p.firstCessation)) · break \(TU.minBetween(p.firstCessation, p.secondStart)) min · match ends \(TU.shortTime(p.secondCessation))")
                    .font(.headline).foregroundStyle(Board.text)
            }
        } else {
            Text("Restart must be after play stopped.").font(.callout).foregroundStyle(Board.stop)
        }
    }

    @ViewBuilder private var startByTable: some View {
        let rows = ms.restartDeadlines(stoppedAt: stoppedAt)
        if !rows.isEmpty {
            BoardSection(title: ms.matchPhase == .second ? "Start by (overs this innings)" : "Start by (overs a side)") {
                ForEach(rows, id: \.overs) { row in
                    HStack {
                        Text("\(row.overs) overs").font(.headline.monospacedDigit()).foregroundStyle(Board.text)
                        Spacer()
                        Text("restart by \(TU.shortTime(row.latest))")
                            .font(.headline.monospacedDigit()).foregroundStyle(Board.gold)
                    }
                }
                Text("Latest restart that still gives that many overs, from a stop at \(TU.shortTime(stoppedAt)).")
                    .font(.footnote).foregroundStyle(Board.dim)
            }
        }
    }
}

// MARK: - Recorded stoppages (tap to correct)

struct StoppageListSection: View {
    @EnvironmentObject var ms: MatchState
    let second: Bool
    @State private var editing: InningsDelay?

    private var delays: [InningsDelay] { (second ? ms.secondInningsDelays : ms.firstInningsDelays).sorted { $0.start < $1.start } }

    var body: some View {
        if !delays.isEmpty || (!second && ms.LS_actualStart > ms.gameStartTime) {
            BoardSection(title: "Time lost") {
                if !second && ms.LS_actualStart > ms.gameStartTime {
                    row(label: "Late start", from: ms.gameStartTime, to: ms.LS_actualStart)
                }
                ForEach(delays) { d in
                    Button { editing = d } label: {
                        row(label: "Stoppage", from: d.start, to: d.end, editable: true)
                    }
                    .buttonStyle(.plain)
                }
                if !second, ms.undoFirstInningsDelays != nil {
                    Button("Undo last change") { ms.undoLastFirstInningsChange() }
                        .font(.callout.weight(.semibold)).foregroundStyle(Board.gold)
                }
            }
            .sheet(item: $editing) { d in
                StoppageEditSheet(delay: d, second: second).environmentObject(ms)
            }
        }
    }

    private func row(label: String, from: Date, to: Date, editable: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(label).font(.subheadline.weight(.semibold)).foregroundStyle(Board.text)
                Text("\(TU.shortTime(from)) – \(TU.shortTime(to))")
                    .font(.caption.monospacedDigit()).foregroundStyle(Board.dim)
            }
            Spacer()
            Text("\(TU.minBetween(from, to)) min").font(.headline.monospacedDigit()).foregroundStyle(Board.rain)
            if editable { Image(systemName: "pencil").foregroundStyle(Board.dim) }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

struct StoppageEditSheet: View {
    @EnvironmentObject var ms: MatchState
    @Environment(\.dismiss) private var dismiss
    let delay: InningsDelay
    let second: Bool
    @State private var start: Date
    @State private var end: Date
    @State private var failed = false

    init(delay: InningsDelay, second: Bool) {
        self.delay = delay
        self.second = second
        _start = State(initialValue: delay.start)
        _end = State(initialValue: delay.end)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Play stopped", selection: $start, displayedComponents: .hourAndMinute)
                DatePicker("Play resumed", selection: $end, displayedComponents: .hourAndMinute)
                Text("\(TU.signedMinBetween(start, end)) min").monospacedDigit()
                if failed {
                    Text("Those times overlap another stoppage or run backwards.").foregroundStyle(.red)
                }
                Section {
                    Button("Delete this stoppage", role: .destructive) {
                        if second { ms.secondInningsDelays.removeAll { $0.id == delay.id } }
                        else { ms.deleteFirstInningsDelay(id: delay.id) }
                        dismiss()
                    }
                }
            }
            .navigationTitle("Correct stoppage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let ok = second ? ms.editSecondInningsDelay(id: delay.id, start: start, end: end)
                                        : ms.editFirstInningsDelay(id: delay.id, start: start, end: end)
                        if ok { dismiss() } else { failed = true; Haptic.warning() }
                    }
                }
            }
        }
    }
}

// MARK: - First innings

struct FirstInningsPanel: View {
    @EnvironmentObject var ms: MatchState
    private var plan: EqualOversPlan { ms.firstInningsPlan }
    private var loss: MatchState.FirstInningsLoss { ms.firstInningsLoss }

    var body: some View {
        VStack(spacing: 14) {
            BlockingBanner(warnings: ms.blockingWarnings)
            AnswerBoard(
                caption: loss.totalLoss > 0 ? "Revised match" : "Full match",
                headline: "\(plan.oversPerTeam)", headlineUnit: "overs a side",
                rows: [("Innings break", "\(TU.minBetween(plan.firstCessation, plan.secondStart)) min"),
                       ("1st innings ends", TU.shortTime(plan.firstCessation)),
                       ("2nd innings starts", TU.shortTime(plan.secondStart)),
                       ("Match ends", TU.shortTime(plan.secondCessation))],
                note: loss.totalLoss > 0
                    ? "Time lost \(loss.totalLoss) min" +
                      (loss.extraApplied > 0 ? " · extra time used \(loss.extraApplied) min" : "") +
                      (loss.intervalCredit > 0 ? " · break shortened by \(loss.intervalCredit) min" : "")
                    : nil)
            StoppageControl()
            StoppageListSection(second: false)
            BigActionButton(title: "1st innings complete", systemImage: "flag.checkered",
                            color: Board.panelHi) {
                ms.matchPhase = .second
                Haptic.light()
            }
            RulesFooter(overs: plan.oversPerTeam)
        }
    }
}

// MARK: - Second innings

struct SecondInningsPanel: View {
    @EnvironmentObject var ms: MatchState
    @State private var overs: Int = 0
    @State private var firstBall = Date()

    var body: some View {
        if ms.secondInningsStarted { started } else { setup }
    }

    private var setup: some View {
        let plan = ms.firstInningsPlan
        let early = TU.minBetween(firstBall, plan.secondStart)
        return VStack(spacing: 14) {
            AnswerBoard(caption: "2nd innings", headline: "\(overs)", headlineUnit: "overs",
                        rows: [("Scheduled start", TU.shortTime(plan.secondStart)),
                               ("Innings length", "\(TU.ceilMin(Double(overs) * ms.rules.minutesPerOver)) min")],
                        note: early > 0 ? "Starting \(early) min early: that time is credited if play is lost later." : nil)
            BoardSection(title: "Set up") {
                Stepper(value: $overs, in: 1...ms.rules.maxOversPerTeam) {
                    Text("Overs: \(overs)").font(.body.weight(.semibold)).foregroundStyle(Board.text)
                }
                Text("Normally the 1st innings allocation (\(plan.oversPerTeam)). Change it only if the 1st innings was terminated.")
                    .font(.footnote).foregroundStyle(Board.dim)
                BoardTimeRow(label: "First ball", time: $firstBall)
            }
            BigActionButton(title: "First ball bowled now", systemImage: "figure.cricket", color: Board.pitch,
                            foreground: Board.bg) {
                ms.beginSecondInnings(at: Date(), overs: overs); Haptic.success()
            }
            Button("Record first ball at \(TU.shortTime(firstBall)) instead") {
                ms.beginSecondInnings(at: firstBall, overs: overs); Haptic.success()
            }
            .font(.callout.weight(.semibold)).foregroundStyle(Board.gold)
        }
        .onAppear {
            if overs == 0 { overs = plan.oversPerTeam }
            firstBall = max(Date(), Calendar.current.date(byAdding: .minute, value: 0, to: plan.firstCessation) ?? Date())
            if firstBall > plan.secondStart { firstBall = plan.secondStart }
        }
    }

    private var started: some View {
        let w = ms.secondInningsLive
        return VStack(spacing: 14) {
            BlockingBanner(warnings: ms.blockingWarnings)
            AnswerBoard(
                caption: w.oversLost > 0 ? "Revised 2nd innings" : "2nd innings",
                headline: "\(w.revisedOvers)", headlineUnit: "overs",
                rows: [("Innings ends", TU.shortTime(w.revisedCessation)),
                       ("Overs lost", "\(w.oversLost)"),
                       ("Started", TU.shortTime(ms.A3_startOfInnings)),
                       ("Time lost", "\(w.interruptionMinutes) min")],
                note: w.allowanceMinutes > 0 ? "\(w.allowanceMinutes) min credited (extra time / early start) before overs were lost." : nil)
            if w.exceedsCompletedOvers {
                BlockingBanner(warnings: [ValidationWarning(message: "Revised overs are fewer than the overs already bowled. Check the stoppage times.", severity: .error)])
            }
            StoppageControl()
            BoardSection(title: "Overs bowled (optional)") {
                Stepper(value: $ms.secondInningsCompletedOvers, in: 0...ms.rules.maxOversPerTeam) {
                    Text("\(ms.secondInningsCompletedOvers).\(ms.secondInningsCompletedBalls) overs")
                        .font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(Board.text)
                }
                Stepper(value: $ms.secondInningsCompletedBalls, in: 0...5) {
                    Text("Balls in current over").foregroundStyle(Board.dim)
                }
            }
            StoppageListSection(second: true)
            RulesFooter(overs: w.revisedOvers)
            Button("Restart 2nd innings set-up") { ms.secondInningsStarted = false }
                .font(.footnote).foregroundStyle(Board.dim)
        }
    }
}

// MARK: - Summary

struct SummaryPanel: View {
    @EnvironmentObject var ms: MatchState
    @Binding var showShare: Bool
    @State private var saved = false

    var body: some View {
        let plan = ms.firstInningsPlan
        let w = ms.secondInningsLive
        VStack(spacing: 14) {
            AnswerBoard(caption: ms.competition.fullName,
                        headline: "\(ms.secondInningsStarted ? w.revisedOvers : plan.oversPerTeam)",
                        headlineUnit: ms.secondInningsStarted ? "overs (2nd inns)" : "overs a side",
                        rows: [("Scheduled start", TU.shortTime(ms.gameStartTime)),
                               ("First ball", TU.shortTime(ms.LS_actualStart)),
                               ("1st innings overs", "\(plan.oversPerTeam)"),
                               ("Match ends", TU.shortTime(ms.secondInningsStarted ? w.revisedCessation : plan.secondCessation))])
            StoppageListSection(second: false)
            StoppageListSection(second: true)
            BigActionButton(title: "Share with scorers & referee", systemImage: "square.and.arrow.up",
                            color: Board.gold, foreground: Board.bg) { showShare = true }
            BigActionButton(title: saved ? "Saved" : "Save match", systemImage: saved ? "checkmark" : "tray.and.arrow.down",
                            color: Board.panelHi) {
                ms.saveCurrentMatch(); saved = true; Haptic.success()
            }
        }
    }
}

// MARK: - Detailed Appendix J sheets (the original screens)

struct WorkingSheet: View {
    @EnvironmentObject var ms: MatchState
    @Environment(\.dismiss) private var dismiss
    @State private var tab: Tab = .firstInns

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                TabBar(selection: $tab, competition: ms.competition)
                Group {
                    switch tab {
                    case .lateStart:   LateStartODCView()
                    case .firstInns:   FirstInningsView()
                    case .termination: TerminationCheckView()
                    case .secondStart: SecondInningsStartView()
                    case .secondInter: SecondInningsInterruptionView()
                    case .powerplays:  PowerplayHelperView()
                    case .breaks:      BreaksAndDelaysView()
                    case .summary:     LiveMatchSummaryView()
                    }
                }
                .environmentObject(ms)
            }
            .padding(.top, 8)
            .navigationTitle("Working")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
