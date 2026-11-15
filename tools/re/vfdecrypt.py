import sys, struct, hmac, hashlib
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
src, dst, keyhex = sys.argv[1:4]
k = bytes.fromhex(keyhex); aes_key, hmac_key = k[:16], k[16:36]
f = open(src, 'rb'); hdr = f.read(0x100)
assert hdr[:8] == b'encrcdsa', hdr[:8]
bs = struct.unpack('>I', hdr[52:56])[0]
datasize, dataoff = struct.unpack('>QQ', hdr[56:72])
print('blocksize', bs, 'datasize', datasize, 'dataoff', dataoff)
f.seek(dataoff); out = open(dst, 'wb'); n = 0; left = datasize
while left > 0:
    c = f.read(bs)
    if not c: break
    iv = hmac.new(hmac_key, struct.pack('>I', n), hashlib.sha1).digest()[:16]
    d = Cipher(algorithms.AES(aes_key), modes.CBC(iv)).decryptor()
    p = d.update(c) + d.finalize()
    out.write(p[:min(bs, left)]); left -= bs; n += 1
out.close()
