#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - Login IP Position & Nav Icon FIX + Expiry Logic Update + Status FIX + PASSWORD EDIT FEATURE + USER LIMIT ENFORCEMENT
# ================================== MODIFIED: USER COUNT + EXPIRES EDIT MODAL + LIMIT ENFORCEMENT ==================================
# 💡 NEW MODIFICATION: Added User Limit Count Feature + ENFORCEMENT FIX (Real blocking)
set -euo pipefail

# ===== Pretty (CLEANED UP) =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ 
    echo -e "\n$LINE"
    echo -e "${G}ZIVPN UDP Server + Web UI (သက်တမ်းကုန်ဆုံးချိန် Logic နှင့် Status ပြင်ဆင်ပြီး) - (User Limit ထည့်သွင်းပြီး + ကန့်သတ်ချက် အမှန်တကယ် အလုပ်လုပ်စေရန် ပြင်ဆင်ပြီး)${Z}"
    echo -e "$LINE"
    echo -e "${C}သက်တမ်းကုန်ဆုံးသည့်နေ့ ည ၁၁:၅၉:၅၉ အထိ သုံးခွင့်ပေးပြီးမှ ဖျက်ပါမည်။${Z}\n"
}
say 

# ===== Root check (unchanged) =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== apt guards (unchanged for brevity) =====
wait_for_apt() {
  echo -e "${Y}⏳ apt သင့်လျော်မှုကို စောင့်ပါ...${Z}"
  for _ in $(seq 1 60); do
    if pgrep -x apt-get >/dev/null || pgrep -x apt >/dev/null || pgrep -f 'apt.systemd.daily' >/dev/null || pgrep -x unattended-upgrade >/dev/null; then
      sleep 5
    else
      return 0
    fi
  done
  echo -e "${Y}⚠️ apt timers ကို ယာယီရပ်နေပါတယ်${Z}"
  systemctl stop --now unattended-upgrades.service 2>/dev/null || true
  systemctl stop --now apt-daily.service apt-daily.timer 2>/dev/null || true
  systemctl stop --now apt-daily-upgrade.service apt-daily-upgrade.timer 2>/dev/null || true
}

apt_guard_start(){
  wait_for_apt
  CNF_CONF="/etc/apt/apt.conf.d/50command-not-found"
  if [ -f "$CNF_CONF" ]; then mv "$CNF_CONF" "${CNF_CONF}.disabled"; CNF_DISABLED=1; else CNF_DISABLED=0; fi
}

apt_guard_end(){
  dpkg --configure -a >/dev/null 2>&1 || true
  apt-get -f install -y >/dev/null 2>&1 || true
  if [ "${CNF_DISABLED:-0}" = "1" ] && [ -f "${CNF_CONF}.disabled" ]; then mv "${CNF_CONF}.disabled" "$CNF_CONF"; fi
}

# ===== Packages (CHANGED: added Y color) =====
echo -e "${Y}📦 Packages တင်နေပါတယ်...${Z}"
apt_guard_start
apt-get update -y -o APT::Update::Post-Invoke-Success::= -o APT::Update::Post-Invoke::= >/dev/null
apt-get install -y curl ufw jq python3 python3-flask python3-apt iproute2 conntrack ca-certificates >/dev/null || {
  apt-get install -y -o DPkg::Lock::Timeout=60 python3-apt >/dev/null || true
  apt-get install -y curl ufw jq python3 python3-flask iproute2 conntrack ca-certificates >/dev/null
}
apt_guard_end

# stop old services
systemctl stop zivpn.service 2>/dev/null || true
systemctl stop zivpn-web.service 2>/dev/null || true

# ===== Paths and setup directories (unchanged) =====
BIN="/usr/local/bin/zivpn"
CFG="/etc/zivpn/config.json"
USERS="/etc/zivpn/users.json"
ENVF="/etc/zivpn/web.env"
TEMPLATES_DIR="/etc/zivpn/templates" 
mkdir -p /etc/zivpn "$TEMPLATES_DIR" 

# --- ZIVPN Binary, Config, Certs (CHANGED: added Y color) ---
echo -e "${Y}⬇️ ZIVPN binary ကို ဒေါင်းနေပါတယ်...${Z}"
PRIMARY_URL="https://github.com/zahidbd2/udp-zivpn/releases/download/udp-zivpn_1.4.9/udp-zivpn-linux-amd64"
FALLBACK_URL="https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
TMP_BIN="$(mktemp)"
if ! curl -fsSL -o "$TMP_BIN" "$PRIMARY_URL"; then
  echo -e "${Y}Primary URL မရ — latest ကို စမ်းပါတယ်...${Z}"
  curl -fSL -o "$TMP_BIN" "$FALLBACK_URL"
fi
install -m 0755 "$TMP_BIN" "$BIN"
rm -f "$TMP_BIN"

if [ ! -f "$CFG" ]; then
  echo -e "${Y}🧩 config.json ဖန်တီးနေပါတယ်...${Z}"
  curl -fsSL -o "$CFG" "https://raw.githubusercontent.com/zahidbd2/udp-zivpn/main/config.json" || echo '{}' > "$CFG"
fi

if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
  echo -e "${Y}🔐 SSL စိတျဖိုင်တွေ ဖန်တီးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=M-69P/OU=Net/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# --- Web Admin Login, VPN Passwords, config.json Update, systemd: ZIVPN (unchanged logic) ---
echo -e "${G}🔒 Web Admin Login UI ထည့်မလား..?${Z}"
read -r -p "Web Admin Username (Enter=disable): " WEB_USER
if [ -n "${WEB_USER:-}" ]; then
  read -r -p "Web Admin Password: " WEB_PASS; echo
  
  echo -e "${G}🔗 Login အောက်နားတွင် ပြသရန် ဆက်သွယ်ရန် Link (Optional)${Z}"
  read -r -p "Contact Link (ဥပမာ: https://m.me/taknds69 or Enter=disable): " CONTACT_LINK
  
  if command -v openssl >/dev/null 2>&1; then
    WEB_SECRET="$(openssl rand -hex 32)"
  else
    WEB_SECRET="$(python3 - <<'PY_SECRET'
import secrets;print(secrets.token_hex(32))
PY_SECRET
)"
  fi
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
  echo -e "${Y}ℹ️ Web login UI မဖွင့်ထားပါ (dev mode)${Z}" # ADDED Y
fi

