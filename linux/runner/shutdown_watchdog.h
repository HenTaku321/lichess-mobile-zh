#ifndef LICHESS_SHUTDOWN_WATCHDOG_H_
#define LICHESS_SHUTDOWN_WATCHDOG_H_

#include <chrono>

// Armed only after a user close request. The deadline survives GTK/Flutter
// teardown, including a Dart isolate blocked inside native engine code.
void arm_shutdown_watchdog(std::chrono::milliseconds timeout);

#endif
