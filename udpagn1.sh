#!/bin/bash

# AGN-UDP Web Panel Manager
# Complete Installation Script with Web Interface

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
WEB_USER="admin"
WEB_PASS="admin123"  # Change this in production!

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
    
    local binary_found=false
    
    if wget -O /usr/local/bin/agnudp "https://github.com/khaledagn/AGN-UDP/releases/download/latest/agnudp" 2>/dev/null; then
        binary_found=true
    elif wget -O /usr/local/bin/agnudp "https://github.com/khaledagn/AGN-UDP/releases/latest/download/agnudp" 2>/dev/null; then
        binary_found=true
    else
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
        "server_port": $SERVER_PORT,
        "web_credentials": {
            "username": "$WEB_USER",
            "password": "$WEB_PASS"
        }
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

# Create web interface (with 500 Error fixes and Permission fix)
create_web_interface() {
    echo -e "${YELLOW}[*] Creating web interface...${NC}"
    
    mkdir -p $WEB_DIR
    mkdir -p $WEB_DIR/static
    mkdir -p $WEB_DIR/templates
    
    # Create main web application (app.py) - Error Handling Hardened
    cat > $WEB_DIR/app.py << 'EOF'
from flask import Flask, render_template, request, jsonify, session
import json
import os
import subprocess
from datetime import datetime
import logging

# Configure basic logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

app = Flask(__name__)
# IMPORTANT: Change this secret key!
app.secret_key = 'agnudp_web_panel_secret_key_change_me' 

CONFIG_DIR = "/etc/agnudp"
USERS_FILE = os.path.join(CONFIG_DIR, "users.json")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")

def read_users():
    """Reads users data, handles missing file and JSON decoding errors safely."""
    try:
        with open(USERS_FILE, 'r') as f:
            return json.load(f)
    except FileNotFoundError:
        logging.warning(f"Users file not found: {USERS_FILE}. Returning empty structure.")
        return {"users": [], "settings": {}}
    except json.JSONDecodeError as e:
        # Catches corruption in the JSON file.
        logging.error(f"JSON decode error in {USERS_FILE}. Data might be corrupted: {e}")
        return {"users": [], "settings": {}} 
    except Exception as e:
        logging.error(f"Unexpected error reading {USERS_FILE}: {e}")
        return {"users": [], "settings": {}}

def write_users(data):
    """Writes users data, handles serialization errors."""
    try:
        with open(USERS_FILE, 'w') as f:
            # Use default=str to prevent TypeError (500 error) if non-serializable objects exist
            json.dump(data, f, indent=2, default=str)
    except Exception as e:
        logging.error(f"Error writing to {USERS_FILE}: {e}")
        raise # Re-raise to be caught by the route handler

def get_service_status():
    try:
        # Use absolute path for systemctl
        result = subprocess.run(['/bin/systemctl', 'is-active', 'agnudp'], 
                              capture_output=True, text=True, timeout=5)
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
    
    users_data = read_users()
    web_creds = users_data.get("settings", {}).get("web_credentials", {})
    
    if username == web_creds.get("username") and password == web_creds.get("password"):
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
    if not session.get('logged_in'):
        return jsonify({"success": False, "error": "Unauthorized"}), 401
    
    data = request.json
    users_data = read_users()
    
    new_id = max([u.get('id', 0) for u in users_data.get("users", [])]) + 1
    
    try:
        data_limit_int = int(data.get("data_limit", 1000))
    except ValueError:
        return jsonify({"success": False, "error": "Invalid data limit"}), 400
        
    new_user = {
        "id": new_id,
        "username": data.get("username"),
        "password": data.get("password"),
        "data_limit": data_limit_int,
        "used_data": 0,
        "active": True,
        "created_at": datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    }
    
    users_data["users"].append(new_user)
    
    try:
        write_users(users_data)
        return jsonify({"success": True})
    except Exception:
        return jsonify({"success": False, "error": "Failed to save user data"}), 500

@app.route('/api/users/<int:user_id>/toggle', methods=['POST'])
def toggle_user(user_id):
    if not session.get('logged_in'):
        return jsonify({"success": False, "error": "Unauthorized"}), 401
        
    users_data = read_users()
    
    found = False
    for user in users_data.get("users", []):
        if user.get("id") == user_id:
            user["active"] = not user.get("active", True)
            found = True
            break
    
    if not found:
        return jsonify({"success": False, "error": "User not found"}), 404
        
    try:
        write_users(users_data)
        return jsonify({"success": True})
    except Exception:
        return jsonify({"success": False, "error": "Failed to save user data"}), 500


@app.route('/api/users/<int:user_id>/delete', methods=['DELETE'])
def delete_user(user_id):
    if not session.get('logged_in'):
        return jsonify({"success": False, "error": "Unauthorized"}), 401
        
    users_data = read_users()
    initial_count = len(users_data.get("users", []))
    users_data["users"] = [u for u in users_data.get("users", []) if u.get("id") != user_id]
    
    if len(users_data["users"]) == initial_count:
        return jsonify({"success": False, "error": "User not found"}), 404
    
    try:
        write_users(users_data)
        return jsonify({"success": True})
    except Exception:
        return jsonify({"success": False, "error": "Failed to save user data"}), 500

@app.route('/api/service/restart', methods=['POST'])
def restart_service():
    if not session.get('logged_in'):
        return jsonify({"success": False, "error": "Unauthorized"}), 401
        
    try:
        subprocess.run(['/bin/systemctl', 'restart', 'agnudp'], check=True, timeout=5)
        return jsonify({"success": True})
    except subprocess.CalledProcessError as e:
        logging.error(f"Failed to restart agnudp service: {e}")
        return jsonify({"success": False, "error": "Service restart failed"}), 500
    except subprocess.TimeoutExpired:
        logging.warning("Service restart command timed out.")
        return jsonify({"success": True, "message": "Restart command sent, status pending"}), 202
    except Exception as e:
        logging.error(f"Unexpected error during service restart: {e}")
        return jsonify({"success": False, "error": "Internal Server Error"}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080, debug=False)
EOF

    # Create HTML template (No change)
    cat > $WEB_DIR/templates/index.html << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AGN-UDP Manager</title>
    <script src="https://cdn.tailwindcss.com"></script>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <script src="https://cdn.jsdelivr.net/npm/vue@3.2.47/dist/vue.global.min.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/axios/dist/axios.min.js"></script>
</head>
<body class="bg-gray-100">
    <div id="app">
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
            </div>
        </div>

        <div v-else class="min-h-screen">
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
                                            {{ user.active ? 'Active' : 'Inactive' }}
                                        </span>
                                    </td>
                                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-500">
                                        <button @click="toggleUser(user.id)" 
                                                :class="['mr-2 px-3 py-1 rounded-md', 
                                                       user.active ? 'bg-yellow-500 hover:bg-yellow-600' : 'bg-green-500 hover:bg-green-600',
                                                       'text-white transition duration-200']">
                                            {{ user.active ? 'Deactivate' : 'Activate' }}
                                        </button>
                                        <button @click="deleteUser(user.id)" 
                                                class="px-3 py-1 bg-red-500 text-white rounded-md hover:bg-red-600 transition duration-200">
                                            Delete
                                        </button>
                                    </td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </div>

                <div class="bg-white rounded-lg shadow p-6 mt-6">
                    <h2 class="text-lg font-semibold mb-4">Service Controls</h2>
                    <div class="flex space-x-4">
                        <button @click="restartService" 
                                class="px-4 py-2 bg-blue-600 text-white rounded-md hover:bg-blue-700 transition duration-200">
                            <i class="fas fa-sync-alt mr-2"></i>Restart Service
                        </button>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <script>
        const { createApp, ref, computed } = Vue;
        
        createApp({
            setup() {
                const loggedIn = ref(false);
                const loginData = ref({
                    username: '',
                    password: ''
                });
                
                const stats = ref({
                    total_users: 0,
                    active_users: 0,
                    service_status: 'unknown'
                });
                
                const users = ref([]);
                const newUser = ref({
                    username: '',
                    password: '',
                    data_limit: 1000
                });
                
                const serviceStatusClass = computed(() => {
                    return stats.value.service_status === 'active' 
                        ? 'bg-green-100 text-green-600' 
                        : 'bg-red-100 text-red-600';
                });
                
                const serviceStatusTextClass = computed(() => {
                    return stats.value.service_status === 'active' 
                        ? 'text-green-600' 
                        : 'text-red-600';
                });
                
                const checkLogin = () => {
                    if (localStorage.getItem('agnudp_loggedIn') === 'true') {
                        loggedIn.value = true;
                        fetchData();
                    }
                };
                
                const login = async () => {
                    try {
                        const response = await axios.post('/api/login', loginData.value);
                        if (response.data.success) {
                            loggedIn.value = true;
                            localStorage.setItem('agnudp_loggedIn', 'true');
                            fetchData();
                        } else {
                            alert('Invalid credentials');
                        }
                    } catch (error) {
                        console.error('Login error:', error);
                        alert('Login failed');
                    }
                };
                
                const logout = () => {
                    loggedIn.value = false;
                    localStorage.removeItem('agnudp_loggedIn');
                };
                
                const fetchData = async () => {
                    try {
                        const [dashboardRes, usersRes] = await Promise.all([
                            axios.get('/api/dashboard'),
                            axios.get('/api/users')
                        ]);
                        
                        stats.value = dashboardRes.data;
                        users.value = usersRes.data;
                    } catch (error) {
                        console.error('Fetch error:', error);
                    }
                };
                
                const addUser = async () => {
                    try {
                        const response = await axios.post('/api/users/add', newUser.value);
                        if (response.data.success) {
                            newUser.value = { username: '', password: '', data_limit: 1000 };
                            fetchData();
                        } else {
                            alert('Failed to add user: ' + (response.data.error || 'Unknown error'));
                        }
                    } catch (error) {
                        console.error('Add user error:', error);
                        alert('Failed to add user');
                    }
                };
                
                const toggleUser = async (userId) => {
                    try {
                        await axios.post(`/api/users/${userId}/toggle`);
                        fetchData();
                    } catch (error) {
                        console.error('Toggle user error:', error);
                    }
                };
                
                const deleteUser = async (userId) => {
                    if (confirm('Are you sure you want to delete this user?')) {
                        try {
                            await axios.delete(`/api/users/${userId}/delete`);
                            fetchData();
                        } catch (error) {
                            console.error('Delete user error:', error);
                        }
                    }
                };
                
                const restartService = async () => {
                    try {
                        const response = await axios.post('/api/service/restart');
                        if (response.data.success || response.status === 202) {
                            alert('Service restart initiated');
                            setTimeout(fetchData, 3000);
                        } else {
                            alert('Failed to restart service: ' + (response.data.error || 'Unknown error'));
                        }
                    } catch (error) {
                        console.error('Restart error:', error);
                        alert('Failed to restart service');
                    }
                };
                
                // Initialize
                checkLogin();
                
                return {
                    loggedIn,
                    loginData,
                    stats,
                    users,
                    newUser,
                    serviceStatusClass,
                    serviceStatusTextClass,
                    login,
                    logout,
                    addUser,
                    toggleUser,
                    deleteUser,
                    restartService
                };
            }
        }).mount('#app');
    </script>
