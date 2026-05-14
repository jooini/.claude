#!/usr/bin/env python3
"""
finops-dashboard — LLM 비용 HTML 대시보드 (KRW + USD)

llm-usage.py --json 출력을 받아 HTML 단일 파일로 렌더링.

사용:
  python3 ~/.claude/scripts/finops-dashboard.py            # HTML stdout
  python3 ~/.claude/scripts/finops-dashboard.py --out path.html
  python3 ~/.claude/scripts/finops-dashboard.py --days 30 --open
"""
import argparse
import json
import os
import subprocess
import sys
from datetime import datetime

USD_TO_KRW = 1380  # 2026-05 환율 기준. 변동 시 갱신.

LLM_USAGE = os.path.expanduser("~/.claude/scripts/llm-usage.py")
MISPREDICT = os.path.expanduser("~/.claude/scripts/mispredict-cost.py")


def load_data(days):
    out = subprocess.check_output(
        [sys.executable, LLM_USAGE, "--json", "--days", str(days)],
        text=True,
    )
    return json.loads(out)


def load_mispredict(days):
    try:
        out = subprocess.check_output(
            [sys.executable, MISPREDICT, "--json", "--days", str(days)],
            text=True, stderr=subprocess.DEVNULL,
        )
        return json.loads(out)
    except Exception:
        return {"total_incidents": 0, "total_wasted_usd": 0, "total_wasted_krw": 0, "daily": {}}


def krw(usd):
    return f"₩{int(usd * USD_TO_KRW):,}"


def fmt_usd(v):
    return f"${v:,.2f}"


def fmt_tokens(n):
    if n >= 1_000_000_000:
        return f"{n/1_000_000_000:.2f}B"
    if n >= 1_000_000:
        return f"{n/1_000_000:.2f}M"
    if n >= 1_000:
        return f"{n/1_000:.1f}K"
    return str(n)


