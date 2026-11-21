"""Independent expectations for BBL|16 (2026/27, PCs dated 1 Dec 2026), Appendix J.1 and cl. 12.7.
Written from the PDF text, not from the Swift code."""
import math
def ceil_(x): return math.ceil(round(x,9))
def floor_(x): return math.floor(round(x,9))
A,rate=160,4.0
def table1(C,E=0,D=0):
    F=C-(D+E); G=A-F; H=round(G/rate,2); I=ceil_(H/2); K=ceil_(I*rate); return dict(C=C,E=E,F=F,G=G,H=H,I=I,K=K)
def table4(H,Etime,F=0):
    G=max(0,Etime-F); I=floor_(G/rate); J=H-I; return dict(G=G,I=I,J=J,K=ceil_(J*rate))
def finish(overs):   # cl 12.7.1: 84 min full innings; reduced = overs*4 + 3 (12.8.2.6 one-over allowance NOT added)
    return None if overs<10 else (84 if overs>=20 else overs*4+3)
print('T1 BBL  C=30, interval 15->10 gives E=5 :',table1(30,E=5))
print('T1 BBL  C=22 (interval cut to 10, E=5)  :',table1(22,E=5))
print('T1 BBL  C=20 (interval stays 15, E=0)   :',table1(20,0))
print('T4 BBL  H=20 lost 17                    :',table4(20,17))
print('T4 BBL  H=20 lost 17, 5 early-start cr. :',table4(20,17,5))
print('finish times 20/15/10/9 ov:',[finish(o) for o in (20,15,10,9)])
