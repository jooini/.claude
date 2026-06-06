#!/usr/bin/env python3
"""Audit the local Claude Code configuration against transitional registry rules."""

from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def load_json(relative_path: str) -> dict:
    path = ROOT / relative_path
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing file: {relative_path}")
    except json.JSONDecodeError as error:
        fail(f"invalid JSON in {relative_path}: {error}")
    raise AssertionError("unreachable")


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    raise SystemExit(1)


def flatten_hooks(settings: dict) -> list[dict]:
    flattened: list[dict] = []
    order = 0
    for event, groups in settings.get("hooks", {}).items():
        for group_index, group in enumerate(groups):
            matcher = group.get("matcher", "*")
            for hook_index, hook in enumerate(group.get("hooks", [])):
                command = hook.get("command", "")
                flattened.append(
                    {
                        "id": f"{event}:{group_index}:{hook_index}",
                        "order": order,
                        "event": event,
                        "matcher": matcher,
                        "command": command,
                    }
                )
                order += 1
    return flattened


def hook_exists(
    hooks: list[dict],
    event: str,
    matcher: str,
    command_contains: str,
    inventory_hooks: list[dict] | None = None,
) -> bool:
    for hook in hooks:
        if hook["event"] != event:
            continue
        if matcher != "*" and hook["matcher"] != matcher:
            continue
        if command_contains in hook["command"]:
            return True
    for hook in inventory_hooks or []:
        if hook["event"] != event:
            continue
        if matcher != "*" and hook["matcher"] != matcher:
            continue
        if any(command_contains in str(script) for script in hook.get("wrapped_scripts", [])):
            return True
    return False


