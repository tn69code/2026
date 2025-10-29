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

# ===== FIXED TEMPLATES - MODAL DIALOGS WORKING PROPERLY =====
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

{# 💡 FIXED: MODAL DIALOGS - CORRECTED STRUCTURE #}

{# Password Edit Modal #}
<div id="editModal" class="modal">
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
<div id="expiresModal" class="modal">
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
<div id="limitModal" class="modal">
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

/* 💡 FIXED: MODAL STYLES */
.modal {
  display: none;
  position: fixed;
  z-index: 1000;
  left: 0;
  top: 0;
  width: 100%;
  height: 100%;
  background-color: rgba(0,0,0,0.5);
}

.modal-content {
  background-color: #fefefe;
  margin: 10% auto;
  padding: 20px;
  border: 1px solid #888;
  width: 90%;
  max-width: 400px;
  border-radius: 10px;
  position: relative;
  animation: modalopen 0.3s;
}

@keyframes modalopen {
  from {opacity: 0; transform: translateY(-50px);}
  to {opacity: 1; transform: translateY(0);}
}

.close-btn {
  color: #aaa;
  position: absolute;
  top: 10px;
  right: 15px;
  font-size: 28px;
  font-weight: bold;
  cursor: pointer;
}

.close-btn:hover {
  color: black;
}

.section-title {
  margin-top: 0;
  padding-bottom: 10px;
  border-bottom: 1px solid #ddd;
  color: #333;
}

.modal .input-group {
  margin-bottom: 15px;
}

.modal .input-label {
  display: block;
  text-align: left;
  font-weight: 600;
  color: #333;
  font-size: 0.9em;
  margin-bottom: 5px;
}

.modal .input-field-wrapper {
  display: flex;
  align-items: center;
  border: 1px solid #ddd;
  border-radius: 5px;
  background-color: #fff;
}

.modal .input-field-wrapper.is-readonly {
  background-color: #f5f5f5;
  border: 1px solid #ddd;
}

.modal .input-field-wrapper input {
  width: 100%;
  padding: 10px;
  border: none;
  border-radius: 5px;
  font-size: 14px;
  outline: none;
  background: transparent;
}

.modal .input-hint {
  margin-top: 5px;
  text-align: left;
  font-size: 0.75em;
  color: #666;
  line-height: 1.4;
}

.modal-save-btn {
  width: 100%;
  padding: 12px;
  background-color: #007bff;
  color: white;
  border: none;
  border-radius: 5px;
  font-size: 14px;
  cursor: pointer;
  margin-top: 10px;
}

.modal-save-btn:hover {
  background-color: #0056b3;
}

.btn-edit {
  background-color: #ffc107;
  color: #212529;
  border: none;
  padding: 5px 10px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 0.8em;
  margin-right: 5px;
}

.btn-edit:hover {
  background-color: #e0a800;
}

.delform {
  display: inline-block;
  margin: 0;
}

.btn-delete {
  background-color: #dc3545;
  color: white;
  border: none;
  padding: 5px 10px;
  border-radius: 4px;
  cursor: pointer;
  font-size: 0.8em;
}

.btn-delete:hover {
  background-color: #c82333;
}

.btn-edit-expires {
  background-color: #28a745;
  color: white;
  border: none;
  padding: 3px 6px;
  border-radius: 3px;
  cursor: pointer;
  font-size: 0.7em;
  margin-left: 5px;
  margin-top: 5px;
}

.btn-edit-expires:hover {
  background-color: #218838;
}

.btn-edit-limit {
  background-color: #6c757d;
  color: white;
  border: none;
  padding: 3px 6px;
  border-radius: 3px;
  cursor: pointer;
  font-size: 0.7em;
  margin-left: 5px;
  margin-top: 5px;
}

.btn-edit-limit:hover {
  background-color: #5a6268;
}

.days-remaining {
  font-size: 0.8em;
  color: #666;
  display: block;
  margin-top: 2px;
}

.pill {
  display: inline-block;
  padding: 4px 8px;
  border-radius: 12px;
  font-size: 0.8em;
  font-weight: bold;
}

.pill-online { background-color: #d4edda; color: #155724; }
.pill-offline { background-color: #e2e3e5; color: #6c757d; }
.pill-unknown { background-color: #fff3cd; color: #856404; }
.pill-limit-single { background-color: #007bff; color: white; }
.pill-limit-multi { background-color: #28a745; color: white; }
.pill-limit-default { background-color: #e2e3e5; color: #6c757d; }
.pill-expired { background-color: #f8d7da; color: #721c24; }
.pill-expiring { background-color: #fff3cd; color: #856404; }
.pill-over-limit { background-color: #dc3545; color: white; }

@media (max-width: 768px) {
  .modal-content {
    margin: 20% auto;
    max-width: 320px;
  }
}
</style>

<script>
// 💡 FIXED: CORRECTED MODAL FUNCTIONS
function showEditModal(user, password) {
    document.getElementById('edit-user').value = user;
    document.getElementById('current-user-display').value = user;
    document.getElementById('current-password').value = password;
    document.getElementById('new-password').value = '';
    document.getElementById('editModal').style.display = 'block';
}

function showExpiresModal(user, expires) {
    document.getElementById('expires-edit-user').value = user;
    document.getElementById('expires-current-user-display').value = user;
    document.getElementById('new-expires').value = expires || '';
    document.getElementById('expiresModal').style.display = 'block';
}

function showLimitModal(user, limit) {
    document.getElementById('limit-edit-user').value = user;
    document.getElementById('limit-current-user-display').value = user;
    document.getElementById('new-limit').value = limit && limit !== 'None' ? limit : 1;
    document.getElementById('limitModal').style.display = 'block';
}

function closeModal(modalId) {
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
        closeModal('editModal');
        closeModal('expiresModal');
        closeModal('limitModal');
    }
});
</script>
TABLE_HTML

# ===== Web Panel (web.py) - Fixed for modal forms =====
echo -e "${Y}🖥️ Web Panel (web.py) ကို ပြင်ဆင်နေပါတယ်...${Z}"
cat >/etc/zivpn/web.py <<'PY'
from flask import Flask, render_template, request, redirect, url_for, session
import json, subprocess, os, hmac
from datetime import datetime, timedelta, date

USERS_FILE = "/etc/zivpn/users.json"
CONFIG_FILE = "/etc/zivpn/config.json"

def get_server_ip():
    try:
        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, check=True)
        return result.stdout.strip().split()[0]
    except:
        return "127.0.0.1"

SERVER_IP = get_server_ip()

app = Flask(__name__, template_folder="/etc/zivpn/templates")
app.secret_key = os.environ.get("WEB_SECRET", "dev-secret-key")
ADMIN_USER = os.environ.get("WEB_ADMIN_USER", "admin")
ADMIN_PASS = os.environ.get("WEB_ADMIN_PASSWORD", "admin")

def read_json(path):
    try:
        with open(path, "r") as f:
            return json.load(f)
    except:
        return []

def write_json(path, data):
    with open(path, "w") as f:
        json.dump(data, f, indent=2)

def load_users():
    return read_json(USERS_FILE)

def save_users(users):
    write_json(USERS_FILE, users)

def get_user_online_count(port):
    if not port:
        return 0
    try:
        result = subprocess.run(
            f"conntrack -L -p udp 2>/dev/null | grep 'dport={port}'",
            shell=True, capture_output=True, text=True
        )
        lines = result.stdout.strip().split('\n')
        return len([line for line in lines if 'dport=' in line])
    except:
        return 0

def is_expiring_soon(expires_str):
    if not expires_str:
        return False
    try:
        expires_date = datetime.strptime(expires_str, "%Y-%m-%d").date()
        today = date.today()
        return (expires_date - today).days <= 1
    except:
        return False

def calculate_days_remaining(expires_str):
    if not expires_str:
        return None
    try:
        expires_date = datetime.strptime(expires_str, "%Y-%m-%d").date()
        today = date.today()
        return (expires_date - today).days
    except:
        return None

def sync_config_passwords():
    users = load_users()
    today_date = date.today()
    valid_passwords = []
    
    for user in users:
        expires_str = user.get("expires")
        is_valid = True
        if expires_str:
            try:
                if datetime.strptime(expires_str, "%Y-%m-%d").date() < today_date:
                    is_valid = False
            except:
                pass
        if is_valid and user.get("password"):
            valid_passwords.append(user["password"])
    
    config = read_json(CONFIG_FILE)
    if not isinstance(config, dict):
        config = {}
    
    config["auth"] = {
        "mode": "passwords",
        "config": valid_passwords
    }
    write_json(CONFIG_FILE, config)
    
    # Restart service
    subprocess.run("systemctl restart zivpn.service", shell=True)

def login_enabled():
    return bool(ADMIN_USER and ADMIN_PASS)

def is_authed():
    return session.get("auth") == True

def require_login():
    return not login_enabled() or is_authed()

@app.route("/")
def index():
    if not require_login():
        return redirect(url_for('login'))
    return redirect(url_for('users_table'))

@app.route("/users")
def users_table():
    if not require_login():
        return redirect(url_for('login'))
    
    users = load_users()
    today_date = date.today()
    
    user_data = []
    for user in users:
        expires_date = None
        if user.get("expires"):
            try:
                expires_date = datetime.strptime(user["expires"], "%Y-%m-%d").date()
            except:
                pass
        
        online_count = get_user_online_count(user.get("port"))
        limit_count = user.get("limit_count", 1)
        
        user_data.append({
            "user": user["user"],
            "password": user["password"],
            "expires": user.get("expires"),
            "expires_date": expires_date,
            "days_remaining": calculate_days_remaining(user.get("expires")),
            "online_count": online_count,
            "limit_count": limit_count,
            "is_over_limit": online_count > limit_count,
            "expiring_soon": is_expiring_soon(user.get("expires"))
        })
    
    return render_template("users_table.html", 
                         users=user_data, 
                         today_date=today_date)

@app.route("/login", methods=["GET", "POST"])
def login():
    if not login_enabled():
        return redirect(url_for('users_table'))
    
    if request.method == "POST":
        username = request.form.get("u", "").strip()
        password = request.form.get("p", "").strip()
        
        if (hmac.compare_digest(username, ADMIN_USER) and 
            hmac.compare_digest(password, ADMIN_PASS)):
            session["auth"] = True
            return redirect(url_for('users_table'))
        else:
            return render_template_string('''
                <div style="text-align:center;padding:50px;">
                    <h2>Login Failed</h2>
                    <p>Invalid username or password</p>
                    <a href="/login">Try Again</a>
                </div>
            ''')
    
    return render_template_string('''
        <div style="text-align:center;padding:50px;">
            <h2>ZIVPN Login</h2>
            <form method="POST">
                <input type="text" name="u" placeholder="Username" required><br><br>
                <input type="password" name="p" placeholder="Password" required><br><br>
                <button type="submit">Login</button>
            </form>
        </div>
    ''')

@app.route("/logout")
def logout():
    session.pop("auth", None)
    return redirect(url_for('login'))

@app.route("/edit", methods=["POST"])
def edit_password():
    if not require_login():
        return redirect(url_for('login'))
    
    user = request.form.get("user", "").strip()
    new_password = request.form.get("password", "").strip()
    
    users = load_users()
    for u in users:
        if u["user"] == user:
            u["password"] = new_password
            break
    
    save_users(users)
    sync_config_passwords()
    
    return redirect(url_for('users_table'))

@app.route("/edit_expires", methods=["POST"])
def edit_expires():
    if not require_login():
        return redirect(url_for('login'))
    
    user = request.form.get("user", "").strip()
    new_expires = request.form.get("expires", "").strip()
    
    if new_expires.isdigit():
        new_expires = (datetime.now() + timedelta(days=int(new_expires))).strftime("%Y-%m-%d")
    
    users = load_users()
    for u in users:
        if u["user"] == user:
            u["expires"] = new_expires
            break
    
    save_users(users)
    return redirect(url_for('users_table'))

@app.route("/edit_limit", methods=["POST"])
def edit_limit():
    if not require_login():
        return redirect(url_for('login'))
    
    user = request.form.get("user", "").strip()
    try:
        new_limit = int(request.form.get("limit_count", "1"))
    except:
        new_limit = 1
    
    users = load_users()
    for u in users:
        if u["user"] == user:
            u["limit_count"] = new_limit
            break
    
    save_users(users)
    return redirect(url_for('users_table'))

@app.route("/delete", methods=["POST"])
def delete_user():
    if not require_login():
        return redirect(url_for('login'))
    
    user_to_delete = request.form.get("user", "").strip()
    users = load_users()
    users = [u for u in users if u["user"] != user_to_delete]
    save_users(users)
    sync_config_passwords()
    
    return redirect(url_for('users_table'))

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
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
echo 'net.ipv4.ip_forward=1' >> /etc/sysctl.conf

IFACE=$(ip -4 route ls | awk '{print $5; exit}')
[ -n "${IFACE:-}" ] || IFACE=eth0

# Clear and setup iptables
iptables -t nat -F
iptables -t nat -A PREROUTING -i "$IFACE" -p udp --dport 6000:19999 -j DNAT --to-destination :5667
iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE
iptables -A INPUT -p udp --dport 6000:19999 -j ACCEPT

ufw allow 5667/udp >/dev/null 2>&1
ufw allow 6000:19999/udp >/dev/null 2>&1
ufw allow 8080/tcp >/dev/null 2>&1
echo "y" | ufw enable >/dev/null 2>&1

# ===== Cleanup and start services =====
echo -e "${Y}🧹 File formatting ပြင်ဆင်နေပါတယ်...${Z}"
sed -i 's/\r$//' /etc/zivpn/web.py /etc/zivpn/templates/users_table.html 2>/dev/null || true

echo -e "${Y}🚀 Services စတင်နေပါတယ်...${Z}"
systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service

# Wait for services
sleep 2

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ ZIVPN Installation Completed!${Z}"
echo -e "${C}Web Panel:${Z} ${Y}http://$IP:8080/users${Z}"
echo -e "${C}VPN Port:${Z} ${Y}5667 (UDP)${Z}"
echo -e "${C}Port Range:${Z} ${Y}6000-19999 (UDP)${Z}"
echo -e "${C}Features:${Z} ${G}Fixed Modal Dialogs • User Limit • Auto Delete${Z}"
echo -e "$LINE"
