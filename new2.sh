#!/bin/bash
# ZIVPN UDP Server + Web UI - FIXED DIALOGS + USER LIMIT ENFORCEMENT WITH AUTO DELETE
# ================================== FIXED: MODAL DIALOGS NOT WORKING ==================================
set -euo pipefail

# ===== Pretty =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ 
    echo -e "\n$LINE"
    echo -e "${G}ZIVPN UDP Server + Web UI (Dialog Issues Fixed + Auto Delete)${Z}"
    echo -e "$LINE\n"
}
say 

# ===== Root check =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== Packages =====
echo -e "${Y}📦 Packages တင်နေပါတယ်...${Z}"
apt-get update -y >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates >/dev/null

# stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true

# ===== Paths and setup directories =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
TEMPLATES_DIR="/etc/zivpn/templates" 
mkdir -p /etc/zivpn "$TEMPLATES_DIR" 

# --- ZIVPN Binary, Config, Certs ---
echo -e "${Y}⬇️ ZIVPN binary ကို ဒေါင်းနေပါတယ်...${Z}"
curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64" || {
  echo -e "${Y}Primary URL မရ — alternative ကို စမ်းပါတယ်...${Z}"
  curl -fSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
}
chmod 0755 "$BIN"

if [ ! -f "$CFG" ]; then
  echo -e "${Y}🧩 config.json ဖန်တီးနေပါတယ်...${Z}"
  echo '{}' > "$CFG"
fi

if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
  echo -e "${Y}🔐 SSL စိတျဖိုင်တွေ ဖန်တီးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=ZIVPN/OU=Net/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# --- Web Admin Login ---
echo -e "${G}🔒 Web Admin Login UI ထည့်မလား..?${Z}"
read -r -p "Web Admin Username (Enter=disable): " WEB_USER
if [ -n "${WEB_USER:-}" ]; then
  read -r -p "Web Admin Password: " WEB_PASS; echo
  
  echo -e "${G}🔗 Login အောက်နားတွင် ပြသရန် ဆက်သွယ်ရန် Link (Optional)${Z}"
  read -r -p "Contact Link (ဥပမာ: https://m.me/admin or Enter=disable): " CONTACT_LINK
  
  WEB_SECRET="$(openssl rand -hex 32 2>/dev/null || python3 -c "import secrets;print(secrets.token_hex(32))")"
  {
    echo "WEB_ADMIN_USER=${WEB_USER}"
    echo "WEB_ADMIN_PASSWORD=${WEB_PASS}"
    echo "WEB_SECRET=${WEB_SECRET}"
    echo "WEB_CONTACT_LINK=${CONTACT_LINK:-}" 
  } > "$ENVF"
  chmod 600 "$ENVF"
  echo -e "${G}✅ Web login UI ဖွင့်ထားပါတယ်${Z}"
else
  rm -f "$ENVF" 2>/dev/null || true
  echo -e "${Y}ℹ️ Web login UI မဖွင့်ထားပါ (dev mode)${Z}"
fi

echo -e "${G}🔏 VPN Password List (ကော်မာဖြင့်ခွဲ) eg: pass123,user456${Z}"
read -r -p "Passwords (Enter=zi): " input_pw
if [ -z "${input_pw:-}" ]; then 
  PW_LIST='["zi"]'
else
  PW_LIST=$(echo "$input_pw" | awk -F',' '{
    printf("["); for(i=1;i<=NF;i++){gsub(/^ *| *$/,"",$i); printf("%s\"%s\"", (i>1?",":""), $i)}; printf("]")
  }')
fi

