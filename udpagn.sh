#!/bin/bash

# AGN-UDP + Web Panel တစ်ခုထဲပေါင်းထားသော Script (Ubuntu အသုံးပြုပါ)
# Login စနစ်ကို Apache Basic Authentication ဖြင့် ထည့်သွင်းထားသည်

BOLD=$(tput bold)
NORMAL=$(tput sgr0)
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)

WEB_DIR="/var/www/html/agnweb"
HTPASSWD_FILE="/etc/apache2/.htpasswd"
DEFAULT_USER="admin"
DEFAULT_PASS="agnpanel123" # ⚠️ လုံခြုံရေးအတွက် ဤစကားဝှက်ကို ပြောင်းလဲသင့်ပါသည်။

# အခြေခံပြင်ဆင်ခြင်း
setup_env() {
    echo "${GREEN}Setting up environment...${NORMAL}"

    # အောက်ပါအဆင့်များကို စစ်ဆေးပါ
    if [ -f /etc/os-release ]; then
        if grep -qi ubuntu /etc/os-release; then
            echo "${GREEN}Ubuntu OS detected. Continuing...${NORMAL}"
        else
            echo "${RED}Only Ubuntu is fully supported in this script. Exiting...${NORMAL}"
            exit 1
        fi
    else
        echo "${RED}Cannot detect Ubuntu OS. Exiting...${NORMAL}"
        exit 1
    fi

    # အခြေခံပိုင်းများ install
    # apache2-utils ကို htpasswd အတွက် ထည့်သွင်း
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl jq apache2 php php-curl php-cli php-mbstring ufw apache2-utils

    # အဆင့်မြင့်ပိုင်းများ
    sudo systemctl enable apache2
    sudo systemctl start apache2
}

# AGN-UDP ကို install
install_agnudp() {
    echo "${GREEN}Installing AGN-UDP...${NORMAL}"
    if [ -f agnudp_manager.sh ]; then
        echo "${YELLOW}agnudp_manager.sh already exists. Skipping download.${NORMAL}"
    else
        curl -O https://raw.githubusercontent.com/khaledagn/AGN-UDP/refs/heads/main/agnudp_manager.sh
        chmod +x agnudp_manager.sh
    fi
    # AGN-UDP install ကို run မလုပ်ခင် agnudp_manager.sh သည် root ဖြင့် run ရမည့် အခြေအနေရှိနိုင်သောကြောင့် sudo ဖြင့် ခေါ်သည်
    sudo ./agnudp_manager.sh install
}

# Web panel ကို ဖန်တီးပေး
setup_web_panel() {
    echo "${GREEN}Setting up AGN-UDP Web Panel...${NORMAL}"
    
    sudo mkdir -p $WEB_DIR

    # index.php ဖိုင်ထည့်ပေး (Login ထည့်ပြီးနောက်ပိုင်းတွင် ဤဖိုင်ကို အရင်ခေါ်မည့်အစား /var/www/html/agnweb/index.php သို့ ပြောင်းလိုက်ပါ)
    echo "<?php
// AGN-UDP Service Status 
header('Content-Type: application/json');

// agnudp_manager သည် sudo ဖြင့် ခေါ်ယူရန် လိုအပ်သည့်အတွက် www-data အား sudo ခွင့်ပြုချက် ပေးထားရပါမည်။
// sudo visudo တွင် www-data ALL=(ALL) NOPASSWD: /usr/bin/agnudp_manager
\$output = shell_exec('sudo /usr/bin/agnudp_manager --status 2>&1');
echo json_encode(['status' => trim(\$output)]);
" | sudo tee $WEB_DIR/index.php > /dev/null

    # Apache Basic Authentication အတွက် .htaccess နှင့် .htpasswd ဖန်တီး
    echo "${GREEN}Setting up Basic Authentication (Login)...${NORMAL}"

    # .htpasswd ဖိုင် ဖန်တီး (admin/agnpanel123 ဖြင့်)
    # စကားဝှက်ကို လုံခြုံရေးအရ ပြောင်းလဲပါ
    if ! sudo htpasswd -b -c $HTPASSWD_FILE $DEFAULT_USER $DEFAULT_PASS; then
        echo "${RED}Failed to create .htpasswd file. Exiting...${NORMAL}"
        exit 1
    fi
    
    # .htaccess ဖိုင် ဖန်တီး
    sudo tee $WEB_DIR/.htaccess > /dev/null <<EOL
AuthType Basic
AuthName "AGN-UDP Panel Login"
AuthUserFile $HTPASSWD_FILE
Require valid-user
EOL

    # Directory Permission ပြင်ဆင်
    sudo chown -R www-data:www-data $WEB_DIR
    sudo chmod -R 755 $WEB_DIR

    # Apache config (AllowOverride All သေချာစေရန်)
    sudo tee /etc/apache2/sites-available/agnweb.conf > /dev/null <<EOL
<VirtualHost *:80>
    ServerAdmin admin@example.com
    DocumentRoot $WEB_DIR
    ServerName localhost

    <Directory $WEB_DIR>
        Options Indexes FollowSymLinks
        AllowOverride All  # 👈 .htaccess ကို ခွင့်ပြုရန်
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/agnweb_error.log
    CustomLog \${APACHE_LOG_DIR}/agnweb_access.log combined
</VirtualHost>
EOL
    
    # Apache module mod_authn_file နှင့် mod_auth_basic နှင့် mod_rewrite ကို ဖွင့်
    sudo a2enmod auth_basic authn_file rewrite
    
    # Virtual Host ဖွင့် နှင့် Apache Restart
    sudo a2ensite agnweb.conf
    sudo systemctl restart apache2
}

