// BoundaryLineSelfTests.swift
// ON-DEVICE SELF-TESTS for Swift Playgrounds on iPad (no Xcode, no XCTest needed).
// NOT COMPILED OR RUN where it was written. Add this file to your app project next to the main file,
// build, then open  About > "Run self-tests".
//
// SAFETY: every test runs against a TEMPORARY UserDefaults suite (Store.defaults is swapped for the
// duration and restored). Your current match, saved matches and history are never read or changed.
//
// WHERE THE EXPECTED NUMBERS COME FROM: not from the Swift formulas. They come from
//   * the 2026-27 ODC / WNCL / WBBL Playing Conditions and Appendix J worksheets,
//   * Cricket Australia's WBBL Almanac 2026/27 pp.47-48 worked example (7:40pm start -> latest 9:39pm),
//   * an independent Python re-implementation (verification/*.py) of the same rules.
// BBL checks follow the BBL|16 Playing Conditions dated 1 December 2026 (verification/bbl_expectations.py).
//
// BEFORE APP STORE UPLOAD: set BLDiagnostics.enabled = false (hides the About button).

import SwiftUI

enum BLDiagnostics {
    static let enabled = true      // <-- set to false before uploading to App Store Connect
}

struct SelfTestResult: Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let detail: String
}

private final class Recorder {
    var results: [SelfTestResult] = []
    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        results.append(SelfTestResult(name: name, passed: ok, detail: detail))
    }
    func equal<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
        check(name, actual == expected, "got \(actual), expected \(expected)")
    }
    func near(_ name: String, _ actual: Double, _ expected: Double, tol: Double = 0.01) {
        check(name, abs(actual - expected) <= tol, "got \(actual), expected \(expected)")
    }
}

enum BoundaryLineSelfTests {

    // Fixed calendar day so results never depend on today's date.
    private static func day(_ h: Int, _ m: Int = 0, _ s: Int = 0, plus d: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 11; c.day = 7 + d; c.hour = h; c.minute = m; c.second = s
        return Calendar.current.date(from: c) ?? Date()
    }

    static func run() -> [SelfTestResult] {
        let r = Recorder()
        // Swap in a throwaway store. Restored on every exit path.
        let suite = "BoundaryLineSelfTest"
        let live = Store.defaults
        guard let temp = UserDefaults(suiteName: suite) else {
            r.check("Create temporary test store", false, "UserDefaults(suiteName:) returned nil")
            return r.results
        }
        temp.removePersistentDomain(forName: suite)
        Store.defaults = temp
        defer {
            temp.removePersistentDomain(forName: suite)
            Store.defaults = live
        }

        rules(r)
        latestStart(r)
        firstInnings(r)
        secondInnings(r)
        bbl(r)
        flow(r)
        icc(r)                                   // before persistence: that group deliberately corrupts stored data
        persistence(r, suite: suite, temp: temp)
        return r.results
    }

