#!/bin/bash
# Master Script for Cloudflare DNS Manager: Adding CNAME/NS Support and Design Update

# =========================================================
# CONFIGURATION - CONFIG FILE LOCATION (Web Root အပြင်ဘက်မှ လုံခြုံသော ဖိုင်)
# =========================================================
WEB_ROOT="/var/www/html"
CONFIG_DIR="/etc/app-config"
CONFIG_FILE="${CONFIG_DIR}/cloudflare_config.php"
# =========================================================

echo "========================================================"
echo "  Step 1: Rewriting index.php (Design & Multi-Record Type) "
echo "========================================================"

# index.php ကို Design အသစ်နှင့် Record Type ရွေးချယ်မှုများဖြင့် ပြန်လည်ရေးသားသည်။
cat << 'EOF_INDEX_PHP' | sudo tee "${WEB_ROOT}/index.php" > /dev/null
<?php 
// Error Debugging ကို ဖွင့်ထားဆဲ
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

// Base Domain ကို စနစ်တကျ ထုတ်ပြရန်
// Config File (လုံခြုံရေးအရ) တွင် Domain ပါရှိသော်လည်း index.php တွင် ပြသရန်အတွက် ထည့်သွင်းသည်။
$config_file = '/etc/app-config/cloudflare_config.php';
$domain = 'zivpn-panel.cc'; // Default value