def read_text(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def comparable_hooks(hooks: list[dict]) -> list[dict]:
    return [
        {
            "id": hook["id"],
            "order": hook["order"],
            "event": hook["event"],
            "matcher": hook["matcher"],
            "command": hook["command"],
        }
        for hook in hooks
    ]


def settings_hook_count(settings_hooks: dict) -> int:
    return sum(
        len(group.get("hooks", []))
        for groups in settings_hooks.values()
        for group in groups
    )


def generated_json_from_script(script_name: str) -> dict:
    output = subprocess.check_output(
        [sys.executable, str(ROOT / "scripts" / script_name)],
        cwd=ROOT,
        text=True,
    )
    return json.loads(output)


def generated_text_from_script(script_name: str) -> str:
    return subprocess.check_output(
        [sys.executable, str(ROOT / "scripts" / script_name)],
        cwd=ROOT,
        text=True,
    )


def is_executable(relative_path: str) -> bool:
    path = ROOT / relative_path
    return path.is_file() and path.stat().st_mode & 0o111 != 0


def registered_hook_scripts(hooks: list[dict]) -> list[str]:
    scripts = {
        hook["script"]
        for hook in hooks
        if hook.get("script") and str(hook["script"]).startswith("hooks/")
    }
    return sorted(scripts)


def registered_hook_direct_llm_hits(hooks: list[dict]) -> list[str]:
    patterns = [
        re.compile(r"\$GEM_CLI\b"),
        re.compile(r"\bGEM_CLI="),
        re.compile(r"\$QWEN_CLI\b"),
        re.compile(r"\$QWEN\b"),
        re.compile(r"codex exec --skip-git-repo-check"),
        re.compile(r"codex exec --full-auto"),
        re.compile(r"\.local/bin/ini"),
    ]
    hits: list[str] = []
    for script in registered_hook_scripts(hooks):
        path = ROOT / script
        try:
            lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        except OSError:
            continue
        for line_number, line in enumerate(lines, start=1):
            if any(pattern.search(line) for pattern in patterns):
                hits.append(f"{script}:{line_number}")
    return hits


def direct_llm_patterns(policy: dict) -> list[re.Pattern]:
    return [re.compile(pattern) for pattern in policy.get("disallowed_runtime_patterns", [])]


def allowed_direct_path_map(policy: dict) -> dict[str, dict]:
    return {
        item["path"]: item
        for item in policy.get("allowed_direct_paths", [])
        if item.get("path")
    }


def runtime_llm_scan_files(policy: dict) -> list[Path]:
    excluded_meta = set(policy.get("excluded_meta_paths", []))
    excluded_parts = {"__pycache__", "_archive", "_disabled", "_removed_2026-06-01", "_test", "dashboard"}
    files: set[Path] = set()
    for pattern in ["hooks/**/*.sh", "scripts/*.sh", "scripts/*.py"]:
        for path in ROOT.glob(pattern):
            if not path.is_file():
                continue
            relative = str(path.relative_to(ROOT))
            if relative in excluded_meta:
                continue
            if any(part in excluded_parts for part in path.relative_to(ROOT).parts):
                continue
            files.add(path)
    return sorted(files)


def is_allowed_direct_hit(relative_path: str, line: str, allow_map: dict[str, dict]) -> bool:
    item = allow_map.get(relative_path)
    if not item:
        return False
    allowed_line_contains = item.get("allowed_line_contains")
    if not allowed_line_contains:
        return True
    return any(fragment in line for fragment in allowed_line_contains)


def unapproved_runtime_direct_llm_hits(policy: dict) -> list[str]:
    patterns = direct_llm_patterns(policy)
    allow_map = allowed_direct_path_map(policy)
    hits: list[str] = []
    for path in runtime_llm_scan_files(policy):
        relative = str(path.relative_to(ROOT))
        try:
            lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
        except OSError:
            continue
        for line_number, line in enumerate(lines, start=1):
            if not any(pattern.search(line) for pattern in patterns):
                continue
            if is_allowed_direct_hit(relative, line, allow_map):
                continue
            hits.append(f"{relative}:{line_number}")
    return hits


def validate_llm_log_schema(schema: dict) -> None:
    required_fields = schema.get("required_common_fields", [])
    if not required_fields:
        fail("registry/llm-log-schema.json must define required_common_fields")
    if schema.get("threshold_policy") != "registry/llm-adapter-thresholds.json":
        fail("registry/llm-log-schema.json must reference registry/llm-adapter-thresholds.json")
    sources = schema.get("sources", [])
    if not sources:
        fail("registry/llm-log-schema.json must define sources")
    for source in sources:
        path = source.get("path")
        if not path:
            fail("registry/llm-log-schema.json source missing path")
        source_path = ROOT / path
        if not source_path.exists():
            fail(f"registry/llm-log-schema.json source does not exist: {path}")
        text = source_path.read_text(encoding="utf-8", errors="ignore")
        missing_fields = [
            field
            for field in required_fields
            if f'"{field}"' not in text and f"'{field}'" not in text
        ]
        if missing_fields:
            fail(f"{path} missing LLM log schema fields: {', '.join(missing_fields)}")


def validate_llm_adapter_thresholds(thresholds: dict) -> None:
    if thresholds.get("version") != 1:
        fail("registry/llm-adapter-thresholds.json version must be 1")
    if thresholds.get("status") != "active":
        fail("registry/llm-adapter-thresholds.json status must be active")
    if thresholds.get("metric_source") != "cache/llm-adapter-calls.jsonl":
        fail("registry/llm-adapter-thresholds.json metric_source mismatch")
    minimum_calls = thresholds.get("minimum_calls_for_rate")
    if not isinstance(minimum_calls, int) or minimum_calls < 1:
        fail("registry/llm-adapter-thresholds.json minimum_calls_for_rate must be positive")
    defaults = thresholds.get("defaults", {})
    required_defaults = [
        "warning_error_rate",
        "critical_error_rate",
        "warning_timeout_rate",
        "critical_timeout_rate",
        "warning_avg_duration_ms",
        "critical_avg_duration_ms",
    ]
    for key in required_defaults:
        value = defaults.get(key)
        if not isinstance(value, (int, float)) or value < 0:
            fail(f"registry/llm-adapter-thresholds.json defaults.{key} must be nonnegative")
    if defaults["warning_error_rate"] > defaults["critical_error_rate"]:
        fail("registry/llm-adapter-thresholds.json error thresholds are inverted")
    if defaults["warning_timeout_rate"] > defaults["critical_timeout_rate"]:
        fail("registry/llm-adapter-thresholds.json timeout thresholds are inverted")
    if defaults["warning_avg_duration_ms"] > defaults["critical_avg_duration_ms"]:
        fail("registry/llm-adapter-thresholds.json duration thresholds are inverted")


def validate_llm_usage_report(schema: dict) -> None:
    path = ROOT / "scripts" / "llm-usage.py"
    if not path.exists():
        fail("scripts/llm-usage.py must exist")
    text = path.read_text(encoding="utf-8", errors="ignore")
    required_fragments = [
        "llm-adapter-calls.jsonl",
        "collect_llm_adapter",
        "'llm_adapter'",
        "'by_provider'",
        "'by_caller'",
        "llm-adapter-thresholds.json",
        "evaluate_adapter_health",
        "warning_error_rate",
        "critical_timeout_rate",
        "warning_avg_duration_ms",
    ]
    missing_fragments = [fragment for fragment in required_fragments if fragment not in text]
    if missing_fragments:
        fail("scripts/llm-usage.py missing adapter reporting fragments: " + ", ".join(missing_fragments))
    required_fields = schema.get("required_common_fields", [])
    missing_fields = [
        field
        for field in required_fields
        if f'"{field}"' not in text and f"'{field}'" not in text
    ]
    if missing_fields:
        fail("scripts/llm-usage.py does not consume LLM log schema fields: " + ", ".join(missing_fields))


def validate_settings_policy(settings: dict, project_mcp: dict, policy: dict) -> None:
    projection_scope = policy.get("projection_scope", {})
    projected_settings_scope = set(projection_scope.get("settings_json", []))
    for required_scope in [
        "hooks",
        "env.required_exact",
        "env.path_must_start_with",
        "mcpServers.required_server_commands",
        "permissions.defaultMode",
        "permissions.required_allow",
        "permissions.required_deny",
    ]:
        if required_scope not in projected_settings_scope:
            fail(f"registry/settings-policy.json projection_scope missing: {required_scope}")
    if "secret values" not in set(projection_scope.get("excluded", [])):
        fail("registry/settings-policy.json projection_scope must exclude secret values")

    missing_top_level = [
        key for key in policy.get("settings_top_level_required_keys", []) if key not in settings
    ]
    if missing_top_level:
        fail("settings.json missing required top-level keys: " + ", ".join(missing_top_level))

    env = settings.get("env", {})
    for key, expected in policy.get("env", {}).get("required_exact", {}).items():
        if env.get(key) != expected:
            fail(f"settings.json env.{key} must be {expected!r}")
    path_prefix = policy.get("env", {}).get("path_must_start_with")
    if path_prefix and not str(env.get("PATH", "")).startswith(path_prefix):
        fail(f"settings.json env.PATH must start with {path_prefix}")

    settings_mcp = settings.get("mcpServers", {})
    for name, expected in policy.get("mcp", {}).get("settings_json_required_servers", {}).items():
        server = settings_mcp.get(name)
        if not server:
            fail(f"settings.json missing MCP server from policy: {name}")
        if expected.get("command") and server.get("command") != expected["command"]:
            fail(f"settings.json mcpServers.{name}.command must be {expected['command']!r}")
        server_env = server.get("env") or {}
        missing_env_keys = [
            key for key in expected.get("required_env_keys", []) if key not in server_env
        ]
        if missing_env_keys:
            fail(f"settings.json mcpServers.{name} missing env keys: {', '.join(missing_env_keys)}")

    project_mcp_servers = project_mcp.get("mcpServers", {})
    for name, expected in policy.get("mcp", {}).get("project_mcp_required_servers", {}).items():
        server = project_mcp_servers.get(name)
        if not server:
            fail(f".mcp.json missing MCP server from policy: {name}")
        if expected.get("command") and server.get("command") != expected["command"]:
            fail(f".mcp.json mcpServers.{name}.command must be {expected['command']!r}")
        args_text = " ".join(str(item) for item in server.get("args", []))
        if expected.get("args_contains") and expected["args_contains"] not in args_text:
            fail(f".mcp.json mcpServers.{name}.args must contain {expected['args_contains']!r}")

    permissions = settings.get("permissions", {})
    permission_policy = policy.get("permissions", {})
    if permissions.get("defaultMode") != permission_policy.get("default_mode"):
        fail(f"settings.json permissions.defaultMode must be {permission_policy.get('default_mode')!r}")
    allow = permissions.get("allow", [])
    deny = permissions.get("deny", [])
    additional_directories = permissions.get("additionalDirectories", [])
    if len(allow) < permission_policy.get("minimum_allow_count", 0):
        fail("settings.json permissions.allow count is below policy minimum")
    if len(deny) < permission_policy.get("minimum_deny_count", 0):
        fail("settings.json permissions.deny count is below policy minimum")
    missing_directories = [
        item for item in permission_policy.get("required_additional_directories", [])
        if item not in additional_directories
    ]
    if missing_directories:
        fail("settings.json permissions.additionalDirectories missing: " + ", ".join(missing_directories))
    missing_allow = [item for item in permission_policy.get("required_allow", []) if item not in allow]
    if missing_allow:
        fail("settings.json permissions.allow missing required entries: " + ", ".join(missing_allow))
    missing_deny = [item for item in permission_policy.get("required_deny", []) if item not in deny]
    if missing_deny:
        fail("settings.json permissions.deny missing required entries: " + ", ".join(missing_deny))


def validate_hook_consolidation_report(report: dict) -> None:
    candidates = report.get("candidates", [])
    if not isinstance(candidates, list):
        fail("registry/hook-consolidation-candidates.json candidates must be an array")
    if report.get("candidate_count") != len(candidates):
        fail("registry/hook-consolidation-candidates.json candidate_count mismatch")

    risk_counts = {"low": 0, "medium": 0, "high": 0}
    recommendation_counts = {
        "candidate-for-router-or-wrapper": 0,
        "order-review-before-wrapper": 0,
        "manual-review-only": 0,
    }
    required_candidate_fields = [
        "event",
        "matcher",
        "bucket",
        "risk",
        "score",
        "hook_count",
        "first_order",
        "last_order",
        "order_span",
        "contiguous_within_trigger",
        "interleaved_hook_count",
        "interleaved_hooks",
        "recommendation",
        "hooks",
    ]

    for index, candidate in enumerate(candidates):
        missing_fields = [field for field in required_candidate_fields if field not in candidate]
        if missing_fields:
            fail(
                "registry/hook-consolidation-candidates.json candidate "
                f"{index} missing fields: {', '.join(missing_fields)}"
            )
        risk = candidate.get("risk")
        if risk not in risk_counts:
            fail(f"registry/hook-consolidation-candidates.json candidate {index} has invalid risk: {risk}")
        risk_counts[risk] += 1
        recommendation = candidate.get("recommendation")
        if recommendation not in recommendation_counts:
            fail(
                "registry/hook-consolidation-candidates.json candidate "
                f"{index} has invalid recommendation: {recommendation}"
            )
        recommendation_counts[recommendation] += 1

        hooks = candidate.get("hooks", [])
        if not isinstance(hooks, list) or candidate.get("hook_count") != len(hooks):
            fail(f"registry/hook-consolidation-candidates.json candidate {index} hook_count mismatch")
        first_order = candidate.get("first_order")
        last_order = candidate.get("last_order")
        order_span = candidate.get("order_span")
        if not all(isinstance(value, int) for value in [first_order, last_order, order_span]):
            fail(f"registry/hook-consolidation-candidates.json candidate {index} has invalid order metadata")
        if first_order > last_order or order_span != last_order - first_order + 1:
            fail(f"registry/hook-consolidation-candidates.json candidate {index} has inconsistent order span")

        interleaved_hooks = candidate.get("interleaved_hooks", [])
        interleaved_count = candidate.get("interleaved_hook_count")
        if not isinstance(interleaved_hooks, list) or interleaved_count != len(interleaved_hooks):
            fail(f"registry/hook-consolidation-candidates.json candidate {index} interleaved count mismatch")
        contiguous = candidate.get("contiguous_within_trigger")
        if not isinstance(contiguous, bool):
            fail(f"registry/hook-consolidation-candidates.json candidate {index} contiguous flag must be boolean")
        if contiguous and interleaved_count != 0:
            fail(f"registry/hook-consolidation-candidates.json candidate {index} is contiguous but has interleaved hooks")
        if not contiguous and interleaved_count == 0:
            fail(f"registry/hook-consolidation-candidates.json candidate {index} is non-contiguous without interleaved hooks")
        if recommendation == "candidate-for-router-or-wrapper" and not contiguous:
            fail(f"registry/hook-consolidation-candidates.json candidate {index} wrapper-ready item is non-contiguous")
        if recommendation == "order-review-before-wrapper" and (contiguous or risk == "high"):
            fail(f"registry/hook-consolidation-candidates.json candidate {index} has invalid order-review recommendation")
        if recommendation == "manual-review-only" and risk != "high":
            fail(f"registry/hook-consolidation-candidates.json candidate {index} manual-review item is not high risk")

    expected_risk_keys = {
        "low_risk_count": risk_counts["low"],
        "medium_risk_count": risk_counts["medium"],
        "high_risk_count": risk_counts["high"],
    }
    for key, actual in expected_risk_keys.items():
        if report.get(key) != actual:
            fail(f"registry/hook-consolidation-candidates.json {key} mismatch")
    expected_recommendation_keys = {
        "wrapper_ready_count": recommendation_counts["candidate-for-router-or-wrapper"],
        "order_review_count": recommendation_counts["order-review-before-wrapper"],
        "manual_review_count": recommendation_counts["manual-review-only"],
    }
    for key, actual in expected_recommendation_keys.items():
        if report.get(key) != actual:
            fail(f"registry/hook-consolidation-candidates.json {key} mismatch")


def validate_hook_wrapper_plan(plan: dict, consolidation_report: dict) -> None:
    if plan.get("runner") != "scripts/hook-wrapper-runner.py":
        fail("registry/hook-wrapper-plan.json runner must be scripts/hook-wrapper-runner.py")
    if not is_executable(str(plan.get("runner"))):
        fail("scripts/hook-wrapper-runner.py must exist and be executable")
    runner_text = (ROOT / "scripts" / "hook-wrapper-runner.py").read_text(
        encoding="utf-8",
        errors="ignore",
    )
    for fragment in [
        "hook-wrapper-runs.jsonl",
        "--execute",
        "--allow-side-effects",
        "stop_after_blocking_exit",
        "preserve_first_nonzero_exit",
    ]:
        if fragment not in runner_text:
            fail(f"scripts/hook-wrapper-runner.py missing required fragment: {fragment}")
    if plan.get("fixture_file") != "registry/hook-replay-fixtures.json":
        fail("registry/hook-wrapper-plan.json fixture_file must be registry/hook-replay-fixtures.json")
    if not (ROOT / "registry" / "hook-replay-fixtures.json").exists():
        fail("registry/hook-replay-fixtures.json is missing")
    if plan.get("definitions_file") != "registry/hook-wrapper-definitions.json":
        fail("registry/hook-wrapper-plan.json definitions_file must be registry/hook-wrapper-definitions.json")
    if not (ROOT / "registry" / "hook-wrapper-definitions.json").exists():
        fail("registry/hook-wrapper-definitions.json is missing")

    plans = plan.get("plans", [])
    if not isinstance(plans, list):
        fail("registry/hook-wrapper-plan.json plans must be an array")
    if plan.get("wrapper_ready_candidate_count") != consolidation_report.get("wrapper_ready_count"):
        fail("registry/hook-wrapper-plan.json wrapper_ready_candidate_count mismatch")
    if plan.get("plan_count") != len(plans):
        fail("registry/hook-wrapper-plan.json plan_count mismatch")
    if plan.get("definition_count", 0) + plan.get("candidate_plan_count", 0) != len(plans):
        fail("registry/hook-wrapper-plan.json definition/candidate plan count mismatch")

    ids = [item.get("id") for item in plans]
    if len(ids) != len(set(ids)):
        fail("registry/hook-wrapper-plan.json contains duplicate plan ids")
    safe_initial_count = sum(1 for item in plans if item.get("safe_initial_migration"))
    if plan.get("safe_initial_migration_count") != safe_initial_count:
        fail("registry/hook-wrapper-plan.json safe_initial_migration_count mismatch")
    active_definition_count = sum(
        1
        for item in plans
        if item.get("source") == "definition" and item.get("definition_state") == "active"
    )
    planned_definition_count = sum(
        1
        for item in plans
        if item.get("source") == "definition" and item.get("definition_state") == "planned"
    )
    if plan.get("active_definition_count") != active_definition_count:
        fail("registry/hook-wrapper-plan.json active_definition_count mismatch")
    if plan.get("planned_definition_count") != planned_definition_count:
        fail("registry/hook-wrapper-plan.json planned_definition_count mismatch")
    if plan.get("wrapper_ready_candidate_count", 0) > 0 and safe_initial_count <= 0:
        fail("registry/hook-wrapper-plan.json must expose at least one initial migration candidate")

    for index, item in enumerate(plans):
        execution = item.get("execution", [])
        if not execution:
            fail(f"registry/hook-wrapper-plan.json plan {index} has no execution steps")
        source = item.get("source")
        if source not in {"candidate", "definition"}:
            fail(f"registry/hook-wrapper-plan.json plan {index} has invalid source")
        if source == "definition" and item.get("definition_state") not in {"planned", "active"}:
            fail(f"registry/hook-wrapper-plan.json plan {index} has invalid definition_state")
        replacement = item.get("settings_replacement", {})
        if (
            source == "definition"
            and "statusMessage cannot be represented one-for-one in a single settings hook"
            in item.get("risk_notes", [])
        ):
            status_policy = item.get("status_message_policy") or {}
            wrapper_status_message = status_policy.get("wrapper_status_message")
            if not wrapper_status_message:
                fail(f"registry/hook-wrapper-plan.json plan {index} missing status_message_policy")
            if replacement.get("statusMessage") != wrapper_status_message:
                fail(f"registry/hook-wrapper-plan.json plan {index} statusMessage policy mismatch")
        command = str(replacement.get("command", ""))
        if "scripts/hook-wrapper-runner.py" not in command or str(item.get("id")) not in command:
            fail(f"registry/hook-wrapper-plan.json plan {index} replacement command mismatch")
        if "--execute" not in command or "--allow-side-effects" not in command:
            fail(f"registry/hook-wrapper-plan.json plan {index} replacement command must execute side effects")
        dry_run_command = str(replacement.get("dry_run_command", ""))
        if "scripts/hook-wrapper-runner.py" not in dry_run_command or "--execute" in dry_run_command:
            fail(f"registry/hook-wrapper-plan.json plan {index} dry_run_command mismatch")
        timeout_strategy = item.get("timeout_strategy", {})
        step_timeout_sum = sum(int(step.get("timeout_seconds") or 0) for step in execution)
        if timeout_strategy.get("sum_hook_timeouts_seconds") != step_timeout_sum:
            fail(f"registry/hook-wrapper-plan.json plan {index} timeout sum mismatch")
        expected_wrapper_timeout = step_timeout_sum + 2
        if timeout_strategy.get("wrapper_timeout_seconds") != expected_wrapper_timeout:
            fail(f"registry/hook-wrapper-plan.json plan {index} wrapper timeout mismatch")
        if replacement.get("timeout") != expected_wrapper_timeout:
            fail(f"registry/hook-wrapper-plan.json plan {index} settings timeout mismatch")
        orders = [step.get("order") for step in execution]
        if orders != sorted(orders):
            fail(f"registry/hook-wrapper-plan.json plan {index} execution order is not sorted")
        if item.get("safe_initial_migration"):
            if item.get("risk_notes") != ["candidate risk is medium"]:
                fail(f"registry/hook-wrapper-plan.json plan {index} has unexpected safe migration notes")
            if any(step.get("blocking") or step.get("calls_llm") for step in execution):
                fail(f"registry/hook-wrapper-plan.json plan {index} safe migration contains blocking or LLM step")
        if any(step.get("blocking") for step in execution):
            execution_contract = item.get("execution_contract") or {}
            if not execution_contract.get("preserve_first_nonzero_exit"):
                fail(
                    f"registry/hook-wrapper-plan.json plan {index} with blocking steps "
                    "must preserve first nonzero exit"
                )
            if not execution_contract.get("stop_after_blocking_exit"):
                fail(
                    f"registry/hook-wrapper-plan.json plan {index} with blocking steps "
                    "must stop after blocking exit"
                )
            if not execution_contract.get("reason"):
                fail(f"registry/hook-wrapper-plan.json plan {index} missing execution_contract.reason")

    overlaps = plan.get("overlaps", [])
    if not isinstance(overlaps, list) or plan.get("overlap_count") != len(overlaps):
        fail("registry/hook-wrapper-plan.json overlap_count mismatch")


def validate_hook_wrapper_decisions(decisions: dict, wrapper_plan: dict) -> int:
    if decisions.get("version") != 1:
        fail("registry/hook-wrapper-decision-log.json version must be 1")
    items = decisions.get("decisions", [])
    if not isinstance(items, list):
        fail("registry/hook-wrapper-decision-log.json decisions must be an array")
    if decisions.get("decision_count") != len(items):
        fail("registry/hook-wrapper-decision-log.json decision_count mismatch")

    candidate_plan_ids = {
        str(plan.get("id"))
        for plan in wrapper_plan.get("plans", [])
        if plan.get("source") == "candidate"
    }
    decision_ids = {
        str(item.get("plan_id"))
        for item in items
        if item.get("plan_id")
    }
    missing = sorted(candidate_plan_ids - decision_ids)
    if missing:
        fail(
            "registry/hook-wrapper-decision-log.json missing candidate plan decisions: "
            + ", ".join(missing)
        )
    unknown = sorted(decision_ids - candidate_plan_ids)
    if unknown:
        fail(
            "registry/hook-wrapper-decision-log.json contains stale plan decisions: "
            + ", ".join(unknown)
        )

    allowed_decisions = {"defer", "promote-to-planned", "reject"}
    for index, item in enumerate(items):
        for field in [
            "plan_id",
            "event",
            "matcher",
            "bucket",
            "decision",
            "status",
            "reviewed_at",
            "blockers",
            "reason",
            "next_action",
        ]:
            if field not in item:
                fail(f"registry/hook-wrapper-decision-log.json decision {index} missing {field}")
        if item.get("decision") not in allowed_decisions:
            fail(f"registry/hook-wrapper-decision-log.json decision {index} has invalid decision")
        if not isinstance(item.get("blockers"), list) or not item.get("blockers"):
            fail(f"registry/hook-wrapper-decision-log.json decision {index} missing blockers")
        if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(item.get("reviewed_at"))):
            fail(f"registry/hook-wrapper-decision-log.json decision {index} reviewed_at must be YYYY-MM-DD")
        plan = next(
            plan
            for plan in wrapper_plan.get("plans", [])
            if str(plan.get("id")) == str(item.get("plan_id"))
        )
        for field in ["event", "matcher", "bucket"]:
            if item.get(field) != plan.get(field):
                fail(
                    "registry/hook-wrapper-decision-log.json decision "
                    f"{index} {field} differs from wrapper plan"
                )
    return len(items)


