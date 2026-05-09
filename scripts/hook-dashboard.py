#!/usr/bin/env python3
"""
hook-dashboard — 브라우저로 훅 발동 실시간 시각화 (B안)

사용법:
  python3 ~/.claude/scripts/hook-dashboard.py
  # 자동으로 브라우저 열림 → http://localhost:8765

설계:
- Server-Sent Events (SSE)로 jsonl 새 라인 푸시
- 의존성 0 (표준 라이브러리만)
- 비용: 백그라운드 1개 프로세스 (CPU ~0%, 메모리 ~20MB)
"""
import http.server
import socketserver
import json
import os
import threading
import time
import webbrowser
from datetime import datetime, timedelta
from pathlib import Path
from collections import defaultdict, deque

PORT = 8765
HOST = "127.0.0.1"
TRACE_DIR = Path.home() / ".claude" / "cache" / "hook-trace"

# /usage endpoint 캐시 (60초 TTL — 풀 스캔 8~9초이므로 매 호출 회피)
_usage_cache = {}


def _warm_usage_cache():
    """백그라운드: 45초마다 usage 데이터 미리 계산해 캐시 적재.
    Claude projects 풀 스캔 8~9초 — 60초 TTL과 맞춰 항상 신선한 캐시 유지."""
    import subprocess
    while True:
        try:
            result = subprocess.run(
                ["/usr/bin/python3", os.path.expanduser("~/.claude/scripts/llm-usage.py"), "--json"],
                capture_output=True, text=True, timeout=60
            )
            if result.returncode == 0:
                _usage_cache['payload'] = result.stdout
                _usage_cache['at'] = time.time()
        except Exception:
            pass
        time.sleep(45)  # 45초 — TTL 60초 안에 항상 갱신


def _rotate_old_logs():
    """매일 30일 이상 된 timing/trace 파일을 _archive로 이동 (삭제 안 함, 안전 우선)."""
    import shutil
    while True:
        try:
            now = time.time()
            cutoff = now - 30 * 86400  # 30일
            for d in [TRACE_DIR, Path.home() / ".claude" / "cache" / "hook-timing"]:
                if not d.exists():
                    continue
                archive = d / "_archive"
                archive.mkdir(exist_ok=True)
                for f in d.glob("*.tsv"):
                    if f.stat().st_mtime < cutoff and f.parent == d:
                        shutil.move(str(f), str(archive / f.name))
                for f in d.glob("*.jsonl"):
                    if f.stat().st_mtime < cutoff and f.parent == d:
                        shutil.move(str(f), str(archive / f.name))
        except Exception:
            pass
        # 매일 1회 (자정 직후 효과)
        time.sleep(86400)

