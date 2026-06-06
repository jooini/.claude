#!/usr/bin/env python3
"""
llm-usage — LLM 사용량 집계 (Claude Code + Codex)

데이터 출처:
- Claude Code: ~/.claude/projects/**/*.jsonl (message.usage)
- Codex (GPT):  ~/.codex/state_5.sqlite (threads.tokens_used)
- Ollama:       ~/.claude/cache/gemma-calls.jsonl (현재 부분 기록만)
- LLM Adapter:  ~/.claude/cache/llm-adapter-calls.jsonl (shell adapter 공통 telemetry)

사용:
  python3 ~/.claude/scripts/llm-usage.py           # 전체 + 최근 7일
  python3 ~/.claude/scripts/llm-usage.py --json    # JSON 출력 (대시보드용)
  python3 ~/.claude/scripts/llm-usage.py --days 30 # 최근 N일
"""
import json
import glob
import os
import sqlite3
import sys
import argparse
from datetime import datetime, timedelta
from collections import defaultdict


ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LLM_ADAPTER_THRESHOLDS_PATH = os.path.join(ROOT, "registry", "llm-adapter-thresholds.json")


# 모델별 1M 토큰당 USD 가격 (2026-05 기준 — 검증 필요 시 갱신)
# 출처: OpenAI / Anthropic / Google 공식 가격표 (2026-05-07 시점 추정)
PRICING = {
    # Anthropic Claude
    'claude-opus-4-7':         {'input': 15.0, 'output': 75.0, 'cache_read': 1.5, 'cache_create': 18.75},
    'claude-sonnet-4-6':       {'input':  3.0, 'output': 15.0, 'cache_read': 0.3, 'cache_create':  3.75},
    'claude-haiku-4-5':        {'input':  1.0, 'output':  5.0, 'cache_read': 0.1, 'cache_create':  1.25},
    # OpenAI GPT
    'gpt-5':                   {'input':  2.5, 'output': 10.0, 'cache_read': 0.25, 'cache_create': 0},
    'gpt-5.1':                 {'input':  2.5, 'output': 10.0, 'cache_read': 0.25, 'cache_create': 0},
    'gpt-5.2':                 {'input':  2.5, 'output': 10.0, 'cache_read': 0.25, 'cache_create': 0},
    'gpt-5.3':                 {'input':  3.0, 'output': 12.0, 'cache_read': 0.30, 'cache_create': 0},
    'gpt-5.3-codex':           {'input':  3.0, 'output': 12.0, 'cache_read': 0.30, 'cache_create': 0},
    'gpt-5.4':                 {'input':  3.0, 'output': 12.0, 'cache_read': 0.30, 'cache_create': 0},
    'gpt-5.4-codex':           {'input':  3.0, 'output': 12.0, 'cache_read': 0.30, 'cache_create': 0},
    'gpt-5.4-mini':            {'input':  0.6, 'output':  2.4, 'cache_read': 0.06, 'cache_create': 0},
    'gpt-5.5':                 {'input':  3.5, 'output': 14.0, 'cache_read': 0.35, 'cache_create': 0},
    'gpt-5-codex':             {'input':  3.0, 'output': 12.0, 'cache_read': 0.30, 'cache_create': 0},
    'gpt-5-pro':               {'input': 15.0, 'output': 60.0, 'cache_read': 1.50, 'cache_create': 0},
    'codex-mini-latest':       {'input':  0.6, 'output':  2.4, 'cache_read': 0.06, 'cache_create': 0},
    'o3':                      {'input': 15.0, 'output': 60.0, 'cache_read': 7.50, 'cache_create': 0},
    'o4-mini':                 {'input':  1.1, 'output':  4.4, 'cache_read': 0.275, 'cache_create': 0},
    # Google Gemini
    'gemini-3-flash-preview':  {'input': 0.30, 'output': 2.50, 'cache_read': 0.075, 'cache_create': 0},
    'gemini-2.5-flash-lite':   {'input': 0.10, 'output': 0.40, 'cache_read': 0.025, 'cache_create': 0},
    'gemini-2.5-flash':        {'input': 0.30, 'output': 2.50, 'cache_read': 0.075, 'cache_create': 0},
    'gemini-2.5-pro':          {'input': 1.25, 'output': 10.0, 'cache_read': 0.31,  'cache_create': 0},
    'auto-gemini-3':           {'input': 0.30, 'output': 2.50, 'cache_read': 0.075, 'cache_create': 0},
}

