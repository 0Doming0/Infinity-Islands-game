param(
    [switch]$Commit,
    [switch]$AllowOtherBranch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBranch = 'agent/lobby-mvp-integration'
$InstallerVersion = 6
$PayloadSha256 = 'abc195860df6f666a6fd1376590af01a3d28870e6095c1aec103c2243594e196'
$script:InstallerScriptPath = $PSCommandPath

function Stop-Installer([string]$Message) {
    throw $Message
}

function Invoke-Git {
    param(
        [Parameter(Mandatory=$true)][string[]]$GitArguments,
        [Parameter(Mandatory=$true)][string]$WorkingDirectory
    )

    $PreviousLocation = Get-Location
    try {
        Set-Location $WorkingDirectory
        $Output = & git @GitArguments 2>&1
        $ExitCode = $LASTEXITCODE
        if ($ExitCode -ne 0) {
            $Detail = ($Output | Out-String).Trim()
            throw "git $($GitArguments -join ' ') falhou com codigo $ExitCode.`n$Detail"
        }
        return $Output
    }
    finally {
        Set-Location $PreviousLocation
    }
}

function Get-RepositoryRoot {
    $Output = & git rev-parse --show-toplevel 2>&1
    $ExitCode = $LASTEXITCODE
    if ($ExitCode -ne 0) {
        $Detail = ($Output | Out-String).Trim()
        throw "Execute este instalador dentro do repositorio Infinity Islands.`n$Detail"
    }

    $First = @($Output)[0]
    if ($null -eq $First) {
        throw 'git rev-parse nao retornou a raiz do repositorio.'
    }

    $Root = $First.ToString().Trim()
    if ([string]::IsNullOrWhiteSpace($Root)) {
        throw 'Raiz do repositorio vazia.'
    }
    return $Root
}

function Invoke-GitPatch {
    param(
        [Parameter(Mandatory=$true)][string]$Repository,
        [Parameter(Mandatory=$true)][string]$PatchPath,
        [Parameter(Mandatory=$true)][string]$Label
    )

    $PreviousLocation = Get-Location
    try {
        Set-Location $Repository

        $CheckOutput = & git apply --check --whitespace=nowarn $PatchPath 2>&1
        $CheckCode = $LASTEXITCODE
        if ($CheckCode -ne 0) {
            $Detail = ($CheckOutput | Out-String).Trim()
            throw "$Label falhou no git apply --check.`n$Detail"
        }

        $ApplyOutput = & git apply --whitespace=nowarn $PatchPath 2>&1
        $ApplyCode = $LASTEXITCODE
        if ($ApplyCode -ne 0) {
            $Detail = ($ApplyOutput | Out-String).Trim()
            throw "$Label falhou durante git apply.`n$Detail"
        }
    }
    finally {
        Set-Location $PreviousLocation
    }
}

function Convert-Base64Utf8([string]$Encoded) {
    $Bytes = [Convert]::FromBase64String($Encoded)
    return [Text.Encoding]::UTF8.GetString($Bytes)
}

function Get-Utf8Sha256([string]$Value) {
    $Hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $Bytes = [Text.Encoding]::UTF8.GetBytes($Value)
        return (
            [BitConverter]::ToString($Hasher.ComputeHash($Bytes)) -replace '-', ''
        ).ToLowerInvariant()
    }
    finally {
        $Hasher.Dispose()
    }
}