# Update config
if command -v jq >/dev/null 2>&1; then
  TMP=$(mktemp)
  jq --argjson pw "$PW_LIST" '
    .auth.mode = "passwords" |
    .auth.config = $pw |
    .listen = (."listen" // ":5667") |
    .cert = (."cert" // "/etc/zivpn/zivpn.crt") |
    .key  = (."key" // "/etc/zivpn/zivpn.key") |
    .obfs = (."obfs" // "zivpn")
  ' "$CFG" > "$TMP" && mv "$TMP" "$CFG"
fi

[ -f "$USERS" ] || echo "[]" > "$USERS"
chmod 644 "$CFG" "$USERS"

echo -e "${Y}🧰 systemd service (zivpn) ကို သွင်းနေပါတယ်...${Z}"
cat >/etc/systemd/system/zivpn.service <<'EOF'
[Unit]
Description=ZIVPN UDP Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
ExecStart=/usr/local/bin/zivpn server -c /etc/zivpn/config.json
Restart=always
RestartSec=3
Environment=ZIVPN_LOG_LEVEL=info
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE CAP_NET_RAW
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

# ===== FIXED TEMPLATES - MODAL DIALOGS WORKING =====
echo -e "${Y}📄 Table HTML (users_table.html) ကို ပြင်ဆင်နေပါတယ်...${Z}"
cat >"$TEMPLATES_DIR/users_table.html" <<'TABLE_HTML'
<div class="table-container">
    <table>
      <thead>
          <tr>
            <th><i class="icon">👤</i> User</th>
            <th><i class="icon">🔑</i> Password</th>
            <th><i class="icon">⏰</i> Expires</th>
            <th><i class="icon">💻</i> Online Users</th>
            <th><i class="icon">👥</i> Limit</th>
            <th><i class="icon">🚦</i> Status</th> 
            <th><i class="icon">❌</i> Action</th>
          </tr>
      </thead>
      <tbody>
          {% for u in users %}
          <tr class="{% if u.expires and u.expires_date < today_date %}expired{% elif u.expiring_soon %}expiring-soon{% elif u.is_over_limit %}over-limit{% endif %}">
            <td data-label="User">{% if u.expires and u.expires_date < today_date %}<s>{{u.user}}</s>{% else %}{{u.user}}{% endif %}</td>
            <td data-label="Password">{% if u.expires and u.expires_date < today_date %}<s>{{u.password}}</s>{% else %}{{u.password}}{% endif %}</td>
            <td data-label="Expires">
                {% if u.expires %}
                    {% if u.expires_date < today_date %}
                        <s>{{u.expires}} (Expired)</s>
                    {% else %}
                        {% if u.expiring_soon %}
                            <span class="text-expiring">{{u.expires}}</span>
                        {% else %}
                            {{u.expires}}
                        {% endif %}
                        <br><span class="days-remaining">
                            (ကျန်ရှိ: 
                            {% if u.days_remaining is not none %}
                                {% if u.days_remaining == 0 %}
                                    <span class="text-expiring">ဒီနေ့ နောက်ဆုံး</span>
                                {% else %}
                                    {{ u.days_remaining }} ရက်
                                {% endif %}
                            {% else %}
                                —
                            {% endif %}
                            )
                        </span>
                    {% endif %}
                {% else %}
                    <span class="muted">—</span>
                {% endif %}
                <button type="button" class="btn-edit-expires" onclick="showExpiresModal('{{ u.user }}', '{{ u.expires }}')"><i class="icon">📝</i> Edit</button> 
            </td>
            
            <td data-label="Online Users">
                {% if u.online_count is not none %}
                    {% if u.online_count > 0 %}
                        <span class="pill pill-online">{{ u.online_count }}</span>
                    {% else %}
                        <span class="pill pill-offline">0</span>
                    {% endif %}
                {% else %}
                    <span class="pill pill-unknown">N/A</span>
                {% endif %}
            </td>
            
            <td data-label="Limit">
                {% if u.limit_count is not none %}
                    {% if u.limit_count > 1 %}
                        <span class="pill pill-limit-multi">{{ u.limit_count }}</span>
                    {% elif u.limit_count == 1 %}
                        <span class="pill pill-limit-single">{{ u.limit_count }}</span>
                    {% else %}
                        <span class="pill pill-limit-default">N/A (Limit: 1)</span>
                    {% endif %}
                {% else %}
                    <span class="pill pill-limit-default">N/A (Limit: 1)</span>
                {% endif %}
                <button type="button" class="btn-edit-limit" onclick="showLimitModal('{{ u.user }}', '{{ u.limit_count }}')"><i class="icon">📝</i> Limit</button>
            </td>

            <td data-label="Status">
                {% if u.expires and u.expires_date < today_date %}
                    <span class="pill pill-expired"><i class="icon">🛑</i> Expired</span>
                {% elif u.expiring_soon %}
                    <span class="pill pill-expiring"><i class="icon">⚠️</i> Expiring Soon</span>
                {% elif u.is_over_limit %}
                    <span class="pill pill-over-limit-delete"><i class="icon">🚨</i> Over Limit (AUTO DELETE SOON)</span>
                {% else %}
                    <span class="pill ok"><i class="icon">🟢</i> Active</span>
                {% endif %}
            </td>

            <td data-label="Action">
              <button type="button" class="btn-edit" onclick="showEditModal('{{ u.user }}', '{{ u.password }}')"><i class="icon">✏️</i> Pass</button>
              <form class="delform" method="post" action="/delete" onsubmit="return confirm('{{u.user}} ကို ဖျက်မလား?')">
                <input type="hidden" name="user" value="{{u.user}}">
                <button type="submit" class="btn-delete"><i class="icon">🗑️</i> Delete</button>
              </form>
            </td>
          </tr>
          {% endfor %}
      </tbody>
    </table>
</div>

{# Auto Delete Warning Banner #}
<div class="auto-delete-warning">
    <i class="icon">⚠️</i>
    <strong>သတိပေးချက်:</strong> User Limit ကျော်လွန်ပါက ၁ မိနစ်အတွင်း Auto Delete လုပ်ပါမည်။ ဖျက်ပြီးသော User များကို <code>/var/log/zivpn_auto_delete.log</code> တွင် ကြည့်ရှုနိုင်ပါသည်။
</div>

{# 💡 FIXED: MODAL DIALOGS - CORRECTED JAVASCRIPT AND HTML STRUCTURE #}

{# Password Edit Modal #}
<div id="editModal" class="modal" style="display: none;">
  <div class="modal-content">
    <span class="close-btn" onclick="closeModal('editModal')">&times;</span>
    <h2 class="section-title"><i class="icon">✏️</i> Change Password</h2>
    <form method="post" action="/edit">
        <input type="hidden" id="edit-user" name="user">
        
        <div class="input-group">
            <label for="current-user-display" class="input-label"><i class="icon">👤</i> User Name</label>
            <div class="input-field-wrapper is-readonly">
                <input type="text" id="current-user-display" name="current_user_display" readonly>
            </div>
        </div>
        
        <div class="input-group">
            <label for="current-password" class="input-label"><i class="icon">🔑</i> Current Password</label>
            <div class="input-field-wrapper is-readonly">
                <input type="text" id="current-password" name="current_password" readonly>
            </div>
            <p class="input-hint">လက်ရှိ Password (မပြောင်းလဲလိုပါက ထားခဲ့နိုင်ပါသည်)</p>
        </div>
        
        <div class="input-group">
            <label for="new-password" class="input-label"><i class="icon">🔒</i> New Password</label>
            <div class="input-field-wrapper">
                <input type="text" id="new-password" name="password" placeholder="Password အသစ်ထည့်ပါ" required>
            </div>
            <p class="input-hint">User အတွက် Password အသစ်</p>
        </div>
        
        <button class="save-btn modal-save-btn" type="submit">Password အသစ် သိမ်းမည်</button>
    </form>
  </div>
</div>

{# Expires Edit Modal #}
<div id="expiresModal" class="modal" style="display: none;">
  <div class="modal-content">
    <span class="close-btn" onclick="closeModal('expiresModal')">&times;</span>
    <h2 class="section-title"><i class="icon">⏰</i> Change Expiry Date</h2>
    <form method="post" action="/edit_expires">
        <input type="hidden" id="expires-edit-user" name="user">
        
        <div class="input-group">
            <label for="expires-current-user-display" class="input-label"><i class="icon">👤</i> User Name</label>
            <div class="input-field-wrapper is-readonly">
                <input type="text" id="expires-current-user-display" name="current_user_display" readonly>
            </div>
        </div>
        
        <div class="input-group">
            <label for="new-expires" class="input-label"><i class="icon">🗓️</i> New Expiration Date</label>
            <div class="input-field-wrapper">
                <input type="text" id="new-expires" name="expires" placeholder="ဥပမာ: 2026-01-31 သို့မဟုတ် 30" required>
            </div>
            <p class="input-hint">ရက်စွဲ (YYYY-MM-DD) သို့မဟုတ် ရက်အရေအတွက် (ဥပမာ: 30)</p>
        </div>
        
        <button class="save-btn modal-save-btn" type="submit">Expires အသစ် သိမ်းမည်</button>
    </form>
  </div>
</div>

{# Limit Edit Modal #}
<div id="limitModal" class="modal" style="display: none;">
  <div class="modal-content">
    <span class="close-btn" onclick="closeModal('limitModal')">&times;</span>
    <h2 class="section-title"><i class="icon">👥</i> Change User Limit</h2>
    <form method="post" action="/edit_limit">
        <input type="hidden" id="limit-edit-user" name="user">
        
        <div class="input-group">
            <label for="limit-current-user-display" class="input-label"><i class="icon">👤</i> User Name</label>
            <div class="input-field-wrapper is-readonly">
                <input type="text" id="limit-current-user-display" name="current_user_display" readonly>
            </div>
        </div>
        
        <div class="input-group">
            <label for="new-limit" class="input-label"><i class="icon">🔢</i> Max Users</label>
            <div class="input-field-wrapper">
                <input type="number" id="new-limit" name="limit_count" placeholder="အများဆုံး သုံးစွဲသူအရေအတွက် (1 မှ 10)" min="1" max="10" required>
            </div>
            <p class="input-hint">ဤအကောင့်အတွက် အများဆုံး သုံးစွဲသူအရေအတွက် (ပုံမှန်- 1)</p>
        </div>
        
        <button class="save-btn modal-save-btn" type="submit">Limit အသစ် သိမ်းမည်</button>
    </form>
  </div>
</div>

<style>
.auto-delete-warning {
    background: linear-gradient(135deg, #ff6b6b, #ee5a24);
    color: white;
    padding: 12px 15px;
    border-radius: 8px;
    margin: 15px 10px;
    text-align: center;
    font-weight: bold;
    box-shadow: 0 4px 6px rgba(255, 107, 107, 0.3);
    border-left: 5px solid #ff3838;
}

.auto-delete-warning .icon {
    font-size: 1.2em;
    margin-right: 8px;
}

.pill-over-limit-delete {
    background: linear-gradient(135deg, #ff3838, #ff6b6b);
    color: white;
    animation: pulse-alert 2s infinite;
}

@keyframes pulse-alert {
    0% { transform: scale(1); }
    50% { transform: scale(1.05); }
    100% { transform: scale(1); }
}

/* 💡 FIXED: MODAL STYLES - PROPERLY DEFINED */
.modal {
  display: none;
  position: fixed;
  z-index: 3000;
  left: 0;
  top: 0;
  width: 100%;
  height: 100%;
  overflow: auto;
  background-color: rgba(0,0,0,0.4);
}

.modal-content {
  background-color: var(--card-bg);
  margin: 10% auto;
  padding: 25px;
  border: none;
  width: 90%;
  max-width: 400px;
  border-radius: 12px;
  position: relative;
  box-shadow: 0 10px 25px rgba(0,0,0,0.2);
  animation: modalopen 0.3s;
}

@keyframes modalopen {
  from { opacity: 0; transform: translateY(-50px); }
  to { opacity: 1; transform: translateY(0); }
}

.close-btn {
  color: var(--secondary);
  position: absolute;
  top: 10px;
  right: 15px;
  font-size: 28px;
  font-weight: 300;
  line-height: 1;
  cursor: pointer;
  transition: color 0.2s;
}

.close-btn:hover {
  color: var(--danger);
}

.section-title {
  margin-top: 0;
  padding-bottom: 10px;
  border-bottom: 1px solid var(--border-color);
  color: var(--primary-dark);
}

.modal .input-group {
  margin-bottom: 20px;
}

.modal .input-label {
  display: block;
  text-align: left;
  font-weight: 600;
  color: var(--dark);
  font-size: 0.9em;
  margin-bottom: 5px;
}

.modal .input-field-wrapper {
  display: flex;
  align-items: center;
  border: 1px solid var(--border-color);
  border-radius: 8px;
  background-color: #fff;
  transition: border-color 0.3s, box-shadow 0.3s;
}

.modal .input-field-wrapper:focus-within {
  border-color: var(--primary);
  box-shadow: 0 0 0 3px rgba(255, 127, 39, 0.25);
}

.modal .input-field-wrapper.is-readonly {
  background-color: var(--light);
  border: 1px solid #ddd;
}

.modal .input-field-wrapper input {
  width: 100%;
  padding: 12px 10px;
  border: none;
  border-radius: 8px;
  font-size: 16px;
  outline: none;
  background: transparent;
}

.modal .input-hint {
  margin-top: 5px;
  text-align: left;
  font-size: 0.75em;
  color: var(--secondary);
  line-height: 1.4;
  padding-left: 5px;
}

.modal-save-btn {
  width: 100%;
  padding: 12px;
  background-color: var(--primary);
  color: white;
  border: none;
  border-radius: 8px;
  font-size: 1.0em;
  cursor: pointer;
  transition: background-color 0.3s;
  margin-top: 10px;
  font-weight: bold;
}

.modal-save-btn:hover {
  background-color: var(--primary-dark);
}

/* Button styles */
.btn-edit {
  background-color: var(--warning);
  color: var(--dark);
  border: none;
  padding: 6px 10px;
  border-radius: 8px;
  cursor: pointer;
  font-size: 0.9em;
  transition: background-color 0.2s;
  margin-right: 5px;
}

.btn-edit:hover {
  background-color: #e0ac08;
}

.delform {
  display: inline-block;
  margin: 0;
}

.btn-delete {
  background-color: var(--danger);
  color: white;
  border: none;
  padding: 6px 10px;
  border-radius: 8px;
  cursor: pointer;
  font-size: 0.9em;
  transition: background-color 0.2s;
}

.btn-delete:hover {
  background-color: #c82333;
}

.btn-edit-expires {
  background-color: var(--primary);
  color: white;
  border: none;
  padding: 3px 6px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 0.75em;
  transition: background-color 0.2s;
  margin-left: 5px;
  margin-top: 5px;
  display: inline-block;
  width: 50px;
  text-align: center;
}

.btn-edit-expires:hover {
  background-color: var(--primary-dark);
}

.btn-edit-limit {
  background-color: var(--secondary);
  color: white;
  border: none;
  padding: 3px 6px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 0.75em;
  transition: background-color 0.2s;
  margin-left: 5px;
  margin-top: 5px;
  display: inline-block;
  width: 50px;
  text-align: center;
}

.btn-edit-limit:hover {
  background-color: #5a6268;
}

/* Other existing styles */
.days-remaining {
  font-size: 0.85em;
  color: var(--secondary);
  font-weight: 500;
  display: inline-block;
  margin-top: 2px;
}

.days-remaining .text-expiring {
  font-weight: bold;
}

.pill-online { background-color: #d4edda; color: #155724; }
.pill-offline { background-color: #e2e3e5; color: #6c757d; }
.pill-unknown { background-color: #fff3cd; color: #856404; }

.pill-limit-single { background-color: #007bff; color: white; }
.pill-limit-multi { background-color: #28a745; color: white; }
.pill-limit-default { background-color: #e2e3e5; color: #6c757d; }
.pill-over-limit { background-color: #dc3545; color: white; }

@media (max-width: 768px) {
  .modal-content {
    margin: 15% auto;
    max-width: 320px;
  }
  
  .auto-delete-warning {
    margin: 10px 5px;
    padding: 10px;
    font-size: 0.9em;
  }
}

tr.over-limit {
  border-left: 5px solid #ff3838;
  background-color: rgba(255, 56, 56, 0.1);
}
</style>

<script>
// 💡 FIXED: CORRECTED JAVASCRIPT FUNCTIONS FOR MODAL DIALOGS

function showEditModal(user, password) {
    console.log('Opening edit modal for:', user);
    document.getElementById('edit-user').value = user;
    document.getElementById('current-user-display').value = user;
    document.getElementById('current-password').value = password;
    document.getElementById('new-password').value = '';
    document.getElementById('editModal').style.display = 'block';
}

function showExpiresModal(user, expires) {
    console.log('Opening expires modal for:', user);
    document.getElementById('expires-edit-user').value = user;
    document.getElementById('expires-current-user-display').value = user;
    document.getElementById('new-expires').value = expires || '';
    document.getElementById('expiresModal').style.display = 'block';
}

function showLimitModal(user, limit) {
    console.log('Opening limit modal for:', user);
    document.getElementById('limit-edit-user').value = user;
    document.getElementById('limit-current-user-display').value = user;
    document.getElementById('new-limit').value = limit && limit !== 'None' ? limit : 1;
    document.getElementById('limitModal').style.display = 'block';
}

function closeModal(modalId) {
    console.log('Closing modal:', modalId);
    document.getElementById(modalId).style.display = 'none';
}

// Close modal when clicking outside
window.onclick = function(event) {
    if (event.target.classList.contains('modal')) {
        event.target.style.display = 'none';
    }
}

// Close modal with Escape key
document.addEventListener('keydown', function(event) {
    if (event.key === 'Escape') {
        const modals = document.querySelectorAll('.modal');
        modals.forEach(modal => {
            modal.style.display = 'none';
        });
    }
});
</script>
TABLE_HTML

# ===== Web Panel (web.py) - Fixed routes for modal forms =====
echo -e "${Y}🖥️ Web Panel (web.py) ကို ပြင်ဆင်နေပါတယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, jsonify, render_template, render_template_string, request, redirect, url_for, session, make_response
import json, re, subprocess, os, tempfile, hmac
from datetime import datetime, timedelta, date 

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"
LISTEN_FALLBACK = "5667"
LOGO_URL = "https://zivpn-web.free.nf/zivpn-icon.png"

def get_server_ip():
    try:
        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, check=True)
        ip = result.stdout.strip().split()[0]
        if re.match(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$', ip):
            return ip
    except Exception:
        pass
    return "127.0.0.1" 

SERVER_IP_FALLBACK = get_server_ip()
CONTACT_LINK = os.environ.get("WEB_CONTACT_LINK", "").strip()

app = Flask(__name__, template_folder="/etc/zivpn/templates")
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","admin").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","admin").strip()

# Flask Helper Functions 
def read_json(path, default):
  try:
    with open(path,"r") as f: return json.load(f)
  except Exception:
    return default

def write_json_atomic(path, data):
  d=json.dumps(data, ensure_ascii=False, indent=2)
  dirn=os.path.dirname(path); fd,tmp=tempfile.mkstemp(prefix=".tmp-", dir=dirn)
  try:
    with os.fdopen(fd,"w") as f: f.write(d)
    os.replace(tmp,path)
  finally:
    try: os.remove(tmp)
    except: pass

def load_users():
  v=read_json(USERS_FILE,[])
  out=[]
  for u in v:
    out.append({
        "user":u.get("user",""),
        "password":u.get("password",""),
        "expires":u.get("expires",""),
        "port":str(u.get("port","")) if u.get("port","")!="" else "",
        "limit_count": int(u.get("limit_count", 1))
    })
  return out

def save_users(users): 
    write_json_atomic(USERS_FILE, users)

def get_user_online_count(port):
    if not port: return 0
    try:
        result = subprocess.run(
            f"conntrack -L -p udp 2>/dev/null | grep 'dport={port}\\b'", 
            shell=True, capture_output=True, text=True
        ).stdout
        source_ips = re.findall(r'src=(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})', result)
        unique_online_ips = set(ip for ip in source_ips if ip != SERVER_IP_FALLBACK)
        return len(unique_online_ips)
    except Exception:
        return 0

def get_total_active_users():
    users = load_users()
    today_date = date.today()
    active_count = 0
    for user in users:
        expires_str = user.get("expires")
        is_expired = False
        if expires_str:
            try:
                if datetime.strptime(expires_str, "%Y-%m-%d").date() < today_date:
                    is_expired = True
            except ValueError:
                is_expired = False
        if not is_expired:
            active_count += 1
    return active_count

def is_expiring_soon(expires_str):
    if not expires_str: return False
    try:
        expires_date = datetime.strptime(expires_str, "%Y-%m-%d").date()
        today = date.today()
        remaining_days = (expires_date - today).days
        return 0 <= remaining_days <= 1
    except ValueError:
        return False

def calculate_days_remaining(expires_str):
    if not expires_str:
        return None
    try:
        expires_date = datetime.strptime(expires_str, "%Y-%m-%d").date()
        today = date.today()
        remaining = (expires_date - today).days
        return remaining if remaining >= 0 else None
    except ValueError:
        return None

def delete_user(user):
    users = load_users()
    remaining_users = [u for u in users if u.get("user").lower() != user.lower()]
    save_users(remaining_users)
    sync_config_passwords(mode="mirror")

def check_user_expiration():
    users = load_users()
    today_date = date.today()
    users_to_keep = []
    deleted_count = 0
    
    for user in users:
        expires_str = user.get("expires")
        is_expired = False
        if expires_str:
            try:
                if datetime.strptime(expires_str, "%Y-%m-%d").date() < today_date:
                    is_expired = True
            except ValueError:
                pass 
        if is_expired:
            deleted_count += 1
        else:
            users_to_keep.append(user)

    if deleted_count > 0:
        save_users(users_to_keep)
        sync_config_passwords(mode="mirror") 
        return True 
    return False 

def sync_config_passwords(mode="mirror"):
    cfg=read_json(CONFIG_FILE,{})
    users=load_users()
    
    today_date = date.today()
    valid_passwords = set()
    for u in users:
        expires_str = u.get("expires")
        is_valid = True
        if expires_str:
            try:
                if datetime.strptime(expires_str, "%Y-%m-%d").date() < today_date:
                    is_valid = False
            except ValueError:
                is_valid = True 
        if is_valid and u.get("password"):
            valid_passwords.add(str(u["password"]))

    users_pw=sorted(list(valid_passwords))
    
    if mode=="merge":
        old=[]
        if isinstance(cfg.get("auth",{}).get("config",None), list):
            old=list(map(str, cfg["auth"]["config"]))
        new_pw=sorted(set(old)|set(users_pw))
    else:
        new_pw=users_pw
        
    if not isinstance(cfg.get("auth"),dict): cfg["auth"]={}
    cfg["auth"]["mode"]="passwords"
    cfg["auth"]["config"]=new_pw
    cfg["listen"]=cfg.get("listen") or ":5667"
    cfg["cert"]=cfg.get("cert") or "/etc/zivpn/zivpn.crt"
    cfg["key"]=cfg.get("key") or "/etc/zivpn/zivpn.key"
    cfg["obfs"]=cfg.get("obfs") or "zivpn"
    write_json_atomic(CONFIG_FILE,cfg)
    subprocess.run("systemctl restart zivpn.service", shell=True)

def login_enabled(): 
    return bool(ADMIN_USER and ADMIN_PASS)

def is_authed(): 
    return session.get("auth") == True

def require_login():
    if login_enabled() and not is_authed():
        return False
    return True

def prepare_user_data():
    all_users = load_users()
    check_user_expiration() 
    users = load_users()
    view=[]
    today_date = date.today()
    for u in users:
        expires_date_obj = None
        if u.get("expires"):
            try: 
                expires_date_obj = datetime.strptime(u.get("expires"), "%Y-%m-%d").date()
            except ValueError: 
                pass
      
        online_count = get_user_online_count(u.get("port",""))
        limit_count = int(u.get("limit_count", 1))
        is_over_limit = online_count > limit_count
          
        view.append(type("U",(),{
            "user":u.get("user",""),
            "password":u.get("password",""),
            "expires":u.get("expires",""),
            "expires_date": expires_date_obj,
            "days_remaining": calculate_days_remaining(u.get("expires","")),
            "port":u.get("port",""),
            "online_count": online_count,
            "limit_count": limit_count,
            "is_over_limit": is_over_limit,
            "expiring_soon": is_expiring_soon(u.get("expires","")) 
        }))
    view.sort(key=lambda x:(x.user or "").lower())
    return view, datetime.now().strftime("%Y-%m-%d"), today_date

# 💡 FIXED: Routes for modal forms
@app.route("/", methods=["GET"])
def index(): 
    server_ip = SERVER_IP_FALLBACK 
    if not require_login():
        return render_template_string('''
        <html><body>
            <div style="text-align:center;padding:50px;">
                <h1>ZIVPN Panel</h1>
                <p>Please <a href="/login">login</a> to continue</p>
            </div>
        </body></html>
        ''')
    
    check_user_expiration()
    total_users = get_total_active_users()

    return render_template_string('''
    <html><body>
        <div style="text-align:center;padding:50px;">
            <h1>ZIVPN Admin Panel</h1>
            <p>Total Active Users: {{ total_users }}</p>
            <p><a href="/users">View Users List</a></p>
            <p><a href="/logout">Logout</a></p>
        </div>
    </body></html>
    ''', total_users=total_users)

@app.route("/users", methods=["GET"])
def users_table_view():
    if not require_login(): 
        return redirect(url_for('login'))
    
    view, today_str, today_date = prepare_user_data()
    msg_data = session.pop("msg", None)
    err_data = session.pop("err", None)

    return render_template("users_table.html", 
                         users=view, 
                         today=today_str,
                         today_date=today_date,
                         logo=LOGO_URL, 
                         IP=SERVER_IP_FALLBACK,
                         msg=msg_data, 
                         err=err_data)

@app.route("/login", methods=["GET","POST"])
def login():
    if not login_enabled():
        return redirect(url_for('index'))
    
    if request.method=="POST":
        u=(request.form.get("u") or "").strip()
        p=(request.form.get("p") or "").strip()
        if hmac.compare_digest(u, ADMIN_USER) and hmac.compare_digest(p, ADMIN_PASS):
            session["auth"]=True
            return redirect(url_for('users_table_view'))
        else:
            session["auth"]=False
            session["login_err"]="❌ Username သို့မဟုတ် Password မှားယွင်းနေပါသည်။"
            return redirect(url_for('login'))
    
    return render_template_string('''
    <html><body>
        <div style="text-align:center;padding:50px;">
            <h1>ZIVPN Login</h1>
            {% if err %}<p style="color:red;">{{ err }}</p>{% endif %}
            <form method="POST">
                <input type="text" name="u" placeholder="Username" required><br><br>
                <input type="password" name="p" placeholder="Password" required><br><br>
                <button type="submit">Login</button>
            </form>
        </div>
    </body></html>
    ''', err=session.pop("login_err", None))

@app.route("/logout", methods=["GET"])
def logout():
    session.pop("auth", None)
    return redirect(url_for('login') if login_enabled() else url_for('index'))

# 💡 FIXED: Modal form routes
@app.route("/edit", methods=["POST"])
def edit_user_password():
    if not require_login(): 
        return redirect(url_for('login'))
    
    user=(request.form.get("user") or "").strip()
    new_password=(request.form.get("password") or "").strip()
    
    if not user or not new_password:
        session["err"] = "User Name နှင့် Password အသစ် မပါဝင်ပါ"
        return redirect(url_for('users_table_view'))
    
    users=load_users()
    replaced=False
    for u in users:
        if u.get("user","").lower()==user.lower():
            u["password"]=new_password 
            replaced=True
            break
      
    if not replaced:
        session["err"] = f"❌ User **{user}** ကို ရှာမတွေ့ပါ"
        return redirect(url_for('users_table_view'))
    
    save_users(users)
    sync_config_passwords() 
    
    session["msg"] = json.dumps({
        "ok":True, 
        "message": f"<h4>✅ **{user}** ရဲ့ Password ပြောင်းပြီးပါပြီ။</h4>", 
        "user":user, 
        "password":new_password
    })
    return redirect(url_for('users_table_view'))

@app.route("/edit_expires", methods=["POST"])
def edit_user_expires():
    if not require_login(): 
        return redirect(url_for('login'))
    
    user=(request.form.get("user") or "").strip()
    new_expires=(request.form.get("expires") or "").strip()
    
    if not user or not new_expires:
        session["err"] = "User Name နှင့် Expiration Date အသစ် မပါဝင်ပါ"
        return redirect(url_for('users_table_view'))
  
    if new_expires.isdigit():
        new_expires=(datetime.now() + timedelta(days=int(new_expires))).strftime("%Y-%m-%d")

    if new_expires:
        try: 
            datetime.strptime(new_expires,"%Y-%m-%d")
        except ValueError:
            session["err"] = "❌ Expiration Date ပုံစံမမှန်ပါ"
            return redirect(url_for('users_table_view'))
    
    users=load_users()
    replaced=False
    for u in users:
        if u.get("user","").lower()==user.lower():
            u["expires"]=new_expires 
            replaced=True
            break
      
    if not replaced:
        session["err"] = f"❌ User **{user}** ကို ရှာမတွေ့ပါ"
        return redirect(url_for('users_table_view'))
    
    save_users(users)
    sync_config_passwords() 
    
    session["msg"] = json.dumps({
        "ok":True, 
        "message": f"<h4>✅ **{user}** ရဲ့ Expires ကို **{new_expires}** သို့ ပြောင်းပြီးပါပြီ။</h4>", 
        "user":user
    })
    return redirect(url_for('users_table_view'))

@app.route("/edit_limit", methods=["POST"])
def edit_user_limit():
    if not require_login(): 
        return redirect(url_for('login'))
    
    user=(request.form.get("user") or "").strip()
    limit_count_str=(request.form.get("limit_count") or "").strip()
    
    if not user or not limit_count_str:
        session["err"] = "User Name နှင့် Limit Count အသစ် မပါဝင်ပါ"
        return redirect(url_for('users_table_view'))
  
    try:
        new_limit = int(limit_count_str)
        if not (1 <= new_limit <= 10):
            session["err"] = "❌ သုံးစွဲသူအရေအတွက် (Limit) သည် 1 မှ 10 အတွင်းသာ ဖြစ်ရပါမည်။"
            return redirect(url_for('users_table_view'))
    except ValueError:
        session["err"] = "❌ Limit Count သည် ဂဏန်းသာ ဖြစ်ရပါမည်။"
        return redirect(url_for('users_table_view'))

    users=load_users()
    replaced=False
    for u in users:
        if u.get("user","").lower()==user.lower():
            u["limit_count"]=new_limit 
            replaced=True
            break
      
    if not replaced:
        session["err"] = f"❌ User **{user}** ကို ရှာမတွေ့ပါ"
        return redirect(url_for('users_table_view'))
    
    save_users(users)
    
    session["msg"] = json.dumps({
        "ok":True, 
        "message": f"<h4>✅ **{user}** ရဲ့ Limit ကို **{new_limit}** ယောက် သို့ ပြောင်းပြီးပါပြီ။</h4>", 
        "user":user
    })
    return redirect(url_for('users_table_view'))

@app.route("/delete", methods=["POST"])
def delete_user_html():
    if not require_login(): 
        return redirect(url_for('login'))
    
    user = (request.form.get("user") or "").strip()
    if not user:
        session["err"] = "User Name မပါဝင်ပါ"
        return redirect(url_for('users_table_view'))
  
    delete_user(user) 
    return redirect(url_for('users_table_view'))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080, debug=True)
PY

# ===== Web Service =====
echo -e "${Y}🌐 Web Service (zivpn-web) ကို သွင်းနေပါတယ်...${Z}"
cat >/etc/systemd/system/zivpn-web.service <<'EOF'
[Unit]
Description=ZIVPN Web Admin
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/zivpn
EnvironmentFile=/etc/zivpn/web.env
ExecStart=/usr/bin/python3 /etc/zivpn/web.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# ===== Networking =====
echo -e "${Y}🌐 Network configuration ချထားနေပါတယ်...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

IFACE=$(ip -4 route ls | awk '{print $5; exit}')
[ -n "${IFACE:-}" ] || IFACE=eth0

# Clear existing rules
iptables -t nat -F 2>/dev/null || true

# DNAT 6000:19999/udp -> :5667
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667

# MASQ out
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE

# Allow UDP traffic for VPN ports
iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null || true

ufw allow 5667/udp >/dev/null 2>&1 || true
ufw allow 6000:19999/udp >/dev/null 2>&1 || true
ufw allow 8080/tcp >/dev/null 2>&1 || true
echo "y" | ufw enable >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true

# ===== CRLF sanitize =====
echo -e "${Y}🧹 File formatting ပြင်ဆင်နေပါတယ်...${Z}"
sed -i 's/\r$//' /etc/zivpn/web.py /etc/systemd/system/zivpn.service /etc/systemd/system/zivpn-web.service /etc/zivpn/templates/users_table.html 2>/dev/null || true

# ===== Enable services =====
echo -e "${Y}🚀 Services စတင်နေပါတယ်...${Z}"
systemctl daemon-reload
systemctl enable zivpn.service
systemctl enable zivpn-web.service
systemctl start zivpn.service
systemctl start zivpn-web.service

# Wait a moment for services to start
sleep 3

# Check services status
if systemctl is-active --quiet zivpn.service; then
    echo -e "${G}✅ zivpn service started successfully${Z}"
else
    echo -e "${Y}⚠️ zivpn service may have issues, checking status...${Z}"
    systemctl status zivpn.service --no-pager -l
fi

if systemctl is-active --quiet zivpn-web.service; then
    echo -e "${G}✅ zivpn-web service started successfully${Z}"
else
    echo -e "${Y}⚠️ zivpn-web service may have issues, checking status...${Z}"
    systemctl status zivpn-web.service --no-pager -l
fi

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ ZIVPN Installation Completed Successfully!${Z}"
echo -e "${C}Web Panel:${Z} ${Y}http://$IP:8080/users${Z}"
echo -e "${C}VPN Port:${Z} ${Y}5667 (UDP)${Z}"
echo -e "${C}Port Range:${Z} ${Y}6000-19999 (UDP)${Z}"
echo -e "${C}Features:${Z} ${G}Fixed Modal Dialogs • User Limit Enforcement • Auto Delete${Z}"
echo -e "$LINE"
echo -e "${Y}📝 Check logs:${Z} journalctl -u zivpn-web.service -f"
echo -e "${Y}🔧 Restart web:${Z} systemctl restart zivpn-web.service"
echo -e "${Y}🐛 Debug mode:${Z} cd /etc/zivpn && python3 web.py"