# Codex tokens_used는 input+output 합산 — 평균 비율로 추정 (검증 필요)
# 통상 input:output = 7:3 정도 (cache 비중 높을수록 비용 ↓)
CODEX_INPUT_RATIO = 0.7


def as_int(value, default=0):
    try:
        return int(value or default)
    except (TypeError, ValueError):
        return default


def iter_jsonl(path):
    """Yield valid JSON objects from a JSONL file."""
    if not os.path.exists(path):
        return
    try:
        with open(path) as f:
            for line in f:
                try:
                    obj = json.loads(line)
                except Exception:
                    continue
                if isinstance(obj, dict):
                    yield obj
    except Exception:
        return


def load_llm_adapter_thresholds():
    defaults = {
        'warning_error_rate': 0.10,
        'critical_error_rate': 0.25,
        'warning_timeout_rate': 0.05,
        'critical_timeout_rate': 0.15,
        'warning_avg_duration_ms': 15000,
        'critical_avg_duration_ms': 30000,
    }
    fallback = {
        'version': 0,
        'status': 'fallback',
        'metric_source': 'cache/llm-adapter-calls.jsonl',
        'minimum_calls_for_rate': 5,
        'defaults': defaults,
        'provider_overrides': {},
    }
    try:
        with open(LLM_ADAPTER_THRESHOLDS_PATH, encoding='utf-8') as handle:
            data = json.load(handle)
        if not isinstance(data, dict):
            return fallback
        merged = dict(fallback)
        merged.update(data)
        merged_defaults = dict(defaults)
        merged_defaults.update(data.get('defaults') or {})
        merged['defaults'] = merged_defaults
        merged['provider_overrides'] = data.get('provider_overrides') or {}
        return merged
    except Exception:
        return fallback


def adapter_thresholds_for(thresholds, provider=None):
    values = dict(thresholds.get('defaults') or {})
    if provider:
        values.update((thresholds.get('provider_overrides') or {}).get(provider) or {})
    return values


def evaluate_adapter_bucket(name, bucket, thresholds, provider=None):
    calls = as_int(bucket.get('calls'))
    errors = as_int(bucket.get('error'))
    timeouts = as_int(bucket.get('timeout'))
    avg_duration_ms = float(bucket.get('avg_duration_ms') or 0.0)
    minimum_calls = as_int(thresholds.get('minimum_calls_for_rate'), 5)
    policy = adapter_thresholds_for(thresholds, provider)
    error_rate = errors / calls if calls else 0.0
    timeout_rate = timeouts / calls if calls else 0.0

    severity = 'ok'
    reasons = []
    if calls < minimum_calls:
        severity = 'insufficient-data'
    else:
        if error_rate >= float(policy.get('critical_error_rate', 1.0)):
            severity = 'critical'
            reasons.append('error_rate')
        elif error_rate >= float(policy.get('warning_error_rate', 1.0)):
            severity = 'warning'
            reasons.append('error_rate')

        if timeout_rate >= float(policy.get('critical_timeout_rate', 1.0)):
            severity = 'critical'
            reasons.append('timeout_rate')
        elif timeout_rate >= float(policy.get('warning_timeout_rate', 1.0)) and severity != 'critical':
            severity = 'warning'
            reasons.append('timeout_rate')

        if avg_duration_ms >= float(policy.get('critical_avg_duration_ms', 10**12)):
            severity = 'critical'
            reasons.append('avg_duration_ms')
        elif avg_duration_ms >= float(policy.get('warning_avg_duration_ms', 10**12)) and severity != 'critical':
            severity = 'warning'
            reasons.append('avg_duration_ms')

    return {
        'name': name,
        'provider': provider,
        'severity': severity,
        'calls': calls,
        'error_rate': error_rate,
        'timeout_rate': timeout_rate,
        'avg_duration_ms': avg_duration_ms,
        'reasons': sorted(set(reasons)),
    }


def evaluate_adapter_health(total, by_provider, thresholds):
    total_health = evaluate_adapter_bucket('total', total, thresholds)
    provider_health = {
        provider: evaluate_adapter_bucket(provider, bucket, thresholds, provider=provider)
        for provider, bucket in by_provider.items()
    }
    alerts = [
        {'scope': 'total', **total_health}
    ] if total_health['severity'] in {'warning', 'critical'} else []
    alerts.extend(
        {'scope': 'provider', **item}
        for item in provider_health.values()
        if item['severity'] in {'warning', 'critical'}
    )
    severity_rank = {'ok': 0, 'insufficient-data': 0, 'warning': 1, 'critical': 2}
    overall = max(
        [total_health['severity']] + [item['severity'] for item in provider_health.values()],
        key=lambda value: severity_rank.get(value, 0),
    )
    return {
        'overall': overall,
        'total': total_health,
        'by_provider': provider_health,
        'alerts': alerts,
    }


