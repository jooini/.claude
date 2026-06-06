#!/usr/bin/env node
'use strict';

const fs = require('fs');
const { spawnSync } = require('child_process');

const DEFAULT_TIMEOUT_MS = 120000;
const DEFAULT_RETRY_LIMIT = 5;

const PHASE_DEFAULT_RUNNER = {
  scan: 'agy',
  analyze: 'agy',
  investigate: 'agy',
  edit: 'codex',
  refactor: 'codex',
  implement: 'codex',
  review: 'codex',
  handoff: 'codex',
  validate: 'codex',
  test: 'codex',
  rollback: 'codex',
};

function taskPrompt(task, phase) {
  const input = task.payload.input || task.payload.instructions || '';
  return `moai ${phase} task ${task.task_id} :: ${input}`.trim();
}

function codexPrompt(task, phase) {
  return [
    `moai ${task.task_id}`,
    `phase: ${phase}`,
    `source: ${task.metadata?.source || 'unknown'}`,
    `labels: ${(task.metadata?.labels || []).join(', ') || 'none'}`,
    '',
    'input:',
    task.payload.input || '(empty)',
    '',
    'instructions:',
    task.payload.instructions || '(empty)',
  ].join('\n');
}

const DEFAULT_COMMANDS = {
  agy: {
    default: {
      command: 'agy',
      argv: (task) => ['--print', taskPrompt(task, task.phase)],
      source: 'agy-default',
      useShell: false,
    },
    scan: {
      command: 'agy',
      argv: (task) => ['--print', `scan request for ${task.task_id}: ${task.payload.input || task.payload.instructions || 'repository scan'}`],
      source: 'agy-default',
      useShell: false,
    },
    analyze: {
      command: 'agy',
      argv: (task) => ['--print', `analysis request for ${task.task_id}: TODO/FIXME/HACK scan`],
      source: 'agy-default',
      useShell: false,
    },
    investigate: {
      command: 'agy',
      argv: (task) => ['--print', `investigate request for ${task.task_id}: ${task.payload.input || task.payload.instructions || ''}`],
      source: 'agy-default',
      useShell: false,
    },
    edit: {
      command: 'agy',
      argv: (task) => ['--print', `edit task ${task.task_id}: ${task.payload.input || task.payload.instructions || ''}`],
      source: 'agy-default',
      useShell: false,
    },
    refactor: {
      command: 'agy',
      argv: (task) => ['--print', `refactor task ${task.task_id}: ${task.payload.input || task.payload.instructions || ''}`],
      source: 'agy-default',
      useShell: false,
    },
    implement: {
      command: 'agy',
      argv: (task) => ['--print', `implement task ${task.task_id}: ${task.payload.input || task.payload.instructions || ''}`],
      source: 'agy-default',
      useShell: false,
    },
    review: {
      command: 'agy',
      argv: (task) => ['--print', `review task ${task.task_id}: ${task.payload.input || task.payload.instructions || ''}`],
      source: 'agy-default',
      useShell: false,
    },
    handoff: {
      command: 'agy',
      argv: (task) => ['--print', `handoff task ${task.task_id}: ${task.payload.input || task.payload.instructions || ''}`],
      source: 'agy-default',
      useShell: false,
    },
    validate: {
      command: 'agy',
      argv: (task) => ['--print', `validate task ${task.task_id}: ${task.payload.input || task.payload.instructions || ''}`],
      source: 'agy-default',
      useShell: false,
    },
    test: {
      command: 'agy',
      argv: (task) => ['--print', `test task ${task.task_id}: ${task.payload.input || task.payload.instructions || ''}`],
      source: 'agy-default',
      useShell: false,
    },
    rollback: {
      command: 'agy',
      argv: (task) => ['--print', `rollback task ${task.task_id}: ${task.payload.input || task.payload.instructions || ''}`],
      source: 'agy-default',
      useShell: false,
    },
  },
  codex: {
    default: {
      command: 'codex',
      argv: (task) => ['exec', '--skip-git-repo-check', '--ephemeral', '--', codexPrompt(task, task.phase)],
      source: 'codex-default',
      useShell: false,
    },
    scan: {
      command: 'codex',
      argv: (task) => ['exec', '--skip-git-repo-check', '--ephemeral', '--', codexPrompt(task, task.phase)],
      source: 'codex-default',
      useShell: false,
    },
    analyze: {
      command: 'codex',
      argv: (task) => ['exec', '--skip-git-repo-check', '--ephemeral', '--', codexPrompt(task, task.phase)],
      source: 'codex-default',
      useShell: false,
    },
    investigate: {
      command: 'codex',
      argv: (task) => ['exec', '--skip-git-repo-check', '--ephemeral', '--', codexPrompt(task, task.phase)],
      source: 'codex-default',
      useShell: false,
    },
    edit: {
      command: 'codex',
      argv: (task) => ['exec', '--skip-git-repo-check', '--ephemeral', '--', codexPrompt(task, task.phase)],
      source: 'codex-default',
      useShell: false,
    },
    refactor: {
      command: 'codex',
      argv: (task) => ['exec', '--skip-git-repo-check', '--ephemeral', '--', codexPrompt(task, task.phase)],
      source: 'codex-default',
      useShell: false,
    },
    implement: {
      command: 'codex',
      argv: (task) => ['exec', '--skip-git-repo-check', '--ephemeral', '--', codexPrompt(task, task.phase)],
      source: 'codex-default',
      useShell: false,
    },
    review: {
      command: 'codex',
      argv: (task) => ['review', '--uncommitted', '--', `review request for ${task.task_id}: ${summary(task.payload.input || task.payload.instructions || '')}`],
      source: 'codex-default',
      useShell: false,
    },
    handoff: {
      command: 'codex',
      argv: (task) => ['exec', '--skip-git-repo-check', '--ephemeral', '--', codexPrompt(task, task.phase)],
      source: 'codex-default',
      useShell: false,
    },
    validate: {
      command: 'npm',
      argv: () => ['run', 'lint'],
      source: 'codex-default',
      useShell: false,
    },
    test: {
      command: 'npm',
      argv: () => ['test'],
      source: 'codex-default',
      useShell: false,
    },
    rollback: {
      command: 'git',
      argv: () => ['status', '--short'],
      source: 'codex-default',
      useShell: false,
    },
  },
};

