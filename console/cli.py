"""workspace console CLI."""
from __future__ import annotations

from pathlib import Path
import json

import typer
from rich.console import Console
from rich.table import Table

from console.adapters.git import scan_repos
from console.vitality import score

app = typer.Typer(help="Workspace Console — 1인 개발자 관제탑")
console = Console()


@app.command()
def sweep(
    root: Path = typer.Option(Path.home() / "Workspace", help="스캔 root"),
    out: Path | None = typer.Option(None, help="JSON 리포트 출력 경로"),
):
    """모든 repo를 스캔하고 vitality 점수 계산. 리포트 출력."""
    results = []
    for repo in scan_repos(root, max_depth=2):
        s = score(repo)
        results.append({
            "path": str(repo.path),
            "value": s.value,
            "label": s.label,
            "dirty_count": repo.dirty_count,
            "last_commit_at": repo.last_commit_at.isoformat() if repo.last_commit_at else None,
            "reason": s.reason,
        })

    results.sort(key=lambda r: r["value"])

    table = Table(title=f"Vitality Sweep — {len(results)} repos")
    table.add_column("Score", justify="right")
    table.add_column("Label")
    table.add_column("Dirty", justify="right")
    table.add_column("Repo")
    for r in results:
        table.add_row(str(r["value"]), r["label"], str(r["dirty_count"]), Path(r["path"]).name)
    console.print(table)

    summary = {
        "total": len(results),
        "by_label": {},
    }
    for r in results:
        summary["by_label"][r["label"]] = summary["by_label"].get(r["label"], 0) + 1
    console.print(summary)

    if out:
        out.write_text(json.dumps({"summary": summary, "repos": results}, indent=2))
        console.print(f"[green]리포트 저장:[/green] {out}")


@app.command()
def report(
    sweep_json: Path = typer.Argument(..., help="sweep 명령으로 생성한 JSON"),
    out: Path = typer.Argument(..., help="출력 마크다운 경로"),
):
    """sweep 결과를 사용자 검토용 마크다운으로 변환."""
    data = json.loads(sweep_json.read_text())
    lines = [
        "# Vitality Sweep — 사용자 검토",
        f"\n**총 {data['summary']['total']} repos** | 라벨별: {data['summary']['by_label']}\n",
        "## 아카이브 후보 (dead + empty)\n",
        "| Repo | Score | 미커밋 | 마지막 커밋 | 액션 |",
        "|------|-------|--------|------------|------|",
    ]
    for r in data["repos"]:
        if r["label"] in ("dead", "empty"):
            lines.append(
                f"| {Path(r['path']).name} | {r['value']} | {r['dirty_count']} | "
                f"{r['last_commit_at'] or 'N/A'} | [ ] keep [ ] archive |"
            )

    lines.extend([
        "\n## 좀비 (정리 필요 — 미커밋 많고 오래됨)\n",
        "| Repo | Score | 미커밋 | 마지막 커밋 |",
        "|------|-------|--------|------------|",
    ])
    for r in data["repos"]:
        if r["label"] == "zombie":
            lines.append(
                f"| {Path(r['path']).name} | {r['value']} | {r['dirty_count']} | "
                f"{r['last_commit_at']} |"
            )

    out.write_text("\n".join(lines))
    console.print(f"[green]리포트:[/green] {out}")


@app.command()
def archive(
    review_md: Path = typer.Argument(..., help="vitality report 마크다운 (체크된 것만 archive)"),
    archive_dir: Path = typer.Option(Path.home() / "Workspace" / "_archive"),
    dry_run: bool = typer.Option(True, help="기본 dry-run. --no-dry-run 으로 실제 이동"),
):
    """사용자가 [x] archive 체크한 repo를 일괄 이동."""
    from console.archive import archive_repos

    text = review_md.read_text()
    targets: list[Path] = []
    for line in text.splitlines():
        if "[x] archive" in line.lower() and "|" in line:
            cells = [c.strip() for c in line.split("|")]
            if len(cells) < 2:
                continue
            name = cells[1]
            candidate = Path.home() / "Workspace" / name
            if candidate.exists():
                targets.append(candidate)

    console.print(f"[yellow]대상 {len(targets)} 개[/yellow]")
    for t in targets[:10]:
        console.print(f"  - {t.name}")
    if len(targets) > 10:
        console.print(f"  ... +{len(targets) - 10}")

    if dry_run:
        console.print("[cyan]dry-run. --no-dry-run 으로 실제 이동[/cyan]")
        return

    moved = archive_repos(targets, archive_dir)
    console.print(f"[green]이동 완료: {len(moved)}[/green]")