HTML = r"""<!DOCTYPE html>
<html lang="ko">
<head>
<meta charset="utf-8">
<title>Hook Dashboard</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chartjs-adapter-date-fns/dist/chartjs-adapter-date-fns.bundle.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/chartjs-chart-matrix@2.0.1/dist/chartjs-chart-matrix.min.js"></script>
<style>
  * { box-sizing: border-box; }
  body { font-family: -apple-system, BlinkMacSystemFont, monospace; margin: 0; padding: 16px;
         background: #0d1117; color: #c9d1d9; }
  h1 { font-size: 18px; margin: 0 0 12px; }
  .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 8px; }
  .live { display: inline-block; width: 8px; height: 8px; border-radius: 50%;
          background: #56d364; animation: pulse 1s infinite; }
  @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:.4} }
  .grid-top { display: grid; grid-template-columns: 1.5fr 1fr 1fr; gap: 12px; margin-bottom: 12px; }
  .grid-mid { display: grid; grid-template-columns: 2fr 1fr; gap: 12px; margin-bottom: 12px; }
  .grid-bot { display: grid; grid-template-columns: 1fr; gap: 12px; }
  .panel { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 12px;
           position: relative; }
  h2 { font-size: 13px; margin: 0 0 8px; color: #c9d1d9; font-weight: 600; }
  h2 .sub { color: #8b949e; font-weight: 400; font-size: 11px; margin-left: 4px; }
  .stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 8px; }
  .stat { display: flex; flex-direction: column; padding: 4px 0; }
  .stat .l { font-size: 11px; color: #8b949e; }
  .stat .v { color: #58a6ff; font-weight: 600; font-size: 16px; }
  .stat.warn .v { color: #d29922; }
  .stat.bad .v { color: #f85149; }
  .stream { max-height: 320px; overflow-y: auto; font-size: 11px; line-height: 1.4;
            font-family: ui-monospace, monospace; }
  .row { display: grid; grid-template-columns: 70px 220px 60px 50px 90px 70px 70px; gap: 6px;
         padding: 2px 4px; border-bottom: 1px solid #21262d; }
  .row:hover { background: #1c2128; }
  .ts { color: #8b949e; }
  .hk { color: #c9d1d9; }
  .ms { text-align: right; }
  .ms.fast { color: #56d364; }
  .ms.med  { color: #d29922; }
  .ms.slow { color: #f85149; }
  .ev { color: #79c0ff; font-size: 10px; }
  .tl { color: #d2a8ff; font-size: 10px; }
  .se { color: #8b949e; font-size: 10px; }
  .se.output { color: #79c0ff; }
  .se.block_or_error { color: #f85149; }
  .filter { width: 100%; padding: 5px; background: #0d1117; color: #c9d1d9;
            border: 1px solid #30363d; border-radius: 4px; font-size: 11px; margin-bottom: 6px; }
  canvas { max-height: 280px; }
  #cv-timeline { max-height: 420px; height: 420px !important; }
  .legend { display: flex; gap: 12px; font-size: 10px; color: #8b949e; margin-top: 4px; }
  .legend span::before { content: "■ "; }
  .legend .a { color: #79c0ff; }   /* PreToolUse */
  .legend .b { color: #d2a8ff; }   /* PostToolUse */
  .legend .c { color: #56d364; }   /* UserPromptSubmit */
  .legend .d { color: #d29922; }   /* Stop */
  .legend .e { color: #f85149; }   /* Other */
</style>
</head>
<body>
<div class="header">
  <h1>🔍 Claude Code Hook Dashboard</h1>
  <span><span class="live"></span> 실시간 (<span id="rate">0</span> 발동/분 · 누적 <span id="total">0</span>건)</span>
</div>

<!-- 1행: 요약 + 이벤트 도넛 + 사이드이펙트 도넛 -->
<div class="grid-top">
  <div class="panel">
    <h2>요약 <span class="sub">전체 누적</span></h2>
    <div class="stats">
      <div class="stat"><span class="l">총 발동</span><span class="v" id="s_total">0</span></div>
      <div class="stat"><span class="l">훅 종류</span><span class="v" id="s_kinds">0</span></div>
      <div class="stat"><span class="l">평균 ms</span><span class="v" id="s_avg">0</span></div>
      <div class="stat"><span class="l">최대 ms</span><span class="v" id="s_max">0</span></div>
      <div class="stat warn"><span class="l">noop %</span><span class="v" id="s_noop">0%</span></div>
      <div class="stat bad"><span class="l">차단/에러</span><span class="v" id="s_blk">0</span></div>
    </div>
  </div>
  <div class="panel">
    <h2>이벤트 분포 <span class="sub">F</span></h2>
    <canvas id="cv-event"></canvas>
  </div>
  <div class="panel">
    <h2>사이드이펙트 <span class="sub">noop vs output</span></h2>
    <canvas id="cv-side"></canvas>
  </div>
</div>

<!-- 2행: 빈도 막대 (TOP) + 속도 분포 -->
<div class="grid-mid">
  <div class="panel">
    <h2>TOP 15 훅 빈도 <span class="sub">C — 어떤 훅이 많이 도는가</span></h2>
    <canvas id="cv-freq"></canvas>
  </div>
  <div class="panel">
    <h2>속도 분포 <span class="sub">D — duration_ms 히스토그램</span></h2>
    <canvas id="cv-dur"></canvas>
  </div>
</div>

<!-- 3행: 실시간 타임라인 (스택 바 — 동시 발동 = 막대 높이) -->
<div class="grid-bot">
  <div class="panel">
    <h2>실시간 타임라인 <span class="sub">A — 최근 5분, 1초 단위 막대 = 동시 발동 수, 색 = 이벤트</span></h2>
    <canvas id="cv-timeline"></canvas>
    <div class="legend">
      <span style="color:#79c0ff">■ PreToolUse</span>
      <span style="color:#d2a8ff">■ PostToolUse</span>
      <span style="color:#56d364">■ UserPromptSubmit</span>
      <span style="color:#d29922">■ Stop</span>
      <span style="color:#8b949e">막대 높을수록 = 한 사건에 더 많은 훅 발동 (클러스터 폭발)</span>
    </div>
  </div>
</div>

<!-- 4행: LLM 사용량 -->
<div class="grid-top" style="margin-top:12px">
  <div class="panel">
    <h2>LLM 누적 비용 <span class="sub">USD 추정 — 1년치</span></h2>
    <canvas id="cv-llm-cost"></canvas>
    <div class="legend"><span style="color:#8b949e" id="llm-updated">로딩...</span></div>
  </div>
  <div class="panel">
    <h2>일별 비용 추이 <span class="sub">최근 14일 ($)</span></h2>
    <canvas id="cv-llm-daily"></canvas>
  </div>
  <div class="panel">
    <h2>모델별 비용 분포 <span class="sub">Codex+Gemini 합산</span></h2>
    <canvas id="cv-llm-models"></canvas>
  </div>
</div>

<!-- 4-2행: 토큰 정보 (보조) -->
<div class="grid-top" style="margin-top:12px">
  <div class="panel">
    <h2>LLM 누적 토큰 <span class="sub">log scale</span></h2>
    <canvas id="cv-llm-total"></canvas>
  </div>
  <div class="panel">
    <h2>일별 토큰 추이 <span class="sub">최근 14일</span></h2>
    <canvas id="cv-llm-tokens-daily"></canvas>
  </div>
  <div class="panel">
    <h2>LLM별 세션/호출 <span class="sub">누적</span></h2>
    <canvas id="cv-llm-sessions"></canvas>
  </div>
</div>

<!-- 4-3행: 프로젝트별 사용량 -->
<div class="grid-bot" style="margin-top:12px">
  <div class="panel">
    <h2>프로젝트별 누적 비용 <span class="sub">Claude Code · TOP 15</span></h2>
    <canvas id="cv-projects" style="max-height: 400px"></canvas>
  </div>
</div>

<!-- 5행: 실시간 스트림 표 -->
<div class="grid-bot" style="margin-top:12px">
  <div class="panel">
    <h2>실시간 스트림 <span class="sub">최근 200건, 최신순</span></h2>
    <input class="filter" id="filter" placeholder="필터: 훅 이름, 이벤트, 도구 (예: gemini, Bash, PreToolUse)">
    <div class="stream" id="stream"></div>
  </div>
</div>

<script>
// ===== 색상 매핑 =====
const EVT_COLOR = {
  'PreToolUse':       '#79c0ff',
  'PostToolUse':      '#d2a8ff',
  'UserPromptSubmit': '#56d364',
  'Stop':             '#d29922',
  '':                 '#8b949e'
};
function evtColor(e) { return EVT_COLOR[e] !== undefined ? EVT_COLOR[e] : '#f85149'; }

// ===== 상태 =====
const events = [];           // 최근 N건 (스트림용)
const counts = {};           // 훅별 카운트
const eventDist = {};        // 이벤트별 카운트
const sideDist = {};         // side별 카운트
const recent = [];           // 분당 율
const durationBuckets = [0,0,0,0,0,0,0,0]; // <20, 20-50, 50-100, 100-200, 200-500, 500-1000, 1000-2000, 2000+
const bucketLabels = ['<20ms','20-50','50-100','100-200','200-500','500ms-1s','1-2s','2s+'];
let totalAll = 0, sumAll = 0, maxAll = 0, noopAll = 0, blockedAll = 0;

function bucketIdx(ms) {
  ms = parseInt(ms);
  if (ms < 20) return 0;
  if (ms < 50) return 1;
  if (ms < 100) return 2;
  if (ms < 200) return 3;
  if (ms < 500) return 4;
  if (ms < 1000) return 5;
  if (ms < 2000) return 6;
  return 7;
}
function classify(ms) {
  ms = parseInt(ms);
  if (ms < 50) return 'fast';
  if (ms < 150) return 'med';
  return 'slow';
}

// ===== Chart.js 공통 옵션 =====
const baseOpt = {
  responsive: true,
  maintainAspectRatio: true,
  animation: false,
  plugins: { legend: { labels: { color: '#c9d1d9', font: { size: 10 } } } },
  scales: {
    x: { ticks: { color: '#8b949e', font: { size: 10 } }, grid: { color: '#21262d' } },
    y: { ticks: { color: '#8b949e', font: { size: 10 } }, grid: { color: '#21262d' } }
  }
};

// ===== 차트 1: 이벤트 도넛 =====
const chEvent = new Chart(document.getElementById('cv-event'), {
  type: 'doughnut',
  data: { labels: [], datasets: [{ data: [], backgroundColor: [] }] },
  options: { responsive: true, maintainAspectRatio: true, animation: false,
    plugins: { legend: { position: 'right', labels: { color: '#c9d1d9', font: { size: 10 } } } } }
});

// ===== 차트 2: 사이드이펙트 도넛 =====
const chSide = new Chart(document.getElementById('cv-side'), {
  type: 'doughnut',
  data: { labels: [], datasets: [{ data: [],
    backgroundColor: ['#8b949e','#79c0ff','#f85149'] }] },
  options: { responsive: true, maintainAspectRatio: true, animation: false,
    plugins: { legend: { position: 'right', labels: { color: '#c9d1d9', font: { size: 10 } } } } }
});

// ===== 차트 3: TOP15 빈도 가로 막대 =====
const chFreq = new Chart(document.getElementById('cv-freq'), {
  type: 'bar',
  data: { labels: [], datasets: [{ label: '호출 수', data: [], backgroundColor: '#58a6ff' }] },
  options: { ...baseOpt, indexAxis: 'y',
    plugins: { legend: { display: false } } }
});

// ===== 차트 4: 속도 분포 막대 =====
const chDur = new Chart(document.getElementById('cv-dur'), {
  type: 'bar',
  data: { labels: bucketLabels, datasets: [{ label: '건수',
    data: durationBuckets,
    backgroundColor: ['#56d364','#56d364','#79c0ff','#79c0ff','#d29922','#d29922','#f85149','#f85149'] }] },
  options: { ...baseOpt, plugins: { legend: { display: false } } }
});

// ===== 차트 5: 실시간 타임라인 — Stacked Bar (동시 발동 막대) =====
// 1초 버킷마다 발동 수를 막대로 쌓고, 색=이벤트
// 변경 이유: heatmap 시도 시 셀 값이 99% '1'로 분포 → 시각 차이 0
//           실제 시그널은 "한 시각에 몇 개 훅이 묶여 발동했나" → 막대 높이가 직관적
//   - X축: 1초 버킷 (시간 진행)
//   - Y축: 발동 수 (막대 높이)
//   - 막대 높이 = 클러스터 크기 (8~10이면 폭발)
//   - 색 segment = 이벤트 종류

const TL_WINDOW_MS = 5 * 60 * 1000;
const TL_BUCKET_MS = 1000;  // 1초 버킷

const chTimeline = new Chart(document.getElementById('cv-timeline'), {
  type: 'bar',
  data: {
    labels: [],  // 시간 라벨
    datasets: [
      { label: 'PreToolUse',       data: [], backgroundColor: '#79c0ff', stack: 's' },
      { label: 'PostToolUse',      data: [], backgroundColor: '#d2a8ff', stack: 's' },
      { label: 'UserPromptSubmit', data: [], backgroundColor: '#56d364', stack: 's' },
      { label: 'Stop',             data: [], backgroundColor: '#d29922', stack: 's' },
      { label: '기타',              data: [], backgroundColor: '#8b949e', stack: 's' }
    ]
  },
  options: {
    responsive: true,
    maintainAspectRatio: false,
    animation: false,
    plugins: {
      legend: { display: false },  // 위에 별도 legend 있음
      tooltip: {
        mode: 'index',
        intersect: false,
        callbacks: {
          title: ctx => ctx[0].label,
          afterBody: ctx => {
            const idx = ctx[0].dataIndex;
            const meta = chTimeline._meta && chTimeline._meta[idx];
            if (!meta) return [];
            const total = meta.hooks.length;
            const lines = [`총 ${total}개 훅 발동`, `평균 ${meta.avgMs}ms`];
            if (meta.maxMs > 200) lines.push(`최대 ${meta.maxMs}ms ⚠️`);
            // TOP 5 훅 이름
            const cnt = {};
            meta.hooks.forEach(h => { cnt[h.hook] = (cnt[h.hook]||0)+1; });
            const topHooks = Object.entries(cnt).sort((a,b)=>b[1]-a[1]).slice(0,5);
            lines.push('주요: ' + topHooks.map(([h,c])=>`${h}${c>1?'×'+c:''}`).join(', '));
            return lines;
          }
        }
      }
    },
    scales: {
      x: {
        stacked: true,
        ticks: {
          color: '#8b949e', font: { size: 10 },
          maxRotation: 0, autoSkip: true, maxTicksLimit: 12
        },
        grid: { display: false }
      },
      y: {
        stacked: true,
        beginAtZero: true,
        ticks: { color: '#8b949e', font: { size: 10 }, stepSize: 1 },
        grid: { color: '#21262d' },
        title: { display: true, text: '동시 발동 훅 수', color: '#8b949e', font: { size: 11 } }
      }
    },
    onClick: (evt, elements) => {
      if (!elements.length) return;
      const idx = elements[0].index;
      const meta = chTimeline._meta && chTimeline._meta[idx];
      if (meta) {
        // 클릭한 시각으로 스트림 필터 (시:분:초)
        document.getElementById('filter').value = chTimeline.data.labels[idx];
        render();
      }
    }
  }
});

// ===== 데이터 흡수 =====
// 타임라인용 raw 이벤트 보관 (5분 윈도우)
const tlEvents = [];  // {epoch, hook, ms, event}

function ingest(d, isLive) {
  events.unshift(d);
  if (events.length > 500) events.pop();
  totalAll++;
  const ms = parseInt(d.ms);
  sumAll += ms;
  if (ms > maxAll) maxAll = ms;
  if (d.side === 'noop') noopAll++;
  if (d.exit && d.exit !== 0 && d.exit !== '0') blockedAll++;
  counts[d.hook] = (counts[d.hook]||0) + 1;
  eventDist[d.event||'?'] = (eventDist[d.event||'?']||0) + 1;
  sideDist[d.side||'?'] = (sideDist[d.side||'?']||0) + 1;
  durationBuckets[bucketIdx(ms)]++;

  // 타임라인 raw 보관 (집계는 render 시점)
  const epoch = new Date(d.ts.replace(/\s/, 'T')).getTime() || Date.now();
  tlEvents.push({ epoch, hook: d.hook, ms, event: d.event });

  if (isLive) recent.push(Date.now());
}

function pruneTimeline() {
  const cutoff = Date.now() - TL_WINDOW_MS;
  // 앞쪽부터 제거 (시간순 보장)
  while (tlEvents.length && tlEvents[0].epoch < cutoff) tlEvents.shift();
}

// 1초 버킷별 이벤트별 카운트 빌드 (stacked bar용)
function buildTimelineBars() {
  pruneTimeline();

  // 5분 윈도우의 모든 1초 버킷 (활동 없어도 0으로 표시 — 흐름 가시성)
  const now = Date.now();
  const startBucket = Math.floor((now - TL_WINDOW_MS) / TL_BUCKET_MS) * TL_BUCKET_MS;
  const endBucket = Math.floor(now / TL_BUCKET_MS) * TL_BUCKET_MS;
  const numBuckets = Math.floor((endBucket - startBucket) / TL_BUCKET_MS) + 1;

  // 5분 = 300버킷 → x축 라벨 너무 많으니 큰 윈도우면 5초 단위로 압축
  const COMPRESS = numBuckets > 60 ? 5 : 1;  // 5분이면 5초 버킷
  const realBucketMs = TL_BUCKET_MS * COMPRESS;

  const buckets = [];
  for (let t = startBucket; t <= endBucket; t += realBucketMs) {
    buckets.push({
      t,
      counts: { 'PreToolUse': 0, 'PostToolUse': 0, 'UserPromptSubmit': 0, 'Stop': 0, '기타': 0 },
      hooks: [],
      sumMs: 0
    });
  }

  tlEvents.forEach(e => {
    const idx = Math.floor((e.epoch - startBucket) / realBucketMs);
    if (idx < 0 || idx >= buckets.length) return;
    const b = buckets[idx];
    const evtKey = e.event in b.counts ? e.event : '기타';
    b.counts[evtKey]++;
    b.hooks.push({ hook: e.hook, ms: e.ms, event: e.event });
    b.sumMs += e.ms;
  });

  // 레이블 (HH:MM:SS)
  const labels = buckets.map(b => {
    const d = new Date(b.t);
    return d.getHours().toString().padStart(2,'0') + ':' +
           d.getMinutes().toString().padStart(2,'0') + ':' +
           d.getSeconds().toString().padStart(2,'0');
  });

  // 데이터셋별 배열
  const ds = {
    'PreToolUse':       buckets.map(b => b.counts['PreToolUse']),
    'PostToolUse':      buckets.map(b => b.counts['PostToolUse']),
    'UserPromptSubmit': buckets.map(b => b.counts['UserPromptSubmit']),
    'Stop':             buckets.map(b => b.counts['Stop']),
    '기타':              buckets.map(b => b.counts['기타'])
  };

  // 메타 (툴팁용)
  const meta = buckets.map(b => ({
    hooks: b.hooks,
    avgMs: b.hooks.length ? Math.round(b.sumMs / b.hooks.length) : 0,
    maxMs: b.hooks.length ? Math.max(...b.hooks.map(h=>h.ms)) : 0
  }));

  return { labels, ds, meta };
}

// ===== 렌더 =====
const stream = document.getElementById('stream');
const filterEl = document.getElementById('filter');

function render() {
  // 요약 통계
  document.getElementById('s_total').textContent = totalAll;
  document.getElementById('total').textContent = totalAll;
  document.getElementById('s_kinds').textContent = Object.keys(counts).length;
  document.getElementById('s_avg').textContent = totalAll ? Math.round(sumAll/totalAll) : 0;
  document.getElementById('s_max').textContent = maxAll;
  document.getElementById('s_noop').textContent = totalAll ? Math.round(noopAll/totalAll*100) + '%' : '0%';
  document.getElementById('s_blk').textContent = blockedAll;

  // 이벤트 도넛
  const evEntries = Object.entries(eventDist).sort((a,b)=>b[1]-a[1]);
  chEvent.data.labels = evEntries.map(([k]) => k);
  chEvent.data.datasets[0].data = evEntries.map(([_,v]) => v);
  chEvent.data.datasets[0].backgroundColor = evEntries.map(([k]) => evtColor(k));
  chEvent.update('none');

  // 사이드 도넛
  const sideEntries = Object.entries(sideDist).sort((a,b)=>b[1]-a[1]);
  chSide.data.labels = sideEntries.map(([k]) => k);
  chSide.data.datasets[0].data = sideEntries.map(([_,v]) => v);
  chSide.update('none');

  // 빈도 막대 TOP15
  const top = Object.entries(counts).sort((a,b)=>b[1]-a[1]).slice(0,15);
  chFreq.data.labels = top.map(([h]) => h);
  chFreq.data.datasets[0].data = top.map(([_,c]) => c);
  chFreq.update('none');

  // 속도 분포
  chDur.data.datasets[0].data = durationBuckets;
  chDur.update('none');

  // 타임라인 — 시간 버킷별 동시 발동 막대 (stacked bar)
  const tb = buildTimelineBars();
  chTimeline.data.labels = tb.labels;
  chTimeline.data.datasets[0].data = tb.ds['PreToolUse'];
  chTimeline.data.datasets[1].data = tb.ds['PostToolUse'];
  chTimeline.data.datasets[2].data = tb.ds['UserPromptSubmit'];
  chTimeline.data.datasets[3].data = tb.ds['Stop'];
  chTimeline.data.datasets[4].data = tb.ds['기타'];
  chTimeline._meta = tb.meta;  // 툴팁용 부가 정보
  chTimeline.update('none');

  // 스트림 표
  const filter = filterEl.value.toLowerCase();
  const filtered = filter
    ? events.filter(e => (e.hook+e.event+e.tool).toLowerCase().includes(filter))
    : events;
  stream.innerHTML = filtered.slice(0, 200).map(e => `
    <div class="row">
      <span class="ts">${e.ts.slice(11,19)}</span>
      <span class="hk">${e.hook}</span>
      <span class="ms ${classify(e.ms)}">${e.ms}ms</span>
      <span class="se">${e.exit}</span>
      <span class="ev">${e.event||'-'}</span>
      <span class="tl">${e.tool||'-'}</span>
      <span class="se ${e.side}">${e.side}</span>
    </div>
  `).join('');
}

filterEl.addEventListener('input', render);

// ===== 분당 율 =====
setInterval(() => {
  const now = Date.now();
  while (recent.length && recent[0] < now - 60000) recent.shift();
  document.getElementById('rate').textContent = recent.length;
}, 1000);

// ===== SSE 실시간 =====
const es = new EventSource('/stream');
let renderPending = false;
function scheduleRender() {
  if (renderPending) return;
  renderPending = true;
  requestAnimationFrame(() => { render(); renderPending = false; });
}
es.onmessage = (e) => {
  try {
    const d = JSON.parse(e.data);
    ingest(d, true);
    scheduleRender();
  } catch (err) { console.error('parse', err); }
};
es.onerror = () => { console.log('stream lost, retrying...'); };

// ===== 초기 백필 =====
fetch('/backfill?n=500').then(r => r.json()).then(arr => {
  arr.reverse().forEach(d => ingest(d, false));
  render();
});

// ===== LLM 사용량 차트 =====
function fmtTokens(n) {
  if (!n) return '0';
  if (n >= 1e9) return (n/1e9).toFixed(2) + 'B';
  if (n >= 1e6) return (n/1e6).toFixed(2) + 'M';
  if (n >= 1e3) return (n/1e3).toFixed(1) + 'K';
  return String(n);
}
function fmtCost(n) {
  if (!n) return '$0';
  if (n >= 1000) return '$' + (n/1000).toFixed(2) + 'K';
  if (n >= 1) return '$' + n.toFixed(2);
  return '$' + n.toFixed(4);
}

// 차트 1: 누적 비용 (메인)
const chLlmCost = new Chart(document.getElementById('cv-llm-cost'), {
  type: 'bar',
  data: { labels: ['Claude Code', 'Codex/GPT', 'Gemini'],
    datasets: [{ label: '누적 비용 USD', data: [0,0,0],
      backgroundColor: ['#79c0ff', '#56d364', '#d2a8ff'] }] },
  options: {
    responsive: true, maintainAspectRatio: true, animation: false,
    plugins: { legend: { display: false },
      tooltip: { callbacks: { label: c => fmtCost(c.raw) } } },
    scales: {
      x: { ticks: { color: '#c9d1d9', font: { size: 10 } }, grid: { display: false } },
      y: { ticks: { color: '#8b949e', font: { size: 10 }, callback: v => fmtCost(v) },
           grid: { color: '#21262d' } }
    }
  }
});

// 차트 2: 일별 비용 추이
const chLlmDaily = new Chart(document.getElementById('cv-llm-daily'), {
  type: 'line',
  data: { labels: [], datasets: [
    { label: 'Claude $', data: [], borderColor: '#79c0ff', backgroundColor: '#79c0ff40', tension: 0.3, fill: true },
    { label: 'Codex $', data: [], borderColor: '#56d364', backgroundColor: '#56d36440', tension: 0.3, fill: true },
    { label: 'Gemini $', data: [], borderColor: '#d2a8ff', backgroundColor: '#d2a8ff40', tension: 0.3, fill: true }
  ]},
  options: {
    responsive: true, maintainAspectRatio: true, animation: false,
    plugins: { legend: { labels: { color: '#c9d1d9', font: { size: 10 } } },
      tooltip: { callbacks: { label: c => `${c.dataset.label}: ${fmtCost(c.raw)}` } } },
    scales: {
      x: { stacked: true, ticks: { color: '#8b949e', font: { size: 9 }, maxRotation: 45 }, grid: { color: '#21262d' } },
      y: { stacked: true, ticks: { color: '#8b949e', font: { size: 10 }, callback: v => fmtCost(v) },
           grid: { color: '#21262d' } }
    }
  }
});

// 차트 3: 모델별 비용 분포 (도넛)
const chLlmModels = new Chart(document.getElementById('cv-llm-models'), {
  type: 'doughnut',
  data: { labels: [], datasets: [{ data: [], backgroundColor: [] }] },
  options: { responsive: true, maintainAspectRatio: true, animation: false,
    plugins: {
      legend: { position: 'right', labels: { color: '#c9d1d9', font: { size: 9 } } },
      tooltip: { callbacks: { label: c => `${c.label}: ${fmtCost(c.raw)}` } } }
  }
});

// 차트 4: 누적 토큰 (보조 — log scale)
const chLlmTotal = new Chart(document.getElementById('cv-llm-total'), {
  type: 'bar',
  data: { labels: ['Claude Code', 'Codex/GPT', 'Gemini', 'Ollama'],
    datasets: [{ label: '누적 토큰', data: [0,0,0,0],
      backgroundColor: ['#79c0ff', '#56d364', '#d2a8ff', '#d29922'] }] },
  options: {
    responsive: true, maintainAspectRatio: true, animation: false,
    plugins: { legend: { display: false },
      tooltip: { callbacks: { label: c => fmtTokens(c.raw) } } },
    scales: {
      x: { ticks: { color: '#c9d1d9', font: { size: 10 } }, grid: { display: false } },
      y: { ticks: { color: '#8b949e', font: { size: 10 }, callback: v => fmtTokens(v) },
           grid: { color: '#21262d' }, type: 'logarithmic' }
    }
  }
});

// 차트 5: 일별 토큰 (보조)
const chLlmTokensDaily = new Chart(document.getElementById('cv-llm-tokens-daily'), {
  type: 'line',
  data: { labels: [], datasets: [
    { label: 'Claude', data: [], borderColor: '#79c0ff', tension: 0.3, fill: false },
    { label: 'Codex', data: [], borderColor: '#56d364', tension: 0.3, fill: false },
    { label: 'Gemini', data: [], borderColor: '#d2a8ff', tension: 0.3, fill: false }
  ]},
  options: {
    responsive: true, maintainAspectRatio: true, animation: false,
    plugins: { legend: { labels: { color: '#c9d1d9', font: { size: 10 } } },
      tooltip: { callbacks: { label: c => `${c.dataset.label}: ${fmtTokens(c.raw)}` } } },
    scales: {
      x: { ticks: { color: '#8b949e', font: { size: 9 }, maxRotation: 45 }, grid: { color: '#21262d' } },
      y: { ticks: { color: '#8b949e', font: { size: 10 }, callback: v => fmtTokens(v) },
           grid: { color: '#21262d' }, type: 'logarithmic' }
    }
  }
});

// 차트 6: 세션/호출 도넛
const chLlmSessions = new Chart(document.getElementById('cv-llm-sessions'), {
  type: 'doughnut',
  data: { labels: [], datasets: [{ data: [],
    backgroundColor: ['#79c0ff', '#56d364', '#d2a8ff', '#d29922'] }] },
  options: { responsive: true, maintainAspectRatio: true, animation: false,
    plugins: { legend: { position: 'right', labels: { color: '#c9d1d9', font: { size: 10 } } } } }
});

// 차트 7: 프로젝트별 비용 가로 막대
const chProjects = new Chart(document.getElementById('cv-projects'), {
  type: 'bar',
  data: { labels: [], datasets: [{ label: '비용 USD', data: [], backgroundColor: '#58a6ff' }] },
  options: {
    responsive: true, maintainAspectRatio: false, animation: false,
    indexAxis: 'y',
    plugins: {
      legend: { display: false },
      tooltip: { callbacks: { label: c => fmtCost(c.raw) } }
    },
    scales: {
      x: { ticks: { color: '#8b949e', font: { size: 10 }, callback: v => fmtCost(v) },
           grid: { color: '#21262d' } },
      y: { ticks: { color: '#c9d1d9', font: { size: 10 } }, grid: { display: false } }
    }
  }
});

function loadUsage() {
  fetch('/usage').then(r => r.json()).then(d => {
    if (d.error) { console.error('usage', d.error); return; }
    const cc = d.claude_code || {}, cx = d.codex || {}, gm = d.gemini || {}, ol = d.ollama || {};
    const ccTotal = (cc.total||{}).in + (cc.total||{}).out + (cc.total||{}).cache_r + (cc.total||{}).cache_c;
    const ccCost = (cc.total||{}).cost || 0;
    const cxCost = (cx.total||{}).cost || 0;
    const gmCost = (gm.total||{}).cost || 0;
    const totalCost = ccCost + cxCost + gmCost;

    // 1) 누적 비용 (메인)
    chLlmCost.data.datasets[0].data = [ccCost, cxCost, gmCost];
    chLlmCost.update('none');

    // 2) 일별 추이 (비용 + 토큰 둘 다)
    const allDays = new Set();
    Object.keys(cc.daily || {}).forEach(k => allDays.add(k));
    Object.keys(cx.daily || {}).forEach(k => allDays.add(k));
    Object.keys(gm.daily || {}).forEach(k => allDays.add(k));
    const sortedDays = [...allDays].sort().slice(-14);
    const dayLabels = sortedDays.map(s => s.slice(5));

    // 비용 추이 (stacked area)
    chLlmDaily.data.labels = dayLabels;
    chLlmDaily.data.datasets[0].data = sortedDays.map(day => cc.daily?.[day]?.cost || 0);
    chLlmDaily.data.datasets[1].data = sortedDays.map(day => cx.daily?.[day]?.cost || 0);
    chLlmDaily.data.datasets[2].data = sortedDays.map(day => gm.daily?.[day]?.cost || 0);
    chLlmDaily.update('none');

    // 토큰 추이 (보조)
    chLlmTokensDaily.data.labels = dayLabels;
    chLlmTokensDaily.data.datasets[0].data = sortedDays.map(day => {
      const c = cc.daily?.[day]; if (!c) return 0;
      return (c.in||0)+(c.out||0)+(c.cache_r||0)+(c.cache_c||0);
    });
    chLlmTokensDaily.data.datasets[1].data = sortedDays.map(day => cx.daily?.[day]?.tokens || 0);
    chLlmTokensDaily.data.datasets[2].data = sortedDays.map(day => gm.daily?.[day]?.tokens || 0);
    chLlmTokensDaily.update('none');

    // 3) 모델별 비용 도넛 — Codex 모델별 + Gemini 모델별
    const modelCosts = [];
    const colors = ['#56d364','#d2a8ff','#79c0ff','#d29922','#f85149','#f97583','#79b8ff','#85e89d','#b392f0','#ffab70'];
    Object.entries(cx.by_model || {}).forEach(([k,v]) => {
      if ((v.cost||0) > 0) modelCosts.push({ label: k, cost: v.cost });
    });
    Object.entries(gm.by_model || {}).forEach(([k,v]) => {
      if ((v.cost||0) > 0) modelCosts.push({ label: 'gemini:'+k.replace('gemini-',''), cost: v.cost });
    });
    modelCosts.sort((a,b)=>b.cost-a.cost);
    chLlmModels.data.labels = modelCosts.map(m => m.label);
    chLlmModels.data.datasets[0].data = modelCosts.map(m => m.cost);
    chLlmModels.data.datasets[0].backgroundColor = modelCosts.map((_,i) => colors[i % colors.length]);
    chLlmModels.update('none');

    // 4) 누적 토큰 (보조)
    chLlmTotal.data.datasets[0].data = [
      ccTotal || 0,
      (cx.total||{}).tokens || 0,
      (gm.total||{}).tokens || 0,
      (ol.total||{}).tokens || (ol.total||{}).calls || 0
    ];
    chLlmTotal.update('none');

    // 5) 세션/호출 도넛
    chLlmSessions.data.labels = [
      `Claude (${(cc.total||{}).turns?.toLocaleString() || 0}턴)`,
      `Codex (${(cx.total||{}).sessions?.toLocaleString() || 0}세션)`,
      `Gemini (${(gm.total||{}).calls?.toLocaleString() || 0}호출)`,
      `Ollama (${(ol.total||{}).calls?.toLocaleString() || 0}호출)`
    ];
    chLlmSessions.data.datasets[0].data = [
      (cc.total||{}).turns || 0,
      (cx.total||{}).sessions || 0,
      (gm.total||{}).calls || 0,
      (ol.total||{}).calls || 0
    ];
    chLlmSessions.update('none');

    // 6) 프로젝트별 TOP 15
    const projects = Object.entries(cc.by_project || {})
      .sort((a,b) => (b[1].cost||0) - (a[1].cost||0))
      .slice(0, 15);
    chProjects.data.labels = projects.map(([name]) => name);
    chProjects.data.datasets[0].data = projects.map(([_,p]) => p.cost || 0);
    chProjects.update('none');

    document.getElementById('llm-updated').textContent =
      '업데이트: ' + new Date().toLocaleTimeString('ko-KR') +
      ' · 누적 비용 ' + fmtCost(totalCost) +
      ' (Claude ' + fmtCost(ccCost) + ' / Codex ' + fmtCost(cxCost) + ' / Gemini ' + fmtCost(gmCost) + ')';
  }).catch(e => console.error('loadUsage', e));
}

loadUsage();
setInterval(loadUsage, 60000);  // 1분마다 갱신 (호출 비용 ~1초)
</script>
</body>
</html>
"""


