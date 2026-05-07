/**
 * Roblox AI Bridge Server v2.0 - Project-Based Two-Way Sync
 * ==========================================================
 * Creates per-map project folders with a live file tree that mirrors
 * the Roblox Studio hierarchy.  Files can be edited on disk (VS Code)
 * or inside Studio -- changes flow both ways automatically.
 *
 * Usage:  node src/server.js <projectName>
 */

const express = require('express');
const cors    = require('cors');
const fs      = require('fs');
const path    = require('path');
const chokidar = require('chokidar');

// ── CLI Args ────────────────────────────────────────────────────────────────
const projectName = process.argv[2] || 'default';
const PORT        = 3000;

// ── Paths ───────────────────────────────────────────────────────────────────
const CORE_DIR    = __dirname;
const ROOT_DIR    = path.join(CORE_DIR, '..');
const PROJECTS    = path.join(ROOT_DIR, 'projects');
const PROJECT_DIR = path.join(PROJECTS, projectName);
const SRC_DIR     = path.join(PROJECT_DIR, 'src');
const ACTIONS_DIR = path.join(PROJECT_DIR, 'actions');

// Services that are synced between Studio and disk
const SYNC_SERVICES = [
  'Workspace',
  'ServerScriptService',
  'ReplicatedStorage',
  'StarterGui',
  'StarterPlayer',
  'StarterPack',
  'Lighting',
  'SoundService',
  'ServerStorage',
];

// ── State ───────────────────────────────────────────────────────────────────
let actionQueue  = [];
let recentWrites = new Set();   // our own disk writes -> ignore in watcher
let watcher      = null;

// ═════════════════════════════════════════════════════════════════════════════
// 1.  PROJECT SETUP
// ═════════════════════════════════════════════════════════════════════════════

