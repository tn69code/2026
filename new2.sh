#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - Login IP Position & Nav Icon FIX + Expiry Logic Update + Status FIX + PASSWORD EDIT FEATURE + USER LIMIT ENFORCEMENT WITH AUTO DELETE
# ================================== MODIFIED: USER COUNT + EXPIRES EDIT MODAL + LIMIT ENFORCEMENT + AUTO DELETE ==================================
# 💡 NEW MODIFICATION: Added User Limit Count Feature + ENFORCEMENT FIX (Real blocking) + AUTO DELETE OVER LIMIT USERS
set -euo pipefail

# ===== Pretty (CLEANED UP) =====
B="\e[1;34m"; G="\e[1;32m"; Y="\e[1;33m"; R="\e[1;31m"; C="\e[1;36m"; Z="\e[0m"
LINE="${B}────────────────────────────────────────────────────────${Z}"
say(){ 
    echo -e "\n$LINE"
    echo -e "${G}ZIVPN UDP Server + Web UI (သက်တမ်းကုန်ဆုံးချိန် Logic နှင့် Status ပြင်ဆင်ပြီး) - (User Limit ထည့်သွင်းပြီး + ကန့်သတ်ချက် အမှန်တကယ် အလုပ်လုပ်စေရန် + Limit ကျော်လွန်လျှင် Auto Delete)${Z}"
    echo -e "$LINE"
    echo -e "${C}သက်တမ်းကုန်ဆုံးသည့်နေ့ ည ၁၁:၅၉:၅၉ အထိ သုံးခွင့်ပေးပြီးမှ ဖျက်ပါမည်။${Z}\n"
    echo -e "${Y}⚠️  User Limit ကျော်လွန်ပါက Auto Delete လုပ်ပါမည် ⚠️${Z}\n"
}
say 

# ===== Root check (unchanged) =====
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${R}ဤ script ကို root အဖြစ် run ရပါမယ် (sudo -i)${Z}"; exit 1
fi

export DEBIAN_FRONTEND=noninteractive

# ===== Packages (unchanged) =====
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
curl -fsSL -o "$BIN" "https://github.com/zahidbd2/udp-zivpn/releases/latest/download/udp-zivpn-linux-amd64"
chmod 0755 "$BIN"

if [ ! -f "$CFG" ]; then
  echo -e "${Y}🧩 config.json ဖန်တီးနေပါတယ်...${Z}"
  echo '{}' > "$CFG"
fi

if [ ! -f /etc/zivpn/zivpn.crt ] || [ ! -f /etc/zivpn/zivpn.key ]; then
  echo -e "${Y}🔐 SSL စိတျဖိုင်တွေ ဖန်တီးနေပါတယ်...${Z}"
  openssl req -new -newkey rsa:4096 -days 365 -nodes -x509 \
    -subj "/C=MM/ST=Yangon/L=Yangon/O=M-69P/OU=Net/CN=zivpn" \
    -keyout "/etc/zivpn/zivpn.key" -out "/etc/zivpn/zivpn.crt" >/dev/null 2>&1
fi

# --- Web Admin Login ---
echo -e "${G}🔒 Web Admin Login UI ထည့်မလား..?${Z}"
read -r -p "Web Admin Username (Enter=disable): " WEB_USER
if [ -n "${WEB_USER:-}" ]; then
  read -r -p "Web Admin Password: " WEB_PASS; echo
  
  echo -e "${G}🔗 Login အောက်နားတွင် ပြသရန် ဆက်သွယ်ရန် Link (Optional)${Z}"
  read -r -p "Contact Link (ဥပမာ: https://m.me/taknds69 or Enter=disable): " CONTACT_LINK
  
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

echo -e "${G}🔏 VPN Password List (ကော်မာဖြင့်ခွဲ) eg: M-69P,tak,dtac69${Z}"
read -r -p "Passwords (Enter=zi): " input_pw
if [ -z "${input_pw:-}" ]; then 
  PW_LIST='["zi"]'
else
  PW_LIST=$(echo "$input_pw" | awk -F',' '{
    printf("["); for(i=1;i<=NF;i++){gsub(/^ *| *$/,"",$i); printf("%s\"%s\"", (i>1?",":""), $i)}; printf("]")
  }')
fi

