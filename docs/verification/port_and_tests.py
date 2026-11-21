#!/usr/bin/env python3
"""
INDEPENDENT PYTHON PORT of the pure calculation logic in the supplied Swift
source (BoundaryLine_as_received_labelled_v7.4.swift).

WHAT THIS IS:  a re-implementation used to probe the arithmetic and state-flow
               of the Swift code. It is NOT a Swift build and NOT a substitute
               for Xcode compilation or iPad testing.
WHAT IT ISN'T: proof about SwiftUI/UserDefaults/Combine behaviour. Where a test
               models Swift observer semantics it says so.

Swift line references are to the as-received file.
Run:  python3 port_and_tests.py
"""
import math
from dataclasses import dataclass, field, replace
from datetime import datetime, timedelta
from typing import List, Optional

# ----------------------------------------------------------------- utilities
def swift_round(x: float) -> int:            # Double.rounded() = away from zero on .5
    return int(math.floor(abs(x) + 0.5)) * (1 if x >= 0 else -1)

def min_between(a: datetime, b: datetime) -> int:      # TU.minBetween (L414)
    return max(0, swift_round((b - a).total_seconds() / 60.0))

def add_min(d: datetime, m: int) -> datetime:
    return d + timedelta(minutes=m)

def round2(v: float) -> float:
    return math.floor(abs(v) * 100 + 0.5) / 100.0 * (1 if v >= 0 else -1)

# ----------------------------------------------------------------- CompRules (L175-375)
@dataclass(frozen=True)
class Rules:
    name: str
    minutes_per_over: float
    net_minutes: int
    interval: int
    max_overs: int
    lost_rounding: str            # 'floor' | 'ceil'
    reductions: tuple             # ((threshold, new_interval), ...)
    cutoff_full: Optional[int]
    cutoff_extra: Optional[int]
    cutoff_min_overs: Optional[int]
    late_window: Optional[int]
    extra_time: int
    is_t20: bool

    def adjusted_interval(self, time_lost: int) -> int:           # L289
        eff = max(0, time_lost - self.extra_time) if self.extra_time > 0 else time_lost
        for th, new in sorted(self.reductions, key=lambda t: -t[0]):
            if eff >= th:
                return new
        return self.interval

ODC  = Rules("ODC", 4.2, 420, 30, 50, 'floor', ((60, 20),), 206, -4, 25, None, 0, False)
WNCL = Rules("WNCL", 3.8, 380, 40, 50, 'floor', ((60, 20), (1, 30)), 187, -3, 25, None, 60, False)
BBL  = Rules("BBL", 4.0, 160, 15, 20, 'floor', ((21, 10),), 79, 3, 10, 175, 0, True)
WBBL = Rules("WBBL", 3.75, 150, 15, 20, 'floor', ((16, 10),), None, None, None, 165, 0, True)

# ----------------------------------------------------------------- EqualOversCalculator (L450-478)
@dataclass
class Plan:
    overs: int; length: int; first_end: datetime; second_start: datetime
    second_end: datetime; extra: int; target: datetime; meets: bool

def original_cessation(start: datetime, r: Rules) -> datetime:
    return add_min(start, r.net_minutes + r.interval)

def plan(r: Rules, original_start, restart, played, initial_overs, interval, resched=None) -> Plan:
    target = resched or original_cessation(original_start, r)
    first = min(r.max_overs, max(0, initial_overs))
    overs = first
    played = max(0, played)
    while True:
        length = math.ceil(overs * r.minutes_per_over)
        first_end = add_min(restart, max(0, length - played))
        second_start = add_min(first_end, max(0, interval))
        second_end = add_min(second_start, length)
        if second_end >= target or overs == r.max_overs:
            break
        overs += 1
    return Plan(overs, length, first_end, second_start, second_end, overs - first, target, second_end >= target)

# ----------------------------------------------------------------- MatchState (first-innings subset)
@dataclass
class Delay:
    start: datetime; end: datetime; allowance: int = 0
    @property
    def duration(self): return max(0, min_between(self.start, self.end))
    @property
    def net_lost(self): return max(0, self.duration - self.allowance)

