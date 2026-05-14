"""
ini CLI 호출 helper (urllib fallback 포함).

기존 gemma-* Python 스크립트들이 직접 urllib로 Ollama를 호출하던 패턴을
ini CLI 호출로 통일하기 위한 공용 라이브러리.

사용:
    from _lib_ini_call import call_ollama
    response = call_ollama(prompt, model="gemma4:e4b", num_predict=1500, temperature=0.4, caller="my-script")

전송 우선순위:
    1) ~/.local/bin/ini -p (LAN 도달 가능 시)
    2) urllib /api/chat fallback (ini 실패 또는 미설치)

JSONL 로깅: ~/.claude/cache/gemma-calls.jsonl (gemma-logger.sh와 동일 위치, transport 필드로 경로 구분)
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

OLLAMA = os.environ.get("OLLAMA_HOST_LAN", "leonard.local:11434")
INI_BIN = Path.home() / ".local" / "bin" / "ini"
LOG_FILE = Path.home() / ".claude" / "cache" / "gemma-calls.jsonl"


def _log_call(record: dict) -> None:
    LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
    try:
        with LOG_FILE.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
    except OSError:
        pass


def _call_ini(prompt: str, model: str, timeout: int) -> tuple[str | None, str]:
    """Returns (response or None on failure, stderr_preview)."""
    if not INI_BIN.exists() or not os.access(INI_BIN, os.X_OK):
        return None, "ini binary not found"
    env = os.environ.copy()
    env["OLLAMA_HOST_URL"] = f"http://{OLLAMA}"
    try:
        result = subprocess.run(
            [
                str(INI_BIN),
                "--model", model,
                "--keep-alive", "30m",
                "--no-rag",
                "--no-cache",
                "-p", "-",
            ],
            input=prompt,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout.rstrip("\n"), ""
        return None, (result.stderr or "")[:300]
    except subprocess.TimeoutExpired:
        return None, "ini timeout"
    except OSError as e:
        return None, f"ini OSError: {e}"


def _call_urllib(prompt: str, model: str, num_predict: int, temperature: float, timeout: int) -> tuple[str | None, dict, str]:
    """Returns (response or None, meta dict, error message)."""
    body = json.dumps({
        "model": model,
        "messages": [{"role": "user", "content": prompt}],
        "stream": False,
        "keep_alive": "30m",
        "options": {"num_predict": num_predict, "temperature": temperature},
    }).encode()
    req = urllib.request.Request(
        f"http://{OLLAMA}/api/chat",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = json.loads(r.read())
        result = data.get("message", {}).get("content", "")
        meta = {
            "done_reason": data.get("done_reason"),
            "prompt_eval_count": data.get("prompt_eval_count"),
            "eval_count": data.get("eval_count"),
            "total_duration_ns": data.get("total_duration"),
        }
        return result, meta, ""
    except Exception as e:
        return None, {}, str(e)


def call_ollama(
    prompt: str,
    model: str = "gemma4:e4b",
    num_predict: int = 800,
    temperature: float = 0.3,
    timeout: int = 90,
    caller: str = "unknown",
) -> str:
    """Call Ollama via ini (preferred) or urllib (fallback). Returns response string (empty on total failure).

    Logs every call to ~/.claude/cache/gemma-calls.jsonl with transport field.
    """
    ts_start = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    t_start = time.time()

    # 1) Try ini
    response, ini_err = _call_ini(prompt, model, timeout)
    transport = "ini"
    meta: dict = {}
    err = ""

    if response is None:
        # 2) Fallback to urllib
        transport = "urllib_fallback"
        response, meta, err = _call_urllib(prompt, model, num_predict, temperature, timeout)

    duration_ms = int((time.time() - t_start) * 1000)
    status = "ok" if response else "error"
    response = response or ""

    record = {
        "timestamp": ts_start,
        "caller": caller,
        "model": model,
        "status": status,
        "duration_ms": duration_ms,
        "num_predict": num_predict,
        "temperature": temperature,
        "transport": transport,
        "input_tokens": meta.get("prompt_eval_count"),
        "output_tokens": meta.get("eval_count"),
        "done_reason": meta.get("done_reason"),
        "prompt_preview": prompt[:500],
        "prompt_length": len(prompt),
        "response_preview": response[:500],
        "response_length": len(response),
    }
    if ini_err:
        record["ini_stderr_preview"] = ini_err
    if err:
        record["urllib_error"] = err[:300]

    _log_call(record)
    return response


def _call_urllib_messages(messages: list[dict], model: str, num_predict: int,
                          temperature: float, timeout: int,
                          extra_options: dict | None = None) -> tuple[str | None, dict, str]:
    options = {"num_predict": num_predict, "temperature": temperature}
    if extra_options:
        options.update(extra_options)
    body = json.dumps({
        "model": model,
        "messages": messages,
        "stream": False,
        "keep_alive": "30m",
        "options": options,
    }).encode()
    req = urllib.request.Request(
        f"http://{OLLAMA}/api/chat",
        data=body,
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            data = json.loads(r.read())
        result = data.get("message", {}).get("content", "").strip()
        meta = {
            "done_reason": data.get("done_reason"),
            "prompt_eval_count": data.get("prompt_eval_count"),
            "eval_count": data.get("eval_count"),
            "total_duration_ns": data.get("total_duration"),
        }
        return result, meta, ""
    except Exception as e:
        return None, {}, str(e)


def call_ollama_messages(
    messages: list[dict],
    model: str = "gemma4:e4b",
    num_predict: int = 800,
    temperature: float = 0.3,
    timeout: int = 90,
    caller: str = "unknown",
    extra_options: dict | None = None,
    force_format: str | None = None,
) -> str:
    """Call Ollama with chat messages list. ini for flattened, urllib fallback preserves messages.

    force_format: Ollama API "format" param (e.g. "json"). ini doesn't support format option,
                  so when force_format is set, urllib is used directly (skips ini).
    """
    ts_start = datetime.now(timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
    t_start = time.time()

    transport = "ini"
    response = None
    ini_err = ""
    meta: dict = {}
    err = ""

    if force_format:
        # ini doesn't support format=json, go direct to urllib
        transport = "urllib_format_required"
        body = json.dumps({
            "model": model,
            "messages": messages,
            "stream": False,
            "keep_alive": "30m",
            "format": force_format,
            "options": {
                "num_predict": num_predict,
                "temperature": temperature,
                **(extra_options or {}),
            },
        }).encode()
        req = urllib.request.Request(
            f"http://{OLLAMA}/api/chat",
            data=body,
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                data = json.loads(r.read())
            response = data.get("message", {}).get("content", "").strip()
            meta = {
                "done_reason": data.get("done_reason"),
                "prompt_eval_count": data.get("prompt_eval_count"),
                "eval_count": data.get("eval_count"),
            }
        except Exception as e:
            err = str(e)
    else:
        # Flatten for ini
        parts = []
        for m in messages:
            role = m.get("role", "user")
            content = m.get("content", "")
            if role == "system":
                parts.append(f"[SYSTEM]\n{content}")
            elif role == "assistant":
                parts.append(f"[ASSISTANT]\n{content}")
            else:
                parts.append(content)
        flat_prompt = "\n\n".join(parts)

        response, ini_err = _call_ini(flat_prompt, model, timeout)

        if response is None:
            transport = "urllib_fallback"
            response, meta, err = _call_urllib_messages(messages, model, num_predict, temperature, timeout, extra_options)

    duration_ms = int((time.time() - t_start) * 1000)
    status = "ok" if response else "error"
    response = response or ""

    flat_for_log = ""
    if not force_format:
        flat_for_log = flat_prompt
    else:
        flat_for_log = "\n\n".join(m.get("content", "") for m in messages)
    record = {
        "timestamp": ts_start,
        "caller": caller,
        "model": model,
        "status": status,
        "duration_ms": duration_ms,
        "num_predict": num_predict,
        "temperature": temperature,
        "transport": transport,
        "input_tokens": meta.get("prompt_eval_count"),
        "output_tokens": meta.get("eval_count"),
        "done_reason": meta.get("done_reason"),
        "messages_count": len(messages),
        "format": force_format,
        "prompt_preview": flat_for_log[:500],
        "prompt_length": len(flat_for_log),
        "response_preview": response[:500],
        "response_length": len(response),
    }
    if ini_err:
        record["ini_stderr_preview"] = ini_err
    if err:
        record["urllib_error"] = err[:300]
    _log_call(record)
    return response


def is_ollama_reachable(timeout: int = 3) -> bool:
    """Quick health check via /api/tags."""
    try:
        req = urllib.request.Request(f"http://{OLLAMA}/api/tags")
        with urllib.request.urlopen(req, timeout=timeout) as r:
            r.read()
        return True
    except Exception:
        return False


if __name__ == "__main__":
    # Self-test
    print(f"INI_BIN exists: {INI_BIN.exists()}")
    print(f"OLLAMA: {OLLAMA}")
    print(f"reachable: {is_ollama_reachable()}")
    if len(sys.argv) > 1:
        prompt = " ".join(sys.argv[1:])
        print(f"Calling: {prompt}")
        print(call_ollama(prompt, caller="self-test"))
