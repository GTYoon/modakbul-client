[CmdletBinding()]
param(
    [string]$Version = "1.0.0",
    [string]$ServerAddress = "116.126.112.66:25565",
    [string]$UpdateManifestUrl = "https://raw.githubusercontent.com/GTYoon/modakbul-client/main/manifest.json",
    [string]$LauncherFilesBaseUrl = "https://raw.githubusercontent.com/GTYoon/modakbul-client/main",
    [string]$LauncherServerIconUrl = "https://raw.githubusercontent.com/GTYoon/modakbul-client/main/server-icon.png",
    [string]$LauncherNewsRssUrl = "https://github.com/GTYoon/modakbul-launcher/releases.atom",
    [string]$LargeFileReleaseBaseUrl = "",
    [long]$RepositoryFileLimitBytes = 100MB,
    [string]$ReferenceClientRoot = "D:\___ ___"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

$Workspace = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$BuildRoot = Join-Path $Workspace "client-build"
$ReferenceClientRoot = [IO.Path]::GetFullPath($ReferenceClientRoot)
$ReferenceMetadataPath = Join-Path $ReferenceClientRoot "minecraftinstance.json"
$WorkRoot = Join-Path $BuildRoot "work\modakbul-season-1"
$PackRoot = Join-Path $WorkRoot "pack"
$OverridesRoot = Join-Path $PackRoot "overrides"
$ReleaseRoot = Join-Path $BuildRoot "release"
$ReleaseAssetsRoot = Join-Path $ReleaseRoot "release-assets"
$RepositoryRoot = Join-Path $ReleaseRoot "update-repository"
$RepositoryFilesRoot = Join-Path $RepositoryRoot "files"
$MrpackPath = Join-Path $ReleaseRoot "모닥불-Season-1-v$Version.mrpack"
$CurseForgePackPath = Join-Path $ReleaseRoot "모닥불-Season-1-v$Version-CurseForge.zip"

if ([string]::IsNullOrWhiteSpace($LargeFileReleaseBaseUrl)) {
    $LargeFileReleaseBaseUrl = "https://github.com/GTYoon/modakbul-client/releases/download/client-v$Version"
}

function Reset-SafeDirectory {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $allowed = [IO.Path]::GetFullPath($BuildRoot).TrimEnd("\") + "\"
    if (-not $full.StartsWith($allowed, [StringComparison]::OrdinalIgnoreCase)) {
        throw "빌드 폴더 밖은 초기화할 수 없습니다: $full"
    }
    if (Test-Path -LiteralPath $full) {
        Remove-Item -LiteralPath $full -Recurse -Force
    }
    New-Item -ItemType Directory -Force -Path $full | Out-Null
}

function Copy-DirectoryContents {
    param(
        [string]$Source,
        [string]$Destination
    )
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
}

function Get-JarFabricMetadata {
    param([string]$JarPath)
    $archive = $null
    try {
        $archive = [IO.Compression.ZipFile]::OpenRead($JarPath)
        $entry = $archive.GetEntry("fabric.mod.json")
        if ($null -eq $entry) {
            return [pscustomobject]@{ id = ""; environment = "*" }
        }
        $reader = [IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8)
        try {
            $json = $reader.ReadToEnd() | ConvertFrom-Json
            $environment = if ([string]::IsNullOrWhiteSpace([string]$json.environment)) {
                "*"
            } else {
                [string]$json.environment
            }
            return [pscustomobject]@{
                id = [string]$json.id
                environment = $environment
            }
        } finally {
            $reader.Dispose()
        }
    } finally {
        if ($null -ne $archive) {
            $archive.Dispose()
        }
    }
}

function New-ModEntry {
    param(
        [IO.FileInfo]$File,
        [string]$Environment,
        [string]$DownloadUrl
    )
    $sha1 = (Get-FileHash -Algorithm SHA1 -LiteralPath $File.FullName).Hash.ToLowerInvariant()
    $sha512 = (Get-FileHash -Algorithm SHA512 -LiteralPath $File.FullName).Hash.ToLowerInvariant()
    $env = if ($Environment -eq "client") {
        [ordered]@{ client = "required"; server = "unsupported" }
    } else {
        [ordered]@{ client = "required"; server = "required" }
    }
    return [ordered]@{
        path = "mods/$($File.Name)"
        hashes = [ordered]@{
            sha512 = $sha512
            sha1 = $sha1
        }
        env = $env
        downloads = @($DownloadUrl)
        fileSize = [long]$File.Length
    }
}

function Add-RepositoryFile {
    param(
        [string]$Source,
        [string]$RelativePath,
        [System.Collections.ArrayList]$ManifestFiles,
        [string]$AbsoluteUrl = ""
    )
    $sourceItem = Get-Item -LiteralPath $Source
    $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $sourceItem.FullName).Hash.ToLowerInvariant()
    $entry = [ordered]@{
        path = $RelativePath.Replace("\", "/")
        sha256 = $sha256
        size = [long]$sourceItem.Length
    }
    if (-not [string]::IsNullOrWhiteSpace($AbsoluteUrl)) {
        $entry.url = $AbsoluteUrl
    } elseif ($sourceItem.Length -gt $RepositoryFileLimitBytes) {
        $extension = [IO.Path]::GetExtension($sourceItem.Name).ToLowerInvariant()
        $assetName = "large-$($sha256.Substring(0, 16))$extension"
        $assetDestination = Join-Path $ReleaseAssetsRoot $assetName
        $entry.url = $LargeFileReleaseBaseUrl.TrimEnd("/") + "/" + [Uri]::EscapeDataString($assetName)
        if (-not (Test-Path -LiteralPath $assetDestination -PathType Leaf)) {
            Copy-Item -LiteralPath $sourceItem.FullName -Destination $assetDestination -Force
        }
    } else {
        $destination = Join-Path $RepositoryFilesRoot $RelativePath
        New-Item -ItemType Directory -Force -Path (Split-Path -Parent $destination) | Out-Null
        Copy-Item -LiteralPath $sourceItem.FullName -Destination $destination -Force
    }
    [void]$ManifestFiles.Add($entry)
}

function Add-RepositoryTree {
    param(
        [string]$SourceRoot,
        [string]$RelativeRoot,
        [System.Collections.ArrayList]$ManifestFiles
    )
    if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) {
        return
    }
    Get-ChildItem -LiteralPath $SourceRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        $suffix = $_.FullName.Substring($SourceRoot.Length).TrimStart("\", "/")
        $relative = ($RelativeRoot.TrimEnd("/", "\") + "/" + $suffix.Replace("\", "/"))
        Add-RepositoryFile -Source $_.FullName -RelativePath $relative -ManifestFiles $ManifestFiles
    }
}

if (-not (Test-Path -LiteralPath $ReferenceMetadataPath -PathType Leaf)) {
    throw "본 PC 기준 클라이언트를 찾지 못했습니다: $ReferenceClientRoot"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.Drawing
New-Item -ItemType Directory -Force -Path $ReleaseRoot | Out-Null
Reset-SafeDirectory -Path $WorkRoot
Reset-SafeDirectory -Path $RepositoryRoot
Reset-SafeDirectory -Path $ReleaseAssetsRoot
New-Item -ItemType Directory -Force -Path $PackRoot, $OverridesRoot, $RepositoryFilesRoot | Out-Null

Write-Host "[1/8] 본 PC 실사용 클라이언트 자료 복사"
foreach ($folder in @("config", "datapacks", "defaultconfigs", "resourcepacks", "shaderpacks")) {
    $source = Join-Path $ReferenceClientRoot $folder
    if (Test-Path -LiteralPath $source -PathType Container) {
        Copy-DirectoryContents -Source $source -Destination (Join-Path $OverridesRoot $folder)
    }
}

$overrideMods = Join-Path $OverridesRoot "mods"
New-Item -ItemType Directory -Force -Path $overrideMods | Out-Null

Write-Host "[2/8] 현재 서버 설정을 클라이언트 기준으로 병합"
$stagedConfig = Join-Path $OverridesRoot "config"
Copy-DirectoryContents -Source (Join-Path $Workspace "config\cobbleverse") -Destination (Join-Path $stagedConfig "cobbleverse")
Copy-Item -LiteralPath (Join-Path $Workspace "config\gcmclaims.json") -Destination (Join-Path $stagedConfig "gcmclaims.json") -Force
Copy-Item -LiteralPath (Join-Path $Workspace "config\cobblemon-battle-extras.json") -Destination (Join-Path $stagedConfig "cobblemon-battle-extras.json") -Force
Copy-Item -LiteralPath (Join-Path $Workspace "config\limitedlegends.json") -Destination (Join-Path $stagedConfig "limitedlegends.json") -Force
Copy-Item -LiteralPath (Join-Path $Workspace "config\lumymon.json") -Destination (Join-Path $stagedConfig "lumymon.json") -Force
New-Item -ItemType Directory -Force -Path (Join-Path $stagedConfig "cobblemon_ranked") | Out-Null
Copy-Item -LiteralPath (Join-Path $Workspace "config\cobblemon_ranked\messages.json") -Destination (Join-Path $stagedConfig "cobblemon_ranked\messages.json") -Force
Copy-Item -LiteralPath (Join-Path $Workspace "datapacks\COBBLEVERSE-DP-v19-CF.zip") -Destination (Join-Path $OverridesRoot "datapacks\COBBLEVERSE-DP-v19-CF.zip") -Force

$battleExtrasConfigPath = Join-Path $stagedConfig "cobblemon-battle-extras.json"
$battleExtrasConfig = Get-Content -LiteralPath $battleExtrasConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$battleExtrasConfig.enableMoveDamageRange = $false
[IO.File]::WriteAllText(
    $battleExtrasConfigPath,
    ($battleExtrasConfig | ConvertTo-Json -Depth 20),
    [Text.UTF8Encoding]::new($false)
)

$rankedRuntimeDatabase = Join-Path $stagedConfig "cobblemon_ranked\ranked.db"
if (Test-Path -LiteralPath $rankedRuntimeDatabase) {
    Remove-Item -LiteralPath $rankedRuntimeDatabase -Force
}
$globalKoreanPackMeta = Join-Path $stagedConfig "cobbleverse\pack.mcmeta"
if (Test-Path -LiteralPath $globalKoreanPackMeta) {
    $meta = Get-Content -LiteralPath $globalKoreanPackMeta -Raw -Encoding UTF8 | ConvertFrom-Json
    $meta.pack.description = "모닥불 Season 1 코블몬 한글화 v1.1"
    [IO.File]::WriteAllText(
        $globalKoreanPackMeta,
        ($meta | ConvertTo-Json -Depth 8),
        [Text.UTF8Encoding]::new($false)
    )
}

$stagedDefaultOptions = Join-Path $stagedConfig "defaultoptions"
New-Item -ItemType Directory -Force -Path $stagedDefaultOptions | Out-Null
Copy-Item -LiteralPath (Join-Path $ReferenceClientRoot "options.txt") -Destination (Join-Path $OverridesRoot "options.txt") -Force
$optionsPath = Join-Path $OverridesRoot "options.txt"
$optionsText = Get-Content -LiteralPath $optionsPath -Raw -Encoding UTF8
$optionsText = [regex]::Replace($optionsText, '(?m)^lang:.*$', "lang:ko_kr")
$optionsText = [regex]::Replace(
    $optionsText,
    '(?m)^key_key\.lumymon\.access_pc:.*$',
    "key_key.lumymon.access_pc:key.keyboard.unknown"
)
$optionsText = $optionsText.Replace(
    '"file/!Cobbleverse Questsbook Resourcepack.zip"]',
    '"file/!Cobbleverse Questsbook Resourcepack.zip","file/Modakbul-Korean-v1.1.zip"]'
)
[IO.File]::WriteAllText($optionsPath, $optionsText, [Text.UTF8Encoding]::new($false))
Copy-Item -LiteralPath $optionsPath -Destination (Join-Path $stagedDefaultOptions "options.txt") -Force
Copy-Item -LiteralPath (Join-Path $Workspace "config\defaultoptions\keybindings.txt") -Destination (Join-Path $stagedDefaultOptions "keybindings.txt") -Force

Write-Host "[3/8] 모닥불 이름·서버 목록·한글팩 적용"
$fancyOptions = Join-Path $stagedConfig "fancymenu\options.txt"
if (Test-Path -LiteralPath $fancyOptions) {
    $text = Get-Content -LiteralPath $fancyOptions -Raw -Encoding UTF8
    $text = [regex]::Replace($text, '(?m)^S:custom_window_title = ''.*?'';$', "S:custom_window_title = '모닥불 Season 1';")
    [IO.File]::WriteAllText($fancyOptions, $text, [Text.UTF8Encoding]::new($false))
}

$fancyCustomization = Join-Path $stagedConfig "fancymenu\customization"
if (Test-Path -LiteralPath $fancyCustomization) {
    Get-ChildItem -LiteralPath $fancyCustomization -File -Filter "*.txt" | ForEach-Object {
        $text = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8
        $text = $text.Replace("cobbleverse_title.png", "modakbul_title.png")
        $text = [regex]::Replace(
            $text,
            '(?m)^  source = &b&lMMO .*경험입니다\.\s*$',
            "  source = &6&l모닥불 Season 1%n%&f전용 서버 클라이언트"
        )
        [IO.File]::WriteAllText($_.FullName, $text, [Text.UTF8Encoding]::new($false))
    }
}

$titlePath = Join-Path $stagedConfig "fancymenu\assets\modakbul_title.png"
$bitmap = [Drawing.Bitmap]::new(1200, 180, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
$graphics = [Drawing.Graphics]::FromImage($bitmap)
try {
    $graphics.Clear([Drawing.Color]::Transparent)
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [Drawing.Text.TextRenderingHint]::AntiAliasGridFit
    $font = [Drawing.Font]::new("Malgun Gothic", 88, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
    $subFont = [Drawing.Font]::new("Segoe UI", 46, [Drawing.FontStyle]::Bold, [Drawing.GraphicsUnit]::Pixel)
    try {
        $black = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(230, 24, 13, 7))
        $orange = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(255, 255, 151, 24))
        $cream = [Drawing.SolidBrush]::new([Drawing.Color]::FromArgb(255, 255, 238, 196))
        try {
            foreach ($offset in @(@(-4,0),@(4,0),@(0,-4),@(0,4),@(-3,-3),@(3,3))) {
                $graphics.DrawString("모닥불", $font, $black, (14 + $offset[0]), (18 + $offset[1]))
            }
            $graphics.DrawString("모닥불", $font, $orange, 14, 18)
            $graphics.DrawString("SEASON 1", $subFont, $black, 417, 72)
            $graphics.DrawString("SEASON 1", $subFont, $cream, 413, 68)
        } finally {
            $black.Dispose()
            $orange.Dispose()
            $cream.Dispose()
        }
    } finally {
        $font.Dispose()
        $subFont.Dispose()
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $titlePath) | Out-Null
    $bitmap.Save($titlePath, [Drawing.Imaging.ImageFormat]::Png)
} finally {
    $graphics.Dispose()
    $bitmap.Dispose()
}

$resourcePackDir = Join-Path $OverridesRoot "resourcepacks"
New-Item -ItemType Directory -Force -Path $resourcePackDir | Out-Null
$localKoreanPack = Join-Path $resourcePackDir "Modakbul-Korean-v1.1.zip"
Copy-Item -LiteralPath (Join-Path $Workspace "client-update\GCM-Korean-Complete-v1.1.zip") -Destination $localKoreanPack -Force
$packArchive = [IO.Compression.ZipFile]::Open($localKoreanPack, [IO.Compression.ZipArchiveMode]::Update)
try {
    $latestKoreanAssets = Join-Path $Workspace "config\cobbleverse\assets"
    Get-ChildItem -LiteralPath $latestKoreanAssets -Recurse -File | Sort-Object FullName | ForEach-Object {
        $suffix = $_.FullName.Substring($latestKoreanAssets.Length).TrimStart("\", "/")
        $entryName = "assets/" + $suffix.Replace("\", "/")
        $oldEntry = $packArchive.GetEntry($entryName)
        if ($null -ne $oldEntry) {
            $oldEntry.Delete()
        }
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $packArchive,
            $_.FullName,
            $entryName,
            [IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }

    $oldMeta = $packArchive.GetEntry("pack.mcmeta")
    if ($null -ne $oldMeta) {
        $oldMeta.Delete()
    }
    $newMeta = $packArchive.CreateEntry("pack.mcmeta", [IO.Compression.CompressionLevel]::Optimal)
    $newMeta.LastWriteTime = [DateTimeOffset]::new(2026, 1, 1, 0, 0, 0, [TimeSpan]::Zero)
    $writer = [IO.StreamWriter]::new($newMeta.Open(), [Text.UTF8Encoding]::new($false))
    try {
        $writer.Write("{`n  `"pack`": {`n    `"pack_format`": 34,`n    `"supported_formats`": [34, 34],`n    `"description`": `"모닥불 Season 1 코블몬 한글화 v1.1`"`n  }`n}`n")
    } finally {
        $writer.Dispose()
    }
} finally {
    $packArchive.Dispose()
}

$nbtJava = Join-Path $Workspace "tools\NbtStringTool.java"
& javac -encoding UTF-8 $nbtJava
if ($LASTEXITCODE -ne 0) {
    throw "servers.dat 도구 컴파일에 실패했습니다."
}
& java -cp (Join-Path $Workspace "tools") NbtStringTool write-server (Join-Path $stagedDefaultOptions "servers.dat") "모닥불 Season 1" $ServerAddress
if ($LASTEXITCODE -ne 0) {
    throw "전용 서버 목록 생성에 실패했습니다."
}
Copy-Item -LiteralPath (Join-Path $stagedDefaultOptions "servers.dat") -Destination (Join-Path $OverridesRoot "servers.dat") -Force

$updaterTarget = Join-Path $OverridesRoot "modakbul-updater"
Copy-DirectoryContents -Source (Join-Path $Workspace "client-kit\updater") -Destination $updaterTarget
$channelPath = Join-Path $updaterTarget "channel.json"
$channelText = Get-Content -LiteralPath $channelPath -Raw -Encoding UTF8
$channelText = $channelText.Replace("__UPDATE_MANIFEST_URL__", $UpdateManifestUrl)
[IO.File]::WriteAllText($channelPath, $channelText, [Text.UTF8Encoding]::new($false))

Write-Host "[4/8] 실사용 클라이언트 모드와 CurseForge 원본 주소 분류"
$referenceInstance = Get-Content -LiteralPath $ReferenceMetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
$trackedDownloads = @{}
$trackedProjects = @{}
foreach ($addon in @($referenceInstance.installedAddons)) {
    $folder = ([string]$addon.categorySection.path).Trim("\", "/")
    $fileName = [string]$addon.fileNameOnDisk
    if ([string]::IsNullOrWhiteSpace($folder) -or [string]::IsNullOrWhiteSpace($fileName)) {
        continue
    }
    $relativePath = "$folder/$fileName"
    $sourcePath = Join-Path $ReferenceClientRoot $relativePath.Replace("/", "\")
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        continue
    }
    $expectedSha1 = [string](@($addon.installedFile.hashes | Where-Object {
        [int]$_.type -eq 1
    } | Select-Object -First 1).value)
    $actualSha1 = (Get-FileHash -Algorithm SHA1 -LiteralPath $sourcePath).Hash.ToLowerInvariant()
    $downloadUrl = [string]$addon.installedFile.downloadUrl
    if ($actualSha1 -eq $expectedSha1.ToLowerInvariant() -and
        -not [string]::IsNullOrWhiteSpace($downloadUrl)) {
        $trackedDownloads[$relativePath.ToLowerInvariant()] = $downloadUrl
        $trackedProjects[$relativePath.ToLowerInvariant()] = [pscustomobject]@{
            projectID = [int]$addon.addonID
            fileID = [int]$addon.installedFile.id
        }
    }
}

$clientMods = @()
Get-ChildItem -LiteralPath (Join-Path $ReferenceClientRoot "mods") -File -Filter "*.jar" | Sort-Object Name | ForEach-Object {
    $metadata = Get-JarFabricMetadata -JarPath $_.FullName
    if ($metadata.environment -ne "server" -and $metadata.id -ne "pasture-loot") {
        $clientMods += [pscustomobject]@{
            File = $_
            Id = $metadata.id
            Environment = $metadata.environment
        }
    }
}

$workspaceClientJars = @(
    (Join-Path $Workspace "gcm-client-localization\build\libs\gcm-client-localization-1.0.0.jar")
)
foreach ($clientJarPath in $workspaceClientJars) {
    if (-not (Test-Path -LiteralPath $clientJarPath -PathType Leaf)) {
        throw "클라이언트 전용 모드를 찾지 못했습니다: $clientJarPath"
    }
    $clientJar = Get-Item -LiteralPath $clientJarPath
    $metadata = Get-JarFabricMetadata -JarPath $clientJar.FullName
    if (-not @($clientMods | Where-Object Id -eq $metadata.id)) {
        $clientMods += [pscustomobject]@{
            File = $clientJar
            Id = $metadata.id
            Environment = $metadata.environment
        }
    }
}

$packFiles = [System.Collections.ArrayList]::new()
$repositoryManifestFiles = [System.Collections.ArrayList]::new()
$publicCount = 0
$bundledCount = 0
foreach ($mod in $clientMods) {
    $relativePath = "mods/$($mod.File.Name)"
    $downloadUrl = [string]$trackedDownloads[$relativePath.ToLowerInvariant()]

    if (-not [string]::IsNullOrWhiteSpace($downloadUrl)) {
        [void]$packFiles.Add((New-ModEntry -File $mod.File -Environment $mod.Environment -DownloadUrl $downloadUrl))
        Add-RepositoryFile `
            -Source $mod.File.FullName `
            -RelativePath "mods/$($mod.File.Name)" `
            -ManifestFiles $repositoryManifestFiles `
            -AbsoluteUrl $downloadUrl
        $publicCount++
    } else {
        Copy-Item -LiteralPath $mod.File.FullName -Destination (Join-Path $overrideMods $mod.File.Name) -Force
        Add-RepositoryFile `
            -Source $mod.File.FullName `
            -RelativePath "mods/$($mod.File.Name)" `
            -ManifestFiles $repositoryManifestFiles
        $bundledCount++
    }
}

foreach ($folder in @("resourcepacks", "shaderpacks")) {
    $sourceFolder = Join-Path $ReferenceClientRoot $folder
    Get-ChildItem -LiteralPath $sourceFolder -File | Sort-Object Name | ForEach-Object {
        $relativePath = "$folder/$($_.Name)"
        $downloadUrl = [string]$trackedDownloads[$relativePath.ToLowerInvariant()]
        $stagedPath = Join-Path $OverridesRoot $relativePath.Replace("/", "\")
        if (-not [string]::IsNullOrWhiteSpace($downloadUrl)) {
            $entry = [ordered]@{
                path = $relativePath
                hashes = [ordered]@{
                    sha512 = (Get-FileHash -Algorithm SHA512 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
                    sha1 = (Get-FileHash -Algorithm SHA1 -LiteralPath $_.FullName).Hash.ToLowerInvariant()
                }
                env = [ordered]@{ client = "required"; server = "optional" }
                downloads = @($downloadUrl)
                fileSize = [long]$_.Length
            }
            [void]$packFiles.Add($entry)
            if (Test-Path -LiteralPath $stagedPath) {
                Remove-Item -LiteralPath $stagedPath -Force
            }
            Add-RepositoryFile `
                -Source $_.FullName `
                -RelativePath $relativePath `
                -ManifestFiles $repositoryManifestFiles `
                -AbsoluteUrl $downloadUrl
        } else {
            Add-RepositoryFile `
                -Source $_.FullName `
                -RelativePath $relativePath `
                -ManifestFiles $repositoryManifestFiles
        }
    }
}

Write-Host "[5/8] 자동 업데이트 저장소 생성"
Add-RepositoryTree -SourceRoot (Join-Path $stagedConfig "cobbleverse") -RelativeRoot "config/cobbleverse" -ManifestFiles $repositoryManifestFiles
Add-RepositoryTree -SourceRoot (Join-Path $stagedConfig "fancymenu") -RelativeRoot "config/fancymenu" -ManifestFiles $repositoryManifestFiles
Add-RepositoryTree -SourceRoot $stagedDefaultOptions -RelativeRoot "config/defaultoptions" -ManifestFiles $repositoryManifestFiles
Add-RepositoryTree -SourceRoot (Join-Path $OverridesRoot "datapacks") -RelativeRoot "datapacks" -ManifestFiles $repositoryManifestFiles
Add-RepositoryTree -SourceRoot (Join-Path $OverridesRoot "defaultconfigs") -RelativeRoot "defaultconfigs" -ManifestFiles $repositoryManifestFiles
Get-ChildItem -LiteralPath (Join-Path $OverridesRoot "shaderpacks") -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    Add-RepositoryTree `
        -SourceRoot $_.FullName `
        -RelativeRoot "shaderpacks/$($_.Name)" `
        -ManifestFiles $repositoryManifestFiles
}
foreach ($relative in @(
    "config\cobblemon-battle-extras.json",
    "config\cobblemon_ranked\messages.json",
    "config\gcmclaims.json",
    "config\limitedlegends.json",
    "config\lumymon.json",
    "config\global_packs.toml",
    "config\resourcepackoverrides.json",
    "config\iris.properties"
)) {
    $source = Join-Path $OverridesRoot $relative
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Add-RepositoryFile -Source $source -RelativePath $relative.Replace("\", "/") -ManifestFiles $repositoryManifestFiles
    }
}
Add-RepositoryFile -Source $localKoreanPack -RelativePath "resourcepacks/Modakbul-Korean-v1.1.zip" -ManifestFiles $repositoryManifestFiles
Add-RepositoryFile -Source (Join-Path $updaterTarget "update.ps1") -RelativePath "modakbul-updater/update.ps1" -ManifestFiles $repositoryManifestFiles
Add-RepositoryFile -Source (Join-Path $updaterTarget "update.cmd") -RelativePath "modakbul-updater/update.cmd" -ManifestFiles $repositoryManifestFiles

$repositoryManifest = [ordered]@{
    schemaVersion = 1
    packId = "modakbul-season-1"
    displayName = "모닥불 Season 1"
    version = $Version
    minecraft = "1.21.1"
    fabricLoader = "0.19.3"
    generatedAt = (Get-Date).ToUniversalTime().ToString("o")
    files = @($repositoryManifestFiles | Sort-Object { $_.path })
}
[IO.File]::WriteAllText(
    (Join-Path $RepositoryRoot "manifest.json"),
    ($repositoryManifest | ConvertTo-Json -Depth 10),
    [Text.UTF8Encoding]::new($false)
)

$installedState = [ordered]@{
    packId = "modakbul-season-1"
    version = $Version
    installedAt = (Get-Date).ToString("o")
    files = @($repositoryManifest.files | ForEach-Object {
        [ordered]@{ path = $_.path; sha256 = $_.sha256 }
    })
}
[IO.File]::WriteAllText(
    (Join-Path $updaterTarget "installed-state.json"),
    ($installedState | ConvertTo-Json -Depth 8),
    [Text.UTF8Encoding]::new($false)
)

Write-Host "[6/8] Modrinth 팩 인덱스 생성"
$newIndex = [ordered]@{
    game = "minecraft"
    formatVersion = 1
    versionId = $Version
    name = "모닥불 Season 1"
    summary = "모닥불 Season 1 전용 Cobblemon 클라이언트"
    files = @($packFiles | Sort-Object { $_.path })
    dependencies = [ordered]@{
        minecraft = "1.21.1"
        "fabric-loader" = "0.19.3"
    }
}
[IO.File]::WriteAllText(
    (Join-Path $PackRoot "modrinth.index.json"),
    ($newIndex | ConvertTo-Json -Depth 20),
    [Text.UTF8Encoding]::new($false)
)

Write-Host "[7/8] Modrinth·CurseForge 배포 파일 압축"
if (Test-Path -LiteralPath $MrpackPath) {
    Remove-Item -LiteralPath $MrpackPath -Force
}
$outputArchive = [IO.Compression.ZipFile]::Open($MrpackPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    Get-ChildItem -LiteralPath $PackRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relativeName = $_.FullName.Substring($PackRoot.Length).TrimStart("\", "/").Replace("\", "/")
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $outputArchive,
            $_.FullName,
            $relativeName,
            [IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
} finally {
    $outputArchive.Dispose()
}

$curseForgeFiles = @($packFiles | Sort-Object { $_.path } | ForEach-Object {
    $project = $trackedProjects[([string]$_.path).ToLowerInvariant()]
    if ($null -eq $project) {
        throw "CurseForge 프로젝트 정보가 없는 다운로드 파일입니다: $($_.path)"
    }
    [ordered]@{
        projectID = [int]$project.projectID
        fileID = [int]$project.fileID
        required = $true
    }
})
$curseForgeManifest = [ordered]@{
    minecraft = [ordered]@{
        version = "1.21.1"
        modLoaders = @(
            [ordered]@{
                id = "fabric-0.19.3"
                primary = $true
            }
        )
    }
    manifestType = "minecraftModpack"
    manifestVersion = 1
    name = "모닥불 Season 1"
    version = $Version
    author = "모닥불 Season 1 운영팀"
    files = $curseForgeFiles
    overrides = "overrides"
}
$curseForgeManifestPath = Join-Path $WorkRoot "curseforge-manifest.json"
[IO.File]::WriteAllText(
    $curseForgeManifestPath,
    ($curseForgeManifest | ConvertTo-Json -Depth 10),
    [Text.UTF8Encoding]::new($false)
)
if (Test-Path -LiteralPath $CurseForgePackPath) {
    Remove-Item -LiteralPath $CurseForgePackPath -Force
}
$curseForgeArchive = [IO.Compression.ZipFile]::Open($CurseForgePackPath, [IO.Compression.ZipArchiveMode]::Create)
try {
    [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $curseForgeArchive,
        $curseForgeManifestPath,
        "manifest.json",
        [IO.Compression.CompressionLevel]::Optimal
    ) | Out-Null
    Get-ChildItem -LiteralPath $OverridesRoot -Recurse -File | Sort-Object FullName | ForEach-Object {
        $relativeName = $_.FullName.Substring($OverridesRoot.Length).TrimStart("\", "/").Replace("\", "/")
        [IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
            $curseForgeArchive,
            $_.FullName,
            "overrides/$relativeName",
            [IO.Compression.CompressionLevel]::Optimal
        ) | Out-Null
    }
} finally {
    $curseForgeArchive.Dispose()
}

Copy-DirectoryContents -Source (Join-Path $Workspace "client-kit\install") -Destination $ReleaseRoot

$repositoryGuide = @"
모닥불 Season 1 자동 업데이트 저장소
====================================

이 폴더의 manifest.json, distribution.json, fabric 폴더와 files 폴더를 HTTPS 정적 호스팅에 그대로 올립니다.
그 다음 아래처럼 빌드를 다시 실행하면 모든 클라이언트가 실행 시 업데이트를 확인합니다.

powershell -ExecutionPolicy Bypass -File tools\build-modakbul-client.ps1 ``
  -Version "$Version" ``
  -ServerAddress "$ServerAddress" ``
  -UpdateManifestUrl "https://호스트/경로/manifest.json" ``
  -LauncherFilesBaseUrl "https://호스트/경로" ``
  -LauncherServerIconUrl "https://호스트/경로/server-icon.png" ``
  -LauncherNewsRssUrl "https://github.com/GTYoon/modakbul-launcher/releases.atom"

운영 순서:
1. 서버/클라이언트 파일 수정
2. 위 빌드 명령 실행
3. release\update-repository 전체 업로드
4. 서버 테스트 후 유저에게 실행 안내

주의:
- manifest.json과 files는 반드시 같은 상대 구조를 유지합니다.
- HTTPS 사용을 권장합니다.
- files 폴더에는 공식 CurseForge 주소로 직접 받을 수 없는 파일과 모닥불 전용 설정만 들어갑니다.
"@
[IO.File]::WriteAllText(
    (Join-Path $RepositoryRoot "배포-안내.txt"),
    $repositoryGuide,
    [Text.UTF8Encoding]::new($false)
)

$distributionBuilder = Join-Path $Workspace "client-launcher\modakbul-season1\tools\Build-Distribution.ps1"
$distributionTester = Join-Path $Workspace "client-launcher\modakbul-season1\tools\Test-Distribution.ps1"
if (-not (Test-Path -LiteralPath $distributionBuilder -PathType Leaf)) {
    throw "Helios 배포 생성기를 찾을 수 없습니다: $distributionBuilder"
}
if (-not (Test-Path -LiteralPath $distributionTester -PathType Leaf)) {
    throw "Helios 배포 검증기를 찾을 수 없습니다: $distributionTester"
}

$distributionFileName = if ($LauncherFilesBaseUrl -eq "__CLIENT_FILES_BASE_URL__") {
    "distribution.template.json"
} else {
    "distribution.json"
}
$distributionPath = Join-Path $RepositoryRoot $distributionFileName

& $distributionBuilder `
    -Version $Version `
    -ServerAddress $ServerAddress `
    -FilesBaseUrl $LauncherFilesBaseUrl `
    -ServerIconUrl $LauncherServerIconUrl `
    -NewsRssUrl $LauncherNewsRssUrl `
    -ReferenceClientRoot $ReferenceClientRoot `
    -UpdateRepositoryRoot $RepositoryRoot `
    -OutputPath $distributionPath | Out-Host

& $distributionTester -DistributionPath $distributionPath | Out-Host

Write-Host "[8/8] 무결성 보고서 생성"
$mrpackHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $MrpackPath).Hash.ToLowerInvariant()
$curseForgePackHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $CurseForgePackPath).Hash.ToLowerInvariant()
$repoFiles = @(Get-ChildItem -LiteralPath $RepositoryFilesRoot -Recurse -File)
$releaseAssetFiles = @(Get-ChildItem -LiteralPath $ReleaseAssetsRoot -File)
$report = [ordered]@{
    name = "모닥불 Season 1"
    version = $Version
    serverAddress = $ServerAddress
    updateManifestUrl = $UpdateManifestUrl
    minecraft = "1.21.1"
    fabricLoader = "0.19.3"
    clientMods = $clientMods.Count
    curseForgeHostedMods = $publicCount
    bundledPrivateOrCustomMods = $bundledCount
    originalNonModDownloads = @($packFiles | Where-Object { $_.path -notlike "mods/*" }).Count
    updaterManagedFiles = $repositoryManifest.files.Count
    repositoryLocalFiles = $repoFiles.Count
    repositoryReleaseAssets = $releaseAssetFiles.Count
    releaseAssetsPath = $ReleaseAssetsRoot
    launcherDistribution = $distributionPath
    mrpack = [ordered]@{
        path = $MrpackPath
        size = (Get-Item -LiteralPath $MrpackPath).Length
        sha256 = $mrpackHash
    }
    curseForgePack = [ordered]@{
        path = $CurseForgePackPath
        size = (Get-Item -LiteralPath $CurseForgePackPath).Length
        sha256 = $curseForgePackHash
    }
}
[IO.File]::WriteAllText(
    (Join-Path $ReleaseRoot "build-report.json"),
    ($report | ConvertTo-Json -Depth 8),
    [Text.UTF8Encoding]::new($false)
)

$report | ConvertTo-Json -Depth 8