    // MARK: 1. Constants and boundaries vs 2026-27 Playing Conditions (ODC / WNCL / WBBL)
    private static func rules(_ r: Recorder) {
        let odc = CompRules.odc, wncl = CompRules.wncl, wbbl = CompRules.wbbl
        r.equal("ODC net playing time 420 (cl 12.6.1: 2x3h30 + 30)", odc.defaultNetPlayingTimeMinutes, 420)
        r.equal("WNCL net playing time 380 (cl 12.6.1: 2x3h10 + 40)", wncl.defaultNetPlayingTimeMinutes, 380)
        r.equal("WBBL net playing time 150 (cl 12.5.1: 2x1h15 + 15)", wbbl.defaultNetPlayingTimeMinutes, 150)
        r.equal("ODC interval 30 / WNCL 40 / WBBL 15",
                [odc.defaultIntervalMinutes, wncl.defaultIntervalMinutes, wbbl.defaultIntervalMinutes], [30, 40, 15])
        r.equal("Extra time ODC 0 / WNCL 60 / WBBL 0",
                [odc.extraTimeMinutes, wncl.extraTimeMinutes, wbbl.extraTimeMinutes], [0, 60, 0])
        r.near("App. J rates 4.2 / 3.8 / 3.75",
               odc.minutesPerOver + wncl.minutesPerOver + wbbl.minutesPerOver, 11.75, tol: 0.0001)
        r.equal("Minimum overs ODC 15 (20 Final), WNCL 15 (20 Final), WBBL 5",
                [odc.minValidOvers, odc.minValidOversFinal, wncl.minValidOvers, wncl.minValidOversFinal, wbbl.minValidOvers],
                [15, 20, 15, 20, 5])
        r.equal("Over-rate cut-off ODC 206 / WNCL 187",
                [odc.cutoffFullMinutes ?? -1, wncl.cutoffFullMinutes ?? -1], [206, 187])

        r.equal("ODC interval: 59 lost -> 30", odc.adjustedInterval(timeLost: 59), 30)
        r.equal("ODC interval: 60 lost -> 20 (cl 11.3.2.1)", odc.adjustedInterval(timeLost: 60), 20)
        r.equal("WBBL interval: 15 lost -> 15", wbbl.adjustedInterval(timeLost: 15), 15)
        r.equal("WBBL interval: 16 lost -> 10 (cl 11.3.3)", wbbl.adjustedInterval(timeLost: 16), 10)
        r.equal("WNCL interval: 0 / 60 gross lost -> 40 (extra time exhausted first, cl 12.7.1)",
                [wncl.adjustedInterval(timeLost: 0), wncl.adjustedInterval(timeLost: 60)], [40, 40])
        r.equal("WNCL interval: 61 -> 30, 119 -> 30, 120 -> 20 (cl 11.3.2.1)",
                [wncl.adjustedInterval(timeLost: 61), wncl.adjustedInterval(timeLost: 119), wncl.adjustedInterval(timeLost: 120)],
                [30, 30, 20])

        // Spot checks of the tables (the full tables were compared row-by-row against the PDFs:
        // ODC 35/35, WNCL 35/35, WBBL 16/16 identical).
        let p25 = odc.odcPowerplays(for: 25)
        r.check("ODC powerplays 25 ov = 5+15+5", p25 == (5, 15, 5), "got \(p25)")
        let w25 = wncl.wnclPowerplay(for: 25)
        r.check("WNCL powerplay 25 ov = 5 / 20 / max 5", w25.pp == 5 && w25.nonPp == 20 && w25.maxBowler == 5, "got \(w25)")
        let t20 = wbbl.powerplayInfo(for: 20)
        r.check("WBBL 20 ov: 4 fixed + 2 floating, after over 10, window 11-19",
                t20.powerplayOvers == 4 && t20.surgeOvers == 2 && t20.surgeAvailableAfter == 10
                && t20.surgeWindowStart == 11 && t20.surgeWindowEnd == 19, "got \(t20)")

        // Equal-overs sanity: undisturbed ODC 50 overs = ceil(50 x 4.2) = 210 minutes.
        let plan = EqualOversCalculator.plan(rules: odc, originalStart: day(10), restart: day(10),
                                             playedMinutes: 0, initialOvers: 50, interval: 30)
        r.equal("ODC undisturbed innings length 210 min", plan.inningsMinutes, 210)
    }

    // MARK: 2. Latest permissible start (defect 2) -- CA WBBL Almanac 2026/27 pp.47-48
    private static func latestStart(_ r: Recorder) {
        let wbbl = CompRules.wbbl
        let inn = EqualOversCalculator.minimumInningsSeconds(competition: .wbbl, rules: wbbl, minOvers: 5)
        r.equal("WBBL five-over innings = 18:00 (CA convention)", inn, 18 * 60)
        // CA's worked example: 7:40pm scheduled, cessation 10:25pm, 2x18 + 10 = 46 min -> latest 9:39pm.
        let sched = day(19, 40)
        let cess = EqualOversCalculator.originalCessation(start: sched, rules: wbbl)
        r.equal("WBBL 7:40pm start -> scheduled cessation 10:25pm", cess, day(22, 25))
        let latest = EqualOversCalculator.latestFirstBall(cessation: cess, inningsSeconds: inn, intervalMinutes: 10)
        r.equal("WBBL latest first ball = 9:39pm (CA almanac example)", latest, day(21, 39))
        r.check("A 9:39pm start is permitted (inclusive)", day(21, 39) <= latest)
        r.check("A 9:40pm start is NOT permitted (CA: the 9:45pm reading is wrong)", !(day(21, 40) <= latest))
        // Seconds: never round a latest start LATER than the exact limit.
        let withSeconds = EqualOversCalculator.latestFirstBall(cessation: day(22, 25, 30), inningsSeconds: inn, intervalMinutes: 10)
        r.equal("Floors to the minute (exact 9:39:30 -> 9:39)", withSeconds, day(21, 39))
        // BBL: 2025/26 constants (2026/27 not yet published): 5 x 4.0 = 20 min each + 10 = 50.
        let bbl = CompRules.bbl
        let bInn = EqualOversCalculator.minimumInningsSeconds(competition: .bbl, rules: bbl, minOvers: 5)
        let bCess = EqualOversCalculator.originalCessation(start: day(19, 15), rules: bbl)
        let bLatest = EqualOversCalculator.latestFirstBall(cessation: bCess, inningsSeconds: bInn, intervalMinutes: 10)
        r.equal("BBL 7:15pm start -> latest 9:20pm (derived: 175 - 5x4 - 5x4 - 10; no CA almanac example for BBL)", bLatest, day(21, 20))
    }

