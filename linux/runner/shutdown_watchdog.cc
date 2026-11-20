#include "shutdown_watchdog.h"

#include <atomic>
#include <cstdlib>
#include <thread>
#include <fcntl.h>
#include <unistd.h>

void arm_shutdown_watchdog(std::chrono::milliseconds timeout) {
  static std::atomic<bool> armed{false};
  if (armed.exchange(true)) return;
  std::thread([timeout] {
    std::this_thread::sleep_for(timeout);
    // Never let a full diagnostic pipe defeat the exit deadline.
    const int flags = fcntl(STDERR_FILENO, F_GETFL);
    if (flags >= 0 && fcntl(STDERR_FILENO, F_SETFL, flags | O_NONBLOCK) >= 0) {
      const char message[] = "Lichess: native shutdown deadline exceeded; exiting\n";
      const auto ignored = write(STDERR_FILENO, message, sizeof(message) - 1);
      (void)ignored;
    }
    std::_Exit(70);
  }).detach();
}