# Web service systemd ဖန်တီးပေး (Apache သုံးမှာဖြစ်တဲ့အတွက် ဒီအပိုင်းကို ဖယ်ထုတ်လိုက်ပါမယ်။)
# မူရင်း script တွင် PHP Built-in Server ကို port 80 တွင် Apache နှင့် ထပ်နေအောင် လုပ်ထား၍ ဖြုတ်လိုက်သည်။
# Apache သည် systemd ကို သုံးပြီးသားဖြစ်ပါသည်။
# setup_systemd_service() { ... }

# www-data အား agnudp_manager ကို password မလိုဘဲ run ခွင့်ပြုရန်
grant_sudo_for_wwwdata() {
    echo "${GREEN}Granting 'www-data' user NOPASSWD access to agnudp_manager...${NORMAL}"
    # agnudp_manager သည် /usr/bin/ တွင် ရှိရမည်ဟု ယူဆသည်။
    AGNUDP_MANAGER_PATH=$(which agnudp_manager 2>/dev/null)
    
    if [ -z "$AGNUDP_MANAGER_PATH" ]; then
        echo "${YELLOW}agnudp_manager path not found in PATH. Assuming /usr/bin/agnudp_manager.${NORMAL}"
        AGNUDP_MANAGER_PATH="/usr/bin/agnudp_manager"
    fi

    # visudo ထဲတွင် ထည့်သွင်းရန်
    # www-data ALL=(ALL) NOPASSWD: /usr/bin/agnudp_manager
    echo "www-data ALL=(ALL) NOPASSWD: $AGNUDP_MANAGER_PATH" | sudo tee /etc/sudoers.d/agnudp_wwwdata > /dev/null
    sudo chmod 0440 /etc/sudoers.d/agnudp_wwwdata
}

# စားသုံးနေသည့်အခြေခံပိုင်းများ
main() {
    setup_env
    install_agnudp
    grant_sudo_for_wwwdata # www-data ကို sudo ခွင့်ပြုချက် ပေးသည်
    setup_web_panel        # Apache နှင့် Login ကို set up လုပ်သည်
    # setup_systemd_service သည် Apache နှင့် ထပ်နေ၍ ဖြုတ်လိုက်ပါသည်။

    echo ""
    echo "${GREEN}✅ AGN-UDP Web Panel အောင်မြင်စွာ ထည့်သွင်းပြီးပါပြီ။${NORMAL}"
    echo "===================================================================="
    echo "${BOLD}🌐 Web Panel လင့်ခ်: ${YELLOW}http://your_vps_ip/agnweb${NORMAL}"
    echo "${BOLD}🔒 Panel Login Info:${NORMAL}"
    echo "   ${BOLD}Username:${NORMAL} ${GREEN}$DEFAULT_USER${NORMAL}"
    echo "   ${BOLD}Password:${NORMAL} ${GREEN}$DEFAULT_PASS${NORMAL} ${RED}(⚠️ အမြန်ဆုံးပြောင်းလဲပါ)${NORMAL}"
    echo "===================================================================="
    echo "🔧 သုံးပြီးသော အခြေခံအချက်များ: Apache + PHP + Basic Auth (.htaccess)"
}

main
