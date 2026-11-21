import SwiftUI
import Combine
import QuickLook

// ==============================================================================
//  BoundaryLine Rain & Overs v7.4 — match summary and persistence review
//  ODC . WNCL . BBL . WBBL . ICC Men's ODI . ICC Men's T20I (ICC tiles added, UNVERIFIED, not compiled)
//
//  AUDIT PATCH 2026-10-30 (UNVERIFIED until built and self-tested on device -- see AUDIT_STATUS.md):
//    late start + rain accounting (one shared firstInningsLoss), restart anchor from first ball,
//    relaunch/persistence ordering guard, undecodable-data backup, cross-midnight restore,
//    new-match reset (isFinal, scheduled start), second-innings extra-time pool + early-start credit,
//    latest-start maths extracted (WBBL 18-minute convention: CA WBBL Almanac 2026/27 p.47-48),
//    on-device self-tests (BoundaryLineSelfTests.swift). BBL moved to the BBL|16 (1 Dec 2026) conditions: over-rate finish 84 / overs x 4 + 3.
//
//  What's new in v5.3 (field-use fixes):
//    - Replaced the live "Start Delay Now" / "Resume Play" timer with
//      retrospective logging: two TimeFields ("Delay started", "Delay
//      ended", both defaulting to now but freely editable) plus a
//      "Log Delay" button. The umpire's iPad/iPhone isn't out on the
//      field with them -- by the time they open the app the delay has
//      usually already started or finished, so a clock that only counts
//      from the moment you press it isn't practical. This can also be
//      logged multiple times per innings for multiple stoppages.
//    - ODC's Powerplay tab now renders the same Ov/P1/P2/P3 reference
//      table as WNCL and the T20 comps (full scrollable list, selected
//      row highlighted), instead of just the compact PowerplayDisplay
//      badges it showed before -- it was the odd one out.
//    - Playing Conditions PDF now opens from a bundled app resource via
//      QuickLook (PDFOpenButton/PDFPreviewSheet), not a Link to the
//      requester's personal Google Drive -- anyone using this app can
//      open it, not just people with Drive access to that file. Add
//      "One Day Cup Playing Conditions 2026-27.pdf" and "WNCL Playing
//      Conditions 2026-27.pdf" to this project's target resources
//      (CompRules.pdfFileName names what to add); tapping shows an
//      explanatory alert instead of a dead link until then.
//
//  What's new in v5.2 (UX pass):
//    - Reset now requires confirmation (confirmationDialog) -- previously
//      one mis-tap on the header's reset icon silently wiped the match.
//    - Header decluttered from 8 icon-only buttons to 5: Match info,
//      Share, Save, a "More" overflow menu (Scenarios / History /
//      Appearance / About, with a dot badge when any are non-empty), and
//      Reset. Fewer, larger, less error-prone targets.
//    - Termination check recommendation (CONTINUE/TERMINATE) is now a
//      large, high-contrast banner with icon -- it's the highest-stakes
//      call in the app and previously looked like every other HeroCard.
//    - Timeline bar labels bumped from 9pt to 12pt bold with a text
//      shadow, and the bar itself from 28pt to 36pt tall, for legibility
//      in direct sunlight.
//    - Two-column (iPad-style) layout now kicks in at 700pt instead of
//      800pt, so a phone held in landscape gets it too.
//
//  What's new in v5.1:
//    - ODC and WNCL updated to the 2026-27 Playing Conditions
//      (1 September 2026 edition). Every numeric constant for these two
//      competitions was cross-checked line-by-line against the official
//      PDFs and was already correct for the new season; only the
//      almanacVersion label was stale.
//    - Fixed a real rules gap found while re-checking the 2026-27 text:
//      the over-rate cut-off (cl. 12.8.2.1) no longer applies once an
//      ODC/WNCL innings is reduced below 25 overs. Previously this
//      exemption only existed for T20 (BBL/WBBL) via a hardcoded
//      "< 10 overs" check; both are now handled generically through the
//      new `cutoffMinOvers` field on CompRules.
//    - BBL/WBBL numbers are UNCHANGED and NOT re-verified this pass --
//      no 2026-27 BBL Playing Conditions document was
//      available to check them against. Update `almanacVersion` and the
//      relevant constants for those two once that document is in hand.
//
//  What's new in v5.0:
//    - State persists across app restarts (UserDefaults)
//    - Match history -- last 20 matches saved and browsable
//    - Editable calculation clock in header, used by scenario time fields
//    - "Now" button on every time field
//    - Input validation with inline warnings
//    - Haptic feedback on key state changes
//    - Termination flip triggers strong haptic
//    - Monospaced fixed-size hero numerals
//    - Highlighted row in powerplay table
//    - Structured share summary with clause references
//    - Rules version indicator in header
//    - Better keyboard handling via FocusState
//    - Over-rate penalty threshold display
//
//  Rules verified against official CA Playing Conditions:
//    BBL|16 2026/27 (1 Dec 2026) . WBBL12 2026/27 (1 Oct 2026)
//    ODC Playing Conditions 2026-27 (1 Sep 2026) . WNCL Playing Conditions 2026-27 (1 Sep 2026)
//
//  Developed by BoundaryLine Apps
//  (c) 2025-2026 BoundaryLine Apps. All rights reserved.
// ==============================================================================

// MARK: - WBBL12 2026-27 playing conditions (cl. 12.7, 12.8 and Appendix J)
// Separate the NEW in-game penalty from the match-time rain calculation.
// Times are seconds to avoid rounding 78:45 or 3:45 per over.
enum WBBL12Rules {
    // WBBL12 rain-delay and interval parameters only; over-rate penalties
    // belong to the separate third-umpire app.
    static let secondsPerOver = 225
    static let fullInningsSeconds = 75 * 60
    static let standardIntervalSeconds = 15 * 60
    static let reducedIntervalSeconds = 10 * 60
    static let intervalReductionThresholdSeconds = 16 * 60
    
    static func intervalSeconds(firstInningsPlayingTimeLostSeconds: Int) -> Int {
        firstInningsPlayingTimeLostSeconds >= intervalReductionThresholdSeconds
        ? reducedIntervalSeconds : standardIntervalSeconds
    }
}

// MARK: - Haptics

struct Haptic {
    static func light()    { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func medium()   { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func heavy()    { UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func success()  { UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning()  { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
    static func error()    { UINotificationFeedbackGenerator().notificationOccurred(.error) }
}

// MARK: - Competition

enum Competition: String, CaseIterable, Identifiable, Codable {
    case odc  = "ODC"
    case wncl = "WNCL"
    case bbl  = "BBL"
    case wbbl = "WBBL"
    // ICC international tiles (ICC Men's Playing Conditions, effective October 2026)
    case odi  = "ODI"
    case t20i = "T20I"
    var id: String { rawValue }
    
    var fullName: String {
        switch self {
        case .odc:  return "One Day Cup"
        case .wncl: return "Women's National Cricket League"
        case .bbl:  return "Big Bash League"
        case .wbbl: return "Women's Big Bash League"
        case .odi:  return "ICC Men's ODI"
        case .t20i: return "ICC Men's T20I"
        }
    }
    
    var isT20: Bool           { self == .bbl || self == .wbbl || self == .t20i }
    var isLimitedOvers: Bool  { self == .odc || self == .wncl || self == .odi }
    var isInternational: Bool { self == .odi || self == .t20i }
}

// MARK: - Powerplay Info

struct PowerplayInfo {
    let totalOvers: Int
    let powerplayOvers: Int
    let surgeOvers: Int
    let surgeAvailableAfter: Int?
    let surgeWindowStart: Int?
    let surgeWindowEnd: Int?
    var hasSurge: Bool { surgeOvers > 0 }
}

// MARK: - Validation Warning

struct ValidationWarning: Identifiable {
    let id = UUID()
    let message: String
    let severity: Severity
    enum Severity { case info, caution, error }
    var color: Color {
        switch severity {
        case .info:    return AppTheme.info
        case .caution: return AppTheme.warning
        case .error:   return AppTheme.destructive
        }
    }
    var icon: String {
        switch severity {
        case .info:    return "info.circle"
        case .caution: return "exclamationmark.triangle"
        case .error:   return "xmark.circle"
        }
    }
}

// MARK: - Competition Rules

struct CompRules {
    let minutesPerOver: Double
    let defaultNetPlayingTimeMinutes: Int
    let defaultIntervalMinutes: Int
    let maxOversPerTeam: Int
    let oversLostRounding: OversRounding
    let terminationRounding: OversRounding
    let intervalReductions: [(threshold: Int, newInterval: Int)]
    let cutoffFullMinutes: Int?
    let cutoffExtraMinutes: Int?
    /// Below this many overs, the over-rate cut-off (cl. 12.8.2.1 / T20 equivalent) no longer applies.
    let cutoffMinOvers: Int?
    let lateStartMaxWindow: Int?
    let fiveOverInningsDuration: Int?
    let minValidOvers: Int
    let minValidOversFinal: Int
    let extraTimeMinutes: Int
    let almanacVersion: String
    /// Link to the official source PDF for this competition's Playing Conditions, if known.
    /// Filename (with extension) of the Playing Conditions PDF bundled into the app's target resources,
    /// e.g. add "One Day Cup Playing Conditions 2026-27.pdf" to the project and it opens in-app via
    /// QuickLook -- no network or Google Drive permissions required. nil where no PDF has been bundled yet.
    let pdfFileName: String?
    /// ICC T20I cl. 13.9.3: in an innings of 5-9 overs no bowler may bowl more than this many overs.
    var shortInningsBowlerCap: Int? = nil
    
    enum OversRounding { case ceil, floor }
    
    // Verified against the official 2026-27 One Day Cup Playing Conditions
    // (1 September 2026): cl. 11.3.2 (interval), 12.7 (extra time -- none for
    // ODC), 12.8.1-12.8.2.1 (over-rate cut-off + <25-over exemption),
    // 13.7.2 (interrupted matches), 13.8.2 (bowler limit), 16.1.2 & 16.4
    // (minimum overs / target-setting).
    static let odc = CompRules(
        minutesPerOver: 4.2, defaultNetPlayingTimeMinutes: 420,
        defaultIntervalMinutes: 30, maxOversPerTeam: 50,
        oversLostRounding: .floor, terminationRounding: .ceil,
        intervalReductions: [(60, 20)],
        cutoffFullMinutes: 206, cutoffExtraMinutes: -4, cutoffMinOvers: 25,
        lateStartMaxWindow: nil, fiveOverInningsDuration: nil,
        minValidOvers: 15, minValidOversFinal: 20,
        extraTimeMinutes: 0,
        almanacVersion: "2026/27 (eff. 1 Sep 2026)",
        pdfFileName: "One Day Cup Playing Conditions 2026-27.pdf"
    )
    
    // Verified against the official 2026-27 WNCL Playing Conditions
    // (1 September 2026): cl. 11.3.2.1.1-2 (interval), 12.7.1 (60 min extra
    // time), 12.8.1-12.8.2.1 (over-rate cut-off + <25-over exemption),
    // 13.7.2 (interrupted matches), 13.8.2 (bowler limit), 16.1.2 & 16.4
    // (minimum overs / target-setting).
    static let wncl = CompRules(
        minutesPerOver: 3.8, defaultNetPlayingTimeMinutes: 380,
        defaultIntervalMinutes: 40, maxOversPerTeam: 50,
        oversLostRounding: .floor, terminationRounding: .ceil,
        intervalReductions: [(60, 20), (1, 30)],
        cutoffFullMinutes: 187, cutoffExtraMinutes: -3, cutoffMinOvers: 25,
        lateStartMaxWindow: nil, fiveOverInningsDuration: nil,
        minValidOvers: 15, minValidOversFinal: 20,
        extraTimeMinutes: 60,
        almanacVersion: "2026/27 (eff. 1 Sep 2026)",
        pdfFileName: "WNCL Playing Conditions 2026-27.pdf"
    )
    
    // NOT re-verified this pass -- no 2026-27 (or newer) BBL Playing
    // Conditions document was available. Numbers carried over unchanged
    // from the prior almanac; confirm against the current document before
    // relying on this for the coming season.
    // BBL|16 (2026/27, 1 December 2026): cl. 11.2.1 (15-min interval), 11.3.3 (10 min after 21 min lost),
    // 12.5.1 (2 x 80 min), 12.6 (no extra time), 12.7.1 (in-game over-rate finish time 84 min; reduced
    // innings = overs x 4 + 3 min, 12.8.2.6 one-over allowance NOT included in the figure shown),
    // 13.7.2 (4 min/over), 13.8 (bowlers), 28.7.4 (powerplay/surge table), Appendix J.1.
    static let bbl = CompRules(
        minutesPerOver: 4.0, defaultNetPlayingTimeMinutes: 160,
        defaultIntervalMinutes: 15, maxOversPerTeam: 20,
        oversLostRounding: .floor, terminationRounding: .floor,
        intervalReductions: [(21, 10)],
        cutoffFullMinutes: 84, cutoffExtraMinutes: 3, cutoffMinOvers: 10,
        lateStartMaxWindow: 175, fiveOverInningsDuration: 20,
        minValidOvers: 5, minValidOversFinal: 5,
        extraTimeMinutes: 0,
        almanacVersion: "2026/27 (BBL|16, 1 Dec 2026)",
        pdfFileName: "BBL Playing Conditions 2026-27.pdf"
    )
    
    // WBBL12: checked against 2026-27 conditions (1 October 2026):
    // clauses 11.3.3, 12.5-12.8, 13.7, 13.8, 28.7 and Appendix J.
    // 12.7 in-game penalty (78:45 full innings; reduced overs +2 min)
    // is distinct from the existing legacy cutoff display; see WBBL12Rules.
    static let wbbl = CompRules(
        minutesPerOver: 3.75, defaultNetPlayingTimeMinutes: 150,
        defaultIntervalMinutes: 15, maxOversPerTeam: 20,
        oversLostRounding: .floor, terminationRounding: .floor,
        intervalReductions: [(16, 10)],
        cutoffFullMinutes: nil, cutoffExtraMinutes: nil, cutoffMinOvers: nil,
        lateStartMaxWindow: 165, fiveOverInningsDuration: 18,
        minValidOvers: 5, minValidOversFinal: 5,
        extraTimeMinutes: 0,
        almanacVersion: "2026/27 (WBBL|12, 1 Oct 2026)",
        pdfFileName: "WBBL Playing Conditions 2026-27.pdf"
    )
    
    // ICC Men's ODI Playing Conditions (effective October 2026): cl. 11.2.1 (30-min interval),
    // 12.7.1 (2 x 3.5 h = 420 min net), 13.7.2 (interrupted matches, 14.28 ov/h = 4.2 min/ov),
    // 13.7.3 (extra time up to 90 min only where participating countries agree), 13.9 (bowler
    // limits), 16.1.2/16.4 (min 20 overs, DLS), 28.7.2 (powerplays), Appendix E Tables 1-4.
    // Not modelled: ICC over-rate penalty offsets (cl. 13.8), DLS targets, reduced interval
    // (Match Referee discretion, not less than 10 min, cl. 11.4.1 note).
    static let odi = CompRules(
        minutesPerOver: 4.2, defaultNetPlayingTimeMinutes: 420,
        defaultIntervalMinutes: 30, maxOversPerTeam: 50,
        oversLostRounding: .floor, terminationRounding: .ceil,
        intervalReductions: [],
        cutoffFullMinutes: nil, cutoffExtraMinutes: nil, cutoffMinOvers: nil,
        lateStartMaxWindow: nil, fiveOverInningsDuration: nil,
        minValidOvers: 20, minValidOversFinal: 20,
        extraTimeMinutes: 0,
        almanacVersion: "ICC Men's ODI PC (eff. Oct 2026)",
        pdfFileName: "ICC Men's ODI Playing Conditions 2026.pdf"
    )
    
    // ICC Men's T20I Playing Conditions (effective October 2026): cl. 11.2.1 (15-min interval),
    // 11.4.2 (reduction to not less than 10 min is Match Referee discretion), 12.7.1 (2 x 85 min = 170
    // min net), 13.7.2 (14.11 ov/h; Appendix E uses 4.25 min/ov), 13.7.3 (extra time only where
    // agreed), 13.9 (bowler limits), 16.1.2 (min 5 overs), 28.7.6 (powerplay table), Appendix E.
    static let t20i = CompRules(
        minutesPerOver: 4.25, defaultNetPlayingTimeMinutes: 170,
        defaultIntervalMinutes: 15, maxOversPerTeam: 20,
        oversLostRounding: .floor, terminationRounding: .ceil,
        intervalReductions: [],
        cutoffFullMinutes: nil, cutoffExtraMinutes: nil, cutoffMinOvers: nil,
        lateStartMaxWindow: nil, fiveOverInningsDuration: nil,
        minValidOvers: 5, minValidOversFinal: 5,
        extraTimeMinutes: 0,
        almanacVersion: "ICC Men's T20I PC (eff. Oct 2026)",
        pdfFileName: "ICC Men's T20I Playing Conditions 2026.pdf",
        shortInningsBowlerCap: 2
    )
    
    static func rules(for comp: Competition) -> CompRules {
        switch comp {
        case .odc:  return .odc
        case .wncl: return .wncl
        case .bbl:  return .bbl
        case .wbbl: return .wbbl
        case .odi:  return .odi
        case .t20i: return .t20i
        }
    }
    
    /// ICC extra time is only available where the participating countries agree (ODI cl. 13.7.3:
    /// up to 90 min), so it is a per-match setting rather than a fixed constant.
    func withExtraTime(_ minutes: Int) -> CompRules {
        CompRules(
            minutesPerOver: minutesPerOver, defaultNetPlayingTimeMinutes: defaultNetPlayingTimeMinutes,
            defaultIntervalMinutes: defaultIntervalMinutes, maxOversPerTeam: maxOversPerTeam,
            oversLostRounding: oversLostRounding, terminationRounding: terminationRounding,
            intervalReductions: intervalReductions,
            cutoffFullMinutes: cutoffFullMinutes, cutoffExtraMinutes: cutoffExtraMinutes,
            cutoffMinOvers: cutoffMinOvers,
            lateStartMaxWindow: lateStartMaxWindow, fiveOverInningsDuration: fiveOverInningsDuration,
            minValidOvers: minValidOvers, minValidOversFinal: minValidOversFinal,
            extraTimeMinutes: minutes,
            almanacVersion: almanacVersion, pdfFileName: pdfFileName,
            shortInningsBowlerCap: shortInningsBowlerCap)
    }
    
    func roundOversLost(_ value: Double) -> Int {
        oversLostRounding == .floor ? Int(floor(value)) : Int(ceil(value))
    }
    func roundTermination(_ value: Double) -> Int {
        terminationRounding == .floor ? Int(floor(value)) : Int(ceil(value))
    }
    func maxOversPerBowler(teamOvers: Int) -> Int {
        if let cap = shortInningsBowlerCap, teamOvers < 10 { return cap }
        return Int(ceil(Double(teamOvers) / 5.0))
    }
    func adjustedInterval(timeLost: Int) -> Int {
        // WNCL clause 12.7.1: exhaust the 60-minute extra-time allowance first.
        // NOTE: callers must pass cumulative gross loss for the match.
        let effectiveLoss = extraTimeMinutes > 0 ? max(0, timeLost - extraTimeMinutes) : timeLost
        let sorted = intervalReductions.sorted { $0.threshold > $1.threshold }
        for (threshold, newInterval) in sorted {
            if effectiveLoss >= threshold { return newInterval }
        }
        return defaultIntervalMinutes
    }
    func isValidMatch(overs: Int, isFinal: Bool = false) -> Bool {
        overs >= (isFinal ? minValidOversFinal : minValidOvers)
    }
    func cutoffMinutes(for overs: Int) -> Int? {
        guard let full = cutoffFullMinutes, let extra = cutoffExtraMinutes else { return nil }
        if let minOvers = cutoffMinOvers, overs < minOvers { return nil }
        if overs >= maxOversPerTeam { return full }
        // BBL|16 cl. 12.7.1: reduced innings = overs x 4 + 3. (BBL|15 used (overs - 1) x 4 + 3.)
        return Int(round(Double(overs) * minutesPerOver + Double(extra)))
    }
    func bowlingRestrictionText(for overs: Int) -> String {
        let c = min(max(overs, 1), maxOversPerTeam)
        if let cap = shortInningsBowlerCap, c < 10 { return "No bowler may bowl more than \(cap) ov (innings of 5-9 ov)" }
        let base = c / 5; let rem = c % 5
        if rem == 0 { return "5 bowlers: up to \(base) ov each" }
        return "\(rem) bowl up to \(base + 1) ov, \(5 - rem) bowl up to \(base) ov"
    }
    
    // Powerplay tables
    func powerplayInfo(for overs: Int) -> PowerplayInfo {
        let c = min(max(overs, 5), maxOversPerTeam)
        if maxOversPerTeam == 20 { return t20PowerplayInfo(for: c) }
        return PowerplayInfo(totalOvers: c, powerplayOvers: 0, surgeOvers: 0,
                             surgeAvailableAfter: nil, surgeWindowStart: nil, surgeWindowEnd: nil)
    }
    private func t20PowerplayInfo(for ov: Int) -> PowerplayInfo {
        let pp: Int; let surge: Int
        let sa: Int?; let ss: Int?; let se: Int?
        switch ov {
        case 20: pp=4;surge=2;sa=10;ss=11;se=19
        case 19: pp=4;surge=2;sa=9;ss=10;se=18
        case 18: pp=4;surge=1;sa=9;ss=10;se=18
        case 17: pp=4;surge=1;sa=8;ss=9;se=17
        case 16: pp=4;surge=1;sa=8;ss=9;se=16
        case 15: pp=3;surge=1;sa=7;ss=8;se=15
        case 14: pp=3;surge=1;sa=7;ss=8;se=14
        case 13: pp=3;surge=1;sa=6;ss=7;se=13
        case 12: pp=3;surge=1;sa=6;ss=7;se=12
        case 11: pp=2;surge=1;sa=5;ss=6;se=11
        case 10: pp=2;surge=1;sa=5;ss=6;se=10
        case  9: pp=2;surge=1;sa=5;ss=6;se=9
        default: pp=2;surge=0;sa=nil;ss=nil;se=nil
        }
        return PowerplayInfo(totalOvers: ov, powerplayOvers: pp, surgeOvers: surge,
                             surgeAvailableAfter: sa, surgeWindowStart: ss, surgeWindowEnd: se)
    }
    /// ICC T20I cl. 28.7.6: powerplay length as (overs, extra balls), e.g. 16 ov -> 4 ov 5 balls ("4.5").
    /// Full 20-over innings: 6 overs (cl. 28.7.2).
    func t20iPowerplay(for totalOvers: Int) -> (overs: Int, balls: Int) {
        if totalOvers >= 20 { return (6, 0) }
        return Self.t20iPPMap[totalOvers] ?? (0, 0)
    }
    private static let t20iPPMap: [Int: (overs: Int, balls: Int)] = [
        5:(1,3), 6:(1,5), 7:(2,1), 8:(2,2), 9:(2,4), 10:(3,0), 11:(3,2), 12:(3,4), 13:(3,5),
        14:(4,1), 15:(4,3), 16:(4,5), 17:(5,1), 18:(5,2), 19:(5,4)
    ]
    func odcPowerplays(for totalOvers: Int) -> (Int, Int, Int) {
        if totalOvers >= 50 { return (10, 30, 10) }
        if let m = Self.odcPPMap[totalOvers] { return m }
        return (0, totalOvers, 0)
    }
    private static let odcPPMap: [Int: (Int, Int, Int)] = [
        15:(3,9,3),16:(3,10,3),17:(4,10,3),18:(4,11,3),19:(4,11,4),
        20:(4,12,4),21:(4,13,4),22:(5,13,4),23:(5,14,4),24:(5,14,5),
        25:(5,15,5),26:(5,16,5),27:(6,16,5),28:(6,17,5),29:(6,17,6),
        30:(6,18,6),31:(6,19,6),32:(7,19,6),33:(7,20,6),34:(7,20,7),
        35:(7,21,7),36:(7,22,7),37:(8,22,7),38:(8,23,7),39:(8,23,8),
        40:(8,24,8),41:(8,25,8),42:(9,25,8),43:(9,26,8),44:(9,26,9),
        45:(9,27,9),46:(9,28,9),47:(10,28,9),48:(10,29,9),49:(10,29,10)
    ]
    func wnclPowerplay(for totalOvers: Int) -> (pp: Int, nonPp: Int, maxBowler: Int) {
        if totalOvers >= 50 { return (10, 40, 10) }
        if let m = Self.wnclPPMap[totalOvers] { return m }
        return (0, totalOvers, maxOversPerBowler(teamOvers: totalOvers))
    }
    private static let wnclPPMap: [Int: (Int, Int, Int)] = [
        15:(3,12,3),16:(3,13,4),17:(3,14,4),18:(3,15,4),19:(4,15,4),
        20:(4,16,4),21:(4,17,5),22:(4,18,5),23:(4,19,5),24:(4,20,5),
        25:(5,20,5),26:(5,21,6),27:(5,22,6),28:(5,23,6),29:(6,23,6),
        30:(6,24,6),31:(6,25,7),32:(7,25,7),33:(7,26,7),34:(7,27,7),
        35:(7,28,7),36:(7,29,8),37:(7,30,8),38:(7,31,8),39:(8,31,8),
        40:(8,32,8),41:(8,33,9),42:(9,33,9),43:(9,34,9),44:(9,35,9),
        45:(9,36,9),46:(9,37,10),47:(9,38,10),48:(10,38,10),49:(10,39,10)
    ]
}

// MARK: - Theme

struct AppTheme {
    static let bg          = Color(UIColor.systemBackground)
    static let panel       = Color(UIColor.secondarySystemBackground)
    static let panelAlt    = Color(UIColor.tertiarySystemBackground)
    static let line        = Color.primary.opacity(0.08)
    static let shadow      = Color.black.opacity(0.12)
    static let accent      = Color(red: 18/255, green: 112/255, blue: 75/255)
    static let gold        = Color(red: 199/255, green: 159/255, blue: 75/255)
    static let charcoal    = Color(red: 28/255, green: 38/255, blue: 34/255)
    static let hero        = Color(red: 0/255, green: 130/255, blue: 80/255)
    static let destructive = Color.red
    static let success     = Color.green
    static let warning     = Color.orange
    static let info        = Color.blue
}

struct CardModifier: ViewModifier {
    let pad: CGFloat
    func body(content: Content) -> some View {
        content
            .padding(pad)
            .background(AppTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(color: AppTheme.shadow, radius: 10, x: 0, y: 4)
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1))
    }
}
extension View {
    func card(padding p: CGFloat = 16) -> some View { modifier(CardModifier(pad: p)) }
}

// MARK: - Utilities

struct TU {
    static func minBetween(_ a: Date, _ b: Date) -> Int {
        max(0, Int((b.timeIntervalSince(a) / 60.0).rounded()))
    }
    static func signedMinBetween(_ a: Date, _ b: Date) -> Int {
        Int((b.timeIntervalSince(a) / 60.0).rounded())
    }
    static func addMin(_ d: Date, _ m: Int) -> Date {
        Calendar.current.date(byAdding: .minute, value: m, to: d) ?? d
    }
    static func ceilMin(_ v: Double) -> Int  { Int(ceil(v)) }
    static func ceilOv(_ v: Double) -> Int   { Int(ceil(v)) }
    static func fmt2(_ v: Double) -> String  { String(format: "%.2f", v) }
    static func round2(_ v: Double) -> Double {
        (v * 100).rounded(.toNearestOrAwayFromZero) / 100.0
    }
    static func shortTime(_ d: Date) -> String {
        d.formatted(date: .omitted, time: .shortened)
    }
    static func shortDateTime(_ d: Date) -> String {
        d.formatted(date: .abbreviated, time: .shortened)
    }
}

// MARK: - Equal-overs cessation safeguard (Appendix J)

struct EqualOversPlan {
    let oversPerTeam: Int
    let inningsMinutes: Int
    let firstCessation: Date
    let secondStart: Date
    let secondCessation: Date
    let extraOversPerTeam: Int
    let targetCessation: Date
    let meetsTarget: Bool
}

enum EqualOversCalculator {
    static func originalCessation(start: Date, rules: CompRules) -> Date {
        TU.addMin(start, rules.defaultNetPlayingTimeMinutes + rules.defaultIntervalMinutes)
    }

    // PROPOSED: latest-permissible-start maths in ONE pure place (was duplicated in two views and
    // untestable). Source for the WBBL five-over figure: Cricket Australia WBBL Playing Conditions
    // Almanac 2026/27, pp. 47-48 (cl. 13.7.2 guidance): 2 x 18 min + 10 min interval = 46 min, e.g.
    // a 7:40pm start with 10:25pm cessation has a latest start of 9:39pm. CA states the "add an extra
    // over" sentence of Appendix J "should never apply when setting the start time for a match".
    static func minimumInningsSeconds(competition: Competition, rules: CompRules, minOvers: Int) -> Int {
        if competition == .wbbl && minOvers == 5 { return 18 * 60 }
        return Int(ceil(Double(minOvers) * rules.minutesPerOver * 60.0))
    }
    /// Never rounds a latest start LATER than the limit permits (floors to the minute).
    static func latestFirstBall(cessation: Date, inningsSeconds: Int, intervalMinutes: Int) -> Date {
        let exact = cessation.addingTimeInterval(-Double(inningsSeconds * 2 + intervalMinutes * 60))
        return Calendar.current.dateInterval(of: .minute, for: exact)?.start ?? exact
    }

    static func plan(rules: CompRules, originalStart: Date, restart: Date,
                     playedMinutes: Int, initialOvers: Int, interval: Int,
                     rescheduledCessation: Date? = nil) -> EqualOversPlan {
        let target = rescheduledCessation ?? originalCessation(start: originalStart, rules: rules)
        let firstOvers = min(rules.maxOversPerTeam, max(0, initialOvers))
        var overs = firstOvers
        let played = max(0, playedMinutes)
        var length = 0
        var firstEnd = restart
        var secondStart = restart
        var secondEnd = restart
        while true {
            length = TU.ceilMin(Double(overs) * rules.minutesPerOver)
            firstEnd = TU.addMin(restart, max(0, length - played))
            secondStart = TU.addMin(firstEnd, max(0, interval))
            secondEnd = TU.addMin(secondStart, length)
            if secondEnd >= target || overs == rules.maxOversPerTeam { break }
            overs += 1
        }
        return EqualOversPlan(oversPerTeam: overs, inningsMinutes: length,
                              firstCessation: firstEnd, secondStart: secondStart,
                              secondCessation: secondEnd, extraOversPerTeam: overs - firstOvers,
                              targetCessation: target, meetsTarget: secondEnd >= target)
    }
}

// MARK: - Logged second-innings interruptions

struct InningsDelay: Identifiable, Codable {
    var id = UUID()
    var start: Date
    var end: Date
    var allowanceMinutes: Int
    var duration: Int { max(0, TU.minBetween(start, end)) }
    var netLost: Int { max(0, duration - allowanceMinutes) }
}

// MARK: - Match timeline (recorded events; schedule changes require confirmation)

enum MatchEventKind: String, CaseIterable, Codable {
    case firstInningsAllOut = "First innings all out"
    case firstInningsComplete = "First innings complete"
    case intervalStart = "Interval started"
    case secondInningsStart = "Second innings started"
    case rainStopped = "Play suspended"
    case playResumed = "Play resumed"
    case adjustment = "Cessation adjustment confirmed"
}

struct MatchTimelineEvent: Identifiable, Codable {
    var id = UUID()
    var kind: MatchEventKind
    var time: Date
    var note: String
    var confirmedCessation: Date?
}

// MARK: - Match Record (for history)

struct MatchRecord: Identifiable, Codable {
    var id = UUID()
    var date: Date
    var competition: String
    var teamA: String
    var teamB: String
    var venue: String
    var summary: String
    var isFinal: Bool
}

// MARK: - Snapshot

struct Snapshot: Identifiable, Codable {
    var id = UUID()
    var label: String
    var createdAt: Date
    var A_netPlayingTime: Int
    var B_timeInProgress: Int
    var C_playingTimeLost: Int
    var D_extraTimeAvail: Int
    var E_timeFromReducedInterval: Int
    var J_startMinutesFromMidnight: Int
    var M_intervalLength: Int
    var A2_maxOvers: Int
    var C2_startMinutesFromMidnight: Int
    var H_maxOversAtStart: Int
    var A3_startMinutes: Int
    var B3_interruptMinutes: Int
    var D3_restartMinutes: Int
    var F3_additionalTimeAvail: Int
    var P_restartMinutes: Int
    var Q_cutoffMinutes: Int
    var T_completeOversFaced: Int
    var LS_actualStartMinutes: Int
    var gameStartMinutes: Int
    // Full match-date anchor, optional so previously saved snapshots still decode.
    var savedMatchStartDate: Date?
    // Match identity is optional to decode older snapshots safely.
    var competitionCode: String?
    var savedTeamA: String?
    var savedTeamB: String?
    var savedVenue: String?
    var savedIsFinal: Bool?
    var savedMatchIsActive: Bool?
    var savedTimelineEvents: [MatchTimelineEvent]?
    var savedConfirmedCessation: Date?
    // Optional for backward compatibility with snapshots saved before v7.6.
    var firstInningsDelays: [InningsDelay]?
    var secondInningsDelays: [InningsDelay]?
    var secondInningsCompletedOvers: Int?
    var secondInningsCompletedBalls: Int?
    var rescheduledCessationEnabled: Bool?
    var rescheduledCessation: Date?
    // ICC ODI/T20I agreed extra time; optional so older snapshots still decode.
    var savedAgreedExtraTime: Int?
}

// MARK: - Persistence

struct Store {
    // PROPOSED (iPad/Swift Playgrounds testing): swappable so the on-device self-tests can run
    // against a throwaway UserDefaults suite and can never touch a live match or saved matches.
    // Production always uses .standard.
    nonisolated(unsafe) static var defaults: UserDefaults = .standard

    static func save<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        }
    }
    
    static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            // PROPOSED FIX (saved-matches retention): an undecodable payload used to
            // become `nil`, then `?? []`, then be overwritten by the next didSet save.
            // Keep the raw bytes so a schema change can never silently destroy saved matches.
            defaults.set(data, forKey: key + ".undecodable")
            return nil
        }
    }
    