    // MARK: 3. First innings: late start followed by rain (defect 1) and start anchor
    private static func firstInnings(_ r: Recorder) {
        // WNCL: 60-min late start + 45 min rain. Independent expectation: total loss 105, extra 60,
        // interval credit 10 (40 -> 30), effective 35, remaining 345, 345/3.8 = 90.79 overs.
        func wnclCase(typedExtra: Int) -> MatchState {
            let ms = MatchState(); ms.startMatch(.wncl)
            ms.gameStartTime = day(10); ms.LS_actualStart = day(11)
            ms.D_extraTimeAvail = typedExtra
            ms.C_playingTimeLost = 45; ms.B_timeInProgress = 60
            ms.J_startOrRecommence = day(12, 45)
            ms.updateIntervalIfNeeded()
            return ms
        }
        let a = wnclCase(typedExtra: 0), b = wnclCase(typedExtra: 60)
        r.near("WNCL late start 60 + rain 45: total overs (both) = 90.79", a.firstInningsLoss.totalOvers, 90.79)
        r.equal("... extra time applied automatically = 60", a.firstInningsLoss.extraApplied, 60)
        r.equal("... overs/side identical whether or not 'Extra time available' was typed (46)",
                [a.firstInningsPlan.oversPerTeam, b.firstInningsPlan.oversPerTeam], [46, 46])

        // Continuity: a 1-minute rain delay after a 30-minute WNCL late start must not drop overs.
        let c = MatchState(); c.startMatch(.wncl)
        c.gameStartTime = day(10); c.LS_actualStart = day(10, 30)
        let before = c.firstInningsPlan.oversPerTeam
        c.B_timeInProgress = 60; c.C_playingTimeLost = 1; c.J_startOrRecommence = day(11, 31)
        c.updateIntervalIfNeeded()
        let after = c.firstInningsPlan.oversPerTeam
        r.check("WNCL late start then 1-min rain: overs do not jump (\(before) -> \(after))", before - after <= 1)

        // Restart anchor: ODC first ball 10:40 (40 late), 30 min bowled, no rain: innings ends length after 10:40.
        let d = MatchState(); d.startMatch(.odc)
        d.gameStartTime = day(10); d.LS_actualStart = day(10, 40); d.B_timeInProgress = 30
        let plan = d.firstInningsPlan
        let expected = Calendar.current.date(byAdding: .minute, value: plan.inningsMinutes, to: day(10, 40)) ?? day(10, 40)
        r.equal("ODC late start: first innings measured from the ACTUAL first ball", plan.firstCessation, expected)

        // No behaviour change when nothing was lost.
        let e = MatchState(); e.startMatch(.odc)
        e.gameStartTime = day(10); e.LS_actualStart = day(10)
        r.equal("ODC undisturbed: 50 overs per side", e.firstInningsPlan.oversPerTeam, 50)
    }

    // MARK: 4. Second innings: extra-time pool (defect 3) and early-start credit (defect 8)
    private static func secondInnings(_ r: Recorder) {
        func overs(_ rules: CompRules, start: Date, stopS: Date, stopE: Date, initial: Int,
                   used: Int, credit: Int) -> (allowance: Int, revised: Int) {
            let w = SecondInningsWorksheet.calculate(
                rules: rules, inningsStart: start, restart: stopE, initialOvers: initial,
                delays: [InningsDelay(start: stopS, end: stopE, allowanceMinutes: 0)],
                completedOvers: 10, completedBalls: 0,
                extraTimeAlreadyUsed: used, earlyStartCredit: credit)
            return (w.allowanceMinutes, w.revisedOvers)
        }
        let n = CompRules.wncl, o = CompRules.odc, w = CompRules.wbbl
        // Independent expectations (verification/port_second_innings_and_latest_start.py).
        var x = overs(n, start: day(14), stopS: day(15), stopE: day(16, 20), initial: 40, used: 0, credit: 0)
        r.check("S1 WNCL 80-min stoppage, pool unused: allowance 60, revised 35", x.allowance == 60 && x.revised == 35, "got \(x)")
        x = overs(n, start: day(14), stopS: day(15), stopE: day(16, 20), initial: 40, used: 60, credit: 0)
        r.check("S2 WNCL pool fully used in innings 1: allowance 0, revised 19 (App. J 1.4 'unused' extra time)",
                x.allowance == 0 && x.revised == 19, "got \(x)")
        x = overs(n, start: day(14), stopS: day(15), stopE: day(16, 20), initial: 40, used: 45, credit: 0)
        r.check("S3 WNCL 45 of pool used: allowance 15, revised 23", x.allowance == 15 && x.revised == 23, "got \(x)")
        x = overs(o, start: day(14), stopS: day(15), stopE: day(15, 40), initial: 40, used: 0, credit: 30)
        r.check("S4 ODC 40-min stoppage + 30 early-start credit: allowance 30, revised 38", x.allowance == 30 && x.revised == 38, "got \(x)")
        x = overs(o, start: day(14), stopS: day(15), stopE: day(15, 40), initial: 40, used: 0, credit: 0)
        r.check("S5 ODC no credit: allowance 0, revised 31 (unchanged from before)", x.allowance == 0 && x.revised == 31, "got \(x)")
        x = overs(w, start: day(19), stopS: day(19, 30), stopE: day(20, 10), initial: 20, used: 0, credit: 30)
        r.check("S6 WBBL 40-min stoppage + 30 credit: allowance 30, revised 18", x.allowance == 30 && x.revised == 18, "got \(x)")
        x = overs(o, start: day(14), stopS: day(15), stopE: day(15, 40), initial: 40, used: 0, credit: 60)
        r.check("S7 ODC credit larger than stoppage is capped: allowance 40, revised 40", x.allowance == 40 && x.revised == 40, "got \(x)")
        x = overs(n, start: day(14), stopS: day(15), stopE: day(16, 20), initial: 40, used: 0, credit: 30)
        r.check("S8 WNCL 80-min stoppage, 60 pool + 30 credit: allowance 80, revised 40", x.allowance == 80 && x.revised == 40, "got \(x)")
    }

