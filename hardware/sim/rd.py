"""rd.py <wrdata file> <names comma> <times comma>  -- print traces at given times
wrdata writes (time, value) pairs per vector, so column 2k+1 is vector k."""
import numpy as np,sys
d=np.loadtxt(sys.argv[1]); names=sys.argv[2].split(','); t=d[:,0]
for ts in [float(x) for x in sys.argv[3].split(',')]:
    i=min(np.searchsorted(t,ts),len(t)-1)
    print(f'{ts:7.3f}',' '.join(f'{n}={d[i,2*k+1]:.3f}' for k,n in enumerate(names)))
