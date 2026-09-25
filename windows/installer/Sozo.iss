; Inno Setup script for the Sozo Windows desktop app.
; Build the app first:  flutter build windows --release
; Then compile this:    "C:\Program Files (x86)\Inno Setup 6\ISCC.exe" /DMyAppVersion=1.2.3 windows\installer\Sozo.iss
; Output: Sozo-Setup.exe on the Desktop.

#define MyAppName "Sozo"
; The release workflow passes the resolved version in with
; /DMyAppVersion=<name>. Everything downstream of it — AppVersion, AppVerName,
; the entry in Add/Remove Programs, and the upgrade comparison Inno makes
; against the previous install — reads that one define, so a hard-coded value
; here meant every release ever shipped identified itself as the same version.
; The fallback exists only so a local `ISCC Sozo.iss` still compiles; 0.0.0 is
; deliberately a version nobody would mistake for a release.
#ifndef MyAppVersion
  #define MyAppVersion "0.0.0"
#endif
#define MyAppPublisher "Azamov"
#define MyAppURL "https://sozo.azamov.me"
#define MyAppExeName "soplay.exe"
; Must stay in step with DeeplinkService._scheme.
#define MyAppScheme "sozo"
#define SourceDir "..\..\build\windows\x64\runner\Release"
#define IconFile "..\runner\resources\app_icon.ico"

[Setup]
; A stable AppId so upgrades replace the previous install (do NOT change it).
AppId={{C84B2ADE-1E25-4A1D-96F1-80943040A908}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#MyAppExeName}
UninstallDisplayName={#MyAppName}
; Per-user install -> no admin / UAC prompt, so anyone can install it.
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
; Compile-time output folder (relative to this .iss). The setup.exe is copied to
; the Desktop by the build step afterwards.
OutputDir=..\..\build\installer
OutputBaseFilename=Sozo-Setup
SetupIconFile={#IconFile}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
; The whole build output. Skip linker artifacts and the runtime WebView2
; user-data folder (it is recreated on first run).
Source: "{#SourceDir}\*"; DestDir: "{app}"; \
  Flags: recursesubdirs createallsubdirs ignoreversion; \
  Excludes: "*.lib,*.exp,*.pdb,soplay.exe.WebView2,soplay.exe.WebView2\*"

[Registry]
; DeeplinkService handles the custom `sozo:` scheme on every platform, but on
; Windows nothing had ever told the OS which program owns it, so a sozo:// link
; in a browser or a chat client went nowhere. HKA rather than HKCU/HKLM: this is
; a per-user install by default (PrivilegesRequired=lowest) but the user may
; elevate through the dialog, and HKA follows whichever one actually happened.
; uninsdeletekey on the root key alone removes the whole subtree.
;
; Nothing is needed on the Dart side for this: app_links is a native plugin on
; Windows and reads ::GetCommandLineW() itself, accepting the link only when the
; command line holds exactly one argument after the exe — which is precisely
; what the "%1" in shell\open\command below produces.
Root: HKA; Subkey: "Software\Classes\{#MyAppScheme}"; ValueType: string; ValueName: ""; \
  ValueData: "URL:{#MyAppName} Protocol"; Flags: uninsdeletekey
; An empty "URL Protocol" value is the marker Windows looks for; its content is
; never read, only its presence.
Root: HKA; Subkey: "Software\Classes\{#MyAppScheme}"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""
; The path is quoted here as it is in shell\open\command below. Windows' icon
; parser copes either way, but {app} defaults to a Program Files path with a
; space in it and there is no reason for two values in the same key to disagree
; about how a path is written.
Root: HKA; Subkey: "Software\Classes\{#MyAppScheme}\DefaultIcon"; ValueType: string; ValueName: ""; \
  ValueData: """{app}\{#MyAppExeName}"",0"
Root: HKA; Subkey: "Software\Classes\{#MyAppScheme}\shell\open\command"; ValueType: string; ValueName: ""; \
  ValueData: """{app}\{#MyAppExeName}"" ""%1"""

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; \
  Flags: nowait postinstall skipifsilent