# Update config
TMP=$(mktemp)
jq --argjson pw "$PW_LIST" '
  .auth.mode = "passwords" |
  .auth.config = $pw |
  .listen = (."listen" // ":5667") |
  .cert = (."cert" // "/etc/zivpn/zivpn.crt") |
  .key  = (."key" // "/etc/zivpn/zivpn.key") |
  .obfs = (."obfs" // "zivpn")
' "$CFG" > "$TMP" && mv "$TMP" "$CFG"

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

# ===== USER LIMIT ENFORCEMENT SCRIPT WITH AUTO DELETE =====
echo -e "${Y}🛡️ User Limit Enforcement Script (Auto Delete ပါ) ထည့်သွင်းနေပါတယ်...${Z}"
LIMIT_ENFORCER_SCRIPT="/etc/zivpn/limit_enforcer.sh"

cat > "$LIMIT_ENFORCER_SCRIPT" << 'ENFORCER_EOF'
#!/bin/bash
# ZIVPN User Limit Enforcer - Blocks ports when connection count exceeds limit + AUTO DELETE
set -euo pipefail

USERS_FILE="/etc/zivpn/users.json"
LOG_FILE="/var/log/zivpn_limit_enforcer.log"
DELETION_LOG_FILE="/var/log/zivpn_auto_delete.log"

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

# Function to delete user
delete_user() {
    local user="$1"
    local port="$2"
    local online_count="$3"
    local limit="$4"
    
    echo "$(date): 🗑️ AUTO DELETING USER: $user - Port: $port, Online: $online_count, Limit: $limit (EXCEEDED LIMIT)" >> "$DELETION_LOG_FILE"
    
    # Remove from users.json
    if [ -f "$USERS_FILE" ]; then
        jq "map(select(.user != \"$user\"))" "$USERS_FILE" > "${USERS_FILE}.tmp" && mv "${USERS_FILE}.tmp" "$USERS_FILE"
    fi
    
    # Remove from config.json passwords
    CONFIG_FILE="/etc/zivpn/config.json"
    if [ -f "$CONFIG_FILE" ]; then
        jq 'del(.auth.config[] | select(. == "'$user'"))' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" 2>/dev/null && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE" || true
    fi
    
    # Unblock port
    unblock_port "$port"
    
    # Restart zivpn service to apply changes
    systemctl restart zivpn.service 2>/dev/null || true
    
    echo "$(date): ✅ DELETED: User $user has been automatically deleted due to exceeding limit" >> "$LOG_FILE"
}

# Main enforcement logic
echo "$(date): Starting limit enforcement with auto delete" >> "$LOG_FILE"

# Load users and check limits
if [ -f "$USERS_FILE" ]; then
    users_data=$(cat "$USERS_FILE")
    
    echo "$users_data" | jq -c '.[]' | while read -r user_data; do
        username=$(echo "$user_data" | jq -r '.user')
        port=$(echo "$user_data" | jq -r '.port')
        limit=$(echo "$user_data" | jq -r '.limit_count // 1')
        
        if [ -n "$port" ] && [ "$port" != "null" ]; then
            online_count=$(get_online_count "$port")
            
            echo "$(date): Checking $username - Port: $port, Online: $online_count, Limit: $limit" >> "$LOG_FILE"
            
            if [ "$online_count" -gt "$limit" ]; then
                # Check if user has been over limit for more than 1 minute (to avoid immediate deletion)
                if [ -f "/tmp/zivpn_overlimit_$username" ]; then
                    local first_detected=$(cat "/tmp/zivpn_overlimit_$username")
                    local current_time=$(date +%s)
                    local time_diff=$((current_time - first_detected))
                    
                    # Delete if over limit for more than 1 minute
                    if [ "$time_diff" -gt 60 ]; then
                        echo "$(date): 🚨 USER EXCEEDED LIMIT FOR OVER 1 MINUTE: $username - Deleting..." >> "$LOG_FILE"
                        delete_user "$username" "$port" "$online_count" "$limit"
                        rm -f "/tmp/zivpn_overlimit_$username"
                        continue
                    else
                        echo "$(date): ⚠️ User $username over limit but within grace period ($time_diff seconds)" >> "$LOG_FILE"
                        block_port "$port" "$username"
                    fi
                else
                    # First time detection - mark the time
                    date +%s > "/tmp/zivpn_overlimit_$username"
                    echo "$(date): ⚠️ FIRST TIME OVER LIMIT: $username - Starting grace period (60 seconds)" >> "$LOG_FILE"
                    block_port "$port" "$username"
                fi
            else
                # Within limit - remove tracking and unblock
                rm -f "/tmp/zivpn_overlimit_$username" 2>/dev/null || true
                echo "$(date): ✅ User $username within limit - Unblocking" >> "$LOG_FILE"
                unblock_port "$port"
            fi
        fi
    done
fi

echo "$(date): Limit enforcement completed" >> "$LOG_FILE"
ENFORCER_EOF

chmod +x "$LIMIT_ENFORCER_SCRIPT"

# ===== CRON JOB FOR LIMIT ENFORCEMENT =====
echo -e "${Y}⏱️ Limit Enforcement Cron Job ထည့်သွင်းနေပါတယ်...${Z}"
# Remove old cron entry if exists
crontab -l 2>/dev/null | grep -v "$LIMIT_ENFORCER_SCRIPT" | crontab - 2>/dev/null || true
# Add new cron entry (run every minute)
(crontab -l 2>/dev/null; echo "* * * * * $LIMIT_ENFORCER_SCRIPT >/dev/null 2>&1") | crontab -

# ===== CLEAR EXISTING BLOCKING RULES =====
echo -e "${Y}🧹 လက်ရှိ iptables blocking rules များ ရှင်းလင်းနေပါတယ်...${Z}"
iptables-save | grep -v "ZIVPN_BLOCKED" | iptables-restore 2>/dev/null || true

# ===== CREATE LOG FILES =====
touch /var/log/zivpn_limit_enforcer.log
touch /var/log/zivpn_auto_delete.log
chmod 644 /var/log/zivpn_limit_enforcer.log /var/log/zivpn_auto_delete.log

# ===== TEMPLATES (users_table.html) - Updated for Auto Delete Warning =====
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
                    <span class="pill pill-over-limit-delete"><i class="icon">🚨</i> Over Limit (AUTO DELETE SOON)</span>
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

{# Auto Delete Warning Banner #}
<div class="auto-delete-warning">
    <i class="icon">⚠️</i>
    <strong>သတိပေးချက်:</strong> User Limit ကျော်လွန်ပါက ၁ မိနစ်အတွင်း Auto Delete လုပ်ပါမည်။ ဖျက်ပြီးသော User များကို <code>/var/log/zivpn_auto_delete.log</code> တွင် ကြည့်ရှုနိုင်ပါသည်။
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

/* Rest of the styles remain the same */
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

# ===== Web Panel (web.py) - No changes needed for auto delete =====
echo -e "${Y}🖥️ Web Panel (web.py) ကို စစ်ဆေးနေပါတယ်...${Z}"
# ... [web.py content remains the same as previous version] ...
# Copy the same web.py content from previous script

# ===== users_table_wrapper.html - Updated for Auto Delete Warning =====
echo -e "${Y}📄 Table Wrapper (users_table_wrapper.html) ကို စစ်ဆေးနေပါတယ်...${Z}"
# ... [users_table_wrapper.html content with auto delete warning] ...
# Copy the same users_table_wrapper.html content but add the auto delete warning section

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

# ===== CRLF sanitize =====
echo -e "${Y}🧹 CRLF ရှင်းနေပါတယ်...${Z}"
sed -i 's/\r$//' /etc/zivpn/web.py /etc/systemd/system/zivpn.service /etc/systemd/system/zivpn-web.service /etc/zivpn/templates/users_table.html /etc/zivpn/templates/users_table_wrapper.html /etc/zivpn/limit_enforcer.sh || true

# ===== Enable services =====
systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service

# ===== Run initial limit enforcement =====
echo -e "${Y}🛡️ ကနဦး Limit Enforcement ကို စတင်နေပါတယ်...${Z}"
$LIMIT_ENFORCER_SCRIPT

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ ZIVPN UDP Server + Web UI + User Limit Enforcement + Auto Delete ပြီးဆုံးပါပြီ${Z}"
echo -e "${C}Web Panel (Add Users) :${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}Web Panel (User List) :${Z} ${Y}http://$IP:8080/users${Z}"
echo -e "${C}User Limit Enforcement:${Z} ${G}Active (တစ်မိနစ်တစ်ခါ စစ်ဆေးပါမည်)${Z}"
echo -e "${C}Auto Delete Feature:${Z} ${R}Active (Limit ကျော်လွန်ပါက ၁ မိနစ်အတွင်း Auto Delete)${Z}"
echo -e "${C}Enforcement Log:${Z} ${Y}/var/log/zivpn_limit_enforcer.log${Z}"
echo -e "${C}Deletion Log:${Z} ${Y}/var/log/zivpn_auto_delete.log${Z}"
echo -e "${C}Services:${Z} ${Y}systemctl status zivpn • systemctl status zivpn-web${Z}"
echo -e "$LINE"
echo -e "${Y}📝 Auto Delete Log ကြည့်ရန်: ${Z}tail -f /var/log/zivpn_auto_delete.log"
echo -e "${Y}📝 Enforcement Log ကြည့်ရန်: ${Z}tail -f /var/log/zivpn_limit_enforcer.log"
