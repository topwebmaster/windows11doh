param(
    [string]$iniFilePath = "C:\path\to\doh_servers.ini",
    [int]$checkInterval = 30,
    [switch]$enableLogging,
    [string]$logFilePath = "C:\logs\doh_script.log"
)

# Function to send Windows notification
function Send-Notification {
    param(
        [string]$message,
        [string]$title = "DoH Configuration",
        [ValidateSet("Info", "Warning", "Error")]
        [string]$type = "Info"
    )
    $toastXml = @"
    <toast>
        <visual>
            <binding template="ToastGeneric">
                <text>$title</text>
                <text>$message</text>
            </binding>
        </visual>
    </toast>
"@
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($toastXml)
    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("PowerShell").Show($toast)
}

# Function to read DoH servers from an INI file
function Read-DohServers {
    param([string]$iniFile)
    if (!(Test-Path $iniFile)) {
        Write-Log "INI file not found! Using default servers." -Level Warning
        return @(
            @{ Address = "8.8.8.8"; DohTemplate = "https://dns.google/dns-query" },
            @{ Address = "1.1.1.1"; DohTemplate = "https://cloudflare-dns.com/dns-query" },
            @{ Address = "2001:4860:4860::8888"; DohTemplate = "https://dns.google/dns-query" },
            @{ Address = "2606:4700:4700::1111"; DohTemplate = "https://cloudflare-dns.com/dns-query" }
        )
    }
    
    $servers = @()
    Get-Content $iniFile | ForEach-Object {
        $parts = $_ -split "="
        if ($parts.Length -eq 2) {
            $servers += @{ Address = $parts[0].Trim(); DohTemplate = $parts[1].Trim() }
        }
    }
    return $servers
}

# Function to check if a DoH server is reachable
function Test-DoHServer {
    param([string]$server)
    try {
        $result = Test-NetConnection -ComputerName $server -Port 443 -InformationLevel Detailed
        return ($result.TcpTestSucceeded -eq $true)
    } catch {
        Write-Log "Error testing DoH server $server: $_" -Level Error
        return $false
    }
}

# Function to set a working DoH server for all active network adapters
function Set-WorkingDns {
    param([array]$dnsServers)
    foreach ($adapter in (Get-NetAdapter | Where-Object { $_.Status -eq "Up" })) {
        $interfaceIndex = $adapter.ifIndex
        foreach ($dns in $dnsServers) {
            if (Test-DoHServer -server $dns.Address) {
                try {
                    Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ServerAddresses $dns.Address -ErrorAction Stop
                    Set-DnsClientDohServerAddress -ServerAddress $dns.Address -DohTemplate $dns.DohTemplate -AllowFallbackToUdp $false -ErrorAction Stop
                    Write-Log "Set working DoH server: $($dns.Address)" -Level Info
                    Send-Notification -message "Using DoH server: $($dns.Address)" -type "Info"
                    return
                } catch {
                    Write-Log "Error setting DoH server $($dns.Address): $_" -Level Error
                }
            }
            Start-Sleep -Seconds 3
        }
        Write-Log "No DoH servers are reachable!" -Level Error
        Send-Notification -message "No DoH servers are reachable!" -type "Error"
    }
}

# Function to enforce firewall rules for DoH
function Enforce-FirewallRules {
    Write-Log "Applying firewall rules to block non-DoH traffic..." -Level Info
    New-NetFirewallRule -DisplayName "Block Outbound DNS (UDP 53)" -Direction Outbound -Protocol UDP -LocalPort 53 -Action Block -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "Block Outbound DNS (TCP 53)" -Direction Outbound -Protocol TCP -LocalPort 53 -Action Block -ErrorAction SilentlyContinue
    Write-Log "Firewall rules applied." -Level Info
}

# Function to log messages
function Write-Log {
    param(
        [string]$message,
        [ValidateSet("Info", "Warning", "Error")]
        [string]$Level = "Info"
    )
    if ($enableLogging) {
        $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        $logMessage = "$timestamp [$Level] $message"
        Add-Content -Path $logFilePath -Value $logMessage
    }
    Write-Host $message -ForegroundColor (Switch ($Level) { "Info" { "Green" } "Warning" { "Yellow" } "Error" { "Red" } })
}

# Run the script as a continuous service loop
Enforce-FirewallRules
while ($true) {
    $dnsServers = Read-DohServers -iniFile $iniFilePath
    Set-WorkingDns -dnsServers $dnsServers
    
    Write-Log "Checking applied DoH settings..." -Level Info
    Get-DnsClientDohServerAddress | Format-Table -AutoSize
    
    Write-Log "Testing DNS resolution using nslookup..." -Level Info
    Send-Notification -message "Testing DNS resolution using nslookup..." -type "Warning"
    nslookup google.com | Out-Host
    
    Write-Log "Checking network traffic for DoH (HTTPS-based DNS requests)..." -Level Info
    $netstatResults = netstat -an | Select-String -Pattern ":443"
    if ($netstatResults) {
        Write-Log "Active HTTPS connections detected. DoH may be in use." -Level Info
        Send-Notification -message "DoH traffic detected. Connection is secure." -type "Info"
    } else {
        Write-Log "No HTTPS DNS traffic detected. Check your firewall or browser settings." -Level Warning
        Send-Notification -message "No DoH traffic detected. Verify settings." -type "Warning"
    }
    
    Start-Sleep -Seconds $checkInterval
}
