import Foundation

#if DEBUG
/// Debug-only: sets up a match from launch arguments so CI can screenshot each screen.
/// Usage: -blDemo <ODC|WNCL|BBL|WBBL|ODI|T20I> <before|first|calc|second|summary>
/// Not compiled into Release (TestFlight / App Store) builds.
enum DemoSetup {
    struct Plan { let comp: Competition; let start: (Int, Int); let late: Int; let stop1: (Int, Int); let stop1Len: Int; let stop2After: Int; let stop2Len: Int }

    static let plans: [String: Plan] = [
        "WBBL": Plan(comp: .wbbl, start: (19, 40), late: 10, stop1: (20, 30), stop1Len: 15, stop2After: 30, stop2Len: 17),
        "BBL":  Plan(comp: .bbl,  start: (19, 15), late: 0,  stop1: (19, 45), stop1Len: 21, stop2After: 40, stop2Len: 20),
        "ODC":  Plan(comp: .odc,  start: (10, 0),  late: 0,  stop1: (11, 0),  stop1Len: 70, stop2After: 60, stop2Len: 30),
        "WNCL": Plan(comp: .wncl, start: (10, 0),  late: 0,  stop1: (11, 0),  stop1Len: 30, stop2After: 60, stop2Len: 50),
        "ODI":  Plan(comp: .odi,  start: (14, 0),  late: 0,  stop1: (14, 20), stop1Len: 45, stop2After: 60, stop2Len: 30),
        "T20I": Plan(comp: .t20i, start: (19, 0),  late: 0,  stop1: (19, 20), stop1Len: 30, stop2After: 30, stop2Len: 17),
    ]

    static func apply(to ms: MatchState) {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-blDemo"), args.count > i + 2,
              let p = plans[args[i + 1]] else { return }
        let stage = args[i + 2]
        let cal = Calendar.current
        func at(_ h: Int, _ m: Int) -> Date { cal.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date() }

        ms.startMatch(p.comp)
        ms.teamA = "Home XI"; ms.teamB = "Away XI"
        ms.gameStartTime = at(p.start.0, p.start.1)
        ms.LS_actualStart = TU.addMin(ms.gameStartTime, p.late)
        ms.updateIntervalIfNeeded()
        if stage == "before" { ms.matchPhase = .before; return }

        ms.recordFirstBall(at: TU.addMin(ms.gameStartTime, p.late))
        let s1 = at(p.stop1.0, p.stop1.1)
        if stage == "calc" {
            StoppageControl.demo = (s1, TU.addMin(s1, p.stop1Len))
            return
        }
        _ = ms.recordStoppage(from: s1, to: TU.addMin(s1, p.stop1Len))
        if stage == "first" { return }

        let b2 = ms.firstInningsPlan.secondStart
        ms.beginSecondInnings(at: b2, overs: ms.firstInningsPlan.oversPerTeam)
        let s2 = TU.addMin(b2, p.stop2After)
        _ = ms.recordStoppage(from: s2, to: TU.addMin(s2, p.stop2Len))
        ms.matchPhase = stage == "summary" ? .summary : .second
    }
}
#endif