    // MARK: 8. Match-day flow (one-tap first ball / play stopped / play resumed)
    // These record events into the same fields the Appendix J sheets use; the checks confirm the
    // "if play restarts now" preview equals the result after the restart is recorded.
    private static func flow(_ r: Recorder) {
        let ms = MatchState(); ms.startMatch(.wbbl)
        ms.gameStartTime = day(19, 40)
        r.check("Flow: cannot stop play before the first ball", ms.stopPlay(at: day(19, 50)) != nil)
        ms.recordFirstBall(at: day(19, 40))
        r.equal("Flow: first ball moves to 1st innings, on time", [ms.matchPhase == .first ? 1 : 0, TU.minBetween(ms.gameStartTime, ms.LS_actualStart)], [1, 0])
        r.check("Flow: play stopped at 20:00 accepted", ms.stopPlay(at: day(20)) == nil)
        let relaunch = MatchState()
        r.equal("Flow: open stoppage and phase survive a relaunch",
                [relaunch.openStoppageStart == day(20) ? 1 : 0, relaunch.matchPhase == .first ? 1 : 0], [1, 1])
        let preview = ms.firstInningsPreview(resumingAt: day(20, 20))
        r.check("Flow: resume before the stop time is rejected", ms.resumePlay(at: day(19, 59)) != nil)
        r.check("Flow: play resumed at 20:20 accepted", ms.resumePlay(at: day(20, 20)) == nil)
        // WBBL, 20 min lost: interval 15 -> 10 (credit 5), 150 - 15 = 135, 135 / 3.75 = 36 -> 18 a side.
        r.equal("Flow WBBL: 20 min stoppage -> 18 overs a side, 10 min break",
                [ms.firstInningsPlan.oversPerTeam, ms.M_intervalLength], [18, 10])
        r.equal("Flow: preview before restart equals the recorded result (overs, match end)",
                [preview?.oversPerTeam ?? -1, preview.map { TU.signedMinBetween($0.secondCessation, ms.firstInningsPlan.secondCessation) } ?? -1],
                [18, 0])
        r.equal("Flow: stoppage logged once, no open stoppage left",
                [ms.firstInningsDelays.count, ms.openStoppageStart == nil ? 1 : 0, ms.C_playingTimeLost], [1, 1, 20])

        // Second innings starting 10 min before schedule: 10 min credited (App. J 1.4 F).
        let scheduled = ms.firstInningsPlan.secondStart
        ms.beginSecondInnings(at: TU.addMin(scheduled, -10), overs: 18)
        r.equal("Flow: 2nd innings 10 min early -> 10 min credit, 18 overs",
                [ms.F3_additionalTimeAvail, ms.secondInningsLive.revisedOvers], [10, 18])
        let s2 = TU.addMin(scheduled, 30)
        r.check("Flow: 2nd innings stoppage accepted", ms.stopPlay(at: s2) == nil)
        let p2 = ms.secondInningsPreview(resumingAt: TU.addMin(s2, 17))
        _ = ms.resumePlay(at: TU.addMin(s2, 17))
        // 17 lost - 10 credit = 7; floor(7 / 3.75) = 1 over lost -> 17.
        r.equal("Flow WBBL 2nd inns: 17 min lost with 10 min credit -> 17 overs; preview matches",
                [ms.secondInningsLive.revisedOvers, p2?.revisedOvers ?? -1], [17, 17])

        // Entered after coming off: stopped 20:45, restart 21:05 (same result as stop/resume buttons).
        let w = MatchState(); w.startMatch(.wbbl)
        w.gameStartTime = day(19, 40); w.recordFirstBall(at: day(19, 40))
        let pv = w.previewOvers(stoppedAt: day(20), resumingAt: day(20, 20))
        r.check("Flow: record stoppage 20:00-20:20 after the event", w.recordStoppage(from: day(20), to: day(20, 20)) == nil)
        r.equal("Flow: after-the-event entry -> 18 overs a side; preview matched", [w.firstInningsPlan.oversPerTeam, pv ?? -1], [18, 18])
        let rows = w.restartDeadlines(stoppedAt: day(20, 45))
        let consistent = !rows.isEmpty && rows.allSatisfy { row in
            w.previewOvers(stoppedAt: day(20, 45), resumingAt: row.latest) == row.overs &&
            (w.previewOvers(stoppedAt: day(20, 45), resumingAt: TU.addMin(row.latest, 1)) ?? 0) < row.overs }
        r.check("Flow: start-by table gives the latest restart for each overs figure", consistent,
                rows.map { "\($0.overs)@\(TU.shortTime($0.latest))" }.joined(separator: " "))
        r.check("Flow: overlapping after-the-event stoppage rejected", w.recordStoppage(from: day(20, 10), to: day(20, 30)) != nil)
        // Correcting a stoppage: the pure "what if" must equal the recorded plan.
        r.equal("Flow: plan for the recorded stoppages equals the live plan",
                [w.firstInningsPlan(for: w.firstInningsDelays)?.oversPerTeam ?? -1, w.firstInningsPlan.oversPerTeam], [18, 18])
        if let d = w.firstInningsDelays.first {
            let ov = w.overs(replacing: d.id, start: day(20), end: day(20, 30))
            _ = w.editFirstInningsDelay(id: d.id, start: day(20), end: day(20, 30))
            r.equal("Flow: edit preview (20:00-20:30) equals the plan after saving the edit", [ov ?? -1], [w.firstInningsPlan.oversPerTeam])
        }
        r.check("Flow: no termination alert with time left in the innings", !w.firstInningsTimeUsedUp)
        let tm = MatchState(); tm.startMatch(.wbbl)
        tm.gameStartTime = day(19, 40); tm.recordFirstBall(at: day(19, 40))
        _ = tm.recordStoppage(from: day(20, 50), to: day(21, 50))   // 70 min played, 60 min lost
        r.check("Flow: termination alert when the innings has used its revised length",
                tm.firstInningsTimeUsedUp, "played \(tm.B_timeInProgress) vs length \(tm.firstInningsPlan.inningsMinutes)")

        // Match set up the day before: times entered on the match day are compared on the same day.
        let nd = MatchState(); nd.startMatch(.wbbl)
        nd.gameStartTime = day(14, 40); nd.recordFirstBall(at: day(14, 40))
        let err = nd.recordStoppage(from: day(15, plus: 1), to: day(15, 20, plus: 1))
        r.check("Flow: next-day clock times map to the match day (2:40 start, 3:00-3:20 stoppage)", err == nil, err ?? "")
        r.equal("... 20 min played, 20 min lost -> 18 overs a side",
                [nd.B_timeInProgress, nd.C_playingTimeLost, nd.firstInningsPlan.oversPerTeam], [20, 20, 18])
        r.equal("Flow: a restart after midnight is the next day (23:50 -> 00:20 = 30 min)",
                [TU.minBetween(nd.onMatchDay(day(23, 50)), nd.onMatchDay(day(0, 20)))], [30])

        ms.saveCurrentMatch()
        ms.matchPhase = .before
        if let saved = ms.snapshots.first(where: { $0.id == ms.currentSavedMatchID }) {
            _ = ms.restoreSnapshot(saved)
            r.equal("Flow: a saved match restores to the 2nd innings", [ms.matchPhase == .second ? 1 : 0, ms.secondInningsStarted ? 1 : 0], [1, 1])
        } else { r.check("Flow: saved match found", false) }
        ms.startMatch(.odc)
        r.equal("Flow: new match starts before play with nothing open",
                [ms.matchPhase == .before ? 1 : 0, ms.openStoppageStart == nil ? 1 : 0, ms.secondInningsStarted ? 1 : 0], [1, 1, 0])
    }

