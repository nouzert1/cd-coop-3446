#pragma once
// Passive logger for the game's internal client<->server messages ("Troc").
// Hooks the two byte-level funnels with mid-hooks at their entry points and
// only COPIES packets out; nothing is modified, blocked or delayed beyond a
// short memcpy. A writer thread turns the copies into:
//   cdmp_packets.log  one line per packet (direction, name, opcode, hex preview)
//                     plus per-opcode statistics every 10 s
//   cdmp_packets.bin  full packet bytes for offline analysis (format in .cpp)

#include <windows.h>

#include <cstdint>
#include <string>
#include <vector>

namespace cdmp::net {

// `dir` is the mod's folder; `stop` is the mod-wide stop event. With
// record=false the hooks still feed co-op but nothing is written to disk.
bool sniffer_install(const std::wstring& dir, HANDLE stop, bool record = true);

// Experimental (combat tests): queue a client->server packet (u16 opcode |
// u8 slot | u16 len | payload) for the game's own in-process server. It is
// posted from inside the next real ClientNet::PostPacket call, on that game
// thread, with the channel/flags real packets use. False if not possible.
bool sniffer_inject_c2s(std::vector<uint8_t> packet);
// The world is loading (GameLoadingStartReq until 1.5 s after
// LoadingCompleteAck): nothing of ours goes in either way. Any thread.
bool sniffer_world_loading();

// ---------------------------------------------------------------- opcodes
// Every Troc handler instance the game keeps carries its own RTTI name, and the
// sniffer already walks that table at startup (see load_troc_names). The opcode
// numbers in offsets.h are only valid for ONE game build, so code that needs an
// opcode should ask for it by NAME and use the compiled-in number only as a
// fallback:
//
//     const uint16_t op = net::opcode_for("TrocTrMoveActorReq", off::kOpMoveActorReq);
//
// `name` is the Troc class name without the ".?AV" decoration and without the
// trailing "@@", e.g. "TrocTrMoveActorReq". Returns `fallback` when the table
// has not been read yet or the name is not there, so behaviour is identical to
// before on a build where resolution is unavailable.
uint16_t opcode_for(const char* name, uint16_t fallback);

// True once the Troc table has been read and at least one opcode resolved.
bool opcodes_resolved();

}  // namespace cdmp::net
