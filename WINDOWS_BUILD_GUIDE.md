# SpoofTrap Windows Build Guide

Complete guide to build the Windows version of SpoofTrap - a Roblox bypass launcher app.

---

## What the app does

SpoofTrap runs a local proxy (spoofdpi) that helps bypass Roblox network restrictions. It launches Roblox with proxy settings configured.

---

## Tech Stack

- **Language:** C# / .NET 8
- **UI Framework:** WinUI 3 (Windows App SDK)
- **Packaging:** MSIX for distribution

---

## Core Features

### 1. Main Bypass Functionality

- Start/stop a local spoofdpi proxy on `127.0.0.1:8080`
- Set system proxy or app-specific proxy for Roblox
- Launch Roblox with proxy environment variables
- Configuration presets: Stable, Balanced, Fast, Custom
- Bundle spoofdpi.exe with the app

### 2. License Key System (CRITICAL)

**IMPORTANT: License must be validated with server on EVERY app launch. No offline grace period.**

Connect to existing Supabase backend for license validation.

#### Supabase Details

| Setting | Value |
|---------|-------|
| URL | `https://xucsfvyijnjkwdiiquwy.supabase.co` |
| Anon Key | `eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh1Y3Nmdnlpam5qa3dkaWlxdXd5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5NzY0NDksImV4cCI6MjA5MDU1MjQ0OX0.hfeGgWqqWdIym6Y4BqlW8nlIZ8y7MDmtWynS3bWQ0BM` |

#### License Key Format

Keys follow this pattern: `ST[A-Z0-9]{3}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}`

Example: `STYGC-LR6HG-X6FPU-46ZHT-NDQF9`

Regex validation:
```csharp
var pattern = @"^ST[A-Z0-9]{3}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}-[A-Z0-9]{5}$";
bool isValid = Regex.IsMatch(key.ToUpper().Trim(), pattern);
```

#### API Endpoints

**1. Validate/Activate License**

POST `https://xucsfvyijnjkwdiiquwy.supabase.co/rest/v1/rpc/validate_license`

**Headers:**
```
apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh1Y3Nmdnlpam5qa3dkaWlxdXd5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5NzY0NDksImV4cCI6MjA5MDU1MjQ0OX0.hfeGgWqqWdIym6Y4BqlW8nlIZ8y7MDmtWynS3bWQ0BM
Content-Type: application/json
```

**Request Body:**
```json
{
  "p_license_key": "STXXX-XXXXX-XXXXX-XXXXX-XXXXX",
  "p_device_id": "<hardware_hash>",
  "p_device_name": "Windows PC",
  "p_platform": "windows",
  "p_app_version": "1.0.0",
  "p_os_version": "Windows 11"
}
```

**Success Response:**
```json
{
  "valid": true,
  "plan": "lifetime",
  "expires_at": null,
  "activation_id": "uuid",
  "newly_activated": true
}
```

**Error Responses:**
```json
{"valid": false, "error": "invalid_key", "message": "License key not found"}
{"valid": false, "error": "revoked", "message": "License has been revoked"}
{"valid": false, "error": "inactive", "message": "License is not active"}
{"valid": false, "error": "expired", "message": "License has expired", "expired_at": "2026-01-01T00:00:00Z"}
{"valid": false, "error": "max_activations", "message": "Maximum devices reached", "max": 2, "current": 2}
```

**2. Deactivate Device**

POST `https://xucsfvyijnjkwdiiquwy.supabase.co/rest/v1/rpc/deactivate_device`

**Headers:** Same as above (apikey + Content-Type)

**Request Body:**
```json
{
  "p_license_key": "STXXX-XXXXX-XXXXX-XXXXX-XXXXX",
  "p_device_id": "<hardware_hash>"
}
```

**Response:**
```json
{"success": true}
{"success": false, "error": "invalid_key"}
{"success": false, "error": "device_not_found"}
```

Note: Always clear local license even if server call fails.

**3. Heartbeat (send every hour while app is running)**

POST `https://xucsfvyijnjkwdiiquwy.supabase.co/rest/v1/rpc/license_heartbeat`

```json
{
  "p_license_key": "STXXX-XXXXX-XXXXX-XXXXX-XXXXX",
  "p_device_id": "<hardware_hash>"
}
```

**Headers:** Same as above (apikey + Content-Type)

