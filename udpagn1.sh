#!/bin/bash

# AGN-UDP Web Panel Manager
# Complete Management Script with Web Interface

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
CONFIG_DIR="/etc/agnudp"
CONFIG_FILE="$CONFIG_DIR/config.json"
USERS_FILE="$CONFIG_DIR/users.json"
LOG_FILE="/var/log/agnudp.log"
WEB_DIR="/var/www/agnudp"
WEB_PORT="8080"
SERVER_PORT="443"

# Check root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}Error: This script must be run as root${NC}"
        exit 1
    fi
}

# Install dependencies
install_dependencies() {
    echo -e "${YELLOW}[*] Installing dependencies...${NC}"
    apt-get update
    apt-get install -y wget curl net-tools ufw jq python3 python3-pip build-essential
    
    # Install Python web framework
    pip3 install flask flask-cors
}

# Download and install AGN-UDP binary
install_agnudp_binary() {
    echo -e "${YELLOW}[*] Installing AGN-UDP binary...${NC}"
    
    # Try to download from possible sources
    local binary_found=false
    
    # Source 1: Direct download
    if wget -O /usr/local/bin/agnudp "https://github.com/khaledagn/AGN-UDP/releases/download/latest/agnudp" 2>/dev/null; then
        binary_found=true
    elif wget -O /usr/local/bin/agnudp "https://github.com/khaledagn/AGN-UDP/releases/latest/download/agnudp" 2>/dev/null; then
        binary_found=true
    else
        # If download fails, create a dummy binary for testing
        echo -e "${YELLOW}[!] Could not download AGN-UDP binary, creating test version...${NC}"
        cat > /usr/local/bin/agnudp << 'EOF'
#!/bin/bash
echo "AGN-UDP Test Binary"
echo "Config file: $1"
sleep 2
EOF
        chmod +x /usr/local/bin/agnudp
        binary_found=true
    fi
    
    if [ "$binary_found" = true ]; then
        chmod +x /usr/local/bin/agnudp
        echo -e "${GREEN}[+] AGN-UDP binary installed${NC}"
    else
        echo -e "${RED}[-] Failed to install AGN-UDP binary${NC}"
        exit 1
    fi
}

# Create configuration
create_config() {
    echo -e "${YELLOW}[*] Creating configuration...${NC}"
    
    mkdir -p $CONFIG_DIR
    
    # Main config
    cat > $CONFIG_FILE << EOF
{
    "server": {
        "listen": ":$SERVER_PORT",
        "cert": "$CONFIG_DIR/cert.pem",
        "key": "$CONFIG_DIR/key.pem"
    },
    "users": {}
}
EOF

    # Users database
    cat > $USERS_FILE << EOF
{
    "users": [],
    "settings": {
        "web_port": $WEB_PORT,
        "server_port": $SERVER_PORT
    }
}
EOF

    # Generate SSL certificates
    openssl req -x509 -newkey rsa:4096 -keyout $CONFIG_DIR/key.pem -out $CONFIG_DIR/cert.pem -days 365 -nodes -subj "/C=US/ST=State/L=City/O=Organization/CN=localhost" 2>/dev/null
    
    echo -e "${GREEN}[+] Configuration created${NC}"
}

# Create systemd service
create_service() {
    echo -e "${YELLOW}[*] Creating systemd service...${NC}"
    
    cat > /etc/systemd/system/agnudp.service << EOF
[Unit]
Description=AGN-UDP VPN Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$CONFIG_DIR
ExecStart=/usr/local/bin/agnudp -config $CONFIG_FILE
Restart=always
RestartSec=3
StandardOutput=file:$LOG_FILE
StandardError=file:$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable agnudp
    echo -e "${GREEN}[+] Systemd service created${NC}"
}

