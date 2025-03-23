# windows11doh
DoH for windows 11

1. **Prepare the INI File:**
   - Create a file at `C:\path\to\doh_servers.ini`.
   - Add DoH servers in the format: `IP=DoH_Template_URL` (one per line), e.g.:
     ```
     8.8.8.8=https://dns.google/dns-query
     1.1.1.1=https://cloudflare-dns.com/dns-query
     ```

2. **Run the Script:**
   - Open PowerShell as Administrator.
   - Execute: `powershell -ExecutionPolicy Bypass -File path\to\this_script.ps1`

3. **How it Works:**
   - Reads DoH servers from the INI file.
   - Tests the availability of each DoH server.
   - Configures the system to use an available DoH server.
   - Blocks non-DoH DNS traffic using firewall rules.
   - Runs continuously, checking and enforcing DoH settings every 30 seconds.

4. **Stopping the Script:**
   - Use `Ctrl + C` to terminate execution.
   - Remove the firewall rules manually if needed:
     ```
     Remove-NetFirewallRule -DisplayName "Block Outbound DNS (UDP 53)"
     Remove-NetFirewallRule -DisplayName "Block Outbound DNS (TCP 53)"
     ```
