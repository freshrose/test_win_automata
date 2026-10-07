#!/usr/bin/env python3
"""agent_pty.py -- host an interactive `claude` inside a Windows ConPTY (pywinpty).

The Windows analog of tmux: claude's interactive TUI needs a real terminal to stay
alive across turns. pywinpty gives it a pseudo-console without a visible desktop
window, so it runs unattended (launched from the logon Run key).

claude is spawned with a single-word `boot` prompt (multi-word args get truncated
through claude.cmd); CLAUDE.md in the cwd drives the rest.

Two threads, because winpty read() BLOCKS: a reader drains PTY output to a log; a
watcher answers the one-time "Do you trust this folder?" prompt (which
--dangerously-skip-permissions does NOT skip) by sending "1" + Enter.
"""
import os
import threading
import time

from winpty import PtyProcess

CLAUDE = os.path.join(os.environ["APPDATA"], "npm", "claude.cmd")
AGENT_DIR = r"C:\avensio\agent"
LOG = r"C:\avensio\agent-pty.log"

ARGV = [
    "cmd.exe", "/c", CLAUDE,
    "--mcp-config", r"C:\automata\mcp\agent-mcp.json",
    "--strict-mcp-config",
    "--dangerously-skip-permissions",
    "boot",
]

_buf = ""
_buf_lock = threading.Lock()


def reader(proc, log):
    global _buf
    while proc.isalive():
        try:
            data = proc.read(1024)
        except EOFError:
            break
        if data:
            log.write(data)
            log.flush()
            with _buf_lock:
                _buf = (_buf + data)[-4000:]
        else:
            time.sleep(0.1)


def watcher(proc, log):
    """Answer claude's first-run prompts IN ORDER (the blocking reader can't).
    Each is a menu; send the right option digit + Enter, then clear the buffer so
    the next prompt is detected cleanly. Words are intact in the raw stream.
      1) 'Do you trust this folder?'        -> 1 (Yes, I trust)
      2) 'Bypass Permissions mode' warning  -> 2 (Yes, I accept)  [default is No!]
    """
    global _buf
    # Single intact words (escapes sit between words). Handle whichever appears,
    # each once -- prompts may be skipped once persisted, so do NOT require order.
    # NOTE: check "bypass" BEFORE "trust": the Bypass-Permissions warning text also
    # contains the word "trust", so a trust-first match would send "1" (= "No, exit")
    # on the bypass screen and kill claude. On the bypass screen 1=exit, 2=accept.
    answers = [("bypass", "2"), ("trust", "1")]
    done = set()
    last = 0.0
    while proc.isalive():
        if (time.time() - last) > 2.5:
            with _buf_lock:
                b = _buf.lower()
            for key, ans in answers:
                if key not in done and key in b:
                    time.sleep(1.5)           # let the TUI finish rendering
                    proc.write(ans)
                    time.sleep(0.4)
                    proc.write("\r")
                    done.add(key)
                    last = time.time()
                    with _buf_lock:
                        _buf = ""             # avoid re-matching; detect next fresh
                    log.write(f"\n=== answered prompt '{key}' -> {ans} ===\n")
                    log.flush()
                    break
        time.sleep(0.5)


def main() -> None:
    log = open(LOG, "a", encoding="utf-8", errors="replace")
    log.write(f"\n=== agent_pty start {time.strftime('%Y-%m-%d %H:%M:%S')} cwd={AGENT_DIR} ===\n")
    log.flush()
    proc = PtyProcess.spawn(ARGV, cwd=AGENT_DIR, dimensions=(50, 200))
    t_read = threading.Thread(target=reader, args=(proc, log), daemon=True)
    t_watch = threading.Thread(target=watcher, args=(proc, log), daemon=True)
    t_read.start()
    t_watch.start()
    while proc.isalive():
        time.sleep(1)
    log.write(f"\n=== agent_pty exit {time.strftime('%H:%M:%S')} ===\n")
    log.flush()


if __name__ == "__main__":
    main()
