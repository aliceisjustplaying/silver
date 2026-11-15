import struct, sys, re
from functools import lru_cache
P = sys.argv[1] if len(sys.argv)>1 and not sys.argv[1].startswith('-') else None
class Cache:
    def __init__(s, path):
        s.f = open(path,'rb').read()
        mo, mc, io, ic = struct.unpack_from('<IIII', s.f, 16)
        s.maps = [struct.unpack_from('<QQQII', s.f, mo+i*32) for i in range(mc)]
        s.images = []
        for i in range(ic):
            a, mt, ino, po, _ = struct.unpack_from('<QQQII', s.f, io+i*32)
            s.images.append((a, s.cstr_off(po)))
    def cstr_off(s, o):
        e = s.f.index(b'\0', o); return s.f[o:e].decode('latin1')
    def off(s, va):
        for a, sz, fo, *_ in s.maps:
            if a <= va < a+sz: return fo + va - a
        return None
    def u32(s, va): return struct.unpack_from('<I', s.f, s.off(va))[0]
    def cstr(s, va):
        o = s.off(va); return s.cstr_off(o) if o is not None else None
    def image(s, name):
        for a, p in s.images:
            if p.split('/')[-1] == name: return MachO(s, a, p)
        raise KeyError(name)
class MachO:
    def __init__(s, c, base, path):
        s.c, s.base, s.path = c, base, path
        o = c.off(base)
        magic, cpu, sub, ft, ncmds, sz, fl = struct.unpack_from('<7I', c.f, o)
        p = o + 28; s.sects = {}; s.segs = {}; s.symtab = None
        for _ in range(ncmds):
            cmd, csz = struct.unpack_from('<II', c.f, p)
            if cmd == 1:
                seg = c.f[p+8:p+24].rstrip(b'\0').decode()
                va, vs, fo, fs, mp, ip, ns, fl = struct.unpack_from('<8I', c.f, p+24)
                s.segs[seg] = (va, vs)
                for k in range(ns):
                    q = p + 56 + k*68
                    sn = c.f[q:q+16].rstrip(b'\0').decode(); sg = c.f[q+16:q+32].rstrip(b'\0').decode()
                    a, z = struct.unpack_from('<II', c.f, q+32)
                    s.sects[(sg, sn)] = (a, z)
            elif cmd == 2:
                s.symtab = struct.unpack_from('<4I', c.f, p+8)
            p += csz
    def symbols(s):
        so, n, sto, ss = s.symtab; out = {}
        for i in range(n):
            sx, ty, sc, de, va = struct.unpack_from('<IBBhI', s.c.f, so + i*12)
            if va == 0: continue
            nm = s.c.cstr_off(sto + sx)
            out[va] = nm
        return out
    def classes(s):
        res = []
        for key in [('__DATA','__objc_classlist')]:
            if key not in s.sects: continue
            a, z = s.sects[key]
            for i in range(z//4):
                cls = s.c.u32(a + 4*i)
                res.append(s.parse_class(cls))
        return res
    def methods(s, ml):
        out = []
        if not ml: return out
        es, cnt = s.c.u32(ml) & 0xfffc, s.c.u32(ml+4)
        for i in range(cnt):
            n, t, imp = (s.c.u32(ml+8+i*es+j*4) for j in range(3))
            out.append((s.c.cstr(n), s.c.cstr(t), imp))
        return out
    def ivars(s, il):
        out = []
        if not il: return out
        es, cnt = s.c.u32(il), s.c.u32(il+4)
        for i in range(cnt):
            offp, n, t, al, sz = (s.c.u32(il+8+i*es+j*4) for j in range(5))
            out.append((s.c.cstr(n), s.c.cstr(t), s.c.u32(offp) if offp else None))
        return out
    def parse_class(s, cls):
        isa, sup, _, _, ro = (s.c.u32(cls + 4*j) for j in range(5))
        ro &= ~3
        name = s.c.cstr(s.c.u32(ro+16))
        meta_ro = s.c.u32(isa+16) & ~3
        supname = None
        if sup: supname = s.c.cstr(s.c.u32((s.c.u32(sup+16) & ~3)+16))
        return dict(name=name, sup=supname, addr=cls,
                    imethods=s.methods(s.c.u32(ro+20)), cmethods=s.methods(s.c.u32(meta_ro+20)),
                    ivars=s.ivars(s.c.u32(ro+28)))

def stub_map(m):
    """map stub/lazy-pointer address -> imported symbol name"""
    c = m.c; o = c.off(m.base)
    ncmds = struct.unpack_from('<I', c.f, o+16)[0]
    p = o + 28; dysym = None; sects = []
    for _ in range(ncmds):
        cmd, csz = struct.unpack_from('<II', c.f, p)
        if cmd == 1:
            ns = struct.unpack_from('<I', c.f, p+48)[0]
            for k in range(ns):
                q = p + 56 + k*68
                a, z, off, al, ro, nr, fl, r1, r2 = struct.unpack_from('<9I', c.f, q+32)
                sects.append((c.f[q:q+16].rstrip(b'\0').decode(), a, z, fl, r1, r2))
        elif cmd == 0xb:
            dysym = struct.unpack_from('<18I', c.f, p+8)
        p += csz
    indoff, nind = dysym[12], dysym[13]
    so, n, sto, ss = m.symtab
    res = {}
    for name, a, z, fl, r1, r2 in sects:
        t = fl & 0xff
        if t == 8 and r2:  # stubs
            for i in range(z // r2):
                si = struct.unpack_from('<I', c.f, indoff + 4*(r1+i))[0]
                if si & 0xc0000000: continue
                res[a + i*r2] = c.cstr_off(sto + struct.unpack_from('<I', c.f, so + si*12)[0])
        elif t in (6, 7):  # pointers
            for i in range(z // 4):
                si = struct.unpack_from('<I', c.f, indoff + 4*(r1+i))[0]
                if si & 0xc0000000: continue
                res[a + i*4] = c.cstr_off(sto + struct.unpack_from('<I', c.f, so + si*12)[0])
    return res