def render(data, days):
    cc = data.get("claude_code", {})
    cx = data.get("codex", {})
    gm = data.get("gemini", {})
    ol = data.get("ollama", {})

    cc_total = cc.get("total", {})
    cx_total = cx.get("total", {})

    cc_cost = cc_total.get("cost", 0.0)
    cx_cost = cx_total.get("cost", 0.0)
    gm_cost = gm.get("cost", 0.0)
    grand = cc_cost + cx_cost + gm_cost

    # 추정 정정 낭비 비용
    mp = data.get("mispredict", {})
    mp_cost = mp.get("total_wasted_usd", 0)
    mp_count = mp.get("total_incidents", 0)
    waste_pct = (mp_cost / grand * 100) if grand else 0

    daily_rows = []
    cc_daily = cc.get("daily", {}) or {}
    cx_daily = cx.get("daily", {}) or {}
    gm_daily = gm.get("daily", {}) or {}
    all_days = sorted(set(cc_daily) | set(cx_daily) | set(gm_daily), reverse=True)[:days]
    for day in all_days:
        c = cc_daily.get(day, {})
        x = cx_daily.get(day, {})
        g = gm_daily.get(day, {})
        c_cost = c.get("cost", 0.0)
        x_cost = x.get("cost", 0.0)
        g_cost = g.get("cost", 0.0)
        total = c_cost + x_cost + g_cost
        daily_rows.append({
            "day": day,
            "claude_turns": c.get("turns", 0),
            "claude_cost": c_cost,
            "codex_sessions": x.get("sessions", 0),
            "codex_cost": x_cost,
            "gemini_calls": g.get("calls", 0),
            "gemini_cost": g_cost,
            "total": total,
        })

    # 프로젝트 TOP 10 (claude_code by_project)
    proj = cc.get("by_project", {}) or {}
    proj_top = sorted(proj.items(), key=lambda kv: kv[1].get("cost", 0), reverse=True)[:10]

    # 모델별
    cc_models = cc.get("by_model", {}) or {}
    cx_models = cx.get("by_model", {}) or {}
    gm_models = gm.get("by_model", {}) or {}

    daily_chart_labels = [r["day"] for r in reversed(daily_rows)]
    daily_chart_total = [r["total"] for r in reversed(daily_rows)]
    daily_chart_claude = [r["claude_cost"] for r in reversed(daily_rows)]
    daily_chart_codex = [r["codex_cost"] for r in reversed(daily_rows)]
    daily_chart_gemini = [r["gemini_cost"] for r in reversed(daily_rows)]

    generated = data.get("generated_at", datetime.now().isoformat())

    daily_table_rows = "\n".join(
        f"<tr><td>{r['day']}</td>"
        f"<td class='num'>{r['claude_turns']:,}</td>"
        f"<td class='num cost'>{fmt_usd(r['claude_cost'])}</td>"
        f"<td class='num krw'>{krw(r['claude_cost'])}</td>"
        f"<td class='num'>{r['codex_sessions']}</td>"
        f"<td class='num cost'>{fmt_usd(r['codex_cost'])}</td>"
        f"<td class='num'>{r['gemini_calls']}</td>"
        f"<td class='num cost'>{fmt_usd(r['gemini_cost'])}</td>"
        f"<td class='num total'>{fmt_usd(r['total'])}</td>"
        f"<td class='num krw total'>{krw(r['total'])}</td></tr>"
        for r in daily_rows
    )

    # 추정 정정 사건 TOP
    mp_top = mp.get("top_incidents", [])[:10]
    mp_daily = mp.get("daily", {})
    mp_rows_html = "\n".join(
        f"<tr><td class='num cost' style='color:#f85149;'>{fmt_usd(inc.get('wasted_cost',0))}</td>"
        f"<td class='num krw'>{krw(inc.get('wasted_cost',0))}</td>"
        f"<td>{inc.get('timestamp','')[:16]}</td>"
        f"<td>{(inc.get('correction_text','') or '')[:80]}</td></tr>"
        for inc in mp_top
    ) or "<tr><td colspan='4'>데이터 없음</td></tr>"

    proj_rows = "\n".join(
        f"<tr><td>{name}</td>"
        f"<td class='num'>{fmt_tokens(info.get('tokens', 0))}</td>"
        f"<td class='num'>{info.get('turns', 0):,}</td>"
        f"<td class='num cost'>{fmt_usd(info.get('cost', 0))}</td>"
        f"<td class='num krw'>{krw(info.get('cost', 0))}</td></tr>"
        for name, info in proj_top
    )

    def models_table(models, key_token="tokens", key_cost="cost", session_key="sessions"):
        rows = sorted(models.items(), key=lambda kv: kv[1].get(key_cost, 0), reverse=True)
        return "\n".join(
            f"<tr><td>{name}</td>"
            f"<td class='num'>{info.get(session_key, info.get('calls', info.get('turns', 0))):,}</td>"
            f"<td class='num'>{fmt_tokens(info.get(key_token, 0))}</td>"
            f"<td class='num cost'>{fmt_usd(info.get(key_cost, 0))}</td>"
            f"<td class='num krw'>{krw(info.get(key_cost, 0))}</td></tr>"
            for name, info in rows if info.get(key_cost, 0) > 0
        )

    cc_models_html = models_table(cc_models, session_key="turns")
    cx_models_html = models_table(cx_models)
    gm_models_html = models_table(gm_models, session_key="calls")

    return f"""<!doctype html>
<html lang="ko"><head>
<meta charset="utf-8">
<title>LLM FinOps Dashboard — {days}일</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<style>
  body {{ font-family: -apple-system, 'Segoe UI', sans-serif; margin: 24px; background: #0f1419; color: #e6edf3; }}
  h1 {{ font-size: 24px; margin: 0 0 8px; }}
  .subtitle {{ color: #8b949e; margin-bottom: 24px; font-size: 13px; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(280px, 1fr)); gap: 16px; margin-bottom: 24px; }}
  .card {{ background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 16px; }}
  .card h3 {{ margin: 0 0 8px; font-size: 13px; color: #8b949e; text-transform: uppercase; letter-spacing: 0.5px; }}
  .big {{ font-size: 28px; font-weight: 700; color: #58a6ff; }}
  .big.krw {{ color: #f0883e; font-size: 24px; }}
  .sub {{ color: #8b949e; font-size: 12px; margin-top: 4px; }}
  table {{ width: 100%; border-collapse: collapse; font-size: 13px; }}
  th, td {{ padding: 6px 10px; text-align: left; border-bottom: 1px solid #30363d; }}
  th {{ background: #161b22; color: #8b949e; font-weight: 600; font-size: 11px; text-transform: uppercase; }}
  td.num {{ text-align: right; font-variant-numeric: tabular-nums; }}
  td.cost {{ color: #58a6ff; }}
  td.krw {{ color: #f0883e; }}
  td.total {{ font-weight: 700; }}
  section {{ background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 16px; margin-bottom: 16px; }}
  section h2 {{ margin: 0 0 12px; font-size: 15px; color: #e6edf3; }}
  .chart-wrap {{ height: 280px; }}
  .badges {{ display: flex; gap: 8px; flex-wrap: wrap; margin-bottom: 16px; }}
  .badge {{ background: #21262d; color: #8b949e; padding: 4px 10px; border-radius: 12px; font-size: 11px; }}
  .badge.warn {{ background: #3d2c00; color: #f0883e; }}
</style></head><body>

<h1>💰 LLM FinOps Dashboard</h1>
<div class="subtitle">최근 {days}일 · 생성: {generated} · 환율 ₩{USD_TO_KRW:,}/$</div>

<div class="badges">
  <div class="badge">Claude turns: {cc_total.get('turns', 0):,}</div>
  <div class="badge">Codex sessions: {cx_total.get('sessions', 0):,}</div>
  <div class="badge">Gemini calls: {gm.get('calls', 0):,}</div>
  <div class="badge {'warn' if ol.get('calls', 0) <= 1 else ''}">Ollama calls: {ol.get('calls', 0)}</div>
</div>

<div class="grid">
  <div class="card">
    <h3>총 비용 (누적)</h3>
    <div class="big">{fmt_usd(grand)}</div>
    <div class="big krw">{krw(grand)}</div>
    <div class="sub">Claude + Codex + Gemini 합산</div>
  </div>
  <div class="card">
    <h3>Claude Code</h3>
    <div class="big">{fmt_usd(cc_cost)}</div>
    <div class="big krw">{krw(cc_cost)}</div>
    <div class="sub">{fmt_tokens(cc_total.get('in', 0) + cc_total.get('out', 0) + cc_total.get('cache_r', 0))} tokens</div>
  </div>
  <div class="card">
    <h3>Codex / GPT</h3>
    <div class="big">{fmt_usd(cx_cost)}</div>
    <div class="big krw">{krw(cx_cost)}</div>
    <div class="sub">{fmt_tokens(cx_total.get('tokens', 0))} tokens</div>
  </div>
  <div class="card">
    <h3>Gemini</h3>
    <div class="big">{fmt_usd(gm_cost)}</div>
    <div class="big krw">{krw(gm_cost)}</div>
    <div class="sub">{fmt_tokens(gm.get('tokens', 0))} tokens</div>
  </div>
  <div class="card" style="border-color:#f85149;">
    <h3 style="color:#f85149;">💸 추정 정정 낭비</h3>
    <div class="big" style="color:#f85149;">{fmt_usd(mp_cost)}</div>
    <div class="big krw">{krw(mp_cost)}</div>
    <div class="sub">{mp_count}건 · 전체의 {waste_pct:.1f}%</div>
  </div>
</div>

<section>
  <h2>📊 일별 추이 (USD)</h2>
  <div class="chart-wrap"><canvas id="dailyChart"></canvas></div>
</section>

<section>
  <h2>📅 일별 상세</h2>
  <table>
    <thead><tr>
      <th>날짜</th>
      <th class="num">Claude턴</th><th class="num">$</th><th class="num">₩</th>
      <th class="num">Codex세션</th><th class="num">$</th>
      <th class="num">Gemini</th><th class="num">$</th>
      <th class="num">합계 $</th><th class="num">합계 ₩</th>
    </tr></thead>
    <tbody>{daily_table_rows}</tbody>
  </table>
</section>

<section style="border-color:#f85149;">
  <h2 style="color:#f85149;">💸 추정 정정 낭비 사건 TOP 10</h2>
  <table>
    <thead><tr><th class="num">USD</th><th class="num">KRW</th><th>일시</th><th>사용자 정정 발화</th></tr></thead>
    <tbody>{mp_rows_html}</tbody>
  </table>
  <div class="sub" style="margin-top:8px;">정의: 사용자가 '아니/틀렸/잘못/추정' 발화 직전의 assistant 응답 토큰 비용 합산</div>
</section>

<section>
  <h2>🏢 프로젝트 TOP 10 (Claude Code)</h2>
  <table>
    <thead><tr><th>프로젝트</th><th class="num">토큰</th><th class="num">턴</th><th class="num">USD</th><th class="num">KRW</th></tr></thead>
    <tbody>{proj_rows}</tbody>
  </table>
</section>

<section>
  <h2>🤖 모델별 — Claude</h2>
  <table>
    <thead><tr><th>모델</th><th class="num">턴</th><th class="num">토큰</th><th class="num">USD</th><th class="num">KRW</th></tr></thead>
    <tbody>{cc_models_html}</tbody>
  </table>
</section>

<section>
  <h2>🤖 모델별 — Codex</h2>
  <table>
    <thead><tr><th>모델</th><th class="num">세션</th><th class="num">토큰</th><th class="num">USD</th><th class="num">KRW</th></tr></thead>
    <tbody>{cx_models_html}</tbody>
  </table>
</section>

<section>
  <h2>🤖 모델별 — Gemini</h2>
  <table>
    <thead><tr><th>모델</th><th class="num">호출</th><th class="num">토큰</th><th class="num">USD</th><th class="num">KRW</th></tr></thead>
    <tbody>{gm_models_html}</tbody>
  </table>
</section>

<script>
new Chart(document.getElementById('dailyChart'), {{
  type: 'line',
  data: {{
    labels: {json.dumps(daily_chart_labels)},
    datasets: [
      {{ label: 'Total', data: {json.dumps(daily_chart_total)}, borderColor: '#58a6ff', backgroundColor: 'rgba(88,166,255,0.1)', fill: true, tension: 0.3 }},
      {{ label: 'Claude', data: {json.dumps(daily_chart_claude)}, borderColor: '#f0883e', tension: 0.3 }},
      {{ label: 'Codex', data: {json.dumps(daily_chart_codex)}, borderColor: '#7ee787', tension: 0.3 }},
      {{ label: 'Gemini', data: {json.dumps(daily_chart_gemini)}, borderColor: '#d2a8ff', tension: 0.3 }}
    ]
  }},
  options: {{
    responsive: true, maintainAspectRatio: false,
    plugins: {{ legend: {{ labels: {{ color: '#e6edf3' }} }} }},
    scales: {{
      x: {{ ticks: {{ color: '#8b949e' }}, grid: {{ color: '#30363d' }} }},
      y: {{ ticks: {{ color: '#8b949e', callback: v => '$' + v }}, grid: {{ color: '#30363d' }} }}
    }}
  }}
}});
</script>
</body></html>"""


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--days", type=int, default=14)
    p.add_argument("--out", default=None, help="HTML 출력 파일 경로 (기본: stdout)")
    p.add_argument("--open", action="store_true", help="생성 후 브라우저로 열기")
    args = p.parse_args()

    data = load_data(args.days)
    data["mispredict"] = load_mispredict(args.days)
    html = render(data, args.days)

    if args.out:
        out_path = os.path.expanduser(args.out)
        os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
        with open(out_path, "w") as f:
            f.write(html)
        print(f"✅ {out_path}")
        if args.open:
            subprocess.run(["open", out_path], check=False)
    else:
        sys.stdout.write(html)


if __name__ == "__main__":
    main()