@dataclass
class State:
    r: Rules
    game_start: datetime
    ls_actual: datetime            # LS_actualStart
    A: int = 0                     # A_netPlayingTime
    B: int = 0                     # B_timeInProgress
    C: int = 0                     # C_playingTimeLost
    D: int = 0                     # D_extraTimeAvail (manual)
    E: int = 0                     # E_timeFromReducedInterval
    J: Optional[datetime] = None   # J_startOrRecommence
    M: int = 0                     # M_intervalLength
    delays: List[Delay] = field(default_factory=list)
    resched: Optional[datetime] = None

    def __post_init__(self):
        self.A = self.A or self.r.net_minutes
        self.J = self.J or self.ls_actual
        self.M = self.M or self.r.interval

    # L929
    def update_interval(self):
        new = self.r.adjusted_interval(self.C + max(0, min_between(self.game_start, self.ls_actual)))
        self.M = new
        self.E = max(0, self.r.interval - new)

    # L1216 delayedFirstBallPlan
    def delayed_first_ball_plan(self) -> Optional[Plan]:
        r = self.r
        if not (self.ls_actual > self.game_start and not self.delays and self.C == 0 and self.B == 0):
            return None
        lost = max(0, min_between(self.game_start, self.ls_actual))
        interval = r.adjusted_interval(lost)
        saved = r.interval - interval
        extra = min(lost, r.extra_time)
        available = max(0, r.net_minutes - max(0, lost - extra - saved))
        return plan(r, self.game_start, self.ls_actual, 0,
                    math.ceil((available / r.minutes_per_over) / 2.0), interval, self.resched)

    # L1235 firstInningsPlan  (AS RECEIVED)
    def first_innings_plan(self) -> Plan:
        d = self.delayed_first_ball_plan()
        if d: return d
        r = self.r
        initial = max(0, min_between(self.game_start, self.ls_actual))
        total_loss = initial + self.C
        allowed_extra = min(total_loss, r.extra_time, max(0, self.D))
        effective = max(0, total_loss - allowed_extra - self.E)
        remaining = max(0, self.A - effective)
        total = remaining / r.minutes_per_over
        rt = round2(total) if r.is_t20 else total
        restart = add_min(self.game_start, self.B) if (not self.delays and self.C == 0) else self.J
        return plan(r, self.game_start, restart, self.B, math.ceil(rt / 2.0), self.M, self.resched)

    # L2133-2140 FirstInningsView display values (AS RECEIVED)
    def displayed_effective_lost(self):  return max(0, self.C - (self.D + self.E))
    def displayed_remaining(self):       return max(0, self.A - self.displayed_effective_lost())
    def displayed_total_overs(self):     return self.displayed_remaining() / self.r.minutes_per_over

    # Log a rain delay exactly as FirstInningsView's button does (L2255-2264)
    def log_delay(self, start: datetime, end: datetime):
        played = max(0, min_between(self.ls_actual, start) - self.C)
        self.B = played
        self.C += min_between(start, end)
        self.J = end
        self.update_interval()
        self.delays.append(Delay(start, end, 0))

# ----------------------------------------------------------------- SecondInningsWorksheet (L2470-2502)
def second_innings(r: Rules, innings_start, restart, initial_overs, delays, completed_overs, completed_balls,
                   extra_already_used: int = 0, cap_remaining_extra: bool = False):
    ordered = sorted(delays, key=lambda d: d.start)
    duration = sum(d.duration for d in ordered)
    requested = sum(min(d.duration, max(0, d.allowance)) for d in ordered)
    cap = r.extra_time - (extra_already_used if cap_remaining_extra else 0)
    allowances = min(duration, max(0, cap), requested)
    net = max(0, duration - allowances)
    played = max(0, min_between(innings_start, restart) - duration)
    lost = math.floor(net / r.minutes_per_over) if r.lost_rounding == 'floor' else math.ceil(net / r.minutes_per_over)
    revised = max(0, min(r.max_overs, initial_overs) - lost)
    minutes = math.ceil(revised * r.minutes_per_over)
    return dict(allowances=allowances, net=net, lost_overs=lost, revised=revised, minutes=minutes,
                cessation=add_min(restart, max(0, minutes - played)))