def cost_for(model, in_tokens=0, out_tokens=0, cache_r=0, cache_c=0):
    """모델 + 토큰 → USD"""
    p = PRICING.get(model)
    if not p:
        # unknown 모델 — claude-opus 가격 기준으로 보수적 추정
        p = PRICING.get('gpt-5.4', {'input': 3.0, 'output': 12.0, 'cache_read': 0.3, 'cache_create': 0})
    return (
        in_tokens / 1_000_000 * p['input'] +
        out_tokens / 1_000_000 * p['output'] +
        cache_r / 1_000_000 * p['cache_read'] +
        cache_c / 1_000_000 * p.get('cache_create', 0)
    )


def collect_claude_code():
    """~/.claude/projects/**/*.jsonl 에서 토큰 집계"""
    daily = defaultdict(lambda: {'in':0, 'out':0, 'cache_r':0, 'cache_c':0, 'turns':0, 'cost':0.0})
    by_project = defaultdict(lambda: {'tokens':0, 'turns':0, 'cost':0.0, 'last_seen':''})
    total = {'in':0, 'out':0, 'cache_r':0, 'cache_c':0, 'turns':0, 'cost':0.0}
    sessions = set()

    pattern = os.path.expanduser("~/.claude/projects/**/*.jsonl")
    for path in glob.glob(pattern, recursive=True):
        # 프로젝트명 = 파일이 들어있는 디렉토리 이름 (사용자 친화 변환)
        proj_dir = os.path.basename(os.path.dirname(path))
        proj_name = proj_dir.replace('-Users-leonard-', '~/').replace('-Workspace-', 'Workspace/').replace('-', '/')
        if len(proj_name) > 60:
            proj_name = '...' + proj_name[-57:]
        try:
            with open(path) as f:
                for line in f:
                    try:
                        obj = json.loads(line)
                    except Exception:
                        continue
                    msg = obj.get('message', {})
                    usage = msg.get('usage') if isinstance(msg, dict) else None
                    if not usage:
                        continue
                    ts = obj.get('timestamp', '')
                    if not ts or len(ts) < 10:
                        continue
                    day = ts[:10]
                    inp = usage.get('input_tokens', 0) or 0
                    out = usage.get('output_tokens', 0) or 0
                    cr = usage.get('cache_read_input_tokens', 0) or 0
                    cc = usage.get('cache_creation_input_tokens', 0) or 0
                    model = (msg.get('model') if isinstance(msg, dict) else None) or obj.get('model') or 'claude-opus-4-7'
                    model_key = model
                    for k in PRICING:
                        if model.startswith(k):
                            model_key = k
                            break
                    cost = cost_for(model_key, inp, out, cr, cc)
                    tot = inp + out + cr + cc

                    daily[day]['in'] += inp
                    daily[day]['out'] += out
                    daily[day]['cache_r'] += cr
                    daily[day]['cache_c'] += cc
                    daily[day]['turns'] += 1
                    daily[day]['cost'] += cost
                    total['in'] += inp
                    total['out'] += out
                    total['cache_r'] += cr
                    total['cache_c'] += cc
                    total['turns'] += 1
                    total['cost'] += cost
                    by_project[proj_name]['tokens'] += tot
                    by_project[proj_name]['turns'] += 1
                    by_project[proj_name]['cost'] += cost
                    if ts > by_project[proj_name]['last_seen']:
                        by_project[proj_name]['last_seen'] = ts
                    sid = obj.get('sessionId')
                    if sid:
                        sessions.add(sid)
        except Exception:
            pass

    total['sessions'] = len(sessions)
    return {'total': total, 'daily': dict(daily), 'by_project': dict(by_project)}


