'use strict';
// Retention planner shared by every job of .github/workflows/clean-up.yml.
// Pure planning functions (no API calls) plus thin paginated listers, so the
// analyze preview and the deleting jobs always agree on what would be removed.

const DAY_MS = 24 * 60 * 60 * 1000;
const MB = 1024 * 1024;
const GB = 1024 * MB;

// Literal name of the rolling pins artifact written by build-kernel-release.yml
// (job record-last-successful-pins). Exempt from every clean-up path unless
// pin_policy == delete_pin.
const PINS_ARTIFACT = 'last-success-pins';

const CHOICES = {
  cleanup_type: ['cache_only', 'runs_only', 'full_cleanup', 'analyze_only'],
  cache_pattern: ['all_caches', 'ccache_only', 'ccache_stale', 'apt_only', 'kernel_only', 'old_only'],
  delete_order: ['oldest_first', 'newest_first', 'largest_first'],
  workflow_filter: ['ALL', 'build-kernel-release', 'patch-hygiene', 'sync-sanitize', 'clean-up', 'mirror-toolchains'],
  status_filter: ['all', 'failed_only', 'unsuccessful_only'],
  pin_policy: ['keep_pin', 'delete_pin'],
};

const UNSUCCESSFUL = new Set(['failure', 'cancelled', 'skipped']);

function parseCount(name, raw, fallback) {
  const s = String(raw === undefined || raw === null ? '' : raw).trim();
  if (s === '') return fallback;
  if (!/^\d+$/.test(s)) {
    throw new Error(`Input ${name} must be a non-negative integer, got '${s}'`);
  }
  return parseInt(s, 10);
}

function parseChoice(name, raw, fallback) {
  const s = String(raw === undefined || raw === null ? '' : raw).trim();
  if (s === '') return fallback;
  if (!CHOICES[name].includes(s)) {
    throw new Error(`Input ${name} must be one of ${CHOICES[name].join(' | ')}, got '${s}'`);
  }
  return s;
}

// All dispatch inputs arrive as CU_* environment variables (set at workflow level).
function readOptions(env = process.env) {
  return {
    cleanupType: parseChoice('cleanup_type', env.CU_CLEANUP_TYPE, 'cache_only'),
    deviceFilter: String(env.CU_DEVICE_FILTER || 'ALL').trim() || 'ALL',
    cachePattern: parseChoice('cache_pattern', env.CU_CACHE_PATTERN, 'all_caches'),
    cacheAgeDays: parseCount('cache_age_days', env.CU_CACHE_AGE_DAYS, 7),
    keepLastSuccessful: parseCount('keep_last_successful', env.CU_KEEP_LAST_SUCCESSFUL, 3),
    daysToKeep: parseCount('days_to_keep', env.CU_DAYS_TO_KEEP, 7),
    dryRun: env.CU_DRY_RUN === 'true',
    forceCleanup: env.CU_FORCE_CLEANUP === 'true',
    deleteOrder: parseChoice('delete_order', env.CU_DELETE_ORDER, 'oldest_first'),
    deleteCount: parseCount('delete_count', env.CU_DELETE_COUNT, 0),
    keepCount: parseCount('keep_count', env.CU_KEEP_COUNT, 0),
    minCacheSizeMb: parseCount('min_cache_size_mb', env.CU_MIN_CACHE_SIZE_MB, 0),
    workflowFilter: parseChoice('workflow_filter', env.CU_WORKFLOW_FILTER, 'ALL'),
    statusFilter: parseChoice('status_filter', env.CU_STATUS_FILTER, 'all'),
    artifactCleanup: env.CU_ARTIFACT_CLEANUP === 'true',
    artifactDaysToKeep: parseCount('artifact_days_to_keep', env.CU_ARTIFACT_DAYS_TO_KEEP, 30),
    pinPolicy: parseChoice('pin_policy', env.CU_PIN_POLICY, 'keep_pin'),
  };
}

