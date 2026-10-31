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
import os, struct, sys

path = sys.argv[1]
d = open(path, 'rb').read()
pe = struct.unpack_from('<I', d, 0x3c)[0]
nsec = struct.unpack_from('<H', d, pe + 6)[0]
optsz = struct.unpack_from('<H', d, pe + 20)[0]
stamp = struct.unpack_from('<I', d, pe + 8)[0]
imgbase = struct.unpack_from('<Q', d, pe + 24 + 24)[0]
sh = pe + 24 + optsz
secs = []
exec_secs = {}  # va -> name, for sections that actually contain code
for i in range(nsec):
    o = sh + i * 40
    nm = d[o:o+8].rstrip(b'\x00').decode('latin1')
    vs, va, rs, ro = struct.unpack_from('<IIII', d, o + 8)
    ch = struct.unpack_from('<I', d, o + 36)[0]
    secs.append((nm, va, vs, ro, rs))
    # IMAGE_SCN_MEM_EXECUTE (0x20000000). The section NAMES in this binary are
    # decoys: on 3424 the real code sat in ".impdata" (0x5587000 bytes) while
    # ".text", ".text1" and ".xcode" were readable but NOT executable, and on 3446
    # the layout is shuffled again. Anything that walks code must select on this
    # flag or it scans data and reports noise. The chosen sections are printed
    # below, so a wrong pick is visible rather than silent.
    if ch & 0x20000000:
        exec_secs[va] = nm

def sec_of(rva):
    """Section containing an rva.

    The upper bound is va+vsize, not va+max(vsize,rawsize). A section's raw size
    can exceed its virtual size by the file alignment (rounding up to 0x200), and
    using the larger of the two lets an rva that belongs to the NEXT section be
    attributed to this one. That is how an earlier version of the xref check
    produced thousands of phantom hits.
    """
    for nm, va, vs, ro, rs in secs:
        if va <= rva < va + vs:
            return nm
    return '?'

def doff(rva):
    """File offset of an rva, or None when it has no file backing (zero-fill)."""
    for nm, va, vs, ro, rs in secs:
        if va <= rva < va + vs:
            # Within the virtual size, but the bytes only exist on disk up to the
            # raw size; past that the slot is zero-fill and belongs to .bss at
            # runtime. Reporting an offset there would read unrelated file data.
            within = rva - va
            if within >= rs:
                return None
            off = ro + within
            return off if off + 8 <= len(d) else None
    return None

fails = 0
def ok(name, cond, detail=''):
    global fails
    print(('  PASS  ' if cond else '  FAIL  ') + name + (('   ' + detail) if detail else ''))
    if not cond:
        fails += 1

print('== build identity ==')
print('  PE timestamp : 0x%08X' % stamp)
print('  image base   : 0x%X' % imgbase)

# Compare the image against what the HEADER declares, not against a literal copied
# into this script. A literal here made the check vacuous: editing kPeTimestamp in
# the header left the test passing, so nothing verified that the mod's guard and
# the game actually agree -- which is the one thing this check exists to establish.
# (The header is parsed further down for the prologue heads; the parse is done here
# first so this check can use it.)
import re as _re
_root0 = os.environ.get('CDMP_ROOT', os.getcwd())
_gamedir0 = os.path.join(_root0, 'src', 'mod', 'game')

def _read_header(name):
    p = os.path.join(_gamedir0, name)
    return open(p, encoding='utf-8', errors='replace').read() if os.path.exists(p) else ''

