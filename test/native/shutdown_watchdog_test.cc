#include "../../linux/runner/shutdown_watchdog.h"
#include <cassert>
#include <chrono>
#include <cstdlib>
#include <initializer_list>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>

int main() {
  for (bool stuck : {false, true}) {
    const auto started = std::chrono::steady_clock::now();
    const auto child = fork();
    assert(child >= 0);
    if (child == 0) {
      arm_shutdown_watchdog(std::chrono::milliseconds(150));
      // A repeated close cannot postpone the deadline.
      arm_shutdown_watchdog(std::chrono::seconds(60));
      if (!stuck) std::_Exit(0);
      std::this_thread::sleep_for(std::chrono::seconds(3));
      std::_Exit(99);
    }
    int status = 0;
    assert(waitpid(child, &status, 0) == child);
    assert(WIFEXITED(status));
    assert(WEXITSTATUS(status) == (stuck ? 70 : 0));
    assert(std::chrono::steady_clock::now() - started < std::chrono::seconds(2));
  }
}
