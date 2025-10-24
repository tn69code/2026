#!/bin/bash

# AGN-UDP + Web Panel တစ်ခုထဲပေါင်းထားသော Script (Ubuntu/CentOS အသုံးပြုပါ)

BOLD=$(tput bold)
NORMAL=$(tput sgr0)
GREEN=$(tput setaf 2)
RED=$(tput setaf 1)
YELLOW=$(tput setaf 3)

# အခြေခံပြင်ဆင်ခြင်း
setup_env() {
    echo "${GREEN}Setting up environment...${NORMAL}"

    # အောက်ပါအဆင့်များကို စစ်ဆေးပါ
    if [ -f /etc/os-release ]; then
        OS=$(grep -i ubuntu /etc/os-release)
        if [ -z "$OS" ]; then
            echo "${RED}Only Ubuntu is supported in this script.${NORMAL}"
            exit 1
        fi
    else
        echo "${RED}Cannot detect Ubuntu OS. Exiting...${NORMAL}"
        exit 1
    fi

    # အခြေခံပိုင်းများ install
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl jq apache2 php php-curl php-cli php-mbstring ufw

    # အဆင့်မြင့်ပိုင်းများ
    sudo systemctl enable apache2
    sudo systemctl start apache2
}

# AGN-UDP ကို install
install_agnudp() {
    echo "${GREEN}Installing AGN-UDP...${NORMAL}"
    curl -O https://raw.githubusercontent.com/khaledagn/AGN-UDP/refs/heads/main/agnudp_manager.sh
    chmod +x agnudp_manager.sh
    sudo ./agnudp_manager.sh install
}

# Web panel ကို ဖန်တီးပေး
setup_web_panel() {
    echo "${GREEN}Setting up AGN-UDP Web Panel...${NORMAL}"
    
    WEB_DIR="/var/www/html/agnweb"
    sudo mkdir -p $WEB_DIR
    sudo touch $WEB_DIR/index.php

    # index.php ဖိုင်ထည့်ပေး
    echo "<?php
header('Content-Type: application/json');
\$output = shell_exec('sudo /usr/bin/agnudp_manager --status 2>&1');
echo json_encode(['status' => \$output]);
" | sudo tee $WEB_DIR/index.php > /dev/null

    sudo chown -R www-data:www-data $WEB_DIR
    sudo chmod 755 $WEB_DIR

    # Apache config
    sudo tee /etc/apache2/sites-available/agnweb.conf > /dev/null <<EOL
<VirtualHost *:80>
    ServerAdmin admin@example.com
    DocumentRoot $WEB_DIR
    ServerName localhost

    <Directory $WEB_DIR>
        Options Indexes FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/agnweb_error.log
    CustomLog \${APACHE_LOG_DIR}/agnweb_access.log combined
</VirtualHost>
EOL

    sudo a2ensite agnweb.conf
    sudo systemctl restart apache2
}

# Web service systemd ဖန်တီးပေး
setup_systemd_service() {
    echo "${GREEN}Creating systemd service for AGN-UDP Web Panel...${NORMAL}"

    sudo tee /etc/systemd/system/agnweb.service > /dev/null <<EOL
[Unit]
Description=AGN-UDP Web Panel
After=network.target

[Service]
ExecStart=/usr/bin/php -S 0.0.0.0:80 -t /var/www/html/agnweb
User=www-data
Group=www-data
Restart=always
WorkingDirectory=/var/www/html/agnweb

[Install]
WantedBy=multi-user.target
EOL

    sudo systemctl daemon-reload
    sudo systemctl enable agnweb
    sudo systemctl start agnweb
}

# စားသုံးနေသည့်အခြေခံပိုင်းများ
main() {
    setup_env
    install_agnudp
    setup_web_panel
    setup_systemd_service

    echo "${GREEN}✅ AGN-UDP Web Panel အောင်မြင်စွာ ထည့်သွင်းပြီးပါပြီ။${NORMAL}"
    echo "🌐 အလုပ်လုပ်နေသည့် လင့်ခ်: http://your_vps_ip"
    echo "🔧 သုံးပြီးသော အခြေခံအချက်များ: Apache + PHP + systemd service"
}

main