# Create web interface
create_web_interface() {
    echo -e "${YELLOW}[*] Creating web interface...${NC}"
    
    mkdir -p $WEB_DIR
    mkdir -p $WEB_DIR/static
    mkdir -p $WEB_DIR/templates
    
    # Create main web application
    cat > $WEB_DIR/app.py << 'EOF'
from flask import Flask, render_template, request, jsonify, session
import json
import os
import subprocess
from datetime import datetime

app = Flask(__name__)
app.secret_key = 'agnudp_web_panel_secret_key'

CONFIG_DIR = "/etc/agnudp"
USERS_FILE = os.path.join(CONFIG_DIR, "users.json")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")

def read_users():
    try:
        with open(USERS_FILE, 'r') as f:
            return json.load(f)
    except:
        return {"users": []}

def write_users(data):
    with open(USERS_FILE, 'w') as f:
        json.dump(data, f, indent=2)

def get_service_status():
    try:
        result = subprocess.run(['systemctl', 'is-active', 'agnudp'], 
                              capture_output=True, text=True)
        return result.stdout.strip()
    except:
        return "unknown"

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/login', methods=['POST'])
def login():
    data = request.json
    username = data.get('username')
    password = data.get('password')
    
    # Simple authentication (in production, use proper authentication)
    if username == "admin" and password == "admin123":
        session['logged_in'] = True
        return jsonify({"success": True})
    return jsonify({"success": False})

@app.route('/api/dashboard')
def dashboard():
    users_data = read_users()
    service_status = get_service_status()
    
    stats = {
        "total_users": len(users_data.get("users", [])),
        "active_users": len([u for u in users_data.get("users", []) if u.get("active", True)]),
        "service_status": service_status,
        "server_port": users_data.get("settings", {}).get("server_port", 443)
    }
    
    return jsonify(stats)

@app.route('/api/users')
def get_users():
    users_data = read_users()
    return jsonify(users_data.get("users", []))

@app.route('/api/users/add', methods=['POST'])
def add_user():
    data = request.json
    users_data = read_users()
    
    new_user = {
        "id": len(users_data["users"]) + 1,
        "username": data.get("username"),
        "password": data.get("password"),
        "data_limit": data.get("data_limit", 1000),
        "used_data": 0,
        "active": True,
        "created_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }
    
    users_data["users"].append(new_user)
    write_users(users_data)
    
    return jsonify({"success": True})

@app.route('/api/users/<int:user_id>/toggle', methods=['POST'])
def toggle_user(user_id):
    users_data = read_users()
    
    for user in users_data["users"]:
        if user["id"] == user_id:
            user["active"] = not user.get("active", True)
            break
    
    write_users(users_data)
    return jsonify({"success": True})

@app.route('/api/users/<int:user_id>/delete', methods=['DELETE'])
def delete_user(user_id):
    users_data = read_users()
    users_data["users"] = [u for u in users_data["users"] if u["id"] != user_id]
    write_users(users_data)
    return jsonify({"success": True})

@app.route('/api/service/restart', methods=['POST'])
def restart_service():
    try:
        subprocess.run(['systemctl', 'restart', 'agnudp'], check=True)
        return jsonify({"success": True})
    except:
        return jsonify({"success": False})

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF

    # Create HTML template
    cat > $WEB_DIR/templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AGN-UDP Manager</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
</head>
<body class="bg-gray-100">
    <div id="app">
        <!-- Login Screen -->
        <div v-if="!loggedIn" class="min-h-screen flex items-center justify-center">
            <div class="bg-white p-8 rounded-lg shadow-md w-96">
                <h2 class="text-2xl font-bold mb-6 text-center text-blue-600">
                    <i class="fas fa-shield-alt mr-2"></i>AGN-UDP Login
                </h2>
                <form @submit.prevent="login">
                    <div class="mb-4">
                        <label class="block text-gray-700 text-sm font-bold mb-2">Username</label>
                        <input v-model="loginData.username" type="text" 
                               class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500">
                    </div>
                    <div class="mb-6">
                        <label class="block text-gray-700 text-sm font-bold mb-2">Password</label>
                        <input v-model="loginData.password" type="password" 
                               class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500">
                    </div>
                    <button type="submit" class="w-full bg-blue-600 text-white py-2 px-4 rounded-md hover:bg-blue-700 transition duration-200">
                        Login
                    </button>
                </form>
                <p class="mt-4 text-center text-sm text-gray-600">
                    Default: admin / admin123
                </p>
            </div>
        </div>

        <!-- Main Dashboard -->
        <div v-else class="min-h-screen">
            <!-- Header -->
            <header class="bg-white shadow-sm">
                <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
                    <div class="flex justify-between items-center py-4">
                        <h1 class="text-2xl font-bold text-gray-900">
                            <i class="fas fa-shield-alt text-blue-600 mr-2"></i>AGN-UDP Manager
                        </h1>
                        <button @click="logout" class="bg-red-500 text-white px-4 py-2 rounded-md hover:bg-red-600 transition duration-200">
                            <i class="fas fa-sign-out-alt mr-2"></i>Logout
                        </button>
                    </div>
                </div>
            </header>

            <!-- Stats -->
            <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-6">
                <div class="grid grid-cols-1 md:grid-cols-3 gap-6 mb-8">
                    <div class="bg-white rounded-lg shadow p-6">
                        <div class="flex items-center">
                            <div class="p-3 rounded-full bg-blue-100 text-blue-600">
                                <i class="fas fa-users text-xl"></i>
                            </div>
                            <div class="ml-4">
                                <h3 class="text-sm font-medium text-gray-500">Total Users</h3>
                                <p class="text-2xl font-semibold text-gray-900">{{ stats.total_users }}</p>
                            </div>
                        </div>
                    </div>
                    
                    <div class="bg-white rounded-lg shadow p-6">
                        <div class="flex items-center">
                            <div class="p-3 rounded-full bg-green-100 text-green-600">
                                <i class="fas fa-user-check text-xl"></i>
                            </div>
                            <div class="ml-4">
                                <h3 class="text-sm font-medium text-gray-500">Active Users</h3>
                                <p class="text-2xl font-semibold text-gray-900">{{ stats.active_users }}</p>
                            </div>
                        </div>
                    </div>
                    
                    <div class="bg-white rounded-lg shadow p-6">
                        <div class="flex items-center">
                            <div :class="['p-3 rounded-full', serviceStatusClass]">
                                <i class="fas fa-server text-xl"></i>
                            </div>
                            <div class="ml-4">
                                <h3 class="text-sm font-medium text-gray-500">Service Status</h3>
                                <p class="text-2xl font-semibold" :class="serviceStatusTextClass">{{ stats.service_status }}</p>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- Add User Form -->
                <div class="bg-white rounded-lg shadow p-6 mb-6">
                    <h2 class="text-lg font-semibold mb-4">Add New User</h2>
                    <form @submit.prevent="addUser" class="grid grid-cols-1 md:grid-cols-4 gap-4">
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-1">Username</label>
                            <input v-model="newUser.username" type="text" required
                                   class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500">
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-1">Password</label>
                            <input v-model="newUser.password" type="text" required
                                   class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500">
                        </div>
                        <div>
                            <label class="block text-sm font-medium text-gray-700 mb-1">Data Limit (MB)</label>
                            <input v-model="newUser.data_limit" type="number" required
                                   class="w-full px-3 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500">
                        </div>
                        <div class="flex items-end">
                            <button type="submit" class="w-full bg-blue-600 text-white py-2 px-4 rounded-md hover:bg-blue-700 transition duration-200">
                                Add User
                            </button>
                        </div>
                    </form>
                </div>

                <!-- Users Table -->
                <div class="bg-white rounded-lg shadow overflow-hidden">
                    <div class="px-6 py-4 border-b border-gray-200">
                        <h2 class="text-lg font-semibold">User Management</h2>
                    </div>
                    <div class="overflow-x-auto">
                        <table class="min-w-full divide-y divide-gray-200">
                            <thead class="bg-gray-50">
                                <tr>
                                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">ID</th>
                                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Username</th>
                                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Used Data</th>
                                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Data Limit</th>
                                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Status</th>
                                    <th class="px-6 py-3 text-left text-xs font-medium text-gray-500 uppercase tracking-wider">Actions</th>
                                </tr>
                            </thead>
                            <tbody class="bg-white divide-y divide-gray-200">
                                <tr v-for="user in users" :key="user.id">
                                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{{ user.id }}</td>
                                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{{ user.username }}</td>
                                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{{ user.used_data }} MB</td>
                                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">{{ user.data_limit }} MB</td>
                                    <td class="px-6 py-4 whitespace-nowrap">
                                        <span :class="['px-2 inline-flex text-xs leading-5 font-semibold rounded-full', 
                                                     user.active ? 'bg-green-100 text-green-800' : 'bg-red-100 text-red-800']">
                                            {{ user.active }}
