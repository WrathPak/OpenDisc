#ifndef PAGE_H
#define PAGE_H

const char PAGE_HTML[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>OpenDisc</title>
<style>
*{box-sizing:border-box;margin:0;padding:0}
body{font-family:system-ui,-apple-system,sans-serif;background:#111;color:#e0e0e0;padding:12px;max-width:600px;margin:0 auto}
h1{font-size:18px;font-weight:600;margin-bottom:8px;color:#fff}
h2{font-size:14px;font-weight:500;margin-bottom:6px;color:#aaa;text-transform:uppercase;letter-spacing:1px}
.card{background:#1a1a1a;border:1px solid #333;border-radius:10px;padding:14px;margin-bottom:12px}
.grid{display:grid;grid-template-columns:1fr 1fr;gap:8px}
.metric{text-align:center;padding:8px;background:#222;border-radius:8px}
.metric .val{font-size:28px;font-weight:700;font-variant-numeric:tabular-nums}
.metric .lbl{font-size:11px;color:#888;margin-top:2px}
.warn{color:#f59e0b}
.ok{color:#22c55e}
.err{color:#ef4444}
.big{font-size:36px}
button{background:#2563eb;color:#fff;border:none;border-radius:8px;padding:10px 18px;font-size:14px;font-weight:500;cursor:pointer;width:100%;margin-top:8px}
button:active{background:#1d4ed8}
button.danger{background:#dc2626}
button.danger:active{background:#b91c1c}
button.secondary{background:#333;color:#ccc}
button:disabled{opacity:0.4;cursor:default}
.status{display:inline-block;padding:3px 10px;border-radius:12px;font-size:12px;font-weight:600}
.s-idle{background:#333;color:#888}
.s-armed{background:#f59e0b22;color:#f59e0b;animation:pulse 1s infinite}
.s-capturing{background:#ef444422;color:#ef4444;animation:pulse .3s infinite}
.s-done{background:#22c55e22;color:#22c55e}
.s-cal{background:#a855f722;color:#a855f7;animation:pulse 1s infinite}
@keyframes pulse{0%,100%{opacity:1}50%{opacity:.5}}
#log{font-family:monospace;font-size:11px;background:#0a0a0a;border:1px solid #222;border-radius:6px;padding:8px;max-height:150px;overflow-y:auto;white-space:pre-wrap;color:#666;margin-top:8px}
canvas{width:100%;height:180px;display:block;margin-top:8px;border-radius:6px}
.row{display:flex;gap:8px;margin-top:8px}
.row button{flex:1}
.cal-info{font-size:12px;color:#888;margin-top:6px;line-height:1.5}
.tag{display:inline-block;padding:2px 6px;border-radius:4px;font-size:11px;font-weight:600;margin-left:6px}
.mph{font-size:56px;font-weight:800;color:#22c55e;text-align:center;font-variant-numeric:tabular-nums;line-height:1}
.mph-lbl{font-size:11px;color:#888;text-align:center;margin-top:-4px;text-transform:uppercase;letter-spacing:1px}
.mph.bad{color:#666}
#hist{list-style:none}
#hist li{display:flex;justify-content:space-between;padding:8px 4px;border-bottom:1px solid #222;font-size:13px}
#hist li:last-child{border-bottom:none}
#hist .t{color:#888;font-size:11px}
#hist .m{font-weight:600;color:#22c55e}
#hist .r{color:#ccc}
#hist .empty{color:#555;text-align:center;padding:12px;font-style:italic}
.modal{display:none;position:fixed;inset:0;background:#000c;align-items:center;justify-content:center;z-index:10}
.modal.on{display:flex}
.modal-body{background:#1a1a1a;border:1px solid #333;border-radius:12px;padding:20px;max-width:360px;width:90%}
.modal-body label{display:block;margin:12px 0 4px;color:#aaa;font-size:12px;text-transform:uppercase;letter-spacing:1px}
.modal-body input[type=range]{width:100%}
.modal-body .val-readout{text-align:right;color:#22c55e;font-weight:600;font-variant-numeric:tabular-nums}
.modal-body .toggle{display:flex;align-items:center;gap:10px;margin:10px 0}
.modal-body .toggle input{width:18px;height:18px}
.icon-btn{background:transparent;border:1px solid #333;color:#aaa;width:34px;height:34px;padding:0;margin:0;font-size:18px}
.auto-tag{font-size:10px;color:#22c55e;margin-left:6px}
.bar{background:#222;border-radius:6px;height:10px;overflow:hidden;margin:6px 0}
.bar>div{background:#a855f7;height:100%;transition:width .15s ease}
.cal-hint{font-size:12px;padding:6px 10px;border-radius:6px;margin:6px 0;text-align:center;font-weight:500}
.hint-slow{background:#f59e0b22;color:#f59e0b}
.hint-good{background:#22c55e22;color:#22c55e}
.hint-clip{background:#ef444422;color:#ef4444}
.hint-span{background:#2563eb22;color:#60a5fa}
.cal-meta{display:flex;justify-content:space-between;font-size:11px;color:#888;margin-top:4px}
</style>
</head><body>

<div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:12px">
<h1>OpenDisc<span id="autoTag" class="auto-tag"></span></h1>
<div style="display:flex;align-items:center;gap:8px">
<span id="st" class="status s-idle">IDLE</span>
<button class="icon-btn" onclick="openSettings()" title="Settings">&#9881;</button>
</div>
</div>

<!-- CAL REQUIRED BANNER -->
<div class="card" id="calBanner" style="display:none;background:#f59e0b22;border-color:#f59e0b">
<h2 style="color:#f59e0b">Calibration required</h2>
<p style="font-size:13px;color:#ccc;margin-bottom:8px">Spin the disc on a flat surface at varying speeds (200&ndash;500 RPM) to calibrate the sensor offset.
This enables accurate MPH, RPM above 333, and throw analysis.</p>
<button onclick="document.getElementById('calCard').scrollIntoView({behavior:'smooth'})">Go to calibration</button>
</div>

<!-- LAST THROW -->
<div class="card" id="lastThrowCard" style="display:none">
<h2>Last throw</h2>
<div class="mph" id="ltMph">--</div>
<div class="mph-lbl">MPH at release</div>
<div class="grid" style="margin-top:12px">
  <div class="metric"><div class="val" id="ltRpm">--</div><div class="lbl">Release RPM</div></div>
  <div class="metric"><div class="val" id="ltPeakG">--</div><div class="lbl">Peak g</div></div>
  <div class="metric"><div class="val" id="ltHyzer">--</div><div class="lbl">Launch hyzer &deg;</div></div>
  <div class="metric"><div class="val" id="ltNose">--</div><div class="lbl">Launch nose &deg;</div></div>
  <div class="metric"><div class="val" id="ltWobble">--</div><div class="lbl">Wobble &deg;</div></div>
  <div class="metric"><div class="val" id="ltDur">--</div><div class="lbl">Duration ms</div></div>
</div>
</div>

<!-- HISTORY -->
<div class="card">
<h2 style="display:flex;justify-content:space-between;align-items:center">Throw history <button class="icon-btn" style="width:auto;height:26px;padding:0 10px;font-size:11px" onclick="clearHistory()">clear</button></h2>
<ul id="hist"><li class="empty">no throws yet</li></ul>
</div>

<!-- SETTINGS MODAL -->
<div class="modal" id="settingsModal">
<div class="modal-body">
<h2>Settings</h2>
<div class="toggle">
  <input type="checkbox" id="optAutoArm">
  <label for="optAutoArm" style="margin:0;text-transform:none;letter-spacing:0;color:#ccc;font-size:13px">Auto-arm on motion</label>
</div>
<label>Trigger threshold <span class="val-readout" id="trgVal">3.0 g</span></label>
<input type="range" id="optTrigger" min="1.5" max="8" step="0.1" value="3.0">
<label style="margin-top:14px">Gyro FS experiment</label>
<div style="display:flex;gap:8px;align-items:center;margin:6px 0">
  <select id="fsSelect" style="background:#222;color:#ccc;border:1px solid #444;padding:4px 8px;border-radius:4px;font-size:13px">
    <option value="0">0 (125 dps?)</option>
    <option value="1">1 (250 dps)</option>
    <option value="2">2 (500 dps)</option>
    <option value="3">3 (1000 dps)</option>
    <option value="4" selected>4 (2000 dps)</option>
    <option value="5">5 (4000 dps? - WRONG per ST fix)</option>
    <option value="6">6 (reserved)</option>
    <option value="7">7 (reserved)</option>
    <option value="12">0xC (4000 dps - per ST fix)</option>
    <option value="13">0xD (FS_G=5 + bit3=1 preserved!)</option>
    <option value="99">CTRL2=0x4C (datasheet method)</option>
  </select>
  <button class="secondary" style="width:auto;padding:6px 12px;margin:0" onclick="setFsG()">Write CTRL6</button>
</div>
<p style="font-size:11px;color:#666;margin-bottom:4px">Do a slow 10s hand rotation after each change. If gz_dps reads ~36, the FS is working at that range. Reading ~72 means still 2000 dps.</p>
<button class="secondary" style="margin:4px 0;width:auto;padding:6px 12px" onclick="eisTest()">Test EIS 4000 dps channel</button>
<pre id="eisResult" style="font-family:monospace;font-size:10px;background:#0a0a0a;padding:4px;border-radius:4px;color:#888;margin:4px 0;display:none"></pre>
<label style="margin-top:8px">IMU diagnostic</label>
<pre id="imuDiag" style="font-family:monospace;font-size:11px;background:#0a0a0a;padding:8px;border-radius:6px;color:#888;white-space:pre-wrap;margin:4px 0">loading...</pre>
<div class="row">
  <button onclick="saveSettings()">Save</button>
  <button class="secondary" onclick="closeSettings()">Cancel</button>
</div>
</div>
</div>

<!-- LIVE READINGS -->
<div class="card">
<h2>Live readings</h2>
<div class="grid">
  <div class="metric"><div class="val big" id="rpm">--</div><div class="lbl">RPM (gyro)</div></div>
  <div class="metric"><div class="val big" id="rpm2">--</div><div class="lbl">RPM (accel)</div></div>
  <div class="metric"><div class="val" id="ag">--</div><div class="lbl">Accel (g)</div></div>
  <div class="metric"><div class="val" id="hg">--</div><div class="lbl">High-g</div></div>
  <div class="metric"><div class="val" id="hyzer">--</div><div class="lbl">Hyzer &deg;</div></div>
  <div class="metric"><div class="val" id="nose">--</div><div class="lbl">Nose &deg;</div></div>
</div>
<canvas id="chart"></canvas>
<pre id="rawDump" style="font-family:monospace;font-size:10px;background:#0a0a0a;padding:6px;border-radius:6px;color:#888;margin-top:8px;white-space:pre"></pre>
</div>

<!-- BURST CAPTURE -->
<div class="card">
<h2>Burst capture</h2>
<p style="font-size:12px;color:#888;margin-bottom:8px">Arms trigger at <span id="thr">3.0</span>g. Captures 200ms pre + 800ms post.</p>
<button id="armBtn" onclick="doArm()">Arm &amp; wait for throw</button>
<div class="row">
  <button class="secondary" id="dumpBtn" onclick="doDump()" disabled>Export CSV</button>
  <button class="secondary" id="chartBtn" onclick="doChart()" disabled>Show chart</button>
</div>
<canvas id="burstChart" style="display:none"></canvas>
</div>

<!-- CALIBRATION -->
<div class="card" id="calCard">
<h2>Radius calibration</h2>
<p class="cal-info">Spin the disc on a flat surface and vary the speed across <b>200&ndash;600 RPM</b>
(faster is better — the signal grows as &omega;&sup2;). Need a wide span for a clean fit.
Result is stored on the device.</p>
<div class="grid" style="margin-top:8px">
  <div class="metric"><div class="val" id="calPts">0</div><div class="lbl">Good samples</div></div>
  <div class="metric"><div class="val" id="calR">--</div><div class="lbl">Radius (mm)</div></div>
</div>
<div id="calProgress" style="display:none">
  <div class="cal-hint" id="calHint">Spin the disc</div>
  <div class="bar"><div id="calBar" style="width:0%"></div></div>
  <div class="cal-meta"><span id="calRange">-- &ndash; -- RPM</span><span id="calPctTxt">0 / 200</span></div>
</div>
<div class="row">
  <button id="calStartBtn" onclick="calStart()">Start collecting</button>
  <button class="danger" id="calStopBtn" onclick="calStop()" disabled>Stop &amp; compute</button>
</div>
<button class="secondary" style="margin-top:6px" onclick="downloadCalCsv()">Download cal CSV</button>
</div>

<!-- DEBUG LOG -->
<div class="card">
<h2 style="display:flex;justify-content:space-between;align-items:center">Debug log <button class="icon-btn" style="width:auto;height:26px;padding:0 10px;font-size:11px" onclick="refreshDebug()">refresh</button></h2>
<div id="log">Connecting...\n</div>
</div>

<script>
const $ = id => document.getElementById(id);
let rpmHist = new Float32Array(120).fill(0);
let histIdx = 0;
let pollTimer = null;
let connected = false;
let lastState = null;
let settings = {auto_arm: true, trigger_g: 3.0};
const HIST_KEY = 'opendisc_throws';
const HIST_MAX = 50;

// Live polling
async function poll() {
  try {
    const r = await fetch('/api/live', {cache: 'no-store'});
    if (!r.ok) throw new Error('HTTP ' + r.status);
    const d = await r.json();
    if (!connected) { connected = true; log('Stream connected'); }

    $('rpm').textContent = d.rpm_gyro.toFixed(0);
    $('rpm').style.color = d.gyro_clipped ? '#f59e0b' : '#fff';
    $('rpm2').textContent = d.rpm_accel >= 0 ? d.rpm_accel.toFixed(0) : '--';
    $('ag').textContent = d.accel_g.toFixed(1);
    $('hg').textContent = d.hg_g.toFixed(1);
    $('hyzer').textContent = d.hyzer.toFixed(1);
    $('nose').textContent = d.nose.toFixed(1);

    rpmHist[histIdx % 120] = d.rpm_gyro;
    histIdx++;
    drawSparkline();

    if (d.raw_ax !== undefined) {
      const p = (v, w) => String(v).padStart(w);
      const hxg = d.raw_hx !== undefined ? (d.raw_hx*0.00977).toFixed(2) : '?';
      const hyg = d.raw_hy !== undefined ? (d.raw_hy*0.00977).toFixed(2) : '?';
      const hzg = d.raw_hz !== undefined ? (d.raw_hz*0.00977).toFixed(2) : '?';
      $('rawDump').textContent =
        'accel  ax=' + p(d.raw_ax,7) + '  ay=' + p(d.raw_ay,7) + '  az=' + p(d.raw_az,7) + '\n' +
        'hi-g   hx=' + p(d.raw_hx||0,7) + '  hy=' + p(d.raw_hy||0,7) + '  hz=' + p(d.raw_hz||0,7) + '\n' +
        'gyro   gx=' + p(d.raw_gx,7) + '  gy=' + p(d.raw_gy,7) + '  gz=' + p(d.raw_gz,7) + '\n' +
        'ax_g=' + d.ax_g.toFixed(3) + '  ay_g=' + d.ay_g.toFixed(3) + '  az_g=' + d.az_g.toFixed(3) +
        '  (|xy|=' + Math.sqrt(d.ax_g*d.ax_g + d.ay_g*d.ay_g).toFixed(3) + 'g)\n' +
        'hx_g=' + hxg + '  hy_g=' + hyg + '  hz_g=' + hzg + '\n' +
        'gz_dps=' + d.gz_dps.toFixed(0) + '  rpm_gyro=' + d.rpm_gyro.toFixed(0);
    }

    const st = $('st');
    st.textContent = d.state;
    st.className = 'status s-' + d.state.toLowerCase();
    $('armBtn').disabled = (d.state === 'ARMED' || d.state === 'CAPTURING');
    $('dumpBtn').disabled = (d.state !== 'DONE');
    $('chartBtn').disabled = (d.state !== 'DONE');
    if (d.state === 'DONE' && lastState !== 'DONE') {
      log('Capture complete! ' + d.samples + ' samples');
      fetchThrow();
    }
    lastState = d.state;
    if (d.calPts !== undefined) $('calPts').textContent = d.calPts;
    if (d.radius !== undefined && d.radius > 0) {
      $('calR').textContent = (d.radius * 1000).toFixed(1);
      $('calBanner').style.display = 'none';
    } else if (d.radius !== undefined && d.radius <= 0) {
      $('calBanner').style.display = 'block';
    }
    updateCalProgress(d);
  } catch (e) {
    if (connected) { connected = false; log('Stream error, retrying...'); }
  }
}

function connect() {
  if (pollTimer) clearInterval(pollTimer);
  poll();
  pollTimer = setInterval(poll, 100);
}

function drawSparkline() {
  const c = $('chart'), ctx = c.getContext('2d');
  const W = c.width = c.offsetWidth * 2, H = c.height = 180 * 2;
  ctx.scale(2, 2);
  const w = W/2, h = H/2;

  let max = 100;
  for (let i = 0; i < 120; i++) if (rpmHist[i] > max) max = rpmHist[i];
  max *= 1.2;

  ctx.clearRect(0, 0, w, h);
  ctx.strokeStyle = '#2563eb44';
  ctx.lineWidth = 0.5;
  for (let y = 0; y < 4; y++) {
    const py = h - (y/3) * (h-20) - 10;
    ctx.beginPath(); ctx.moveTo(0, py); ctx.lineTo(w, py); ctx.stroke();
  }

  ctx.strokeStyle = '#2563eb';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  for (let i = 0; i < 120; i++) {
    const idx = (histIdx - 120 + i + 120*100) % 120;
    const x = (i / 119) * w;
    const y = h - (rpmHist[idx] / max) * (h - 20) - 10;
    i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
  }
  ctx.stroke();

  ctx.fillStyle = '#888';
  ctx.font = '10px system-ui';
  ctx.fillText(max.toFixed(0) + ' RPM', 4, 14);
  ctx.fillText('0', 4, h - 2);
}

// Burst capture
function doArm() {
  fetch('/api/arm').then(r => r.json()).then(d => log(d.msg));
}

function doDump() {
  log('Downloading CSV...');
  window.open('/api/dump', '_blank');
}

function doChart() {
  log('Loading chart data...');
  fetch('/api/dump').then(r => r.text()).then(csv => {
    const lines = csv.trim().split('\n');
    const hdr = lines[0].split(',');
    const data = lines.slice(1).map(l => {
      const v = l.split(',');
      const o = {};
      hdr.forEach((h, i) => o[h] = parseFloat(v[i]));
      return o;
    });
    drawBurst(data);
  });
}

function drawBurst(data) {
  const canvas = $('burstChart');
  canvas.style.display = 'block';
  canvas.height = 360;
  const ctx = canvas.getContext('2d');
  const W = canvas.width = canvas.offsetWidth * 2, H = canvas.height * 2;
  canvas.style.height = '360px';
  ctx.scale(2, 2);
  const w = W/2, h = H/2;

  const times = data.map(d => d.time_us / 1000);
  const t0 = times[0], t1 = times[times.length-1];

  function px(t) { return ((t - t0) / (t1 - t0)) * (w - 40) + 30; }

  // Draw RPM
  let maxRpm = 0;
  data.forEach(d => { if (d.rpm_gyro > maxRpm) maxRpm = d.rpm_gyro; });
  maxRpm = Math.max(maxRpm * 1.1, 100);

  ctx.clearRect(0, 0, w, h);

  // RPM trace (top half)
  const halfH = h / 2 - 10;
  ctx.strokeStyle = '#7c3aed';
  ctx.lineWidth = 1;
  ctx.beginPath();
  data.forEach((d, i) => {
    const x = px(times[i]);
    const y = halfH - (d.rpm_gyro / maxRpm) * halfH + 5;
    i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
  });
  ctx.stroke();

  // G-force trace (bottom half)
  let maxG = 0;
  data.forEach(d => { if (d.hg_mag_g > maxG) maxG = d.hg_mag_g; });
  maxG = Math.max(maxG * 1.1, 5);

  ctx.strokeStyle = '#22c55e';
  ctx.lineWidth = 1;
  ctx.beginPath();
  data.forEach((d, i) => {
    const x = px(times[i]);
    const y = h - (d.hg_mag_g / maxG) * halfH - 5;
    i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
  });
  ctx.stroke();

  // Trigger line
  const trigT = data.find(d => d.sample >= 0);
  if (trigT) {
    const tx = px(trigT.time_us / 1000);
    ctx.strokeStyle = '#ef4444';
    ctx.lineWidth = 0.5;
    ctx.setLineDash([4, 4]);
    ctx.beginPath(); ctx.moveTo(tx, 0); ctx.lineTo(tx, h); ctx.stroke();
    ctx.setLineDash([]);
  }

  ctx.fillStyle = '#7c3aed'; ctx.font = '10px system-ui';
  ctx.fillText('RPM (max ' + maxRpm.toFixed(0) + ')', 4, 14);
  ctx.fillStyle = '#22c55e';
  ctx.fillText('High-g (max ' + maxG.toFixed(0) + 'g)', 4, halfH + 20);
  ctx.fillStyle = '#ef4444';
  ctx.fillText('trigger', (trigT ? px(trigT.time_us/1000) + 4 : 0), h - 4);
}

// Live calibration progress
function updateCalProgress(d) {
  const panel = $('calProgress');
  if (d.state !== 'CALIBRATING') {
    panel.style.display = 'none';
    return;
  }
  panel.style.display = 'block';

  const target = d.calTarget || 200;
  const pts = d.calPts || 0;
  const pct = Math.min(100, (pts / target) * 100);
  $('calBar').style.width = pct + '%';
  $('calPctTxt').textContent = pts + ' / ' + target;

  const lo = d.calRpmMin || 0, hi = d.calRpmMax || 0;
  $('calRange').textContent = (pts > 0)
    ? lo.toFixed(0) + ' – ' + hi.toFixed(0) + ' RPM span ' + (hi - lo).toFixed(0)
    : '-- – -- RPM';

  const hint = $('calHint');
  const rpm = d.rpm_gyro || 0;
  hint.className = 'cal-hint';
  if (d.gyro_clipped) {
    hint.classList.add('hint-clip');
    hint.textContent = 'Too fast — gyro clipping';
  } else if (rpm < 150) {
    hint.classList.add('hint-slow');
    hint.textContent = 'Spin faster (aim 200–600 RPM)';
  } else if (pts >= 20 && (hi - lo) < 150) {
    hint.classList.add('hint-span');
    hint.textContent = 'Vary the speed — need a wider range';
  } else if (pts >= target) {
    hint.classList.add('hint-good');
    hint.textContent = 'Ready — tap Stop & compute';
  } else {
    hint.classList.add('hint-good');
    hint.textContent = 'Good — keep varying the spin';
  }
}

// Calibration
function calStart() {
  fetch('/api/cal/start').then(r => r.json()).then(d => {
    log(d.msg);
    $('calStartBtn').disabled = true;
    $('calStopBtn').disabled = false;
  });
}

function downloadCalCsv() {
  window.open('/api/caldump', '_blank');
}

function calStop() {
  fetch('/api/cal/stop').then(r => r.json()).then(d => {
    log(d.msg);
    if (d.accepted && d.radius > 0) {
      $('calR').textContent = (d.radius * 1000).toFixed(1);
    }
    $('calStartBtn').disabled = false;
    $('calStopBtn').disabled = true;
  });
}

function log(msg) {
  const el = $('log');
  el.textContent += msg + '\n';
  el.scrollTop = el.scrollHeight;
}

// ── Last throw & history ──
async function fetchThrow() {
  try {
    const r = await fetch('/api/throw');
    const d = await r.json();
    if (!d.valid) { log('Throw analyzer: no release detected'); return; }
    renderLastThrow(d);
    pushHistory(d);
  } catch (e) { log('Throw fetch error: ' + e.message); }
}

function renderLastThrow(d) {
  $('lastThrowCard').style.display = 'block';
  const mphEl = $('ltMph');
  if (d.mph >= 0) {
    mphEl.textContent = d.mph.toFixed(1);
    mphEl.classList.remove('bad');
  } else {
    mphEl.textContent = '--';
    mphEl.classList.add('bad');
  }
  $('ltRpm').textContent = d.rpm.toFixed(0);
  $('ltPeakG').textContent = d.peak_g.toFixed(1);
  $('ltHyzer').textContent = d.hyzer.toFixed(1);
  $('ltNose').textContent = d.nose.toFixed(1);
  $('ltWobble').textContent = d.wobble.toFixed(1);
  $('ltDur').textContent = (d.duration_ms || 0);
  localStorage.setItem('opendisc_last_throw', JSON.stringify(d));
}

function restoreLastThrow() {
  try {
    const d = JSON.parse(localStorage.getItem('opendisc_last_throw'));
    if (d && d.rpm !== undefined) renderLastThrow(d);
  } catch(e) {}
}

function loadHistory() {
  try { return JSON.parse(localStorage.getItem(HIST_KEY) || '[]'); }
  catch (e) { return []; }
}

function saveHistory(list) {
  localStorage.setItem(HIST_KEY, JSON.stringify(list));
}

function pushHistory(d) {
  const list = loadHistory();
  list.unshift({
    t: Date.now(),
    mph: d.mph,
    rpm: d.rpm,
    hyzer: d.launch_hyzer,
    nose: d.launch_nose,
    wobble: d.wobble,
    peak_g: d.peak_g
  });
  if (list.length > HIST_MAX) list.length = HIST_MAX;
  saveHistory(list);
  renderHistory();
}

function renderHistory() {
  const ul = $('hist');
  const list = loadHistory();
  if (list.length === 0) {
    ul.innerHTML = '<li class="empty">no throws yet</li>';
    return;
  }
  ul.innerHTML = list.map(e => {
    const when = new Date(e.t);
    const hh = when.getHours().toString().padStart(2,'0');
    const mm = when.getMinutes().toString().padStart(2,'0');
    const mph = e.mph >= 0 ? e.mph.toFixed(1) + ' mph' : '-- mph';
    return '<li><span class="t">' + hh + ':' + mm + '</span>' +
           '<span class="m">' + mph + '</span>' +
           '<span class="r">' + e.rpm.toFixed(0) + ' rpm</span></li>';
  }).join('');
}

function clearHistory() {
  if (!confirm('Clear throw history?')) return;
  localStorage.removeItem(HIST_KEY);
  renderHistory();
}

// ── Settings ──
async function loadSettings() {
  try {
    const r = await fetch('/api/settings');
    settings = await r.json();
    $('autoTag').textContent = settings.auto_arm ? '(auto)' : '';
    $('thr').textContent = settings.trigger_g.toFixed(1);
  } catch (e) {}
}

async function refreshImuDiag() {
  const el = $('imuDiag');
  try {
    const r = await fetch('/api/imudiag', {cache: 'no-store'});
    const d = await r.json();
    const whoOk = d.whoami === '0x73' ? 'ok' : 'BAD (expect 0x73)';
    el.textContent =
      'WHO_AM_I: ' + d.whoami + '  ' + whoOk + '\n' +
      'CTRL1: ' + d.ctrl1 + '   ODR_XL=' + d.odr_xl + ' OP=' + d.op_xl + '\n' +
      'CTRL2: ' + d.ctrl2 + '   ODR_G=' + d.odr_g + ' OP=' + d.op_g + '\n' +
      'CTRL3: ' + d.ctrl3 + '\n' +
      'CTRL4: ' + d.ctrl4 + '\n' +
      'CTRL5: ' + d.ctrl5 + '\n' +
      'CTRL6: ' + d.ctrl6 + '   FS_G=' + d.fs_g + '\n' +
      'CTRL8: ' + d.ctrl8 + '   FS_XL=' + d.fs_xl + '\n' +
      'CTRL9: ' + d.ctrl9 + '   (filter bits)\n' +
      'CTRL10: ' + d.ctrl10 + '\n' +
      'CTRL1_XL_HG: ' + d.ctrl1_xl_hg + '\n' +
      '─── cal peaks ───\n' +
      'raw accel max: x=' + d.cal_raw_ax_max + ' y=' + d.cal_raw_ay_max + ' z=' + d.cal_raw_az_max + '\n' +
      'raw gyro max:  x=' + d.cal_raw_gx_max + ' y=' + d.cal_raw_gy_max + ' z=' + d.cal_raw_gz_max + '\n' +
      'axy peak: ' + d.cal_axy_max.toFixed(1) + ' m/s² (' + (d.cal_axy_max/9.81).toFixed(2) + ' g)\n' +
      'rpm peak: ' + d.cal_rpm_max.toFixed(0) + '\n' +
      '(±16g saturates at raw ±32768; ±4000dps at raw ±28571)';
  } catch (e) {
    el.textContent = 'diag error: ' + e.message;
  }
}

async function eisTest() {
  const el = $('eisResult');
  el.style.display = 'block';
  el.textContent = 'testing... rotate the board slowly while this runs';
  try {
    // Take 5 readings over 2 seconds while user rotates
    let results = [];
    for (let i = 0; i < 5; i++) {
      const r = await fetch('/api/eis_test', {cache: 'no-store'});
      const d = await r.json();
      results.push(d);
      await new Promise(r => setTimeout(r, 400));
    }
    let txt = 'CTRL_EIS: ' + results[0].eis_ctrl + '\n\n';
    txt += 'sample | main_gz (raw) | eis_gz (raw) | ratio | main@70mdps | eis@140mdps\n';
    for (const d of results) {
      txt += '       | ' + String(d.main_gz).padStart(13) + ' | ' +
             String(d.eis_gz).padStart(12) + ' | ' +
             d.ratio.toFixed(3).padStart(5) + ' | ' +
             d.main_gz_dps.toFixed(1).padStart(11) + ' | ' +
             d.eis_gz_dps_at4000.toFixed(1).padStart(11) + '\n';
    }
    txt += '\nIf ratio ~0.5 and eis@140 matches main@70, EIS is at 4000 dps!';
    txt += '\nIf ratio ~1.0, EIS is also stuck at 2000 dps.';
    el.textContent = txt;
  } catch(e) { el.textContent = 'error: ' + e.message; }
}

async function setFsG() {
  const val = $('fsSelect').value;
  try {
    const r = await fetch('/api/setfsg?v=' + val, {cache: 'no-store'});
    const d = await r.json();
    log('CTRL6 written: 0x' + parseInt(val).toString(16).padStart(2,'0') + ' -> readback ' + d.ctrl6 + ' (fs_g=' + d.fs_g + ')');
    refreshImuDiag();
  } catch (e) { log('setfsg error: ' + e.message); }
}

function openSettings() {
  $('optAutoArm').checked = !!settings.auto_arm;
  $('optTrigger').value = settings.trigger_g;
  $('trgVal').textContent = settings.trigger_g.toFixed(1) + ' g';
  $('settingsModal').classList.add('on');
  refreshImuDiag();
}

function closeSettings() { $('settingsModal').classList.remove('on'); }

async function saveSettings() {
  const body = new URLSearchParams();
  body.append('auto_arm', $('optAutoArm').checked ? '1' : '0');
  body.append('trigger_g', $('optTrigger').value);
  try {
    const r = await fetch('/api/settings', {method: 'POST', body});
    settings = await r.json();
    $('autoTag').textContent = settings.auto_arm ? '(auto)' : '';
    $('thr').textContent = settings.trigger_g.toFixed(1);
    closeSettings();
    log('Settings saved');
  } catch (e) { log('Settings error: ' + e.message); }
}

document.addEventListener('DOMContentLoaded', () => {
  document.getElementById('optTrigger').addEventListener('input', e => {
    $('trgVal').textContent = parseFloat(e.target.value).toFixed(1) + ' g';
  });
});

async function refreshDebug() {
  try {
    const r = await fetch('/api/debuglog', {cache: 'no-store'});
    const msgs = await r.json();
    if (msgs.length > 0) {
      const el = $('log');
      el.textContent = msgs.join('\n') + '\n';
      el.scrollTop = el.scrollHeight;
    }
  } catch(e) {}
}
setInterval(refreshDebug, 2000);

restoreLastThrow();
renderHistory();
loadSettings();
connect();
</script>
</body></html>
)rawliteral";

#endif
