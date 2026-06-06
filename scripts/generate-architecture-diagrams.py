#!/usr/bin/env python3
"""Generate presentation-ready Claude architecture diagrams from registries."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_PATH = ROOT / "cache" / "generated-docs" / "claude-architecture-diagrams.generated.md"


def load_json(relative_path: str) -> dict[str, Any]:
    return json.loads((ROOT / relative_path).read_text(encoding="utf-8"))


def count_files(pattern: str) -> int:
    return sum(1 for path in ROOT.glob(pattern) if path.is_file())


def markdown_table(headers: list[str], rows: list[list[str]]) -> str:
    rendered = [
        "| " + " | ".join(headers) + " |",
        "| " + " | ".join("---" for _ in headers) + " |",
    ]
    for row in rows:
        rendered.append("| " + " | ".join(row) + " |")
    return "\n".join(rendered)


def provider_label(provider: str, info: dict[str, Any], count_by_provider: dict[str, int]) -> str:
    count = count_by_provider.get(provider, 0)
    role = info.get("role", "")
    return f"{provider}<br/>{role}<br/>{count} runtime files"


def generate() -> str:
    settings = load_json("settings.json")
    mcp = load_json(".mcp.json")
    hook_manifest = load_json("registry/hooks-manifest.json")
    settings_policy = load_json("registry/settings-policy.json")
    hooks_inventory = load_json("registry/hooks-inventory.json")
    hook_consolidation = load_json("registry/hook-consolidation-candidates.json")
    hook_consolidation_plan_exists = (ROOT / "registry" / "hook-consolidation-plan.md").exists()
    hook_wrapper_plan = load_json("registry/hook-wrapper-plan.json")
    hook_wrapper_activation_gates = load_json("registry/hook-wrapper-activation-gates.json")
    hook_wrapper_activation_report = load_json("registry/hook-wrapper-activation-report.json")
    hook_wrapper_isolated_execute_report = load_json(
        "registry/hook-wrapper-isolated-execute-report.json"
    )
    hook_order_review = load_json("registry/hook-order-review.json")
    hook_output_contracts = load_json("registry/hook-output-contracts.json")
    llm_calls_inventory = load_json("registry/llm-calls-inventory.json")
    llm_routing = load_json("registry/llm-routing.json")
    hook_timeout_policy = load_json("registry/hook-timeout-policy.json")

    hooks = hooks_inventory.get("hooks", [])
    hook_count = hooks_inventory.get("hook_count", len(hooks))
    event_count = hooks_inventory.get("event_count", len(settings.get("hooks", {})))
    event_counts = Counter(hook.get("event", "unknown") for hook in hooks)
    priority_counts = Counter(hook.get("priority", "unknown") for hook in hooks)
    llm_hook_count = sum(1 for hook in hooks if hook.get("llm_providers"))
    side_effect_count = hooks_inventory.get("side_effect_count", 0)
    timeout_missing = hooks_inventory.get("timeout_missing_count", 0)
    effective_timeout_missing = hooks_inventory.get("effective_timeout_missing_count", 0)
    stop_contract = next(
        (
            contract
            for contract in hook_output_contracts.get("contracts", [])
            if contract.get("event") == "Stop"
        ),
        {},
    )
    stop_contract_hooks = stop_contract.get("hooks", [])
    stop_user_visible_hooks = sum(
        1 for hook in stop_contract_hooks if hook.get("user_visible")
    )
    pretool_contract = next(
        (
            contract
            for contract in hook_output_contracts.get("contracts", [])
            if contract.get("event") == "PreToolUse"
        ),
        {},
    )
    pretool_contract_hooks = pretool_contract.get("hooks", [])
    pretool_blocking_hooks = sum(
        1 for hook in pretool_contract_hooks if hook.get("blocks_tool")
    )

    provider_counts_raw = {
        item.get("provider", ""): item.get("file_count", 0)
        for item in llm_calls_inventory.get("provider_counts", [])
    }
    provider_alias = {
        "gemini": "gemini_or_agy",
        "codex": "codex",
        "gemma": "gemma",
    }
    provider_counts = {
        provider: provider_counts_raw.get(provider_alias.get(provider, provider), 0)
        for provider in llm_routing.get("providers", {})
    }
    provider_counts["antigravity"] = provider_counts_raw.get("gemini_or_agy", 0)
    provider_counts["claude"] = hook_count

    skill_count = count_files("skills/*/SKILL.md")
    moai_skill_count = count_files("skills/moai*/SKILL.md")
    agent_count = count_files("agents-src/*.md")
    moai_agent_count = count_files("agents/moai/*.md")
    command_count = count_files("commands/**/*.md")
    moai_command_count = count_files("commands/moai/*.md")
    settings_mcp_servers = sorted(settings.get("mcpServers", {}).keys())
    project_mcp_servers = sorted(mcp.get("mcpServers", {}).keys())
    mcp_servers = settings_mcp_servers + project_mcp_servers

    event_rows = [
        [
            event,
            str(event_counts.get(event, 0)),
            str(
                sum(
                    1
                    for hook in hooks
                    if hook.get("event") == event and hook.get("priority") == "P0"
                )
            ),
            str(
                sum(
                    1
                    for hook in hooks
                    if hook.get("event") == event and hook.get("llm_providers")
                )
            ),
        ]
        for event in sorted(event_counts)
    ]
    provider_rows = []
    for provider, info in llm_routing.get("providers", {}).items():
        provider_rows.append(
            [
                provider,
                info.get("role", ""),
                str(provider_counts.get(provider, 0)),
                info.get("privacy_tier", ""),
                ", ".join(info.get("entrypoints", [])[:3]),
            ]
        )

    p0 = priority_counts.get("P0", 0)
    p1 = priority_counts.get("P1", 0)
    p2 = priority_counts.get("P2", 0)
    p3 = priority_counts.get("P3", 0)

    provider_nodes = []
    provider_edges = []
    for provider, info in llm_routing.get("providers", {}).items():
        node_id = "LLM_" + provider.replace("-", "_")
        label = provider_label(provider, info, provider_counts)
        provider_nodes.append(f'        {node_id}["{label}"]')
        if provider == "claude":
            continue
        provider_edges.append(f"    Claude --> Router --> {node_id}")

    overall_diagram = f"""```mermaid
%%{{init: {{"flowchart": {{"defaultRenderer": "elk"}} }} }}%%
flowchart TB
    User["사용자"]
    Claude["Active orchestrator<br/>Claude / Codex / Gemini / local routes"]

    subgraph HookLayer["Hook automation<br/>{hook_count} hooks / {event_count} events"]
        SessionStart["SessionStart"]
        UserPromptSubmit["UserPromptSubmit"]
        PreToolUse["PreToolUse"]
        PostToolUse["PostToolUse"]
        StopHooks["Stop / SessionEnd"]
    end

    subgraph RuleLayer["Rules and registry"]
        Settings["settings.json"]
        McpConfig[".mcp.json"]
        ClaudeMd["CLAUDE.md / AGENTS.md"]
        Workflows["workflows/*.md"]
        Registry["registry/*.json"]
        SettingsPolicy["settings-policy.json"]
        HookManifest["hooks-manifest.json"]
        HookCandidates["hook-consolidation-candidates.json"]
        HookPlan["hook-consolidation-plan.md"]
        HookWrapperPlan["hook-wrapper-plan.json"]
        HookActivationGates["hook-wrapper-activation-gates.json"]
        HookActivationReport["hook-wrapper-activation-report.json"]
        HookIsolatedExecute["hook-wrapper-isolated-execute-report.json"]
        HookOrderReview["hook-order-review.json"]
        HookOutputContracts["hook-output-contracts.json"]
        HookWrapperRunner["hook-wrapper-runner.py"]
        Projection["project-settings-from-registry.py"]
        Audit["scripts/audit-claude-config.py"]
    end

    subgraph AgentLayer["Agents and skills"]
        Agents["agents-src<br/>{agent_count} roles"]
        MoaiAgents["agents/moai<br/>{moai_agent_count} agents"]
        Skills["skills<br/>{skill_count} total / {moai_skill_count} moai"]
        Commands["commands<br/>{command_count} total / {moai_command_count} moai"]
    end

    subgraph LLMLayer["LLM support layer"]
        Router["scripts/llm-router.sh<br/>task fallback + handoff"]
{chr(10).join(provider_nodes)}
    end

    subgraph KnowledgeLayer["Knowledge and records"]
        LocalRag["local-rag MCP"]
        ClaudeMem["claude-mem plugin"]
        Caches["cache/*"]
        Obsidian["Obsidian Vault"]
        MoaiState[".moai/*"]
    end

    User --> UserPromptSubmit
    UserPromptSubmit --> Claude
    Claude --> SessionStart
    Claude --> PreToolUse
    Claude --> PostToolUse
    Claude --> StopHooks

    Claude --> ClaudeMd
    Claude --> Workflows
    Settings --> McpConfig
    Registry --> SettingsPolicy
    Registry --> HookManifest
    Registry --> HookCandidates
    HookCandidates --> HookPlan
    HookCandidates --> HookWrapperPlan
    HookWrapperPlan --> HookActivationGates
    HookActivationGates --> HookActivationReport
    HookActivationGates --> HookIsolatedExecute
    HookWrapperPlan --> HookOrderReview
    HookOrderReview --> HookOutputContracts
    HookWrapperPlan --> HookWrapperRunner
    HookManifest --> Projection
    Projection --> Settings
    Registry --> Audit
    Audit --> Settings
    Audit --> McpConfig

    Claude --> Agents
    Claude --> Skills
    Skills --> Commands
    Skills --> MoaiAgents
    Skills --> MoaiState

{chr(10).join(provider_edges)}
    Claude --> LocalRag
    Claude --> ClaudeMem
    PostToolUse --> Caches
    StopHooks --> Obsidian
```"""

    sequence_diagram = f"""```mermaid
%%{{init: {{"flowchart": {{"defaultRenderer": "elk"}} }} }}%%
flowchart TB
    Start["세션 시작"] --> Load["settings.json / .mcp.json / CLAUDE.md 로드"]
    Load --> SessionStartNode["SessionStart hooks<br/>{event_counts.get('SessionStart', 0)} registered"]
    SessionStartNode --> Wait["사용자 입력 대기"]

    Wait --> PromptNode["UserPromptSubmit hooks<br/>{event_counts.get('UserPromptSubmit', 0)} registered"]
    PromptNode --> Judge["Active orchestrator 판단<br/>rules + context + user intent"]
    Judge --> NeedTool{{"도구 호출 필요?"}}
    NeedTool -->|"아니오"| Answer["응답 생성"]
    NeedTool -->|"예"| PreNode["PreToolUse hooks<br/>{event_counts.get('PreToolUse', 0)} registered"]
    PreNode --> Tool["Bash / Edit / Agent / Skill / MCP / LLM"]
    Tool --> PostNode["PostToolUse hooks<br/>{event_counts.get('PostToolUse', 0)} registered"]
    PostNode --> Judge

    Answer --> StopNode["Stop hooks<br/>{event_counts.get('Stop', 0)} registered"]
    StopNode --> Continue{{"다음 입력?"}}
    Continue -->|"예"| Wait
    Continue -->|"아니오"| SessionEndNode["SessionEnd hooks<br/>{event_counts.get('SessionEnd', 0)} registered"]
    SessionEndNode --> End["세션 종료"]

    Tool -. "compact 필요 시" .-> PreCompact["PreCompact hooks<br/>{event_counts.get('PreCompact', 0)} registered"]
    Tool -. "알림 이벤트" .-> Notification["Notification hooks<br/>{event_counts.get('Notification', 0)} registered"]
```"""

    llm_diagram = f"""```mermaid
%%{{init: {{"flowchart": {{"defaultRenderer": "elk"}} }} }}%%
flowchart LR
    Claude["Active orchestrator<br/>provider-neutral"]
    Router["scripts/llm-router.sh<br/>task fallback + recursion guard"]
    Adapter["scripts/llm-call.sh<br/>shell adapter telemetry"]
    PythonIni["scripts/_lib_ini_call.py<br/>python ini telemetry"]
    Usage["scripts/llm-usage.py<br/>usage and health report"]
    Audit["audit-claude-config.py<br/>schema + consumer check"]

    Claude --> Router
    Router --> Gemini["Gemini / agy<br/>{provider_counts_raw.get('gemini_or_agy', 0)} runtime files"]
    Router --> Codex["Codex CLI/plugin<br/>{provider_counts_raw.get('codex', 0)} runtime files"]
    Router --> Gemma["Gemma/Ollama/ini<br/>{provider_counts_raw.get('gemma', 0)} runtime files"]
    Router --> Antigravity["Antigravity surface"]

    Router --> Handoff["cache/llm-handoff/current.json"]
    Router --> Health["cache/llm-provider-health.json"]
    Router --> RouterLog["cache/llm-router-calls.jsonl"]
    Adapter --> Gemini
    Adapter --> Codex
    Adapter --> Gemma
    PythonIni --> Gemma

    Adapter --> AdapterLog["cache/llm-adapter-calls.jsonl"]
    PythonIni --> GemmaLog["cache/gemma-calls.jsonl"]
    AdapterLog --> Usage
    GemmaLog --> Usage
    Usage --> Audit
```"""

    snapshot = markdown_table(
        ["항목", "값"],
        [
            ["registered hooks", str(hook_count)],
            ["hook events", str(event_count)],
            ["settings policy", settings_policy.get("status", "")],
            ["hook manifest projection", hook_manifest.get("projection_target", "")],
            ["settings projection", "project-settings-from-registry.py"],
            [
                "hook consolidation candidates",
                (
                    f"{hook_consolidation.get('candidate_count', 0)} "
                    f"(low/medium/high "
                    f"{hook_consolidation.get('low_risk_count', 0)}/"
                    f"{hook_consolidation.get('medium_risk_count', 0)}/"
                    f"{hook_consolidation.get('high_risk_count', 0)})"
                ),
            ],
            ["hook consolidation plan", "present" if hook_consolidation_plan_exists else "missing"],
            [
                "hook wrapper plans / safe initial",
                (
                    f"{hook_wrapper_plan.get('plan_count', 0)} / "
                    f"{hook_wrapper_plan.get('safe_initial_migration_count', 0)}"
                ),
            ],
            [
                "hook wrapper definitions / candidate plans",
                (
                    f"{hook_wrapper_plan.get('definition_count', 0)} / "
                    f"{hook_wrapper_plan.get('candidate_plan_count', 0)}"
                ),
            ],
            [
                "hook wrapper active / planned",
                (
                    f"{hook_wrapper_plan.get('active_definition_count', 0)} / "
                    f"{hook_wrapper_plan.get('planned_definition_count', 0)}"
                ),
            ],
            [
                "planned wrapper gates / validations",
                (
                    f"{hook_wrapper_activation_gates.get('gate_count', 0)} / "
                    f"{hook_wrapper_activation_report.get('validation_count', 0)}"
                ),
            ],
            [
                "planned wrapper validation status",
                (
                    f"{hook_wrapper_activation_report.get('status', '')} "
                    f"(failed {hook_wrapper_activation_report.get('failed_validation_count', 0)})"
                ),
            ],
            [
                "isolated execute scenarios",
                (
                    f"{hook_wrapper_isolated_execute_report.get('scenario_count', 0)} "
                    f"(failed {hook_wrapper_isolated_execute_report.get('failed_scenario_count', 0)})"
                ),
            ],
            ["hook order-review items", str(hook_order_review.get("review_item_count", 0))],
            ["Stop output contract hooks", str(len(stop_contract_hooks))],
            ["Stop user-visible hooks", str(stop_user_visible_hooks)],
            ["PreToolUse output contract hooks", str(len(pretool_contract_hooks))],
            ["PreToolUse blocking contracts", str(pretool_blocking_hooks)],
            [
                "order-review top blocker",
                max(
                    hook_order_review.get("blocker_counts", {"none": 0}).items(),
                    key=lambda item: item[1],
                )[0],
            ],
            [
                "order-review top strategy",
                max(
                    hook_order_review.get("strategy_counts", {"none": 0}).items(),
                    key=lambda item: item[1],
                )[0],
            ],
            ["priority P0/P1/P2/P3", f"{p0}/{p1}/{p2}/{p3}"],
            ["hooks with LLM provider signals", str(llm_hook_count)],
            ["side effect tags", str(side_effect_count)],
            ["timeout missing / effective missing", f"{timeout_missing} / {effective_timeout_missing}"],
            ["timeout runtime requirement", str(hook_timeout_policy.get("runtime_requirement"))],
            ["skills / moai skills", f"{skill_count} / {moai_skill_count}"],
            ["agents-src / moai agents", f"{agent_count} / {moai_agent_count}"],
            ["commands / moai commands", f"{command_count} / {moai_command_count}"],
            ["MCP servers", ", ".join(mcp_servers)],
        ],
    )

    content = f"""<!-- generated by scripts/generate-architecture-diagrams.py; do not edit by hand -->

