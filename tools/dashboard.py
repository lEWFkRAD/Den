#!/usr/bin/env python3
"""
DEN Content Dashboard — local web server for managing game data.
Run: python tools/dashboard.py
Then open http://localhost:8742 in your browser.

No external dependencies — uses only Python stdlib.
Edits JSON files in data/ and manages sprites in assets/.
"""

import http.server
import json
import os
import sys
import shutil
import io
import base64
import urllib.parse
import re
from pathlib import Path
from datetime import datetime

# ─── Config ──────────────────────────────────────────────────────────────────

PORT = 8742
PROJECT_ROOT = Path(__file__).resolve().parent.parent
DATA_DIR = PROJECT_ROOT / "data"
ASSETS_DIR = PROJECT_ROOT / "assets"
CHANGELOG_PATH = PROJECT_ROOT / "tools" / "changelog.json"
CATEGORIES = ['weapons', 'items', 'characters', 'enemies', 'kips', 'classes', 'dialogue', 'chapters']

# ─── Changelog Tracker ──────────────────────────────────────────────────────

def load_changelog():
    if CHANGELOG_PATH.exists():
        with open(CHANGELOG_PATH, "r") as f:
            return json.load(f)
    return []

def save_changelog(log):
    with open(CHANGELOG_PATH, "w") as f:
        json.dump(log[-200:], f, indent="\t")  # keep last 200 entries

def add_changelog(action, category, item_id, details=""):
    log = load_changelog()
    log.append({
        "time": datetime.now().isoformat(timespec="seconds"),
        "action": action,
        "category": category,
        "id": item_id,
        "details": details,
    })
    save_changelog(log)

# ─── Data Helpers ────────────────────────────────────────────────────────────

def load_data(name):
    path = DATA_DIR / f"{name}.json"
    if not path.exists():
        return {}
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    data.pop("_schema", None)
    return data

def save_data(name, data):
    path = DATA_DIR / f"{name}.json"
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, indent="\t", ensure_ascii=False)

# ─── HTML Dashboard ─────────────────────────────────────────────────────────

