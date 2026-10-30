#pragma once
// Room code text codec: lobby id <-> short code the player can read out loud.
//
// Kept separate from room_code.cpp so it is pure logic with no Windows or Steam
// dependency, and can be unit-tested (tests/tests.cpp).
//
// Crockford-style base32: the alphabet leaves out I, L, O and U, and decoding
// folds the letters that are easy to confuse back onto their digits (O -> 0,
// I/L -> 1, U -> V). A code read over voice chat therefore cannot turn into a
// different but valid code.
//
// 7 digits = 35 bits. That is enough for the SEQUENTIAL PART of a lobby id, which
// is what actually varies between rooms -- see kLobbyIdLowMask below.
//
// This used to claim the whole 64-bit lobby id fit in 35 bits, on the assumption
// that "Steam allocates lobby ids from 1 upwards". It does not. A live lobby on
// this game came back as 109775242893225821 = 0x186000075C86F5D, 57 bits wide:
// Steam packs the id TYPE into the high bits of the CSteamID, so the value is
// huge even though the room counter is small. kRoomCodeMaxId therefore rejected
// every real lobby, room_code_encode returned "", and the mod reported itself as
// hosting with an EMPTY code -- which is exactly what the panel showed as
// "(no code: room: hosting)" and the log as "hosting, code  (lobby 109775...)".
//
// The fix is not to widen the code: 7 digits is what a player can read out loud.
// It is to encode the part that identifies the room and rebuild the constant part
// on decode.

#include <cstdint>
#include <string>

namespace cdmp::net {

inline constexpr int kRoomCodeLen = 7;

// The low 32 bits of the lobby id: the part that actually differs between rooms.
// The high bits are the CSteamID type/instance, which is the same for every lobby
// of this kind, so it does not need to travel in the code.
inline constexpr uint64_t kLobbyIdLowMask = 0xFFFFFFFFull;

// The high bits of a lobby CSteamID on this game, OR-ed back on decode. Every
// lobby seen here carries the same high 32 bits, 0x01860000, so the constant is
// 0x0186000000000000.
//
// Count the zeros: it is 0x01860000_00000000, NOT 0x18600000_00000000. Writing it
// with one zero fewer is a 4-bit shift, and it fails in the worst way -- the code
// still encodes and decodes, the round trip is still self-consistent, and every
// unit test that only checks "encode then decode gives the same value" still
// passes. What breaks is the join: the guest rebuilds a lobby id that no room has.
// Only comparing against a REAL lobby id catches it, which is why the regression
// case in tests.cpp uses the literal value read from the live game.
inline constexpr uint64_t kLobbyIdHighBits = 0x0186000000000000ull;

// A 7-digit code carries 35 bits, comfortably more than the 32 it now needs. The
// bound stays as a guard: a low part of 0 would decode to the "no lobby" value and
// must never be produced.
inline constexpr uint64_t kRoomCodeMaxId = (1ull << (5 * kRoomCodeLen)) - 1;

// Encodes a lobby id as a room code. Empty when there is nothing encodable.
inline std::string room_code_encode(uint64_t lobby_id) {
    constexpr char kAlphabet[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    if (lobby_id == 0) return {};
    uint64_t low = lobby_id & kLobbyIdLowMask;
    if (low == 0 || low > kRoomCodeMaxId) return {};
    std::string s(kRoomCodeLen, '0');
    for (int i = kRoomCodeLen - 1; i >= 0; --i) {
        s[static_cast<size_t>(i)] = kAlphabet[low & 31];
        low >>= 5;
    }
    return s;
}

// Uppercases and drops separators, so "ab1-2 cd3" and "AB12CD3" are the same.
inline std::string room_code_normalise(const std::string& typed) {
    std::string out;
    out.reserve(kRoomCodeLen);
    for (unsigned char ch : typed) {
        if (ch == ' ' || ch == '-' || ch == '\t' || ch == '_' || ch == '.') continue;
        if (ch >= 'a' && ch <= 'z') ch = static_cast<unsigned char>(ch - 'a' + 'A');
        out.push_back(static_cast<char>(ch));
    }
    return out;
}

// Decodes a (possibly sloppy) room code. False when it is malformed or zero.
inline bool room_code_decode(const std::string& code, uint64_t& out_lobby_id) {
    const std::string c = room_code_normalise(code);
    if (c.size() != static_cast<size_t>(kRoomCodeLen)) return false;
    uint64_t v = 0;
    for (char ch : c) {
        int d = -1;
        if (ch >= '0' && ch <= '9') {
            d = ch - '0';
        } else if (ch == 'O') {
            d = 0;
        } else if (ch == 'I' || ch == 'L') {
            d = 1;
        } else if (ch == 'U') {
            d = 27;
        } else {
            constexpr char kAlphabet[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
            for (int i = 0; i < 32; ++i) {
                if (kAlphabet[i] == ch) {
                    d = i;
                    break;
                }
            }
        }
        if (d < 0) return false;
        v = (v << 5) | static_cast<uint64_t>(d);
    }
    if (v == 0) return false;
    // The code carries only the low 32 bits (see room_code_encode). Put the
    // CSteamID type/instance back, or the guest would try to join a lobby id that
    // no room has -- one whose high bits are zero.
    out_lobby_id = kLobbyIdHighBits | v;
    return true;
}

}  // namespace cdmp::net