function Invoke-ExactReplacement {
    param(
        [Parameter(Mandatory=$true)][string]$Repository,
        [Parameter(Mandatory=$true)]$Operation,
        [Parameter(Mandatory=$true)][string]$Label
    )

    $Relative = [string]$Operation.path
    $FullPath = Join-Path $Repository ($Relative -replace '/', [IO.Path]::DirectorySeparatorChar)

    if (-not (Test-Path -LiteralPath $FullPath -PathType Leaf)) {
        throw "${Label}: arquivo nao encontrado: $Relative"
    }

    $RawBytes = [IO.File]::ReadAllBytes($FullPath)
    $HasUtf8Bom = (
        $RawBytes.Length -ge 3 -and
        $RawBytes[0] -eq 0xEF -and
        $RawBytes[1] -eq 0xBB -and
        $RawBytes[2] -eq 0xBF
    )

    $Text = [IO.File]::ReadAllText($FullPath)
    $UsesCrLf = $Text.Contains("`r`n")

    # Canonicalize source text for matching; payload contexts always use LF.
    $Normalized = $Text.Replace("`r`n", "`n").Replace("`r", "`n")
    $Before = Convert-Base64Utf8 ([string]$Operation.before_b64)
    $After = Convert-Base64Utf8 ([string]$Operation.after_b64)

    $BeforeSha = Get-Utf8Sha256 $Before

    if ($BeforeSha -ne [string]$Operation.before_sha256) {
        throw "${Label}: contexto interno corrompido."
    }

    $Pattern = [Regex]::Escape($Before)
    $Count = [Regex]::Matches($Normalized, $Pattern).Count
    if ($Count -ne 1) {
        $AfterCount = [Regex]::Matches($Normalized, [Regex]::Escape($After)).Count
        throw "${Label}: contexto exato esperado 1 vez em '$Relative', encontrado $Count. Contexto novo ja presente: $AfterCount."
    }

    $Updated = $Normalized.Replace($Before, $After)

    # Verify that the old context was actually removed and the new context exists.
    if ([Regex]::Matches($Updated, [Regex]::Escape($Before)).Count -ne 0) {
        throw "${Label}: contexto antigo permaneceu apos substituicao em '$Relative'."
    }
    if ([Regex]::Matches($Updated, [Regex]::Escape($After)).Count -lt 1) {
        throw "${Label}: contexto novo nao apareceu apos substituicao em '$Relative'."
    }

    if ($UsesCrLf) {
        $Updated = $Updated.Replace("`n", "`r`n")
    }

    $Utf8 = [Text.UTF8Encoding]::new([bool]$HasUtf8Bom)
    [IO.File]::WriteAllText($FullPath, $Updated, $Utf8)
}

function Invoke-Operation {
    param(
        [Parameter(Mandatory=$true)][string]$Repository,
        [Parameter(Mandatory=$true)][string]$PayloadDirectory,
        [Parameter(Mandatory=$true)]$Operation,
        [Parameter(Mandatory=$true)][int]$Index,
        [Parameter(Mandatory=$true)][int]$Total
    )

    $TaskNumber = [int]$Operation.task
    $Kind = [string]$Operation.kind
    $Label = ("Task {0:D2} [{1}/{2}] - {3}" -f $TaskNumber, $Index, $Total, [string]$Operation.label)

    Write-Host ('  ' + $Label) -NoNewline
    try {
        if ($Kind -eq 'patch') {
            $PatchPath = Join-Path $PayloadDirectory (
                ([string]$Operation.file) -replace '/', [IO.Path]::DirectorySeparatorChar
            )
            Invoke-GitPatch -Repository $Repository -PatchPath $PatchPath -Label $Label
        }
        elseif ($Kind -eq 'replace') {
            Invoke-ExactReplacement -Repository $Repository -Operation $Operation -Label $Label
        }
        else {
            throw "${Label}: tipo de operacao desconhecido '$Kind'."
        }
        Write-Host '  OK' -ForegroundColor Green
    }
    catch {
        Write-Host '  FALHOU' -ForegroundColor Red
        throw
    }
}

function Get-InstallerRelativePath {
    param(
        [Parameter(Mandatory=$true)][string]$Repository
    )

    try {
        $InstallerFullPath = [IO.Path]::GetFullPath($script:InstallerScriptPath)
        $TrimCharacters = [char[]]@(
            [IO.Path]::DirectorySeparatorChar,
            [IO.Path]::AltDirectorySeparatorChar
        )
        $RepositoryFullPath = [IO.Path]::GetFullPath($Repository).TrimEnd(
            $TrimCharacters
        )

        $Prefix = $RepositoryFullPath + [IO.Path]::DirectorySeparatorChar
        if ($InstallerFullPath.StartsWith($Prefix, [StringComparison]::OrdinalIgnoreCase)) {
            return $InstallerFullPath.Substring($Prefix.Length).Replace(
                [IO.Path]::DirectorySeparatorChar,
                '/'
            )
        }
    }
    catch {}

    return $null
}

