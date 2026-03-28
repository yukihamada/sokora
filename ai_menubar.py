#!/usr/bin/env python3
"""Local AI — macOS Menu Bar App"""
import rumps, subprocess, os, threading, time

HOME = os.path.expanduser("~")
AI_SH = f"{HOME}/ai.sh"

def is_running(port):
    try:
        import urllib.request
        r = urllib.request.urlopen(f"http://127.0.0.1:{port}/v1/models", timeout=2)
        return r.status == 200
    except:
        return False

def run_ai(cmd):
    env = os.environ.copy()
    env["PATH"] = f"/opt/homebrew/bin:{HOME}/.cargo/bin:{env.get('PATH','')}"
    return subprocess.run(
        f'{AI_SH} {cmd}', shell=True, executable='/bin/zsh',
        env=env, capture_output=True, text=True
    )

class AIMenuBar(rumps.App):
    def __init__(self):
        super().__init__("AI", title="🧠💤")
        self.menu = [
            rumps.MenuItem("Status", callback=self.show_status),
            None,
            rumps.MenuItem("▶ Start All", callback=self.on_start),
            rumps.MenuItem("■ Stop All", callback=self.on_stop),
            rumps.MenuItem("↻ Restart", callback=self.on_restart),
            None,
            rumps.MenuItem("Health Check", callback=self.on_health),
            None,
            rumps.MenuItem("Generate Image...", callback=self.on_image),
        ]
        self._timer = rumps.Timer(self.update_icon, 10)
        self._timer.start()

    def update_icon(self, _=None):
        ports = [5000, 5001, 5002, 4001]
        running = sum(1 for p in ports if is_running(p))
        if running == len(ports): self.title = "🧠"
        elif running > 0: self.title = "🧠⚡"
        else: self.title = "🧠💤"

    def show_status(self, _):
        r = run_ai("status")
        # Strip ANSI codes
        import re
        clean = re.sub(r'\033\[[0-9;]*m', '', r.stdout)
        rumps.alert("Local AI Status", clean)

    def on_start(self, _):
        self.title = "🧠⏳"
        threading.Thread(target=self._do_start, daemon=True).start()

    def _do_start(self):
        run_ai("start")
        time.sleep(3)
        self.update_icon()
        rumps.notification("Local AI", "Started", "All servers ready")

    def on_stop(self, _):
        run_ai("stop")
        self.title = "🧠💤"
        rumps.notification("Local AI", "Stopped", "All servers stopped")

    def on_restart(self, _):
        self.title = "🧠⏳"
        threading.Thread(target=self._do_restart, daemon=True).start()

    def _do_restart(self):
        run_ai("stop")
        time.sleep(3)
        run_ai("start")
        time.sleep(5)
        self.update_icon()
        rumps.notification("Local AI", "Restarted", "All servers ready")

    def on_health(self, _):
        r = run_ai("health")
        import re
        clean = re.sub(r'\033\[[0-9;]*m', '', r.stdout)
        rumps.alert("Health Check", clean or "All healthy")

    def on_image(self, _):
        w = rumps.Window("Enter prompt:", "Generate Image", dimensions=(400, 60))
        r = w.run()
        if r.clicked and r.text:
            threading.Thread(target=self._gen_image, args=(r.text,), daemon=True).start()
            rumps.notification("Local AI", "Generating...", r.text[:50])

    def _gen_image(self, prompt):
        run_ai(f'img "{prompt}"')
        rumps.notification("Local AI", "Image Ready!", prompt[:50])

if __name__ == "__main__":
    AIMenuBar().run()
