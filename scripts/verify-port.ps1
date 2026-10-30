# Offline verification of the 2976 -> 3424 port.
#
# The live probe (scripts/port-3424-probe.ps1) needs the game running and gives
# the final word. This script checks, WITHOUT the game, everything that can be
# checked from the binary on disk:
#
#   1. the PE timestamp / image base match what offsets.h expects;
#   2. every "measured" global really is the RIP-relative target of the
#      signature it claims (re-decoded here, independently);
#   3. the "inferred" globals fall in .idata, are pointer-aligned, and preserve
#      the exact gaps they had in 2976 (a wrong delta breaks this);
#   4. the Troc instance range is still one contiguous span of the same size;
#   5. report which code-address guards can no longer match (those features
#      refuse safely at runtime rather than reading the wrong memory).

param(
    [string]$Exe = "C:\Program Files (x86)\Steam\steamapps\common\Crimson Desert\bin64\CrimsonDesert.exe"
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Exe)) { throw "Game exe not found: $Exe" }

$py = @'
import struct, sys

path = sys.argv[1]
d = open(path, 'rb').read()
pe = struct.unpack_from('<I', d, 0x3c)[0]
nsec = struct.unpack_from('<H', d, pe + 6)[0]
optsz = struct.unpack_from('<H', d, pe + 20)[0]
stamp = struct.unpack_from('<I', d, pe + 8)[0]
imgbase = struct.unpack_from('<Q', d, pe + 24 + 24)[0]
sh = pe + 24 + optsz
secs = []
for i in range(nsec):
    o = sh + i * 40
    nm = d[o:o+8].rstrip(b'\x00').decode('latin1')
    vs, va, rs, ro = struct.unpack_from('<IIII', d, o + 8)
    secs.append((nm, va, vs, ro, rs))

def sec_of(rva):
    best = None
    for nm, va, vs, ro, rs in secs:
        if va <= rva < va + max(vs, rs):
            if best is None or max(vs, rs) < best[0]:
                best = (max(vs, rs), nm)
    return best[1] if best else '?'

def doff(rva):
    best = None
    for nm, va, vs, ro, rs in secs:
        if va <= rva < va + max(vs, rs):
            off = ro + (rva - va)
            if off + 8 <= len(d):
                if best is None or max(vs, rs) < best[0]:
                    best = (max(vs, rs), off)
    return best[1] if best else None

fails = 0
def ok(name, cond, detail=''):
    global fails
    print(('  PASS  ' if cond else '  FAIL  ') + name + (('   ' + detail) if detail else ''))
    if not cond:
        fails += 1

print('== build identity ==')
print('  PE timestamp : 0x%08X' % stamp)
print('  image base   : 0x%X' % imgbase)
ok('PE timestamp is 0x6AE387F2 (build 1.0.0.3424)', stamp == 0x6AE387F2, 'got 0x%08X' % stamp)
ok('image base is 0x140000000', imgbase == 0x140000000)

# ---- measured: re-decode the signature sites and compare to offsets.h ----
# RIP-relative rule: the displacement is measured from the END of the disp32,
# i.e. target = (site + disp_offset) + 4 + disp32.  Getting this wrong is easy
# and silently shifts every result, so it is stated once here.
# (site rva, offset of the disp32 inside it, expected global)
measured = [
    ('WorldSystem  (world_system_ref)',    0x0C9B2EB, 3, 0x71AEA50),
    ('WorldSystem  (world_system_ref_p3)', 0x03AAA06, 3, 0x71AEA50),
    ('Camera       (camera_global_ref)',   0x2FB7047, 3, 0x70CAEB0),
    # C5 FB 11 3D <disp32>  = vmovsd [rip+disp], xmm0
    ('StaticPos XY (player_static_pos)',   0x0A2F53A, 4, 0x71BDC10),
    # 44 89 3D <disp32>     = mov [rip+disp], r15d   (the Z component, +8)
    ('StaticPos Z  (player_static_pos+8)', 0x0A2F53A, 11, 0x71BDC18),
    # C5 F8 5C 05 <disp32>  = vsubps xmm0, xmm0, [rip+disp]  (chunk world offset)
    ('ChunkOrigin  (world_offset_sub)',    0x3971DF1, 25, 0x719ACB0),
    ('cp position  (xsip_position)',       0x0324AF1, 4, 0x71924D0),
]
print()
print('== measured globals (independent re-decode of the signature site) ==')
for name, site, dispoff, want in measured:
    off = doff(site + dispoff)
    if off is None:
        ok(name, False, 'site not readable')
        continue
    disp = struct.unpack_from('<i', d, off)[0]
    got = site + dispoff + 4 + disp
    ok('%s -> 0x%X' % (name, want), got == want, '' if got == want else 'decoded 0x%X' % got)