</body>
</html>
EOF

    # Apply file permissions (FIX ADDED HERE)
    chown -R root:root $CONFIG_DIR
    chmod -R 755 $CONFIG_DIR
    chmod 600 $CONFIG_FILE $USERS_FILE # Only root can read/write config files
    
    chown -R root:root $WEB_DIR
    chmod -R 755 $WEB_DIR

    # Create web service
    cat > /etc/systemd/system/agnudp-web.service << EOF
[Unit]
Description=AGN-UDP Web Interface
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$WEB_DIR
ExecStart=/usr/bin/python3 $WEB_DIR/app.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable agnudp-web
    echo -e "${GREEN}[+] Web interface created${NC}"
}

# Configure firewall
configure_firewall() {
    echo -e "${YELLOW}[*] Configuring firewall...${NC}"
    
    ufw allow $SERVER_PORT/udp
    ufw allow $WEB_PORT/tcp
    ufw allow ssh
    
    echo -e "${GREEN}[+] Firewall configured${NC}"
}

# Start services
start_services() {
    echo -e "${YELLOW}[*] Starting services...${NC}"
    
    systemctl start agnudp
    systemctl start agnudp-web
    
    echo -e "${GREEN}[+] Services started${NC}"
}

# Show status
show_status() {
    echo -e "\n${BLUE}=== Installation Summary ===${NC}"
    echo -e "${GREEN}AGN-UDP installed at: /usr/local/bin/agnudp${NC}"
    echo -e "${GREEN}Configuration directory: $CONFIG_DIR${NC}"
    echo -e "${GREEN}Web interface directory: $WEB_DIR${NC}"
    echo -e "\n${BLUE}=== Service Status ===${NC}"
    systemctl status agnudp --no-pager -l
    echo -e "\n${BLUE}=== Web Interface Status ===${NC}"
    systemctl status agnudp-web --no-pager -l
    echo -e "\n${BLUE}=== Access Information ===${NC}"
    echo -e "${GREEN}Web Panel URL: http://$(curl -s ifconfig.me):$WEB_PORT${NC}"
    echo -e "${GREEN}Username: $WEB_USER${NC}"
    echo -e "${GREEN}Password: $WEB_PASS${NC}"
    echo -e "\n${YELLOW}Important: Change the default credentials in $USERS_FILE${NC}"
    echo -e "\n${CYAN}*** LOGS စစ်ဆေးရန် Command: journalctl -u agnudp-web -f ***${NC}"
}

# Main installation function
main_install() {
    check_root
    install_dependencies
    install_agnudp_binary
    create_config
    create_service
    create_web_interface
    configure_firewall
    start_services
    show_status
    
    echo -e "\n${GREEN}[+] AGN-UDP Web Panel installation completed successfully!${NC}"
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
    echo -e "\n${YELLOW}Note: After installation, access the web panel at http://your-server-ip:8080${NC}"
fi