def validate_pretooluse_guard_policy(
    decisions: dict,
    wrapper_plan: dict,
    inventory_hooks: list[dict],
) -> int:
    policy = decisions.get("pretooluse_guard_policy")
    if not isinstance(policy, dict):
        fail("registry/hook-wrapper-decision-log.json missing pretooluse_guard_policy")
    if policy.get("version") != 1:
        fail("registry/hook-wrapper-decision-log.json pretooluse_guard_policy version must be 1")
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", str(policy.get("reviewed_at"))):
        fail("registry/hook-wrapper-decision-log.json pretooluse_guard_policy reviewed_at must be YYYY-MM-DD")
    items = policy.get("decisions", [])
    if not isinstance(items, list) or not items:
        fail("registry/hook-wrapper-decision-log.json pretooluse_guard_policy decisions must be non-empty")
    if policy.get("decision_count") != len(items):
        fail("registry/hook-wrapper-decision-log.json pretooluse_guard_policy decision_count mismatch")

    definition_states = {
        str(plan.get("id")): plan.get("definition_state")
        for plan in wrapper_plan.get("plans", [])
        if plan.get("source") == "definition" and plan.get("id")
    }
    allowed_decisions = {"active-wrapper", "planned-wrapper", "keep-direct"}
    covered: set[tuple[str, str]] = set()

    for index, item in enumerate(items):
        for field in ["matcher", "decision", "status", "scripts", "reason", "next_action"]:
            if field not in item:
                fail(
                    "registry/hook-wrapper-decision-log.json "
                    f"pretooluse_guard_policy decision {index} missing {field}"
                )
        decision = item.get("decision")
        if decision not in allowed_decisions:
            fail(
                "registry/hook-wrapper-decision-log.json "
                f"pretooluse_guard_policy decision {index} has invalid decision"
            )
        scripts = item.get("scripts")
        if not isinstance(scripts, list) or not scripts:
            fail(
                "registry/hook-wrapper-decision-log.json "
                f"pretooluse_guard_policy decision {index} missing scripts"
            )
        matcher = str(item.get("matcher"))
        wrapper_id = item.get("wrapper_id")
        if decision in {"active-wrapper", "planned-wrapper"}:
            if not wrapper_id:
                fail(
                    "registry/hook-wrapper-decision-log.json "
                    f"pretooluse_guard_policy decision {index} missing wrapper_id"
                )
            expected_state = "active" if decision == "active-wrapper" else "planned"
            if definition_states.get(str(wrapper_id)) != expected_state:
                fail(
                    "registry/hook-wrapper-decision-log.json "
                    f"pretooluse_guard_policy decision {index} wrapper state mismatch"
                )
        elif wrapper_id not in (None, ""):
            fail(
                "registry/hook-wrapper-decision-log.json "
                f"pretooluse_guard_policy decision {index} keep-direct must not set wrapper_id"
            )
        for script in scripts:
            covered.add((matcher, str(script)))

    def scripts_for_hook(hook: dict) -> list[str]:
        wrapped = [script for script in hook.get("wrapped_scripts", []) if script]
        if wrapped:
            return wrapped
        script = hook.get("script")
        return [script] if script else []

    current = {
        (str(hook.get("matcher")), script)
        for hook in inventory_hooks
        if hook.get("event") == "PreToolUse"
        for script in scripts_for_hook(hook)
    }
    missing = sorted(current - covered)
    if missing:
        fail(
            "registry/hook-wrapper-decision-log.json pretooluse_guard_policy missing current hooks: "
            + ", ".join(f"{matcher}/{script}" for matcher, script in missing)
        )
    stale = sorted(covered - current)
    if stale:
        fail(
            "registry/hook-wrapper-decision-log.json pretooluse_guard_policy contains stale hooks: "
            + ", ".join(f"{matcher}/{script}" for matcher, script in stale)
        )
    return len(items)