// Rows for the "options in effect" table every job summary carries.
function optionRows(o) {
  return [
    ['cleanup_type', o.cleanupType],
    ['device_filter', o.deviceFilter],
    ['cache_pattern', o.cachePattern],
    ['cache_age_days', String(o.cacheAgeDays)],
    ['min_cache_size_mb', o.minCacheSizeMb === 0 ? '0 (disabled)' : String(o.minCacheSizeMb)],
    ['keep_count (per device)', o.keepCount === 0 ? '0 (disabled)' : String(o.keepCount)],
    ['delete_order', o.deleteOrder],
    ['delete_count', o.deleteCount === 0 ? '0 (unlimited)' : String(o.deleteCount)],
    ['workflow_filter', o.workflowFilter],
    ['status_filter', o.statusFilter],
    ['days_to_keep', o.daysToKeep === 0 ? '0 (no age gate)' : String(o.daysToKeep)],
    ['keep_last_successful', String(o.keepLastSuccessful)],
    ['artifact_cleanup', String(o.artifactCleanup)],
    ['artifact_days_to_keep', o.artifactDaysToKeep === 0 ? '0 (no age gate)' : String(o.artifactDaysToKeep)],
    ['pin_policy', o.pinPolicy],
    ['dry_run', String(o.dryRun)],
    ['force_cleanup', String(o.forceCleanup)],
  ];
}

const ageDays = (iso, now) => Math.floor((now - new Date(iso).getTime()) / DAY_MS);
const toMB = (b) => (b / MB).toFixed(2);
const toGB = (b) => (b / GB).toFixed(2);
const pct = (part, whole) => (whole > 0 ? `${((part / whole) * 100).toFixed(1)}%` : '0%');

function cacheCategory(key) {
  if (key.startsWith('ccache-')) return 'ccache';
  if (key.includes('apt')) return 'apt';
  if (key.includes('kernel') || key.includes('android')) return 'kernel';
  return 'other';
}

// Device bucket for a cache key. Build caches look like
// <ksu_type>-v3-[LTO-]<MODEL>-<OS>-<kernel>-<clang>; legacy keys look like ccache-<device>-...
function cacheDevice(key) {
  let m = key.match(/-v3-(?:LTO-)?(.+?)-[A-Z]+1\d-/);
  if (m) return m[1];
  m = key.match(/ccache-([^-]+)-/);
  if (m) return m[1];
  return key.split('-')[0] || key;
}

// Device + pattern + age gate, unchanged from the pre-matrix cleaner.
function cacheMatches(cache, o, now) {
  const key = cache.key;
  const created = new Date(cache.created_at).getTime();
  const cutoff = now - o.cacheAgeDays * DAY_MS;
  const staleCutoff = now - 14 * DAY_MS;

  const deviceMatch =
    o.deviceFilter === 'ALL' ||
    key.includes(o.deviceFilter) ||
    key.includes(`-${o.deviceFilter}-`) ||
    key.startsWith(`${o.deviceFilter}-`);
  if (!deviceMatch) return false;

  switch (o.cachePattern) {
    case 'ccache_only':
      return key.startsWith('ccache-');
    case 'ccache_stale':
      return key.startsWith('ccache-') && created < staleCutoff;
    case 'apt_only':
      return key.includes('apt-cache') || key.includes('apt-');
    case 'kernel_only':
      return key.includes('kernel-') || key.includes('android') || key.startsWith('ccache-');
    case 'old_only':
      return created < cutoff;
    case 'all_caches':
    default:
      return true;
  }
}

function orderBy(list, order) {
  const created = (c) => new Date(c.created_at).getTime();
  const sorted = [...list];
  if (order === 'newest_first') sorted.sort((a, b) => created(b) - created(a));
  else if (order === 'largest_first') sorted.sort((a, b) => b.size_in_bytes - a.size_in_bytes || created(a) - created(b));
  else sorted.sort((a, b) => created(a) - created(b));
  return sorted;
}

