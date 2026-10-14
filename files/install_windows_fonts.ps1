# WSL 안의 글꼴 파일을 Windows 사용자 글꼴로 설치한다 (관리자 권한 불필요).
# install_wsl_gui.yml 이 앞에 $FontDir, $FontFiles 를 붙여 -EncodedCommand 로 넘긴다.
#   $FontDir   글꼴이 있는 디렉터리의 Windows 경로 (\\wsl.localhost\<distro>\...)
#   $FontFiles 설치할 파일 이름 목록
#
# 설치는 세 단계다.
#   1) %LOCALAPPDATA%\Microsoft\Windows\Fonts 로 복사
#   2) HKCU\...\Fonts 에 등록  -> 다음 로그온부터 자동으로 로드된다
#   3) AddFontResource + WM_FONTCHANGE -> 지금 세션에서도 바로 쓸 수 있다
# 이미 같은 파일이 같은 경로로 등록되어 있으면 아무것도 하지 않는다.
# 마지막 줄에 'changed' 또는 'ok' 를 출력한다 (ansible changed_when 용).

$ErrorActionPreference = 'Stop'

Add-Type -Namespace Win32 -Name Font -MemberDefinition @'
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern int AddFontResourceW(string path);
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern bool RemoveFontResourceW(string path);
[DllImport("user32.dll")]
public static extern IntPtr SendMessageTimeoutW(IntPtr hWnd, uint msg, UIntPtr wParam,
    IntPtr lParam, uint flags, uint timeout, out UIntPtr result);
'@

$userFonts = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$regPath = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
New-Item -ItemType Directory -Force -Path $userFonts | Out-Null
if (-not (Test-Path $regPath)) { New-Item -Force -Path $regPath | Out-Null }

$changed = $false
foreach ($file in $FontFiles) {
    $src = Join-Path $FontDir $file
    $dst = Join-Path $userFonts $file
    $valueName = "$([IO.Path]::GetFileNameWithoutExtension($file)) (TrueType)"

    $sameFile = (Test-Path $dst) -and
        ((Get-FileHash $dst).Hash -eq (Get-FileHash $src).Hash)
    $registered = (Get-ItemProperty -Path $regPath -Name $valueName `
        -ErrorAction SilentlyContinue).$valueName -eq $dst

    if ($sameFile -and $registered) { continue }

    if (-not $sameFile) {
        # 이미 로드된 글꼴 파일은 잠겨 있어 덮어쓸 수 없으므로 먼저 내린다.
        if (Test-Path $dst) { [Win32.Font]::RemoveFontResourceW($dst) | Out-Null }
        Copy-Item -Force -Path $src -Destination $dst
    }
    Set-ItemProperty -Path $regPath -Name $valueName -Value $dst
    [Win32.Font]::AddFontResourceW($dst) | Out-Null
    $changed = $true
}

if ($changed) {
    # HWND_BROADCAST, WM_FONTCHANGE, SMTO_ABORTIFHUNG
    $r = [UIntPtr]::Zero
    [Win32.Font]::SendMessageTimeoutW([IntPtr]0xffff, 0x001D, [UIntPtr]::Zero,
        [IntPtr]::Zero, 0x0002, 1000, [ref]$r) | Out-Null
    'changed'
} else {
    'ok'
}
