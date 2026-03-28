#!/usr/bin/env python3
"""Local AI — macOS Menu Bar App
Start/stop/status for MLX servers from the menu bar."""
import rumps, subprocess, os, threading, time

SERVICES = {
    "main":   {"port": 5000, "label": "LLM 122B",  "cmd": None},
    "fast":   {"port": 5001, "label": "LLM 35B",   "cmd": None},
    "vision": {"port": 5002, "label": "Vision 8B",  "cmd": None},
    "proxy":  {"port": 4001, "label": "Proxy",      "cmd": None},
}

def is_running(port):
    try:
        import urllib.request
        r = urllib.request.urlopen(f"http://127.0.0.1:{port}/v1/models", timeout=2)
        return r.status == 200
    except:
        if port == 4001:
            try:
                r = urllib.request.urlopen(f"http://127.0.0.1:{port}/health", timeout=2)
                return r.status == 200
            except:
                return False
        return False

def start_all():
    home = os.path.expanduser("~")
    venv = f"{home}/mlx_env/bin/activate"
    subprocess.Popen(
        f'source {venv} && {home}/ai.sh start',
        shell=True, executable='/bin/zsh',
        stdout=open(f'{home}/ai_start.log', 'w'),
        stderr=subprocess.STDOUT
    )

def stop_all():
    home = os.path.expanduser("~")
    subprocess.run(f'{home}/ai.sh stop', shell=True, executable='/bin/zsh')

class AIMenuBar(rumps.App):
    def __init__(self):
        super().__init__("AI", icon=None, title="🧠")
        self.menu = [
            rumps.MenuItem("Status", callback=self.show_status),
            None,  # separator
            rumps.MenuItem("▶ Start All", callback=self.on_start),
            rumps.MenuItem("■ Stop All", callback=self.on_stop),
            rumps.MenuItem("↻ Restart", callback=self.on_restart),
            None,
            rumps.MenuItem("Health Check", callback=self.on_health),
            None,
            rumps.MenuItem("Generate Image...", callback=self.on_image),
            None,
            rumps.MenuItem("Open Logs", callback=self.on_logs),
        ]
        # Auto-update title based on status
        self._timer = rumps.Timer(self.update_status, 10)
        self._timer.start()

    def update_status(self, _=None):
        running = sum(1 for s in SERVICES.values() if is_running(s["port"]))
        total = len(SERVICES)
        if running == total:
            self.title = "🧠"
        elif running > 0:
            self.title = "🧠⚡"
        else:
            self.title = "🧠💤"

    def show_status(self, _):
        lines = []
        for key, svc in SERVICES.items():
            status = "✅ ON" if is_running(svc["port"]) else "❌ OFF"
            lines.append(f"{svc['label']:12s} :{svc['port']}  {status}")
        rumps.alert("Local AI Status", "\n".join(lines))

    def on_start(self, _):
        self.title = "🧠⏳"
        threading.Thread(target=self._do_start, daemon=True).start()

    def _do_start(self):
        start_all()
        time.sleep(5)
        self.update_status()
        rumps.notification("Local AI", "Started", "All servers are starting up")

    def on_stop(self, _):
        stop_all()
        self.title = "🧠💤"
        rumps.notification("Local AI", "Stopped", "All servers stopped")

    def on_restart(self, _):
        self.title = "🧠⏳"
        threading.Thread(target=self._do_restart, daemon=True).start()

    def _do_restart(self):
        stop_all()
        time.sleep(2)
        start_all()
        time.sleep(10)
        self.update_status()

    def on_health(self, _):
        home = os.path.expanduser("~")
        result = subprocess.run(
            f'{home}/ai.sh health',
            shell=True, executable='/bin/zsh', capture_output=True, text=True
        )
        rumps.alert("Health Check", result.stdout or "All healthy")

    def on_image(self, _):
        w = rumps.Window("Enter prompt:", "Generate Image", dimensions=(400, 60))
        r = w.run()
        if r.clicked and r.text:
            threading.Thread(target=self._gen_image, args=(r.text,), daemon=True).start()
            rumps.notification("Local AI", "Generating...", r.text[:50])

    def _gen_image(self, prompt):
        home = os.path.expanduser("~")
        subprocess.run(
            f'source {home}/mlx_env/bin/activate && {home}/ai.sh img "{prompt}"',
            shell=True, executable='/bin/zsh'
        )
        rumps.notification("Local AI", "Image Ready!", prompt[:50])

    def on_logs(self, _):
        home = os.path.expanduser("~")
        subprocess.Popen(['open', '-a', 'Console', f'{home}/proxy.log'])

if __name__ == "__main__":
    AIMenuBar().run()
