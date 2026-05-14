#!/usr/bin/env python3
"""
morning-dashboard — 통합 아침 대시보드

5개 패널을 단일 HTML로:
1. FinOps (비용 + KRW + 추정 정정 낭비)
2. Project Vitality (109개 프로젝트 활기 점수)
3. Backlog (12개 프로젝트 백로그 카운트)
4. Active 잔존 (docs/active/ 누적 파일)
5. QQ (사용자 발화 품질 추이)

사용:
  python3 ~/.claude/scripts/morning-dashboard.py --out ~/.claude/cache/morning.html --open
"""
import argparse
import glob
import json
import os
import subprocess
import sys
from datetime import datetime, timedelta
from pathlib import Path

USD_TO_KRW = 1380
WORKSPACE = Path.home() / "Workspace"


def krw(usd):
    return f"₩{int(usd * USD_TO_KRW):,}"


def fmt_usd(v):
    return f"${v:,.2f}"


def collect_finops(days):
    try:
        out = subprocess.check_output(
            [sys.executable, str(Path.home() / ".claude/scripts/llm-usage.py"), "--json", "--days", str(days)],
            text=True, stderr=subprocess.DEVNULL,
        )
        usage = json.loads(out)
    except Exception:
        usage = {}
    try:
        out = subprocess.check_output(
            [sys.executable, str(Path.home() / ".claude/scripts/mispredict-cost.py"), "--json", "--days", str(days)],
            text=True, stderr=subprocess.DEVNULL,
        )
        mp = json.loads(out)
    except Exception:
        mp = {}

    cc = usage.get("claude_code", {}).get("total", {}).get("cost", 0)
    cx = usage.get("codex", {}).get("total", {}).get("cost", 0)
    gm = usage.get("gemini", {}).get("cost", 0)
    return {
        "total_usd": cc + cx + gm,
        "claude": cc, "codex": cx, "gemini": gm,
        "mispredict_usd": mp.get("total_wasted_usd", 0),
        "mispredict_count": mp.get("total_incidents", 0),
        "mispredict_top": mp.get("top_incidents", [])[:5],
    }


def collect_vitality():
    """간단한 vitality — 14일 git activity"""
    cutoff = datetime.now() - timedelta(days=14)
    results = []
    for path in WORKSPACE.iterdir():
        if not path.is_dir() or not (path / ".git").exists():
            continue
        try:
            out = subprocess.check_output(
                ["git", "-C", str(path), "log", "--since", cutoff.strftime("%Y-%m-%d"),
                 "--pretty=format:%H", "--all"],
                text=True, stderr=subprocess.DEVNULL, timeout=5,
            )
            commits = len([l for l in out.split("\n") if l.strip()])
        except Exception:
            commits = 0
        if commits > 0:
            results.append({"name": path.name, "commits": commits})
    results.sort(key=lambda r: r["commits"], reverse=True)
    return results[:15]


def collect_backlog():
    items = []
    for bpath in glob.glob(str(WORKSPACE / "*/docs/backlog.md")):
        proj = Path(bpath).parent.parent.name
        try:
            content = Path(bpath).read_text()
        except Exception:
            continue
        # 간단 카운트: H/M/L 셀
        lines = content.splitlines()
        h = sum(1 for l in lines if "| H |" in l and "backlog" in l.lower())
        m = sum(1 for l in lines if "| M |" in l and "backlog" in l.lower())
        active = sum(1 for l in lines if "active" in l.lower() and "|" in l)
        if h + m + active > 0:
            items.append({"project": proj, "high": h, "med": m, "active": active})
    items.sort(key=lambda x: (x["active"], x["high"]), reverse=True)
    return items[:10]


def collect_active_residue():
    """docs/active/ 가 비어있지 않은 프로젝트 + 가장 오래된 파일"""
    items = []
    cutoff = datetime.now() - timedelta(days=7)
    for apath in glob.glob(str(WORKSPACE / "*/docs/active")):
        proj = Path(apath).parent.parent.name
        files = [f for f in Path(apath).iterdir() if f.is_file() and f.suffix == ".md"]
        if not files:
            continue
        oldest = min(files, key=lambda f: f.stat().st_mtime)
        oldest_age = int((datetime.now().timestamp() - oldest.stat().st_mtime) / 86400)
        items.append({
            "project": proj,
            "count": len(files),
            "oldest_age_days": oldest_age,
            "oldest_file": oldest.name,
        })
    items.sort(key=lambda x: (x["oldest_age_days"], x["count"]), reverse=True)
    return items[:10]