def collect_codex():
    """~/.codex/state_5.sqlite 에서 threads 사용량 집계"""
    db_path = os.path.expanduser("~/.codex/state_5.sqlite")
    if not os.path.exists(db_path):
        return {'total': {}, 'daily': {}, 'by_model': {}, 'available': False}

    try:
        conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True, timeout=2)
        cur = conn.cursor()

        # 일별 + 모델별 동시 (비용 계산 위해 매일 모델 분리 필요)
        cur.execute("""
            SELECT
              date(created_at,'unixepoch','localtime') AS day,
              COALESCE(model, '(unknown)') AS model,
              COUNT(*) AS sessions,
              SUM(tokens_used) AS tokens
            FROM threads
            GROUP BY day, model
        """)
        daily = defaultdict(lambda: {'sessions': 0, 'tokens': 0, 'cost': 0.0})
        by_model = defaultdict(lambda: {'sessions': 0, 'tokens': 0, 'cost': 0.0})
        total_sessions = 0
        total_tokens = 0
        total_cost = 0.0
        for day, model, sessions, tokens in cur.fetchall():
            tokens = tokens or 0
            # Codex tokens_used = total — input/output 추정 비율 적용
            inp = int(tokens * CODEX_INPUT_RATIO)
            out = tokens - inp
            cost = cost_for(model, inp, out)

            daily[day]['sessions'] += sessions
            daily[day]['tokens'] += tokens
            daily[day]['cost'] += cost
            by_model[model]['sessions'] += sessions
            by_model[model]['tokens'] += tokens
            by_model[model]['cost'] += cost
            total_sessions += sessions
            total_tokens += tokens
            total_cost += cost

        conn.close()
        return {
            'total': {'sessions': total_sessions, 'tokens': total_tokens, 'cost': total_cost},
            'daily': dict(daily),
            'by_model': dict(by_model),
            'available': True
        }
    except Exception as e:
        return {'total': {}, 'daily': {}, 'by_model': {}, 'available': False, 'error': str(e)}


def _parse_gemini_telemetry(path):
    """OTel pretty-JSON 멀티 객체 파일에서 api_response 이벤트만 추출"""
    import re
    if not os.path.exists(path):
        return []
    try:
        content = open(path).read()
    except Exception:
        return []
    parts = re.split(r'(?<=\n\})\s*\n(?=\{)', content)
    events = []
    for p in parts:
        try:
            o = json.loads(p)
        except Exception:
            continue
        attrs = o.get('attributes', {})
        if not isinstance(attrs, dict):
            continue
        if attrs.get('event.name') == 'gemini_cli.api_response':
            events.append(attrs)
    return events


def collect_gemini():
    """Gemini 사용량 — telemetry 우선, wrapper 보조"""
    daily = defaultdict(lambda: {'calls': 0, 'tokens': 0, 'in': 0, 'out': 0,
                                   'cached': 0, 'thoughts': 0, 'duration_ms': 0, 'cost': 0.0})
    by_model = defaultdict(lambda: {'calls': 0, 'tokens': 0, 'cost': 0.0})
    by_caller = defaultdict(lambda: {'calls': 0, 'tokens': 0})
    total_calls = 0
    total_tokens = 0
    total_cost = 0.0
    sources = []

    # 1) Telemetry (모든 호출 — interactive 포함)
    tele_path = os.path.expanduser("~/.claude/cache/gemini-telemetry.jsonl")
    tele_events = _parse_gemini_telemetry(tele_path)
    if tele_events:
        sources.append(f'telemetry ({len(tele_events)} api_response)')
        for e in tele_events:
            ts = e.get('event.timestamp', '')
            if not ts or len(ts) < 10:
                continue
            day = ts[:10]
            tot = int(e.get('total_token_count', 0) or 0)
            inp = int(e.get('input_token_count', 0) or 0)
            out = int(e.get('output_token_count', 0) or 0)
            cached = int(e.get('cached_content_token_count', 0) or 0)
            thoughts = int(e.get('thoughts_token_count', 0) or 0)
            dur = int(e.get('duration_ms', 0) or 0)
            model = e.get('model', '(unknown)')
            role = e.get('role', 'unknown')
            cost = cost_for(model, inp, out, cached)

            daily[day]['calls'] += 1
            daily[day]['tokens'] += tot
            daily[day]['in'] += inp
            daily[day]['out'] += out
            daily[day]['cached'] += cached
            daily[day]['thoughts'] += thoughts
            daily[day]['duration_ms'] += dur
            daily[day]['cost'] += cost
            by_model[model]['calls'] += 1
            by_model[model]['tokens'] += tot
            by_model[model]['cost'] += cost
            by_caller[role]['calls'] += 1
            by_caller[role]['tokens'] += tot
            total_calls += 1
            total_tokens += tot
            total_cost += cost

    # 2) Wrapper jsonl (telemetry 활성화 전 또는 wrapper 직접 호출)
    wrapper_path = os.path.expanduser("~/.claude/cache/gemini-calls.jsonl")
    wrapper_count = 0
    if os.path.exists(wrapper_path):
        try:
            with open(wrapper_path) as f:
                for line in f:
                    try:
                        d = json.loads(line)
                    except Exception:
                        continue
                    ts = d.get('timestamp', '')
                    if not ts or len(ts) < 10:
                        continue
                    # Wrapper 호출이 telemetry로도 잡혔으면 중복 — session_id로 검증 어려우니 일단 추가
                    # 실용적 절충: wrapper만의 caller 정보를 추가 표시 (중복 카운트 위험 있음)
                    wrapper_count += 1
        except Exception:
            pass
    if wrapper_count > 0:
        sources.append(f'wrapper ({wrapper_count} calls — telemetry와 중복 가능)')

    # 3) agy CLI (Antigravity, 2026-06-18 이후 기본) — stream-json 미지원으로 토큰 0
    agy_path = os.path.expanduser("~/.claude/cache/agy-calls.jsonl")
    agy_count = 0
    agy_duration = 0
    if os.path.exists(agy_path):
        try:
            with open(agy_path) as f:
                for line in f:
                    try:
                        d = json.loads(line)
                    except Exception:
                        continue
                    ts = d.get('timestamp', '')
                    if not ts or len(ts) < 10:
                        continue
                    day = ts[:10]
                    dur = int(d.get('duration_ms', 0) or 0)
                    caller = d.get('caller', 'unknown')
                    daily[day]['calls'] += 1
                    daily[day]['duration_ms'] += dur
                    by_model['agy(antigravity)']['calls'] += 1
                    by_caller[caller]['calls'] += 1
                    total_calls += 1
                    agy_count += 1
                    agy_duration += dur
        except Exception:
            pass
    if agy_count > 0:
        sources.append(f'agy ({agy_count} calls, {agy_duration/1000:.1f}s — 토큰 메타 없음)')

    note = ' / '.join(sources) if sources else 'telemetry/wrapper/agy 미작동'

    return {
        'total': {'calls': total_calls, 'tokens': total_tokens, 'cost': total_cost},
        'daily': dict(daily),
        'by_model': dict(by_model),
        'by_caller': dict(by_caller),
        'available': total_calls > 0,
        'note': note
    }


