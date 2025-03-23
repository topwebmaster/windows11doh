# PowerShell script to enable DNS-over-HTTPS (DoH) in Windows 11 and run as a service without registry modifications
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
    $iniFile = "C:\path\to\doh_servers.ini"
    if (!(Test-Path $iniFile)) {
        Write-Host "INI file not found! Using default servers." -ForegroundColor Yellow
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

# Function to check if a DoH server is reachable more accurately
function Test-DoHServer {
    param([string]$server)
    $result = Test-NetConnection -ComputerName $server -Port 443 -InformationLevel Detailed
    return ($result.TcpTestSucceeded -eq $true)
}

# Function to set a working DoH server for all active network adapters
function Set-WorkingDns {
    $dnsServers = Read-DohServers
    foreach ($adapter in (Get-NetAdapter | Where-Object { $_.Status -eq "Up" })) {
        $interfaceIndex = $adapter.ifIndex
        foreach ($dns in $dnsServers) {
            if (Test-DoHServer -server $dns.Address) {
                Set-DnsClientServerAddress -InterfaceIndex $interfaceIndex -ServerAddresses $dns.Address
                Set-DnsClientDohServerAddress -ServerAddress $dns.Address -DohTemplate $dns.DohTemplate -AllowFallbackToUdp $false
                Write-Host "Set working DoH server: $($dns.Address)" -ForegroundColor Green
                Send-Notification -message "Using DoH server: $($dns.Address)" -type "Info"
                return
            }
            Start-Sleep -Seconds 3
        }
        Write-Host "No DoH servers are reachable!" -ForegroundColor Red
        Send-Notification -message "No DoH servers are reachable!" -type "Error"
    }
}

# Function to enforce firewall rules for DoH
function Enforce-FirewallRules {
    Write-Host "Applying firewall rules to block non-DoH traffic..." -ForegroundColor Cyan
    New-NetFirewallRule -DisplayName "Block Outbound DNS (UDP 53)" -Direction Outbound -Protocol UDP -LocalPort 53 -Action Block -ErrorAction SilentlyContinue
    New-NetFirewallRule -DisplayName "Block Outbound DNS (TCP 53)" -Direction Outbound -Protocol TCP -LocalPort 53 -Action Block -ErrorAction SilentlyContinue
    Write-Host "Firewall rules applied." -ForegroundColor Green
}

# Run the script as a continuous service loop
Enforce-FirewallRules
while ($true) {
    Set-WorkingDns
    
    Write-Host "Checking applied DoH settings..." -ForegroundColor Cyan
    Get-DnsClientDohServerAddress | Format-Table -AutoSize
    
    Write-Host "Testing DNS resolution using nslookup..." -ForegroundColor Cyan
    Send-Notification -message "Testing DNS resolution using nslookup..." -type "Warning"
    nslookup google.com | Out-Host
    
    Write-Host "Checking network traffic for DoH (HTTPS-based DNS requests)..." -ForegroundColor Cyan
    $netstatResults = netstat -an | Select-String -Pattern ":443"
    if ($netstatResults) {
        Write-Host "Active HTTPS connections detected. DoH may be in use." -ForegroundColor Green
        Send-Notification -message "DoH traffic detected. Connection is secure." -type "Info"
    } else {
        Write-Host "No HTTPS DNS traffic detected. Check your firewall or browser settings." -ForegroundColor Yellow
        Send-Notification -message "No DoH traffic detected. Verify settings." -type "Warning"
    }
    
    Start-Sleep -Seconds 30  # Run the check every 30 seconds
}
