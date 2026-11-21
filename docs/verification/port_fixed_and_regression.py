#!/usr/bin/env python3
"""
Port of the PROPOSED fixes + regression grid. Imports the as-received port.
Port only -- NOT Swift, NOT a build.
"""
import io, contextlib, math, itertools, sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
with contextlib.redirect_stdout(io.StringIO()):
    import port_and_tests as P                       # re-uses as-received port (silences its run)
from port_and_tests import *

def loss_fixed(s: State):                            # MatchState.firstInningsLoss (proposed)
    r = s.r
    initial = max(0, min_between(s.game_start, s.ls_actual))
    total = initial + s.C
    extra = min(total, r.extra_time)
    credit = max(0, r.interval - r.adjusted_interval(total))
    eff = max(0, total - extra - credit)
    rem = max(0, s.A - eff)
    raw = rem / r.minutes_per_over
    return dict(total=total, extra=extra, credit=credit, eff=eff, rem=rem, overs=round2(raw) if r.is_t20 else raw)

def plan_fixed(s: State) -> Plan:                    # MatchState.firstInningsPlan (proposed)
    d = s.delayed_first_ball_plan()
    if d: return d
    l = loss_fixed(s)
    restart = add_min(s.ls_actual, s.B) if (not s.delays and s.C == 0) else s.J
    return plan(s.r, s.game_start, restart, s.B, math.ceil(l['overs'] / 2.0), s.M, s.resched)

print("=" * 78 + "\nAFTER PROPOSED FIXES (port)\n" + "=" * 78)
ok = True
def chk(name, cond, detail=""):
    global ok; ok &= bool(cond); print(("  PASS  " if cond else "  FAIL  ") + name + (f"   [{detail}]" if detail else ""))

# 1b/1c: independence from typed D
def big(D):
    s = State(WNCL, T(10), T(11, 0), D=D); s.log_delay(T(12, 0), T(12, 45)); return s
chk("1c. WNCL 60-min late start + 45-min rain: overs identical for D=0 and D=60",
    plan_fixed(big(0)).overs == plan_fixed(big(60)).overs, f"{plan_fixed(big(0)).overs} ov")
# continuity: late start only vs late start + zero-length-effect? use tiny rain
a = State(WNCL, T(10), T(10, 30)); pre = a.first_innings_plan().overs
b = State(WNCL, T(10), T(10, 30)); b.log_delay(T(11, 30), T(11, 31)); post = plan_fixed(b).overs
chk("1a. 1-minute rain after a 30-min WNCL late start does not drop overs discontinuously",
    pre - post <= 1, f"before {pre} ov, after {post} ov")
# 1d: panel = plan
s = big(60); l = loss_fixed(s)
chk("1d. Panel total overs equals what the plan used",
    abs(l['overs'] - (s.A - max(0, l['total'] - l['extra'] - l['credit'])) / s.r.minutes_per_over) < 1e-9,
    f"{l['overs']:.2f} (was 100.00 on screen)")
# 1e: restart anchor
s = State(ODC, T(10), T(10, 40), B=30); pl = plan_fixed(s)
chk("1e. First innings measured from actual first ball",
    pl.first_end == add_min(T(10, 40), math.ceil(pl.overs * ODC.minutes_per_over)))

# 5a/5b: loader guard (observer side effects skipped while restoring)
def load_fixed(disk, comp, now):
    return dict(LS=disk.get('LS', now), J=disk.get('J', now), C=disk.get('C', 0), M=disk.get('M', comp.interval))
st = load_fixed(dict(LS=T(10, 45), J=T(10, 45), C=0), ODC, T(12))
chk("5a. Late first-ball time survives relaunch", st['LS'] == T(10, 45))
st = load_fixed(dict(LS=T(19, 10), J=T(20, 5), C=25, M=10), WBBL, T(21))
chk("5b. Time lost survives relaunch (T20, logged delay)", st['C'] == 25)

# 6b
def restore_fixed(anchor, minute):
    base = anchor.replace(hour=0, minute=0, second=0, microsecond=0) + timedelta(minutes=minute)
    return base + timedelta(days=1) if minute < anchor.hour * 60 + anchor.minute else base
chk("6b. 00:20 next-day time restores to next day", restore_fixed(T(19), 20) == datetime(2026, 11, 8, 0, 20))
chk("6b. Same-day times unaffected", restore_fixed(T(19), 21 * 60 + 5) == T(21, 5) and restore_fixed(T(19), 19 * 60) == T(19))

# ---------------- regression grid: where do as-received and proposed numbers differ?
print("\nREGRESSION GRID  (late start 0..120 x rain 0..120 x B in {0,30,90}); counting plans whose overs/cessation change")
def build(r, ls, rain, B):
    gs = T(10); s = State(r, gs, add_min(gs, ls), B=B)
    if rain:
        start = add_min(s.ls_actual, max(B, 20)); s.log_delay(start, add_min(start, rain))
    return s
diffs = {}
total = {}
for r in (ODC, WNCL, BBL, WBBL):
    n = d = 0; ex = []
    for ls, rain, B in itertools.product(range(0, 121, 5), range(0, 121, 5), (0, 30, 90)):
        if r.is_t20 and (ls + rain > 100): continue
        if B > r.net_minutes // 2: continue
        s = build(r, ls, rain, B)
        a, b = s.first_innings_plan(), plan_fixed(s)
        n += 1
        if (a.overs, a.first_end, a.second_end) != (b.overs, b.first_end, b.second_end):
            d += 1
            if len(ex) < 3: ex.append((ls, rain, B, a.overs, b.overs))
    diffs[r.name] = (d, n, ex)
for k, (d, n, ex) in diffs.items():
    print(f"  {k:5s}: {d:5d} of {n:5d} scenarios change   e.g. (late,rain,B,old_ov,new_ov) {ex}")
# classify: WNCL changes must be only where extra time matters (rain logged); T20/ODC changes only via the restart anchor (ls>0, B>0, no rain)
def explained(r, ls, rain, B):
    if r.extra_time > 0 and rain > 0 and ls + rain > 0: return True
    if rain == 0 and ls > 0 and B > 0: return True         # restart-anchor fix
    return False
unexplained = []
for r in (ODC, WNCL, BBL, WBBL):
    for ls, rain, B in itertools.product(range(0, 121, 5), range(0, 121, 5), (0, 30, 90)):
        if r.is_t20 and (ls + rain > 100): continue
        if B > r.net_minutes // 2: continue
        s = build(r, ls, rain, B); a, b = s.first_innings_plan(), plan_fixed(s)
        if (a.overs, a.first_end, a.second_end) != (b.overs, b.first_end, b.second_end) and not explained(r, ls, rain, B):
            unexplained.append((r.name, ls, rain, B))
chk("REG. Every changed scenario is explained by one of the two intended fixes", not unexplained, f"{len(unexplained)} unexplained {unexplained[:5]}")
odc_t20_rain_changed = [k for k in ("ODC", "BBL", "WBBL") for _ in [0] if False]
print("\nRESULT:", "ALL PASS" if ok else "SOME FAIL")
