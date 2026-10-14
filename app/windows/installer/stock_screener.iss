; 台股選股 Windows 安裝程式（Inno Setup）。GitHub Actions 編譯 Windows 版後自動產生
; stock_screener_setup.exe，使用者點兩下就安裝到自己的 AppData，不需要管理員權限，
; 並建立開始功能表與桌面捷徑。歷史資料、持股存在另一個資料夾，重新安裝或更新都不影響。

#ifndef AppVersion
  #define AppVersion "1.0"
#endif

[Setup]
AppId={{6E1B7C52-3A9D-4F0B-9C11-7D2A5E8F4B31}
AppName=台股選股
AppVersion={#AppVersion}
AppPublisher=nmymdf
DefaultDirName={localappdata}\Programs\stock_screener
DefaultGroupName=台股選股
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=..\..\build\installer
OutputBaseFilename=stock_screener_setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\stock_screener.exe
UninstallDisplayName=台股選股
CloseApplications=yes
; 裝完通知 Windows 重新整理圖示（不然更新後桌面捷徑會一直顯示快取裡的舊圖示）
ChangesAssociations=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

[Tasks]
Name: "desktopicon"; Description: "建立桌面捷徑"

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\台股選股"; Filename: "{app}\stock_screener.exe"
Name: "{autodesktop}\台股選股"; Filename: "{app}\stock_screener.exe"; Tasks: desktopicon

[Run]
; Windows 10／11：重建圖示快取，桌面捷徑馬上換成新圖示
Filename: "{sys}\ie4uinit.exe"; Parameters: "-show"; Flags: runhidden skipifdoesntexist
Filename: "{app}\stock_screener.exe"; Description: "立即開啟台股選股"; Flags: nowait postinstall skipifsilent
