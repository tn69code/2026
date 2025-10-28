#!/bin/bash
# ZIVPN UDP Server + Web UI (Myanmar) - Login IP Position & Nav Icon FIX + Expiry Logic Update + Status FIX + PASSWORD EDIT FEATURE (MODAL UI UPDATE - Syntax Fixed + MAX-WIDTH Reduced)
# ================================== MODIFIED: USER COUNT + EXPIRES EDIT MODAL ==================================
# 💡 NEW MODIFICATION: Added User Limit Count Feature + ENFORCEMENT FIX
# 💡 MODIFICATION REQUEST: Shorten 'Edit Expires' and 'Edit Limit' buttons & make their Modals the same width as 'Password Edit' modal.
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

# ===== Packages (unchanged) =====
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

# --- ZIVPN Binary, Config, Certs (UNCHANGED) ---
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

# --- Web Admin Login, VPN Passwords, config.json Update, systemd: ZIVPN (UNCHANGED logic) ---
echo -e "${G}🔒 Web Admin Login UI ထည့်မလား..?${Z}"
read -r -p "Web Admin Username (Enter=disable): " WEB_USER
if [ -n "${WEB_USER:-}" ]; then
  # 💡 ပြင်ဆင်ပြီး: -s (silent) ကို ဖျက်လိုက်သဖြင့် Password ရိုက်ထည့်ရင် စာပေါ်မည်။
  read -r -p "Web Admin Password: " WEB_PASS; echo
  
  # 💡 NEW: Contact Link ကို မေးမြန်းခြင်း
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
    # 💡 NEW: Contact Link ကို web.env ထဲသို့ ထည့်ခြင်း
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

