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
// 7 digits = 35 bits, which covers every lobby id Steam hands out (they are
// allocated small: the low 32 bits are the interesting part).

#include <cstdint>
#include <string>

namespace cdmp::net {

inline constexpr int kRoomCodeLen = 7;

// A 7-digit code carries 35 bits. Steam allocates lobby ids from 1 upwards, so
// real ids are far below this bound; it is here so a nonsensical id can never be
// silently truncated into someone else's room.
inline constexpr uint64_t kRoomCodeMaxId = (1ull << (5 * kRoomCodeLen)) - 1;

// Encodes a lobby id as a room code. Empty when lobby_id is 0 or out of range.
inline std::string room_code_encode(uint64_t lobby_id) {
    constexpr char kAlphabet[] = "0123456789ABCDEFGHJKMNPQRSTVWXYZ";
    if (lobby_id == 0 || lobby_id > kRoomCodeMaxId) return {};
    std::string s(kRoomCodeLen, '0');
    for (int i = kRoomCodeLen - 1; i >= 0; --i) {
        s[static_cast<size_t>(i)] = kAlphabet[lobby_id & 31];
        lobby_id >>= 5;
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
    out_lobby_id = v;
    return true;
}

}  // namespace cdmp::net
