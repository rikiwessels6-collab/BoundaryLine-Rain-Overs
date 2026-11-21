#!/usr/bin/env python3
"""Independent expectations for the proposed second-innings model and the latest-start helper.
Port only -- not Swift. Numbers here are what BoundaryLineSelfTests.swift asserts."""
import sys, os, io, contextlib, math
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
with contextlib.redirect_stdout(io.StringIO()):
    from port_and_tests import *

def ws(r, start, stop_s, stop_e, restart, init, done, used=0, credit=0):
    d = [Delay(stop_s, stop_e, 0)]; dur = d[0].duration
    extra = min(dur, max(0, r.extra_time - used)); cr = min(max(0, dur - extra), max(0, credit))
    net = dur - (extra + cr); lost = math.floor(net / r.minutes_per_over)
    return dict(allow=extra + cr, net=net, lost=lost, revised=max(0, min(r.max_overs, init) - lost))

cases = [
 ("S1 WNCL pool unused, 80-min stoppage",        WNCL, T(14), T(15,0), T(16,20), T(16,20), 40, 0, 0),
 ("S2 WNCL pool fully used in innings 1",         WNCL, T(14), T(15,0), T(16,20), T(16,20), 40, 60, 0),
 ("S3 WNCL 45 of pool used",                      WNCL, T(14), T(15,0), T(16,20), T(16,20), 40, 45, 0),
 ("S4 ODC 40-min stoppage, 30 credit",            ODC,  T(14), T(15,0), T(15,40), T(15,40), 40, 0, 30),
 ("S5 ODC 40-min stoppage, no credit",            ODC,  T(14), T(15,0), T(15,40), T(15,40), 40, 0, 0),
 ("S6 WBBL 40-min stoppage, 30 credit",           WBBL, T(19), T(19,30), T(20,10), T(20,10), 20, 0, 30),
 ("S7 ODC credit larger than stoppage (60)",      ODC,  T(14), T(15,0), T(15,40), T(15,40), 40, 0, 60),
 ("S8 WNCL 80-min stoppage + 30 credit",          WNCL, T(14), T(15,0), T(16,20), T(16,20), 40, 0, 30),
]
for n, r, a, s, e, rs, init, used, cr in cases:
    w = ws(r, a, s, e, rs, init, 10, used, cr)
    print(f"{n:45s} allowance {w['allow']:>3}  net {w['net']:>3}  overs lost {w['lost']:>2}  revised {w['revised']:>2}")

print()
def latest(r, comp_wbbl, sched, window_minutes, interval, minovers=5):
    inn = 18*60 if (comp_wbbl and minovers == 5) else math.ceil(minovers * r.minutes_per_over * 60)
    cess = sched + timedelta(minutes=window_minutes)
    exact = cess - timedelta(seconds=inn*2 + interval*60)
    return exact.replace(second=0, microsecond=0), cess
fl, c = latest(WBBL, True, T(19,40), 150+15, 10);  print("CA almanac example  WBBL 19:40 -> cessation", c.time(), " latest first ball", fl.time(), " (almanac: 21:39)")
assert fl == T(21,39) and c == T(22,25)
fl2,_ = latest(WBBL, True, T(19,40), 165, 10); 
exact_with_secs = (T(22,25,30) - timedelta(minutes=46)).replace(second=0); print("floor check (cessation 22:25:30) ->", exact_with_secs.time(), "(never later than exact 21:39:30)")
fl3, c3 = latest(BBL, False, T(19,15), 160+15, 10); print("BBL (2025/26 constants) 19:15 -> cessation", c3.time(), " latest first ball", fl3.time())
print("OK")