# 💡 MODIFIED: users_table.html (Added Online Users column, Expires Edit Modal, Limit Count Column, Limit Count Edit Modal)
echo -e "${Y}📄 Table HTML (users_table.html) ကို စစ်ဆေးနေပါတယ်...${Z}"
cat >"$TEMPLATES_DIR/users_table.html" <<'TABLE_HTML'
<div class="table-container">
    <table>
      <thead>
          <tr>
            <th><i class="icon">👤</i> User</th>
            <th><i class="icon">🔑</i> Password</th>
            <th><i class="icon">⏰</i> Expires</th>
            <th><i class="icon">💻</i> Online Users</th> {# 💡 NEW COLUMN #}
            <th><i class="icon">👥</i> Limit</th> {# 💡 NEW COLUMN #}
            <th><i class="icon">🚦</i> Status</th> 
            <th><i class="icon">❌</i> Action</th>
          </tr>
      </thead>
      <tbody>
          {% for u in users %}
          <tr class="{% if u.expires and u.expires_date < today_date %}expired{% elif u.expiring_soon %}expiring-soon{% elif u.is_over_limit %}over-limit{% endif %}"> {# 💡 ADDED over-limit CLASS #}
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
                        
                        {# 💡 Display Days Remaining #}
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
                {# 💡 MODIFIED BUTTON TEXT #}
                <button type="button" class="btn-edit-expires" onclick="showExpiresModal('{{ u.user }}', '{{ u.expires }}')"><i class="icon">📝</i> Edit</button> 

            </td>
            
            <td data-label="Online Users"> {# 💡 NEW ONLINE USERS DATA #}
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
            
            <td data-label="Limit"> {# 💡 NEW LIMIT DATA #}
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
                {# 💡 MODIFIED BUTTON TEXT #}
                <button type="button" class="btn-edit-limit" onclick="showLimitModal('{{ u.user }}', '{{ u.limit_count }}')"><i class="icon">📝</i> Limit</button>
            </td>

            <td data-label="Status">
                {# Flask's is_expiring_soon() and expiration logic determines the status #}
                {% if u.expires and u.expires_date < today_date %}
                    <span class="pill pill-expired"><i class="icon">🛑</i> Expired</span>
                
                {# Expiring Soon (Today or Tomorrow) #}
                {% elif u.expiring_soon %}
                    <span class="pill pill-expiring"><i class="icon">⚠️</i> Expiring Soon</span>
                    
                {# Over Limit #}
                {% elif u.is_over_limit %}
                    <span class="pill pill-over-limit"><i class="icon">❌</i> Over Limit</span> {# 💡 NEW STATUS #}

                {# Active (Including no expiration set, or 2 days or more left, and not over limit) #}
                {% else %}
                    <span class="pill ok"><i class="icon">🟢</i> Active</span>
                {% endif %}
            </td>

            <td data-label="Action">
              <button type="button" class="btn-edit" onclick="showEditModal('{{ u.user }}', '{{ u.password }}', '{{ u.expires }}')"><i class="icon">✏️</i> Pass</button> {# 💡 Password Edit Button #}
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

{# 💡 PASSWORD EDIT MODAL (UNCHANGED) #}
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

{# 💡 NEW: EXPIRES EDIT MODAL (MODIFIED: max-width removed to inherit from CSS) #}
<div id="expiresModal" class="modal">
  <div class="modal-content"> {# Removed style="max-width: 350px;" to use default 320px from CSS #}
    <span class="close-btn" onclick="document.getElementById('expiresModal').style.display='none'">&times;</span>
    <h2 class="section-title"><i class="icon">⏰</i> Change Expiry Date</h2>
    <form method="post" action="/edit_expires"> {# NEW ROUTE #}
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
{# 💡 END NEW EXPIRES EDIT MODAL #}

{# 💡 NEW: LIMIT EDIT MODAL (MODIFIED: max-width removed to inherit from CSS) #}
<div id="limitModal" class="modal">
  <div class="modal-content"> {# Removed style="max-width: 350px;" to use default 320px from CSS #}
    <span class="close-btn" onclick="document.getElementById('limitModal').style.display='none'">&times;</span>
    <h2 class="section-title"><i class="icon">👥</i> Change User Limit</h2>
    <form method="post" action="/edit_limit"> {# NEW ROUTE #}
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
{# 💡 END NEW LIMIT EDIT MODAL #}


<style>
/* 💡 MODAL UI UPDATE START (UNCHANGED) */
.modal-content {
  background-color: var(--card-bg); /* Use card background color */
  margin: 15% auto; /* နေရာချထားမှု ချိန်ညှိသည် */
  padding: 25px; 
  border: none; /* Remove default border */
  width: 90%; 
  max-width: 320px; /* 💡 MAX-WIDTH ကို 320px သို့ လျှော့ချသည်။ (Used by all modals now) */
  border-radius: 12px;
  position: relative;
  box-shadow: 0 10px 25px rgba(0,0,0,0.2); /* Stronger, modern shadow */
}
/* 💡 CLOSE BUTTON POSITIONING FIX */
.close-btn { 
  color: var(--secondary); 
  position: absolute; /* modal-content နှင့် စပ်လျဉ်း၍ နေရာချထားသည် */
  top: 8px; /* အပေါ်သို့ ရွှေ့သည် */
  right: 15px; /* ညာဘက်သို့ ရွှေ့သည် */
  font-size: 32px; 
  font-weight: 300; 
  transition: color 0.2s;
  line-height: 1; /* စာကြောင်း အကွာအဝေး ချိန်ညှိသည် */
}
.close-btn:hover { color: var(--danger); }
.section-title { margin-top: 0; padding-bottom: 10px; border-bottom: 1px solid var(--border-color); color: var(--primary-dark);}

/* Re-use Input Group styles from main HTML, but define specifically for modal for clarity */
.modal .input-group { margin-bottom: 20px; }
.modal .input-label {
    display: block;
    text-align: left;
    font-weight: 600;
    color: var(--dark);
    font-size: 0.9em; /* ညီညာပြီး သေးငယ်စေရန် */
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
    background-color: var(--light); /* Light gray background for readonly */
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

/* Hint Text */
.modal .input-hint {
    margin-top: 5px;
    text-align: left;
    font-size: 0.75em; /* ပိုသေးငယ်စေရန် */
    color: var(--secondary);
    line-height: 1.4;
    padding-left: 5px;
}

/* Save Button Design (Using Primary Color) */
.modal-save-btn {
    width: 100%;
    padding: 12px; 
    background-color: var(--primary); /* Orange Primary Color */
    color: white; 
    border: none; 
    border-radius: 8px; 
    font-size: 1.0em;
    cursor: pointer; 
    transition: background-color 0.3s, transform 0.1s; 
    margin-top: 10px; 
    font-weight: bold;
    box-shadow: 0 4px 6px rgba(255, 127, 39, 0.3); /* Subtle button shadow */
}
.modal-save-btn:hover { background-color: var(--primary-dark); } 
.modal-save-btn:active { background-color: var(--primary-dark); transform: translateY(1px); box-shadow: 0 2px 4px rgba(255, 127, 39, 0.3); }

/* Button Styles for Action Column */
.btn-edit { background-color: var(--warning); color: var(--dark); border: none; padding: 6px 10px; border-radius: 8px; cursor: pointer; font-size: 0.9em; transition: background-color 0.2s; margin-right: 5px; }
.btn-edit:hover { background-color: #e0ac08; }
.delform { display: inline-block; margin: 0; }
.btn-delete { background-color: var(--danger); color: white; border: none; padding: 6px 10px; border-radius: 8px; cursor: pointer; font-size: 0.9em; transition: background-color 0.2s; }
.btn-delete:hover { background-color: #c82333; }

/* 💡 MODIFIED BUTTON: Expires Edit Button */
.btn-edit-expires { 
    background-color: var(--primary); 
    color: white; 
    border: none; 
    padding: 3px 6px; /* Reduced padding */
    border-radius: 4px; 
    cursor: pointer; 
    font-size: 0.75em; 
    transition: background-color 0.2s; 
    margin-left: 5px;
    margin-top: 5px;
    display: inline-block; 
    width: 50px; /* 💡 Set fixed width */
    text-align: center;
}
.btn-edit-expires:hover { background-color: var(--primary-dark); }

/* 💡 MODIFIED BUTTON: Limit Edit Button */
.btn-edit-limit { 
    background-color: var(--secondary); 
    color: white; 
    border: none; 
    padding: 3px 6px; /* Reduced padding */
    border-radius: 4px; 
    cursor: pointer; 
    font-size: 0.75em; 
    transition: background-color 0.2s; 
    margin-left: 5px;
    margin-top: 5px;
    display: inline-block;
    width: 50px; /* 💡 Set fixed width */
    text-align: center;
}
.btn-edit-limit:hover { background-color: #5a6268; }


/* Days Remaining Text Style (UNCHANGED) */
.days-remaining {
    font-size: 0.85em; /* ဥပမာ- 2025-10-24 ထက် အနည်းငယ် သေးငယ်စေရန် */
    color: var(--secondary);
    font-weight: 500;
    display: inline-block;
    margin-top: 2px;
}
.days-remaining .text-expiring {
    font-weight: bold;
}

/* 💡 NEW PILL STYLES for Online Users */
.pill-online { background-color: #d4edda; color: #155724; } /* Greenish */
.pill-offline { background-color: #e2e3e5; color: #6c757d; } /* Grayish */
.pill-unknown { background-color: #fff3cd; color: #856404; } /* Yellowish */

/* 💡 NEW PILL STYLES for Limit */
.pill-limit-single { background-color: #007bff; color: white; } /* Blue for single user */
.pill-limit-multi { background-color: #28a745; color: white; } /* Green for multiple users */
.pill-limit-default { background-color: #e2e3e5; color: #6c757d; } /* Grayish for default/N/A */
.pill-over-limit { background-color: #dc3545; color: white; } /* Red for over limit */


@media (max-width: 768px) {
    /* 💡 MODIFIED: Column count changed, need to adjust data-label padding */
    td { padding-left: 50%; } /* Increase padding for more space */
    td:before { width: 45%; } /* Increase label width */
    td[data-label="Action"] { display: flex; justify-content: flex-end; align-items: center; }
    .btn-edit { width: auto; padding: 6px 8px; font-size: 0.8em; margin-right: 5px; }
    .btn-delete { width: auto; padding: 6px 8px; font-size: 0.8em; margin-top: 0; }
    .modal-content { 
        margin: 20% auto; 
        max-width: 280px; /* 💡 Mobile အတွက် ပိုသေးအောင် လျှော့ချသည်။ */
    }
    .days-remaining { display: block; text-align: right; }
    /* 💡 MODIFIED BUTTONS FOR MOBILE */
    .btn-edit-expires { display: inline-block; margin-left: 5px; width: auto; box-sizing: border-box; }
    .btn-edit-limit { display: inline-block; margin-left: 5px; width: auto; box-sizing: border-box; }


}
/* 💡 MODAL UI UPDATE END */
/* 💡 NEW ROW STYLE: Over Limit */
tr.over-limit { 
    border-left: 5px solid var(--danger); 
    background-color: rgba(220, 53, 69, 0.1); /* Light red background */
}
</style>

<script>
    // JavaScript to handle the modal display
    function showEditModal(user, password, expires) {
        document.getElementById('edit-user').value = user;
        document.getElementById('current-user-display').value = user; // Display user
        document.getElementById('current-password').value = password;
        
        // Clear new password field when opening
        document.getElementById('new-password').value = '';
        
        document.getElementById('editModal').style.display = 'block';
    }

    // 💡 NEW JAVASCRIPT: Handle Expires Modal Display
    function showExpiresModal(user, expires) {
        document.getElementById('expires-edit-user').value = user;
        document.getElementById('expires-current-user-display').value = user; 
        document.getElementById('new-expires').value = expires;
        
        document.getElementById('expiresModal').style.display = 'block';
    }
    
    // 💡 NEW JAVASCRIPT: Handle Limit Modal Display
    function showLimitModal(user, limit) {
        document.getElementById('limit-edit-user').value = user;
        document.getElementById('limit-current-user-display').value = user; 
        // Default to 1 if limit is 'None' or empty
        document.getElementById('new-limit').value = limit && limit !== 'None' ? limit : 1; 
        
        document.getElementById('limitModal').style.display = 'block';
    }

    // Close modal when clicking outside of it (MODIFIED to check all modals)
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

# 💡 Mobile Friendly: users_table_wrapper.html (MODIFIED: style for new column)
echo -e "${Y}📄 Table Wrapper (users_table_wrapper.html) ကို စစ်ဆေးနေပါတယ်...${Z}"
cat >"$TEMPLATES_DIR/users_table_wrapper.html" <<'WRAPPER_HTML'
<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<title>ZIVPN User Panel - Users</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<style>
/* Global Styles for Mobile UI */
:root {
    --primary: #ff7f27; /* 💡 Color Change: Orange */
    --primary-dark: #cc661f; /* Darker shade for active/hover state */
    --secondary: #6c757d; --success: #28a745; --danger: #dc3545;
    --light: #f8f9fa; --dark: #343a40; 
    --bg-color: #f0f2f5; 
    --card-bg: #ffffff;
    --border-color: #dee2e6;
    --warning: #ffc107; /* New: Warning color for expiry */
    --warning-bg: #fff3cd;
}
body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: var(--bg-color);
    line-height: 1.6; color: var(--dark); margin: 0; padding: 0;
    padding-bottom: 70px; /* Space for fixed bottom navigation */
}
.icon { font-style: normal; margin-right: 5px; }

/* Header/Logo Only */
.main-header {
    display: flex; justify-content: space-between; align-items: center;
    background-color: var(--card-bg); padding: 10px 15px; box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1);
    margin-bottom: 15px; position: sticky; top: 0; z-index: 1000;
}
.header-logo a { font-size: 1.6em; font-weight: bold; color: var(--primary); text-decoration: none;}
.header-logo .highlight { color: var(--dark); }

/* 💡 Mobile Bottom Navigation (New) */
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


/* Table Styles (Mobile Responsiveness) */
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

/* Mobile Table Stacked View (Crucial for mobile friendliness) */
@media (max-width: 768px) {
    .table-container { padding: 0 5px; }
    
    table, thead, tbody, th, td, tr { display: block; }
    thead { display: none; } /* Hide Header on Mobile */
    
    tr { 
        border: 1px solid var(--border-color); 
        margin-bottom: 15px; 
        border-radius: 8px; 
        box-shadow: 0 1px 4px rgba(0, 0, 0, 0.05);
    }
    td {
        border: none;
        position: relative;
        padding-left: 50%; /* 💡 MODIFIED: Increased padding */
        text-align: right;
        border-bottom: 1px dashed #e0e0e0;
    }
    td:last-child { border-bottom: none; }
    
    td:before {
        content: attr(data-label);
        position: absolute;
        left: 0;
        width: 45%; /* 💡 MODIFIED: Increased label width */
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
    /* 💡 MODIFIED BUTTONS FOR MOBILE */
    .btn-edit-expires { display: inline-block; margin-left: 5px; width: auto; box-sizing: border-box; }
    .btn-edit-limit { display: inline-block; margin-left: 5px; width: auto; box-sizing: border-box; }
}
/* Desktop Navigation Hidden */
.main-nav { display: none; } 
@media (min-width: 769px) {
    .bottom-nav { display: none; } 
    body { padding-bottom: 0; }
}

/* Pill/Status & Buttons */
.pill { display: inline-flex; align-items: center; padding: 6px 10px; border-radius: 15px; font-size: 0.85em; font-weight: bold; min-width: 90px; justify-content: center;}
.ok { background-color: #d4edda; color: var(--success); } 
.bad { background-color: #f8d7da; color: var(--danger); } 
.unk { background-color: #e2e3e5; color: var(--secondary); } 
.shared-online { background-color: #fff3cd; color: var(--warning); } 
.shared-offline { background-color: #f0f0f0; color: var(--secondary); } 

.pill-expired { background-color: #f0f0f0; color: var(--danger); }
.pill-expiring { background-color: var(--warning-bg); color: var(--warning); } 
.text-expiring { color: var(--warning); font-weight: bold; } 

/* 💡 NEW PILL STYLES for Online Users */
.pill-online { background-color: #d4edda; color: #155724; } /* Greenish */
.pill-offline { background-color: #e2e3e5; color: #6c757d; } /* Grayish */
.pill-unknown { background-color: #fff3cd; color: #856404; } /* Yellowish */

/* 💡 NEW PILL STYLES for Limit and Over Limit */
.pill-limit-single { background-color: #007bff; color: white; } /* Blue for single user */
.pill-limit-multi { background-color: #28a745; color: white; } /* Green for multiple users */
.pill-limit-default { background-color: #e2e3e5; color: #6c757d; } /* Grayish for default/N/A */
.pill-over-limit { background-color: #dc3545; color: white; } /* Red for over limit */


/* Days Remaining Text Style */
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


/* Row Styles for Expiry */
tr.expired td { opacity: 0.6; text-decoration-color: var(--danger); }
tr.expiring-soon { border-left: 5px solid var(--warning); background-color: rgba(255, 193, 7, 0.1); } 
tr.over-limit { border-left: 5px solid var(--danger); background-color: rgba(220, 53, 69, 0.1); } 


.btn-delete { background-color: var(--danger); color: white; border: none; padding: 8px 12px; border-radius: 8px; cursor: pointer; font-size: 0.9em; transition: background-color 0.2s;}
.btn-delete:hover { background-color: #c82333; }
/* 💡 MODIFIED BUTTON: Expires Edit Button - Matches Table HTML change */
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
/* 💡 MODIFIED BUTTON: Limit Edit Button - Matches Table HTML change */
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

/* 💡 New/Updated styles for Edit Modal (Must be included here for the HTML wrapper) */
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
  background-color: var(--card-bg); /* Use card background color */
  margin: 15% auto; /* နေရာချထားမှု ချိန်ညှိသည် */
  padding: 25px; 
  border: none; 
  width: 90%; 
  max-width: 320px; /* 💡 MAX-WIDTH ကို 320px သို့ လျှော့ချသည်။ (Used by all modals now) */
  border-radius: 12px;
  position: relative;
  box-shadow: 0 10px 25px rgba(0,0,0,0.2); 
}
/* 💡 CLOSE BUTTON POSITIONING FIX */
.close-btn { 
  color: var(--secondary); 
  position: absolute; 
  top: 8px; /* အပေါ်သို့ ရွှေ့သည် */
  right: 15px; /* ညာဘက်သို့ ရွှေ့သည် */
  font-size: 32px; 
  font-weight: 300;
  line-height: 1;
}
.close-btn:hover { color: var(--danger); }
.btn-edit { background-color: var(--warning); color: var(--dark); border: none; padding: 6px 10px; border-radius: 8px; cursor: pointer; font-size: 0.9em; transition: background-color 0.2s; margin-right: 5px; }

/* MODAL UI SPECIFIC STYLES - Duplicated for full self-containment */
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
    
{# 💡 users_table_wrapper.html တွင် error message ပြသခြင်း ထပ်ပေါင်းထည့်ရန် #}
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

# 💡 Web Panel (Flask - web.py) (MODIFIED: load_users, prepare_user_data, /add, /edit_limit, HTML for limit input, login password type)
echo -e "${Y}🖥️ Web Panel (web.py) ကို စစ်ဆေးနေပါတယ်...${Z}"
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
        # Use a more reliable method to get the primary, external IP if possible
        result = subprocess.run(['hostname', '-I'], capture_output=True, text=True, check=True)
        # 💡 FIX: Split by space, take the first IP, and trim
        ip = result.stdout.strip().split()[0]
        if re.match(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$', ip):
            return ip
    except Exception:
        pass
    return "127.0.0.1" 

SERVER_IP_FALLBACK = get_server_ip()
# 💡 NEW: Contact Link ကို Environment ကနေ ယူခြင်း
CONTACT_LINK = os.environ.get("WEB_CONTACT_LINK", "").strip()

# 💡 HTML Template အဓိကဖိုင် (MODIFIED for Contact Link and New Input Field)
HTML = """<!doctype html>
<html lang="my"><head><meta charset="utf-8">
<title>ZIVPN User Panel</title>
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta http-equiv="refresh" content="120">
<style>
/* Global Styles */
:root {
    --primary: #ff7f27; /* 💡 Color Change: Orange */
    --primary-dark: #cc661f; /* Darker shade for active/hover state */
    --secondary: #6c757d; --success: #28a745; --danger: #dc3545;
    --light: #f8f9fa; --dark: #343a40; --bg-color: #f0f2f5; --card-bg: #ffffff;
    --border-color: #dee2e6;
    --warning: #ffc107; 
}
body {
    font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; background-color: var(--bg-color);
    line-height: 1.6; color: var(--dark); margin: 0; padding: 0;
    padding-bottom: 70px; 
}
.icon { font-style: normal; margin-right: 5px; }

/* Header/Logo Only */
.main-header {
    display: flex; justify-content: space-between; align-items: center;
    background-color: var(--card-bg); padding: 10px 15px; box-shadow: 0 1px 4px rgba(0, 0, 0, 0.1);
    margin-bottom: 15px; position: sticky; top: 0; z-index: 1000;
}
.header-logo a { font-size: 1.6em; font-weight: bold; color: var(--primary); text-decoration: none;} 
.header-logo .highlight { color: var(--dark); }

/* 💡 Mobile Bottom Navigation */
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
@media (min-width: 769px) {
    .bottom-nav { display: none; }
    body { padding-bottom: 0; }
}

/* Login/Form Styles - Enhanced UI */
.login-container, .boxa1 {
    background-color: var(--card-bg); 
    padding: 30px 20px; 
    border-radius: 12px;
    box-shadow: 0 4px 15px rgba(0, 0, 0, 0.15); 
    width: 90%; max-width: 400px;
    margin: 30px auto;
    text-align: center;
}
.boxa1 {
    max-width: 600px;
    margin-top: 15px;
    text-align: left;
}


/* New: Info Card for total users */
.info-card {
    background-color: #fcece3; 
    color: var(--primary-dark);
    padding: 15px 20px;
    border-radius: 8px;
    text-align: center;
    font-weight: bold;
    font-size: 1.0em; 
    margin-bottom: 15px;
    border: 1px solid var(--primary);
    box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
}
/* 💡 ပြင်ဆင်ချက်: စုစုပေါင်းအရေအရေအတွက် (Total Users) ကို စာလုံးသေးပေးလိုက်သည် */
.info-card span {
    font-size: 1.1em; 
    margin-right: 5px;
}

.profile-image-container {
    display: inline-block; margin-bottom: 15px; border-radius: 50%;
    overflow: hidden; border: 4px solid var(--primary); 
}
.profile-image { width: 70px; height: 70px; object-fit: cover; display: block; }
h1 { font-size: 22px; color: var(--dark); margin-bottom: 5px; }
.panel-title { font-size: 14px; color: var(--secondary); margin-bottom: 25px; }
/* 💡 New: Login IP Display Style */
.login-ip-display {
    font-size: 16px;
    color: var(--primary-dark);
    font-weight: bold;
    margin-top: -15px; 
    margin-bottom: 25px; 
}

/* Input Fields with Icons/Design */
.input-group { 
    margin-bottom: 15px; 
    text-align: left;
}
.input-field-wrapper {
    display: flex;
    align-items: center;
    border: 1px solid var(--border-color);
    border-radius: 8px;
    margin-Top: 5px; 
    background-color: #fff;
    transition: border-color 0.3s, box-shadow 0.3s;
}
.input-field-wrapper:focus-within {
    border-color: var(--primary); 
    box-shadow: 0 0 0 3px rgba(255, 127, 39, 0.25); 
}
.input-field-wrapper .icon {
    padding: 0 10px;
    color: var(--secondary);
    background: transparent; 
}
input[type="text"], input[type="password"], input[name="expires"], input[name="port"], input[name="ip"], input[type="number"] {
    width: 100%;
    padding: 12px 10px;
    border: none; 
    border-radius: 0 8px 8px 0;
    font-size: 16px;
    outline: none;
    background: transparent; 
    appearance: none; 
    -webkit-appearance: none;
}
input[name="ip"] {
    background-color: var(--light);
    color: var(--secondary);
    cursor: pointer; 
}
/* 💡 Button Color and Hover/Active State */
.login-button, .save-btn {
    width: 100%; padding: 12px; 
    background-color: var(--primary); 
    color: white; border: none; border-radius: 8px; font-size: 16px;
    cursor: pointer; transition: background-color 0.3s; margin-top: 20px; font-weight: bold;
}
.login-button:hover, .save-btn:hover { background-color: var(--primary-dark); } 
.login-button:active, .save-btn:active { background-color: var(--primary-dark); transform: translateY(1px); } 


.section-title { font-size: 18px; font-weight: bold; color: var(--dark); margin-bottom: 15px; }
.row{display:flex;gap:15px;flex-wrap:wrap;margin-bottom: 5px;}
.row>div{flex:1 1 100%;}
@media (min-width: 600px) {
    .row>div{flex:1 1 220px;}
}
/* 💡 Error Message Style (For Login) */
.err{
    color: var(--danger); 
    background-color: #f8d7da;
    border: 1px solid #f5c6cb;
    padding: 10px;
    border-radius: 8px;
    margin-bottom: 15px; 
    font-weight: bold;
    text-align: center;
}

.user-info-card {
    position: fixed; 
    top: 20px; 
    left: 50%; 
    transform: translateX(-50%); 
    
    background-color: #d4edda;
    color: #155724; 
    border: 1px solid #c3e6cb; 
    border-radius: 8px;
    padding: 15px 20px; 
    box-shadow: 0 4px 8px rgba(0, 0, 0, 0.1);
    z-index: 2000; 
    max-width: 300px; 
    width: 90%; 
    text-align: left;
}


@keyframes fadein {
    from { opacity: 0; transform: translateY(-20px); }
    to { opacity: 1; transform: translateY(0); }
}

@keyframes fadeout {
    from { opacity: 1; }
    to { opacity: 0; visibility: hidden; }
}
/* New: Copy Success Message Style */
#copy-notification {
    position: fixed; top: 10px; right: 50%; transform: translateX(50%);
    background-color: var(--success); color: white; padding: 8px 15px;
    border-radius: 5px; z-index: 2000; font-size: 0.9em;
    opacity: 0; transition: opacity 0.5s;
}

text {
  
  font-size: 15px;
  margin-Top: 0px;
}
/* 💡 NEW: Contact Link Style */
.contact-link {
    margin-top: 15px;
    font-size: 0.9em;
    font-weight: 500;
}
.contact-link a {
    color: var(--primary-dark);
    text-decoration: none;
    font-weight: bold;
    transition: color 0.2s;
}
.contact-link a:hover {
    color: var(--primary);
    text-decoration: underline;
}

</style>
<script>
    // 💡 ULTIMATE FIX: JavaScript function for copy-to-clipboard with Fallback (Re-applied)
    function copyToClipboard(elementId) {
        const copyText = document.getElementById(elementId);
        if (!copyText) return;
        
        const notification = document.getElementById('copy-notification');
        const showNotification = () => {
            notification.innerText = 'Server IP ကို ကူးပြီးပါပြီ';
            notification.style.opacity = 1;
            setTimeout(() => {
                notification.style.opacity = 0;
            }, 2000);
        };
        
        // 1. New Clipboard API (Requires HTTPS or localhost)
        if (navigator.clipboard && navigator.clipboard.writeText) {
            navigator.clipboard.writeText(copyText.value).then(showNotification).catch(err => {
                // If New API fails (e.g., due to HTTP), fall back
                fallbackCopy(copyText, showNotification);
            });
        } else {
            // 2. Fallback using execCommand (Works better on HTTP/older browsers)
            fallbackCopy(copyText, showNotification);
        }
    }

    function fallbackCopy(copyText, onSuccess) {
        let isCopied = false;
        try {
            // Select the text field
            copyText.select();
            // For mobile devices: ensure the selection range covers all text
            copyText.setSelectionRange(0, 99999); 
            
            // Copy the text inside the text field
            isCopied = document.execCommand('copy');

            if (isCopied) {
                onSuccess();
            } else {
                console.error('Copy failed using execCommand');
            }
        } catch (err) {
            console.error('Fallback copy failed: ', err);
        }
    }
</script>

</head><body>

{% if not authed %}
    <div class="login-container">
        <div class="profile-image-container">
            <img src="{{logo}}" alt="Profile" class="profile-image">
        </div>
        <h1>ZIVPN Panel</h1>
        <br>
        {% if IP %}
        <p class="login-ip-display">Server IP: {{ IP }}</p>
        {% endif %}
        
        <p class="panel-title">Login to Admin Dashboard</p>
        
        {% if err %}<div class="err">{{err}}</div>{% endif %} <form action="/login" method="POST" class="login-form">
            <div class="input-group">
                <label for="username" style="display:none;">Username</label>
                <div class="input-field-wrapper">
                    <i class="icon">🔑</i>
                    <input type="text" id="username" name="u" placeholder="Username" required>
                </div>
            </div>
            <div class="input-group">
                <label for="password" style="display:none;">Password</label>
                <div class="input-field-wrapper">
                    <i class="icon">🔒</i>
                    {# 💡 FIX: Change type="password" to type="text" to display password #}
                    <input type="text" id="password" name="p" placeholder="Password" required> 
                </div>
            </div>
            <button type="submit" class="login-button">Login</button>
        </form>
        
        {# 💡 NEW: Contact Link ကို ဒီမှာ ထည့်သွင်းပြသခြင်း #}
        {% if contact_link %}
        <p class="contact-link"><i class="icon">🗨️</i><a href="{{ contact_link }}" target="_blank">Admin ကို ဆက်သွယ်ပါ</a></p>
        {% endif %}
    </div>
{% else %}

   <header class="main-header">
        <div class="header-logo">
            <a href="/">ZIVPN<span class="highlight"> Panel</span></a>
        </div>
    </header>
    
    <div id="copy-notification"></div> <div class="boxa1">
        <div class="info-card">
            <i class="icon">💡</i> လက်ရှိ Member User စုစုပေါင်း<br><span>{{ total_users }}</span>ယောက်
        </div>
        
    <script>
        {% if msg and '{' in msg and '}' in msg %}
        try {
            const data = JSON.parse('{{ msg | safe }}');
            if (data.user) { 
                const card = document.createElement('div');
                card.className = 'user-info-card';
                // Check if the message is from /edit or /edit_expires or /edit_limit route
                if (data.message) {
                    card.innerHTML = data.message;
                } else {
                    // Message from /add route
                    card.innerHTML = `
                        <h4>✅ အကောင့်အသစ် ဖန်တီးပြီးပါပြီ</h4>
                        <p><i class="icon">🔥</i> Server IP: <b>${data.ip || '{{ IP }}'}</b></p>  
                        <p><i class="icon">👤</i> Username: <b>${data.user}</b></p>
                        <p><i class="icon">🔑</i> Password: <b>${data.password}</b></p>
                        <p><i class="icon">⏰</i> Expires: <b>${data.expires || 'N/A'}</b></p>
                        <p><i class="icon">👥</i> Limit: <b>${data.limit_count || '1'}</b></p> {# 💡 Added Limit Count #}
                    `;
                }
                
                document.body.appendChild(card);
                
                setTimeout(() => {
                    if (card.parentNode) {
                        card.parentNode.removeChild(card);
                    }
                }, 20000); 
            }
        } catch (e) {
            console.error("Error parsing message JSON:", e);
        }
        {% endif %}
    </script>


    <form method="post" action="/add" class="">
        <h2 class="section-title"><i class="icon">➕</i> Add new user</h2>
        {% if err %}<div class="err">{{err}}</div>{% endif %}
  
        <div class="input-group">
            <label for="username" style="display:none;">Username</label>
            <div class="input-field-wrapper">
                <i class="icon">👤</i>
                <input type="text" id="username" name="user" placeholder="Username" required>
            </div>
        </div>
        <div class="input-group">
            <label for="password" style="display:none;">Password</label>
            <div class="input-field-wrapper">
                <i class="icon">🔑</i>
                <input type="password" id="password" name="password" placeholder="Password" required>
            </div>
        </div>
        <div class="row">
            <div>
            <text> <label><i class="icon"></i>Add (expiration date)</label></text>
            <tak1>  <div class="input-field-wrapper">
                <i class="icon">🗓️</i>
                <input name="expires" required placeholder="Example : 2025-12-31 or 30">
            </div></tak1>
            </div>
            
            {# 💡 NEW INPUT FIELD: Limit Count #}
            <div>
            <text> <label><i class="icon"></i>User Limit Count</label></text>
            <div class="input-field-wrapper">
                <i class="icon">👥</i>
                <input type="number" name="limit_count" placeholder="အများဆုံး သုံးစွဲသူအရေအတွက် (1-10)" min="1" max="10" value="1" required>
            </div>
            </div>
            
        </div>
        <div class="input-group">
            <label><i class="icon"></i>Server IP (Click to Copy)</label> 
            <div class="input-field-wrapper">
                <i class="icon">📡</i>
                <input name="ip" id="server-ip-input" placeholder="ip" value="{{ IP }}" readonly onclick="copyToClipboard('server-ip-input')">
            </div>
        </div>

        <button class="save-btn" type="submit">Create Account</button>
    </form>
    </div> <nav class="bottom-nav">
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


{% endif %}
</body></html>"""

app = Flask(__name__, template_folder="/etc/zivpn/templates")

# Secret & Admin credentials (via env)
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
                "limit_count": int(u.get("limit_count", 1)) # 💡 NEW: Load Limit Count (default to 1)
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
    # Check for recent conntrack entries for the specific port
    out=subprocess.run(f"conntrack -L -p udp 2>/dev/null | grep 'dport={port}\\b'",
                       shell=True, capture_output=True, text=True).stdout
    return bool(out)
  except Exception:
    return False

# 💡 NEW FUNCTION: Get the number of unique source IPs connected to a user's port
def get_user_online_count(port):
    if not port: return 0
    try:
        # Get conntrack entries for the specific port
        result = subprocess.run(f"conntrack -L -p udp 2>/dev/null | grep 'dport={port}\\b'",
                                shell=True, capture_output=True, text=True).stdout
        
        # Regex to find the source IP (src=...) from the conntrack output line
        # Example output: udp 17 29 src=1.2.3.4 dst=5.6.7.8 sport=5000 dport=6001 [UNREPLIED] src=5.6.7.8 dst=1.2.3.4 sport=6001 dport=5000 [ASSURED] mark=0 zone=0 use=1
        # The first 'src=' is the client's source IP
        source_ips = re.findall(r'src=(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})', result)
        
        # Count unique IPs that are NOT the server's own IP (to avoid counting NAT loopback or internal communication)
        # 💡 FIX: get_server_ip() returns a single string, compare against it.
        server_ip_single = SERVER_IP_FALLBACK.split()[0]
        unique_online_ips = set(ip for ip in source_ips if ip != server_ip_single)

        return len(unique_online_ips)
    except Exception:
        return 0
    
# Function to get the count of non-expired users
def get_total_active_users():
    users = load_users()
    today_date = date.today() # 💡 Use date.today()
    active_count = 0
    for user in users:
        expires_str = user.get("expires")
        is_expired = False
        if expires_str:
            try:
                # 💡 FIX: Expires date is strictly less than today's date
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
        today = date.today() # 💡 Use date.today()
        remaining_days = (expires_date - today).days
        
        # 💡 FIX: Yellow pill if it expires on Today or Tomorrow (0 or 1 days left). Expiration day is the LAST valid day.
        # remaining_days = 0 means it expires TODAY (23:59:59)
        # remaining_days = 1 means it expires TOMORROW
        return 0 <= remaining_days <= 1
    except ValueError:
        return False
    
# 💡 NEW FUNCTION: Calculate days remaining
def calculate_days_remaining(expires_str):
    if not expires_str:
        return None
    try:
        expires_date = datetime.strptime(expires_str, "%Y-%m-%d").date()
        today = date.today()
        # The expiration day is the last valid day, so we want to count how many days *including* today
        # up to the expiration date. 
        remaining = (expires_date - today).days
        return remaining if remaining >= 0 else None
    except ValueError:
        return None
    
def delete_user(user):
    users = load_users()
    remaining_users = [u for u in users if u.get("user").lower() != user.lower()]
    save_users(remaining_users)
    sync_config_passwords(mode="mirror")
    
# 💡 DELETION LOGIC (Standard): Deletes users whose expiration date is before today (at 00:00:00 of the following day)
def check_user_expiration():
    users = load_users()
    today_date = date.today() # 💡 Use date.today()
    users_to_keep = []
    deleted_count = 0
    
    for user in users:
        expires_str = user.get("expires")
        is_expired = False
        if expires_str:
            try:
                # 💡 FIX: Delete if expiration date is strictly before today's date
                # If expires='2025-10-23', it is deleted only on 2025-10-24 (since 2025-10-23 < 2025-10-24 is FALSE)
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
  
  today_date = date.today() # 💡 Use date.today()
  valid_passwords = set()
  for u in users:
      expires_str = u.get("expires")
      is_valid = True
      if expires_str:
          try:
              # 💡 FIX: Expiration check for VPN Passwords
              if datetime.strptime(expires_str, "%Y-%m-%d").date() < today_date:
                  is_valid = False
          except ValueError:
              is_valid = True 

      # 💡 NEW: Online Count check (Users over limit are NOT removed from passwords.json 
      # but are visually flagged in the web panel. The actual blocking is done by the firewall/OS 
      # which is what conntrack tracks. We only remove expired users from the passwords list).
      
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
    users = load_users() # Reload after expiration check
    view=[]
    today_date = date.today()
    for u in users:
      expires_date_obj = None
      if u.get("expires"):
          try: expires_date_obj = datetime.strptime(u.get("expires"), "%Y-%m-%d").date()
          except ValueError: pass
      
      online_count = get_user_online_count(u.get("port","")) # 💡 Get online count
      limit_count = int(u.get("limit_count", 1)) # 💡 Get limit count (default to 1)
      is_over_limit = online_count > limit_count # 💡 Check if over limit
          
      view.append(type("U",(),{
        "user":u.get("user",""),
        "password":u.get("password",""),
        "expires":u.get("expires",""),
        "expires_date": expires_date_obj, # 💡 New field for comparison
        "days_remaining": calculate_days_remaining(u.get("expires","")), # 💡 New field for display
        "port":u.get("port",""),
        "online_count": online_count, # 💡 Online Count
        "limit_count": limit_count, # 💡 Limit Count
        "is_over_limit": is_over_limit, # 💡 Over Limit status
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
                                contact_link=CONTACT_LINK) # 💡 Added Contact Link
    
    # Run expiration check and get the total count
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
    
    view, today_str, today_date = prepare_user_data() # 💡 Get today_date object
    
    msg_data = session.pop("msg", None)
    err_data = session.pop("err", None) # 💡 Get the error data

    return render_template("users_table_wrapper.html", 
                           users=view, 
                           today=today_str, # Passed as string for compatibility (though not used in table)
                           today_date=today_date, # 💡 Passed as object for comparison in template
                           logo=LOGO_URL, 
                           IP=SERVER_IP_FALLBACK,
                           msg=msg_data, 
                           err=err_data) # 💡 Pass the error data to the template


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
  # GET
  return render_template_string(HTML, 
                                authed=False, 
                                logo=LOGO_URL, 
                                err=session.pop("login_err", None), 
                                IP=SERVER_IP_FALLBACK,
                                contact_link=CONTACT_LINK) # 💡 Added Contact Link

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
  limit_count_str=(request.form.get("limit_count") or "1").strip() # 💡 NEW: Get Limit Count
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

  # 💡 NEW FIX: Myanmar Unicode Check (Myanmar Unicode Range U+1000 to U+109F)
  myanmar_chars_pattern = re.compile(r'[\u1000-\u109F]')
  if myanmar_chars_pattern.search(user) or myanmar_chars_pattern.search(password):
      session["err"] = "❌ User Name သို့မဟုတ် Password တွင် မြန်မာစာလုံးများ ပါဝင်၍ မရပါ။ (English, Numbers သာ ခွင့်ပြုသည်)"
      return redirect(url_for('index'))
  # 💡 END NEW FIX

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
      u["password"]=password; u["expires"]=expires; u["port"]=port; u["limit_count"]=limit_count; replaced=True; break # 💡 NEW: Update limit_count
  if not replaced:
    # 💡 NEW FIX: Pick a free port if not provided (Important for conntrack tracking)
    if not port:
        port = pick_free_port()
        if not port:
            session["err"] = "❌ အသုံးပြုရန် Port မရှိတော့ပါ"
            return redirect(url_for('index'))
            
    users.append({"user":user,"password":password,"expires":expires,"port":port, "limit_count":limit_count}) # 💡 NEW: Add limit_count
  
  save_users(users)
  sync_config_passwords()

  msg_dict = {
      "user": user,
      "password": password,
      "expires": expires,
      "ip": ip,
      "limit_count": limit_count # 💡 Add limit_count to message
  }
  
  session["msg"] = json.dumps(msg_dict)
  return redirect(url_for('index'))

# 💡 NEW ROUTE: Edit Expiration Date
@app.route("/edit_expires", methods=["POST"])
def edit_user_expires():
  if not require_login(): return redirect(url_for('login'))
  user=(request.form.get("user") or "").strip()
  new_expires=(request.form.get("expires") or "").strip()
  
  if not user or not new_expires:
    session["err"] = "User Name နှင့် Expiration Date အသစ် မပါဝင်ပါ"
    return redirect(url_for('users_table_view'))
  
  # Convert days to date if a number is provided
  if new_expires.isdigit():
    new_expires=(datetime.now() + timedelta(days=int(new_expires))).strftime("%Y-%m-%d")

  # Validate the date format
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
# 💡 END NEW ROUTE

# 💡 NEW ROUTE: Edit Limit Count
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
  # No need to restart zivpn, only web panel needs to see the new limit for display/flagging.
  
  session["msg"] = json.dumps({"ok":True, "message": f"<h4>✅ **{user}** ရဲ့ Limit ကို **{new_limit}** ယောက် သို့ ပြောင်းပြီးပါပြီ။</h4>", "user":user})
  return redirect(url_for('users_table_view'))
# 💡 END NEW ROUTE

# 💡 EXISTING ROUTE: Password Edit Function (MODIFIED for Myanmar Char Check)
@app.route("/edit", methods=["POST"])
def edit_user_password():
  if not require_login(): return redirect(url_for('login'))
  user=(request.form.get("user") or "").strip()
  new_password=(request.form.get("password") or "").strip()
  
  if not user or not new_password:
    session["err"] = "User Name နှင့် Password အသစ် မပါဝင်ပါ"
    # ❌ FIX: users_table_view သို့ redirect ပြန်လုပ်ပါ
    return redirect(url_for('users_table_view'))
    
  # 💡 NEW FIX: Myanmar Unicode Check for New Password
  myanmar_chars_pattern = re.compile(r'[\u1000-\u109F]')
  if myanmar_chars_pattern.search(new_password):
      session["err"] = "❌ Password အသစ်တွင် မြန်မာစာလုံးများ ပါဝင်၍ မရပါ။ (English, Numbers သာ ခွင့်ပြုသည်)"
      # ❌ FIX: users_table_view သို့ redirect ပြန်လုပ်ပါ
      return redirect(url_for('users_table_view')) 
  # 💡 END NEW FIX

  users=load_users(); replaced=False
  for u in users:
    if u.get("user","").lower()==user.lower():
      u["password"]=new_password 
      replaced=True
      break
      
  if not replaced:
    session["err"] = f"❌ User **{user}** ကို ရှာမတွေ့ပါ"
    # ❌ FIX: users_table_view သို့ redirect ပြန်လုပ်ပါ
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
      u["online_count"]=get_user_online_count(u.get("port","")) # 💡 API Update
      u["limit_count"]=int(u.get("limit_count",1)) # 💡 API Update
      u["is_over_limit"] = u["online_count"] > u["limit_count"] # 💡 API Update
    return jsonify(users)
  
  if request.method=="POST":
    data=request.get_json(silent=True) or {}
    user=(data.get("user") or "").strip()
    password=(data.get("password") or "").strip()
    expires=(data.get("expires") or "").strip()
    port=str(data.get("port") or "").strip()
    limit_count_str=(data.get("limit_count") or "1").strip() # 💡 NEW: Get Limit Count

    try:
      limit_count = int(limit_count_str)
      if not (1 <= limit_count <= 10):
          return jsonify({"ok": False, "err": "limit_count must be between 1 and 10"}), 400
    except ValueError:
      return jsonify({"ok": False, "err": "invalid limit_count"}), 400

    
    # 💡 NEW FIX: Myanmar Unicode Check for API
    myanmar_chars_pattern = re.compile(r'[\u1000-\u109F]')
    if myanmar_chars_pattern.search(user) or myanmar_chars_pattern.search(password):
        return jsonify({"ok": False, "err": "Myanmar characters not allowed in user or password"}), 400
    # 💡 END NEW FIX

    if expires.isdigit():
      expires=(datetime.now()+timedelta(days=int(expires))).strftime("%Y-%m-%d")
    if not user or not password: return jsonify({"ok":False,"err":"user/password required"}),400
    if port and (not re.fullmatch(r"\d{2,5}",port) or not (6000<=int(port)<=19999)):
      return jsonify({"ok":False,"err":"invalid port"}),400
      
    users=load_users(); replaced=False
    for u in users:
      if u.get("user","").lower()==user.lower():
        u["password"]=password; u["expires"]=expires; u["port"]=port; u["limit_count"]=limit_count; replaced=True; break # 💡 NEW: Update limit_count
    if not replaced:
      # 💡 NEW FIX: Pick a free port if not provided (API)
      if not port:
          port = pick_free_port()
          if not port:
              return jsonify({"ok": False, "err": "No free port available"}), 500
      users.append({"user":user,"password":password,"expires":expires,"port":port, "limit_count":limit_count}) # 💡 NEW: Add limit_count
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

# ===== FIX: User Limit Enforcement Script + Cron Job =====
LIMIT_ENFORCER_SCRIPT="/etc/zivpn/limit_enforcer.sh"
echo -e "${Y}🛡️ User Limit Enforcement Script (limit_enforcer.sh) ကို ဖန်တီးနေပါတယ် (User ကန့်သတ်ချက် အမှန်တကယ် အလုပ်လုပ်စေရန်)...${Z}"

# This script runs every minute, clears old rules, and blocks ports where conntrack entries > limit.
cat >"$LIMIT_ENFORCER_SCRIPT" <<'ENFORCER_SHELL'
#!/bin/bash
# ZIVPN User Limit Enforcer - Checks connection count via conntrack and enforces limit via iptables.
set -euo pipefail

USERS_FILE="/etc/zivpn/users.json"
CHAIN_NAME="ZIVPN_LIMIT_ENFORCER"
SERVER_IP=$(hostname -I | awk '{print $1}') # Get the server's main IP

# --- Conntrack-based Online Count Function ---
# Counts the number of UNIQUE SOURCE IPs connected to the specific dport.
get_online_count() {
    local port="$1"
    local server_ip="$2"
    
    # 1. List conntrack entries for the specific dport
    # 2. Filter for the client's source IP (the first 'src=' in the line)
    # 3. Exclude the server's own IP (in case of NAT loopback/local traffic)
    # 4. Sort and count unique IPs
    
    conntrack -L -p udp 2>/dev/null | 
    grep "dport=${port}\b" | 
    awk '{ 
        for(i=1; i<=NF; i++) {
            if ($i ~ /^src=[0-9.]*$/) {
                split($i, a, "="); 
                if (a[2] != "'"$server_ip"'") {
                    print a[2]; 
                    next;
                }
            }
        }
    }' |
    sort -u | 
    wc -l
}

# --- IPTables Management ---
setup_iptables() {
    # Check if the custom chain exists, if not, create and link it from INPUT
    if ! iptables -L "$CHAIN_NAME" -n > /dev/null 2>&1; then
        echo "Setting up $CHAIN_NAME chain..." >&2
        iptables -N "$CHAIN_NAME"
        # Link the custom chain from the main INPUT chain (for incoming connections to the VPN port)
        # Check if the jump rule exists before inserting it
        if ! iptables -C INPUT -p udp -j "$CHAIN_NAME" > /dev/null 2>&1; then
            iptables -I INPUT -p udp -j "$CHAIN_NAME"
        fi
    fi
}

clear_iptables_rules() {
    # Delete all rules from the custom chain
    iptables -F "$CHAIN_NAME" || true
}

# --- Main Logic ---
setup_iptables
clear_iptables_rules

# Get active users with port and limit (excluding expired users via jq)
USERS=$(jq -r '.[] | select(.expires == null or (.expires | fromdateiso8601 | now | . < . )) | "\(.user):\(.port):\(.limit_count)"' "$USERS_FILE" 2>/dev/null || echo "")

if [ -z "$USERS" ]; then
    exit 0
fi

for USER_DATA in $USERS; do
    USER=$(echo "$USER_DATA" | cut -d: -f1)
    PORT=$(echo "$USER_DATA" | cut -d: -f2)
    LIMIT=$(echo "$USER_DATA" | cut -d: -f3)
    
    # Default limit is 1 if not set or invalid
    if ! [[ "$LIMIT" =~ ^[0-9]+$ ]] || [ "$LIMIT" -lt 1 ]; then
        LIMIT=1
    fi

    if [ -n "$PORT" ]; then
        ONLINE_COUNT=$(get_online_count "$PORT" "$SERVER_IP")

        if [ "$ONLINE_COUNT" -gt "$LIMIT" ]; then
            # Block the port if over limit: Add a DROP rule to the custom chain
            # This DROP rule in the INPUT chain will immediately block new incoming traffic to this port.
            echo "Blocking user ${USER} (Port: ${PORT}, Online: ${ONLINE_COUNT}, Limit: ${LIMIT})" >&2
            iptables -A "$CHAIN_NAME" -p udp --dport "$PORT" -m comment --comment "ZIVPN_LIMIT_BLOCK_${USER}" -j DROP
        fi
    fi
done

exit 0
ENFORCER_SHELL

chmod +x "$LIMIT_ENFORCER_SCRIPT"

# --- Cron Job Setup ---
echo -e "${Y}⏱️ User Limit Enforcement Cron Job ကို ထည့်သွင်းနေပါတယ် (တစ်မိနစ်လျှင် တစ်ခါ)...${Z}"

# Remove old cron entry if it exists
crontab -l 2>/dev/null | grep -v "${LIMIT_ENFORCER_SCRIPT}" | crontab - 2>/dev/null || true

# Add new cron entry
(crontab -l 2>/dev/null; echo "* * * * * ${LIMIT_ENFORCER_SCRIPT} >/dev/null 2>&1") | crontab -

# ===== Networking: forwarding + DNAT + MASQ + UFW (unchanged) =====
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

ufw allow 5667/udp >/dev/null 2>&1 || true
ufw allow 6000:19999/udp >/dev/null 2>&1 || true
ufw allow 8080/tcp >/dev/null 2>&1 || true
ufw reload >/dev/null 2>&1 || true

# ===== CRLF sanitize (File တွေ အားလုံး ဖန်တီးပြီးမှ ရှင်းခြင်း) =====
echo -e "${Y}🧹 CRLF ရှင်းနေပါတယ်...${Z}"
sed -i 's/\r$//' /etc/zivpn/web.py /etc/systemd/system/zivpn.service /etc/systemd/system/zivpn-web.service /etc/zivpn/templates/users_table.html /etc/zivpn/templates/users_table_wrapper.html /etc/zivpn/limit_enforcer.sh || true

# ===== Enable services =====
systemctl daemon-reload
systemctl enable --now zivpn.service
systemctl enable --now zivpn-web.service

IP=$(hostname -I | awk '{print $1}')
echo -e "\n$LINE\n${G}✅ Done${Z}"
echo -e "${C}Web Panel (Add Users) :${Z} ${Y}http://$IP:8080${Z}"
echo -e "${C}Web Panel (User List) :${Z} ${Y}http://$IP:8080/users${Z}"
echo -e "${C}Services    :${Z} ${Y}systemctl status|systemctl restart zivpn  •  systemctl status|systemctl restart zivpn-web${Z}"
echo -e "$LINE"
