#pragma once
// Room codes: enter your friend's world by typing a short code instead of
// hunting for their SteamID64.
//
// How it works (all inside Steam, no server of our own, no ports, no IP):
//   host : creates a Steam lobby (ISteamMatchmaking), writes our own SteamID64
//          into the lobby's "host" metadata and shows the lobby id as a short
//          code. The lobby is friends-only.
//   guest: turns the typed code back into a lobby id, joins it, reads the
//          "host" field and gets the host's SteamID64. From there the existing
//          Steam transport takes over unchanged.
//
// This module never touches game memory: it is pure Steamworks. Every call is
// wrapped (a crash in there would be reported to Pearl Abyss as a game crash),
// and the first exception disables the whole feature -- the mod then falls back
// to [steam] peer_steamid / the "only friend playing" scan.

#include <cstdint>
#include <string>

#include "mod/net/room_codec.h"

namespace cdmp::net {

// The code text codec (room_code_encode / room_code_decode / room_code_normalise)
// is in room_codec.h: pure logic, no Steam and no Windows, unit-tested.

// Creates a friends-only lobby and returns its code. Empty on failure.
std::string room_host_open();

// Joins the lobby of `code` and returns the host's SteamID64 (0 on failure).
uint64_t room_guest_resolve(const std::string& code);

// The lobby we are in (0 if none).
uint64_t room_lobby_id();
// The code we are currently hosting (empty if we are not hosting).
const std::string& room_current_code();
// Leaves the lobby, if any. Safe to call when not in one.
void room_leave();

// True when the Steamworks matchmaking API could be resolved. When false, the
// caller must keep using peer_steamid / the friends scan.
bool room_available();
// Human-readable state, for the overlay and the log.
std::string room_status();

}  // namespace cdmp::net