function parseArgs() {
  const args = process.argv.slice(2);
  const parsed = {};

  for (let i = 0; i < args.length; i += 1) {
    const arg = args[i];

    if (arg === '--help' || arg === '-h') {
      parsed.help = true;
      continue;
    }

    if (!arg.startsWith('--')) {
      continue;
    }

    const key = arg.slice(2);
    const next = args[i + 1];
    if (next && !next.startsWith('--')) {
      parsed[key] = next;
      i += 1;
    } else {
      parsed[key] = true;
    }
  }

  return parsed;
}

function readInput(taskPath) {
  if (taskPath) {
    return fs.readFileSync(taskPath, 'utf8');
  }
  return fs.readFileSync(0, 'utf8');
}

function first(value, ...rest) {
  for (const current of [value, ...rest]) {
    if (typeof current === 'string' && current.trim() !== '') {
      return current.trim();
    }
  }
  return undefined;
}

function toInt(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.max(1, Math.trunc(parsed)) : fallback;
}

function toRetry(value, fallback) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed) || parsed < 0) {
    return fallback;
  }
  return Math.min(DEFAULT_RETRY_LIMIT, Math.trunc(parsed));
}

function toIntNoNegative(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? Math.max(0, Math.trunc(parsed)) : fallback;
}

function normalizePhase(value) {
  const v = first(value, 'handoff').toLowerCase();
  const allowed = Object.keys(PHASE_DEFAULT_RUNNER);
  if (allowed.includes(v)) return v;
  if (v === 'read') return 'scan';
  if (v === 'write') return 'implement';
  return 'handoff';
}

function normalizeRunner(value) {
  const normalized = first(value, 'auto').toLowerCase();
  if (normalized === 'codex' || normalized === 'agy') return normalized;
  return 'auto';
}

function normalizePreferred(value) {
  if (!Array.isArray(value) || value.length === 0) {
    return ['codex', 'agy'];
  }
  const filtered = value.filter((runner) => runner === 'codex' || runner === 'agy');
  if (filtered.length === 0) return ['codex', 'agy'];
  const deduped = [];
  for (const item of filtered) {
    if (!deduped.includes(item)) deduped.push(item);
  }
  return deduped;
}

