// Throwaway: prove the room codec is injective and reversible over the lobby id
// range Steam actually uses, and that no two ids share a code.
//
// Note on the round trip: the code carries only the LOW 32 BITS of a lobby id
// (the high bits are the CSteamID type, identical for every lobby), so decode
// returns the low part with that constant prefix restored -- not the bare number
// that was passed in. The check compares against kLobbyIdHighBits | id for that
// reason. Comparing against the bare id was correct before the fix and is exactly
// the kind of assertion that would have hidden the bug, which is why the live
// lobby id is checked explicitly at the bottom as well.
#include <cstdio>
#include <cstdint>
#include <set>
#include <string>

#include "mod/net/room_codec.h"

int main() {
    using namespace cdmp::net;
    std::set<std::string> seen;
    int bad = 0;

    // The low 32 bits are what vary between rooms; 20 million covers far beyond any
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
        const uint64_t want = kLobbyIdHighBits | id;
        if (!room_code_decode(code, back) || back != want) {
            if (bad++ < 5)
                std::printf("ROUNDTRIP id=%llu code=%s back=%llu want=%llu\n", (unsigned long long)id,
                            code.c_str(), (unsigned long long)back, (unsigned long long)want);
        }
    }
    std::printf("checked %llu ids, collisions/roundtrip errors: %d\n", (unsigned long long)kLimit, bad);

    // THE CASE THAT FAILED LIVE: a real lobby id, 57 bits wide. The old codec
    // refused everything this size and the room code came out empty.
    const uint64_t live = 109775242893225821ull;
    const std::string live_code = room_code_encode(live);
    uint64_t live_back = 0;
    const bool live_ok = !live_code.empty() && room_code_decode(live_code, live_back) && live_back == live;
    std::printf("live lobby %llu -> code '%s' -> %llu ; ok=%d\n", (unsigned long long)live,
                live_code.c_str(), (unsigned long long)live_back, live_ok ? 1 : 0);
    if (!live_ok) ++bad;

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