def validate_hook_wrapper_activation_gates(
    gates: dict,
    wrapper_plan: dict,
    fixtures: dict,
) -> int:
    if gates.get("version") != 1:
        fail("registry/hook-wrapper-activation-gates.json version must be 1")
    items = gates.get("gates", [])
    if not isinstance(items, list):
        fail("registry/hook-wrapper-activation-gates.json gates must be an array")
    if gates.get("gate_count") != len(items):
        fail("registry/hook-wrapper-activation-gates.json gate_count mismatch")

    planned_plans = {
        str(plan.get("id")): plan
        for plan in wrapper_plan.get("plans", [])
        if plan.get("source") == "definition"
        and plan.get("definition_state") == "planned"
    }
    gate_ids = {
        str(item.get("plan_id"))
        for item in items
        if item.get("plan_id")
    }
    missing = sorted(set(planned_plans) - gate_ids)
    if missing:
        fail(
            "registry/hook-wrapper-activation-gates.json missing planned wrapper gates: "
            + ", ".join(missing)
        )
    unknown = sorted(gate_ids - set(planned_plans))
    if unknown:
        fail(
            "registry/hook-wrapper-activation-gates.json contains stale gates: "
            + ", ".join(unknown)
        )

    fixture_by_id = {
        str(item.get("id")): item
        for item in fixtures.get("fixtures", [])
        if item.get("id")
    }
    allowed_states = {
        "blocked-pending-isolated-execute-validation",
        "ready-for-settings-migration",
        "rejected",
    }
    allowed_validation_modes = {"dry-run-only", "isolated-execute-required", "ready"}
    for index, item in enumerate(items):
        for field in [
            "plan_id",
            "event",
            "matcher",
            "activation_state",
            "validation_mode",
            "dry_run_fixtures",
            "risk_reasons",
            "forbidden_execution",
            "required_before_activation",
            "current_evidence",
        ]:
            if field not in item:
                fail(f"registry/hook-wrapper-activation-gates.json gate {index} missing {field}")
        if item.get("activation_state") not in allowed_states:
            fail(f"registry/hook-wrapper-activation-gates.json gate {index} has invalid activation_state")
        if item.get("validation_mode") not in allowed_validation_modes:
            fail(f"registry/hook-wrapper-activation-gates.json gate {index} has invalid validation_mode")
        for list_field in [
            "dry_run_fixtures",
            "risk_reasons",
            "forbidden_execution",
            "required_before_activation",
            "current_evidence",
        ]:
            if not isinstance(item.get(list_field), list) or not item.get(list_field):
                fail(f"registry/hook-wrapper-activation-gates.json gate {index} missing {list_field}")

        plan = planned_plans[str(item.get("plan_id"))]
        for field in ["event", "matcher"]:
            if item.get(field) != plan.get(field):
                fail(
                    "registry/hook-wrapper-activation-gates.json gate "
                    f"{index} {field} differs from wrapper plan"
                )
        if any(step.get("calls_llm") for step in plan.get("execution", [])):
            if "contains-llm-backed-step" not in item.get("risk_reasons", []):
                fail(f"registry/hook-wrapper-activation-gates.json gate {index} missing LLM risk")
            if "no-unstubbed-llm-execute" not in item.get("forbidden_execution", []):
                fail(f"registry/hook-wrapper-activation-gates.json gate {index} missing LLM execute ban")
        if any(step.get("blocking") for step in plan.get("execution", [])):
            if "contains-blocking-step" not in item.get("risk_reasons", []):
                fail(f"registry/hook-wrapper-activation-gates.json gate {index} missing blocking risk")
        for fixture_id in item.get("dry_run_fixtures", []):
            fixture = fixture_by_id.get(str(fixture_id))
            if fixture is None:
                fail(f"registry/hook-wrapper-activation-gates.json gate {index} missing fixture {fixture_id}")
            if fixture.get("event") != item.get("event") or fixture.get("matcher") != item.get("matcher"):
                fail(
                    "registry/hook-wrapper-activation-gates.json gate "
                    f"{index} fixture {fixture_id} trigger mismatch"
                )
    return len(items)


def validate_hook_wrapper_activation_report(report: dict, gates: dict) -> int:
    if report.get("version") != 1:
        fail("registry/hook-wrapper-activation-report.json version must be 1")
    if report.get("runner") != "scripts/hook-wrapper-runner.py":
        fail("registry/hook-wrapper-activation-report.json runner mismatch")
    if report.get("status") != "pass":
        fail("registry/hook-wrapper-activation-report.json status must be pass")
    if report.get("failed_validation_count") != 0:
        fail("registry/hook-wrapper-activation-report.json failed_validation_count must be 0")
    gate_items = gates.get("gates", [])
    report_items = report.get("gates", [])
    if not isinstance(report_items, list):
        fail("registry/hook-wrapper-activation-report.json gates must be an array")
    if report.get("gate_count") != len(report_items):
        fail("registry/hook-wrapper-activation-report.json gate_count mismatch")
    if report.get("gate_count") != len(gate_items):
        fail("registry/hook-wrapper-activation-report.json gate_count differs from activation gates")

    gate_by_id = {str(item.get("plan_id")): item for item in gate_items}
    report_by_id = {str(item.get("plan_id")): item for item in report_items}
    if set(gate_by_id) != set(report_by_id):
        fail("registry/hook-wrapper-activation-report.json gate ids differ from activation gates")

    validation_count = 0
    for index, item in enumerate(report_items):
        plan_id = str(item.get("plan_id"))
        gate = gate_by_id[plan_id]
        if item.get("event") != gate.get("event") or item.get("matcher") != gate.get("matcher"):
            fail(f"registry/hook-wrapper-activation-report.json gate {index} trigger mismatch")
        if item.get("activation_state") != gate.get("activation_state"):
            fail(f"registry/hook-wrapper-activation-report.json gate {index} activation_state mismatch")
        if item.get("validation_mode") != gate.get("validation_mode"):
            fail(f"registry/hook-wrapper-activation-report.json gate {index} validation_mode mismatch")
        fixture_results = item.get("fixture_results", [])
        if not isinstance(fixture_results, list):
            fail(f"registry/hook-wrapper-activation-report.json gate {index} fixture_results must be an array")
        if item.get("fixture_count") != len(fixture_results):
            fail(f"registry/hook-wrapper-activation-report.json gate {index} fixture_count mismatch")
        if item.get("fixture_count") != len(gate.get("dry_run_fixtures", [])):
            fail(f"registry/hook-wrapper-activation-report.json gate {index} fixture_count differs from gate")
        if item.get("status") != "pass":
            fail(f"registry/hook-wrapper-activation-report.json gate {index} status must be pass")
        validation_count += len(fixture_results)
        for fixture_index, fixture in enumerate(fixture_results):
            if fixture.get("status") != "pass":
                fail(
                    "registry/hook-wrapper-activation-report.json "
                    f"gate {index} fixture {fixture_index} status must be pass"
                )
            if fixture.get("failures") not in ([], None):
                fail(
                    "registry/hook-wrapper-activation-report.json "
                    f"gate {index} fixture {fixture_index} has failures"
                )
            if not fixture.get("orders") or fixture.get("orders") != sorted(fixture.get("orders")):
                fail(
                    "registry/hook-wrapper-activation-report.json "
                    f"gate {index} fixture {fixture_index} orders invalid"
                )
    if report.get("validation_count") != validation_count:
        fail("registry/hook-wrapper-activation-report.json validation_count mismatch")
    return validation_count


def validate_hook_wrapper_isolated_execute_report(report: dict) -> int:
    if report.get("version") != 1:
        fail("registry/hook-wrapper-isolated-execute-report.json version must be 1")
    if report.get("runner") != "scripts/hook-wrapper-runner.py":
        fail("registry/hook-wrapper-isolated-execute-report.json runner mismatch")
    if report.get("status") != "pass":
        fail("registry/hook-wrapper-isolated-execute-report.json status must be pass")
    if report.get("failed_scenario_count") != 0:
        fail("registry/hook-wrapper-isolated-execute-report.json failed_scenario_count must be 0")
    boundary = report.get("side_effect_boundary", {})
    for field in ["home", "cwd", "path", "llm"]:
        if not boundary.get(field):
            fail(f"registry/hook-wrapper-isolated-execute-report.json missing boundary {field}")

    scenarios = report.get("scenarios", [])
    if not isinstance(scenarios, list) or not scenarios:
        fail("registry/hook-wrapper-isolated-execute-report.json scenarios must be a non-empty array")
    if report.get("scenario_count") != len(scenarios):
        fail("registry/hook-wrapper-isolated-execute-report.json scenario_count mismatch")
    required_scenarios = {
        "git-commit-non-korean-block",
        "git-commit-coauthor-block",
        "gh-pr-create-safe-skip",
        "edit-write-large-direct-block",
        "agent-reviewer-safe-stubbed",
    }
    scenario_ids = {str(item.get("id")) for item in scenarios}
    missing_scenarios = sorted(required_scenarios - scenario_ids)
    if missing_scenarios:
        fail(
            "registry/hook-wrapper-isolated-execute-report.json missing scenarios: "
            + ", ".join(missing_scenarios)
        )
    for index, item in enumerate(scenarios):
        for field in [
            "id",
            "plan_id",
            "status",
            "expected_exit_code",
            "actual_exit_code",
            "expected_executed_step_count",
            "actual_executed_step_count",
            "steps",
            "failures",
        ]:
            if field not in item:
                fail(f"registry/hook-wrapper-isolated-execute-report.json scenario {index} missing {field}")
        if item.get("status") != "pass":
            fail(f"registry/hook-wrapper-isolated-execute-report.json scenario {index} status must be pass")
        if item.get("failures") not in ([], None):
            fail(f"registry/hook-wrapper-isolated-execute-report.json scenario {index} has failures")
        if item.get("actual_exit_code") != item.get("expected_exit_code"):
            fail(f"registry/hook-wrapper-isolated-execute-report.json scenario {index} exit mismatch")
        if item.get("actual_executed_step_count") != item.get("expected_executed_step_count"):
            fail(f"registry/hook-wrapper-isolated-execute-report.json scenario {index} step count mismatch")
        steps = item.get("steps", [])
        if not isinstance(steps, list) or len(steps) != item.get("actual_executed_step_count"):
            fail(f"registry/hook-wrapper-isolated-execute-report.json scenario {index} steps mismatch")
        if item.get("actual_blocked_hook_id") != item.get("expected_blocked_hook_id"):
            fail(f"registry/hook-wrapper-isolated-execute-report.json scenario {index} blocked hook mismatch")
        if any(step.get("timed_out") for step in steps):
            fail(f"registry/hook-wrapper-isolated-execute-report.json scenario {index} timed out")
    return len(scenarios)


