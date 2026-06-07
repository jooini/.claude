#!/usr/bin/env python3
"""Provider-neutral LLM router built on top of scripts/llm-call.sh."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, timezone
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REGISTRY_PATH = ROOT / "registry" / "llm-routing.json"
ADAPTER_PATH = ROOT / "scripts" / "llm-call.sh"
CACHE_DIR = ROOT / "cache"
ROUTER_LOG_PATH = CACHE_DIR / "llm-router-calls.jsonl"
HEALTH_PATH = CACHE_DIR / "llm-provider-health.json"
HANDOFF_PATH = CACHE_DIR / "llm-handoff" / "current.json"

ADAPTER_PROVIDER = {
    "agy": "gemini",
    "antigravity": "gemini",
    "gemini": "gemini",
    "codex": "codex",
    "gemma": "ini",
    "ini": "ini",
    "ollama": "ini",
    "qwen": "ini",
}

SKIP_HEALTH_STATUSES = {"unavailable", "expected_offline"}
LOCAL_PROVIDER_PRIVACY_TIERS = {"local"}
LOCAL_ADAPTER_PROVIDERS = {"ini"}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")


def parse_utc(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def load_registry() -> dict[str, Any]:
    return json.loads(REGISTRY_PATH.read_text(encoding="utf-8"))


def append_jsonl(path: Path, record: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("a", encoding="utf-8") as file:
        file.write(json.dumps(record, ensure_ascii=False) + "\n")


def first_nonempty_line(text: str) -> str:
    for line in text.splitlines():
        if line.strip():
            return line.strip()
    return ""


def safe_int(value: Any, default: int) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default


def run_git(args: list[str], cwd: Path) -> str | None:
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=str(cwd),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except OSError:
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip()


def write_handoff(
    task: str,
    caller: str,
    prompt: str,
    cwd: Path,
    parent_provider: str | None,
    active_provider: str | None,
    privacy_tier: str,
    active_providers: list[str] | None = None,
) -> None:
    root = run_git(["rev-parse", "--show-toplevel"], cwd)
    branch = run_git(["branch", "--show-current"], cwd) if root else None
    status = run_git(["status", "--short"], cwd) if root else None
    changed_files = []
    if status:
        changed_files = [line[3:] if len(line) > 3 else line for line in status.splitlines()]

    prompt_redacted = privacy_tier == "local_only"
    record = {
        "schema_version": 1,
        "updated_at": utc_now(),
        "task": task,
        "caller": caller,
        "cwd": str(cwd),
        "parent_provider": parent_provider,
        "active_provider": active_provider,
        "active_providers": active_providers or ([active_provider] if active_provider else []),
        "privacy_tier": privacy_tier,
        "prompt_length": len(prompt),
        "prompt_redacted": prompt_redacted,
        "prompt_preview": "" if prompt_redacted else prompt[:2000],
        "git": {
            "root": root,
            "branch": branch,
            "status_short": status,
            "changed_files": changed_files[:80],
        },
    }
    HANDOFF_PATH.parent.mkdir(parents=True, exist_ok=True)
    HANDOFF_PATH.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def detect_providers(registry: dict[str, Any]) -> dict[str, dict[str, Any]]:
    fixed_codex = Path.home() / ".nvm" / "versions" / "node" / "v22.22.0" / "bin" / "codex"
    providers = {}
    provider_policy = registry.get("providers", {})
    for provider in provider_policy:
        status = "unknown"
        detail = ""
        extra: dict[str, Any] = {}
        if provider == "claude":
            status = "session-only"
            detail = "Claude is not invoked by llm-router; use active session state."
        elif provider in {"gemini", "antigravity"}:
            wrapper = ROOT / "scripts" / "gemini-wrapped.sh"
            cli = shutil.which("agy") or shutil.which("gemini")
            status = "available" if wrapper.exists() and os.access(wrapper, os.X_OK) else "unavailable"
            detail = str(wrapper if wrapper.exists() else cli or "missing gemini-wrapped.sh")
        elif provider == "codex":
            cli = shutil.which("codex")
            status = "available" if cli or fixed_codex.exists() else "unavailable"
            detail = cli or str(fixed_codex)
        elif provider == "gemma":
            ini = Path.home() / ".local" / "bin" / "ini"
            if not ini.exists() or not os.access(ini, os.X_OK):
                status = "unavailable"
                detail = str(ini)
            else:
                reachable, detail, extra = probe_ollama_hosts(
                    configured_ollama_hosts(registry)
                )
                if reachable:
                    status = "available"
                else:
                    availability = provider_policy.get("gemma", {}).get("availability", {})
                    if is_office_only_expected_offline_policy(availability):
                        status = availability.get("expected_offline_status", "expected_offline")
                    else:
                        status = "unavailable"
                    if status == "expected_offline":
                        detail = (
                            "Expected offline: Gemma/Ollama is an office-only Windows host. "
                            + detail
                        )
        else:
            status = "configured"
            detail = "No active health probe is defined."
        providers[provider] = {"status": status, "detail": detail, **extra}
    return providers


def is_office_only_expected_offline_policy(availability: dict[str, Any]) -> bool:
    return (
        availability.get("policy") == "office_only_locked"
        and availability.get("mode") == "office_only_remote"
        and availability.get("offsite_status_is_normal") is True
        and availability.get("expected_offline_status") == "expected_offline"
    )


def provider_is_local(registry: dict[str, Any], provider: str) -> bool:
    provider_policy = registry.get("providers", {}).get(provider, {})
    adapter_provider = ADAPTER_PROVIDER.get(provider, provider)
    privacy_tier = provider_policy.get("privacy_tier")
    return bool(provider_policy) and (
        privacy_tier in LOCAL_PROVIDER_PRIVACY_TIERS
        or adapter_provider in LOCAL_ADAPTER_PROVIDERS
    )


def route_policy_violation(
    registry: dict[str, Any],
    policy: dict[str, Any],
    providers: list[str],
) -> str | None:
    privacy_tier = str(policy.get("privacy_tier", ""))
    external_fallback_allowed = policy.get("external_fallback_allowed")
    if privacy_tier != "local_only" and external_fallback_allowed is not False:
        return None

    external_providers = [
        provider
        for provider in providers
        if not provider_is_local(registry, provider)
    ]
    if not external_providers:
        return None

    if privacy_tier == "local_only":
        return (
            "local_only route forbids external providers: "
            + ", ".join(external_providers)
        )
    return (
        "external_fallback_allowed=false forbids external providers: "
        + ", ".join(external_providers)
    )


def normalize_host(value: str) -> str:
    return value.removeprefix("http://").removeprefix("https://").rstrip("/")


def parse_host_line(line: str) -> str | None:
    stripped = line.split("#", 1)[0].strip()
    if not stripped or stripped.startswith("#") or "=" not in stripped:
        return None
    key, value = stripped.split("=", 1)
    if key.strip() != "host":
        return None
    return normalize_host(value.strip().strip('"').strip("'"))


def config_ollama_host() -> str | None:
    config = Path.home() / ".config" / "ini" / "config.toml"
    if not config.exists():
        return None
    for line in config.read_text(encoding="utf-8", errors="ignore").splitlines():
        host = parse_host_line(line)
        if host:
            return host
    return None


def configured_ollama_hosts(registry: dict[str, Any]) -> list[str]:
    candidates: list[str] = []
    env_host = os.environ.get("OLLAMA_HOST_LAN") or os.environ.get("OLLAMA_HOST_URL")
    if env_host:
        candidates.append(normalize_host(env_host))
    config_host = config_ollama_host()
    if config_host:
        candidates.append(config_host)
    candidates.extend(
        registry.get("providers", {}).get("gemma", {}).get("host_candidates", [])
    )
    seen = set()
    unique = []
    for candidate in candidates or ["leonard.local:11434"]:
        normalized = normalize_host(candidate)
        if normalized and normalized not in seen:
            unique.append(normalized)
            seen.add(normalized)
    return unique


def probe_ollama_hosts(hosts: list[str], timeout: int = 2) -> tuple[bool, str, dict[str, Any]]:
    failures = []
    for host in hosts:
        url = f"http://{normalize_host(host)}/api/tags"
        try:
            with urllib.request.urlopen(url, timeout=timeout) as response:
                response.read(1)
            return True, url, {"selected_host": normalize_host(host), "host_candidates": hosts}
        except (OSError, urllib.error.URLError) as error:
            failures.append({"host": normalize_host(host), "error": str(error)})
    detail = "Ollama unreachable for candidates: " + ", ".join(
        f"{item['host']} ({item['error']})" for item in failures
    )
    return False, detail, {"host_candidates": hosts, "failures": failures}


def doctor(
    registry: dict[str, Any],
    as_json: bool,
    strict: bool,
    live_providers: list[str] | None = None,
    live_timeout: int = 20,
) -> int:
    providers = detect_providers(registry)
    unavailable = {
        provider
        for provider, info in providers.items()
        if provider != "claude" and info["status"] == "unavailable"
    }
    expected_offline = {
        provider
        for provider, info in providers.items()
        if provider != "claude" and info["status"] == "expected_offline"
    }
    critical_unavailable = unavailable.intersection({"codex", "gemini"})
    overall_status = (
        "failed" if critical_unavailable
        else "degraded" if unavailable
        else "ok"
    )
    if strict and (unavailable or expected_offline):
        overall_status = "failed"
    live_smoke: dict[str, Any] = {}
    if live_providers is not None:
        selected_live_providers = normalized_providers({"providers": live_providers}, None)
        if not selected_live_providers:
            selected_live_providers = [
                provider
                for provider, info in providers.items()
                if provider in ADAPTER_PROVIDER and info.get("status") == "available"
            ]
        live_smoke = run_live_smoke(
            registry,
            selected_live_providers,
            live_timeout,
        )
        if any(item.get("status") != "ok" for item in live_smoke.get("results", [])):
            overall_status = "failed"
    score = provider_score(providers, strict)
    record = {
        "schema_version": 1,
        "generated_at": utc_now(),
        "overall_status": overall_status,
        "score": score,
        "router_entrypoint": registry.get("router", {}).get("entrypoint"),
        "adapter_entrypoint": registry.get("router", {}).get("adapter_entrypoint"),
        "expected_offline_providers": sorted(expected_offline),
        "providers": providers,
    }
    if live_smoke:
        record["live_smoke"] = live_smoke
    HEALTH_PATH.parent.mkdir(parents=True, exist_ok=True)
    HEALTH_PATH.write_text(json.dumps(record, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    if as_json:
        print(json.dumps(record, ensure_ascii=False, indent=2))
    else:
        print(f"overall\t{overall_status}")
        print(f"score\t{score}")
        for provider, info in providers.items():
            print(f"{provider}\t{info['status']}\t{info['detail']}")
        if live_smoke:
            for item in live_smoke.get("results", []):
                print(
                    f"live\t{item['provider']}\t{item['status']}\t"
                    f"{item.get('duration_ms', 0)}ms\t{item.get('stdout_preview', '')}"
                )
        print(f"health\twritten\t{HEALTH_PATH}")
    if strict:
        return 1 if unavailable or expected_offline else 0
    return 1 if critical_unavailable else 0


def task_policy(registry: dict[str, Any], task: str) -> dict[str, Any]:
    tasks = registry.get("tasks", {})
    if task in tasks:
        return tasks[task]
    if "default" in tasks:
        return tasks["default"]
    raise SystemExit(f"unknown task and no default route: {task}")


def provider_statuses_from_health() -> dict[str, str]:
    if not HEALTH_PATH.exists():
        return {}
    try:
        health = json.loads(HEALTH_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {}
    providers = health.get("providers", {})
    return {
        provider: str(info.get("status", "unknown"))
        for provider, info in providers.items()
    }


def health_cache_metadata() -> dict[str, Any]:
    if not HEALTH_PATH.exists():
        return {
            "path": str(HEALTH_PATH),
            "exists": False,
            "generated_at": None,
            "age_seconds": None,
            "is_stale": True,
        }
    try:
        health = json.loads(HEALTH_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return {
            "path": str(HEALTH_PATH),
            "exists": True,
            "generated_at": None,
            "age_seconds": None,
            "is_stale": True,
        }
    generated_at = health.get("generated_at")
    generated = parse_utc(generated_at if isinstance(generated_at, str) else None)
    age_seconds = None
    if generated:
        age_seconds = max(0, int((datetime.now(timezone.utc) - generated).total_seconds()))
    return {
        "path": str(HEALTH_PATH),
        "exists": True,
        "generated_at": generated_at,
        "age_seconds": age_seconds,
        "is_stale": age_seconds is None or age_seconds > 300,
    }


def skip_provider_statuses_from_health() -> dict[str, str]:
    return {
        provider: status
        for provider, status in provider_statuses_from_health().items()
        if status in SKIP_HEALTH_STATUSES
    }


def selected_ollama_host_from_health() -> str | None:
    if not HEALTH_PATH.exists():
        return None
    try:
        health = json.loads(HEALTH_PATH.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    selected = health.get("providers", {}).get("gemma", {}).get("selected_host")
    return normalize_host(selected) if isinstance(selected, str) and selected else None


def read_prompt(value: str | None) -> str:
    if value == "-":
        return sys.stdin.read()
    if value is None:
        if not sys.stdin.isatty():
            return sys.stdin.read()
        raise SystemExit("--prompt is required for routing tasks")
    return value


def normalized_providers(policy: dict[str, Any], forced: list[str] | None) -> list[str]:
    providers = forced or list(policy.get("providers", []))
    normalized = []
    for provider in providers:
        if provider not in ADAPTER_PROVIDER:
            continue
        if provider not in normalized:
            normalized.append(provider)
    return normalized


def provider_score(providers: dict[str, dict[str, Any]], strict: bool = False) -> int:
    statuses = {
        provider: info.get("status")
        for provider, info in providers.items()
        if provider != "claude"
    }
    if any(statuses.get(provider) == "unavailable" for provider in {"codex", "gemini"}):
        return 0
    score = 100
    for provider, status in statuses.items():
        if status == "unavailable":
            score -= 20
        elif status == "expected_offline" and strict:
            score -= 12
    return max(0, min(100, score))


def route_score(
    *,
    status: str,
    privacy_tier: str,
    configured: list[str],
    available: list[str],
    skipped: dict[str, str],
) -> int:
    if status == "unavailable":
        return 0
    if status == "expected_offline":
        return 95 if privacy_tier == "local_only" and skipped else 70
    score = 100
    expected_skipped = sum(1 for value in skipped.values() if value == "expected_offline")
    hard_skipped = sum(1 for value in skipped.values() if value == "unavailable")
    score -= hard_skipped * 25
    score -= expected_skipped * 8
    if privacy_tier == "local_preferred" and configured and configured[0] not in available:
        score -= 8
    return max(0, min(100, score))


def route_action(status: str, privacy_tier: str, skipped: dict[str, str]) -> str:
    if status == "expected_offline" and privacy_tier == "local_only":
        return "Office Windows Ollama is required; external providers are intentionally excluded."
    if status == "unavailable":
        return "Run doctor, inspect skipped providers, or pass --ignore-health only for manual recovery."
    if skipped:
        return "Fallback providers are active; skipped providers are documented in skipped_providers."
    return "Ready."


def route_empty_message(
    task: str,
    policy: dict[str, Any],
    configured: list[str],
    skipped: dict[str, str],
) -> str:
    privacy_tier = str(policy.get("privacy_tier", ""))
    skipped_text = ", ".join(
        f"{provider}={status}" for provider, status in skipped.items() if provider in configured
    ) or "none"
    if privacy_tier == "local_only":
        return (
            f"llm-router: {task} route is local_only and has no reachable local provider. "
            f"Configured providers: {', '.join(configured) or 'none'}; skipped by health: {skipped_text}. "
            "External providers are intentionally excluded. If you are offsite, this is expected for the "
            "office-only Gemma/Ollama host."
        )
    return (
        f"llm-router: no providers remain for {task} after health filters. "
        f"Configured providers: {', '.join(configured) or 'none'}; skipped by health: {skipped_text}."
    )


def route_health(registry: dict[str, Any], as_json: bool) -> int:
    providers = detect_providers(registry)
    provider_statuses = {
        provider: str(info.get("status", "unknown"))
        for provider, info in providers.items()
    }
    tasks = registry.get("tasks", {})
    routes: dict[str, Any] = {}
    for task_name, policy in tasks.items():
        configured = normalized_providers(policy, None)
        policy_violation = route_policy_violation(registry, policy, configured)
        available = [
            provider
            for provider in configured
            if provider_statuses.get(provider) == "available"
        ]
        skipped = {
            provider: provider_statuses.get(provider, "unknown")
            for provider in configured
            if provider_statuses.get(provider) in SKIP_HEALTH_STATUSES
        }
        minimum_successes = safe_int(policy.get("minimum_successes", 1), 1)
        privacy_tier = str(policy.get("privacy_tier", ""))
        if policy_violation:
            status = "unavailable"
        elif len(available) >= minimum_successes:
            status = "ok"
        elif privacy_tier == "local_only" and skipped and all(
            status == "expected_offline" for status in skipped.values()
        ):
            status = "expected_offline"
        else:
            status = "unavailable"
        score = route_score(
            status=status,
            privacy_tier=privacy_tier,
            configured=configured,
            available=available,
            skipped=skipped,
        )
        routes[task_name] = {
            "status": status,
            "score": score,
            "strategy": policy.get("strategy", "first_success"),
            "privacy_tier": privacy_tier,
            "configured_providers": configured,
            "available_providers": available,
            "skipped_providers": skipped,
            "minimum_successes": minimum_successes,
            "policy_violation": policy_violation,
            "action": policy_violation or route_action(status, privacy_tier, skipped),
            "purpose": policy.get("purpose", ""),
        }
    route_scores = [route["score"] for route in routes.values()]
    record = {
        "schema_version": 1,
        "generated_at": utc_now(),
        "overall_status": "failed"
        if any(route["status"] == "unavailable" for route in routes.values())
        else "ok",
        "overall_score": int(sum(route_scores) / len(route_scores)) if route_scores else 0,
        "health_cache": health_cache_metadata(),
        "providers": providers,
        "routes": routes,
    }
    if as_json:
        print(json.dumps(record, ensure_ascii=False, indent=2))
    else:
        print(f"overall\t{record['overall_status']}")
        cache = record["health_cache"]
        print(
            "health-cache\t"
            f"age={cache.get('age_seconds') if cache.get('age_seconds') is not None else '-'}s\t"
            f"stale={cache.get('is_stale')}"
        )
        for task_name, route in routes.items():
            available = ",".join(route["available_providers"]) or "-"
            skipped = ",".join(
                f"{provider}:{status}"
                for provider, status in route["skipped_providers"].items()
            ) or "-"
            print(
                f"{task_name}\t{route['status']}\tscore={route['score']}\t"
                f"available={available}\tskipped={skipped}\taction={route['action']}"
            )
    return 0 if record["overall_status"] == "ok" else 1


def provider_timeout_seconds(policy: dict[str, Any], provider: str, default_timeout: int) -> int:
    overrides = policy.get("provider_timeouts_seconds") or {}
    if not isinstance(overrides, dict):
        return default_timeout
    return safe_int(overrides.get(provider), default_timeout)


def run_live_smoke(registry: dict[str, Any], providers: list[str], timeout_seconds: int) -> dict[str, Any]:
    prompt = "Reply with only: ok"
    results = []
    for provider in providers:
        item = call_provider(
            provider,
            "doctor-live",
            "doctor-live",
            prompt,
            timeout_seconds,
            0,
            registry,
            None,
            None,
            None,
        )
        stdout = item.get("stdout", "").strip()
        results.append(
            {
                "provider": provider,
                "status": item.get("status"),
                "exit_code": item.get("exit_code"),
                "duration_ms": item.get("duration_ms"),
                "stdout_preview": stdout[:80],
                "stderr_preview": first_nonempty_line(item.get("stderr", ""))[:200],
            }
        )
    return {
        "prompt_length": len(prompt),
        "timeout_seconds": timeout_seconds,
        "providers": providers,
        "results": results,
    }


def call_provider(
    provider: str,
    task: str,
    caller: str,
    prompt: str,
    timeout_seconds: int,
    depth: int,
    registry: dict[str, Any],
    model: str | None,
    profile: str | None,
    num_ctx: str | None,
) -> dict[str, Any]:
    adapter_provider = ADAPTER_PROVIDER[provider]
    command = [
        str(ADAPTER_PATH),
        adapter_provider,
        "--caller",
        f"{caller}:{task}:{provider}",
        "--timeout",
        str(timeout_seconds),
        "--prompt",
        "-",
    ]
    if model:
        command.extend(["--model", model])
    if profile:
        command.extend(["--profile", profile])
    if num_ctx:
        command.extend(["--num-ctx", num_ctx])

    env = os.environ.copy()
    router = registry.get("router", {})
    env[router.get("call_depth_env", "LLM_CALL_DEPTH")] = str(depth + 1)
    env[router.get("parent_provider_env", "LLM_PARENT_PROVIDER")] = (
        env.get(router.get("active_provider_env", "LLM_ACTIVE_PROVIDER"), "") or provider
    )
    env[router.get("active_provider_env", "LLM_ACTIVE_PROVIDER")] = provider
    if adapter_provider == "ini":
        selected_host = selected_ollama_host_from_health()
        if selected_host and "OLLAMA_HOST_LAN" not in env and "OLLAMA_HOST_URL" not in env:
            env["OLLAMA_HOST_LAN"] = selected_host

    started = time.time()
    result = subprocess.run(
        command,
        input=prompt,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        env=env,
        check=False,
    )
    return {
        "provider": provider,
        "adapter_provider": adapter_provider,
        "exit_code": result.returncode,
        "status": "ok" if result.returncode == 0 else "error",
        "duration_ms": int((time.time() - started) * 1000),
        "stdout": result.stdout,
        "stderr": result.stderr,
    }


def route(args: argparse.Namespace, registry: dict[str, Any]) -> int:
    router = registry.get("router", {})
    task = args.command or "default"
    policy = task_policy(registry, task)
    strategy = policy.get("strategy", "first_success")
    privacy_tier = str(policy.get("privacy_tier", ""))
    timeout_seconds = args.timeout or safe_int(policy.get("timeout_seconds", 60), 60)
    prompt = read_prompt(args.prompt)
    cwd = Path.cwd()

    depth_env = router.get("call_depth_env", "LLM_CALL_DEPTH")
    parent_env = router.get("parent_provider_env", "LLM_PARENT_PROVIDER")
    active_env = router.get("active_provider_env", "LLM_ACTIVE_PROVIDER")
    depth = safe_int(os.environ.get(depth_env, "0") or "0", 0)
    max_depth = safe_int(router.get("max_call_depth", 2), 2)
    parent_provider = args.from_provider or os.environ.get(active_env) or os.environ.get(parent_env)
    configured_providers = normalized_providers(policy, args.provider)
    policy_violation = route_policy_violation(registry, policy, configured_providers)
    if policy_violation:
        print(f"llm-router: {policy_violation}", file=sys.stderr)
        return 2
    providers = list(configured_providers)
    if parent_provider and not args.allow_self_provider:
        providers = [provider for provider in providers if provider != parent_provider]
    skipped_by_health: dict[str, str] = {}
    if not args.ignore_health and not args.provider:
        skipped_by_health = skip_provider_statuses_from_health()
        providers = [provider for provider in providers if provider not in skipped_by_health]

    if depth >= max_depth:
        print(f"llm-router: max call depth reached ({depth}/{max_depth})", file=sys.stderr)
        return 2
    if not providers:
        print(route_empty_message(task, policy, configured_providers, skipped_by_health), file=sys.stderr)
        return 2
    if not ADAPTER_PATH.exists() or not os.access(ADAPTER_PATH, os.X_OK):
        print(f"llm-router: missing executable adapter {ADAPTER_PATH}", file=sys.stderr)
        return 127

    if not args.no_handoff:
        write_handoff(task, args.caller, prompt, cwd, parent_provider, None, privacy_tier)

    route_record = {
        "schema_version": 1,
        "timestamp": utc_now(),
        "task": task,
        "caller": args.caller,
        "strategy": strategy,
        "providers": providers,
        "parent_provider": parent_provider,
        "depth": depth,
        "timeout_seconds": timeout_seconds,
        "prompt_length": len(prompt),
        "dry_run": args.dry_run,
    }
    if args.dry_run:
        print(json.dumps(route_record, ensure_ascii=False, indent=2))
        append_jsonl(ROUTER_LOG_PATH, {**route_record, "status": "dry-run"})
        return 0

    started = time.time()
    results: list[dict[str, Any]] = []
    if strategy == "parallel_best_effort":
        max_workers = min(len(providers), safe_int(policy.get("max_parallel", len(providers)), len(providers)))
        with ThreadPoolExecutor(max_workers=max_workers) as executor:
            futures = {
                executor.submit(
                    call_provider,
                    provider,
                    task,
                    args.caller,
                    prompt,
                    provider_timeout_seconds(policy, provider, timeout_seconds),
                    depth,
                    registry,
                    args.model,
                    args.profile,
                    args.num_ctx,
                ): provider
                for provider in providers
            }
            for future in as_completed(futures):
                provider = futures[future]
                try:
                    results.append(future.result())
                except Exception as error:
                    results.append(
                        {
                            "provider": provider,
                            "adapter_provider": ADAPTER_PROVIDER.get(provider, provider),
                            "exit_code": 1,
                            "status": "error",
                            "duration_ms": 0,
                            "stdout": "",
                            "stderr": f"{type(error).__name__}: {error}",
                        }
                    )
        results.sort(key=lambda item: providers.index(item["provider"]))
        successes = [item for item in results if item["status"] == "ok"]
        for item in successes:
            print(f"## {item['provider']}")
            print(item["stdout"].rstrip())
            print()
        for item in results:
            if item["status"] != "ok" and item["stderr"]:
                print(
                    f"llm-router: {item['provider']} failed: {first_nonempty_line(item['stderr'])}",
                    file=sys.stderr,
                )
        minimum = safe_int(policy.get("minimum_successes", 1), 1)
        status = "ok" if len(successes) >= minimum else "error"
        exit_code = 0 if status == "ok" else 1
    else:
        status = "error"
        exit_code = 1
        for provider in providers:
            item = call_provider(
                provider,
                task,
                args.caller,
                prompt,
                provider_timeout_seconds(policy, provider, timeout_seconds),
                depth,
                registry,
                args.model,
                args.profile,
                args.num_ctx,
            )
            results.append(item)
            if item["status"] == "ok":
                print(item["stdout"], end="")
                status = "ok"
                exit_code = 0
                break
            if item["stderr"]:
                print(
                    f"llm-router: {provider} failed: {first_nonempty_line(item['stderr'])}",
                    file=sys.stderr,
                )

    active_providers = [item["provider"] for item in results if item["status"] == "ok"]
    active_provider = active_providers[0] if active_providers else None
    if not args.no_handoff:
        write_handoff(
            task,
            args.caller,
            prompt,
            cwd,
            parent_provider,
            active_provider,
            privacy_tier,
            active_providers,
        )

    append_jsonl(
        ROUTER_LOG_PATH,
        {
            **route_record,
            "status": status,
            "exit_code": exit_code,
            "duration_ms": int((time.time() - started) * 1000),
            "results": [
                {
                    "provider": item["provider"],
                    "status": item["status"],
                    "exit_code": item["exit_code"],
                    "duration_ms": item["duration_ms"],
                    "stdout_length": len(item["stdout"]),
                    "stderr_length": len(item["stderr"]),
                }
                for item in results
            ],
        },
    )
    return exit_code


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Route LLM calls through a neutral fallback policy.",
        epilog=(
            "doctor treats office-only providers marked expected_offline as non-fatal. "
            "doctor --strict counts expected_offline providers as failures. "
            "doctor --live performs a short real provider call."
        ),
    )
    parser.add_argument("command", nargs="?", default="default", help="task name, doctor, route-health, or list-tasks")
    parser.add_argument("--caller", default="manual", help="logical caller name for telemetry")
    parser.add_argument("--timeout", type=int, help="provider timeout in seconds")
    parser.add_argument("--prompt", help="prompt text, or '-' to read stdin")
    parser.add_argument("--provider", action="append", help="force a provider; can be repeated")
    parser.add_argument("--from-provider", help="current provider, used to avoid self-recursion")
    parser.add_argument("--allow-self-provider", action="store_true", help="allow routing back to caller provider")
    parser.add_argument("--dry-run", action="store_true", help="print selected route without calling a provider")
    parser.add_argument("--json", action="store_true", help="emit JSON for metadata commands")
    parser.add_argument("--strict", action="store_true", help="doctor exits non-zero when any provider is unavailable or expected_offline")
    parser.add_argument("--live", action="store_true", help="doctor performs a short live provider call")
    parser.add_argument("--live-timeout", type=int, default=20, help="timeout seconds for doctor --live provider smoke calls")
    parser.add_argument("--no-handoff", action="store_true", help="do not update handoff cache")
    parser.add_argument("--ignore-health", action="store_true", help="do not skip providers marked unavailable by doctor")
    parser.add_argument("--model", help="model override for providers that support it")
    parser.add_argument("--profile", help="ini profile for local providers")
    parser.add_argument("--num-ctx", help="ini context window for local providers")
    return parser


def main() -> int:
    registry = load_registry()
    parser = build_parser()
    args = parser.parse_args()

    if args.command == "doctor":
        return doctor(
            registry,
            args.json,
            args.strict,
            args.provider or [] if args.live else None,
            args.live_timeout,
        )
    if args.command == "route-health":
        return route_health(registry, args.json)
    if args.command == "list-tasks":
        tasks = sorted(registry.get("tasks", {}))
        if args.json:
            print(json.dumps(tasks, ensure_ascii=False, indent=2))
        else:
            print("\n".join(tasks))
        return 0
    return route(args, registry)


if __name__ == "__main__":
    raise SystemExit(main())