def collect_ollama():
    """~/.claude/cache/gemma-calls.jsonl 에서 호출 집계"""
    path = os.path.expanduser("~/.claude/cache/gemma-calls.jsonl")
    if not os.path.exists(path):
        return {'total': {'calls': 0}, 'daily': {}, 'by_caller': {}, 'available': False}

    daily = defaultdict(lambda: {'calls': 0, 'duration_ms': 0, 'in_tokens': 0, 'out_tokens': 0})
    by_caller = defaultdict(lambda: {'calls': 0, 'duration_ms': 0})
    total_calls = 0
    total_duration = 0

    try:
        with open(path) as f:
            for line in f:
                try:
                    d = json.loads(line)
                except Exception:
                    continue
                ts = d.get('timestamp', '')
                if not ts or len(ts) < 10:
                    continue
                day = ts[:10]
                dur = d.get('duration_ms', 0) or 0
                inp = d.get('input_tokens') or 0
                out = d.get('output_tokens') or 0
                caller = d.get('caller', 'unknown')

                daily[day]['calls'] += 1
                daily[day]['duration_ms'] += dur
                daily[day]['in_tokens'] += inp
                daily[day]['out_tokens'] += out
                by_caller[caller]['calls'] += 1
                by_caller[caller]['duration_ms'] += dur
                total_calls += 1
                total_duration += dur
    except Exception:
        pass

    return {
        'total': {'calls': total_calls, 'duration_ms': total_duration},
        'daily': dict(daily),
        'by_caller': dict(by_caller),
        'available': total_calls > 0,
        'note': '부분 기록 — 다른 ollama hook들은 이 파일에 안 씀'
    }