function normalizeTask(raw) {
  const now = new Date().toISOString();
  const taskId = first(raw.task_id, raw.id, `task-${Date.now()}`);
  const phase = normalizePhase(first(raw.phase, raw.stage, raw.step, raw.type));

  return {
    schema_version: first(raw.schema_version, '1.0'),
    task_id: taskId,
    phase,
    runner: normalizeRunner(first(raw.runner, raw.runner_hint)),
    preferred_runners: normalizePreferred(raw.preferred_runners),
    metadata: {
      source: first(raw.source, 'moai-adk'),
      origin_task: first(raw.origin_task, taskId),
      labels: Array.isArray(raw.labels) ? raw.labels.filter((label) => typeof label === 'string') : [],
    },
    context: {
      cwd: first(raw.cwd, raw.working_directory, process.cwd()),
      timeout_ms: toInt(raw.timeout_ms, toInt(raw.timeout, DEFAULT_TIMEOUT_MS)),
      dry_run: Boolean(raw.dry_run),
      constraints: Array.isArray(raw.constraints) ? raw.constraints.filter((value) => typeof value === 'string') : [],
      retry: toRetry(raw.retry, 1),
    },
    payload: {
      input: first(raw.input, raw.task, raw.instructions, raw.prompt, ''),
      instructions: first(raw.instructions, ''),
      command: typeof raw.command === 'string' ? raw.command : null,
      command_argv: Array.isArray(raw.command_argv) ? raw.command_argv.filter((value) => typeof value === 'string') : null,
      artifacts: Array.isArray(raw.payload_artifacts)
        ? raw.payload_artifacts
        : Array.isArray(raw.artifacts)
          ? raw.artifacts
          : [],
    },
    state: {
      task_id: taskId,
      phase,
      last_step: first(raw.last_step, raw.state?.last_step, 'received'),
      timestamp: first(raw.timestamp, raw.state?.timestamp, now),
      next_action: first(raw.next_action, raw.state?.next_action, 'run'),
      artifacts: Array.isArray(raw.state?.artifacts) ? raw.state.artifacts : [],
      retry_count: toIntNoNegative(raw.state?.retry_count, 0),
    },
  };
}

function shellQuoted(value) {
  return `'${String(value).replaceAll("'", "'\\''")}'`;
}

function commandDisplay(command, argv) {
  const args = Array.isArray(argv) ? argv : [];
  return [command, ...args].map((part) => {
    if (typeof part !== 'string') {
      return String(part);
    }
    if (/\s/.test(part)) {
      return shellQuoted(part);
    }
    return part;
  }).join(' ').trim();
}

function summary(text) {
  const source = first(text, '') || '';
  return source.length > 120 ? `${source.slice(0, 117)}...` : source;
}

function commandTemplate(task, runner) {
  if (typeof task.payload.command === 'string' && task.payload.command.trim() !== '') {
    const command = task.payload.command.trim();
    const argv = task.payload.command_argv || [];
    return {
      command,
      argv,
      useShell: command.includes(' ') && argv.length === 0,
      source: 'payload',
    };
  }

  const runnerTemplates = DEFAULT_COMMANDS[runner] || DEFAULT_COMMANDS.codex;
  const mapping = runnerTemplates[task.phase] || runnerTemplates.default;
  const argvTemplate = mapping?.argv || (() => []);
  const argv = Array.isArray(argvTemplate)
    ? argvTemplate
    : typeof argvTemplate === 'function'
      ? argvTemplate(task)
      : [];

  return {
    command: mapping?.command || 'echo',
    argv,
    useShell: Boolean(mapping?.useShell),
    source: mapping?.source || `${runner}-default`,
  };
}

function selectPrimaryRunner(task) {
  if (task.runner === 'auto') {
    return PHASE_DEFAULT_RUNNER[task.phase] || 'codex';
  }
  return task.runner;
}

function selectRunners(task, primary) {
  const seen = new Set();
  const list = [];
  const push = (value) => {
    if (!seen.has(value)) {
      seen.add(value);
      list.push(value);
    }
  };

  push(primary);

  if (task.context.retry > 0) {
    for (const runner of task.preferred_runners) {
      push(runner);
    }
    push(primary === 'codex' ? 'agy' : 'codex');
  }

  return task.context.retry > 0 ? list.slice(0, 2) : [primary];
}