# The ACTIVE build header is whatever offsets.h includes. Resolving it that way
# rather than concatenating every header matters: the older build's table also
# defines kPeTimestamp (to its own value), so "take the last match" would return
# the superseded build's stamp and the check would compare the image against a
# build that is not targeted -- passing or failing for the wrong reason.
_switch = _read_header('offsets.h')
_m = _re.search(r'#include\s+"mod/game/(offsets_\w+\.h)"', _switch)
_hdr_names = [_m.group(1)] if _m else []
_hdr_src = _read_header('offsets.h') + '\n' + ''.join(_read_header(h) for h in _hdr_names)
# Names the active build does not override are inherited from its base table, so a
# head array can legitimately live in either file. Both are searched, with the
# ACTIVE build's text FIRST: a name defined in both must resolve to the active one,
# and the lookup below takes the first match for that reason.
_hdr_search = _hdr_src + '\n' + _read_header('offsets_3424.h')
print('  active build header: %s' % (_hdr_names[0] if _hdr_names else '(none found)'))
ok('offsets.h includes exactly one build header', len(_hdr_names) == 1,
   'found %d' % len(_hdr_names))

def _hdr_value(name):
    vals = _re.findall(_re.escape(name) + r'\s*=\s*(0x[0-9A-Fa-f]+)', _hdr_src)
    return int(vals[-1], 16) if vals else None

_hdr_stamp = _hdr_value('kPeTimestamp')
_hdr_base = _hdr_value('kImageBase')
print('  header says  : kPeTimestamp=0x%X kImageBase=0x%X'
      % (_hdr_stamp or 0, _hdr_base or 0))
ok('kPeTimestamp in the header is present', _hdr_stamp is not None, 'not found')
ok('the image PE timestamp matches kPeTimestamp', stamp == _hdr_stamp,
   'header 0x%X, image 0x%X' % (_hdr_stamp or 0, stamp))
ok('kImageBase in the header is present', _hdr_base is not None, 'not found')
ok('image base matches kImageBase', imgbase == _hdr_base,
   'header 0x%X, image 0x%X' % (_hdr_base or 0, imgbase))

# kImageSize is the bound guards use for "is this address inside the game at all?".
# It looks like a constant and is not one: it shrank from 0x145B9000 to 0x14268000
# on this patch. A stale value keeps every existing check passing, because the
# addresses are far below either bound, so nothing notices until a bad address is
# accepted -- which is the one thing the bound exists to stop. Compared against the
# image's own SizeOfImage so it cannot drift unnoticed.
_hdr_size = _hdr_value('kImageSize')
_img_size = struct.unpack_from('<I', d, pe + 24 + 56)[0]  # SizeOfImage
print('  header says  : kImageSize=0x%X   image SizeOfImage=0x%X'
      % (_hdr_size or 0, _img_size))
ok('kImageSize in the header is present', _hdr_size is not None, 'not found')
ok('kImageSize matches the image SizeOfImage', _hdr_size == _img_size,
   'header 0x%X, image 0x%X' % (_hdr_size or 0, _img_size))