# Claude Architecture Diagrams

이 문서는 `settings.json`, `.mcp.json`, `registry/settings-policy.json`, `registry/hooks-manifest.json`, `registry/hooks-inventory.json`, `registry/hook-consolidation-candidates.json`, `registry/hook-wrapper-definitions.json`, `registry/hook-wrapper-plan.json`, `registry/hook-wrapper-activation-gates.json`, `registry/hook-wrapper-activation-report.json`, `registry/hook-wrapper-isolated-execute-report.json`, `registry/hook-order-review.json`, `registry/hook-output-contracts.json`, `registry/llm-calls-inventory.json`, `registry/llm-routing.json`에서 자동 생성된다. `registry/presentation-pipeline.json`은 이 파일을 발표 deck/문서 생성 입력으로 선언한다. 발표 문서에 들어가는 구조도 숫자는 이 파일을 기준으로 맞춘다.

## Snapshot

{snapshot}

## Overall Architecture

{overall_diagram}

## Execution Order

{sequence_diagram}

## LLM Routing And Telemetry

{llm_diagram}

## Hook Event Matrix

{markdown_table(["event", "hooks", "P0 hooks", "LLM hooks"], event_rows)}

## LLM Provider Matrix

{markdown_table(["provider", "role", "runtime files", "privacy", "entrypoints"], provider_rows)}
"""
    return content


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--write", action="store_true", help=f"write {OUTPUT_PATH.relative_to(ROOT)}")
    args = parser.parse_args()

    rendered = generate()
    if args.write:
        OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
        OUTPUT_PATH.write_text(rendered, encoding="utf-8")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