def collect_llm_adapter():
    """Common shell adapter telemetry from ~/.claude/cache/llm-adapter-calls.jsonl."""
    path = os.path.expanduser("~/.claude/cache/llm-adapter-calls.jsonl")
    daily = defaultdict(lambda: {
        'calls': 0,
        'ok': 0,
        'error': 0,
        'timeout': 0,
        'duration_ms': 0,
        'timeout_seconds': 0,
        'prompt_length': 0,
        'response_length': 0,
        'output_bytes': 0,
    })
    by_provider = defaultdict(lambda: {
        'calls': 0,
        'ok': 0,
        'error': 0,
        'timeout': 0,
        'duration_ms': 0,
        'prompt_length': 0,
        'response_length': 0,
        'output_bytes': 0,
    })
    by_caller = defaultdict(lambda: {
        'calls': 0,
        'ok': 0,
        'error': 0,
        'timeout': 0,
        'duration_ms': 0,
    })
    by_adapter = defaultdict(lambda: {'calls': 0, 'ok': 0, 'error': 0, 'timeout': 0})
    total = {
        'calls': 0,
        'ok': 0,
        'error': 0,
        'timeout': 0,
        'duration_ms': 0,
        'timeout_seconds': 0,
        'prompt_length': 0,
        'response_length': 0,
        'output_bytes': 0,
    }
    schema_versions = set()

    for d in iter_jsonl(path) or []:
        ts = d.get('timestamp', '')
        if not ts or len(ts) < 10:
            continue
        day = ts[:10]
        schema_versions.add(d.get('schema_version'))
        provider = d.get('provider') or 'unknown'
        adapter = d.get('adapter') or 'unknown'
        caller = d.get('caller') or 'unknown'
        exit_code = as_int(d.get('exit_code'))
        status = d.get('status') or ('ok' if exit_code == 0 else 'error')
        ok = status == 'ok' and exit_code == 0
        timed_out = status == 'timeout' or exit_code == 124
        duration_ms = as_int(d.get('duration_ms'))
        timeout_seconds = as_int(d.get('timeout_seconds'))
        prompt_length = as_int(d.get('prompt_length'))
        response_length = as_int(d.get('response_length'))
        output_bytes = as_int(d.get('output_bytes'))

        for bucket in (daily[day], by_provider[provider], total):
            bucket['calls'] += 1
            bucket['ok'] += 1 if ok else 0
            bucket['error'] += 0 if ok else 1
            bucket['timeout'] += 1 if timed_out else 0
            bucket['duration_ms'] += duration_ms
            bucket['prompt_length'] += prompt_length
            bucket['response_length'] += response_length
            bucket['output_bytes'] += output_bytes
        daily[day]['timeout_seconds'] += timeout_seconds
        total['timeout_seconds'] += timeout_seconds
        by_caller[caller]['calls'] += 1
        by_caller[caller]['ok'] += 1 if ok else 0
        by_caller[caller]['error'] += 0 if ok else 1
        by_caller[caller]['timeout'] += 1 if timed_out else 0
        by_caller[caller]['duration_ms'] += duration_ms
        by_adapter[adapter]['calls'] += 1
        by_adapter[adapter]['ok'] += 1 if ok else 0
        by_adapter[adapter]['error'] += 0 if ok else 1
        by_adapter[adapter]['timeout'] += 1 if timed_out else 0

    if total['calls']:
        thresholds = load_llm_adapter_thresholds()
        total['success_rate'] = total['ok'] / total['calls']
        total['error_rate'] = total['error'] / total['calls']
        total['timeout_rate'] = total['timeout'] / total['calls']
        total['avg_duration_ms'] = total['duration_ms'] / total['calls']
        for bucket in by_provider.values():
            bucket['success_rate'] = bucket['ok'] / bucket['calls'] if bucket['calls'] else 0.0
            bucket['error_rate'] = bucket['error'] / bucket['calls'] if bucket['calls'] else 0.0
            bucket['timeout_rate'] = bucket['timeout'] / bucket['calls'] if bucket['calls'] else 0.0
            bucket['avg_duration_ms'] = bucket['duration_ms'] / bucket['calls'] if bucket['calls'] else 0.0
        health = evaluate_adapter_health(total, by_provider, thresholds)
        note = f"{path} ({total['calls']} calls)"
    elif os.path.exists(path):
        thresholds = load_llm_adapter_thresholds()
        total['success_rate'] = 0.0
        total['error_rate'] = 0.0
        total['timeout_rate'] = 0.0
        total['avg_duration_ms'] = 0.0
        health = evaluate_adapter_health(total, by_provider, thresholds)
        note = f"{path} exists but has no valid records"
    else:
        thresholds = load_llm_adapter_thresholds()
        total['success_rate'] = 0.0
        total['error_rate'] = 0.0
        total['timeout_rate'] = 0.0
        total['avg_duration_ms'] = 0.0
        health = evaluate_adapter_health(total, by_provider, thresholds)
        note = f"{path} not created yet"

    return {
        'total': total,
        'daily': dict(daily),
        'by_provider': dict(by_provider),
        'by_caller': dict(by_caller),
        'by_adapter': dict(by_adapter),
        'thresholds': thresholds,
        'health': health,
        'schema_versions': sorted(v for v in schema_versions if v is not None),
        'available': total['calls'] > 0,
        'note': note,
    }


def fmt_tokens(n):
    if n >= 1_000_000_000:
        return f"{n/1_000_000_000:.2f}B"
    if n >= 1_000_000:
        return f"{n/1_000_000:.2f}M"
    if n >= 1_000:
        return f"{n/1_000:.1f}K"
    return str(n)