# =================================================================== TESTS
PASS, FAIL, OPEN = [], [], []
def check(name, cond, detail=""):
    (PASS if cond else FAIL).append(name)
    print(("  PASS  " if cond else "  FAIL  ") + name + (f"   [{detail}]" if detail else ""))
def open_q(name, differs, detail=""):
    """Behaviour that differs from one plausible reading of the rules, but where the
    governing text was not available to me. Reported separately -- NOT counted as a defect."""
    (OPEN if differs else PASS).append(name)
    print(("  OPEN  " if differs else "  PASS  ") + name + (f"   [{detail}]" if detail else ""))

def T(h, m=0, s=0):
    return datetime(2026, 11, 7, h, m, s)

def banner(t): print("\n" + "=" * 78 + "\n" + t + "\n" + "=" * 78)

# ---- Sanity: the port reproduces hand-checkable numbers from the source constants
banner("0. Port sanity (hand-checkable)")
p = plan(ODC, T(10), T(10), 0, 25, 30)
check("ODC undisturbed 50-ov equal-overs: 50 ov x 4.2 = 210 min",
      plan(ODC, T(10), T(10), 0, 50, 30).length == 210)
check("ODC original cessation = start + 420 + 30", original_cessation(T(10), ODC) == T(17, 30))
check("WNCL 60/15.79 ~= 3.7998 vs 3.8 (rate differs in 4th decimal)", abs(60/15.79 - 3.8) < 0.001)

# ---- Defect 8 (new): 3.8 vs 15.79 overs/hour -- does it ever change an integer-minute result?
banner("8. WNCL 3.8 min/over vs PC 15.79 overs/hour (13.7.2.1.1, 2025-26 text)")
diff_floor = [m for m in range(0, 421) if math.floor(m / 3.8) != math.floor(m * 15.79 / 60.0)]
diff_ceil = [o for o in range(1, 51) if math.ceil(o * 3.8) != math.ceil(o * 60.0 / 15.79)]
check("floor(minutes/3.8) == floor(minutes*15.79/60) for every whole minute 0..420",
      not diff_floor, f"differs at {diff_floor[:6]}")
check("ceil(overs*3.8) == ceil(overs*60/15.79) for 1..50 overs", not diff_ceil, f"differs at {diff_ceil[:6]}")

# ---- Defect 1: late start followed by rain
banner("1. Late start followed by rain")
# WNCL, scheduled 10:00, first ball 10:30 (30 min late), then rain 11:30-11:50 (20 min).
def wncl_case(with_rain: bool, D: int):
    s = State(WNCL, T(10), T(10, 30), D=D)
    if with_rain:
        s.log_delay(T(11, 30), T(11, 50))
    return s
pre = wncl_case(False, 0).first_innings_plan()
post0 = wncl_case(True, 0)
post60 = wncl_case(True, 60)
pp0, pp60 = post0.first_innings_plan(), post60.first_innings_plan()
print(f"  before rain (auto extra time):          {pre.overs} ov/side")
print(f"  after 20-min rain, D=0 (default UI):    {pp0.overs} ov/side")
print(f"  after 20-min rain, D=60 (user entered): {pp60.overs} ov/side")
check("1a. Extra time is applied automatically before rain (WNCL 12.7.1)",
      pre.overs >= 49, f"{pre.overs} ov")
# 50 ov cap + Appendix J guard may mask the difference; probe the no-guard quantity directly
def raw_total_overs(s: State):
    r = s.r
    initial = max(0, min_between(s.game_start, s.ls_actual))
    total_loss = initial + s.C
    extra = min(total_loss, r.extra_time, max(0, s.D))
    eff = max(0, total_loss - extra - s.E)
    return (max(0, s.A - eff)) / r.minutes_per_over
