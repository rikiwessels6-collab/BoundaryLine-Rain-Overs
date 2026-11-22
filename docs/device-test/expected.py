"""Independent expected figures for the device test script.
Written from Appendix J (CA) / Appendix E (ICC) and the PC constants, using EXACT arithmetic
(fractions), not the app's code. Output: JSON used by the self-tests and the printed script."""
from fractions import Fraction as Fr
import math, json, sys

C = {  # comp: rate, A (net), interval, max overs, extra time, interval reductions [(threshold, new)], T20
 'ODC':  dict(rate=Fr(42,10), A=420, iv=30, mx=50, et=0,  red=[(60,20)],          t20=False),
 'WNCL': dict(rate=Fr(38,10), A=380, iv=40, mx=50, et=60, red=[(60,20),(1,30)],   t20=False),
 'BBL':  dict(rate=Fr(4),     A=160, iv=15, mx=20, et=0,  red=[(21,10)],          t20=True),
 'WBBL': dict(rate=Fr(375,100),A=150,iv=15, mx=20, et=0,  red=[(16,10)],          t20=True),
 'ODI':  dict(rate=Fr(42,10), A=420, iv=30, mx=50, et=0,  red=[],                 t20=False),
 'T20I': dict(rate=Fr(425,100),A=170,iv=15, mx=20, et=0,  red=[],                 t20=True),
}
def ceil(x): return math.ceil(x)
def floor(x): return math.floor(x)
def interval(c, lost):
    eff = max(0, lost - c['et']) if c['et'] > 0 else lost
    for th, new in sorted(c['red'], reverse=True):
        if eff >= th: return new
    return c['iv']

def first(comp, start, ball, stops):
    """start/ball/stops in minutes after midnight. Returns overs, interval, times, extra used."""
    c = C[comp]
    late = ball - start
    lost = late + sum(e - s for s, e in stops)
    iv = interval(c, lost); credit = c['iv'] - iv
    extra = min(lost, c['et'])
    G = c['A'] - max(0, lost - extra - credit)
    H = Fr(G) / c['rate']
    if c['t20']: H = Fr(round(H * 100), 100)   # T20 worksheets: H to 2 decimal places
    overs = min(c['mx'], ceil(H / 2))
    if stops:
        restart = stops[-1][1]
        played = (stops[-1][0] - ball) - sum(e - s for s, e in stops[:-1])
    else:
        restart, played = ball, 0
    target = start + c['A'] + c['iv']                  # original cessation
    while True:                                        # never finish before the original cessation
        K = ceil(overs * c['rate'])
        e1 = restart + max(0, K - played); s2 = e1 + iv; e2 = s2 + K
        if e2 >= target or overs == c['mx']: break
        overs += 1
    return dict(overs=overs, interval=iv, firstEnd=e1, secondStart=s2, matchEnd=e2, extraUsed=extra)

def second(comp, extra_used, scheduled_start, first_ball, overs, stops):
    c = C[comp]
    dur = sum(e - s for s, e in stops)
    ext = min(dur, max(0, c['et'] - extra_used))
    credit = min(dur - ext, max(0, scheduled_start - first_ball))
    net = dur - ext - credit
    lostov = floor(Fr(net) / c['rate'])
    rev = min(c['mx'], overs) - lostov
    restart = stops[-1][1] if stops else first_ball
    played = (restart - first_ball) - dur
    K = ceil(rev * c['rate'])
    return dict(overs=rev, oversLost=lostov, inningsEnd=restart + max(0, K - played))

def t(h, m=0): return h * 60 + m
def hm(x):
    x %= 1440; h, m = divmod(x, 60)
    return f"{(h - 1) % 12 + 1}:{m:02d}{'am' if h < 12 else 'pm'}"

# id, comp, scheduled start, first ball, 1st-innings stoppages, 2nd innings first ball offset from scheduled (min, negative = early), 2nd stoppages (minutes after 2nd innings first ball)
S = [
 ('W1', 'WBBL', t(19,40), t(19,40), [], 0, []),
 ('W2', 'WBBL', t(19,40), t(20,10), [], 0, []),
 ('W3', 'WBBL', t(19,40), t(19,40), [(t(20,0), t(20,20))], 0, []),
 ('W4', 'WBBL', t(19,40), t(19,50), [(t(20,30), t(20,45))], -5, [(30, 47)]),
 ('B1', 'BBL',  t(19,15), t(19,15), [(t(19,45), t(20,5))], 0, []),
 ('B2', 'BBL',  t(19,15), t(19,15), [(t(19,45), t(20,6))], 0, [(40, 60)]),
 ('O1', 'ODC',  t(10,0),  t(10,45), [], 0, []),
 ('O2', 'ODC',  t(10,0),  t(10,0),  [(t(11,0), t(12,10))], 0, [(60, 90)]),
 ('N1', 'WNCL', t(10,0),  t(11,0),  [(t(11,30), t(12,15))], 0, []),
 ('N2', 'WNCL', t(10,0),  t(10,0),  [(t(11,0), t(11,30))], 0, [(60, 110)]),
 ('I1', 'ODI',  t(14,0),  t(14,0),  [(t(14,20), t(15,5))], 0, []),
 ('I2', 'T20I', t(19,0),  t(19,0),  [(t(19,20), t(19,50))], 0, [(30, 47)]),
]
out = []
for sid, comp, st, ball, stops, early, s2 in S:
    f = first(comp, st, ball, stops)
    sched = f['secondStart']; fb2 = sched + early
    sec = second(comp, f['extraUsed'], sched, fb2, f['overs'], [(fb2 + a, fb2 + b) for a, b in s2])
    out.append(dict(id=sid, comp=comp, start=st, ball=ball, stops=stops, secondFirstBall=fb2,
                    secondStops=[(fb2 + a, fb2 + b) for a, b in s2], first=f, second=sec))
json.dump(out, open(sys.argv[1], 'w'), indent=1)
for o in out:
    f, s = o['first'], o['second']
    print(o['id'], o['comp'], f"{f['overs']} a side, break {f['interval']}, 1st ends {hm(f['firstEnd'])}, 2nd starts {hm(f['secondStart'])}, ends {hm(f['matchEnd'])} | 2nd: {s['overs']} ov, ends {hm(s['inningsEnd'])}")
