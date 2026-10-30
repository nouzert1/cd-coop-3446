#include "mod/net/room_code.h"

#include <windows.h>

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>

#include "mod/log.h"
#include "mod/net/room_codec.h"

namespace cdmp::net {
namespace {

// ---------------------------------------------------------------- flat API
// Same approach as steam_transport.cpp: our own declarations, because the
// Steamworks SDK is not vendored. Every export name below was checked against
// the exports of the game's own bin64\steam_api64.dll.
using SteamAPICall_t = uint64_t;
using CSteamID = uint64_t;

constexpr int kELobbyTypeFriendsOnly = 1;
inline constexpr const char* kHostKey = "host";
inline constexpr int kCallResultTimeoutMs = 10000;

// LobbyCreated_t { EResult result; CSteamID lobby; } (pack 8).
struct LobbyCreated {
    int32_t result;   // EResult, 1 = k_EResultOK
    int32_t pad_;
    CSteamID lobby;
};

struct Api {
    void* (*matchmaking)() = nullptr;  // SteamAPI_SteamMatchmaking_v009
    void* (*utils)() = nullptr;        // SteamAPI_SteamUtils_v010
    void* (*user)() = nullptr;         // SteamAPI_SteamUser_v023
    SteamAPICall_t (*create_lobby)(void*, int, int) = nullptr;
    void (*join_lobby)(void*, CSteamID) = nullptr;
    void (*leave_lobby)(void*, CSteamID) = nullptr;
    bool (*set_lobby_data)(void*, CSteamID, const char*, const char*) = nullptr;
    const char* (*get_lobby_data)(void*, CSteamID, const char*) = nullptr;
    bool (*set_lobby_joinable)(void*, CSteamID, bool) = nullptr;
    // The mod has no callback pump of its own: the result of an async call is
    // polled. (There is no SteamAPI_SteamAPI_GetCallResult export.)
    bool (*is_call_completed)(void*, SteamAPICall_t, bool*) = nullptr;
    bool (*get_call_result)(void*, SteamAPICall_t, void*, int, bool*) = nullptr;
    uint64_t (*get_steam_id)(void*) = nullptr;