echo -e "${G}🔏 VPN Password List (ကော်မာဖြင့်ခွဲ) eg: M-69P,tak,dtac69${Z}"
read -r -p "Passwords (Enter=zi): " input_pw
if [ -z "${input_pw:-}" ]; then PW_LIST='["zi"]'; else
  PW_LIST=$(echo "$input_pw" | awk -F',' '{
    printf("["); for(i=1;i<=NF;i++){gsub(/^ *| *$/,"",$i); printf("%s\"%s\"", (i>1?",":""), $i)}; printf("]")
  }')
fi

if jq . >/dev/null 2>&1 <<<'{}'; then
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

echo -e "${Y}🧰 systemd service (zivpn) ကို သွင်းနေပါတယ်...${Z}" # ADDED Y
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

# ===== USER LIMIT ENFORCEMENT SCRIPT (CHANGED: added Y color) =====
echo -e "${Y}🛡️ User Limit Enforcement Script ထည့်သွင်းနေပါတယ်...${Z}"
LIMIT_ENFORCER_SCRIPT="/etc/zivpn/limit_enforcer.sh"

cat > "$LIMIT_ENFORCER_SCRIPT" << 'ENFORCER_EOF'
#!/bin/bash
# ZIVPN User Limit Enforcer - Blocks ports when connection count exceeds limit
set -euo pipefail

USERS_FILE="/etc/zivpn/users.json"
LOG_FILE="/var/log/zivpn_limit_enforcer.log"

# Function to get online count for a port
get_online_count() {
    local port="$1"
    conntrack -L -p udp 2>/dev/null | grep "dport=$port" | awk '{print $5}' | cut -d= -f2 | sort -u | wc -l
}

# Function to block port using iptables
block_port() {
    local port="$1"
    local user="$2"
    iptables -I INPUT -p udp --dport "$port" -j DROP -m comment --comment "ZIVPN_BLOCKED_$user"
}

# Function to unblock port
unblock_port() {
    local port="$1"
    iptables -D INPUT -p udp --dport "$port" -j DROP 2>/dev/null || true
}

# Main enforcement logic
echo "$(date): Starting limit enforcement" >> "$LOG_FILE"

# Load users and check limits
if [ -f "$USERS_FILE" ]; then
    users_data=$(cat "$USERS_FILE")
    
    echo "$users_data" | jq -c '.[]' | while read -r user_data; do
        username=$(echo "$user_data" | jq -r '.user')
        port=$(echo "$user_data" | jq -r '.port')
        limit=$(echo "$user_data" | jq -r '.limit_count // 1')
        
        if [ -n "$port" ] && [ "$port" != "null" ]; then
            online_count=$(get_online_count "$port")
            
            echo "$(date): User $username - Port: $port, Online: $online_count, Limit: $limit" >> "$LOG_FILE"
            
            if [ "$online_count" -gt "$limit" ]; then
                echo "$(date): BLOCKING $username - Over limit! ($online_count > $limit)" >> "$LOG_FILE"
                block_port "$port" "$username"
            else
                echo "$(date): Unblocking $username - Within limit" >> "$LOG_FILE"
                unblock_port "$port"
            fi
        fi
    done
fi

echo "$(date): Limit enforcement completed" >> "$LOG_FILE"
ENFORCER_EOF

chmod +x "$LIMIT_ENFORCER_SCRIPT"

# ===== CRON JOB FOR LIMIT ENFORCEMENT (CHANGED: added Y color) =====
echo -e "${Y}⏱️ Limit Enforcement Cron Job ထည့်သွင်းနေပါတယ်...${Z}"
# Remove old cron entry if exists
crontab -l 2>/dev/null | grep -v "$LIMIT_ENFORCER_SCRIPT" | crontab - 2>/dev/null || true
# Add new cron entry
(crontab -l 2>/dev/null; echo "* * * * * $LIMIT_ENFORCER_SCRIPT >/dev/null 2>&1") | crontab -

# ===== CLEAR EXISTING BLOCKING RULES (CHANGED: added Y color) =====
echo -e "${Y}🧹 လက်ရှိ iptables blocking rules များ ရှင်းလင်းနေပါတယ်...${Z}"
iptables-save | grep -v "ZIVPN_BLOCKED" | iptables-restore 2>/dev/null || true

# ===== TEMPLATES (users_table.html) (CHANGED: added Y color) =====
echo -e "${Y}📄 Table HTML (users_table.html) ကို စစ်ဆေးနေပါတယ်...${Z}"
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
                    <span class="pill pill-over-limit"><i class="icon">❌</i> Over Limit (BLOCKED)</span>
                {% else %}
                    <span class="pill ok"><i class="icon">🟢</i> Active</span>
                {% endif %}
            </td>

            <td data-label="Action">
              <button type="button" class="btn-edit" onclick="showEditModal('{{ u.user }}', '{{ u.password }}', '{{ u.expires }}')"><i class="icon">✏️</i> Pass</button>
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

{# MODALS - Same as before but shortened for brevity #}
<div id="editModal" class="modal">
  <div class="modal-content">
    <span class="close-btn" onclick="document.getElementById('editModal').style.display='none'">&times;</span>
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

<div id="expiresModal" class="modal">
  <div class="modal-content">
    <span class="close-btn" onclick="document.getElementById('expiresModal').style.display='none'">&times;</span>
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

<div id="limitModal" class="modal">
  <div class="modal-content">
    <span class="close-btn" onclick="document.getElementById('limitModal').style.display='none'">&times;</span>
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
/* Styles remain the same as previous version */
.modal-content {
  background-color: var(--card-bg);
  margin: 15% auto;
  padding: 25px; 
  border: none;
  width: 90%; 
  max-width: 320px;
  border-radius: 12px;
  position: relative;
  box-shadow: 0 10px 25px rgba(0,0,0,0.2);
}
.close-btn { 
  color: var(--secondary); 
  position: absolute;
  top: 8px;
  right: 15px;
  font-size: 32px; 
  font-weight: 300; 
  line-height: 1;
}
.close-btn:hover { color: var(--danger); }
.section-title { margin-top: 0; padding-bottom: 10px; border-bottom: 1px solid var(--border-color); color: var(--primary-dark);}

.modal .input-group { margin-bottom: 20px; }
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
    transition: background-color 0.3s, transform 0.1s; 
    margin-top: 10px; 
    font-weight: bold;
    box-shadow: 0 4px 6px rgba(255, 127, 39, 0.3);
}
.modal-save-btn:hover { background-color: var(--primary-dark); } 
.modal-save-btn:active { background-color: var(--primary-dark); transform: translateY(1px); box-shadow: 0 2px 4px rgba(255, 127, 39, 0.3); }