    static func saveDate(_ date: Date, key: String) {
        defaults.set(date.timeIntervalSince1970, forKey: key)
    }
    
    static func loadDate(key: String) -> Date? {
        let v = defaults.double(forKey: key)
        return v == 0 ? nil : Date(timeIntervalSince1970: v)
    }
    
    static func saveInt(_ v: Int, key: String) { defaults.set(v, forKey: key) }
    static func loadInt(key: String, default d: Int) -> Int {
        defaults.object(forKey: key) == nil ? d : defaults.integer(forKey: key)
    }
    static func saveString(_ v: String, key: String) { defaults.set(v, forKey: key) }
    static func loadString(key: String, default d: String = "") -> String {
        defaults.string(forKey: key) ?? d
    }
    static func saveBool(_ v: Bool, key: String) { defaults.set(v, forKey: key) }
    static func loadBool(key: String) -> Bool { defaults.bool(forKey: key) }
}

// MARK: - Match State

final class MatchState: ObservableObject {
    @Published var matchIsActive: Bool = false {
        didSet { Store.saveBool(matchIsActive, key: "blMatchActive") }
    }
    @Published var firstInningsDelays: [InningsDelay] = [] {
        didSet { Store.save(firstInningsDelays, key: "blFirstInningsDelays") }
    }
    @Published var timelineEvents: [MatchTimelineEvent] = [] {
        didSet { Store.save(timelineEvents, key: "blTimelineEvents") }
    }
    @Published var confirmedCessation: Date? = nil {
        didSet {
            if let confirmedCessation { Store.saveDate(confirmedCessation, key: "blConfirmedCessation") }
            else { Store.defaults.removeObject(forKey: "blConfirmedCessation") }
        }
    }
    @Published var currentSavedMatchID: UUID? = nil
    
    func startMatch(_ comp: Competition) {
        // Always initialise a fresh match, including when the competition is unchanged.
        // Persisted saved matches are not affected by resetAll().
        matchIsActive = false
        competition = comp
        agreedExtraTime = 0
        refreshRules()
        // PROPOSED FIX (new-match reset): resetAll() never cleared these, so a Final
        // flag and the previous match's scheduled start/date leaked into the next match.
        isFinal = false
        gameStartTime = Date()
        resetAll()
        teamA = ""
        teamB = ""
        venue = ""
        matchIsActive = true
    }
    func addTimelineEvent(kind: MatchEventKind, time: Date, note: String,
                          cessation: Date? = nil) {
        timelineEvents.append(MatchTimelineEvent(kind: kind, time: time,
                                                 note: note, confirmedCessation: cessation))
        timelineEvents.sort { $0.time < $1.time }
        if let cessation { confirmedCessation = cessation }
    }
    func deleteTimelineEvent(_ id: UUID) {
        timelineEvents.removeAll { $0.id == id }
        confirmedCessation = timelineEvents
            .filter { $0.kind == .adjustment && $0.confirmedCessation != nil }
            .sorted { $0.time < $1.time }.last?.confirmedCessation
    }
    func leaveMatch() { matchIsActive = false }
    
    @Published var competition: Competition = .odc {
        didSet { Store.saveString(competition.rawValue, key: "competition") }
    }
    @Published var rules: CompRules = .odc
    /// ICC ODI/T20I only: extra time (minutes) the participating countries agreed for this match.
    @Published var agreedExtraTime: Int = 0 {
        didSet {
            Store.saveInt(agreedExtraTime, key: "agreedExtraTime")
            refreshRules()
        }
    }
    func refreshRules() {
        let base = CompRules.rules(for: competition)
        rules = competition.isInternational ? base.withExtraTime(max(0, agreedExtraTime)) : base
    }
    @Published var themePreference: ThemePreference = .system {
        didSet { Store.saveString(themePreference.rawValue, key: "theme") }
    }
    @Published var isFinal: Bool = false {
        didSet { Store.saveBool(isFinal, key: "isFinal") }
    }
    @Published var teamA: String = "" { didSet { Store.saveString(teamA, key: "teamA") } }
    @Published var teamB: String = "" { didSet { Store.saveString(teamB, key: "teamB") } }
    @Published var venue: String = "" { didSet { Store.saveString(venue, key: "venue") } }
    
    @Published var rescheduledCessationEnabled = false {
        didSet { Store.saveBool(rescheduledCessationEnabled, key: "reschedEnabled") }
    }
    @Published var rescheduledCessation: Date = Date() {
        didSet { Store.saveDate(rescheduledCessation, key: "reschedCessation") }
    }
    // Enter legal overs completed at the latest interruption; never reduce the
    // revised allocation below overs already completed.
    @Published var secondInningsCompletedOvers: Int = 0 {
        didSet { Store.saveInt(secondInningsCompletedOvers, key: "secondInningsCompletedOvers") }
    }
    @Published var secondInningsCompletedBalls: Int = 0 {
        didSet { Store.saveInt(secondInningsCompletedBalls, key: "secondInningsCompletedBalls") }
    }
    @Published var secondInningsDelays: [InningsDelay] = [] {
        didSet { Store.save(secondInningsDelays, key: "secondInningsDelays") }
    }
    
    @Published var snapshots: [Snapshot] = [] {
        didSet { Store.save(snapshots, key: "snapshots") }
    }
    @Published var matchHistory: [MatchRecord] = [] {
        didSet { Store.save(matchHistory, key: "matchHistory") }
    }
    
    enum ThemePreference: String, CaseIterable {
        case system = "Auto"
        case light  = "Light"
        case dark   = "Dark"
        var colorScheme: ColorScheme? {
            switch self {
            case .system: return nil
            case .light:  return .light
            case .dark:   return .dark
            }
        }
    }
    
    // The user-selected scenario clock drives all "Use clock" inputs and
    // timeline markers. It stays fixed until manually edited or reset to Now.
    @Published var calculationClockTime: Date = Date() {
        didSet { Store.saveDate(calculationClockTime, key: "calculationClockTime") }
    }
    
    // PROPOSED FIX (persistence): true while loadFromDisk()/restoreSnapshot() assign
    // properties, so gameStartTime's observer cannot recompute and re-persist
    // LS_actualStart, J, C2, C_playingTimeLost or the interval from half-loaded defaults.
    private var isRestoringState = false

    @Published var gameStartTime: Date = Date() {
        didSet {
            Store.saveDate(gameStartTime, key: "gameStartTime")
            if isRestoringState { return }
            // A new scheduled start must also move the first-innings anchor
            // when no play or interruption has been recorded. Otherwise a
            // previously saved restart (e.g. 09:30) silently overrides 18:00.
            if firstInningsDelays.isEmpty && C_playingTimeLost == 0 {
                J_startOrRecommence = TU.addMin(gameStartTime, B_timeInProgress)
                LS_actualStart = gameStartTime
                C2_startTime = TU.addMin(gameStartTime,
                                         rules.defaultNetPlayingTimeMinutes / 2 + rules.defaultIntervalMinutes)
            } else if !competition.isT20 {
                J_startOrRecommence = TU.addMin(gameStartTime,
                                                B_timeInProgress + C_playingTimeLost)
            } else {
                // Preserve an explicitly entered restart in a live match.
                recalcTimeLostFromRestart()
            }
        }
    }
    @Published var LS_actualStart: Date = Date() {
        didSet { Store.saveDate(LS_actualStart, key: "LS_actualStart") }
    }
    @Published var A_netPlayingTime: Int = 420 {
        didSet { Store.saveInt(A_netPlayingTime, key: "A_npt") }
    }
    @Published var B_timeInProgress: Int = 0 {
        didSet { Store.saveInt(B_timeInProgress, key: "B_tip") }
    }
    @Published var C_playingTimeLost: Int = 0 {
        didSet { Store.saveInt(C_playingTimeLost, key: "C_ptl") }
    }
    @Published var D_extraTimeAvail: Int = 0 {
        didSet { Store.saveInt(D_extraTimeAvail, key: "D_eta") }
    }
    @Published var E_timeFromReducedInterval: Int = 0 {
        didSet { Store.saveInt(E_timeFromReducedInterval, key: "E_tfri") }
    }
    @Published var J_startOrRecommence: Date = Date() {
        didSet { Store.saveDate(J_startOrRecommence, key: "J_sor") }
    }
    @Published var M_intervalLength: Int = 30 {
        didSet { Store.saveInt(M_intervalLength, key: "M_il") }
    }
    @Published var A2_maxOvers: Int = 50 {
        didSet { Store.saveInt(A2_maxOvers, key: "A2_mo") }
    }
    @Published var C2_startTime: Date = Date() {
        didSet { Store.saveDate(C2_startTime, key: "C2_st") }
    }
    @Published var H_maxOversAtStart: Int = 50 {
        didSet { Store.saveInt(H_maxOversAtStart, key: "H_moas") }
    }
    @Published var A3_startOfInnings: Date = Date() {
        didSet { Store.saveDate(A3_startOfInnings, key: "A3_soi") }
    }
    @Published var B3_startOfInterruption: Date = Date() {
        didSet { Store.saveDate(B3_startOfInterruption, key: "B3_soi") }
    }
    @Published var D3_restartTime: Date = Date() {
        didSet { Store.saveDate(D3_restartTime, key: "D3_rt") }
    }
    @Published var F3_additionalTimeAvail: Int = 0 {
        didSet { Store.saveInt(F3_additionalTimeAvail, key: "F3_ata") }
    }
    @Published var P_proposedRestart: Date = Date() {
        didSet { Store.saveDate(P_proposedRestart, key: "P_pr") }
    }
    @Published var Q_rescheduledCutoff: Date = Date() {
        didSet { Store.saveDate(Q_rescheduledCutoff, key: "Q_rc") }
    }
    @Published var T_completeOversFaced: Int = 0 {
        didSet { Store.saveInt(T_completeOversFaced, key: "T_cof") }
    }
    
    init() { loadFromDisk() }
    