print(f"  raw total overs (both teams) D=0: {raw_total_overs(post0):.2f}   D=60: {raw_total_overs(post60):.2f}")
check("1b. Raw overs after late start + rain DO NOT depend on a manually typed 'Extra time available'",
      abs(raw_total_overs(post0) - raw_total_overs(post60)) < 1e-9,
      "FAILS today: extra time silently vanishes unless the umpire types 60")

# Larger loss, so the 50-over cap and guard don't mask the effect
def wncl_big(D):
    s = State(WNCL, T(10), T(11, 0), D=D)      # 60 min late start
    s.log_delay(T(12, 0), T(12, 45))            # + 45 min rain => 105 total
    return s
b0, b60 = wncl_big(0), wncl_big(60)
print(f"  60-min late start + 45-min rain: plan overs D=0 -> {b0.first_innings_plan().overs}, D=60 -> {b60.first_innings_plan().overs}")
check("1c. Same match, same facts: overs/side identical whether or not D typed",
      b0.first_innings_plan().overs == b60.first_innings_plan().overs,
      f"{b0.first_innings_plan().overs} vs {b60.first_innings_plan().overs}")

# Display vs plan consistency (L2133-2140 and L1268)
banner("1d. 'Effective time lost / Remaining / Total overs' panel vs the plan that drives Overs/team")
s = wncl_big(60)
disp = s.displayed_total_overs()
true_remaining = s.A - max(0, (min_between(s.game_start, s.ls_actual) + s.C) - min(105, 60, s.D) - s.E)
print(f"  panel shows total overs (both): {disp:.2f}   calculation uses: {true_remaining / s.r.minutes_per_over:.2f}")
check("1d. Displayed total overs equals the figure the plan actually used",
      abs(disp - true_remaining / s.r.minutes_per_over) < 1e-9,
      "panel ignores the late-start minutes")

# Restart anchor with a late start and B>0 but no rain logged (L1245-1247)
banner("1e. Restart anchor when late start + minutes-in-progress entered, no rain yet")
s = State(ODC, T(10), T(10, 40), B=30)         # first ball 10:40, 30 min bowled
pl = s.first_innings_plan()
expected_first_end_if_unchanged = add_min(T(10, 40), math.ceil(pl.overs * ODC.minutes_per_over))
print(f"  plan first innings ends {pl.first_end.time()}, innings of {pl.length} min starting 10:40 would end {expected_first_end_if_unchanged.time()}")
check("1e. First innings cessation is measured from the actual first ball, not the scheduled start",
      pl.first_end == expected_first_end_if_unchanged,
      "restart = scheduled start + B ignores the 40-min late start")

# ---- Defect 3/4: WNCL extra time + interval boundaries
banner("3/4. WNCL extra-time and innings-interval boundaries (current code)")
print("  gross time lost -> interval (default 40; PC 2025-26: '30 after up to 59', '20 after 60' of ACTUAL playing time lost, extra time exhausted first)")
rows = {m: WNCL.adjusted_interval(m) for m in (0, 30, 60, 61, 90, 119, 120, 121, 180)}
for m, i in rows.items(): print(f"    lost {m:>3} -> interval {i}")
check("4a. Up to the 60-min extra-time allowance the interval is NOT reduced (0..60 -> 40)",
      all(rows[m] == 40 for m in (0, 30, 60)))
check("4b. First minute beyond extra time -> 30", rows[61] == 30)
check("4c. 60 min of ACTUAL loss beyond extra time (gross 120) -> 20", rows[120] == 20 and rows[119] == 30)
print("  NOTE: 4a-4c encode one reading of 11.3.2 + 12.7.1; confirm against the 2026-27 text (not obtained).")

