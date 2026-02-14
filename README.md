# Windows Process Governor ⚡

A lightweight, efficient PowerShell utility that dynamically manages Windows process priorities to ensure your active window always gets the most CPU resources.

## 🚀 How It Works
This script runs in the background and monitors your active (foreground) window.
1.  **Dynamic Boosting:** When you switch to a new window, the script automatically sets its process priority to **High**.
2.  **Smart Reverting:** When you switch *away* from that window, it reverts the priority back to **Normal**.
3.  **Zero Overhead:** It uses "smart polling" (caching the window handle) to ensure the script itself uses negligible CPU.

## ✨ Key Features
* **Auto-Admin:** Automatically requests Administrator privileges if started without them.
* **Safety First:** Includes a `SafeProcessList` to prevent tampering with critical Windows system processes.
* **Graceful Exit:** If you close the script or press `Ctrl+C`, it automatically runs a cleanup routine to **undo all changes** and reset processes to Normal priority.
* **Maintenance Mode:** Every 60 seconds, it checks for stopped critical services (like Audio) and attempts to restart them.

## 🛠️ Usage

1.  Download `ProcessGovernor.ps1` from this repository.
2.  Right-click the file and select **Run with PowerShell**.
3.  Accept the Administrator prompt.
4.  Minimize the terminal window and enjoy a snappier system.

**To Stop:**
Open the terminal window and press `Ctrl+C`. The script will display a "Reverting changes..." message and exit cleanly.

## ⚠️ Disclaimer
This script modifies system process priorities. While it includes safety checks, use it at your own risk. It is recommended to test it with your specific workflow.