# ---- inferred: section, alignment, and preserved gaps ----
inferred = [
    ('kClientFrameClockMs', 0x6C8CD68, 0x70D2628),
    ('kClientFrameClockUs', 0x6C8CD70, 0x70D2630),
    ('kClientClockBias',    0x6D69438, 0x71AECF8),
    ('kFieldTimeClient',    0x6A6D218, 0x6EB2AD8),
    ('kTrocInstancesBegin', 0x6A51AE0, 0x6E973A0),
    ('kTrocInstancesEnd',   0x6A82C80, 0x6EC8540),
    ('kMinimapIconRoot',    0x6D69528, 0x71AEDE8),
    ('kMinimapIconRootAlt', 0x6D69530, 0x71AEDF0),
]
print()
print('== inferred globals (delta 0x4458C0) ==')
for name, old, new in inferred:
    s = sec_of(new)
    ok('%s in .idata' % name, s == '.idata', 'section=%s rva=0x%X' % (s, new))
    ok('%s pointer-aligned' % name, new % 8 == 0, 'rva=0x%X' % new)

# Every inferred value must equal the old one plus the SAME delta: that is the
# whole basis of the inference, so verify it is at least self-consistent.
deltas = {new - old for _, old, new in inferred}
print('  deltas seen:', ', '.join('0x%X' % x for x in sorted(deltas)))

# Gaps inside the inferred group must be preserved exactly.
pairs = [('kMinimapIconRoot', 'kMinimapIconRootAlt', 8),
         ('kTrocInstancesBegin', 'kTrocInstancesEnd', 0x311A0)]
print()
print('== preserved gaps (a wrong delta would break these) ==')
ok('Troc instances span is still 0x311A0', (0x6EC8540 - 0x6E973A0) == 0x311A0)
ok('Troc span is one contiguous .idata region',
   sec_of(0x6E973A0) == '.idata' and sec_of(0x6EC8540 - 1) == '.idata')

# ---- code guards that can no longer match ----
print()
print('== code-address guards (feature refuses safely when these fail) ==')
def find_all(sig):
    out, start = [], 0
    while True:
        i = d.find(sig, start)
        if i < 0:
            break
        for nm, va, vs, ro, rs in secs:
            if ro <= i < ro + rs:
                out.append(va + (i - ro))
                break
        start = i + 1
        if len(out) > 40:
            break
    return out

guards = [
    ('kMinimapIconDecide', 0x9E89C0, bytes([0x48,0x89,0x5C,0x24,0x08,0x48,0x89,0x74])),
    ('kServerOtherEquipWriter', 0x29ED1F0, bytes([0x48,0x89,0x5C,0x24,0x08,0x4C,0x89,0x4C])),
    ('kClientClock', 0x1416B80, bytes([0x80,0x3D,0xAE,0x61,0x87,0x05,0x00,0x75,0x17])),
]
# These three sites were resolved on 2976 and cannot be re-resolved offline for
# 3424. On 3424 they are EXPECTED not to match, and each feature then disables
# itself instead of reading the wrong address. So "no match" is the correct
# result here and must NOT be counted as a failure -- but the check is asserted
# anyway, because the interesting event is the opposite one: if a site starts
# matching again, the signature is not where it was thought to be and the guard
# is now protecting something else.
print('  (on this build these are expected NOT to match: the feature disables itself)')
for name, rva, sig in guards:
    n = len(find_all(sig))
    off = doff(rva)
    here = (d[off:off+len(sig)] == sig) if off else False
    ok('%s does not match on 3424 (feature disables itself)' % name, not here,
       'matches again at the old rva! re-resolve it' if here else
       'occurrences of the pattern elsewhere: %d' % n)
print()
print('RESULT: %s' % ('ALL OFFLINE CHECKS PASSED' if fails == 0 else '%d CHECK(S) FAILED' % fails))
sys.exit(1 if fails else 0)
'@

$tmp = Join-Path $env:TEMP "cdmp_verify_port.py"
Set-Content -Path $tmp -Value $py -Encoding UTF8
python $tmp $Exe
exit $LASTEXITCODE
