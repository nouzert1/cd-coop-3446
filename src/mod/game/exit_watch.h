#ifndef CDMP_MOD_GAME_EXIT_WATCH_H
#define CDMP_MOD_GAME_EXIT_WATCH_H

#include <cstdint>

// Records a SILENT death of the game.
//
// The two crashes during the 2-PC test of 31 Oct 2026 (16:33 and 17:11) left nothing
// behind: no Windows Error Reporting entry, no crash dump, and no exception caught by
// our own __try/__except around the injection -- and that block does run, it has caught
// injected garbage before and logged "Inject: EXCEPTION".
//
// Three separate mechanisms can end a process, and only the first is visible:
//
//   1. an unhandled exception  -> WER entry, dump, and our __except would fire
//   2. ExitProcess / TerminateProcess -> silent from outside, instant
//   3. heap corruption abort   -> the CRT calls TerminateProcess(3) itself
//
// The 31 Oct crashes were not (1). That leaves (2) and (3), both of which go through
// TerminateProcess, and both of which are invisible unless something is watching the
// call. This watches it.
//
// ---------------------------------------------------------------------------------
// READ THIS BEFORE CHANGING ANYTHING: the first version of this header's implementation
// hooked RaiseException as well, and that broke BOTH players' games -- the mod died
// before the main menu on two different machines, and the only difference from the build
// that had worked was this feature. RaiseException is normal C++ control flow, not an
// error path. The implementation records into a pre-allocated buffer with no allocation,
// no locks and no formatting, because the hook runs while the process is going down.
// ---------------------------------------------------------------------------------

namespace cdmp::game {

// Hooks the process-exit paths. Returns false if the prologues are not recognisable on
// this build, in which case nothing is installed and the game behaves as before.
//
// RaiseException is deliberately not hooked. The first version did, and both players'
// games began dying before the main menu; the C++ runtime uses RaiseException as normal
// control flow, so the hook ran logging and a stack walk inside exception dispatch. See
// the comment block in the .cpp before changing anything here.
bool exit_watch_install();

// Reads the record an exiting process leaves behind. Returns false when no exit was seen.
// There is no callback by design: the callback was the unsafe part.
bool exit_watch_take_record(uint32_t& code, const char*& via, void* const*& frames, int& count);

}  // namespace cdmp::game

#endif  // CDMP_MOD_GAME_EXIT_WATCH_H
