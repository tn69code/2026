#!/bin/bash

# Configuration
CONFIG_DIR="/etc/agnudp"
WEB_DIR="/var/www/agnudp"
USERS_FILE="$CONFIG_DIR/users.json"
SERVICE_NAME="agnudp-web"
SERVICE_FILE="/etc/systemd/system/$SERVICE_NAME.service"
WEB_PORT=8080

log() {
    echo -e "\n[INFO] $1"
}

error() {
    echo -e "\n[ERROR] $1" >&2
    exit 1
}

# ----------------------------------------------------
# 1. Create Python Flask Application (app.py) - Syntax Fix
# ----------------------------------------------------

create_app_py() {
    log "Creating Flask application script ($WEB_DIR/app.py) with final fixes..."
    # Writing the Python file with correct indentation and Jinja2 fix
    cat > "$WEB_DIR/app.py" << 'EOF'
from flask import Flask, render_template, request, jsonify, redirect, url_for, session
from flask_cors import CORS
import json
import os
import subprocess
import time

# --- Configuration ---
CONFIG_DIR = "/etc/agnudp"
USERS_FILE = os.path.join(CONFIG_DIR, "users.json")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.json")

# --- Flask App Initialization (JINJA2 FIX) ---
# Customizing Jinja2 to change default delimiters from {{ }} to [[ ]] 
class CustomFlask(Flask):
    jinja_options = Flask.jinja_options.copy()
    jinja_options.update(dict(
        variable_start_string='[[',
        variable_end_string=']]',
    ))

app = CustomFlask(__name__, template_folder='templates')
CORS(app)
app.secret_key = os.urandom(24) 

# Load configuration and user data
def load_data():
    try:
        with open(CONFIG_FILE, 'r') as f:
            config = json.load(f)
        with open(USERS_FILE, 'r') as f:
            users = json.load(f)
        return config, users
    except (FileNotFoundError, json.JSONDecodeError, Exception) as e:
        print(f"Error loading data: {e}. Falling back to defaults.")
        config = {"admin_username": "admin", "admin_password": "admin123"}
        users = [{"id": 1, "username": "user1", "password": "password123", "data_limit": 10240, "used_data": 0, "active": True}]
        return config, users

def save_users(users):
    try:
        with open(USERS_FILE, 'w') as f:
            json.dump(users, f, indent=4)
        return True
    except Exception as e:
        print(f"Error saving user data: {e}")
        return False

# --- Authentication ---
def check_auth():
    return session.get('logged_in')

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/api/login', methods=['POST'])
def login():
    data = request.json
    config, _ = load_data()
    if config and data['username'] == config['admin_username'] and data['password'] == config['admin_password']:
        session['logged_in'] = True
        return jsonify(success=True)
    return jsonify(success=False), 401

# --- API Endpoints ---
@app.route('/api/dashboard')
def dashboard():
    if not check_auth():
        return jsonify(error="Unauthorized"), 401
    
    _, users = load_data()
    total_users = len(users)
    active_users = sum(1 for u in users if u['active'])
    
    try:
        status_output = subprocess.check_output(['systemctl', 'is-active', 'agnudp'], universal_newlines=True).strip()
        service_status = 'active' if status_output == 'active' else 'inactive'
    except Exception:
        service_status = 'unknown'

    return jsonify({
        'total_users': total_users,
        'active_users': active_users,
        'service_status': service_status
    })

@app.route('/api/users')
def get_users():
    if not check_auth():
        return jsonify(error="Unauthorized"), 401
    
    _, users = load_data()
    return jsonify(users)

@app.route('/api/users/add', methods=['POST'])
def add_user():
    if not check_auth():
        return jsonify(error="Unauthorized"), 401
    
    data = request.json
    _, users = load_data()

    new_id = max(u['id'] for u in users) + 1 if users else 1
    new_user = {
        'id': new_id,
        'username': data['username'],
        'password': data['password'],
        'data_limit': int(data.get('data_limit', 10240)),
        'used_data': 0,
        'active': True
    }
    users.append(new_user)
    if save_users(users):
        return jsonify(success=True)
    return jsonify(success=False, error="Failed to save data"), 500

@app.route('/api/users/<int:user_id>/toggle', methods=['POST'])
def toggle_user(user_id):
    if not check_auth():
        return jsonify(error="Unauthorized"), 401
    
    _, users = load_data()
    user = next((u for u in users if u['id'] == user_id), None)
    if user:
        user['active'] = not user['active']
        if save_users(users):
            return jsonify(success=True)
    return jsonify(success=False, error="User not found or save failed"), 404

@app.route('/api/users/<int:user_id>/delete', methods=['DELETE'])
def delete_user(user_id):
    if not check_auth():
        return jsonify(error="Unauthorized"), 401
    
    _, users = load_data()
    initial_count = len(users)
    users[:] = [u for u in users if u['id'] != user_id]
    
    if len(users) < initial_count:
        if save_users(users):
            return jsonify(success=True)
        return jsonify(success=False, error="Failed to save data"), 500
        
    return jsonify(success=False, error="User not found"), 404

@app.route('/api/service/restart', methods=['POST'])
def restart_service():
    if not check_auth():
        return jsonify(error="Unauthorized"), 401
    
    try:
        subprocess.run(['systemctl', 'restart', 'agnudp'], check=True, timeout=10)
        return jsonify(success=True, message="Service restart initiated"), 202
    except subprocess.CalledProcessError as e:
        return jsonify(success=False, error=f"Command failed: {e.output}"), 500
    except subprocess.TimeoutExpired:
        return jsonify(success=False, error="Service restart command timed out"), 500
    except Exception as e:
        return jsonify(success=False, error=str(e)), 500


# --- Run App ---
if __name__ == '__main__':
    WEB_PORT = 8080 
    app.run(host='0.0.0.0', port=WEB_PORT, debug=False)
EOF
}