.btn-edit { background-color: var(--warning); color: var(--dark); border: none; padding: 6px 10px; border-radius: 8px; cursor: pointer; font-size: 0.9em; transition: background-color 0.2s; margin-right: 5px; }
.btn-edit:hover { background-color: #e0ac08; }
.delform { display: inline-block; margin: 0; }
.btn-delete { background-color: var(--danger); color: white; border: none; padding: 6px 10px; border-radius: 8px; cursor: pointer; font-size: 0.9em; transition: background-color 0.2s; }
.btn-delete:hover { background-color: #c82333; }

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
.btn-edit-expires:hover { background-color: var(--primary-dark); }

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
.btn-edit-limit:hover { background-color: #5a6268; }

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
    td { padding-left: 50%; }
    td:before { width: 45%; }
    td[data-label="Action"] { display: flex; justify-content: flex-end; align-items: center; }
    .btn-edit { width: auto; padding: 6px 8px; font-size: 0.8em; margin-right: 5px; }
    .btn-delete { width: auto; padding: 6px 8px; font-size: 0.8em; margin-top: 0; }
    .modal-content { 
        margin: 20% auto; 
        max-width: 280px;
    }
    .days-remaining { display: block; text-align: right; }
    .btn-edit-expires { display: inline-block; margin-left: 5px; width: auto; box-sizing: border-box; }
    .btn-edit-limit { display: inline-block; margin-left: 5px; width: auto; box-sizing: border-box; }
}

tr.over-limit { 
    border-left: 5px solid var(--danger); 
    background-color: rgba(220, 53, 69, 0.1);
}
</style>

<script>
    function showEditModal(user, password, expires) {
        document.getElementById('edit-user').value = user;
        document.getElementById('current-user-display').value = user;
        document.getElementById('current-password').value = password;
        document.getElementById('new-password').value = '';
        document.getElementById('editModal').style.display = 'block';
    }

    function showExpiresModal(user, expires) {
        document.getElementById('expires-edit-user').value = user;
        document.getElementById('expires-current-user-display').value = user; 
        document.getElementById('new-expires').value = expires;
        document.getElementById('expiresModal').style.display = 'block';
    }
    
    function showLimitModal(user, limit) {
        document.getElementById('limit-edit-user').value = user;
        document.getElementById('limit-current-user-display').value = user; 
        document.getElementById('new-limit').value = limit && limit !== 'None' ? limit : 1;
        document.getElementById('limitModal').style.display = 'block';
    }

    window.onclick = function(event) {
        if (event.target == document.getElementById('editModal')) {
            document.getElementById('editModal').style.display = 'none';
        }
        if (event.target == document.getElementById('expiresModal')) {
            document.getElementById('expiresModal').style.display = 'none';
        }
        if (event.target == document.getElementById('limitModal')) {
            document.getElementById('limitModal').style.display = 'none';
        }
    }
</script>
TABLE_HTML

# ===== WEB PANEL (web.py) =====
echo -e "${Y}🖥️ Web Panel (web.py) ကို စစ်ဆေးနေပါတယ်...${Z}" # ADDED Y
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

# HTML Template (shortened for brevity - same as previous)
HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<title>ZIVPN User Panel</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<style>
:root { --primary: #ff7f27; --primary-dark: #cc661f; --secondary: #6c757d; --success: #28a745; --danger: #dc3545; --light: #f8f9fa; --dark: #343a40; --bg-color: #f0f2f5; --card-bg: #ffffff; --border-color: #dee2e6; --warning: #ffc107; }
body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: var(--bg-color); line-height: 1.6; color: var(--dark); margin: 0; padding: 0; padding-bottom: 70px; }
.icon { font-style: normal; margin-right: 5px; }
.main-header { display: flex; justify-content: space-between; align-items: center; background-color: var(--card-bg); padding: 10px 15px; box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1); margin-bottom: 15px; position: sticky; top: 0; z-index: 1000; }
.header-logo a { font-size: 1.6em; font-weight: bold; color: var(--primary); text-decoration: none;} 
.header-logo .highlight { color: var(--dark); }
.bottom-nav { display: flex; justify-content: space-around; align-items: center; position: fixed; bottom: 0; left: 0; width: 100%; background-color: var(--card-bg); box-shadow: 0 -2px 10px rgba(0, 0, 0, 0.1); z-index: 1000; padding: 5px 0; }
.bottom-nav a { display: flex; flex-direction: column; align-items: center; text-decoration: none; color: var(--secondary); font-size: 0.75em; padding: 8px; border-radius: 6px; transition: color 0.2s, background-color 0.2s; min-width: 80px; }
.bottom-nav a:hover, .bottom-nav a.active { color: var(--primary); }
.bottom-nav a i.icon { font-size: 1.2em; margin-right: 0; margin-bottom: 3px; color: #ffd966; }
.bottom-nav a:hover i.icon, .bottom-nav a.active i.icon { color: var(--primary); }
@media (min-width: 769px) { .bottom-nav { display: none; } body { padding-bottom: 0; } }
.login-container, .boxa1 { background-color: var(--card-bg); padding: 30px 20px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0, 0, 0, 0.15); width: 90%; max-width: 400px; margin: 30px auto; text-align: center; }
.boxa1 { max-width: 600px; margin-top: 15px; text-align: left; }
.info-card { background-color: #fcece3; color: var(--primary-dark); padding: 15px 20px; border-radius: 8px; text-align: center; font-weight: bold; font-size: 1.0em; margin-bottom: 15px; border: 1px solid var(--primary); box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1); }
.info-card span { font-size: 1.1em; margin-right: 5px; }
.profile-image-container { display: inline-block; margin-bottom: 15px; border-radius: 50%; overflow: hidden; border: 4px solid var(--primary); }
.profile-image { width: 70px; height: 70px; object-fit: cover; display: block; }
h1 { font-size: 22px; color: var(--dark); margin-bottom: 5px; }
.panel-title { font-size: 14px; color: var(--secondary); margin-bottom: 25px; }
.login-ip-display { font-size: 16px; color: var(--primary-dark); font-weight: bold; margin-top: -15px; margin-bottom: 25px; }
.input-group { margin-bottom: 15px; text-align: left; }
.input-field-wrapper { display: flex; align-items: center; border: 1px solid var(--border-color); border-radius: 8px; margin-Top: 5px; background-color: #fff; transition: border-color 0.3s, box-shadow 0.3s; }
.input-field-wrapper:focus-within { border-color: var(--primary); box-shadow: 0 0 0 3px rgba(255, 127, 39, 0.25); }
.input-field-wrapper .icon { padding: 0 10px; color: var(--secondary); background: transparent; }
input[type="text"], input[type="password"], input[name="expires"], input[name="port"], input[name="ip"], input[type="number"] { width: 100%; padding: 12px 10px; border: none; border-radius: 0 8px 8px 0; font-size: 16px; outline: none; background: transparent; appearance: none; -webkit-appearance: none; }
input[name="ip"] { background-color: var(--light); color: var(--secondary); cursor: pointer; }
.login-button, .save-btn { width: 100%; padding: 12px; background-color: var(--primary); color: white; border: none; border-radius: 8px; font-size: 16px; cursor: pointer; transition: background-color 0.3s; margin-top: 20px; font-weight: bold; }
.login-button:hover, .save-btn:hover { background-color: var(--primary-dark); } 
.login-button:active, .save-btn:active { background-color: var(--primary-dark); transform: translateY(1px); } 
.section-title { font-size: 18px; font-weight: bold; color: var(--dark); margin-bottom: 15px; }
.row{display:flex;gap:15px;flex-wrap:wrap;margin-bottom: 5px;}
.row>div{flex:1 1 100%;}
@media (min-width: 600px) { .row>div{flex:1 1 220px;} }
.err{ color: var(--danger); background-color: #f8d7da; border: 1px solid #f5c6cb; padding: 10px; border-radius: 8px; margin-bottom: 15px; font-weight: bold; text-align: center; }
.user-info-card { position: fixed; top: 20px; left: 50%; transform: translateX(-50%); background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; border-radius: 8px; padding: 15px 20px; box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1); z-index: 2000; max-width: 300px; width: 90%; text-align: left; }
@keyframes fadein { from { opacity: 0; transform: translateY(-20px); } to { opacity: 1; transform: translateY(0); } }
@keyframes fadeout { from { opacity: 1; } to { opacity: 0; visibility: hidden; } }
#copy-notification { position: fixed; top: 10px; right: 50%; transform: translateX(50%); background-color: var(--success); color: white; padding: 8px 15px; border-radius: 5px; z-index: 2000; font-size: 0.9em; opacity: 0; transition: opacity 0.5s; }
text { font-size: 15px; margin-Top: 0px; }
.contact-link { margin-top: 15px; font-size: 0.9em; font-weight: 500; }
.contact-link a { color: var(--primary-dark); text-decoration: none; font-weight: bold; transition: color 0.2s; }
.contact-link a:hover { color: var(--primary); text-decoration: underline; }
</style>
<script>
    function copyToClipboard(elementId) {
        const copyText = document.getElementById(elementId);
        if (!copyText) return;
        const notification = document.getElementById('copy-notification');
        const showNotification = () => {
            notification.innerText = 'Server IP ကို ကူးပြီးပါပြီ';
            notification.style.opacity = 1;
            setTimeout(() => { notification.style.opacity = 0; }, 2000);
        };
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(copyText.value).then(showNotification).catch(err => { fallbackCopy(copyText, showNotification); });
        } else { fallbackCopy(copyText, showNotification); }
    }
    function fallbackCopy(copyText, onSuccess) {
        let isCopied = false;
        try {
            copyText.select();
            copyText.setSelectionRange(0, 99999); 
            isCopied = document.execCommand('copy');
            if (isCopied) { onSuccess(); }
        } catch (err) { console.error('Fallback copy failed: ', err); }
    }
</script>
</head><body>
{% if not authed %}
    <div class="login-container">
        <div class="profile-image-container"><img src="{{logo}}" alt="Profile" class="profile-image"></div>
        <h1>ZIVPN Panel</h1><br>
        {% if IP %}<p class="login-ip-display">Server IP: {{ IP }}</p>{% endif %}
        <p class="panel-title">Login to Admin Dashboard</p>
        {% if err %}<div class="err">{{err}}</div>{% endif %} 
        <form action="/login" method="POST" class="login-form">
            <div class="input-group">
                <label for="username" style="display:none;">Username</label>
                <div class="input-field-wrapper"><i class="icon">🔑</i><input type="text" id="username" name="u" placeholder="Username" required></div>
            </div>
            <div class="input-group">
                <label for="password" style="display:none;">Password</label>
                <div class="input-field-wrapper"><i class="icon">🔒</i><input type="text" id="password" name="p" placeholder="Password" required></div>
            </div>
            <button type="submit" class="login-button">Login</button>
        </form>
        {% if contact_link %}<p class="contact-link"><i class="icon">🗨️</i><a href="{{ contact_link }}" target="_blank">Admin ကို ဆက်သွယ်ပါ</a></p>{% endif %}
    </div>
{% else %}
   <header class="main-header"><div class="header-logo"><a href="/">ZIVPN<span class="highlight"> Panel</span></a></div></header>
   <div id="copy-notification"></div> 
   <div class="boxa1">
        <div class="info-card"><i class="icon">💡</i> လက်ရှိ Member User စုစုပေါင်း<br><span>{{ total_users }}</span>ယောက်</div>
    <script>
        {% if msg and '{' in msg and '}' in msg %}
        try {
            const data = JSON.parse('{{ msg | safe }}');
            if (data.user) { 
                const card = document.createElement('div');
                card.className = 'user-info-card';
                if (data.message) {
                    card.innerHTML = data.message;
                } else {
                    card.innerHTML = `
                        <h4>✅ အကောင့်အသစ် ဖန်တီးပြီးပါပြီ</h4>
                        <p><i class="icon">🔥</i> Server IP: <b>${data.ip || '{{ IP }}'}</b></p>  
                        <p><i class="icon">👤</i> Username: <b>${data.user}</b></p>
                        <p><i class="icon">🔑</i> Password: <b>${data.password}</b></p>
                        <p><i class="icon">⏰</i> Expires: <b>${data.expires || 'N/A'}</b></p>
                        <p><i class="icon">👥</i> Limit: <b>${data.limit_count || '1'}</b></p>
                    `;
                }
                document.body.appendChild(card);
                setTimeout(() => { if (card.parentNode) { card.parentNode.removeChild(card); } }, 20000); 
            }
        } catch (e) { console.error("Error parsing message JSON:", e); }
        {% endif %}
    </script>
    <form method="post" action="/add" class="">
        <h2 class="section-title"><i class="icon">➕</i> Add new user</h2>
        {% if err %}<div class="err">{{err}}</div>{% endif %}
        <div class="input-group">
            <label for="username" style="display:none;">Username</label>
            <div class="input-field-wrapper"><i class="icon">👤</i><input type="text" id="username" name="user" placeholder="Username" required></div>
        </div>
        <div class="input-group">
            <label for="password" style="display:none;">Password</label>
            <div class="input-field-wrapper"><i class="icon">🔑</i><input type="password" id="password" name="password" placeholder="Password" required></div>
        </div>
        <div class="row">
            <div><text> <label><i class="icon"></i>Add (expiration date)</label></text><tak1>  <div class="input-field-wrapper"><i class="icon">🗓️</i><input name="expires" required placeholder="Example : 2025-12-31 or 30"></div></tak1></div>
            <div><text> <label><i class="icon"></i>User Limit Count</label></text><div class="input-field-wrapper"><i class="icon">👥</i><input type="number" name="limit_count" placeholder="အများဆုံး သုံးစွဲသူအရေအတွက် (1-10)" min="1" max="10" value="1" required></div></div>
        </div>
        <div class="input-group">
            <label><i class="icon"></i>Server IP (Click to Copy)</label> 
            <div class="input-field-wrapper"><i class="icon">📡</i><input name="ip" id="server-ip-input" placeholder="ip" value="{{ IP }}" readonly onclick="copyToClipboard('server-ip-input')"></div>
        </div>
        <button class="save-btn" type="submit">Create Account</button>
    </form>
    </div> 
    <nav class="bottom-nav">
        <a href="/"><i class="icon">➕</i><span>အကောင့်ထည့်ရန်</span></a>
        <a href="/users"><i class="icon">📜</i><span>အသုံးပြုသူ စာရင်း</span></a>
        <a href="/logout"><i class="icon">➡️</i><span>ထွက်ရန်</span></a>
    </nav>
{% endif %}
</body></html>"""

app = Flask(__name__, template_folder="/etc/zivpn/templates")
app.secret_key = os.environ.get("WEB_SECRET","dev-secret-change-me")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER","M-69P").strip()
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD","M-69P").strip()

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
    out.append({"user":u.get("user",""),
                "password":u.get("password",""),
                "expires":u.get("expires",""),
                "port":str(u.get("port","")) if u.get("port","")!="" else "",
                "limit_count": int(u.get("limit_count", 1))
                })
  return out
def save_users(users): write_json_atomic(USERS_FILE, users)
def get_listen_port_from_config():
  cfg=read_json(CONFIG_FILE,{})
  listen=str(cfg.get("listen","")).strip()
  m=re.search(r":(\d+)$", listen) if listen else None
  return (m.group(1) if m else LISTEN_FALLBACK)
def get_udp_listen_ports():
  out=subprocess.run("ss -uHln", shell=True, capture_output=True, text=True).stdout
  return set(re.findall(r":(\d+)\s", out))
def pick_free_port():
  used={str(u.get("port","")) for u in load_users() if str(u.get("port",""))}
  used |= get_udp_listen_ports()
  for p in range(6000,20000):
    if str(p) not in used: return str(p)
  return ""
def has_recent_udp_activity(port):
  if not port: return False
  try:
    out=subprocess.run(f"conntrack -L -p udp 2>/dev/null | grep 'dport={port}\\b'",
                       shell=True, capture_output=True, text=True).stdout
    return bool(out)
  except Exception:
    return False

def get_user_online_count(port):
    if not port: return 0
    try:
        result = subprocess.run(f"conntrack -L -p udp 2>/dev/null | grep 'dport={port}\\b'",
                                shell=True, capture_output=True, text=True).stdout
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

def login_enabled(): return bool(ADMIN_USER and ADMIN_PASS)
def is_authed(): return session.get("auth") == True
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
          try: expires_date_obj = datetime.strptime(u.get("expires"), "%Y-%m-%d").date()
          except ValueError: pass
      
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
    today=datetime.now().strftime("%Y-%m-%d")
    return view, today, today_date

# Flask Routes 
@app.route("/", methods=["GET"])
def index(): 
    server_ip = SERVER_IP_FALLBACK 
    if not require_login():
      return render_template_string(HTML, 
                                authed=False, 
                                logo=LOGO_URL, 
                                err=session.pop("login_err", None),
                                IP=server_ip,
                                contact_link=CONTACT_LINK)
    
    check_user_expiration()
    total_users = get_total_active_users()

    return render_template_string(HTML, 
                                authed=True, 
                                logo=LOGO_URL, 
                                total_users=total_users, 
                                msg=session.pop("msg", None), 
                                err=session.pop("err", None), 
                                today=datetime.now().strftime("%Y-%m-%d"),
                                IP=server_ip)

@app.route("/users", methods=["GET"])
def users_table_view():
    if not require_login(): return redirect(url_for('login'))
    
    view, today_str, today_date = prepare_user_data()
    
    msg_data = session.pop("msg", None)
    err_data = session.pop("err", None)

    return render_template("users_table_wrapper.html", 
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
      return redirect(url_for('index'))
    else:
      session["auth"]=False
      session["login_err"]="❌ Username သို့မဟုတ် Password မှားယွင်းနေပါသည်။ ထပ်မံစစ်ဆေးပါ။" 
      return redirect(url_for('login'))
  return render_template_string(HTML, 
                                authed=False, 
                                logo=LOGO_URL, 
                                err=session.pop("login_err", None), 
                                IP=SERVER_IP_FALLBACK,
                                contact_link=CONTACT_LINK)

@app.route("/logout", methods=["GET"])
def logout():
  session.pop("auth", None)
  return redirect(url_for('login') if login_enabled() else url_for('index'))

@app.route("/add", methods=["POST"])
def add_user():
  if not require_login(): return redirect(url_for('login'))
  user=(request.form.get("user") or "").strip()
  password=(request.form.get("password") or "").strip()
  expires=(request.form.get("expires") or "").strip()
  limit_count_str=(request.form.get("limit_count") or "1").strip()
  port=(request.form.get("port") or "").strip() 
  ip = (request.form.get("ip") or "").strip() or SERVER_IP_FALLBACK
  
  try:
    limit_count = int(limit_count_str)
    if not (1 <= limit_count <= 10):
        session["err"] = "❌ သုံးစွဲသူအရေအတွက် (Limit) သည် 1 မှ 10 အတွင်းသာ ဖြစ်ရပါမည်။"
        return redirect(url_for('index'))
  except ValueError:
    session["err"] = "❌ သုံးစွဲသူအရေအတွက် (Limit) သည် ဂဏန်းသာ ဖြစ်ရပါမည်။"
    return redirect(url_for('index'))

  myanmar_chars_pattern = re.compile(r'[\u1000-\u109F]')
  if myanmar_chars_pattern.search(user) or myanmar_chars_pattern.search(password):
      session["err"] = "❌ User Name သို့မဟုတ် Password တွင် မြန်မာစာလုံးများ ပါဝင်၍ မရပါ။ (English, Numbers သာ ခွင့်ပြုသည်)"
      return redirect(url_for('index'))

  if expires.isdigit():
    expires=(datetime.now() + timedelta(days=int(expires))).strftime("%Y-%m-%d")

  if not user or not password:
    session["err"] = "User Name နှင့် Password များ မပါဝင်ပါ"
    return redirect(url_for('index')) 
  if expires:
    try: datetime.strptime(expires,"%Y-%m-%d")
    except ValueError:
      session["err"] = "Expires ရက်စွဲ မမှန်ပါ"
      return redirect(url_for('index'))
  
  if port:
    if not re.fullmatch(r"\d{2,5}",port) or not (6000 <= int(port) <= 19999):
      session["err"] = "Port နံပါတ် (6000-19999) မမှန်ပါ"
      return redirect(url_for('index'))
  
  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=password; u["expires"]=expires; u["port"]=port; u["limit_count"]=limit_count; replaced=True; break
  if not replaced:
    if not port:
        port = pick_free_port()
        if not port:
            session["err"] = "❌ အသုံးပြုရန် Port မရှိတော့ပါ"
            return redirect(url_for('index'))
    users.append({"user":user,"password":password,"expires":expires,"port":port, "limit_count":limit_count})
  
  save_users(users)
  sync_config_passwords()

  msg_dict = {
      "user": user,
      "password": password,
      "expires": expires,
      "ip": ip,
      "limit_count": limit_count
  }
  
  session["msg"] = json.dumps(msg_dict)
  return redirect(url_for('index'))

@app.route("/edit_expires", methods=["POST"])
def edit_user_expires():
  if not require_login(): return redirect(url_for('login'))
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
        session["err"] = "❌ Expiration Date ပုံစံမမှန်ပါ (YYYY-MM-DD သို့မဟုတ် ရက်အရေအတွက်) "
        return redirect(url_for('users_table_view'))
    
  users=load_users(); replaced=False
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
  
  session["msg"] = json.dumps({"ok":True, "message": f"<h4>✅ **{user}** ရဲ့ Expires ကို **{new_expires}** သို့ ပြောင်းပြီးပါပြီ။</h4>", "user":user})
  return redirect(url_for('users_table_view'))

@app.route("/edit_limit", methods=["POST"])
def edit_user_limit():
  if not require_login(): return redirect(url_for('login'))
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

  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["limit_count"]=new_limit 
      replaced=True
      break
      
  if not replaced:
    session["err"] = f"❌ User **{user}** ကို ရှာမတွေ့ပါ"
    return redirect(url_for('users_table_view'))
    
  save_users(users)
  
  session["msg"] = json.dumps({"ok":True, "message": f"<h4>✅ **{user}** ရဲ့ Limit ကို **{new_limit}** ယောက် သို့ ပြောင်းပြီးပါပြီ။</h4>", "user":user})
  return redirect(url_for('users_table_view'))

@app.route("/edit", methods=["POST"])
def edit_user_password():
  if not require_login(): return redirect(url_for('login'))
  user=(request.form.get("user") or "").strip()
  new_password=(request.form.get("password") or "").strip()
  
  if not user or not new_password:
    session["err"] = "User Name နှင့် Password အသစ် မပါဝင်ပါ"
    return redirect(url_for('users_table_view'))
    
  myanmar_chars_pattern = re.compile(r'[\u1000-\u109F]')
  if myanmar_chars_pattern.search(new_password):
      session["err"] = "❌ Password အသစ်တွင် မြန်မာစာလုံးများ ပါဝင်၍ မရပါ။ (English, Numbers သာ ခွင့်ပြုသည်)"
      return redirect(url_for('users_table_view')) 

  users=load_users(); replaced=False
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
  
  session["msg"] = json.dumps({"ok":True, "message": f"<h4>✅ **{user}** ရဲ့ Password ပြောင်းပြီးပါပြီ။</h4>", "user":user, "password":new_password})
  return redirect(url_for('users_table_view'))

@app.route("/delete", methods=["POST"])
def delete_user_html():
  if not require_login(): return redirect(url_for('login'))
  user = (request.form.get("user") or "").strip()
  if not user:
    session["err"] = "User Name မပါဝင်ပါ"
    return redirect(url_for('users_table_view'))
  
  delete_user(user) 
  return redirect(url_for('users_table_view'))

@app.route("/api/user.delete", methods=["POST"])
def delete_user_api():
  if not require_login():
    return make_response(jsonify({"ok": False, "err":"login required"}), 401)
  data = request.get_json(silent=True) or {}
  user = (data.get("user") or "").strip()
  if not user:
    return jsonify({"ok": False, "err": "user required"}), 400
  
  delete_user(user) 
  return jsonify({"ok": True})

@app.route("/api/users", methods=["GET","POST"])
def api_users():
  if not require_login():
    return make_response(jsonify({"ok": False, "err":"login required"}), 401)
  
  if request.method=="GET":
    all_users = load_users()
    check_user_expiration() 
    users = load_users() 
    for u in users: 
      u["expiring_soon"]=is_expiring_soon(u.get("expires",""))
      u["online_count"]=get_user_online_count(u.get("port",""))
      u["limit_count"]=int(u.get("limit_count",1))
      u["is_over_limit"] = u["online_count"] > u["limit_count"]
    return jsonify(users)
  
  if request.method=="POST":
    data=request.get_json(silent=True) or {}
    user=(data.get("user") or "").strip()
    password=(data.get("password") or "").strip()
    expires=(data.get("expires") or "").strip()
    port=str(data.get("port") or "").strip()
    limit_count_str=(data.get("limit_count") or "1").strip()

    try:
      limit_count = int(limit_count_str)
      if not (1 <= limit_count <= 10):
          return jsonify({"ok": False, "err": "limit_count must be between 1 and 10"}), 400
    except ValueError:
      return jsonify({"ok": False, "err": "invalid limit_count"}), 400

    myanmar_chars_pattern = re.compile(r'[\u1000-\u109F]')
    if myanmar_chars_pattern.search(user) or myanmar_chars_pattern.search(password):
        return jsonify({"ok": False, "err": "Myanmar characters not allowed in user or password"}), 400

    if expires.isdigit():
      expires=(datetime.now()+timedelta(days=int(expires))).strftime("%Y-%m-%d")
    if not user or not password: return jsonify({"ok":False,"err":"user/password required"}),400
    if port and (not re.fullmatch(r"\d{2,5}",port) or not (6000<=int(port)<=19999)):
      return jsonify({"ok":False,"err":"invalid port"}),400
      
    users=load_users(); replaced=False
    for u in users:
      if u.get("user","").lower()==user.lower():
        u["password"]=password; u["expires"]=expires; u["port"]=port; u["limit_count"]=limit_count; replaced=True; break
    if not replaced:
      if not port:
          port = pick_free_port()
          if not port:
              return jsonify({"ok": False, "err": "No free port available"}), 500
      users.append({"user":user,"password":password,"expires":expires,"port":port, "limit_count":limit_count})
    save_users(users)
    sync_config_passwords()
    return jsonify({"ok":True})

@app.route("/favicon.ico", methods=["GET"])
def favicon(): return ("",204)

@app.errorhandler(405)
def handle_405(e): return redirect(url_for('index'))

if __name__ == "__main__":
  app.run(host="0.0.0.0", port=8080)
PY

# ===== users_table_wrapper.html (CHANGED: added Y color) =====
echo -e "${Y}📄 Table Wrapper (users_table_wrapper.html) ကို စစ်ဆေးနေပါတယ်...${Z}"
cat >"$TEMPLATES_DIR/users_table_wrapper.html" <<'WRAPPER_HTML'
<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<title>ZIVPN User Panel - Users</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<style>
:root {
    --primary: #ff7f27;
    --primary-dark: #cc661f;
    --secondary: #6c757d; --success: #28a745; --danger: #dc3545;
    --light: #f8f9fa; --dark: #343a40; 
    --bg-color: #f0f2f5; 
    --card-bg: #ffffff;
    --border-color: #dee2e6;
    --warning: #ffc107;
    --warning-bg: #fff3cd;
}
body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: var(--bg-color);
    line-height: 1.6; color: var(--dark); margin: 0; padding: 0;
    padding-bottom: 70px;
}
.icon { font-style: normal; margin-right: 5px; }

.main-header {
    display: flex; justify-content: space-between; align-items: center;
    background-color: var(--card-bg); padding: 10px 15px; box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1);
    margin-bottom: 15px; position: sticky; top: 0; z-index: 1000;
}
.header-logo a { font-size: 1.6em; font-weight: bold; color: var(--primary); text-decoration: none;}
.header-logo .highlight { color: var(--dark); }

.bottom-nav {
    display: flex;
    justify-content: space-around;
    align-items: center;
    position: fixed;
    bottom: 0;
    left: 0;
    width: 100%;
    background-color: var(--card-bg);
    box-shadow: 0 -2px 10px rgba(0, 0, 0, 0.1);
    z-index: 1000;
    padding: 5px 0;
}
.bottom-nav a {
    display: flex;
    flex-direction: column;
    align-items: center;
    text-decoration: none;
    color: var(--secondary);
    font-size: 0.75em;
    padding: 8px;
    border-radius: 6px;
    transition: color 0.2s, background-color 0.2s;
    min-width: 80px;
}
.bottom-nav a:hover, .bottom-nav a.active {
    color: var(--primary); 
}
.bottom-nav a i.icon {
    font-size: 1.2em;
    margin-right: 0;
    margin-bottom: 3px;
    color: #ffd966; 
}
.bottom-nav a:hover i.icon, .bottom-nav a.active i.icon {
    color: var(--primary); 
}

.table-container { padding: 0 10px; margin: 0 auto; max-width: 100%; } 
table {
    width: 100%; border-collapse: separate; border-spacing: 0; margin-top: 15px;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.05); border-radius: 8px; overflow: hidden;
}
th, td { padding: 10px; text-align: left; border-bottom: 1px solid var(--border-color); font-size: 0.9em; }
th { background-color: var(--primary); color: white; font-weight: 600; text-transform: uppercase; font-size: 0.8em; } 
tr:last-child td { border-bottom: none; }
tr:nth-child(even) { background-color: var(--light); }
tr:hover { background-color: #e9ecef; }

@media (max-width: 768px) {
    .table-container { padding: 0 5px; }
    table, thead, tbody, th, td, tr { display: block; }
    thead { display: none; }
    tr { 
        border: 1px solid var(--border-color); 
        margin-bottom: 15px; 
        border-radius: 8px; 
        box-shadow: 0 1px 4px rgba(0, 0, 0, 0.05);
    }
    td {
        border: none;
        position: relative;
        padding-left: 50%;
        text-align: right;
        border-bottom: 1px dashed #e0e0e0;
    }
    td:last-child { border-bottom: none; }
    td:before {
        content: attr(data-label);
        position: absolute;
        left: 0;
        width: 45%;
        padding-left: 10px;
        font-weight: bold;
        text-align: left;
        color: var(--secondary);
        font-size: 0.9em;
    }
    .pill { padding: 4px 8px; font-size: 0.8em; min-width: 70px; }
    .delform { display: block; text-align: right; }
    .btn-delete { width: 80px; padding: 6px 8px; font-size: 0.8em; margin-top: 5px;}
    .days-remaining { display: block !important; }
    .btn-edit-expires { display: inline-block; margin-left: 5px; width: auto; box-sizing: border-box; }
    .btn-edit-limit { display: inline-block; margin-left: 5px; width: auto; box-sizing: border-box; }
}
.main-nav { display: none; } 
@media (min-width: 769px) {
    .bottom-nav { display: none; } 
    body { padding-bottom: 0; }
}

.pill { display: inline-flex; align-items: center; padding: 6px 10px; border-radius: 15px; font-size: 0.85em; font-weight: bold; min-width: 90px; justify-content: center;}
.ok { background-color: #d4edda; color: var(--success); } 
.bad { background-color: #f8d7da; color: var(--danger); } 
.unk { background-color: #e2e3e5; color: var(--secondary); } 
.shared-online { background-color: #fff3cd; color: var(--warning); } 
.shared-offline { background-color: #f0f0f0; color: var(--secondary); } 

.pill-expired { background-color: #f0f0f0; color: var(--danger); }
.pill-expiring { background-color: var(--warning-bg); color: var(--warning); } 
.text-expiring { color: var(--warning); font-weight: bold; } 

.pill-online { background-color: #d4edda; color: #155724; }
.pill-offline { background-color: #e2e3e5; color: #6c757d; }
.pill-unknown { background-color: #fff3cd; color: #856404; }

.pill-limit-single { background-color: #007bff; color: white; }
.pill-limit-multi { background-color: #28a745; color: white; }
.pill-limit-default { background-color: #e2e3e5; color: #6c757d; }
.pill-over-limit { background-color: #dc3545; color: white; }

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

tr.expired td { opacity: 0.6; text-decoration-color: var(--danger); }
tr.expiring-soon { border-left: 5px solid var(--warning); background-color: rgba(255, 193, 7, 0.1); } 
tr.over-limit { border-left: 5px solid var(--danger); background-color: rgba(220, 53, 69, 0.1); } 

.btn-delete { background-color: var(--danger); color: white; border: none; padding: 8px 12px; border-radius: 8px; cursor: pointer; font-size: 0.9em; transition: background-color 0.2s;}
.btn-delete:hover { background-color: #c82333; }

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
    width: 50px; 
    text-align: center;
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
    width: 50px; 
    text-align: center;
}

.modal {
  display: none; 
  position: fixed; 
  z-index: 3000; 
  left: 0; top: 0;
  width: 100%; height: 100%; 
  overflow: auto; 
  background-color: rgba(0,0,0,0.4); 
}
.modal-content {
  background-color: var(--card-bg);
  margin: 15% auto;
  padding: 25px; 
  border: none;
  width: 90%; 
  max-width: 320px;
  border-radius: 12px;
  position: relative;
  box-shadow: 0 10px 25px rgba(0,0,0,0.2); 
}
.close-btn { 
  color: var(--secondary); 
  position: absolute; 
  top: 8px;
  right: 15px;
  font-size: 32px; 
  font-weight: 300;
  line-height: 1;
}
.close-btn:hover { color: var(--danger); }
.btn-edit { background-color: var(--warning); color: var(--dark); border: none; padding: 6px 10px; border-radius: 8px; cursor: pointer; font-size: 0.9em; transition: background-color 0.2s; margin-right: 5px; }

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
.modal-save-btn:hover { background-color: var(--primary-dark); } 
</style>
</head><body>
    
    <header class="main-header">
        <div class="header-logo">
            <a href="/">ZIVPN<span class="highlight"> Panel</span></a>
        </div>
    </header>
    
{% if err %}
<div class="boxa1">
    <div class="err" style="text-align: center;">{{ err }}</div>
</div>
{% endif %}

{% include 'users_table.html' %}

    <nav class="bottom-nav">
        <a href="/">
            <i class="icon">➕</i>
            <span>အကောင့်ထည့်ရန်</span>
        </a>
        <a href="/users">
            <i class="icon">📜</i>
            <span>အသုံးပြုသူ စာရင်း</span>
        </a>
        <a href="/logout">
            <i class="icon">➡️</i>
            <span>ထွက်ရန်</span>
        </a>
    </nav>

</body></html>
WRAPPER_HTML

# ===== Web Service (CHANGED: added Y color) =====
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

# ===== Networking: forwarding + DNAT + MASQ + UFW (CHANGED: added Y color) =====
echo -e "${Y}🌐 UDP/DNAT + UFW + sysctl အပြည့်ချထားနေပါတယ်...${Z}"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
grep -q '^net.ipv4.ip_forward=1' /etc/sysctl.conf || echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

IFACE=$(ip -4 route ls | awk '{print $5; exit}')
[ -n "${IFACE:-}" ] || IFACE=eth0
# DNAT 6000:19999/udp -> :5667
iptables -t nat -C PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667 2>/dev/null || \
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
# MASQ out
iptables -t nat -C POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || \
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE

# Allow UDP traffic for VPN ports
iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT 2>/dev/null || true

ufw allow 5667/udp >/dev/null 2>&1 || true
ufw allow 6000:19999/udp >/dev/null 2>&1 || true
ufw allow 8080/tcp >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true

# ===== CRLF sanitize (CHANGED: added Y color) =====
echo -e "${Y}🧹 CRLF ရှင်းနေပါတယ်...${Z}"
sed -i 's/\r$//' /etc/zivpn/web.py /etc/systemd/system/zivpn.service /etc/systemd/system/zivpn-web.service /etc/zivpn/templates/users_table.html /etc/zivpn/templates/users_table_wrapper.html /etc/zivpn/limit_enforcer.sh || true

# ===== Enable services =====
systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service

# ===== Run initial limit enforcement (CHANGED: added Y color) =====
echo -e "${Y}🛡️ ကနဦး Limit Enforcement ကို စတင်နေပါတယ်...${Z}"
$LIMIT_ENFORCER_SCRIPT

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ ZIVPN UDP Server + Web UI + User Limit Enforcement ပြီးဆုံးပါပြီ${Z}"
echo -e "${C}Web Panel (Add Users) :${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}Web Panel (User List) :${Z} ${Y}http://$IP:8080/users${Z}"
echo -e "${C}User Limit Enforcement:${Z} ${G}Active (တစ်မိနစ်တစ်ခါ စစ်ဆေးပါမည်)${Z}"
echo -e "${C}Log File:${Z} ${Y}/var/log/zivpn_limit_enforcer.log${Z}"
echo -e "${C}Services:${Z} ${Y}systemctl status zivpn • systemctl status zivpn-web${Z}"
echo -e "$LINE"