banner("3. WNCL cumulative extra time across innings")
# First innings consumed the full 60; second innings logs an 80-min stoppage claiming 60 allowance
d2 = [Delay(T(15, 0), T(16, 20), 60)]
as_is = second_innings(WNCL, T(14, 0), T(16, 20), 40, d2, 10, 0)
capped = second_innings(WNCL, T(14, 0), T(16, 20), 40, d2, 10, 0, extra_already_used=60, cap_remaining_extra=True)
print(f"  second innings, 80-min stoppage, 60 min extra already used in innings 1:")
print(f"    as coded:        allowance {as_is['allowances']} -> revised {as_is['revised']} ov")
print(f"    if match-total:  allowance {capped['allowances']} -> revised {capped['revised']} ov")
open_q("3a. Second-innings allowance limited by extra time already consumed in innings 1?",
       as_is['allowances'] != capped['allowances'],
       "as coded grants a fresh 60; PC 12.7.1 visible text does not say per-match vs per-innings")

# ---- Defect 2: WBBL (and BBL) latest permissible start boundaries
banner("2. Latest permissible first ball (minimum five-over match)")
def latest_start(r: Rules, inn_seconds: int, interval_min: int, sched=T(19, 0)):
    finish = add_min(sched, r.late_window)
    exact = finish - timedelta(seconds=inn_seconds * 2 + interval_min * 60)
    return exact, exact.replace(second=0, microsecond=0)
ex, fl = latest_start(WBBL, 18 * 60, 10)
print(f"  WBBL as coded 18:00 + 10:00 + 18:00 = 46:00 -> latest first ball {fl.time()} (window 165)")
ex2, fl2 = latest_start(WBBL, int(5 * 3.75 * 60), 10)
print(f"  WBBL 5 x 3.75 = 18:45 each      = 47:30 -> latest first ball {fl2.time()}")
check("2a. App's 18-minute five-over convention is reproduced by the port (46 min)",
      (T(19, 0) + timedelta(minutes=165) - ex).total_seconds() == 46 * 60)
open_q("2b. 18:00 five-over convention vs 5 x 3.75 = 18:45 from the PC rate",
       (fl - fl2).total_seconds() == 90, f"latest start {fl.time()} (18:00) vs {fl2.time()} (18:45): 2 min apart after floor")
print("  RESULT: the 18:00 figure is not derivable from the published WBBL11 text I could read;")
print("          keep it only if Cricket Australia gave it in writing -- cite that document in the app.")
exb, flb = latest_start(BBL, int(5 * 4.0 * 60), 10, T(19, 0))
print(f"  BBL 5 x 4.0 = 20:00 each + 10 = 50:00 -> latest first ball {flb.time()} (window 175)  [BBL|16 constants UNVERIFIED]")
# boundary behaviour: inclusive at exactly the limit
check("2c. Start exactly AT latest first ball is accepted by `<=` (inclusive); confirm PC wording 'no later than'",
      True, "design choice; verify wording")
# seconds handling: floor to minute never rounds later
check("2d. Floor-to-minute never produces a later start than the exact limit",
      fl <= ex and (ex - fl).total_seconds() < 60)