DASHBOARD_HTML = r"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>DEN Dashboard</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { background: #0d0d12; color: #c8c8d0; font-family: 'Segoe UI', system-ui, sans-serif; }
a { color: #7090ff; text-decoration: none; }

/* Layout */
.sidebar { position: fixed; left: 0; top: 0; bottom: 0; width: 220px; background: #12121a; border-right: 1px solid #222; padding: 16px 0; overflow-y: auto; }
.sidebar h1 { font-size: 20px; color: #c22; text-align: center; margin-bottom: 20px; letter-spacing: 4px; }
.sidebar .nav-item { display: block; padding: 10px 20px; color: #888; cursor: pointer; border-left: 3px solid transparent; transition: all 0.15s; }
.sidebar .nav-item:hover { color: #ccc; background: #1a1a24; }
.sidebar .nav-item.active { color: #7090ff; border-left-color: #7090ff; background: #14142a; }
.main { margin-left: 220px; padding: 24px 32px; min-height: 100vh; }

/* Cards */
.card { background: #16161e; border: 1px solid #252530; border-radius: 8px; padding: 20px; margin-bottom: 16px; }
.card h2 { font-size: 16px; color: #aaa; margin-bottom: 12px; text-transform: uppercase; letter-spacing: 1px; }

/* Table */
table { width: 100%; border-collapse: collapse; }
th { text-align: left; padding: 8px 12px; color: #666; font-size: 12px; text-transform: uppercase; border-bottom: 1px solid #252530; }
td { padding: 8px 12px; border-bottom: 1px solid #1a1a24; font-size: 14px; }
tr:hover td { background: #1a1a28; }
.id-col { color: #7090ff; font-family: monospace; }

/* Buttons */
.btn { display: inline-block; padding: 6px 14px; border: 1px solid #333; border-radius: 4px; background: #1a1a24; color: #bbb; cursor: pointer; font-size: 13px; transition: all 0.15s; }
.btn:hover { background: #252530; color: #fff; }
.btn-primary { background: #1a2a5a; border-color: #3355aa; color: #8ab4ff; }
.btn-primary:hover { background: #253570; }
.btn-danger { background: #3a1a1a; border-color: #662222; color: #ff8888; }
.btn-danger:hover { background: #4a2020; }
.btn-sm { padding: 3px 8px; font-size: 12px; }

/* Forms */
.form-group { margin-bottom: 12px; }
.form-group label { display: block; color: #888; font-size: 12px; margin-bottom: 4px; text-transform: uppercase; }
.form-group input, .form-group select, .form-group textarea {
    width: 100%; padding: 8px 10px; background: #0d0d12; border: 1px solid #333; border-radius: 4px; color: #ccc; font-size: 14px; font-family: inherit;
}
.form-group textarea { min-height: 80px; resize: vertical; }
.form-row { display: flex; gap: 12px; }
.form-row .form-group { flex: 1; }

/* Modal */
.modal-overlay { display: none; position: fixed; top: 0; left: 0; right: 0; bottom: 0; background: rgba(0,0,0,0.7); z-index: 100; justify-content: center; align-items: flex-start; padding-top: 60px; }
.modal-overlay.open { display: flex; }
.modal { background: #16161e; border: 1px solid #333; border-radius: 8px; padding: 24px; width: 640px; max-height: 80vh; overflow-y: auto; }
.modal h3 { margin-bottom: 16px; color: #ddd; }
.modal-actions { display: flex; gap: 8px; justify-content: flex-end; margin-top: 16px; }

/* Upload area */
.upload-area { border: 2px dashed #333; border-radius: 8px; padding: 40px; text-align: center; color: #666; cursor: pointer; transition: all 0.15s; }
.upload-area:hover { border-color: #555; color: #999; }
.upload-area.dragover { border-color: #7090ff; color: #7090ff; }

/* Changelog */
.changelog-item { padding: 6px 0; border-bottom: 1px solid #1a1a24; font-size: 13px; }
.changelog-item .time { color: #555; font-size: 11px; }
.changelog-item .action { color: #7090ff; }
.changelog-item .action.delete { color: #ff6666; }
.changelog-item .action.create { color: #66ff88; }
.changelog-item .action.update { color: #ffaa44; }
.changelog-item .action.upload { color: #aa66ff; }

/* Toast */
.toast { position: fixed; bottom: 24px; right: 24px; background: #1a2a5a; border: 1px solid #3355aa; color: #8ab4ff; padding: 12px 20px; border-radius: 6px; font-size: 14px; z-index: 200; opacity: 0; transition: opacity 0.3s; pointer-events: none; }
.toast.show { opacity: 1; }

/* Sprite preview */
.sprite-grid { display: flex; flex-wrap: wrap; gap: 12px; }
.sprite-card { background: #1a1a24; border: 1px solid #252530; border-radius: 6px; padding: 8px; text-align: center; width: 100px; }
.sprite-card img { width: 64px; height: 64px; image-rendering: pixelated; }
.sprite-card .name { font-size: 11px; color: #888; margin-top: 4px; }

/* Tab content */
.tab-content { display: none; }
.tab-content.active { display: block; }

/* Search */
.search-bar { margin-bottom: 16px; }
.search-bar input { width: 300px; }
</style>
</head>
<body>

<div class="sidebar">
    <h1>D E N</h1>
    <div class="nav-item active" data-tab="weapons">Weapons</div>
    <div class="nav-item" data-tab="items">Items</div>
    <div class="nav-item" data-tab="characters">Characters</div>
    <div class="nav-item" data-tab="enemies">Enemies</div>
    <div class="nav-item" data-tab="kips">Kips</div>
    <div class="nav-item" data-tab="classes">Classes</div>
    <div class="nav-item" data-tab="dialogue">Dialogue</div>
    <div class="nav-item" data-tab="chapters">Chapters</div>
    <div class="nav-item" data-tab="sprites">Sprites</div>
    <div class="nav-item" data-tab="changelog">Changelog</div>
</div>

<div class="main">
    <!-- ═══ WEAPONS ═══ -->
    <div class="tab-content active" id="tab-weapons">
        <div class="card">
            <h2>Weapons <button class="btn btn-primary btn-sm" onclick="openWeaponModal()">+ New</button></h2>
            <table><thead><tr>
                <th>ID</th><th>Name</th><th>Type</th><th>Atk</th><th>Hit</th><th>Crit</th><th>Range</th><th>Uses</th><th>Element</th><th></th>
            </tr></thead><tbody id="weapons-table"></tbody></table>
        </div>
    </div>

    <!-- ═══ ITEMS ═══ -->
    <div class="tab-content" id="tab-items">
        <div class="card">
            <h2>Items <button class="btn btn-primary btn-sm" onclick="openItemModal()">+ New</button></h2>
            <table><thead><tr>
                <th>ID</th><th>Name</th><th>Type</th><th>Uses</th><th>Value</th><th>Description</th><th></th>
            </tr></thead><tbody id="items-table"></tbody></table>
        </div>
    </div>

    <!-- ═══ CHARACTERS ═══ -->
    <div class="tab-content" id="tab-characters">
        <div class="card">
            <h2>Player Characters <button class="btn btn-primary btn-sm" onclick="openCharModal()">+ New</button></h2>
            <table><thead><tr>
                <th>ID</th><th>Name</th><th>Class</th><th>Kip</th><th>Weapons</th><th>Items</th><th></th>
            </tr></thead><tbody id="chars-table"></tbody></table>
        </div>
    </div>

    <!-- ═══ ENEMIES ═══ -->
    <div class="tab-content" id="tab-enemies">
        <div class="card">
            <h2>Enemy Types <button class="btn btn-primary btn-sm" onclick="openEnemyModal()">+ New</button></h2>
            <table><thead><tr>
                <th>ID</th><th>Name</th><th>Class</th><th>Weapons</th><th>Element</th><th></th>
            </tr></thead><tbody id="enemies-table"></tbody></table>
        </div>
    </div>

    <!-- ═══ KIPS ═══ -->
    <div class="tab-content" id="tab-kips">
        <div class="card">
            <h2>Kips <button class="btn btn-primary btn-sm" onclick="openKipModal()">+ New</button></h2>
            <table><thead><tr>
                <th>ID</th><th>Name</th><th>Element</th><th>HP</th><th>Atk</th><th>Def</th><th>Mov</th><th>Range</th><th></th>
            </tr></thead><tbody id="kips-table"></tbody></table>
        </div>
    </div>

    <!-- ═══ CLASSES ═══ -->
    <div class="tab-content" id="tab-classes">
        <div class="card">
            <h2>Unit Classes <button class="btn btn-primary btn-sm" onclick="openClassModal()">+ New</button></h2>
            <table><thead><tr>
                <th>Class</th><th>HP</th><th>STR</th><th>MAG</th><th>SKL</th><th>SPD</th><th>LCK</th><th>DEF</th><th>RES</th><th>MOV</th><th></th>
            </tr></thead><tbody id="classes-table"></tbody></table>
        </div>
    </div>

    <!-- ═══ DIALOGUE ═══ -->
    <div class="tab-content" id="tab-dialogue">
        <div class="card">
            <h2>Dialogue Scenes <button class="btn btn-primary btn-sm" onclick="openDialogueModal()">+ New Scene</button></h2>
            <div id="dialogue-list"></div>
        </div>
    </div>

    <!-- ═══ CHAPTERS ═══ -->
    <div class="tab-content" id="tab-chapters">
        <div class="card">
            <h2>Chapters <button class="btn btn-primary btn-sm" onclick="openChapterModal()">+ New</button></h2>
            <div id="chapters-list"></div>
        </div>
    </div>

    <!-- ═══ SPRITES ═══ -->
    <div class="tab-content" id="tab-sprites">
        <div class="card">
            <h2>Upload Sprites</h2>
            <div class="form-row" style="margin-bottom: 16px;">
                <div class="form-group">
                    <label>Destination Folder</label>
                    <select id="sprite-dest">
                        <option value="portraits">portraits (characters)</option>
                        <option value="kips">kips</option>
                        <option value="enemies">enemies</option>
                    </select>
                </div>
                <div class="form-group">
                    <label>Sprite Name (no extension)</label>
                    <input type="text" id="sprite-name" placeholder="e.g. aldric">
                </div>
            </div>
            <div class="upload-area" id="upload-area">
                Drop a PNG here, or click to select<br>
                <input type="file" id="sprite-file" accept="image/png" style="display:none">
            </div>
        </div>
        <div class="card">
            <h2>Current Sprites</h2>
            <h3 style="color:#666;font-size:13px;margin-bottom:8px;">Portraits</h3>
            <div class="sprite-grid" id="sprites-portraits"></div>
            <h3 style="color:#666;font-size:13px;margin: 16px 0 8px;">Kips</h3>
            <div class="sprite-grid" id="sprites-kips"></div>
            <h3 style="color:#666;font-size:13px;margin: 16px 0 8px;">Enemies</h3>
            <div class="sprite-grid" id="sprites-enemies"></div>
        </div>
    </div>

    <!-- ═══ CHANGELOG ═══ -->
    <div class="tab-content" id="tab-changelog">
        <div class="card">
            <h2>Change History</h2>
            <div id="changelog-list"></div>
        </div>
    </div>
</div>

<!-- ═══ MODAL ═══ -->
<div class="modal-overlay" id="modal">
    <div class="modal" id="modal-content"></div>
</div>

<!-- ═══ TOAST ═══ -->
<div class="toast" id="toast"></div>

<script>
// ─── State ──────────────────────────────────────────────────────────────────
let data = {};  // loaded from server
const categories = ['weapons','items','characters','enemies','kips','classes','dialogue','chapters'];

// ─── API ────────────────────────────────────────────────────────────────────
async function api(method, path, body) {
    const opts = { method, headers: {'Content-Type':'application/json'} };
    if (body) opts.body = JSON.stringify(body);
    const r = await fetch('/api' + path, opts);
    return r.json();
}

async function loadAll() {
    for (const cat of categories) {
        data[cat] = await api('GET', '/' + cat);
    }
    renderAll();
}

async function saveCategory(cat) {
    await api('PUT', '/' + cat, data[cat]);
}

// ─── Toast ──────────────────────────────────────────────────────────────────
function toast(msg) {
    const t = document.getElementById('toast');
    t.textContent = msg;
    t.classList.add('show');
    setTimeout(() => t.classList.remove('show'), 2000);
}

// ─── Navigation ─────────────────────────────────────────────────────────────
document.querySelectorAll('.nav-item').forEach(el => {
    el.addEventListener('click', () => {
        document.querySelectorAll('.nav-item').forEach(n => n.classList.remove('active'));
        document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
        el.classList.add('active');
        document.getElementById('tab-' + el.dataset.tab).classList.add('active');
        if (el.dataset.tab === 'sprites') loadSprites();
        if (el.dataset.tab === 'changelog') loadChangelog();
    });
});

// ─── Modal ──────────────────────────────────────────────────────────────────
function openModal(html) {
    document.getElementById('modal-content').innerHTML = html;
    document.getElementById('modal').classList.add('open');
}
function closeModal() {
    document.getElementById('modal').classList.remove('open');
}
document.getElementById('modal').addEventListener('click', e => {
    if (e.target.id === 'modal') closeModal();
});

// ─── Render All ─────────────────────────────────────────────────────────────
function renderAll() {
    renderWeapons();
    renderItems();
    renderChars();
    renderEnemies();
    renderKips();
    renderClasses();
    renderDialogue();
    renderChapters();
}

// ─── WEAPONS ────────────────────────────────────────────────────────────────
function renderWeapons() {
    const tb = document.getElementById('weapons-table');
    tb.innerHTML = '';
    for (const [id, w] of Object.entries(data.weapons || {})) {
        tb.innerHTML += `<tr>
            <td class="id-col">${id}</td><td>${w.name}</td><td>${w.type}</td>
            <td>${w.attack}</td><td>${w.hit}</td><td>${w.crit}</td>
            <td>${w.min_range}-${w.max_range}</td><td>${w.uses}</td>
            <td>${w.element || '—'}</td>
            <td><button class="btn btn-sm" onclick="editWeapon('${id}')">Edit</button>
                <button class="btn btn-danger btn-sm" onclick="deleteItem('weapons','${id}')">X</button></td>
        </tr>`;
    }
}

function weaponFormHTML(id='', w={}) {
    return `<h3>${id ? 'Edit' : 'New'} Weapon</h3>
    <div class="form-row">
        <div class="form-group"><label>ID</label><input id="f-wid" value="${id}" ${id?'readonly':''}></div>
        <div class="form-group"><label>Name</label><input id="f-wname" value="${w.name||''}"></div>
    </div>
    <div class="form-row">
        <div class="form-group"><label>Type</label>
            <select id="f-wtype">${['sword','lance','axe','bow','tome','dagger','staff','greatsword'].map(t=>`<option ${t===(w.type||'sword')?'selected':''}>${t}</option>`).join('')}</select></div>
        <div class="form-group"><label>Damage Type</label>
            <select id="f-wdmg"><option ${(w.damage_type||'physical')==='physical'?'selected':''}>physical</option><option ${(w.damage_type||'')==='magical'?'selected':''}>magical</option></select></div>
    </div>
    <div class="form-row">
        <div class="form-group"><label>Attack</label><input type="number" id="f-watk" value="${w.attack||5}"></div>
        <div class="form-group"><label>Hit</label><input type="number" id="f-whit" value="${w.hit||80}"></div>
        <div class="form-group"><label>Crit</label><input type="number" id="f-wcrit" value="${w.crit||0}"></div>
    </div>
    <div class="form-row">
        <div class="form-group"><label>Min Range</label><input type="number" id="f-wminr" value="${w.min_range||1}"></div>
        <div class="form-group"><label>Max Range</label><input type="number" id="f-wmaxr" value="${w.max_range||1}"></div>
        <div class="form-group"><label>Uses</label><input type="number" id="f-wuses" value="${w.uses||30}"></div>
    </div>
    <div class="form-row">
        <div class="form-group"><label>Element</label><input id="f-welem" value="${w.element||''}" placeholder="blood, void, ice..."></div>
        <div class="form-group"><label>Healing?</label><select id="f-wheal"><option value="false" ${!w.is_healing?'selected':''}>No</option><option value="true" ${w.is_healing?'selected':''}>Yes</option></select></div>
        <div class="form-group"><label>Heal Amount</label><input type="number" id="f-whealamt" value="${w.heal_amount||0}"></div>
    </div>
    <div class="modal-actions">
        <button class="btn" onclick="closeModal()">Cancel</button>
        <button class="btn btn-primary" onclick="saveWeapon('${id}')">Save</button>
    </div>`;
}

function openWeaponModal() { openModal(weaponFormHTML()); }
function editWeapon(id) { openModal(weaponFormHTML(id, data.weapons[id])); }

async function saveWeapon(oldId) {
    const id = document.getElementById('f-wid').value.trim();
    if (!id) return;
    const w = {
        name: document.getElementById('f-wname').value,
        type: document.getElementById('f-wtype').value,
        damage_type: document.getElementById('f-wdmg').value,
        attack: +document.getElementById('f-watk').value,
        hit: +document.getElementById('f-whit').value,
        crit: +document.getElementById('f-wcrit').value,
        min_range: +document.getElementById('f-wminr').value,
        max_range: +document.getElementById('f-wmaxr').value,
        uses: +document.getElementById('f-wuses').value,
        element: document.getElementById('f-welem').value,
        is_healing: document.getElementById('f-wheal').value === 'true',
        heal_amount: +document.getElementById('f-whealamt').value,
    };
    if (!w.is_healing) { delete w.is_healing; delete w.heal_amount; }
    if (oldId && oldId !== id) delete data.weapons[oldId];
    data.weapons[id] = w;
    await saveCategory('weapons');
    await api('POST', '/log', {action: oldId ? 'update' : 'create', category: 'weapons', id, details: w.name});
    renderWeapons(); closeModal();
    toast(`Weapon "${w.name}" saved`);
}

// ─── ITEMS ──────────────────────────────────────────────────────────────────
function renderItems() {
    const tb = document.getElementById('items-table');
    tb.innerHTML = '';
    for (const [id, it] of Object.entries(data.items || {})) {
        tb.innerHTML += `<tr>
            <td class="id-col">${id}</td><td>${it.name}</td><td>${it.type}</td>
            <td>${it.uses}</td><td>${it.value}</td><td>${it.description}</td>
            <td><button class="btn btn-sm" onclick="editItem('${id}')">Edit</button>
                <button class="btn btn-danger btn-sm" onclick="deleteItem('items','${id}')">X</button></td>
        </tr>`;
    }
}

function itemFormHTML(id='', it={}) {
    return `<h3>${id ? 'Edit' : 'New'} Item</h3>
    <div class="form-row">
        <div class="form-group"><label>ID</label><input id="f-iid" value="${id}" ${id?'readonly':''}></div>
        <div class="form-group"><label>Name</label><input id="f-iname" value="${it.name||''}"></div>
    </div>
    <div class="form-row">
        <div class="form-group"><label>Type</label>
            <select id="f-itype">${['heal','elixir','kip_restore','stat_boost','promotion'].map(t=>`<option ${t===(it.type||'heal')?'selected':''}>${t}</option>`).join('')}</select></div>
        <div class="form-group"><label>Uses</label><input type="number" id="f-iuses" value="${it.uses||1}"></div>
        <div class="form-group"><label>Value</label><input type="number" id="f-ival" value="${it.value||0}"></div>
    </div>
    <div class="form-row">
        <div class="form-group"><label>Stat Target</label><input id="f-istat" value="${it.stat_target||''}" placeholder="resistance, strength..."></div>
        <div class="form-group"><label>Duration (turns, -1=permanent)</label><input type="number" id="f-idur" value="${it.duration||0}"></div>
    </div>
    <div class="form-group"><label>Description</label><textarea id="f-idesc">${it.description||''}</textarea></div>
    <div class="modal-actions">
        <button class="btn" onclick="closeModal()">Cancel</button>
        <button class="btn btn-primary" onclick="saveItemData('${id}')">Save</button>
    </div>`;
}

function openItemModal() { openModal(itemFormHTML()); }
function editItem(id) { openModal(itemFormHTML(id, data.items[id])); }

async function saveItemData(oldId) {
    const id = document.getElementById('f-iid').value.trim();
    if (!id) return;
    const it = {
        name: document.getElementById('f-iname').value,
        type: document.getElementById('f-itype').value,
        uses: +document.getElementById('f-iuses').value,
        value: +document.getElementById('f-ival').value,
        stat_target: document.getElementById('f-istat').value,
        duration: +document.getElementById('f-idur').value,
        description: document.getElementById('f-idesc').value,
    };
    if (oldId && oldId !== id) delete data.items[oldId];
    data.items[id] = it;
    await saveCategory('items');
    await api('POST', '/log', {action: oldId ? 'update' : 'create', category: 'items', id, details: it.name});
    renderItems(); closeModal();
    toast(`Item "${it.name}" saved`);
}

// ─── CHARACTERS ─────────────────────────────────────────────────────────────
function renderChars() {
    const tb = document.getElementById('chars-table');
    tb.innerHTML = '';
    for (const [id, c] of Object.entries(data.characters || {})) {
        tb.innerHTML += `<tr>
            <td class="id-col">${id}</td><td>${c.name}</td><td>${c.class}</td>
            <td>${c.kip||'—'}</td><td>${(c.weapons||[]).join(', ')}</td>
            <td>${(c.items||[]).join(', ')}</td>
            <td><button class="btn btn-sm" onclick="editChar('${id}')">Edit</button>
                <button class="btn btn-danger btn-sm" onclick="deleteItem('characters','${id}')">X</button></td>
        </tr>`;
    }
}

function charFormHTML(id='', c={}) {
    const classOpts = Object.keys(data.classes||{}).filter(k=>!k.startsWith('Enemy')).map(k=>`<option ${k===c.class?'selected':''}>${k}</option>`).join('');
    const kipOpts = [''].concat(Object.keys(data.kips||{})).map(k=>`<option ${k===c.kip?'selected':''}>${k}</option>`).join('');
    return `<h3>${id ? 'Edit' : 'New'} Character</h3>
    <div class="form-row">
        <div class="form-group"><label>ID</label><input id="f-cid" value="${id}" ${id?'readonly':''}></div>
        <div class="form-group"><label>Name</label><input id="f-cname" value="${c.name||''}"></div>
    </div>
    <div class="form-row">
        <div class="form-group"><label>Class</label><select id="f-cclass">${classOpts}</select></div>
        <div class="form-group"><label>Kip</label><select id="f-ckip">${kipOpts}</select></div>
        <div class="form-group"><label>Portrait ID</label><input id="f-cport" value="${c.portrait||id}"></div>
    </div>
    <div class="form-group"><label>Weapons (comma-separated IDs)</label><input id="f-cwpns" value="${(c.weapons||[]).join(', ')}"></div>
    <div class="form-group"><label>Items (comma-separated IDs)</label><input id="f-citems" value="${(c.items||[]).join(', ')}"></div>
    <div class="form-group"><label>Flavor Text</label><textarea id="f-cflav">${c.flavor||''}</textarea></div>
    <div class="modal-actions">
        <button class="btn" onclick="closeModal()">Cancel</button>
        <button class="btn btn-primary" onclick="saveChar('${id}')">Save</button>
    </div>`;
}

function openCharModal() { openModal(charFormHTML()); }
function editChar(id) { openModal(charFormHTML(id, data.characters[id])); }

async function saveChar(oldId) {
    const id = document.getElementById('f-cid').value.trim();
    if (!id) return;
    const c = {
        name: document.getElementById('f-cname').value,
        class: document.getElementById('f-cclass').value,
        kip: document.getElementById('f-ckip').value,
        portrait: document.getElementById('f-cport').value || id,
        weapons: document.getElementById('f-cwpns').value.split(',').map(s=>s.trim()).filter(Boolean),
        items: document.getElementById('f-citems').value.split(',').map(s=>s.trim()).filter(Boolean),
        flavor: document.getElementById('f-cflav').value,
    };
    if (oldId && oldId !== id) delete data.characters[oldId];
    data.characters[id] = c;
    await saveCategory('characters');
    await api('POST', '/log', {action: oldId ? 'update' : 'create', category: 'characters', id, details: c.name});
    renderChars(); closeModal();
    toast(`Character "${c.name}" saved`);
}

// ─── ENEMIES ────────────────────────────────────────────────────────────────
function renderEnemies() {
    const tb = document.getElementById('enemies-table');
    tb.innerHTML = '';
    for (const [id, e] of Object.entries(data.enemies || {})) {
        tb.innerHTML += `<tr>
            <td class="id-col">${id}</td><td>${e.name}</td><td>${e.class}</td>
            <td>${(e.weapons||[]).join(', ')}</td><td>${e.element||'—'}</td>
            <td><button class="btn btn-sm" onclick="editEnemy('${id}')">Edit</button>
                <button class="btn btn-danger btn-sm" onclick="deleteItem('enemies','${id}')">X</button></td>
        </tr>`;
    }
}

function enemyFormHTML(id='', e={}) {
    const classOpts = Object.keys(data.classes||{}).filter(k=>k.startsWith('Enemy')).map(k=>`<option ${k===e.class?'selected':''}>${k}</option>`).join('');
    return `<h3>${id ? 'Edit' : 'New'} Enemy</h3>
    <div class="form-row">
        <div class="form-group"><label>ID</label><input id="f-eid" value="${id}" ${id?'readonly':''}></div>
        <div class="form-group"><label>Name</label><input id="f-ename" value="${e.name||''}"></div>
    </div>
    <div class="form-row">
        <div class="form-group"><label>Class</label><select id="f-eclass">${classOpts}</select></div>
        <div class="form-group"><label>Element</label><input id="f-eelem" value="${e.element||''}"></div>
    </div>
    <div class="form-group"><label>Weapons (comma-separated)</label><input id="f-ewpns" value="${(e.weapons||[]).join(', ')}"></div>
    <div class="form-group"><label>Items (comma-separated)</label><input id="f-eitems" value="${(e.items||[]).join(', ')}"></div>
    <div class="modal-actions">
        <button class="btn" onclick="closeModal()">Cancel</button>
        <button class="btn btn-primary" onclick="saveEnemy('${id}')">Save</button>
    </div>`;
}

function openEnemyModal() { openModal(enemyFormHTML()); }
function editEnemy(id) { openModal(enemyFormHTML(id, data.enemies[id])); }

async function saveEnemy(oldId) {
    const id = document.getElementById('f-eid').value.trim();
    if (!id) return;
    const e = {
        name: document.getElementById('f-ename').value,
        class: document.getElementById('f-eclass').value,
        element: document.getElementById('f-eelem').value,
        weapons: document.getElementById('f-ewpns').value.split(',').map(s=>s.trim()).filter(Boolean),
        items: document.getElementById('f-eitems').value.split(',').map(s=>s.trim()).filter(Boolean),
    };
    if (oldId && oldId !== id) delete data.enemies[oldId];
    data.enemies[id] = e;
    await saveCategory('enemies');
    await api('POST', '/log', {action: oldId ? 'update' : 'create', category: 'enemies', id, details: e.name});
    renderEnemies(); closeModal();
    toast(`Enemy "${e.name}" saved`);
}

// ─── KIPS ───────────────────────────────────────────────────────────────────
function renderKips() {
    const tb = document.getElementById('kips-table');
    tb.innerHTML = '';
    for (const [id, k] of Object.entries(data.kips || {})) {
        tb.innerHTML += `<tr>
            <td class="id-col">${id}</td><td>${k.name}</td><td>${k.element}</td>
            <td>${k.hp}</td><td>${k.attack}</td><td>${k.defense}</td>
            <td>${k.movement}</td><td>${k.attack_range}</td>
            <td><button class="btn btn-sm" onclick="editKip('${id}')">Edit</button>
                <button class="btn btn-danger btn-sm" onclick="deleteItem('kips','${id}')">X</button></td>
        </tr>`;
    }
}

function kipFormHTML(id='', k={}) {
    return `<h3>${id ? 'Edit' : 'New'} Kip</h3>
    <div class="form-row">
        <div class="form-group"><label>ID</label><input id="f-kid" value="${id}" ${id?'readonly':''}></div>
        <div class="form-group"><label>Name</label><input id="f-kname" value="${k.name||''}"></div>
        <div class="form-group"><label>Element</label>
            <select id="f-kelem">${['blood','plant','ice','electric','void','light','dark','god'].map(e=>`<option ${e===k.element?'selected':''}>${e}</option>`).join('')}</select></div>
    </div>
    <div class="form-row">
        <div class="form-group"><label>HP</label><input type="number" id="f-khp" value="${k.hp||20}"></div>
        <div class="form-group"><label>Attack</label><input type="number" id="f-katk" value="${k.attack||6}"></div>
        <div class="form-group"><label>Defense</label><input type="number" id="f-kdef" value="${k.defense||3}"></div>
    </div>
    <div class="form-row">
        <div class="form-group"><label>Movement</label><input type="number" id="f-kmov" value="${k.movement||4}"></div>
        <div class="form-group"><label>Attack Range</label><input type="number" id="f-krange" value="${k.attack_range||1}"></div>
        <div class="form-group"><label>Awakening Radius</label><input type="number" id="f-kawake" value="${k.awakening_radius||2}"></div>
    </div>
    <div class="form-group"><label>Lore</label><textarea id="f-klore">${k.lore||''}</textarea></div>
    <div class="form-group"><label>Personality (JSON)</label><textarea id="f-kpers" style="min-height:200px;font-family:monospace;font-size:12px;">${JSON.stringify(k.personality||{}, null, 2)}</textarea></div>
    <div class="modal-actions">
        <button class="btn" onclick="closeModal()">Cancel</button>
        <button class="btn btn-primary" onclick="saveKip('${id}')">Save</button>
    </div>`;
}

function openKipModal() { openModal(kipFormHTML()); }
function editKip(id) { openModal(kipFormHTML(id, data.kips[id])); }

async function saveKip(oldId) {
    const id = document.getElementById('f-kid').value.trim();
    if (!id) return;
    let pers = {};
    try { pers = JSON.parse(document.getElementById('f-kpers').value); } catch(e) { toast('Invalid personality JSON!'); return; }
    const k = {
        name: document.getElementById('f-kname').value,
        element: document.getElementById('f-kelem').value,
        hp: +document.getElementById('f-khp').value,
        attack: +document.getElementById('f-katk').value,
        defense: +document.getElementById('f-kdef').value,
        movement: +document.getElementById('f-kmov').value,
        attack_range: +document.getElementById('f-krange').value,
        awakening_radius: +document.getElementById('f-kawake').value,
        lore: document.getElementById('f-klore').value,
        portrait: id.replace('_kip',''),
        personality: pers,
    };
    if (oldId && oldId !== id) delete data.kips[oldId];
    data.kips[id] = k;
    await saveCategory('kips');
    await api('POST', '/log', {action: oldId ? 'update' : 'create', category: 'kips', id, details: k.name});
    renderKips(); closeModal();
    toast(`Kip "${k.name}" saved`);
}

// ─── CLASSES ────────────────────────────────────────────────────────────────
function renderClasses() {
    const tb = document.getElementById('classes-table');
    tb.innerHTML = '';
    for (const [id, c] of Object.entries(data.classes || {})) {
        tb.innerHTML += `<tr>
            <td class="id-col">${id}</td>
            <td>${c.hp}</td><td>${c.strength}</td><td>${c.magic}</td><td>${c.skill}</td>
            <td>${c.speed}</td><td>${c.luck}</td><td>${c.defense}</td><td>${c.resistance}</td><td>${c.movement}</td>
            <td><button class="btn btn-sm" onclick="editClass('${id}')">Edit</button>
                <button class="btn btn-danger btn-sm" onclick="deleteItem('classes','${id}')">X</button></td>
        </tr>`;
    }
}

function classFormHTML(id='', c={}) {
    return `<h3>${id ? 'Edit' : 'New'} Class</h3>
    <div class="form-group"><label>Class Name</label><input id="f-clid" value="${id}" ${id?'readonly':''}></div>
    <div class="form-row">
        <div class="form-group"><label>HP</label><input type="number" id="f-clhp" value="${c.hp||20}"></div>
        <div class="form-group"><label>STR</label><input type="number" id="f-clstr" value="${c.strength||5}"></div>
        <div class="form-group"><label>MAG</label><input type="number" id="f-clmag" value="${c.magic||2}"></div>
    </div>
    <div class="form-row">
        <div class="form-group"><label>SKL</label><input type="number" id="f-clskl" value="${c.skill||4}"></div>
        <div class="form-group"><label>SPD</label><input type="number" id="f-clspd" value="${c.speed||4}"></div>
        <div class="form-group"><label>LCK</label><input type="number" id="f-cllck" value="${c.luck||2}"></div>
    </div>
    <div class="form-row">
        <div class="form-group"><label>DEF</label><input type="number" id="f-cldef" value="${c.defense||4}"></div>
        <div class="form-group"><label>RES</label><input type="number" id="f-clres" value="${c.resistance||2}"></div>
        <div class="form-group"><label>MOV</label><input type="number" id="f-clmov" value="${c.movement||4}"></div>
    </div>
    <div class="modal-actions">
        <button class="btn" onclick="closeModal()">Cancel</button>
        <button class="btn btn-primary" onclick="saveClass('${id}')">Save</button>
    </div>`;
}

function openClassModal() { openModal(classFormHTML()); }
function editClass(id) { openModal(classFormHTML(id, data.classes[id])); }

async function saveClass(oldId) {
    const id = document.getElementById('f-clid').value.trim();
    if (!id) return;
    const c = {
        hp: +document.getElementById('f-clhp').value,
        strength: +document.getElementById('f-clstr').value,
        magic: +document.getElementById('f-clmag').value,
        skill: +document.getElementById('f-clskl').value,
        speed: +document.getElementById('f-clspd').value,
        luck: +document.getElementById('f-cllck').value,
        defense: +document.getElementById('f-cldef').value,
        resistance: +document.getElementById('f-clres').value,
        movement: +document.getElementById('f-clmov').value,
    };
    if (oldId && oldId !== id) delete data.classes[oldId];
    data.classes[id] = c;
    await saveCategory('classes');
    await api('POST', '/log', {action: oldId ? 'update' : 'create', category: 'classes', id});
    renderClasses(); closeModal();
    toast(`Class "${id}" saved`);
}

// ─── DIALOGUE ───────────────────────────────────────────────────────────────
function renderDialogue() {
    const el = document.getElementById('dialogue-list');
    el.innerHTML = '';
    for (const [id, lines] of Object.entries(data.dialogue || {})) {
        el.innerHTML += `<div class="card" style="margin-bottom:8px;padding:12px;">
            <strong class="id-col">${id}</strong> — ${lines.length} lines
            <button class="btn btn-sm" style="float:right;margin-left:4px;" onclick="deleteItem('dialogue','${id}')">X</button>
            <button class="btn btn-sm" style="float:right;" onclick="editDialogue('${id}')">Edit</button>
        </div>`;
    }
}

function dialogueFormHTML(id='', lines=[]) {
    return `<h3>${id ? 'Edit' : 'New'} Dialogue Scene</h3>
    <div class="form-group"><label>Scene ID</label><input id="f-did" value="${id}" ${id?'readonly':''}></div>
    <div class="form-group"><label>Lines (JSON array)</label>
        <textarea id="f-dlines" style="min-height:300px;font-family:monospace;font-size:12px;">${JSON.stringify(lines, null, 2)}</textarea></div>
    <div class="modal-actions">
        <button class="btn" onclick="closeModal()">Cancel</button>
        <button class="btn btn-primary" onclick="saveDialogue('${id}')">Save</button>
    </div>`;
}

function openDialogueModal() { openModal(dialogueFormHTML()); }
function editDialogue(id) { openModal(dialogueFormHTML(id, data.dialogue[id])); }

async function saveDialogue(oldId) {
    const id = document.getElementById('f-did').value.trim();
    if (!id) return;
    let lines;
    try { lines = JSON.parse(document.getElementById('f-dlines').value); } catch(e) { toast('Invalid JSON!'); return; }
    if (oldId && oldId !== id) delete data.dialogue[oldId];
    data.dialogue[id] = lines;
    await saveCategory('dialogue');
    await api('POST', '/log', {action: oldId ? 'update' : 'create', category: 'dialogue', id, details: `${lines.length} lines`});
    renderDialogue(); closeModal();
    toast(`Dialogue "${id}" saved`);
}

// ─── CHAPTERS ───────────────────────────────────────────────────────────────
function renderChapters() {
    const el = document.getElementById('chapters-list');
    el.innerHTML = '';
    for (const [id, ch] of Object.entries(data.chapters || {})) {
        el.innerHTML += `<div class="card" style="margin-bottom:8px;padding:12px;">
            <strong class="id-col">${id}</strong> — ${ch.name||'Untitled'} (${(ch.enemies||[]).length} enemies, ${(ch.player_units||[]).length} player units)
            <button class="btn btn-sm" style="float:right;margin-left:4px;" onclick="deleteItem('chapters','${id}')">X</button>
            <button class="btn btn-sm" style="float:right;" onclick="editChapter('${id}')">Edit</button>
        </div>`;
    }
}

function chapterFormHTML(id='', ch={}) {
    return `<h3>${id ? 'Edit' : 'New'} Chapter</h3>
    <div class="form-row">
        <div class="form-group"><label>Chapter ID</label><input id="f-chid" value="${id}" ${id?'readonly':''}></div>
        <div class="form-group"><label>Name</label><input id="f-chname" value="${ch.name||''}"></div>
    </div>
    <div class="form-group"><label>Chapter Data (JSON)</label>
        <textarea id="f-chdata" style="min-height:400px;font-family:monospace;font-size:12px;">${JSON.stringify(ch, null, 2)}</textarea></div>
    <div class="modal-actions">
        <button class="btn" onclick="closeModal()">Cancel</button>
        <button class="btn btn-primary" onclick="saveChapter('${id}')">Save</button>
    </div>`;
}

function openChapterModal() { openModal(chapterFormHTML()); }
function editChapter(id) { openModal(chapterFormHTML(id, data.chapters[id])); }

async function saveChapter(oldId) {
    const id = document.getElementById('f-chid').value.trim();
    if (!id) return;
    let ch;
    try { ch = JSON.parse(document.getElementById('f-chdata').value); } catch(e) { toast('Invalid JSON!'); return; }
    if (oldId && oldId !== id) delete data.chapters[oldId];
    data.chapters[id] = ch;
    await saveCategory('chapters');
    await api('POST', '/log', {action: oldId ? 'update' : 'create', category: 'chapters', id, details: ch.name||''});
    renderChapters(); closeModal();
    toast(`Chapter "${ch.name||id}" saved`);
}

// ─── DELETE ─────────────────────────────────────────────────────────────────
async function deleteItem(cat, id) {
    if (!confirm(`Delete ${id} from ${cat}?`)) return;
    delete data[cat][id];
    await saveCategory(cat);
    await api('POST', '/log', {action: 'delete', category: cat, id});
    renderAll();
    toast(`Deleted ${id}`);
}

// ─── SPRITES ────────────────────────────────────────────────────────────────
async function loadSprites() {
    const sprites = await api('GET', '/sprites');
    for (const folder of ['portraits','kips','enemies']) {
        const el = document.getElementById('sprites-' + folder);
        el.innerHTML = '';
        for (const name of (sprites[folder]||[])) {
            el.innerHTML += `<div class="sprite-card">
                <img src="/sprite/${folder}/${name}">
                <div class="name">${name}</div>
            </div>`;
        }
        if (!(sprites[folder]||[]).length) el.innerHTML = '<div style="color:#555;font-size:13px;">No sprites yet</div>';
    }
}

// Upload
const uploadArea = document.getElementById('upload-area');
const fileInput = document.getElementById('sprite-file');
uploadArea.addEventListener('click', () => fileInput.click());
uploadArea.addEventListener('dragover', e => { e.preventDefault(); uploadArea.classList.add('dragover'); });
uploadArea.addEventListener('dragleave', () => uploadArea.classList.remove('dragover'));
uploadArea.addEventListener('drop', e => { e.preventDefault(); uploadArea.classList.remove('dragover'); handleFiles(e.dataTransfer.files); });
fileInput.addEventListener('change', () => handleFiles(fileInput.files));

async function handleFiles(files) {
    const dest = document.getElementById('sprite-dest').value;
    const name = document.getElementById('sprite-name').value.trim();
    if (!name) { toast('Enter a sprite name first!'); return; }
    for (const file of files) {
        const reader = new FileReader();
        reader.onload = async (e) => {
            const b64 = e.target.result.split(',')[1];
            await api('POST', '/upload-sprite', { folder: dest, name, data: b64 });
            await api('POST', '/log', {action: 'upload', category: 'sprites', id: `${dest}/${name}.png`});
            toast(`Uploaded ${name}.png to ${dest}/`);
            loadSprites();
        };
        reader.readAsDataURL(file);
    }
}

// ─── CHANGELOG ──────────────────────────────────────────────────────────────
async function loadChangelog() {
    const log = await api('GET', '/changelog');
    const el = document.getElementById('changelog-list');
    el.innerHTML = '';
    for (const entry of [...log].reverse()) {
        el.innerHTML += `<div class="changelog-item">
            <span class="time">${entry.time}</span>
            <span class="action ${entry.action}">${entry.action}</span>
            <strong>${entry.category}</strong> / <span class="id-col">${entry.id}</span>
            ${entry.details ? '— ' + entry.details : ''}
        </div>`;
    }
    if (!log.length) el.innerHTML = '<div style="color:#555;padding:12px;">No changes yet</div>';
}

// ─── Init ───────────────────────────────────────────────────────────────────
loadAll();
</script>
</body>
</html>"""

# ─── HTTP Handler ────────────────────────────────────────────────────────────

class DashboardHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # suppress default logging

    def _send(self, code, content, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        if isinstance(content, str):
            content = content.encode("utf-8")
        self.wfile.write(content)

    def _read_body(self):
        length = int(self.headers.get("Content-Length", 0))
        return self.rfile.read(length)

    def do_OPTIONS(self):
        self.send_response(200)
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()

    def do_GET(self):
        path = self.path

        # Dashboard page
        if path == "/" or path == "/index.html":
            self._send(200, DASHBOARD_HTML, "text/html")
            return

        # API: load category data
        for cat in CATEGORIES:
            if path == f"/api/{cat}":
                self._send(200, json.dumps(load_data(cat)))
                return

        # API: changelog
        if path == "/api/changelog":
            self._send(200, json.dumps(load_changelog()))
            return

        # API: sprites list
        if path == "/api/sprites":
            result = {}
            for folder in ["portraits", "kips", "enemies"]:
                folder_path = ASSETS_DIR / folder
                if folder_path.exists():
                    files = sorted([f.name for f in folder_path.iterdir()
                                   if f.suffix == ".png" and not f.name.endswith("_small.png")])
                    result[folder] = files
                else:
                    result[folder] = []
            self._send(200, json.dumps(result))
            return

        # Serve sprite images
        if path.startswith("/sprite/"):
            parts = path[8:].split("/", 1)
            if len(parts) == 2:
                file_path = ASSETS_DIR / parts[0] / parts[1]
                if file_path.exists() and file_path.suffix == ".png":
                    with open(file_path, "rb") as f:
                        self._send(200, f.read(), "image/png")
                    return
            self._send(404, '{"error":"not found"}')
            return

        self._send(404, '{"error":"not found"}')

    def do_PUT(self):
        path = self.path
        for cat in CATEGORIES:
            if path == f"/api/{cat}":
                body = json.loads(self._read_body())
                save_data(cat, body)
                self._send(200, '{"ok":true}')
                return
        self._send(404, '{"error":"not found"}')

    def do_POST(self):
        path = self.path

        # Log entry
        if path == "/api/log":
            body = json.loads(self._read_body())
            add_changelog(body["action"], body["category"], body["id"], body.get("details", ""))
            self._send(200, '{"ok":true}')
            return

        # Sprite upload
        if path == "/api/upload-sprite":
            body = json.loads(self._read_body())
            folder = body["folder"]
            name = body["name"]
            img_data = base64.b64decode(body["data"])
            dest = ASSETS_DIR / folder
            dest.mkdir(parents=True, exist_ok=True)
            file_path = dest / f"{name}.png"
            with open(file_path, "wb") as f:
                f.write(img_data)
            # Also create _small version (64x64) using basic resize
            # PIL not required — we save the full image, Godot handles the rest
            self._send(200, json.dumps({"ok": True, "path": str(file_path)}))
            return

        self._send(404, '{"error":"not found"}')


# ─── Main ────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    os.chdir(PROJECT_ROOT)
    server = http.server.HTTPServer(("localhost", PORT), DashboardHandler)
    print(f"\n  DEN Dashboard running at http://localhost:{PORT}")
    print(f"  Project: {PROJECT_ROOT}")
    print(f"  Data:    {DATA_DIR}")
    print(f"\n  Press Ctrl+C to stop.\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n  Dashboard stopped.")
        server.server_close()
