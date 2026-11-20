# Engine shutdown and child ownership implementation plan

**Goal:** Closing the Linux application terminates the application and its owned children, and a native reader cannot survive into the next engine generation.

**Architecture:** Keep a native engine slot claimed until its main entry and stdout reader have both returned. Report failed disposal instead of declaring a live native engine dead. Arm a Linux native watchdog only for an explicit close request, before asynchronous Dart cleanup; it remains effective while Flutter is tearing down. Manage audio children through a bounded owner with graceful termination and SIGKILL escalation.

**Tech Stack:** Flutter/Dart, multistockfish fork, GTK/C++, GitHub Actions.

## Constraints and tradeoffs

- Reuse the existing clean mobile worktree and the existing dependency checkout. Work is performed by the primary agent.
- No local compilation or Flutter test runs; format locally, run regression tests and builds in Actions.
- No package installation or secret replacement is part of this fix.
- Increasing the Dart timeout alone cannot recover a native FFI isolate. Moving all engines to subprocesses would solve isolation but change the platform engine architecture; use explicit lifecycle state plus a process exit watchdog for this bounded repair.
- The watchdog is only armed after the user requests close and exits with failure on its deadline. Normal closes retain their existing successful exit.

## Task 1: Capture failing lifecycle regressions

Files: `test/service/window_service_test.dart`, `test/model/engine/system_stockfish_transport_test.dart`, dependency `pkgs/multistockfish/test/stockfish_test.dart`, dependency `.github/workflows/test.yml`.

1. Assert native-close cleanup arms the watchdog before running Dart shutdown, once for duplicate close requests.
2. Run a test-owned UCI process that ignores quit and SIGTERM. Assert disposal actually waits for its termination, with SIGKILL used only by teardown on the failing baseline.
3. Assert a spontaneous native main exit keeps the flavor claimed until its reader ends; assert a quit timeout is a failed disposal retaining the slot.
4. Push regression commits and inspect Actions failures before implementing the behavior.

## Task 2: Repair the multistockfish lifecycle

Files: dependency `pkgs/multistockfish/lib/src/stockfish.dart`, lifecycle tests and documentation.

1. Retain ports and the slot through main-only exits, failed startup cleanup, and failed disposal.
2. Release only on the combined main/reader completion; allow late genuine completion to release a previously stuck slot.
3. Surface disposal failure and provide a drain operation covering handles that failed during startup.
4. Preserve the deprecated singleton's restart behavior without an early slot release.
5. Run plugin analysis and all tests in Actions; pin the verified fork commit in all five mobile dependency entries and the lockfile.

## Task 3: Repair application shutdown and process ownership

Files: `lib/src/model/engine/engine_transport.dart`, `engine_factory.dart`, `system_stockfish_transport.dart`; `lib/src/service/sound_service.dart`, new managed Linux audio owner and tests; `lib/src/app.dart`.

1. Propagate transport cleanup failures, keep failed resources reachable, and handle asynchronous factory cleanup errors without unhandled futures.
2. Implement TERM then KILL with bounded waits for system engines; never report a running child as successfully disposed.
3. Add tests for audio concurrency, delayed process start, shutdown during playback, startup failure and ignored TERM. Own and drain all process pipes.
4. Stop sound creation before draining sound children, and join audio and engine cleanup on close.

## Task 4: Protect native shutdown

Files: `linux/runner/my_application.cc`, `linux/runner/CMakeLists.txt`, native watchdog implementation/test; `lib/src/service/window_service.dart`, fake window channel and tests.

1. Arm a native monotonic deadline through a method channel before Dart cleanup; duplicate requests do not extend it.
2. Make timeout termination independent of GTK and Dart event loops, with an explicit diagnostic and nonzero process exit.
3. Exercise native deadline and normal completion behavior in isolated test processes on Actions.
4. Keep a watchdog active across native window destruction, where the original isolate hang occurred.

## Task 5: Verification

1. Check diffs and format every changed Dart file.
2. Actions: plugin tests/analyze; app analyze and targeted lifecycle tests followed by existing full unit suite; native watchdog tests.
3. Build a verification-only Linux artifact, without publishing a rolling release.
4. Use isolated Xvfb, private D-Bus and private XDG configuration for runtime verification of ordinary close and fault-injected close; inspect exit status and owned-process cleanup.
5. Record exact commits, Actions run IDs and any unrelated pre-existing CI failures. Do not claim current HEAD passes based on older runs.