**Response:**
```json
{"valid": true}
{"valid": false}
{"valid": false, "expired": true}
```
If `valid` is false, immediately clear stored license and revoke Pro status. Heartbeat failures (network errors) are silent - don't revoke on network error, only on explicit `false`.

#### Device ID Generation (Windows)

Use WMI to get hardware identifiers and SHA256 hash them:

```csharp
using System.Management;
using System.Security.Cryptography;
using System.Text;

public static string GetDeviceId()
{
    var sb = new StringBuilder();
    
    // CPU ID
    using (var searcher = new ManagementObjectSearcher("SELECT ProcessorId FROM Win32_Processor"))
    {
        foreach (var obj in searcher.Get())
            sb.Append(obj["ProcessorId"]?.ToString() ?? "");
    }
    
    // Motherboard Serial
    using (var searcher = new ManagementObjectSearcher("SELECT SerialNumber FROM Win32_BaseBoard"))
    {
        foreach (var obj in searcher.Get())
            sb.Append(obj["SerialNumber"]?.ToString() ?? "");
    }
    
    // BIOS Serial
    using (var searcher = new ManagementObjectSearcher("SELECT SerialNumber FROM Win32_BIOS"))
    {
        foreach (var obj in searcher.Get())
            sb.Append(obj["SerialNumber"]?.ToString() ?? "");
    }
    
    // Hash
    var bytes = SHA256.HashData(Encoding.UTF8.GetBytes(sb.ToString()));
    return Convert.ToHexString(bytes).ToLower();
}
```

#### License Validation Flow