    private func loadFromDisk() {
        isRestoringState = true
        defer { isRestoringState = false }
        matchIsActive = Store.loadBool(key: "blMatchActive")
        firstInningsDelays = Store.load([InningsDelay].self, key: "blFirstInningsDelays") ?? []
        timelineEvents = Store.load([MatchTimelineEvent].self, key: "blTimelineEvents") ?? []
        confirmedCessation = Store.loadDate(key: "blConfirmedCessation")
        let compRaw = Store.loadString(key: "competition", default: "ODC")
        competition = Competition(rawValue: compRaw) ?? .odc
        agreedExtraTime = Store.loadInt(key: "agreedExtraTime", default: 0)
        refreshRules()
        
        let themeRaw = Store.loadString(key: "theme", default: "Auto")
        themePreference = ThemePreference(rawValue: themeRaw) ?? .system
        
        isFinal = Store.loadBool(key: "isFinal")
        teamA   = Store.loadString(key: "teamA")
        teamB   = Store.loadString(key: "teamB")
        venue   = Store.loadString(key: "venue")
        
        let now = Date()
        calculationClockTime = Store.loadDate(key: "calculationClockTime") ?? now
        gameStartTime       = Store.loadDate(key: "gameStartTime") ?? now
        LS_actualStart      = Store.loadDate(key: "LS_actualStart") ?? now
        J_startOrRecommence = Store.loadDate(key: "J_sor") ?? now
        C2_startTime        = Store.loadDate(key: "C2_st") ?? now
        A3_startOfInnings   = Store.loadDate(key: "A3_soi") ?? now
        B3_startOfInterruption = Store.loadDate(key: "B3_soi") ?? now
        D3_restartTime      = Store.loadDate(key: "D3_rt") ?? now
        P_proposedRestart   = Store.loadDate(key: "P_pr") ?? now
        Q_rescheduledCutoff = Store.loadDate(key: "Q_rc") ?? now
        
        A_netPlayingTime      = Store.loadInt(key: "A_npt", default: rules.defaultNetPlayingTimeMinutes)
        B_timeInProgress      = Store.loadInt(key: "B_tip", default: 0)
        C_playingTimeLost     = Store.loadInt(key: "C_ptl", default: 0)
        D_extraTimeAvail      = Store.loadInt(key: "D_eta", default: 0)
        E_timeFromReducedInterval = Store.loadInt(key: "E_tfri", default: 0)
        M_intervalLength      = Store.loadInt(key: "M_il", default: rules.defaultIntervalMinutes)
        A2_maxOvers           = Store.loadInt(key: "A2_mo", default: rules.maxOversPerTeam)
        H_maxOversAtStart     = Store.loadInt(key: "H_moas", default: rules.maxOversPerTeam)
        F3_additionalTimeAvail = Store.loadInt(key: "F3_ata", default: 0)
        T_completeOversFaced  = Store.loadInt(key: "T_cof", default: 0)
        
        rescheduledCessationEnabled = Store.loadBool(key: "reschedEnabled")
        rescheduledCessation = Store.loadDate(key: "reschedCessation") ??
        EqualOversCalculator.originalCessation(start: gameStartTime, rules: rules)
        secondInningsDelays = Store.load([InningsDelay].self, key: "secondInningsDelays") ?? []
        secondInningsCompletedOvers = Store.loadInt(key: "secondInningsCompletedOvers", default: 0)
        secondInningsCompletedBalls = Store.loadInt(key: "secondInningsCompletedBalls", default: 0)
        snapshots    = Store.load([Snapshot].self, key: "snapshots") ?? []
        matchHistory = Store.load([MatchRecord].self, key: "matchHistory") ?? []
        // Repair stale first-innings anchor in saved untouched matches.
        if B_timeInProgress == 0 && C_playingTimeLost == 0 &&
            J_startOrRecommence != gameStartTime {
            J_startOrRecommence = gameStartTime
        }
    }
    
    func switchTo(_ comp: Competition) {
        guard !matchIsActive else { return }
        competition = comp
        agreedExtraTime = 0
        refreshRules()
        resetAll()
    }
    
    func resetAll() {
        currentSavedMatchID = nil
        firstInningsDelays = []
        undoFirstInningsDelays = nil
        timelineEvents = []
        confirmedCessation = nil
        A_netPlayingTime = rules.defaultNetPlayingTimeMinutes
        B_timeInProgress = 0
        C_playingTimeLost = 0
        D_extraTimeAvail = 0
        E_timeFromReducedInterval = 0
        M_intervalLength = rules.defaultIntervalMinutes
        J_startOrRecommence = gameStartTime
        LS_actualStart = gameStartTime
        A2_maxOvers = rules.maxOversPerTeam
        C2_startTime = gameStartTime
        H_maxOversAtStart = rules.maxOversPerTeam
        A3_startOfInnings = gameStartTime
        B3_startOfInterruption = gameStartTime
        D3_restartTime = gameStartTime
        F3_additionalTimeAvail = 0
        P_proposedRestart = gameStartTime
        Q_rescheduledCutoff = gameStartTime
        T_completeOversFaced = 0
        rescheduledCessationEnabled = false
        rescheduledCessation = EqualOversCalculator.originalCessation(start: gameStartTime, rules: rules)
        secondInningsDelays = []
        secondInningsCompletedOvers = 0
        secondInningsCompletedBalls = 0
        Haptic.medium()
    }
    
    // Rebuild derived first-innings values from the remaining chronological delays.
    // Do not retain a stale manually overridden lost-time total after deleting a log.
    // One-step undo for first-innings delay changes. Keep the prior records, not
    // merely the previous totals, so derived values can be rebuilt reliably.
    @Published var undoFirstInningsDelays: [InningsDelay]? = nil
    
    func rebuildFirstInningsFromLogs() {
        let ordered = firstInningsDelays.sorted { $0.start < $1.start }
        C_playingTimeLost = ordered.reduce(0) { $0 + $1.duration }
        if let last = ordered.last {
            let earlierLost = ordered.dropLast().reduce(0) { $0 + $1.duration }
            B_timeInProgress = max(0, TU.minBetween(LS_actualStart, last.start) - earlierLost)
            J_startOrRecommence = last.end
        } else {
            B_timeInProgress = 0
            J_startOrRecommence = LS_actualStart
        }
        updateIntervalIfNeeded()
    }
    
    func deleteFirstInningsDelay(id: UUID) {
        undoFirstInningsDelays = firstInningsDelays
        firstInningsDelays.removeAll { $0.id == id }
        rebuildFirstInningsFromLogs()
    }
    
    func editFirstInningsDelay(id: UUID, start: Date, end: Date) -> Bool {
        guard end > start, start >= LS_actualStart else { return false }
        let other = firstInningsDelays.filter { $0.id != id }
        guard !other.contains(where: { start < $0.end && end > $0.start }) else { return false }
        undoFirstInningsDelays = firstInningsDelays
        guard let index = firstInningsDelays.firstIndex(where: { $0.id == id }) else { return false }
        firstInningsDelays[index].start = start
        firstInningsDelays[index].end = end
        firstInningsDelays.sort { $0.start < $1.start }
        rebuildFirstInningsFromLogs()
        return true
    }
    
    func undoLastFirstInningsChange() {
        guard let previous = undoFirstInningsDelays else { return }
        firstInningsDelays = previous
        undoFirstInningsDelays = nil
        rebuildFirstInningsFromLogs()
    }
    
    func updateIntervalIfNeeded() {
        let newInterval = rules.adjustedInterval(timeLost: C_playingTimeLost + max(0, TU.minBetween(gameStartTime, LS_actualStart)))
        M_intervalLength = newInterval
        E_timeFromReducedInterval = max(0, rules.defaultIntervalMinutes - newInterval)
    }
    
    func recalcTimeLostFromRestart() {
        let offTime = TU.addMin(LS_actualStart, B_timeInProgress)
        C_playingTimeLost = max(0, TU.minBetween(offTime, J_startOrRecommence))
        updateIntervalIfNeeded()
    }
    
    // Snapshot operations
    private func makeSnapshot(label: String) -> Snapshot {
        let s = Snapshot(
            label: label, createdAt: Date(),
            A_netPlayingTime: A_netPlayingTime, B_timeInProgress: B_timeInProgress,
            C_playingTimeLost: C_playingTimeLost, D_extraTimeAvail: D_extraTimeAvail,
            E_timeFromReducedInterval: E_timeFromReducedInterval,
            J_startMinutesFromMidnight: minutesFromMidnight(J_startOrRecommence),
            M_intervalLength: M_intervalLength,
            A2_maxOvers: A2_maxOvers,
            C2_startMinutesFromMidnight: minutesFromMidnight(C2_startTime),
            H_maxOversAtStart: H_maxOversAtStart,
            A3_startMinutes: minutesFromMidnight(A3_startOfInnings),
            B3_interruptMinutes: minutesFromMidnight(B3_startOfInterruption),
            D3_restartMinutes: minutesFromMidnight(D3_restartTime),
            F3_additionalTimeAvail: F3_additionalTimeAvail,
            P_restartMinutes: minutesFromMidnight(P_proposedRestart),
            Q_cutoffMinutes: minutesFromMidnight(Q_rescheduledCutoff),
            T_completeOversFaced: T_completeOversFaced,
            LS_actualStartMinutes: minutesFromMidnight(LS_actualStart),
            gameStartMinutes: minutesFromMidnight(gameStartTime),
            savedMatchStartDate: gameStartTime,
            competitionCode: competition.rawValue,
            savedTeamA: teamA, savedTeamB: teamB,
            savedVenue: venue, savedIsFinal: isFinal,
            savedMatchIsActive: matchIsActive,
            savedTimelineEvents: timelineEvents,
            savedConfirmedCessation: confirmedCessation,
            firstInningsDelays: firstInningsDelays,
            secondInningsDelays: secondInningsDelays,
            secondInningsCompletedOvers: secondInningsCompletedOvers,
            secondInningsCompletedBalls: secondInningsCompletedBalls,
            rescheduledCessationEnabled: rescheduledCessationEnabled,
            rescheduledCessation: rescheduledCessation,
            savedAgreedExtraTime: competition.isInternational ? agreedExtraTime : nil
        )
        return s
    }
    
    func captureSnapshot(label: String) {
        snapshots.insert(makeSnapshot(label: label), at: 0)
        // Never silently evict a saved match or scenario. Retain all records.
        Haptic.success()
    }
    
    // Compare all persisted snapshot fields, excluding only presentation metadata.
    private func snapshotSignature(_ snapshot: Snapshot) -> Data? {
        guard let data = try? JSONEncoder().encode(snapshot),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        for key in ["id", "label", "createdAt"] { object.removeValue(forKey: key) }
        return try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    
    var currentMatchHasUnsavedChanges: Bool {
        guard let id = currentSavedMatchID,
              let saved = snapshots.first(where: { $0.id == id }) else { return true }
        return snapshotSignature(makeSnapshot(label: saved.label)) != snapshotSignature(saved)
    }
    
    func saveCurrentMatch() {
        let previous = snapshots.first(where: { $0.id == currentSavedMatchID })
        var snapshot = makeSnapshot(label: previous?.label ?? "\(competition.fullName) — \(teamA.isEmpty ? "Match" : teamA) \(teamB.isEmpty ? "" : "v \(teamB)")")
        if let previous {
            snapshot.id = previous.id
            snapshots.removeAll { $0.id == previous.id }
        }
        currentSavedMatchID = snapshot.id
        snapshots.insert(snapshot, at: 0)
        // Never silently evict a saved match or scenario. Retain all records.
        Haptic.success()
    }
    
    @discardableResult
    func restoreSnapshot(_ s: Snapshot) -> Bool {
        // Older snapshots did not include interruption records. Restoring one
        // would mix old calculated inputs with the current match's delay logs.
        // Refuse such a restore rather than silently creating unsafe results.
        // PROPOSED FIX: report the refusal to the caller instead of failing silently.
        guard let restoredFirst = s.firstInningsDelays,
              let restoredSecond = s.secondInningsDelays,
              let restoredOvers = s.secondInningsCompletedOvers,
              let restoredBalls = s.secondInningsCompletedBalls,
              let code = s.competitionCode,
              let comp = Competition(rawValue: code),
              let restoredTeamA = s.savedTeamA,
              let restoredTeamB = s.savedTeamB,
              let restoredVenue = s.savedVenue,
              let restoredFinal = s.savedIsFinal,
              s.savedMatchIsActive != nil,
              let restoredEvents = s.savedTimelineEvents else { return false }
        // Older incomplete snapshots are intentionally not restored.
        isRestoringState = true
        defer { isRestoringState = false }
        matchIsActive = false
        competition = comp
        agreedExtraTime = s.savedAgreedExtraTime ?? 0
        refreshRules()
        teamA = restoredTeamA
        teamB = restoredTeamB
        venue = restoredVenue
        isFinal = restoredFinal
        // Reset the date anchor before assigning the snapshot's records and
        // numeric inputs; gameStartTime's observer can otherwise recalculate.
        func atMinute(_ minute: Int) -> Date {
            // Legacy snapshots lack a match-date anchor: preserve their old
            // behaviour rather than guessing an unrelated historical date.
            let anchor = s.savedMatchStartDate ?? s.createdAt
            let sameDay = TU.addMin(Calendar.current.startOfDay(for: anchor), minute)
            // PROPOSED FIX (cross-midnight): times are stored as minutes from midnight and
            // every match time is on/after the scheduled start, so an earlier clock time
            // (e.g. 00:20 for a 19:00 start) belongs to the NEXT calendar day.
            return minute < s.gameStartMinutes ? TU.addMin(sameDay, 24 * 60) : sameDay
        }
        gameStartTime = atMinute(s.gameStartMinutes)
        A_netPlayingTime = s.A_netPlayingTime
        B_timeInProgress = s.B_timeInProgress
        C_playingTimeLost = s.C_playingTimeLost
        D_extraTimeAvail = s.D_extraTimeAvail
        E_timeFromReducedInterval = s.E_timeFromReducedInterval
        M_intervalLength = s.M_intervalLength
        A2_maxOvers = s.A2_maxOvers
        H_maxOversAtStart = s.H_maxOversAtStart
        F3_additionalTimeAvail = s.F3_additionalTimeAvail
        T_completeOversFaced = s.T_completeOversFaced
        LS_actualStart = atMinute(s.LS_actualStartMinutes)
        J_startOrRecommence = atMinute(s.J_startMinutesFromMidnight)
        C2_startTime = atMinute(s.C2_startMinutesFromMidnight)
        A3_startOfInnings = atMinute(s.A3_startMinutes)
        B3_startOfInterruption = atMinute(s.B3_interruptMinutes)
        D3_restartTime = atMinute(s.D3_restartMinutes)
        P_proposedRestart = atMinute(s.P_restartMinutes)
        Q_rescheduledCutoff = atMinute(s.Q_cutoffMinutes)
        firstInningsDelays = restoredFirst
        secondInningsDelays = restoredSecond
        secondInningsCompletedOvers = restoredOvers
        secondInningsCompletedBalls = restoredBalls
        if let enabled = s.rescheduledCessationEnabled {
            rescheduledCessationEnabled = enabled
        }
        if let cessation = s.rescheduledCessation {
            rescheduledCessation = cessation
        }
        timelineEvents = restoredEvents
        confirmedCessation = s.savedConfirmedCessation
        matchIsActive = true
        currentSavedMatchID = s.id
        undoFirstInningsDelays = nil
        Haptic.medium()
        return true
    }
    
    func deleteSnapshot(_ s: Snapshot) {
        snapshots.removeAll { $0.id == s.id }
        Haptic.light()
    }
    
    func saveToHistory() {
        let rec = MatchRecord(
            date: Date(),
            competition: competition.fullName,
            teamA: teamA, teamB: teamB, venue: venue,
            summary: generateSummary(),
            isFinal: isFinal
        )
        matchHistory.insert(rec, at: 0)
        if matchHistory.count > 20 { matchHistory = Array(matchHistory.prefix(20)) }
        Haptic.success()
    }
    
    func deleteHistoryRecord(_ r: MatchRecord) {
        matchHistory.removeAll { $0.id == r.id }
        Haptic.light()
    }
    
    private func minutesFromMidnight(_ date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    
    // Validation
    func firstInningsWarnings() -> [ValidationWarning] {
        var w: [ValidationWarning] = []
        if C_playingTimeLost > A_netPlayingTime {
            w.append(ValidationWarning(message: "Playing time lost exceeds net playing time available", severity: .error))
        }
        if D_extraTimeAvail > C_playingTimeLost {
            w.append(ValidationWarning(message: "Extra time available exceeds time lost", severity: .caution))
        }
        if B_timeInProgress > A_netPlayingTime / 2 {
            w.append(ValidationWarning(message: "Time in progress is more than half the available time", severity: .caution))
        }
        if rules.extraTimeMinutes == 0 && D_extraTimeAvail > 0 {
            w.append(ValidationWarning(message: competition.isInternational
                ? "No extra time is set for this match. If the participating countries agreed some, enter it in Match Info (Extra time)."
                : "This competition has no general extra-time allowance; check any entered exception against the playing conditions", severity: .caution))
        }
        if rescheduledCessationEnabled && rescheduledCessation <= J_startOrRecommence {
            w.append(ValidationWarning(message: "Rescheduled cessation must be after the restart", severity: .error))
        }
        if rules.extraTimeMinutes > 0 && D_extraTimeAvail > rules.extraTimeMinutes {
            w.append(ValidationWarning(message: "Extra time entered exceeds the \(rules.extraTimeMinutes) min allocation", severity: .error))
        }
        return w
    }
    
    func secondInningsInterruptionWarnings() -> [ValidationWarning] {
        var w: [ValidationWarning] = []
        if B3_startOfInterruption < A3_startOfInnings {
            w.append(ValidationWarning(message: "Interruption start is before innings start", severity: .error))
        }
        if D3_restartTime < B3_startOfInterruption {
            w.append(ValidationWarning(message: "Restart time is before interruption start", severity: .error))
        }
        if secondInningsDelays.isEmpty && F3_additionalTimeAvail > TU.minBetween(B3_startOfInterruption, D3_restartTime) {
            w.append(ValidationWarning(message: "Additional time exceeds the interruption length", severity: .caution))
        }
        if secondInningsCompletedOvers > H_maxOversAtStart ||
            (secondInningsCompletedOvers == H_maxOversAtStart && secondInningsCompletedBalls > 0) {
            w.append(ValidationWarning(message: "Completed overs exceed the maximum allocation at innings start", severity: .error))
        }
        if !secondInningsDelays.isEmpty && !secondInningsDelays.contains(where: {
            $0.start == B3_startOfInterruption && $0.end == D3_restartTime
        }) {
            w.append(ValidationWarning(message: "The current interruption is not in the log. Add it before relying on cumulative revised overs.", severity: .error))
        }
        if secondInningsDelays.contains(where: { $0.start < A3_startOfInnings }) {
            w.append(ValidationWarning(message: "A logged stoppage begins before the second innings", severity: .error))
        }
        // Validate the entire delay log before using its cumulative loss.
        let orderedDelays = secondInningsDelays.sorted { $0.start < $1.start }
        for delay in orderedDelays {
            if delay.end <= delay.start {
                w.append(ValidationWarning(message: "A logged stoppage has an invalid start or restart time", severity: .error))
            }
            if delay.allowanceMinutes < 0 || delay.allowanceMinutes > delay.duration {
                w.append(ValidationWarning(message: "A logged stoppage allowance is outside its duration", severity: .error))
            }
            if delay.end > D3_restartTime {
                w.append(ValidationWarning(message: "A logged stoppage ends after the latest restart", severity: .error))
            }
        }
        if orderedDelays.count > 1 {
            for index in 1..<orderedDelays.count where orderedDelays[index].start < orderedDelays[index - 1].end {
                w.append(ValidationWarning(message: "Logged stoppages overlap; cumulative time lost would be double-counted", severity: .error))
                break
            }
        }
        if secondInningsCompletedOvers < 0 || secondInningsCompletedBalls < 0 || secondInningsCompletedBalls > 5 {
            w.append(ValidationWarning(message: "Completed legal overs and balls are invalid", severity: .error))
        }
        if H_maxOversAtStart < 0 || H_maxOversAtStart > rules.maxOversPerTeam {
            w.append(ValidationWarning(message: "Maximum overs at innings start is outside competition limits", severity: .error))
        }
        // A reduced allocation below balls already delivered is not a valid
        // match instruction. Flag it rather than silently raising the allocation.
        let allDelays = secondInningsDelays.isEmpty
        ? [InningsDelay(start: B3_startOfInterruption, end: D3_restartTime, allowanceMinutes: 0)]
        : secondInningsDelays
        let worksheet = SecondInningsWorksheet.calculate(rules: rules,
                                                         inningsStart: A3_startOfInnings, restart: D3_restartTime,
                                                         initialOvers: H_maxOversAtStart, delays: allDelays,
                                                         completedOvers: secondInningsCompletedOvers,
                                                         completedBalls: secondInningsCompletedBalls,
                                                         extraTimeAlreadyUsed: firstInningsLoss.extraApplied,
                                                         earlyStartCredit: F3_additionalTimeAvail)
        if worksheet.exceedsCompletedOvers {
            w.append(ValidationWarning(message: "Calculated revised overs are fewer than legal overs already faced. Check interruption details and refer to match officials; do not use this result.", severity: .error))
        }
        if !secondInningsDelays.isEmpty {
            w.append(ValidationWarning(message: "Logged delays are cumulative. Confirm completed overs and any revised cessation with match officials; this remains a time-based projection, not a verified revised cessation schedule.", severity: .info))
        }
        return w
    }
    
    func terminationWarnings() -> [ValidationWarning] {
        var w: [ValidationWarning] = []
        if Q_rescheduledCutoff <= P_proposedRestart {
            w.append(ValidationWarning(message: "Cut-off time is not after the proposed restart", severity: .error))
        }
        if T_completeOversFaced > rules.maxOversPerTeam {
            w.append(ValidationWarning(message: "Overs faced exceeds maximum overs per team", severity: .error))
        }
        return w
    }
    
    // All competitions: use the shared delayed-start equal-overs worksheet
    // before any separate first-innings interruption is recorded.
    // WBBL's 18-minute convention applies ONLY to minimum-match latest-start
    // eligibility; never to this revised-overs calculation.
    var delayedFirstBallPlan: EqualOversPlan? {
        guard LS_actualStart > gameStartTime,
              firstInningsDelays.isEmpty,
              C_playingTimeLost == 0,
              B_timeInProgress == 0 else { return nil }
        let lost = max(0, TU.minBetween(gameStartTime, LS_actualStart))
        let interval = rules.adjustedInterval(timeLost: lost)
        let savedInterval = rules.defaultIntervalMinutes - interval
        let extra = min(lost, rules.extraTimeMinutes)
        let available = max(0, rules.defaultNetPlayingTimeMinutes -
                            max(0, lost - extra - savedInterval))
        return EqualOversCalculator.plan(
            rules: rules, originalStart: gameStartTime,
            restart: LS_actualStart, playedMinutes: 0,
            initialOvers: TU.ceilOv((Double(available) / rules.minutesPerOver) / 2.0),
            interval: interval,
            rescheduledCessation: rescheduledCessationEnabled ? rescheduledCessation : nil)
    }
    
    // PROPOSED FIX (late start followed by rain): ONE accounting of first-innings time,
    // used by the plan, the on-screen panel, the provisional preview and the share summary.
    // Previously the panel and summary omitted the late-start minutes, and the plan only
    // applied extra time if the umpire had typed it into "Extra time available"
    // (delayedFirstBallPlan applied it automatically), so overs changed discontinuously
    // the moment the first rain delay was logged.
    struct FirstInningsLoss {
        let totalLoss: Int        // late start before first ball + every logged stoppage
        let extraApplied: Int     // rule-driven extra time, exhausted first (WNCL cl. 12.7.1)
        let intervalCredit: Int   // minutes saved by the reduced innings interval
        let effective: Int
        let remaining: Int
        let totalOvers: Double
    }
    var firstInningsLoss: FirstInningsLoss {
        let initialDelay = max(0, TU.minBetween(gameStartTime, LS_actualStart))
        let totalLoss = initialDelay + C_playingTimeLost
        let extra = min(totalLoss, rules.extraTimeMinutes)
        let credit = max(0, rules.defaultIntervalMinutes - rules.adjustedInterval(timeLost: totalLoss))
        let effective = max(0, totalLoss - extra - credit)
        let remaining = max(0, A_netPlayingTime - effective)
        let raw = Double(remaining) / rules.minutesPerOver
        return FirstInningsLoss(totalLoss: totalLoss, extraApplied: extra, intervalCredit: credit,
                                effective: effective, remaining: remaining,
                                totalOvers: competition.isT20 ? TU.round2(raw) : raw)
    }

    var firstInningsPlan: EqualOversPlan {
        if let delayedFirstBallPlan { return delayedFirstBallPlan }
        let loss = firstInningsLoss
        return EqualOversCalculator.plan(rules: rules, originalStart: gameStartTime,
                                         // PROPOSED FIX: measure from the actual first ball,
                                         // not the scheduled start, when a late start is recorded.
                                         restart: (firstInningsDelays.isEmpty && C_playingTimeLost == 0
                                                   ? TU.addMin(LS_actualStart, B_timeInProgress)
                                                   : J_startOrRecommence),
                                         playedMinutes: B_timeInProgress,
                                         initialOvers: TU.ceilOv(loss.totalOvers / 2.0),
                                         interval: M_intervalLength,
                                         rescheduledCessation: rescheduledCessationEnabled ? rescheduledCessation : nil)
    }
    
    // Summary
    func generateSummary() -> String {
        var lines: [String] = []
        lines.append("=== \(competition.fullName)\(isFinal ? " -- FINAL" : "") ===")
        if !teamA.isEmpty || !teamB.isEmpty {
            lines.append("\(teamA) v \(teamB)".trimmingCharacters(in: .whitespaces))
        }
        if !venue.isEmpty { lines.append("Venue: \(venue)") }
        let df = DateFormatter(); df.dateStyle = .medium
        lines.append("Date: \(df.string(from: Date()))")
        lines.append("Scheduled start: \(TU.shortTime(gameStartTime))")
        lines.append("Rules: \(competition.isInternational ? "ICC" : "CA") \(competition.rawValue) PC \(rules.almanacVersion)")
        lines.append("")
        
        // PROPOSED FIX: same accounting as the plan (includes the late-start minutes).
        let loss = firstInningsLoss
        let effLost = loss.effective
        let remaining = loss.remaining
        let totalOv = loss.totalOvers
        let plan = firstInningsPlan
        let perTeam = plan.oversPerTeam
        let innLen = plan.inningsMinutes
        
        lines.append("--- FIRST INNINGS (PC Appendix J) ---")
        if loss.totalLoss > 0 {
            lines.append("Late start + stoppages: \(loss.totalLoss) min lost")
            if loss.extraApplied > 0 { lines.append("Extra time offset: +\(loss.extraApplied) min") }
            if loss.intervalCredit > 0 {
                lines.append("Reduced interval offset: +\(loss.intervalCredit) min")
            }
            lines.append("Effective loss [lost-(extra+interval)]: \(effLost) min")
        }
        lines.append("Remaining time [A-F]: \(remaining) min")
        lines.append("Total overs [G/\(TU.fmt2(rules.minutesPerOver))]: \(TU.fmt2(totalOv))")
        lines.append("Max overs/team [H/2, ceil + Appendix J guard]: \(perTeam)")
        lines.append("Cessation target: \(TU.shortTime(plan.targetCessation))")
        if !plan.meetsTarget {
            lines.append("WARNING: Target cessation cannot be reached within maximum overs")
        }
        if !secondInningsDelays.isEmpty {
            let total = secondInningsDelays.reduce(0) { $0 + $1.duration }
            lines.append("Second innings logged stoppages: \(secondInningsDelays.count), total \(total) min")
        }
        let minOv = isFinal ? rules.minValidOversFinal : rules.minValidOvers
        lines.append("Min for result: \(minOv) ov -- \(perTeam >= minOv ? "VALID" : "NO RESULT")")
        lines.append("Max per bowler [I/5, ceil]: \(rules.maxOversPerBowler(teamOvers: perTeam))")
        lines.append("Innings length [I x \(TU.fmt2(rules.minutesPerOver)), ceil]: \(innLen) min")
        if let cutoff = rules.cutoffMinutes(for: perTeam) {
            lines.append("Cut-off (last over by): \(cutoff) min")
        }
        
        switch competition {
        case .odc, .odi:
            let pp = rules.odcPowerplays(for: perTeam)
            lines.append("Powerplays: P1=\(pp.0) + P2=\(pp.1) + P3=\(pp.2)")
        case .t20i:
            let pp = rules.t20iPowerplay(for: perTeam)
            lines.append("Powerplay: \(pp.overs).\(pp.balls) ov (2 outside). Remainder: 5 outside")
        case .wncl:
            let pp = rules.wnclPowerplay(for: perTeam)
            lines.append("Powerplay: \(pp.pp) ov (2 out). Non-PP: \(pp.nonPp) ov (4 out)")
        case .bbl, .wbbl:
            let info = rules.powerplayInfo(for: perTeam)
            if info.hasSurge, let ws = info.surgeWindowStart, let we = info.surgeWindowEnd {
                lines.append("PP: \(info.powerplayOvers) ov. Surge: \(info.surgeOvers) ov (ov \(ws)-\(we))")
            } else {
                lines.append("PP: \(info.powerplayOvers) ov. No surge.")
            }
        }
        
        let cease1 = plan.firstCessation
        let start2 = plan.secondStart
        let cease2 = plan.secondCessation
        lines.append("Applicable cessation target: \(TU.shortTime(plan.targetCessation))")
        if plan.extraOversPerTeam > 0 {
            lines.append("Appendix J adjustment: +\(plan.extraOversPerTeam) over(s) per team")
        }
        if !plan.meetsTarget {
            lines.append("NOTE: Cannot reach applicable cessation target within maximum overs")
        }
        lines.append("Interval: \(M_intervalLength) min")
        lines.append("1st innings cease [L]: \(TU.shortTime(cease1))")
        lines.append("2nd innings start [N]: \(TU.shortTime(start2))")
        lines.append("2nd innings cease [O]: \(TU.shortTime(cease2))")
        lines.append("")
        lines.append("Calculated: \(TU.shortDateTime(Date()))")
        lines.append("BoundaryLine Rain & Overs")
        return lines.joined(separator: "\n")
    }
}

// MARK: - Timeline

struct TimelineSegment: Identifiable {
    let id = UUID()
    let label: String
    let start: Date
    let end: Date
    let color: Color
    let isDelay: Bool
}

struct TimelineBar: View {
    let segments: [TimelineSegment]
    let overallStart: Date
    let overallEnd: Date
    let currentTime: Date?
    
    private var totalMinutes: Double {
        max(1, Double(TU.signedMinBetween(overallStart, overallEnd)))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("TIMELINE").font(.caption.weight(.bold)).foregroundStyle(.secondary).tracking(1)
            
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 8).fill(AppTheme.panelAlt).frame(height: 36)
                    ForEach(segments) { seg in
                        let start = Double(TU.signedMinBetween(overallStart, seg.start))
                        let dur = Double(TU.signedMinBetween(seg.start, seg.end))
                        if dur > 0 {
                            let xPos = (start / totalMinutes) * w
                            let width = (dur / totalMinutes) * w
                            RoundedRectangle(cornerRadius: 8)
                                .fill(seg.color.opacity(seg.isDelay ? 0.9 : 0.8))
                                .frame(width: max(2, width), height: 36)
                                .offset(x: max(0, xPos))
                                .overlay(
                                    Text(seg.label)
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white).lineLimit(1)
                                        .shadow(color: .black.opacity(0.5), radius: 2, x: 0, y: 1)
                                        .padding(.horizontal, 6)
                                        .offset(x: max(0, xPos))
                                        .frame(width: max(2, width), height: 36, alignment: .leading)
                                        .clipped(),
                                    alignment: .leading
                                )
                        }
                    }
                    if let now = currentTime {
                        let nowPos = Double(TU.signedMinBetween(overallStart, now))
                        if nowPos >= 0 && nowPos <= totalMinutes {
                            let x = (nowPos / totalMinutes) * w
                            Rectangle().fill(Color.red).frame(width: 3, height: 44)
                                .offset(x: x - 1.5, y: -4)
                        }
                    }
                }
            }
            .frame(height: 36)
            
            HStack {
                Text(TU.shortTime(overallStart)).font(.caption2.monospaced()).foregroundStyle(.secondary)
                Spacer()
                Text(TU.shortTime(overallEnd)).font(.caption2.monospaced()).foregroundStyle(.secondary)
            }
            // Exact boundary timestamps for every logged rain interruption.
            // Rows alternate so neighbouring Off/On times remain legible on iPad.
            let rainSegments = segments.filter { $0.isDelay && $0.end > $0.start }
            if !rainSegments.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(rainSegments.enumerated()), id: \.element.id) { index, delay in
                        HStack(spacing: 8) {
                            Text("Rain \(index + 1)")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(.secondary)
                                .frame(width: 54, alignment: .leading)
                            Text("Off \(TU.shortTime(delay.start))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(AppTheme.destructive)
                            Image(systemName: "arrow.right")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("On \(TU.shortTime(delay.end))")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(AppTheme.hero)
                            Spacer(minLength: 0)
                            Text("\(max(0, TU.signedMinBetween(delay.start, delay.end))) min")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.top, 4)
                .accessibilityElement(children: .contain)
            }
        }
    }
}