def get_today_file():
    return TRACE_DIR / f"{datetime.now().strftime('%Y-%m-%d')}.jsonl"


def tail_lines(n=200):
    """최근 N개 라인 반환"""
    f = get_today_file()
    if not f.exists():
        return []
    with f.open() as fh:
        lines = fh.readlines()
    out = []
    for line in lines[-n:]:
        try:
            out.append(json.loads(line))
        except Exception:
            pass
    return out


class StreamServer(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args, **kwargs):
        pass  # 콘솔 노이즈 제거

    def handle_one_request(self):
        # 브라우저가 SSE 연결을 끊을 때 readline에서 ConnectionResetError 발생
        # → socketserver가 traceback 전체를 stderr에 찍음. 흡수해서 로그 깔끔하게.
        try:
            super().handle_one_request()
        except (ConnectionResetError, BrokenPipeError):
            self.close_connection = True
        except OSError as e:
            if e.errno in (54, 32):  # ECONNRESET, EPIPE
                self.close_connection = True
            else:
                raise

    def do_GET(self):
        if self.path == "/":
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.end_headers()
            self.wfile.write(HTML.encode("utf-8"))
            return
        if self.path.startswith("/backfill"):
            from urllib.parse import urlparse, parse_qs
            qs = parse_qs(urlparse(self.path).query)
            n = int(qs.get("n", ["200"])[0])
            data = tail_lines(n)
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(data).encode("utf-8"))
            return
        if self.path.startswith("/usage"):
            # 캐시: 60초 TTL — 첫 호출만 무겁고 이후는 즉답
            now = time.time()
            cached = _usage_cache.get('payload')
            cached_at = _usage_cache.get('at', 0)
            if cached and (now - cached_at) < 60:
                payload = cached
            else:
                import subprocess
                try:
                    result = subprocess.run(
                        ["/usr/bin/python3", os.path.expanduser("~/.claude/scripts/llm-usage.py"), "--json"],
                        capture_output=True, text=True, timeout=30
                    )
                    if result.returncode == 0:
                        payload = result.stdout
                        _usage_cache['payload'] = payload
                        _usage_cache['at'] = now
                    else:
                        payload = json.dumps({"error": result.stderr or "non-zero exit"})
                except subprocess.TimeoutExpired:
                    # 타임아웃 시 직전 캐시라도 반환
                    payload = cached or json.dumps({"error": "timeout — Claude projects 스캔 중. 잠시 후 새로고침."})
                except Exception as e:
                    payload = json.dumps({"error": str(e)})
            self.send_response(200)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Cache-Control", "max-age=60")
            self.end_headers()
            self.wfile.write(payload.encode("utf-8"))
            return
        if self.path == "/stream":
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.send_header("Cache-Control", "no-cache")
            self.send_header("Connection", "keep-alive")
            self.end_headers()
            f = get_today_file()
            # 파일 끝부터 시작 — 백필은 /backfill로
            offset = f.stat().st_size if f.exists() else 0
            try:
                while True:
                    cur_file = get_today_file()
                    if not cur_file.exists():
                        time.sleep(0.5)
                        continue
                    if cur_file != f:
                        # 자정 넘어 새 파일
                        f = cur_file
                        offset = 0
                    size = cur_file.stat().st_size
                    if size > offset:
                        with cur_file.open() as fh:
                            fh.seek(offset)
                            for line in fh:
                                line = line.strip()
                                if not line:
                                    continue
                                try:
                                    json.loads(line)  # 검증
                                    self.wfile.write(f"data: {line}\n\n".encode("utf-8"))
                                    self.wfile.flush()
                                except Exception:
                                    pass
                            offset = fh.tell()
                    else:
                        # heartbeat
                        self.wfile.write(b": ping\n\n")
                        self.wfile.flush()
                        time.sleep(0.5)
            except (BrokenPipeError, ConnectionResetError):
                return
            return
        self.send_error(404)


def main():
    if not TRACE_DIR.exists():
        TRACE_DIR.mkdir(parents=True, exist_ok=True)
    print(f"📊 Hook Dashboard: http://{HOST}:{PORT}")
    print(f"📁 데이터: {TRACE_DIR}")
    print("Ctrl+C 종료\n")

    # 브라우저 자동 열기 (옵션)
    if "--no-browser" not in os.sys.argv:
        threading.Timer(0.8, lambda: webbrowser.open(f"http://{HOST}:{PORT}")).start()

    # /usage 캐시 워머 시작 (별도 데몬 스레드)
    threading.Thread(target=_warm_usage_cache, daemon=True).start()
    # 30일 이상 된 로그 자동 회전
    threading.Thread(target=_rotate_old_logs, daemon=True).start()

    # SO_REUSEADDR을 bind 전에 설정 (재시작 시 TIME_WAIT 회피)
    socketserver.ThreadingTCPServer.allow_reuse_address = True
    with socketserver.ThreadingTCPServer((HOST, PORT), StreamServer) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\n종료")


if __name__ == "__main__":
    main()