**On App Launch:**
1. Load stored license from `%APPDATA%\SpoofTrap\license.json`
2. If stored license exists:
   - Set `IsValidated = false` (don't trust stored data)
   - Call `validate_license` API with stored key
   - If valid: set `IsValidated = true`, start heartbeat timer
   - If invalid: clear stored license, show error
3. If no stored license: show upgrade card with license input field

**NO GRACE PERIOD** - If network fails, Pro features are locked.

#### License Storage (local)

Store in `%APPDATA%\SpoofTrap\license.json`:

```json
{
  "licenseKey": "STXXX-XXXXX-XXXXX-XXXXX-XXXXX",
  "plan": "lifetime",
  "expiresAt": null,
  "activatedAt": "2026-03-29T12:00:00Z",
  "deviceId": "abc123..."
}
```

### 3. Pro Features (require valid license)

**Pro Only:**
- Fast & Custom presets
- Full FastFlags editor (add/edit/remove flags)
- Advanced settings (Chunk Size, Disorder toggle)
- Detailed session stats
- Custom mod file imports (App Icon, Fonts, Skybox, Avatar BG categories)

**Free Users Get:**
- Stable & Balanced presets
- Basic FastFlags ON/OFF toggle
- FastFlags presets (Performance, Graphics, etc.) - read-only apply
- Core bypass functionality
- Choose spoofdpi binary location
- Death Sound and Custom Cursor mod categories

### 4. FastFlags

Write flags to: `%LOCALAPPDATA%\Roblox\Versions\<version>\ClientSettings\ClientAppSettings.json`

The Roblox player installs into version-specific subdirectories. Find the active version folder first.

**IMPORTANT (Feb 2026):** Roblox now enforces a FastFlag allowlist. Only explicitly whitelisted flags are applied; disallowed entries are silently ignored. The flags in our allowlist below have been tested. Roblox also clears ClientSettings on updates, so flags must be re-applied each launch.

```csharp
// Find the Roblox version directory
var robloxVersionsDir = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
    "Roblox", "Versions"
);

// Find the active version (contains RobloxPlayerBeta.exe)
string? versionDir = null;
if (Directory.Exists(robloxVersionsDir))
{
    foreach (var dir in Directory.GetDirectories(robloxVersionsDir))
    {
        if (File.Exists(Path.Combine(dir, "RobloxPlayerBeta.exe")))
        {
            versionDir = dir;
            break;
        }
    }
}

if (versionDir != null)
{
    var flagsDir = Path.Combine(versionDir, "ClientSettings");
    Directory.CreateDirectory(flagsDir);
    var flagsPath = Path.Combine(flagsDir, "ClientAppSettings.json");
    // Write JSON here
}
```

**Example flags file (matches macOS output format):**
```json
{
  "DFIntTaskSchedulerTargetFps": 9999,
  "FFlagDebugGraphicsPreferVulkan": true,
  "FFlagDisablePostFx": true
}
```

**FastFlag Presets (exact from macOS source):**

| Preset | Flags Enabled | Free |
|--------|--------------|------|
| None | All disabled | Yes |
| Performance | FPS Unlock (9999), Disable PostFX, Fast Light Culling, Texture Override (quality 1) | Yes |
| Quality | Quality Override (10), Texture Override (quality 3) | Yes |
| Network Fix | MTU Size (1400), Disable Timeout, Resend Buffer (256) | Yes |
| Debug | Show FPS, Perf Mode (1) | Yes |

**All FastFlag Allowed List (exact IDs):**

| ID | Name | Category | Type | Default |
|----|------|----------|------|---------|
| DFIntTaskSchedulerTargetFps | FPS Unlock | Graphics | int | 60 |
| FFlagDebugGraphicsPreferVulkan | Prefer Vulkan | Graphics | bool | false |
| FFlagDebugGraphicsDisableMetal | Disable Metal | Graphics | bool | false | *(macOS only, skip on Windows)* |
| DFIntDebugFRMQualityLevelOverride | Quality Override | Graphics | int | 0 |
| FFlagDisablePostFx | Disable PostFX | Graphics | bool | false |
| DFIntConnectionMTUSize | MTU Size | Network | int | 1396 |
| FFlagDebugDisableTimeoutDisconnect | Disable Timeout | Network | bool | false |
| DFIntRakNetResendBufferArrayLength | Resend Buffer | Network | int | 128 |
| FFlagEnableInGameMenuChrome | New Menu | Performance | bool | false |
| DFFlagTextureQualityOverrideEnabled | Texture Override | Performance | bool | false |
| DFIntTextureQualityOverride | Texture Quality | Performance | int | 0 |
| FFlagFastGPULightCulling3 | Fast Light Culling | Performance | bool | false |
| FFlagDebugDisplayFPS | Show FPS | Debug | bool | false |
| DFIntDebugPerfMode | Perf Mode | Debug | int | 0 |
| FFlagDebugDisplayUnthemedInstances | Debug Instances | Debug | bool | false |

**Show green "ON" badge next to "FastFlags" title when enabled.**

### 5. File Replacement Mods (Bloxstrap-style)

Cosmetic asset swaps applied to the Roblox install directory before each launch. These don't touch FastFlags or proxy logic.

**Mod Categories:**

| Category | Roblox Path (relative to version dir) | Extensions | Free |
|----------|---------------------------------------|------------|------|
| Death Sound | `content\sounds\ouch.ogg` | .ogg | Yes |
| Custom Cursor | `content\textures\Cursors\KeyboardMouse\ArrowCursor.png`, `ArrowFarCursor.png` | .png | Yes |
| App Icon | `content\textures\ui\icon_app-512.png` | .png | PRO |
| Custom Fonts | `content\fonts\BuilderSans-Regular.otf`, `-Medium.otf`, `-Bold.otf`, `-ExtraBold.otf` | .otf, .ttf | PRO |
| Avatar Background | `ExtraContent\places\Mobile.rbxl` | .rbxl | PRO |

**Note:** Roblox replaced Gotham fonts with Builder fonts. Skybox textures use binary `.tex` format and can't be swapped with PNGs — omitted for now.

**Pro Gating:**
- Free users: Can enable/disable mods, use Death Sound and Custom Cursor categories
- Pro users: All categories + import custom files via file picker

**How it works:**
1. Before each Roblox launch, if mods are enabled, iterate enabled mods
2. For each mod, back up the original file (if not already backed up) to `%APPDATA%\SpoofTrap\Mods\Backups\`
3. Copy the mod file over the original
4. On "Restore All", copy backups back and delete the backup

**Storage:**
- Custom imported files: `%APPDATA%\SpoofTrap\Mods\<categoryId>\<filename>`
- Backups of originals: `%APPDATA%\SpoofTrap\Mods\Backups\<hash>.<ext>`
- Settings: `%APPDATA%\SpoofTrap\mods_settings.json`

```json
{
  "isEnabled": true,
  "mods": [
    {
      "id": "uuid-string",
      "categoryId": "death_sound",
      "name": "Minecraft Oof",
      "isEnabled": true,
      "isBuiltIn": false,
      "customFilePath": "C:\\Users\\...\\SpoofTrap\\Mods\\death_sound\\minecraft_oof.ogg",
      "originalBackedUp": true
    }
  ]
}
```

**Windows path resolution (find Roblox version dir):**
Reuse the same version detection from FastFlags:
```csharp
var contentBase = Path.Combine(versionDir, "content");
// e.g. for death sound: Path.Combine(contentBase, "sounds", "ouch.ogg")
```

**UI:** Purple accent color. Shows a "Mods" card with enable toggle and category summary, plus expandable "Mod Browser" with per-category sections. PRO-locked categories show a PRO badge and are greyed out. Each mod has a toggle, name, and delete button (for custom mods).

**Important:** Roblox updates overwrite mods, so always re-apply before launch. Always backup before overwriting.

### 6. Proxy Settings

**Proxy Modes:**
- **App** (recommended): Sets `http_proxy` and `https_proxy` environment variables when launching Roblox
- **System**: Uses `netsh winhttp set proxy 127.0.0.1:8080` (or newer `netsh winhttp set advproxy` on Win 11). Reset with `netsh winhttp reset proxy`. Requires admin elevation.

**spoofdpi launch arguments (actual from macOS source):**
```
spoofdpi.exe --listen-addr 127.0.0.1:8080 --dns-mode https --dns-https-url https://1.1.1.1/dns-query --https-split-mode chunk --https-chunk-size 1
```

If disorder is enabled, also add: `--https-disorder`

**Preset values:**

| Preset | Chunk Size | Disorder | DNS URL |
|--------|-----------|----------|---------|
| Stable | 1 | true | https://1.1.1.1/dns-query |
| Balanced | 2 | true | https://1.1.1.1/dns-query |
| Fast (PRO) | 4 | false | https://1.1.1.1/dns-query |
| Custom (PRO) | user-defined | user-defined | user-defined |

Advanced settings (PRO only):
- Chunk Size: 1-16 (default 1)
- Disorder: true/false (default true)
- DNS HTTPS URL (default: https://1.1.1.1/dns-query)
- App Launch Delay: 0-10 seconds (default 0)
- Reduce Motion: disable UI animations for better performance (this setting is available to ALL users, not PRO-only)

### 6. UI Design

Modern dark theme matching macOS version:

- Mica backdrop (Windows 11) or Acrylic (Windows 10)
- Purple/cyan accent colors
- Two-column layout
- PRO badge for licensed users
- Green "ON" badge for FastFlags status
- Session log with colored lines (green=success, red=error)

**Color Palette (exact from macOS source):**
```
Background gradient:
  Top-left:     rgb(15, 23, 41)   = #0f1729
  Mid:          rgb(20, 28, 46)   = #141c2e
  Bottom-right: rgb(26, 33, 51)   = #1a2133

Card Background: rgba(255,255,255,0.08) → rgba(255,255,255,0.05) gradient
Card Border:     rgba(255,255,255,0.08)
Card Shadow:     rgba(0,0,0,0.2) blur 20 y:10

Ambient orb (top-right): rgb(107, 217, 255) = #6bd9ff at 0.15 opacity
Ambient orb (bottom-left): rgb(255, 204, 140) = #ffcc8c at 0.10 opacity

Status colors (statusColor):
  Running:  Color(red: 0.45, green: 0.92, blue: 0.65) = #73eba6
  Starting: Color(red: 1.0,  green: 0.78, blue: 0.35) = #ffc759
  Stopping/Stopped: Color(red: 1.0, green: 0.45, blue: 0.45) = #ff7373

Action button tint (actionTint):
  Stopping/Stopped: Color(red: 0.75, green: 0.88, blue: 1.0) = #bfe0ff (cyan)
  Running:          Color(red: 0.6,  green: 0.92, blue: 0.75) = #99ebbf (green)
  Starting:         Color(red: 0.95, green: 0.85, blue: 0.55) = #f2d98c (yellow)

Log colors (logColor):
  Error/Failed lines: Color(red: 1.0, green: 0.55, blue: 0.55) = #ff8c8c
  Success/Active:     Color(red: 0.55, green: 0.92, blue: 0.65) = #8ceba6
  Default:            rgba(255,255,255,0.8)

Text Primary:   #ffffff
Text Secondary: rgba(255,255,255,0.7)
Text Muted:     rgba(255,255,255,0.4)
```

**Main Button States:**
- Stopped: White → cyan gradient, "Start Session" / "Launch Roblox"
- Running: White → green gradient, "Stop Session" / "Terminate proxy"
- Starting: White → yellow gradient

**Status Pill States:**
- Offline, Starting, Live, Stopping

---

## Project Structure

```
SpoofTrapWindows/
├── SpoofTrapWindows.sln
├── SpoofTrapWindows/
│   ├── App.xaml
│   ├── App.xaml.cs
│   ├── MainWindow.xaml
│   ├── MainWindow.xaml.cs
│   ├── ViewModels/
│   │   ├── MainViewModel.cs
│   │   └── ViewModelBase.cs
│   ├── Services/
│   │   ├── LicenseManager.cs
│   │   ├── ProManager.cs
│   │   ├── ProxyService.cs
│   │   ├── FastFlagsManager.cs
│   │   ├── ModsManager.cs
│   │   └── SettingsService.cs
│   ├── Models/
│   │   ├── LicenseInfo.cs
│   │   ├── FastFlag.cs
│   │   ├── InstalledMod.cs
│   │   ├── ProxyPreset.cs
│   │   └── SessionStats.cs
│   ├── Controls/
│   │   ├── GlassCard.xaml
│   │   ├── SettingRow.xaml
│   │   └── StatusPill.xaml
│   ├── Assets/
│   │   ├── icon.ico
│   │   └── spooftrap-icon.png
│   ├── Resources/
│   │   └── spoofdpi.exe
│   └── Package.appxmanifest
└── README.md
```

---

## Key Classes

### LicenseManager.cs

```csharp
public class LicenseManager : INotifyPropertyChanged
{
    private const string SupabaseUrl = "https://xucsfvyijnjkwdiiquwy.supabase.co";
    private const string SupabaseAnonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inh1Y3Nmdnlpam5qa3dkaWlxdXd5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ5NzY0NDksImV4cCI6MjA5MDU1MjQ0OX0.hfeGgWqqWdIym6Y4BqlW8nlIZ8y7MDmtWynS3bWQ0BM";
    
    public bool IsValidated { get; private set; }
    public bool IsValidating { get; private set; }
    public LicenseInfo? CurrentLicense { get; private set; }
    public string? ValidationError { get; private set; }
    
    public string DeviceId => GetDeviceId();
    public string DeviceName => Environment.MachineName;
    public string AppVersion => "1.0.0";
    public string OsVersion => Environment.OSVersion.VersionString;
    
    // Call on app startup
    public async Task InitializeAsync()
    {
        var stored = LoadStoredLicense();
        if (stored != null)
        {
            IsValidated = false; // Don't trust stored data
            await ValidateOnLaunchAsync(stored);
        }
    }
    
    private async Task ValidateOnLaunchAsync(LicenseInfo stored)
    {
        IsValidating = true;
        var success = await ActivateAsync(stored.LicenseKey);
        if (!success)
        {
            ClearLicense();
            ValidationError ??= "License validation failed. Please check your connection.";
        }
        IsValidating = false;
    }
    
    public async Task<bool> ActivateAsync(string licenseKey);
    public async Task<bool> DeactivateAsync();
    
    private void StartHeartbeat(); // Timer every 3600 seconds
    private void StopHeartbeat();
    private async Task SendHeartbeatAsync();
    
    private void SaveLicense(LicenseInfo license);
    private LicenseInfo? LoadStoredLicense();
    private void ClearLicense();
    
    private static string GetDeviceId();
    private static bool IsValidKeyFormat(string key);
}
```

### ProManager.cs

```csharp
public class ProManager : INotifyPropertyChanged
{
    private readonly LicenseManager _licenseManager;
    
    public bool IsPro => _licenseManager.IsValidated;
    
    // Feature checks
    public bool CanUsePreset(string preset) => 
        preset is "stable" or "balanced" || IsPro;
    
    public bool CanEditFastFlags => IsPro;
    public bool CanAccessAdvanced => IsPro;
    public bool CanViewStats => IsPro;
    public bool CanImportCustomMods => IsPro;
    
    public bool CanUseModCategory(string categoryId) =>
        categoryId is "death_sound" or "cursor" || IsPro;
}
```

### MainViewModel.cs

```csharp
public class MainViewModel : ViewModelBase
{
    public LicenseManager LicenseManager { get; }
    public ProManager ProManager { get; }
    public FastFlagsManager FastFlagsManager { get; }
    public ModsManager ModsManager { get; }
    
    // State
    public enum BypassState { Stopped, Starting, Running, Stopping }
    public BypassState State { get; set; }
    public bool IsRunning => State == BypassState.Running;
    
    // Settings
    public string Preset { get; set; } = "stable"; // stable, balanced, fast, custom
    public string ProxyScope { get; set; } = "app"; // app, system
    public string DnsHttpsUrl { get; set; } = "https://1.1.1.1/dns-query";
    public int HttpsChunkSize { get; set; } = 1;     // range: 1-16
    public bool HttpsDisorder { get; set; } = true;
    public bool HybridLaunch { get; set; } = false;
    public int AppLaunchDelay { get; set; } = 0;      // range: 0-10
    public bool ReducedMotion { get; set; } = false;   // disable animations
    
    // Paths
    public string RobloxPath { get; set; }
    public string SpoofdpiPath { get; set; }
    public bool RobloxInstalled => !string.IsNullOrEmpty(RobloxPath) && File.Exists(RobloxPath);
    public bool BinaryAvailable => !string.IsNullOrEmpty(SpoofdpiPath) && File.Exists(SpoofdpiPath);
    
    // Logs
    public ObservableCollection<string> Logs { get; }
    
    // Commands
    public ICommand ToggleBypassCommand { get; }
    public ICommand ChooseRobloxCommand { get; }
    public ICommand ChooseSpoofdpiCommand { get; }
    public ICommand CopyLogsCommand { get; }
    
    public async Task StartSessionAsync();
    public async Task StopSessionAsync();
}
```

---

## Settings Persistence

Store in `%APPDATA%\SpoofTrap\settings.json`:

```json
{
  "robloxAppPath": "C:\\Users\\...\\RobloxPlayerBeta.exe",
  "customSpoofdpiPath": "",
  "preset": "stable",
  "proxyScope": "app",
  "hybridLaunch": false,
  "dnsHttpsURL": "https://1.1.1.1/dns-query",
  "httpsChunkSize": 1,
  "httpsDisorder": true,
  "appLaunchDelay": 0,
  "reducedMotion": false
}
```

Store FastFlags separately in `%APPDATA%\SpoofTrap\fastflags.json`:

```json
{
  "isEnabled": true,
  "flags": [
    {"id": "DFIntTaskSchedulerTargetFps", "isEnabled": true, "value": "9999"},
    {"id": "FFlagDebugGraphicsPreferVulkan", "isEnabled": false, "value": "true"}
  ]
}
```

License storage: see "License Storage (local)" section above.

---

## Dependencies (NuGet)

```xml
<PackageReference Include="Microsoft.WindowsAppSDK" Version="1.8.*" />
<PackageReference Include="CommunityToolkit.Mvvm" Version="8.*" />
<PackageReference Include="CommunityToolkit.WinUI.UI.Controls" Version="7.*" />
<PackageReference Include="System.Management" Version="8.*" />
```

---

## Implementation Order

1. **Project Setup** - Create WinUI 3 project
2. **Settings Service** - Load/save settings
3. **LicenseManager** - Critical for Pro features
4. **ProManager** - Feature gating
5. **Basic UI** - Main window layout
6. **MainViewModel** - Core state
7. **ProxyService** - spoofdpi management
8. **FastFlagsManager** - Flag editing
9. **Polish** - Error handling, packaging

---

## Testing

**Test License Key:**
```
STVQ8-M597T-NQRYF-HZZAD-XH7HH
```

Or create new via Discord `/license create` command.

---

## Distribution

Download spoofdpi Windows binary (v1.2.1, current stable) from:
https://github.com/xvzc/SpoofDPI/releases/tag/v1.2.1

Look for `spoofdpi-windows-amd64.zip` (or `arm64` if needed).

Bundle `spoofdpi.exe` with the app in the Resources folder.

---

## Notes

- License system is shared - same database, same keys work on both platforms
- Device activations are tracked per-platform (user can have 1 Mac + 1 Windows active)
- The macOS Swift source is in `Sources/` for reference
- Keep UI consistent between platforms for brand recognition
- No offline grace period - must validate with server every launch