function Invoke-Rollback {
    param(
        [Parameter(Mandatory=$true)][string]$Repository,
        [Parameter(Mandatory=$true)][string]$OriginalHead,
        [string]$InstallerRelativePath
    )

    Invoke-Git -GitArguments @('reset', '--hard', $OriginalHead) -WorkingDirectory $Repository | Out-Null

    if ($null -ne $InstallerRelativePath -and -not [string]::IsNullOrWhiteSpace($InstallerRelativePath)) {
        Invoke-Git -GitArguments @(
            'clean', '-fd', '-e', $InstallerRelativePath
        ) -WorkingDirectory $Repository | Out-Null
    }
    else {
        Invoke-Git -GitArguments @('clean', '-fd') -WorkingDirectory $Repository | Out-Null
    }
}

function Test-DiffCheck {
    param(
        [Parameter(Mandatory=$true)][string]$Repository,
        [Parameter(Mandatory=$true)][string]$StageName
    )

    $PreviousLocation = Get-Location
    try {
        Set-Location $Repository
        $Output = & git diff --check 2>&1
        $ExitCode = $LASTEXITCODE
        if ($ExitCode -ne 0) {
            $Detail = ($Output | Out-String).Trim()
            throw "$StageName falhou em git diff --check.`n$Detail"
        }
    }
    finally {
        Set-Location $PreviousLocation
    }
}

Write-Host ''
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host ' Infinity Islands - Instalador Tasks 01 -> 20  [V6 AUDITADA]' -ForegroundColor Cyan
Write-Host ' Patches completos + substituicoes exatas sem line-number falso' -ForegroundColor Cyan
Write-Host '==================================================================' -ForegroundColor Cyan
Write-Host ''

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Host 'ERRO: Git nao foi encontrado no PATH.' -ForegroundColor Red
    exit 1
}

$RepoRoot = $null
$TempBase = $null
$TempWorktree = $null
$StartHead = $null
$BackupBranch = $null
$RealInstallStarted = $false