def print_human(data, days):
    cc = data['claude_code']
    cx = data['codex']
    ol = data['ollama']
    ad = data['llm_adapter']

    today = datetime.now().date()
    cutoff = today - timedelta(days=days)

    print("=" * 70)
    print("LLM 사용량 종합")
    print("=" * 70)

    # Claude Code
    t = cc['total']
    total_tokens_cc = t['in'] + t['out'] + t['cache_r'] + t['cache_c']
    print(f"\n📘 Claude Code (누적)")
    print(f"   세션 {t['sessions']:,} / 턴 {t['turns']:,}")
    print(f"   Input        {fmt_tokens(t['in']):>10}")
    print(f"   Output       {fmt_tokens(t['out']):>10}")
    print(f"   Cache Read   {fmt_tokens(t['cache_r']):>10}")
    print(f"   Cache Create {fmt_tokens(t['cache_c']):>10}")
    print(f"   ───────────────────────")
    print(f"   합계         {fmt_tokens(total_tokens_cc):>10}")
    print(f"   💰 비용      ${t.get('cost', 0):.2f}")
    # 프로젝트별 TOP 5
    bp = cc.get('by_project', {})
    if bp:
        print(f"   프로젝트 TOP 5 (비용):")
        for proj, p in sorted(bp.items(), key=lambda x: -x[1].get('cost', 0))[:5]:
            print(f"     {proj[:50]:50s} {fmt_tokens(p['tokens']):>8} / ${p.get('cost', 0):>8.2f}")

    # Codex
    print(f"\n📗 Codex / GPT (누적)")
    if cx.get('available'):
        ct = cx['total']
        print(f"   세션 {ct.get('sessions', 0):,} / 토큰 {fmt_tokens(ct.get('tokens', 0))} / 💰 ${ct.get('cost', 0):.2f}")
        print(f"   모델별:")
        for model, m in sorted(cx['by_model'].items(), key=lambda x: -x[1].get('cost', 0)):
            print(f"     {model:20s} {m['sessions']:>4}세션 / {fmt_tokens(m['tokens']):>8} / ${m.get('cost', 0):>7.2f}")
    else:
        print("   (데이터 없음)")

    # Gemini
    gm = data['gemini']
    print(f"\n📕 Gemini")
    if gm.get('available'):
        gt = gm['total']
        print(f"   호출 {gt['calls']:,} / 토큰 {fmt_tokens(gt['tokens'])} / 💰 ${gt.get('cost', 0):.4f}")
        if gm.get('by_model'):
            print(f"   모델별:")
            for model, m in sorted(gm['by_model'].items(), key=lambda x: -x[1].get('cost', 0)):
                print(f"     {model:25s} {m['calls']:>4}회 / {fmt_tokens(m['tokens']):>7} / ${m.get('cost', 0):>7.4f}")
        print(f"   ⚠️  {gm.get('note','')}")
    else:
        print(f"   ⚠️  {gm.get('note','wrapper 미사용')}")
        print(f"        해결: ~/.claude/scripts/gemini-wrapped.sh 사용 또는 telemetry 활성화")

    # Ollama
    print(f"\n📙 Ollama (로컬)")
    if ol.get('available'):
        ot = ol['total']
        print(f"   호출 {ot['calls']:,} / 누적 시간 {ot['duration_ms']/1000:.1f}초")
        print(f"   ⚠️  {ol.get('note','')}")
    else:
        print(f"   ⚠️  부분 기록만 — gemma-calls.jsonl 비어있음")

    # LLM adapter telemetry
    print(f"\n🔌 LLM Adapter Telemetry")
    at = ad['total']
    if ad.get('available'):
        print(
            f"   호출 {at['calls']:,} / 성공 {at['ok']:,} / 실패 {at['error']:,} "
            f"/ 성공률 {at.get('success_rate', 0.0) * 100:.1f}% "
            f"/ 평균 {at.get('avg_duration_ms', 0.0):.0f}ms"
        )
        health = ad.get('health', {})
        print(f"   Health: {health.get('overall', 'unknown')}")
        for alert in health.get('alerts', [])[:5]:
            reasons = ",".join(alert.get('reasons', [])) or "threshold"
            print(
                f"     {alert.get('scope')}:{alert.get('name')} "
                f"{alert.get('severity')} ({reasons}) "
                f"err={alert.get('error_rate', 0.0) * 100:.1f}% "
                f"timeout={alert.get('timeout_rate', 0.0) * 100:.1f}% "
                f"avg={alert.get('avg_duration_ms', 0.0):.0f}ms"
            )
        print("   Provider별:")
        for provider, p in sorted(ad['by_provider'].items(), key=lambda x: -x[1].get('calls', 0)):
            print(
                f"     {provider:12s} {p['calls']:>4}회 / "
                f"성공률 {p.get('success_rate', 0.0) * 100:>5.1f}% / "
                f"timeout {p.get('timeout_rate', 0.0) * 100:>5.1f}% / "
                f"평균 {p.get('avg_duration_ms', 0.0):>7.0f}ms"
            )
        callers = sorted(ad['by_caller'].items(), key=lambda x: -x[1].get('calls', 0))[:5]
        if callers:
            print("   Caller TOP 5:")
            for caller, c in callers:
                print(f"     {caller[:36]:36s} {c['calls']:>4}회 / 실패 {c['error']:>3}")
    else:
        print(f"   ⚠️  {ad.get('note','adapter 로그 없음')}")

    # 일별 요약
    print(f"\n📊 최근 {days}일 일별 사용량")
    all_days = set()
    for src in [cc['daily'], cx.get('daily', {}), data['gemini'].get('daily', {}), ol.get('daily', {}), ad.get('daily', {})]:
        for d in src.keys():
            try:
                if datetime.strptime(d, "%Y-%m-%d").date() >= cutoff:
                    all_days.add(d)
            except Exception:
                pass

    print(f"   {'날짜':12s} {'Claude턴':>8s} {'Claude $':>9s} {'Codex세션':>9s} {'Codex $':>9s} {'Gemini':>7s} {'Adapter':>8s} {'실패':>5s} {'합계 $':>8s}")
    grand_total = 0.0
    for day in sorted(all_days, reverse=True)[:days]:
        cc_d = cc['daily'].get(day, {})
        cx_d = cx.get('daily', {}).get(day, {})
        gm_d = data['gemini'].get('daily', {}).get(day, {})
        ad_d = ad.get('daily', {}).get(day, {})
        cc_turns = cc_d.get('turns', 0)
        cc_cost = cc_d.get('cost', 0.0)
        cx_cost = cx_d.get('cost', 0.0)
        gm_cost = gm_d.get('cost', 0.0)
        day_total = cc_cost + cx_cost + gm_cost
        grand_total += day_total
        print(f"   {day:12s} {cc_turns:>8,} {'$'+f'{cc_cost:.2f}':>9s} "
              f"{cx_d.get('sessions',0):>9,} {'$'+f'{cx_cost:.2f}':>9s} "
              f"{'$'+f'{gm_cost:.4f}':>7s} {ad_d.get('calls',0):>8,} "
              f"{ad_d.get('error',0):>5,} {'$'+f'{day_total:.2f}':>8s}")
    print(f"   {'─'*70}")
    print(f"   {'기간 합계':12s} {'':>8s} {'':>9s} {'':>9s} {'':>9s} {'':>7s} {'$'+f'{grand_total:.2f}':>8s}")

    print()
    print("📁 데이터 출처:")
    print("   Claude Code: ~/.claude/projects/**/*.jsonl  (message.usage)")
    print("   Codex:       ~/.codex/state_5.sqlite        (threads.tokens_used)")
    print("   Gemini:      ~/.claude/cache/gemini-telemetry.jsonl  (gemini_cli.api_response, telemetry)")
    print("                + ~/.claude/cache/gemini-calls.jsonl    (gemini-wrapped.sh, caller 식별용)")
    print("                + ~/.claude/cache/agy-calls.jsonl       (Antigravity CLI, 2026-06-18부터 기본)")
    print("   Ollama:      ~/.claude/cache/gemma-calls.jsonl       (부분 기록)")
    print("   Adapter:     ~/.claude/cache/llm-adapter-calls.jsonl (provider/caller/status/duration)")
    print("❌ GPT 직접:    별도 인증 안 됨 — Codex가 곧 GPT 사용량")


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--json', action='store_true', help='JSON 출력 (대시보드용)')
    p.add_argument('--days', type=int, default=14, help='일별 표시 일수 (기본 14일)')
    args = p.parse_args()

    data = {
        'claude_code': collect_claude_code(),
        'codex': collect_codex(),
        'gemini': collect_gemini(),
        'ollama': collect_ollama(),
        'llm_adapter': collect_llm_adapter(),
        'generated_at': datetime.now().isoformat()
    }

    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2))
    else:
        print_human(data, args.days)


if __name__ == '__main__':
    main()
