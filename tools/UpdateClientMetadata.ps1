[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version
)

$ErrorActionPreference = "Stop"

$RepositoryRoot = [IO.Path]::GetFullPath((Split-Path -Parent $PSScriptRoot))
$FilesRoot = Join-Path $RepositoryRoot "files"
$ManifestPath = Join-Path $RepositoryRoot "manifest.json"
$DistributionPath = Join-Path $RepositoryRoot "distribution.json"
$Utf8NoBom = [Text.UTF8Encoding]::new($false)

$ManagedPaths = @(
    "config/cobblemon-battle-extras.json",
    "config/cobbleverse/assets/cobblemon-battle-extras/lang/ko_kr.json",
    "config/fancymenu/assets/icon_arena.png",
    "config/fancymenu/assets/icon_casino.png",
    "config/fancymenu/assets/icon_compass.png",
    "config/fancymenu/assets/icon_exit.png",
    "config/fancymenu/assets/icon_home.png",
    "config/fancymenu/assets/icon_market.png",
    "config/fancymenu/assets/icon_pokemon.png",
    "config/fancymenu/assets/icon_settings.png",
    "config/fancymenu/assets/icon_village.png",
    "config/fancymenu/assets/ui_button.png",
    "config/fancymenu/assets/ui_button_hover.png",
    "config/fancymenu/assets/ui_button_inactive.png",
    "config/fancymenu/assets/ui_button_selected.png",
    "config/fancymenu/assets/ui_panel.png",
    "config/fancymenu/assets/ui_panel_soft.png",
    "config/fancymenu/custom_gui_screens.txt",
    "config/fancymenu/customization/cobbleverse_pause_menu.txt",
    "config/fancymenu/customization/modakbul_quick_guide.txt",
    "config/fancymenu/customization/modakbul_region_travel.txt",
    "mods/gcm-client-localization-1.0.0.jar"
)

function Get-TextSha1Prefix {
    param([string]$Text)

    $sha1 = [Security.Cryptography.SHA1]::Create()
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes($Text)
        $hash = $sha1.ComputeHash($bytes)
        $hex = -join ($hash | ForEach-Object { $_.ToString("x2") })
        return $hex.Substring(0, 16)
    } finally {
        $sha1.Dispose()
    }
}

function Get-SourceFile {
    param([string]$RelativePath)

    $candidate = [IO.Path]::GetFullPath((Join-Path $FilesRoot $RelativePath.Replace("/", "\")))
    $allowedRoot = $FilesRoot.TrimEnd("\") + "\"
    if (-not $candidate.StartsWith($allowedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Managed path escaped the files root: $RelativePath"
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Managed client file does not exist: $RelativePath"
    }
    return Get-Item -LiteralPath $candidate
}

$manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$manifest.version = $Version
$manifest.generatedAt = (Get-Date).ToUniversalTime().ToString("o")
$manifestFiles = [System.Collections.ArrayList]::new()
foreach ($entry in @($manifest.files)) {
    [void]$manifestFiles.Add($entry)
}

foreach ($relativePath in $ManagedPaths) {
    $source = Get-SourceFile -RelativePath $relativePath
    $sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $source.FullName).Hash.ToLowerInvariant()
    $entry = @($manifestFiles | Where-Object { [string]$_.path -eq $relativePath } | Select-Object -First 1)
    if ($entry.Count -eq 0) {
        [void]$manifestFiles.Add([pscustomobject][ordered]@{
            path = $relativePath
            sha256 = $sha256
            size = [long]$source.Length
        })
    } else {
        $entry[0].sha256 = $sha256
        $entry[0].size = [long]$source.Length
    }
}
$manifest.files = @($manifestFiles | Sort-Object { [string]$_.path })
[IO.File]::WriteAllText(
    $ManifestPath,
    ($manifest | ConvertTo-Json -Depth 100),
    $Utf8NoBom
)

$distribution = Get-Content -LiteralPath $DistributionPath -Raw -Encoding UTF8 | ConvertFrom-Json
$distribution.version = $Version
foreach ($server in @($distribution.servers)) {
    $server.version = $Version
    $modules = [System.Collections.ArrayList]::new()
    foreach ($module in @($server.modules)) {
        [void]$modules.Add($module)
    }

    foreach ($relativePath in $ManagedPaths) {
        $source = Get-SourceFile -RelativePath $relativePath
        $md5 = (Get-FileHash -Algorithm MD5 -LiteralPath $source.FullName).Hash.ToLowerInvariant()
        $isFabricMod = $relativePath.StartsWith("mods/", [StringComparison]::OrdinalIgnoreCase)
        $moduleId = if ($isFabricMod) {
            "generated.fabricmod:mod-$(Get-TextSha1Prefix -Text $relativePath):$Version@jar"
        } else {
            "generated.file:file-$(Get-TextSha1Prefix -Text $relativePath):$Version"
        }
        $artifactPath = if ($isFabricMod) {
            [IO.Path]::GetFileName($relativePath)
        } else {
            $relativePath
        }
        $rawUrl = "https://raw.githubusercontent.com/GTYoon/modakbul-client/main/files/$relativePath"
        $matching = @($modules | Where-Object {
            $null -ne $_.artifact -and (
                [string]$_.artifact.path -eq $relativePath -or (
                    $isFabricMod -and
                    [string]$_.type -eq "FabricMod" -and
                    [string]$_.artifact.path -eq $artifactPath
                )
            )
        } | Select-Object -First 1)

        if ($matching.Count -eq 0) {
            [void]$modules.Add([pscustomobject][ordered]@{
                id = $moduleId
                name = [IO.Path]::GetFileName($relativePath)
                type = if ($isFabricMod) { "FabricMod" } else { "File" }
                artifact = [pscustomobject][ordered]@{
                    size = [long]$source.Length
                    MD5 = $md5
                    url = $rawUrl
                    path = $artifactPath
                }
            })
        } else {
            $matching[0].id = $moduleId
            $matching[0].name = [IO.Path]::GetFileName($relativePath)
            $matching[0].type = if ($isFabricMod) { "FabricMod" } else { "File" }
            $matching[0].artifact.size = [long]$source.Length
            $matching[0].artifact.MD5 = $md5
            $matching[0].artifact.url = $rawUrl
            $matching[0].artifact.path = $artifactPath
        }
    }
    $server.modules = @($modules)
}
[IO.File]::WriteAllText(
    $DistributionPath,
    ($distribution | ConvertTo-Json -Depth 100),
    $Utf8NoBom
)

Write-Host "Updated manifest.json and distribution.json to $Version"