    void* mm = nullptr;
    void* utl = nullptr;
};

Api g_api;
bool g_resolved = false;
bool g_disabled = false;
std::once_flag g_once;

std::mutex g_mutex;
uint64_t g_lobby = 0;
std::string g_code;
std::string g_status = "room: idle";

template <class R, class... P, class... A>
bool call(R& out, R (*fn)(P...), A... args) {
    if (!fn) return false;
    __try {
        out = fn(args...);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}
template <class... P, class... A>
bool call_void(void (*fn)(P...), A... args) {
    if (!fn) return false;
    __try {
        fn(args...);
        return true;
    } __except (EXCEPTION_EXECUTE_HANDLER) {
        return false;
    }
}

void fail(const char* what) {
    if (!g_disabled) log::error("Room: exception in {}; room codes disabled", what);
    g_disabled = true;
    g_status = "room: disabled after an error";
}

void resolve() {
    std::call_once(g_once, [] {
        // steam_api64.dll is already loaded: the game links it. Never load a
        // second copy (steam_transport.cpp does the same).
        HMODULE dll = GetModuleHandleW(L"steam_api64.dll");
        if (!dll) {
            g_disabled = true;
            g_status = "room: steam_api64.dll not loaded";
            return;
        }
        Api& a = g_api;
        int missing = 0;
        auto get = [&](auto& fn, const char* name) {
            fn = reinterpret_cast<std::remove_reference_t<decltype(fn)>>(GetProcAddress(dll, name));
            if (!fn) {
                log::warn("Room: export {} not found", name);
                ++missing;
            }
        };
        get(a.matchmaking, "SteamAPI_SteamMatchmaking_v009");
        get(a.utils, "SteamAPI_SteamUtils_v010");
        get(a.user, "SteamAPI_SteamUser_v023");
        get(a.create_lobby, "SteamAPI_ISteamMatchmaking_CreateLobby");
        get(a.join_lobby, "SteamAPI_ISteamMatchmaking_JoinLobby");
        get(a.leave_lobby, "SteamAPI_ISteamMatchmaking_LeaveLobby");
        get(a.set_lobby_data, "SteamAPI_ISteamMatchmaking_SetLobbyData");
        get(a.get_lobby_data, "SteamAPI_ISteamMatchmaking_GetLobbyData");
        get(a.set_lobby_joinable, "SteamAPI_ISteamMatchmaking_SetLobbyJoinable");
        get(a.is_call_completed, "SteamAPI_ISteamUtils_IsAPICallCompleted");
        get(a.get_call_result, "SteamAPI_ISteamUtils_GetAPICallResult");
        get(a.get_steam_id, "SteamAPI_ISteamUser_GetSteamID");
        if (missing) {
            log::warn("Room: {} matchmaking exports missing; room codes unavailable", missing);
            g_disabled = true;
            g_status = "room: matchmaking API unavailable";
            return;
        }
        if (!call(a.mm, a.matchmaking) || !a.mm || !call(a.utl, a.utils) || !a.utl) {
            g_disabled = true;
            g_status = "room: matchmaking interface unavailable";
            return;
        }
        g_resolved = true;
        g_status = "room: ready";
        log::info("Room: Steam matchmaking resolved");
    });
}

// Waits for an async Steam call by polling the game's own callback queue.
template <class T>
bool wait_call(SteamAPICall_t h, T& out, const char* what) {
    if (h == 0) return false;
    const uint32_t start = GetTickCount();
    while (GetTickCount() - start < static_cast<uint32_t>(kCallResultTimeoutMs)) {
        bool failed = false;
        bool complete = false;
        if (!call(complete, g_api.is_call_completed, g_api.utl, h, &failed)) {
            return fail("IsAPICallCompleted"), false;
        }
        if (failed) {
            log::warn("Room: {} call failed", what);
            return false;
        }
        if (complete) {
            std::memset(&out, 0, sizeof out);
            bool io_failed = false;
            if (!call(io_failed, g_api.get_call_result, g_api.utl, h, &out,
                      static_cast<int>(sizeof(T)), &failed) ||
                failed) {
                log::warn("Room: {} result could not be read", what);
                return false;
            }
            return true;
        }
        Sleep(20);
    }
    log::warn("Room: {} timed out after {} ms", what, kCallResultTimeoutMs);
    return false;
}

}  // namespace

// ---------------------------------------------------------------- public API
// The code text codec lives in room_codec.h (pure logic, unit-tested).

bool room_available() {
    resolve();
    return g_resolved && !g_disabled;
}

std::string room_host_open() {
    if (!room_available()) return {};
    std::lock_guard lock(g_mutex);
    if (g_lobby != 0) return g_code;  // already hosting

    SteamAPICall_t h = 0;
    if (!call(h, g_api.create_lobby, g_api.mm, kELobbyTypeFriendsOnly, 2)) {
        return fail("CreateLobby"), std::string{};
    }
    LobbyCreated created{};
    if (!wait_call(h, created, "CreateLobby")) return {};
    if (created.result != 1 || created.lobby == 0) {
        log::warn("Room: lobby creation failed (EResult {})", created.result);
        return {};
    }
    g_lobby = created.lobby;
    g_code = room_code_encode(g_lobby);

    // The guest reads this to learn our SteamID64, so the transport can connect
    // with no external server of ours.
    uint64_t own = 0;
    void* u = nullptr;
    if (call(u, g_api.user) && u && g_api.get_steam_id) call(own, g_api.get_steam_id, u);
    char idbuf[32];
    std::snprintf(idbuf, sizeof idbuf, "%llu", static_cast<unsigned long long>(own));
    bool data_ok = false, joinable_ok = false;
    call(data_ok, g_api.set_lobby_data, g_api.mm, g_lobby, kHostKey, idbuf);
    call(joinable_ok, g_api.set_lobby_joinable, g_api.mm, g_lobby, true);
    if (!data_ok) log::warn("Room: could not publish the host field in the lobby");

    g_status = "room: hosting " + g_code;
    log::info("Room: hosting, code {} (lobby {}, host SteamID64 {})", g_code, g_lobby, own);
    return g_code;
}

uint64_t room_guest_resolve(const std::string& code) {
    if (!room_available()) return 0;
    uint64_t lobby = 0;
    if (!room_code_decode(code, lobby)) {
        log::warn("Room: '{}' is not a valid code ({} characters expected)", code, kRoomCodeLen);
        return 0;
    }
    std::lock_guard lock(g_mutex);
    if (g_lobby != lobby) {
        if (g_lobby) call_void(g_api.leave_lobby, g_api.mm, static_cast<CSteamID>(g_lobby));
        g_lobby = lobby;
        g_code = room_code_encode(lobby);
        call_void(g_api.join_lobby, g_api.mm, static_cast<CSteamID>(lobby));
    }
    // JoinLobby is asynchronous and there is no call result for it: the lobby
    // data appears a moment after. The caller retries on its own cadence, so a
    // single short wait here is enough.
    for (int attempt = 0; attempt < 10; ++attempt) {
        const char* v = nullptr;
        if (call(v, g_api.get_lobby_data, g_api.mm, static_cast<CSteamID>(lobby), kHostKey) &&
            v && *v) {
            const uint64_t id = std::strtoull(v, nullptr, 10);
            if (id != 0) {
                g_status = "room: joined " + g_code;
                log::info("Room: code {} -> host SteamID64 {}", code, id);
                return id;
            }
        }
        Sleep(100);
    }
    g_status = "room: waiting for the host of " + code;
    log::warn("Room: lobby {} (code {}) has no host field yet", lobby, code);
    return 0;
}

uint64_t room_lobby_id() { return g_lobby; }
const std::string& room_current_code() { return g_code; }

void room_leave() {
    std::lock_guard lock(g_mutex);
    if (g_lobby && g_api.mm && g_api.leave_lobby) {
        call_void(g_api.leave_lobby, g_api.mm, static_cast<CSteamID>(g_lobby));
    }
    g_lobby = 0;
    g_code.clear();
    g_status = "room: left";
}

std::string room_status() { return g_status; }

}  // namespace cdmp::net