if (file_exists($config_file)) {
    $config = require $config_file;
    $domain = $config['DOMAIN'] ?? $domain;
}
?>
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DNS Manager - Record ဖန်တီး/ပြင်ဆင်</title>
    <style>
        /* Modern & Clean Design */
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background-color: #e9ecef; }
        .container { max-width: 650px; margin: auto; padding: 35px; background: #ffffff; border-radius: 15px; box-shadow: 0 8px 25px rgba(0, 0, 0, 0.15); }
        h2 { color: #0056b3; border-bottom: 4px solid #0056b3; padding-bottom: 10px; margin-bottom: 30px; text-align: center; font-size: 1.8em; }
        label { display: block; margin-bottom: 8px; font-weight: 600; color: #343a40; }
        input[type="text"], select { width: 100%; padding: 12px; margin-bottom: 20px; border: 1px solid #ced4da; border-radius: 8px; box-sizing: border-box; font-size: 16px; transition: border-color 0.3s; }
        input[type="text"]:focus, select:focus { border-color: #007bff; box-shadow: 0 0 0 0.2rem rgba(0, 123, 255, 0.25); outline: none; }
        
        .btn-primary { width: 100%; padding: 15px; background-color: #007bff; color: white; cursor: pointer; font-size: 18px; font-weight: bold; border: none; border-radius: 8px; transition: background-color 0.3s, transform 0.1s; margin-top: 15px; }
        .btn-primary:hover { background-color: #0056b3; transform: translateY(-1px); }
        
        .domain-suffix { display: block; margin-top: -15px; margin-bottom: 25px; color: #6c757d; font-weight: normal; font-size: 0.9em; padding-left: 5px; }
        
        /* Navigation Button */
        .list-btn { display: block; text-align: center; padding: 12px; margin-top: 15px; background-color: #6c757d; color: white; border-radius: 8px; text-decoration: none; font-weight: bold; transition: background-color 0.3s; }
        .list-btn:hover { background-color: #5a6268; }

        /* Result Styles (Existing styles retained for functionality) */
        .result-box { padding: 20px; border-radius: 8px; margin-top: 30px; white-space: pre-wrap; font-size: 1em; }
        .result-success { background-color: #e6ffed; border: 2px solid #28a745; color: #155724; }
        .result-error { background-color: #f8d7da; border: 2px solid #dc3545; color: #721c24; }
        .result-info { background-color: #fcefd7; border: 2px solid #ffc107; color: #856404; }
        .result-title { font-size: 1.2em; font-weight: bold; margin-bottom: 10px; border-bottom: 1px dashed #ccc; padding-bottom: 5px; }
        
        /* Input Grouping */
        .input-group { margin-bottom: 20px; }
    </style>
</head>
<body>
    <div class="container">
        <h2>🌐 Cloudflare DNS Record စီမံခန့်ခွဲမှု</h2>

        <form action="process.php?action=manage" method="POST">
            <h3>Record အသစ်ဖန်တီး / Update လုပ်မည်</h3>
            
            <div class="input-group">
                <label for="record_type">Record Type:</label>
                <select id="record_type" name="record_type" onchange="updateFormFields()">
                    <option value="A">A Record (IP Address)</option>
                    <option value="CNAME">CNAME Record (Host/Alias)</option>
                    <option value="NS">NS Record (Name Server)</option>
                </select>
            </div>

            <div class="input-group">
                <label for="subdomain">Subdomain Name:</label>
                <input type="text" id="subdomain" name="subdomain" placeholder="ဥပမာ: svp101" required>
                <span class="domain-suffix">.<?php echo htmlspecialchars($domain); ?></span>
            </div>

            <div class="input-group" id="dynamic_input_group">
                <label for="content_input" id="content_label">IP Address (A Record):</label>
                <input type="text" id="content_input" name="content_input" placeholder="ဥပမာ: 203.0.113.10 သို့မဟုတ် 'auto' ရိုက်ပါ" value="auto" required>
            </div>

            <div class="input-group" id="proxied_group">
                <label for="proxied">Cloudflare Proxy (Orange Cloud):</label>
                <select id="proxied" name="proxied">
                    <option value="false">Off (DNS Only) - Dynamic IP အတွက် အကြံပြု</option>
                    <option value="true">On (Proxied)</option>
                </select>
            </div>

            <button type="submit" class="btn-primary">DNS Record ဖန်တီး / Update လုပ်မည်</button>
        </form>

        <a href="list.php" class="list-btn">Record များ စာရင်းကြည့်ရန်</a>

        <?php 
        if (isset($_GET['result'])) {
            $data = json_decode(base64_decode($_GET['result']), true);
            $class = 'result-info'; 
            $title = 'လုပ်ဆောင်ချက် ရလဒ်:';
            $details = '';

            if (isset($data['status'])) {
                if ($data['status'] === 'SUCCESS') {
                    $class = 'result-success';
                    $title = '✅ SUCCESS: Record ဖန်တီး/ပြင်ဆင်ခြင်း အောင်မြင်ပါသည်။';
                    $details = "Record Type: " . htmlspecialchars($data['record_type']) . "\n";
                    $details .= "Subdomain: <span style='font-weight: bold;'>" . htmlspecialchars($data['record_name']) . "</span>\n";
                    $details .= "Content: " . htmlspecialchars($data['content']) . "\n";
                    if (isset($data['proxied'])) {
                        $details .= "Proxy Status: " . ($data['proxied'] ? "On (Proxied)" : "Off (DNS Only)") . "\n";
                    }
                    $details .= "\nCloudflare တွင် အသက်ဝင်နေပါပြီ။";
                } elseif ($data['status'] === 'DELETE_SUCCESS') {
                    $class = 'result-success';
                    $title = '🗑️ SUCCESS: Record ဖျက်ပစ်ခြင်း အောင်မြင်ပါသည်။';
                    $details = "ဖျက်လိုက်သော Record: <span style='font-weight: bold;'>" . htmlspecialchars($data['record_name']) . "</span>\n";
                    $details .= "Type: " . htmlspecialchars($data['record_type']) . "\n";
                } elseif ($data['status'] === 'INFO') {
                    $title = 'ℹ️ INFO: DNS Record သည် အမှန်အတိုင်းရှိနေပါသည်။';
                    $details = "Record Type: " . htmlspecialchars($data['record_type']) . "\n";
                    $details .= "Subdomain: <span style='font-weight: bold;'>" . htmlspecialchars($data['record_name']) . "</span>\n";
                    $details .= "Content: " . htmlspecialchars($data['content']) . "\n";
                    if (isset($data['proxied'])) {
                        $details .= "Proxy Status: " . ($data['proxied'] ? "On (Proxied)" : "Off (DNS Only)") . "\n";
                    }
                } elseif ($data['status'] === 'ERROR') {
                    $class = 'result-error';
                    $title = '❌ ERROR: လုပ်ဆောင်ချက် မအောင်မြင်ပါ။';
                    $details = "Cloudflare Error: " . htmlspecialchars($data['cf_error']) . "\n";
                    $details .= "HTTP Status: " . htmlspecialchars($data['http_code']) . "\n";
                    $details .= "\nFull Response: " . print_r($data['full_response'] ?? [], true);
                }
            }
            
            echo "<div class='result-box {$class}'>";
            echo "<div class='result-title'>{$title}</div>";
            echo "<div class='result-details'>{$details}</div>";
            echo "</div>";

            // JavaScript to clean the URL bar
            echo '<script>';
            echo 'if (history.replaceState) {';
            echo '  history.replaceState(null, document.title, window.location.pathname);';
            echo '}';
            echo '</script>';
        }
        ?>
    </div>
    
    <script>
        function updateFormFields() {
            const type = document.getElementById('record_type').value;
            const contentLabel = document.getElementById('content_label');
            const contentInput = document.getElementById('content_input');
            const proxiedGroup = document.getElementById('proxied_group');

            // Reset Input State
            contentInput.value = '';
            contentInput.placeholder = '';
            contentInput.setAttribute('type', 'text');
            
            // Update fields based on selected type
            if (type === 'A') {
                contentLabel.textContent = 'IP Address (A Record):';
                contentInput.placeholder = "ဥပမာ: 203.0.113.10 သို့မဟုတ် 'auto' ရိုက်ပါ";
                contentInput.value = 'auto';
                proxiedGroup.style.display = 'block'; // Show proxy option
            } else if (type === 'CNAME') {
                contentLabel.textContent = 'Target Hostname (CNAME Content):';
                contentInput.placeholder = 'ဥပမာ: www.othersite.com သို့မဟုတ် @';
                proxiedGroup.style.display = 'block'; // CNAME can also be proxied
            } else if (type === 'NS') {
                contentLabel.textContent = 'Name Server (NS Content):';
                contentInput.placeholder = 'ဥပမာ: ns1.mydnshost.com';
                proxiedGroup.style.display = 'none'; // NS cannot be proxied
            }
        }

        // Initialize form fields on page load
        document.addEventListener('DOMContentLoaded', updateFormFields);
    </script>
</body>
</html>
EOF_INDEX_PHP

echo "========================================================"
echo "  Step 2: Rewriting process.php (CNAME/NS Logic Integration) "
echo "========================================================"

# process.php ကို A, CNAME, NS Record များအတွက် API logic များဖြင့် ပြန်လည်ရေးသားသည်။
cat << EOF_PHP | sudo tee "${WEB_ROOT}/process.php" > /dev/null
<?php
// Error Debugging
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

// =========================================================
// CONFIGURATION (Secure Config File မှ ခေါ်ယူခြင်း)
// =========================================================
\$config_file = '${CONFIG_FILE}';
if (!file_exists(\$config_file)) {
    die("Error: Configuration file not found at " . \$config_file);
}

\$config = require \$config_file;

\$api_token = \$config['API_TOKEN']; 
\$zone_id = \$config['ZONE_ID']; 
\$domain = \$config['DOMAIN'];

// Default TTL for all records
\$ttl = 1; 

// Helper function to redirect with JSON result
function redirect_with_result(\$status, \$message_data) {
    \$output_data = array_merge(['status' => \$status], \$message_data);
    \$encoded_result = base64_encode(json_encode(\$output_data));
    // Always redirect back to index.php after any action
    header("Location: index.php?result=" . \$encoded_result);
    exit();
}

// =========================================================
// ACTION ROUTING
// =========================================================
\$action = \$_GET['action'] ?? 'manage';

if (\$_SERVER['REQUEST_METHOD'] !== 'POST' && \$action !== 'delete') {
    if (\$action === 'manage') {
        header("Location: index.php"); 
        exit();
    }
}

if (\$action === 'manage') {
    handle_manage_record();
} elseif (\$action === 'delete') {
    handle_delete_record();
} else {
    header("Location: index.php"); 
    exit();
}

// FUNCTION: MANAGE (CREATE/UPDATE) RECORD
function handle_manage_record() {
    global \$api_token, \$zone_id, \$domain, \$ttl;

    \$record_type = trim(\$_POST['record_type'] ?? 'A');
    \$subdomain = trim(\$_POST['subdomain'] ?? '');
    \$content_input = trim(\$_POST['content_input'] ?? '');
    \$proxied = (\$_POST['proxied'] === 'true') ? true : false;
    
    // NS Record များအတွက် Proxy ကို အမြဲ Off လုပ်ရန်
    if (\$record_type === 'NS') {
        \$proxied = false;
    }

    if (empty(\$subdomain) || empty(\$content_input)) {
        redirect_with_result('ERROR', ['cf_error' => 'Subdomain သို့မဟုတ် Content ကို ဖြည့်သွင်းရန် လိုအပ်ပါသည်။', 'http_code' => 400]);
    }

    \$record_name = \$subdomain . '.' . \$domain;
    \$content_value = \$content_input;

    // A Record အတွက် 'auto' IP ကိုင်တွယ်ခြင်း
    if (\$record_type === 'A') {
        if (strtolower(\$content_input) === 'auto') {
            \$content_value = @trim(file_get_contents('https://api.ipify.org'));
            if (empty(\$content_value)) {
                redirect_with_result('ERROR', ['cf_error' => 'IP Address ကို အလိုအလျောက် ရယူရာတွင် မအောင်မြင်ပါ။', 'http_code' => 500]);
            }
        } elseif (!filter_var(\$content_value, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4)) {
            redirect_with_result('ERROR', ['cf_error' => "A Record Content (\$content_value) သည် မှန်ကန်သော IPv4 ပုံစံမဟုတ်ပါ။", 'http_code' => 400]);
        }
    }
    
    // 1. လက်ရှိ DNS Record ကို ရှာဖွေခြင်း
    \$ch = curl_init("https://api.cloudflare.com/client/v4/zones/\$zone_id/dns_records?type=\$record_type&name=\$record_name");
    curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt(\$ch, CURLOPT_HTTPHEADER, array(
        "Authorization: Bearer \$api_token",
        "Content-Type: application/json"
    ));
    \$response = curl_exec(\$ch);
    \$http_code = curl_getinfo(\$ch, CURLINFO_HTTP_CODE);
    curl_close(\$ch);

    \$data = json_decode(\$response, true);

    if (\$http_code !== 200 || !(\$data['success'] ?? false)) {
        \$cf_error = \$data['errors'][0]['message'] ?? 'Unknown API Query Error (Search)';
        redirect_with_result('ERROR', ['cf_error' => \$cf_error, 'http_code' => \$http_code, 'full_response' => \$data]);
    }

    \$record_id = \$data['result'][0]['id'] ?? null;
    \$current_content = \$data['result'][0]['content'] ?? null;
    \$current_proxied = \$data['result'][0]['proxied'] ?? null; 
    \$action_url = '';
    \$method = '';

    // 2. စီမံခန့်ခွဲခြင်း (Create or Update)
    if (\$record_id) {
        // အချက်အလက်များ မပြောင်းလဲပါက INFO ပြ
        if (\$current_content === \$content_value && (\$record_type === 'NS' || \$current_proxied == \$proxied)) {
            redirect_with_result('INFO', ['record_name' => \$record_name, 'content' => \$content_value, 'proxied' => \$proxied, 'record_type' => \$record_type]);
        }
        
        \$action_url = "https://api.cloudflare.com/client/v4/zones/\$zone_id/dns_records/\$record_id";
        \$method = 'PUT';

    } else {
        \$action_url = "https://api.cloudflare.com/client/v4/zones/\$zone_id/dns_records";
        \$method = 'POST';
    }

    // Final API Call (Create or Update)
    \$api_data_array = [
        'type' => \$record_type,
        'name' => \$subdomain,
        'content' => \$content_value,
        'ttl' => \$ttl,
        'proxied' => \$proxied
    ];
    
    // NS Record အတွက် Proxied field ဖြုတ်ရန်
    if (\$record_type === 'NS') {
        unset(\$api_data_array['proxied']);
    }

    \$api_data = json_encode(\$api_data_array);

    \$ch = curl_init(\$action_url);
    curl_setopt(\$ch, CURLOPT_CUSTOMREQUEST, \$method);
    curl_setopt(\$ch, CURLOPT_POSTFIELDS, \$api_data);
    curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt(\$ch, CURLOPT_HTTPHEADER, array(
        "Authorization: Bearer \$api_token",
        "Content-Type: application/json",
        'Content-Length: ' . strlen(\$api_data)
    ));
    \$final_response = curl_exec(\$ch);
    \$final_http_code = curl_getinfo(\$ch, CURLINFO_HTTP_CODE);
    curl_close(\$ch);

    \$final_data = json_decode(\$final_response, true);

    if (\$final_http_code >= 200 && \$final_http_code < 300 && (\$final_data['success'] ?? false)) {
        redirect_with_result('SUCCESS', ['record_name' => \$record_name, 'content' => \$content_value, 'proxied' => \$proxied, 'record_type' => \$record_type]);
    } else {
        \$cf_error = \$final_data['errors'][0]['message'] ?? 'Unknown API Error (Create/Update)';
        redirect_with_result('ERROR', ['cf_error' => \$cf_error, 'http_code' => \$final_http_code, 'full_response' => \$final_data]);
    }
}


// FUNCTION: DELETE RECORD
function handle_delete_record() {
    global \$api_token, \$zone_id;

    \$record_id = trim(\$_POST['record_id'] ?? '');
    \$record_name = trim(\$_POST['record_name'] ?? '');
    \$record_type = trim(\$_POST['record_type'] ?? 'A');

    if (empty(\$record_id) || empty(\$record_name)) {
        redirect_with_result('ERROR', ['cf_error' => 'Delete လုပ်ရန် Record ID မပြည့်စုံပါ။', 'http_code' => 400]);
    }
    
    // API Call: DELETE
    \$action_url = "https://api.cloudflare.com/client/v4/zones/\$zone_id/dns_records/\$record_id";

    \$ch = curl_init(\$action_url);
    curl_setopt(\$ch, CURLOPT_CUSTOMREQUEST, 'DELETE');
    curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt(\$ch, CURLOPT_HTTPHEADER, array(
        "Authorization: Bearer \$api_token",
        "Content-Type: application/json"
    ));
    \$final_response = curl_exec(\$ch);
    \$final_http_code = curl_getinfo(\$ch, CURLINFO_HTTP_CODE);
    curl_close(\$ch);

    \$final_data = json_decode(\$final_response, true);

    if (\$final_http_code === 200 && (\$final_data['success'] ?? false)) {
        redirect_with_result('DELETE_SUCCESS', ['record_name' => \$record_name, 'record_type' => \$record_type]);
    } else {
        \$cf_error = \$final_data['errors'][0]['message'] ?? 'Unknown API Error during delete';
        redirect_with_result('ERROR', ['cf_error' => \$cf_error, 'http_code' => \$final_http_code, 'full_response' => \$final_data]);
    }
}
?>
EOF_PHP


echo "========================================================"
echo "  Step 3: Rewriting list.php (All Record Types Listing) "
echo "========================================================"

# list.php ကို All Record Types များကို တစ်ခါတည်း ပြသနိုင်ရန် ပြင်ဆင်ခြင်း
cat << EOF_LIST_PHP | sudo tee "${WEB_ROOT}/list.php" > /dev/null
<?php
// Error Debugging
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

// =========================================================
// CONFIGURATION (Secure Config File မှ ခေါ်ယူခြင်း)
// =========================================================
\$config_file = '${CONFIG_FILE}';
if (!file_exists(\$config_file)) {
    die("Error: Configuration file not found at " . \$config_file);
}

\$config = require \$config_file;

\$api_token = \$config['API_TOKEN']; 
\$zone_id = \$config['ZONE_ID']; 
\$domain = \$config['DOMAIN'];

// 1. Cloudflare မှ DNS Record အားလုံးကို ရယူခြင်း (Type အားလုံးပါဝင်ရန် type parameter ဖြုတ်ထားသည်)
function fetch_records(\$api_token, \$zone_id) {
    // A, CNAME, NS Record များ အားလုံးပါဝင်ရန် type parameter ဖြုတ်ထားသည်
    \$url = "https://api.cloudflare.com/client/v4/zones/\$zone_id/dns_records?per_page=100"; 
    
    \$ch = curl_init(\$url);
    curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt(\$ch, CURLOPT_HTTPHEADER, array(
        "Authorization: Bearer \$api_token",
        "Content-Type: application/json"
    ));
    \$response = curl_exec(\$ch);
    \$http_code = curl_getinfo(\$ch, CURLINFO_HTTP_CODE);
    curl_close(\$ch);

    \$data = json_decode(\$response, true);

    if (\$http_code !== 200 || !(\$data['success'] ?? false)) {
        \$error_message = \$data['errors'][0]['message'] ?? 'Unknown API Query Error';
        return ['error' => true, 'message' => \$error_message, 'full_response' => \$data];
    }
    return ['error' => false, 'records' => \$data['result'] ?? []];
}

\$result = fetch_records(\$api_token, \$zone_id);
\$records = \$result['records'] ?? [];

// Filter: Root domain (zivpn-panel.cc) နှင့် Cloudflare Default Record များကို ချန်လှပ်ထားသည်
\$filtered_records = array_filter(\$records, function(\$record) use (\$domain) {
    // Filter only A, CNAME, NS records that are NOT the root domain itself
    \$valid_type = in_array(\$record['type'], ['A', 'CNAME', 'NS']);
    \$is_not_root = (\$record['name'] !== \$domain);
    return \$valid_type && \$is_not_root;
});

?>
<!DOCTYPE html>
<html lang="my">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>DNS Records များစာရင်း</title>
    <style>
        /* Design based on index.php (Modern & Clean) */
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 0; padding: 20px; background-color: #e9ecef; }
        .container { max-width: 950px; margin: auto; padding: 35px; background: #ffffff; border-radius: 15px; box-shadow: 0 8px 25px rgba(0, 0, 0, 0.15); }
        h2 { color: #0056b3; border-bottom: 4px solid #0056b3; padding-bottom: 10px; margin-bottom: 30px; text-align: center; font-size: 1.8em; }
        
        /* Navigation Button */
        .back-btn { display: inline-block; padding: 10px 15px; margin-bottom: 25px; background-color: #6c757d; color: white; border-radius: 8px; text-decoration: none; font-weight: bold; transition: background-color 0.3s; }
        .back-btn:hover { background-color: #5a6268; }

        /* Error/Info Box */
        .info-box { padding: 15px; border-radius: 8px; margin-top: 20px; background-color: #fcefd7; border: 2px solid #ffc107; color: #856404; font-weight: bold; }
        .error-box { padding: 15px; border-radius: 8px; margin-top: 20px; background-color: #f8d7da; border: 2px solid #dc3545; color: #721c24; font-weight: bold; }

        /* Record Table Design */
        .record-table { width: 100%; border-collapse: collapse; margin-top: 15px; font-size: 0.9em; table-layout: fixed; }
        .record-table th, .record-table td { padding: 12px 10px; text-align: left; border-bottom: 1px solid #dee2e6; word-wrap: break-word; }
        .record-table th { background-color: #007bff; color: white; font-weight: 600; }
        .record-table tr:nth-child(even) { background-color: #f8f9fa; }
        .record-table .delete-form { margin: 0; text-align: center; }
        .delete-btn { background-color: #dc3545; color: white; border: none; padding: 6px 12px; border-radius: 4px; cursor: pointer; transition: background-color 0.3s; font-size: 0.9em; }
        .delete-btn:hover { background-color: #c82333; }
        .proxy-on { color: #ff9900; font-weight: bold; }
        .proxy-off { color: #28a745; font-weight: bold; }
        .type-badge { display: inline-block; padding: 4px 8px; border-radius: 4px; font-weight: bold; font-size: 0.85em; }
        .type-A { background-color: #007bff; color: white; }
        .type-CNAME { background-color: #28a745; color: white; }
        .type-NS { background-color: #ffc107; color: #343a40; }
        .type-OTHER { background-color: #6c757d; color: white; }

        /* Card view for mobile (Simplified) */
        .record-card-list { display: none; }
        @media (max-width: 768px) {
            .record-table { display: none; }
            .record-card-list { display: block; }
            .record-card {
                background: #fff;
                border: 1px solid #ddd;
                border-radius: 8px;
                padding: 15px;
                margin-bottom: 15px;
                box-shadow: 0 2px 5px rgba(0,0,0,0.05);
            }
            .card-item { padding: 5px 0; border-bottom: 1px dotted #eee; }
            .card-label { font-weight: bold; color: #555; display: inline-block; width: 35%; }
            .card-value { display: inline-block; width: 60%; text-align: right; }
        }
    </style>
</head>
<body>
    <div class="container">
        <a href="index.php" class="back-btn">← Record ဖန်တီးရန် စာမျက်နှာသို့</a>
        <h2>📊 လက်ရှိ DNS Record များစာရင်း (<?php echo htmlspecialchars(\$domain); ?>)</h2>
        
        <?php if (\$result['error']): ?>
            <div class='error-box'>❌ ERROR: Record စာရင်းရယူရာတွင် မအောင်မြင်ပါ။ <?php echo htmlspecialchars(\$result['message']); ?></div>
        <?php elseif (empty(\$filtered_records)): ?>
            <div class='info-box'>ℹ️ လက်ရှိတွင် A, CNAME, NS Record များ မရှိသေးပါ သို့မဟုတ် Domain Root Record များသာ ရှိပါသည်။</div>
        <?php else: ?>
            
            <table class="record-table">
                <thead>
                    <tr>
                        <th style="width: 10%;">Type</th>
                        <th style="width: 30%;">Subdomain</th>
                        <th style="width: 40%;">Content (Value)</th>
                        <th style="width: 10%;">Proxy</th>
                        <th style="width: 10%;">Action</th>
                    </tr>
                </thead>
                <tbody>
                    <?php foreach (\$filtered_records as \$record): 
                        \$subdomain_only = str_replace("." . \$domain, "", \$record['name']);
                        \$proxy_status = isset(\$record['proxied']) 
                            ? (\$record['proxied'] ? "<span class='proxy-on'>Proxied (On)</span>" : "<span class='proxy-off'>DNS Only (Off)</span>")
                            : "N/A"; // NS Records will be N/A
                        
                        \$type_class = 'type-' . \$record['type'];
                    ?>
                        <tr>
                            <td><span class="type-badge <?php echo \$type_class; ?>"><?php echo htmlspecialchars(\$record['type']); ?></span></td>
                            <td><?php echo htmlspecialchars(\$subdomain_only); ?></td>
                            <td><?php echo htmlspecialchars(\$record['content']); ?></td>
                            <td><?php echo \$proxy_status; ?></td>
                            <td>
                                <form action='process.php?action=delete' method='POST' style='margin: 0;' onsubmit="return confirm('<?php echo htmlspecialchars(\$record['name']); ?> (<?php echo htmlspecialchars(\$record['type']); ?>) ကို ဖျက်တော့မှာ သေချာပါသလား?');">
                                    <input type='hidden' name='record_id' value='<?php echo htmlspecialchars(\$record['id']); ?>'>
                                    <input type='hidden' name='record_name' value='<?php echo htmlspecialchars(\$record['name']); ?>'>
                                    <input type='hidden' name='record_type' value='<?php echo htmlspecialchars(\$record['type']); ?>'>
                                    <button type='submit' class='delete-btn'>🗑️ ဖျက်မည်</button>
                                </form>
                            </td>
                        </tr>
                    <?php endforeach; ?>
                </tbody>
            </table>
            
            <div class="record-card-list">
                <?php foreach (\$filtered_records as \$record): 
                    \$subdomain_only = str_replace("." . \$domain, "", \$record['name']);
                    \$proxy_status = isset(\$record['proxied']) 
                        ? (\$record['proxied'] ? "<span class='proxy-on'>Proxied (On)</span>" : "<span class='proxy-off'>DNS Only (Off)</span>")
                        : "N/A";
                    \$type_class = 'type-' . \$record['type'];
                ?>
                    <div class="record-card">
                        <div class="card-item"><span class="card-label">Type:</span> <span class="card-value"><span class="type-badge <?php echo \$type_class; ?>"><?php echo htmlspecialchars(\$record['type']); ?></span></span></div>
                        <div class="card-item"><span class="card-label">Subdomain:</span> <span class="card-value"><?php echo htmlspecialchars(\$subdomain_only); ?></span></div>
                        <div class="card-item"><span class="card-label">Content:</span> <span class="card-value"><?php echo htmlspecialchars(\$record['content']); ?></span></div>
                        <div class="card-item"><span class="card-label">Proxy Status:</span> <span class="card-value"><?php echo \$proxy_status; ?></span></div>
                        <div style="margin-top: 10px; text-align: center;">
                            <form action='process.php?action=delete' method='POST' style='margin: 0;' onsubmit="return confirm('<?php echo htmlspecialchars(\$record['name']); ?> (<?php echo htmlspecialchars(\$record['type']); ?>) ကို ဖျက်တော့မှာ သေချာပါသလား?');">
                                <input type='hidden' name='record_id' value='<?php echo htmlspecialchars(\$record['id']); ?>'>
                                <input type='hidden' name='record_name' value='<?php echo htmlspecialchars(\$record['name']); ?>'>
                                <input type='hidden' name='record_type' value='<?php echo htmlspecialchars(\$record['type']); ?>'>
                                <button type='submit' class='delete-btn'>🗑️ ဖျက်မည်</button>
                            </form>
                        </div>
                    </div>
                <?php endforeach; ?>
            </div>

        <?php endif; ?>
    </div>
</body>
</html>
EOF_LIST_PHP

echo "========================================================"
echo "  Step 4: Restarting Apache Server "
echo "========================================================"
sudo systemctl restart apache2

echo "========================================================"
echo "✅ CNAME/NS Support နှင့် Design Update ပြီးဆုံးပါပြီ။"
echo "Browser Cache ကို ရှင်းလင်းပြီး http://185.84.161.211/index.php ကို ဖွင့်ပါ။"
echo "========================================================"