def validate_active_hook_wrappers(plan: dict, hooks: list[dict]) -> None:
    for item in plan.get("plans", []):
        if item.get("source") != "definition" or item.get("definition_state") != "active":
            continue
        wrapper_id = str(item.get("id"))
        event = item.get("event")
        matcher = item.get("matcher")
        wrapper_command_fragment = (
            f"hook-wrapper-runner.py {wrapper_id} --execute --allow-side-effects"
        )
        matching_wrappers = [
            hook
            for hook in hooks
            if hook.get("event") == event
            and hook.get("matcher") == matcher
            and wrapper_command_fragment in hook.get("command", "")
        ]
        if len(matching_wrappers) != 1:
            fail(
                "active hook wrapper must have exactly one settings hook: "
                f"{event}/{matcher}/{wrapper_id}"
            )
        original_commands = {step.get("command") for step in item.get("execution", [])}
        still_registered = [
            hook.get("command", "")
            for hook in hooks
            if hook.get("event") == event
            and hook.get("matcher") == matcher
            and hook.get("command") in original_commands
        ]
        if still_registered:
            fail(
                "active hook wrapper still has original commands registered in settings: "
                + ", ".join(still_registered[:5])
            )


def validate_hook_replay_fixtures(fixtures: dict, wrapper_plan: dict) -> None:
    items = fixtures.get("fixtures", [])
    if not isinstance(items, list) or not items:
        fail("registry/hook-replay-fixtures.json fixtures must be a non-empty array")
    ids = [item.get("id") for item in items]
    if len(ids) != len(set(ids)):
        fail("registry/hook-replay-fixtures.json contains duplicate fixture ids")
    covered_triggers = set()
    for index, item in enumerate(items):
        if not item.get("id"):
            fail(f"registry/hook-replay-fixtures.json fixture {index} missing id")
        if not item.get("event"):
            fail(f"registry/hook-replay-fixtures.json fixture {index} missing event")
        if "matcher" not in item:
            fail(f"registry/hook-replay-fixtures.json fixture {index} missing matcher")
        payload = item.get("payload")
        if not isinstance(payload, dict):
            fail(f"registry/hook-replay-fixtures.json fixture {index} payload must be an object")
        json.dumps(payload, ensure_ascii=False)
        covered_triggers.add((item.get("event"), item.get("matcher")))

    required_triggers = {
        (plan.get("event"), plan.get("matcher"))
        for plan in wrapper_plan.get("plans", [])
    }
    missing = sorted(required_triggers - covered_triggers)
    if missing:
        fail(
            "registry/hook-replay-fixtures.json missing fixtures for wrapper triggers: "
            + ", ".join(f"{event}/{matcher}" for event, matcher in missing)
        )


def validate_hook_order_review(review: dict, wrapper_plan: dict, consolidation_report: dict) -> None:
    required_keys = [
        "active_wrapper_count",
        "wrapper_review_count",
        "order_review_count",
        "manual_review_count",
        "review_item_count",
        "blocker_counts",
        "strategy_counts",
        "active_wrappers",
        "wrapper_review_items",
        "order_review_items",
        "manual_review_items",
    ]
    missing_keys = [key for key in required_keys if key not in review]
    if missing_keys:
        fail("registry/hook-order-review.json missing keys: " + ", ".join(missing_keys))

    active_wrappers = review.get("active_wrappers", [])
    wrapper_review_items = review.get("wrapper_review_items", [])
    order_review_items = review.get("order_review_items", [])
    manual_review_items = review.get("manual_review_items", [])
    if review.get("active_wrapper_count") != len(active_wrappers):
        fail("registry/hook-order-review.json active_wrapper_count mismatch")
    if review.get("wrapper_review_count") != len(wrapper_review_items):
        fail("registry/hook-order-review.json wrapper_review_count mismatch")
    if review.get("order_review_count") != len(order_review_items):
        fail("registry/hook-order-review.json order_review_count mismatch")
    if review.get("manual_review_count") != len(manual_review_items):
        fail("registry/hook-order-review.json manual_review_count mismatch")
    if review.get("review_item_count") != (
        len(wrapper_review_items) + len(order_review_items) + len(manual_review_items)
    ):
        fail("registry/hook-order-review.json review_item_count mismatch")
    if review.get("active_wrapper_count") != wrapper_plan.get("active_definition_count"):
        fail("registry/hook-order-review.json active wrapper count differs from wrapper plan")
    if review.get("wrapper_review_count") != wrapper_plan.get("candidate_plan_count"):
        fail("registry/hook-order-review.json wrapper review count differs from wrapper plan")
    if review.get("order_review_count") != consolidation_report.get("order_review_count"):
        fail("registry/hook-order-review.json order review count differs from consolidation report")
    if review.get("manual_review_count") != consolidation_report.get("manual_review_count"):
        fail("registry/hook-order-review.json manual review count differs from consolidation report")

    for collection_name in ["wrapper_review_items", "order_review_items", "manual_review_items"]:
        for index, item in enumerate(review.get(collection_name, [])):
            if not item.get("blockers"):
                fail(f"registry/hook-order-review.json {collection_name}[{index}] missing blockers")
            if not item.get("strategy"):
                fail(f"registry/hook-order-review.json {collection_name}[{index}] missing strategy")
            if not item.get("next_action"):
                fail(f"registry/hook-order-review.json {collection_name}[{index}] missing next_action")


