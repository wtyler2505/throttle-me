; throttle-me.iss — Inno Setup script for the throttle-me Windows installer.
;
; The output is a single throttle-me-setup.exe that the end user double-clicks.
; UAC elevation is requested automatically, the helper service is registered,
; the WinDivert driver is dropped next to the helper, and three Start Menu
; shortcuts are created (Turn ON / Turn OFF / Status).
;
; This file is consumed by ISCC.exe (Inno Setup Compiler 6+). The CI workflow
; under .github/workflows/build-windows-installer.yml runs it on each tag push.
;
; Inputs (relative to this .iss file):
;   ..\throttle-me.ps1
;   ..\throttle-me.cmd
;   ..\VERSION
;   ..\lib\*.ps1
;   ..\helper\bin\throttle-me-helper.exe
;   ..\helper\bin\WinDivert.dll
;   ..\helper\bin\WinDivert64.sys
;   .\Toggle-Bypass.ps1
;
; Output:
;   .\Output\throttle-me-setup.exe

#define MyAppName       "throttle-me"
#define MyAppPublisher  "wtyler2505"
#define MyAppURL        "https://github.com/wtyler2505/throttle-me"
#define MyAppExeName    "throttle-me.cmd"
#define ServiceName     "ThrottleMeHelper"

; Read version from VERSION file (trimmed)
#define MyAppVersion    Trim(FileRead(FileOpen("..\VERSION")))

[Setup]
AppId={{8E2A1B6F-9F3D-4B54-8C7A-1C9E4F2A3D1A}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}/issues
AppUpdatesURL={#MyAppURL}/releases
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=
OutputBaseFilename=throttle-me-setup
OutputDir=Output
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
WizardStyle=modern
UninstallDisplayName={#MyAppName} {#MyAppVersion}
SetupLogging=yes
CloseApplications=force

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicons"; Description: "Create desktop shortcuts (Turn ON / Turn OFF)"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
; PowerShell CLI + libs
Source: "..\throttle-me.ps1";       DestDir: "{app}";              Flags: ignoreversion
Source: "..\throttle-me.cmd";       DestDir: "{app}";              Flags: ignoreversion
Source: "..\VERSION";               DestDir: "{app}";              Flags: ignoreversion
Source: "..\lib\*.ps1";             DestDir: "{app}\lib";          Flags: ignoreversion

; Helper service binary + WinDivert runtime
Source: "..\helper\bin\throttle-me-helper.exe"; DestDir: "{app}\helper"; Flags: ignoreversion
Source: "..\helper\bin\WinDivert.dll";          DestDir: "{app}\helper"; Flags: ignoreversion
Source: "..\helper\bin\WinDivert64.sys";        DestDir: "{app}\helper"; Flags: ignoreversion

; Shortcut helper
Source: "Toggle-Bypass.ps1";        DestDir: "{app}";              Flags: ignoreversion

; Optional reference docs (not visible in Start Menu)
Source: "..\README.md";             DestDir: "{app}";              Flags: ignoreversion
Source: "..\config\throttle-me.conf.template"; DestDir: "{app}\config"; Flags: ignoreversion

[Icons]
; Start Menu — the three shortcuts the buddy uses day-to-day
Name: "{group}\Throttle Me - Turn ON";  Filename: "powershell.exe"; \
    Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Toggle-Bypass.ps1"" -Action Enable"; \
    WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 277; \
    Comment: "Turn the carrier-bypass ON"

Name: "{group}\Throttle Me - Turn OFF"; Filename: "powershell.exe"; \
    Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Toggle-Bypass.ps1"" -Action Disable"; \
    WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 131; \
    Comment: "Turn the carrier-bypass OFF"

Name: "{group}\Throttle Me - Status";   Filename: "powershell.exe"; \
    Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Toggle-Bypass.ps1"" -Action Status"; \
    WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 23; \
    Comment: "Check if the bypass is currently active"

Name: "{group}\Uninstall Throttle Me";  Filename: "{uninstallexe}"

; Optional desktop shortcuts (opt-in via the Tasks page)
Name: "{autodesktop}\Throttle Me - ON";  Filename: "powershell.exe"; \
    Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Toggle-Bypass.ps1"" -Action Enable"; \
    WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 277; Tasks: desktopicons

Name: "{autodesktop}\Throttle Me - OFF"; Filename: "powershell.exe"; \
    Parameters: "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File ""{app}\Toggle-Bypass.ps1"" -Action Disable"; \
    WorkingDir: "{app}"; IconFilename: "{sys}\shell32.dll"; IconIndex: 131; Tasks: desktopicons

[Run]
; 1. Register the Windows service.
Filename: "{sys}\sc.exe"; Parameters: "create {#ServiceName} binPath= ""\""{app}\helper\throttle-me-helper.exe\"""" start= demand DisplayName= ""throttle-me bypass helper"""; \
    Flags: runhidden; StatusMsg: "Registering helper service..."

Filename: "{sys}\sc.exe"; Parameters: "description {#ServiceName} ""TTL + DNS bypass for tethered hotspots ({#MyAppURL})"""; \
    Flags: runhidden

; 2. Grant Authenticated Users start/stop/query rights so the CLI and shortcuts
;    don't need UAC for everyday on/off toggling.
Filename: "{sys}\sc.exe"; Parameters: "sdset {#ServiceName} D:(A;;CCLCSWRPWPDTLOCRRC;;;SY)(A;;CCDCLCSWRPWPDTLOCRSDRCWDWO;;;BA)(A;;CCLCSWLOCRRC;;;IU)(A;;CCLCSWLOCRRC;;;SU)(A;;RPWPDTLOCRRC;;;AU)"; \
    Flags: runhidden

; 3. Seed registry defaults under HKLM\SOFTWARE\throttle-me.
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -Command ""& {{ . '{app}\lib\Config.ps1'; Initialize-BypassConfig }}"""; \
    Flags: runhidden; StatusMsg: "Seeding registry defaults..."

; 4. Tell the user where to go next (only after a successful interactive install).
Filename: "{group}\Throttle Me - Status"; Description: "Check status now"; Flags: postinstall nowait skipifsilent unchecked

[UninstallRun]
; Stop and delete the service before files are removed.
Filename: "{sys}\sc.exe"; Parameters: "stop {#ServiceName}";   Flags: runhidden; RunOnceId: "StopHelperService"
Filename: "{sys}\sc.exe"; Parameters: "delete {#ServiceName}"; Flags: runhidden; RunOnceId: "DeleteHelperService"

[UninstallDelete]
Type: filesandordirs; Name: "{app}\helper"
Type: filesandordirs; Name: "{app}\lib"
Type: filesandordirs; Name: "{app}\config"

[Registry]
; Cleanly remove our config tree on uninstall (so reinstall starts fresh).
; If the user wants to preserve their settings, they can opt out by deleting
; this registry section before reinstalling — uncommon for the target audience.
Root: HKLM; Subkey: "SOFTWARE\throttle-me"; Flags: uninsdeletekey
