"""Regenerate the re-export list in offsets_3446.h from offsets_3424.h.

The two headers are kept in sync mechanically rather than by hand: every name the
older build defines and the newer one does not override must be re-exported with a
`using` declaration, or the consumers stop compiling. Doing it by hand already
dropped 37 names once -- including the whole kOp* opcode set, which is exactly the
kind of value that carries across a patch and would have been missed by eye.
"""
import re

OLD = r"src\mod\game\offsets_3424.h"
NEW = r"src\mod\game\offsets_3446.h"

# cp1252: the 3424 header carries a mojibake byte in a comment ("0x?") that is not
# valid UTF-8. Decoding strictly raises, and the file is fine otherwise.
old = open(OLD, encoding="cp1252", errors="replace").read()
new = open(NEW, encoding="utf-8").read()

NAME_RE = re.compile(r"inline constexpr [\w:]+ \s*(\w+)\s*[\[=]")
# A single `inline constexpr` line can declare several names:
#     inline constexpr uint8_t kPinShapeCount = 14, kPinColourCount = 15;
# The regex above only sees the first, so the extras are picked up here.
EXTRA_RE = re.compile(r",\s*(\w+)\s*=")
# Types and non-constexpr entities also have to be re-exported, and they do not
# look like a value declaration at all.
TYPE_RE = re.compile(r"^\s*(?:struct|class|enum(?:\s+class)?)\s+(\w+)", re.M)


def names(text):
    found = set(NAME_RE.findall(text))
    for line in text.splitlines():
        if "inline constexpr" in line:
            found.update(EXTRA_RE.findall(line))
    found.update(TYPE_RE.findall(text))
    return found


overridden = names(new)
need = sorted(n for n in names(old) if n not in overridden)

usings = "\n".join("using build_3424::%s;" % n for n in need)

start = new.index("using build_3424::")
end = new.index("\n", new.rindex("using build_3424::")) + 1

out = new[:start] + usings + "\n" + new[end:]
open(NEW, "w", encoding="utf-8").write(out)
print("re-exported %d names" % len(need))
