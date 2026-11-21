import Foundation

// MARK: - Match-day flow (one-tap events on top of the Appendix J calculations)
//
// These functions only record real events (first ball, play stopped, play resumed,
// second innings first ball) into the same fields the detailed worksheets use.
// No calculation here is new: overs, intervals, extra time and cessation times all come
// from firstInningsPlan / firstInningsLoss / SecondInningsWorksheet, which the self-tests cover.

extension MatchState {

    // MARK: Before play

    /// Records the first ball. A first ball before the scheduled start is treated as on time.
    func recordFirstBall(at time: Date) {
        let ball = max(time, gameStartTime)
        LS_actualStart = ball
        if firstInningsDelays.isEmpty {
            B_timeInProgress = 0
            C_playingTimeLost = 0
            J_startOrRecommence = ball
        }
        updateIntervalIfNeeded()
        matchPhase = .first
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
            guard played <= A_netPlayingTime / 2 else {
                return "More than half the playing time had been used before this stoppage. Check the times."
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
    func restartDeadlines(stoppedAt start: Date, horizon: Int = 300, limit: Int = 6) -> [(overs: Int, latest: Date)] {
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

    /// First-innings playing minutes already used when play stopped at `start`.
    func firstInningsPlayed(before start: Date) -> Int {
        max(0, TU.minBetween(LS_actualStart, start) - C_playingTimeLost)
    }

    /// Discards an open stoppage without recording it (tapped by mistake).
    func cancelOpenStoppage() { openStoppageStart = nil }

    /// What the first innings would look like if play resumed at `time` (nothing is saved).
    func firstInningsPreview(resumingAt time: Date) -> EqualOversPlan? {
        guard let start = openStoppageStart else { return nil }
        return firstInningsPreview(stoppedAt: start, resumingAt: time)
    }

    /// Pure preview for a stoppage entered after the event: stopped at `start`, restarting at `time`.
    func firstInningsPreview(stoppedAt start: Date, resumingAt time: Date) -> EqualOversPlan? {
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
    func beginSecondInnings(at time: Date, overs: Int) {
        let scheduled = firstInningsPlan.secondStart
        let o = min(rules.maxOversPerTeam, max(1, overs))
        H_maxOversAtStart = o
        A2_maxOvers = o
        A3_startOfInnings = time
        C2_startTime = time
        B3_startOfInterruption = time
        D3_restartTime = time
        F3_additionalTimeAvail = TU.minBetween(time, scheduled)
        secondInningsDelays = []
        secondInningsCompletedOvers = 0
        secondInningsCompletedBalls = 0
        openStoppageStart = nil
        secondInningsStarted = true
        matchPhase = .second
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

    func secondInningsPreview(stoppedAt start: Date, resumingAt time: Date) -> SecondInningsWorksheet? {
        guard matchPhase == .second, time > start else { return nil }
        return secondWorksheet(with: secondInningsDelays + [InningsDelay(start: start, end: time, allowanceMinutes: 0)])
    }

    // MARK: Corrections

    /// Edits a recorded second-innings stoppage. Returns false if it would overlap or run backwards.
    @discardableResult
    func editSecondInningsDelay(id: UUID, start: Date, end: Date) -> Bool {
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