    // MARK: 7. BBL|16 (Playing Conditions dated 1 December 2026)
    // Expected numbers: verification/bbl_expectations.py (from Appendix J.1 and cl. 11.3.3, 12.7, 13.7, 13.8, 28.7.4).
    private static func bbl(_ r: Recorder) {
        let b = CompRules.bbl
        r.equal("BBL: 160 net, 15 interval, 20 ov, min 5 ov, no extra time (cl 11.2.1, 12.5.1, 12.6, 16.1.2, App J.1)",
                [b.defaultNetPlayingTimeMinutes, b.defaultIntervalMinutes, b.maxOversPerTeam, b.minValidOvers, b.extraTimeMinutes],
                [160, 15, 20, 5, 0])
        r.near("BBL rate 4.0 min/over (cl 13.7.2.1.1)", b.minutesPerOver, 4.0, tol: 0.0001)
        r.equal("BBL over-rate finish time (cl 12.7.1): 20 ov = 84, 15 ov = 63, 10 ov = 43, 9 ov = none",
                [b.cutoffMinutes(for: 20) ?? -1, b.cutoffMinutes(for: 15) ?? -1, b.cutoffMinutes(for: 10) ?? -1, b.cutoffMinutes(for: 9) ?? -1],
                [84, 63, 43, -1])
        r.equal("BBL interval: 20 lost -> 15, 21 lost -> 10, 22 lost -> 10 (cl 11.3.3; 21 follows the same convention as WBBL 16, confirmed by the user, not stated by the clause)",
                [b.adjustedInterval(timeLost: 20), b.adjustedInterval(timeLost: 21), b.adjustedInterval(timeLost: 22)], [15, 10, 10])
        let p20 = b.powerplayInfo(for: 20), p16 = b.powerplayInfo(for: 16), p9 = b.powerplayInfo(for: 9), p8 = b.powerplayInfo(for: 8)
        r.equal("BBL powerplay table (28.7.4): 20 ov = 4+2, 16 ov = 4+1, 9 ov = 2+1, 8 ov = 2+0",
                [p20.powerplayOvers, p20.surgeOvers, p16.powerplayOvers, p16.surgeOvers, p9.powerplayOvers, p9.surgeOvers, p8.powerplayOvers, p8.surgeOvers],
                [4, 2, 4, 1, 2, 1, 2, 0])
        r.equal("BBL surge windows: 20 ov = after 10 / overs 11-19; 16 ov = after 8 / overs 9-16",
                [p20.surgeAvailableAfter ?? -1, p20.surgeWindowStart ?? -1, p20.surgeWindowEnd ?? -1,
                 p16.surgeAvailableAfter ?? -1, p16.surgeWindowStart ?? -1, p16.surgeWindowEnd ?? -1],
                [10, 11, 19, 8, 9, 16])
        // Table 1: 30 min of rain, 14:00 start. Interval 15 -> 10 gives E = 5, G = 135, H = 33.75 -> 17 overs.
        let ms = MatchState(); ms.startMatch(.bbl)
        ms.gameStartTime = day(14); ms.LS_actualStart = day(14)
        ms.B_timeInProgress = 20; ms.C_playingTimeLost = 30
        ms.J_startOrRecommence = TU.addMin(day(14), 50)
        ms.updateIntervalIfNeeded()
        r.near("BBL Table 1: 30 min lost (interval credit 5) -> H = 33.75", ms.firstInningsLoss.totalOvers, 33.75)
        r.equal("... 17 overs per side", ms.firstInningsPlan.oversPerTeam, 17)
        let s = SecondInningsWorksheet.calculate(
            rules: b, inningsStart: day(15, 30), restart: TU.addMin(day(16), 17), initialOvers: 20,
            delays: [InningsDelay(start: day(16), end: TU.addMin(day(16), 17), allowanceMinutes: 0)],
            completedOvers: 10, completedBalls: 0, extraTimeAlreadyUsed: 0, earlyStartCredit: 0)
        r.equal("BBL Table 4: 17 min lost -> 16 overs", s.revisedOvers, 16)
        let s2 = SecondInningsWorksheet.calculate(
            rules: b, inningsStart: day(15, 30), restart: TU.addMin(day(16), 17), initialOvers: 20,
            delays: [InningsDelay(start: day(16), end: TU.addMin(day(16), 17), allowanceMinutes: 0)],
            completedOvers: 10, completedBalls: 0, extraTimeAlreadyUsed: 0, earlyStartCredit: 5)
        r.equal("BBL Table 4: 17 min lost with 5 min early-start credit -> 17 overs", s2.revisedOvers, 17)
    }