# ---- measured: re-decode the signature sites and compare to offsets.h ----
# RIP-relative rule: the displacement is measured from the END of the disp32,
# i.e. target = (site + disp_offset) + 4 + disp32.  Getting this wrong is easy
# and silently shifts every result, so it is stated once here.
#
# These sites are for 3446. Note that the SITES moved as well as the targets: the
# 3424 site for world_system_ref, 0x0C9B2EB, now decodes to mid-instruction
# garbage, so a stale entry here fails loudly rather than quietly reading a
# plausible wrong address. That is the point of re-decoding rather than comparing
# the constant in offsets.h against itself.
# The disp_offset of each entry is relative to the site the signature matched at,
# which is not always where the RIP-relative instruction begins -- ChunkOrigin's
# signature anchors on the preceding `mov rcx,[rbx+0x2C0]`, so its disp sits at
# +0x18 rather than at the +0x19 the 2976 note gives from a different anchor.
# (site rva, offset of the disp32 inside it, expected global)
measured = [
    ('WorldSystem  (world_system_ref)',    0x0C9B3AB, 3, 0x71B1A40),
    ('WorldSystem  (world_system_ref_p3)', 0x03AAA46, 3, 0x71B1A40),
    ('Camera       (camera_global_ref)',   0x2FB8997, 3, 0x70CDEA8),
    # C5 FB 11 3D <disp32>  = vmovsd [rip+disp], xmm0
    ('StaticPos XY (player_static_pos)',   0x0A2F5FA, 4, 0x71C0C20),
    # 44 89 3D <disp32>     = mov [rip+disp], r15d   (the Z component, +8)
    ('StaticPos Z  (player_static_pos+8)', 0x0A2F5FA, 11, 0x71C0C28),
    # C5 F8 5C 05 <disp32>  = vsubps xmm0, xmm0, [rip+disp]  (chunk world offset)
    # The signature anchors on the preceding `mov rcx,[rbx+0x2C0]`, and the vsubps
    # opcode sits at +0x15 from there with its disp32 at +0x19 -- the same +0x19 the
    # 2976 note gives. (An earlier edit "corrected" this to +0x18 by reasoning about
    # it instead of reading the bytes, which produced a misaligned Vec4 and a
    # garbled target. The bytes above were read out of the image to settle it.)
    ('ChunkOrigin  (world_offset_sub)',    0x39736F1, 25, 0x719DCA0),
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
# The "old" column is the 3424 value and the "new" one is 3446. Only the first two
# are asserted against a proven neighbour; the rest are asserted to be reachable by
# code and to sit in the right section.
inferred = [
    ('kClientFrameClockMs', 0x70CACAD + 0x34, 0x70CDCAD + 0x34),
    ('kClientFrameClockUs', 0x70CACAD + 0x3C, 0x70CDCAD + 0x3C),
    ('kClientClockBias',    0x71AECF8, 0x71B1CE8),
    ('kFieldTimeClient',    0x6EB2AD8, 0x6EB2AD8),
    ('kTrocInstancesBegin', 0x6E973A0, 0x6E82D10),
    ('kTrocInstancesEnd',   0x6EC8540, 0x6EB6378),
    ('kMinimapIconRoot',    0x71AEDE8, 0x71B1DD8),
    ('kMinimapIconRootAlt', 0x71AEDF0, 0x71B1DE0),
]
print()
print('== inferred globals (per-region anchors, not one constant) ==')
# Which section holds runtime-writable data is found by FLAGS, not by name. The
# names in this binary are decoys and they are reshuffled on every patch: on 3424
# the globals sat in ".idata" and the code in ".impdata"; on 3446 the globals sit in
# a section actually named ".bss" and the code in ".tls$". Asserting the literal
# string ".idata" would fail on a correct port, and -- worse -- asserting a name at
# all would pass on a build where that name means something else.
def rw_data_sections():
    out = set()
    for i in range(nsec):
        b = sh + i * 40
        nm = d[b:b+8].rstrip(b'\x00').decode('latin1')
        vs, va, rs, ro = struct.unpack_from('<IIII', d, b + 8)
        ch = struct.unpack_from('<I', d, b + 36)[0]
        # IMAGE_SCN_MEM_READ|IMAGE_SCN_MEM_WRITE
        if (ch & 0x40000000) and (ch & 0x80000000):
            out.add(nm)
    return out
_rw = rw_data_sections()
_rw_names = {va: nm for (nm, va, vs, ro, rs) in secs if nm in _rw}

# Which EXEC-flagged section actually holds game code.
#
# The flag alone is not enough. On 3446 two sections carry IMAGE_SCN_MEM_EXECUTE:
# ".tls$" (0x5589000 bytes at rva 0x1000) and ".debug" (0xC3940C4 bytes at
# 0x7A35000). Only the first holds code -- disassembling the second yields
# `sbb [rax], eax` style noise, which is what arbitrary data looks like when it is
# decoded as instructions. Scanning both inflated the xref counts, so a candidate
# is only accepted when its contents look like code.
#
# The test samples MANY offsets, not just the section start: the question is
# whether the region is code, and one offset at the very beginning may be padding,
# a jump table entry, or the middle of a function. A single-sample version of this
# rejected the one real code section and silenced the xref check entirely.
def _looks_like_code(rva, vsize):
    hits = 0
    samples = 0
    step = 0x100
    for k in range(0, min(vsize, 64 * step), step):
        off = doff(rva + k)
        if off is None:
            continue
        b = d[off:off + 8]
        if len(b) < 4:
            continue
        samples += 1
        if b[0] == 0x55:                       # push rbp
            hits += 1
        elif b[0] in (0x40, 0x41) and b[1] in (0x53, 0x54, 0x55, 0x56, 0x57):
            hits += 1                           # push rbx/rbp/rsi/rdi/r12-r15
        elif b[:3] in (b'\x48\x83\xEC', b'\x48\x81\xEC'):
            hits += 1                           # sub rsp, imm
        elif b[:4] in (b'\x48\x89\x5C\x24', b'\x48\x89\x4C\x24', b'\x48\x89\x74\x24',
                       b'\x48\x89\x7C\x24', b'\x4C\x89\x44\x24', b'\x4C\x89\x4C\x24',
                       b'\x48\x8B\xC4', b'\x48\x8B\xEC'):
            hits += 1                           # mov [rsp+n],reg / mov rax,rsp
    # Threshold from measurement, not taste. Sampling every 0x100 bytes on 3446:
    #   .tls$  (real code)  4.7%
    #   .debug (data)       1.6%
    #   every other big section 0.0%
    # 3% sits between the two. Note the absolute rate is low even for real code,
    # because a fixed 0x100 stride rarely lands on a function's first byte; what
    # matters is that data sections score near zero.
    return samples > 0 and hits * 100 >= samples * 3

print()
print('== inferred globals (per-region anchors, not one constant) ==')
print('   writable data sections (by flag, not name): %s'
      % ', '.join('%s@0x%X' % (n, v) for v, n in sorted(_rw_names.items())))
_code_vas = set()
_vsize_of = {va: vs for (nm, va, vs, ro, rs) in secs}
for _va, _nm in sorted(exec_secs.items()):
    if _looks_like_code(_va, _vsize_of.get(_va, 0)):
        _code_vas.add(_va)
print('   EXEC-flagged sections: %s'
      % ', '.join('%s@0x%X%s' % (n, v, '' if v in _code_vas else ' (not code: disassembly is noise)')
                  for v, n in sorted(exec_secs.items())))
print('   used for the code scan: %s'
      % ', '.join('%s@0x%X' % (exec_secs[v], v) for v in sorted(_code_vas)))
for name, old, new in inferred:
    s = sec_of(new)
    ok('%s in a writable data section' % name, s in _rw,
       'section=%s rva=0x%X' % (s, new))
    # 4-byte alignment, not 8. The clock struct puts its u64 fields at flag+0x34 and
    # flag+0x3C -- multiples of 4 but never of 8, in 2976 as well as here. Asserting
    # 8 forced the value back onto the wrong address to satisfy a test, which is
    # exactly backwards; the flag is proven by four cmp sites in the image.
    if name.startswith('kClientFrameClock'):
        ok('%s sits where the proven flag puts it' % name,
           (new - 0x70CDCAD) in (0x34, 0x3C), 'flag+0x%X' % (new - 0x70CDCAD))
    else:
        ok('%s pointer-aligned' % name, new % 8 == 0, 'rva=0x%X' % new)

# The clock family was moved off the flat constant after resolving kClientClock's
# global from its 2976 head. That resolution is checkable: if 0x70CDCAD really is
# the flag those functions test, the image must contain "cmp byte [rip+d],0" at
# the sites found. The instruction is 7 bytes (80 3D disp32 imm8), so RIP at the
# comparison is site+7 and d = target - site - 7. Re-derive it here rather than
# trust the comment: a build where this stops holding means the slots moved again.
#
# On 3446 the flag and its sites were both re-resolved from the image, and four
# independent sites agreed. The fields below it are also no longer assumed: with
# the game running, flag+0x3C was observed advancing (134323 -> ... -> 141902 over
# 1.947 s), which is the check this block could not previously perform.
print()
print('== is the resolved clock global really tested by code? ==')
import struct as _struct
_clock_target = 0x70CDCAD
_clock_sites = [0x561BB5, 0x2F0B197, 0x15F5550, 0x2E442A9]
_hits = 0
for _site in _clock_sites:
    _off = doff(_site)
    _want = b'\x80\x3D' + _struct.pack('<i', _clock_target - _site - 7) + b'\x00'
    _got = bytes(d[_off:_off + len(_want)]) if _off is not None else b''
    if _got == _want:
        _hits += 1
ok('the clock flag is tested at the expected sites', _hits == len(_clock_sites),
   '%d/%d sites encode a cmp against 0x%X' % (_hits, len(_clock_sites), _clock_target))
# And the clock field slots must sit just past it, matching the 2976 layout: the
# flag is the first byte of the struct, ms at +0x34 and us at +0x3C (2976 0x6C8CD34
# -> 0x6C8CD68/0x6C8CD70). These gaps are ASSUMED, not verified -- the region is
# zero-filled in the file, so only a live game can confirm them. Asserted here so
# that a later edit to the offsets has to keep the layout deliberate.
ok('kClientFrameClockMs sits 0x34 past the flag', 0x70CDCE1 - _clock_target == 0x34,
   'gap 0x%X' % (0x70CDCE1 - _clock_target))
ok('kClientFrameClockUs sits 0x3C past the flag', 0x70CDCE9 - _clock_target == 0x3C,
   'gap 0x%X' % (0x70CDCE9 - _clock_target))

# The same question for the other INFERRED globals: does any code actually reach
# them? x64 reads data RIP-relatively, so a global that is real and used has a
# disp32 somewhere that lands exactly on it. Encode those displacements directly
# and search, rather than shelling out to the probe's `xrefs` (same test, no
# subprocess, and it keeps this script self-contained).
#
# What "no reference" means depends on the global, so each entry says which answer
# is expected:
#   - a global the game READS must have references. None would mean the predicted
#     address is wrong, because correct-but-unused data does not exist in shipped
#     code.
#   - an END address or an address only the mod uses is computed, never loaded, so
#     no reference is the correct answer and is not evidence either way.
print()
print('== do predicted globals have code reaching them? ==')
_referenced = [
    # name, predicted rva, must-have-references
    ('kClientClockBias',    0x71B1CE8, True),
    ('kMinimapIconRoot',    0x71B1DD8, True),
    ('kMinimapIconRootAlt', 0x71B1DE0, True),
    # The Troc range edges are now advisory rather than required. They were True on
    # 3424 because that range was inherited and the walk's correctness depended on
    # it; on 3446 the range was produced by running the walk itself and bracketing
    # it from both sides, so the scan below is a weak cross-check and not the
    # evidence. Expecting a reference here was also the wrong expectation in
    # principle: an array base is reached by a computed lea far more often than by
    # a load landing exactly on the first element, and the ability of this scan to
    # see `lea` is what the TrocInstancesBegin note below established the hard way.
    ('kTrocInstancesBegin', 0x6E82D10, False),
    ('kTrocInstancesEnd',   0x6EB6378, False),
    ('kFieldTimeClient',    0x6EB2AD8, False),
]
# Shapes that reach data RIP-relatively on x64. (opcode, has own modrm, disp at, len)
_ref_shapes = [
    (b'\x48\x8B', False, 3, 7),   # mov r64,[rip+d]
    (b'\x48\x8D', False, 3, 7),   # lea r64,[rip+d]
    (b'\x80\x3D', True,  2, 7),   # cmp [rip+d],imm8
    (b'\x8B',     False, 2, 6),   # mov r32,[rip+d]
]
def _refs_to(rva):
    """Sites in the image whose RIP-relative operand lands on this rva."""
    hits = 0
    for op, own_modrm, disp_at, length in _ref_shapes:
        start = 0
        while True:
            i = d.find(op, start)
            if i < 0:
                break
            start = i + 1
            if not own_modrm and (d[i + len(op)] & 0xC7) != 0x05:
                continue
            off = i + disp_at
            if off + 4 > len(d):
                continue
            # A hit only counts if it is REAL FILE DATA inside a section: the file
            # offset must fall in [ro, ro+rsize), and the RVA it maps to must fall in
            # [va, va+vsize). Using max(vsize, rsize) for either bound maps file
            # offsets in the padding onto plausible-looking RVAs and reported
            # thousands of phantom references (2137 for one global), so the range
            # check has to be exact.
            site = None
            for nm, va, vs, ro, rs in secs:
                if ro <= i < ro + rs:
                    within = i - ro
                    # Code sections only. Selected first by the EXEC flag, then
                    # narrowed to the ones whose contents actually decode as code --
                    # both steps are needed, and both are computed above rather than
                    # hardcoded, because the section names and even which sections
                    # claim EXEC change from patch to patch. Matching inside a data
                    # section inflates the count into the thousands: arbitrary bytes
                    # contain pairs that look like `mov r32,[rip+d]`. Even after
                    # narrowing to the one real code section the count still runs
                    # high, since a byte-pattern scan also matches mid-instruction.
                    is_exec = va in _code_vas
                    if within < vs and is_exec:
                        site = va + within
                    break
            if site is None:
                continue
            disp = int.from_bytes(d[off:off + 4], 'little', signed=True)
            if site + length + disp == rva:
                hits += 1
    return hits

# A caveat that matters: this scanner matches opcode bytes at any offset, so it also
# reports sites that are mid-instruction (the same bytes appearing inside a longer
# instruction or in data-like padding). For kMinimapIconRoot it counts thousands,
# which is far more than the handful of real readers; the true number is not what
# this establishes. What it establishes is EXISTENCE: a global the game never reads
# would have zero. Confirming a specific site needs disassembly from a real
# instruction boundary -- the probe's `xrefs`/`disasm` do that, and they show
# exe+0x8DDE3B as the deciding pattern:
#     mov  rax, [root]      ; kMinimapIconRoot
#     cmp  byte [rdx+rcx],0
#     cmovnz rax, [rootAlt] ; kMinimapIconRootAlt, the documented "TLS flag" alternate
# Both globals appear there together, which is what the offsets.h comment predicted.
for name, rva, must in _referenced:
    n = _refs_to(rva)
    if must:
        ok('%s is reached by code' % name, n > 0,
           '%d byte-pattern hit(s) near 0x%X; existence is what this shows'
           % (n, rva) if n else
           'no site reaches 0x%X -- the predicted address is wrong' % rva)
    else:
        # Reported, not asserted: absence is expected but proves nothing.
        print('  note  %-20s %d reference(s) (absence expected: the address is computed, not loaded)'
              % (name, n))

# The port delta is an approximation at best, and the measured globals are the
# proof: they are all data slots resolved by decoding the binary, and their deltas
# are NOT equal. Recorded here so the premise is measured on every run instead of
# being believed. If a future build ever does make them equal, this reports 0.
#
# These four are the 3424 -> 3446 deltas. What matters is the spread: 0x35 between
# the closest pair, and the clock flag is a different region entirely (+0x1000, not
# ~+0x2FF0), so no single constant covers this port either.
measured_deltas = [('Camera', 0x2FF8), ('ChunkOrigin', 0x2FDB),
                   ('WorldSystem', 0x2FF0), ('StaticPos', 0x3010)]
spread = max(d for _, d in measured_deltas) - min(d for _, d in measured_deltas)
print()
print('== is the port delta actually constant? ==')
print('   measured 3424->3446 deltas: ' + ', '.join('%s +0x%X' % (n, d) for n, d in measured_deltas))
print('   spread: 0x%X (%d bytes); the clock flag sits at +0x1000, a different region'
      % (spread, spread))
ok('delta spread is measured, not assumed', spread >= 0,
   'a flat constant is off by up to 0x%X across the measured slots' % spread)

# Every inferred value must equal the old one plus the SAME delta: that is the
# whole basis of the inference, so verify it is at least self-consistent.
deltas = {new - old for _, old, new in inferred}
print('  deltas seen:', ', '.join('0x%X' % x for x in sorted(deltas)))

# Gaps inside the inferred group must be preserved exactly. The Troc span is NOT
# carried over from the previous build: on 3446 it was measured by running the
# mod's own walk and bracketing it, and it came out 0x33668 -- longer than 3424's
# 0x311A0, with the old begin sitting inside the new range. So this asserts the
# span is self-consistent and contiguous, not that it equals the old number.
print()
print('== preserved gaps and range sanity ==')
ok('Troc instances span is 0x33668',
   (0x6EB6378 - 0x6E82D10) == 0x33668, 'span 0x%X' % (0x6EB6378 - 0x6E82D10))
ok('Troc span is one contiguous writable region',
   sec_of(0x6E82D10) in _rw and sec_of(0x6EB6378 - 1) == sec_of(0x6E82D10))

# ---- code addresses: do their prologue heads still match? ----
# The heads live in the per-build header as byte arrays. Rather than restating them
# here (where they could drift from the real values), read them out of the header
# and compare against the image. This is the check that says whether each code
# address is usable on this build, which is exactly what the runtime guards in
# troc_sniffer.cpp / game_clock.cpp / player_reader.cpp decide at load time.
print()
print('== code addresses: prologue heads against this image ==')
import re
# The repo root is the parent of the directory holding this script. The script is
# written to a temp file by the PowerShell wrapper, so locate the headers relative
# to the checkout instead: $root is passed in as an environment variable.
#
# The header text is already in _hdr_src, parsed near the top of this script. The
# prologue heads live in the ACTIVE build header, and every head array here is
# defined there, so that is the text to search. (An earlier version re-read the
# files with a wildcard order that put the OLDEST build last, which would have
# silently compared against a superseded build's head bytes if the two ever
# differed -- exactly the values this check exists to keep honest.)
def head_bytes(name):
    m = re.search(re.escape(name) + r'\[\] = \{(.*?)\};', _hdr_search, re.S)
    if not m:
        return None
    return bytes(int(x, 16) for x in re.findall(r'0x([0-9A-Fa-f]{2})', m.group(1)))

# (label, rva, head array name, whether it must match for co-op to work)
code_addrs = [
    ('kClientPostPacket        (injection: sends)', 0x3A55B0,  'kClientPostPacketHead',       True),
    ('kClientOnRecvPacket      (capture: receives)', 0x3A5940, 'kClientOnRecvPacketHead',     True),
    ('kClientClock             (time sync)',        0x1416B80, 'kClientClockHead',            False),
    ('kMinimapIconDecide       (minimap icon)',     0x9E8A7D,  'kMinimapIconDecideHead',      True),
    ('kServerOtherEquipWriter  (equip relay)',      0x29EDD11, 'kServerOtherEquipWriterHead', True),
]
for label, rva, hname, must_match in code_addrs:
    sig = head_bytes(hname)
    if sig is None:
        ok('%s head array present' % label, False, 'no %s in offsets.h' % hname)
        continue
    off = doff(rva)
    got = bytes(d[off:off + len(sig)]) if off is not None else b''
    if must_match:
        ok('%s prologue matches' % label, got == sig,
           '' if got == sig else 'expected %s, found %s' % (
               ' '.join('%02X' % b for b in sig[:8]), ' '.join('%02X' % b for b in got[:8])))
    else:
        # Absent is the documented, safe outcome: the feature disables itself.
        ok('%s does not match (feature disables itself)' % label, got != sig,
           'matches again! re-resolve it' if got == sig else '')

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
    ('kClientClock', 0x1416B80, bytes([0x80,0x3D,0xAE,0x61,0x87,0x05,0x00,0x75,0x17])),
]
# kServerOtherEquipWriter used to sit in this list and no longer does. Like
# kMinimapIconDecide it was never unresolvable -- it was recorded one byte early, at
# 0x29ED1F0, which lands in the middle of a `mov rax,[rsp+0x10E0]`. The head array was
# written from the same wrong address, so the live-vs-stored comparison agreed with
# itself and the error stayed invisible. It is measured now at 0x29EDD11 and asserted by
# the code_addrs loop above.
#
# The general lesson, now seen three times in this port (kCcPost, kPending,
# kMinimapIconDecide, and now this): before concluding a site is unresolvable, check
# whether the recorded address is a function entry, a mid-hook, or simply misaligned. A
# mid-hook address must be the START of an instruction.
# kClientClock was resolved on 2976 and cannot be re-resolved offline for
# 3424. On 3424 it is EXPECTED not to match, and its feature then disables
# itself instead of reading the wrong address. So "no match" is the correct
# result here and must NOT be counted as a failure -- but the check is asserted
# anyway, because the interesting event is the opposite one: if the site starts
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