// collect -> size floor -> keep_count per device -> delete_order -> delete_count cap
function planCaches(caches, o, now = Date.now()) {
  const decorate = (c) => ({
    ...c,
    device: cacheDevice(c.key),
    category: cacheCategory(c.key),
    age: ageDays(c.created_at, now),
  });
  const matched = caches.filter((c) => cacheMatches(c, o, now)).map(decorate);
  const floorBytes = o.minCacheSizeMb * MB;
  const belowFloor = floorBytes > 0 ? matched.filter((c) => c.size_in_bytes < floorBytes) : [];
  const candidates = floorBytes > 0 ? matched.filter((c) => c.size_in_bytes >= floorBytes) : matched;

  const protectedCaches = [];
  const protectedByDevice = new Map();
  let remainder = candidates;
  if (o.keepCount > 0) {
    const byDevice = new Map();
    for (const c of candidates) {
      if (!byDevice.has(c.device)) byDevice.set(c.device, []);
      byDevice.get(c.device).push(c);
    }
    const keepIds = new Set();
    for (const [device, list] of byDevice) {
      const keep = orderBy(list, 'newest_first').slice(0, o.keepCount);
      keep.forEach((c) => keepIds.add(c.id));
      protectedCaches.push(...keep);
      protectedByDevice.set(device, keep);
    }
    remainder = candidates.filter((c) => !keepIds.has(c.id));
  }

  const ordered = orderBy(remainder, o.deleteOrder);
  const toDelete = o.deleteCount > 0 ? ordered.slice(0, o.deleteCount) : ordered;
  const overCap = o.deleteCount > 0 ? ordered.slice(o.deleteCount) : [];
  return { matched, belowFloor, candidates, protectedCaches, protectedByDevice, ordered, toDelete, overCap };
}

const workflowBasename = (wf) => String(wf.path || '').split('/').pop().replace(/\.ya?ml$/, '');

function statusMatches(conclusion, filter) {
  if (filter === 'failed_only') return conclusion === 'failure';
  if (filter === 'unsuccessful_only') return UNSUCCESSFUL.has(conclusion);
  return true;
}

// runsByWorkflowId: Map(workflow.id -> run[]). pinRunIds: runs owning a live pins artifact.
function planRuns(workflows, runsByWorkflowId, o, ctx = {}) {
  const now = ctx.now || Date.now();
  const pinRunIds = ctx.pinRunIds || new Set();
  const cutoff = now - o.daysToKeep * DAY_MS;
  const results = [];
  for (const wf of workflows) {
    const base = workflowBasename(wf);
    if (o.workflowFilter !== 'ALL' && base !== o.workflowFilter) continue;
    const runs = [...(runsByWorkflowId.get(wf.id) || [])].sort(
      (a, b) => new Date(b.created_at) - new Date(a.created_at));
    const keptSuccess = new Set(
      runs.filter((r) => r.conclusion === 'success').slice(0, o.keepLastSuccessful).map((r) => r.id));
    const stats = { total: runs.length, success: 0, failure: 0, cancelled: 0, skipped: 0, other: 0 };
    const eligible = [];
    let protectedCount = 0;
    let pinProtected = 0;
    let active = 0;
    for (const r of runs) {
      const c = r.conclusion;
      if (c in stats && c !== 'total') stats[c]++;
      else stats.other++;
      if (r.status !== 'completed' || r.id === ctx.currentRunId) { active++; continue; }
      if (!statusMatches(c, o.statusFilter)) continue;
      if (o.daysToKeep > 0 && new Date(r.created_at).getTime() >= cutoff) continue;
      if (keptSuccess.has(r.id)) { protectedCount++; continue; }
      if (o.pinPolicy !== 'delete_pin' && pinRunIds.has(r.id)) { pinProtected++; continue; }
      eligible.push({ ...r, age: ageDays(r.created_at, now) });
    }
    results.push({ workflow: wf, base, stats, eligible, protectedCount, pinProtected, active });
  }
  return results;
}

