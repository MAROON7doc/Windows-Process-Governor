# WRAPPER TO CATCH ERRORS AND KEEP WINDOW OPEN
try {
    # --- AUTO-ADMIN CHECK ---
    if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Re-launching as Administrator..." -ForegroundColor Yellow
        Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        Exit
    }

    # --- CONFIGURATION ---
    $Config = @{
        LogFile          = "$env:TEMP\GovernorLog.txt"
        CriticalServices = @("Audiosrv", "Spooler", "wuauserv", "Dhcp", "SysMain") 
        # Only clean temp if drive C has less than this many GB free
        MinDiskSpaceGB   = 10 
    }

    # --- WIN32 API ---
    # We check if the type exists first to avoid errors on script re-runs in ISE
    if (-not ([System.Management.Automation.PSTypeName]'Win32').Type) {
        Add-Type -TypeDefinition @"
        using System;
        using System.Runtime.InteropServices;
        public class Win32 {
            [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
            [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out int lpdwProcessId);
        }
"@ -ErrorAction Stop
    }

    # --- HELPER FUNCTIONS ---
    function Write-GovLog ($Message) {
        $Line = "[$(Get-Date -Format 'HH:mm:ss')] $Message"
        Write-Host $Line -ForegroundColor Cyan
    }

    # --- STATE TRACKING ---
    $Global:LastActivePID = 0
    $Global:LastHwnd = [IntPtr]::Zero
    # Hash table to track modified processes so we can revert them on exit
    $Global:ModifiedProcesses = @{} 

    # --- MAIN LOGIC ---
    $Host.UI.RawUI.WindowTitle = ">> GOVERNOR ACTIVE (Ctrl+C to Quit) <<"
    Clear-Host
    Write-GovLog "Governor Started. Optimized Mode."
    Write-GovLog "Minimizing this window reduces overhead."

    $TickCounter = 0

    try {
        while ($true) {
            # --- 1. FAST LOOP (Priority Boosting) ---
            
            # Get current window handle
            $CurrentHwnd = [Win32]::GetForegroundWindow()

            # OPTIMIZATION: Only process logic if the window actually changed
            if ($CurrentHwnd -ne [IntPtr]::Zero -and $CurrentHwnd -ne $Global:LastHwnd) {
                
                $ProcId = 0
                [void][Win32]::GetWindowThreadProcessId($CurrentHwnd, [ref]$ProcId)
                
                # Double check that we are actually on a new process ID
                if ($ProcId -ne $Global:LastActivePID) {
                    
                    # A. Revert the PREVIOUS process to Normal
                    if ($Global:LastActivePID -gt 0) {
                        $OldProc = Get-Process -Id $Global:LastActivePID -ErrorAction SilentlyContinue
                        if ($OldProc) {
                            # Restore to Normal (or tracking logic could be added here to restore specific previous state)
                            $OldProc.PriorityClass = 'Normal'
                        }
                    }

                    # B. Boost the NEW process
                    $NewProc = Get-Process -Id $ProcId -ErrorAction SilentlyContinue
                    if ($NewProc) {
                        # Track it so we can undo on exit
                        if (-not $Global:ModifiedProcesses.ContainsKey($NewProc.Id)) {
                            $Global:ModifiedProcesses[$NewProc.Id] = $NewProc.ProcessName
                        }

                        # Only boost if not already High/RealTime
                        if ($NewProc.PriorityClass -ne 'High' -and $NewProc.PriorityClass -ne 'RealTime') {
                            $NewProc.PriorityClass = 'High'
                            Write-Host "[★] Boosted: $($NewProc.ProcessName)" -ForegroundColor Green
                        }
                    }

                    $Global:LastActivePID = $ProcId
                    $Global:LastHwnd = $CurrentHwnd
                }
            }

            # --- 2. SLOW LOOP (Maintenance - Every 30s approx) ---
            $TickCounter++
            if ($TickCounter -ge 60) { 
                # Run this in a distinct try/catch so it doesn't crash the main loop
                try {
                    # Service Check
                    foreach ($SvcName in $Config.CriticalServices) {
                        $Svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
                        if ($Svc -and $Svc.Status -eq 'Stopped') {
                            Write-GovLog "Restarting Service: $SvcName"
                            Start-Service -Name $SvcName -ErrorAction SilentlyContinue
                        }
                    }

                    # Temp Cleanup
                    $Drive = Get-PSDrive C -ErrorAction SilentlyContinue
                    if ($Drive -and ($Drive.Free / 1GB) -lt $Config.MinDiskSpaceGB) {
                        # Using Start-Job for cleanup prevents the UI from freezing during delete
                        Start-Job -ScriptBlock { Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue } | Out-Null
                        Write-GovLog "Cleaned Temp Files (Background Job)."
                    }
                } catch {
                    Write-GovLog "Maintenance Error: $($_.Exception.Message)"
                }
                $TickCounter = 0
            }

            Start-Sleep -Milliseconds 500
        }
    }
    finally {
        # --- UNDO CHANGES (Runs on Exit/Ctrl+C) ---
        Write-Host "`n[!] Shutting down... Reverting changes..." -ForegroundColor Yellow
        
        # 1. Revert current active process immediately
        if ($Global:LastActivePID -gt 0) {
            $CurrentProc = Get-Process -Id $Global:LastActivePID -ErrorAction SilentlyContinue
            if ($CurrentProc) { 
                $CurrentProc.PriorityClass = 'Normal'
                Write-Host " -> Reverted Active: $($CurrentProc.ProcessName)" -ForegroundColor Gray
            }
        }

        # 2. Check all historically touched processes just in case
        foreach ($pidKey in $Global:ModifiedProcesses.Keys) {
            $hProc = Get-Process -Id $pidKey -ErrorAction SilentlyContinue
            if ($hProc -and $hProc.PriorityClass -eq 'High') {
                $hProc.PriorityClass = 'Normal'
                Write-Host " -> Reverted History: $($hProc.ProcessName)" -ForegroundColor Gray
            }
        }
        
        Write-Host "Done. Goodbye." -ForegroundColor Cyan
        Start-Sleep -Seconds 1
    }
}
catch {
    Write-Host "CRITICAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Read-Host "Press ENTER to exit..."
}