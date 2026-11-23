import Foundation

// MARK: - Match-day flow (one-tap events on top of the Appendix J calculations)
//
// These functions only record real events (first ball, play stopped, play resumed,
// second innings first ball) into the same fields the detailed worksheets use.
// No calculation here is new: overs, intervals, extra time and cessation times all come
// from firstInningsPlan / firstInningsLoss / SecondInningsWorksheet, which the self-tests cover.

extension MatchState {

    // MARK: Match-day clock

    /// Puts a clock time on the match day. Time pickers keep whatever date a Date already had, so a
    /// match set up the night before would otherwise compare Saturday's start with Sunday's stoppage.
    /// A time more than 6 hours before the scheduled start is treated as after midnight.
    func onMatchDay(_ clock: Date) -> Date {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: clock)
        guard let h = hm.hour, let m = hm.minute,
              var d = cal.date(bySettingHour: h, minute: m, second: 0, of: gameStartTime) else { return clock }
        if d < TU.addMin(gameStartTime, -6 * 60) { d = TU.addMin(d, 24 * 60) }
        return d
    }

    /// Scheduled start set from a clock time. Before the first ball is recorded it moves to today,
    /// so a match created on an earlier day is played on the day it is used.
    func setScheduledStart(clock: Date) {
        let cal = Calendar.current
        let hm = cal.dateComponents([.hour, .minute], from: clock)
        let base = (matchPhase == .before && firstInningsDelays.isEmpty) ? Date() : gameStartTime
        if let h = hm.hour, let m = hm.minute,
           let d = cal.date(bySettingHour: h, minute: m, second: 0, of: base) {
            gameStartTime = d
            if LS_actualStart < d || matchPhase == .before { LS_actualStart = d }
            updateIntervalIfNeeded()
        }
    }

    // MARK: Before play

    /// Records the first ball. A first ball before the scheduled start is treated as on time.
    func recordFirstBall(at time: Date) {
        let ball = max(onMatchDay(time), gameStartTime)
        LS_actualStart = ball
        if firstInningsDelays.isEmpty {
            B_timeInProgress = 0
            C_playingTimeLost = 0
            J_startOrRecommence = ball
        }
        updateIntervalIfNeeded()
        matchPhase = .first
    }

    /// Corrects the first ball after it was recorded (or removes a late start: pass the scheduled start).
    /// Refused if the new time would fall inside or after a recorded stoppage.
    @discardableResult
    func correctFirstBall(to clock: Date) -> Bool {
        let ball = max(onMatchDay(clock), gameStartTime)
        if let first = firstInningsDelays.map(\.start).min(), ball > first { return false }
        LS_actualStart = ball
        if firstInningsDelays.isEmpty {
            B_timeInProgress = 0; C_playingTimeLost = 0; J_startOrRecommence = ball
            updateIntervalIfNeeded()
        } else {
            rebuildFirstInningsFromLogs()
        }
        return true
    }

    /// Latest permissible first ball for domestic T20s (BBL/WBBL), or nil where the PCs give none.
    var latestPermissibleStart: Date? {
        guard competition.isT20, !competition.isInternational,
              let window = rules.lateStartMaxWindow else { return nil }
        let seconds = EqualOversCalculator.minimumInningsSeconds(
            competition: competition, rules: rules, minOvers: rules.minValidOvers)
        return EqualOversCalculator.latestFirstBall(
            cessation: TU.addMin(gameStartTime, window), inningsSeconds: seconds, intervalMinutes: 10)
    }

    // MARK: Stoppages

    /// Start of the playing time the current innings can be stopped from.
    private var currentInningsFloor: Date {
        switch matchPhase {
        case .second: return max(A3_startOfInnings, secondInningsDelays.map(\.end).max() ?? A3_startOfInnings)
        default:      return max(LS_actualStart, firstInningsDelays.map(\.end).max() ?? LS_actualStart)
        }
    }

    /// "Play stopped". Returns a message when the time cannot be accepted.
    @discardableResult
    func stopPlay(at time: Date) -> String? {
        guard openStoppageStart == nil else { return "Play is already stopped." }
        guard matchPhase == .first || (matchPhase == .second && secondInningsStarted) else {
            return "Start the innings first."
        }
        guard time >= currentInningsFloor else {
            return "That time is before play was last under way (\(TU.shortTime(currentInningsFloor)))."
        }
        openStoppageStart = time
        return nil
    }

    /// "Play resumed". Records the stoppage into the innings log. Returns a message on rejection.
    @discardableResult
    func resumePlay(at time: Date) -> String? {
        guard let start = openStoppageStart else { return "Play is not stopped." }
        guard time > start else { return "Restart must be after play stopped (\(TU.shortTime(start)))." }
        switch matchPhase {
        case .second:
            secondInningsDelays.append(InningsDelay(start: start, end: time, allowanceMinutes: 0))
            secondInningsDelays.sort { $0.start < $1.start }
            B3_startOfInterruption = start
            D3_restartTime = time
        default:
            let played = max(0, TU.minBetween(LS_actualStart, start) - C_playingTimeLost)
            guard played <= A_netPlayingTime else {
                return "More than the whole match's playing time had been used before this stoppage. Check the times."
            }
            undoFirstInningsDelays = firstInningsDelays
            firstInningsDelays.append(InningsDelay(start: start, end: time, allowanceMinutes: 0))
            firstInningsDelays.sort { $0.start < $1.start }
            rebuildFirstInningsFromLogs()
        }
        openStoppageStart = nil
        return nil
    }

    /// Records a stoppage entered after coming off: stopped at `start`, play restarted at `end`.
    @discardableResult
    func recordStoppage(from start: Date, to end: Date) -> String? {
        let start = onMatchDay(start)
        var end = onMatchDay(end)
        if end <= start { end = TU.addMin(end, 24 * 60) }
        let previous = openStoppageStart
        openStoppageStart = nil
        if let message = stopPlay(at: start) { openStoppageStart = previous; return message }
        if let message = resumePlay(at: end) { openStoppageStart = previous; return message }
        return nil
    }

    /// Overs per side (1st innings) or revised overs (2nd innings) for a restart at `time`.
    func previewOvers(stoppedAt start: Date, resumingAt time: Date) -> Int? {
        if matchPhase == .second { return secondInningsPreview(stoppedAt: start, resumingAt: time)?.revisedOvers }
        return firstInningsPreview(stoppedAt: start, resumingAt: time)?.oversPerTeam
    }

    /// The latest restart time that still gives each number of overs, highest overs first.
    /// Scans minute by minute from the stop time (up to `horizon` minutes) using the same previews.
    func restartDeadlines(stoppedAt rawStart: Date, horizon: Int = 300, limit: Int = 6) -> [(overs: Int, latest: Date)] {
        let start = onMatchDay(rawStart)
        var latest: [Int: Date] = [:]
        var order: [Int] = []
        for m in 1...horizon {
            let t = TU.addMin(start, m)
            guard let o = previewOvers(stoppedAt: start, resumingAt: t), o > 0 else { break }
            if latest[o] == nil { order.append(o) }
            latest[o] = t
        }
        return order.prefix(limit).compactMap { o in latest[o].map { (o, $0) } }
    }

    // MARK: Pure "what if" for a set of first-innings stoppages (used when correcting one)

    /// The first-innings plan if the recorded stoppages were `delays` (same steps as
    /// rebuildFirstInningsFromLogs + firstInningsLoss + firstInningsPlan; nothing is saved).
    func firstInningsPlan(for delays: [InningsDelay]) -> EqualOversPlan? {
        let ordered = delays.sorted { $0.start < $1.start }
        guard let last = ordered.last, ordered.allSatisfy({ $0.end > $0.start }) else { return nil }
        let lostInLog = ordered.reduce(0) { $0 + $1.duration }
        let earlier = ordered.dropLast().reduce(0) { $0 + $1.duration }
        let played = max(0, TU.minBetween(LS_actualStart, last.start) - earlier)
        let late = max(0, TU.minBetween(gameStartTime, LS_actualStart))
        let lost = late + lostInLog
        let interval = rules.adjustedInterval(timeLost: lost)
        let credit = max(0, rules.defaultIntervalMinutes - interval)
        let effective = max(0, lost - min(lost, rules.extraTimeMinutes) - credit)
        let raw = Double(max(0, A_netPlayingTime - effective)) / rules.minutesPerOver
        let total = competition.isT20 ? TU.round2(raw) : raw
        return EqualOversCalculator.plan(
            rules: rules, originalStart: gameStartTime, restart: last.end, playedMinutes: played,
            initialOvers: TU.ceilOv(total / 2.0), interval: interval,
            rescheduledCessation: rescheduledCessationEnabled ? rescheduledCessation : nil)
    }

    /// Overs for the current innings if stoppage `id` (nil = a new one) ran from `start` to `end`.
    func overs(replacing id: UUID?, start rawStart: Date, end rawEnd: Date) -> Int? {
        let start = onMatchDay(rawStart)
        var end = onMatchDay(rawEnd)
        if end <= start { end = TU.addMin(end, 24 * 60) }
        guard end > start else { return nil }
        let edited = InningsDelay(start: start, end: end, allowanceMinutes: 0)
        if matchPhase == .second {
            return secondWorksheet(with: secondInningsDelays.filter { $0.id != id } + [edited]).revisedOvers
        }
        return firstInningsPlan(for: firstInningsDelays.filter { $0.id != id } + [edited])?.oversPerTeam
    }

    /// Start-by table for stoppage `id` (nil = a new one) that began at `start`.
    func restartDeadlines(replacing id: UUID?, stoppedAt rawStart: Date, horizon: Int = 300, limit: Int = 4) -> [(overs: Int, latest: Date)] {
        let start = onMatchDay(rawStart)
        var latest: [Int: Date] = [:]
        var order: [Int] = []
        for m in 1...horizon {
            let t = TU.addMin(start, m)
            guard let o = overs(replacing: id, start: start, end: t), o > 0 else { break }
            if latest[o] == nil { order.append(o) }
            latest[o] = t
        }
        return order.prefix(limit).compactMap { o in latest[o].map { (o, $0) } }
    }

    /// True when the recorded 1st innings has already used all the playing time its revised length allows,
    /// i.e. the innings has reached its end (termination: Appendix J 1.2).
    var firstInningsTimeUsedUp: Bool {
        guard matchPhase != .second, !firstInningsDelays.isEmpty else { return false }
        return B_timeInProgress >= firstInningsPlan.inningsMinutes
    }

    /// First-innings playing minutes already used when play stopped at `start`.
    func firstInningsPlayed(before start: Date) -> Int {
        max(0, TU.minBetween(LS_actualStart, onMatchDay(start)) - C_playingTimeLost)
    }

    /// Discards an open stoppage without recording it (tapped by mistake).
    func cancelOpenStoppage() { openStoppageStart = nil }

    /// What the first innings would look like if play resumed at `time` (nothing is saved).
    func firstInningsPreview(resumingAt time: Date) -> EqualOversPlan? {
        guard let start = openStoppageStart else { return nil }
        return firstInningsPreview(stoppedAt: start, resumingAt: time)
    }

    /// Pure preview for a stoppage entered after the event: stopped at `start`, restarting at `time`.
    func firstInningsPreview(stoppedAt rawStart: Date, resumingAt rawTime: Date) -> EqualOversPlan? {
        let start = onMatchDay(rawStart)
        var time = onMatchDay(rawTime)
        if time <= start { time = TU.addMin(time, 24 * 60) }
        guard time > start, matchPhase != .second else { return nil }
        let thisStoppage = TU.minBetween(start, time)
        let played = max(0, TU.minBetween(LS_actualStart, start) - C_playingTimeLost)
        let lost = max(0, TU.minBetween(gameStartTime, LS_actualStart)) + C_playingTimeLost + thisStoppage
        let interval = rules.adjustedInterval(timeLost: lost)
        let credit = max(0, rules.defaultIntervalMinutes - interval)
        let effective = max(0, lost - min(lost, rules.extraTimeMinutes) - credit)
        let available = max(0, A_netPlayingTime - effective)
        let raw = Double(available) / rules.minutesPerOver
        let total = competition.isT20 ? TU.round2(raw) : raw
        return EqualOversCalculator.plan(
            rules: rules, originalStart: gameStartTime, restart: time, playedMinutes: played,
            initialOvers: TU.ceilOv(total / 2.0), interval: interval,
            rescheduledCessation: rescheduledCessationEnabled ? rescheduledCessation : nil)
    }

    // MARK: Second innings

    /// First ball of the second innings. Overs default to the first-innings allocation; time gained by
    /// starting before the scheduled second-innings start is credited (App. J 1.4 step F, cl. 13.7.2.2.2).
    func beginSecondInnings(at clock: Date, overs: Int) {
        let time = onMatchDay(clock)
        let scheduled = firstInningsPlan.secondStart
        let o = min(rules.maxOversPerTeam, max(1, overs))
        H_maxOversAtStart = o
        A2_maxOvers = o
        A3_startOfInnings = time
        C2_startTime = time
        B3_startOfInterruption = time
        D3_restartTime = time
        if time > scheduled {
            // Started late (e.g. rain in the interval): lost playing time for the side batting
            // second (cl. 13.7.2.2.1). Recorded as a delayed start from the scheduled time.
            A3_startOfInnings = scheduled
            C2_startTime = scheduled
            B3_startOfInterruption = scheduled
            F3_additionalTimeAvail = 0
            secondInningsDelays = [InningsDelay(start: scheduled, end: time, allowanceMinutes: 0)]
        } else {
            F3_additionalTimeAvail = TU.minBetween(time, scheduled)
            secondInningsDelays = []
        }
        secondInningsCompletedOvers = 0
        secondInningsCompletedBalls = 0
        openStoppageStart = nil
        secondInningsStarted = true
        matchPhase = .second
    }

    /// Overs for a 2nd innings whose first ball is at `clock` (late start reduces overs; early start does not).
    func secondInningsStartPreview(at clock: Date, overs: Int) -> SecondInningsWorksheet {
        let time = onMatchDay(clock)
        let scheduled = firstInningsPlan.secondStart
        let late = time > scheduled
        return SecondInningsWorksheet.calculate(
            rules: rules, inningsStart: late ? scheduled : time, restart: time, initialOvers: overs,
            delays: late ? [InningsDelay(start: scheduled, end: time, allowanceMinutes: 0)] : [],
            completedOvers: 0, completedBalls: 0,
            extraTimeAlreadyUsed: firstInningsLoss.extraApplied, earlyStartCredit: 0)
    }

    /// When the 2nd innings actually started (after any delayed start).
    var secondInningsFirstBall: Date {
        if let d = secondInningsDelays.first, d.start == A3_startOfInnings { return d.end }
        return A3_startOfInnings
    }

    /// True when the recorded first ball is after the latest permissible start (BBL/WBBL).
    var firstBallAfterLatestStart: Bool {
        guard let latest = latestPermissibleStart else { return false }
        return LS_actualStart > latest
    }

    private func secondWorksheet(with delays: [InningsDelay]) -> SecondInningsWorksheet {
        SecondInningsWorksheet.calculate(
            rules: rules, inningsStart: A3_startOfInnings,
            restart: delays.map(\.end).max() ?? A3_startOfInnings,
            initialOvers: H_maxOversAtStart, delays: delays,
            completedOvers: secondInningsCompletedOvers, completedBalls: secondInningsCompletedBalls,
            extraTimeAlreadyUsed: firstInningsLoss.extraApplied,
            earlyStartCredit: F3_additionalTimeAvail)
    }

    /// The second innings as recorded so far.
    var secondInningsLive: SecondInningsWorksheet { secondWorksheet(with: secondInningsDelays) }

    /// What the second innings would look like if play resumed at `time` (nothing is saved).
    func secondInningsPreview(resumingAt time: Date) -> SecondInningsWorksheet? {
        guard let start = openStoppageStart else { return nil }
        return secondInningsPreview(stoppedAt: start, resumingAt: time)
    }

    func secondInningsPreview(stoppedAt rawStart: Date, resumingAt rawTime: Date) -> SecondInningsWorksheet? {
        let start = onMatchDay(rawStart)
        var time = onMatchDay(rawTime)
        if time <= start { time = TU.addMin(time, 24 * 60) }
        guard matchPhase == .second, time > start else { return nil }
        return secondWorksheet(with: secondInningsDelays + [InningsDelay(start: start, end: time, allowanceMinutes: 0)])
    }

    // MARK: Corrections

    /// Edits a recorded second-innings stoppage. Returns false if it would overlap or run backwards.
    @discardableResult
    func editSecondInningsDelay(id: UUID, start rawStart: Date, end rawEnd: Date) -> Bool {
        let start = onMatchDay(rawStart)
        var end = onMatchDay(rawEnd)
        if end <= start { end = TU.addMin(end, 24 * 60) }
        guard end > start, start >= A3_startOfInnings else { return false }
        let others = secondInningsDelays.filter { $0.id != id }
        guard !others.contains(where: { start < $0.end && end > $0.start }),
              let i = secondInningsDelays.firstIndex(where: { $0.id == id }) else { return false }
        secondInningsDelays[i].start = start
        secondInningsDelays[i].end = end
        secondInningsDelays.sort { $0.start < $1.start }
        return true
    }

    /// Only the warnings that stop a calculation being used.
    var blockingWarnings: [ValidationWarning] {
        let all = matchPhase == .second && secondInningsStarted
            ? secondInningsInterruptionWarnings() : firstInningsWarnings()
        return all.filter { $0.severity == .error }
    }
}