def validate_hook_output_contracts(contracts: dict, inventory_hooks: list[dict]) -> dict[str, int]:
    if contracts.get("version") != 1:
        fail("registry/hook-output-contracts.json version must be 1")
    contract_items = contracts.get("contracts", [])
    if not isinstance(contract_items, list) or not contract_items:
        fail("registry/hook-output-contracts.json contracts must be a non-empty array")

    stop_contracts = [item for item in contract_items if item.get("event") == "Stop"]
    if len(stop_contracts) != 1:
        fail("registry/hook-output-contracts.json must define exactly one Stop contract")
    stop_contract = stop_contracts[0]
    rules = stop_contract.get("rules", {})
    required_behaviors = set(rules.get("required_wrapper_behaviors", []))
    for behavior in [
        "stdin-replay-once-per-child",
        "per-child-timeout",
        "stdout-stderr-passthrough",
        "fail-open-unless-explicitly-documented",
    ]:
        if behavior not in required_behaviors:
            fail(f"Stop output contract missing required wrapper behavior: {behavior}")

    hook_contracts = stop_contract.get("hooks", [])
    if not isinstance(hook_contracts, list) or not hook_contracts:
        fail("Stop output contract hooks must be a non-empty array")
    by_script = {item.get("script"): item for item in hook_contracts if item.get("script")}
    if len(by_script) != len(hook_contracts):
        fail("Stop output contract contains duplicate or missing script entries")

    def contract_scripts_for_hook(hook: dict) -> list[str]:
        wrapped_scripts = [
            script for script in hook.get("wrapped_scripts", []) if script
        ]
        if wrapped_scripts:
            return wrapped_scripts
        script = hook.get("script")
        return [script] if script else []

    current_stop_scripts = {
        script
        for hook in inventory_hooks
        if hook.get("event") == "Stop"
        for script in contract_scripts_for_hook(hook)
    }
    missing = sorted(current_stop_scripts - set(by_script))
    if missing:
        fail("Stop output contract missing current hooks: " + ", ".join(missing))

    allowed_policies = {
        "composite-stop-router-planned",
        "background-wrapper-candidate",
        "keep-direct-until-notification-router",
        "keep-direct-until-output-router",
        "notification-router-candidate",
        "output-preserving-wrapper-candidate",
        "status-aware-background-wrapper-candidate",
    }
    user_visible_count = 0
    for hook in inventory_hooks:
        if hook.get("event") != "Stop":
            continue
        for script in contract_scripts_for_hook(hook):
            item = by_script[script]
            for field in [
                "stdout",
                "stderr",
                "status_message",
                "user_visible",
                "visible_channels",
                "migration_policy",
                "wrapper_requirements",
                "notes",
            ]:
                if field not in item:
                    fail(f"Stop output contract for {script} missing {field}")
            if item.get("migration_policy") not in allowed_policies:
                fail(f"Stop output contract for {script} has invalid migration_policy")
            wrapper_requirements = set(item.get("wrapper_requirements", []))
            if "per-child-timeout" not in wrapper_requirements:
                fail(f"Stop output contract for {script} missing per-child-timeout")
            if item.get("stdout") != "none" or item.get("stderr") != "none":
                if "stdout-stderr-passthrough" not in wrapper_requirements:
                    fail(f"Stop output contract for {script} must preserve stdout/stderr")
            if item.get("status_message") and "status-message-policy-for-status-hooks" not in wrapper_requirements:
                fail(f"Stop output contract for {script} status hook missing status-message-policy")
            if item.get("user_visible"):
                user_visible_count += 1

    for hook in inventory_hooks:
        if hook.get("event") != "Stop" or hook.get("wrapped_scripts"):
            continue
        item = by_script[hook["script"]]
        for field in [
            "status_message",
        ]:
            if hook.get(field) != item.get(field):
                fail(f"Stop output contract for {hook['script']} {field} mismatch")

    pre_contracts = [item for item in contract_items if item.get("event") == "PreToolUse"]
    if len(pre_contracts) != 1:
        fail("registry/hook-output-contracts.json must define exactly one PreToolUse contract")
    pre_contract = pre_contracts[0]
    pre_rules = pre_contract.get("rules", {})
    pre_required_behaviors = set(pre_rules.get("required_wrapper_behaviors", []))
    for behavior in [
        "stdin-replay-once-per-child",
        "per-child-timeout",
        "stdout-stderr-passthrough",
        "preserve-first-nonzero-exit",
        "stop-after-blocking-exit",
    ]:
        if behavior not in pre_required_behaviors:
            fail(f"PreToolUse output contract missing required wrapper behavior: {behavior}")

    pre_hook_contracts = pre_contract.get("hooks", [])
    if not isinstance(pre_hook_contracts, list) or not pre_hook_contracts:
        fail("PreToolUse output contract hooks must be a non-empty array")
    by_pre_key = {
        (item.get("matcher"), item.get("script")): item
        for item in pre_hook_contracts
        if item.get("matcher") is not None and item.get("script")
    }
    if len(by_pre_key) != len(pre_hook_contracts):
        fail("PreToolUse output contract contains duplicate or missing matcher/script entries")

    current_pre_keys = {
        (hook.get("matcher"), script)
        for hook in inventory_hooks
        if hook.get("event") == "PreToolUse"
        for script in contract_scripts_for_hook(hook)
    }
    missing_pre = sorted(current_pre_keys - set(by_pre_key))
    if missing_pre:
        fail(
            "PreToolUse output contract missing current hooks: "
            + ", ".join(f"{matcher}/{script}" for matcher, script in missing_pre)
        )

    allowed_pre_policies = {
        "blocking-router-candidate",
        "keep-direct-hardware-bug-guard",
        "keep-direct-until-mcp-router",
        "notification-router-candidate",
        "output-preserving-wrapper-candidate",
        "status-aware-output-wrapper-candidate",
    }
    pre_blocking_contracts = 0
    for hook in inventory_hooks:
        if hook.get("event") != "PreToolUse":
            continue
        for script in contract_scripts_for_hook(hook):
            item = by_pre_key[(hook.get("matcher"), script)]
            for field in [
                "blocks_tool",
                "exit_contract",
                "stdout",
                "stderr",
                "status_message",
                "user_visible",
                "visible_channels",
                "migration_policy",
                "wrapper_requirements",
                "notes",
            ]:
                if field not in item:
                    fail(f"PreToolUse output contract for {hook['matcher']}/{script} missing {field}")
            if item.get("migration_policy") not in allowed_pre_policies:
                fail(f"PreToolUse output contract for {hook['matcher']}/{script} has invalid migration_policy")
            wrapper_requirements = set(item.get("wrapper_requirements", []))
            if "per-child-timeout" not in wrapper_requirements:
                fail(f"PreToolUse output contract for {hook['matcher']}/{script} missing per-child-timeout")
            if item.get("stdout") != "none" or item.get("stderr") != "none":
                if "stdout-stderr-passthrough" not in wrapper_requirements:
                    fail(f"PreToolUse output contract for {hook['matcher']}/{script} must preserve stdout/stderr")
            if item.get("blocks_tool"):
                pre_blocking_contracts += 1
                for requirement in ["preserve-first-nonzero-exit", "stop-after-blocking-exit"]:
                    if requirement not in wrapper_requirements:
                        fail(
                            f"PreToolUse blocking contract for {hook['matcher']}/{script} "
                            f"missing {requirement}"
                        )
            script_text = read_text(str(script))
            if "llm-call.sh" in script_text and "adapter-telemetry" not in wrapper_requirements:
                fail(f"PreToolUse output contract for {hook['matcher']}/{script} LLM hook missing adapter-telemetry")

    for hook in inventory_hooks:
        if hook.get("event") != "PreToolUse" or hook.get("wrapped_scripts"):
            continue
        item = by_pre_key[(hook.get("matcher"), hook.get("script"))]
        if hook.get("status_message") != item.get("status_message"):
            fail(f"PreToolUse output contract for {hook['matcher']}/{hook['script']} status_message mismatch")

    return {
        "stop_contract_hooks": len(current_stop_scripts),
        "stop_user_visible_hooks": user_visible_count,
        "pretool_contract_hooks": len(current_pre_keys),
        "pretool_blocking_contracts": pre_blocking_contracts,
    }


def validate_presentation_pipeline(pipeline: dict) -> None:
    if pipeline.get("version") != 1:
        fail("registry/presentation-pipeline.json version must be 1")
    if pipeline.get("status") != "active":
        fail("registry/presentation-pipeline.json status must be active")

    generated_input = pipeline.get("generated_diagram_input")
    if generated_input != "cache/generated-docs/claude-architecture-diagrams.generated.md":
        fail("registry/presentation-pipeline.json generated_diagram_input mismatch")
    if not (ROOT / generated_input).exists():
        fail("registry/presentation-pipeline.json generated_diagram_input does not exist")

    for document in pipeline.get("source_documents", []):
        if not (ROOT / document).exists():
            fail(f"registry/presentation-pipeline.json source document does not exist: {document}")

    consumers = pipeline.get("consumers")
    if not isinstance(consumers, list) or not consumers:
        fail("registry/presentation-pipeline.json consumers must be a non-empty array")
    if not any(item.get("format") == "pptx" for item in consumers):
        fail("registry/presentation-pipeline.json must declare a pptx consumer")
    if not any(item.get("type") == "markdown-document" for item in consumers):
        fail("registry/presentation-pipeline.json must declare a markdown-document consumer")
    for item in consumers:
        if item.get("input") != generated_input:
            fail("registry/presentation-pipeline.json consumer input must use generated diagram file")

    stale_checks = set(pipeline.get("stale_checks", []))
    for required in [
        "scripts/generate-architecture-diagrams.py",
        "scripts/audit-claude-config.py",
    ]:
        if required not in stale_checks:
            fail(f"registry/presentation-pipeline.json missing stale check: {required}")
    if pipeline.get("manual_copy_policy") != "forbidden":
        fail("registry/presentation-pipeline.json manual_copy_policy must be forbidden")


