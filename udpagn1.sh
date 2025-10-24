#!/bin/bash

# AGN-UDP Web Panel Management Script
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}Error: This script must be run as root${NC}"
   exit 1
fi

# Default configuration
CONFIG_FILE="/etc/agnudp/config.json"
SERVICE_FILE="/etc/systemd/system/agnudp.service"
LOG_FILE="/var/log/agnudp.log"
WEB_PORT="8080"
WEB_USER="admin"
WEB_PASS=$(date +%s | sha256sum | base64 | head -c 16)

# Install required packages
install_dependencies() {
    echo -e "${YELLOW}Installing dependencies...${NC}"
    apt-get update
    apt-get install -y curl wget net-tools ufw jq
}

# Install AGN-UDP
install_agnudp() {
    echo -e "${YELLOW}Installing AGN-UDP...${NC}"
    
    # Download binary
    LATEST_RELEASE=$(curl -s https://api.github.com/repos/khaledagn/AGN-UDP/releases/latest | grep browser_download_url | cut -d '"' -f 4)
    
    if [ -z "$LATEST_RELEASE" ]; then
        echo -e "${RED}Error: Could not find AGN-UDP release${NC}"
        exit 1
    fi
    
    wget -O /usr/local/bin/agnudp $LATEST_RELEASE
    chmod +x /usr/local/bin/agnudp
    
    # Create config directory
    mkdir -p /etc/agnudp
    
    # Create initial config
    cat > $CONFIG_FILE << EOF
{
    "server": {
        "listen": ":443",
        "cert": "/etc/agnudp/cert.pem",
        "key": "/etc/agnudp/key.pem"
    },
    "users": {}
}
EOF
    
    # Generate self-signed certificate
    openssl req -x509 -newkey rsa:4096 -keyout /etc/agnudp/key.pem -out /etc/agnudp/cert.pem -days 365 -nodes -subj "/CN=localhost"
    
    echo -e "${GREEN}AGN-UDP installed successfully${NC}"
}

# Create systemd service
create_service() {
    echo -e "${YELLOW}Creating systemd service...${NC}"
    
    cat > $SERVICE_FILE << EOF
[Unit]
Description=AGN-UDP Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/etc/agnudp
ExecStart=/usr/local/bin/agnudp -config $CONFIG_FILE
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable agnudp
    echo -e "${GREEN}Systemd service created${NC}"
}

# Web interface setup
setup_web_interface() {
    echo -e "${YELLOW}Setting up web interface...${NC}"
    
    # Create web directory
    WEB_DIR="/var/www/agnudp"
    mkdir -p $WEB_DIR
    
    # Create simple web interface
    cat > $WEB_DIR/index.html << EOF
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AGN-UDP Manager</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 40px; background: #f4f4f4; }
        .container { max-width: 1000px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; }
        .header { text-align: center; margin-bottom: 30px; }
        .stats { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; margin-bottom: 30px; }
        .stat-box { background: #e3f2fd; padding: 20px; border-radius: 5px; text-align: center; }
        .form-group { margin-bottom: 15px; }
        label { display: block; margin-bottom: 5px; font-weight: bold; }
        input { width: 100%; padding: 8px; border: 1px solid #ddd; border-radius: 4px; }
        button { background: #2196f3; color: white; padding: 10px 20px; border: none; border-radius: 4px; cursor: pointer; }
        table { width: 100%; border-collapse: collapse; margin-top: 20px; }
        th, td { padding: 12px; text-align: left; border-bottom: 1px solid #ddd; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>AGN-UDP Manager</h1>
            <p>Web Management Panel</p>
        </div>
        
        <div class="stats">
            <div class="stat-box">
                <h3>Active Users</h3>
                <p id="userCount">0</p>
            </div>
            <div class="stat-box">
                <h3>Total Traffic</h3>
                <p id="totalTraffic">0 MB</p>
            </div>
            <div class="stat-box">
                <h3>Server Status</h3>
                <p id="serverStatus">Loading...</p>
            </div>
        </div>

        <div>
            <h2>Add New User</h2>
            <form id="userForm">
                <div class="form-group">
                    <label for="username">Username:</label>
                    <input type="text" id="username" required>
                </div>
                <div class="form-group">
                    <label for="password">Password:</label>
                    <input type="password" id="password" required>
                </div>
                <div class="form-group">
                    <label for="limit">Data Limit (MB):</label>
                    <input type="number" id="limit" value="1000">
                </div>
                <button type="submit">Add User</button>
            </form>
        </div>

        <div>
            <h2>User List</h2>
            <table id="userTable">
                <thead>
                    <tr>
                        <th>Username</th>
                        <th>Used Traffic</th>
                        <th>Data Limit</th>
                        <th>Actions</th>
                    </tr>
                </thead>
                <tbody></tbody>
            </table>
        </div>
    </div>

    <script>
        // JavaScript code for the web interface would go here
        // This would handle API calls to the backend
        console.log("AGN-UDP Web Interface Loaded");
    </script>
</body>
</html>
EOF
    
    # Install simple HTTP server if needed
    if ! command -v python3 &> /dev/null; then
        apt-get install -y python3
    fi
    
    # Create startup script for web server
    cat > /usr/local/bin/agnudp-web << EOF
#!/bin/bash
cd $WEB_DIR
python3 -m http.server $WEB_PORT
EOF
    
    chmod +x /usr/local/bin/agnudp-web
    
    # Create web service
    cat > /etc/systemd/system/agnudp-web.service << EOF
[Unit]
Description=AGN-UDP Web Interface
After=network.target

[Service]
Type=simple
User=root
ExecStart=/usr/local/bin/agnudp-web
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable agnudp-web
    systemctl start agnudp-web
    
    echo -e "${GREEN}Web interface setup complete${NC}"
    echo -e "${BLUE}Web URL: http://$(curl -s ifconfig.me):$WEB_PORT${NC}"
    echo -e "${BLUE}Username: $WEB_USER${NC}"
    echo -e "${BLUE}Password: $WEB_PASS${NC}"
}

# Firewall configuration
setup_firewall() {
    echo -e "${YELLOW}Configuring firewall...${NC}"
    
    ufw allow 443/udp
    ufw allow $WEB_PORT/tcp
    ufw allow ssh
    
    echo -e "${GREEN}Firewall configured${NC}"
}

# Start services
start_services() {
    echo -e "${YELLOW}Starting services...${NC}"
    
    systemctl start agnudp
    systemctl start agnudp-web
    
    echo -e "${GREEN}Services started${NC}"
}

# Show status
show_status() {
    echo -e "\n${BLUE}=== AGN-UDP Status ===${NC}"
    systemctl status agnudp --no-pager -l
    echo -e "\n${BLUE}=== Web Interface Status ===${NC}"
    systemctl status agnudp-web --no-pager -l
    echo -e "\n${BLUE}Access Web Panel: http://$(curl -s ifconfig.me):$WEB_PORT${NC}"
}

# Main installation
main_install() {
    echo -e "${BLUE}Starting AGN-UDP Web Panel Installation...${NC}"
    
    install_dependencies
    install_agnudp
    create_service
    setup_web_interface
    setup_firewall
    start_services
    show_status
    
    echo -e "${GREEN}Installation completed successfully!${NC}"
}

# Check if script is called with install parameter
if [ "$1" == "install" ]; then
    main_install
else
    echo -e "${BLUE}AGN-UDP Web Panel Management Script${NC}"
    echo "Usage:"
    echo "  ./agnudp-web-panel.sh install  - Install AGN-UDP with web panel"
    echo "  systemctl status agnudp        - Check AGN-UDP status"
    echo "  systemctl status agnudp-web    - Check web panel status"
fi
