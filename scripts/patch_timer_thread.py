#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Stop fosslight_util TimerThread before interpreter shutdown.

Python 3.14 aborts if a daemon thread writes to stderr while the
interpreter is finalizing. fosslight_scanner starts TimerThread as a
daemon, and progress.spinner writes to stderr once a second. pytest can
report every test passed and still die with SIGABRT (tox exit -6).

This replaces the installed timer_thread.py inside a tox env so the
spinner loop can be stopped, and an atexit hook joins those threads
before stderr is torn down.
"""

from __future__ import annotations

import sys
from pathlib import Path

MARKER = "patched-for-py314-shutdown"

PATCHED_SOURCE = '''\
#!/usr/bin/env python
# -*- coding: utf-8 -*-
# Copyright (c) 2021 LG Electronics Inc.
# SPDX-License-Identifier: Apache-2.0
# patched-for-py314-shutdown: stop the spinner before interpreter finalization
import atexit
import threading

from progress.spinner import Spinner


class TimerThread(threading.Thread):
    _instances = []

    def __init__(self):
        threading.Thread.__init__(self, name=" Thread")
        self._stop = threading.Event()
        self.daemon = True
        TimerThread._instances.append(self)

    def stop(self):
        self._stop.set()

    def run(self):
        spinner = Spinner("")
        while not self._stop.is_set():
            # Wake within one second when stop() is called during sleep.
            if self._stop.wait(1):
                break
            try:
                spinner.next()
            except Exception:
                break


def _stop_timer_threads():
    threads = list(TimerThread._instances)
    for thread in threads:
        thread.stop()
    for thread in threads:
        if thread.is_alive():
            thread.join(timeout=2)


atexit.register(_stop_timer_threads)
'''


def find_timer_thread(env_dir: Path) -> Path:
    matches = sorted(env_dir.rglob("fosslight_util/timer_thread.py"))
    if not matches:
        raise SystemExit(f"fosslight_util/timer_thread.py not found under {env_dir}")
    return matches[0]


def patch(env_dir: Path) -> Path:
    target = find_timer_thread(env_dir)
    current = target.read_text(encoding="utf-8")
    if MARKER in current:
        print(f"already patched: {target}")
        return target
    target.write_text(PATCHED_SOURCE, encoding="utf-8")
    print(f"patched: {target}")
    return target


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(f"usage: {argv[0]} <tox-env-dir>", file=sys.stderr)
        return 2
    patch(Path(argv[1]))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
