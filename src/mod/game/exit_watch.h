#ifndef CDMP_MOD_GAME_EXIT_WATCH_H
#define CDMP_MOD_GAME_EXIT_WATCH_H

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
// call. This watches it: it hooks TerminateProcess and ExitProcess, writes the exit
// code, the calling module and a short stack to cdmp.log, and then lets the exit proceed.
//
// A note on what this can and cannot do: it cannot PREVENT the exit, and it must not try.
// If the game decided to die, holding it open would be a worse bug than the one being
// diagnosed. It exists only to leave a record.

namespace cdmp::game {

// Hooks the process-exit paths. Returns false if the prologues are not recognisable on
// this build, in which case nothing is installed and the game behaves as before.
bool exit_watch_install();

}  // namespace cdmp::game

#endif  // CDMP_MOD_GAME_EXIT_WATCH_H
