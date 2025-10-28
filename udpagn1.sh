#!/bin/bash

# AGN-UDP Web Panel Installer
# GitHub: https://github.com/khaledagn/AGN-UDP

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PANEL_PORT="8080"
PANEL_DIR="/opt/agn-udp-panel"
REPO_URL="https://github.com/khaledagn/AGN-UDP.git"
SERVICE_NAME="agn-udp-panel"

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root"
        exit 1
    fi
}

# Install dependencies
install_dependencies() {
    log "Installing dependencies..."
    
    # Detect OS
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case $ID in
            ubuntu|debian)
                sudo apt update
                sudo apt install -y nginx curl git python3 python3-pip
                ;;
            centos|rhel|fedora)
                sudo yum install -y nginx curl git python3 python3-pip || \
                sudo dnf install -y nginx curl git python3 python3-pip
                ;;
            *)
                error "Unsupported OS: $ID"
                exit 1
                ;;
        esac
    else
        error "Cannot detect OS"
        exit 1
    fi
}

# Clone repository
clone_repo() {
    log "Cloning AGN-UDP repository..."
    
    if [[ -d "$PANEL_DIR" ]]; then
        warning "Panel directory already exists. Backing up..."
        sudo mv "$PANEL_DIR" "${PANEL_DIR}.backup.$(date +%Y%m%d%H%M%S)"
    fi
    
    sudo mkdir -p "$PANEL_DIR"
    sudo chown $USER:$USER "$PANEL_DIR"
    
    git clone "$REPO_URL" "$PANEL_DIR"
    
    if [[ ! -d "$PANEL_DIR" ]]; then
        error "Failed to clone repository"
        exit 1
    fi
}