@app.command()
def triage(
    root: Path = typer.Option(Path.home() / "Workspace", help="스캔 root"),
    out: Path = typer.Option(..., help="마크다운 리포트 출력 경로"),
):
    """모든 repo의 미커밋 파일을 분류 → 마크다운 리포트."""
    from console.triage import classify, FileCategory
    from collections import defaultdict
    import subprocess

    by_category: dict[FileCategory, list[tuple[str, str, str]]] = defaultdict(list)

    for repo in scan_repos(root, max_depth=2):
        if repo.dirty_count == 0:
            continue
        try:
            result = subprocess.run(
                ["git", "status", "--porcelain"],
                cwd=repo.path, capture_output=True, text=True, timeout=5,
            )
        except subprocess.TimeoutExpired:
            continue
        for line in result.stdout.splitlines():
            if not line.strip():
                continue
            status_code = line[:2].strip()
            file_path = line[3:].strip()
            cat = classify(file_path, status_code)
            by_category[cat].append((repo.path.name, file_path, status_code))

    lines = ["# Dirty Triage — 미커밋 분류\n"]
    for cat in FileCategory:
        items = by_category.get(cat, [])
        lines.append(f"\n## {cat.value} ({len(items)})\n")
        for repo_name, file_path, status_code in items[:50]:
            lines.append(f"- `{repo_name}/{file_path}` [{status_code}]")
        if len(items) > 50:
            lines.append(f"- ... +{len(items) - 50} more")

    out.write_text("\n".join(lines))
    console.print(f"[green]리포트:[/green] {out}")
    summary = {cat.value: len(by_category.get(cat, [])) for cat in FileCategory}
    console.print(summary)


@app.command()
def cleanup(
    triage_md: Path = typer.Argument(..., exists=True, help="triage 리포트 마크다운"),
    dry_run: bool = typer.Option(True, help="기본 dry-run. --no-dry-run 으로 실제 처리"),
):
    """triage 리포트의 commit_ready 일괄 커밋 + delete 일괄 삭제."""
    from console.cleanup import commit_ready_in_repo, delete_in_repo
    from collections import defaultdict
    import re
    import subprocess

    text = triage_md.read_text()
    sections: dict[str, list[tuple[str, str]]] = {"commit_ready": [], "delete": []}
    current = None
    item_re = re.compile(r"^- `([^/]+)/(.+)` \[")

    for line in text.splitlines():
        if line.startswith("## commit_ready"):
            current = "commit_ready"
            continue
        if line.startswith("## delete"):
            current = "delete"
            continue
        if line.startswith("## "):
            current = None
            continue
        if current is None:
            continue
        m = item_re.match(line)
        if m:
            sections[current].append((m.group(1), m.group(2)))

    by_repo_commit: dict[str, list[str]] = defaultdict(list)
    by_repo_delete: dict[str, list[str]] = defaultdict(list)
    for repo_name, file_path in sections["commit_ready"]:
        by_repo_commit[repo_name].append(file_path)
    for repo_name, file_path in sections["delete"]:
        by_repo_delete[repo_name].append(file_path)

    workspace = Path.home() / "Workspace"
    console.print(
        f"[yellow]commit_ready: {len(sections['commit_ready'])} files in "
        f"{len(by_repo_commit)} repos[/yellow]"
    )
    console.print(
        f"[yellow]delete: {len(sections['delete'])} files in "
        f"{len(by_repo_delete)} repos[/yellow]"
    )

    if dry_run:
        console.print("[cyan]dry-run. --no-dry-run 으로 실제 처리[/cyan]")
        return

    committed = 0
    for repo_name, files in by_repo_commit.items():
        repo_path = workspace / repo_name
        if not (repo_path / ".git").exists():
            continue
        try:
            commit_ready_in_repo(repo_path, files)
            committed += 1
        except subprocess.CalledProcessError as e:
            console.print(f"[red]commit failed: {repo_name}: {e}[/red]")

    deleted_count = 0
    for repo_name, files in by_repo_delete.items():
        repo_path = workspace / repo_name
        if not repo_path.exists():
            continue
        delete_in_repo(repo_path, files)
        deleted_count += len(files)

    console.print(f"[green]commit: {committed} repos, delete: {deleted_count} files[/green]")


if __name__ == "__main__":
    app()
