<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
<html xmlns="http://www.w3.org/1999/xhtml">
<head>
<meta http-equiv="X-UA-Compatible" content="IE=Edge">
<meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
<meta HTTP-EQUIV="Pragma" CONTENT="no-cache">
<meta HTTP-EQUIV="Expires" CONTENT="-1">
<link rel="shortcut icon" href="images/favicon.png">
<link rel="icon" href="images/favicon.png">
<title>Whitelist Window</title>
<link rel="stylesheet" type="text/css" href="index_style.css">
<link rel="stylesheet" type="text/css" href="form_style.css">
<script type="text/javascript" src="/js/jquery.js"></script>
<script type="text/javascript" src="/state.js"></script>
<script type="text/javascript" src="/general.js"></script>
<script type="text/javascript" src="/popup.js"></script>
<script type="text/javascript" src="/help.js"></script>
<script type="text/javascript" src="/validator.js"></script>
<style>
  /* Toggle switches */
  .wlw_toggle_wrap { display:inline-flex; align-items:center; gap:10px; padding:4px 0; }
  .wlw_toggle { position:relative; width:44px; height:24px; flex-shrink:0; }
  .wlw_toggle input { opacity:0; width:0; height:0; position:absolute; }
  .wlw_toggle_track {
    position:absolute; inset:0; border-radius:12px;
    background: #2a2a2a !important; border:1px solid #434343; cursor:pointer;
    transition:background 0.2s, border-color 0.2s;
  }
  .wlw_toggle_track:before {
    content:""; position:absolute; width:16px; height:16px;
    left:3px; top:3px; border-radius:50%; background: #434343;
    transition:transform 0.2s, background 0.2s;
  }
  .wlw_toggle input:checked + .wlw_toggle_track { background: #1a3d1a !important; border-color: #3a7a3a; }
  .wlw_toggle input:checked + .wlw_toggle_track:before {
    transform:translateX(20px); background: #7fdd7f !important; box-shadow:0 0 4px #7fdd7f;
  }
  .wlw_toggle_label { font-size:12px; font-weight:bold; min-width:140px; transition:color 0.2s; }
  .tog_on  { color: #7fdd7f !important; }
  .tog_off { color: #434343 !important; }

  /* Type badges */
  .wlw_type_badge { display:inline-block; padding:1px 7px; border-radius:2px; font-size:11px; font-weight:bold; letter-spacing:0.5px; }

  .wlw_type_mac { background: #2a6496 !important; color: #fff !important; }
  .wlw_type_ip  { background: #5b5ea6 !important; color: #fff !important; }
  .wlw_type_int { background: #3c763d !important; color: #fff !important; }

  /* Whitelist table */
  #wlw_entry_table {
    font-size:12px;
    font-family:Arial, Helvetica, MS UI Gothic, MS P Gothic, Microsoft Yahei UI, sans-serif;
    border:1px solid #000; border-collapse:collapse;
  }
  #wlw_entry_table th { color: #b3bdc2; font-size:11px; font-weight:normal; text-align:left; padding:6px 8px; }
  #wlw_entry_table td { padding:5px 8px; vertical-align:middle; font-size:12px; color: #c0cdd2; }
  #wlw_entry_table tr:last-child td { border-bottom:none; }
  #wlw_entry_table tr:hover td { background:rgba(255,255,255,0.04); }

  /* Resolved name cells */
  .wlw_name_assigned   { color: #c0cdd2 !important; font-size:11px; background-color: unset !important; }
  .wlw_name_associated { color: #7a9aaa !important; font-size:11px; background-color: unset !important; }
  .wlw_name_none       { color: #445a66 !important; font-style:italic; background-color: unset !important; }

  /* Buttons */
  .wlw_icon_btn {
    width:28px; height:28px; border-radius:50%; border:1px solid; cursor:pointer;
    font-size:18px; line-height:1; font-weight:bold;
    display:inline-flex; align-items:center; justify-content:center;
    transition:background 0.2s, border-color 0.2s, color 0.2s;
    padding:0 0 2px 0; flex-shrink:0;
  }
  .btn_add    { background: #1a3a4a; border-color: #4a7a96; color: #7fc4e0; }
  .btn_add:hover    { background: #225066; border-color: #7aafcc; color: #fff; }
  .btn_remove { background: #3a1a1a; border-color: #7a3a3a; color: #dd7f7f; }
  .btn_remove:hover { background: #5c2020; border-color: #aa4444; color: #fff; }

  /* Add-entry inputs */
  select.wlw_type_sel, input.wlw_value_input, select.wlw_client_sel {
    background: #1e2d34; border:1px solid #4a5f6a; color: #c0cdd2; padding:3px 6px; font-size:12px;
  }
  input.wlw_value_input { padding:3px 8px; }
  input.wlw_value_input:focus { border-color: #7aafcc; outline:none; }
  select.wlw_client_sel { max-width:50%; min-width:50%; box-sizing:border-box; }
  option.wlw_opt_active   { color: #7fdd7f; }
  option.wlw_opt_inactive { color: #7a9aaa; }

  .wlw_add_row_inner { display:flex; gap:6px; align-items:center; width:100%; box-sizing:border-box; }
  .wlw_add_row_inner input, .wlw_add_row_inner select { flex:1; min-width:0; }

  /* Section label */
  .wlw_section_label {
    line-height:180%; color: #FFF; font-size:12px; font-weight:bolder;
    text-align:left; padding:3px 3px 3px 10px;
    border:1px solid #222; border-bottom:none;
    background:linear-gradient(to bottom, #92A0A5 0%, #66757C 100%);
  }

  /* Day picker */
  .wlw_day_picker { display:flex; gap:4px; align-items:center; flex-wrap:wrap; padding:4px 0; }
  .wlw_day_btn {
    display:inline-block; width:38px; padding:5px 0; text-align:center;
    font-size:11px; font-weight:bold; letter-spacing:0.3px; cursor:pointer;
    border-radius:3px; border:1px solid #3a5060; background: #1e2d34 !important; color: #7a9aaa !important;
    user-select:none; -webkit-user-select:none;
    transition:background 0.15s, color 0.15s, border-color 0.15s;
  }
  .wlw_day_btn.day_on { background: #1a4a6a !important; border-color: #4a9acc; color: #7fc4e0; box-shadow:0 0 4px rgba(74,154,204,0.35); }
  .wlw_day_btn:hover  { border-color: #6abadc !important; color: #b0dcf0 !important; }
  .wlw_day_shortcut_bar { display:flex; gap:6px; margin-top:6px; flex-wrap:wrap; align-items:center; }
  .wlw_day_shortcut {
    font-size:11px; color: #7aafcc; cursor:pointer; text-decoration:underline;
    background:none; border:none; padding:0;
  }
  .wlw_day_shortcut:hover { color: #b0dcf0; }
  #wlw_days_summary { font-size:11px; color: #93b0bd; margin-left:4px; font-style:italic; }

  /* Misc */
  .wlw_hint  { color: #7a9aaa; font-size:11px; margin-top:3px; }
  .wlw_empty_row td { color: #556a76; font-style:italic; text-align:center; padding:12px; }
  .wlw_th_mid { vertical-align:middle !important; }
  .wlw_warn {
    padding:8px 10px; background: #2a1f0a; border:1px solid #7a5a1a; border-radius:3px;
  }
  .wlw_warn_title { color: #e0a840; font-size:11px; font-weight:bold; letter-spacing:0.5px; }
  .wlw_warn_body  { color: #c0944a; font-size:11px; margin-top:4px; line-height:1.6; }
</style>

<script type="text/javascript">

var custom_settings = <% get_custom_settings(); %>;

var wlw_entries      = [];
var wlw_days         = [];
var wlw_resolve      = {};
var wlw_clients      = [];
var wlw_ifaces       = [];
var _wlw_uid_counter = 0;

var DAY_LABELS = ['Sun','Mon','Tue','Wed','Thu','Fri','Sat'];

function _makeEntry(type, value) {
  return { type: type, value: value, _uid: _wlw_uid_counter++, _pending: true };
}

function initial() {
  SetCurrentPage();
  show_menu();
  loadSettings();
  renderTable();
  renderDayPicker();
  updateDaysSummary();
  syncAllToggles();
  onTypeChange();
}

function SetCurrentPage() {
  document.form.next_page.value    = window.location.pathname.substring(1);
  document.form.current_page.value = window.location.pathname.substring(1);
}

/* ---- Toggle helpers ---- */
function _syncToggle(id, active, labelOn, labelOff) {
  var chk   = document.getElementById(id);
  var label = document.getElementById(id + '_label');
  if (!chk || !label) return;
  chk.checked     = active;
  label.className = 'wlw_toggle_label ' + (active ? 'tog_on' : 'tog_off');
  label.innerHTML = active ? labelOn : labelOff;
}

function syncAllToggles() {
  _syncToggle('tog_cron',    custom_settings.wlw_cron_active === "1", 'SCHEDULER ON',   'SCHEDULER OFF');
  _syncToggle('tog_fw',      custom_settings.wlw_active      === "1", 'BLOCK ACTIVE',   'BLOCK INACTIVE');
  _syncToggle('tog_persist', custom_settings.wlw_persist     === "1", 'PERSISTENCE ON', 'PERSISTENCE OFF');
}

/* ---- Load settings ---- */
function loadSettings() {
  if (custom_settings.wlw_entries) {
    try {
      var raw = JSON.parse(custom_settings.wlw_entries);
      wlw_entries = raw.map(function(e){ return { type:e.type, value:e.value, _uid:_wlw_uid_counter++, _pending:false }; });
    } catch(e) { wlw_entries = []; }
  } else {
    var defaults = [
      { type:"mac", value:"aa:bb:cc:dd:ee:ff" },
      { type:"mac", value:"11:22:33:44:55:66" },
      { type:"int", value:"wl0.1" },
      { type:"int", value:"wl0.2" },
      { type:"ip",  value:"192.168.1.50" },
      { type:"ip",  value:"192.168.1.100" }
    ];
    wlw_entries = defaults.map(function(e){ return _makeEntry(e.type, e.value); }).map(function(e){ e._pending=false; return e; });
  }

  ['start_hh','start_mm','end_hh','end_mm'].forEach(function(k) {
    var el = document.getElementById('wlw_' + k);
    if (el && custom_settings['wlw_' + k] !== undefined) el.value = custom_settings['wlw_' + k];
  });

  wlw_days = _parseDays(custom_settings.wlw_days);

  try { wlw_resolve = JSON.parse(custom_settings.wlw_resolve || "{}"); } catch(e) { wlw_resolve = {}; }
  try { wlw_clients = JSON.parse(custom_settings.wlw_clients || "[]"); } catch(e) { wlw_clients = []; }
  try { wlw_ifaces  = JSON.parse(custom_settings.wlw_ifaces  || "[]"); } catch(e) { wlw_ifaces  = []; }
}

/* ---- Day serialisation ---- */
function _parseDays(stored) {
  if (!stored || stored === "*" || stored === "0,1,2,3,4,5,6") return [0,1,2,3,4,5,6];
  return stored.split(',').map(Number).filter(function(n){ return n >= 0 && n <= 6; });
}

function _serialiseDays(days) {
  if (!days || days.length === 0 || days.length === 7) return "*";
  return days.slice().sort(function(a,b){ return a-b; }).join(',');
}

/* ---- Day picker ---- */
function renderDayPicker() {
  var container = document.getElementById('wlw_day_picker_btns');
  if (!container) return;
  container.innerHTML = '';
  for (var d = 0; d < 7; d++) {
    (function(day) {
      var btn = document.createElement('span');
      btn.className = 'wlw_day_btn' + (isDaySelected(day) ? ' day_on' : '');
      btn.id        = 'wlw_day_' + day;
      btn.title     = DAY_LABELS[day];
      btn.textContent = DAY_LABELS[day];
      btn.onclick   = function() { toggleDay(day); };
      container.appendChild(btn);
    })(d);
  }
}

function isDaySelected(d) {
  return wlw_days.indexOf(d) !== -1;
}

function toggleDay(d) {
  if (isDaySelected(d)) {
    if (wlw_days.length === 1) {
      alert("At least one day must be selected.\nUse 'Every day' to re-select all.");
      return;
    }
    wlw_days = wlw_days.filter(function(x){ return x !== d; });
  } else {
    wlw_days.push(d);
  }
  var btn = document.getElementById('wlw_day_' + d);
  if (btn) btn.className = 'wlw_day_btn' + (isDaySelected(d) ? ' day_on' : '');
  updateDaysSummary();
}

function selectDays(preset) {
  var presets = {
    all:             [0,1,2,3,4,5,6],
    weekdays:        [1,2,3,4,5],
    weekends:        [0,6],
    offset_weekdays: [0,1,2,3,4],
    offset_weekends: [5,6]
  };
  if (presets[preset]) wlw_days = presets[preset];
  renderDayPicker();
  updateDaysSummary();
}

function updateDaysSummary() {
  var el = document.getElementById('wlw_days_summary');
  if (!el) return;
  var s = _serialiseDays(wlw_days);
  el.innerHTML = (s === '*') ? 'Every day'
    : wlw_days.slice().sort(function(a,b){return a-b;}).map(function(d){ return DAY_LABELS[d]; }).join(', ');
}

/* ---- Pack & submit ---- */
function packSettings() {
  custom_settings.wlw_entries     = JSON.stringify(wlw_entries.map(function(e){ return { type:e.type, value:e.value }; }));
  custom_settings.wlw_start_hh    = document.getElementById('wlw_start_hh').value;
  custom_settings.wlw_start_mm    = document.getElementById('wlw_start_mm').value;
  custom_settings.wlw_end_hh      = document.getElementById('wlw_end_hh').value;
  custom_settings.wlw_end_mm      = document.getElementById('wlw_end_mm').value;
  custom_settings.wlw_days        = _serialiseDays(wlw_days);
  custom_settings.wlw_active      = custom_settings.wlw_active      || "0";
  custom_settings.wlw_cron_active = custom_settings.wlw_cron_active || "0";
  custom_settings.wlw_persist     = custom_settings.wlw_persist     || "0";
  document.getElementById('amng_custom').value = JSON.stringify(custom_settings);
}

function submitAction(script, wait) {
  packSettings();
  document.form.action_script.value = script;
  document.form.action_wait.value   = String(wait);
  showLoading();
  document.form.submit();
}

function applySettings()          { submitAction("restart_wlwindow", 5); }

function cronControl(action) {
  if (!confirm("Are you sure you want to " + (action === 'enable' ? 'enable' : 'disable') + " the schedule?")) {
    _syncToggle('tog_cron', custom_settings.wlw_cron_active === "1", 'SCHEDULER ON', 'SCHEDULER OFF');
    return;
  }
  submitAction("restart_wlwindow_cron_" + action, 3);
}

function manualControl(action) {
  if (!confirm("Manually " + (action === 'start' ? 'activate' : 'deactivate') + " the firewall block now?")) {
    _syncToggle('tog_fw', custom_settings.wlw_active === "1", 'BLOCK ACTIVE', 'BLOCK INACTIVE');
    return;
  }
  submitAction("restart_wlwindow_" + action, 3);
}

function persistControl(action) {
  if (!confirm("Are you sure you want to " + (action === 'enable' ? 'enable' : 'disable') + " block persistence on reboot?")) {
    _syncToggle('tog_persist', custom_settings.wlw_persist === "1", 'PERSISTENCE ON', 'PERSISTENCE OFF');
    return;
  }
  submitAction("restart_wlwindow_persist_" + action, 3);
}

/* ---- Name resolution ---- */
function _resolveEntry(type, value) {
    if (type === 'int') return { assigned:'', associated:'' };

    // Primary: server-populated resolve map (entries that were saved on last Apply)
    var r = wlw_resolve[value];
    if (r && (r.assigned || r.associated)) return r;

    // Fallback: search wlw_clients (already loaded at page load) so newly added
    // entries show their names immediately without needing an Apply first.
    if (type === 'mac') {
        for (var i = 0; i < wlw_clients.length; i++) {
            if (wlw_clients[i].value === value) {
                return { assigned: wlw_clients[i].assigned || '', associated: wlw_clients[i].associated || '' };
            }
        }
    } else if (type === 'ip') {
        for (var i = 0; i < wlw_clients.length; i++) {
            if (wlw_clients[i].ip === value) {
                return { assigned: wlw_clients[i].assigned || '', associated: wlw_clients[i].associated || '' };
            }
        }
    }

    return { assigned:'', associated:'' };
}
/* ---- Whitelist table ---- */
function renderTable() {
  var tbody = document.getElementById('wlw_tbody');
  tbody.innerHTML = "";

  if (wlw_entries.length === 0) {
    tbody.innerHTML = '<tr class="wlw_empty_row"><td colspan="4">No entries &mdash; use the form below to add MACs, IPs, or interfaces.</td></tr>';
    return;
  }

  var order  = { mac:0, ip:1, int:2 };
  var sorted = wlw_entries.slice().sort(function(a,b){ return order[a.type] - order[b.type]; });
  var badgeMap = {
    mac: '<span class="wlw_type_badge wlw_type_mac">MAC</span>',
    ip:  '<span class="wlw_type_badge wlw_type_ip">IP</span>',
    int: '<span class="wlw_type_badge wlw_type_int">IFACE</span>'
  };

  for (var i = 0; i < sorted.length; i++) {
    var entry   = sorted[i];
    var resolve = _resolveEntry(entry.type, entry.value);
    var nameHtml;

    if (resolve.assigned && resolve.associated) {
      nameHtml = '<span class="wlw_name_assigned">' + escapeHtml(resolve.assigned)
               + ' <span class="wlw_name_associated">(' + escapeHtml(resolve.associated) + ')</span></span>';
    } else if (resolve.assigned) {
      nameHtml = '<span class="wlw_name_assigned">'   + escapeHtml(resolve.assigned)   + '</span>';
    } else if (resolve.associated) {
      nameHtml = '<span class="wlw_name_associated">' + escapeHtml(resolve.associated) + '</span>';
    } else {
      nameHtml = '<span class="wlw_name_none">&mdash;</span>';
    }

    var tr = document.createElement('tr');
    tr.innerHTML =
      '<td style="width:60px;text-align:center;">'  + badgeMap[entry.type] + '</td>' +
      '<td style="font-family:monospace;">'          + escapeHtml(entry.value) + '</td>' +
      '<td>'                                         + nameHtml + '</td>' +
      '<td style="width:80px;text-align:right;">' +
        '<button class="wlw_icon_btn btn_remove" title="Remove" onclick="deleteEntry(' + entry._uid + ');return false;">&minus;</button>' +
      '</td>';
    if (entry._pending) {
        tr.style.boxShadow = 'inset 0 0 5px 5px #4a7a96';
        var cells = tr.querySelectorAll('td');
        for (var c = 0; c < cells.length; c++) {
            cells[c].style.background = 'rgba(26, 58, 74, 0.60)';
        }
    }
    tbody.appendChild(tr);
  }
}

/* ---- Add-entry dropdown ---- */
function onTypeChange() {
  var type = document.getElementById('wlw_new_type').value;
  var sel  = document.getElementById('wlw_client_sel');
  var inp  = document.getElementById('wlw_new_value');
  sel.innerHTML = '';
  sel.style.display = 'none';
  inp.value = '';
  if (type === 'int') _populateInterfaceDropdown(sel, inp);
  else                _populateClientDropdown(sel, inp, type);
}

function _isWhitelisted(val) {
  return wlw_entries.some(function(e){ return e.value === val; });
}

function _addPlaceholderOption(sel, text) {
  var ph = document.createElement('option');
  ph.value = ''; ph.textContent = text;
  sel.appendChild(ph);
}

function _populateInterfaceDropdown(sel, inp) {
  inp.placeholder = 'e.g. wl0.1, wl0.2, eth5, eth6 \u2026';
  if (!wlw_ifaces.length) return;
  _addPlaceholderOption(sel, '\u2014 pick interface \u2014');
  var added = 0;
  wlw_ifaces.forEach(function(iface) {
    if (_isWhitelisted(iface.value)) return;
    var opt = document.createElement('option');
    opt.value = iface.value; opt.textContent = iface.label;
    sel.appendChild(opt); added++;
  });
  if (added) sel.style.display = '';
}

function _populateClientDropdown(sel, inp, type) {
  inp.placeholder = type === 'mac'
    ? 'e.g. aa:bb:cc:dd:ee:ff \u2026'
    : 'e.g. 192.168.1.40 or 2001:0db8:: \u2026';
  if (!wlw_clients.length) return;
  _addPlaceholderOption(sel, '\u2014 pick client \u2014');

  var sorted = wlw_clients.slice().sort(function(a, b) {
    if (a.status !== b.status) return a.status === 'ACTIVE' ? -1 : 1;
    return (a.assigned || a.associated || a.value).localeCompare(b.assigned || b.associated || b.value);
  });

  var added = 0;
  sorted.forEach(function(c) {
    var val = (type === 'mac') ? c.value : c.ip;
    if (!val || _isWhitelisted(val)) return;
    var displayName = c.assigned || c.associated || val;
    var subName     = (c.assigned && c.associated) ? ' (' + c.associated + ')' : '';
    var opt = document.createElement('option');
    opt.value = val;
    opt.textContent = displayName + subName + ' \u2014 ' + c.status + ' [' + val + ']';
    opt.className   = (c.status === 'ACTIVE') ? 'wlw_opt_active' : 'wlw_opt_inactive';
    sel.appendChild(opt); added++;
  });
  if (added) sel.style.display = '';
}

function onClientSelect(val) {
  if (val) document.getElementById('wlw_new_value').value = val;
}

/* ---- Add / delete entries ---- */
function addEntry() {
  var type  = document.getElementById('wlw_new_type').value;
  var value = document.getElementById('wlw_new_value').value.trim().toLowerCase();
  if (!value) { alert("Please enter or select a value."); return; }

  if (type === "mac") {
    if (!/^([0-9a-f]{2}:){5}[0-9a-f]{2}$/.test(value)) {
      alert("Invalid MAC address.\nExpected format: xx:xx:xx:xx:xx:xx"); return;
    }
  } else if (type === "ip") {
    var isIPv4 = /^(\d{1,3}\.){3}\d{1,3}$/.test(value);
    var isIPv6 = value.indexOf(':') !== -1 && /^[0-9a-f:\/]+$/.test(value);
    if (!isIPv4 && !isIPv6) { alert("Invalid IP address."); return; }
    if (isIPv4 && value.split('.').some(function(o){ return parseInt(o,10) > 255; })) {
      alert("Invalid IPv4 address \u2014 octet out of range."); return;
    }
  } else if (type === "int") {
    if (!/^[a-z0-9._-]+$/i.test(value)) {
      alert("Invalid interface name.\nExpected: eth5, wl0.1, wl0.2, etc."); return;
    }
  }

  if (_isWhitelisted(value)) { alert("Already in the whitelist."); return; }

  wlw_entries.push(_makeEntry(type, value));
  document.getElementById('wlw_new_value').value = "";
  renderTable();
  onTypeChange();
}

function deleteEntry(uid) {
  var idx = wlw_entries.findIndex(function(e){ return e._uid === uid; });
  if (idx === -1) return;
  if (!confirm('Remove "' + wlw_entries[idx].value + '" from the whitelist?')) return;
  wlw_entries.splice(idx, 1);
  renderTable();
  onTypeChange();
}

/* ---- Utilities ---- */
function escapeHtml(s) {
  return String(s).replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;").replace(/"/g,"&quot;");
}

function wlw_keydown(e) {
  if (e.keyCode === 13) { addEntry(); return false; }
}
</script>
</head>

<body onload="initial();" class="bg">
<div id="TopBanner"></div>
<div id="Loading" class="popup_bg"></div>
<iframe name="hidden_frame" id="hidden_frame" src="" width="0" height="0" frameborder="0"></iframe>

<form method="post" name="form" action="start_apply.htm" target="hidden_frame">
<input type="hidden" name="current_page"   value="WL_Window.asp">
<input type="hidden" name="next_page"      value="WL_Window.asp">
<input type="hidden" name="group_id"       value="">
<input type="hidden" name="modified"       value="0">
<input type="hidden" name="action_mode"    value="apply">
<input type="hidden" name="action_wait"    value="5">
<input type="hidden" name="first_time"     value="">
<input type="hidden" name="action_script"  value="restart_wlwindow">
<input type="hidden" name="preferred_lang" id="preferred_lang" value="<% nvram_get("preferred_lang"); %>">
<input type="hidden" name="firmver"        value="<% nvram_get("firmver"); %>">
<input type="hidden" name="amng_custom"    id="amng_custom" value="">

<table class="content" align="center" cellpadding="0" cellspacing="0">
<tr>
  <td width="17">&nbsp;</td>
  <td valign="top" width="202">
    <div id="mainMenu"></div>
    <div id="subMenu"></div>
  </td>
  <td valign="top">
    <div id="tabMenu" class="submenuBlock"></div>
    <table width="98%" border="0" align="left" cellpadding="0" cellspacing="0">
    <tr>
    <td align="left" valign="top">

      <table width="760px" border="0" cellpadding="5" cellspacing="0"
             bordercolor="#6b8fa3" class="FormTitle" id="FormTitle">
      <tr>
      <td bgcolor="#4D595D" colspan="3" valign="top">

        <div>&nbsp;</div>
        <div class="formfonttitle">Whitelist Window &mdash; Internet Access Scheduler</div>
        <div style="margin:10px 0 10px 5px;" class="splitLine"></div>
        <div class="formfontdesc">
          Blocks internet access during a scheduled window, <strong>except for authorized (whitelisted) devices</strong>. Preventing users from bypassing restrictions with <strong>MAC Randomization</strong>. A feature most modern devices have enabled by default.<br><strong>Turn off MAC Randomization</strong> and reset wifi on devices before adding to the whitelist.
        </div>

        <!-- SCHEDULE / CRON CONTROL -->
        <div class="wlw_section_label" style="margin-top:16px;">Internet Access Management</div>
        <table width="100%" border="1" align="center" cellpadding="4" cellspacing="0"
               bordercolor="#6b8fa3" class="FormTable">

          <tr>
            <th style="width:160px;" class="wlw_th_mid">Scheduler (Cron)</th>
            <td>
              <div class="wlw_toggle_wrap">
                <label class="wlw_toggle">
                  <input type="checkbox" id="tog_cron"
                         onchange="cronControl(this.checked ? 'enable' : 'disable');">
                  <span class="wlw_toggle_track"></span>
                </label>
                <span class="wlw_toggle_label tog_off" id="tog_cron_label">SCHEDULER OFF</span>
              </div>
            </td>
          </tr>

          <tr>
            <th>Block Start (HH:MM)</th>
            <td>
              <input type="text" id="wlw_start_hh" maxlength="2" class="input_6_table"
                     value="22" style="width:38px;text-align:center;" autocorrect="off">
              &nbsp;:&nbsp;
              <input type="text" id="wlw_start_mm" maxlength="2" class="input_6_table"
                     value="00" style="width:38px;text-align:center;" autocorrect="off">
              <span class="wlw_hint">&nbsp;24-hour &middot; block activates at this time</span>
            </td>
          </tr>

          <tr>
            <th>Block End (HH:MM)</th>
            <td>
              <input type="text" id="wlw_end_hh" maxlength="2" class="input_6_table"
                     value="06" style="width:38px;text-align:center;" autocorrect="off">
              &nbsp;:&nbsp;
              <input type="text" id="wlw_end_mm" maxlength="2" class="input_6_table"
                     value="00" style="width:38px;text-align:center;" autocorrect="off">
              <span class="wlw_hint">&nbsp;24-hour &middot; block lifts at this time</span>
            </td>
          </tr>

          <tr>
            <th class="wlw_th_mid">
              Days (<span id="wlw_days_summary"></span> )
              <div class="wlw_warn" style="margin:6px 6px 6px 0;">
                <span class="wlw_warn_title">&#9888;&nbsp;&nbsp;MIDNIGHT SCHEDULE NOTE&nbsp;&nbsp;&#9888;</span>
                <div class="wlw_warn_body">If the block schedule crosses midnight, be mindful of what day the block starts/ends.</div>
              </div>
            </th>
            <td>
              <div id="wlw_day_picker_btns" class="wlw_day_picker"></div>
              <div class="wlw_day_shortcut_bar">
                <button class="wlw_day_shortcut" onclick="selectDays('weekdays');return false;">Weekdays (Mon&ndash;Fri)</button>
                <button class="wlw_day_shortcut" onclick="selectDays('offset_weekdays');return false;">Midnight Weekdays (Sun&ndash;Thu)</button>
              </div>
              <div class="wlw_day_shortcut_bar">
                <button class="wlw_day_shortcut" onclick="selectDays('weekends');return false;">Weekends (Sat&ndash;Sun)</button>
                <button class="wlw_day_shortcut" onclick="selectDays('offset_weekends');return false;">Midnight Weekends (Fri&ndash;Sat)</button>
                <button class="wlw_day_shortcut" onclick="selectDays('all');return false;">Every day</button>
              </div>
              <div class="wlw_hint" style="margin-top:4px;">Click a day to toggle it. Click Apply for changes to take effect.</div>
            </td>
          </tr>

          <tr>
            <th style="width:160px;" class="wlw_th_mid">Internet Access Block (Manual Control)</th>
            <td>
              <div class="wlw_toggle_wrap">
                <label class="wlw_toggle">
                  <input type="checkbox" id="tog_fw"
                         onchange="manualControl(this.checked ? 'start' : 'stop');">
                  <span class="wlw_toggle_track"></span>
                </label>
                <span class="wlw_toggle_label tog_off" id="tog_fw_label">BLOCK INACTIVE</span>
              </div>
            </td>
          </tr>

          <tr>
            <th style="width:160px;" class="wlw_th_mid">Block Persistence (Survives Reboot)</th>
            <td>
              <div class="wlw_toggle_wrap">
                <label class="wlw_toggle">
                  <input type="checkbox" id="tog_persist"
                         onchange="persistControl(this.checked ? 'enable' : 'disable');">
                  <span class="wlw_toggle_track"></span>
                </label>
                <span class="wlw_toggle_label tog_off" id="tog_persist_label">PERSISTENCE OFF</span>
              </div>
            </td>
          </tr>

        </table>

        <!-- WHITELIST TABLE -->
        <div class="wlw_section_label" style="margin-top:8px;">
          Whitelist Management (<span style="font-weight:normal;"> Click Apply to populate/refresh dropdown with existing clients </span>)
        </div>
        <table id="wlw_entry_table" width="100%" border="1" align="center"
               cellpadding="0" cellspacing="0" bordercolor="#6b8fa3"
               class="FormTable" style="table-layout:fixed;">
          <thead></thead>
          <tr style="background: #3a5060;color: #7a9aaa;font-size:12px;">
            <td style="width:max-content;padding:8px 10px;text-align:center;">
              <select id="wlw_new_type" class="wlw_type_sel" style="width:100%;"
                      onchange="onTypeChange();">
                <option value="mac">MAC</option>
                <option value="ip">IP</option>
                <option value="int">IFACE</option>
              </select>
            </td>
            <td colspan="2" style="padding:8px 10px;text-align:center;">
              <div class="wlw_add_row_inner">
                <input type="text" id="wlw_new_value" class="wlw_value_input"
                       placeholder="e.g. aa:bb:cc:dd:ee:ff ..."
                       autocorrect="off" autocapitalize="off" autocomplete="on"
                       onkeydown="wlw_keydown(event);">
                <select id="wlw_client_sel" class="wlw_client_sel"
                        style="display:none;"
                        onchange="onClientSelect(this.value);">
                </select>
              </div>
            </td>
            <td style="width:max-content;text-align:right;">
              <button class="wlw_icon_btn btn_add" title="Add" onclick="addEntry();return false;">+</button>
            </td>
          </tr>
          <tbody id="wlw_tbody"></tbody>
          <tfoot></tfoot>
        </table>

        <!-- APPLY -->
        <div class="apply_gen">
          <input name="button" type="button" class="button_gen"
                 onclick="applySettings();" value="Apply" />
        </div>

      </td>
      </tr>
      </table>

    </td>
    </tr>
    </table>
  </td>
  <td width="10" align="center" valign="top"></td>
</tr>
</table>
</form>

<div id="footer"></div>
</body>
</html>