# ----------------------------------------------------
# 2. Create HTML Template (index.html) - Delimiter Fix
# ----------------------------------------------------

create_index_html() {
    log "Creating HTML template (index.html) with Jinja2 delimiter fix..."
    # The new code for index.html from the previous step which uses [[ ]] for Jinja2
    cat > "$WEB_DIR/templates/index.html" << 'EOF'
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
                                <p class="text-2xl font-semibold text-gray-900">[[ stats.total_users ]]</p>
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
                                <p class="text-2xl font-semibold text-gray-900">[[ stats.active_users ]]</p>
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
                                <p class="text-2xl font-semibold" :class="serviceStatusTextClass">[[ stats.service_status ]]</p>
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
                                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">[[ user.id ]]</td>
                                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">[[ user.username ]]</td>
                                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">[[ user.used_data ]] MB</td>
                                    <td class="px-6 py-4 whitespace-nowrap text-sm text-gray-900">[[ user.data_limit ]] MB</td>
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
                                            [[ user.active ? 'Deactivate' : 'Activate' ]]
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
}

# ----------------------------------------------------
# 3. Service Restart
# ----------------------------------------------------

start_service() {
    log "Restarting $SERVICE_NAME service..."
    
    # Reload daemon to ensure systemd picks up any changes (though service file is assumed to be okay)
    sudo systemctl daemon-reload

    # Stop any failed attempts and start fresh
    sudo systemctl stop "$SERVICE_NAME"
    sudo systemctl start "$SERVICE_NAME" || error "Failed to start $SERVICE_NAME. Check logs with 'journalctl -u $SERVICE_NAME -f'"

    log "Service should now be running. Please check: http://185.84.160.65:8080"
    log "----------------------------------------------------"
    log "Check service status: sudo systemctl status $SERVICE_NAME"
}

# --- Execute All Steps ---
# Rerun file creation to fix any encoding/indentation errors
create_app_py
create_index_html
start_service
