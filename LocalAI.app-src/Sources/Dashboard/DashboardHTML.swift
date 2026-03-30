enum DashboardHTML {
    static let content = #"""
    <!DOCTYPE html>
    <html lang="ja">
    <head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width,initial-scale=1">
    <title>LocalAI Dashboard</title>
    <style>
    :root{--bg:#0d1117;--card:#161b22;--border:#30363d;--text:#e6edf3;--muted:#8b949e;--green:#3fb950;--red:#f85149;--blue:#58a6ff;--yellow:#d29922}
    *{box-sizing:border-box;margin:0;padding:0}
    body{background:var(--bg);color:var(--text);font-family:-apple-system,sans-serif;padding:24px;max-width:900px;margin:0 auto}
    h1{font-size:24px;font-weight:700;margin-bottom:24px;display:flex;align-items:center;gap:10px}
    h2{font-size:14px;font-weight:600;color:var(--muted);text-transform:uppercase;letter-spacing:.05em;margin-bottom:12px}
    .section{background:var(--card);border:1px solid var(--border);border-radius:8px;padding:16px;margin-bottom:16px}
    .model-row{display:flex;align-items:center;justify-content:space-between;padding:8px 0;border-bottom:1px solid var(--border)}
    .model-row:last-child{border-bottom:none}
    .dot{width:10px;height:10px;border-radius:50%;display:inline-block;margin-right:8px}
    .dot.on{background:var(--green)}
    .dot.off{background:var(--red)}
    .model-name{font-weight:600;font-size:14px}
    .model-id{font-size:12px;color:var(--muted)}
    .port{font-size:12px;color:var(--blue)}
    .code{background:#0d1117;border:1px solid var(--border);border-radius:6px;padding:12px;font-family:monospace;font-size:12px;white-space:pre-wrap;word-break:break-all;position:relative;margin-bottom:8px}
    .copy-btn{position:absolute;top:8px;right:8px;background:var(--border);border:none;color:var(--text);border-radius:4px;padding:4px 10px;font-size:11px;cursor:pointer}
    .copy-btn:hover{background:var(--blue);color:#fff}
    .status-bar{font-size:12px;color:var(--muted);margin-top:16px}
    .title-icon{font-size:28px}
    </style>
    </head>
    <body>
    <h1><span class="title-icon">&#x1F9E0;</span> LocalAI Dashboard</h1>

    <div class="section">
      <h2>&#x30E2;&#x30C7;&#x30EB;&#x72B6;&#x614B;</h2>
      <div id="models-list"><div class="model-row"><span style="color:var(--muted)">&#x8AAD;&#x307F;&#x8FBC;&#x307F;&#x4E2D;...</span></div></div>
      <div class="status-bar" id="status-bar">&#x2014;</div>
    </div>

    <div class="section">
      <h2>&#x63A5;&#x7D9A;&#x60C5;&#x5831;</h2>
      <p style="font-size:13px;color:var(--muted);margin-bottom:12px">Claude Code / Aider &#x304B;&#x3089;&#x63A5;&#x7D9A;&#x3059;&#x308B;&#x305F;&#x3081;&#x306E;&#x8A2D;&#x5B9A;</p>
      <div class="code" id="claude-code-snippet">&#x8AAD;&#x307F;&#x8FBC;&#x307F;&#x4E2D;...
        <button class="copy-btn" onclick="copyEl('claude-code-snippet')">&#x30B3;&#x30D4;&#x30FC;</button>
      </div>
      <div class="code" id="aider-snippet">&#x8AAD;&#x307F;&#x8FBC;&#x307F;&#x4E2D;...
        <button class="copy-btn" onclick="copyEl('aider-snippet')">&#x30B3;&#x30D4;&#x30FC;</button>
      </div>
    </div>

    <div class="section">
      <h2>&#x63A8;&#x5968;&#x30E2;&#x30C7;&#x30EB;&#xFF08;mlx-community&#xFF09;</h2>
      <div id="recommended-models">
        <div class="model-row"><div><div class="model-name">Qwen3.5-122B-A10B-4bit</div><div class="model-id">mlx-community/Qwen3.5-122B-A10B-4bit</div></div><div class="port">~60GB RAM</div></div>
        <div class="model-row"><div><div class="model-name">Qwen3.5-35B-A3B-4bit</div><div class="model-id">mlx-community/Qwen3.5-35B-A3B-4bit</div></div><div class="port">~8GB RAM</div></div>
        <div class="model-row"><div><div class="model-name">Qwen3.5-9B-4bit</div><div class="model-id">mlx-community/Qwen3.5-9B-4bit</div></div><div class="port">~5GB RAM</div></div>
        <div class="model-row"><div><div class="model-name">Qwen3.5-4B-4bit</div><div class="model-id">mlx-community/Qwen3.5-4B-4bit</div></div><div class="port">~3GB RAM</div></div>
        <div class="model-row"><div><div class="model-name">Qwen3-VL-8B-4bit</div><div class="model-id">mlx-community/Qwen3-VL-8B-Instruct-4bit</div></div><div class="port">~5GB RAM / Vision</div></div>
      </div>
    </div>

    <script>
    const BASE = window.location.origin;
    const lanIP = window.location.hostname;

    function dot(running) {
      return '<span class="dot ' + (running ? 'on' : 'off') + '"></span>';
    }

    async function refreshModels() {
      try {
        const [health, models] = await Promise.all([
          fetch(BASE + '/health').then(r => r.json()),
          fetch(BASE + '/api/models').then(r => r.json())
        ]);
        const list = document.getElementById('models-list');
        if (!models.length) {
          list.innerHTML = '<div style="color:var(--muted);padding:8px">No models configured</div>';
          return;
        }
        list.innerHTML = models.map(m =>
          '<div class="model-row">' +
          '<div>' + dot(m.running) + '<span class="model-name">' + m.label + '</span>' +
          ' <span class="model-id">— ' + m.model + '</span></div>' +
          '<span class="port">:' + m.port + '</span>' +
          '</div>'
        ).join('');
        document.getElementById('status-bar').textContent = 'Last updated: ' + new Date().toLocaleTimeString();
      } catch(e) {
        document.getElementById('status-bar').textContent = 'Error: ' + e.message;
      }
    }

    function updateSnippets() {
      const claudeText = 'export ANTHROPIC_BASE_URL=http://' + lanIP + ':4001\nexport ANTHROPIC_API_KEY=sk-ant-dummy\nclaude --dangerously-skip-permissions';
      const aiderText = 'OPENAI_API_BASE=http://' + lanIP + ':4001/v1 OPENAI_API_KEY=sk-dummy aider --model openai/qwen3.5-122b';

      const claudeEl = document.getElementById('claude-code-snippet');
      claudeEl.textContent = claudeText;
      const b1 = document.createElement('button');
      b1.className = 'copy-btn';
      b1.textContent = 'Copy';
      b1.onclick = function() { navigator.clipboard.writeText(claudeText); b1.textContent = 'Copied!'; setTimeout(() => b1.textContent = 'Copy', 2000); };
      claudeEl.appendChild(b1);

      const aiderEl = document.getElementById('aider-snippet');
      aiderEl.textContent = aiderText;
      const b2 = document.createElement('button');
      b2.className = 'copy-btn';
      b2.textContent = 'Copy';
      b2.onclick = function() { navigator.clipboard.writeText(aiderText); b2.textContent = 'Copied!'; setTimeout(() => b2.textContent = 'Copy', 2000); };
      aiderEl.appendChild(b2);
    }

    refreshModels();
    updateSnippets();
    setInterval(refreshModels, 10000);
    </script>
    </body>
    </html>
    """#
}