// MARK: - Hero Cards

struct HeroCard: View {
    let primaryLabel: String
    let primaryValue: String
    let secondaryLabel: String?
    let secondaryValue: String?
    var tint: Color = AppTheme.hero
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(primaryLabel.uppercased())
                .font(.system(.caption, design: .rounded).weight(.semibold))
                .foregroundStyle(.white.opacity(0.85)).tracking(1.2)
            Text(primaryValue)
                .font(.system(size: 52, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white).lineLimit(1)
            if let sl = secondaryLabel, let sv = secondaryValue {
                HStack(spacing: 6) {
                    Text(sl).font(.caption).foregroundStyle(.white.opacity(0.8))
                    Text(sv).font(.callout.weight(.semibold)).foregroundStyle(.white)
                }.padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(LinearGradient(colors: [tint, tint.opacity(0.82)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: tint.opacity(0.3), radius: 14, x: 0, y: 6)
    }
}

struct DualHeroCard: View {
    let leftLabel: String
    let leftValue: String
    let rightLabel: String
    let rightValue: String
    var tint: Color = AppTheme.hero
    
    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(leftLabel.uppercased())
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85)).tracking(1)
                Text(leftValue)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Rectangle().fill(.white.opacity(0.25)).frame(width: 1, height: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(rightLabel.uppercased())
                    .font(.system(.caption2, design: .rounded).weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85)).tracking(1)
                Text(rightValue)
                    .font(.system(size: 34, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white).lineLimit(1)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 16)
        }
        .padding(18)
        .background(LinearGradient(colors: [tint, tint.opacity(0.82)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .shadow(color: tint.opacity(0.3), radius: 14, x: 0, y: 6)
    }
}

// MARK: - Valid Match Badge

struct ValidMatchBadge: View {
    let overs: Int
    let minimum: Int
    var isValid: Bool { overs >= minimum }
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isValid ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isValid ? AppTheme.success : AppTheme.destructive)
            VStack(alignment: .leading, spacing: 2) {
                Text(isValid ? "Minimum overs met" : "Below minimum overs")
                    .font(.callout.weight(.semibold))
                Text(isValid
                     ? "\(overs) ov allocation meets the \(minimum)-over threshold"
                     : "\(overs) ov allocation is below the \(minimum)-over threshold; check match status")
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background((isValid ? AppTheme.success : AppTheme.destructive).opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Validation Banner

struct ValidationBanner: View {
    let warnings: [ValidationWarning]
    
    var body: some View {
        if !warnings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(warnings) { w in
                    HStack(spacing: 8) {
                        Image(systemName: w.icon).foregroundStyle(w.color)
                        Text(w.message).font(.caption)
                        Spacer()
                    }
                }
            }
            .padding(10)
            .background(AppTheme.warning.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Shared Components

struct StatRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(.body, design: .monospaced).weight(.medium))
        }
    }
}

struct StatDateRow: View {
    let label: String
    let date: Date
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(TU.shortTime(date)).font(.system(.body, design: .monospaced).weight(.medium))
        }
    }
}

struct SectionDivider: View {
    var body: some View { Divider().overlay(AppTheme.line).padding(.vertical, 4) }
}