    // MARK: 6. ICC Men's ODI / T20I (PCs effective October 2026)
    // Expected numbers: verification/icc_expectations.py, written from Appendix E Tables 1 and 4 and the
    // clause text (not from the Swift code). NOT covered: DLS targets, ICC over-rate penalties,
    // Match Referee interval reductions.
    private static func icc(_ r: Recorder) {
        let odi = CompRules.odi, t20 = CompRules.t20i
        r.equal("ODI: 420 net, 30 interval, 50 ov, min 20 ov (cl 12.7.1, 11.2.1, 13.6.1, 16.1.2)",
                [odi.defaultNetPlayingTimeMinutes, odi.defaultIntervalMinutes, odi.maxOversPerTeam, odi.minValidOvers],
                [420, 30, 50, 20])
        r.equal("T20I: 170 net, 15 interval, 20 ov, min 5 ov (cl 12.7.1, 11.2.1, 13.6.1, 16.1.2)",
                [t20.defaultNetPlayingTimeMinutes, t20.defaultIntervalMinutes, t20.maxOversPerTeam, t20.minValidOvers],
                [170, 15, 20, 5])
        r.near("ICC rates 4.2 (ODI) and 4.25 (T20I) min/over (Appendix E)", odi.minutesPerOver + t20.minutesPerOver, 8.45, tol: 0.0001)
        r.equal("ICC extra time is 0 until agreed", [odi.extraTimeMinutes, t20.extraTimeMinutes], [0, 0])

        // Powerplay tables (ODI 28.7.2.3 identical to ODC rows 20-49; T20I 28.7.6 overs.balls)
        let p20 = odi.odcPowerplays(for: 20), p25 = odi.odcPowerplays(for: 25), p49 = odi.odcPowerplays(for: 49)
        r.equal("ODI powerplay 20 ov = 4+12+4, 25 ov = 5+15+5, 49 ov = 10+29+10",
                [p20.0, p20.1, p20.2, p25.0, p25.1, p25.2, p49.0, p49.1, p49.2],
                [4, 12, 4, 5, 15, 5, 10, 29, 10])
        let q5 = t20.t20iPowerplay(for: 5), q16 = t20.t20iPowerplay(for: 16), q19 = t20.t20iPowerplay(for: 19), q20 = t20.t20iPowerplay(for: 20)
        r.equal("T20I powerplay 5 ov = 1.3, 16 ov = 4.5, 19 ov = 5.4, 20 ov = 6.0",
                [q5.overs, q5.balls, q16.overs, q16.balls, q19.overs, q19.balls, q20.overs, q20.balls],
                [1, 3, 4, 5, 5, 4, 6, 0])

        // Bowler limits (13.9): T20I innings of 5-9 overs -> 2; otherwise one-fifth rounded up.
        r.equal("T20I bowler limit: 5 ov -> 2, 9 ov -> 2, 10 ov -> 2, 13 ov -> 3, 20 ov -> 4",
                [5, 9, 10, 13, 20].map { t20.maxOversPerBowler(teamOvers: $0) }, [2, 2, 2, 3, 4])
        r.equal("ODI bowler limit: 50 ov -> 10, 21 ov -> 5",
                [50, 21].map { odi.maxOversPerBowler(teamOvers: $0) }, [10, 5])

        // Interval is NOT reduced automatically (Match Referee discretion only).
        r.equal("ICC interval is never auto-reduced (ODI 30, T20I 15)",
                [odi.adjustedInterval(timeLost: 200), t20.adjustedInterval(timeLost: 100)], [30, 15])

        // Table 1: first innings, 14:00 start, no late start. ODI 45 min lost -> H 89.29, 45 ov/side.
        func first(_ comp: Competition, lost: Int, extra: Int) -> MatchState {
            let ms = MatchState(); ms.startMatch(comp)
            ms.agreedExtraTime = extra
            ms.gameStartTime = day(14); ms.LS_actualStart = day(14)
            ms.B_timeInProgress = 20; ms.C_playingTimeLost = lost
            ms.J_startOrRecommence = TU.addMin(day(14), 20 + lost)
            ms.updateIntervalIfNeeded()
            return ms
        }
        let o1 = first(.odi, lost: 45, extra: 0), o2 = first(.odi, lost: 45, extra: 60)
        r.near("ODI Table 1: 45 min lost, no extra time -> H = 89.29", o1.firstInningsLoss.totalOvers, 89.29)
        r.equal("... 45 overs per side", o1.firstInningsPlan.oversPerTeam, 45)
        r.equal("ODI Table 1: same loss with 60 min agreed extra time -> 50 overs per side (nothing lost)",
                [o2.firstInningsLoss.extraApplied, o2.firstInningsPlan.oversPerTeam], [45, 50])
        let t1 = first(.t20i, lost: 30, extra: 0), t2 = first(.t20i, lost: 30, extra: 30)
        r.near("T20I Table 1: 30 min lost -> H = 32.94", t1.firstInningsLoss.totalOvers, 32.94)
        r.equal("... 17 overs per side", t1.firstInningsPlan.oversPerTeam, 17)
        r.equal("T20I Table 1: 30 min agreed extra time covers the loss -> 20 overs per side",
                t2.firstInningsPlan.oversPerTeam, 20)

        // Table 4: second innings. ODI 50 ov, 30 min stoppage.
        func second(_ rules: CompRules, initial: Int, mins: Int, used: Int, credit: Int) -> Int {
            let s = day(16), e = TU.addMin(day(16), mins)
            return SecondInningsWorksheet.calculate(
                rules: rules, inningsStart: day(15, 30), restart: e, initialOvers: initial,
                delays: [InningsDelay(start: s, end: e, allowanceMinutes: 0)],
                completedOvers: 10, completedBalls: 0,
                extraTimeAlreadyUsed: used, earlyStartCredit: credit).revisedOvers
        }
        r.equal("ODI Table 4: 30 min lost -> 43 overs", second(odi, initial: 50, mins: 30, used: 0, credit: 0), 43)
        r.equal("ODI Table 4: 30 min lost with 15 min early-start credit (13.7.2.2.2) -> 47",
                second(odi, initial: 50, mins: 30, used: 0, credit: 15), 47)
        r.equal("ODI Table 4: 30 min lost, 10 min of agreed extra time left (30 agreed, 20 used) -> 46",
                second(odi.withExtraTime(30), initial: 50, mins: 30, used: 20, credit: 0), 46)
        r.equal("T20I Table 4: 17 min lost -> 16 overs", second(t20, initial: 20, mins: 17, used: 0, credit: 0), 16)
        r.equal("T20I Table 4: 20 min lost -> 16 overs", second(t20, initial: 20, mins: 20, used: 0, credit: 0), 16)

        // Agreed extra time survives relaunch and a saved match; a new match starts at 0.
        let a = MatchState(); a.startMatch(.odi); a.agreedExtraTime = 60
        r.equal("Agreed extra time reaches the rules (60)", a.rules.extraTimeMinutes, 60)
        let a2 = MatchState()
        r.equal("Relaunch keeps ODI and 60 min agreed extra time",
                [a2.competition == .odi ? 1 : 0, a2.agreedExtraTime, a2.rules.extraTimeMinutes], [1, 60, 60])
        a.teamA = "Australia"; a.teamB = "India"; a.saveCurrentMatch()
        a.agreedExtraTime = 0
        if let saved = a.snapshots.first {
            r.check("Restore reports success", a.restoreSnapshot(saved))
            r.equal("Restoring the saved match brings back 60 min agreed extra time", a.agreedExtraTime, 60)
        } else { r.check("ICC saved match exists", false) }
        a.startMatch(.odi)
        r.equal("New ICC match resets agreed extra time to 0", a.rules.extraTimeMinutes, 0)
        let w = MatchState(); w.startMatch(.wncl)
        r.equal("Non-ICC match unaffected: WNCL keeps its 60 min", w.rules.extraTimeMinutes, 60)
    }