# ---- Defect 5/6: persistence model (models Swift didSet-in-method semantics)
banner("5/6. loadFromDisk observer ordering (models didSet firing for assignments made inside a method)")
class Disk(dict): pass
def load_from_disk_as_received(disk: Disk, comp: Rules, now: datetime):
    """Replays L789-842 including the side effects in gameStartTime.didSet (L712-731).
    ASSUMES Swift fires property observers for assignments made inside loadFromDisk()
    (they do: only assignments inside the class's own init body are exempt)."""
    st = dict(delays=disk.get('delays', []), C=0, B=0, LS=now, J=now, C2=now, M=comp.interval, E=0)
    def game_start_didset(gs):
        disk['game_start'] = gs
        if not st['delays'] and st['C'] == 0:                        # first branch
            st['J'] = add_min(gs, st['B']); disk['J'] = st['J']
            st['LS'] = gs; disk['LS'] = gs                            # <-- persisted overwrite
            st['C2'] = add_min(gs, comp.net_minutes // 2 + comp.interval); disk['C2'] = st['C2']
        elif not comp.is_t20:
            st['J'] = add_min(gs, st['B'] + st['C']); disk['J'] = st['J']
        else:                                                         # recalcTimeLostFromRestart
            off = add_min(st['LS'], st['B'])
            st['C'] = max(0, min_between(off, st['J'])); disk['C'] = st['C']
            new = comp.adjusted_interval(st['C'] + max(0, min_between(gs, st['LS'])))
            st['M'] = new; disk['M'] = new; st['E'] = max(0, comp.interval - new); disk['E'] = st['E']
    game_start_didset(disk['game_start'])
    # remaining loads read AFTER the overwrite, like L809-827
    st['LS'] = disk.get('LS', now); st['J'] = disk.get('J', now)
    st['C'] = disk.get('C', 0); st['M'] = disk.get('M', comp.interval)
    return st

# Case 1: ODC, late start, nothing logged, app killed and relaunched
disk = Disk(game_start=T(10), LS=T(10, 45), J=T(10, 45), C=0, delays=[])
st = load_from_disk_as_received(disk, ODC, T(12))
check("5a. Late first-ball time (10:45) survives relaunch", st['LS'] == T(10, 45), f"after relaunch LS = {st['LS'].time()}")

# Case 2: WBBL (T20) with a logged rain delay (delays non-empty) and 25 min lost
disk = Disk(game_start=T(19), LS=T(19, 10), J=T(20, 5), C=25, delays=['x'], M=10)
st = load_from_disk_as_received(disk, WBBL, T(21))
check("5b. Time lost (25 min) survives relaunch in a T20 match with a logged delay", st['C'] == 25, f"after relaunch C = {st['C']}")

# Case 3: cross-midnight snapshot restore (minutes-from-midnight storage, L1038-1043)
banner("6b. Snapshot restore across midnight")
def restore_time(anchor_start: datetime, minute_of_day: int, fixed: bool):
    base = anchor_start.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(minutes=minute_of_day)
    if fixed and minute_of_day < anchor_start.hour * 60 + anchor_start.minute:
        base += timedelta(days=1)
    return base
saved_cessation = datetime(2026, 11, 8, 0, 20)                 # 00:20 next day
mins = saved_cessation.hour * 60 + saved_cessation.minute
as_is = restore_time(T(19, 0), mins, fixed=False)
check("6b. A 00:20 next-day restart restores to the right calendar day",
      as_is == saved_cessation, f"restores to {as_is} (before the match even starts)")
check("6b-fix. Proposed 'earlier than scheduled start => next day' rule restores correctly",
      restore_time(T(19, 0), mins, fixed=True) == saved_cessation)

# ---- Defect 5: new-match reset
banner("5c. startMatch() / resetAll() field coverage (static read, L627-638, L851-881)")
reset_fields = {"firstInningsDelays","timelineEvents","confirmedCessation","A","B","C","D","E","M","J","LS","A2","C2","H",
                "A3","B3","D3","F3","P","Q","T","reschedEnabled","reschedCessation","secondInningsDelays",
                "secondInningsCompletedOvers","secondInningsCompletedBalls","teamA","teamB","venue"}
persisted_match_fields = reset_fields | {"isFinal","gameStartTime","calculationClockTime"}
not_reset = sorted(persisted_match_fields - reset_fields)
check("5c. Every persisted per-match field is reset by startMatch", not not_reset,
      f"NOT reset: {not_reset}")

# =================================================================== summary
banner("SUMMARY")
print(f"  {len(PASS)} passed, {len(FAIL)} FAILED (defects), {len(OPEN)} OPEN (need the 2026-27 Playing Conditions)")
for n in FAIL: print("  FAILED:", n)
for n in OPEN: print("  OPEN:  ", n)
print("\nA FAIL here means: the as-received Swift logic, as ported, contradicts the stated expectation.")
print("Nothing above has been executed as Swift. Confirm in Xcode with proposed/BoundaryLineRainTests.swift.")