def main() -> int:
    settings = load_json("settings.json")
    mcp = load_json(".mcp.json")
    hook_policy = load_json("registry/hook-policy.json")
    hook_timeout_policy = load_json("registry/hook-timeout-policy.json")
    settings_policy = load_json("registry/settings-policy.json")
    llm_adapter_policy = load_json("registry/llm-adapter-policy.json")
    llm_log_schema = load_json("registry/llm-log-schema.json")
    llm_adapter_thresholds = load_json("registry/llm-adapter-thresholds.json")
    hook_manifest = load_json("registry/hooks-manifest.json")
    hook_inventory = load_json("registry/hooks-inventory.json")
    hook_consolidation = load_json("registry/hook-consolidation-candidates.json")
    hook_wrapper_plan = load_json("registry/hook-wrapper-plan.json")
    hook_wrapper_decisions = load_json("registry/hook-wrapper-decision-log.json")
    hook_wrapper_activation_gates = load_json("registry/hook-wrapper-activation-gates.json")
    hook_wrapper_activation_report = load_json("registry/hook-wrapper-activation-report.json")
    hook_wrapper_isolated_execute_report = load_json("registry/hook-wrapper-isolated-execute-report.json")
    hook_replay_fixtures = load_json("registry/hook-replay-fixtures.json")
    hook_order_review = load_json("registry/hook-order-review.json")
    hook_output_contracts = load_json("registry/hook-output-contracts.json")
    llm_calls_inventory = load_json("registry/llm-calls-inventory.json")
    llm_routing = load_json("registry/llm-routing.json")
    presentation_pipeline = load_json("registry/presentation-pipeline.json")
    validate_settings_policy(settings, mcp, settings_policy)

    hooks = flatten_hooks(settings)
    inventory_hooks = hook_inventory.get("hooks", [])
    settings_hooks = settings.get("hooks", {})
    if hook_manifest.get("generated_from") != "settings.json:hooks":
        fail("registry/hooks-manifest.json generated_from must be settings.json:hooks during transition")
    if hook_manifest.get("projection_target") != "settings.json:hooks":
        fail("registry/hooks-manifest.json projection_target must be settings.json:hooks")
    if hook_manifest.get("hooks") != settings_hooks:
        fail("registry/hooks-manifest.json hooks differ from settings.json hooks")
    if hook_manifest.get("hook_count") != settings_hook_count(settings_hooks):
        fail("registry/hooks-manifest.json hook_count mismatch")
    generated_hook_manifest = generated_json_from_script("generate-hook-manifest.py")
    if generated_hook_manifest != hook_manifest:
        fail("registry/hooks-manifest.json differs from generator output")
    if not is_executable("scripts/project-settings-from-registry.py"):
        fail("scripts/project-settings-from-registry.py must exist and be executable")
    projected_settings = generated_json_from_script("project-settings-from-registry.py")
    if projected_settings != settings:
        fail("settings.json differs from registry projection; run scripts/project-settings-from-registry.py --write")
    if hook_inventory.get("generated_from") != "settings.json":
        fail("registry/hooks-inventory.json generated_from must be settings.json")
    if hook_inventory.get("hook_count") != len(hooks):
        fail(
            "registry/hooks-inventory.json hook_count mismatch: "
            f"inventory={hook_inventory.get('hook_count')} settings={len(hooks)}"
        )
    if comparable_hooks(inventory_hooks) != comparable_hooks(hooks):
        fail("registry/hooks-inventory.json is stale; run scripts/generate-hook-inventory.py --write")
    generated_hook_inventory = generated_json_from_script("generate-hook-inventory.py")
    if generated_hook_inventory != hook_inventory:
        fail("registry/hooks-inventory.json differs from generator output")
    generated_hook_consolidation = generated_json_from_script("generate-hook-consolidation-candidates.py")
    if generated_hook_consolidation != hook_consolidation:
        fail(
            "registry/hook-consolidation-candidates.json is stale; "
            "run scripts/generate-hook-consolidation-candidates.py --write"
        )
    if hook_consolidation.get("generated_from") != "registry/hooks-inventory.json":
        fail("registry/hook-consolidation-candidates.json generated_from must be registry/hooks-inventory.json")
    if hook_consolidation.get("hook_count") != hook_inventory.get("hook_count"):
        fail("registry/hook-consolidation-candidates.json hook_count mismatch")
    if hook_consolidation.get("candidate_count", 0) <= 0:
        fail("registry/hook-consolidation-candidates.json must contain at least one candidate")
    validate_hook_consolidation_report(hook_consolidation)
    if not is_executable("scripts/generate-hook-wrapper-plan.py"):
        fail("scripts/generate-hook-wrapper-plan.py must exist and be executable")
    generated_hook_wrapper_plan = generated_json_from_script("generate-hook-wrapper-plan.py")
    if generated_hook_wrapper_plan != hook_wrapper_plan:
        fail(
            "registry/hook-wrapper-plan.json is stale; "
            "run scripts/generate-hook-wrapper-plan.py --write"
        )
    validate_hook_wrapper_plan(hook_wrapper_plan, hook_consolidation)
    hook_wrapper_decision_count = validate_hook_wrapper_decisions(
        hook_wrapper_decisions,
        hook_wrapper_plan,
    )
    pretooluse_guard_decision_count = validate_pretooluse_guard_policy(
        hook_wrapper_decisions,
        hook_wrapper_plan,
        inventory_hooks,
    )
    hook_wrapper_activation_gate_count = validate_hook_wrapper_activation_gates(
        hook_wrapper_activation_gates,
        hook_wrapper_plan,
        hook_replay_fixtures,
    )
    if not is_executable("scripts/validate-hook-wrapper-activation.py"):
        fail("scripts/validate-hook-wrapper-activation.py must exist and be executable")
    generated_activation_report = generated_json_from_script("validate-hook-wrapper-activation.py")
    if generated_activation_report != hook_wrapper_activation_report:
        fail(
            "registry/hook-wrapper-activation-report.json is stale; "
            "run scripts/validate-hook-wrapper-activation.py --write"
        )
    hook_wrapper_activation_validation_count = validate_hook_wrapper_activation_report(
        hook_wrapper_activation_report,
        hook_wrapper_activation_gates,
    )
    if not is_executable("scripts/validate-hook-wrapper-isolated-execute.py"):
        fail("scripts/validate-hook-wrapper-isolated-execute.py must exist and be executable")
    generated_isolated_execute_report = generated_json_from_script(
        "validate-hook-wrapper-isolated-execute.py"
    )
    if generated_isolated_execute_report != hook_wrapper_isolated_execute_report:
        fail(
            "registry/hook-wrapper-isolated-execute-report.json is stale; "
            "run scripts/validate-hook-wrapper-isolated-execute.py --write"
        )
    hook_wrapper_isolated_execute_count = validate_hook_wrapper_isolated_execute_report(
        hook_wrapper_isolated_execute_report,
    )
    validate_active_hook_wrappers(hook_wrapper_plan, hooks)
    validate_hook_replay_fixtures(hook_replay_fixtures, hook_wrapper_plan)
    if not is_executable("scripts/generate-hook-order-review.py"):
        fail("scripts/generate-hook-order-review.py must exist and be executable")
    generated_hook_order_review = generated_json_from_script("generate-hook-order-review.py")
    if generated_hook_order_review != hook_order_review:
        fail(
            "registry/hook-order-review.json is stale; "
            "run scripts/generate-hook-order-review.py --write"
        )
    hook_order_review_md_path = ROOT / "registry" / "hook-order-review.md"
    if not hook_order_review_md_path.exists():
        fail("registry/hook-order-review.md is missing")
    generated_hook_order_review_md = subprocess.check_output(
        [
            sys.executable,
            str(ROOT / "scripts" / "generate-hook-order-review.py"),
            "--markdown",
        ],
        cwd=ROOT,
        text=True,
    )
    if generated_hook_order_review_md != hook_order_review_md_path.read_text(encoding="utf-8"):
        fail(
            "registry/hook-order-review.md is stale; "
            "run scripts/generate-hook-order-review.py --write"
        )
    validate_hook_order_review(hook_order_review, hook_wrapper_plan, hook_consolidation)
    output_contract_counts = validate_hook_output_contracts(
        hook_output_contracts,
        inventory_hooks,
    )
    if not is_executable("scripts/generate-hook-consolidation-plan.py"):
        fail("scripts/generate-hook-consolidation-plan.py must exist and be executable")
    hook_consolidation_plan_path = ROOT / "registry" / "hook-consolidation-plan.md"
    if not hook_consolidation_plan_path.exists():
        fail("registry/hook-consolidation-plan.md is missing")
    generated_hook_consolidation_plan = generated_text_from_script("generate-hook-consolidation-plan.py")
    current_hook_consolidation_plan = hook_consolidation_plan_path.read_text(encoding="utf-8")
    if generated_hook_consolidation_plan != current_hook_consolidation_plan:
        fail(
            "registry/hook-consolidation-plan.md is stale; "
            "run scripts/generate-hook-consolidation-plan.py --write"
        )
    if hook_timeout_policy.get("runtime_requirement") is None:
        fail("registry/hook-timeout-policy.json must define runtime_requirement")
    if not hook_timeout_policy.get("default_timeout_rules"):
        fail("registry/hook-timeout-policy.json must define default_timeout_rules")
    missing_script_hooks = [hook["id"] for hook in inventory_hooks if not hook.get("script_exists")]
    if missing_script_hooks:
        fail(f"hook inventory has missing scripts: {', '.join(missing_script_hooks)}")
    non_executable_hooks = [hook["id"] for hook in inventory_hooks if not hook.get("script_executable")]
    if non_executable_hooks:
        fail(f"hook inventory has non-executable scripts: {', '.join(non_executable_hooks)}")
    runtime_timeout_missing = [
        hook["id"]
        for hook in inventory_hooks
        if hook.get("timeout_seconds") is None
    ]
    if runtime_timeout_missing:
        fail(f"settings.json hooks without runtime timeout: {', '.join(runtime_timeout_missing)}")
    effective_timeout_missing = [
        hook["id"]
        for hook in inventory_hooks
        if hook.get("effective_timeout_seconds") is None
    ]
    if effective_timeout_missing:
        fail(f"hook inventory has missing effective timeout: {', '.join(effective_timeout_missing)}")
    invalid_effective_timeouts = [
        hook["id"]
        for hook in inventory_hooks
        if not isinstance(hook.get("effective_timeout_seconds"), int)
        or hook.get("effective_timeout_seconds") <= 0
    ]
    if invalid_effective_timeouts:
        fail(f"hook inventory has invalid effective timeout: {', '.join(invalid_effective_timeouts)}")
    if hook_inventory.get("timeout_missing_count") != 0:
        fail("registry/hooks-inventory.json timeout_missing_count must be 0")
    if hook_inventory.get("effective_timeout_missing_count") != 0:
        fail("registry/hooks-inventory.json effective_timeout_missing_count must be 0")

    events = set(settings.get("hooks", {}).keys())
    missing_events = [event for event in hook_policy["required_events"] if event not in events]
    if missing_events:
        fail(f"missing required hook events: {', '.join(missing_events)}")

    for required in hook_policy["required_hooks"]:
        if not hook_exists(
            hooks,
            required["event"],
            required["matcher"],
            required["command_contains"],
            inventory_hooks,
        ):
            fail(
                "missing required hook: "
                f"{required['event']} {required['matcher']} {required['command_contains']}"
            )

    settings_mcp_servers = set(settings.get("mcpServers", {}).keys())
    project_mcp_servers = set(mcp.get("mcpServers", {}).keys())
    for server in ["gitlab", "local-rag"]:
        if server not in settings_mcp_servers:
            fail(f"missing settings.json MCP server: {server}")
    for server in ["context7", "sequential-thinking"]:
        if server not in project_mcp_servers:
            fail(f"missing .mcp.json MCP server: {server}")

    if "mcp__codex-cli__codex" in json.dumps(settings, ensure_ascii=False):
        fail("settings.json still references forbidden mcp__codex-cli__codex tool")

    env = settings.get("env", {})
    if env.get("GEMINI_CLI") != "agy":
        fail("settings.json env.GEMINI_CLI must be 'agy'")

    if llm_routing.get("version") != 2:
        fail("registry/llm-routing.json version must be 2")
    if llm_routing.get("status") != "active":
        fail("registry/llm-routing.json status must be active")
    router_policy = llm_routing.get("router", {})
    if router_policy.get("entrypoint") != "scripts/llm-router.sh":
        fail("registry/llm-routing.json must declare scripts/llm-router.sh as router entrypoint")
    if router_policy.get("python_entrypoint") != "scripts/llm-router.py":
        fail("registry/llm-routing.json must declare scripts/llm-router.py as python entrypoint")
    if router_policy.get("adapter_entrypoint") != "scripts/llm-call.sh":
        fail("registry/llm-routing.json must route through scripts/llm-call.sh")
    for router_script in ["scripts/llm-router.sh", "scripts/llm-router.py"]:
        if not is_executable(router_script):
            fail(f"{router_script} must exist and be executable")
    if not isinstance(router_policy.get("max_call_depth"), int) or router_policy["max_call_depth"] < 1:
        fail("registry/llm-routing.json router.max_call_depth must be positive")
    for key in ["handoff_path", "health_path", "telemetry_path"]:
        value = router_policy.get(key, "")
        if not isinstance(value, str) or not value.startswith("cache/"):
            fail(f"registry/llm-routing.json router.{key} must point under cache/")
    tasks = llm_routing.get("tasks", {})
    required_tasks = ["default", "scan", "implement", "review", "private", "rescue", "summarize"]
    for task in required_tasks:
        if task not in tasks:
            fail(f"registry/llm-routing.json missing task route: {task}")
    provider_names = set(llm_routing.get("providers", {}))
    for task_name, task_policy in tasks.items():
        strategy = task_policy.get("strategy")
        if strategy not in {"first_success", "parallel_best_effort"}:
            fail(f"registry/llm-routing.json task {task_name} has invalid strategy")
        task_providers = task_policy.get("providers")
        if not isinstance(task_providers, list) or not task_providers:
            fail(f"registry/llm-routing.json task {task_name} must list providers")
        unknown_task_providers = [
            provider for provider in task_providers if provider not in provider_names
        ]
        if unknown_task_providers:
            fail(
                f"registry/llm-routing.json task {task_name} has unknown providers: "
                + ", ".join(unknown_task_providers)
            )
        timeout = task_policy.get("timeout_seconds")
        if not isinstance(timeout, int) or timeout <= 0:
            fail(f"registry/llm-routing.json task {task_name} timeout_seconds must be positive")
    if tasks["private"].get("providers") != ["gemma"]:
        fail("registry/llm-routing.json private route must use only gemma")
    if tasks["review"].get("strategy") != "parallel_best_effort":
        fail("registry/llm-routing.json review route must use parallel_best_effort")
    routing_principles = "\n".join(llm_routing.get("routing_principles", []))
    if "Claude is not assumed to be available" not in routing_principles:
        fail("registry/llm-routing.json must not assume Claude availability")
    gemma_policy = llm_routing.get("providers", {}).get("gemma", {})
    if not gemma_policy.get("default_model"):
        fail("registry/llm-routing.json gemma provider must declare default_model")
    host_candidates = gemma_policy.get("host_candidates", [])
    if not isinstance(host_candidates, list) or not host_candidates:
        fail("registry/llm-routing.json gemma provider must declare host_candidates")
    if not any("11434" in str(candidate) for candidate in host_candidates):
        fail("registry/llm-routing.json gemma host_candidates must include Ollama port 11434")

    codex_entrypoints = llm_routing["providers"]["codex"]["entrypoints"]
    if "codex exec" not in codex_entrypoints:
        fail("registry/llm-routing.json must document codex exec")
    if "mcp__codex-cli__*" not in llm_routing["providers"]["codex"]["forbidden_entrypoints"]:
        fail("registry/llm-routing.json must forbid mcp__codex-cli__*")
    if not is_executable("scripts/llm-call.sh"):
        fail("scripts/llm-call.sh must exist and be executable")
    required_adapter_entrypoints = [
        ("gemini", "scripts/llm-call.sh gemini"),
        ("codex", "scripts/llm-call.sh codex"),
        ("gemma", "scripts/llm-call.sh ini"),
    ]
    for provider, entrypoint in required_adapter_entrypoints:
        entrypoints = llm_routing["providers"][provider]["entrypoints"]
        if entrypoint not in entrypoints:
            fail(f"registry/llm-routing.json must document {entrypoint}")
    if llm_adapter_policy.get("router_entrypoint") != "scripts/llm-router.sh":
        fail("registry/llm-adapter-policy.json must declare scripts/llm-router.sh as router_entrypoint")
    if llm_adapter_policy.get("adapter_entrypoint") != "scripts/llm-call.sh":
        fail("registry/llm-adapter-policy.json must declare scripts/llm-call.sh as adapter_entrypoint")
    for item in llm_adapter_policy.get("allowed_direct_paths", []):
        path = item.get("path")
        if path and not (ROOT / path).exists():
            fail(f"registry/llm-adapter-policy.json allowed path does not exist: {path}")
    direct_llm_hits = registered_hook_direct_llm_hits(inventory_hooks)
    if direct_llm_hits:
        fail(
            "registered hooks must use scripts/llm-call.sh instead of direct LLM CLI calls: "
            + ", ".join(direct_llm_hits[:10])
        )
    unapproved_direct_hits = unapproved_runtime_direct_llm_hits(llm_adapter_policy)
    if unapproved_direct_hits:
        fail(
            "runtime hooks/scripts have unapproved direct LLM CLI calls: "
            + ", ".join(unapproved_direct_hits[:10])
        )
    validate_llm_log_schema(llm_log_schema)
    validate_llm_adapter_thresholds(llm_adapter_thresholds)
    validate_llm_usage_report(llm_log_schema)

    generated_llm_calls_inventory = generated_json_from_script("generate-llm-call-inventory.py")
    if generated_llm_calls_inventory != llm_calls_inventory:
        fail("registry/llm-calls-inventory.json is stale; run scripts/generate-llm-call-inventory.py --write")
    if not is_executable("scripts/generate-architecture-diagrams.py"):
        fail("scripts/generate-architecture-diagrams.py must exist and be executable")
    generated_diagrams_path = ROOT / "cache" / "generated-docs" / "claude-architecture-diagrams.generated.md"
    if not generated_diagrams_path.exists():
        fail("cache/generated-docs/claude-architecture-diagrams.generated.md is missing")
    generated_diagrams = generated_text_from_script("generate-architecture-diagrams.py")
    current_diagrams = generated_diagrams_path.read_text(encoding="utf-8")
    if generated_diagrams != current_diagrams:
        fail(
            "cache/generated-docs/claude-architecture-diagrams.generated.md is stale; "
            "run scripts/generate-architecture-diagrams.py --write"
        )
    validate_presentation_pipeline(presentation_pipeline)
    llm_inventory_paths = {entry["path"] for entry in llm_calls_inventory.get("entries", [])}
    if "scripts/llm-call.sh" not in llm_inventory_paths:
        fail("registry/llm-calls-inventory.json must include scripts/llm-call.sh")
    provider_counts = {
        item["provider"]: item["file_count"]
        for item in llm_calls_inventory.get("provider_counts", [])
    }
    for provider in ["gemini_or_agy", "codex", "ollama", "gemma", "qwen_ini"]:
        if provider_counts.get(provider, 0) <= 0:
            fail(f"registry/llm-calls-inventory.json has no runtime files for provider: {provider}")
    invalid_llm_paths = [
        entry["path"]
        for entry in llm_calls_inventory.get("entries", [])
        if any(part in entry["path"].split("/") for part in ["_disabled", "_archive", "_test"])
    ]
    if invalid_llm_paths:
        fail(f"llm call inventory includes non-runtime paths: {', '.join(invalid_llm_paths[:5])}")

    important_files = [
        "CLAUDE.md",
        "workflows/codex.md",
        "workflows/debugging.md",
        "workflows/standard-routines.md",
        "skills/moai/SKILL.md",
        "rules/moai/core/moai-constitution.md",
        "hooks/delegation-enforcer.sh",
        "hooks/error-codex-remind.sh",
    ]
    combined = "\n".join(read_text(path) for path in important_files)
    forbidden_phrases = [
        "Codex MCP",
        "codex:codex-rescue",
        "/Users/goos/",
    ]
    for phrase in forbidden_phrases:
        if phrase in combined:
            fail(f"forbidden stale phrase remains: {phrase}")

    print("OK: Claude config registry audit passed")
    print(
        f"hooks_checked={len(hooks)} events_checked={len(events)} "
        f"llm_runtime_files={llm_calls_inventory.get('file_count')} "
        f"runtime_timeouts_missing={hook_inventory.get('timeout_missing_count')} "
        "settings_policy=1 "
        "hook_manifest=1 "
        f"hook_consolidation_candidates={hook_consolidation.get('candidate_count')} "
        f"hook_consolidation_low={hook_consolidation.get('low_risk_count')} "
        f"hook_consolidation_medium={hook_consolidation.get('medium_risk_count')} "
        f"hook_consolidation_high={hook_consolidation.get('high_risk_count')} "
        f"hook_wrapper_ready={hook_consolidation.get('wrapper_ready_count')} "
        f"hook_order_review={hook_consolidation.get('order_review_count')} "
        f"hook_manual_review={hook_consolidation.get('manual_review_count')} "
        f"hook_wrapper_plans={hook_wrapper_plan.get('plan_count')} "
        f"hook_wrapper_definitions={hook_wrapper_plan.get('definition_count')} "
        f"hook_wrapper_active={hook_wrapper_plan.get('active_definition_count')} "
        f"hook_wrapper_planned={hook_wrapper_plan.get('planned_definition_count')} "
        f"hook_wrapper_candidate_plans={hook_wrapper_plan.get('candidate_plan_count')} "
        f"hook_wrapper_decisions={hook_wrapper_decision_count} "
        f"pretooluse_guard_decisions={pretooluse_guard_decision_count} "
        f"hook_wrapper_activation_gates={hook_wrapper_activation_gate_count} "
        f"hook_wrapper_activation_validations={hook_wrapper_activation_validation_count} "
        f"hook_wrapper_isolated_executes={hook_wrapper_isolated_execute_count} "
        f"hook_wrapper_safe_initial={hook_wrapper_plan.get('safe_initial_migration_count')} "
        f"hook_order_review_items={hook_order_review.get('review_item_count')} "
        "hook_output_contracts=1 "
        f"stop_output_contract_hooks={output_contract_counts['stop_contract_hooks']} "
        f"stop_user_visible_hooks={output_contract_counts['stop_user_visible_hooks']} "
        f"pretool_output_contract_hooks={output_contract_counts['pretool_contract_hooks']} "
        f"pretool_blocking_contracts={output_contract_counts['pretool_blocking_contracts']} "
        "hook_consolidation_plan=1 "
        "settings_projection=1 "
        "settings_projection_scope=1 "
        "registered_direct_llm_calls=0 "
        "unapproved_direct_llm_calls=0 "
        f"llm_log_schema_version={llm_log_schema.get('version')} "
        "llm_adapter_thresholds=1 "
        "llm_usage_adapter=1 "
        "architecture_diagrams=1 "
        "presentation_pipeline=1"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