function runCommand(command, argv, cwd, timeoutMs, dryRun, useShell) {
  const startedAt = Date.now();
  const preparedArgv = Array.isArray(argv) ? argv : [];
  const display = commandDisplay(command, preparedArgv);

  if (dryRun) {
    return {
      code: 0,
      stdout: `[dry-run] ${display}`,
      stderr: '',
      duration_ms: 0,
    };
  }

  const result = spawnSync(command, preparedArgv, {
    cwd,
    timeout: timeoutMs,
    encoding: 'utf8',
    shell: useShell,
    maxBuffer: 1024 * 1024 * 20,
    env: process.env,
  });

  if (result.error) {
    throw result.error;
  }

  return {
    code: result.status ?? 1,
    stdout: result.stdout || '',
    stderr: result.stderr || '',
    duration_ms: Date.now() - startedAt,
  };
}

function buildArtifacts(task, runner, command, commandArgv, execution) {
  return [
    {
      type: 'command',
      source: runner,
      summary: `phase=${task.phase}, task=${task.task_id}`,
      command: commandDisplay(command, commandArgv),
      stdout_excerpt: String(execution.stdout || '').split('\n').slice(0, 3).join('\n'),
    },
  ];
}

function buildRetryPlan(task, attempts, maxAttempts) {
  return {
    retry_count: attempts,
    remaining: Math.max(0, task.context.retry - attempts),
    max_attempts: maxAttempts,
  };
}

function executeTask(task) {
  const primaryRunner = selectPrimaryRunner(task);
  const runners = selectRunners(task, primaryRunner);
  const attemptLimit = Math.min(runners.length, task.context.retry + 1);
  let lastResult = null;

  for (let i = 0; i < attemptLimit; i += 1) {
    const runner = runners[i];
    const command = commandTemplate(task, runner);
    const startedAt = new Date().toISOString();
    const execution = runCommand(
      command.command,
      command.argv,
      task.context.cwd,
      task.context.timeout_ms,
      task.context.dry_run,
      command.useShell,
    );
    const artifacts = buildArtifacts(task, runner, command.command, command.argv, execution);

    const result = {
      status: execution.code === 0 ? 'succeeded' : 'failed',
      artifacts,
      next_step: execution.code === 0 ? task.state.next_action : 'retry_or_escalate',
      state: {
        task_id: task.task_id,
        phase: task.phase,
        last_step: `${task.state.last_step}#${runner}#${i + 1}`,
        timestamp: new Date().toISOString(),
        artifacts: artifacts.map((item) => item.type),
        next_action: task.state.next_action,
      },
      logs: [
        {
          level: execution.code === 0 ? 'info' : 'error',
          runner,
          command,
          started_at: startedAt,
          duration_ms: execution.duration_ms,
          code: execution.code,
          message: command.source,
        },
      ],
      error_summary: execution.code === 0 ? null : execution.stderr || execution.stdout,
      retry_plan: buildRetryPlan(task, i + 1, attemptLimit),
    };

    lastResult = result;

    if (execution.code === 0) {
      return result;
    }
  }

  return lastResult;
}

function printUsage() {
  const lines = [
    'Usage:',
    '  node run.js --task /path/to/task.json',
    '  cat task.json | node run.js',
    '',
    'Options:',
    '  --task    Input task path (or read from stdin)',
    '  -h, --help  show this help',
  ];
  process.stdout.write(`${lines.join('\n')}\n`);
}

function main() {
  const args = parseArgs();

  if (args.help) {
    printUsage();
    return;
  }

  let rawTask;
  try {
    const rawInput = readInput(args.task);
    if (!rawInput.trim()) {
      throw new Error('empty input');
    }
    rawTask = JSON.parse(rawInput);
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    process.stderr.write(`run error: ${msg}\n`);
    process.exit(1);
  }

  const task = rawTask.schema_version ? rawTask : normalizeTask(rawTask);

  try {
    const output = executeTask(task);
    process.stdout.write(`${JSON.stringify(output, null, 2)}\n`);
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    process.stdout.write(`${JSON.stringify({
      status: 'failed',
      artifacts: [],
      next_step: 'retry_or_escalate',
      state: {
        task_id: task.task_id,
        phase: task.phase,
        last_step: `${task.state.last_step}#error`,
        timestamp: new Date().toISOString(),
        artifacts: [],
        next_action: task.state.next_action,
      },
      logs: [{ level: 'error', message: msg, duration_ms: 0 }],
      error_summary: msg,
      retry_plan: {
        retry_count: 0,
        remaining: 0,
        max_attempts: 1,
      },
    }, null, 2)}\n`);
  }
}

main();