// activeRunIds: runs still queued/in progress -> their artifacts are never touched.
function planArtifacts(artifacts, o, ctx = {}) {
  const now = ctx.now || Date.now();
  const activeRunIds = ctx.activeRunIds || new Set();
  const cutoff = now - o.artifactDaysToKeep * DAY_MS;
  const toDelete = [];
  const pins = [];
  let kept = 0;
  let expired = 0;
  let active = 0;
  for (const a of artifacts) {
    if (a.expired) { expired++; continue; }
    const runId = a.workflow_run && a.workflow_run.id;
    if (runId && activeRunIds.has(runId)) { active++; continue; }
    const decorated = { ...a, age: ageDays(a.created_at, now) };
    if (a.name === PINS_ARTIFACT) {
      pins.push(decorated);
      // delete_pin is the supported reset: the pins store goes regardless of age.
      if (o.pinPolicy === 'delete_pin') toDelete.push(decorated);
      continue;
    }
    if (o.artifactDaysToKeep === 0 || new Date(a.created_at).getTime() < cutoff) toDelete.push(decorated);
    else kept++;
  }
  toDelete.sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
  const bytes = toDelete.reduce((s, a) => s + a.size_in_bytes, 0);
  return { toDelete, bytes, pins, kept, expired, active };
}

// ---- thin paginated listers (github = octokit from actions/github-script) ----
async function listPaged(fn, params, field) {
  const out = [];
  for (let page = 1; ; page++) {
    const res = await fn({ ...params, per_page: 100, page });
    const items = res.data[field] || [];
    out.push(...items);
    if (items.length < 100) break;
  }
  return out;
}

const listCaches = (github, owner, repo) =>
  listPaged(github.rest.actions.getActionsCacheList, { owner, repo }, 'actions_caches');

const listArtifacts = (github, owner, repo, extra = {}) =>
  listPaged(github.rest.actions.listArtifactsForRepo, { owner, repo, ...extra }, 'artifacts');

const listWorkflows = (github, owner, repo) =>
  listPaged(github.rest.actions.listRepoWorkflows, { owner, repo }, 'workflows');

const listRunsForWorkflow = (github, owner, repo, workflowId) =>
  listPaged(github.rest.actions.listWorkflowRuns, { owner, repo, workflow_id: workflowId }, 'workflow_runs');

async function listActiveRunIds(github, owner, repo) {
  const ids = new Set();
  for (const status of ['queued', 'in_progress', 'waiting', 'requested', 'pending']) {
    const runs = await listPaged(github.rest.actions.listWorkflowRunsForRepo, { owner, repo, status }, 'workflow_runs');
    runs.forEach((r) => ids.add(r.id));
  }
  return ids;
}

async function listPinRunIds(github, owner, repo) {
  const pins = await listArtifacts(github, owner, repo, { name: PINS_ARTIFACT });
  return new Set(pins.filter((a) => !a.expired && a.workflow_run).map((a) => a.workflow_run.id));
}

async function deleteCache(github, owner, repo, cache) {
  if (typeof github.rest.actions.deleteActionsCacheById === 'function') {
    return github.rest.actions.deleteActionsCacheById({ owner, repo, cache_id: cache.id });
  }
  return github.rest.actions.deleteActionsCacheByKey({ owner, repo, key: cache.key, ref: cache.ref });
}

module.exports = {
  PINS_ARTIFACT, CHOICES, DAY_MS, MB, GB,
  readOptions, optionRows, ageDays, toMB, toGB, pct,
  cacheCategory, cacheDevice, cacheMatches, orderBy, planCaches,
  workflowBasename, statusMatches, planRuns, planArtifacts,
  listCaches, listArtifacts, listWorkflows, listRunsForWorkflow,
  listActiveRunIds, listPinRunIds, deleteCache,
};
