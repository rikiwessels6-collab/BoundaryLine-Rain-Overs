"""Independent expectations for ICC Men's ODI / T20I (PCs effective Oct 2026), Appendix E Tables 1 & 4.
Written from the PDF worksheets, not from the Swift code. Pure Python, no app code."""
import math
def ceil_(x): return math.ceil(round(x,9))
def floor_(x): return math.floor(round(x,9))
SPEC={'ODI':dict(A=420,rate=4.2,H_round2=False,maxov=50,interval=30),
      'T20I':dict(A=170,rate=4.25,H_round2=True,maxov=20,interval=15)}
def table1(f,C,D_agreed):
    s=SPEC[f]; D=min(C,D_agreed); F=C-D; G=s['A']-F
    H=round(G/s['rate'],2)          # "to 2 decimal places" on the form
    I=ceil_(H/2); K=ceil_(I*s['rate']); return dict(C=C,D=D,F=F,G=G,H=H,I=I,K=K)
def table4(f,H,E,F_unused):
    s=SPEC[f]; G=E-F_unused; G=max(0,G)
    I=floor_(G/s['rate']); J=H-I; K=ceil_(J*s['rate']); return dict(G=G,I=I,J=J,K=K)
print('T1 ODI  C=45  extra0 ',table1('ODI',45,0))
print('T1 ODI  C=45  extra60',table1('ODI',45,60))
print('T1 T20I C=30  extra0 ',table1('T20I',30,0))
print('T1 T20I C=30  extra30',table1('T20I',30,30))
print('T1 T20I C=100 extra0 ',table1('T20I',100,0))
print('T4 ODI  H=50 E=30 F=0  ',table4('ODI',50,30,0))
print('T4 ODI  H=50 E=30 F=15 (early start credit)',table4('ODI',50,30,15))
print('T4 ODI  H=50 E=30 pool 10 left',table4('ODI',50,30,10))
print('T4 T20I H=20 E=17 F=0  ',table4('T20I',20,17,0))
print('T4 T20I H=20 E=20 F=0  ',table4('T20I',20,20,0))
print('bowler caps T20I: 5-9 ->2; 10->2; 13->',math.ceil(13/5),'; 20->',math.ceil(20/5),'  ODI 50->',math.ceil(50/5),' 21->',math.ceil(21/5))