function initProject() {
  const dirs = [
    PROJECT_DIR, SRC_DIR, ACTIONS_DIR,
    ...SYNC_SERVICES.map(s => path.join(SRC_DIR, s)),
  ];
  dirs.forEach(d => { if (!fs.existsSync(d)) fs.mkdirSync(d, { recursive: true }); });

  const projFile = path.join(PROJECT_DIR, 'project.json');
  if (!fs.existsSync(projFile)) {
    fs.writeFileSync(projFile, JSON.stringify({
      name: projectName,
      createdAt: new Date().toISOString(),
      syncServices: SYNC_SERVICES,
    }, null, 2));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 2.  FILE <-> INSTANCE MAPPING
// ═════════════════════════════════════════════════════════════════════════════

function isScript(cls) {
  return cls === 'Script' || cls === 'LocalScript' || cls === 'ModuleScript';
}

function luaExt(cls) {
  if (cls === 'Script')       return '.server.lua';
  if (cls === 'LocalScript')  return '.client.lua';
  if (cls === 'ModuleScript') return '.module.lua';
  return '.lua';
}

function classFromFile(filename) {
  if (filename.endsWith('.server.lua')) return 'Script';
  if (filename.endsWith('.client.lua')) return 'LocalScript';
  if (filename.endsWith('.module.lua')) return 'ModuleScript';
  return null;
}

function baseName(filename) {
  for (const ext of ['.server.lua', '.client.lua', '.module.lua']) {
    if (filename.endsWith(ext)) return filename.slice(0, -ext.length);
  }
  return path.parse(filename).name;
}

// Mark a path as "we just wrote it" so the file-watcher ignores it
function ownWrite(p) {
  const abs = path.resolve(p);
  recentWrites.add(abs);
  setTimeout(() => recentWrites.delete(abs), 2000);
}

// ═════════════════════════════════════════════════════════════════════════════
// 3.  WRITE ROBLOX TREE -> DISK
// ═════════════════════════════════════════════════════════════════════════════

function clearDir(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    ownWrite(full);
    if (entry.isDirectory()) {
      fs.rmSync(full, { recursive: true, force: true });
    } else {
      fs.unlinkSync(full);
    }
  }
}

function writeInstance(baseDir, inst) {
  if (!inst || !inst.ClassName) return;
  const name        = inst.Name || inst.ClassName;
  const hasChildren = inst.Children && inst.Children.length > 0;
  const script      = isScript(inst.ClassName);
  const source      = (inst.Properties && inst.Properties.Source) || '';

  if (script && !hasChildren) {
    // Simple script -> single .lua file
    const fp = path.join(baseDir, name + luaExt(inst.ClassName));
    ownWrite(fp);
    fs.writeFileSync(fp, source, 'utf-8');

  } else if (script && hasChildren) {
    // Script with children -> folder + init.lua
    const dir = path.join(baseDir, name);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const fp = path.join(dir, 'init' + luaExt(inst.ClassName));
    ownWrite(fp);
    fs.writeFileSync(fp, source, 'utf-8');
    for (const child of inst.Children) writeInstance(dir, child);

  } else if (hasChildren) {
    // Container (Model/Folder/etc) -> folder + init.json
    const dir = path.join(baseDir, name);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const props = { ...(inst.Properties || {}) };
    if (Object.keys(props).length > 0 || inst.ClassName !== 'Folder') {
      const fp = path.join(dir, 'init.json');
      ownWrite(fp);
      fs.writeFileSync(fp, JSON.stringify({ ClassName: inst.ClassName, Properties: props }, null, 2));
    }
    for (const child of inst.Children) writeInstance(dir, child);

  } else {
    // Leaf instance -> .json
    const fp = path.join(baseDir, name + '.json');
    ownWrite(fp);
    fs.writeFileSync(fp, JSON.stringify({
      ClassName: inst.ClassName,
      Properties: inst.Properties || {},
    }, null, 2));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// 4.  FILE WATCHER  (Disk -> Studio)
// ═════════════════════════════════════════════════════════════════════════════

function fileToRobloxPath(filePath) {
  const rel   = path.relative(SRC_DIR, filePath);
  const parts = rel.split(path.sep);
  const out   = [];
  for (const p of parts) {
    if (p === 'init.json' || p.startsWith('init.')) continue;
    if (p === '_meta.json') continue;
    out.push(baseName(p));
  }
  return out.join('.');
}

function startWatcher() {
  if (watcher) watcher.close();

  watcher = chokidar.watch(SRC_DIR, {
    ignoreInitial: true,
    ignored: /(^|[\\/])\../,
    persistent: true,
    awaitWriteFinish: { stabilityThreshold: 300, pollInterval: 100 },
  });

  watcher.on('change', (fp) => {
    if (recentWrites.has(path.resolve(fp))) return;
    const rPath = fileToRobloxPath(fp);
    if (!rPath) return;

    if (fp.endsWith('.lua')) {
      const src = fs.readFileSync(fp, 'utf-8');
      actionQueue.push({ action: 'update', target: rPath, properties: { Source: src } });
      console.log(` [แก้] สคริปต์: ${rPath}`);
    } else if (fp.endsWith('.json') && !fp.endsWith('project.json')) {
      try {
        const data = JSON.parse(fs.readFileSync(fp, 'utf-8'));
        if (data.Properties) {
          actionQueue.push({ action: 'update', target: rPath, properties: data.Properties });
          console.log(` [แก้] คุณสมบัติ: ${rPath}`);
        }
      } catch (_) { /* skip bad json */ }
    }
  });

  watcher.on('unlink', (fp) => {
    if (recentWrites.has(path.resolve(fp))) return;
    const rPath = fileToRobloxPath(fp);
    if (rPath) {
      actionQueue.push({ action: 'delete', target: rPath });
      console.log(` [ลบ] ไฟล์: ${rPath}`);
    }
  });

  console.log(' [OK] ระบบตรวจจับไฟล์ทำงานแล้ว');
}

// ═════════════════════════════════════════════════════════════════════════════
// 5.  LOAD FILE-BASED ACTIONS
// ═════════════════════════════════════════════════════════════════════════════

function loadFileActions() {
  try {
    const files = fs.readdirSync(ACTIONS_DIR).filter(f => f.endsWith('.json')).sort();
    for (const file of files) {
      const fp = path.join(ACTIONS_DIR, file);
      try {
        const data = JSON.parse(fs.readFileSync(fp, 'utf-8'));
        if (Array.isArray(data)) actionQueue.push(...data);
        else actionQueue.push(data);
        fs.unlinkSync(fp);
        console.log('  [Actions] Loaded:', file);
      } catch (e) { console.error(` [!] ไฟล์ Action มีปัญหา: ${file}`, e.message); }
    }
  } catch (_) {}
}

// ═════════════════════════════════════════════════════════════════════════════
// 6.  EXPRESS APP
// ═════════════════════════════════════════════════════════════════════════════

const app = express();
app.use(cors());
app.use(express.json({ limit: '100mb' }));

// GET /sync  -- Plugin polls for pending actions
app.get('/sync', (req, res) => {
  loadFileActions();
  const pending = [...actionQueue];
  actionQueue = [];
  res.json({ success: true, project: projectName, actions: pending });
  if (pending.length) console.log(` [Sync] ส่งออก ${pending.length} คำสั่ง`);
});

// POST /sync -- Plugin pushes full map state (writes to disk)
app.post('/sync', (req, res) => {
  const body = req.body;
  if (!body || !body.services) {
    return res.status(400).json({ success: false, error: 'Missing services object' });
  }

  let totalFiles = 0;
  for (const [serviceName, tree] of Object.entries(body.services)) {
    const serviceDir = path.join(SRC_DIR, serviceName);
    if (!fs.existsSync(serviceDir)) fs.mkdirSync(serviceDir, { recursive: true });

    // Clear existing files for this service
    clearDir(serviceDir);

    // Write children of the service (not the service itself)
    if (tree && tree.Children) {
      for (const child of tree.Children) {
        writeInstance(serviceDir, child);
        totalFiles++;
      }
    }
  }

  // Save full snapshot too
  const ctxPath = path.join(PROJECT_DIR, 'map_context.json');
  ownWrite(ctxPath);
  fs.writeFileSync(ctxPath, JSON.stringify({ receivedAt: new Date().toISOString(), data: body }, null, 2));

  console.log(` [Push] บันทึกไฟล์ลง Disk: ${totalFiles} รายการ`);
  res.json({ success: true, message: `Project "${projectName}" synced`, totalFiles });
});

// POST /action -- AI or external tool pushes actions
app.post('/action', (req, res) => {
  const data = req.body;
  if (!data) return res.status(400).json({ success: false, error: 'Empty body' });
  if (Array.isArray(data)) actionQueue.push(...data);
  else actionQueue.push(data);
  res.json({ success: true, queued: actionQueue.length });
});

// GET /status
app.get('/status', (req, res) => {
  res.json({
    server: 'Roblox AI Bridge',
    version: '2.0.0',
    project: projectName,
    projectDir: PROJECT_DIR,
    uptime: process.uptime(),
    pendingActions: actionQueue.length,
    mapContextExists: fs.existsSync(path.join(PROJECT_DIR, 'map_context.json')),
  });
});

// GET /projects -- List all projects
app.get('/projects', (req, res) => {
  if (!fs.existsSync(PROJECTS)) return res.json({ projects: [] });
  const dirs = fs.readdirSync(PROJECTS, { withFileTypes: true })
    .filter(d => d.isDirectory())
    .map(d => {
      const pj = path.join(PROJECTS, d.name, 'project.json');
      let meta = {};
      try { meta = JSON.parse(fs.readFileSync(pj, 'utf-8')); } catch (_) {}
      return { name: d.name, ...meta };
    });
  res.json({ projects: dirs });
});

// ═════════════════════════════════════════════════════════════════════════════
// 7.  START
// ═════════════════════════════════════════════════════════════════════════════

initProject();
startWatcher();

app.listen(PORT, () => {
  const pkg = require('../package.json');
  console.log('\n ==============================');
  console.log(`   Z-Sync Server v${pkg.version}`);
  console.log(' ==============================');
  console.log(`  โปรเจกต์ : ${projectName}`);
  console.log(`  ที่อยู่   : ${PROJECT_DIR}`);
  console.log(`  เซิร์ฟเวอร์: http://localhost:${PORT}`);
  console.log(' ------------------------------\n');
});

module.exports = app;