// Int field with large +/- buttons, presets, and Now-style quick sets
struct IntField: View {
    let title: String
    @Binding var value: Int
    var lo: Int = 0
    var hi: Int = 2000
    var step: Int = 1
    var suffix: String? = "min"
    var presets: [Int]? = nil
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                Text(title).lineLimit(2).minimumScaleFactor(0.8)
                Spacer()
                HStack(spacing: 6) {
                    Button {
                        value = max(lo, value - step)
                        Haptic.light()
                    } label: {
                        Image(systemName: "minus").font(.system(size: 13, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(AppTheme.panelAlt).clipShape(Circle())
                    }
                    .buttonStyle(.plain).foregroundStyle(.primary)
                    
                    TextField("0", value: $value, format: .number)
                        .keyboardType(.numberPad).multilineTextAlignment(.center)
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                        .frame(width: 64).padding(.vertical, 6)
                        .background(AppTheme.panelAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    
                    Button {
                        value = min(hi, value + step)
                        Haptic.light()
                    } label: {
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(AppTheme.panelAlt).clipShape(Circle())
                    }
                    .buttonStyle(.plain).foregroundStyle(.primary)
                    
                    if let s = suffix { Text(s).foregroundStyle(.secondary).font(.callout) }
                }
            }
            if let presets = presets, !presets.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(presets, id: \.self) { p in
                            Button {
                                value = min(hi, max(lo, p))
                                Haptic.light()
                            } label: {
                                Text("\(p)")
                                    .font(.system(.caption, design: .rounded).weight(.semibold))
                                    .frame(minWidth: 40)
                                    .padding(.vertical, 6).padding(.horizontal, 10)
                                    .background(value == p ? AppTheme.accent : AppTheme.panelAlt)
                                    .foregroundStyle(value == p ? .white : .primary)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }
}

// Time field with Now button always shown
struct TimeField: View {
    @EnvironmentObject var ms: MatchState
    let title: String
    @Binding var value: Date
    var showNow: Bool = true
    
    var body: some View {
        HStack(spacing: 12) {
            Text(title).lineLimit(2).minimumScaleFactor(0.8)
            Spacer()
            DatePicker("", selection: $value, displayedComponents: [.hourAndMinute])
                .labelsHidden().datePickerStyle(.compact).font(.title3)
            
        }
    }
}

// MARK: - Powerplay Display

struct PowerplayDisplay: View {
    let competition: Competition
    let rules: CompRules
    let overs: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("POWERPLAY").font(.caption.weight(.bold)).foregroundStyle(.secondary).tracking(1)
            switch competition {
            case .odc, .odi:
                let pp = rules.odcPowerplays(for: overs)
                HStack(spacing: 10) {
                    ppBadge("P1", "\(pp.0)")
                    ppBadge("P2", "\(pp.1)")
                    ppBadge("P3", "\(pp.2)")
                }
                if competition == .odi {
                    Text("P1: max 2 outside. P2: max 4 outside. P3: max 5 outside (PC 28.7.2)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            case .t20i:
                let pp = rules.t20iPowerplay(for: overs)
                HStack(spacing: 10) {
                    ppBadge("PP", "\(pp.overs).\(pp.balls)")
                    ppBadge("Bowler", "\(rules.maxOversPerBowler(teamOvers: overs))")
                }
                Text("Powerplay: max 2 outside. Remainder: max 5 outside. Shown as overs.balls (PC 28.7.4-28.7.6)")
                    .font(.caption).foregroundStyle(.secondary)
            case .wncl:
                let pp = rules.wnclPowerplay(for: overs)
                HStack(spacing: 10) {
                    ppBadge("PP", "\(pp.pp)")
                    ppBadge("Non-PP", "\(pp.nonPp)")
                    ppBadge("Bowler", "\(pp.maxBowler)")
                }
                Text("PP: max 2 outside. Non-PP: max 4 outside")
                    .font(.caption).foregroundStyle(.secondary)
            case .bbl, .wbbl:
                let info = rules.powerplayInfo(for: overs)
                HStack(spacing: 10) {
                    ppBadge("PP", "\(info.powerplayOvers)")
                    if info.hasSurge, let s = info.surgeWindowStart, let e = info.surgeWindowEnd {
                        ppBadge("Surge", "\(info.surgeOvers)")
                        Text("Ov \(s)-\(e)").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Text("No Surge").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text(rules.bowlingRestrictionText(for: overs))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    
    private func ppBadge(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            Text(value).font(.title3.weight(.bold).monospacedDigit())
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(AppTheme.panelAlt)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Tabs

enum Tab: String, CaseIterable {
    case lateStart   = "Late Start"
    case firstInns   = "1st Innings"
    case termination = "Termination"
    case secondStart = "2nd Start"
    case secondInter = "2nd Interrupt"
    case powerplays  = "Powerplays"
    case breaks      = "Breaks & Delays"
    case summary     = "Summary"
    
    var icon: String {
        switch self {
        case .lateStart:   return "clock.badge.exclamationmark"
        case .firstInns:   return "1.circle"
        case .termination: return "stop.circle"
        case .secondStart: return "2.circle"
        case .secondInter: return "cloud.rain"
        case .powerplays:  return "bolt.circle"
        case .breaks:      return "list.bullet.rectangle"
        case .summary:     return "chart.bar.doc.horizontal"
        }
    }
}

// MARK: - Responsive Layout

struct ResponsiveLayout<Inputs: View, Outputs: View>: View {
    let inputs: Inputs
    let outputs: Outputs
    
    init(@ViewBuilder inputs: () -> Inputs, @ViewBuilder outputs: () -> Outputs) {
        self.inputs = inputs()
        self.outputs = outputs()
    }
    
    var body: some View {
        GeometryReader { geo in
            // 700pt catches a phone held in landscape (a common way to check this app under
            // an umbrella), not just iPad -- portrait phones never reach this width.
            if geo.size.width >= 700 {
                HStack(alignment: .top, spacing: 18) {
                    ScrollView { VStack(spacing: 16) { inputs }.padding(.vertical, 8) }
                        .frame(maxWidth: .infinity)
                    ScrollView { VStack(spacing: 16) { outputs }.padding(.vertical, 8) }
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 20)
            } else {
                ScrollView {
                    VStack(spacing: 16) { outputs; inputs }
                        .padding(.horizontal, 20).padding(.vertical, 8)
                }
            }
        }
    }
}

// MARK: - Optional rescheduled cessation target

struct CessationTargetEditor: View {
    @EnvironmentObject var ms: MatchState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Use rescheduled cessation time", isOn: $ms.rescheduledCessationEnabled)
            if ms.rescheduledCessationEnabled {
                TimeField(title: "Rescheduled cessation", value: $ms.rescheduledCessation,
                          showNow: false)
                Text("Only enable when a revised match cessation has been formally established. This overrides the original target for the Appendix J safeguard.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Late Start ODC/WNCL

struct LateStartODCView: View {
    @EnvironmentObject var ms: MatchState
    
    private var timeLost: Int { max(0, TU.minBetween(ms.gameStartTime, ms.LS_actualStart)) }
    private var remaining: Int {
        let savedInterval = ms.rules.defaultIntervalMinutes - autoInterval
        let extra = min(timeLost, ms.rules.extraTimeMinutes)
        return max(0, ms.rules.defaultNetPlayingTimeMinutes - max(0, timeLost - extra - savedInterval))
    }
    private var totalOvAll: Double { Double(remaining) / ms.rules.minutesPerOver }
    private var autoInterval: Int { ms.rules.adjustedInterval(timeLost: timeLost) }
    private var plan: EqualOversPlan {
        // A late start consumes extra time (where permitted) and saved interval minutes
        // before reducing equal overs.
        let intervalSaved = ms.rules.defaultIntervalMinutes - autoInterval
        let extra = min(timeLost, ms.rules.extraTimeMinutes)
        let available = max(0, ms.rules.defaultNetPlayingTimeMinutes -
                            max(0, timeLost - extra - intervalSaved))
        let total = Double(available) / ms.rules.minutesPerOver
        return EqualOversCalculator.plan(rules: ms.rules, originalStart: ms.gameStartTime,
                                         restart: ms.LS_actualStart, playedMinutes: 0,
                                         initialOvers: TU.ceilOv(total / 2.0), interval: autoInterval,
                                         rescheduledCessation: ms.rescheduledCessationEnabled ? ms.rescheduledCessation : nil)
    }
    private var ovPerTeam: Int { plan.oversPerTeam }
    private var bowler: Int { ms.rules.maxOversPerBowler(teamOvers: ovPerTeam) }
    private var inningsLen: Int { plan.inningsMinutes }
    private var cease1: Date { plan.firstCessation }
    private var start2: Date { plan.secondStart }
    private var cease2: Date { plan.secondCessation }
    
    private var segments: [TimelineSegment] {
        var s: [TimelineSegment] = []
        if timeLost > 0 {
            s.append(TimelineSegment(label: "Delay", start: ms.gameStartTime,
                                     end: ms.LS_actualStart, color: AppTheme.destructive, isDelay: true))
        }
        s.append(TimelineSegment(label: "1st", start: ms.LS_actualStart,
                                 end: cease1, color: AppTheme.hero, isDelay: false))
        s.append(TimelineSegment(label: "Int", start: cease1,
                                 end: start2, color: AppTheme.warning, isDelay: false))
        s.append(TimelineSegment(label: "2nd", start: start2,
                                 end: cease2, color: AppTheme.hero, isDelay: false))
        return s
    }
    
    var body: some View {
        ResponsiveLayout {
            VStack(spacing: 12) {
                TimeField(title: "Scheduled start", value: $ms.gameStartTime, showNow: false)
                TimeField(title: "Actual first ball", value: $ms.LS_actualStart)
                CessationTargetEditor().environmentObject(ms)
            }.card()
        } outputs: {
            DualHeroCard(leftLabel: "Overs/team", leftValue: "\(ovPerTeam)",
                         rightLabel: "2nd cease", rightValue: TU.shortTime(cease2))
            ValidMatchBadge(overs: ovPerTeam,
                            minimum: ms.isFinal ? ms.rules.minValidOversFinal : ms.rules.minValidOvers)
            if ms.competition.isT20 && !ms.competition.isInternational {
                let minOvers = ms.rules.minValidOvers
                let inningsSeconds = EqualOversCalculator.minimumInningsSeconds(
                    competition: ms.competition, rules: ms.rules, minOvers: minOvers)
                // At the latest permissible start, the delayed-match interval is reduced.
                // Do not derive this from the currently entered actual start.
                let reducedInterval = ms.rules.adjustedInterval(timeLost: ms.rules.lateStartMaxWindow ?? 0)
                let requiredSeconds = inningsSeconds * 2 + reducedInterval * 60
                let latestStart = EqualOversCalculator.latestFirstBall(
                    cessation: ms.rescheduledCessationEnabled
                        ? ms.rescheduledCessation
                        : EqualOversCalculator.originalCessation(start: ms.gameStartTime, rules: ms.rules),
                    inningsSeconds: inningsSeconds, intervalMinutes: reducedInterval)
                VStack(alignment: .leading, spacing: 8) {
                    StatRow(label: "Latest permissible first ball (minimum overs)", value: TU.shortTime(latestStart))
                    StatRow(label: "Minimum-match duration", value: "\(Int(ceil(Double(requiredSeconds) / 60.0))) min")
                    if ms.competition == .wbbl && minOvers == 5 && reducedInterval == 10 {
                        Text("WBBL latest-start check only: 18 + 10 + 18 = 46 min (CA WBBL Almanac 2026/27, p.47-48)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("The overs and timeline above use the actual first-ball time, not the latest permissible start.")
                        .font(.caption).foregroundStyle(.secondary)
                }.card()
            }
            VStack(alignment: .leading, spacing: 10) {
                TimelineBar(segments: segments, overallStart: ms.gameStartTime,
                            overallEnd: cease2, currentTime: ms.calculationClockTime)
                DelayTimestampList(delays: ms.firstInningsDelays)
            }.card()
            VStack(alignment: .leading, spacing: 10) {
                StatRow(label: "Late start delay", value: "\(timeLost) min")
                StatRow(label: "Extra time applied", value: "\(min(timeLost, ms.rules.extraTimeMinutes)) min")
                StatRow(label: "Interval time saved", value: "\(ms.rules.defaultIntervalMinutes - autoInterval) min")
                StatRow(label: "Remaining time", value: "\(remaining) min")
                StatRow(label: "Total overs (both)", value: TU.fmt2(totalOvAll))
                StatRow(label: "Max per bowler", value: "\(bowler)")
                if autoInterval != ms.rules.defaultIntervalMinutes {
                    StatRow(label: "Interval (auto-reduced)", value: "\(autoInterval) min")
                }
                if let co = ms.rules.cutoffMinutes(for: ovPerTeam) {
                    StatRow(label: "Scheduled last-over offset", value: "\(co) min")
                }
                SectionDivider()
                PowerplayDisplay(competition: ms.competition, rules: ms.rules, overs: ovPerTeam)
                SectionDivider()
                StatDateRow(label: "1st innings cease", date: cease1)
                StatDateRow(label: "2nd innings start", date: start2)
            }.card()
        }
    }
}

// MARK: - Late Start T20

enum TimingStatus {
    case good, tight, fail
    var color: Color {
        switch self {
        case .good: return AppTheme.success
        case .tight: return AppTheme.warning
        case .fail: return AppTheme.destructive
        }
    }
    var text: String {
        switch self {
        case .good:  return "Fits within the window"
        case .tight: return "Exactly at the limit"
        case .fail:  return "Cannot complete in time"
        }
    }
    var icon: String {
        switch self {
        case .good:  return "checkmark.circle.fill"
        case .tight: return "exclamationmark.triangle.fill"
        case .fail:  return "xmark.circle.fill"
        }
    }
}

struct LateStartT20View: View {
    @EnvironmentObject var ms: MatchState
    
    // Match window comes from the selected competition rules, not user input.
    private var maxDuration: Int { ms.rules.lateStartMaxWindow ?? 165 }
    @State private var minOvers: Int = 5
    @State private var intervalMin: Int = 10
    
    // CA WBBL-specific Latest Start interpretation: five overs per side
    // require 18 minutes each, plus the applicable reduced interval.
    // Do not apply this exception to BBL or other WBBL calculations.
    private var inningsSeconds: Int {
        EqualOversCalculator.minimumInningsSeconds(competition: ms.competition, rules: ms.rules, minOvers: minOvers)
    }
    private var totalRequiredSeconds: Int { inningsSeconds * 2 + intervalMin * 60 }
    private var totalRequired: Int { Int(ceil(Double(totalRequiredSeconds) / 60.0)) }
    private var canFit: Bool { totalRequiredSeconds <= maxDuration * 60 }
    private var latestFinish: Date { TU.addMin(ms.gameStartTime, maxDuration) }
    private var exactLatestFirstBall: Date {
        latestFinish.addingTimeInterval(-Double(totalRequiredSeconds))
    }
    private var latestFirstBall: Date {
        // Never round a latest permissible start *later* than the cutoff permits.
        // WBBL five-over CA interpretation remains 18 + 10 + 18 minutes.
        EqualOversCalculator.latestFirstBall(cessation: latestFinish, inningsSeconds: inningsSeconds,
                                             intervalMinutes: intervalMin)
    }
    private var actualStartWithinLimit: Bool {
        canFit && ms.LS_actualStart <= latestFirstBall && ms.LS_actualStart >= ms.gameStartTime
    }
    private var actualDelayMinutes: Int {
        max(0, TU.minBetween(ms.gameStartTime, ms.LS_actualStart))
    }
    private var end1: Date { latestFirstBall.addingTimeInterval(Double(inningsSeconds)) }
    private var endInterval: Date { TU.addMin(end1, intervalMin) }
    private var end2: Date { endInterval.addingTimeInterval(Double(inningsSeconds)) }
    private var status: TimingStatus {
        if !canFit { return .fail }
        if totalRequiredSeconds == maxDuration * 60 { return .tight }
        return .good
    }
    
    private var segments: [TimelineSegment] {
        guard canFit else { return [] }
        var s: [TimelineSegment] = []
        let delay = TU.signedMinBetween(ms.gameStartTime, latestFirstBall)
        if delay > 0 {
            s.append(TimelineSegment(label: "Window", start: ms.gameStartTime,
                                     end: latestFirstBall, color: AppTheme.destructive, isDelay: true))
        }
        s.append(TimelineSegment(label: "1st", start: latestFirstBall,
                                 end: end1, color: AppTheme.hero, isDelay: false))
        s.append(TimelineSegment(label: "Int", start: end1,
                                 end: endInterval, color: AppTheme.warning, isDelay: false))
        s.append(TimelineSegment(label: "2nd", start: endInterval,
                                 end: end2, color: AppTheme.hero, isDelay: false))
        return s
    }
    
    var body: some View {
        ResponsiveLayout {
            VStack(spacing: 12) {
                TimeField(title: "Scheduled start", value: $ms.gameStartTime, showNow: false)
                TimeField(title: "Actual first ball", value: $ms.LS_actualStart, showNow: false)
                CessationTargetEditor().environmentObject(ms)
            }.card()
        } outputs: {
            if canFit {
                DualHeroCard(leftLabel: "Latest first ball",
                             leftValue: TU.shortTime(latestFirstBall),
                             rightLabel: "Latest finish",
                             rightValue: TU.shortTime(latestFinish),
                             tint: status == .tight ? AppTheme.warning : AppTheme.hero)
            } else {
                HeroCard(primaryLabel: "Status", primaryValue: "Cannot Fit",
                         secondaryLabel: "Required",
                         secondaryValue: "\(totalRequired) min (have \(maxDuration))",
                         tint: AppTheme.destructive)
            }
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Image(systemName: actualStartWithinLimit ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(actualStartWithinLimit ? AppTheme.hero : AppTheme.destructive)
                    Text(actualStartWithinLimit ? "Actual start meets minimum-match cutoff" : "Actual start is outside the permissible window")
                        .font(.callout.weight(.semibold))
                }
                StatRow(label: "Actual delay", value: "\(actualDelayMinutes) min")
                if canFit {
                    StatRow(label: "Latest permissible first ball", value: TU.shortTime(latestFirstBall))
                }
                Text("Minimum five-over eligibility only. Revised T20 overs and First Innings synchronization still require validation. The timeline depicts the latest permissible start, not the actual match.")
                    .font(.caption).foregroundStyle(.secondary)
            }.card()
            if canFit {
                TimelineBar(segments: segments, overallStart: ms.gameStartTime,
                            overallEnd: latestFinish, currentTime: ms.calculationClockTime).card()
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: status.icon).font(.title3).foregroundStyle(status.color)
                    Text(status.text).font(.callout.weight(.semibold))
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(status.color.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                SectionDivider()
                StatRow(label: "Minimum overs per side", value: "\(minOvers)")
                StatRow(label: "First innings", value: "\(inningsSeconds / 60) min \(inningsSeconds % 60) sec")
                StatRow(label: "Interval", value: "\(intervalMin) min")
                StatRow(label: "Second innings", value: "\(inningsSeconds / 60) min \(inningsSeconds % 60) sec")
                StatRow(label: "Total required", value: "\(totalRequired) min")
                if ms.competition == .wbbl && minOvers == 5 && intervalMin == 10 {
                    Text("WBBL Latest Start only: CA interpretation uses 18 + 10 + 18 = 46 minutes (CA WBBL Almanac 2026/27, p.47-48; the extra-over rule does not apply when setting a start time).")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if canFit {
                    SectionDivider()
                    StatDateRow(label: "1st innings end", date: end1)
                    StatDateRow(label: "Interval ends", date: endInterval)
                    StatDateRow(label: "2nd innings end", date: end2)
                }
            }.card()
        }
    }
}

// MARK: - First Innings

struct FirstInningsView: View {
    @EnvironmentObject var ms: MatchState
    /// Umpires carry the delay, not the iPad -- these get logged after the fact, so both default
    /// to "now" but are freely editable to the actual times the umpires came off/back on.
    @State private var delayLogStart: Date = Date()
    @State private var delayLogEnd: Date = Date()
    @State private var isProvisionalRestart = true
    private var lastLoggedDelayEnd: Date? { ms.firstInningsDelays.map(\.end).max() }
    
    // DatePicker displays only hour/minute, but its Date can retain a hidden
    // calendar day from an earlier session. Anchor both selections to the
    // scheduled match date before validating or storing the interruption.
    private func onMatchDate(_ time: Date) -> Date {
        let clock = Calendar.current.dateComponents([.hour, .minute], from: time)
        let day = Calendar.current.startOfDay(for: ms.gameStartTime)
        return Calendar.current.date(byAdding: DateComponents(hour: clock.hour ?? 0,
                                                              minute: clock.minute ?? 0),
                                     to: day) ?? time
    }
    private var normalizedDelayStart: Date { onMatchDate(delayLogStart) }
    private var normalizedDelayEnd: Date {
        let end = onMatchDate(delayLogEnd)
        // A clock time earlier than the off time is treated as the next day.
        // The innings-duration guard below rejects implausibly long entries.
        return end < normalizedDelayStart ? TU.addMin(end, 24 * 60) : end
    }
    private var proposedTimeInProgress: Int {
        max(0, TU.minBetween(ms.LS_actualStart, normalizedDelayStart) - ms.C_playingTimeLost)
    }
    private var validDelayLog: Bool {
        let duration = TU.signedMinBetween(normalizedDelayStart, normalizedDelayEnd)
        return duration > 0 && duration <= ms.A_netPlayingTime &&
        normalizedDelayStart >= ms.LS_actualStart &&
        (lastLoggedDelayEnd == nil || normalizedDelayStart >= lastLoggedDelayEnd!) &&
        proposedTimeInProgress <= ms.A_netPlayingTime / 2
    }
    private var logMinutes: Int { TU.minBetween(normalizedDelayStart, normalizedDelayEnd) }
    // Pure preview: never writes to MatchState, snapshots, or interruption history.
    private var provisionalPlan: EqualOversPlan? {
        guard validDelayLog else { return nil }
        let lost = max(0, TU.minBetween(ms.gameStartTime, ms.LS_actualStart)) + ms.C_playingTimeLost + logMinutes
        let interval = ms.rules.adjustedInterval(timeLost: lost)
        let intervalCredit = max(0, ms.rules.defaultIntervalMinutes - interval)
        let effective = max(0, lost - min(lost, ms.rules.extraTimeMinutes) - intervalCredit)   // PROPOSED FIX: rule-driven extra time
        let available = max(0, ms.A_netPlayingTime - effective)
        let raw = Double(available) / ms.rules.minutesPerOver
        let total = ms.competition.isT20 ? TU.round2(raw) : raw
        return EqualOversCalculator.plan(
            rules: ms.rules, originalStart: ms.gameStartTime,
            restart: normalizedDelayEnd, playedMinutes: proposedTimeInProgress,
            initialOvers: TU.ceilOv(total / 2.0), interval: interval,
            rescheduledCessation: ms.rescheduledCessationEnabled ? ms.rescheduledCessation : nil)
    }
    
    // PROPOSED FIX: show exactly the figures the plan uses (late start included).
    private var effectiveLost: Int { ms.firstInningsLoss.effective }
    private var remaining: Int { ms.firstInningsLoss.remaining }
    private var totalOvAll: Double { ms.firstInningsLoss.totalOvers }
    private var plan: EqualOversPlan { ms.firstInningsPlan }
    private var ovPerTeam: Int { plan.oversPerTeam }
    private var bowler: Int { ms.rules.maxOversPerBowler(teamOvers: ovPerTeam) }
    private var inningsLen: Int { plan.inningsMinutes }
    private var cease1: Date { plan.firstCessation }
    private var start2: Date { plan.secondStart }
    private var cease2: Date { plan.secondCessation }
    private var autoInterval: Int { ms.rules.adjustedInterval(timeLost: ms.C_playingTimeLost) }
    private var warnings: [ValidationWarning] { ms.firstInningsWarnings() }
    
    private var lossPresets: [Int] { ms.competition.isT20 ? [15,30,45,60] : [15,30,60,90] }
    private var progressPresets: [Int] { ms.competition.isT20 ? [20,40,60,80] : [60,120,180,240] }
    
    private var segments: [TimelineSegment] {
        let delays = ms.firstInningsDelays.sorted { $0.start < $1.start }
        guard !delays.isEmpty else {
            var items: [TimelineSegment] = []
            if ms.B_timeInProgress > 0 {
                items.append(TimelineSegment(label: "1st", start: ms.gameStartTime,
                                             end: TU.addMin(ms.gameStartTime, ms.B_timeInProgress),
                                             color: AppTheme.hero, isDelay: false))
            }
            if ms.C_playingTimeLost > 0 {
                items.append(TimelineSegment(label: "Rain", start: TU.addMin(ms.gameStartTime, ms.B_timeInProgress),
                                             end: ms.J_startOrRecommence, color: AppTheme.destructive, isDelay: true))
            }
            items.append(TimelineSegment(label: "1st", start: ms.J_startOrRecommence,
                                         end: cease1, color: AppTheme.hero, isDelay: false))
            items.append(TimelineSegment(label: "Int", start: cease1,
                                         end: start2, color: AppTheme.warning, isDelay: false))
            items.append(TimelineSegment(label: "2nd", start: start2,
                                         end: cease2, color: AppTheme.hero, isDelay: false))
            return items
        }
        var items: [TimelineSegment] = []
        if ms.LS_actualStart > ms.gameStartTime {
            items.append(TimelineSegment(label: "Late start", start: ms.gameStartTime,
                                         end: ms.LS_actualStart, color: AppTheme.destructive, isDelay: true))
        }
        var cursor = ms.LS_actualStart
        for (index, delay) in delays.enumerated() {
            if delay.start > cursor {
                items.append(TimelineSegment(label: "1st", start: cursor,
                                             end: delay.start, color: AppTheme.hero, isDelay: false))
            }
            items.append(TimelineSegment(label: "Rain \(index + 1)", start: delay.start,
                                         end: delay.end, color: AppTheme.destructive, isDelay: true))
            cursor = delay.end
        }
        items.append(TimelineSegment(label: "1st", start: cursor,
                                     end: cease1, color: AppTheme.hero, isDelay: false))
        items.append(TimelineSegment(label: "Int", start: cease1,
                                     end: start2, color: AppTheme.warning, isDelay: false))
        items.append(TimelineSegment(label: "2nd", start: start2,
                                     end: cease2, color: AppTheme.hero, isDelay: false))
        return items
    }
    
    var body: some View {
        ResponsiveLayout {
            VStack(spacing: 12) {
                ValidationBanner(warnings: warnings)
                CessationTargetEditor().environmentObject(ms)
                IntField(title: "Net playing time", value: $ms.A_netPlayingTime)
                IntField(title: "Time in progress (auto on Log Delay)", value: $ms.B_timeInProgress,
                         presets: progressPresets)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Playing time lost")
                        Spacer()
                        Text("\(ms.C_playingTimeLost) min")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Record a rain interruption", systemImage: "cloud.rain")
                            .font(.headline)
                        Text("Enter the times manually whenever convenient. You do not need to press anything when leaving or returning to the field.")
                            .font(.caption).foregroundStyle(.secondary)
                        TimeField(title: "Play stopped at", value: $delayLogStart)
                        Picker("Restart time type", selection: $isProvisionalRestart) {
                            Text("Expected (preview)").tag(true)
                            Text("Actual (record)").tag(false)
                        }
                        .pickerStyle(.segmented)
                        TimeField(title: isProvisionalRestart ? "Expected restart at" : "Actual restart at", value: $delayLogEnd)
                        HStack {
                            Text("Interruption duration")
                            Spacer()
                            Text("\(logMinutes) min").font(.headline.monospacedDigit())
                        }
                        .font(.subheadline)
                        if validDelayLog {
                            Text("Playing time before interruption: \(proposedTimeInProgress) min (automatic)")
                                .font(.caption).foregroundStyle(AppTheme.accent)
                        }
                        if isProvisionalRestart, let preview = provisionalPlan {
                            VStack(alignment: .leading, spacing: 6) {
                                Label("PROVISIONAL — NOT SAVED", systemImage: "eye")
                                    .font(.caption.weight(.bold))
                                Text("Projected overs per side: \(preview.oversPerTeam)")
                                    .font(.headline)
                                Text("Projected first innings cessation: \(TU.shortTime(preview.firstCessation))")
                                Text("Projected second innings start: \(TU.shortTime(preview.secondStart))")
                                Text("Projected match finish: \(TU.shortTime(preview.secondCessation))")
                                Text("Select Actual (record) after restart is confirmed. Previewing does not change the match.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                            .background(AppTheme.accent.opacity(0.10))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        Button {
                            // Calculate playing time before adding this delay to the
                            // cumulative lost minutes; then anchor the restart to its end.
                            let played = proposedTimeInProgress
                            let newLoss = ms.C_playingTimeLost + logMinutes
                            ms.B_timeInProgress = played
                            ms.C_playingTimeLost = newLoss
                            ms.J_startOrRecommence = normalizedDelayEnd
                            ms.updateIntervalIfNeeded()
                            ms.firstInningsDelays.append(InningsDelay(start: normalizedDelayStart, end: normalizedDelayEnd, allowanceMinutes: 0))
                            let now = ms.calculationClockTime
                            delayLogStart = now
                            delayLogEnd = now
                            isProvisionalRestart = true
                            Haptic.success()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "cloud.rain.fill")
                                Text("Add interruption to match (+\(logMinutes) min)").font(.callout.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(AppTheme.destructive)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .disabled(!validDelayLog || isProvisionalRestart)
                        .buttonStyle(.plain)
                        if !validDelayLog {
                            Text("Enter valid Off/On times after Game Start, without overlapping a previous interruption.")
                                .font(.caption).foregroundStyle(AppTheme.destructive)
                        }
                    }
                    .padding(10).background(AppTheme.destructive.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    
                    IntField(title: "Adjust lost time manually (override)", value: $ms.C_playingTimeLost,
                             presets: lossPresets)
                    .onChange(of: ms.C_playingTimeLost) { _, _ in
                        ms.updateIntervalIfNeeded()
                    }
                }
                
                IntField(title: "Extra time available", value: $ms.D_extraTimeAvail,
                         presets: ms.rules.extraTimeMinutes > 0
                         ? [0, 30, ms.rules.extraTimeMinutes] : nil)
                IntField(title: "Time from reduced interval",
                         value: $ms.E_timeFromReducedInterval)
                SectionDivider()
                TimeField(title: "Start / recommence", value: $ms.J_startOrRecommence)
                HStack {
                    Text("Interval")
                    Spacer()
                    Text("\(ms.M_intervalLength) min")
                        .font(.system(.body, design: .rounded).weight(.medium))
                    if autoInterval != ms.rules.defaultIntervalMinutes {
                        Text("auto").font(.caption2)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(AppTheme.accent.opacity(0.2))
                            .foregroundStyle(AppTheme.accent).clipShape(Capsule())
                    }
                }
            }
            .card()
        } outputs: {
            DualHeroCard(leftLabel: "Overs/team", leftValue: "\(ovPerTeam)",
                         rightLabel: "1st cease", rightValue: TU.shortTime(cease1))
            ValidMatchBadge(overs: ovPerTeam,
                            minimum: ms.isFinal ? ms.rules.minValidOversFinal : ms.rules.minValidOvers)
            TimelineBar(segments: segments, overallStart: ms.gameStartTime,
                        overallEnd: cease2, currentTime: ms.calculationClockTime).card()
            VStack(alignment: .leading, spacing: 10) {
                StatRow(label: "Effective time lost", value: "\(effectiveLost) min")
                StatRow(label: "Remaining time", value: "\(remaining) min")
                StatRow(label: "Total overs (both)", value: TU.fmt2(totalOvAll))
                StatRow(label: "Max per bowler", value: "\(bowler)")
                if let co = ms.rules.cutoffMinutes(for: ovPerTeam) {
                    StatRow(label: "Scheduled last-over offset", value: "\(co) min")
                }
                SectionDivider()
                PowerplayDisplay(competition: ms.competition, rules: ms.rules, overs: ovPerTeam)
                SectionDivider()
                StatRow(label: "Innings length", value: "\(inningsLen) min")
                StatDateRow(label: "2nd innings start", date: start2)
                StatDateRow(label: "2nd innings cease", date: cease2)
            }.card()
        }
    }
    
    private func recalcJ() {
        ms.J_startOrRecommence = TU.addMin(ms.gameStartTime,
                                           ms.B_timeInProgress + ms.C_playingTimeLost)
    }
}

// MARK: - Termination Check

struct TerminationCheckView: View {
    @EnvironmentObject var ms: MatchState
    @State private var prevShouldContinue: Bool = true
    
    private var gap: Int { TU.minBetween(ms.P_proposedRestart, ms.Q_rescheduledCutoff) }
    private var rawPotential: Double {
        Double(gap) / ms.rules.minutesPerOver
    }
    private var potential: Int { ms.rules.roundTermination(rawPotential) }
    // BBL/WBBL Appendix J compares S (unrounded) with T; ODC/WNCL
    // explicitly round potential overs upwards before comparing.
    private var shouldContinue: Bool {
        ms.competition.isT20 ? rawPotential > Double(ms.T_completeOversFaced)
        : potential > ms.T_completeOversFaced
    }
    private var warnings: [ValidationWarning] { ms.terminationWarnings() }
    private var hasBlockingWarnings: Bool { warnings.contains { $0.severity == .error } }
    
    var body: some View {
        ResponsiveLayout {
            VStack(spacing: 12) {
                ValidationBanner(warnings: warnings)
                TimeField(title: "Proposed restart", value: $ms.P_proposedRestart)
                TimeField(title: "Rescheduled cut-off", value: $ms.Q_rescheduledCutoff)
                IntField(title: "Complete overs faced",
                         value: $ms.T_completeOversFaced,
                         hi: ms.rules.maxOversPerTeam, suffix: "ov",
                         presets: ms.competition.isT20 ? [5,10,15] : [10,20,30,40])
            }.card()
        } outputs: {
            // The highest-stakes call in the app -- deliberately oversized and unmistakable
            // at a glance, not just another HeroCard.
            VStack(spacing: 10) {
                Image(systemName: hasBlockingWarnings ? "exclamationmark.triangle.fill" : (shouldContinue ? "checkmark.circle.fill" : "xmark.octagon.fill"))
                    .font(.system(size: 56))
                    .foregroundStyle(.white)
                Text(hasBlockingWarnings ? "CHECK INPUTS" : (shouldContinue ? "CONTINUE" : "TERMINATE"))
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(ms.competition.isT20 ? "\(TU.fmt2(rawPotential)) potential vs \(ms.T_completeOversFaced) ov faced" : "\(potential) ov potential vs \(ms.T_completeOversFaced) ov faced")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 28)
            .background(
                LinearGradient(
                    colors: [hasBlockingWarnings ? AppTheme.warning : (shouldContinue ? AppTheme.success : AppTheme.destructive),
                             (hasBlockingWarnings ? AppTheme.warning : (shouldContinue ? AppTheme.success : AppTheme.destructive)).opacity(0.8)],
                    startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .shadow(color: (shouldContinue ? AppTheme.success : AppTheme.destructive).opacity(0.35),
                    radius: 16, x: 0, y: 8)
            VStack(alignment: .leading, spacing: 10) {
                Text("WORKING (PC J.1.2)").font(.caption.weight(.bold))
                    .foregroundStyle(.secondary).tracking(1)
                StatRow(label: "Minutes available", value: "\(gap) min")
                StatRow(label: "Divided by \(TU.fmt2(ms.rules.minutesPerOver)) min/ov",
                        value: TU.fmt2(Double(gap) / ms.rules.minutesPerOver))
                StatRow(label: "Potential overs (\(ms.rules.terminationRounding == .floor ? "floor" : "ceil"))",
                        value: "\(potential)")
                StatRow(label: "Overs faced", value: "\(ms.T_completeOversFaced)")
                SectionDivider()
                Text(hasBlockingWarnings ? "Correct the invalid inputs before using a termination recommendation."
                     : (shouldContinue ? "Potential overs exceed overs faced: CONTINUE"
                        : "Potential overs do not exceed overs faced: TERMINATE"))
                .font(.caption).foregroundStyle(.secondary)
            }.card()
        }
        .onChange(of: shouldContinue) { _, newVal in
            if newVal != prevShouldContinue {
                newVal ? Haptic.success() : Haptic.error()
                prevShouldContinue = newVal
            }
        }
        .onAppear { prevShouldContinue = shouldContinue }
    }
}

// MARK: - Second Innings Start

struct SecondInningsStartView: View {
    @EnvironmentObject var ms: MatchState
    
    private var len: Int { TU.ceilMin(Double(ms.A2_maxOvers) * ms.rules.minutesPerOver) }
    private var cessation: Date { TU.addMin(ms.C2_startTime, len) }
    private var bowler: Int { ms.rules.maxOversPerBowler(teamOvers: ms.A2_maxOvers) }
    
    var body: some View {
        ResponsiveLayout {
            VStack(spacing: 12) {
                IntField(title: "Max overs", value: $ms.A2_maxOvers,
                         lo: 5, hi: ms.rules.maxOversPerTeam, suffix: "ov")
                TimeField(title: "Start time", value: $ms.C2_startTime)
            }.card()
        } outputs: {
            DualHeroCard(leftLabel: "Max overs", leftValue: "\(ms.A2_maxOvers)",
                         rightLabel: "Cessation", rightValue: TU.shortTime(cessation))
            ValidMatchBadge(overs: ms.A2_maxOvers,
                            minimum: ms.isFinal ? ms.rules.minValidOversFinal : ms.rules.minValidOvers)
            VStack(alignment: .leading, spacing: 10) {
                StatRow(label: "Scheduled length", value: "\(len) min")
                StatRow(label: "Max per bowler", value: "\(bowler)")
                if let co = ms.rules.cutoffMinutes(for: ms.A2_maxOvers) {
                    StatRow(label: "Scheduled last-over offset", value: "\(co) min")
                }
                SectionDivider()
                PowerplayDisplay(competition: ms.competition, rules: ms.rules, overs: ms.A2_maxOvers)
            }.card()
        }
    }
}

// MARK: - Appendix J second-innings worksheet (auditable intermediate steps)
// One worksheet is recalculated from the ORIGINAL second-innings allocation,
// with cumulative, non-overlapping stoppages. Never repeatedly subtract a
// rounded overs-loss from an already reduced allocation.
struct SecondInningsWorksheet {
    let elapsedPlayingMinutes: Int    // C: actual playing time, excluding stoppages
    let interruptionMinutes: Int     // E: all recorded stoppages
    let allowanceMinutes: Int        // F: allowances actually used
    let netLostMinutes: Int          // G: E - F
    let oversLost: Int               // I: floor(G / minutes per over)
    let revisedOvers: Int            // J: H - I
    let scheduledMinutes: Int        // K: ceil(J * minutes per over)
    let revisedCessation: Date       // L: restart + (K - C)
    let exceedsCompletedOvers: Bool
    
    // PROPOSED FIX (defects 3 and 8; CA Appendix J 1.4 step F and cl. 13.7.2.2.2):
    //  - extra time is ONE match-wide pool (WNCL cl. 12.7.1), applied automatically and reduced by what
    //    the first innings (and any late start) already used -- "any UNUSED provision for Extra Time";
    //  - time gained because the second innings started earlier than scheduled is credited in EVERY
    //    competition (previously capped at the extra-time pool, so it was discarded for ODC/BBL/WBBL).
    static func calculate(rules: CompRules, inningsStart: Date, restart: Date,
                          initialOvers: Int, delays: [InningsDelay],
                          completedOvers: Int, completedBalls: Int,
                          extraTimeAlreadyUsed: Int = 0, earlyStartCredit: Int = 0) -> SecondInningsWorksheet {
        let ordered = delays.sorted { $0.start < $1.start }
        let duration = ordered.reduce(0) { $0 + $1.duration }
        let extraAvailable = max(0, rules.extraTimeMinutes - max(0, extraTimeAlreadyUsed))
        let extraApplied = min(duration, extraAvailable)
        let credit = min(max(0, duration - extraApplied), max(0, earlyStartCredit))
        let allowances = extraApplied + credit
        let net = max(0, duration - allowances)
        let played = max(0, TU.minBetween(inningsStart, restart) - duration)
        let lostOvers = rules.roundOversLost(Double(net) / rules.minutesPerOver)
        let revised = max(0, min(rules.maxOversPerTeam, initialOvers) - lostOvers)
        let usedOvers = max(0, completedOvers) + (completedBalls > 0 ? 1 : 0)
        let minutes = TU.ceilMin(Double(revised) * rules.minutesPerOver)
        return SecondInningsWorksheet(elapsedPlayingMinutes: played,
                                      interruptionMinutes: duration, allowanceMinutes: allowances,
                                      netLostMinutes: net, oversLost: lostOvers, revisedOvers: revised,
                                      scheduledMinutes: minutes,
                                      revisedCessation: TU.addMin(restart, max(0, minutes - played)),
                                      exceedsCompletedOvers: revised < usedOvers)
    }
}

// MARK: - Second Innings Interruption

struct SecondInningsInterruptionView: View {
    @EnvironmentObject var ms: MatchState
    
    // The latest restart and every previous interruption are represented in
    // one worksheet. When the log is empty, use the single interruption fields.
    private var effectiveDelays: [InningsDelay] {
        if !ms.secondInningsDelays.isEmpty { return ms.secondInningsDelays }
        return [InningsDelay(start: ms.B3_startOfInterruption,
                             end: ms.D3_restartTime,
                             allowanceMinutes: 0)]
    }
    private var worksheet: SecondInningsWorksheet {
        SecondInningsWorksheet.calculate(rules: ms.rules,
                                         inningsStart: ms.A3_startOfInnings,
                                         restart: ms.D3_restartTime,
                                         initialOvers: ms.H_maxOversAtStart,
                                         delays: effectiveDelays,
                                         completedOvers: ms.secondInningsCompletedOvers,
                                         completedBalls: ms.secondInningsCompletedBalls,
                                         extraTimeAlreadyUsed: ms.firstInningsLoss.extraApplied,
                                         earlyStartCredit: ms.F3_additionalTimeAvail)
    }
    private var inProgress: Int { worksheet.elapsedPlayingMinutes }
    private var interruptLen: Int { TU.minBetween(ms.B3_startOfInterruption, ms.D3_restartTime) }
    private var timeLost: Int { worksheet.netLostMinutes }
    private var oversLost: Int { worksheet.oversLost }
    private var adjOvers: Int { worksheet.revisedOvers }
    private var newLen: Int { worksheet.scheduledMinutes }
    private var cessation: Date { worksheet.revisedCessation }
    private var bowler: Int { ms.rules.maxOversPerBowler(teamOvers: adjOvers) }
    private var warnings: [ValidationWarning] { ms.secondInningsInterruptionWarnings() }
    
    private var hasBlockingErrors: Bool {
        warnings.contains { $0.severity == .error }
    }
    
    // Draw every logged stoppage in chronological order. Only the current
    // interruption is used when no delay log exists.
    private var segments: [TimelineSegment] {
        let ordered = effectiveDelays.sorted { $0.start < $1.start }
        var result: [TimelineSegment] = []
        var cursor = ms.A3_startOfInnings
        for (index, delay) in ordered.enumerated() {
            if delay.start > cursor {
                result.append(TimelineSegment(label: index == 0 ? "Pre" : "Play",
                                              start: cursor, end: delay.start, color: AppTheme.hero, isDelay: false))
            }
            if delay.end > delay.start {
                result.append(TimelineSegment(label: "Rain \(index + 1)",
                                              start: delay.start, end: delay.end,
                                              color: AppTheme.destructive, isDelay: true))
            }
            cursor = max(cursor, delay.end)
        }
        if cessation > cursor {
            result.append(TimelineSegment(label: "Resume", start: cursor,
                                          end: cessation, color: AppTheme.hero, isDelay: false))
        }
        return result
    }
    
    var body: some View {
        ResponsiveLayout {
            VStack(spacing: 12) {
                ValidationBanner(warnings: warnings)
                IntField(title: "Max overs at start", value: $ms.H_maxOversAtStart,
                         lo: 5, hi: ms.rules.maxOversPerTeam, suffix: "ov")
                TimeField(title: "Innings start", value: $ms.A3_startOfInnings)
                IntField(title: "Completed legal overs", value: $ms.secondInningsCompletedOvers,
                         lo: 0, hi: ms.rules.maxOversPerTeam, suffix: "ov")
                IntField(title: "Balls in current over", value: $ms.secondInningsCompletedBalls,
                         lo: 0, hi: 5, suffix: "balls")
                TimeField(title: "Interruption start", value: $ms.B3_startOfInterruption)
                TimeField(title: "Restart time", value: $ms.D3_restartTime)
                // PROPOSED: always visible. Early-start credit (App. J 1.4 step F / cl. 13.7.2.2.2):
                // minutes by which the second innings started earlier than scheduled. Extra time (WNCL)
                // is applied automatically and is NOT entered here.
                IntField(title: "Early-start credit (min)", value: $ms.F3_additionalTimeAvail)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Multiple interruptions").font(.headline)
                    Text("Log each stoppage with its actual start and restart. Logged entries replace the single-delay loss in the revised-over calculation. WNCL extra time is applied automatically (the unused part of the 60 minutes); enter any early-start credit above.")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(ms.secondInningsDelays) { entry in
                        HStack {
                            VStack(alignment: .leading) {
                                Text("\(TU.shortTime(entry.start)) – \(TU.shortTime(entry.end))")
                                Text("\(entry.duration) min")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                ms.secondInningsDelays.removeAll { $0.id == entry.id }
                            } label: { Image(systemName: "trash") }
                        }
                    }
                    Button("Add current interruption to log") {
                        guard ms.D3_restartTime > ms.B3_startOfInterruption else { return }
                        // PROPOSED: credit/extra time are now match-level (see worksheet), not per stoppage.
                        let entry = InningsDelay(start: ms.B3_startOfInterruption,
                                                 end: ms.D3_restartTime,
                                                 allowanceMinutes: 0)
                        let overlaps = ms.secondInningsDelays.contains {
                            entry.start < $0.end && entry.end > $0.start
                        }
                        if !overlaps && entry.start >= ms.A3_startOfInnings {
                            ms.secondInningsDelays.append(entry)
                        }
                    }
                    .disabled(ms.D3_restartTime <= ms.B3_startOfInterruption ||
                              ms.B3_startOfInterruption < ms.A3_startOfInnings ||
                              ms.secondInningsDelays.contains {
                        ms.B3_startOfInterruption < $0.end && ms.D3_restartTime > $0.start
                    })
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.accent)
                    if !ms.secondInningsDelays.isEmpty {
                        Text("Enter the latest restart above. Avoid overlapping entries. Delete an entry to correct it.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.card()
        } outputs: {
            if hasBlockingErrors {
                VStack(alignment: .leading, spacing: 10) {
                    Label("CALCULATION BLOCKED", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(AppTheme.destructive)
                    Text("Invalid second-innings entries have been detected. Revised overs, cessation, bowling limits, powerplays and the projected timeline are hidden until all errors are corrected.")
                        .font(.callout)
                    Text("Review the validation messages above, then correct or delete the affected interruption.")
                        .font(.caption).foregroundStyle(.secondary)
                }.card()
            } else {
                DualHeroCard(leftLabel: "Revised overs (J)", leftValue: "\(adjOvers)",
                             rightLabel: "Projected cease", rightValue: TU.shortTime(cessation),
                             tint: oversLost > 0 ? AppTheme.warning : AppTheme.hero)
                ValidMatchBadge(overs: adjOvers,
                                minimum: ms.isFinal ? ms.rules.minValidOversFinal : ms.rules.minValidOvers)
                TimelineBar(segments: segments,
                            overallStart: ms.A3_startOfInnings,
                            overallEnd: cessation, currentTime: ms.calculationClockTime).card()
                VStack(alignment: .leading, spacing: 10) {
                    StatRow(label: "Actual playing time before latest interruption", value: "\(inProgress) min")
                    StatRow(label: "Completed legal overs", value: "\(ms.secondInningsCompletedOvers).\(ms.secondInningsCompletedBalls)")
                    StatRow(label: "Interruption", value: "\(interruptLen) min")
                    StatRow(label: "Time lost", value: "\(timeLost) min")
                    StatRow(label: "Overs lost (I)", value: "\(oversLost)")
                    if !ms.secondInningsDelays.isEmpty {
                        StatRow(label: "Logged stoppages", value: "\(ms.secondInningsDelays.count)")
                    }
                    StatRow(label: "Rescheduled length", value: "\(newLen) min")
                    if !ms.secondInningsDelays.isEmpty {
                        Text("This is a provisional projection. Playing time excludes logged stoppages; confirm the applicable revised cessation and allowances with match officials.")
                            .font(.caption).foregroundStyle(AppTheme.warning)
                    }
                    StatRow(label: "Max per bowler", value: "\(bowler)")
                    if let co = ms.rules.cutoffMinutes(for: adjOvers) {
                        StatRow(label: "Scheduled last-over offset", value: "\(co) min")
                    }
                    SectionDivider()
                    PowerplayDisplay(competition: ms.competition, rules: ms.rules, overs: adjOvers)
                }.card()
            }
        }
    }
}

// MARK: - Powerplay Helper

struct PowerplayHelperView: View {
    @EnvironmentObject var ms: MatchState
    @State private var overs: Int = 50
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                IntField(title: "Total innings overs", value: $overs,
                         lo: 5, hi: ms.rules.maxOversPerTeam, suffix: "ov").card()
                
                if ms.competition == .t20i {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("ICC T20I Powerplay Table (PC 28.7.6)").font(.headline)
                        Text("Powerplay length in overs.balls, e.g. 4.5 = 4 overs 5 balls. Two fielders outside the circle in the powerplay, up to five afterwards.")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach((5...20).reversed(), id: \.self) { ov in
                            let pp = ms.rules.t20iPowerplay(for: ov)
                            let isSelected = ov == overs
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("\(ov) ov")
                                        .font(.system(.callout, design: .monospaced)
                                            .weight(isSelected ? .bold : .regular))
                                        .frame(width: 50, alignment: .leading)
                                    Text("PP \(pp.overs).\(pp.balls)").frame(width: 80)
                                    Spacer()
                                }
                                Text(ms.rules.bowlingRestrictionText(for: ov))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6).padding(.horizontal, isSelected ? 8 : 0)
                            .background(isSelected ? AppTheme.accent.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            if ov > 5 { Divider().overlay(AppTheme.line) }
                        }
                    }.card()
                } else if ms.competition.isT20 {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("\(ms.competition.rawValue) PP & Surge (PC 28.7.4)").font(.headline)
                        ForEach((5...ms.rules.maxOversPerTeam).reversed(), id: \.self) { ov in
                            let info = ms.rules.powerplayInfo(for: ov)
                            let isSelected = ov == overs
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("\(ov) ov")
                                        .font(.system(.callout, design: .monospaced)
                                            .weight(isSelected ? .bold : .regular))
                                        .frame(width: 50, alignment: .leading)
                                    Text("PP \(info.powerplayOvers)").frame(width: 50)
                                    if info.hasSurge,
                                       let s = info.surgeWindowStart,
                                       let e = info.surgeWindowEnd {
                                        Text("Surge \(info.surgeOvers) (ov \(s)-\(e))").font(.callout)
                                    } else {
                                        Text("No Surge").font(.callout).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                Text(ms.rules.bowlingRestrictionText(for: ov))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 6).padding(.horizontal, isSelected ? 8 : 0)
                            .background(isSelected ? AppTheme.accent.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            if ov > 5 { Divider().overlay(AppTheme.line) }
                        }
                    }.card()
                } else if ms.competition == .wncl {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WNCL Powerplay Table (PC 28.7.4)").font(.headline)
                        HStack {
                            Text("Ov").font(.caption.weight(.bold)).frame(width: 36)
                            Text("PP").font(.caption.weight(.bold)).frame(width: 36)
                            Text("Non-PP").font(.caption.weight(.bold)).frame(width: 60)
                            Text("Bowler").font(.caption.weight(.bold)).frame(width: 56)
                            Spacer()
                        }.foregroundStyle(.secondary)
                        Divider().overlay(AppTheme.line)
                        ForEach(stride(from: 50, through: 15, by: -1).map { $0 }, id: \.self) { ov in
                            let pp = ms.rules.wnclPowerplay(for: ov)
                            let isSelected = ov == overs
                            HStack {
                                Text("\(ov)").font(.system(.callout, design: .monospaced)
                                    .weight(isSelected ? .bold : .regular)).frame(width: 36)
                                Text("\(pp.pp)").frame(width: 36)
                                Text("\(pp.nonPp)").frame(width: 60)
                                Text("\(pp.maxBowler)").frame(width: 56)
                                Spacer()
                            }
                            .padding(.vertical, 5).padding(.horizontal, isSelected ? 8 : 0)
                            .background(isSelected ? AppTheme.accent.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            if ov > 15 { Divider().overlay(AppTheme.line) }
                        }
                    }.card()
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(ms.competition == .odi ? "ICC ODI Powerplay Table (PC 28.7.2.3)" : "ODC Powerplay Table (PC 28.7.3)").font(.headline)
                        HStack {
                            Text("Ov").font(.caption.weight(.bold)).frame(width: 36)
                            Text("P1").font(.caption.weight(.bold)).frame(width: 36)
                            Text("P2").font(.caption.weight(.bold)).frame(width: 36)
                            Text("P3").font(.caption.weight(.bold)).frame(width: 36)
                            Spacer()
                        }.foregroundStyle(.secondary)
                        Divider().overlay(AppTheme.line)
                        ForEach(stride(from: 50, through: (ms.competition == .odi ? 20 : 15), by: -1).map { $0 }, id: \.self) { ov in
                            let pp = ms.rules.odcPowerplays(for: ov)
                            let isSelected = ov == overs
                            HStack {
                                Text("\(ov)").font(.system(.callout, design: .monospaced)
                                    .weight(isSelected ? .bold : .regular)).frame(width: 36)
                                Text("\(pp.0)").frame(width: 36)
                                Text("\(pp.1)").frame(width: 36)
                                Text("\(pp.2)").frame(width: 36)
                                Spacer()
                            }
                            .padding(.vertical, 5).padding(.horizontal, isSelected ? 8 : 0)
                            .background(isSelected ? AppTheme.accent.opacity(0.12) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            if ov > (ms.competition == .odi ? 20 : 15) { Divider().overlay(AppTheme.line) }
                        }
                        SectionDivider()
                        StatRow(label: "Max per bowler",
                                value: "\(ms.rules.maxOversPerBowler(teamOvers: overs))")
                    }.card()
                }
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
        }
        .onAppear { overs = ms.rules.maxOversPerTeam }
        .onChange(of: ms.competition) { _, _ in overs = ms.rules.maxOversPerTeam }
    }
}

// MARK: - Snapshots Sheet

struct SnapshotsSheet: View {
    @EnvironmentObject var ms: MatchState
    @Environment(\.dismiss) private var dismiss
    @State private var newLabel: String = ""
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Save current state").font(.headline)
                        HStack {
                            TextField("Label (e.g. Before rain)", text: $newLabel)
                                .textFieldStyle(.roundedBorder)
                            Button("Save") {
                                ms.captureSnapshot(label: newLabel.isEmpty
                                                   ? "Snapshot \(ms.snapshots.count + 1)" : newLabel)
                                newLabel = ""
                            }
                            .buttonStyle(.borderedProminent).tint(AppTheme.accent)
                        }
                        Text("Saves all inputs. Compare what-if scenarios by restoring. Max 10 kept.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.card()
                    
                    if ms.snapshots.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.on.rectangle")
                                .font(.system(size: 40)).foregroundStyle(.secondary)
                            Text("No snapshots yet").foregroundStyle(.secondary)
                        }.padding(30)
                    } else {
                        ForEach(ms.snapshots) { s in
                            SnapshotRow(snapshot: s).environmentObject(ms)
                        }
                    }
                }.padding()
            }
            .navigationTitle("Scenarios").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct SnapshotRow: View {
    @EnvironmentObject var ms: MatchState
    let snapshot: Snapshot
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(snapshot.label).font(.headline)
                Spacer()
                Text(TU.shortTime(snapshot.createdAt))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 14) {
                chip("Lost", "\(snapshot.C_playingTimeLost)m")
                chip("Int", "\(snapshot.M_intervalLength)m")
                chip("Overs", "\(snapshot.A2_maxOvers)")
            }
            if snapshot.firstInningsDelays == nil || snapshot.secondInningsDelays == nil {
                Text("Legacy scenario: missing delay records; restore unavailable. Save a new scenario.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Button {
                    ms.restoreSnapshot(snapshot)
                } label: {
                    Label("Restore", systemImage: "arrow.uturn.backward")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(AppTheme.accent).foregroundStyle(.white)
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
                    .disabled(snapshot.firstInningsDelays == nil || snapshot.secondInningsDelays == nil)
                    .opacity(snapshot.firstInningsDelays == nil ? 0.4 : 1)
                Button { ms.deleteSnapshot(snapshot) } label: {
                    Label("Delete", systemImage: "trash")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(AppTheme.destructive.opacity(0.15))
                        .foregroundStyle(AppTheme.destructive)
                        .clipShape(Capsule())
                }.buttonStyle(.plain)
                Spacer()
            }
        }.card()
    }
    
    private func chip(_ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.caption.monospaced().weight(.semibold))
        }
    }
}

// MARK: - Match History Sheet

struct MatchHistorySheet: View {
    @EnvironmentObject var ms: MatchState
    @Environment(\.dismiss) private var dismiss
    @State private var selected: MatchRecord? = nil
    
    var body: some View {
        NavigationView {
            Group {
                if ms.matchHistory.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "book.closed")
                            .font(.system(size: 44)).foregroundStyle(.secondary)
                        Text("No match history yet")
                            .foregroundStyle(.secondary)
                        Text("Tap \"Save to History\" after completing a calculation.")
                            .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }.padding(40)
                } else {
                    List {
                        ForEach(ms.matchHistory) { rec in
                            Button { selected = rec } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text(rec.competition)
                                            .font(.callout.weight(.semibold))
                                        if rec.isFinal {
                                            Text("Final").font(.caption2.weight(.bold))
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(AppTheme.accent.opacity(0.2))
                                                .foregroundStyle(AppTheme.accent)
                                                .clipShape(Capsule())
                                        }
                                        Spacer()
                                        Text(TU.shortDateTime(rec.date))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    if !rec.teamA.isEmpty || !rec.teamB.isEmpty {
                                        Text("\(rec.teamA) v \(rec.teamB)")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    if !rec.venue.isEmpty {
                                        Text(rec.venue).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete { idx in
                            idx.forEach { ms.matchHistory.remove(at: $0) }
                        }
                    }
                }
            }
            .navigationTitle("Match History")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    if !ms.matchHistory.isEmpty {
                        EditButton()
                    }
                }
            }
            .sheet(item: $selected) { rec in
                HistoryDetailSheet(record: rec)
            }
        }
    }
}

struct HistoryDetailSheet: View {
    let record: MatchRecord
    @Environment(\.dismiss) private var dismiss
    @State private var showShare = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.competition).font(.title2.weight(.bold))
                        if !record.teamA.isEmpty || !record.teamB.isEmpty {
                            Text("\(record.teamA) v \(record.teamB)")
                                .font(.headline).foregroundStyle(.secondary)
                        }
                        if !record.venue.isEmpty {
                            Label(record.venue, systemImage: "mappin").font(.callout).foregroundStyle(.secondary)
                        }
                        Text(TU.shortDateTime(record.date)).font(.caption).foregroundStyle(.secondary)
                    }.card()
                    
                    Text(record.summary)
                        .font(.system(.body, design: .monospaced))
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(AppTheme.panelAlt)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding()
            }
            .navigationTitle("Match Summary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showShare = true
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
            .sheet(isPresented: $showShare) {
                ShareSheet(items: [record.summary])
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

// MARK: - Playing Conditions PDF (bundled resource, no network/Drive dependency)

/// Wraps QLPreviewController so a bundled PDF opens in-app. Nobody needs Google Drive access --
/// add the PDF to this project's target resources and it's available to every install.
struct PDFPreviewSheet: UIViewControllerRepresentable {
    let fileURL: URL
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ vc: QLPreviewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(fileURL: fileURL) }
    
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let fileURL: URL
        init(fileURL: URL) { self.fileURL = fileURL }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            fileURL as NSURL
        }
    }
}

/// A tappable label that opens a competition's Playing Conditions PDF from the app bundle.
/// Falls back to an explanatory alert (not a dead link) if the PDF hasn't been bundled yet.
struct PDFOpenButton<Label: View>: View {
    let rules: CompRules
    /// Display name of the competition these Playing Conditions belong to (e.g. Competition.fullName),
    /// used only for the fallback alert's wording -- CompRules itself doesn't carry this.
    let competitionName: String
    @ViewBuilder var label: () -> Label
    @State private var showPreview = false
    @State private var showMissingAlert = false
    
    private var bundledURL: URL? {
        guard let name = rules.pdfFileName else { return nil }
        let base = (name as NSString).deletingPathExtension
        return Bundle.main.url(forResource: base, withExtension: "pdf")
    }
    
    var body: some View {
        Button {
            if bundledURL != nil { showPreview = true } else { showMissingAlert = true }
        } label: { label() }
            .buttonStyle(.plain)
            .sheet(isPresented: $showPreview) {
                if let url = bundledURL { PDFPreviewSheet(fileURL: url) }
            }
            .alert("Playing Conditions PDF", isPresented: $showMissingAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                if let name = rules.pdfFileName {
                    Text("Add \u{201C}\(name)\u{201D} to this project's target resources to enable in-app viewing -- no network needed once it's bundled.")
                } else {
                    Text("No source document has been bundled for \(competitionName) yet.")
                }
            }
    }
}

// MARK: - Match Context Sheet

// MARK: - Match Data (teams & venues per competition)

struct MatchData {
    
    // BBL 2024-25 (BBL|14)
    static let bblTeams = [
        "Adelaide Strikers",
        "Brisbane Heat",
        "Hobart Hurricanes",
        "Melbourne Renegades",
        "Melbourne Stars",
        "Perth Scorchers",
        "Sydney Sixers",
        "Sydney Thunder",
    ]
    
    static let bblVenues = [
        "Adelaide Oval, Adelaide",
        "Bellerive Oval, Hobart",
        "Brisbane Cricket Ground (The Gabba), Brisbane",
        "Docklands Stadium (Marvel Stadium), Melbourne",
        "GMHBA Stadium, Geelong",
        "International Sports Stadium, Coffs Harbour",
        "Manuka Oval, Canberra",
        "Melbourne Cricket Ground (MCG), Melbourne",
        "Perth Stadium (Optus Stadium), Perth",
        "Sydney Cricket Ground (SCG), Sydney",
        "Sydney Showground Stadium, Sydney",
    ]
    
    // WBBL 2025-26 (WBBL|11)
    static let wbblTeams = [
        "Adelaide Strikers Women",
        "Brisbane Heat Women",
        "Hobart Hurricanes Women",
        "Melbourne Renegades Women",
        "Melbourne Stars Women",
        "Perth Scorchers Women",
        "Sydney Sixers Women",
        "Sydney Thunder Women",
    ]
    
    static let wbblVenues = [
        "Adelaide Oval, Adelaide",
        "Allan Border Field, Brisbane",
        "Bellerive Oval, Hobart",
        "Drummoyne Oval, Sydney",
        "Junction Oval, Melbourne",
        "Karen Rolton Oval, Adelaide",
        "North Sydney Oval, Sydney",
        "WACA Ground, Perth",
    ]
    
    // ODC 2025-26 (six states)
    static let odcTeams = [
        "New South Wales Blues",
        "Queensland Bulls",
        "South Australia Redbacks",
        "Tasmania Tigers",
        "Victoria Bushrangers",
        "Western Australia Warriors",
    ]
    
    static let odcVenues = [
        "Adelaide Oval, Adelaide",
        "Allan Border Field, Brisbane",
        "Bellerive Oval, Hobart",
        "Cricket Central (Sydney Olympic Park), Sydney",
        "Junction Oval, Melbourne",
        "Karen Rolton Oval, Adelaide",
        "WACA Ground, Perth",
    ]
    
    // WNCL 2025-26 (seven teams)
    static let wnclTeams = [
        "ACT Meteors Women",
        "NSW Breakers Women",
        "Queensland Fire Women",
        "South Australia Women",
        "Tasmania Women",
        "Victoria Women",
        "Western Australia Women",
    ]
    
    static let wnclVenues = [
        "Allan Border Field, Brisbane",
        "Bellerive Oval, Hobart",
        "Cricket Central (Sydney Olympic Park), Sydney",
        "Junction Oval (CitiPower Centre), Melbourne",
        "Karen Rolton Oval, Adelaide",
        "Manuka Oval, Canberra",
        "WACA Ground, Perth",
    ]
    
    // ICC full-member men's teams.
    static let iccTeams = [
        "Afghanistan", "Australia", "Bangladesh", "England", "India", "Ireland",
        "New Zealand", "Pakistan", "South Africa", "Sri Lanka", "West Indies", "Zimbabwe",
    ]
    // Major Australian international grounds; confirm the venue name against the fixture.
    static let iccVenues = [
        "Adelaide Oval, Adelaide",
        "Bellerive Oval, Hobart",
        "Manuka Oval, Canberra",
        "Melbourne Cricket Ground, Melbourne",
        "Optus Stadium, Perth",
        "Sydney Cricket Ground, Sydney",
        "The Gabba, Brisbane",
    ]
    
    static func teams(for comp: Competition) -> [String] {
        switch comp {
        case .bbl:  return bblTeams
        case .wbbl: return wbblTeams
        case .odc:  return odcTeams
        case .wncl: return wnclTeams
        case .odi, .t20i: return iccTeams
        }
    }
    
    static func venues(for comp: Competition) -> [String] {
        switch comp {
        case .bbl:  return bblVenues
        case .wbbl: return wbblVenues
        case .odc:  return odcVenues
        case .wncl: return wnclVenues
        case .odi, .t20i: return iccVenues
        }
    }
}

// MARK: - Match Context Sheet

struct MatchContextSheet: View {
    @EnvironmentObject var ms: MatchState
    @Environment(\.dismiss) private var dismiss
    
    @State private var teamASearch: String = ""
    @State private var teamBSearch: String = ""
    @State private var venueSearch: String = ""
    @State private var showTeamAPicker = false
    @State private var showTeamBPicker = false
    @State private var showVenuePicker = false
    
    private var teams: [String] { MatchData.teams(for: ms.competition) }
    private var venues: [String] { MatchData.venues(for: ms.competition) }
    
    var body: some View {
        NavigationView {
            Form {
                // Team selection
                Section {
                    // Team A
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Team A").font(.caption).foregroundStyle(.secondary)
                        if ms.teamA.isEmpty {
                            Button {
                                showTeamAPicker = true
                            } label: {
                                HStack {
                                    Text("Select team...").foregroundStyle(.secondary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            HStack {
                                Text(ms.teamA)
                                Spacer()
                                Button {
                                    ms.teamA = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    
                    // Team B
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Team B").font(.caption).foregroundStyle(.secondary)
                        if ms.teamB.isEmpty {
                            Button {
                                showTeamBPicker = true
                            } label: {
                                HStack {
                                    Text("Select team...").foregroundStyle(.secondary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            HStack {
                                Text(ms.teamB)
                                Spacer()
                                Button {
                                    ms.teamB = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Teams")
                } footer: {
                    Text(ms.competition.isInternational ? "ICC full-member teams." : "2025-26 \(ms.competition.fullName) teams.")
                }
                
                // Venue selection
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Venue").font(.caption).foregroundStyle(.secondary)
                        if ms.venue.isEmpty {
                            Button {
                                showVenuePicker = true
                            } label: {
                                HStack {
                                    Text("Select venue...").foregroundStyle(.secondary)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        } else {
                            HStack {
                                Text(ms.venue)
                                Spacer()
                                Button {
                                    ms.venue = ""
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Venue")
                } footer: {
                    Text(ms.competition.isInternational ? "Major Australian international grounds." : "2025-26 season \(ms.competition.rawValue) grounds.")
                }
                
                // ICC agreed extra time
                if ms.competition.isInternational {
                    Section {
                        Stepper(value: $ms.agreedExtraTime, in: 0...180, step: 5) {
                            Text("Extra time agreed: \(ms.agreedExtraTime) min")
                        }
                    } header: {
                        Text("Extra time (ICC)")
                    } footer: {
                        Text("Extra time exists only where the participating countries have agreed it (ODI PC 13.7.3: up to 90 min; T20I PC 13.7.3: no cap stated). Set 0 if none was agreed. It is used first, before any overs are lost. The Match Referee's discretion to shorten the interval (10 min minimum, PC 11.4) is not applied automatically.")
                    }
                }
                
                // Match type
                Section {
                    Toggle("This is a Final", isOn: $ms.isFinal)
                } header: {
                    Text("Match type")
                } footer: {
                    Text(ms.isFinal && ms.competition.isLimitedOvers
                         ? "Finals require minimum \(ms.rules.minValidOversFinal) overs for a valid match."
                         : "Regular matches require minimum \(ms.rules.minValidOvers) overs for a valid match.")
                }
                
                // Quick clear
                if !ms.teamA.isEmpty || !ms.teamB.isEmpty || !ms.venue.isEmpty {
                    Section {
                        Button(role: .destructive) {
                            ms.teamA = ""
                            ms.teamB = ""
                            ms.venue = ""
                            ms.isFinal = false
                        } label: {
                            Label("Clear match details", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Match Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $showTeamAPicker) {
                TeamPickerSheet(title: "Select Team A", teams: teams,
                                excludeTeam: ms.teamB) { picked in
                    ms.teamA = picked
                }
            }
            .sheet(isPresented: $showTeamBPicker) {
                TeamPickerSheet(title: "Select Team B", teams: teams,
                                excludeTeam: ms.teamA) { picked in
                    ms.teamB = picked
                }
            }
            .sheet(isPresented: $showVenuePicker) {
                VenuePickerSheet(venues: venues) { picked in
                    ms.venue = picked
                }
            }
        }
    }
}

// MARK: - Team Picker Sheet

struct TeamPickerSheet: View {
    let title: String
    let teams: [String]
    let excludeTeam: String
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    
    private var filtered: [String] {
        let available = teams.filter { $0 != excludeTeam }
        if search.isEmpty { return available }
        return available.filter { $0.localizedCaseInsensitiveContains(search) }
    }
    
    var body: some View {
        NavigationView {
            List(filtered, id: \.self) { team in
                Button {
                    onSelect(team)
                    dismiss()
                    Haptic.light()
                } label: {
                    HStack {
                        Text(team)
                            .foregroundStyle(.primary)
                        Spacer()
                        Image(systemName: "checkmark")
                            .font(.caption)
                            .foregroundStyle(AppTheme.accent)
                            .opacity(0)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search teams")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Venue Picker Sheet

struct VenuePickerSheet: View {
    let venues: [String]
    let onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    
    private var filtered: [String] {
        if search.isEmpty { return venues }
        return venues.filter { $0.localizedCaseInsensitiveContains(search) }
    }
    
    var body: some View {
        NavigationView {
            List(filtered, id: \.self) { venue in
                Button {
                    onSelect(venue)
                    dismiss()
                    Haptic.light()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        // Split "Ground Name, City" into two lines
                        let parts = venue.components(separatedBy: ", ")
                        Text(parts.first ?? venue)
                            .foregroundStyle(.primary)
                        if parts.count > 1 {
                            Text(parts.dropFirst().joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $search, prompt: "Search venues")
            .navigationTitle("Select Venue")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Cancel") { dismiss() } }
            }
        }
    }
}

// MARK: - Editable reference clock (not copied into match inputs)

struct CalculationClock: View {
    @EnvironmentObject var ms: MatchState
    
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "clock")
                .font(.caption)
                .foregroundStyle(.secondary)
            DatePicker("Calculation time", selection: $ms.calculationClockTime,
                       displayedComponents: [.hourAndMinute])
            .labelsHidden()
            .datePickerStyle(.compact)
            .font(.system(.caption, design: .monospaced).weight(.semibold))
            .accessibilityLabel("Calculation clock, editable")
            Button("Now") { ms.calculationClockTime = Date() }
                .font(.caption2.weight(.semibold))
                .buttonStyle(.borderless)
                .accessibilityLabel("Set calculation clock to current time")
        }
    }
}

// MARK: - Boundary Line Apps brand mark

/// If an image asset named "BoundaryLineLogo" is included, show the official logo.
/// Otherwise, use a crisp typographic mark; no replacement artwork is generated.
struct BoundaryLineBrandMark: View {
    var body: some View {
        Group {
            if UIImage(named: "BoundaryLineHeader") != nil {
                Image("BoundaryLineHeader")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 330)
                    .frame(height: 76)
                    .accessibilityLabel("Boundary Line Apps — Rain & Overs")
            } else {
                HStack(spacing: 10) {
                    Text("BL")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(AppTheme.gold)
                        .frame(width: 44, height: 44)
                        .background(AppTheme.charcoal, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 0) {
                            Text("BOUNDARY ")
                            Text("LINE").foregroundColor(AppTheme.gold)
                        }
                        .font(.system(size: 16, weight: .heavy, design: .rounded))
                        Text("RAIN & OVERS")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(1.4)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

// MARK: - Brand Header

struct BrandHeader: View {
    @EnvironmentObject var ms: MatchState
    @Binding var selectedComp: Competition
    @State private var showAbout = false
    @State private var showLibrary = false
    @State private var showSnapshots = false
    @State private var showMatch = false
    @State private var showShare = false
    @State private var showHistory = false
    @State private var showResetConfirm = false
    @State private var showMatchDetails = false
    @State private var showExitMatch = false
    @State private var shareText = ""
    
    /// Only the actions an umpire needs mid-match stay as visible icons; the rest live in "More".
    private var hasSavedExtras: Bool { !ms.snapshots.isEmpty || !ms.matchHistory.isEmpty }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Button { if ms.currentMatchHasUnsavedChanges { showExitMatch = true } else { ms.leaveMatch() } } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline.weight(.semibold))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to competition selection")
                .help("Back to home")
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 8) {
                        BoundaryLineBrandMark()
                        CalculationClock()
                    }
                    Group {
                        if !ms.teamA.isEmpty || !ms.teamB.isEmpty {
                            Text("\(ms.teamA) v \(ms.teamB)".trimmingCharacters(in: .whitespaces))
                        } else {
                            Text("Match-day calculations\(ms.isFinal ? " — Final" : "")")
                        }
                    }
                    .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                
                Button { showLibrary = true } label: {
                    Image(systemName: "books.vertical.fill").font(.title3)
                }
                .accessibilityLabel("Playing Conditions library")
                .help("Offline Playing Conditions")
                Menu {
                    Button { showMatch = true } label: {
                        Label("Match details", systemImage: "person.2.fill")
                    }
                    Button {
                        shareText = ms.generateSummary()
                        showShare = true
                    } label: {
                        Label("Share calculation summary", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        ms.saveCurrentMatch()
                    } label: {
                        Label("Save match", systemImage: "square.and.arrow.down")
                    }
                    Divider()
                    
                    Button { showSnapshots = true } label: {
                        Label("Scenarios (\(ms.snapshots.count))", systemImage: "camera.fill")
                    }
                    Button { showHistory = true } label: {
                        Label("Match History (\(ms.matchHistory.count))", systemImage: "book.closed.fill")
                    }
                    Divider()
                    Menu {
                        ForEach(MatchState.ThemePreference.allCases, id: \.self) { pref in
                            Button {
                                ms.themePreference = pref
                            } label: {
                                Label(pref.rawValue,
                                      systemImage: pref == ms.themePreference ? "checkmark" : "")
                            }
                        }
                    } label: {
                        Label("Appearance", systemImage: themeIcon)
                    }
                    Button { showLibrary = true } label: {
                        Label("Playing Conditions library", systemImage: "books.vertical.fill")
                    }
                    Button { showAbout = true } label: {
                        Label("About & Rules", systemImage: "info.circle")
                    }
                    Divider()
                    Button { if ms.currentMatchHasUnsavedChanges { showExitMatch = true } else { ms.leaveMatch() } } label: {
                        Label("Back to home / Change competition", systemImage: "house")
                    }
                    Button(role: .destructive) { showResetConfirm = true } label: {
                        Label("Reset current match", systemImage: "arrow.counterclockwise")
                    }
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "ellipsis.circle").font(.title3)
                        if hasSavedExtras {
                            Circle().fill(AppTheme.accent).frame(width: 8, height: 8)
                                .offset(x: 5, y: -3)
                        }
                    }
                }
                
            }
            
            VStack(spacing: 10) {
                HStack {
                    Label(ms.competition.fullName, systemImage: "lock.shield")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("Locked for this match")
                        .font(.caption).foregroundStyle(.secondary)
                }
                
                HStack {
                    Text("Game Start").foregroundStyle(.secondary)
                    Spacer()
                    DatePicker("", selection: $ms.gameStartTime, displayedComponents: [.hourAndMinute])
                        .labelsHidden().datePickerStyle(.compact).font(.title3)
                    
                }
                
                DisclosureGroup("Match details & rules", isExpanded: $showMatchDetails) {
                    VStack(spacing: 10) {
                        if let cutoff = ms.rules.cutoffMinutes(for: ms.rules.maxOversPerTeam) {
                            HStack {
                                Label("Original last-over target", systemImage: "flag.checkered")
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(TU.shortTime(TU.addMin(ms.gameStartTime, cutoff)))
                                    .font(.system(.callout, design: .monospaced))
                            }
                        }
                        
                        if !ms.rules.almanacVersion.isEmpty {
                            HStack {
                                Text("PC version").foregroundStyle(.secondary).font(.caption)
                                Spacer()
                                Text(ms.rules.almanacVersion).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        
                        PDFOpenButton(rules: ms.rules, competitionName: ms.competition.fullName) {
                            HStack {
                                Label("Playing Conditions PDF", systemImage: ms.rules.pdfFileName != nil ? "doc.text.fill" : "doc.text")
                                    .font(.caption)
                                Spacer()
                                Image(systemName: "arrow.up.right.square").font(.caption2)
                            }
                            .foregroundStyle(ms.rules.pdfFileName != nil ? AppTheme.accent : .secondary)
                        }
                    }
                    .padding(.top, 8)
                }
                .font(.subheadline)
            }
            .padding(12).background(AppTheme.panel)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.line, lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .sheet(isPresented: $showAbout) {
            AboutSheet(competition: ms.competition, rules: ms.rules)
        }
        .sheet(isPresented: $showLibrary) {
            PlayingConditionsLibrarySheet()
        }
        .sheet(isPresented: $showSnapshots) { SnapshotsSheet().environmentObject(ms) }
        .sheet(isPresented: $showMatch) { MatchContextSheet().environmentObject(ms) }
        .sheet(isPresented: $showShare) { ShareSheet(items: [shareText]) }
        .sheet(isPresented: $showHistory) { MatchHistorySheet().environmentObject(ms) }
        .confirmationDialog("Return to competition selection?", isPresented: $showExitMatch) {
            Button("Save and return") {
                ms.saveCurrentMatch()
                ms.leaveMatch()
            }
            Button("Discard changes and return") {
                if let id = ms.currentSavedMatchID, let saved = ms.snapshots.first(where: { $0.id == id }) { ms.restoreSnapshot(saved) }
                ms.leaveMatch()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You have unsaved changes. Save to update the resumable match, or discard changes and return home.")
        }
        .confirmationDialog(
            "Start a new match?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset match data", role: .destructive) { ms.resetAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This clears every time, over count and interruption entered for the current match. This can't be undone.")
        }
    }
    
    private var themeIcon: String {
        switch ms.themePreference {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max.fill"
        case .dark:   return "moon.fill"
        }
    }
}

// MARK: - Tab Bar

struct TabBar: View {
    @Binding var selection: Tab
    let competition: Competition
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(Tab.allCases, id: \.self) { tab in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { selection = tab }
                        Haptic.light()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(tab.rawValue)
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 9)
                        .background(selection == tab ? AppTheme.accent : Color.clear)
                        .foregroundStyle(selection == tab ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(selection == tab ? AppTheme.accent : AppTheme.line, lineWidth: 1))
                    }
                }
            }.padding(.horizontal, 20)
        }
    }
}

// MARK: - Offline Playing Conditions Library

struct PlayingConditionsLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label("Available offline", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    Text("Official documents packaged with the app. Check the edition before using a document for a match.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    ForEach(Competition.allCases, id: \.self) { item in
                        let itemRules = CompRules.rules(for: item)
                        PDFOpenButton(rules: itemRules, competitionName: item.fullName) {
                            HStack(spacing: 12) {
                                Image(systemName: "doc.text.fill")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 32)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.fullName).font(.headline)
                                    Text(itemRules.almanacVersion)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(AppTheme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                    }
                    Label("Add the 2026-27 PDFs to the project (file names are shown in the About screen) to open them here.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                .padding(20)
            }
            .navigationTitle("Playing Conditions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - About Sheet

struct AboutSheet: View {
    let competition: Competition
    let rules: CompRules
    @Environment(\.dismiss) private var dismiss
    @State private var showSelfTests = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("BoundaryLine Rain & Overs")
                            .font(.title3.weight(.semibold))
                        Text("by BoundaryLine Apps").foregroundStyle(.secondary)
                        Text("v6.6 — WBBL12 conditions").font(.caption).foregroundStyle(.secondary)
                        // PROPOSED: on-device self-tests (no Xcode/XCTest needed). Set
                        // BLDiagnostics.enabled = false in BoundaryLineSelfTests.swift before App Store upload.
                        if BLDiagnostics.enabled {
                            Button { showSelfTests = true } label: {
                                Label("Run self-tests", systemImage: "checkmark.seal")
                            }
                            .buttonStyle(.bordered).padding(.top, 6)
                        }
                    }.padding(.top, 8)
                    
                    // All four source documents are bundled for offline access.
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "books.vertical.fill")
                                .foregroundStyle(AppTheme.accent)
                            Text("Playing Conditions Library")
                                .font(.headline)
                            Spacer()
                            Text("OFFLINE")
                                .font(.caption2.weight(.bold))
                                .foregroundStyle(AppTheme.accent)
                        }
                        Text("Official source documents. WBBL, BBL, ODC, WNCL and the ICC tiles follow the 2026–27 conditions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(Competition.allCases, id: \.self) { item in
                            let itemRules = CompRules.rules(for: item)
                            PDFOpenButton(rules: itemRules, competitionName: item.fullName) {
                                HStack(spacing: 10) {
                                    Image(systemName: "doc.richtext")
                                        .foregroundStyle(AppTheme.accent)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.fullName)
                                            .font(.callout.weight(.semibold))
                                        Text(itemRules.almanacVersion)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .foregroundStyle(.secondary)
                                }
                                .padding(12)
                                .background(AppTheme.accent.opacity(0.08))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding(12)
                    .background(AppTheme.line.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    
                    if rules.pdfFileName != nil {
                        PDFOpenButton(rules: rules, competitionName: competition.fullName) {
                            HStack(spacing: 10) {
                                Image(systemName: "doc.text.fill")
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("View official Playing Conditions").font(.callout.weight(.semibold))
                                    Text("\(competition.fullName) -- \(rules.almanacVersion)")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "arrow.up.right.square").foregroundStyle(.secondary)
                            }
                            .padding(12)
                            .background(AppTheme.accent.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .foregroundStyle(.primary)
                        }
                    } else {
                        HStack(spacing: 10) {
                            Image(systemName: "doc.text").foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("No source PDF bundled yet").font(.callout.weight(.semibold))
                                Text("Numbers are from the \(rules.almanacVersion) almanac -- add the PDF to this project's resources once the current document is available.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(AppTheme.warning.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    
                    VStack(spacing: 10) {
                        row("Competition", competition.fullName)
                        row("Min/over", String(format: "%.2f min", rules.minutesPerOver))
                        row("Net playing time", "\(rules.defaultNetPlayingTimeMinutes) min")
                        row("Default interval", "\(rules.defaultIntervalMinutes) min")
                        row("Max overs", "\(rules.maxOversPerTeam)")
                        row("Min valid match", "\(rules.minValidOvers) ov (\(rules.minValidOversFinal) ov Final)")
                        row("Extra time", rules.extraTimeMinutes > 0 ? "\(rules.extraTimeMinutes) min" : "None")
                        if let co = rules.cutoffFullMinutes {
                            row("Cut-off (full innings)", "\(co) min")
                        }
                        row("Overs lost rounding",
                            rules.oversLostRounding == .floor ? "Floor (PC J.1.4)" : "Ceil")
                        row("Termination rounding",
                            rules.terminationRounding == .ceil ? "Ceil (PC J.1.2)" : "Floor")
                        row("PC Almanac", rules.almanacVersion)
                    }.card()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Interval reductions (PC 11.3)").font(.headline)
                        ForEach(rules.intervalReductions.sorted(by: {$0.threshold > $1.threshold}),
                                id: \.threshold) { t, i in
                            HStack {
                                Text(">= \(t) min lost")
                                Spacer()
                                Text("\(i) min interval").foregroundStyle(.secondary)
                            }
                        }
                    }.card()
                    
                    Text("(c) 2025-2026 BoundaryLine Apps")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding()
            }
            .navigationTitle("About").navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showSelfTests) { SelfTestsView() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
    }
    
    private func row(_ l: String, _ r: String) -> some View {
        HStack { Text(l); Spacer(); Text(r).foregroundStyle(.secondary) }
    }
}

// MARK: - Competition landing and live timeline

struct CompetitionLandingView: View {
    @EnvironmentObject var ms: MatchState
    @State private var showLibrary = false
    @State private var showSavedMatches = false
    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                if UIImage(named: "BoundaryLineStadium") != nil {
                    Image("BoundaryLineStadium").resizable().scaledToFit()
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                } else { BoundaryLineBrandMark().padding(.top, 36) }
                Text("RAIN & OVERS").font(.title2.bold())
                Text("Select a competition to start a match")
                    .font(.subheadline).foregroundStyle(.secondary)
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(Competition.allCases) { comp in
                        Button {
                            ms.startMatch(comp)
                        } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(comp.fullName).font(.headline).multilineTextAlignment(.leading)
                                Text(comp.isInternational
                                     ? (comp.isT20 ? "20-over international" : "50-over international")
                                     : (comp.isT20 ? "20-over competition" : "50-over competition"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
                            .padding(12).background(AppTheme.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }.buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("PREVIOUS SAVED MATCHES").font(.headline)
                    if ms.snapshots.isEmpty {
                        Text("No resumable saved matches yet. Open a competition and select Save match to make it available here.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        ForEach(ms.snapshots.prefix(3)) { saved in
                            Button {
                                ms.restoreSnapshot(saved)
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(saved.label).font(.headline)
                                        Text("\(saved.savedTeamA ?? "") v \(saved.savedTeamB ?? "")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Label("Resume", systemImage: "arrow.right.circle.fill")
                                }
                                .padding(12).background(AppTheme.panel)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                            .buttonStyle(.plain)
                            .disabled(saved.competitionCode == nil || saved.firstInningsDelays == nil || saved.secondInningsDelays == nil || saved.savedTimelineEvents == nil)
                        }
                        Button { showSavedMatches = true } label: {
                            Label("View all saved matches (\(ms.snapshots.count))", systemImage: "folder.fill")
                        }.buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button { showLibrary = true } label: {
                    Label("Playing Conditions library", systemImage: "books.vertical")
                }.buttonStyle(.bordered)
            }.padding(20).frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $showLibrary) { PlayingConditionsLibrarySheet() }
        .sheet(isPresented: $showSavedMatches) { SnapshotsSheet().environmentObject(ms) }
    }
}

// MARK: - Breaks and delays record (read-only; existing calculators own edits)

struct DelayTimestampList: View {
    let delays: [InningsDelay]
    var body: some View {
        if !delays.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(delays.sorted { $0.start < $1.start }.enumerated()), id: \.element.id) { index, entry in
                    HStack(spacing: 8) {
                        Text("Delay \(index + 1)").font(.caption.weight(.bold))
                        Spacer(minLength: 4)
                        Text("Off \(TU.shortTime(entry.start))")
                        Text("On \(TU.shortTime(entry.end))")
                        Text("\(entry.duration) min").foregroundStyle(.secondary)
                    }
                    .font(.caption2.monospacedDigit())
                }
            }
        }
    }
}

struct BreaksAndDelaysView: View {
    @EnvironmentObject var ms: MatchState
    @State private var pendingFirstDelete: UUID?
    @State private var editingFirstDelay: UUID?
    @State private var editStart: Date = Date()
    @State private var editEnd: Date = Date()
    @State private var editError = false
    @State private var showResetConfirmation = false
    
    private var first: [InningsDelay] { ms.firstInningsDelays.sorted { $0.start < $1.start } }
    private var second: [InningsDelay] { ms.secondInningsDelays.sorted { $0.start < $1.start } }
    private var total: Int { (first + second).reduce(0) { $0 + $1.duration } }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Breaks & Delays").font(.title2.bold())
                    Text("Recorded interruption times for this match. Times are taken directly from the calculators.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    HStack {
                        Text("Game start")
                        Spacer()
                        Text(TU.shortTime(ms.gameStartTime)).monospacedDigit()
                    }
                    HStack {
                        Text("Logged delays")
                        Spacer()
                        Text("\(first.count + second.count)")
                    }
                    HStack {
                        Text("Total logged stoppages")
                        Spacer()
                        Text("\(total) min")
                    }
                }.card()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("First innings").font(.headline)
                    if first.isEmpty {
                        Text("No first-innings delays logged yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(first.enumerated()), id: \.element.id) { index, entry in
                            HStack(spacing: 8) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Delay \(index + 1): Off \(TU.shortTime(entry.start)) · On \(TU.shortTime(entry.end))")
                                    Text("\(entry.duration) min lost").font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button {
                                    editStart = entry.start
                                    editEnd = entry.end
                                    editingFirstDelay = entry.id
                                    editError = false
                                } label: { Image(systemName: "pencil") }
                                    .accessibilityLabel("Edit first innings delay \(index + 1)")
                                Button(role: .destructive) { pendingFirstDelete = entry.id } label: {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel("Delete first innings delay \(index + 1)")
                            }
                        }
                    }
                    if ms.undoFirstInningsDelays != nil {
                        Button { ms.undoLastFirstInningsChange() } label: {
                            Label("Undo last delay change", systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("First-innings manual lost-time overrides are not individual logged delays.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.card()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Second innings").font(.headline)
                    if second.isEmpty {
                        Text("No second-innings delays logged yet.").foregroundStyle(.secondary)
                    } else {
                        DelayTimestampList(delays: second)
                    }
                }.card()
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Scheduled innings interval").font(.headline)
                    HStack {
                        Text("Current calculated interval")
                        Spacer()
                        Text("\(ms.M_intervalLength) min")
                    }
                    Text("Scheduled intervals are shown separately and are not included in the logged stoppage total.")
                        .font(.caption2).foregroundStyle(.secondary)
                }.card()
                
                Button(role: .destructive) { showResetConfirmation = true } label: {
                    Label("Reset all match timings", systemImage: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                Text("Edit or delete a first-innings interruption to recalculate from the remaining logs. Undo restores the previous delay records.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(20)
        }
        .sheet(isPresented: Binding(
            get: { editingFirstDelay != nil },
            set: { if !$0 { editingFirstDelay = nil } })) {
                NavigationStack {
                    Form {
                        DatePicker("Umpires off", selection: $editStart, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("Umpires back on", selection: $editEnd, displayedComponents: [.date, .hourAndMinute])
                        if editError {
                            Text("Invalid or overlapping interruption. Check the entered times.")
                                .foregroundStyle(.red)
                        }
                    }
                    .navigationTitle("Edit rain delay")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { editingFirstDelay = nil }
                        }
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                guard let id = editingFirstDelay else { return }
                                if ms.editFirstInningsDelay(id: id, start: editStart, end: editEnd) {
                                    editingFirstDelay = nil
                                } else { editError = true }
                            }
                        }
                    }
                }
            }
            .confirmationDialog("Delete this first-innings delay?", isPresented: Binding(
                get: { pendingFirstDelete != nil },
                set: { if !$0 { pendingFirstDelete = nil } }), titleVisibility: .visible) {
                    Button("Delete delay", role: .destructive) {
                        if let id = pendingFirstDelete { ms.deleteFirstInningsDelay(id: id) }
                        pendingFirstDelete = nil
                    }
                    Button("Cancel", role: .cancel) { pendingFirstDelete = nil }
                } message: { Text("The first-innings calculations will be rebuilt from the remaining delays.") }
            .confirmationDialog("Reset all match timings?", isPresented: $showResetConfirmation,
                                titleVisibility: .visible) {
                Button("Reset match", role: .destructive) { ms.resetAll() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("All recorded delays and manual values for this match will be cleared.") }
    }
}

// MARK: - Live match summary (read-only, derived from persisted match state)

struct LiveMatchSummaryView: View {
    @EnvironmentObject var ms: MatchState
    
    private var plan: EqualOversPlan { ms.firstInningsPlan }
    private var firstDelays: [InningsDelay] { ms.firstInningsDelays.sorted { $0.start < $1.start } }
    private var secondDelays: [InningsDelay] { ms.secondInningsDelays.sorted { $0.start < $1.start } }
    private var hasManualOverrides: Bool {
        ms.C_playingTimeLost != firstDelays.reduce(0) { $0 + $1.duration }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("LIVE MATCH SUMMARY")
                        .font(.caption.weight(.bold)).foregroundStyle(AppTheme.accent)
                    Text(ms.competition.fullName)
                        .font(.title2.weight(.bold))
                    Text("Updates as you change match times or log interruptions")
                        .font(.caption).foregroundStyle(.secondary)
                }.card()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("First innings — calculated schedule")
                        .font(.headline)
                    StatDateRow(label: "Game start", date: ms.gameStartTime)
                    StatRow(label: "Overs per team", value: "\(plan.oversPerTeam)")
                    StatRow(label: "Playing time completed", value: "\(ms.B_timeInProgress) min")
                    StatRow(label: "Playing time lost", value: "\(ms.C_playingTimeLost) min")
                    StatDateRow(label: "Projected first cessation", date: plan.firstCessation)
                    StatDateRow(label: "Projected second start", date: plan.secondStart)
                    StatDateRow(label: "Projected match cessation", date: plan.secondCessation)
                    if !plan.meetsTarget {
                        Label("Target cessation cannot be reached within the maximum overs", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(AppTheme.destructive)
                    }
                    if hasManualOverrides {
                        Label("Playing-time loss has a manual override; it differs from the logged delays", systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(AppTheme.warning)
                    }
                }.card()
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recorded interruptions").font(.headline)
                    StatRow(label: "First innings", value: "\(firstDelays.count) delay(s), \(firstDelays.reduce(0) { $0 + $1.duration }) min")
                    StatRow(label: "Second innings", value: "\(secondDelays.count) delay(s), \(secondDelays.reduce(0) { $0 + $1.duration }) min")
                    if let last = (firstDelays + secondDelays).max(by: { $0.end < $1.end }) {
                        StatDateRow(label: "Last recorded restart", date: last.end)
                    }
                    Text("Second-innings revised overs and cessation must be checked in 2nd Interrupt; the first-innings projection above does not include subsequent second-innings interruptions.")
                        .font(.caption).foregroundStyle(.secondary)
                }.card()
                
                VStack(alignment: .leading, spacing: 6) {
                    Label("Auto-save enabled", systemImage: "externaldrive.fill.badge.checkmark")
                        .font(.headline)
                    Text("Match times, interruption logs, team details and calculation inputs are saved on this device as you edit them. Reopening the app restores the active match. Saving to Match History is a separate action.")
                        .font(.caption).foregroundStyle(.secondary)
                }.card()
            }
            .padding(.horizontal, 16).padding(.bottom, 30)
        }
    }
}

// MARK: - Root View

struct ContentView: View {
    @StateObject private var ms = MatchState()
    @State private var selectedTab: Tab = .firstInns
    @State private var selectedComp: Competition = .odc
    
    var body: some View {
        ZStack {
            AppTheme.bg.ignoresSafeArea()
            if !ms.matchIsActive {
                CompetitionLandingView().environmentObject(ms)
            } else {
                VStack(spacing: 10) {
                    BrandHeader(selectedComp: $selectedComp)
                        .environmentObject(ms).padding(.top, 8)
                    if ms.competition == .bbl {
                        Label("BBL|16: 12.8.2.6 one-over allowance (reduced matches) is not added to the cut-off shown. Interval reduction: see PC 11.3.3 wording (\"after 21 minutes\").",
                              systemImage: "info.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.info)
                            .padding(.horizontal, 16)
                    }
                    if ms.competition.isInternational {
                        Label("ICC Men's Playing Conditions (Oct 2026). Unverified build. DLS targets and over-rate penalties are not calculated.",
                              systemImage: "info.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.info)
                            .padding(.horizontal, 16)
                    }
                    TabBar(selection: $selectedTab, competition: ms.competition)
                    Group {
                        switch selectedTab {
                        case .lateStart:
                            LateStartODCView()
                        case .firstInns: FirstInningsView()
                        case .termination: TerminationCheckView()
                        case .secondStart: SecondInningsStartView()
                        case .secondInter: SecondInningsInterruptionView()
                        case .powerplays: PowerplayHelperView()
                        case .breaks: BreaksAndDelaysView()
                        case .summary: LiveMatchSummaryView()
                        }
                    }.environmentObject(ms)
                }
            }
        }
        .preferredColorScheme(ms.themePreference.colorScheme)
        .onAppear { selectedComp = ms.competition }
        .onChange(of: ms.matchIsActive) { _, active in
            if active { selectedTab = .firstInns; selectedComp = ms.competition }
        }
        .onTapGesture {
            UIApplication.shared.sendAction(
                #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
    }
}

// MARK: - App Entry

@main
struct BoundaryLineRainApp: App {
    var body: some Scene { WindowGroup { ContentView() } }
}
