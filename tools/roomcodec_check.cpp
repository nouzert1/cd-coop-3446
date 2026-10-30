// Throwaway: prove the room codec is injective and reversible over the lobby id
// range Steam actually uses, and that no two ids share a code.
#include <cstdio>
#include <cstdint>
#include <set>
#include <string>

#include "mod/net/room_codec.h"

int main() {
    using namespace cdmp::net;
    std::set<std::string> seen;
    int bad = 0;

    // Steam allocates lobby ids from 1 upwards; 20 million covers far beyond any
    // realistic allocation while still being a fast exhaustive check.
    constexpr uint64_t kLimit = 20000000;
    for (uint64_t id = 1; id <= kLimit; ++id) {
        const std::string code = room_code_encode(id);
        if (code.size() != static_cast<size_t>(kRoomCodeLen)) {
            if (bad++ < 5) std::printf("BAD LEN id=%llu code='%s'\n", (unsigned long long)id, code.c_str());
            continue;
        }
        if (!seen.insert(code).second) {
            if (bad++ < 5) std::printf("COLLISION id=%llu code=%s\n", (unsigned long long)id, code.c_str());
        }
        uint64_t back = 0;
        if (!room_code_decode(code, back) || back != id) {
            if (bad++ < 5)
                std::printf("ROUNDTRIP id=%llu code=%s back=%llu\n", (unsigned long long)id, code.c_str(),
                            (unsigned long long)back);
        }
    }
    std::printf("checked %llu ids, collisions/roundtrip errors: %d\n", (unsigned long long)kLimit, bad);

    // The bound must be refused, and the fold must land on the right digit.
    uint64_t t = 0;
    std::printf("max id %llu encodes: %s\n", (unsigned long long)kRoomCodeMaxId,
                room_code_encode(kRoomCodeMaxId).c_str());
    std::printf("max+1 refused: %d\n", room_code_encode(kRoomCodeMaxId + 1).empty());
    std::printf("id 0 refused:  %d\n", room_code_encode(0).empty());

    // Confusables: O->0, I/L->1, U->27(=V). "OO1ILU" style input must decode to
    // the same id as its canonical form.
    uint64_t a = 0, b = 0;
    const bool o = room_code_decode("0000001", a);
    const bool f = room_code_decode("OOOOOOI", b);
    std::printf("canonical 0000001 -> %d id=%llu ; folded OOOOOOI -> %d id=%llu ; equal=%d\n", o,
                (unsigned long long)a, f, (unsigned long long)b, a == b);

    uint64_t u = 0, v = 0;
    const bool du = room_code_decode("000000U", u);
    const bool dv = room_code_decode("000000V", v);
    std::printf("U -> %d id=%llu ; V -> %d id=%llu ; equal=%d (expect 1)\n", du, (unsigned long long)u, dv,
                (unsigned long long)v, u == v);
    return bad == 0 ? 0 : 1;
}
