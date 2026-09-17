#!/usr/bin/env python3
# ***************************************************************************
#                      DGT Smart Board - Web Display Server
#
#           Copyright (C) 2026 By Ulrik Hørlyk Hjort
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
# ***************************************************************************

"""DGT Smart Board web display - serves http://localhost:8080/

Reads /tmp/dgt_status.txt and exposes it as JSON at /status.json.
The HTML page polls every 400 ms and updates automatically; works on
any device on the local network (use the machine's IP instead of localhost).

Usage: python3 dgt_webdisplay.py [port]   (default port: 8080)
"""

import http.server
import json
import os
import socket
import sys

STATUS_FILE  = "/tmp/dgt_status.txt"
DEFAULT_PORT = 8080

# ---------------------------------------------------------------------------
# Embedded HTML / CSS / JS - served at GET /
# ---------------------------------------------------------------------------
PAGE = """\
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>DGT Board</title>
<style>
  :root {
    --bg:       #1e1e2e;
    --fg-move:  #cdd6f4;
    --fg-dim:   #6c7086;
    --fg-pv:    #89b4fa;
    --fg-good:  #a6e3a1;
    --fg-bad:   #f38ba8;
    --fg-even:  #f9e2af;
    --fg-stat:  #fab387;
    --fg-open:  #cba6f7;
    --bar-w:    #dce0e8;
    --bar-b:    #11111b;
    --bar-div:  #45475a;
  }
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body {
    background: var(--bg);
    color: var(--fg-move);
    font-family: "DejaVu Sans", "Segoe UI", sans-serif;
    display: flex;
    flex-direction: column;
    min-height: 100vh;
    padding: 0 16px 0;
  }
  #move {
    font-size: clamp(4rem, 18vw, 9rem);
    font-weight: 700;
    text-align: center;
    line-height: 1.05;
    padding-top: 20px;
    letter-spacing: -2px;
  }
  #turn {
    font-size: clamp(1rem, 3vw, 1.4rem);
    color: var(--fg-dim);
    text-align: center;
    margin-top: 4px;
  }
  #best {
    font-family: "DejaVu Sans Mono", monospace;
    font-size: clamp(1rem, 3.5vw, 1.6rem);
    font-weight: 700;
    text-align: center;
    margin-top: 14px;
  }
  #pv {
    font-family: "DejaVu Sans Mono", monospace;
    font-size: clamp(0.85rem, 2.5vw, 1.15rem);
    color: var(--fg-pv);
    text-align: center;
    margin-top: 5px;
  }
  #status {
    font-size: clamp(0.9rem, 2.8vw, 1.1rem);
    color: var(--fg-stat);
    text-align: center;
    margin-top: 8px;
  }
  #opening {
    font-size: clamp(0.8rem, 2.2vw, 1rem);
    font-style: italic;
    color: var(--fg-open);
    text-align: center;
    margin-top: 4px;
  }
  /* Spacer pushes bar to bottom */
  .spacer { flex: 1; }

  /* Eval bar */
  #eval-bar {
    position: relative;
    width: 100%;
    height: 52px;
    display: flex;
    overflow: hidden;
    margin: 0 -16px;
    width: calc(100% + 32px);
  }
  #bar-white { background: var(--bar-w); height: 100%; }
  #bar-black { background: var(--bar-b); height: 100%; flex: 1; }
  #bar-center {
    position: absolute;
    left: 50%;
    top: 0; bottom: 0;
    width: 2px;
    background: var(--bar-div);
    transform: translateX(-1px);
  }
  #bar-score {
    position: absolute;
    top: 50%;
    transform: translateY(-50%);
    font-family: "DejaVu Sans Mono", monospace;
    font-size: 1.1rem;
    font-weight: 700;
    pointer-events: none;
    transition: left 0.3s ease;
  }
  #waiting { color: var(--fg-dim); text-align: center; margin-top: 40px; }
</style>
</head>
<body>
  <div id="move">—</div>
  <div id="turn"></div>
  <div id="best"></div>
  <div id="pv"></div>
  <div id="status">Waiting for board...</div>
  <div id="opening"></div>
  <div class="spacer"></div>
  <div id="eval-bar">
    <div id="bar-white" style="width:50%"></div>
    <div id="bar-black"></div>
    <div id="bar-center"></div>
    <div id="bar-score" style="left:25%">0.00</div>
  </div>

<script>
const POLL_MS = 400;
const MAX_CP  = 500;

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

function evalColor(cp) {
  if (Math.abs(cp) < 25) return 'var(--fg-even)';
  return cp > 0 ? 'var(--fg-good)' : 'var(--fg-bad)';
}

function updateBar(scoreCp, isMate, mateIn) {
  let ratio;
  if (isMate) {
    ratio = mateIn > 0 ? 1.0 : 0.0;
  } else {
    ratio = (clamp(scoreCp, -MAX_CP, MAX_CP) + MAX_CP) / (2 * MAX_CP);
  }

  document.getElementById('bar-white').style.width = (ratio * 100).toFixed(1) + '%';

  let label;
  if (isMate) {
    label = mateIn > 0 ? `Mate ${mateIn}` : `Mated ${-mateIn}`;
  } else {
    const sign = scoreCp >= 0 ? '+' : '';
    label = sign + (scoreCp / 100).toFixed(2);
  }

  const scoreEl = document.getElementById('bar-score');
  if (ratio >= 0.5) {
    // score label on white side, dark text
    scoreEl.style.left  = clamp(ratio * 100 - 8, 2, 92) + '%';
    scoreEl.style.transform = 'translate(-100%, -50%)';
    scoreEl.style.color = '#111';
  } else {
    // score label on black side, light text
    scoreEl.style.left  = clamp(ratio * 100 + 2, 2, 92) + '%';
    scoreEl.style.transform = 'translateY(-50%)';
    scoreEl.style.color = '#eee';
  }
  scoreEl.textContent = label;
}

function setText(id, text, color) {
  const el = document.getElementById(id);
  el.textContent = text;
  if (color) el.style.color = color;
}

async function poll() {
  try {
    const r = await fetch('/status.json');
    if (!r.ok) return;
    const d = await r.json();

    setText('move', d.move || '—');

    const parts = [];
    if (d.move_num) parts.push('Move ' + d.move_num);
    if (d.turn)     parts.push(d.turn + ' to move');
    setText('turn', parts.join('  •  '));

    const isMate = d.is_mate === '1';
    const mateIn = parseInt(d.mate_in || '0', 10);
    const cp     = parseInt(d.score_cp || '0', 10);
    updateBar(cp, isMate, mateIn);

    const fg = isMate ? (mateIn > 0 ? 'var(--fg-good)' : 'var(--fg-bad)') : evalColor(cp);
    setText('best', d.best ? 'Best: ' + d.best : '', fg);
    setText('pv',   d.pv   ? 'PV: '  + d.pv   : '');
    setText('status',  d.status  || '');
    setText('opening', d.opening || '');
  } catch (_) {}
}

setInterval(poll, POLL_MS);
poll();
</script>
</body>
</html>
"""


def read_status() -> dict:
    data: dict[str, str] = {}
    try:
        with open(STATUS_FILE, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if "=" in line:
                    k, _, v = line.partition("=")
                    data[k.strip()] = v.strip()
    except OSError:
        pass
    return data


class Handler(http.server.BaseHTTPRequestHandler):

    def log_message(self, fmt, *args):  # silence access log
        pass

    def do_GET(self):
        if self.path == "/status.json":
            body = json.dumps(read_status()).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Access-Control-Allow-Origin", "*")
            self.end_headers()
            self.wfile.write(body)
        elif self.path in ("/", "/index.html"):
            body = PAGE.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:
            self.send_response(404)
            self.end_headers()


def local_ip() -> str:
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except OSError:
        return "unknown"


def main() -> None:
    port = int(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_PORT
    server = http.server.HTTPServer(("", port), Handler)
    ip = local_ip()
    print(f"DGT web display running at http://localhost:{port}/")
    print(f"Network address:            http://{ip}:{port}/")
    print("Ctrl+C to stop.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