# Create web panel script
create_panel_script() {
    log "Creating web panel script..."
    
    cat > "$PANEL_DIR/web_panel.sh" << 'EOF'
#!/bin/bash

# AGN-UDP Web Panel
# Control panel for AGN-UDP

set -e

PANEL_PORT="8080"
PANEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$PANEL_DIR/panel.log"
CONFIG_FILE="$PANEL_DIR/panel.conf"

# Load configuration
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Default values
: ${PANEL_PORT:="8080"}
: ${PANEL_HOST:="0.0.0.0"}

# Logging
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# HTML template functions
html_header() {
    cat << HTML
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8

<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>AGN-UDP Control Panel</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px;
        }
        .container { 
            max-width: 1200px; 
            margin: 0 auto; 
            background: white; 
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            overflow: hidden;
        }
        .header { 
            background: linear-gradient(135deg, #2c3e50, #3498db);
            color: white; 
            padding: 30px; 
            text-align: center;
        }
        .header h1 { 
            font-size: 2.5em; 
            margin-bottom: 10px;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.3);
        }
        .nav { 
            background: #34495e; 
            padding: 15px; 
            display: flex;
            justify-content: center;
            gap: 10px;
            flex-wrap: wrap;
        }
        .nav button, .nav a {
            background: #3498db;
            color: white;
            border: none;
            padding: 12px 24px;
            border-radius: 25px;
            cursor: pointer;
            text-decoration: none;
            font-size: 14px;
            transition: all 0.3s ease;
        }
        .nav button:hover, .nav a:hover {
            background: #2980b9;
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.2);
        }
        .content { 
            padding: 30px; 
            min-height: 400px;
        }
        .card {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 25px;
            margin-bottom: 20px;
            border-left: 5px solid #3498db;
            box-shadow: 0 5px 15px rgba(0,0,0,0.08);
        }
        .status-badge {
            display: inline-block;
            padding: 5px 15px;
            border-radius: 20px;
            font-size: 12px;
            font-weight: bold;
            margin-left: 10px;
        }
        .status-running { background: #2ecc71; color: white; }
        .status-stopped { background: #e74c3c; color: white; }
        .status-unknown { background: #95a5a6; color: white; }
        .form-group { margin-bottom: 20px; }
        .form-group label { display: block; margin-bottom: 8px; font-weight: bold; color: #2c3e50; }
        .form-group input, .form-group select { 
            width: 100%; 
            padding: 12px; 
            border: 2px solid #bdc3c7; 
            border-radius: 8px; 
            font-size: 14px;
            transition: border-color 0.3s ease;
        }
        .form-group input:focus, .form-group select:focus {
            border-color: #3498db;
            outline: none;
        }
        .btn { 
            background: linear-gradient(135deg, #3498db, #2980b9);
            color: white; 
            border: none; 
            padding: 15px 30px; 
            border-radius: 8px; 
            cursor: pointer; 
            font-size: 16px;
            font-weight: bold;
            transition: all 0.3s ease;
            margin: 5px;
        }
        .btn:hover { 
            transform: translateY(-2px);
            box-shadow: 0 8px 25px rgba(52, 152, 219, 0.3);
        }
        .btn-danger { background: linear-gradient(135deg, #e74c3c, #c0392b); }
        .btn-success { background: linear-gradient(135deg, #2ecc71, #27ae60); }
        .btn-warning { background: linear-gradient(135deg, #f39c12, #d35400); }
        .log-output {
            background: #2c3e50;
            color: #ecf0f1;
            padding: 15px;
            border-radius: 8px;
            font-family: 'Courier New', monospace;
            font-size: 12px;
            max-height: 300px;
            overflow-y: auto;
            white-space: pre-wrap;
        }
        .alert {
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 20px;
            font-weight: bold;
        }
        .alert-success { background: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .alert-danger { background: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .alert-warning { background: #fff3cd; color: #856404; border: 1px solid #ffeaa7; }
        .footer {
            text-align: center;
            padding: 20px;
            background: #ecf0f1;
            color: #7f8c8d;
            border-top: 1px solid #bdc3c7;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 AGN-UDP Control Panel</h1>
            <p>Web-based management interface for AGN-UDP</p>
        </div>
        <div class="nav">
            <a href="/">Dashboard</a>
            <a href="/status">Status</a>
            <a href="/config">Configuration</a>
            <a href="/logs">Logs</a>
            <a href="/update">Update</a>
        </div>
        <div class="content">
HTML
}

html_footer() {
    cat << HTML
        </div>
        <div class="footer">
            <p>AGN-UDP Web Panel &copy; $(date +%Y) | $(uname -n)</p>
        </div>
    </div>
    <script>
        function showAlert(message, type) {
            const alertDiv = document.createElement('div');
            alertDiv.className = 'alert alert-' + type;
            alertDiv.textContent = message;
            document.querySelector('.content').insertBefore(alertDiv, document.querySelector('.content').firstChild);
            setTimeout(() => alertDiv.remove(), 5000);
        }
        
        function executeAction(action) {
            fetch('/action', {
                method: 'POST',
                headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
                body: 'action=' + action
            }).then(r => r.text()).then(data => {
                showAlert('Action completed: ' + action, 'success');
                setTimeout(() => location.reload(), 1000);
            }).catch(err => {
                showAlert('Error: ' + err, 'danger');
            });
        }
    </script>
</body>
</html>
EOF
}

# Generate dashboard HTML
generate_dashboard() {
    cat << HTML
    <div class="card">
        <h2>📊 Dashboard</h2>
        <p>Welcome to AGN-UDP Control Panel. Monitor and manage your UDP services.</p>
    </div>
    
    <div class="card">
        <h2>🛠️ Quick Actions</h2>
        <div style="display: grid; grid-template-columns: repeat(auto-fit, minmax(200px, 1fr)); gap: 15px; margin-top: 20px;">
            <button class="btn btn-success" onclick="executeAction('start')">▶️ Start Service</button>
            <button class="btn btn-danger" onclick="executeAction('stop')">⏹️ Stop Service</button>
            <button class="btn btn-warning" onclick="executeAction('restart')">🔄 Restart Service</button>
            <button class="btn" onclick="executeAction('update')">📥 Update</button>
        </div>
    </div>
    
    <div class="card">
        <h2>📈 Service Status</h2>
        <div id="status-content">
            <p>Loading status...</p>
        </div>
    </div>
    
    <script>
        // Load status on page load
        fetch('/status-data').then(r => r.text()).then(html => {
            document.getElementById('status-content').innerHTML = html;
        });
    </script>
HTML
}

# Generate status HTML
generate_status() {
    # Check if AGN-UDP is running
    if pgrep -f "agn-udp" > /dev/null; then
        STATUS="RUNNING"
        STATUS_CLASS="status-running"
    else
        STATUS="STOPPED"
        STATUS_CLASS="status-stopped"
    fi
    
    cat << HTML
    <div class="card">
        <h2>🔍 Service Status</h2>
        <p>Current Status: <span class="status-badge $STATUS_CLASS">$STATUS</span></p>
        <p>Last Checked: $(date)</p>
    </div>
    
    <div class="card">
        <h2>📊 System Information</h2>
        <p><strong>Hostname:</strong> $(hostname)</p>
        <p><strong>Uptime:</strong> $(uptime -p)</p>
        <p><strong>Load Average:</strong> $(uptime | awk -F'load average:' '{print $2}')</p>
        <p><strong>Memory Usage:</strong> $(free -h | awk 'NR==2{printf "%.2f/%.2f", \$3,\$2}')</p>
    </div>
HTML
}

# Generate configuration HTML
generate_config() {
    cat << HTML
    <div class="card">
        <h2>⚙️ Configuration</h2>
        <form action="/save-config" method="POST">
            <div class="form-group">
                <label for="panel_port">Panel Port:</label>
                <input type="number" id="panel_port" name="panel_port" value="$PANEL_PORT" min="1024" max="65535">
            </div>
            <div class="form-group">
                <label for="panel_host">Panel Host:</label>
                <input type="text" id="panel_host" name="panel_host" value="$PANEL_HOST" placeholder="0.0.0.0">
            </div>
            <button type="submit" class="btn btn-success">💾 Save Configuration</button>
        </form>
    </div>
HTML
}

# Generate logs HTML
generate_logs() {
    cat << HTML
    <div class="card">
        <h2>📋 Recent Logs</h2>
        <div class="log-output">
$(tail -20 "$LOG_FILE" 2>/dev/null || echo "No logs available")
        </div>
        <button class="btn" onclick="location.reload()">🔄 Refresh Logs</button>
        <button class="btn btn-danger" onclick="executeAction('clear_logs')">🗑️ Clear Logs</button>
    </div>
HTML
}

# Generate update HTML
generate_update() {
    cat << HTML
    <div class="card">
        <h2>🔄 Update System</h2>
        <p>Update AGN-UDP to the latest version from GitHub.</p>
        <button class="btn btn-success" onclick="executeAction('update_repo')">📥 Update Repository</button>
        <button class="btn btn-warning" onclick="executeAction('reinstall')">🔧 Reinstall</button>
    </div>
    
    <div class="card">
        <h2>📦 Current Version</h2>
        <div class="log-output">
$(cd "$PANEL_DIR" && git log --oneline -5 2>/dev/null || echo "Version information not available")
        </div>
    </div>
HTML
}

# Handle actions
handle_action() {
    local action="$1"
    log "Executing action: $action"
    
    case "$action" in
        start)
            # Start AGN-UDP service
            cd "$PANEL_DIR"
            nohup python3 server.py > server.log 2>&1 &
            echo "Service started"
            ;;
        stop)
            # Stop AGN-UDP service
            pkill -f "agn-udp\|server.py"
            echo "Service stopped"
            ;;
        restart)
            pkill -f "agn-udp\|server.py"
            sleep 2
            cd "$PANEL_DIR"
            nohup python3 server.py > server.log 2>&1 &
            echo "Service restarted"
            ;;
        update)
            cd "$PANEL_DIR" && git pull
            echo "Repository updated"
            ;;
        update_repo)
            cd "$PANEL_DIR" && git pull --force
            echo "Repository updated forcefully"
            ;;
        reinstall)
            cd "$PANEL_DIR" && git reset --hard && git pull --force
            echo "System reinstalled"
            ;;
        clear_logs)
            > "$LOG_FILE"
            echo "Logs cleared"
            ;;
        *)
            echo "Unknown action: $action"
            ;;
    esac
}

# Main web server function
start_web_server() {
    log "Starting web panel on port $PANEL_PORT..."
    
    # Create a simple HTTP server using netcat
    while true; do
        {
            read -r request
            local method=$(echo "$request" | awk '{print $1}')
            local path=$(echo "$request" | awk '{print $2}')
            
            # Read headers
            while read -r header; do
                [[ "$header" =~ $'\r' ]] && break
            done
            
            log "Request: $method $path"
            
            # Route requests
            case "$path" in
                "/")
                    html_header
                    generate_dashboard
                    html_footer
                    ;;
                "/status")
                    html_header
                    generate_status
                    html_footer
                    ;;
                "/status-data")
                    generate_status
                    ;;
                "/config")
                    html_header
                    generate_config
                    html_footer
                    ;;
                "/logs")
                    html_header
                    generate_logs
                    html_footer
                    ;;
                "/update")
                    html_header
                    generate_update
                    html_footer
                    ;;
                "/action")
                    if [[ "$method" == "POST" ]]; then
                        read -n $CONTENT_LENGTH post_data
                        local action=$(echo "$post_data" | sed 's/action=//')
                        html_header
                        echo "<div class='alert alert-success'>$(handle_action "$action")</div>"
                        generate_dashboard
                        html_footer
                    fi
                    ;;
                "/save-config")
                    if [[ "$method" == "POST" ]]; then
                        read -n $CONTENT_LENGTH post_data
                        # Save configuration logic here
                        html_header
                        echo "<div class='alert alert-success'>Configuration saved successfully!</div>"
                        generate_config
                        html_footer
                    fi
                    ;;
                *)
                    html_header
                    echo "<div class='alert alert-danger'>404 - Page not found</div>"
                    html_footer
                    ;;
            esac
        } | nc -l -p "$PANEL_PORT" -q 1
    done
}

