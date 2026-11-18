#!/bin/sh
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
node "$project_dir/tests/require-runtime-node.mjs"
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
"${CXX:-c++}" -std=c++17 -I "$project_dir/entry/src/main/cpp" "$project_dir/tests/native/node-budget.cpp" -o "$scratch/node-budget"
"$scratch/node-budget" > "$scratch/budgets.txt"
node --input-type=module - "$scratch/budgets.txt" <<'JS'
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
const budgets = [...new Set(readFileSync(process.argv[2], 'utf8').trim().split('\n').map(Number))];
let overhead;
for (const budget of budgets) {
  const actual = Number(execFileSync(process.execPath, ['--jitless', '--no-addons', `--max-old-space-size=${budget}`, '-p', 'require("node:v8").getHeapStatistics().heap_size_limit'], { stdio: ['ignore', 'pipe', 'ignore'] }));
  // heap_size_limit also includes V8's young generation, sized by this host.
  // Compare the exact old-space delta rather than assuming a particular V8 young-space default.
  const extra = actual - budget * 1024 * 1024;
  assert.ok(extra > 0 && extra <= 512 * 1024 * 1024, `Unexpected aggregate V8 limit: ${actual}`);
  if (overhead === undefined) overhead = extra;
  else assert.equal(extra, overhead, `V8 did not apply the ${budget} MiB old-space change`);
}
console.log('PASS fixed C++ physical-memory boundaries and actual jitless Node old-space startup:', budgets.join(', '), 'MiB');
JS
