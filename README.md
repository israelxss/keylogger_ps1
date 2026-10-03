# Threat Analysis Report: In-Memory PowerShell Keylogger

## 1. VirusTotal Detection Overview
**Analysis Link:** [VirusTotal Report](https://www.virustotal.com/gui/file/a216497c71896cfffbbc23a2ed8bb35872c6013d3abc75d8db32a2ede6ea1004/detection)

When analyzing scripts of this nature on VirusTotal, detection engines often flag them using heuristic or generic signatures (e.g., `HEUR:Trojan.PowerShell`, `RiskWare.Keylogger`, or `Spyware.MSIL`). 

If the detection ratio is relatively low, it is usually because the script does not contain traditional malicious binaries. Instead, it relies on "Living off the Land" (LotL) techniques—abusing legitimate system administration tools to achieve its goals.

## 2. Core Mechanism of Action
The script functions as a low-level system monitor by bridging PowerShell with native Windows APIs. 

*   **Dynamic Compilation (In-Memory Execution):** 
    The script utilizes the `Add-Type` cmdlet to compile C# code dynamically at runtime. This compiles the payload directly into the system's memory (RAM), avoiding the need to drop a compiled `.exe` file onto the hard drive, which bypasses many static file scanners.
*   **Low-Level Keyboard Hooking:** 
    It leverages the `user32.dll` library to call `SetWindowsHookEx` with the `WH_KEYBOARD_LL` (13) parameter. This installs a global hook that intercepts raw keyboard input events across the entire operating system before they are processed by individual applications.
*   **Window Context Tracking:** 
    To provide context to the intercepted keystrokes, the script uses `GetForegroundWindow` and `GetWindowThreadProcessId`. This allows it to log exactly which application (e.g., browser, terminal) the user is currently typing in.
*   **Keystroke Translation:** 
    Raw virtual key codes are converted into human-readable characters using `ToUnicodeEx`, taking into account the current keyboard layout and modifier keys (like Shift or Caps Lock).

## 3. Evasion Characteristics
This type of script often evades basic endpoint protection for several reasons:
1.  **Dual-Use APIs:** The APIs used (`SetWindowsHookEx`) are entirely legitimate and frequently used by standard software, such as macro recorders, accessibility tools, and screen readers.
2.  **No Network Exfiltration:** The script writes data to a local text file (`keyboard_log.txt`) rather than opening a network connection to a Command and Control (C2) server. This avoids triggering firewall alerts or network behavior monitors.
3.  **Fileless Nature:** Because the core logic is plain text compiled in memory, there is no static hash for traditional AV engines to block permanently without risking false positives against legitimate admin scripts.
