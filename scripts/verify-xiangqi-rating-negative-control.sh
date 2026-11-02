#!/usr/bin/env bash
set -euo pipefail

# Never run a Flutter test on the author's machine. The disposable Actions checkout is restored
# before the normal regressions start, including when the expected red assertion fails.
if [[ "${GITHUB_ACTIONS:-}" != true ]]; then
  echo 'This negative control only runs on GitHub Actions.' >&2
  exit 2
fi

baseline_sha=d2f89a627cbb35d959954d6f2bfd5c7cc6c8c1d2
current_sha=$(git rev-parse HEAD)
source_paths=(
  lib/src/widgets/xiangqi_player_row.dart
  lib/src/view/xiangqi/xiangqi_watch_screen.dart
  lib/src/view/xiangqi/xiangqi_online_game_screen.dart
  lib/src/view/xiangqi/xiangqi_leaderboard_screen.dart
  lib/src/view/account/account_menu.dart
  lib/src/view/xiangqi/xiangqi_profile_screen.dart
  lib/src/view/xiangqi/xiangqi_saved_screen.dart
  lib/src/view/xiangqi/xiangqi_puzzle_screen.dart
)

git diff --quiet -- "${source_paths[@]}"
if ! git cat-file -e "${baseline_sha}^{commit}" 2>/dev/null; then
  git fetch --no-tags --depth=1 origin "$baseline_sha"
fi

restore_current() {
  for path in "${source_paths[@]}"; do
    git show "${current_sha}:${path}" > "$path"
  done
}
trap restore_current EXIT
for path in "${source_paths[@]}"; do
  git show "${baseline_sha}:${path}" > "$path"
done

mkdir -p out/parity-negative-control
report=out/parity-negative-control/real-ratings-baseline.jsonl
printf 'Negative control: original rendering %s, current tests %s\n' "$baseline_sha" "$current_sha"
set +e
flutter test --no-pub --reporter json \
  test/view/xiangqi/xiangqi_preference_presentation_contract_test.dart \
  --name 'rating|except-in-game|completed puzzle' > "$report" 2>&1
test_status=$?
set -e
if [[ "$test_status" == 0 ]]; then
  echo 'Original rendering unexpectedly passed; this is not a useful negative control.' >&2
  exit 1
fi

python3 - "$report" <<'PY'
import json
import sys
from pathlib import Path

tests = {}
errors = {}
results = {}
for line in Path(sys.argv[1]).read_text().splitlines():
    try:
        event = json.loads(line)
    except json.JSONDecodeError:
        continue
    if event.get('type') == 'testStart':
        tests[event['test']['id']] = event['test']['name']
    elif event.get('type') == 'error':
        errors.setdefault(event['testID'], []).append(str(event['error']))
    elif event.get('type') == 'print':
        # Flutter's widget binding prints the detailed TestFailure, then emits a generic error
        # event. Accept neither that generic event nor an arbitrary runtime error on its own.
        errors.setdefault(event['testID'], []).append(str(event['message']))
    elif event.get('type') == 'testDone':
        results[event['testID']] = event['result']

required = {
    'a xiangqi player row reacts': 'Expected: no matching candidates',
    'watch rows hide ratings': 'Expected: no matching candidates',
    'leaderboard ratings follow': 'Expected: no matching candidates',
    'the account subtitle hides': 'Expected: no matching candidates',
    'profile ratings obey': 'Expected: no matching candidates',
    'a profile record does not leak': 'Expected: no matching candidates',
    'saved puzzle metadata hides': 'Expected: no matching candidates',
    'puzzle difficulty follows': 'Expected: no matching candidates',
    'a completed puzzle exposes': 'Expected: contains',
}
for prefix, assertion in required.items():
    matching = [key for key, name in tests.items() if prefix in name]
    if len(matching) != 1:
        raise SystemExit(f'Missing or ambiguous negative-control test: {prefix}')
    key = matching[0]
    if results.get(key) not in ('failure', 'error') or not any(assertion in error for error in errors.get(key, [])):
        raise SystemExit(f'Not the expected UI assertion (including fixture/compile errors): {tests[key]}')

spectators = [key for key, name in tests.items() if 'except-in-game follows' in name and '(false)' in name]
if len(spectators) != 1 or results.get(spectators[0]) != 'success':
    raise SystemExit('The spectator positive control must still pass.')
print(f'Confirmed {len(required)} original-rendering UI failures with real preferences; spectator control passed.')
PY