    // MARK: 5. Persistence, saved matches, new-match reset (defects 5 and 6)
    private static func persistence(_ r: Recorder, suite: String, temp: UserDefaults) {
        // 5a. Relaunch keeps a recorded late first ball.
        let a = MatchState(); a.startMatch(.odc)
        a.gameStartTime = day(10); a.LS_actualStart = day(10, 45)
        let a2 = MatchState()                                   // reads the store like a cold start
        r.equal("Relaunch keeps late first ball (10:45)", a2.LS_actualStart, day(10, 45))

        // 5b. Relaunch keeps lost time in a T20 match with a logged delay.
        let b = MatchState(); b.startMatch(.wbbl)
        b.gameStartTime = day(19); b.LS_actualStart = day(19, 10)
        b.firstInningsDelays = [InningsDelay(start: day(19, 40), end: day(20, 5), allowanceMinutes: 0)]
        b.C_playingTimeLost = 25; b.J_startOrRecommence = day(20, 5)
        let b2 = MatchState()
        r.equal("Relaunch keeps WBBL time lost (25) and restart (20:05)",
                [b2.C_playingTimeLost, Int(b2.J_startOrRecommence.timeIntervalSince(day(20, 5)))], [25, 0])

        // 5c. New match clears the Final flag and the previous match's scheduled start.
        let c = MatchState(); c.startMatch(.odc)
        c.isFinal = true; c.gameStartTime = day(10, 0, plus: -30)
        c.startMatch(.odc)
        r.check("New match clears 'Final'", c.isFinal == false)
        r.check("New match resets stale scheduled start (within a minute of now)",
                abs(c.gameStartTime.timeIntervalSinceNow) < 60, "start = \(c.gameStartTime)")

        // 5d. Saved matches: kept, reloaded, and restored across midnight.
        let s = MatchState(); s.startMatch(.bbl)
        s.snapshots = []                                        // isolate from matches saved by earlier test groups
        s.gameStartTime = day(19); s.LS_actualStart = day(19)
        s.J_startOrRecommence = day(0, 20, plus: 1)             // 00:20 the next day
        s.saveCurrentMatch()
        for i in 1...4 { s.currentSavedMatchID = nil; s.teamA = "Team \(i)"; s.saveCurrentMatch() }
        r.equal("Five saved matches kept", s.snapshots.count, 5)
        let reloaded = MatchState()
        r.equal("... and still five after relaunch", reloaded.snapshots.count, 5)
        if let midnight = s.snapshots.last {                    // the first one saved (oldest)
            let ok = s.restoreSnapshot(midnight)
            r.check("Restore reports success", ok)
            r.equal("After-midnight restart (00:20) restores onto the NEXT day", s.J_startOrRecommence, day(0, 20, plus: 1))
        } else {
            r.check("Found the saved match to restore", false)
        }

        // 5e. Undecodable saved data is backed up, not silently destroyed.
        temp.set(Data("not json".utf8), forKey: "snapshots")
        _ = MatchState()
        r.check("Undecodable snapshots are backed up to 'snapshots.undecodable'",
                temp.data(forKey: "snapshots.undecodable") != nil)
    }
}

// MARK: - Results screen

struct SelfTestsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var results: [SelfTestResult] = []
    @State private var ran = false
    private var failed: Int { results.filter { !$0.passed }.count }

    var body: some View {
        NavigationView {
            List {
                Section {
                    Text(summary).font(.headline)
                        .foregroundStyle(!ran ? Color.secondary : (failed == 0 ? AppTheme.success : AppTheme.destructive))
                    Text("Runs on a temporary store; your current match and saved matches are not touched. A pass means the app's arithmetic matches the Playing Conditions worked figures used here. It is not a substitute for checking real match scenarios.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Checks") {
                    ForEach(results) { item in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: item.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(item.passed ? AppTheme.success : AppTheme.destructive)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name).font(.subheadline)
                                if !item.passed && !item.detail.isEmpty {
                                    Text(item.detail).font(.caption).foregroundStyle(AppTheme.destructive)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Self-tests").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Run again") { run() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .onAppear { if !ran { run() } }
        }
    }

    private var summary: String {
        if !ran { return "Not run" }
        return failed == 0 ? "All \(results.count) checks passed" : "\(failed) of \(results.count) checks FAILED"
    }
    private func run() { results = BoundaryLineSelfTests.run(); ran = true }
}