def collect_qq():
    qq_path = Path.home() / ".claude/cache/question-quality.json"
    if not qq_path.exists():
        return None
    try:
        return json.loads(qq_path.read_text())
    except Exception:
        return None


def render(data, days):
    fo = data["finops"]
    waste_pct = (fo["mispredict_usd"] / fo["total_usd"] * 100) if fo["total_usd"] else 0

    vit_rows = "\n".join(
        f"<tr><td>{v['name']}</td><td class='num'>{v['commits']}</td></tr>"
        for v in data["vitality"]
    ) or "<tr><td colspan='2'>활동 없음</td></tr>"

    bl_rows = "\n".join(
        f"<tr><td>{b['project']}</td><td class='num warn'>{b['high']}</td>"
        f"<td class='num'>{b['med']}</td><td class='num'>{b['active']}</td></tr>"
        for b in data["backlog"]
    ) or "<tr><td colspan='4'>데이터 없음</td></tr>"

    ar_rows = "\n".join(
        f"<tr><td>{a['project']}</td><td class='num'>{a['count']}</td>"
        f"<td class='num {'warn' if a['oldest_age_days']>14 else ''}'>{a['oldest_age_days']}일</td>"
        f"<td><code>{a['oldest_file'][:50]}</code></td></tr>"
        for a in data["active_residue"]
    ) or "<tr><td colspan='4'>비어있음</td></tr>"

    mp_rows = "\n".join(
        f"<tr><td class='num cost'>{fmt_usd(inc.get('wasted_cost',0))}</td>"
        f"<td>{inc.get('timestamp','')[:16]}</td>"
        f"<td>{(inc.get('correction_text','') or '')[:70]}</td></tr>"
        for inc in fo["mispredict_top"]
    ) or "<tr><td colspan='3'>없음</td></tr>"

    qq = data["qq"]
    qq_section = ""
    if qq:
        rules = qq.get("rules", {})
        qq_section = f"""
<section>
  <h2>💬 QQ — 사용자 발화 품질 ({qq.get('real_user_msgs', 0):,} 메시지 분석)</h2>
  <div class="grid">
    <div class="card"><h3>전체 BAD rate</h3><div class="big">{qq.get('bad_rate',0)*100:.1f}%</div><div class="sub">정정 유발 발화 비율</div></div>
    <div class="card"><h3>매우 짧음 (&lt;5자)</h3><div class="big warn">{rules.get('very_short_bad_rate',0)*100:.1f}%</div></div>
    <div class="card"><h3>모호 키워드</h3><div class="big warn">{rules.get('ambiguous_bad_rate',0)*100:.1f}%</div></div>
    <div class="card"><h3>지시대명사</h3><div class="big warn">{rules.get('deixis_bad_rate',0)*100:.1f}%</div></div>
    <div class="card"><h3>구체성 0</h3><div class="big warn">{rules.get('no_concrete_bad_rate',0)*100:.1f}%</div></div>
  </div>
</section>
"""

    return f"""<!doctype html>
<html lang="ko"><head>
<meta charset="utf-8">
<title>🌅 Morning Dashboard — {datetime.now():%Y-%m-%d}</title>
<style>
  body {{ font-family: -apple-system, 'Segoe UI', sans-serif; margin: 24px; background: #0f1419; color: #e6edf3; max-width: 1400px; }}
  h1 {{ font-size: 28px; margin: 0 0 8px; }}
  .subtitle {{ color: #8b949e; margin-bottom: 24px; font-size: 14px; }}
  .grid {{ display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 12px; margin-bottom: 16px; }}
  .card {{ background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 12px 16px; }}
  .card h3 {{ margin: 0 0 6px; font-size: 11px; color: #8b949e; text-transform: uppercase; letter-spacing: 0.5px; }}
  .big {{ font-size: 22px; font-weight: 700; color: #58a6ff; }}
  .big.warn {{ color: #f0883e; }}
  .big.danger {{ color: #f85149; }}
  .sub {{ color: #8b949e; font-size: 11px; margin-top: 2px; }}
  table {{ width: 100%; border-collapse: collapse; font-size: 13px; }}
  th, td {{ padding: 5px 10px; text-align: left; border-bottom: 1px solid #30363d; }}
  th {{ background: #161b22; color: #8b949e; font-weight: 600; font-size: 11px; }}
  td.num {{ text-align: right; font-variant-numeric: tabular-nums; }}
  td.warn {{ color: #f0883e; }}
  td.cost {{ color: #f85149; font-weight: 700; }}
  section {{ background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 16px; margin-bottom: 16px; }}
  section h2 {{ margin: 0 0 12px; font-size: 16px; }}
  .two-col {{ display: grid; grid-template-columns: 1fr 1fr; gap: 16px; }}
  @media (max-width: 900px) {{ .two-col {{ grid-template-columns: 1fr; }} }}
  code {{ background: #0d1117; padding: 1px 4px; border-radius: 3px; font-size: 11px; }}
</style></head><body>

<h1>🌅 Morning Dashboard</h1>
<div class="subtitle">{datetime.now():%Y-%m-%d %H:%M} · 최근 {days}일 · ₩{USD_TO_KRW:,}/$</div>

<section>
  <h2>💰 FinOps</h2>
  <div class="grid">
    <div class="card"><h3>총 비용</h3><div class="big">{fmt_usd(fo['total_usd'])}</div><div class="sub">{krw(fo['total_usd'])}</div></div>
    <div class="card"><h3>Claude</h3><div class="big">{fmt_usd(fo['claude'])}</div></div>
    <div class="card"><h3>Codex</h3><div class="big">{fmt_usd(fo['codex'])}</div></div>
    <div class="card"><h3>Gemini</h3><div class="big">{fmt_usd(fo['gemini'])}</div></div>
    <div class="card"><h3>💸 추정 정정 낭비</h3><div class="big danger">{fmt_usd(fo['mispredict_usd'])}</div><div class="sub">{krw(fo['mispredict_usd'])} · {fo['mispredict_count']}건 · {waste_pct:.1f}%</div></div>
  </div>
</section>

<div class="two-col">
  <section>
    <h2>🟢 Vitality TOP 15 (14일 commit)</h2>
    <table><thead><tr><th>프로젝트</th><th class="num">커밋</th></tr></thead><tbody>{vit_rows}</tbody></table>
  </section>

  <section>
    <h2>📋 Backlog 잔존</h2>
    <table><thead><tr><th>프로젝트</th><th class="num">High</th><th class="num">Med</th><th class="num">Active</th></tr></thead><tbody>{bl_rows}</tbody></table>
  </section>
</div>

<section>
  <h2>📁 Active 잔존 (docs/active/)</h2>
  <table><thead><tr><th>프로젝트</th><th class="num">파일수</th><th class="num">최오래</th><th>최오래 파일</th></tr></thead><tbody>{ar_rows}</tbody></table>
</section>

<section>
  <h2>💸 추정 정정 낭비 사건 TOP 5</h2>
  <table><thead><tr><th class="num">USD</th><th>일시</th><th>정정 발화</th></tr></thead><tbody>{mp_rows}</tbody></table>
  <div class="sub" style="margin-top:8px;">사용자가 '아니/틀렸/잘못/추정' 발화 직전 assistant 토큰 비용 합산</div>
</section>

{qq_section}

</body></html>"""


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--days", type=int, default=14)
    p.add_argument("--out", default="~/.claude/cache/morning.html")
    p.add_argument("--open", action="store_true")
    args = p.parse_args()

    print("📊 데이터 수집 중...", file=sys.stderr)
    data = {
        "finops": collect_finops(args.days),
        "vitality": collect_vitality(),
        "backlog": collect_backlog(),
        "active_residue": collect_active_residue(),
        "qq": collect_qq(),
    }

    html = render(data, args.days)
    out_path = os.path.expanduser(args.out)
    os.makedirs(os.path.dirname(out_path) or ".", exist_ok=True)
    with open(out_path, "w") as f:
        f.write(html)
    print(f"✅ {out_path}", file=sys.stderr)
    if args.open:
        subprocess.run(["open", out_path], check=False)

    # 콘솔 요약
    fo = data["finops"]
    print(f"\n💰 비용 ${fo['total_usd']:.2f} ({krw(fo['total_usd'])})")
    print(f"💸 정정 낭비 ${fo['mispredict_usd']:.2f} ({fo['mispredict_count']}건)")
    print(f"🟢 활동 프로젝트 {len(data['vitality'])}개")
    print(f"📁 active 잔존 {len(data['active_residue'])}개 프로젝트")


if __name__ == "__main__":
    main()
