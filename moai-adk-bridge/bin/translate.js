#!/usr/bin/env node
'use strict';

const fs = require('fs');

function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = {};

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];

    if (arg === '--help' || arg === '-h') {
      parsed.help = true;
      continue;
    }

    if (arg.startsWith('--')) {
      const key = arg.slice(2);
      const next = args[i + 1];
      if (!next || next.startsWith('--')) {
        parsed[key] = true;
      } else {
        parsed[key] = next;
        i += 1;
      }
    }
  }

  return parsed;
}

function readInput(argvInput) {
  if (argvInput) {
    return fs.readFileSync(argvInput, 'utf8');
  }

  return fs.readFileSync(0, 'utf8');
}

function toStringOrDefault(...values) {
  for (const value of values) {
    if (typeof value === 'string' && value.trim() !== '') {
      return value.trim();
    }
  }
  return undefined;
}

function normalizeRunner(raw) {
  const value = toStringOrDefault(raw?.runner_hint, raw?.runner)?.toLowerCase();
  if (value === 'codex' || value === 'agy') return value;
  return 'auto';
}

function normalizePhase(value) {
  const phase = toStringOrDefault(value, 'handoff')?.toLowerCase();
  const allowed = [
    'scan',
    'analyze',
    'investigate',
    'edit',
    'refactor',
    'implement',
    'review',
    'handoff',
    'validate',
    'test',
    'rollback',
  ];

  if (allowed.includes(phase)) {
    return phase;
  }
  if (phase === 'read') return 'scan';
  if (phase === 'write') return 'implement';
  return 'handoff';
}

function normalizePreferredRunners(rawRunner, preferred) {
  const candidates = [];
  const addIfValid = (value) => {
    const next = toStringOrDefault(value, '').toLowerCase();
    if ((next === 'codex' || next === 'agy') && !candidates.includes(next)) {
      candidates.push(next);
    }
  };

  if (Array.isArray(preferred)) {
    preferred.forEach(addIfValid);
  }
  addIfValid(rawRunner);

  if (candidates.length === 0) {
    return ['codex', 'agy'];
  }

  return candidates;
}

function normalizeTimeout(value) {
  const timeout = Number(value);
  if (Number.isFinite(timeout) && timeout > 0) {
    return Math.max(1000, Math.floor(timeout));
  }
  return 120000;
}

function normalizeMetadata(raw) {
  const source = toStringOrDefault(raw.source, 'moai-adk');
  return {
    source,
    origin_task: toStringOrDefault(raw.origin_task, raw.task_id),
    labels: Array.isArray(raw.labels) ? raw.labels.filter((label) => typeof label === 'string') : [],
  };
}

function normalizeContext(raw, cwd) {
  return {
    cwd: toStringOrDefault(raw.cwd, raw.working_directory, cwd),
    timeout_ms: normalizeTimeout(raw.timeout_ms ?? raw.timeout ?? undefined),
    dry_run: Boolean(raw.dry_run ?? false),
    constraints: Array.isArray(raw.constraints) ? raw.constraints.filter((item) => typeof item === 'string') : [],
    retry: normalizeRetry(raw.retry_count ?? raw.retry),
  };
}

function normalizePayload(raw) {
  const input = toStringOrDefault(raw.input, raw.task, raw.prompt, raw.instructions, '');
  const instructions = toStringOrDefault(raw.instructions, raw.message, '');
  return {
    input,
    instructions,
    command: typeof raw.command === 'string' && raw.command.trim() !== '' ? raw.command.trim() : null,
    command_argv: Array.isArray(raw.command_argv) ? raw.command_argv.filter((item) => typeof item === 'string') : null,
    artifacts: Array.isArray(raw.payload?.artifacts)
      ? raw.payload.artifacts.filter((item) => typeof item === 'string')
      : Array.isArray(raw.artifacts)
        ? raw.artifacts.filter((item) => typeof item === 'string')
        : [],
  };
}

function normalizeState(raw, phase) {
  const now = new Date().toISOString();
  const taskId = toStringOrDefault(raw.task_id, raw.id, `task-${Date.now()}`);
  return {
    task_id: taskId,
    phase,
    last_step: toStringOrDefault(raw.last_step, raw.previous_step, 'received'),
    timestamp: toStringOrDefault(raw.timestamp, now),
    next_action: toStringOrDefault(raw.next_action, raw.state?.next_action, 'run'),
    artifacts: Array.isArray(raw.state_artifacts)
      ? raw.state_artifacts
      : Array.isArray(raw.state?.artifacts)
        ? raw.state.artifacts
        : [],
    retry_count: normalizeNumeric(raw.state_retry_count ?? raw.state?.retry_count, 0),
  };
}

function normalizeNumeric(value, fallback = 1) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function normalizeRetry(value, fallback = 1) {
  const normalized = normalizeNumeric(value, fallback);
  if (!Number.isFinite(normalized)) {
    return fallback;
  }
  const rounded = Math.trunc(normalized);
  if (rounded < 0) {
    return 0;
  }
  if (rounded > 5) {
    return 5;
  }
  return rounded;
}

function normalizeTaskEnvelope(raw, cwd) {
  const phase = normalizePhase(
    toStringOrDefault(raw.phase, raw.stage, raw.step, raw.state?.phase),
  );

  const taskId = toStringOrDefault(raw.task_id, raw.id, `task-${Date.now()}`);
  const runner = normalizeRunner(raw);

  return {
    schema_version: '1.0',
    task_id: taskId,
    phase,
    metadata: normalizeMetadata(raw),
    runner,
    preferred_runners: normalizePreferredRunners(runner, raw.preferred_runners),
    context: normalizeContext(raw, cwd),
    payload: normalizePayload(raw),
    state: normalizeState(raw, phase),
  };
}

function printUsage() {
  const usage = [
    'Usage:',
    '  node translate.js --input /path/to/task.json',
    '  cat task.json | node translate.js',
    '',
    'Options:',
    '  --input   Input file path (or read from stdin)',
    '  -h, --help  show this help',
  ];

  process.stdout.write(`${usage.join('\n')}\n`);
}

function main() {
  const args = parseArgs();

  if (args.help) {
    printUsage();
    return;
  }

  try {
    const rawInput = readInput(args.input);
    if (!rawInput.trim()) {
      throw new Error('empty input');
    }
    const raw = JSON.parse(rawInput);
    const envelope = normalizeTaskEnvelope(raw, process.cwd());
    process.stdout.write(`${JSON.stringify(envelope, null, 2)}\n`);
  } catch (error) {
    const err = error instanceof Error ? error.message : String(error);
    process.stderr.write(`translate error: ${err}\n`);
    process.exit(1);
  }
}

main();
