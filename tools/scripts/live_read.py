"""Read live game memory through cdmp_probe and report stability.

The probe only exposes one read per process, so a scan needs many calls; this
keeps that in one place and parses the output strictly, because a regex that
silently returns 0 for an unparsable line produced a completely wrong value once.

Usage: live_read.py <rva-hex> [count] [--repeat N]
"""
import re
import subprocess
import sys
import time

PROBE = r"C:\Users\ACER\Downloads\Mods\CD-coop-3424\build\bin\RelWithDebInfo\cdmp_probe.exe"

# One or more hex digits, not exactly two: the probe prints small values as
# "(0x0)" and "(0x1)", and requiring two digits silently dropped them -- which
# turned 0x14598BDF8 into 0x12D620000 before the length check caught it.
BYTE_RE = re.compile(r"\(0x([0-9A-Fa-f]+)\)")


def read_bytes(rva, count):
    out = subprocess.run(
        [PROBE, "read", "exe+%X" % rva, "--type", "u8", "--count", str(count)],
        capture_output=True, text=True).stdout
    vals = [int(m, 16) for m in BYTE_RE.findall(out)]
    if len(vals) != count:
        raise RuntimeError("wanted %d bytes, parsed %d from:\n%s" % (count, len(vals), out))
    return vals


def show(label, vals):
    print("  %-8s %s" % (label, " ".join("%02X" % v for v in vals)))


def main():
    rva = int(sys.argv[1], 16)
    count = int(sys.argv[2]) if len(sys.argv) > 2 and not sys.argv[2].startswith("--") else 8
    repeats = 2
    if "--repeat" in sys.argv:
        repeats = int(sys.argv[sys.argv.index("--repeat") + 1])

    print("exe+0x%X  (%d bytes, %d reads)" % (rva, count, repeats))
    first = None
    stable = True
    for i in range(repeats):
        vals = read_bytes(rva, count)
        show("read%d" % (i + 1), vals)
        if first is None:
            first = vals
        elif vals != first:
            stable = False
        if i + 1 < repeats:
            time.sleep(0.4)

    # Assemble the first qword for convenience.
    if count >= 8:
        q = sum(v << (8 * i) for i, v in enumerate(first[:8]))
        print("  as u64   0x%X" % q)
    print("  stable   %s" % ("yes" if stable else "NO -- this address is being written"))


if __name__ == "__main__":
    main()