try {
    $RepoRoot = Get-RepositoryRoot

    $CurrentBranchOutput = Invoke-Git -GitArguments @('branch', '--show-current') -WorkingDirectory $RepoRoot
    $CurrentBranch = (@($CurrentBranchOutput)[0]).ToString().Trim()

    if (-not $AllowOtherBranch -and $CurrentBranch -ne $ExpectedBranch) {
        throw "Branch atual '$CurrentBranch'. Esperado '$ExpectedBranch'."
    }

    $InstallerRelativePath = Get-InstallerRelativePath -Repository $RepoRoot

    $StatusOutput = & git -C $RepoRoot status --porcelain --untracked-files=all 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Nao foi possivel consultar git status.`n$(($StatusOutput | Out-String).Trim())"
    }

    $EffectiveStatus = @()
    foreach ($StatusLine in @($StatusOutput)) {
        $LineText = $StatusLine.ToString()
        $IsInstallerOnly = $false

        if ($null -ne $InstallerRelativePath -and $LineText.StartsWith('?? ')) {
            $UntrackedPath = $LineText.Substring(3).Trim('"').Replace('\', '/')
            if ($UntrackedPath -eq $InstallerRelativePath) {
                $IsInstallerOnly = $true
            }
        }

        if (-not $IsInstallerOnly) {
            $EffectiveStatus += $StatusLine
        }
    }

    if ($EffectiveStatus.Count -gt 0) {
        Write-Host 'Alteracoes nao commitadas detectadas:' -ForegroundColor Yellow
        $EffectiveStatus | ForEach-Object { Write-Host ('  ' + $_) -ForegroundColor Yellow }
        throw 'Faca commit ou stash antes de instalar. O instalador exige worktree limpo.'
    }

    $HeadOutput = Invoke-Git -GitArguments @('rev-parse', 'HEAD') -WorkingDirectory $RepoRoot
    $StartHead = (@($HeadOutput)[0]).ToString().Trim()

    $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $RandomSuffix = [Guid]::NewGuid().ToString('N').Substring(0, 6)
    $BackupBranch = "backup/mobile-dungeon-tasks01-20-v6-$Timestamp-$RandomSuffix"

    $TempBase = Join-Path ([IO.Path]::GetTempPath()) (
        "InfinityIslandsInstallerV6-" + [Guid]::NewGuid().ToString('N')
    )
    $PayloadDir = Join-Path $TempBase 'payload'
    $TempWorktree = Join-Path $TempBase 'preflight-worktree'
    $PayloadZip = Join-Path $TempBase 'payload.zip'
    New-Item -ItemType Directory -Path $PayloadDir -Force | Out-Null

    # Decode embedded payload.
    $PayloadChunks = @(
        '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'
    'F39HBA+/0EwhkT3CsaDhaEEahxfutWahvGsEeBhgKYE5UuFkgTikYxHmrAYcq8KhYzAtfLVZBv//79D6bwsPnDf1yQIa/1//kT0MuNUmI/jh7/Xp/GH5434W'
    'hlGeTZf3syTx93/Lfi0eDFS8Kefpsp74e/3Zu37M7pf3erQszyZGL087Jx+77XJmoIutWbw8Hk0+dksL+jW9PR0tq947o+34Y7ddxfHC3ns/bd/de72sT93I'
    'hlOJF58bX2XqJ89Nr52Gjo+Wz5+7u+mf9L2rJrOnj93X8L+W9UWipy5bldrDyOkpSNoP3V2aLRbrdUnvf+u+/UI+u6elYz+YTfcI+QO3rgc8e1j6mp9CO8tR'
    'mIdkZJ8/10R4fmuun964eR89HVvrF4vRZ1YouzGj3nB29cQv75/fma7L7o/W82LpJ4u/7729lZ3D9fo4rt/czMI9VyWQG8OTTqNWuWoM2xWwEH80r9pX5auL'
    'v01c8YGvT/sKlOBdPTBp07vRvbfLNxYouzcf7Z7bPjY/hRu3blgLpLl+TmbaDRcgLyd6CB1dwIKDdMLpz3Y2AdmYLwl8m4nz30bTxVIHKTOcjKaFm0TeEf9r'
    'Dl30bmjuge5TUKJvQ7fSUf0+eZz/Ppou/W1GXqvuz+Y5vQ0nM5fpgMnol3e/g4j+PRXRvwNL/e5/abv8PQdVvz+mh73+93/893/8/1BLAwQUAAAACACIuQdd'
    'ExAXZ4QFAABQEAAAMQAAAHBhdGNoZXMvMDAxXzAxXzAxX1RBU0tfMDFfSU5QVVRfUFJPRklMRS5naXQucGF0Y2ilV9tu20YQfba+YiG0gATJlA0EfTBgwIbj'
    'pEGbxIiS9CFIgRG5kjYhd5m9KFYein5Ev7Bf0rMXStQtkd0XW+TOnJ3bmRkWYjplp6czYRmNjM5HeSm4tKMXsnb2TqupKPmNklarsuQ6i6dZ6cixycPkO5J/'
    'Zf6YVarg7Pzs7JcnTzqnp6dsVPDFSLqy7AwGgwfDXl2x07PhGRucD8/Pz9jVVWcAzJdq4q966uSMK4lHXPnv3/+wt2Q+s7PzCyY8MqsjNBswpT0kWQHpqXKy'
    'CD8zDxYArxmONRXEcLAgVnvEyhWkWeE0ScsZMe3kkFVkmPJOKgYRqjU3HjknPFPAaqziEMhFISDpKmJOipzYgn9jEA236Yy9MAYPC2GBroACo3AlMctLYlIF'
    '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'
    '7Uy408Rk3lWU6Hz9MfjTl+fZxk+FKkaaWsaDg8L8T1mnGDLy50/LHTSe9VpOMDlwPsWK3aDonJS/TTabyF8kO5yucLyKs0szuzp85GCNxo0Iuf8kK6C9XPZL'
    'yOuf7EMqM3CbgMt/wLR38AxGZe49wlzENVbjOSSgpErBnRxKOqFvHBRN6NRacq3eVvv/BVBLAQIUAxQAAAAIAIi5B13p4kLYpz0AAJHbAAANAAAAAAAAAAAA'
    'AACAAQAAAABtYW5pZmVzdC5qc29uUEsBAhQDFAAAAAgAiLkHXRMQF2eEBQAAUBAAADEAAAAAAAAAAAAAAIAB0j0AAHBhdGNoZXMvMDAxXzAxXzAxX1RBU0tf'
    'MDFfSU5QVVRfUFJPRklMRS5naXQucGF0Y2hQSwECFAMUAAAACACIuQddjoPNu00MAABxMAAAOwAAAAAAAAAAAAAAgAGlQwAAcGF0Y2hlcy8wMDJfMDJfMDFf'
    'VEFTS18wMl9EVU5HRU9OX1BPUlRSQUlUX0NBTUVSQS5naXQucGF0Y2hQSwECFAMUAAAACACIuQddWF+yjuYbAACScgAANwAAAAAAAAAAAAAAgAFLUAAAcGF0'
    'Y2hlcy8wMDNfMDNfMDFfVEFTS18wM19QT1JUUkFJVF9DT01CQVRfSFVELmdpdC5wYXRjaFBLAQIUAxQAAAAIAIi5B11Vid4nVA0AALQ0AAA7AAAAAAAAAAAA'
    'AACAAYZsAABwYXRjaGVzLzAwNF8wNF8wMV9UQVNLXzA0X1NPRlRfQUlNX1RBUkdFVF9TQ09SSU5HLmdpdC5wYXRjaFBLAQIUAxQAAAAIAIi5B10C5pIZUQkA'
    'ACIfAAAyAAAAAAAAAAAAAACAATN6AABwYXRjaGVzLzAwNV8wNV8wMV9UQVNLXzA1X0hPTERfVE9fQVRUQUNLLmdpdC5wYXRjaFBLAQIUAxQAAAAIAIi5B11F'
    '7gZneQsAAM4oAAA8AAAAAAAAAAAAAACAAdSDAABwYXRjaGVzLzAwNl8wNl8wMV9UQVNLXzA2X1NFUlZFUl9DT01CQVRfVkFMSURBVElPTi5naXQucGF0Y2hQ'
    'SwECFAMUAAAACACIuQddwlDlPAcFAAA7DQAAOQAAAAAAAAAAAAAAgAGnjwAAcGF0Y2hlcy8wMDdfMDdfMDFfVEFTS18wN19UT0xFUkFOVF9NRUxFRV9ISVRC'
    'T1guZ2l0LnBhdGNoUEsBAhQDFAAAAAgAiLkHXf+GM2jUCQAAKSAAAD8AAAAAAAAAAAAAAIABBZUAAHBhdGNoZXMvMDA4XzA4XzAxX1RBU0tfMDhfU1RST05H'
    'X0hJVF9GRUVEQkFDS19IQVBUSUNTLmdpdC5wYXRjaFBLAQIUAxQAAAAIAIi5B10kE0uCShQAAJBIAAA/AAAAAAAAAAAAAACAATafAABwYXRjaGVzLzAwOV8w'
    'OV8wMV9UQVNLXzA5X09GRlNDUkVFTl9USFJFQVRfSU5ESUNBVE9SUy5naXQucGF0Y2hQSwECFAMUAAAACACIuQddeuenq4sOAADpNgAAPgAAAAAAAAAAAAAA'
    'gAHdswAAcGF0Y2hlcy8wMTBfMTBfMDFfVEFTS18xMF9QT1JUUkFJVF9FTkVNWV9SRUFEQUJJTElUWS5naXQucGF0Y2hQSwECFAMUAAAACACIuQdd4xByxv0S'
    'AADBRgAAQgAAAAAAAAAAAAAAgAHEwgAAcGF0Y2hlcy8wMTFfMTFfMDFfVEFTS18xMV9QT1JUUkFJVF9PQkpFQ1RJVkVfUkVXQVJEX0ZMT1cuZ2l0LnBhdGNo'
    'UEsBAhQDFAAAAAgAiLkHXcOl+o+sDQAAiTUAAD8AAAAAAAAAAAAAAIABIdYAAHBhdGNoZXMvMDEyXzEyXzAxX1RBU0tfMTJfTkVYVF9JU0xBTkRfQ0FNRVJB'
    'X0dVSURBTkNFLmdpdC5wYXRjaFBLAQIUAxQAAAAIAIi5B13IVGeKVQ0AAIUyAAA7AAAAAAAAAAAAAACAASrkAABwYXRjaGVzLzAxM18xM18wMV9UQVNLXzEz'
    'X0JPU1NfQ0FNRVJBX0lOVEVHUkFUSU9OLmdpdC5wYXRjaFBLAQIUAxQAAAAIAIi5B10sXB5A5gsAABYwAAA4AAAAAAAAAAAAAACAAdjxAABwYXRjaGVzLzAx'
    'NF8xNF8wMV9DQU1FUkFfU0FGRV9aT05FX1NFUlZJQ0VfTkVXLmdpdC5wYXRjaFBLAQIUAxQAAAAIAIi5B11itI/xOxEAABpHAAA1AAAAAAAAAAAAAACAART+'
    'AABwYXRjaGVzLzAxNV8xNV8wMV9QT1JUUkFJVF9ST1VURV9HRU5FUkFUSU9OLmdpdC5wYXRjaFBLAQIUAxQAAAAIAIi5B10XR1Kl7QAAAPQBAAA5AAAAAAAA'
    'AAAAAACAAaIPAQBwYXRjaGVzLzAxNl8xNl8wMV9DQU1FUkFfU0FGRV9aT05FX1JFVFVSTl9ST1VURS5naXQucGF0Y2hQSwECFAMUAAAACACIuQddeT/81y8R'
    'AAAvSAAAOgAAAAAAAAAAAAAAgAHmEAEAcGF0Y2hlcy8wMTdfMTZfMDJfUE9SVFJBSVRfU0FGRV9TUEFXTl9QT0xJQ1lfTkVXLmdpdC5wYXRjaFBLAQIUAxQA'
    'AAAIAIi5B11fO+bmKhoAANRjAABAAAAAAAAAAAAAAACAAW0iAQBwYXRjaGVzLzAxOF8xN18wMV9UQVNLXzE3X0RFVklDRV9TQ0FMSU5HX0FDQ0VTU0lCSUxJ'
    'VFkuZ2l0LnBhdGNoUEsBAhQDFAAAAAgAiLkHXeFIUTXGEwAAUlQAADsAAAAAAAAAAAAAAIAB9TwBAHBhdGNoZXMvMDE5XzE4XzAxX1RBU0tfMThfTU9CSUxF'
    'X0NPTUJBVF9URUxFTUVUUlkuZ2l0LnBhdGNoUEsBAhQDFAAAAAgAiLkHXWVQ9CMHHwAAqFIAAEYAAAAAAAAAAAAAAIABFFEBAHBhdGNoZXMvMDIwXzE5XzAx'
    'X1RBU0tfMTlfRU1VTEFUT1JfUkVBTF9ERVZJQ0VfVEVTVF9QUk9UT0NPTC5naXQucGF0Y2hQSwECFAMUAAAACACIuQddIjD7qvAOAAArOAAANQAAAAAAAAAA'
    'AAAAgAF/cAEAcGF0Y2hlcy8wMjFfMjBfMzVfNjBfTkVXX0dVSURFRF9JTlRST19GSUxFUy5naXQucGF0Y2hQSwUGAAAAABYAFgDUCAAAwn8BAAAA'
    )
    $PayloadText = $PayloadChunks -join ''
    [IO.File]::WriteAllBytes(
        $PayloadZip,
        [Convert]::FromBase64String($PayloadText)
    )

    $ActualPayloadSha = (
        Get-FileHash -Algorithm SHA256 -LiteralPath $PayloadZip
    ).Hash.ToLowerInvariant()

    if ($ActualPayloadSha -ne $PayloadSha256) {
        throw 'Falha de integridade no payload interno.'
    }

    Expand-Archive -LiteralPath $PayloadZip -DestinationPath $PayloadDir -Force
    $ManifestPath = Join-Path $PayloadDir 'manifest.json'
    $Manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json

    if ($null -eq $Manifest.payload_schema_version) {
        throw "Manifest sem payload_schema_version."
    }
    if ([int]$Manifest.payload_schema_version -ne 1) {
        throw "Schema do payload nao suportado: $($Manifest.payload_schema_version)."
    }
    if ($null -eq $Manifest.compatibility) {
        throw "Manifest sem bloco de compatibilidade."
    }
    if ([int]$Manifest.compatibility.installer_min_version -gt $InstallerVersion) {
        throw "Payload exige instalador mais novo que esta V$InstallerVersion."
    }

    Write-Host ("Payload schema: " + [int]$Manifest.payload_schema_version)
    Write-Host ("Manifest build:  " + [int]$Manifest.installer_version)

    $Operations = @($Manifest.operations)
    $TotalOperations = $Operations.Count
    if ($TotalOperations -le 0) {
        throw 'Manifest nao possui operacoes.'
    }

    # Verify payload patch checksums before touching Git.
    foreach ($Operation in $Operations) {
        if ([string]$Operation.kind -eq 'patch') {
            $PatchPath = Join-Path $PayloadDir (
                ([string]$Operation.file) -replace '/', [IO.Path]::DirectorySeparatorChar
            )
            if (-not (Test-Path -LiteralPath $PatchPath -PathType Leaf)) {
                throw "Patch ausente: $($Operation.file)"
            }
            $PatchSha = (
                Get-FileHash -Algorithm SHA256 -LiteralPath $PatchPath
            ).Hash.ToLowerInvariant()
            if ($PatchSha -ne [string]$Operation.sha256) {
                throw "Checksum invalido: $($Operation.file)"
            }
        }
    }

    Write-Host ("Repositorio: " + $RepoRoot)
    Write-Host ("Branch:      " + $CurrentBranch)
    Write-Host ("HEAD:        " + $StartHead)
    Write-Host ("Operacoes:   " + $TotalOperations)
    Write-Host ("  git patch: " + [int]$Manifest.git_patch_operations)
    Write-Host ("  replace:   " + [int]$Manifest.exact_replace_operations)
    Write-Host ''

    # --------------------------------------------------------------
    # PRE-FLIGHT: actual repository content, detached temp worktree.
    # --------------------------------------------------------------
    Write-Host '[1/4] Criando worktree temporario...' -ForegroundColor Cyan
    Invoke-Git -GitArguments @(
        'worktree', 'add', '--detach', $TempWorktree, $StartHead
    ) -WorkingDirectory $RepoRoot | Out-Null

    Write-Host '[2/4] Auditando/aplicando Tasks 01 -> 20 no PRE-FLIGHT...' -ForegroundColor Cyan
    $Index = 0
    foreach ($Operation in $Operations) {
        $Index++
        $PreflightOperationParams = @{
            Repository = $TempWorktree
            PayloadDirectory = $PayloadDir
            Operation = $Operation
            Index = $Index
            Total = $TotalOperations
        }
        Invoke-Operation @PreflightOperationParams
    }

    Test-DiffCheck -Repository $TempWorktree -StageName 'Preflight'

    foreach ($Relative in @($Manifest.sentinels)) {
        $ExpectedPath = Join-Path $TempWorktree (
            ([string]$Relative) -replace '/', [IO.Path]::DirectorySeparatorChar
        )
        if (-not (Test-Path -LiteralPath $ExpectedPath -PathType Leaf)) {
            throw "Preflight terminou, mas arquivo esperado nao existe: $Relative"
        }
    }

    $PreflightStatus = & git -C $TempWorktree status --porcelain --untracked-files=all 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'Falha ao consultar status do worktree de preflight.'
    }
    if (@($PreflightStatus).Count -eq 0) {
        throw 'Preflight nao produziu nenhuma alteracao; estado inesperado.'
    }

    Write-Host ''
    Write-Host '  PRE-FLIGHT COMPLETO: TODAS as Tasks 01-20 passaram.' -ForegroundColor Green
    Write-Host ''

    # --------------------------------------------------------------
    # Only now touch the real branch.
    # --------------------------------------------------------------
    Write-Host '[3/4] Criando branch de backup...' -ForegroundColor Cyan
    Invoke-Git -GitArguments @(
        'branch', $BackupBranch, $StartHead
    ) -WorkingDirectory $RepoRoot | Out-Null
    Write-Host ("  Backup: " + $BackupBranch) -ForegroundColor Green

    Write-Host '[4/4] Aplicando no branch real...' -ForegroundColor Cyan
    $RealInstallStarted = $true
    try {
        $Index = 0
        foreach ($Operation in $Operations) {
            $Index++
            $RealOperationParams = @{
                Repository = $RepoRoot
                PayloadDirectory = $PayloadDir
                Operation = $Operation
                Index = $Index
                Total = $TotalOperations
            }
            Invoke-Operation @RealOperationParams
        }

        Test-DiffCheck -Repository $RepoRoot -StageName 'Instalacao final'

        foreach ($Relative in @($Manifest.sentinels)) {
            $ExpectedPath = Join-Path $RepoRoot (
                ([string]$Relative) -replace '/', [IO.Path]::DirectorySeparatorChar
            )
            if (-not (Test-Path -LiteralPath $ExpectedPath -PathType Leaf)) {
                throw "Arquivo esperado ausente apos instalacao: $Relative"
            }
        }
    }
    catch {
        Write-Host ''
        Write-Host 'Falha na aplicacao real. Executando rollback completo...' -ForegroundColor Red
        $RollbackParams = @{
            Repository = $RepoRoot
            OriginalHead = $StartHead
            InstallerRelativePath = $InstallerRelativePath
        }
        Invoke-Rollback @RollbackParams
        $RealInstallStarted = $false
        throw "Rollback concluido; nenhuma Task ficou parcialmente instalada.`n$($_.Exception.Message)"
    }

    if ($Commit) {
        Write-Host ''
        Write-Host 'Criando commit unico...' -ForegroundColor Cyan
        Invoke-Git -GitArguments @('add', '-A') -WorkingDirectory $RepoRoot | Out-Null
        Invoke-Git -GitArguments @(
            'commit',
            '-m',
            'feat: install mobile dungeon tasks 01-20 and guided intro'
        ) -WorkingDirectory $RepoRoot | Out-Null
    }

    Write-Host ''
    Write-Host '==================================================================' -ForegroundColor Green
    Write-Host ' INSTALACAO V6 CONCLUIDA COM SUCESSO' -ForegroundColor Green
    Write-Host '==================================================================' -ForegroundColor Green
    Write-Host ("Backup: " + $BackupBranch)
    if ($Commit) {
        Write-Host 'Alteracoes commitadas automaticamente.'
    }
    else {
        Write-Host 'Alteracoes aplicadas e NAO commitadas.'
        Write-Host 'Revise agora com:'
        Write-Host '  git status'
        Write-Host '  git diff --check'
        Write-Host '  git diff'
    }
    Write-Host ''
}
catch {
    Write-Host ''
    Write-Host ('INSTALADOR INTERROMPIDO: ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host ''
    exit 1
}
finally {
    if ($null -ne $RepoRoot -and $null -ne $TempWorktree -and (Test-Path $TempWorktree)) {
        try {
            & git -C $RepoRoot worktree remove --force $TempWorktree 2>$null | Out-Null
        }
        catch {}
    }

    if ($null -ne $RepoRoot) {
        try {
            & git -C $RepoRoot worktree prune 2>$null | Out-Null
        }
        catch {}
    }

    if ($null -ne $TempBase -and (Test-Path $TempBase)) {
        Remove-Item -Recurse -Force $TempBase -ErrorAction SilentlyContinue
    }
}
