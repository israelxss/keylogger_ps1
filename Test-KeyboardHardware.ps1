# Keyboard Character Output Tool (Clean & Instant Exit on Ctrl+C)
$Host.UI.RawUI.WindowTitle = "Keyboard Character Output"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows.Forms;

public class KeyTester {
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;
    private const int WM_QUIT = 0x0012;

    private static HookProc _proc = HookCallback;
    private static IntPtr _hookID = IntPtr.Zero;
    private static IntPtr _lastWindow = IntPtr.Zero;
    private static uint _mainThreadId = 0;

    [StructLayout(LayoutKind.Sequential)]
    public struct MSG {
        public IntPtr hwnd;
        public uint message;
        public IntPtr wParam;
        public IntPtr lParam;
        public uint time;
        public int pt_x;
        public int pt_y;
    }

    public static void Start() {
        _mainThreadId = GetCurrentThreadId();

        // טיפול מידי בלחיצת Ctrl+C ללא חסימות
        Console.CancelKeyPress += (sender, e) => {
            e.Cancel = true;
            Stop();
        };

        _hookID = SetHook(_proc);

        // לולאת הודעות שאינה תלויה ב-Application.Run
        MSG msg;
        while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0) {
            TranslateMessage(ref msg);
            DispatchMessage(ref msg);
        }

        Unhook();
    }

    public static void Stop() {
        Unhook();
        // שליחת הודעת יציאה ישירות ללולאת ההודעות ב-Thread הראשי
        PostThreadMessage(_mainThreadId, WM_QUIT, UIntPtr.Zero, IntPtr.Zero);
        // יציאה מובטחת
        Environment.Exit(0);
    }

    private static void Unhook() {
        if (_hookID != IntPtr.Zero) {
            UnhookWindowsHookEx(_hookID);
            _hookID = IntPtr.Zero;
        }
    }

    private delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    private static IntPtr SetHook(HookProc proc) {
        using (Process curProcess = Process.GetCurrentProcess())
        using (ProcessModule curModule = curProcess.MainModule) {
            return SetWindowsHookEx(WH_KEYBOARD_LL, proc, GetModuleHandle(curModule.ModuleName), 0);
        }
    }

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN)) {
            int vkCode = Marshal.ReadInt32(lParam);
            int scanCode = Marshal.ReadInt32(lParam, 8);

            IntPtr foregroundWindow = GetForegroundWindow();

            if (foregroundWindow != _lastWindow) {
                _lastWindow = foregroundWindow;

                uint processId = 0;
                GetWindowThreadProcessId(foregroundWindow, out processId);

                string fullPath = "Unknown";
                try {
                    Process p = Process.GetProcessById((int)processId);
                    fullPath = p.MainModule.FileName;
                } catch {
                    try {
                        Process p = Process.GetProcessById((int)processId);
                        fullPath = p.ProcessName + ".exe";
                    } catch {}
                }

                StringBuilder titleBuilder = new StringBuilder(512);
                GetWindowText(foregroundWindow, titleBuilder, titleBuilder.Capacity);
                string windowTitle = titleBuilder.ToString();

                Console.ForegroundColor = ConsoleColor.DarkYellow;
                Console.WriteLine("\n\n--- [Path: " + fullPath + " | Title: " + windowTitle + "] ---");
                Console.ResetColor();
            }

            // טיפול ב-Enter וב-Shift+Enter
            if (vkCode == 0x0D) {
                bool isShift = (GetAsyncKeyState(0x10) & 0x8000) != 0;

                Console.ForegroundColor = ConsoleColor.DarkCyan;
                Console.Write(isShift ? " [Shift+Enter]" : " [Enter]");
                Console.ResetColor();

                Console.WriteLine();

                if (isShift) {
                    Console.Write("\t");
                }

                return CallNextHookEx(_hookID, nCode, wParam, lParam);
            }

            // טיפול ב-Backspace
            if (vkCode == 0x08) {
                try {
                    if (Console.CursorLeft > 0) {
                        Console.Write("\b \b");
                    }
                } catch {}
                return CallNextHookEx(_hookID, nCode, wParam, lParam);
            }

            // טיפול ברווח
            if (vkCode == 0x20) {
                Console.Write(" ");
                return CallNextHookEx(_hookID, nCode, wParam, lParam);
            }

            byte[] keyState = new byte[256];
            for (int i = 0; i < 256; i++) {
                short state = GetAsyncKeyState(i);
                if ((state & 0x8000) != 0) {
                    keyState[i] |= 0x80;
                }
            }

            if ((GetKeyState(0x14) & 0x0001) != 0) {
                keyState[0x14] |= 0x01;
            }

            uint threadId = GetWindowThreadProcessId(foregroundWindow, IntPtr.Zero);
            IntPtr hkl = GetKeyboardLayout(threadId);

            int langId = ((int)hkl) & 0xFFFF;
            if (langId == 0x040D) {
                keyState[0x14] = 0;
            }

            StringBuilder sb = new StringBuilder(10);
            int result = ToUnicodeEx((uint)vkCode, (uint)scanCode, keyState, sb, sb.Capacity, 0, hkl);

            if (result > 0) {
                string character = sb.ToString();
                if (character.Length > 0 && character[0] >= 32) {
                    Console.Write(character);
                }
            }
        }
        return CallNextHookEx(_hookID, nCode, wParam, lParam);
    }

    [DllImport("kernel32.dll")]
    private static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    private static extern bool PostThreadMessage(uint idThread, uint msg, UIntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    private static extern sbyte GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);

    [DllImport("user32.dll")]
    private static extern bool TranslateMessage([In] ref MSG lpMsg);

    [DllImport("user32.dll")]
    private static extern IntPtr DispatchMessage([In] ref MSG lpMsg);

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int vKey);

    [DllImport("user32.dll")]
    private static extern short GetKeyState(int nVirtKey);

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr hWnd, IntPtr ProcessId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);

    [DllImport("user32.dll")]
    private static extern IntPtr GetKeyboardLayout(uint idThread);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    private static extern int ToUnicodeEx(uint wVirtKey, uint wScanCode, byte[] lpKeyState, [Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pwszBuff, int cchBuff, uint wFlags, IntPtr dwhkl);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);

    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);
}
"@ -ReferencedAssemblies System.Windows.Forms

Clear-Host
Write-Host "by @israeli1" -ForegroundColor Gray
Write-Host "Press Ctrl+C to stop cleanly." -ForegroundColor Gray
[KeyTester]::Start()