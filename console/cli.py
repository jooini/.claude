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
    """모든 repo의 미커밋 파일을 분류 → 마크다운 리포트.

    출력 형식: ``- `<repo_rel_path>` :: `<file_path>` [<status>]``.
    repo_rel_path 는 workspace_root 기준 상대 경로(중첩 repo 지원).
    """
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

        # workspace_root 기준 상대 경로 (중첩 repo 지원)
        try:
            rel = repo.path.relative_to(root)
            repo_display = str(rel)
        except ValueError:
            repo_display = repo.path.name

        for line in result.stdout.splitlines():
            if not line.strip():
                continue
            status_code = line[:2].strip()
            file_path = line[3:].strip()
            cat = classify(file_path, status_code)
            by_category[cat].append((repo_display, file_path, status_code))

    lines = ["# Dirty Triage — 미커밋 분류\n"]
    for cat in FileCategory:
        items = by_category.get(cat, [])
        lines.append(f"\n## {cat.value} ({len(items)})\n")
        for repo_name, file_path, status_code in items[:50]:
            lines.append(f"- `{repo_name}` :: `{file_path}` [{status_code}]")
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
    verbose: bool = typer.Option(False, "-v", "--verbose", help="repo 단위 처리 결과 출력"),
):
    """triage 리포트의 commit_ready 일괄 커밋 + delete 일괄 삭제.

    실패 시 침묵하지 않고 사전 검증/실행 단계 별 실패 건수를 명시한다.
    """
    from console.cleanup import (
        commit_ready_in_repo,
        delete_in_repo,
        parse_triage_md,
    )
    from collections import defaultdict
    import subprocess

    sections = parse_triage_md(triage_md)
    workspace = Path.home() / "Workspace"

    by_repo_commit: dict[str, list[str]] = defaultdict(list)
    by_repo_delete: dict[str, list[str]] = defaultdict(list)
    failed_pre: list[tuple[str, str, str]] = []

    for repo_rel, file_path in sections["commit_ready"]:
        repo_path = workspace / repo_rel
        if not (repo_path / ".git").exists():
            failed_pre.append(("commit_ready", f"{repo_rel}/{file_path}", "repo .git 없음"))
            continue
        if not (repo_path / file_path).exists():
            failed_pre.append(("commit_ready", f"{repo_rel}/{file_path}", "파일 없음"))
            continue
        by_repo_commit[repo_rel].append(file_path)

    for repo_rel, file_path in sections["delete"]:
        repo_path = workspace / repo_rel
        if not repo_path.exists():
            failed_pre.append(("delete", f"{repo_rel}/{file_path}", "repo 없음"))
            continue
        by_repo_delete[repo_rel].append(file_path)

    console.print(
        f"[yellow]commit_ready: {len(sections['commit_ready'])} files in "
        f"{len(by_repo_commit)} repos[/yellow]"
    )
    console.print(
        f"[yellow]delete: {len(sections['delete'])} files in "
        f"{len(by_repo_delete)} repos[/yellow]"
    )
    if failed_pre:
        console.print(f"[red]사전 검증 실패: {len(failed_pre)}건[/red]")
        for cat, key, reason in failed_pre[:10]:
            console.print(f"  - [{cat}] {key} — {reason}")
        if len(failed_pre) > 10:
            console.print(f"  ... +{len(failed_pre) - 10}")

    if dry_run:
        console.print("[cyan]dry-run. --no-dry-run 으로 실제 처리[/cyan]")
        raise typer.Exit(code=0)

    committed = 0
    commit_failed: list[tuple[str, str]] = []
    for repo_rel, files in by_repo_commit.items():
        repo_path = workspace / repo_rel
        try:
            commit_ready_in_repo(repo_path, files)
            committed += 1
            if verbose:
                console.print(f"  [green]commit ok[/green]: {repo_rel} ({len(files)} files)")
        except subprocess.CalledProcessError as e:
            commit_failed.append((repo_rel, str(e)))
            console.print(f"  [red]commit fail[/red]: {repo_rel}: {e}")

    deleted_count = 0
    for repo_rel, files in by_repo_delete.items():
        repo_path = workspace / repo_rel
        delete_in_repo(repo_path, files)
        deleted_count += len(files)
        if verbose:
            console.print(f"  [green]delete ok[/green]: {repo_rel} ({len(files)} files)")

    console.print(
        f"[green]commit: {committed} repos, delete: {deleted_count} files[/green]"
    )
    if commit_failed or failed_pre:
        console.print(
            f"[red]총 실패: pre={len(failed_pre)}, commit={len(commit_failed)}[/red]"
        )
        raise typer.Exit(code=1)


@app.command()
def compare(
    yesterday: Path = typer.Argument(..., exists=True, help="이전 sweep JSON"),
    today: Path = typer.Argument(..., exists=True, help="현재 sweep JSON"),
):
    """두 sweep JSON diff: 신규 dead/zombie, 부활, 미커밋 변화, 라벨 분포."""
    a = json.loads(yesterday.read_text())
    b = json.loads(today.read_text())

    a_by = {r["path"]: r for r in a["repos"]}
    b_by = {r["path"]: r for r in b["repos"]}

    new_dead = [
        r for p, r in b_by.items()
        if r["label"] == "dead" and a_by.get(p, {}).get("label") != "dead"
    ]
    new_zombie = [
        r for p, r in b_by.items()
        if r["label"] == "zombie" and a_by.get(p, {}).get("label") != "zombie"
    ]
    revived = [
        r for p, r in b_by.items()
        if r["label"] in ("active", "warm")
        and a_by.get(p, {}).get("label") in ("dead", "stale", "zombie")
    ]

    a_dirty = sum(r["dirty_count"] for r in a["repos"])
    b_dirty = sum(r["dirty_count"] for r in b["repos"])

    console.print(f"[bold]Sweep diff: {yesterday.stem} → {today.stem}[/bold]")
    console.print(f"미커밋: {a_dirty} → {b_dirty} ({b_dirty - a_dirty:+d})")
    console.print(
        f"라벨: {a['summary']['by_label']} → {b['summary']['by_label']}"
    )
    console.print(f"\n[red]신규 dead ({len(new_dead)}):[/red]")
    for r in new_dead[:10]:
        console.print(f"  - {Path(r['path']).name}")
    console.print(f"\n[yellow]신규 zombie ({len(new_zombie)}):[/yellow]")
    for r in new_zombie[:10]:
        console.print(f"  - {Path(r['path']).name}")
    console.print(f"\n[green]부활 ({len(revived)}):[/green]")
    for r in revived[:10]:
        console.print(f"  - {Path(r['path']).name}")


if __name__ == "__main__":
    app()