# Main execution
main() {
    # Make script executable
    chmod +x "$PANEL_DIR/web_panel.sh"
    
    # Start the web panel
    cd "$PANEL_DIR"
    log "AGN-UDP Web Panel started on port $PANEL_PORT"
    log "Access the panel at: http://$(hostname -I | awk '{print $1}'):$PANEL_PORT"
    
    # Start web server
    start_web_server
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main
fi
EOF

    chmod +x "$PANEL_DIR/web_panel.sh"
}

# Create systemd service
create_service() {
    log "Creating systemd service..."
    
    sudo tee "/etc/systemd/system/${SERVICE_NAME}.service" > /dev/null << EOF
[Unit]
Description=AGN-UDP Web Panel
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$PANEL_DIR
ExecStart=$PANEL_DIR/web_panel.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable "$SERVICE_NAME"
}

# Configure nginx (optional)
configure_nginx() {
    log "Configuring nginx..."
    
    sudo tee "/etc/nginx/sites-available/agn-udp-panel" > /dev/null << EOF
server {
    listen 80;
    server_name _;
    
    location / {
        proxy_pass http://127.0.0.1:$PANEL_PORT;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    sudo ln -sf "/etc/nginx/sites-available/agn-udp-panel" "/etc/nginx/sites-enabled/"
    sudo nginx -t && sudo systemctl restart nginx
}

# Main installation function
main_install() {
    log "Starting AGN-UDP Web Panel installation..."
    
    check_root
    install_dependencies
    clone_repo
    create_panel_script
    create_service
    
    read -p "Configure nginx for web access? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        configure_nginx
    fi
    
    log "Installation completed successfully!"
    info "Panel directory: $PANEL_DIR"
    info "Service name: $SERVICE_NAME"
    info "Web interface: http://$(curl -s ifconfig.me):$PANEL_PORT"
    
    read -p "Start the web panel now? (y/n): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo systemctl start "$SERVICE_NAME"
        log "Web panel started!"
        sudo systemctl status "$SERVICE_NAME"
    fi
}

# Show usage
usage() {
    echo "AGN-UDP Web Panel Installer"
    echo ""
    echo "Usage: $0 [option]"
    echo ""
    echo "Options:"
    echo "  install    Install the web panel"
    echo "  start      Start the web panel"
    echo "  stop       Stop the web panel"
    echo "  restart    Restart the web panel"
    echo "  status     Check panel status"
    echo "  uninstall  Remove the web panel"
    echo "  help       Show this help message"
}

# Handle commands
case "${1:-}" in
    "install")
        main_install
        ;;
    "start")
        sudo systemctl start "$SERVICE_NAME"
        log "Web panel started"
        ;;
    "stop")
        sudo systemctl stop "$SERVICE_NAME"
        log "Web panel stopped"
        ;;
    "restart")
        sudo systemctl restart "$SERVICE_NAME"
        log "Web panel restarted"
        ;;
    "status")
        sudo systemctl status "$SERVICE_NAME"
        ;;
    "uninstall")
        log "Uninstalling AGN-UDP Web Panel..."
        sudo systemctl stop "$SERVICE_NAME" 2>/dev/null || true
        sudo systemctl disable "$SERVICE_NAME" 2>/dev/null || true
        sudo rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
        sudo rm -rf "$PANEL_DIR"
        sudo systemctl daemon-reload
        log "Uninstallation completed"
        ;;
    "help"|"")
        usage
        ;;
    *)
        error "Unknown command: $1"
        usage
        exit 1
        ;;
esac