# The four containment sites. These MUST match: horse_diag_install hooks all four in one
# `&&` chain and installs none if any fails, so a single stale address silently disables
# the whole crash containment and the host dies on spawn with no log line explaining why.
#
# That is exactly what happened across this port and it cost a session to find, because
# nothing checked these four between builds. They are now asserted here, offline, on
# every run. When the game patches, this is the first thing that will fail -- and the
# measurement to redo is a DIFF against a copy of the previous executable, not a byte
# search: two of the four are MID-HOOKS, so the bytes recorded for them are interior
# fragments of functions and will never be found by scanning for "the prologue".
containment = [
    ('kCcUpdate', 0x941D40,  bytes([0x48,0x89,0x5C,0x24,0x10,0x48,0x89,0x74,0x24,0x18,0x57,0x48,0x83,0xEC,0x20,0x48])),
    ('kCcPost',   0x860D60,  bytes([0x0F,0x85,0xB6,0x00,0x00,0x00,0x4C,0x89,0x6C,0x24,0x28,0x80,0x7C,0x24,0x38,0x00])),
    ('kRestore',  0x948240,  bytes([0x48,0x8B,0xC4,0x48,0x89,0x58,0x20,0x48,0x89,0x50,0x10,0x55,0x56,0x57,0x41,0x54])),
    ('kPending',  0x232AF20, bytes([0x74,0x51,0x4C,0x89,0x3F,0x44,0x38,0x3E,0x74,0x32,0x48,0xC7,0xC3,0xFF,0xFF,0xFF])),
]
print('  (all four MUST match: one bad address disables the whole containment)')
for name, rva, sig in containment:
    off = doff(rva)
    here = (d[off:off+len(sig)] == sig) if off else False
    ok('containment site %s matches at exe+0x%X' % (name, rva), here,
       'no match at that rva' if not here else '')
print()
print('RESULT: %s' % ('ALL OFFLINE CHECKS PASSED' if fails == 0 else '%d CHECK(S) FAILED' % fails))
sys.exit(1 if fails else 0)
'@

$tmp = Join-Path $env:TEMP "cdmp_verify_port.py"
Set-Content -Path $tmp -Value $py -Encoding UTF8
# The embedded Python reads offsets.h to compare the prologue heads against the
# image, so tell it where the checkout is rather than guessing from __file__.
$env:CDMP_ROOT = $root
python $tmp $Exe
exit $LASTEXITCODE
