import sys; sys.path.insert(0, sys.argv[0].rsplit('/',1)[0])
from dsc import Cache
c = Cache(sys.argv[1]); m = c.image(sys.argv[2])
pat = sys.argv[3] if len(sys.argv)>3 else ''
for k in m.classes():
    if pat not in k['name']: continue
    print(f"@interface {k['name']} : {k['sup']}  // {k['addr']:#x}")
    for n,t,o in k['ivars']: print(f"    {t} {n}; // +{o}")
    for n,t,imp in k['cmethods']: print(f"  + {n}  {t}  @{imp:#x}")
    for n,t,imp in k['imethods']: print(f"  - {n}  {t}  @{imp:#x}")
    print('@end')
