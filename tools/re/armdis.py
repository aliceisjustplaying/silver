import sys, struct; sys.path.insert(0, sys.argv[0].rsplit('/',1)[0])
from dsc import Cache, stub_map
from capstone import *
c = Cache(sys.argv[1]); libs = sys.argv[2].split(','); target = sys.argv[3]; n = int(sys.argv[4]) if len(sys.argv)>4 else 200
syms = {}; stubs = {}; byname = {}
for a, p in c.images:
    lib = p.split('/')[-1]
    if lib in libs or lib in ('libobjc.A.dylib','CoreFoundation','Foundation','libSystem.B.dylib','IOKit','CoreSurface','IOSurface','Camera','QuartzCore','Celestial','MediaToolbox','CoreMedia','PhotoLibrary','H1ISP.mediacapture','UIKit','MBX2D','CoreGraphics','IOMobileFramebuffer'):
        m = c.image(lib)
        for va, nm in m.symbols().items():
            syms[va] = nm
            if lib in libs: byname[nm] = va
            else: byname.setdefault(nm, va)
        if lib in libs: stubs.update(stub_map(m))
addr = int(target, 16) if target.startswith('0x') else byname[target]
thumb = addr & 1; addr &= ~1
md = Cs(CS_ARCH_ARM, CS_MODE_THUMB if thumb else CS_MODE_ARM); md.detail = False
code = c.f[c.off(addr): c.off(addr)+n*4]
def desc(v):
    try:
        if syms.get(c.u32(v)) == '___CFConstantStringClassReference':
            return 'cf @' + repr(c.cstr(c.u32(v + 8)))
    except Exception: pass
    if v in syms: return syms[v]
    if v in stubs: return 'stub:'+stubs[v]
    o = c.off(v)
    if o is None: return None
    s = c.f[o:o+80].split(b'\0')[0]
    if len(s) > 2 and all(32 <= b < 127 for b in s): return repr(s.decode())
    # pointer to selector string / cfstring / pointer to symbol
    try:
        w = c.u32(v)
        if w in syms: return '&'+syms[w]
        if w in stubs: return '&'+stubs[w]
        o2 = c.off(w)
        if o2 is not None:
            s = c.f[o2:o2+80].split(b'\0')[0]
            if len(s) > 2 and all(32 <= b < 127 for b in s): return 'sel/ptr '+repr(s.decode())
        # CFString: isa, flags, cstr, len
        w2 = c.u32(v+8); o3 = c.off(w2)
        if o3 is not None:
            s = c.f[o3:o3+80].split(b'\0')[0]
            if len(s) > 2 and all(32 <= b < 127 for b in s): return 'cf @'+repr(s.decode())
    except Exception: pass
    return None
lit = {}
def gen():
    pos = 0
    while pos < len(code):
        got = False
        for i in md.disasm(code[pos:], addr+pos):
            got = True; yield i; pos = i.address - addr + i.size
        if pos < len(code):
            print(f'{addr+pos:08x}  .word    0x{struct.unpack_from("<I", code, pos)[0]:08x}'); pos += 4
for i in gen():
    if i.address != addr and i.address in syms: print(f'---- {syms[i.address]}'); 
    note = ''
    ops = [o.strip() for o in i.op_str.replace('[','').replace(']','').split(',')]
    if not thumb and len(ops) == 3 and ops[1] == 'pc' and ops[2] in lit and ops[0] == ops[2] and i.mnemonic in ('add', 'ldr'):
        tgt = i.address + 8 + lit[ops[2]]
        if i.mnemonic == 'add':
            note = f'-> 0x{tgt:x} {desc(tgt) or ""}'
        else:
            w = c.u32(tgt); note = f'*0x{tgt:x} = 0x{w:x} {stubs.get(tgt) and "&"+stubs[tgt] or desc(w) or ""}'
        lit.pop(ops[2], None)
        print(f'{i.address:08x}  {i.mnemonic:8} {i.op_str:30} {note}'); continue
    if i.mnemonic.startswith('ldr') and '[pc' in i.op_str:
        try:
            off = int(i.op_str.split('#')[-1].rstrip(']'), 0) if '#' in i.op_str else 0
            pa = (i.address + (4 if thumb else 8)) & ~3 if thumb else i.address + 8
            v = c.u32(pa + off); d = desc(v); lit[ops[0]] = v
            note = f'=0x{v:x} {d or ""}'
        except Exception as e: note = str(e)
    elif i.mnemonic in ('bl','blx','b') and i.op_str.startswith('#'):
        v = int(i.op_str[1:], 16); note = desc(v) or ''
    print(f'{i.address:08x}  {i.mnemonic:8} {i.op_str:30} {note}')
    if i.mnemonic in ('pop','ldm','ldmia') and 'pc' in i.op_str and n < 0: break
