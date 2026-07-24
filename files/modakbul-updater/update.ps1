[CmdletBinding()]
param(
    [string]$GameDir = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Write-UpdateLog {
    param([string]$Message)
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "[$stamp] $Message"
    Write-Host $line
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
}

function Get-SafeTargetPath {
    param(
        [string]$Root,
        [string]$RelativePath
    )
    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        [IO.Path]::IsPathRooted($RelativePath) -or
        $RelativePath.Contains(":")) {
        throw "허용되지 않은 업데이트 경로: $RelativePath"
    }

    $normalized = $RelativePath.Replace("/", [IO.Path]::DirectorySeparatorChar)
    $segments = $normalized.Split([IO.Path]::DirectorySeparatorChar)
    if ($segments -contains "..") {
        throw "상위 폴더를 가리키는 업데이트 경로는 허용되지 않습니다: $RelativePath"
    }

    $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd("\", "/")
    $targetFull = [IO.Path]::GetFullPath((Join-Path $rootFull $normalized))
    $prefix = $rootFull + [IO.Path]::DirectorySeparatorChar
    if (-not $targetFull.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "게임 폴더 밖의 업데이트 경로는 허용되지 않습니다: $RelativePath"
    }
    return $targetFull
}

function Get-FileSha256 {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Resolve-DownloadUri {
    param(
        [uri]$ManifestUri,
        [object]$File
    )
    if (-not [string]::IsNullOrWhiteSpace([string]$File.url)) {
        return [uri]$File.url
    }
    $escaped = (($File.path -split "/") | ForEach-Object {
        [uri]::EscapeDataString($_)
    }) -join "/"
    return [uri]::new($ManifestUri, "files/$escaped")
}

$UpdaterDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($GameDir)) {
    $GameDir = Split-Path -Parent $UpdaterDir
}
$GameDir = [IO.Path]::GetFullPath($GameDir)
$LogPath = Join-Path $UpdaterDir "update.log"
$ChannelPath = Join-Path $UpdaterDir "channel.json"
$InstalledStatePath = Join-Path $UpdaterDir "installed-state.json"
$TempRoot = Join-Path $UpdaterDir "staging"

New-Item -ItemType Directory -Force -Path $UpdaterDir | Out-Null

try {
    if (-not (Test-Path -LiteralPath $ChannelPath -PathType Leaf)) {
        throw "channel.json을 찾지 못했습니다."
    }
    $channel = Get-Content -LiteralPath $ChannelPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $manifestUrl = [string]$channel.manifestUrl
    if ([string]::IsNullOrWhiteSpace($manifestUrl) -or
        $manifestUrl -eq "__UPDATE_MANIFEST_URL__") {
        Write-UpdateLog "자동 업데이트 주소가 아직 연결되지 않았습니다. 현재 설치본으로 실행합니다."
        exit 0
    }

    $manifestUri = [uri]$manifestUrl
    if ($manifestUri.Scheme -ne "https" -and $manifestUri.Scheme -ne "http") {
        throw "업데이트 주소는 HTTP 또는 HTTPS만 사용할 수 있습니다."
    }

    Write-UpdateLog "업데이트 확인 중: $($channel.displayName)"
    $headers = @{ "User-Agent" = "ModakbulSeason1Updater/1.0" }
    $manifest = Invoke-RestMethod -Uri $manifestUri -Headers $headers -TimeoutSec 30
    if ([string]$manifest.packId -ne [string]$channel.packId) {
        throw "업데이트 채널의 packId가 일치하지 않습니다."
    }
    if ([int]$manifest.schemaVersion -ne 1) {
        throw "지원하지 않는 업데이트 목록 형식입니다: $($manifest.schemaVersion)"
    }

    $previous = $null
    if (Test-Path -LiteralPath $InstalledStatePath -PathType Leaf) {
        try {
            $previous = Get-Content -LiteralPath $InstalledStatePath -Raw -Encoding UTF8 | ConvertFrom-Json
        } catch {
            Write-UpdateLog "이전 설치 상태를 읽지 못해 삭제 정리를 건너뜁니다."
        }
    }

    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

    $changed = 0
    $skipped = 0
    $currentPaths = @{}
    foreach ($file in @($manifest.files)) {
        $relativePath = [string]$file.path
        $currentPaths[$relativePath.ToLowerInvariant()] = $true
        $target = Get-SafeTargetPath -Root $GameDir -RelativePath $relativePath
        $expectedHash = ([string]$file.sha256).ToLowerInvariant()
        if ($expectedHash.Length -ne 64) {
            throw "잘못된 SHA-256 값: $relativePath"
        }

        $actualHash = Get-FileSha256 -Path $target
        if (-not $Force -and $actualHash -eq $expectedHash) {
            $skipped++
            continue
        }

        $downloadUri = Resolve-DownloadUri -ManifestUri $manifestUri -File $file
        $tempName = [guid]::NewGuid().ToString("N") + ".download"
        $tempPath = Join-Path $TempRoot $tempName
        Write-UpdateLog "받는 중: $relativePath"
        Invoke-WebRequest -Uri $downloadUri -OutFile $tempPath -Headers $headers -TimeoutSec 180
        $downloadHash = Get-FileSha256 -Path $tempPath
        if ($downloadHash -ne $expectedHash) {
            throw "검증 실패: $relativePath"
        }

        $targetParent = Split-Path -Parent $target
        New-Item -ItemType Directory -Force -Path $targetParent | Out-Null
        Move-Item -LiteralPath $tempPath -Destination $target -Force
        $changed++
    }

    $removed = 0
    if ($null -ne $previous -and $null -ne $previous.files) {
        foreach ($oldFile in @($previous.files)) {
            $relativePath = [string]$oldFile.path
            if ($currentPaths.ContainsKey($relativePath.ToLowerInvariant())) {
                continue
            }
            $target = Get-SafeTargetPath -Root $GameDir -RelativePath $relativePath
            $oldHash = ([string]$oldFile.sha256).ToLowerInvariant()
            if ((Get-FileSha256 -Path $target) -eq $oldHash) {
                Remove-Item -LiteralPath $target -Force
                Write-UpdateLog "이전 관리 파일 정리: $relativePath"
                $removed++
            } else {
                Write-UpdateLog "사용자가 바꾼 파일은 보존: $relativePath"
            }
        }
    }

    $state = [ordered]@{
        packId = [string]$manifest.packId
        version = [string]$manifest.version
        installedAt = (Get-Date).ToString("o")
        files = @($manifest.files | ForEach-Object {
            [ordered]@{
                path = [string]$_.path
                sha256 = ([string]$_.sha256).ToLowerInvariant()
            }
        })
    }
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $InstalledStatePath -Encoding UTF8
    Write-UpdateLog "업데이트 완료: 변경 $changed, 그대로 $skipped, 정리 $removed (버전 $($manifest.version))"
    exit 0
} catch {
    Write-UpdateLog "업데이트 실패: $($_.Exception.Message)"
    Write-UpdateLog "안전을 위해 게임 실행을 중단합니다. update.log를 운영자에게 보내주세요."
    exit 1
} finally {
    if (Test-Path -LiteralPath $TempRoot) {
        Remove-Item -LiteralPath $TempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
