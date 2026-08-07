param(
    [switch]$Commit,
    [switch]$AllowOtherBranch
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$ExpectedBranch = 'agent/lobby-mvp-integration'
$InstallerVersion = 5
$PayloadSha256 = 'b7afe714907c4eb5fcf2c88294be1c755e01e95f9f0ffa6a0263f76a6381c5e0'
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
Write-Host ' Infinity Islands - Instalador Tasks 01 -> 20  [V5 AUDITADA]' -ForegroundColor Cyan
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
    $BackupBranch = "backup/mobile-dungeon-tasks01-20-v5-$Timestamp-$RandomSuffix"

    $TempBase = Join-Path ([IO.Path]::GetTempPath()) (
        "InfinityIslandsInstallerV5-" + [Guid]::NewGuid().ToString('N')
    )
    $PayloadDir = Join-Path $TempBase 'payload'
    $TempWorktree = Join-Path $TempBase 'preflight-worktree'
    $PayloadZip = Join-Path $TempBase 'payload.zip'
    New-Item -ItemType Directory -Path $PayloadDir -Force | Out-Null

    # Decode embedded payload.
    $PayloadChunks = @(
    'UEsDBBQAAAAIAO62B12o3ma0MD0AAMTaAAANAAAAbWFuaWZlc3QuanNvbt29aXMqSbIm/P3+ClnZfHhfu7e7Yo+MMZsPAgFCCzpiF2NjWGwpcUiWEUg60tj8'
    '9/HITCBBCC2lrupuszolITIjIzx9edzD3eP//MfR0W+j6WKpk8TfDx/9/WI0m/7234/Yf4Vv5vezn94u4fNv9Wk8mo6Wz0f1RaKnbvFbeoH/NYfvvRuaez21'
    'd+FCfeuny9+TmTHPf5s8zv82mi797b1ehnHTe5Z6MV7Alf8TPhwd4f9Kf5DsB81+sOwHz36I7IfMfkTZD5X9wCj/mY+D84FwPhLOh8L5WDgfDOej4Xw4nI9H'
    'EPz4X+k8Z3OfTXtoZw/TQASRPuS329FyONdLezdcXxLWQ3BOEm2Xw3s/T7T121ewdLK/xaNffkOA39pAD8x+x+JotJglGqh5dPcwHS+OprOjZDa99fdHzs/9'
    '1B3NpkexHvujZDT1R9OHiYHX9fff/mszDEFH/tdosRxNb/8WjxJ/ZO80DFAc6mGR3f83fLR4ni7v/HJkj9LV+M1YlbCGo3wNE3ifC/jwvx9G9/4oXV7yDHPx'
    'R5NwGzzryM7gJf9aru+/CBOEGcN3iyPglqNOu/q36Kh0dXmkYYz5vV/4+0dYqHnOBtx61nqY2miZTe3I39/P7hfpzYuH+xiudEdPo+XdEdz7oJOjxdLBJesb'
    'm34+W4yWs/vno/vZbAn0WwKbwlsAgngLpIVXGCi1hJk7f2R8PIOR2/ejyf/3/68HKWk7fpgfZZx9NJra5MEBKZejiQd5mcyP5skD0AWWN5vArGJ4ret7w/hu'
    'FMdHf/tb+sSj+4cpTD9ewhuA1cfJ6PZumVIGpArmn4tgyimbVTxM/xZIAK9scQS/HN/fPqQE+q8j/TgbBeoe/Zg9+fvWnU+SI/2wnMEbgdf53/Q90N3OkmS0'
    '2BrQw6NW61kcAVPPHmB6Lvw2So48iP/z0QS4E1htxbfwAhbh+aPp0dLDop9m9+Plvfd//+21oGyY+v+k/4fvxqOpC1ohfY35PHIdAH/G6z8k2vgkXIjwEP5r'
    'H7fOw89640enPfzRvKrWLyp/B6r+fWegwOXr8f3id5Td/5khFneacBEGYRFhMA8cc0cURZgohhjD2uKYWBxZEzutcWyjmGIWOU8jpUSEBJfMCy/0b+mQ//e/'
    'PkMCsocEZDN/MjzpNGqVq8bwx1Wz3Tyut4fl48tK8/hjxCDDLw+2IQuHJVothI1pBHRRHikfMxNpz6WUWBLnYiYI5g5jKhiKkI4lfOBUGyJ8/BWy0D1koZuV'
    '0MIKri5Lx+3haefkYyShwy8NtCEH9pQSWKSMnTcMESm1MREzROvYc+ssoz7iIpbCECOlMs5i7y31iiNmdPQVcrA95GCbVbBh66raHh7XL+EPzVqlPWyVr5r1'
    'Ru1jJGHDLw9W4BIKb18hZlFkkZUE3j6KnATRYMI4RCinBhMfOSM1j7WMhANJsopZYn3ExFfIwveQhW9WwoenVxcnw/bV8LjdPi6ff4wafPjZMTZEsJxoYim2'
    'wPmYOR4TB0zAXOStt0gQFGsnY+s4Jk4bGoG0eB7zWHgmI+7UV4gg9hBBbBYghq1Ks1tprvi7e3xRPzlu168aHyOHGH59tA1hiAHNSZnzgoIOZUbBJ05iJQyN'
    'YxErKpTyRAgigRQ88h44hMsIuUhzo539CmHkHsLIzVIkvNQLUH6N9vCyclGpDE/r7dJV/2NUkcMvDrUhSYS4pBJhDMpEChUZL2Gh1GMhkOOweKyR1ooRFVlr'
    'keLe0yA3cJ3SyOGvkCTaQ5Jos45o2Go3rxq1MP9htVI5KQHHD0+Pf7Tr5dbHCBMN/9CABfIQRSgFK2u8jQ3SHDOwQhHCikoJypfEwBnMKcO15tJ6KSMX8Vga'
    'zUCpRPwr5FF7yKM2q1HDq2q1VW5WKo1h+7RZAf6vN07q5eP2VfOD5FHDPzTghjxUAR8YzpG1SnKDLSgUaxC3XmkPn5TAEbEsNtxISrHjWkSUghUnNkYxRV8h'
    'z8rZKtIHo/Vy4Ne1Ma00Kpc3Q1jRyXGpflFv33yIPDDCHxlvQx3jFKUWSUuIdUQQAZLFkGVM4VhFMULIRsoIDrZaE4WxFlh5wHcECaGM+hLz4D1oFm+gKPy6'
    'Xs1V6axSbte7FVhR77h5MqxeXPU+RiE8/KNjFqgk4jjSVMfMWxJjL0RsRVDSMdgtAWAPU+mNtpY5az31zBkB2AbEKzYRKO4vUWkP4MUbjAq/Nip9EIPWxXHj'
    'JIenw1oHjEyj/DEPAIb4QwMWZEyA6rGOothTyb1yQkce8IpAxnAXAbzmSrLYOyYdRoBnIvADjMSxdMRx6r9Enz3IF28AK/xaumq1VuuoN9qVWvPj1hxu//Jg'
    'G7oIAVLDo0hxizzzxumAcrHXAogTORRhxSjwk0fIW+mdjLQ0gjCvUfrxS3TZA4Fxilrz2beOq5Xh4KpRSRFKvVyB9/5BmWLDr420oYiMAdoSKjA1ziirlBRU'
    'RMRrjCPtNDzCgt3iBgmNgA5SKywkuEzASIwY+g68yYMjH6YJWXH75XHzHLDaKahN+AHa8wJwG7zlfnvfcuBjGsFb3Nvf0/jM/e8nD9NbP5s2Q4Bg4n/PYn+X'
    '+n7s71twxcj6vycPejNEFkkZGsFS/VJTP296T7fXRC1MrfvT1ZJHkzQSOx3Mb0jn9kerNL3p4eRq7BJXXf99Vh83Hk3tV3JDm3NDeHvQPyO610jqo/F5efLr'
    '8YZUF/UKXDMZzAfPx6p+epbYfnduJ52ZJY1n3S+hi6R0ZyfdB1fm1zf9s8RMrx+u03uX4fO9od3ni3E+BlZtTZOK6/HpoKce+vjm12W5+KzkxdSqD4MKhjGX'
    'id1eg4yvZ+frtSJ11a2ela5xM+6Ou60OSn60RzDHk8v1Ne1OtdVC3VYfn/1ow3XtcbXRbME15bPTQA9b+3XnO/mzppejzTxwqVdJGt0OjjuoW22Ww7j1X40T'
    'i65OLgn8PN+8izTa9O/yKjbzry5hDncdUp0MunO4p7uZ0wm6hef8cr3kedC6e7mhZ3N7ev3QqVWfBz2O4Bl3ptd9vuk27gaTLrhoPOmQ7rObJD8Hre9+3dd/'
    '8uvORa/gi0rwGZTmgAUNdgw5D+6nlczwCGMGRi3CEagfKkgkiBY+Zk4KsGkAkEC/Y7zLSZuRneJE4ogb8NmUpgFJIWUMIG8FNpBiBI6MkTEFIIEYDK0t2Ecr'
    'wKGTxMfGfa+2ozvaLndJK3++vitfj8+AAZHrnz3Ua4M7c9pILsrHo85EYTNploHhsEWN2aDfQO1e9VkD87V7yYslycPguX5evk4SM7k+L/e6D4Pj2Was0+az'
    '63XOgYnH5dvZ/3hDxr/58fAz58NaUW46hc9nyU0f5Dbwe+WQbPHeTe/XfFCrIpDLuSW/7mA+DUOaiSk/gcyqRxfUbS+Z1Gscfi/9TOViUm3f9AYJLH826LEw'
    'v+dBv4nthN0OJtWFJXvmcjs7y8n0AfK9khkdxVwGfmXKIKmiyEcqIuAsRAygDXwH10WWGMXAycJKRE5aSimx0kaAidUBmZGAGQWLsQoBY+WppsFJQZEwVDmm'
    'GCYEHihcRIOvb51HIERMKgROr7DfjBDYjsyUOvWLk79CYJKfwCkPg14DadD29plXzbT5rHvdl/LteB7e4kqLBg1up8kJWAuwJEF7Ng7cmywMAc4olxJfSxBY'
    'PQxWB7T38c8boh7AamQWcHr50Ozfzd3p5Xm5f/Zo6LUArkXX/Sayk2Tk+s3kvHxWheuXvtt4uum7h3ys0QWMnf6903gEa4XOrw8I5seXeZMbOHjMgzs9u7uh'
    '118RuDIYwcWgfBuEZlfgUkEyRKEL0DHl3gBIpZ7T3/uNp0EPSNHaK4wn8AwgS/Un/A3pWvcB5n6WCu/JHIxws+ROw5rOsKsF4LAyaI3WoFcd+1Z9sVJKQCp4'
    '7trIPg5q3cUVGFlXqSJY8/xm2gVFcTtqprQoLW76SSMABaDLS2fSvRucjgP5J6BUXlLDXVAMZpIsLjZzDs9+MYTtUWrdQF9+kDUCy02SxD4V2DCwSyV75QFw'
    '1EkALnwFkF4uxl2m+83AgimN966rxxPTT9q2VqVmnI81Slk8/D1n8fEh4x6Dh+FxpDx34GyBEwYqKhLYxy5iLuw+CIewjQzyNI0ogpqSTBMtqRPKI/m2ogIv'
    'RiAXKZxGl2QcWyZiwATYYGHB6SfUwDixNaAawenTAB+kUgIR4hF2gnzJudsTyMdpEH4d3mhedcCk1yqNymfcXT78wjCFGKRHwmjQzhx8XdDPEmsHyjiiEvAP'
    '9kRorm1EtPfGUyCYp4B/wD5458CSROZLtNgTz8dir3varLQ7zUa2po/RQwy/OFTBkDliDHizQmrwbMP+hrKaIe0NNgq8YKSZ5xRrRVRgzRgDe0jOHBALh82g'
    '76QJ2bzYdCmtH8e9sLl5US/ffNz9l8OvjrWhitJOakZjwL0EfH7muNExKGUvpQFWYMLEICqRpCLWiFBgJANomDuNBaKE6C+a9zfosguJs7X8E4QBHgaTZPqu'
    'n7bxF8vhXo3D5+Wj69cfVmP0cePed5qAa10Cajfu/qw8nV/PV1b/pIgfexO4p7vlw4G5qGINvuj5aeMnqPinLd/0gI95XvD9Wv3G4gYw5QpLb8xv8IOXqny7'
    'mU8b8U5nXD3pVlWv2T1rtzrqKtChcby+pnHdPbuA7+LOWP2A666uO7iampixC6b+CcwlXz3LAl5/39X/NyD3+hnXhp4F9DF31RTxZNYzKT2aWvLTt94PPRy+'
    '/7vd/87X3f/b/3HIRYmJB38j9mCYwSyBo05Sh8KkGQlcgw6OEGAaEmFwJLgzWIO/H1EaESOpNORtyw8gIfKUS245xzA28UZL8EBiq5WKgpZ3NOLg+BtkwC6C'
    '6xIxSUHFwxcMO/a9Oozt1WF/oXP/b+YNv+Wr/IsvcyV1tqaeg/8EWDyT9GkjHRd8g6eCJkhduuBTWNB0QVN2CveF6zu0dOcIaA/ya35Dxw9dmIPuNe+Cj7Nn'
    'Da/Gtjil362r3SVhnuBmJu60+2xGK/9lz1yTz7y+VxoCeQEaAjnnqHJxSKGIfcQY5jYCb4FITeCTI9owJqyzCmskhNbcAIY3lKC3NYRGEiOhuEOUSQIKSGrp'
    'Yq1i42KmfGy5FDFgG800Vg5xzYwGdwEheD63Nv5eDcH3aoi/LpTxb+6D7oY0Pr/c09KjnTafb3oJysXqJTX6h0QgqJlq4b4UJORiW1Mgig1+Ea4Fst2QZAFL'
    '+0DII1cfHRg/Hbfx0VDIR8T7rSjSeyGM7TnvDanswYEY1t5r8vTVZepxnoVlVnFgPk/V7QdUzL9mpO31vgeyHHQavEnJI3DeAQiB56UlIQHXcB9ZR8ENk9Jq'
    '7ljMIqaAE51FsSdxJP2BGK5QCOAQ8Db4d95agiPQfDqWRBmrCFNWauSslVyBAnYc1CWznDFtlQmZJV9yffdkseFN6hn8elJJ96hbZYBGjdrwuFyutFr1z2Td'
    'RMM/NmIhY0IbYRwB2oO7L8Cv9WB2OALyEBd5LRGiBrAlQZ4YHkVEuFgJSi0Fp5kY9aXcWLwnqQ1vctDg18srmHtllbLYrlxULivt5geJo4ZfHqwQHuAWwcIB'
    'Tcfg8Ecy9jxCXgoN9lYqRMBMEko1sKq0xKCQdBJhYBnqAGlHzn2JLnuy2fAm+Qx+rVx2LkKqWWYt87ferrTSdPn2Vfnq4kMkImj4HeMWuIhGccy0wzGzMTgw'
    'Pnbwn1ARiimIrjAxYRoxHVLQlYgFjhiOwt6Wlop6+UVHhOzJbiMorya4uCqVbobgeRyDWJxWLo/fAxVpAdQKWlyEDz8S/ezvT/RSfyJm0qxUO9fdRqeNz6p9'
    'xEvtTnBCj0cdsuTNU7CvpPsITmwIkSd2HGBpNXXO65vYQ/sa3VXBCd1xUCsva4e32oBnnHXS2AN2PzrjZtzqpDp8dA02ydLG/AY3KNi+cWHcyzaqVsCprYID'
    'fNbsXobrUWHMEjwv7oy7nc44qXaesz3xd2IW/8Dlor92ua/NFODt2IeoocHguIso1Js40A+A0kEbBrCOmfSSRiwinCDmwcqkO42KOh7ZA2YKeysFwG7hQaWG'
    'HGJNYyKxxyqiTinEuKEcEbB9EgsPRlZwpr3h4CfEyPjvFZ+0BKUgPieV6nHnov0Plp+wF96tKQT4CvBOApglvJDjRcBG5U54yc3079f99MU/ZZgPpd9ftNBt'
    'u5aMzXMJMOCvx3oFXvLkjAN+vbOTyu2g1n25gRdv+91E9yL43Lk1i6ulm3Tn9pndtp9Ll4acjXyrdPXEGj/qNfd80x/cAdx/ARyXbvHZWpRun3VOzx4H9CwJ'
    'TAe4Ig0wAd6dATZL0jmfLuFfmFeitgNDr7b+/8hyOzSBqXWXFwDvzOn4FuDeyJDq86AWUgNgSZPqY9i986MSQLMz8CBKgTw/b/rNO5DdKfw+hr9NsmmnXvup'
    '6yXjQa95FqCiQQA1+6UFQNpkECDlKj0hzKOFlkDi+aAWAUztLsyGfOFZQLZmYsnZwtAqHvSSx/C5XpMn9/1BovuXD/VKBK9LjW6m49v24uoEyD8FiE5uWiUg'
    'a7gW5LdferwI8LxbAjfAgevSeAlQNnhP/rl0rWvVl0H/MovvtUoqzCs+DDODUHJJGHLKgr8N//NYEMU0Q7HiglNOkYxiCzIsmNPgdBNwtWOnqFUe2wPpNSCV'
    'CLvIGY2NETFVGCMpPXFSaiqdUQywgo0k8Zpzb3BkZCwMxfBcwKU4/l75TeuliubvuFFv1weVf7gAJ5fATcFRnJtxNfVzTa+KdJkvb/q3s0twavLPE+DARzu6'
    'QyHBxfRAmEZ3z+C8BG4DTuVb45y3wJkcHT+dt8a5UCXjwMUXyWvOsKT6AA7T3E+613aigKu6IVkGnNI7EGj7sCO88+Bvr2NVtSq6uZ6nCTVv+9D/gkvcCkM8'
    'heA53L8t7Fke4J175geUQOk/QdgedO+pGB9I9d7lSSUI4t45w+dcN/JMaNvHvwo+6GLQc3c3NOmFZ4ASyNY4qdKLpAk+tAKftboAvxL0768EFN4YvlerkBq8'
    'D6BbCWjfnF1M8J0v3z6B75l/zmID56dN8GW7y5tJF35P11gO+VQd0ni0k868Ds8AxTs/bx3/J/xcjZmtZdx41D3+Uj9ht5dpvAGuLd89rdZRD5sO5dL6c5oT'
    'mdErDeuk96XhxgB8Kg9N2gWl2R230hCROjEEw/vookHvOt10Ce/v4DVtdOtOz/Dgej2XB/DLD7zX0h2w8y3cP73pNXh3AuOAgjYhF/Rd1t+TwqBBexHiFSca'
    'Y++Qp1HAKEhSbE3kALQgJwUx1lIeKcGYAQ9AS8FlSLt6W4Fya0AtR4QRDVqYYMs4dgygDvWWMsOJ8kwxrhW4W5R5yxinHjSrBEdVv1uF91kFmqZbFRTocbvd'
    'rJc64A/9o1VoPwfKP/fEkrZBNBjcKrznNNaC7LSbpuikG1O97vO+8GEn/64Z3nW3mQQDC3L2nKX5pLGyF9dr/Axy+95YmfFOgDcDcAn3Z/wNcjo308t5Jt/V'
    'McjOtEOSqQlxLrxM42DAfy7Vm5NkcQgf/fuQIl92fV/47IC63Yz1IZUQQpKHaDZ2WPdg3EoSItiPndX+cka3XN1tX7Oldk/ZSu1+8fW+UicU48jGXHLnQPqZ'
    'NMQiSkL8hGvwqZDHPJR2URlSOo0O6SiRNxLzGEUENMIBf4oIS2UskSMIdAcC30oicMS0UgKHsWnI4zBSG+4pYiEhOkY+1hGgQWyR+151kpYnF9RJo1I5aYXa'
    'nebVP1ifDKbdh2yLgeWAO7nOX1IlvPDC1t8pMExmnwuA+/w0Z6hRiEff3VnSPRuk9my1HZIyaLBdmQPQ3RLMdVLARahRKN+tBCGzubmPti2M6437B5jv3aBw'
    'zwFd8YllXg163TG84S0+3yzzr1rajiluraHWbUhX+YgeiH+uoEFmxsuTATaTLPz/3nyaoJc62evdQMrn9fzWMK/Vu54XoFuqM4Ksv89a17OVDs2g7ns0hfn2'
    'Cve8s31AKVMIs5jFCH6zlEiNqBeOhsYOnDEb8rW9s8QwcM80MhH4awA2Yqkkig/kV1jw47T2JNKxRUJg6a0x2nHhLI8dY1EsCHWAWTwzXnrw5ih2oWCCC6OV'
    '/+awpgj1tSF8HdLehq32cftzLl3bJ34+u1+WZ7N7N5rq5ez+IwHNbi04LemG3kkA1CHCAG84OCxZ0tRk7QwA54EUTlzZd36FTa4kuwasZg3DP+C63tli0LoD'
    'j/0pePFxn4Rc4ixiqJ/rt3FrUziUK5yqC9lAm6SrFxjnOXcEVhto7wUp/7oldB/SgMxa4WyEMPPlusj0uigIzM3kV3IOcwFjLOtVFZueGg+ypKP7+qikColV'
    '0xw0BAMfwAuy6FvGzfyYTpeE/cQNTRooDSBlPkq2/1lIqGri7lmz0q30URISq370cal+3W1U4XMlz4XbUraFAO1pt5NUmp0QzA25dipOk7MqXRhHXbcq1Xaz'
    'q87SGqry2dp3PHR/u1O96aNqB8ZodKrNNsyl2knUZRuBu9RV1XbSbPVaWWnfoXQM5xHGWsWERIBRhPIuDj0KbIwNlhFoAe9lREmkuECWeAFOCsccAIvRJnYH'
    '/BzDGY2i0KYothGBkZV18BHwio/ABYoxkrFSkimFEGgYqz1AJNA/EfNceY2+V6HIUI6+ViihwrpyMrystE+vTv6RiqVort+WTN6+IXfJ4LQbpG0RChIOmKKM'
    'c1tp5kH6/SoNcmWeM85OxgdqPtZBksL0BrnFLUwztW5biGGTHyRDdBac7OcsIJMW/6URW7CGWZBmnKR6q3UKXsCmaFOABX4IjjnotZSpz1d1F600ESJNMNgr'
    'TKP0++vV8sI1hwQyjd5mSRQJ/Dt8H2r8AIEJQhN3KnelDuqGXZdsPUEHnyZt3Z+n87rM5nmZvaazLiig51amMFYo4qEbgkCw/nQO3dId0JKv/pYFzhe3K4t/'
    'kXRfYBwAm1lktwxoJVdArYCIDEEhUYGel8eiPekyF+hR607hOTOYy+3lzwpqvFyzy5cb1BjlQbVJltzyafbrHEKLhUSTbJ23htYL61hls6aIboWQXg7mypXP'
    'zgGA3w0CkgzGo5a82Jp60P1BYspsBGvJi/7g2adrj+/0PY9vy5sbjQueY7E26HUxYo42xy4k4TyX/jeg05Bc8tOcBtmoPNTXCSnJfDAKGzA89QxXaPV6gwzN'
    'ii79zz8z7AzcBUMMBvoR1g10C7Stjm9aOzTJ3kfO26tCZ35mMYxfAxVQcd1Wp1ltVtVZMAhtrNJk7yYYkaKsnL8zx7Teq9bFYRfkZhLUDyDiVmmeevKkicF4'
    'PsJcwvyzudeac0tLMJ8EDOzTLt0CjX4W5rsuqA6G/SZ1vI6jsBP0Du/suS/MKVu7eS7QaqM+79ZAIshh+e4gwOjRnOcSlPL6ZXl8e/6cBnU/fB/IwuaZT7Mz'
    '3bu5vQmB8R5+cqeXtz9GXzXuhXd2IGqz40m1YM5zGxKfKqC7JyB34PDWE5hfrZsmkHXg/dtpcql7eO7K9flbPJHvuj3qoPdo4yWTWaA/eEK6VwV5rtzqbd5+'
    'CMHowN9ZYlvz7mJU3yTifdxDSmloJgqBCdx/T9K4cyHTfqWbVtGyd/j8jTUFHTDR/bPlTarzLoPnOg4/QT+jsDM3eLXWLd77eFQMnyWgA5+zZDY+De/mixGv'
    'cahoAN2/5s8wVoHv3ovWdQa9X0mamBf0Mm4+rjMcRgGarKJjmw0Xt4MbUp/lQ5hi7YisaFFee8vJdqRt9xkXofoh3fzhZ1kyJ+jE6hkuNI8QrX6jDZgF9HQ0'
    '23r/BxyWHfnNNoKu/wC9irWlX3uPQB+7m5T5Jb7q0Cbo8eSxQ5Kl6/26y2xkgc8Kujb7W9APDeRAb5iX2e22PonAAcvGAdtQ0PMbvjC0lCdmhpz85CHYBzMB'
    'eZvwxD3fjgq88cOe5ptJKd5QT6vkzA65e4RnjIEeASuRvIInd1jzDbLN9Sk9XvPcRselUaFWIQJ22gAbFnjpMuQ9p3qx3Qs4tjrNCqZCAvGvxXmKzwq6chP5'
    '2bz/SvXF9/jPizevzXDs+zYwvU6ucc8ox4ebde4mAK8j+QW7+UGMErIe+Nwcv8OfBTsRxuzW1Hrer5J8v2KT0oyOb5GXqp2eAbZNddUj8NxzmO/5q3c7ftO+'
    'NUMtBej1m14UdDvokuQO3sEW5rkaHY/qZfbwzjPe6pkRMMzZNoYCX7LXmK9sYyZL8wnQOEtUHpUKfAa8Q8/Cu70Lm8egC3+CbgP78ys5r60COm8Es3PXMqsp'
    'Sb8/SW1cz6YR0vMt1/PgzgbmcWQlNtzFPubCIOs8Ca1WLNaR4sxrahALvcoQxkLz0OQu8k4xh0PiiXk7gIBw7GKuseAysk4SeNXwf2tjh0JmGI7CgyKLhA6p'
    'zhwhQhg1RsvQEMPRbw4gRKFZ2zqAUD2uX3SaaWXy/uza7wogAPenb6IZkMg08wrBgj+C1oafbh64zudx53qefgCaZrFKh0/R3TgLc2VI7ywxPYVWoa9U076r'
    '0ZKQhlG7CV0betfiepU6X74rcGYhhl6N9mjR1LJMAoruPxfChc8gUSFvq5c8hzj8SluBlso97LDP0Hw8vH3670SiLzmWnwFR2Xbl+GzLqR6tS15TZ3kFhOxz'
    '4RnfBYCuv9E4XP9x5weU50u4BwDWDGj0DO+4EYzoTc+BwxDeyQ6tPhCAKG45n4NxBZ5MHZCMjuOzdKvr885nNhf49+OrEeGcZuuKoDAegCNLFg+h0clNfzxr'
    'lLcCg7MVnVe8uQpyrUq00yyllSMWQEk+x3Ivyxha8UzzcykB88I2/HrMrXmnaaV/MKiVj5MZ2s3vqzWv/54b8AI43nSkgu8HgZeCTK93VSyABgZqrjoHmsw2'
    'zsYZb9e6AJbT7cGxeTq43cediAQhLjZWWooISnOuKdg/ggzY3JgpzsEUYu5VbKmXWHnmEaLeWeXkgY5PGIUmzulOnyc+MoxHNDSEMLElobrBg+XmxHkwvxQr'
    'oTXmioadQUQVExh/r3FVQ/h/6eqq3Wo3j3+AVb3u1JtfSOIszWbLxfJez/+e/TVY1of3Nv3yLd1qWp5fwyE48Ymufdl2czNtIVBahr8Vu/btPCPweZI2KXrd'
    '4fBgG4J37geQNk/L9fNAHYN7A1g+AbCZzjN3Kjoe7ATIXZ7CfDDT4N+KPOvuCW/6C59f01umpfrdr+V1djeNYwC5TgotNOLeagC+IJWRIhHmBvAxfKmQJUhY'
    'qxGOolh7IRniQnKLDlRnhNJr5zBcJQyRlmBOIx4RbkEvcMENll4TFYd+MaBwREhkdEpIHOPYE4zpt6oFjIYEF9RCq33cbP+DlYJdcWd/1Rks3RJPt4U3nBvy'
    '6lKvqR1AT24oQ3QmTytqJHvamD50KBja6fU8T6V9WXHcqky2PF1d212V4QbOz7IAim1Pk7MQDUkCaAgAJuf+1jrluvuJZ76tAP4lSPFmACBN9Xs7CLbB8O10'
    'zPI4Sz86ffXc8w/TIXSyrIGDX+uEZ+dpP5tX9ZlnHkolVM5bryPshGYeUy4Yoc5Kx30sAQgwbI1UVvlIKyzBcQ6Nr5DFkaCeR9EBhztmjCNCmVcKEIA1gBBA'
    'm1CnbSREpJjklIP/Hho3eB66jBmCtJXUUE+ks99bmoXxkJCC8Fe6xxedz6YBfV7+C07OwzW5u8usyTv5sLSxDGnwNyitT9rKzQ075uBMkkFnk6N20/vVAbC6'
    'KOSdbT0r3JcCz2wX90Djxn+eqQIm/4BBfAAfHXy3btagZL2h8242PsNEYkEkQpGPvddGaiWwsl5x6oywkebceCoVFsZauIRqQiKjI4DIRrgDPB+OOAn3KQyM'
    'LbmRmIIEYEDVyCvHeRxapRHhLdEKCRciV/A3oWAe1IJUfC/PkyFFwx+fKOTN+byUzOz4h74fzx7uf3+VNjtsjZ/z/iHDLkYfSYTroEa92cGlPh6AD9k4a6NQ'
    '/Xf86/KpWMqqWs2ugp/VS/i51TmseF23Um2BT9rq40a/jc8qm2ypBvhhoXKm0XbBdyu/2zXsrWkVGpX9Q6b19QSwg+6djxmOg1ulcSR5DH4YMLcAVtTeGQMo'
    'C/kIG0OsiogGtwxbQq0WSioV4N8BHCc1pVHkw1lXTLrYAeqLOGGRAEiHsRA2RG1jAesz4EeGY+QUQkIR63QkY/S92ZyYDinO2fqDBbbfzdegKzsuxAUmyZ2p'
    'gu3uuWIyz+a7yoFS0E416EMOWOanBf15M1GgB9OY225106p50oHium+YzoGcl02+aBrqu+5xuC8Bld54aRerZ9+ufD3Et0wxoS2oRglK04VwO1HYSYsRCrF5'
    'E2kWW6N5ZK1SkfRxqARVhgCQcOHwwgP+B6aIhkMNwb8xQgLQQAxuRuDwEE6J0N4rKxCjMlKSci/AM9FGacEia7CS38u3bEjJSh1/sLD02xk33d3LcuK7p11k'
    'wBsF5tpiuHVQrPfqugA0sx3Mk856FyrLu+elUMviAxigjR9mcvYIgDaLve9wUlqiOP4g82/K9oqdpII3/WTz8dxp8gSedVYCmEUGngAs5No2y9aqTxshUBgC'
    'vjlITssZsyjEaSkZVPMeCCFzbH/PhLebyH07SYtLZUC6sFmIdjfKP1L1GEobsvj8OmEJ7nGbjOAd8u1WwKax2PJZnrmdds1PqyIP3POQ+28vWZz6eATrGxnw'
    'YYLiKJB+pwKXr8rS8/s7T5erSs18I3mdAPCqIjMomoP036lMDXNttm8Ce3y8chWlQZUwd7yu3N1Dn3yNNQzzuX0wvSo7PzlerD4PJr8eDa3PXE09uB4ehaTL'
    'IA7rNbf4et5ZksN4Fauf/5NXxOa0+7BNS+f3UUOy2e8oVmSvRD0db/N+9oj1ihdXm+r1UbaWTBVt1EmHOjCU1ynNO7hZ6iTNsOfR7gYQWFVnzcOGLPLUObBh'
    'zEXgMFCvkbGcc0oB/VOtggsBfjATSEtiEHU0UhECb4Ma8EU4EQfalToBRpIrJAl4FlozEpwR8JtJJMGXdsKQSMSxF6H6z/lwYKAmEffgijgwqeJ7DRkfUpob'
    'svLFVaPyzwK/ckv06rs8d+atovjX91X2s98nYdvnRGKdU/xpmPfnLPsdeJiNdbARyl9HxtdRL8+MVQAjLXg0mAfpQZGJqQJBjFAEfpS0QgrOmPAG5AuQpsYk'
    'nNyqJXY6PrQTRpHAcA2WEfhaILOKG4pABj18EsgoBA4S9RJh8I9AZpHykUI4CtcDqP1eSRVDynJJvbg6Pknr8f90af0nqkdfZ/puMvRW4OxfvZz+gK3/WJn6'
    'pjvIPE+sT/GApd2fIZa8yd14p2W3ZlLzcJBEhC24/9hLzETkKGIOIU2tBxnwkUacSRpOT1SYCGdiCVOL9YGGvJY7rSnYUIa4dA68Ra8V40ioOIb/vOEWBBWE'
    'mDGGndfChDCeA4FFYIm/OYELyyHluWRldV+tP1uuitU4h+qTPwaytmqqX9UpHxq/mADxgTLzQ0Md4OGthP01BkytzrF6M3F/p8R8T7l4igM/Y71SFzEPbOwr'
    'jHprfZ0vrM+uit/ySto8Of2lkMuzlbC77nb0dqHL2m0PqnAzPq98oo1FoQNwY+33NT9Aw0L3oWXoENysJc/udDzbzKOQ3Pp1XbfRvXtPRdtKgD3U1eFDIY13'
    'WiB8rLT/cJk+B5UWIyYtjpQK/YAiSzGPOcIIKE8RYuGMQuM5Z4JoJbnGzEikQ0d0zxU/kBTLAPsQ8C00BcBChAwl/kJZpyJQpZ4LrCThkVaG2sj4yDFtmImZ'
    'MzxyoHq/V6dGQypWOvWqcdW+atTLw9Zx969wMNZyAz5j6HYluv1UHSbX/QY3k8uZJl3enIQuWev3H3IJ13td52mh3WBuaPcly//a1NwCX4J+UtiiNZ+83PT4'
    'HHhSDFp3m++fs5yyNB/sNPNlW71wSJqiZgIyCWo8dGrU/bOX4vNyWfzhCF/7wCGWMKhFH2ly/s+wZEv4nT1tzACCvBfqeAExfbKhpqP8MRWep5+GkM/uvD4e'
    'Msmzj20aMmiG+opbQ91DuG4rVe/0LAGRf3T9Rq5is1eXhRqaLx9I2yNeaAAwIuywOIIUYRxkXBJGvLeCgcBbHdx8HgefgmDLKeAuJ703gsNvB8440M5bEk4z'
    'C8d5RWGzUltLtJY8skgjbQR4Mk7ClAmOUGiu6hi2UiDAdCz6ZvFXQypz8W9WWp2L9rBxNfxxetyqhF7KNfhb66+Jl4cTBvIKun2GtX8XksJDkubaeK0N+Do4'
    'evl+mz+8BM4dhIpHVPx7q9d0W4C8MObGEG/GzPt87gQSsx6p9crZIxjsCjwnudndpSmX0vZ+3VqyHKwqeMollSakZgrljaBtw4DETHQmzZu/d5JxP6t2Ws9t'
    'U228qhwB6Qh4tLIKuoZQwtZYVVNLpjoNsK7A2tb3rUHfhVBA3kcsaweZ02uHnoFm3YUrZ8HALhjiEBoBZ2vVKygZTNLE+wzQhBNdSBKC168C+HmPstvzlzS7'
    'jwZgkP8trZLa9ALaDege34cd5rRKaPMeH64n6gU0EDy/e+fW+xqr4Gy6wbA7t6Adg3JPj4MYpJW/Yd2rROnjWebnbmifB747uodzEPuBMVPNvV5LgT/S4oJi'
    'wcD+5+x9n0FbgwYk3VAJOw5VzOu9pKyqe71ZMeg10oBs6FV7qGbja2J6nrXj3dlkr+E73wqiFw7mWbFMaRbGBjvKQUxGrn99C0qchKYFN5MuTJdPg38cuihn'
    '/TQKZEtFhRWLA+91v7QjSukextbr6KwLrVLD9So/v9BYoliItaUG8lDHnudt+T1fEOu0FVXe0XTjf2iSPO12ec5EK2v0sGGlQuHstoqU9cpuJ1B0G7rD7hOR'
    'dfF+ZZvlwp5X/RSF9/9llZtuVW7m9lq1b4t9qt63xhp3F7rn5qGLUJ6X+Eodbam+rJvq+T5xD4WqrvcL5ftNPfBtU16sj/aqxKLKXNM5f9e5mgxqKIC1gup8'
    'mq3qUjY8tJajHXW19n/SwtFUDV5moGhLXYSi9ybMbdCrrsDaBoB9Vq3le4/nr3ipqJZSvnz1Hm764Bv3mu2gTgyArvrJlmkG9Qv0rcIcelmxabm/WfcfVm2r'
    'uo6dA88LfPQz3XoOZvswEIwAciHtFEE8lphEEfiFBsCbpVLECGEhkQt9lbxGzos4pOvAPxIRRDl3hr0NBD2gRu99HGkcC+SZFKF7JHFGKi8Bc8JImDMviEHK'
    'CuuxoESTSFiM+ftnmXwSCMJ/NNoGgs1K+ap58he4geWb3q+0vrywyZGLUJpb8xplbVncbVWWbXxss9AbbJjl2YCYmV4CrK3ugR2D+ABb4SWIS8eQZWJGh/aK'
    '/tDUV/2Z3wYyGdB6Z0l5ssUhEJKe2bSaT2FpwSIC+ULbkGrzEVzPh3fSiAxChOPQm54pLRHjQjD4oByKDLExeDkyiiLtw76MBxcJx1hhcHRiE8tQbHxg95Vy'
    'qRVHIrLS6cjGmhBuqVZUeHCKWEQjFoIwWmiMNJFhk4ihmFsZTkLy35tGRPCQoWGz02jXLyubEuIfx81W5Wunv21//MSBLcWwZ6G5eqGMNUXLxb4pYdt/tb1Q'
    '2LIfp6kq9WnWdA/MWgovgrezW0/e6jeysxbLefrJph69gNI/3rej0INsPAglvzX1ZEBFp2nGGYTZCs2uS/c29wUYFGrvd9d9e9PvvoS6nGCWXKu06RlWA6iZ'
    'na34WOhltEK9OOsB1ny5yH8PoeMgWGASn3w37+91ejnLmr3v9gMbn3+iTds3v7Y1WUN0uQPPWUc82/Mzi/O2H8+38y1ksW6X0ExcQNN0Xdq16s9fiOBvqih3'
    'z30rtpNo5tF9B2QJZVz7WokAon+rl/+qbVx6cO32NZssqJz8q9YGWaLZ65Td9fNusrItYK3CPa3SfLep7iZTqtAGIptXEAOUlXqt2D7Vw6NNBlFGoxCaKlYi'
    '7841fF8f1bd2+g6I2s/Xz/1XF7dCq6G16OS/hx2HcmZ/7GnSXYlj/g5CmSAqiOF75XUyICUmI2KZ5D7089dKGaeR9szpUEsjfABXFkdE0dAd15nIIQSmylPt'
    'D6RlR86icAwLcVTF0jGDQtmtMiKiSqjYm5gLQqT0gNyo9CISUdoPnElilbTf26ybkCHDr+1S6+ri6k8yS5n30gBd1sn0El2/o31H0q74KH+f2X0ga4HXX4K3'
    'n/FS/TVi32lJuZUNWfjuYNZZsdVULsP1A0kI/+ClBXX9Wh1m0z0vPPcyc7DWFqr3UnXZxuC68cOqg+V8XxAmOz71ePSq69NpONY0eQGV/RKCKq6H7/INz9Dp'
    '7cWQX/ss5XrDs/U6CbBd+G6VqLlSh6Mc3r56ZSkkLdffO5dcS6kUxgD+wO+ykoXzNEwoXmOaeqkiFDkDAoY4lTYcOMaQdzKKwwmQRFB2ICJvLaPYW06YsRJx'
    'ILQRiChrIkCoHsRaW/D5mCYUJsWJJOHMcwPIE3w1rb85Ik/okJG1SLfCwZhXjWG1Xrn4cLbDH5bpgy1iK3tbxBblM2+ZWrS3O7Axa59VFJSwpRTas14cKJY7'
    'NK1a8rLL36k5P8k6nOZVGe0d3i3ycrqs9qrd9FvjvYYmmVnPzfy+Drdvyfjr7ripnO8j1R4IkrtqO51xM9fw9dz3QZ5iZ9sOCTuCacJDeB3vnYXBIoWZ4FZx'
    'J5EJh/thETazOcVKgbw5LrB1IJJxDAYWxMQIIZCIPfLCmOhA9Ujq51FEHVJMUgLjcUssiKWxmHAiEJbIxTRmJiT7glgzHo7xlIRzj813yyIbMrqWxfLV5Y/j'
    '9l/o7t2kEcAqSqOM3Q12A/w9cemR98lUn15vZdxk3/Ftxm+j1bVbiniNgWu/ksH0ejcaDvbUzULLhhWzvb5+q81ywPXzAblDK3cpZbLDR5b9Ky77ep+LUXjW'
    'nu/X7kw+z7Nd2dwi3/iVPO/ev61Ki+ssvJLXtciv5FpZkDBqQsSGeMwkkoZGRGOtcWzASmrElQXYy5CWVhgsVMisB5zt4c+GHpDriFGOZeywiMGqslhw5wWW'
    'WHtHY+sZoxFcQI1FxlHnAYZLaq22IqYCC/bN4Rw+ZGwt1z8ujm8qzTRN98+zsIcaIjaxmbgEVH6RfUOO1ctmL6WIZN9rLLseb2OWRsU8t83f3813XfUDG2f7'
    'B+CpFllvZ45F0/JmgORfnxR7+tNvj/lGAGGLVMVjAj5xAlfaJ4cMQury6SYtsLUnyLLaBnpnXSE49GaqX5hrh1RJmvKXoYe3U0Arb6c1bqXvtT78zs6y7aXq'
    'YsvQ7Ly/Aju+FyQwgPe5cIZE0oJDz72LqBCxjiWHKzwXkiIAHEYRHpLxQvtK5Q0JDSo1oJMDBQkotjEFB0Fqb40Dz8IjGMzpSCPkNAcIg7n0MQpAJvgvmEbS'
    'mYiHo4FCdvb3ajsxZHyt7fLNnYvjUuXiz9J2O4B4n7gVfYb2pJonw+zsVKZHCwDrdvjdarum83pH+DPnayZpRWJ5N6FlUwF4cbB5x9eWdVBSc98gCbgDJ7oP'
    'WKA6eFz5GTubnxXwLVJtkY399Ppc5Of3nrdTItR9nRv0mSNj89yRh53XUji29GCJUGjfQdK9Th/H1EYYgIUXFqTOR54KKTXjXiAQLomU1jQW8C1mPHZUAl44'
    'UMggYuwU9ypSRCFGjTYGRYKEvxJKkFLEWwvuiZE8aAKLOYkB+VjCwaFB8fcWMhA5ZGKDPyrNVr3V/tgRe9/tXqTi1Zit8fDt7PzV31L/uphxCmLTb6SJ45/Z'
    '9ail7vrL24YhPOp2uw5mPYUdg/kaEm+OlNt3QMC6wfhurXd1YarhoIHt9K9N1DEYO9AKNByKkqbzwb2DMJf4onCISkg+1f1VTvAakKwPUDkPtcRpC9zxpqa6'
    'V33WJHvud9QvFHKd1utZPyMLvb2VF98OeVfF0xMLjeS/chxoWHs6Znos6GY+hVqncV4LkYKJTTj1OnlJ7wP140Jf0vIiRJyyPI5Q+5Gl2m29s3WNxXaux/lW'
    'ncT7gCY95MPUfmXzBlUYWhlo2ni6AUBzGAAe4Ockn2c4uKH3a5E/K/B4yA+/t7R0F3Zu9tB23ZT9/bmv+HNDa5gDNtPve851PwXdj/aZo2CWAj8X3e3C2lb1'
    'HqtwcWquLLlbA/hQC7L7t/Q9FvrVgtwCUAZV806NBkI+HLJsDbIUadDYlCtCDMbGMC8VEWA4GPaOE8oMCcaFYkfBXoTToNEBcxEqOmKsXay0cQxHUmFNiVNK'
    'odC1x2PJPeJxHEuhYhoxp2ISXOTI+8jGjH+vuYiGTO4CuJNKtR76mVw1/myTsQVB3jzDbK9zk8KA00WQ1R3osg1TdsKf69y7DcrLsmDiD5yP9tnp7vPn0mnv'
    'm14GFH1IOeuk5yUFFXp1s0rKeRMRgnoP9R7rk5izTPH03K93Sj11xLiJOfMxB1chclEce8aA93lsJROR9J4rE64Ih507L4SxSFkmQ5+dQ4f9aUA8XjAqlAnx'
    'GPCGKLWOaG2VY8aHyK7wCFjexxo7ETtwVwh32EhmjaL6e1leDVm0y/LNSu+4eTIcVP40mAS89zq/MLys2iq/Mds2WKe1d95Mqd/l4T0ve9e7+PKjC3z3OrKY'
    'QoHjp33Z6LtjvRax10X9FnvLtI8NcSgU2JOIuBjz0Guau4h4bajHSgOLssgjCj4Y+NOOOHB4hcHRgVaWaak+8JgxFpS35jgyVIWC5pgK6nzEWGBEDJ66tgiF'
    '8hmQAgOsrqzFNP5WfqRoyNSaH0tXrdawfNVoVxrtrFjmT9bB2YEg6a7Z7sFxWY3jGwGtTSl+vl11+HC2vP8r2OX+4E73fmUZR+st4Xf7Tn9imp+NkW1chPwZ'
    'e3bkVy3c1rtz3XDOyqQ6N+v2SMl7bSsdjlE48oRGPI4ipGLOqQatCsqXxUy50Ffd2hgj5SWOwPx7xrFgBL6MEEEH+JsiBLqTIGs4uKI8VjGWIa/YwuMkwdLB'
    'aBIZxcBJVTEAGuSYiCUSiiEZf/NOF8VDvklwLFVq9ca/G4OHeMQDAF6zBu7JGYDkkPnbdfVKJTB+eirioJcwQzu34Zjk9LS7foi7FE61PJnd1kfHDxejEij0'
    'VY+z/YDnAwe4/jVCEqJdbFZPlptDqwB/u5DP30W316H/YSAfGAjdvwuZXeNBfqhlyPVPsRsB2zbpLvYeoLQfLL3bFF2RcDSBt87FkbWWOYDaXAC4INhSAmhH'
    'AsKOjYtBaiJkhBVBEqUwMdURxQeaElrmFYsEYHmqWUwNZlgIrwTXniErIm2EFJhzFWsQLsZ1xAlWoTGylDH93qbolAz5Jmurd9U8b/04Llf+5B2oUAq7BKau'
    'hjzRb9p6+fCYH9p++bAHvrXTtL0VUtwqOCCM/1bk+P4dqS8GEaJt+uwJ2m1aR32KXm8HnnZPWPzEO/j8RubrqnEDcFcaqjmNDaY29pGkksZOh9AEuFFWU1Be'
    'EpwpKiSHz9RyZiVWQgb0emBHSXAhpAF9B7oRkHPodwW+moxYhF16NHtkDfhhoCTj4A4aS4iNHaDziFCHvlmB0SHf5KhV683W2jkLSTIXlXblT3PQxhubX2uA'
    'rW/cg50OJ/x1bdoQJDRRKRaWvWP4yF1yQ5ZPwSt35dLYPJeeQ3BtkPHUDHCBqJfrtxcjtpXqfVO8Lz+YanXw1OYAonXR5tyiUCwXgrXZ3N50Av9VlpeetbS8'
    'aJV2t7N+ruPV/ctbELOFb5XuBuGQl7RyoRO2IJ5tyITPt4zqleTFZPHquX0O5cjVhTnNnnXRSgsy0gKtsHaAYNXwHN9KAz2h32cakLnpnd2Fg7fNBKfnoa3q'
    'htd7EOXNvFIRz2LPAS99UF2tsooVqA9Y66SZ+PLxf4Yy8633sadP0G6/n7XT3d2cO7V9ttebcex1TKGzPorveOe8re+I/+4cYvxN4wKPtDLeCxY7nLHBwzXj'
    'Qf92vjrH6+N7Rquzxaov+pmHWtSwHVnoObS5Jk/r3lcrvR0EXDcxKZ6fl679Vfz6fKs++BNnkm2dRVaUpQ12B6xdCweEmvKHesHh4IViKTmWmgAoDkZAxhYR'
    'RTSQXtMYhyMXEAJrgRGWobe31twpjDQOYbw3TZCijnAW+nozx7wFYwOOLhLUhnEZ0jrmloZoYwg3RkQLZ+OYSiFliB4K+70miA35JjWzVmlUmsftq+Zf4rR+'
    '+AjiygbAwJsOx1wBx9RDF7aH0NU3AJI0lLydO70PlGW5D9v5lm+lwSwONnH4k6b+qaj6/vTw/XjsYD4BNkZ6rnBg0cikB+VhIqlTDpFQsGPAn1SxYxZpE4Xt'
    'Ik2JDyWkkTIaiUPRG64RQg7YGnPJSQTeaMSsY4yBxwoeo5fag3whRWEYBtOIwbFlBmQzolqZdw7a2eHZd0SBDwUaNiq9Ya1TP6mcZIkEAMsuKnu9yXiU+PVD'
    '/OJ3RPDwC8MUCtkjHAsajhakcfjBvdYstHeNAA8DLCVAIxVOFohDORZhzmrAsSocOgZk4avNMvj//wqj/7bwIHlTnyxg8P/5H9nDQFptMoIvfq9P5w/LH/ez'
    'sIzybLq8nyWJv/979m3xYKDiTblMl/XE3+vP3vVjdr+816NleTYxennaOfnYbZczA1NszeLl8WjysVtaMK/p7eloWfXeGW3HH7vtKo4X9t77afvu3utlfepG'
    'NpxKvPjc+ipTP3lueu00THy0fP7c3U3/pO9dNZk9fey+hv+1rC8SPXXZW6k9jJyegqb90N2l2WKxfi/p/W/dt1/JZ/e0dOwHs+keJX/g1vWCZw9LX/NTGGc5'
    'CnRIRvb5c0OE57fm+umNm/fx07G1frEYfeYNZTdm3BvOrp745f3zO+S67P5oPS+WfrL4fe/trewcrtfHcf3mZhbuuSqB3hiedBq1ylVj2K6Ah/ijedW+Kl9d'
    '/H3iig98fdpX4ATv6kFIm96N7r1dvvGCsnvz1e657WP0Kdy4dUNQSP/xf//j/wFQSwMEFAAAAAgA7rYHXRMQF2eEBQAAUBAAADEAAABwYXRjaGVzLzAwMV8w'
    'MV8wMV9UQVNLXzAxX0lOUFVUX1BST0ZJTEUuZ2l0LnBhdGNopVfbbttGEH22vmIhtIAEyZQNBH0wYMCG46RBm8SIkvQhSIERuZI2IXeZvShWHop+RL+wX9Kz'
    'F0rULZHdF1vkzpyd25kZFmI6ZaenM2EZjYzOR3kpuLSjF7J29k6rqSj5jZJWq7LkOounWenIscnD5DuSf2X+mFWq4Oz87OyXJ086p6enbFTwxUi6suwMBoMH'
    'w15dsdOz4RkbnA/Pz8/Y1VVnAMyXauKveurkjCuJR1z579//sLdkPrOz8wsmPDKrIzQbMKU9JFkB6alysgg/Mw8WAK8ZjjUVxHCwIFZ7xMoVpFnhNEnLGTHt'
    '5JBVZJjyTioGEao1Nx45JzxTwGqs4hDIRSEg6SpiToqc2IJ/YxANt+mMvTAGDwthga6AAqNwJTHLS2JSBbyKC2ArlqtqQjDkiyOJR8U+qRkVSuNA8hwIrvI/'
    'fRT5yPK8xCE87AxKlVPJ7kpacm3YJZtRxS+eczvmeiFy3uumo26/kX1nuA7JSSL7lLZlvHajXwdAaCXk7Hf/Oj5syjx3AmLx98UfJOwzpW/moiwaqyDQRn5/'
    '+2b84vUr6HRTnNtF9P68uxadOpmHhCNHU641L4LoKzjSA+JJlDIuz7kxw7WUtwcnZa8BCNInmlun5U5osrsNdEhyWXgFMW2wGfLVgv/rkklRMjvn0uNGMzR9'
    'xb1WGauFnPVW0v21iIThkIkSWUU2n/egNmTd3oc/f84+Dvo/dfuodI/ltWBAVEGs3iqXz7urOxtn0nv/ipeGtzWe40dNxR6d5mSf1m98OVGki2tZvFTO8D3q'
    'jUg8DyCyiGHzuTtBxT9D9CeUf/bljHAvQpXXpMHOauKJzMFBCfptxp6RALFhDChlLP9EEa0QplZSLHjJesoxXjEqZ06aQGLjWcwrV0YGKza2rhCqn8UM7mQ7'
    'BOxW0qREJhvfdqIZPdqnn4J3CKEV24hxKGopWrEyfDdZJgr46t1b71G0Cp0zUSf0zcst9cu1H4moGg0K175u9dDLNX2zca45l63TfRR0k1KY+Y2DWbJha4uF'
    'eTw4aPxJ6hBjbq8tCDBxFi0ouZFQ242gO2wg18qw9ZH6KQnpzVbwVz5SXZfL2xjLOBRWzeN71geNrbvbGfmRfpyFPpVQ3Envcdp3SmMeCfuGf3GeOsVjoDYa'
    'MZo+nAdMatihhf8oEceH4iDEsdH4AcADA3IQ7YiYoEvsknJzOKxmFIhxYDqdfIePULmVrto9yBo3UxcOSMdXyzUKXoTQJANb+kfGdz+EnyjKrsbnaoR8JS17'
    '3Q/718aPfmzMyW9XRpUix06FoZHuuWBdlmXr+YpA9vut2YMx5p8wLV5Bf6o0VrUSY9vkVPv5wNI+NZrFBp2xwHGMJixrabkMA4RPhRR+EQxgtV/jEBBLgKxo'
    'xO9r7oVzQXGe3d0Mw5DDyub3RT+pjMAGirk0FxON3dFkj03KlODV/0nJCiAEaX/TU3JzBt/MCZhFKEoEYKwqP66xrMJx5AvrtfMDK/4X3/yKynaoi/M27SMU'
    'ACrCootkiMpZWnCBzSos5tjz7wVW7GaHl9Rg+uAdnD3Jo8N9+6BmazRG35PbzfumcvdydVsJUttrgl+0cR1ctsskNRYzSSW24o1wd6Mb+Hto3WwuSSTafn8B'
    'Avmvh96BRK7D5L9sBM0kKCRyxVIAwlJmmgyAqwQUCltVDqpoGv367ukofbogG8cOkDeciiVq0GrnS/ABbXZLszMwuRa1zZ6ij2u1BPtXPm+kxXPfk7SMFYtv'
    'MA0XvSP4EMEnkObAIbb6KsnYa7wzVmlU673AkAjRWBcreKzRN3BgRpqXigq/X0Zr0N/SpskMCrrg4j589xnkD20EZYyll7JD4yFkeGXIHYXdqWmTjxgPe1a8'
    '1kho6N/v/AdQSwMEFAAAAAgA7rYHXY6DzbtNDAAAcTAAADsAAABwYXRjaGVzLzAwMl8wMl8wMV9UQVNLXzAyX0RVTkdFT05fUE9SVFJBSVRfQ0FNRVJBLmdp'
    'dC5wYXRjaL0a7XLbNvK3/BQY/ZJiiZZSJ5d6zp24/mg9k9gey/Hd5E8HJiEZCUmwIOnY7TRzD3FPeE9yi0+CIGhJTe9mPLYBYj+xu9hdIKHLJZpOV7RCeK/k'
    '8V6cUpJXeyd1viIsP8YZ4fiY5RVnaUp4pD5HaY1rdLclwE5OvqAlTQnKWELQfDZ7vb+/M51O0V5CHvbyOk13dnd3t8f79i2aziYztDuf7L9+g96+3dkFpO/Z'
    'naClEcAQaP7nX/9GN7j8jGYvD1DBeMUxSB5L5KjgrGLVU0EiAS9xnJCC5ACXYA02R6PzvKirK86EJGGGxhIBWjCEy7LOCMKGxK81zhNmeFIcSsYOD1HFa0UZ'
    'XR3vxSwvGXAPfyua1zhDdSlBLaoCJxwzBFPX7C5ljwC6s5uyGKfoKsVPhJfoEK1g7cFPpFoQ/kBjMhrqT8OxWXtd5/pjaHnzVUAYmEIigfUaW/ROTKtBs+r2'
    '9HpxfnkBy4Za3iutcLWZt/OhZeL04uT0+pfFzemVWH6eL2lOq6fzMgWZyyD0sCF0cnp29OHdzQJAf9/ZHfxM6Oq+gsHLVxMY/ojjzye0rHAuRZzvi8kzStLk'
    'cnlLwSIP0d9mYu49eyAZbOE7xj4f3ROcwJdXkcRxxvgXzJMfKRZKVRhYXJcNqeilmFxkjFX3i4IQAfy9mLLY2t/eyOU5LhzWXklal3Gc1iUFeXGS0HwleI4E'
    'yT8aiXFc0QcBssRpScxsXHMO/Cv9mMkSP5BETS0qXDWL7zEHNGLD1AQH9q4wr8z4vs5wzmhixne4JFoPQPiWxBXj30Xg0qPZBMHPdG5tqpSikiSkUQP4G+HM'
    'rgc9XJDH6owDn0h5guVTOf49BhsAb8sBHHTTkaL5JHbod0dXyzqX8yihZaxWHQegRsD9YMk4+mWCYjuNKPwUmPJyFCI1BvcDsEEDcHBiqUiMED3gd4XvUgIR'
    'gmAexrOzKxd2eL5nnP4GIQCnH8AhRg9SeROx7ekd2LWgoHfLLvQ2R4FE/5R7pAcfBRxdOkDRe7wCAjVEor8folk0g0AHO5gL4Tipap5bmgh01LP7WloN4GAX'
    'zPeJmNfZHeELUkGcW41wVXF6V1fkAvZ9ghKyxHVa3eK0hlEGUSGrM/gHP4p/GvEfxAJhOUyhG6kQJWLZkcHYxj3WOtCQhyinqRXZoHPJ++JluLqHLcVZMXro'
    'ZS8sMsnLmpObOgeJLXvKArV/20kd0watE0O5sw0+Jv5FambSs94LhBbKne+DPWMPLogTPvsgXJ+3cJ2A0E/PDbgN3Wa6H9KNyw6kne6DbAdoC+lMC0gZWWSg'
    'yKWFKlOBMKGiRLNzJjaAjYWMUUCPfbsb6JULf6WmIyxEW6H8HTavGBdgocQJ+iMVRceN9UqjUituIOMBgdWSqJmbNEsW9d0ncHl/lZ6WC9snql7m28mxifAG'
    'jRwreLFBDqQYan2HpeSkhBikpdQCTlApxNWunTOb2ontsqMIjjkwQjMpQbxoZxQMfwugmo4MWemkg46ugHGJxpnqrGuU6C7Vs87qtibVWmfOxWvUqRHKoYtJ'
    '61TjECMl2LhfqXBGlUapWo+tvAJBRtZJKhzttTbFBZx0oMaOlts0pFfAbIeO+RDyk2HAp49kojScqESpV2wc/1pTz5a6RtQ9EEviiNDR1NdDH3I7ZW6vTR0b'
    'OtqMdUo4CGn02XBh9ydg8adw1joz0SLmtJCpTgPQNub2WS/4GYYPm6EK0n3nzSuZsA++n8FvWZcMwink9nYi4JwwqdCEjeaO5onNJEeQCtmBQLA+2xRKMp+E'
    'bhwEggGdjluTN/l44xwbZ9k92nEM3PLRGwYdfuzqgzNQwRkceyAjTZPR8GfN47VeLIpGl/E+yMvlcQqlcoNAVZuDTnRagkvcWzUJEiptCrInvWtLZoPcPouo'
    'j3ehW8uVdel2FeWl92a5juSR2NFbnfI7gOPeVGEYTPss4DCApsdx3CzDFjA0LwmvghXMpNFPJNVylCQkOdArmuMzFt/GJhaKQXQhCUPZ39kQcULLNQfn5ZGr'
    '4EafFS4/R5CmgwcGraOdMY3Hf1Kaa5KBl20kjxDF7rsRQExay/o25nudIByl6iKBiO4YwRln2eUD4ZwmxCk5mJ4CE/jC+OeywDFpZ6zD/jzd4BvqQ1M00dhy'
    'ZHDKPHeoY9LQyr+mcjXQuna1w49G3cHy9Qeveu31OF2UDpxYtz61ZqY5s8BLcsVKKo1gKTIrMxJFawnJRGImxuvjrA/ieJ5iIIGvioNDfy2aohZ9Rc0CdCr7'
    '+ba0C+A5E2nkNX6KcSkMG8Zyi4Ro6jMc0SnI5WYGennzITp9BO0lxAc6IWUMJHFelee5qkNl3euo648G5nyVQ070D6xOTXuS6SYWKaFeb9mwZqOzSUZBEy2g'
    's00ay9Z6Mv26zdIcv9Hn5Tz+Z/l1pvqRg32b+GjmFMuRNYpdM3PBeAbMvTDs9Vm2lk67tTgMRglJK3xDM7eeciObOzY1laczlakYPa2NRVaXItqeODZvY6c4'
    'ic1AthOaVU5fSqc9foAR670g0yKkI0177qPPVyvXchoqm+26hfS2O9waUXnuXOe5JhiorXom32sFR4HZD5Cv7EYFkHmgIk6C/fSK3nGE1La8/V5KqBneBTtK'
    'i3tRtcwhtMkuG3ksRlMP6wv1KcOPogPZmOp4TWbc++3gHeHFKKSSiTqsXO6s+2kTM/2mzWxA9aE8A3CaU/PX8s93b1rbftfu321Gym3ueQQ7fT95JzF4ud+i'
    'umx14jYt4CyMX8h5DbygfS9bLbxNSVqYDsl250+RfO3tYOt0QIduSRE5EX+w6/e+HWYheIzVGjfneOGqUH3utUH3xPdOecmSf9APph4p10aC7N47nIoq1afy'
    'ZzMcn2/ApIsY6TiV61gWT0ckOeNxPNdqdYkUtIrvT8iKE5kpyEiQkNVI/oNB+pcjI6irERkcQnVTn1VdOXSUWUkKS5CJj1pMvEDzGRy6cD6P0R6az/zzWYs+'
    '8XO1vjZcnkBBovo+oWNYXwDCkRfqLQ8798tQMn1VyVJ/he/et7kZVHTcvld8tiu2XT+sr+9G0pII8E7T6etzXSeLdjpFl3XFGSph40kG9IAJVqOKZZjbG/QI'
    'UIn7+IohAvaBRDUm/gPFwiL4gycaGRMPFsQv+aAgwfZNQUEguYKCEHYCJSxn4psWMVd5Fxy44lJd7FLU1zl+to/maHOb/MveOkS2UJT67xQgg3Ybywdyu4o9'
    'FhM27aZQWZdSmoihJWpj6bWu/3N/sbmoDl2huRf5jScp43fWj1p9+8ip4LQO7NS4SdiUotptGtFW8LD/cNjmzijOvyrQlGQv2Gv92Ia2+jNwL/NNKtfVcFDF'
    'Tn6nVD3ou0+DhEP9mYtsR2YB5hI0mAa67DyXA3YEb41VsmctV5Jy293g9OryBH+qwad1HCmFO6vYvFdWnOBM1HsYuMjBVUgG/3KyoupVzie2wgnjClnMMoYK'
    'JmINzcS7IwGBMgLSmIc9wQAQOZauL3O08YjTseUqyk437QoaqOEEhY1yvAUyydrQCwDPXLaI2FoRc730vzjL7AMZ3c585sZ9ffxrn1I95+J26r+GZO/JuW7Y'
    'FO6W8FLtmn5dNd5qz1MaC6pD85TqNCViJ5IFyegZfSTJ7Xw47u8Q+DvnZCLrd8JEl+4V4/ZXJbKr8FfekPz1V4q6TXukVGZujnseAwSN/NAz8pb2TYz2NsVt'
    'Xfqm3NOR9y+unr/WavzVsNVzgWA4GTestGRWL7qSBV3lOA0qwLLaUaXEGX4Y5revrziDJK168si1XNch1brm39DCt8mbN81/XeU1bzAPfoS9uWHX8gRaVES2'
    'K5y3k+IgVa1XueKKU8Zp9aRzy0g+Y4IiZT6RbtiUGDu77i6t9YDm0es7hhNxwps49i1hTL58PbLPbAvxKpbmNKYiZc/FUyjI4BNSMCqOYTiPkXx1qs5KOCfX'
    'uJb7aldF346HBV1WO5ppLwOg+wpx4M3A/m9s6wGOwnY4+HbR1G2kx6v95kvhP2LsrrAh1hYHYe2511c2sdIPCQ9QKeomrMQJPYr+hBF5hNSL8gnKIasqOIlp'
    'iTNWKkx4VWOegH1AZghHG62wiPICqVRDtGXA/dp+jPWcxtYqrFdftpYKacsN36Uy7BMwdc6eIG8JG0f3VO4JjO2CwP/ckaA3vDot/YETmj7k4uAQDX0nPDmx'
    'aawD2n8BUEsDBBQAAAAIAO62B11YX7KO5hsAAJJyAAA3AAAAcGF0Y2hlcy8wMDNfMDNfMDFfVEFTS18wM19QT1JUUkFJVF9DT01CQVRfSFVELmdpdC5wYXRj'
    'aM09224jx3LP2q8YEDBAWhSXN932nD0wddld4Wgthdxd28cwjBbZoiY7nKFnhtqVF3twgDzkA5KXBHk5CZK3POUT/Cf+klRV32d6hpRk5MQwtDPd1dXV1dV1'
    '6a5pzsLr62BnZx7mAXuapdOn0yjkcf70ZBXPeRJfJmmesjA/ThZXLH/19qQj6jvRiq2Cq/u2eBLzD8F1GPFgkcx40Ot294bDJzs7O8HTGb99Gq+i6Mn29vYD'
    'EH/1VbDTbXeD7V671x0Ogq++erINaF8nV9ibRAGv0Ouvf/nn4A3L3gfdwbNgKbEGU0IbAN4gu+FR1MH2hOOEL3kM7WYso3ZZ0O0FPOj2CSQ4zXIWTNmCzRiU'
    'ZskCaAJgHrBlyjN4YVOWPCPQnSBmCfQUTznhi5PfWeUsynnKAhYuPKXTJIlmyYfYUzWHP9CFD1UQJfNwCg+rPEnDnOXhLQtmSRYkV3/P4SXJzDD/bsXiWaJY'
    'JRhH/Hr+PMjTFW8H2eoqy8N8FcLQeAzcAPwc3qGn2zBbsQhQIwMJHTQULOXI42C1EGzFwiWb5kmwZNBOsR/IeLIdJVPAcZwA/z7mo2keJvGEp7fhFGgI5mzB'
    'n73kuSxpNnxwjZbC8nIV1rQ1tabFZcTueJr5wGWVgR2v6igztdhCtVkSEoCX2DrnWCxeXBigDsDE87NvgDsvkvT4JoxmihIAsDG/Ox1Pzi6+hjaNqrXyrtfQ'
    'tJ9+fXI6/nHy5vQSW5zF12Ec5ndnWQTzn5Va6naj4zfQyY+jN29Gx3/ElpP3d7K7UQ5C/r5hzeHF+cV4AkCfnmxvvYxYhmw9TqIkHXSu02QxfnnU7A3aQX+/'
    'HQz7rbaCGrMw47MybB9ghwftYG+XYN/AvPuADgHjEFD2dwXO16vch6033GsHvX38c3hIgMd3LPbAdRFXfxcR7mq4SXLt6bx30MPOewb2JSxYH5F97BZwgprS'
    'cH6cgEn23xsOBGzKuZfQLgAOcEB7YuSvOKiAmwqUvS7S0BeQk5wtwpiVQQ/72DlxqkuQY+/MCIQI1jsgsJNwUQY76CIUgvb3EOqzkRVQBuEtrqNrFmVclc5X'
    'oXpMkyRXz3myvGQxj9Q76jFq/ybMI14qPeE5C8vAl2kyB92clSpehJGGviEWvmPRirtFNlAmuOdAybIC2Jx/DcoU18Gnz3rooGNh6U0iM0BZ9DXoFN0Y9eYE'
    'nnTJbcg/oOYEFRhz0n+GndlqiXZHLKOM5wtgQc6uIt789LkdfAp+/JFML6zf943gc6vYzKDMHtQeGo4KE6pArlcxIQaDlb+TI2gCgi1RDSYUbdbz4EOSvs/A'
    'RvDO8SpNwYAeUw0AphyMTawgQV3Jx45CNwl/5gFYm3cwhCTtd8DdaA4OQfYOhkPoCcy4n5yzGEaaWcSAnJ1zWpMK1c88TXT1VZLnINjh/KYSJFtNp8CPNrg7'
    'aZaD8eRg93FOllAbNVXv1KcamDFLaE/gjegiECAd/wmvFeIgv+ExtjWk5ndLnlw3qcMWmu2GpKxBvKJymzuS3i13NBKLoNeDRg6kjIe4q4YiqWrbrKqagDRZ'
    'xbPmLa6hlsGwYPlN5zpKklRUBdtBt7NbOYtsNjtO0pinzTCG5QYuVjtI2SxcZZaIEQCM8UyCkIA03p6JlmhTtwRMR5SMCQE0eAtajYC7NlYJe8lQSgFK9WyJ'
    'KkHU0DzJ0+Q9t2ieouJsg8fFYlgEgHh6B2834fR9DLNuxpJRQ89YBEYai4DpkC4GSEJtit9YXeC8268A37UgVfcIpp8BpmdgapggIKqYELErHjWpYxCXGBY0'
    'jBcMfBucwyxEEFg8sK7bQbIkvYQjk4/QnXoCalCxbtkavcQddBzOsT9ijwDqoK4FyJhUriq8lH3jgpWPppLUzHOiyhQegQs0J1EuMLZnYKTjgsNzC4W5NMOR'
    'cwb/C1eKgEyTFwmxWgHTK8CexqsFvXReJvkNW7zmIKkLtydJu2qqi3A2C5R+O4rCebzgTl9WoerRhe3guncRfedD9J0fkSnuHGMklbqovknZckm2zR6BLhWh'
    'itvkTQqihnGI20YX272rws4oPyV1JvH86QwiwI8WBlkAbaXoqpLtoGfJll4VAsisCVFftSauWFpYEcW1QGvZaIMrLXwlmX+RAgKSdwNUkHmrwi/3FoAr+1aF'
    'kX8tzEVfETx4dL33uq2qpoWl0+30ugXQJJ3xFIm4DD/yCGFcgOMoXGYnPJsCZ1mck8oSImEB6ekszV2BG6XpM2bGgLWDXYrG5Fxcg+NXMwtYrfjfQCexoQol'
    'a9HW9Ilp5PQ1Iabo6YYeLiu1Luq9/KEqPegyI8TACUoP2UA5w0YgPWApzDYrrsnt9Yv1VPhzY7L3RVM/jdhi2UR/xLL8eQIr8wq6xfIt7RmiewRBZxpeQYTX'
    'VFHvsYWexkX8hv9gla5peqEiAG9jZM5Wi1QkhThbPfo7gD+tNWMVYfVZLMacauxm6fKPyyichmQX1Gg3pVZhJ3Klf6jxKQfRZvKCfUR5sjiswFst5cJpyuZR'
    'csUiJTW6vWHAQydK0/9S9GCPYtMZk5NdYEXFpImJEvwxc4Dmoudlk5BFa/ywBNvBgFgEMU0JS38zLMFOMCBMw1bRX65ssE8Nqv1e3E+LeM5n91hVzlRubSp1'
    'r8CH5xnuDFkdgtiRs9h2UcnNK//M3fDp+2USxohqEeZFVDRvYp1116+zlME/IkJAuf4YLlYLZIJ8tAUX+KgJVJBaPspMMzItQhMirhU8Vb20g67QzH7CIHJD'
    '7S4Vpo5uQHbIQCiBqdP8FjFygNSjtAfUbYVQpBycmAnuOkA4EC6lM+FED+GyxkhRvbZSuKGJuLKGrrL8BEP1xfU1xqu9fjs4NFicwWE/MA87/SENpn9g4God'
    'aAFSa7clYUWTrccMIpmsck/EdB5mEBVgJY1dwHVw8k7CVGyGQCvhXNuFnVdJGv4M7jaLTDNTZju91NhTZXxc2fwdT/Nw6mlcqig1vQQjHcbzQrS627IhJG+I'
    'VcSaaxDqUGg4jErgOQiXLEyz5ieY916jDX/79HeAf48uJhPc9glmtHMgGBuLDaEqWdrCeiVLMvQRZVIyQqVGh6REcJPBCEu3g27jzpDUYFeod6DZAegWAAi5'
    'zx8VsZS11eyBLrmg3QMD5fWuRJ2WTUdUhWgKiCL7tyy3CgHawYGwUsUQ3+wT0PAJlp4M52hrRo4PN2pN5Ih71gK629nriydhG+2+chUZQ3ciIi90RbFzQ6p5'
    'DM/pqaixujgF/ipyY0XVJ2GkrXC0MJBDUsvSqGzJaLcY3R4l0UxCqB0OOWTa95dV35ZWUiFcFctIQH+2+GL2bL8n6n6QxxlATyqjJ82ciZopMWWiULFTs5aK'
    'P2+iuV+thCUHYzHH4zZgCfyrBMj1NUpuG/8I+kwoAn2e9OwFjOEFbgDKg6Sqg6KG9iIlEtWZKngGsRUM8q5p+4tzOrFyFcBkiocV8qgKIbQ5qexbwo05WJGL'
    'eLJkH2KzjUxVZ/M4SbnaGS1UnoQZDvgC1yhU7R7IcrEUj/gNuw1JTEgM3FLQRVcRDE82OY1xy3tW6MDYFsVXEQUlSV6j/7DamFJ4aajCNQEfwdRaRYLQVM0l'
    'PeqQpIYmBaLpkpPAGfCuYQOM4ulNkl6iu2ZtdQvFuysVrgYueQUGjv4/cKD9joGA7O0OHdg12twPWlblu7sOpFed62qt0ftOsea3OJiylLgCwXO4lqiRetvU'
    'KKpReQFFQxxrp2fvH0wTmDRYGLHPV0FijzWA3LFWr53XYSyZak9Ufx87GRwUgdlHD/AuTkBvrwisB21O4EyciDvi3EvuS1kldIB80RvS9O+E/7TiqgkpWKf4'
    'j/yOYgXlzxSPPg/BxQF/c+9Qhgw1jTu7B21Hata16JW6GwzxgBe63BXdfXbGNU4wxYLE/8Au9zOv5KSrWiEM7tGmY5a1NOFL48IBFCa6cTk+vRyNR1+fXASn'
    '316enpz98o+//MOFqCw77AN9DL9VWI17wk0XR9XScFt2uzcUtm6tiS5Y6Dfag7iPff6s4/jCCe8m3BGQkj2j+YrB2g8SnQnTqeHN3l4Nb3qHFbw59I5cpRA8'
    'ZvQyWUSeYh8xDAKst7Z7oE17eWkda9R5eBULQOgPDrwsOCAWSA5YIyxPlOpjk6lSsMblbHQh7u7V0CcTOfz09fYrpujgYdJr+ZePmcDbEELBrMZKCwBto9/R'
    'a8NU1AbhuNPUO7TQ+M3tnhWHS8Bal0PCaNtYtJbbNlSF1dDzL8DEDIuUlZfR3fJGzvmv//KfFTNuwozyuHHDbFClrroPm3BB2+Nn/Me2zCGBVVpYmmVWVEk7'
    'ZjkVhR0cib5xng6c9SiwCUq2TAoL9O3QQmRaSS/OQi1TRzByonrd7hc11PbWkFs5XQd/G+PiH7ZMlHIE9F//2iiNDL0RMa5KET2oGfPhw8YsqftNRFQmMNXL'
    'qOzQP345sb55P6gSU4lQyqmVREVhtU0RUWtnXlWK6sQCqpDVEtG9NVT/f5PWnZ0AE8hUCi7mHKe3bCYTbFcLFtxQUtkMQjuoZZjZjI1eYGJwMl1FeRLgMThm'
    '6EKIz6HB9SpfpYBgBSHxlKUqJ1gkdo1MhhpisnLYaiyZBaXN2ciUNQog64JOygNyWpRCabnW9jA26Beh159VD6EbdPb39qvb+g+rHVhvgGlDvAuz8CqysuWc'
    'Wm1lB8V21UGoBQVD6LlxqFNZCEUp0bSzW9SBdhNaQY4G/Lf/qjbRA49LJtbQoCqe6A/qF1EEzPeuIpVF+5iVZOVeOhqlxAGEkAx4NTo6Oz87GZ2cVvABZGiw'
    '7/NNpWt6UMGJ/b+NNjHJpr7NBywX50MaTC9ntZ0ngFwYhbDnFnvcw8qzNNyJneR3EebK0XEFkJZzc6IlDyFKu7ZiOzMG7UQQlXunmFmZU5aQ2A0TZ5wN3YB2'
    '8EmhbZLpAl7PPgaOA3MeMXGT8ZTc4iZpEaasWPolECslr9cZ6mraaHZTyrw9GTi9+/57UDO01dyEZf1PwbgRdDqiio4+qZDOf8wpuMUxcRz/UH4hrw4xTXcd'
    'v2RwWc+u7rCeXQcbsEvF6X6ONSzu+Ngx5h9Y+lDp2ccNJvqWYa30gBpYz43dx3NDqdeHceMoybKH8gL4MAB+DNeupDGfPVowDh/PCnuFbDDa6hPJwig3Pepb'
    'y4O9g1oebMAB2v7YUJOUtIjmT/UZ2Go5Uxujdk6+nXJTTiUTMLMkFilclBdXyoxR2ftZNhHCCZYHD2Pj+brklyPVpiGG0TDoljcs4/fFd6kblRGmpDwugTni'
    'FG/TBJ2x3U6l1Lin/DjDsKDk8T0sUsOwP6jZU+t0y2d1LdNIC1KlQ7kkb4ZKKkkbj5Zya7JRkCwe/5l2wjAiuGv46k74NWeWIaoYhrRXuvNq0BcYDclUBpGz'
    'ZfkM9uTbhAHDLTHTZNkehdPZsMRayREXiwjBPOipguEBradyzNnsDhfdBnl1LyBejsTM6PSsRsvKrK4kn7R8y1J9JQiLkzXLH2iDYWAKbxou9Tcycq1R3X3W'
    'GTUoLTScOYkK+GNtPHOMmrHTRjGlryEq+U7GRWidBOBlsusw6VgekYX1DN3rbxhOVxnVL//zMYRIO4lnLJje8Dl+e1uBB1GoeS8iOo3CRRjzIMlg6cDjHB6A'
    'qlxgrkAoZvcbkO/kQxnlmKPi5HHGgigErcOq8eggOPRzTCgW/N45Wv3y35UDRMGpQ3MRIEQAw/rlrwGbhQwYW4MKes35BYygjGl0i+GMmj4E7jSKmZhxGNUb'
    'Ji0tKkUDg4vCad2aFI3fzAKVFIRY6vfUD0XpMkTq70h1EmW3vbE9OtIIVGpny8X+mn2sys/cADW0drD3CtjJxBbw+zKWN+iKUOluZIKQO+WOAxj8+pd/D8an'
    'Z8Hk/Oz1KflNk8novOE0EweSqp0Qgg5YaqCx2XgxmpwGX8wIESzo25DTd/ssZz+tOKwFGAmsgviGBfTZ5S//kTTaZtQtpyN1nFbRFfTyFLpqONwxk98qlQPj'
    'W24PLyo+TXBdc5UR6zRrywxe02E7cDqpWEI5Ml19T6WWEMJvmnsuTst1QmHVibncj5bupTFKlGHqM1SIbNM1bR1OayRyeftOqH2nvw9cm+WzX2uJSg6zdE45'
    'Vg9ZoIbNhMVeopt786H5MMAArf+igsrOeTwnzdX8hEn34H7sBp9b3xv4H+QHjKVUi8IyWS2XmNqjxK1Vzj7wryvaHhzLJXx2/moEa+wpvNJ78IU8bDf00Ks1'
    'YlMthkLvlgBKwXzUKldC5K5xMfEtB3vFCheH+I8IT1xfX+f/FvY3tkoxbq0uUcNqB2YodRZdHKzb36LfgIcwzSmNUOT6dY5VkQa6WYEOTkIKNTU8fZSu3gpZ'
    'lxfXxxjnNxuvZEtnQd8oU6vxIi71Ik9x1QcSoslCWcDKVtpGioTabqG3MbILDxGIbTdS/Wq0LYvR5uC4bTeWToh9bqy8CKusUia/+MIVSJusL5Fg+dV3+eOk'
    'TN9b4TJfS6OZBVcaJ0ugIVfHl62Wzc3Jb4IUmC7wGhrVE8yC1Y2eE6drH4AzZnfWZGHbamfPm3WQ2nYQtPSmtzlH1bGdVbjx3DnUeSfPvwYXyYxFF6lQD/I8'
    'TLnWG6kUYRGkE6tD1aLzL8NXV4pAS6yifJNM6TFBvj1TbrdsidIhHp+dZSMn69mq0/nEm9C0isPrkHKP1xL1VoCqvG2n/VhkJStsSIx8LmGjpOTS/pNMIbbR'
    'WUjwvYzImg9qb7hlUAq26HfBNxikcBk03zSAPiPdiHlLzLrk9hVKdZO6it+KBmZiLQw0XP3qn2BTv+Eky1J53FtnlqwDcjvUtE/c18SZKfsgj+fqPsgrnetb'
    'ssB1InwdBnFbmMQg2eBsGqEBb+LNIk1JkrhYROgUsY2naMU9vIZzIFs4KJcXBmEbRR0+I2vqVMk9etdstU6EvV6hQmdtenma2IfE9aowu0lW0Wwi79KRzk1p'
    'lwHNgnkrr5+C/KnEAlc0lurs1bmpoFCthEfA0mar+PCOKmgXwhzACljrUg2VnoJ36pHWmGJaCt58x7P3ebJ8SvcK5c9ELLuA8PbrJCcwcdMBbVAcsTgWp9SA'
    '6RsmsrNHaZp8aAdn8S0Qk6R3JzARYKrpWkEWZr8LwE1OwKFEnPKuuiS4AjoTgQfmDvpUF/Wpe+ogsg4ynoYsmK3wo2ikNk7sO+rEvqHhjPqgw2bNZYlZlxbP'
    'npvvXyzlXZyyWIGKbeppKD69pGWk63SIVa6CHvO7crFJIHXLXyX5FUsblowAj1Q8wZIg4nO83RDv8QP3bJWypzF0G0mGaDSgTc85lI/BXjfqtGCxlerqEm9D'
    'sDinOSb0C3DqGBwNCB8YTDpo7If04cWvvsrZutc8HicpP0+SJXj1KSx5+QVTvfbHCyMjjvkXIJpGDDMjchneojhZpbfhLYvennWCUcTTnOGej3AmCCZmiV8e'
    'SZzuNQzT1+YMLfTyKFynP61CvL1lzIEBj8Eq2DvSzra8ahJvvJSXT5obLNU9nQyTG/EiSqMRQBmFc1YUbhP7+km0AwD0Dn4DL0DdqSYWetka+K0FqmVzCdz3'
    'ovQHNGxxGFU7DJ4mWplLS6ruHyve9KZwutBWSluxD+uSuVJn6GDAWoX5yO8g5gZNOZuE85hFzYZE3Gg9kwgKt6h5icO5ci/jsUqKnmX1EMzJX/UH/1MWT0z/'
    'Yj8BT15/bNPGobiQxvrC2rinMGbryppmS31fXZAAg2VNSCX8ohIxvkv6pFxWEi9djhDP5ZBoIyctc4rsMvg+3KwawSzMNh6CwmrIbQcfWKa6/W1ItxBabu3a'
    'cTC6GvVolefOOeYVFVC6S/kWWxQH2cK5dNW6pkK2R1EWj9oLFA1lcCLB0NZXn2pleD47sukUzdrBVGQI0mVPlt6RWNfEHkJBWp+oiGb2KnRKOqOrLIkgqtBN'
    'ylcMygabpQdL4KrMYHGPlhqaIqXmixq9H9sUfOl8G+wURtn5ttUugX1XBvtO3kijuv1T6ZIdp6IdDLoW9PqsqV4P74zBfN69PW9D7yUH5XsSpWwVo2fz5ba+'
    'NhH9SS+03vR0blmUkiQ7UpK0yf2M6tLFYtqpBLEgzE1WRJf2Pdbc8ChvkShftLiGGda9i8o+i5ZmU239jY3qNsVSUq0AsSCqRpdVJgrKpLWsKse04sLHvi0Y'
    'bOks5mrJYPIsy5pr2VZPtsZVd0ejAivPt+zBhlmjF3oOwtpv1TFBe98B934911Mfqzugtd/PaaiazG4bTO0hjMACjMaNYlXxqFXeE+nAqC+L7HJzGZyjgbaD'
    'vsMjv5DVbVqJi3Ts/Sq8HELuWNBNCWvshrrcGC808F4U7LtaVgCXrvEFDzmF4MocYoZxU+HvfNvWfZFCNq2sbHUYg2kQ/D4YDLtmQUu4buegb7JRXPBDH/hh'
    '1wv+h2C3XwbXhPdASbdt+KcIb24S8+TbZ+LW6Pte0aA5IbwXKT/WbVTCvmnufolfjwx2W9C6Ly42L2AQnxoU1qT4WEuPZseeT3q3en8a9KGgJ74OMbNWaPSd'
    'r1F/aD5uKHk6rnvWdshtW7gcpshdyQquWAQgX/b7gBYvHtgfbvrNktVB2+6t2H6ds2IPBqS9VORllz06yfUh/JGLDtp8SQeQgiEmgpnY28J09O1sDb96ezKy'
    'uhZn37Yw2LxTFAPjPMXftZTzdK/exbCquief309DVdXG3GvJS4XqaK7gFuJpFORwYxSCzuOIMxgwRSxrj8EhviH6i+p7jcoGRfDB3Ziv3Yx3L9gRreQevbq5'
    'xrrc3D0Dek6dWRR4j0oqYjGRA6dPBCS9YJvWn23gL6FAUPVn79miRY57fxMrRNnuyPWWkDfSLZlTX/ZhKX+hlDvvm1otRHUSpK9lEimFWoLu01SeyT6o7Tue'
    'IjOgsfx9k3u2v0yicIp0a5fxNabIskhATNBavus1Nl5Ra/ixaesiSyq2P3hRWOnkz91vKwlf8ac01P1hqoH/ZivhPVRsuDxwvgn3I5ij2lfc+cmvgcYbldMq'
    'd1ZwL3zTdVzMEXC4rY7yCpNgu756WB2zbzeazfisvDWp7sNvrds+zVn2vjPj1zxtuvt+7cDGochoGTqcARc2TT2j1zSW+Njy3UUOIZ74BQ7F5fLPj+gxlKue'
    'nYR4Fkf9tfwgwXOxPVWwKhv8IAgQI6GqCcBkHoKp3Vk2vx9Sub1smQy9TVjW0mpPUP1ih/WtSKFxqaktYE7iSwXVDjcsss2MAVZ3+p5smx+nenYEVW+SMf64'
    'WTrJOV0TbP06FHo+FJ0KiMs0xN8Qu+ucsyzvUGoQQpS24D2KymgqxRyfLSsbs7I185qzKlbaK2QT7YN7sWkSRTw9TxisZaOkH2m2nmyv0U1n8XKFs4w/jSfM'
    'i508cU8HhdaSZL1XU0r9ppJ9oDv7h4S2CiX+1A+/lvGMo/qs5oEMMVJFeUUurWZhFmpKamjLM06hhbSQ+rnnPQoSWbkdeTcmXpPpHXbBolhr8W2MC/UF7t+a'
    '9Wgtxv8T1eucoEwNUOkExTrAU0cp0+pu64/9rP6Jpf8LUEsDBBQAAAAIAO62B11Vid4nVA0AALQ0AAA7AAAAcGF0Y2hlcy8wMDRfMDRfMDFfVEFTS18wNF9T'
    'T0ZUX0FJTV9UQVJHRVRfU0NPUklORy5naXQucGF0Y2jFG9tyG7f1mfoKDJ/IkFqRsZy0apwxLcm2ZmxZI8p225cMuAuSqHcXNBZL2emk04/oP/RD+if9kp6D'
    'yy72RlJyZvoQjwjgXHHu2ER8uSTHxyuuCD3JZHgSxpyl6uQiT1dMpG/FgsdsLpZqxpPA7AVxTnOyeMjpo5TdkyXskUREjEwnkx9OT4+Oj4/JScS2J2kex0ej'
    '0eiBSJ8/J8eT8YSMpuOn0x/J8+dHI8BozhMLDT+B4H//+S9yR7NPZHJ6RhAVAVywIldMkXkoJE9XAUJrDJeZokTh8dnN5fVsTjIWs5CLlBJBEhavhSQ03goS'
    'i5DGgYGJKbmevTvTP47Jiks8vGEyA7AVS/5kN6jiW0oouRMidmss3XJqMG6ohsuY3PJISHciFGnIQI6IpqLAFCsGh9dcLcSXknkUMyMbkcEuF5Lh3xFLEEWW'
    'J1wC9neLv7FQfaBxzgy/NzH9yuSrnLfq3KjpaHQ00vKScxGDOhToY45show8IyuasLNXTNmVQb9xqD908IZa1gZlt8qzt2wT85AqFs2VkKDINqjGIQ8+38Vk'
    'uYsQDmajmYDzlpvgDS6bH9UzoDE4Zv4++0i5eink+ZrHkZMEDpS8nItkQdW5SJd8BWCSfc65ZIOjUa8hQA3Z/F7IyID3h7U9HyvS8gT5cHk7v3p3DbT6bff6'
    'Ydp3J9/fXMzuLn+5ur67vP0wewMQk2DyhxLTxeXL2fs3d3PY+Dvw+5Z+ueDgJKlW6x/HZmmWrmJ2wVaSMbzc06d2/QOTCqSLLyDUMMkM0I+46ZB8ZHy1Vprq'
    '6Q+4oVF5q09PcXV+z1W4nkVbmipjCpNgOtE7QODT18svSlKPsWlQ39R4YQdZ+60Uj4KhbnF9SeOMuVUW003GIiTjlsJcggDKeURlEcMI4jhOqFoH63zFSgJK'
    'A2iPKwwGbOPsJU+jl1xmyl5mt/vh1fJlBRFNI5IK5a+dXWWzQd/z7/6QqDVLQQv+qQuWKSm+DobVdWAt5RCIWRppYjXkLZgA4io1+g4gxNdIV88G1+B+XbZo'
    'haxB3FBUrK8xy5zT6zJPdYwhaZ4smJwzpSCSD1KgNCYRW9I8NqjGJOEpT/IE/qBf8A/kziDZWkmUMFgG1qEhUsyUknyRK6ZRDhEG9GIBtLacUnoOi08V1jW7'
    'PclULlOiLSOMabIZbDu5aheQQfSW7C5PQb6Cq2xQSpEZ2TPror02LVf91jl14C2Pd4A65/HhfJ/fBdsaA3xEzQOd6BpRo8BT3elEUI0uBbS33AnaDEEFeG0L'
    'UegQ01tCuWAs0tgITyHNg9MP3JUNSSSQIJhWp+nVza1nT87rJy0VNAxrfPrfdqsyznYrhBpgYRZbA0fH178Jsu5+mOCC9VRchhVn2jpw9CyVwt41WD3Ivc4T'
    'KGN4hGTBw1V/TJS0HAM9DRTcSJ5Q+RX3/fUaso9rHq41Wy9oxqrIdknsWPgdpd4l87vleUyzrBS9PzxIqOL4HqFsBrpMQ5GnUPddRYNmeIMa4lO2oSGrWpcL'
    'xx5wvy3OAbMKikqslE3w0ibZ7x+gkhrcHimushgy21UasS+DHUEaSe4RySQjyOyvYrGgsYfY6B8vYA+Kc8NTgcng0OCe1Wz99LjLNjD+L2Mh5B5VLFgsIDDc'
    'ifPazZYG61cuxTYoaKctGOv3jxsDrMpeSFuzCSNwnSSWIXW8/7CVRK+nd939144N8VwNHVYAVT3amqyILb7g5jpKqdttx5AtzhYm1CZ7i6kMfbktllLoroWf'
    'sWo08nvX7h/xxDcL+2V3DiWxttgV4M5p+oKBWDT8xB4e5fwdV4Tt4cxibrR9Z69pdkdXhoVxpQcKTNEHu8MDsBuen7laMDhfQ6scorEVYfQqg8I2BBjIwO+W'
    'g/rBg6l0uYPhF0TYxAx6tb6OgOYuvGDeATxLFnm2fs2jiKUHQc6hHowpqnKmERggx3MX1FW6zeOUSbqI2UFkXuVURh/hvxspFLB6oFyXMVdsvuYsjmoQhxnK'
    'vghHDooCa5sg0au7E3txCp3R/QheMxqrNfkJ2jtyoNvVq6UizrW74lpI/quAahCqWmm8YrCUIrkRGccfkNWF+7uMVoBYUR2m3B45Jj5YKX2BH45/AAJCPtFt'
    'mEYR/HlMJmODLvirU0UBAkX3KuUqj5hWQTCZTFsymEah4xddZBbvX4b1vOZhfQ84x61kWvG0K25JQ0gXpdKkrRRLJUEw/YQzFLsRnL+UUPsGb2DZKGK/khCF'
    '1ZH+81Eq8hFONK7j6T71dElNvV5qAE3DPTgl3J/TgmchAvsWr5m0h88uwDLL88jLmGh2/PojYhCN9U2EAq5CqGHnPUgRsxeQLbPSnY6PiV4hG/Y5Z6k4AwZ1'
    '08XpCQiQxwInjdDW5DQBRqG/BacTgYHEnMAI3bCUZnAsEWCdGUs2VDHokIBFnKzhBBTukv7n3zQ7ERA+IfiJjPBkIyQQgq436I7VV5kOTGVAql8Y3OKTp404'
    'goKCSk2ZEsTiHuJQUbUgdButtyLFIeutiFlZT+7MAfuPmvxYPdfHsciwqL8sk0voGQbI95j0JWieYZcwtY1Ci9Tfa6khrrWjWGEa2I1h+vQBufItC9c05eEM'
    '/eOBmRJB7r5u8BaLQrJFoGaAnnQZcoazOaiJIh6BrblixEWPMSm8LdOzwqFnGNrXdvTJ+sTOZtg6rfPLsfMYbNXbxiJtaUMjd8GuyB9uNfBSg8daQfIQ/pLK'
    'bKg6T0PQ/p6BUt/MTLpmSnoY3JueWg4Lmm6odDhBDdGk1phEfa+Hv70fntZJulHTg6g251NNFjpmWE+M6N8bPpwTo50V9+Irf+TPlJpzbXvc6K3jrN6sOquz'
    'OehLfGLgiy02+HNFTQcYD7W3eEAKw05Kn/65vP6dFCBvXAuZ0Jj/iolhAbmAJRAAAghVIsXXRMLsq1zgeZsR0A3lp1BDeQmz0MaJrw2dv6fDqlQdGIwMJ4UM'
    'BWyDhWLQeKCxVYeYNStrmXAaM59WrJxWJpwHEvbmnzWq9cloG8l7vX0nTKGlNQW6GeiqaVxXxsjn0FdaZrWtuaxe4nc1JHhi5N/Rdz5S5A2ux+NKUzH4R89a'
    'Spsyjej5+VvTb5pUpeW9NbkAA67+7SxD4zQKKwNo5Ae/me8eeqV1Hr5tjR+/dT4JfM75ZsMi/TrojTvCojNuNstlcihP7fQ+HF7/MobTPI5wcs3N6LqAxiSu'
    'p5bA72DoTbIrnf5VZpjUaMrawpHUy7WBdXkdOzqskKb6Fkxnbp5DrHz2TQ/Yb5upVx0A79oUG20lY6Ub7BrSQ+V5Ie5Tvxc+rIXdc1tlGYKpHyddxXnsZst7'
    '2DtlH7Z1zYdha51fV0sgzZ2dGxX44feD221EWrGuSsW9ZQlL1RuBY60DNe24rLkL+fZRWxgzCmE1dl0qo5nJcZVnYveq2tvxTlx59ay8xcJe20tPawDXozb9'
    'jjo24gwfAm1A8ZEWwIH2I4DLWvCRCGxt90hordlHQJ/jPd7q2wPo4hrbL32TL2KerctrD11b4QWfYq2wspqt9K9F0Y6YTs/Ym2eAdSMqcAY6NTUNqjygVzqs'
    'qoHmsRbm3uweZ2A1NvTHAd9mcSVGt/gNBlgi0yvfYIy1W/kGwzRm3dHgast6wTJrL4OqMVaTZKdRvk/plvLYzI5bjfL/kLPqSabboxBsJ9+2I9Ef+uybMC5A'
    'l67/wMdoxqXA2LCFRgQ/0dOf61GVozpEYsdhlCioK6UehxGGrVjZkpiWr/B6m+kqTl4+IlXfbyqnyuurYXSlaDnn0DVWBXhsyi43+NC/XJ+mf7ghzbBZA3L7'
    'pY9XBjafe17pB50VMN3x1OOViG2iOiJekWhtbo+YPQdp5KjJWBWyOIsFRO2brp6RXTNY0sSbGZh3i0zXOTW3hm4Wd6yPl7z39Hkv6upVU5fUqt1iKnBeoaoR'
    'uD9MsMRCtXbUbji6tgv0PlNp9oDtTWDtKxbTCPZ2feTi2sHeJNCTVTvkQL+53HJFyTIGVhlOHAnoGXQVCZ6RLAaf0lNgc50Z+ZzTDIxrlVOuR7yokVKp5KeG'
    'zGZ95MlZ6N2qvelzTuluENpUeHHLDlknLu/mKgCNEgF3h5bqIcXAji92dFuDRl95lf4d2hxPnuJzSBsMur89e0gygzwWfX1M3WCfPx8BCV12xnXutJ/CPgj6'
    'RoDhIsd9V1DoWsDM2a4FNiEfprYTasu/7RcYsfoVet3q/itxbUrdhK5Sal+JH6Va1y50vAOxJTjoemYYR3rDHZ1wm83VG7WKDpxb1FTje0ELIag48NVjzlcp'
    'jVupnkHySUFBgwb/+tLKr7+xOZVqwagqQJzs5q3yjifsAbflvhwePSMFuIF2Oz81PrluR9arfITcbWhDT0kH1JUC4jCmbvlG0Ih535d9k2vpj4Z3mcRVusnV'
    'jRT4f4KYcOA/DD0whun22Gqt1UCtWdlqFMnZyzUPJbWV8kP+/UbWIkfTcIY7Puk8QCFlLgMcdV7L+qK2cwahKrScDFtPFOOIogxp155XnpRxIQsl36jAfj8O'
    '6aBd7GaMq3+33vKVt5Op60N1Fw6GR/8DUEsDBBQAAAAIAO62B10C5pIZUQkAACIfAAAyAAAAcGF0Y2hlcy8wMDVfMDVfMDFfVEFTS18wNV9IT0xEX1RPX0FU'
    'VEFDSy5naXQucGF0Y2i1Wdty27wRvrafAqMrqqJoSbFs2R3PRFacxPPHh5GVdHqVgUjIQk0S+kHQh17kZXrRB+j8T5AX+3cB8ChKltPWFzJF7C728O0BUMAX'
    'C9Lt3nNF6EEi/QM/5CxWB1dizkM2EbGSIkw889YLU5qS+W50+zwO2DMZDU/6w97Q8/onR8NR0CP9Xu/o8HC/2+3uuuN+p9PZedf370m37/aPSKfvDkbk/ft9'
    'MI/cPbx8SON7JmLSJb7hYyRghCr6e8rIikpKlIBHlyjmhzQQhJF7GrEVDTwtYiZE6I19xR+pYoEWwuOUkoTFQExJGnOfEtBD0oDicpJGHJ5WLBQk4YliEYUd'
    'teG+iOYg5a+EwWsyF4qChBWLaUL8JQU63Ow028xpo6YLIWGB+ixJ+CMLvf3OmiBrGCgvM3HseSWBAxgJjxWLfdgpN1vL0HKMQ0nmoysBNAdkRpMH0hueapJY'
    'kEgE+IGkLjln9zwGodznlHwWYdBVojtWivoP4LqLODiY0NhnIbjEZ1JSo/Ddk5DBZbxK1UQHre5HUHYFrqNgIVmBGWigcMkTgCldgVzJfPHI5AvEZJ+Ewqch'
    'QRiwZ4XeEvEdk4/cZ+RMB+/0E1P2jdNqomu1Mym3IX1hMmlitEsF7ZStQgg2wOBOCUnvG7dbIwL+ruH/mjCpfbBF2zoN7p7tv9IKAZfVzPuCr82XwiuIDLB5'
    'we+BUrLfUy6Zs6bV6d8oVx+FnCx5GDgtHR/D22rX1soiW+3cG+PJ7PLm+vv1+OoCNmoVqWbA0NrvGLrPN18+fJ9ezKZ//355PbuYfht/AfqIqiUkMI1WTlm+'
    'p20/TxcLJmc8YuQvpOcNXfjoHerPUXu/k2mAtq1WYBIqn223BEiC7zg8npFe9pZqnT6zMIC3CxomLFsJaaIQxuCX1ZTRBNIArLkW6k5RCf4COzLSRRprEBGe'
    'mMSxBjug055kKpWxjRGGFNwg+TyFPG5ZOsOESdZqk7MzomQKagD+ixDnWywA+Rdl+2ATsmeIoFZI6isNBbOfN8le6UI4GGIN7Lw7dvu6Fu4m3FoQ83CfGKXq'
    'dvvUBtdJkAvN3kGjzh5fQBlRBRW82oMkb/TVZfJBPMXg95KLNHXOXWO4gsIQQUmBZHiosakli5HbWmbjvofG5QHTlpAfZ2g3oXFgXni3VGKZAlmFbbhaBWti'
    'vJd5Qwte81rCFAIP8ATqLuHJhbREoKH/KsBc6n+5+o3QVCIB0+N7x8gg4BmnJAR1bCETkLRwEQpSCJToGdzP+vxuMz7HubCWW8qbNzFXlK6I0Qqiq0G1dfsw'
    'uTNMgXSlLW4q4IiBc03glOpQ22DNcmbRtxAV0QrCCPLM8ulHSIKPXCaqKHNIMKEr3KeFslBYxod62+fTy2TstGag0xc6ZyFALttqz1J4uAhb1QMzno0n4+sP'
    'N57nmeDoF9MW8hpUWm2hB8JAwbeoe2sp6vrmnLhh9mWLxhnJr6usPzdAHyKLEXYKwJfqc+eM9OFNJT90jmYJovdDdKwQvps2oXZeqle0DEgmw8+q7QJFN5XB'
    'oljVah3ZWkyqss/Mnmgb/i9NdEXdKYr/ukVznLG035AhdyKkcmKbUrMnrb1Z9ysIdFpV/Izbu0WleHt2az3GCpIbTHxIAPX5IGNa97V4ctomoRUMlB6QPMVO'
    'ZqO2bO9pieNnDXKZ/mUDSCA0Wm1w1hpwgeeSu4p+C2OpdRr8zQFcD/rRer+QuwFKjdKNM77G9JHykM5Dtk1+0wgs2T8YVzCi454///3zD5aA/Qo+YQq/xoqn'
    'dxgrLxMBUxxTPBJJNtYD17/gxBLpb/KRwpHDT6US5mCDJxx4lD//8wxMZqbORMEXBhMohVNFZAl9OHwE0HsJTWFGBM1ALzg1wILWF05LTEZccWn00UF9gsrh'
    'NEx47Up5yFO3PohItoDJf1nMIPU82pii9Y5SydiKlCJ6Rez0Qj10VsX/pv2QevvpAhz0V+8bTzjsBALrI743E6m/vIhREd0C1jjW500CAUC7q/4yU0y++Np8'
    '9aOYr/YyJzr18Y0UkoqXO45gOqI4STbPuCaGxrHOdxdAjE7B8mSDXLxAiRdxGnmF8/C1d2GaJhTz12nNubQ0FlZhlOd4DpNdRZpGaZ4hhPWxSwu1VV8LqSAK'
    'anoaKu+Oxw+lKeA18ltI3BJkq7760aysOblrM8mOO5DyDruO60TH438OpPUsPg8t2S72aAcbe7q/Mhh00QWGo+mUsGZtlv7rEwAYAQV47eqEPfthmuiSCz0B'
    'r29ANMWLm+otjWf4f2Mvc0FlcCXShB18MldWeFtESVC5siFaFDSHiKRRfvEFVmo8eDbTNjbUtXFoF2+1G7IJztR6dceEsAjPEqI6Eu2aTlkDxkzf1trfhh+y'
    'm/J4Ej/uuyek0x+9c/u9hoN4ol5Cpsu/7SYIZVv+7/g/dbf4wKOBt5AiulksYIRzjo9ccnxUIjyHqNxLkcbBRIRCvtM9Cx801/TTudMfDFwyHLmkPxo2Ms4k'
    'jWE+AzD7L3ht4vUHgN03d67dGte2vvXGtvV/61rZmVHG+k6j8Qx2s5jACTZxWl8vJ5oQREA6XMYwpEMr8GL2VF4DqUaeZ95MacDTxEZYE/dd0iuRZcXF7q7x'
    'NDp2j0ln0OvBvx3h5JsDoncrEq6pMkzhluZyDYDhAlbL1BX0WeW6I0M7KBNuBFEfEJQR2bNl6exYW9n51EkqnJsAPzgEswbvAPWD4bCs7UehPaoTF5+9T0It'
    'aXQOhaUm2jrgRLv9ZGjcPoJs3s3tzRPPHACUw9HJb5aqp7ycAB4gbUx/qw/GmC/Yl3MZnsbkOICDzimUpJj5qjhs+bimkw8qYeMVlqHIq+Hafnrd/MrSO8Sa'
    'NuifuP2my8WNNhJzFFjTecoiyMTXtNZfMEWrmjX0GTvcZ3RmPDDHlYAtQKfyqUMvmqJuDiqIzcaCYaNxx+9jGq5Xj3X18xukN9afJpvqtJVRsXKGyg5cODFt'
    'NNmgU0ezf+QeQjQPe+5ggNHMB736LGOYSjLrsMdfKroNxbvmuKKS5y6ratf5JRkVt+8+rTYcDjOS0k1x1cMZUF7Xs+Hif6PC2+81tt9qNOu5tzVYdTO23Pvg'
    'xmb6mzIavLRc2yffxHorQu4jr750usTrC4W/d+a/rX7rt3YSWbmg1tdwb2ETWHCUfLm0NyYgo/H+4k9QSwMEFAAAAAgA7rYHXUXuBmd5CwAAzigAADwAAABw'
    'YXRjaGVzLzAwNl8wNl8wMV9UQVNLXzA2X1NFUlZFUl9DT01CQVRfVkFMSURBVElPTi5naXQucGF0Y2jFGtlu20jyWf6KBoEA0opi7CROst44iEd2Yi3iYyXH'
    'WSAIjBbZkjom2Rwekj1B5nfmQ+bHtqoPXiJt2ZvBYIKxyK6qrq67qunx2YwMBnOeEvo0id2nCYuXLH56cnk+uU1SFiRPJysRe0MRTGk6kYuOgnH8jGZk+his'
    'rcFg8Lj9tvr9/iP3fPeODJ7t2s93SR/+7LzYJe/ebRFfuNQnSUpTlpB9krA0YPBApz7rfv9hk+/k6ioQHoM169oiP3oGZSqy0LsQwn8YGg15QFMuwiF1F+xB'
    'qCuaAgocMEwpD1m84cZ9hR2zXzOWpB8yGnubYhrc8dF/Ph1NLq4+j04Pzz5fTY6GZ6eHEwDcMRAnB/+90lCTq/OjsQZFkBcFlX8fDS9GZ6dX559++TiaHF+N'
    'Ti+OxpcHHwFs23m2u0W2wBbJexGvgEniMdensRRWQroem/GQeyKB95HgCQkFofGvGV8KmwQ0IVHMXJ7QAE4WkyVP+JIBFAsITVPqXudijFki/CU7AtQoYp40'
    'GrMWxTxMpVKRF/VuloUu8kDmLJ2gnXQjn96yGAh2StaDIpVW9EUtf4VlPgMuU72eLlgI7zoG+js+dD7SJD2QDB6k8HIAxrFwFtmc2XL5lN2Ul7fVW7RxUTxe'
    'iGsWFo/HHM2fA2Pm1Y9835w7wy6ssBDO34lZmsWheSnfNUngI1/ycD5cgGLclMVrsnDNCmyg1pwcOAdaZAENBfcApoCnoVc87b3nofeex0k6XHDfO5sNfZok'
    'XetYY1rFjrEQ6caECgpjQDuncSopaUUVNEQsX+SMwrP57Rwz6qcL8gaka+AkD6Xfe6PkoGv9QhOmtsiVr6Uccr8u+HxvO9/JlrSMMvrryhiXfDrXRF/LZY5v'
    'QTAVx8+Ns2/OrMAkf/1OxyB9x4fOZ5CdWIHRxynzpAGKxHGB/HW3Z5cghhALtXniyzH7xuAkXu31geuyaP01esB5NvV5stCblJ3AQCiaY0YTgaYOApRrP/B/'
    'jScEIHkYAED59Y2c9Uv5bk2mkeLjkvrck4Gn7PC2wi0knPIAtqVBVBGMEm2xNlBoTv2cb+4KiEYfiun8DM2U9ovdAEYxuzdhGDhiPs3gAJaMciopGu1o40ks'
    'fS6norbeBpSMQtcoVTS9CaW6hnNK9YVNiBXa+xTBXxQR0IP16ySiLtv7wHR5cAFSOxWrbq/XZg+x3FoFYH3K3BjinCHtSWoBw4AOfOD7DCz9931yLl8kNbWS'
    'GfUTliu36rbt7t2gLdKXubjTLDQ0EJGAqMJ5V3GNTFqGgiWFuqHlVzlvlhr1fbHSzI/LCXPzMz7GwerR6u1+W+FSiXbOepQru1MFKA9dNY8sr2pVAIvra29b'
    'C6XCMtotzirJ9OjGZczTymu2J/0yjbNWTS2VulnzfikUQrYun/TaTzR3TabNWO5F1mHgQzUMLER0FrEQUu7+vjx6nc6dAi7Q791plByKVYgKeNROBrkuDqju'
    'Z3zujBIZ0Lqogt6DCI9CqVSJXpDPXaq1zFDu2Fbe9ddLpIcwVSN7wpMEnqunL0q2qqBPxJIFYFgfwfkfLe46kZJcoOOYsHkW0/DPPyjhQSTilIZQokfADxEk'
    'YD5jBKpPnqTQf+wpFGg22BTNn4xZIAA6BJ+ihGFXQQn8FwfUIWfkm5hTD31EdSdEFqgEWwxDh/rIGNOoHsXGZlgqZrExha5MYF+z5EgLkhiHaAWvoH2Dgzo6'
    'IgLRkhM+TlPSbk5FatqjiqiMy5ZRkbCufCvvVQmshHO0BJ5UpEL2y2AlhlMlFATBn/XKXXsGik5RPaUB6yFinZ9HuItZRboNXpOgVEYh5ITQZSOPKGbrsacK'
    'ZJlEdRsxMevWSEjGLZWULQyia1vAsvUwG1de1cRG9TSblhjVgl3ntQcWCuip9h3NjU5M9U4zFOA/Pv+NHZh5ycjrgqYy1pODnBevtu2d3dekv/t62959iaOc'
    'Qb0KkVKqJLPe1uABmQOAO3l2uzf6a+huvemV7Wj95YYhDvmVFjDIO4GB1OXg/nQBKCsah1380bG+YK8xujg4PPtaw5GJVVi2hJMhBP2qeFw7uM4srRCfGY1E'
    'eAFWbyH/nd56fbiumYYyQyFJ7wRb/X8qFUWj2oKb9hs43GBwMWhJf0bIVfnmMNClWsVRzOBnbY5kAEKxqhW6KkcM4XRQQoaEEVdOflwRpjzMaEB2trefEJql'
    'IoaMkPKlkHMxkykchY8S4Ql3BWQSdpPGFBKKIMdAdJCKgZIoERlmmSwgrs9lPqJe5sMhIHspKiEVMhu5kKUCyGFRLG7AN8k3GjKfagU5Ruor6G/lgZ3KCOse'
    'JTQNhjYYBeXqyfHbtWPQQGoJnlMZadW7FMHGgc8GhAMoIMSeZdcJNG/UPMTaZGyVn1oi38+YQb3n5KDqC1iG+kJPSrHQUMUJxiixR6gM8hIg8rlLXbAMMB8F'
    'E5fNUWIwxend5QlwIoevwPrkaHw5Ojwbf5VlkrQ77MYqddG/oJACHqGzKrgs8eg4jjqdkq7HqOfzkFW8i/TJtvN8V8oMZMzKS28KFDB/DHS1A+w3HaDTmUI5'
    'dy1/qijd6YyzEIcN3GVoBXE6ZTTd+0x52pX8de4JO53W0aSMvJCGWOLCXuCYZ7PuXFZEd7BjdKyKXkLByGizgG0l4PhOrW6k1txKG+bu1exc4rxIXbXk1W4S'
    'OoUBPMKg/5nk9D7zfUxq3V4Oohg2QIZ/TNWl5yqunJlgRM+JFOncslvnz800FAllAoULVvVU9sgxG6gAC+QjCPJSmBk6nldxToD+ixIZVDYiGeT79pqix0Oa'
    'ZZDE4zq+9V3/hqyxiTR+Qhapb7NxVvk78snmMrk3ZrRUru3Ov7a3ctJ7Q8FPCAQtYaCKowrhFnH8zEK+RRB/TWHfdJ6WLJ5PN1xkGpo7jyKVvABqLY4HbcXx'
    '4P5Cs84fwVB6ABCY16A7jmMc1UwWUOOuyNAX9NrMWwSZCz9iDjkgLo2orKjVREgRgcpHQEUN3YyKu1Caz7I5tfUYSI6OKGyAGZRDC8vnELQjBucOGeZrKJhc'
    'KK+FA+RORMhS/ptqpnWtMMTm3R/SqOisLXU2bCjMjeWKDPTZK9fIb41lyHviMUtYilcd1Rtox1wi72AVjrPVtZXy05MKTT0RULhSsA1s7COH+ZK6pJZDBFLc'
    'FiOxUeixm+p2VQBYK2/+pcD6WtzBR4x5BaCyXOBjgu+VO+EB/0Hk3aLr0yCCt2EWTPMpZ83coXIrkTgBbXGodqHO6MkIsGPjv2fFPfQKImyGNxWSPTn2h8en'
    'irNcDLULfdRhn3QrKH1NYcxcSITxba8gAmTUByTsIqbc76q+V4LbCgb5weNM8POULh5ZwuAPRRWyxvJWBjgtKgmZqPcTOMQcT1ddk68ljW1n95n8URKj3NeG'
    'Yvo1iMR5jhzkNqrpHLJpNldf5uRWqAKFmoA5M5z3yLBRfMNz+fKrucAhTxJ1yv0nHgRZXdbIeFayoV4vbyiNUlL9aUTJBmEtpcm140HXettVWrPz4YS8XkIP'
    'ZzfMBTs45li5qtqrXB2resYm1VrFrgY7W9MCTsDbMdYseDoVN+UeHSIHoMdsTiG4EepjCw8Z7pAGdM5MOEB5FQzVxh6FAGx1Xi2GXttnHAnYEAQchrxq18CZ'
    '2qudl/Yu6b969sJ+Jb+N6lQntWehujaV09w90CyEsrSbC07fwoM2z/PQjSZQf4/VnL47yuv9xlldvxn99yp6v9N8aVbHgwCK5z0DteH9Q4AfU6mRdDGM0JcR'
    'nU0GVFrEUnD/3EHBvd7esXe2peT0BZij/uJYGe8/1mVWfD2z9nUOfiLSb/20QX5AonS81S+utje4Ex9DY3uL5Y6cLz4M91xAu4/Iluniimm8GVKNaThnlzvW'
    'ZrRP6I35euCcxROIeCE6eMstqQwrd0SV/wFQSwMEFAAAAAgA7rYHXcJQ5TwHBQAAOw0AADkAAABwYXRjaGVzLzAwN18wN18wMV9UQVNLXzA3X1RPTEVSQU5U'
    'X01FTEVFX0hJVEJPWC5naXQucGF0Y2itVltTGzcUfsa/4gxPJruWbWxIyMQdUmgaZkJhMKWBTh+OV2dtJbvSVtISk07723u06ws2TuNJ87IX6Vy/c5UqTaHV'
    'GisP2HY2aTuy92Tb5zeXwwfnKXft4Sdj5YnJR+iH1aWoaURWYgmjb+FqKC1pCh087MpeR4gO9pPOYR+6HX72G61W69usaURR9I0WHR9DqxcfQdSLu8/h+LgB'
    'mUkwg7TUiVdGg9JOSfrRTJsjMz15YzGnGJz6zM/COBVo9hqwU3MVRmkPA1iQvrwMJ9fmYvSBEj8sMKHmU7YJZilzBanwDDrioNHaseRLqyFHPxE4cs1KtHi/'
    'B68GFb14DxF0K9Id1HKd8HZJeMuEPdH5AuHdkvBuJjGameVNRhZ1QmzbidGpGotzyojeKs8OMtlWNi6kiHfo+Su7RCmVHjP/FoYvuW/IepV8jX3NnSX7KRV+'
    'suAlLRtRI1qPtTvTb6zR/iJ97T0mH8k2cfZxZYx/HPJoh7P1pxyuzCgz0xhad0CQWtKeBNxgZiy5Gfm9cSAJ7iBl+3NAb5EPDHwwY5TGilrWJdmciXMmxoI0'
    'k5Q5QkF/lvzDbtox5VCgRbBq7GDMbklybdKJcZ7lOLEIXPW8nOXiYwfENlm5iOtSDGP5alMOiCtCez3HuAEBVnhSQgz6dTDfNzPlGERHpBnKDB/IxpBM2KfE'
    'h89VrHMjKYthwjBoo2QMlo/3qordP4gPuWRD4fLv91bHdalS8A8FmbTpS2+swqwW+Sv3jjO5B4MB7OoyH5HdhZCFm6jgn8FMq5gd+AlpFj7Dl7+qNAzKtPFb'
    'ZF8AQFzOA1WLixbiokrcvKdI9n1Wu80VPmitpsRCnjjHsVa+lFQDsJDwwyLyOK3jfqpy4r7IwtZcCsE54FbageiwH+93NoSHppSUPiRQcx4Tbwwjn3CPNmdh'
    'QoSTjxQa5MKd6nLZh0I/N78vOf5YEHImjum8zLwqMkV2yfIz+ZMM84LkL1XgmrXW3atVht0YujH34Bdx6IV72zbDufqqhw/ghuvK2J7Q9KkZGm9lqahph0zC'
    'nfHZuqnxRsLbzcd3T/lDKlTdMFe6GX52vhi2uLrexig+WfbQ35T0k1WFe/H/V3u7ouQtqfHEf38td19xrhoQa2o5rMspvRjqm5tqqIJn8FjtRZo68g35ZNfi'
    'FkTy8WLSrl8zl3gxmW8zX6ec7VT7ox4ltC/EqNcdHXWONuxUW8h6tEdtQV114uehE/OzrvXZ7SnmOKZ3igeaY7T+CoW8jFfdJB0PvOEnnsZM8LzxHy1mAN1+'
    'GNbsyXzUKB6IofgC3DwSvcomKFHABYTdTvFQ5RvtlWYkHXdFAwhYtWiJkkQl6zVkbEcZ5ikjNyIwPGQVc45RT0w9aVO8N+HW8iS3PLaVb3tTJhMWmgP/a5ca'
    'y6O5EohArmAzgMKMR57bnG+Sh4KAlTEJWcCFyaacaAl/5WFpCBZawno7YAuf9pgKyGhnrQgDPKL7IiT9euVUV51+uFpL7vqmYlpdyviC18+DcLG2b9V6Ogth'
    'jxl6FcOqk+G8H87/5thx+sMpOeRdiDeVACbjKy2alwGsHAvedgprEpIcD+XisN3kGPPWlBie1oZXKeIBPXIwQjU1rhJY8MDOOUSf2R/DUD8k6DwXdILhv1CO'
    'o87AVqsWZvdGcMgnNZJJaTkAH3AeCgNjkxWcGPM0vOK1S1nOYE0X6TDAyg6lmDlq/AtQSwMEFAAAAAgA7rYHXf+GM2jUCQAAKSAAAD8AAABwYXRjaGVzLzAw'
    'OF8wOF8wMV9UQVNLXzA4X1NUUk9OR19ISVRfRkVFREJBQ0tfSEFQVElDUy5naXQucGF0Y2i1Gdtu2zj22fkKQsACNuKotpO2abAF6ubSBJvW2TjNYJ8KWqJj'
    'TmjSpaik7qDFfsR+4X7JnkNSlBTLznhm9qGNTZ77/dApn07J3t4dN4S+yHTyIhGcSfPiJJd3TMmx0UrenXNzxlg6ocl97O5jkdOcTLbF2JHskUy5YGSuUkb6'
    'vd6rg4Odvb098iJlDy9kLsTO7u7uHyD87h3Z63V7ZLffHbw5JO/e7ewC1Y9qgsw8BfgKTP/77/+QG5rdk97hEXFECVAlBVmyS87pwvAki5GGpXNM5zSlKO/f'
    'iFAJFQQI0YVmGQhAE6osKPlEFaHCME1JSqXqkhk3E/WtSxI1nyj8o0SqHiVROcmYYIBoCYkHVfIaEfYAVBU5lWy+PAHOdyzI9isljCy0SvPvPFVkwYQCSvoB'
    'vmiSqTkgMiC5UDyDP5YeSkIeqACQmIwflU5B2zHTHLRghMtEM0SjQC6fU5JLnlDywL6TBZJ85GCerzkImTBtVG5JgtiAojJAsMJ3CRJQRJGZtZwiEkFyYfhC'
    'IDkGcIYCmcyd7hmq75gBpXd2nT2vBF0ynZG35I7O2dEHhiI+8IS1I38VdQrYa2apGpaOjdJgniasFaAS/+aRMekBm1Cr94hV4C2sIIDhJYov8dh9qcN8yDmA'
    'uc9Hv1CIWaWPZ1ykhTYAUNVnrgy7Znc8M3oJiJp9zblm7RUd4vGMapbGnw0X3HCWxXXcQHLqA+YUQwko1sFi0LYdHUNQUhN1SdQQaXjskCyJqhluT6/HF6NP'
    'QDVal5q3/aiAPrscjs+/XF6cnd5cfDwFpF7cf1Vcnp8Ob//1pQFksF/yOx5djq7HcPzbzm7rk9JzOHtLjpVQej+eajW//vC+PXj5sksG+4dd0n/9utMFyHNG'
    'H5ZrAPsH+13y6sDCnbApo2Ydxf5rgO7tW8hRbgSXbB2o/w9Bf5TSSyuwqyjF2QxFe3LkSs6FBLdCrn5nKbCZUpGxAuKBZzkVPnHBRiWLaS4Tw6G+QWjkCUtP'
    'p1OWmOxU0olgaRtc1/IkqMhZGZgQBUNjNJ/kBqL+2FbTMTMGUv7LdY0Uur/FpwWBt0RyQcyMSThubaTq6XxUKKAlw2T654it0NLM5FqW9IzOwWr2bsVE3s5V'
    '24Aojdx8cLsegq0j6pCfjnoQ17P2jip1W+OJjXjwF2qrbU3911B9U+wj7BuWYSzM0G2mTDOZcPgM1Qcy2VZ76C2EwecMQm3OsGkhmSHcCNot9IWmC2V4RidY'
    'N7DUI9UFTTXU6a85lXCS5XDm7rCrQD+G8heH2MlcYPy+6PENtAibgFv39TMka/Y/r/lt1fkFrZ8ha5r9D90O6qmj1pZQ+aF3WSfdLBeszJQsTxKWZcUligjH'
    'ol3QsYHjYdXkVwdyITNDJRgNppx25Hi4CLDythxg/Am4AjQyr5wifzgthancXUHRt2Ucuvd9toBWXIkhB+Ps0akYxGlAwLeFEuByMP86y/BQeryti+RoKE31'
    'MA6+aCxiLhvhtloJ4bzmCSRWOBz6iDuNsOi2TmU+j6vGROPEH8B6GDVQiQXPQH4ARXkrpXUjDwu2DaPTbwuhSkbwvw/acTVoG/XIhg+UCwxcx6hmiJ8uJ8A3'
    'VdHdqWPV7C7k7hWziN5ZUpmVGrfGXYjQ5POQBCH2LQMbSVUZMZxqza3g7/EKroFMTe+6wtXa2UBiRfCmbHQ4RzhgtTshH36Hoy5pZoKzhsY5KaRaMRoyfcPn'
    '7JN6tMQ729L9B5epo1xaM7JhGKEtIjfYRJtcDhPztVKmjbuTqPjbfnfu8F+OLrJhO8KeJaKVpuMCq7Ck46GBLnjIIZ+BqGdcZ8aPrOfQfqTiKTKHUoQjIya1'
    'l8Ciojb4wTF+TzNmAVd4I0zV15ZhfKX5nOololhKK6fPkV1BeNoemhT7ZcaTWZ1wUGxNiZxDQBg7/LUXdCkUTYsBwn2L3TCJda95UHCzrAerGqIg4KfWjdgW'
    '5qmG/s6F0ebud2OXrzNBs1nbLWK4moJSXZeS3WJ8KfvhjN/NBPxraHPFje1xAa7ocpHdkYq10/KManBD2FwlQ1AnSu3yhC3MzG7tb4krz8VVuIlHSSLylKU1'
    'xDMuhPUTNgH8W7v1g3wB4E3nT1fo3GgqoRLg6OWWM2sbG6i9+HCAidcuc7oX7x/gUS8+eNlp4rqR3MuBw+0f1lDDAFDYKDhG8Ckz3Jq6Tqn35olgjbsWgNRP'
    'XMWsbsBHxzZobGULEtlCZqEu5FTZSCgk6TpPndIM5rGxWQoW/zOnae34BLZbG5FoFLtbtXC5a7Ua7N23161m67nLH1g1Q+GHLwaG6BgyHg6CgXbRKAddUm8a'
    'ON88NXORdaW6RycwYWu19I3G5p1rL5vy7MKWi2vQt411r55kZW7BeCsmiup0JbfeFzf+uaAVQBvSq+QW1SDLBPPFt7waQ+OH888nfD6wy+xoOoVBuj0AMw0O'
    '6gyH4pEus5G8UYsw1FWuL9FMEAuwgkn7qtKrXX+k3064Uw3uDuuXIbrD40m1M7kNoW6YMw3qW4vgdTBGobw9HMpkpvSV4pb0LcSb0gOLDmnWxVwL+Fcw2Fm/'
    'VW0xBu5sFXbFZg6u3yX9APOeJvd3WuUyfRqugWOhcrBCReUEHaZXlP58cWwvrN4OJnYn1zTleealssAgTq8CFtgh8wonDOp71sBpbC8sJwcTP62m/vgGmui9'
    'xEWjOibaCrhfgaqbAROxvFwnXKW0Vcvr4KBSIn3ecQlJ4BxTgr55hYCvX22saMH+/4eKRtblV5C3W4reIStVbJ3Mzm5/mcAXslqBm6tv1c1/Rc1dSf5Qc8PN'
    'tjUXi8etfSNzlfDJhGZgmQtHuF9Fxm5k63cMR991XCxOfkK7KcYUP32HsaXlJ3B3UBvBm25BvQRYUWlG03bYNhD0GYn8rF5sA45gZR2w98/QoHOoTnbip2YW'
    'z+m3dg9mXwXhMWFhto2HFqpj880z8Ih/hyRez6P2VLnryl7l5bNizNq4W2roJ5m3z75oJr4qNU/mWAC3n3gLM3ohCi1/Z08PG2rDclh5GSheyp2RYPGo2qzz'
    'DL5fLAsauLKSTfvqlvTcVlrRaQvcYgEC9HU7UZnBtV8p4pF0j4j229GxkpJhFj9Ja+vWhvfC4xkFedIxv4OC2o7qP3RFnUCvVor+/NPvSmbNOIThptxq4ldI'
    'azGjTi3jAsHNOVd5D9rIwjm3U3dG1aiNXl75heea0XRZ7stb4d7i67WSgO1/StqWwJUSPEHukU1pzMaR9E9YV0yP8UfL2777zarMiz+k2Lbo24iWJZovcMm1'
    'fQ4umoN0CsHwJbxEc0n4gnKdtX+rPah1a29zPzokVb7XesTyIXil5/qXs+aG6wPkf1BLAwQUAAAACADutgddJBNLgkoUAACQSAAAPwAAAHBhdGNoZXMvMDA5'
    'XzA5XzAxX1RBU0tfMDlfT0ZGU0NSRUVOX1RIUkVBVF9JTkRJQ0FUT1JTLmdpdC5wYXRjaO08y3IbR5Jn6isqMLERwBBsARD1MMdUGAIhCbOkyAAgWZwJh6KA'
    'LgA9anTD/aBEK7Sx171PzC/MfX5h/sRfsplZz36BlL3H9cEGqzKz8lVZmVnV9oPVih0drYOM8Ydpsny4DAMRZQ/P8mgt4uhytUqXiRDRfJMInk0iP1jyLE5S'
    'T8J5Yc5ztvitmA8i8YmtglCwbewL1u/1nhwfPzg6OmIPfXHzMMrD8MHh4eHvWOCHH9hRr9tjh/3u0/6A/fDDg0OgfhEvcFFFCf6ExX/977+zOU8/st53JwyI'
    'H0nqTJJnDn0kQWRGfMt9zsJ4yUMGJEIRZHnC2U2Q5jz01FJpBkNpvAWeBONbwf/9T56yXRLESZDxJIA/fs4FE2km/sa37OXldMiA6hJAE35CRI4APP6byESQ'
    'soegqwTw2CeeREG0Tv+kQF7Eacp4FtzEemQcBpnQf6RhsBUpSzjI7D9UNMQW1+V+jOwv4+2CZ8LKN5MoWxEKms2jlEU8ZolYigWgBqQTP07YjoOM4gblYbs4'
    'zGE4tmp4cChVNIrDUCyzII5mIrkJloKdsjWIefJKZGqk3aoAtToa/1Ue7EG0sxbjKuS3IknrwNWUhZ3m+9iysxZj/gkcZA+OO49YGm9HSwOG4sE7x2H5RxEG'
    'ZAIw+fvkRx5kL+NktAlCX/MPAC7ld+PpbHL5BnBad22Td/2WkXz85mw8/TCbj68QcxKtgijIbidpyCM/baRg8N9enQ3n4w+TN/Px9N3wHGj0vN53evZi+B6m'
    'ziaj4fxyOoPJY3fm4vJsfP7hbDKbD9+MxjDb7z1256+ml38ej+aT87EL9F3PyuxAvBlejHGFLw8OD16EuSAHvsKtAw4Voo2yJBddmJ0s90xOhU+TF3KT2ImX'
    'QSLqZ5zRH+W+tJNfnR1weS51gBwW1ga3j5NH3iqJt9NXL9qDx4+77LtnXVDH0w4uYFasA+w/7nXZkwEBUhhooPcIQPuSHsWGBrhBvw/AktyU4kUVEGI1AgKH'
    'gEKQc/E5qyF4/BRBehbuVcjrOOwfI0iXPXrWKeqMg4pukNUVD1OhR0XIdykx1tND6zzQP5M4zl4msB+dTWe0Lf0YWUhFthUZz/giFO0vX7vsC/vwgY4i2AYf'
    'W+yr2epLnviI8eWrHoHoFgDaKM6jTHKhZ1Z5RPEL4qSfL4U/Xq1g4bQNxA4SASdEpHc0BIthliXBIs8w8tG5NRNZBu7zYVpAbnXYqXQoIHKAEbeOgsK5iHH5'
    'b0GpYojIr5HoU5yE/gVPPkLUGkeoNp/EUirhsOdsvNon3Y8OIQxgB8FKo5+yKAhZthER8r2Xpopxr9+e/VhljMiSGFrrktZ/GU+ql3GZJwlwOqLz1zUaCP8x'
    '3fGl8EYuSBOdtcim4IbtIIITNloKJWUUZ0wPGSnVCiC44RlANdjJJB22Wy94Kq54koGVSmgazsV1l5H4mOWEVWRnTWNI3D6gc4P/Ek56iH1pps6e1/mWR3Hg'
    'o3zEUpe8RklI2HBy0I+7eEeYOpm9qyTY8uQWsYhY3cR9FePilJ2iQcgfN8FyUyRvhKy3dxjcgGfPeQKGb2MQCR2L098MNqH5o2gUd8aD1cC7ysIop7WqkmSK'
    'O+JyQUHuRkg+RvF2F0Le6FeCwV7k4XaRp5vXge+L6F6Ys2CbhxzVMCQCEklzvE8Q43Mb5VPgd3KFJnto53OcThG2JGQMAWb1kPda8DDbsOcYqBv2PaW/kv+C'
    '/eoEvhIQB1Z56AhatpdSWVFKvl4n8dtUJBMUNIujfLsQSbtuiaEFbXUUKy46booCOR0kPTVwH37A9ykNyLBMAfet52QyQzDppq2Wo3GFDqflaAPbpKVcxA7P'
    'oPhZ1YxPRYaHcHVC5jk141iEtJpst4Ck556We2FArWfvU1WTosxpUH8m4TJ3a00xwgqi0iDHY7JR3iXmUMHqlsJHJdjURKL9Ub9BVZMUpagEgEqFdvKap3Ou'
    'fKfLXBWQ2HptxV7FWIa5IndK/3rwC0Fcybr5loqALg39JwQKTNhoPTl0zhcQbnHscjZTY5RvYt5JObiH0DTx9T6KoHS52WEqvD0dFHmT+CXmxueT+bieO4Kv'
    'sCe9YCE2/CYg6L3blmqSFwrYdUNJJkhNbi+JeFD2+W1NHewo5yHO9lWoxdxJ2kaTMGVJAwm1nWtISG23DRfAnSbXodhWE4/vVLthCAk8eYJEnxS9pACh2SPV'
    'aGkLNiqBX07n48n0UiEM37wan5XsV0BQxlQjuHXkgFyqYl7X+/fve1s67ksv1X6tpoI2Y6oBUemHM1OusP9qQN9ABvxT9YSvyym32lMKyOowcOttHfurcKXy'
    'uxmwWo23XAWT27hecx8CZNB+v4dmxOIXaSif2jZ4lLWSdBLjVPdjGLyKSE4uroaj+aUcoQSsxiP1ZAuN9e//AWPJNbVfbu/2SssuYn5t9EE8uMWrPGgrl4O6'
    'm+jCf+tT14ovxKFvSjogVKkv6ntXUObpUhEJ6DXg98mZgPgT37Y7zlJr6p1NtK4j8QlCIpFTTTOEUCZge5ZUgFORiuwymu34p8g2I2hqso7iBDUCi4mMmcMS'
    '586CFOW8THzq+D15qsb/Mol88fmFDeVjSAVLo94sWITgCwpF1bWlxZXGHXVKV9cdkIoOaFSmIxrGaAELulZhZhb8gjNvz4LtgHo1MzCgaEM47xdJvODLj5CM'
    '5pE/T3gEmRGwtcTd1S+AGXapW1PvYVv+UYx44kNsA23YEwubMHvEwWkjibRfi3keIyp6fhgtN3FyFQfExDvw9zgZEKWe97jL4F+GVEV0dA7IqJ4Nuux4YMCs'
    '4LKjZQ9x6nRVwUr66Xn9gQGK0U9w4avgM8WKnp56J/tNjvVpWHoM9U3ZYVFUo+pCN0zrMk4i8siiNt9ORjQhFUo/PTky5X6Qp0ofUmHYTXTgzHq4eqHGSOKP'
    'omapGU3QUhLGWE/N2Ik5lH8fI0GNw7537EyUldl7ZiebOOJJEn+qMIQNTArRxBHBGIaG+FfLDN/PiyTsVZwG5NY1roT90/4TC9vkctgYHTg09242CaLasa1f'
    '//Evy/fLmBimWIO/vVdxtuHbFyHQK2AqRgY9M2oczXW7Q2fBJmWH6tTbp2yCMcqW42Z4nwIfHXfZY0uhoD9cB+LU0SNQck/rWcLt1Z8E0fq7Gk8nry5bhfHy'
    'RsexAsD7YRiso62w2i6OeudiZTGarAInW4Gqku5ZYXCeQNiUtalZSI95w2wcWRp7TKg03WBCP1D9yv1W1GD2UFUDLXfyLnMOegVae016XADda1UDpQ3bKg9a'
    'q5ZuJvAeZtDHLTh41ilj3dfUBqnB2hcC4uu2TN0xuRnfY0ar5KZYjKd3XSjGcRmJ8Zex4FUeyraOHJ4p9L4ZqS5EVyV/pZPoJ3XTdaAzEZyjtHSmzwQZqWls'
    'qKIyhZNCwkzeSSNn1hO1rJKeYoyYohHinG5gGVWcimCaqaRdDX11CwOX9abkRERpnlB6Im90VlSBqDO4W77t9GOn8VHQjOl5VLMd1figf9czIXM9ul5w0qMN'
    'T/gyo1NddQJHesiR0UBRka3/urvH39j4DrCbk/MwvIX0mJLntny80JX3RXrDd9lNID7toOywPO/wCO2yWCGSi9C7B7rQmcfvFAYdte0COafgNeh4y4WQ3l/Y'
    '95AM1LbQuxLEqRSOjtiV+DkXEYfUM1mLrXzPgE8dRLqMI0zdY+e1w885qC5mnF5zLDk9oZBkMrGMApQA33r48O8kBhcwcgP5FBxoGS8E1F5sJ8I4hUwMwUKR'
    'PoRqw7P9cKhOf4EpHl4AT0FEKZ6ZzeKdHX5qxxdxlsVbOzV44mz+G5NCSiW9Z89PK+ugutAzNAjoUbMPfx3dAX+NJA1z5TmX1jXQcrl196Fi1FiqYSf6a3EW'
    'JLIV2eRy6tpX+FfS06ouuERj4Z4xVvojJnC6Q1UkQJumOAS+9txxNf0aKAQDF1PDEtr7MnPedQd0ItlRUYPIeBd8HQVZ7gtcyOv1+pWGqYR7C1Cl8CHdchje'
    'gLtmCXiffVnE6rYYaByWCaIbcFAMEfAzo9c8nqT0NgWvh22Gd7l8SW+BUFpNVG6ceIG4+ZbdCBCeDc5oh9yI0Hp3TOc9KKhgLhSf6HgjVS2qCVX1E5Kjju9P'
    'S/pQ6igk5JAu9DuVFkQOJGB5RVJpTk59NlFIszEN1ptMEj05g5iLyNaBMMM4KiK83TVC+9pjS97xuctuO9/idIUA51I9Mn+4t4Vm8HfpzzicoSZV17xDtQnb'
    'BqVuE0LIwDypq0ICKdxR0C8iibuFv2xGky+XUBd22QoPry5LBUZsjHEwG7Y1L3ROau7tUzFsmevGje4eqYNFETa6USxie+d2J+JVmxakK4GW4kw2CWkcj6IS'
    'vwdF2RQVyW8NGSVIlY6zsaci3YkAIk0MSSu2y18LjqcVKjfh4OFRjKqFc4y5Jw0cbWzBU2H34zaI3gNPjwd2hH/GkS3PNh78bhPEIaY4hePg8aDjErl2UfrP'
    'IHFWaoN4f8iOn3Vc+tcl+tcl+nhEWGLHg4J3EMHvBp2O29TQodx1YNS85h6F6sj43tXj13L8uqPj/oFlcsPDVS05VM4Raa1IDoWi8SI5u/s/a5n5IrVbwnvv'
    'BIjbepBrZ7cgFSCljwN0F2QVLPIQx7FJjAQ2+VpYJKQLxCtI14h024BkTBRE7QxiVKaClM4mpcYPnbD2R9YYD5awZuBDYfoSSitdgpgbjC4cY/TykGIEqFIn'
    '+53yw5S6pzWqs3PDM06JsUmCTZaskkWioW42HPB7XGE4ZXAbqXjOuWUpmdGOjbQ6BCv85650+1d2ryy0xpwrBHI7JS6yJEsfW2EX2NxbQTn3IdYMnh51rzuc'
    'aRwpVGrO3Lkp2vQdhDNJQ3uvGSDxxjJLOUzbuE5HJezEmA/RDnQZ+fxPeEB+DrZyyBep2O7AIh67Mi+nMfwFUc63GP5WWLYKSQtpxAt86JxuY53dQ/oi30hK'
    'LcGPjG8X6sE0g6qP27THc0tIxadRHWyIfq/Xo9xGz2kjNL9FoSt2I35q0tvq0ZmINA8z9TZRH4qylvoiq9uVc0kGPyBJgxOqXXkQ2SlWq6X7QJtzVhDNfeBP'
    '7NTc3csetc2Htekxudp/i3lg2v1K+oLrEABVFd8STRqeEsvlQGC7lhFTZ6qqtlTFCF3xVupdiXCgjGT+Mq7gbkD4RxtR/imZqNSylhGXks4CdRFXgZjhvqFO'
    'SPP+wX/o0asH2oJMvy19qMsqUOhIBfPqdyDmdYb+b7HoQJf70FXP3sDlAulz1acjkH/N+XotfHz5jxmMfLbS6jjeWPNeDu1feCyHA6g+YphmnBbLHh8svaD5'
    'fb6nHsCUHa/4xv3/fW6/z+31K0khjR18k+FDdFx0lMtwzdMpW6if5ZqZmyjMvgcgG5LLD480reealCkT4MenDb7f/4MKws/r+3+S60Rs4xuh+O5Uz3g50Xge'
    'QiJNPc02thFVPiPv+WynU8tYGj8ZoWShrIHKOKeFZ8fy5rPc7K1nKd+h2SxTJVuqXYdvXZKYrg6tx8hU4rTwRkI956gBKr73qAGgp1+6eC4/u9fJnuVEq6mq'
    '0+qLBa1l2zquyCEDQr0lKvSqa9ar3Kbgykru10QnI3qE0Tb2nJm+N4FNolVsqpWDnnesnqPRpcOYp0G0nmW3uGAQicqUaap5k+gylznlwVFf/lcfAPQtx8EX'
    'Zlj2es/YV1U9VX2MpMANTP6IHy+1O/v9inriJbfqsuY8yG2BFFuDUksmTDbEyJqAR+NO4HT71ibFvkeTQ2uk2NSquwDDBaneWoVxnLT1Mh4Wr3ir3G0CuFYA'
    'rgHkcvbhgDKddBh5Q65Tcys8jZjXEuZC2FyONUCeu5emFoaGNcxZ6QpOvxmME5Co3foPf9vqMke4ar6shOzo/sev//gX4zvsRsvO4zLYcvyocRpn9Br9tOcV'
    'RdETuqz1xbota22gP3Cr7S5zq/MONhvoG5+DO6JeKViUYkWTy28CX7yN8hTyIJA0ySb6Lsi9XrIzDfdMhWcyxcusAx3I7DlY6yP6cUltcKwIV3iou+e+ClI0'
    'XyRuFS6/6tr3ZZJ6kSW/1cU0rUWPR52HyEin6YskLaWjWOpiHlS/22p8pqZ62qc1nwSZGz2C+L9YzNw+mOazbszjHbD6Qsp23qj7CzpwmmU1N141IumKEte5'
    'V5VZkuEPloRTXJJP2oTWZvwWWif0peiuXfTOKC+dzFGxwwk2DmVQUK40q3Ol0uO+d45grW7hg75OsyOvIRSJpPkBbuNHW5gl3PGS1lhvf4ntfp5QzyaXnxAI'
    '7avqG8rfsNWaHar4DrR8LW6+2nTeQtoHjHLw28w1Fdy/dT76+QZU9ZnFb8J9B4EFv43s6o+rm/BRSQ00ruIwWN7KB7lOxotZK/WY5HvwC/75mL7KPtAtVh00'
    '643si7KZbWBtNlv5c1r9glcj1L80rWy+fk1o6H2rSY1daJnO79q+vT17dgWl1UZ/VqPugvCW7b57ofzVR0HvutNVMoe7O1U3xO3BqfBY+IroTKRLwOARVi0q'
    'XO4POIq+/TLVkhj6vvBPRnEUAVq7SqZTjzbFIhWyMoNpyms3zt2jBagr5Boljzbk77NgHfGwVuMO3yXbEU37P2M4eQGnxzye0laZZWKH29D5/xnQp+5Y2UgI'
    '3ZOlHMZ7h98DI4SRke7R58FWdJxGaGlH2S1l9tSB/hr98JQZEoqCnvq+8r9JaCJoyZmMwWRPBODq9T47ZSTv/UKRnMfcF86Xk78zDj44vGMXTaJdnoHP4f/j'
    'RcZv92OybzyOyK2U0mr3tNqJui0Oyyk3kq270kj9R+VF33RjelUWjNTVfaJd5zfqxboFtTKKLNv+XGnmBCqkpeKkUwths3XTYasPjDabtwEGHCHYZZ76zKI2'
    'PNDDyGIIdLbp22iB78vwRaXdqs4+7aiA8b9QSwMEFAAAAAgA7rYHXXrnp6uLDgAA6TYAAD4AAABwYXRjaGVzLzAxMF8xMF8wMV9UQVNLXzEwX1BPUlRSQUlU'
    'X0VORU1ZX1JFQURBQklMSVRZLmdpdC5wYXRjaM0b224iyfUZf0WJJ5ChB7A9Y3t3pMEYe5DswQt4dpXVyiroAirTdLF98WVHs8pLfiDahygvifJp+wX5hJy6'
    'dvUNsGcV5cF2d9e51zmnzqkqu3Q+R83mgkYIvwqD2auZR4kfvTqP/QVh/g0LogDTqO+T1dOIYBdPqUejJ0eCOV6MYzR9IeKeTx7QnHoErZhLULvVen14uNds'
    'NtErl9y/8mPP29vf3385/XfvULPVaKH9duPw5Bi9e7e3D8Sv2ZTzVITgFXj//pff0ASHn0CIU6RpI0EcWdTRDQ5Dh1MRlHp4BUPIYzPsoZ9jguBtHWHEJOY4'
    'wlEcnlHPmzIcuIg80jAC4QgK2Ur89Zmgo0SRgnF5HDREIQnuqcuCBhp0G8jFPkMELWk0ZY/IxwyF8IO9iATYZZZMw+mfSUTvWXgqXpsIOLEQrZkX0xmgAJm1'
    '0u8bBeERGsUBRgFeU1AHzDGPfYB9tSYBXTANRh7XHpAIgOs9pxiwiCxAwlADhNTHHv0FIB6o78ZrgBEEQoB2Qd+AgRooIh4Gcff2pdl6zPPILKLMH3OFZwS9'
    'RQu8IqeXJFJfatUcULWu8W88/ESCsAhLDSWwo3gTk2Q0wZg8ELIJxx7nWBpvLVgDhpLBueKf5UsC9bE/Gg+GHwCsusWtP7arGun25rw76d8NPkz6o4/dK0Bu'
    'Oe2OMefw+nr44e66+8Pd+WA86X7o9QHi8FiPD65vhiP4PMmCvHltzcnwajgaw8fPe/uVCXmM4BGmgAUHzjxgq9HlWa1z+KaBOkdt/uuo3gC46zgibh6w/YYD'
    'tlrwq30sAEcYVC2APDkBmE7LogjGwEEB76OjBmofAd3XBwLwnFMsAzwBGdutQwHYB1uSErhO+zUAdwTcGQvDMr6tA/jVeS3gbngMzIr1PugAnFBeqcMjE3z4'
    'nhQZ6RiAD04S4EsPF4nQ5uaBn4M2h/qSTBnWlOfYC4n+CqG2DoV0Lf0pIDMWuJx0SKIVgRSFpx6pff7SQJ/R3Z3IxOCPn6roi+XPPCHw8AN0N54Rtz+fgy5h'
    'DUAqAYHs4SuX59HRjaKATsEdIHBFNh6TKKL+4m6UQq7W0du3KApiELdSYUExBYVzzTj756DkMYjvFmi0INGIsajGNfe4PnQOSTISa5KHgId5OR2E3VqV52cP'
    'yEZL4nMplPo+hcWqIlhUlKWBKphSol5ARrygQRj1ltRza9X38QoyOnU56xscRNWGEFLxF6jYd8WDZHuGQyIAc5w5jGENyIKhcxPQFQ6eOIqglPu6jWwOwfCw'
    'ATKKfb+ks2WasFGs1PzaFskU2BwS6Ut5aQLbeElvEbNdN9M0W+IAokfkDwng9PSnRJQEiotj3rbPa6kwAfPIwJ+zlONJPdPubPLGNQG+Pp11ZxELJk9rIp27'
    'ehlDdfE9/FRVVOSWy9P3OJzghWTVMKtNgsjZZ+a/2hvx1eEKaqN/o+9u+2ejProZDa77g9EQDC3XCMcI19BhqbQt02YQ8uSaC+RdRZbIBdKeDcfjRCwOtqtE'
    'YlEYLynxXOImgmXjofqff/72N3TeH42Gkz4ajtH4li+lfYurWQ52ZW0mwGBu468mAtjL6Rl8DftBKHTfwPP3v/8V9a8Gk37CRaDkOEjnnpIlvqeMh1LEQuDj'
    'qwnMMB57dEXOFDCwB4xqVYWARHPmEFg1TQ/mXxYDIEZbBXlO1ms+GynnlDhpWTewkIXJJhaj7ofL/nnCQGKUGIMHOF9mJTOPPZCgZqzCqRZZ5pr50CNAjvJE'
    'PVkRwbExK2wH7bHVFEdpuCrPFfUCk3OpwRYL7pmbTHF52x2dd7c6Xwn54I8ydbL6NuQvVf8U51xXFIrprCtBQiiEyDa3hWjjYDmHFai8iMfh8nvR+lTzkfSP'
    'f6H++LvbwUcrlmThytUBoVOklLsXkoEavtub5Pw8H42QBEF6PPu0TbEzA5nRbdcMzhdFi92vb6WDFX0fuOCHBQmca1ZFjqPdJV5D91hLkOup5F7uAmVzH+J7'
    'Ak4KRKOnmqyCG4iJKGqgT+RJ1h38szOErpX3sj/K4Z/AfGUjYKzPX1TRVgzyI9D+idsKZLOmcxOsEku8aUVLlCLRJp0a6B57pqrkhawczLiVCdZdbGTJBpIK'
    '+qUlDgmhUiEjQUjRq6eMJQNAdNFZ21hDpz3sz4gniraCYfTWrr4L6L+ni6UHP6qmLhxyoFqDVqVYCgN1eg4qBexJiKKr4UJOSqaUNDwFn2F3QWw5zMcSCcx4'
    'Oe+EbsJ1Dp6pZ24tp5SSEFGogjHUq7WMB9aRyzhTEFa5CBdRPmYFE7QT70poJnw0uUplDR7h1bRLyCnkS1CRF/EBUEzCSA3VH/lbtKrOzCM4yMlf5oPED+OA'
    'GAsZr57qbbn6C6YIotng59qxDE4+LauZMhRyTYTeBTI0dDqeGsl4LIs32cbxTZorPE01ptOc01SmtpMkC7QhlsYFwAFUIzz2HJ88pLgYIOcDXokdg7zQCcwN'
    'C6mYjbfo9pyuOmI/YzifQ/qqHTbQYduiN6a/EAPH2UKJ0DxuoBYUC4cW3BmsCYuAxb4r90j4ZolcH8TeSRHgBMqOcM2ncPYk9s06HQsMZo0EnPsNfYS2U+yZ'
    '6MELxmcd9f14JZ6dSxYt8eqMeW4CxM2jpD9Of81KyL9l8GCSPpGcgEdHabAfupBd/BVJpEl/dXp8XzlII00Cvp0ryhuDor853ajvWzr8aeC75BEgD6zZU06f'
    'eKzwZt0/s8AXzXPaV24HPTEgXUUCOfLTCLs0DtUcC2iY2yMbLuGYiaCChKdBVPip15LlMmJrmaj/V6vR/9NapIevcBgpgeXe7oaqKV674CUpmzWQ6skjwG7A'
    '/INvWxUG/2okLzR4pupIUEvEV3twu9lKyr+0dE/7pUGUjmkAc3lM8rH24Ktp+K7LfZXoHb704DlZR8truZcqYs6wNSNO13vAT+HQn7B1GvkCwiyXCU4O0kDD'
    'OPKon88YreM0nAklI2Wpkxik3JJlm7MYHUDTCoiUB+DCPVKjSvIMQCpUMh4KbUPKq8r8OFJpdXNEbwvpTTFt7JK4bHo/POGy61QpE0eKj32idNoLCERfTVZG'
    'hmBDvgtI3ssKx1Z1Vcs56KjxinC8Pg6hmxpHTx5fWn1SMHhOA7n15gx8kFVDNNv6SXd5lUpdffqMypQ6PEZfBMwGWwpdxbB4OuXnYtL2RDTvO1mv08qUh8UJ'
    'jO86mCPYbNefFHFl+/RFB7lVa4s6oSBaXVPSyT1w/XoZUyjMUhAiq5Xn3ZmYedU5ZaSWNlXHcxVxHqHlF9Oja+KdzngERqaBEN8KFxFrxAoM8bVoVeEDX8zC'
    'E/4oZEza6cSM+r3YGOJYPZnEzDJkTNpAdMXPtrEfJcbyZVovL7bFDPPkX02QYAEQmyblWO8J9qLlJBBbJkmelF+l/luRAUyeGVeK2nhLrSqvKquNfO1s9BW+'
    '1X5zyL2qfXRoWUKMHB3zgcNjseG3jdk1fjyncsmsZgmVHB/zDfz8wXPdrO18DkTXws/PSxuWIsE4BsikS+ucQO0DobJsIDYQSFlQdxWHoqvIEBSmar+u13cR'
    'KVe15wRsOZIiJKzjerrkkV7GgcSTNMxFIFxxo1EEeIOXKrKt2sE12kKrTla6jvx+Uq6t5lVkwDStZqfDiTU7hWZt8THpgJYJrIDhUMnr87wkwdtilZwBDoQB'
    'OhsMkKJd6ocnUr0tu3VLFnvueMkenpfD8D1kcHFuac4oM4eYMKzOsfktleyJtkpO6mhSQuQPXVVFYzFThbdFXH0xpOBdPzsyq6FvYXHO7omoTflt51HmTKO7'
    'msbh8j11XZI/8y88UKKr2MPcyF1BQCJptlvPUCZCwx5brT2SOoTL71NnVZG2dVXCBNvWEnMl+x5Ny6zma925xgufRrFLDKEVfgRVVkDnKxJvsq4auWBWFOnN'
    'nZ6oJvI+IW+X2JchdGOx6wUJuyFWl6L4bMjHC4hQc+iuuJfgF9ZuJUWe3toq2arLn9jpwipTr4COG+sxqJ5kfuBPoq+x08PbgqN+5TWmXGqoZ90UFR1UgTYJ'
    'glHF5pM5G3tR2ZTbptx1A7VANrl99JGGdCqOQnUQJ1tTRtX8jpjZM7Mss9Omnmir1IGanprniaSxSgQys7z7HqPua7Lss9lk03ZLibdw85u5cPo+L/W5Dz97'
    'sdmUFrqebI75zv+dIsT3/anc+M/f3oDQnuDFgrj6+Fmm2GpdnwwUphtthrlO2A0dk5lzi9A6r8ilJNOCF+8+5bsRu7fftH6LNMgbcuXySVosvIeWu9YLSfHX'
    'wosWdtDqi3zKMxXlcRHlstui/PHJulH2EhpqHf06Ih8hy8tKTF11LSPETbGN2A3zKC+wBazJR+beAUCGzJfTLQ/hdRcjLs+K/YiUM5dcESDZWbYWwO2zpgN6'
    'dw8uOyQtc1PN8qsmVYhZfjWNzEGqZVcaQh/bgSl2dvPsfaKUTXUyzJjaDrzChKI3crtQFrpjuvCxl80upz3m+4CYHDjay2dmFiMcfnJcMof0kDmfbDblDX5J'
    '/IIQd8pbtVlA+eX+5Ea/sJu8yo/XLEQYauXFN5oE9haxH6I57+hCca2eeQuMyD2N8IqfmwTquj316YyKq/MzzBxzxHoHc84vL3fMYerGbGe5ZXJ8KnCKyiMb'
    'rzAXlxIUZnsA76rBWnuUPay1Z7K+dSpHZMXuXzCZG+s1eyvZCtkXhJnWocDvoVzlF5K05AVBYMTPhZOgmfy7Ae+cgmgKBWZeY5ApwhO6Is9IRvrW9z7UThpd'
    'YuuRb3P/RVBSrKcukBckUNs6z8pEoGgUcM8Irhh2iXV1949aZ/b2tySsgb+OebvP/wNJrph22/fMRV04jTJiYfpUSU87LrBTcw3jAif1xfT5G3zOXjPzuvAV'
    'L+9OdVUzvdAuSdIQAZYWOUkomZFTWIhnSpJ6IURSg5k0U7wGJTVasniFkJbX/MhNnIZSf2HUThaY+t5/AVBLAwQUAAAACADutgdd4xByxv0SAADBRgAAQgAA'
    'AHBhdGNoZXMvMDExXzExXzAxX1RBU0tfMTFfUE9SVFJBSVRfT0JKRUNUSVZFX1JFV0FSRF9GTE9XLmdpdC5wYXRjaLU8TXPjuHJnza9AsWqrpFjWSLL8+cqv'
    'VpbtWScey5E8s0m2Xk3BImzzmSL1SMoe79S8erf8gOSYS3LLIad3y3X+yf6SdDcAAiRB2p4ke/BSQHej0Wj0B9AYP7i5YZubt0HG+Ns0WbxdhIGIsrfH6+hW'
    'xNFlnGQJD7KZeOSJfxrGjz0J0AvXfM2uX43yJhKP7CYIBVvGvmCDfn9nNHqzubnJ3vri4W20DsM3Gxsb30P5xx/ZZr/bZxuD7s72kP3445sNIPs+vsbRFAn4'
    'CaP+9pd/ZVc8vWeDwQHTVNn0+o9ikQUPgm0wOQSjMZAMkZrwJfc5C+MFDxmQ4atEpDA8X/CYoNjY56uMs1jhn6Uhj/xLHomQic9BmgGwYCuecLbSowqWxUmE'
    'ODfh+nN8kI/G2PTob0+uzj5O2ebv2WQ6OwG+jqYXH+b4ezb9cHHM3o1n44urs2MCGX8cX0zGs5zAlKUieQj8OGGLOMqCaM2hJfJjxtk6Chac8TWMHfgc5pLG'
    '14mgwdkmW4Q8WDI/Ttk1X6e/U60IvQkzjsMHodsW8XIJk/B5Cusp4H/ljpgl8TrydXMYXIsE5cUSgUIEQSTxLRBNSYRvNqRwJ8Cv+JyNYTniaI6zWAh2yG75'
    'Uhy8E5lqaXsuOK+jqVyG/EkkqQtRdRnY2bppHNNrMK4ehWjCsfsRS+OtaGjAUDz0zrFZ/ijCvFsHACa/D34GZTmNk8ldEPqafwCwKX88mc3PpheA49XumI8D'
    'T4OPJ1cA/Wl8dTWe/B0ize+fFN44A6W+zyFnJxfHJ7NP86uTS4Q7i26CKMiepHqn1UE8ayWn59PZHLC+vNlovQt5issxicM42erdJPFy9u6oPdjqsuFul42G'
    'na6GmvEgFX4VdjgCuP0u29km2CtYfQfQFkAMR0ByuC1pvl9nLmoDhBns7sCf/X0CnDzxyAHXR1rDbSS4ncPN4xvH4IO9AQ4+MLDv4tA1k60hDgs0B/1RDuem'
    'CZTU+IPRloRNQLtcjPYBcAsntCNnfrlOVqFwQO7vIbVhzuZXs2hcmsFDdsPDVOhWsBk3gfBB6UotszjOdFNCSkAmTzfdgEbMsyRYFRvEClXhy9d8UP+BRwtx'
    'FfM0M6yALijFGjuZMv0ztDPQPdBdGVKCDRjA9yHrG5pg826DCKhAcyqypch4xq9D0f7ytcu+sE+fyDWBot977Ku1v27WERkalvIHcZnEK5FkT+2Y3EYXDRk1'
    'AEIruGFRnDHZxbI7EUFjKxHZOsEvMMLwN2fjFwn3Bxiy2gbWG2WEJCudv+gxAfWQRUGYD9UIqvgyTZol+lOdrchqJ9tlDzxcixfP+VnJlVkDbmmEOubAdYAP'
    'E+MwbCP6DYirRDYQKQsi8LpBkrZzuXTANSF/KFbJMZgy9dm75Al46nwORLU0Y0PSDKNptlor4DFsayaJM/yvfnLYCxOUgFJU6n/yL+knRDuCJ9Yc6oTyEIhH'
    'DDBoYNm3APcEYcche4yT+3TFF6I3WSc4zQn1AKBcKg2J4pCfvY+K3Dz4VaA+foRJxMmwB6Fce2sfDM7eaNSpXyAZCcntSxypgXJO0G2Cx0mCa7DSbe277BBK'
    'InsdVPMsqdeGhZySZRAsESTKQGRxtF5CGNJ+BQNEy+soPZeUtHpUTdCSZ3ewWHy5atMnGLw4aRNWB4xul2118pVVwigRqZvgrcjQ5bVXpKFdFsEKmRkqTT5k'
    'spvWUH4enAaRfwrqmskAQuOp0Stb4AAWDEIYGOqcX4sQJG/6UAXA1tSxGKQTDB+F317AbAxzKVhZCpTUFLC3C0EHNnuWAZFwRfuhbb6SmSQo9yGYcFi46La3'
    'XsGmahN2DwewpqcgwaJDOHJyNT6eetJIWj2zk8nJ0ZnpUVQh0vHbBAW8Ts7HZ+9Pjj1aQ9TDDvvzYZMslvxeoKfL1wuoic+Aq/hT4AmsBkzkLALuwQXSxvJO'
    'sZUEQ/29CwnkIT2P9XqSVt5Nm/OQfTgOlnJn9nsYL2yOiNm+oXMEkd0t6aKMCDA0oCCtZwVeDuirhEcpzWPxhP60N+gbqDjxRYIsXAafhXK3qu+fzpDPXCn1'
    '7w101ApE2VsNgoLUZgtyIwqWi7L5cDahDhKPhOnJlhn3g3WqBCHlAPbJAsvHoqGtoWDB43vhGGpOHTSUhOmR4IzcMBY0nRU57QytzrtgcR8JioIHprmWqRB3'
    'X4Una18iJH7l6iHb8+aCWmDsNweyog0qMTC4tYs8yEFUoI2KW2gr6xAF2jnEaUyzOgGDS9+9d3F2x5dHEOgWqCgu9wqNPycctjRZbDL5qivXp4J6bVi8OqSZ'
    'h5y/0K75g0pIWqdq6xEkhsutuVYDuTTUdq5WgchTyxFPhSUSbPtaZwRElK4TcaqjYLAFEBwrg5fHxmRf81/5FHBL4OmBO5zKJ4YEFGjZ0nuO9Mw5ONrevEXa'
    'f2WC8tFN97FA8TzJyMbmgYxhzp0y6QagQqnB7BmgXLmdqaYNeBmnAQndVvnpzQ3EsJDsQdq4X6JcMZuwMzaHkBqB2dgalYAb94kFl6vo7k6JPWPoKEGi8EFt'
    '9Kd4nTmsz3mQwl7HTikUCdg7DcLwOEjEQs1WbjG7sfcTBIq/wqbjoYVnGsdhcBsthdmgjq7eBE+sEgv/I4a6Cwd2paOKe8l9H3xqyThvdwogeuuapBG7c0ea'
    't5Nb8377t3/Jj8mkfFyQQ/Td09lJPcQWQNDZWj0IaI+HR2zf/nk8IyghQ5JCbJ7bGak54CUCpQrA7UjnB0W3b3ZVeesWXX3HwtV+QdIg24FfFQrGS7TKbq4Z'
    'dXozwWig5P8oXzKIkgv8UlTzjKnW4LZcNrflNrstl+VtFYyv8Raq82tNBlWT2mZPoVxoFZhR+FiOz1IAyNfJTMkOWcWq3kQDkIp98WAujoSXwyJi77Q2LCsd'
    'Au132S4o6g5lDxJ37gxI6HCoDOOO34ogdnTSG+Xd57XuvjjSuR0q0N4k7VVBA+6XgixUAvqd4tiFXb29hyeHz4pDhhvN0ujvNEtj5yXSUAd4boFYYnjBZF0h'
    'edMkVRDaPMnd5iV/wRR1fNcwv/rtJiMhOuFrqxjEPvUjS2I3lA9iKltLnZZrp1E4j9Sbc/UMjQIHhzX5sok8cJXGFopXNxEc2250h1QFiEJUVeKrElgV+l86'
    'u7pYqyD1SrRVmXMZYxwt7uLkMg5oGezzoX4PklD4UxnEGanJ5EThjPYqSM5obWtE0dr+sAL+ApuKAQjgbw8akKu2YlQBdibABZCPQRpch9YBdrE7jxkHVer1'
    '+XEKI05iWFRYp8gVPs4LADKJLTT13geREqu9bsNdzJt3XPD8swN+tIVL4ILPmS8f8P+fpviDHVeOXzPk96f62t+lTT41rfMf5Wy/hr0syELxTNJPMPlOvcJf'
    'Xt7cmAWhsPqGhDsB6ssEaGDgGnMfCWI7/tL9tFcAqosiJETdoUEIHBTIKNYHO3mrtYm2jTSeEbcvMh48d8gigXKBH9NPz3Q8J3I6IdfATTIf7luAjUJXMFrq'
    'M7GIlytwsTxlkAKK6wBv5X/7y3+AkbjlsuqAs5R/+y+f97wifnlBrqQrVxDNpzgWGb0g/WJz5SBH9ZVWS0vSvVw1Afxd/Gh7JnXITg6wEmuUPXK917SvDjfU'
    'MZi0HPo60YJw7NyCVy+HEnKzdqr614ilNE5NRQ6k+S9sP31wHSdLnrWtzfiDb+3HLrMk5UuiihFNtahf8s7j94dsizIsjHAaVC5mRzEYvm//CV+r5NtfPwfL'
    'GOinWRDFpHx0xv4qnc1rSQjfFd9YLlYp2vc79BeGJ1iCYNV5HEwSAdlNuxy/UXJKgGfRTayP52G305464Sms2BxzUWKy0GzOc6brjG70W1/YC7gbdRjmwp0D'
    'LBVpS1Yznt73fIENw95ulxUvKDE3k+r954J+031Pees42irXpvm2yldLb5NHWbxQJ7qq7KrC23YI7+/X3K8R3lkkZQfCqzeqJLEWCYNYzGWnfkM0sFyFAjKg'
    'gymwV77gNQI8LAqwnNdY5yTPhIj2UYbaqw03rVSa9dPa1wbPVGwQC+anXiqrFZOm8m93/qU3l15Ua5RDU7lUNWDyVvWDhP7pw7F96WfRUJplWmTiNF9gkEAV'
    'T42Xg4YhmtGhTajMEkJ41j2hjdh8sadkPTPVLraTsVeizGwxj1MhsDwIKWawVW7LNYVagBqdruzltzvZxKtrwzFOUaNae9b0592yCKJyyt909Nkq33pYhDvm'
    'bE5LpVA2lEunyIwctMpGLRO2xN3LyLFec3IHfkldRz912WPgZ3fWYmKHVkr8dou2EkLYVTPqqltbbXC+zsuJJ6ovcCBiXOVCIlYp7epY2hQsyDEQr0Ud+hky'
    'krvyzf7LL+hL4UoJzgQoUnbERn6yZ00KO56Rxh7e2XZqEOukMQKskUSrHL26+FBnvY2M4AHj1rDKisbVUa+nkypr5FI4ZaPLrudUYkhnvZ1a5IIg8jRCnoYM'
    'Rw2IFtd7neYjO9ohtpnLby9VEUYgHrGMqVpxRMpZLIZBqN4/sE2GTA73h1jy2TcYdyK4vcscKP/I/gZDmn1YC6xaHG31O5U9RnzhFY05ioLpOY+iOjWozsUo'
    'RFXb/VrkZ/aonFthn0rrdqVSBtflbfN+1fhLumTDu6ZPXbZAPCxOC1R1GpF9JyRBMObtjlX6RtDuWh9JCFyEzWbJTdDYaGoQltqvIYi7L129qJopBxlbjlb/'
    'C0zlflW7iwTce0Pe6w73nsO2t/V2xw5ddRFZTaVZy6JTk5DNTibT95cnF/PxnB1P89yskpEVxYaCbhIb9L9AbFsNM5cUGuU2fA7bktu+Ehs9RIBoL69eNY8R'
    'eLbmYfArl08SsJnfiuXvGIeMENLANIBgG8KhBV/GqSLF8dYwFexPa4UlhYvId2IB2SPDHPNBYL0mvc0QPbN2KWSbkZ+aJYH1WNzZU5A3icxr/+BvdFLPpEUS'
    '0aX+7lWWwb13KW7XgsUpG7Jr/u2/ZWqL7yiW3/49A3fGxJL9kKaeurxU49APGSTJK7PKcLAtPa+RHe8UZa2Em5g0u9eT6Xdxf76sRKVSvPF8ucX2q8stipFx'
    'EEUi+Vl5EulRwHvs2YfHorbyZQKdFNxZRvM6jujs2I1xhL0GxQ4PgRb6+N2uxVMJhmjDNunvl4AsdoMobeAXeif0cCYP7QmB7DF+uWPPQsSIYC+xBANHZKGR'
    '63yZmVRX+ugl/0whkvLcmxAr7XY6nWJhC/gUXenf0m7KF+kCVppD6mF8lZyi01fJeErjVD2WSahlNgCEYEZtObg9XLXC2uJK1jMYhiS6zYNdDAeb7P305Ngy'
    '4/JgC0+2SnDG5pdgDd+FMjvv3fjipykQPplfjdnsw4WnDYRZLFkSUbG5rZa5aDcVrFadBIRI1wlHo+THQWrVsubM1yJKc5au5WmdNillEnVzmskDPhiYr779'
    'NbXMYu9l09urK48vmANVfQwjWpXI0F6yAS4w6lChZV4ZgmVGVLUB/y+UGhkQCGTtkelsVBZ64CGnLnOwi5AM7la3yE89sqlPMtgoiBF5j3aZA5uqDOlMwQVS'
    'Pl1Dxiqk6zGFTXhkSAJQz87mrsr4YhnexAzsFQTReRWZI4tfryiUOkLEupPYTHD/6SpWVwNykk0CktN2p0DrlQ/JnnwSd7TOsjhSIYN8lWDpFXXSJXP1WSLa'
    'NYVdeHhnnTQo/KZCInvgHJBeuT4EWHQXM9g9S/AuC8HC4CFRr00Xd+KWJ4zTi07ccGwsYywIoTL+J/kCBciAnUTUNOVJELOUB/hCMxMhZ/464fh4FfwcZ39E'
    '94WPSZf4zvOaqyhL8u84xWzIL6VwCzc0cnL45EYuufNxhnzWi695PSrCR/PzfJ2IPEiqObyzs6r8sVn1+UrDQtQlBQBfLONt0c/qfUWrVZ9va7vnUEdtey1F'
    'qbyb0yUpTsYr12il5yiFwKz6Is+m+ao9jxGnetvTZeVN9Toy8oVOl1U5rznYwHEs1fv/ULv8HaVa3tIJfZ0e1gm48IjKrWuvFxsaSs+47+9cuzLPryf1USSp'
    'jFfVM+bXG30kcxmHweJJebX8Rf/VY0whuoqularTW2jl7owdcquLL8oKY9mq5xVAW8Lic8UXvQFoLr6XRuHlh+LfUXVXW6Imx3bVqX2/IpGgGq64bkCCd2O5'
    'FPrmDc3rS/fsYWnPFlZVl2aWFtt2X46BJnccxvHnwS1k3M5RDyAgAL+atSv804qYf13g4Ahi7qt4BoOJRAd41ut7VGu63pQQl+ClkyB76p3T7SG9ZdtgW91c'
    'n99sdCymX7gWGL0kcRiK5DzmPgVjyjr873f0m41nFussWq0xCcB/IkTaJuvRZ+uV1pl0Ua20U3XUgmvPD8OplYJ+wim0mH+MoX75betUnQtdyGtlqNy+f6dc'
    'TFRBcUmRZZOMlXoOjoN0oTjpOCGsez4VeriFaKViZuOmC7BGWU+ZC0gn3dMu7TRrJ3yIrvF4BOs0zW6wtoIcqvPmfwBQSwMEFAAAAAgA7rYHXcOl+o+sDQAA'
    'iTUAAD8AAABwYXRjaGVzLzAxMl8xMl8wMV9UQVNLXzEyX05FWFRfSVNMQU5EX0NBTUVSQV9HVUlEQU5DRS5naXQucGF0Y2jVW+tu28gV/i0/xYC/pFpSZK+3'
    'KIwoiNZ2ssY6tmt53WIXi2BEjmSuSY4wJH3ZRRZ9iD5hn6TnzJ0iKclKW6D5kYicmTPn+s2Zc5gons/JYLCIC0Lf5CJ8EyYxy4o3p2W2YDy7ZM/FeZ7QLDqh'
    'KRP0YxlHNAvZUE0bJiUtyWzHhXsZeyLzOGEk5REjB6PRn4+O9gaDAXkTscc3WZkke/v7+7vTf/+eDEb9Edk/6H97eETev9/bB+Kf+Az31ITgEfb+1z/+SW5p'
    '/kAODo8J0h4o4kRRJ5Y8UpBUJkmcwkaUcJIzmpJQxDTiJKOKzujwWE4j5ImLh3xJYa3eUe2vCH/g4omK6OqRCRFHzFI/y4FySFMaUXI5uQIFPTLY6Ve+gE0E'
    'YfIlTQrkTVEannwQ8INEsWAFRdYUs+QsoYQuWUZzkpcLJhgpUyqnhZSTey7i3zjIkZAlFSiN5lJRPYEhwZOECUkrKgUFwuRXmrEECILmMvrIFhRIvSlgLI/h'
    'l1PSGeiFpzMKSzIuUtgEdtCyghCCgVygWPgppUVpHnkCogNnsHDJhRKFS2o5S+PBPH7mJLJahr329hMeAunrhL4wkZMxWcCi44+smDLxGIesG+ihoGfm3pSZ'
    'Hmya7kZxhVmzlERgvqY2vMDX6sHNuju7mZ5fXcK0YIOr3h0EZtGP16eT27PP55e3Zzd3kwtYPBoejBzR07MPkx8vbqcw8PvefucTff5ExQMTpzH4SSaFODj8'
    'to9DcVYbkgOnaPAi5tk05by4ny4Zi3BsKEenT3ER3k+iRzAvXbBpUUaoyIMRDl4tcR1NbnhZsGvwpKR4MTO++QvOuGEhWOmGoS8b8aYs5JmcczREMl+cOOw5'
    'LhSXOJyzIgWXLegsYd3fv/TJ7+TzZ4kIoMOHgHzxbEBBhEccmNMkZ5ZeQpe5FGdkXoWlEMCS2qXx5TTkAimltLgf3kNkmFm5VBCLrMbMAHi8lnHSyIYbP+Fp'
    'GhcFiyYFTBp4W5i5l5O784+TW/CUz9eTk/PLj9q0oOMsupWRhFvD20KUDHX8Hc/z1gFpmiuIcvfe0/e8zKQgJCvTGUjOiiLOFt0M3LEPMTynZVLc0QSWkTTO'
    '4rRM4Qd9xh+g+44i8ogTkDxXVLoqHjBwJkUh4hlwIEn2cE08NwvGJIsTAgoFPXY6hoq/K7xnWQR/A3KVIlMWCROaLruPrVzJFTUBWZaXgt2WGchnucq7Tgpq'
    'X2qFdxpQ2bgwxJkXRiYIh7Xw62+gUw05S6cpJDeSqgaqT64phpGcdITOHI4NZXBlgjgDwI9F3nUa6ZGI4/Zgu1bbrtqzo2dOV2fqfVDz2rry72azuVPoxywu'
    'uo+gFi6c0bxDakzu5OA3Q0ge9MTh3/tkBPuph5+0+7lFYLAFkC0BUd4iso5GB5Z/7XIg0qoXeuuRqTbWlfw3YEDPy8J7OEvDQp4WasLwxLxyO7hZmGnYp+MP'
    'cRZ9ANMUJ/dxEnWD7+HAzngc4SbXVBRBq/trgPuY8BlNzrOIPXfXBDDK32To4KRCRh5dklggrdkBT7JJzcpK7blXs1+ZhMjdSWgeLCVFQy7XBs54oWXabEwJ'
    'KQAe3YO++j1POBcKXnqt6sSAy8GnfH3GmYp5z9ilyDla2gzByNM9pph6RFpX/fxj7OTW0YaB+bkvYxODMlZRKaGpE9T111cD6pXHmBmY8lKErHWdPChqy76Y'
    '0G9zFcV+C9Z3HNpbWKgo3le2HFW2Mf9YBaofQ/BxsPyqCaVVm+2USjQ+z02i0lUvtJ+ohxUvc5MDiWl4aCIvwEfj/EoOtN0St0V90YrH6rdaunUuEUBGnqlT'
    '4weACWU+ZVXv2U26fVkyf5J9tiavWjwH9rPFMOFPYPWCq8duk3zqOABOg0B5Aahar54DJ+boDrjRc59A8KGkPecmVfn9g8KGV0HFghU/sJdW7nBlowU8NRgi'
    'gWYZYaTnnMtn3G7Ywvwf482+eMH5Q34RPzCZz51Bvuv55Drznud2hTNb5dkJtTr3i3eAt1tMO+GWNvhvuOL/zPUEqodJ9VjzmeOndT5pWPB/469NEm/lsNMi'
    'ThLIxuPIc1SL4eoS1engSaaeHEh7L4/P80k3+I7mzKQpldFthF3Pq2ALSLmZUOl35SwGFzCPbWzY8dcwYm3vXVp/NpR+IeMKdjdznYc0O4cUMqaJJtD1YCBi'
    'OVyeIbkvvACrJEendgYsNLGzogpHpbeeGW4SKrijLhMGCnCZDHteJnEY45112wTPUFGZGRjB0VjBmeajTl+5CywRrYuXbfmZIqXX56m4rMzdOhdwElokd2MS'
    'hFZaffDXh+ojguU8eWxak5dhCHc+NbSNnpaCL4Bc7qdm24p4rdcqyPSxahdqKlQCH5MsczZ0ZNTpPRpfvsOCjXpjV78b69E2D57xPL96ynJ1MZ5ynnkubDzJ'
    'Os8GgbB4on1GHyg+yBpDyXoPxaJJQCoWVIWgoI3VjD7GC4o//wZIzZ+62qMab12VWz9WpRUKNQWRLDsB3F/yQk0PbLbcRv08P+VPGcZpW2QaonqeT3GDElXR'
    'S902tEY27uKvqezVZN42It9V5gb1eKEh2OwV7nAtF9QcAtiqFex+VsR/aQK4vt7ZYwhINEBv8+KgBq9BlVJFCixVM3Ebp+wSPYwMmguRuMtbr1y0pmbbjEbW'
    'aJaoz9WKZU5k2T9oPxK5YProUtlBnwjOi75sBblw5vN5LgHKZB1clz8Hcrp93lwqUpR0qUg//OQ2ilydr6lw5PlUWikKViuqMuPdrqCo0uMNNcUjWZzvHB6O'
    'VNlDWd/y+tarSdbq/uC8duK7Ctft5RK/poHpnSwRqIt5e11J37711Kaaic0oYc1gQP5aQsxzwvVKElKgvqAkjmAPUFTEsLEUJ/e0T3JOwM3jgqY8J1S+JHBU'
    'g20ULRA6xJYYy7E9ROAAYQS7CRE248CZwSwlTfGOEUdAYQlagZPmOU7lPkOl0Iq0LmFtfv5jXJ2/hTZz3Wow9jCKOEvJLJ6XIEHIWd4H+QTHjuJM4KkBboid'
    'saVgcyaA3SGZEL4M5X3UiqYILQEHAS2SY69HuMQOCjBPBcHTiiWyzZbnZRpjJRiYpYlsE9re29Cvl9SrKVZSJc6+hyWtHaIqbKmmDhybK10OkxnZ8Wqvo3HY'
    'djxqow0gZTi30rXfz929WIk5GJPDo/pdT1tbXoRV4FmQkiFrukuSiAp1BxpRpW9gugBV6MGas67et9R67znPDYY2YecM4tDe4XWo2aq/d5vxqgZYUm27DzrF'
    '+DchNYj3IJ3dMdkQs5VEuPpE4LuF1cVa0JdMuCUYel3kCUVBQLNDQ6Xft3JEPXgMduT8sZteLzp6XlnpCnrh7qmgMsVtZFLOOHx4WZGvsqImprxUyFWWZ619'
    'I6mUyzjWeIXHmqCKmJLS6N80vLxWUf2w6qw/r1ZaSrqI7B1bbT0n/DMyP45G6oeysEJtwJ3U4J3EcwlSENOCkpziNwE5ngwJFepbBgD1BKJjqEhgmmgNT/Y9'
    'Id8ZZegxp6oGXRmXaHYNHeIqjFpiMGFUmI83uoLRnGcoZdVcJjY2tZ87tc6zWYodBZvyTdtvDY0flQR9JKJO36Zu3ToH0Nl8X+V1vR0oyIsMBIDVzasJSHVd'
    'wjsryKtpuMLOziRc3rY7BW1VS6Klo1jOkji/PzHg1bUwphAES0ZJQTHhb/I1h5Hm44dmx1vBUoOGCEJ1P7RHf4OHOkLeFxMWhzRG6t53AwIF2zXONfZsbp53'
    'DtQnLfBDnts9xwVNlpA+jskBXB9k3LHnZXegePuT6xGOfA17y2cJGEyKUVPD8QUTy26DJvpq016b8lY633qLXvWwq+hVo1MLHrTdQGqY0MiQvWXsjBOmZL4j'
    'TJgTsmn55suVAwrZVlwJhCEO6fbxLvQ9EJE9AVNSWN1nm/Jy7yv4qN4gfS+x7efdSVuIWuMfzbBVLpELlXy73N27J4rqp1NfUVNSSFX7HAtTN4SvykY2V2v5'
    'OGtdKcWWpRq+/PI3Wa+SbgWuNcTSKncq1/DCu12b7lOmBOvkUV/ffFqLjXI7NZd4F6HquYFVzVbU71TzHJvG6rSpxry2N5Cz37/YD2Q0Q3LQ0K+SDy65/VhG'
    'VeRbNvDvFmtuQ3pHN7t1W3mnVDRaNn7d2dzyVYkqJjOjDu0KeGX/urKwx6f9TtK2Edq/i6v79leF5g7gf8No9PIVh8fXZ6l3cJdVmZn+fndXBL3mSRy+uN53'
    'wZ7xdnMJngb3iE9Yjym4eMGKw1ReRORXwO2oGrFVd9kGPVY/k1119fOMaru1d1rnwPC9aXxoIH9N62K1/l+Rw2SHK+L5fcvmrunevvc9ve15TiJImo71Sds1'
    'QlT6w+2tYyDRSvhGfqGeLdbTbmsNq2uf15luv8qvGEiNyt11a9WoRrLaYASATLBBNI0XWLJrsoiVoWZbSdN99D78HngpZowWdbF3OcvM59n7Y4eOulmsR97W'
    'voBvJWZqLmwJCtbrvT3kJ+D69OzirF5Na1uDgvvPDxecYpfWItR/Al729jdE03m2LItrwfF/yCiE9BOgVx4X0hW1UhtjW0ekSdVgO5e4yjWVN/ZcX+ODPlTW'
    'ZUHQq7tXb833x1vopVJOW2XZ/zaxMnIMmXOoOek1znDlTVsyagZIV0LqeUAm4mWBoALe9OKDiUO/3t6/AVBLAwQUAAAACADutgddyFRnilUNAACFMgAAOwAA'
    'AHBhdGNoZXMvMDEzXzEzXzAxX1RBU0tfMTNfQk9TU19DQU1FUkFfSU5URUdSQVRJT04uZ2l0LnBhdGNorRrZchs38ln6ChSfyJAcUZetqOKUaR1r1dqySpKV'
    '3aRSKXAGJMceDpjBjI5sZWs/Yr9wv2S7cc9FkXL8YHGA7kajbzQQxdMpGQ5ncU7ojsjCnTCJWZrvnBbpjPH0HRfiimd5RuP8hC5YRgMFECQFLchkY5TtlD2Q'
    'aZwwsuARI7uj0auDg+04jdgjGal/QfD69eh7uv/99nA4JDsRu99JiyTZ7vf7L1nw7VsyHA1GpL87ONjfJ2/fbveB7Ec+QSY0CfgEZv73n/+SWyq+kt39Y4JU'
    'iSJHLtKczTKaxzwNEFtS+CwoYY9hUoj4HsAAhHBBBKMLQSJuKCsKJzzNM54kLDuWuIQ88OyrWNKQBRpQMaTAz3n2QLPo0z3Lsjhi66GEhfiJZ0kJS2JeUk6Y'
    'CDN2z/SGgpPzDH4EdnrBYe4Ln9GIZzu4czdFk1yKYDwgEU35gMzjfMIfCS8IzVhKnUA+Tb6wPL7nx4Slvxc0ymhmaJK+kidbkKXWFFlmTLDsnqYgrITFeQGr'
    'RFxIUjlLUODLOaCQJJ6wLKKgoCWVMNGM7Sy5iEPQh5Q8Bya2+wkPaUJOUMwhquoGqMchI2/IDKCO/8ZyPdLt1IA6PYN/ldAnlokmLD3lYK+LVYu4WcQwOEtJ'
    'BOA1teADDqsPB3V3dn1z8ekSwDpa2cbCUY5Ki3e7HQP++ep0fHv228Xl7dn13fgDoI2C0StH7vTsfPz5w+0NTPxru7/1MZZOcxqLnKaS+YMBDtPHyvD3Ixx/'
    'RwV7z+LZPIehvUMNakf29w3QOxp+9bB3LdXy+J6les7v4fv1noZTn0cHZvoD51/Hc0YjRAqOcPhqDuO3GU1FjOoDjHc8LYTZwikFYWXjPIcVvTnJoXQRMHyp'
    'dymiA7VwnMqpD2qhw+DQsuNGd48sCScKydKfnu2NP55dj38b395eG1F3GnxVEegMWqZ9abUCweZa56zYOmX2fro4PUPmxid/N+zdfH2a0iS5Q394grE8KxiS'
    'PcnAEG4eGFt6g2P0d3QduhTMG6/oxM14a6PU7xEJlhPMjDJJCuU7MkOC3rNI7QPUmMWTImfCTIZFBjxIHzBDCRV5xWpHbtlpkSp1z3kW/wFRmCaf0zjv3oP3'
    '8wzcckvBuWnAv5OT+wGkKg0Y/GNARgOiP35GvHjqIQUf6QzIFhCjfpC+N9ol+ZylALeVMQhtKUljyGBbLI3gfz3k4SNT2305W2NdRYxrzvOuYzicU7RkGUkU'
    'QHBihtwKDgrCrPs6PoeEex5nIj+Zx0nU7bwvFhDb4wgXuaJZjgGrmZkJiFqyguk70YJIeS7TeUIg1NuP4wsx7nYwsyad3ipxqCUyoAqbUajPMjiQNqbXl6i4'
    'Q/yhlsXwoXZSXRlh7NKALBcMrrJ4QbMnRJGUaqPPka0hVLXdtLGf5nE4LxO2G2uXvxGG04G/hGO/dTFD4LnFYgFFziRh6F9rKDy4woogX98IdCzY0qtbbWAa'
    'tc7f7VwIZADQ/60iC1LATeIitUx+/J6KWzpT7A5s+lQUAPMZFnQ40AICe1wpcAsHnIFFS9GbseA9g9ppTn4kIzle8RyN0ib6KahOih3NVUvdi36SYkk93mRN'
    'zqWwWdnqhIm89OEF0gXN58G8mDEJPwW9/jbQeo/BOpYUbKtb1wBoDzQwY+C3Jen3oHZDrmArDZZlmda85DSbsfxaRYV62DFgkWNXe/aWso6uIxBccZ2ahhLI'
    'fvdc4FaIsMWR/AU8Wso/lOVi+dzCYROy3IgnQENCTqpooP94Jo9mLCkZwi8R9AlfTCh84ZadpJ8V9bqyXiXsl0vbiXs9eTcIfKXEjcibRe+70xvjB9pj1Fd7'
    'CFYFyk1OIT5p71RZuBK6StUZRkEXxRqDIQSsS54r8I6fpRqpX4hT/pCyCIi+WU1Uwz1LUfN7swRDg/NuOnOkkSroaxXaWRIv4hRkEpXQWnjyFqlFJYGSxUKS'
    'C1gknXXt4bd5ZVSi1AYsDEx2Olopmg4co8ZYgKrVEKIywTpVyckSVoF53JW3oIiAPjsdGZDVN65/kaqCt9NmRFjmVqtcY0mNJXCFP4+nZnCo7/90QRvPyX4o'
    '8Q4qJlY0kvkFEX/Vh4WtrbNHcC9hS86yLhDUpLWBBL+jScFWQUuwP81emiWVgSvyrFVYGD03FBjKBJcfAO2QZxEKRsmlkZCXthR8oMVgA5Pe3011f2aBQApC'
    'RlKmyo1VOCC+Xj1atWl5RQ0RJoxmph0ElQSjAoIw0HLOdNMerdr6Sh3L4UZkSh0tS0O6VKt+a0FanRrajnyNMi1z47on2u0Hypd7G2KrWIP6NTLdBBt/XcIv'
    'J8pNsF1v4CXYUqEvRZVKtMgtVidhVSUiuiYfu5NryrMFTeI/5LFfVphhQhfLrgWFsmH3VY/skIM9eere7fmVuWm+mJZW4LpT6DR90rUzrkk1bALvke88ZlwN'
    'TMOvVfp+S6ZhlVJ/a9iO2rLiVLa9Sljn/L5hHeyPDWuAVaqWbm5bMpD1YIU1cmillVMtAHQvR7bX/OyMvK5BXfXlOqqkhCDcrZ5ovO8KFR/d4ncuIlUm9Uwt'
    'Xd6yCdDaaPpvyJ6qr+/xt5VjS08Rgy+EBqDqN85+Ubv/1avWy9SaWpD1CsIzfMXdgOyBue8fqpzoTaM9ghPsIUBtEhYfkFdHA3J0pOYUd62tpGKSxGKO3X9U'
    'G1bn+pwx8M4AA1niyhDn3JZPp4Kh461R6D/fVlPUdFtNf/zsFvPOGU1NNqVr77zgnKTc2dY1q4X8kZTctgxpFFpJm9L0PhX5p6kW2zUqWBlxrbQw7GfMdJkr'
    'jUf36dUvDn5lkdeSIk0Qcc1qz0CQmN3+d277pWa4tBxfhrbzXZnxeuLW64ZDAoOcgN9m9hKJMHnhE5CPNM3ZggvyT7JkWc7xaszAyOuc3/HQYq97FL2UY68S'
    '/gNBxWnBFuQ+FpCtY7wO4uoqKcVbrcUSAwahOukoimG8wFspXy76vOobKMRWJ/bvnPjUlG+rYKFlsb3XDjuqJ6aBTB/GqAZE+qeNl62pca1EXL480Av2NkAt'
    'XyyUON2EjLx6wJ1tguTdSZQTmJ2w1oRXsLt76tqPgrortSNYjLwzVBeKYHQUrxXd8W5HVXaBR2wfDEMICnYiWEbQBlNlXOwxL9BfmRAMb21je4FbZGi4gJEU'
    'ubSmbyp2raX9FdW3NFVtevVK2DVAXloQm8b6S+rhUuJ4YUmsesn48Q2VcbSRYdfLYyPkFxbIJYVvpAVV45ig0YaOUaqNhCxn5OXgVg7FxwLcqLtu6ecVVxa3'
    'qSXfhLCrUkJz5VEsI69XhklP3wi2ZjxdayYJf2DRwHaEWrpvkqKCtSTXasrVHKDU8MJ9tdxIbtmCoVoxCOMApu/Ysjd941W539ObkZNtJcklv7JIKyuRiTo3'
    '124TWtq+5YsK/OFxJAH03Y6HaXiEYHtqo+aSQV5PKflCU5ZQCLBwUl4mcUhDSNsRRGKM1vB7oPK4ep2y4EITKhZkqooteTzngYzjoz2obLCcIKKwKX8CRkhk'
    '201lBAo1AAtZFvwFFkDaNCzt/5Ln12pTsuG5St+NdTfKs1x2G8NpdiGqUpw1ee1Az/Rk12g9e4zaa3rtAJuErmtI4k8vzB/f1o25Y5kACQG6fjfzorDJQZVP'
    'Km7qpz6yqzwHe4pUIgbd35pSVb6+0SWwC27NmotYVXfrBMDqk4maEdomc6+9dzrNmJib4oinG19WVD2htBHTzKzsz2/mNl5aXaQqOY+jiEU38SylSeWq8PiE'
    'pyngdc1WStfPWjK1O9DK7Va5d2gvjXIIJUHEppDalOJ8nnvPMn3N8LXcS9hWF3ogUZ+xZmZVo9Pbq41Ejdz7vWKziQYVn8zx6Fpl3de33UDNcnqGontnItVX'
    '33KvpW1b38zzmnBv6PA6PcsnjOb1FUGsOb2NF2wD7zJPj/pQMht0hW1mfqg9q2smtlV6xVQNB74u1gpm7q3oB05BwC6ifmtI3O4/4/kX6bLIrzKO73NVNPeL'
    'oQ0TjVS6llhjHNLRQ9dCuJxWrDqgV0aar5HKFu2H9/peMFw3W+vWy+XiHFNeD5VZdjfXlZljOKmEmpNeI4SLAfYSuzmYO9d3WQDKqXiZB6dMgCU9QcVht+0i'
    'dW87Wv30u2qNzz78XoWgX3gfhrt0Mo2CgIVHU8qoef+ND7035aH1PfhKJHwNvnc0Grwiffyze0hgpJauBRzfdMkvX0r7EYZgf2giW+/ytCebR/LXu5gKNS0W'
    'UM/NWfQRMgU+ULZNjm3i2hJkd78v2w34YDrkBVS2mYBaeMnCmMaCLMGVFkg7xXpW1sTYZ1sUaRTTRNERAAFHXTBPmhG848/EPF5ivV166U1CvgDKOZNdDy0W'
    '63sP2GCQFY7tsbReFtQrqNZOhSqPZFf+acn4tFtfR7pRRzfbOl5LHWBsc/lNA4M2kBPTclU6c0ioiBIdHBhWFOe3wKRp7L8+HLwm/f2jA/hTtwyvzCFAb93m'
    'V7kyXh+vIYgP10Y29SzpmKfjZwlD5qMbtojP40cWQQ27SQ9vDYolJd3tAXmCegJhrSqJ/w9QSwMEFAAAAAgA7rYHXSxcHkDmCwAAFjAAADgAAABwYXRjaGVz'
    'LzAxNF8xNF8wMV9DQU1FUkFfU0FGRV9aT05FX1NFUlZJQ0VfTkVXLmdpdC5wYXRjaM1a6W7bSBL+bT9Fg7/kiJblK2MY8SCyLXkExJZWUrIZLRZGm2xZnFBs'
    'gYdjJ0gwD7FPuE+yVX2QzUtHJhhsfjhUdV1dXV39VZOuN5uR/f1HLyb0IAqdg4iFTyw8uE6CR8aDURLE3oIdXNEFC+mYztiUB2wMPJ7DWn5CycOPSO0G7DOZ'
    'eT4jC+4ycthuvz452fUClz2TtvzXajHnxD08dnf39/fJgcueDoLE93ebzeYP2nz7luy37TZpHtrHr38hb9/uNkHzJuLIKJgnNPpEDk/If//8D3F4EIc05oRF'
    'S+p41CdLGlLiCAVkyUMY9eJWKtuNYjFKXUoivmBBzMhtZ9Id9Tvv+tMOYeQDPFx3yILFwOPy6OCJ+8mCRcQLnrzIe2Je1JKqfEoCyiF4T0wZtMkf/BGEQhu4'
    'vYX3yCPCE+L5cxplPlzxIAKNYURmSZyEPDoXZD2x03MyVH7v0880ZGTEE3DzhgVgIvZ4kGN/bbBHEDEyXtLPARn61GE4v93mbtPnDkTmivs+c1CBiii5II/g'
    '9/kNixWlYZWYrD1DQ9W6gJav3wyewd1k1Lma3H/ojsb9wR0MH+qx3uDddXd0f9e57QLZyquLLM02HPVvO6Pf76eDu27KPAy9BQ1frEzX1fvxfff6pns/7Fxf'
    '9+9u0FLrNPNkNHg/6d53JpNR/xKexjAe0weftWYhY19Y4+tuc8eC2AZuH3PesvF3P/JpjnDj8wfql8j96BYIkHnhi1geTR0sMXbUzxFHDNbRlTpSGhruPnux'
    'JlzyKBrTwIkTnKatnIvZZQjEed81SHewXwehy0KkfTMWaJYEYu3InIfeF9gb1G88wXLyEJh2QgbpFpAPgnDcgu2vBlsfbdK2ifoxBV4WuCu1vg+8WAnbZEZ9'
    '/4E6n9CGkvBpDOGu9MKbieHWLX0EJQlUnl9Ju9VuH5J4ziC3d7SfggsNAU34o5SjqWSZV69dIDzMza8tJrZ/uGfMX8pX2IfV0YNotlZXXXgcvpTJ0Inj0HuA'
    'h6jhBVBxAofZJFoyB73A/zEVX5asIWjkAtJbZKYlXBAMYBt31c4MHu5tKDQLBjWFeEvqhVGjmNp7xOUYOYgtSv8L2f9Nvl+QwPPTsO5oX87HLE5dbCCvbYih'
    'jyre4m/1XGEvfmJhI+Q8lt5li/9E/QSrAo6JCeHDeQ8Olh74Hl/NPd9VVuMwYcbKSEkUEU/n/ajTsC5pxIY0jK29bATDA1Nbn6f9IPJc1oAfYG3JIw/H4Ym6'
    'rhc8qnQMwE/kQK24LHzW0Kx7GERLZYFVylDqR6yQneLvkHsBbgDU2rrqhVhlBW3CBw9/gDYo0lBtUyup9Jz6My039r4w8gpy8zQdZs9Q6GF8QeN5a0GfMSdj'
    'HiSLB1gLPSmcRtuIqmCmD1Ejc631cY+8uRDWWh9JU+rFiWGEq/inGf8046+OPp5CEHcWN2Y+l3tecizwUEwW13DEw7IAp56IF0hWMWUsRsavaXEmjk8Xy0ZJ'
    'Fwaq/domJzY5q92hGNffmPc4//t9OzmyyRE4d1zvnZCe8B5sl2UIUZeGbfKZh747TJPXw9juVSecdK4+43Kq8mn30cyro9w8P8o0BMwhbMP/5dM3r2xar2y6'
    'lTLxFyECKDSLMSarEXIztaFGi/nYclp7eG7uGA78rhxowl9YkXpNU6VpKjWJ1TZWvCrW/8T4ylCnntevd8hoDFsFcSVUfyxysIlDAG2ypEJVBn9t4szCXIEF'
    'HlzrvirnIh6WLJHAg6OtOzwvLoQWTRLl5EKo1CTpOxClBU3uAN7gIXPxlIICnXLTANEh1FNMNFX69MiEJ868gv6PhIUvZXoUj+cAlD8XRyYAdiIRA+dFIkdJ'
    'H4qwAEXGJ1sEHF0d3x53EgBr4rjKRzfkfu5UgPX8NKHhIwOOiCehw6RYdnZLA64XSoicwyACEmEyZWogt1PtOGIqlUe9QVCr0XoH4jLTVwCQHQH6NNrCGeIq'
    'VuQTmlWzxkcxcXww9cL+hJ1wCvVJ7hXlCM6jEzeMU1M9wc5JQ6D3hPAhDywK+P5KtGpO/AE6HxC07FKrsFqPsY5WhhzW8I9giS250nXcY2MNcNtY+cUvr5PY'
    'W7A0llWnchiyGQthB/V4iMhfBhsU58JWBReFtizfSt3Yecd1J/RR81mqcS5HyKxTSK7HrNBzdwO2eLmCPjakjxosYWe49OmL1BcZ2J770Hmo3tHgEIEq0Iqo'
    'zxKWRIcaWQb6UjoR1aW/JPrriWfAfgXohXtBI6/UtZjDPgTP2inFE/hPkRSWdtAVA0wrc9AFCydhrzT2DEAt2EtQNAXV0mZT1iohUIM+hZ5Wdoy3W7+cGnp2'
    'lKupJgkqTSSu5y45bTnddGHTJa2+fLlMcAE80YPeQv/ol5ZYndJZ9qnFMWT0ChkkGRnxWF4lwOh2sc+XbfCtF0UAVq10bspYMamUwWJercyNKqs3eQV15kUE'
    '0jzEH7Urv8JYDwWLJtKcRHwsL2kudBtVWglrrJmsbOdxAeS8J7ZKcKCZ5CluiMMZII7iWtEuMpgCz168kh9vL4xEySamApg5rAjSBf0D1W8QTbNAR7VRhVwo'
    '16Ri/TEuoJTfKKZ9gOfzaxbFIX9p7JUMpHUvj7t0Eor6go8aexm20rGfckCuVTRi1H2xbIms6k8a1JNtduV8CrQKkVx9GElV+dMou9czsYrE/Bf1TeJctGeq'
    'B67u1XBEodnKlgB7jrNCA6O7jVca5Eg79gqhaU5I4ZzMgxQ8m30AsCr0pD1qr2w/2vCfmrGgCuZ2Ad+Ju4lqeKdDX7oytdMo2Ya3OAP8tTJ9DHS1llfhK307'
    'q6ustZHwZglfoeY384Rl8ThO3MgyGuMKEbARexDMK59RvFBlWkhGv0ZqxBy+gC7eZa50XSbkrYfOHh1tKUWfQer4dL3UJXU+XXuyykhbh0dbSglbm3jY40/S'
    'xOuzzZiF5rM65vTcygNqTRXFsUY0PblyoukZskpUnFw5MXHSrBSB0ycvAYTVNjR0lSVfiZUgbVWxlQhwLaqXbNVlNFdFl4UGo7oRFTPSgBOKmYzJ0OxIBUup'
    '8VS1riIItZ1N0SPTW2FXNCepMxe1l11ZqtTeeKUpsanOLIdqdWIgNlWXi2umqWK+adU2LyHEeSDrNj6qothNhSxJlmhMrlIpgIJcHYdMQt45QNLlzq681BYe'
    'DnKCysuUaK11qRjhvEC1s6nQNpHUMjqQ+iVbjQv5bdIsb65X5CxlLLhZaDSxFngsUq2Z+oWub91lO4oP7+BMXb+Stmi0c/bIQZ4JAPah8G1VgZbNKZ6A1f1q'
    '1UYUPeu68r1OcdVuXKU4K7A6eKBbx2etjDR9hQsgIUIWtrWyEwyqFjUjLFe+EoorJIQlW50QJWy2BsaLDNVWj2uZ14Zli05B4T0QKjZQfx2/baOx4M+Oec/w'
    '1z3ZVFvRC3kP8BNat7V6yuuh+mL8VmGnpztQo+apdFP9kiB1zeMnOzrE2KBY/PMFW8obNTetmDjybdO7pg/U91yo1Suvm37ODZPocTe8YyonY2WfuwMumOaL'
    'd5iFqyTzBuRn3F5Vz2jN/dXa29n1NyE/dg9b7W3l/Vr6ojq7cN14Q4mzYef7RWlfAXkjjwoKwT/o+p15OYCq2VY+FqJWWcoLXxDo53UXh9pPtYPz7lbFTyhd'
    'FTRLfK2AtWMrWz2fPtbZM1/6wdw0Sb7tMwjyNd9WM0yi+JLd8WA4f4mwMy/bVlc3b8hZakrdoLwhR+08bSrYtnFgwvl4QX3//+GCtu4CdQtodlibYKmngyQW'
    'WCifNMUr8NKl7RYwrt6JdNarnaj94unrqlZpRX9S1RJ802938q9Pq7e8/rYpK5HInVZIfPlX+24oHwMxo1aLWMZm0295lPKaUAszObR8dLrejIq0GWPDnHT9'
    'Zs2L1nJFqbNWqCLmeyvjcNK3FRW1rOZqQW0P9V2W0pD/LEud2ebngIrN+MjvjfqQaqPTQrlQe8r+vG4PppZv5b4XGr4afzP0v8GG2rR7+LFO88d6jb+lL6jF'
    '0/K7FhWhahBbQAykCntUS2b3g8XXQLtNbd/8ELlSy97u/wBQSwMEFAAAAAgA7rYHXWK0j/E7EQAAGkcAADUAAABwYXRjaGVzLzAxNV8xNV8wMV9QT1JUUkFJ'
    'VF9ST1VURV9HRU5FUkFUSU9OLmdpdC5wYXRjaMU8W3LjyJHf0ikq6NgI0gQpkmrNoz2aGLVEaRTulmRK89LGhqIEFCl4QICDh7rVjnH4ED7B7oe//Lkn6Jvs'
    'SZxZL1QBBRDq6fDOR4usqnxWZlZmVnGCcLkko9EqzAndy1J/L2PpI0v3Top4xZJ4UcR5uGZ7x3TNUnpNl+w2idk1rAl9No4KSu4/Bmo3jAP2jjD/RTDdD8Zj'
    'f+offHG/JNPJ5LMXL3ZHo9HHcbM7HA4/kqNvviGj6dT7jAzh3y/IN9/skl0SJT6NyHESRczPwySWAOSQrADRyzOWy5F+r7aoNwAMQ4HhKknzlIb5IilydsZi'
    '4AFXXiVR6D8BtpT9UoQp62d+Gm7y8RVNWQx/2qAGu0PNn0sowPqXXw0ZLi9uFkfHN3ffzxfX55cXMD3lMs8OvvSmMzKcfTb1Zp+D3GRZxFwON97xqyKMgn6Y'
    'RTQO3iQBizyujE1En97Q9GeWZh5ZRkmSeiTbMB+0sPMewF9es/woz9PwHoTp9+YxWz9db+jb+DzOwoAdJ7BDPY+E/BvOhizbCnuT5DRSoDl+KSF3hztC9I2p'
    'Rq/8ymgGQh62b44UF5DtmCLj96rUOLZMooCl/CMyDn9hn3bCJYmT3GaE5A8sLkEqItqqB1aDJ5BwSaOMIcKdlOVFGpM4jKoCwSyLAzQON+arNFzT9AnRXgAR'
    'wHq1OH9ztPjp7vbyYn53cfRmPmiCFVydJn6RKaXvNy4ud+k4AU+kK6Tly48ohJs9U0fHSQxf/Px7UC/sCPLauleV9d2IKOXmacG2SF7dDwkCQBVbaIWuS1V1'
    'TmS8HeOnVtMzqFX19RzRq7CGS/1mlXXHZnOBQXD/YN/7kgz3P594s1mHGPg9jcKAAua2MIgsKUflnusRwykui5zHPQt/D0DQexuCFyfr2WMdw5jm+NNHMo5a'
    'hzNbYAer2wKUM26YsZ18TSYE+LfPCrJnL0pSMv03BYD/J/cZthh8K8mP8xMMc3JzcWA36JY5tpvltgxyK/RuzN6SZRgxsgZ5VAIp0suJ+G88nuxPJ/vBPc8r'
    '9wL2uBcXUbQ1V9xOG0PHxJtAyui9+HIfc8YhUHgOGgTgQDc0+5lMD8j//e3v2pNH9C0kgkSkCyXkWAO9AYdOQ3C/95QUazhcMUrmCXkMswJiR0BJCi5Bigy2'
    'OyFJRtbCyAgt8iQNc0D3mGQcFXsXZjkknSwbk4sP/5OAOh8ZCaMHmhHwKEIjIEXJJk1WKcsyWFGysWBZEeUUSIC7c5iXfNy2pszWBF9BiDzA0jQMkjTbk6OE'
    'zEGUp5vk8v7PmFQ/Mj2hR26S+bswv5tMx+OxiYynJxVEfKyOwh5GdHykxCnESOKsWKNv8q8j4n/4bxRsL6aP4YpvCfGjEJT3B7lAbOZnkP9CFCPg3T5bG9PL'
    'ArwI9PrIY/KHf3z4X4hXYLw5W8Na2II9iAcgCrCgCoiPLkGGXUsQKBZKaq5iQc4tLr+7md+dXr4+mS94tgiTdrjpqaVvzi/uji8Xi/OTy8XdD+cnN98iohd6'
    '+ujH+vTMml7Mj06OXr2e3918t7i4O5mfLebza0QyPVDLrr89WlxV5z+fmTxcz8/ezC9u7l7PL844kYNSVH3QP4BDwEEHJ0j/EZSYpBhgZbz7ng/sjyHWyMnx'
    'jx6ZeER+uYW14kxrxvpdHOYSmCfy0T31fx7oc34JGw+cObmAQxenx2/oCpAUYClwAo4nk2nt0MVVSEidsRI5kio2NnrFAh6UpnwTLthoOjDkF/AO+ngKy0kk'
    '24hru3pOIPzQGKw4YsvcI2m4esgNDgzGcQE4kVhR8tREgsariJ0wiFosqyIXS6mlGL5PYl2jWqRW63Acs0eowfma5g/jgK36/AP1k0x88iO63vTpy5Mk798P'
    'ELUHCcugUVW+cG4MUlm/lmkqnlIeiqU7qxRSVHwyYpi5ximck6dhmuXHD1jk9hB5T1qcgsItlp9fnmdH/d4rmrErmsJCbX45vY/YGNIxloIOOAueAhrofE+b'
    'Os+vOrKTKX4kFLIjEzTOzSn/bPCyBBu8g0ITUUCGSMINBZR9CQPhkiNPWdwfDEiQIAii5+sbBWwQkQPxely6m/yj5BVAWWKAqP2smqLUTRSCXvIkLtb3LOVr'
    'kGUzQ0viWMT4c8xxegNBHoRugxIarkJMS7qpRZdz9XzCLrAWyqB1FPcQiWtFS69BGcbYnyBfCR3xL6WG9bqQLxA656edmhEKb/amzVMpkeY362dJkfpQuOQ0'
    'XbFcFBDcoGJkprSnvyATNaV4ldFFErHa4EmYSphAztVHytXXnKE/sqfazA1n0TXzKoVQ+qCRnWey6VOu4DO/KgcQyoF0pMC8QqjA3keUfiA3Taz76yF2n8qN'
    'Ewqz6wmE8sT6QcU7GrYlZZD/nMeQwIbgOuiF/Q1vhooN8EgWvod//WUqGZIhDhYC5+exOER4xO4JH4Y1OCuM6ZBjUUPXgAvlhT9q6Pg0FesEBTV8BOpMUhag'
    'k2Dto1bTGHMuKEJhgle8xsxNUvgPjvE/FYwH48p4ll8/QAr9tjpzA3uZcR3wNG2qxkWPGEaEfkrDx9lG/eKhw3PcmwRz8j6W9lilZyHOe4QFK9B6EITxqtQu'
    '//cqCTk5hJBqesnHVJIOJTsc3wpVCf1Ao6WC4xr/PSQPB8bWcWqwgh+La/quD9NeGVVMlnhVPz4YGKdJBuXFa/7p0Dqw0d6Mg7aUAVO3ETI1/pEMFXmPyJGR'
    'Ghlw3xELf4KF0/HMa8Z5q3De1nDeGjhlF0XulEOVPyRpFAhNasEaU4KMrbCscHjJMk3WV3pT86T8/DYM8gePk/6W2XkQAp2KNNRUpIkLdWd9/6ny/bZElycO'
    'ZCUrLlTGrIEoYFBc8uOJIxxpRksDZfEqR1/jS82ckB8yYvYrd84MQayWofhYCGOG0tc6GUryg4r5PnAlmtb7wpOfw7hfqhmSu4mRO/qy4sVI44h5yJ/cUfzI'
    'NxU/mKqUO/kg0Wv69YrHkyoYCJsWFjeOkuTno7wvZR1Ws10pGJcWct+Bp/S/daWyciVje+tarDGaWt3AurTQGzApmq+5Uq7BULKeVtF2sB9Q7wqKbwIC1Wrv'
    'l0dBcENXfYXNIz3ZGHIrwIgLCqT9lORhvOL3KeQbZjiH3OUtTQNPnumGryPwbzC+GWz0eAbbPXPZVMmA+gRWI3lR1sE5aNtjLp9hF90ARMbFFdEJqJslOdGk'
    'bMlSSApOhWBCPT3PFNQFJxI6kRfLGzixO7y2ER9FtgLhoafKH7lEBa+t+SunrGuvZvPk6xpsU+yAYZhL0S9zW2WKIDew7DiiWdbndbdknn8mXx2S2RfV8Nu7'
    'RnoQP3rIK+Q95vKDg9ryMzDLiLkWOxpBVWDkzgXa3GqqcftA001Pq1UNfws1wSZE3A0eyzuhwmIgkWPX4OKsz6C+FXbgkUT1JMujWhbQujgwjlaea+uJeh+i'
    'xDxW+ODcfBYNoZxDu39SXe5VWSnhMxQRE9bJBEgLbPyI4M03tIqSyUrN6KpXBlgoYijQWyIIDMGoZrUDPFelEab3gDdeQWh6C8lknoiv/UbirvpqIF1R+aLA'
    'uAzjoK8pgQ8lGwSjEXj0VMatCrcj0MeBwa3ZIxI5JV/He03TF3jocsVps9IG1fHNQuWiz3HP51s9+lN96bcpnwnsDo2bPwMjKqUyJBoo/KPRPTEfK9jR91yA'
    'hlkGCi3dStKqsKvoVdtG7j5QM9EzG76JukszigXX3LP5UK8pEKCJCWMbFG1jqLFf1UzUeP5Rpam9h+GVSZf+HK7rlS6v40sHWH0HI0prAwt6Jk9NtjQ8pYYE'
    's1I3/EtVK6gQOV9yWB1oAPqd5OaQTLCft1W95uGeNSoYthwFdBlRRU+12xYpOWJQ3MDnlycMglLy1K93W1NxksuWq90hUcaKkahcplolNdr2st+eVXVEVnv9'
    'ZPKq2yAubbYlPgaShvSnZ7YZVE6etSlRL1Iq7NnXmz1rjWbdYMVqk0OyxVrpySU2NZG1GbNb6PhmXaMKWXEY6X4H1rJG3OF9HCzga2O3oj6eiV5J/QJQDNcu'
    '/kRNYAcgnbgc1ttWBl1PrB6XOc3MEZE6I9MQboRLdE0MSYCIh4b/nP5XfbIzNQ1RoaZRhrGfrEV7rJLicc+viTeydeeJrivqR1Zor6FCE5WKrMOsO6LLIl8l'
    'jeTq8rlySmtlN7KYl1dTTSW5V+WtZijHZS/F7IiJMkk6m2iEVx8V9Er9WOy7hbIchY/UzP+n8pmUzZqK1dZoQ4NBlrB1bgfuk/rUquVFW0DchHH/N0SXJXU5'
    '0KQArXw9rT10NCLzNfGL9JFC3ZhUHlPgWxMYvIeTj8FmcwYZ/5cGlDCS0Q//DOhY4DnPsoSwxxCfqKwpWRcBjT/8g5L7tMh8ii8inuhbQhPiP7AVTfknRJXg'
    'yxZ8ZjIu72IjUAwLWkoiUyzs0dpGZW6nGrMsNbHF3KJtWym9ymCvxciqgthLJUs2M+4HvuhTR4ZD9TzT256DhdfzvKdiFfgmNssnwe3V+Z+pm2i8ROOPsjyj'
    '7DOu03gsta+j2HMCqaPglXFbNZHbLWOHdQlrOwYZV2CTLlLv8VbjUiUw7aiKMknhuDWSY/nG6T8ms4C/jQcFin7bTguD9kg9arnD1o663vOrMWtbQ1TFqwrX'
    'Iodu7lSZ3Q9FobwlLNW4bHA4y+OqGizfcjl0J945NCkssFzP2PLaBsta/Z7fth7Jfom71VNB1bqH9TCkyLZ1M49ddLG3iH8HTdCvSt7LOGEI1AioezSKvtCp'
    '0DPWS1PJ83MsqrssTRg6yaMNzHrUYcUtj/AL/h0V7UWblA8Z6Ybu7fOJa9nxEmaBQ782nNjaU9SrJyso6adQ9rlcj0mO0wl3oR2powlYy+vMcA5eF6CaMOF1'
    '8/71oeOVHYqP/Ww3Z60gZlLY1pwVHbTn1ZDqMuEZYCg8nn7yYzv03KkidVvkVmA7xkuXAhVCp3a3yNc1PeiEoltusB1X42VKPflvQea8orMOwC27x0OA+GGT'
    '6Py0rxfRhl/dawjytfjdQSMUzwUX4gd/2fwdGJsId6issyIMcAt7Zj7KHeFrx/2Gzsk7/g6gW1fmo35U8Cwwh0d1hEZVNBls2U7noVu3vMxGD7+qNDo5dhp2'
    'qjsuZmoxN2ussuDic5fVqsDOqQV8JR+2zxlcYfiTFA6f9ZSDfNGijMNKcfwN13PvBswfAn3664FP2zRXv5r6N7fNnWS7NM7tXutv6e8ixyY2KYQZVJ6vOZe2'
    'ysebBuqz7jFEvOn862EtlNTb5e7dtPEBi5C/+w913ZoNWJPX6sVCpeM6cPRTt4KXF9/KrDVxZctq4GMMWME2Wa/iVNKSXz+CEpej/ZrHSnBZwx1PqY+GZkgT'
    'dKUP4uijbqVv/Cinp57jykduHDTEF4/6Re6nCNaaJYtH68GsuVHWNjW/ILf3ib8mHo9Jz9idauFrPbs0a/bm15ech7FZH9iPMKuVv37MhhKJHyjcZ9ZbyQFk'
    'HuJppHq77Vp2q5fd8rpqi9ANv32tvZ93N3lL33Maa7VjWjG4TojqPzLrVa8cNR61/TUCWzxUv3EQy5vd9N0GeGGBTk7lK2BgpnpBrrvMDpDfbbtPfc6RUCbK'
    'gwG+BK8T7BKe9GpX1AdGOh5JIhPlfFgPRNpIXyS5ADMojkZEvuPJCI3zcJVkZAO5kfhhZRgXNIUzHYqUFf855YamFGbWG8iu7kNMqgKekQGaNc3AHuD8R8VA'
    '1hXmFNt/DH9/6dMA8AJcQmL8nSX4AQ0zAlQe2Xvsef9SsPsUu90kLeKyw52LO5Iu53VDhTcwTJhjQxvlRTaZ6M9QvXwx6aRCxH8e898w9upPWsQzeTn4rP8d'
    'AXHlEu0YhBqar613h4or3vBZgjres/6W/73KvwBQSwMEFAAAAAgA7rYHXRdHUqXtAAAA9AEAADkAAABwYXRjaGVzLzAxNl8xNl8wMV9DQU1FUkFfU0FGRV9a'
    'T05FX1JFVFVSTl9ST1VURS5naXQucGF0Y2idTrtOwzAUneOvuCModtJUbQoDUgWUrQK1G5tjX0cG1478qNqBf8dBagUSU6Z7z0vnSK0UMNbrCLwOXtQB/RF9'
    '/Zxsj87uko36gPUTP6Dne67w3VncZ48WWJnEoZuSItpKPIFoxPKuU1XFV+1cLRtoZrN2sSCMsWlrSFmWExet18Dm9wvaQjmeFWRCJSuidhb+jz0mbeSNDoZb'
    'uXUSDYU+GwfDz1vuP9EHCso45ymEAcUtgaLY2OjPL06kAA+AV0BH7bX7wNx3xIvu/hA/ns1Jx2v88lNSFsWb89FzHXcuRczq8BuP2S+SCyUB8g1QSwMEFAAA'
    'AAgA7rYHXXk//NcvEQAAL0gAADoAAABwYXRjaGVzLzAxN18xNl8wMl9QT1JUUkFJVF9TQUZFX1NQQVdOX1BPTElDWV9ORVcuZ2l0LnBhdGNo7RzLbhvJ8Ux9'
    'RYNBANIiR6Qky17FWtiWJUeA9YDk9cq6GCNOU5rVcJo7M5QlLzbIR+QHkhz2tMdcctWf5EtS1e+emSaH8i5ySYBoye56dXV1vbrpKB6PSb9/FRckXMuz0VpO'
    's1uarb2ZpVeUpaeztIgndO2EZUUWxsVZOKZn0/BzesKSeHQfJLOQXD4ObyWln8k4TiiZsIiS4WCwtbm5EqcRvSMD8b8g2Hj6dGP0zfOVfr9P1iJ6u5bOkmRl'
    'dXX10VxfviT9QW9AVoe9radD8vLlyirQbkYAQTn4+zC/IcMt8p+//o0o2H4OwIRDk5MkHNEJTYtAo5zSKcvjUczSkJwdH+4dvd8jeymd3AuMSZjd0Cwn0SwL'
    '04KSkFzRLHz45eGfjEQhiZPrkNMiRzgyYbeUxGk8ia9YTm7jW/hLSYpTYVIAImHw7d8TmgG2gTTSHF/+QAtE2+Zf+8AfuGYgUZHdk/63HGAEEBS/7N2BeST0'
    '6uHXW5r8SWLQ27gIM5Jz8SNYK/JiZMSyjEYsA6nyWZiQaRano3galvHCCYXlhbDiOKNFiMqCVRfZw99zJKM1r9CmGcXNBswozouHfwDRENeGjMMIbBeB12h0'
    'RddwiCqNGvz4FoztKgYKIza5DIFdEqKuEpIyMpW7CCpaWU3YCEZ3WZKgDlh6BozjESU75AoE3X5LCznSaVeA2l2bQjqOrwAtoz/OYJmdfJTF0yI4CTO0Dfmf'
    '1wB8A59v2CwLBMqns5t7aZKfPgwHFkmPZQKPn362oI7fHex+hMH2WRzR13GY0+iUzQq6m9Aw+zBsawmPj96fvtp9/+nD3unZwfERoAzV3OGr84PD7w4/ne3t'
    'vYHx9eHms83nG1ubzyw+p8f7B+/2zmC6CC8TGowzSr/Qzk8rqy38f+sI9MXFKLJ4VLR7OLYLFhKDhZyEURSnqJ6N4CmfOQXh3sDuhilX9tN1M8qKQ7Ti2QTG'
    'B8FAwKNd8hVJhKFAAL2MgPDhLCniaRKDWcNUMMC5n3tlyXbZBMC9og3rRdvcrBet75XtG69og+Abj2ySLu61T75BvXwbfvnWB7Xybc2R77mW72fLFMezlBs+'
    'HJ9sEibxFxqdURp1bsNkRgGuJcByGAMqk7C4DsYJY1mHfwwv807B0tnkkmYShYDXGHa75I+O6QEhcBCzLJWUQCASphEZIjgOrazSNKoR65pl8ReWFmHSuYUj'
    'yrKuIfWBD2wEEIPkZHDeI4MekV8uuoupKnV3EjoueiSLr64LZBGPSXE/pWzMJ7rkL7CTkl8bZZaTAt6dLa5pitsgpeSKup5dURjj0qgJa2nIA9yboBYchldp'
    'XMwiulj87wBQrr1HxmGSXIajG7NtY3COsG21SoQV4rThRr7FQzkYlhfAoZCRXoAgjqxmU5e8EgFVZG/PgO9LHwzDrF/g1/BHw5CTyNZLy6eezyxLovfsLZyy'
    'DsZrHDQ6mV7fQwgPk+PxOKcF+ldtwYB4AyFoxKPDqwLc3SW42077eyR4IvE+CsQzEDlvd7m9DzRx0MRVnAJNEQKCXUwRTj99f3z67g1ZLS+jJAqsy4iZUVA7'
    'hu4dohcBJiIYdMma4vD29ODNp7ODi736c4H7yC0wY7M06iiqwXm355v66J/CE9Xy6n0MeR+EwKKTMQZnKQUHaNYTp9qv4TTfZPywvQ9Y+3GWF7vXcRJ1EKtH'
    'ikx4H7kijYxY6sv2Qf6q034NYRGZtrvOJG5LGic+UXOIwDTiqduhSDE6Y5ZENLM3IAcHKmNyawz0PvXICGUEJgSSoVgjoblw6SEV6IBJRAwVCAeMg1fkVOer'
    'JcItiExRaZyfZIFiyMMm/gpQFFsDqsWUXZeUP4lt00aYklWLhR9grm7ZsVq9g81pN0OHVSPnHaSgFyq3EYUIeFx8IcTlX8xSNVzMAcTiLTMQK/ft6UjH1azI'
    'wQYxU2KYWI4K367KMQTd5zvJrdNCRKHQrFxygQSGNXvYKFlyRVBiCKvX38vG3xb5nUJuSz+dwnkxFNGy7QFhX4KgZV0lnUkVe+zYEFvKlPnm4prErGsgKst1'
    '1gQCgm3g8Ubcx5yERrYQybC+n7HJa3Z3ftG5ZHfgcKvRgMUpmgNMB7v7GVYGJzj0noniCXMpWhNFrsNkLNHOIGkiTzCJ07PRnUqWJuGdSZU4M3C94McRn2cr'
    'hmT0ZQ7ShUa6kEh2epH/CGoDpk+Q8ypSgk9fvI4a9AwVhdoSVzXwSeSlv5+ObMkdtbzYkXqBNUgp1AGsqkMBX9jA9etNIUOmcMbkgnXOp62+zjK0p7ATOHV8'
    'JGLdCVJnxsWfxKm266pxKmRLju5yBi+29CSLoWK+v2Ap7UBGRu1thQnMHCq7inCP2VaOV2P7eIgL25Ih0dGBRArBo0V3gSnYBKRZ9AX17lyrqOBdWHiezCXM'
    '9lI2u7ruGH2x0Wg2jWkEmhOVlzKbrrEDBg7MNgKFY/nNmlLD4oH4IHSZRSVyQl6dU48nFM50ruXzjpDmj/2PaRKqzKex8Uu7ETYGczrfqxBsc4YqfCkME5l8'
    'J2OusiSZ4KRyRLRs2DSKaS57PJZIlUC7JyCViAoRjUp+9oRVTwBVSLXhs0Eq+FilcLKuSnQ2tXTUlJlJ9jnMIjfj6XGt3IPFqpYijNzFdmLlT6LIYzIo3k1Y'
    'kD2V8g1hHycZHVNsX8qFiGqo7Rb1slexM6duLxfZiCEWrdWNjVBUi9G/v8bnROZjW9qdy8JT0mAjETuFtn9R9AyLsdCKtXGYiIOi7aqxL6F4sqFxwC9rLNV1'
    'dap/u04tc+5uv2FFx+6vaOctaaEf3CjvQhuCZFq0y3pV7L+VfaT2KRLmnZn2O6gy2t4iAaDjCLAPcuzIYX2s1YWfM4a3GeKjjqX41eQK8CVXjdseF8xyrnwA'
    'drknggSqDT9OTBPQhpTDe2UKClw08nBERZaVVasmqAZ9W2gr9g+Dp5XCgIcUcNXHs4Jng+AwsxAFRGSj8EUhTKvCWKiJZ/Z6ffzfM7absJy+Z7od7nB31GvS'
    'EcPE0d5iLiI0NV6fc2SRqzSRwO29LmYL4A5X3ECTdyCubYh6w0UvxrEHSLiUEJVWL/ZnmuhA3Vm1rRi6RHIL8peKiGoK29NSljre3fr0BiR0SkV+pUKjdimU'
    'meYmpM9oMl4fVGOapqFtW+aOpmX3XnGRDpjdn3QmIOlUS3Va+GqZUl7hDsAN2gwxLnDXaDlm3ps10C9c6uYqwKfG1/Qa0h1u6B9i+rlGgw1SR97mV4rr8G89'
    'wmHO5X8vrAyez5fKCN42FVVEuSUp6fCEimNiIRF8FKUEFHT6hkMwQque23Y8xWRP3NYifTiTEZsgAX4VXfLsYi3LuHiT9dS7d+pz4L+Rv/+aSK1W9X0cFdd4'
    'Gba53FEv4+vyypkwtMRWnleTcxmzMfsFMi5Zte8ejwEz61aJmbD0Cg9pnIYJ6CxVUo2ScDI1LW9Moi3rArO1vkGtiEzXxR3bc/53fV20t+Fvv08wrtI4Y6SA'
    '7Q25W3v45eFfUCWIlcRQLjBzx/4qHV3jEeF39ykaIMBF/L6eqzssCjqZ4v4Ne2RzXWpXeiPwpNjo7yigVcINF6/R1vltWddcl/WHVpNXp2GWdrlLWLWo9ckQ'
    'KW3ikoUecV4cku0jelccieq8PwiegRkFz+w2sqVrTMcrSJxav7IlqNxNca3ZKk/ioFCzslGVlQGHag6s5OXm/0Sv+QlXm5yUho/TFjNuvxbtshsyk4FwRtIb'
    'Kc7gkVbJfAdlkbiorCsX4akm6bTwBBnLP7XKjqnluqaW65xaVffT0k6qZbupls8vtbyeqVXjm1qWd+ILbqlQWYlIepHVEAQnbF/dFkYUthQYPfyaF/GIbZNw'
    'wnIoCEkIG8sKfH6C2W4BxzGEEwZnI8RSdkrjAu1RUFOPVnrqOQkmpw+/AigFYHzlAhIW94HlRuDvn8NkfG67tQ3HTZzLHe/D6akiXvgRLxxE5XLF6R8OBs7x'
    't03UDbvGJoXia86sWUXPWlF3MfyFBc9D+f9tt6ntSog5F4yzKWKK7tMhLcAaixB1Jx409Uplp7jVDZOT+lK03F+bm5446pYKtLOIK5iFffVdkgsBt8+c1gpC'
    'nbd7HFeEdi/YRwX2cS7YhQK7EEZXB4h6b+uiUO2suHjne7lsYSqiu5/XUU231GK3fDN1Ljen2NGVZJVf02uL7m9VG9UXKvXvNPx1DH8I5DMBrsN9zafds5jO'
    'VZp+Oqe6XUJVc5tfQW33y2ueDgvxMg/kE6/xmiGpbuYHMAhgC9jlJ3rN6JzxgHUiHEHb1NNH8mXFYgofwoS7sKht3lQ00+2r6IdZzhEXnrSy9+pyC1l/uugA'
    '1PDDAq7pAa+wdd6maE/se0d8SkcsHYE6UZg4T8CaD1lEE4/DHfH+mO6H22Uk5CEjty9nqKnbemtIXALwj21vr8bRzYFAjvMcoliliVQSVnEs34DMfSVQy/at'
    'S8HH39UM711lNROB7FPOAbAfDOCblwYy7jokfCLyrVKK4V+8NzHzmO0jZpmHdflEJ/f6BmTxBZRqwTnPPGwiUl5r6BGbuGewvZKrd+s7de+iLPZSzj9oeHzG'
    'qYSwxVzOoTZFbeZWG1BTvm2XzVKMPYOmUigXsjSi5c3DPHfcse17HoPutPJKG6uj/PzbWtN4N0mAjp7zUUvtD4sAT+yb3hJLFPyJwnwM7KJbx8UsUB4WI7Y+'
    'PSiG+oIMmpyaMzbLRip99x0bq9LhhZLH21n3o/pGdGeR76s+I1vwvA3PpQVun8x5C3UfnHmXqtorO191R1x3K2S9MiyfpdJ7Q4NcUw/w4M9TzvUyO/d+aFl+'
    'NcWA4TWoLE3e0CzLRViaxC5x2bL3QWU1nlsxa7uXr1bcLRetA1jJKf/Ae2alHwkgtw5mP+KGHz8F3KBwlr/sxxH8In8WQFbJcGvwbLi1MZQtfeNvZFnuPs0M'
    'bU+NP2Mwro3/GKU6jm9Mq6O8d1gdHuPlsjUs2zTi0kCGRas3LuNe12nelNNQ3hJCOKd/Kc/zNctp6h0X6b1owsgOvUz5LSHUz3X045LF7Zra/kK5b1Nt3JQ7'
    'N+XWTV3vxmreuN0bf/tmTv+mtoHjdHBEC6faw2m5qsa+ckkHDpjUsr7HE5OXGQ1vzIsaS9uZuW+SAat0A6V7b1JmfQ9VUbvV3XvEFjitn3nqp3O0+3ttia2l'
    'OTtjgS2/KdbeqHrEpa9qDYemluZxuRsPpd1lCOyHcTLLZEbRVr5FV/KPzQItQXxRXpe9SscoCo222yQIbDHKqqypvV3N+gt/o17Xf6/yHybqjeOv4qxdET8N'
    '2DG/NDR0bG/vULGu15OwOLaS1spdT7UfpC593HUFH3s++Au7adxAQY5M+HjE/YFVqyxzyXT1tZalNLlj4qYdf2jEPwTgRG5eFQsEEOrytaZbVnO6rBOpkdow'
    '4uyhGKrpn1RcV8lzlRydtXD3VkLclMqe0ts5BwV7g7q/z7F25Nswo3+TLGijgtNjI8h3ZeZuwCQSNoqQ2WQTFRt1fuBgnha7WraTsMeX079pNb18Me0c+Yby'
    'mNMNBKyz3hC9XJarBkUzdLQJB11bRTN8biIOAWMkzSjwN44OBWNKS+xofYeg2s78eqtYgqCnbdEw3DUT56s6KJ7XUAv7x6q1Xq6puv/7zqxVtn9dN3LsNCLH'
    'v0MPUjx1q3vN7d05/nNr3KtmnRyOesQKiV1971gp8/w/DrWePy6OQObupSrxXJEFUxBZU5ifrMmfj/HrOvuXNlX5ytdu3a6VNyMB0EjEXxzyf2OgmbjWa8Mm'
    'co6sf6/AaZK0akWed0vatdMxi+4O3szjWszYC9JwNRVW0mL9S5v7qNLnPfS/+CHith+w5AEx4yt5QGSjWNv/foeHYnflv1BLAwQUAAAACADutgddXzvm5ioa'
    'AADUYwAAQAAAAHBhdGNoZXMvMDE4XzE3XzAxX1RBU0tfMTdfREVWSUNFX1NDQUxJTkdfQUNDRVNTSUJJTElUWS5naXQucGF0Y2jtPcuO40hyZ9VXJAQsIE2p'
    '1KReJbW3B6N6dHfB9YJU1TPjSyMlpqq4TZFakurumsEY+w827Isvtg+GDfjivfnafzJf4ojITDL5lKpnDwbswbZKYkZGRkbGKyMjuY67WrGjowc3ZvxFFC5f'
    'LD1X+PGLs63/IAL/Kli4npgulyKKXPjqxk9dCdH1tnzLFs/vc+CLT2wFEGwdOILZljUaDA5c3xGfmSX/63YHznK8mhwfHB0dsReO+PjC33reweHh4VeN+N13'
    '7MjqWOzQ7gzHffbddweHgFf2YgoH/ARqfv3T37M7Hn1g9vFLdiY+ukvB5kvuuf4DO2TZERAJIboNxUqEwl+6PGKOiGLOPoow4gHDf16w5G7ENkHIIujNgy6b'
    'C7Zds8iNYrHmbAOw+NWPBaHbbBeeu+QhCyK2FtEa/kzjOHQX21hEjPv4iaMItgz8OAw8T4TM9V0YPuww4UEzjCJRhSIS4UfuAA4YM5Jf1kDeTwy/OmLFt14c'
    'pXO5APQPIV8GInpJD06Jj3MRx8CD9zPhbJfCOV+txDKO2NG3xK2IWeMX1uSFbZV0+T4IPeeKhx9gmozpLsyalMC+5ZvYXSIY/ZfAjgk2s9r3F/cwNVwbkYXt'
    'F2Hvgu3y0QCvhRWfYxNzOkWc3wvbPjg8OMQ19dgpsB+gp8vYDfw58Bml5RV74Gvx8o2I1ZNWswyu2dZY3mzdmr5pa9rj1uNPyMwScNWUws62dZSlrdhD99kQ'
    'EoBX2LqX+Fj+yMIAdQAmv7/8nrvx6yA8fXQ9R1MCACbmd+ez+cXNNfRpVqvuO7uZUH9+fXY+ez+/O7/FPhf+CuQ8frqIPO47UUnfpOf97dn07vz9xfXd+ezd'
    '9BJ6W92elVIyPb0DQubv727ev704O4f2nw8OG835hydFGKgcX35odrJP55vQ9ePCU19wAv3FEI6by5vZXOF94/EI1+s08IKw312FwXr25qRl9zqsN+yw/qSN'
    'GGdgJ4RTBOuNOmww7rDRiMBQQkuABn1ANpggxj7BXYG9KMFmj+wOs8fHAGgdE+DpE/dL4CygrNcbIMIhwb0JhSgFxJH7MBd7JAFvwKcUwMYwA9uCYe2epO8E'
    '+OuEwaYICmPCPOxBO8tSDgr0EeV4xb1I6KfC4xvJNks/eti6aR+UjpNtHAe+frZQAyeyzH3h6R9h8AlX6udf9IOPrvgExjsGLfYFqXBK0Wrr0xP2IOJ3Cq4F'
    '8t6QzUvQt5ADtk9B+CHa8KXonm5D8BTxKbUAYCjibehrSJBq9bWr0c3dnwQD3/EOxg7CXhe8Z6s/sTpsPBjASMJ3ysm58CMRRwYxcbC5FCuUHI3qJxEGSfMi'
    'ABatZ+7DYyVItCVmdsB7h1HcAXcGDggZv4FWr6VHpzH1xFL7hYYHfhFdBAKk4x93pRGz+FH42DclNX7aiGDVogHb7BXYAEVZk3hFz03uKHob2dkoLJLeEjRq'
    'IkU8xF09FUVVx2RV1QIIP9qG4iQIvJYP69nRnvYd97ZCzVqZTWBL4t4JmAj0XS9hhwKc5wGLWDP01uKPw62oIt6huOcUbVZLS7+iWf/s/sB+z/pDC3mWPPsR'
    'no3gmaZb0QH+bw2yH98+Br5odsAQTwZIK+hwHuOgX+ytu9ldy6roNrKK3S55+CCMvoM8e5p3fOGJ+BaQhOC5JNS4iicUlEWPFBWYWuXhMPfoBY0lb2ajGiLl'
    '/gJGIMOV63wqg7hoNwoNaSACVGXSgYxoVoVL5L0amnCUf5w4rqRicXtvrJlgqQyvPfo6vJmAzUCcMEuhH2bR166dDOevBAy7NJdQixIGSKVmvEzxJXDByC5R'
    'aTosBIOyXgM1wpFx5KsqpapgSZYdZ2lfWHsao/2MjrMcNc0igfuh07z53nXiR8Cy5vFjd+UFQdgy9PEQNHzYfh7GtwKZWoHyx2ehnPOVoHW5CzZZhGodvxbf'
    'Ca1+FqUhETvRFsVcGUa5SlLKlzJSfJWzmlK8EXHeDlWIPIY0NxshnXGNQ6iJw281juZOjwHcSaBbAXzsx9qK4ToMUegxlefRQVti6PUDiJQABemY2S0x9+hp'
    'EXXqTvHXjl7l0+SOcxqEvghbweIPECmAHnHH3UaG/lMzIAWJibkPAR/Ga837C9kP90INCdOVT2aEADrcn7lrArZMrAr2lmPQiLTSuDX0zcE8fhAJfUsMrDsw'
    'Ne5D/Ik5iif49eguP/giMuiOqFsJ3RIf0S1huhSrAyShTh/fGUNgyGX8NID0yAihv6fNe05zGQoei0u+EF6LhoCJ4ga7wzZB5CIIxKYQNsunc/q2CDzHdLzQ'
    'tzBb9GaElaZLMF3cpDyEwdZ3chO0E5BbNSgGwupr0kbR+yuiJnmm9m9IW+aZ3AThboi2jvQsAXgdEGNwGuT7zv3tmh523wTxI1+fYAOsS/75lQBRWmfGUTRp'
    '3mTafph67oO/lqtAuLJPu2hAMz2+D/lmQ9svpT+y6W8uKKEHLKEF0r8PTb7p1ZYgqZ2i5tziz8/v7i6u3+gNNf5r/LXAhagKthDizo1JxWlpAyYYbN5FuIKN'
    'GBhxNwhFJOHORMxdFIjmdIvT5MwTLtDCwbKtQdIXoRuygC0FRh9d3Ydib70dxWe/dHaTlgZxGQLVYxHtIizAKOTLvwYQUDAe8z9uxVfTk03m5QjCxp9g1mIF'
    'nAgK5MzEOoC9+GbrRQEGPJggFRBKLUL+5d+AvK8mykwX5kgCEXKX3EHu4Ow3InQfgjxhgIdHKFKwm14LIAZ+rQL45XAQeY8XCEOx3YMulZrMkfQumTDzAwZy'
    'FcYFil4L4aCzYvGXf47h0R+3oMABbHoxuIHp1FL0S4n9C4NPtONrwZcd7h0guoAYs2bQswsz2+nLtxsHrOss+KTRqzSLj9sl1PPC8DDGXfDw4Alt2jQsGqrm'
    'zXUTDVPz5vXrZhY6ta2J6TN7KjMos06AQf2+Wa2Kg5YjKGbb+hP4Z7cNdNLKlrMiFCuQtUfghYzxQY7Y+w4yAAwJczfcDSPkQtRmDqUdCryrCSZiol6JV5bX'
    'H0gAi2tXEVQBeAfEL86uTLssWmzkplTnYHEa2r06CR0d9pQSipzIe9HXIehdUwvGNfyg3U9uHthmOE6Mfnq0UrC8mCDCxXrSSJTHkkA4iN1hR5iZhFhpMNJQ'
    'JeKk1lgmVgtgOY9ude2ehglCBzafMOyt+5kiBUu1GH7NT92cdGs0p4JTS4NGaO+wiYzj1c5S2REzoqEkBkDiX4NtZHLoYZFXwA6ZeG1kWTS2iEW2TPM2bIv+'
    'KD+NbKPxa4KPhFBHW7M9KJWWr5rUXq+O1rFsHNOnSvQSrZKEUmIp022ylVSrNL6TmWASTwmlJbQprUkzbZj6y8cgvA1c38yIKnpxo5eCFiRZz2pCkPBhAGek'
    '2eDNENPoEwOwWqClDdRgpcKqJ7GNAzlnHber5Y8zFltb57jEpGbDUQWh4tFCGOoBzVk8arqT9GmiQ4ZCHbKewU6tRACQ0SDZTkcDxnJjMiN0VGTYSE1mxu6Q'
    'PJFtkngzfjxOlCtx204qxXdanNTw6JqRWPQ0XdePwOmTF+goSiRtegHw0AJUxnmpDhByefKcG9AIVHYcvhg+RTfWWe03W7eltswPW5mGg7+apdksqXZQqZP/'
    '7EZIR3KoB9hevnZ95zUm2tXJXvUWHsJuNXSCSA+oH7w8E7jZe2q1jcEf6Bgxq6zzJfp9dX6IEImi1o6vYGcCNOrGn2/4Jz89MKKmiwcfIkh9EpEqBLaduRHO'
    '+wYVCvd4vaFqkFJ6Ih75R5e0iAQ/+xQUe4GFAqrLeRIwmaOn/kHzlzhgHlPtslsmbMKUDB8UcB622qBZykJlwKvs1ACg+4MCeLW1otPPavCCG6ZcfRa41MRl'
    'QLQhm/JmWVOeJjzzzMPtsGkFnIpBdoHcxMDZvVG+LREAOqQ0bJsJhSelbdmqEjrZVmMS6GDwgNju9qS9WKTHqrVilOTPtAjp89im2VgQAool0bfZGSTVq3+S'
    'nLaWQRcWv9/LAJYufNKsFz1DctHlaQUsSRkWmtK162eGyq4bxtaUVKyOfmWAqJlL2c1m8rhGFSlckNGFhC0Nk+UyaGArha7S2n4f1bZvQO5W2DxcUVN7KVTp'
    'SuVzrZrdmegZeW2n061SEGrGIoOsZqjHeZUYoEr09wm2JQLKzk9Pz+fzi5OLy4uz6dl5syKGHZB6lsSwwzHFsL2BircH+8fb0h4ZR+2Lfcj9wzaiarAgqWJb'
    'k1esoRx2v9WUV0ffmqC94u+lF0Q7w28CSvTjFH81k8f1sXfavTLwtuV2YpKCVioGMsVAucc2UgGWSrxs04bpyz82M88qgmoJUOV/As/JINF+Z5w8rdqV9lJG'
    'pftSKnYx9IoAko2pjGqXnuChTG2ovAcVaJqJACMFopOzOg1inGNnN/5m/65KeFEUbGYcSJ3NhMNwCFNpyQrRI/A77Bs2tNuF4BWrKwH+Ooh3qI2s1/zyH7Jg'
    'U9VnyrpNxJFmL8sVyJqUaVBPaZDS/eOiBqXk1SlRAW5nSv4UK0fDQhi5c+eRObTD9JFxaGjU5yiFfA6ypMxBoUhd82/AUr7pgSg62MZ6x4OzwM0EyCt+zUTV'
    '6ln2LLBiH7RvSUBFFcAnPB+HNjooXnp8vTHPx48Yxmu9MXz0R1ba61GowoJ+30ojjEq7RYN0VC+pu0dHbLrg7ucAPcJpsF7w+K3guJcRum6Ygwt2P3OmC4M5'
    '4wEWXqG2oI67Sw6mFguCc2FrTa4OGUlTXfPPLVADfc6OpQDKoSTN9mCUAuCJuS2Dl3bGfchqyTiArSLuincfXJsVEpTdbTar9jPVJ+wN3CwX/QPMqN8j8QS8'
    '1buhcvl8dB0hV0KW/0bfwyZaJCfzSmYNzasQTZ175oSFvGZqf3PFrNoMq8I+vaksK0NGnkr2tFLMNFc8cpc9kSvy68uLaEolydqNJ8Q2JEBJpKfIrztVV0ZB'
    'M0SVecJ8d687Fu0DGX8rd/HVap3NjSSFpMbWP92uy4fU+RkVXc+v3arpkj+Z26dP9uAsKZ2o7pCcaGnY9MCgWCqVPwpJ7e7zKz1mYJOeDBKf2Z2ciPj6/u/w'
    'vkWAZSaqHH3/gp1swUrgucsnGSk0ZyLagHYDYbqgcC79uOJ2RFXt1TVqjsirgXRgJKiVYp2viK5woCoXqNGUZ6eknn7tWuixag/SlPvX7r6iBrZUw1/lNDzD'
    'LaFMTY6JNTZnAa5O1mC3cpWtaZl3Mlax6eWZGy1VBNMuB2FUw5vwde+CcCBFQVUPj16MYJBxtxBYiTB+On3kwDZnDmEhB10368eb7Yp4yzC3iSWvtgGNhqH2'
    'DW3ZdZBncjuZXg2BmYlXUVhcpxy51cQapGrS4HsW4cGhcquR1NLqPU2JoGbnozDQEXsFt0uYXTygbRRMbepBU/3aSU6ZEiVkFdSRWJFeBupC1BjGC3CZxZk4'
    'wov5nbsW+5qphr6gcYiHKqqzOiVQLb8vXNfZgUollyrrepOl16co6dxenoAE3AUzrH0N57HYoJk37hmhOaddloS4Dd0gxNt+lzyKu3S6jkErnaRWx3YHh21j'
    'lfY1pqfJdb7LAKJ2J3VxfwEPd3C4w9xe+Jst6ipezZQe2igVaTwzGiPTpxax1Pgrk60P8GA4835NI/ckvWRWLfGmty7OBX1vtVp+JV9SPQYceZJTg5prKTiP'
    'Rsl0pe9IbGw5E0tNQ7QM3U3cVedseORWOu1iwPGbPKAkxFCzex9N7WusvUlVzdAzrZxO/QVk3GXRSeAdbVEv0h3qrmvIe/XU945F//j4eNjtLkVvzI8n+lYy'
    'Xj/+aqoqryvv1xsvLQ97nRE7hE97zOC3uq4WBlgdi9ckqD9ulcH7rEXMKXnX+vmXDvuZvX9P96thn/uhyX5pHzAdgoSOuuDGdLKD9mynwZZSTNYBK9YqYdaR'
    'ThyMejMjuyEPssFqLjBPv9NOZK+NtGnDblMcbXUnskjF7tLZa2VEGWFXBxG1FlxGuSZZmGo4zlbqAxT7xpxJWq4vh2CFoNXchMHMWW0hfe0OLjWlrFFpS1Wf'
    'qwCHN7qQJAz7JAqjYWeSikKuaO8U1raFC9yBZQapwmcdFSp2WHrrhDUQqDsNqYrOzEUm3WSZt4a8NAuXUxh6rGHAIMhkvwKTuZsuBFiwCq3m75zc1YkUje5p'
    '3J/I0afLqNNF71kJ2GW+stkAGydQGfJKARnMBPT913/4L8ZhLxdzWUW6dNcc78zPgpgM7yurm2WgbtAJP0c8tOgLqKPfazluKE1m98cOS3/80EYBnFi7DKDe'
    'Tqp03v3ZTsNX20MZvOHK6vcEGbxhzx6vdhm8epxVhq6+F4r1mKQaPu1BiVTTKUzro7zdyDIKrq4IqXiMzksZqjErSS8ZkZFUfa517ppuUcLe1cMUNYin67vr'
    '7Rrl9DN+MS6J0UiYk6yxchm8be1WZc/slU6NTg+dv5xoZo4RtJS0crOVHuy46vgtvVDC9r6mwp5xTQUXcjSycCVHo3GNfXrnxtwjSyqXKg8FDot7N+FMfALt'
    'UqnE/TMFuy4v5a+IGvd9GI6Q2bQWB5FUyVcPqLRHDjXLomaEmqR8MOrYFsj58Bj/FtkTxU9AP71xQGVjF6rSY0mHO/I+C64KGJ4N2Y+6w0IDLCmLuZueTmfN'
    'fFPpeeRRFiYp4DP6JgeOi0zFC544GlDJoaOEUhw5LMNuCLzUepww+Gura9tt+TqAfqXcSOm61Ls+Yvlo0rFtYPnY6vSqJTLpw0ouFn/Lhj0rWdpIXeSU8YXr'
    't/DWbMeEf4HwbT3LxHRs3fR9Iq/KzNEet3UL0ZE91MeKhPebV+YwQEL0KDyPfnT1yJFsgsY42NyWl5akFSj0P/KKR2oenOSzcr0egQmw56A16/WHsGhjfCWE'
    'NTBPzTLvYdmTGWWXgYvRYk/xo55WWbJcRi/GhpmBVCVETw5Ah+2pAZX45clrrkABZSVz2mfeEcXfBm0vWA9PtPudTKcfc51+LOvUG5CcTyyyu5PepDPeR8pp'
    'Dvgvre+sySqAy54mA0P4llKR5sx3o9CXjqPsTePdHWnlde/c6jxjCnKZTrGkIUmpKEuyZ/B17os1HVvwPd+BtU9HFYr1xdA+FoNu13I47w9G+4Zitah3RWS1'
    'nVGu+mMUK/g0d5654wZWfAELMyuy992Y/v9283/ddrNv9TrHsP72AP4UzQrIzSY+cSF2DXDLKZe7Qy908zpsoRs6zF3TJTefNp1RehaQdDFgm1f8s96lNY2u'
    'dAB9cXV7M7ubXt+9v5r+8P7sYg7fT8/lPa6rq5vrzGO5l8PkNJ6TY3f8Ik+vjUu+0rUfNUoJky9YaeoQpUCQ3ScxspO6ld0IDCGqwEUWugaZQpStPJL3oHIY'
    '5fs8RjsxEnlUSGkWdxZmC2EYYQRXOW4bka0UkMN+b/SXkxO5dI+Ce/Ejha9IQPqzYhkrppn2g8nqcCdhoVHH0ctPuW/jhHsTYOHRHrgrBWWCaMaVYlKFpFJY'
    'FD69CsqR0WKMbDLax/3SxZCxAObovRatAKL42hXSb9JyHkTy4ppZ4IkTfFLUblkFBk016RdcdQcz+iGtul5V2S0tLNFmLUWHt3WSfvu6dLmde+0Fn/Z25uVd'
    'lBsf8dXqeAJuvG859njs7OvGK5DucuAV3Wjrc0w5leOM606k4GNazMZ+69vHKjIu/0fdt0wPyNSAyd3fkFeQHMZFtQfkkO1huUNe8w+CTlj0hV1VrosToF1L'
    '4c0TrObNE7IUlWVfPVGaaTgqvldiXPayibyqV74/guXfH7HCCxXmPVuWf30EQRCTetYERb/Xs0uZRFkW4pLiDsQasUiZpE6zI4DIJXSSzAW27Uo4KwdGyKnO'
    '8AzrC1MvhSjomkhpqXnurY6TDgNzzkZ9mdbojSfkbyk8K85Q2uG7gEdSv9OSfQy3f/2nv2Ozm/vrM/ZmOoNQ6uLsppkBKtwDwUOqBKL2etSRgUbXp48yNx6K'
    'vMKbHBp5ehXEGiYPkyXmzkeMCmli2tlZdl2EmueEcXtYvr5iGaw3AMQj3KyIhevAt1//9C8sch9U4p+ziH/5T4d3m9n+pTmzBKJeWww0mktW9m5zCZus3AQK'
    'KqPacjxUT8uZSCzsWZQj6/f7HbtfpjCPwaep0UumetIsSHIr3ERdvC9KUE2lYfJai1aGjIDmToxScf2dY0hshykqDht7SFeS3VW06oGz8kAY2bevWB/bqA64'
    'RkQCdhJEEfvy7/BtE37582d3HdD9AdcPSFhoz/UsGcOCbSKi25SFbDvlQWVCGybr81ESLvLAtnFxDwcQopcuMkWAp49Avjo6fOrIAvacJSuLspUBrQ2sh7J+'
    'uhBF675GzCsvPe6CyrLC5EVxmU1U6kZ3PbX43gkwtu3KzqVbMPUuit6gOM2kozGD4m6gDCrjVUrC/YEMCQbD4+q9lwwuKNkrb9YoLZTRyl1GF7O7k6R9F8Pw'
    'Zb1l20wTQTnT1G25cdkOy+xtSsiwZCNVAWvKCQZuKCHJe0u29OLapaxBlFyaUV64Lb1+grPCOM3OT2+ubs+v59M5O7tJ7FRqnWiFhuSjBqPR168QhOO1K7TG'
    '06GdK9QfVy+RxFC7RL3qJZK9DbZPKleoAGqs0EQvEGyXbtjb+zOI8t0H16fDSh8s6xaMZbzlnvsTvT2J02P+INZ/xTgYWbCsEWxRPXflwhYmiBQqjtEhhPLq'
    'nUtcLSN2fhRLMMgMzfZH4DG9Kt+PRVeu3ISOpA+H1rhjj561dvqmhnzHXFpQSr/lm4KYrBgzg3KISa5uzs8MaZKOBD1JDi4VPQP2sBz2zfT67Q3gPJ/fTdns'
    '/loi1fLUyO4LSqCPEMhcS+pQtuA7wfKLjcVt8shNqxbEDa2UIOg9XYCLxP+bgsDFawp2krxXk63seCsetoJFW+l5tRc2UVTwayb9NIzJN1/+HOHgPbbgX/47'
    '6tazrrbjPlwcP5uLY81FCnHUH/z8H1BLAwQUAAAACADutgdd4UhRNcYTAABSVAAAOwAAAHBhdGNoZXMvMDE5XzE4XzAxX1RBU0tfMThfTU9CSUxFX0NPTUJB'
    'VF9URUxFTUVUUlkuZ2l0LnBhdGNo5TztbiM3kr/lpyD0SzprZDkzk9w640EUW94x1l+wPM4eBoFBd1NS77Sa2ibbHmcxwT3EvcE9wj3Cvsk9yRa/yW62bCl3'
    'ewEuQMYSWawqksVifVFpNpuhV6/mGUd4j5XJXpJnpOB7x1UxJ7Q4p/dZTo7o8h7zG5KTJeHl01DBDPMKV+h+m1E7BXlEM4BBS5oStD8affvmzU5WpOQLGqn/'
    'hkOMX99/t/9259WrV2gvJQ97RZXnO7u7u1vS/OEH9Go0GKHd/cHrb9+gH37Y2QXMahzSWOAr8PPf//4f6Aazz2j/Xw8MgMKMLGrUU7j7Q4FGojqiOeEYMbqE'
    'doISWnCc0pKwvbQqcUIJQymFZoFIzFzglaPRBaaIFA8ZRpx84RTl2UNJBqgATDCGoL/QucI0QMkC8wFaUZYlMIhWkgypAPGKMEZx7vi5Jik5kJ9eISCZLBBG'
    'CU4x+nX/Lfted6Qk55iholqSMksoAzR/rUhBLQAj5UMGxNEDzjMYTBBOqmWVYwMwLnD+xLOETQVkQgBXkQg4YHWJJWM5TFuulpjvzm5OE5yjqxw/kZKhQzTH'
    'S3LwR8I1gl5Xd3X7BvaarHKYMCfplNMSz0lsVAPIG18VhrvYQNsrRpgxK8kEwGtuhmeiWX0JYf5YZQCmPh/8hDN+QsujRZanZiYA4GO+nVxPTy8vYMy+ZXBy'
    'fnkzubsYn0+gubtOqLtmzHR8fnU2uTu9uJlc347PYNxo+M3IYby6vL7xe/ffDkeOiZIsKSfmG0549iAWZ4ZzZlsZXq5yMsnxipFU4HeDV7TkkQ4mpUcus0eL'
    'gWhmcLoO0d92djtjSWtKQHJTsf2jATR+oHlaa5rSGR9ny0jPzaIkmN9mLLvP64iuJWsgjAXXTV+9PSVFmhXzfwoj4yQhKxDGa7EkjHsM/oUkkfYPGZ8+AnMO'
    'OS7nhEOzAyH44akB9wGv4PhdVbBxrDnlHDNuWPF3SrQbVurtggSoA/hW75Ckxtyhn8Fh52JvZ1mRcXJRLe9J2QNdURGQ+E5JeFUWiD+tiG5EhyDfhQQDSe50'
    'cJEi2SM65Iew9T16tcR8MVxU81rPO+R1wMZGmCpocUHmWGzzmPMyu6846RVw/gVvClbTRpwqpnr6HIOCqA0RY7IZ4OSxySK+IIVgUE8Z1q0jmTINktkl/tIb'
    'DZBZnzjXTMnb+AFnOQbB6jW5tYrn4ASuzZOsZFxrnEB1aMlVktT1NqS50AenbNzrXt4LibgVDRLc9Q9lI/r1EBVZHukZXuFSnDkHAHeG1ibxaWLOcfL5AwGu'
    'Pc5iyx9OamzHdaU08bJqpcH9A+qT6a3db0PwcjZjSUlIERz0I1oVsJp9BDMc9UFCR23kSzKDW3shB5DyR8xInhWEqQ0ND2ZUVLvTR1qm4nIiZV2fdA0S7xQ/'
    'i6SufCwS/8ivwWLB3ECtEtwNGF3JM0XDQHdbhR+nqV6uY2Ga9LBBdQFnECyfkjxktGLuSCRVWSplH+U7GO9GSbsHxpjR7w8taiQku2c6XjmSYr91sxMk3TAI'
    'zrfE3jrFFc3zccUXtMy45FZPmHkHHevdHthPx5rj+gKJo7ZWTsQdEUgbfI8IIHa9+pocNq6w3cOQHTG5jjEJlGQN7KeXMtyQScuw6fEY9oS9dL2G4cbdunsY'
    'suMxvDCiPBAfn2fWib7lzzZpBuF2sKhAK9grAezkEAWIarnEuXIUGL0HHwikokRMXOxDNCWgWcsMrPFqlYJBy9AMrP+lRpWAlU9YAkY5+AOAUvIrTDJQNYAQ'
    'I4pYAZbZAi6qJc4YdCWC0PeCBMcFpxqRZ2AIEOCioGgJV9uSunmscIm1Sb8qaVr9kpXo3T7C+QPdU+zK1TBLqpg5dKdB9HYMNrlyHdk3yykte+tVjVa0aBcs'
    '27fyOpL/mN12lhBssyHhA3gTVBASoYCAnYpqK0NZWlruerE76WiHptiutOU7+sZX/9bV6sJJS8u9r3dtSjgXWP37StirnWMinJQjQMykxcKA72Kulvj5e9Mb'
    '3ZW6rPux+FzQx0LaYX25N+AzVglJJ7MZnBnWptOPpDOn2bwLx7hFkwjPxBYcgY9a0vyF+IIhMXQfTzdA9PG0hkJdQWxSCNMqfRkmPQYw/apdJInqJ1rm6Tku'
    'P4Pu3gifP7CG9Gu7LcEIv1LiJyUDdAL6TJ5QBjcKBguwp2Wzj1LqnYJPAPOzMuSVYMbRLzDTyI8x6D3fIrO3ge8uSatHGnmtt0UTpKGfmyDuTEX6fE9njdkF'
    'ajD9UUQ8emCo49wz3JXXK4TffTOWa2jAm9USt8u6+9rhrq+gtCO0twDctaK3PrNWIsZnVkoAdi6mFyzcCj/lFKfape3cAlvK1dZRBimoU+eWG2qy/URydqg5'
    'dKdE9NW946gYqBMVOMZ2s1yr4iHmRRvgZqcc0+JfW/0e6bbcN7zvNjnViq/hlbcJrZqz54U3RFfx7rvvzRtJYak79PHrxdNb1s2PnQk99/CaMII09Jrjut5C'
    'hj1RPW5hg46ajg6BPp7G9a+FCnvWaFg7ItKtdahUX+J0g4NcEmVo9vRZ6etjJ4NSQz9gpE+g1uDT9rvURuO80d0BiuDsb4ZP+EnmtEqE6uMWWBQPY8EWGDWf'
    '2QonNuxJyptsSS7oY6/f12tVu1wiEb4WXStjhD3p8Qiknotl7cAkByAHMkDgIimLLnA2fH0DO5Fyb5eivUr3+nEEq2UjWsjitEgjndo4bIZgmiZgRKFZCpbE'
    'OiDPWFQzqUUrGpOJqsPGrNZCvfROiwmb9IXiAjdVtDU15SFFt057Shui95YvxO11bIe5uT8hgWa/otMSvBBTBYetp00OHVYXJsyz5rlIPSlbMPA4GuaCDdWr'
    'uFcnEqSPnd7OmljUpioPp0/dgbGlVMBvQwWlZAKQiElsOFabODBYmzhbbPsVzbPkSW1190Ilv6TFqLTjrcx1wZ1/u99dt98pqe+4sPf0DrXuILjeE5nto6jK'
    'ufC2dXqu4Crfx8CcF7lCk5W0ucKOs2zNwtUzN1vtghzbfyaKOVZThRYz2RcLdd2NDlaNKL47tcVc46vcZwVYY0L6vIgZ+ZIxrpI7jUxgPUrupdv0VOxoYbSb'
    'LyomrihNHoiMRbhdldJ/aIGlot78FJl9bIoJx+zzEK7tx6JnZi6nq+dLZag+OtsgB+nNdYC+GfX1DaeHi+mqj+sm62arYP2Iw1aTNXu+DRIjrN4F6kQ3FI2d'
    '3YiIHi0woE+n2Rycnqi8HoA9W8A0ew3J3wxnI+htEQcb+hK1Ec3/vDjULkg8ePkb5LJo0BCE8Q35WmzfJoyivri2m82RlavksurCmyn5PRglzfkHduML9Wd4'
    '4wnLxiBpXH1hpyIRDn9/2Eik2yVQesXeosFAaSRErl7d2NPD+qGFF3IHtOtpekPbC2EYcQ9Wd4Nzo52znJRn4PyQ1J3D33jp7uw+cwecFquKX5VUlPqo0+sl'
    '7DobWkUyq6iXJ3ojaZ1i0hFATksb9MsxQUv8EIXn2DcgmnMRhkH8QHe2XxencqW0hCzbvvpkDo4zlmhO+lEIZNOyWp904osYVaosKbMVHx4TBoL0JC5GM213'
    'Z/d30notGZO21N757dX0iXGyZHvRghZlcg0VtF9VtvX4F9WXzb77w7ev0/3W+rLtqXuVZm/e7P/2SjOFu+9Xdslsjak0k9Yj8Yu4UltwNTB1W3m2zIR5aeu3'
    'QNVKZKbAa9is5HI1XBjUPmYI/7XKBqKEjQqzZ56Z6q5rep/TL47BqxJkInk6sDVkS7+y7XuvWdSzBd8pLVOglWLmN6tSuKRinC6zX4Aj26vaYLfB/2eoAu3r'
    'KvBALOfg4ALjMwKEAKdXf9aYbaQyrA7jKsp+79Vr2xSURerSzk8v7pqVZK+HtirofPznux/HN0cf7sZHN6e3k7vp5Ojy4ngqoAKgo8uPAsHdFfwvBwgyrlxN'
    'EJpOpoL+3cnl9d34Ynz2bzenRwLRW2/Tzs4uf5oc3x1Pbk+PJndHZ+OpgOAiRjMEdUZ+IT0RB4cprkAzXS1oYVxl4evVv8u4ZL3xRiDjV3BPl2BHex06XeZa'
    'vvbr9XSbOx9SzcuhJl2g45bt5rgG0OpYh+s0dankpdoOMx7BUIA7LRjHBdhmoCprZCzYUJRMiBk5hl2fTppE5lvz2oAOlxHrv32NVWiRxyk3Lp+f61QhzISA'
    'JZhKC9SVgQ1Mv5fWGOmQtoy7et9N6D5sl3mP7BdptJnMWyznMYrkN0bt2YzRuqTFqD0zMWpLQYwauYZRM7cwiqcSRrGswSiaIrCJ4HhewCU861mAWo8M+ru2'
    'RqTf5mDjYX3T3ZoCVWV3v5vqwntagUmR+mWAA1U/US1FPdAX8aFRNdhSL6isM2V8WW/tnUGHVAG25FgjXocgrPJby72OB7pFNS5mdHajQVyZBz7mofIxn+fP'
    'KwRRI02hRxvHNCe4aOy/pbquEjB1Et+cqy2lUA1+bYRHJ3b5fJIjfvYc6rCwoi2iJo66Lj0cKBUpAqqYyRBDRzYM69prTXZqbWg+LLKSuHSQO0Zmyzi6pHJm'
    'K7Su5VwUGTWvdXHUBx1vvVIJup5eEJevk9kRccxNk/AIu/La70YEbYC6GtUF5fI+7/qHSyMZmmT5rzZbHsel4c4zthSmdtfz6Rtl77VjZUhNvUSeVgd2kCj8'
    'Mp/fHSppGAb3W5Qr03tayOVrcoVrt1l4omUwR3PXzOmr26PNujMFearqK7gD24nUk/sbkGCx27adUks1wQYEefwObyfZUorwMqJ+ssgS8+uogyX2O2IL4/fH'
    '52EgomJ1XJUyGnBZ8cvZtQiHdMPcxbS6tw+adGEg+LJL8AjBaiDAUzYvspkwCcEJVJ4YBfdvuQI3Epqo8E6lyzp0qWJNc5zn9BFri2743VtdU+nN7n1tmXab'
    'Y9uX5n2Aqn1odNVeRnntkl6TXP5li2zVemoTnYjVFrMs87obmEqvTJV6SRO5Gy/17cYLarvWONTfnRFpAAIT0jR6BqRs+mrqy8KIdFzvyeIzExKLWgfhSunh'
    'TvYOumg4FJN3oamOWSFT2WbsOi/OakDqdZrvvR5XvIn24xrWDGb1zQpIeMb4uxj6KGo3KCIIvh/0XOmWUUAnLyjhws+Ubi1eUrLFNirV4huVaNnVe2mNlh3w'
    'bJFWc2OanlRkS+O+VYt4xTwuB/pcoZZvoZpd9SBaCnSNUWxGhAD9qNtWHxP092v+XBT442m/pZjWXPZhx0vKZvXIWG9QIDvwghyx5yPKju1Zo1p8c0Z1LW6g'
    'uq155tnevs1tmxtlSHp8vcZFQdeqfjRsWEuiIONlQoa5WA2KGtdW66NHxrqD2TTfd9gJhV0Rp6Qxpt7l1sGvkzerYNrcXIJqfTMD2+iwNUrvDcqgw8HXMpUG'
    '2mv21iQ8kxrWa/QWonYS7Sr47Z7chWdQQwfNIbA8fT7Yx9PanLzTE0zKtFvw+InTYyKdrS+XSCmekvRkpgFzWoqnTgVdwt0DX7Rv47UId2b0speRqkbQIkZ7'
    'AZ5/EUkcGX6Av+2FKsK6+t9gTj/rauGu3x6vEkkJpYnq8c1PE8A2tAmGI5nGOBED/kSe2ND7PtqXgViwdKS91FXCeCcNo4bMDjbE/U2AOyrZIrTR1W0nf767'
    'LLoyxuG1zGbdTem+jtANj4gkGzRZ0rVWTb41bJjT+TnhZZbYgAsRkW71oFAHthLHG9Oi4hIrB6dsyqsUZKsRttO57Fo4oALtCXuBSCl+QGAFbXktQ1zPLB2c'
    '0blaHxmF99/0qEdTjmX5VbEtP/qsmzdSpkzAxhoUR5b7R1wWikb3UzQp9LPLj8HVC/3pQTfKCEzRI+qbr5rmmmCujMHbTXHhLy9xgHQ8hH1SYD97c5L9wtOT'
    '0uNi+i0VNHUwEy908RJZSOxZl223JIpfhd6TVLcj8nVFoAYs2FIKJTNPN/x9COtpPVbqBrw/yFx91yKSJkvDjL72DllorLYYAu5BWCAc8i5mV6Q0SMQlInWu'
    'h6tmO9fJxlEL2+ZaYGrnu+ZvxAyyOG5tPh3RByLSU60UWqJGTfpxMjruuW7to05KJxS7lqWXhtzky4qyqmwn0BqFevlqabNo/R7XfJk1u/zVP19O56kf59D1'
    'WBHL+v3hmoywOd8iMlLX5O41nD5dJlohKG18EXgVNyHz5r2nCUmEpfwb1FWpuLlVSttVRIdITOjdU6gb47JpAhS4Q/3fd/oh+gohKvhbk6jpWEVDi9pwjTL+'
    'TdNqKLB2sk3Y7Sjb21+aI/p9k8qQeucgyOnowoDLQnEtBzbr48zJ83I7m1z3tj5SQwf1A51wrEHmR+1eZitYpgr6KIqeGbgnNPnsqnUfRV2SjSd4dQrvoiUz'
    'jkos79cVMnIm67PSbn8NN8phMwdbRT6fz5upKhAx8hk+nL6I1NzGJit+cuNRvEFoDbpsp3vCYvH/c+UVvslzSsVv/+1ZU/NaT5rnax7s+Skj7cGfBA+MG4a1'
    'fnwuobqNSmLz82bqr6gEevArPGsHt69yQPoAYVELiLj4+TlYBpQsyJxW4lckgnctYKhkf/+vNEvoAGxeBu0M7HaFSJcpouLv/ymSRKLsW2aKUqJ+Ea9UpGSu'
    'RcClttB1j8MqiunLhzHNSYfz6doIoK8eTCAxshDjNAWfZ80q/PPl+n/i4ZPCFDx/so+dZL25Vfz+0ye5PjoRpX8Xz+Wi9LoJUdUfe31tdf1/WiOxRO7cbj3l'
    'bVDEJt2CB9h97sb3Jt6dZPMFH8/npfiRFpJ6EQrhBuofGVNWl1yL/s4/AFBLAwQUAAAACADutgddZVD0IwcfAACoUgAARgAAAHBhdGNoZXMvMDIwXzE5XzAx'
    'X1RBU0tfMTlfRU1VTEFUT1JfUkVBTF9ERVZJQ0VfVEVTVF9QUk9UT0NPTC5naXQucGF0Y2iVXOtuHMl1/q+nKGCBBBA1bN6klSg4XoocSrRJDpdDamMHgVnT'
    'XTPTZt/c1U1qDMHYP0F+J1nAQRAgQZ4gzxC/iZ4gj5Bzq+rqnuHuxrAtTld1XU6dy3cu1Uk6n6vRaJE2SkdJGdvoYvLu7Hz8u5Pby/fjyeXvbsbTm99dXU9u'
    'JseT8+08UbOf1e1ZYR7VPM2MysvEqN2dnVcHB8/SIjGf1A7/Z3t7tvNmd0/Pn41GIxUl5iEq2ix7trW19XMn+eYbNdp5saO2dl+83n2jvvnm2dZX6qKc4bwn'
    'bbEwZaG+fP+DGudtppuyVlvq2uhMnZiHNDbqxthGXdVlU8YlzPts66OpbVoWh+qOB5Exvj1ynT7u3mG/aVxW5lA96CxNdAMDaXtv1c7ul+//Zfe1mpl5WRvV'
    'LHHzvbWkVsVlYdPE1CZRtdHJSkFfpVWl0ySq2lmWxqqBZW3jNDdLeKGSqVVSGquePy/K5vlzleZVZnJTNGqhc1NlerWtzhqVmHlaQDcNg8OLSRunM5i/NpnR'
    '1kDfxtDIQHH85yu1u81UqJZpVtqyWq5of02bpKUyRDYgiNIFLTcbJUw5XGJaLJQ19YNRCTAR7AgWU7V1VVpjaZKvvnKEdvTHp7ewDuA22PYhrURVZd3UGh7V'
    'xpZZi/NF2lYmhic4+1vsdHum4iytKpwUF1M+mDrTFbU1ZRsvkbBNDWQCWsREGWor6xT+5E3MzFI/pGVNDTGQrdbwVg4LTrGdHtdl2xg6GQ0nlzYrHmX2e1hO'
    '+mCi2jzqOlHzrHyklsQ0ps7TIgV6xPDeAjaBLOQpQPzGVNu4ex03LfTgPcyNyWjYpa5gPMtLwhHmNaxXNWlu6Flu8rJeAW/AbG3Nz4Df6hyHWgLHNBlQih6n'
    'RdU2Cshviph3U5jmsazvPT1UC2JZq+/SL9//02kaCc8CPROii1+FI4nSyC8rm8Ywm41rYwpl0z8yZx0RbwA/W4vsDtxKNM6ATjBPk2YkFyEvIVNiV/PJxED8'
    'pM+ge9tAwj+0KQrMrE2zBB+/EwljLnyBa52ndT6QQw1ddFVlKbyaFsAKsEsafPwJuQueLtPFcpSZB5Mx+8BhWDmXO5FZVgQXoMR+0dStuetxbMhdbiaUZz5N'
    'J/XQpWbKu0GvZIDjMp/p5sPtyTWqgm6C/uTTct4cpfmNrhemuQM6AbPxoSzLLBk15Ug3jY7v4VyaOp0BDS13oj4korWycOSJ01i0XmJoEaAMZAHENwc9YYAq'
    'zaz8FHawIFkgeEvkXGOSGU3WNZfz+Uj4AJjP6MaGrZ5apjD5qs9IG3oFEha2i7wuWlh/AVzDTXRs5hOKUMYkflcC40lnUrD09JgeTPXc/LYsjD9stYA1gZIx'
    'CfVyx3JNSuAnOk0r/VjgiM3qCpjdJHR8b1mmY9QCsklRTEDiYEGNQfUNfIFqDRgkkmOiHsSkZ3NQdCTiNfI/6CiSkjyFkZHnbVNWJEvfHrG0oVqcp5/oGUkK'
    '/KrFknhx2t9WotwHqlnlGpjnk9NRG1mcTFWWOasGBgYtvBVbZYDpkFyolEyjCiA5LOpBp5lGGwQSKDPnegWMWK9gD6VqLVvKDPgVpCduYV+5ekjNIy5BPS6B'
    'qQrgOdELn9XZifqMRpvAxWf10fX8rLxYi2KJMyTLZ3gJtu/+d0h/4EDjXXzdwBHYHHdVLZE1Pqv9vZ2//Pnlq9fwJ8hnBVu64hZ6aQ8eT6n/UZHUZZrgG6/g'
    'jdc7O7iwoOs+dm3gWJCf/ehvsO/BwaAv/j5HAfcdD/ah45v9PdcQ9n4JD2+Qqk13UJ/V169e/+XPuzt7B771yjci7a7bgkg9B5Sl4hqUOyrwSjdLBYc73n2B'
    'S0YuGr/cDvs/pBZNVGfclG1neMT41h6/cdBns4PtjrGAH+YZKNoGm07hAehbsl10hKJu/079fY/VEPjI4t+69qdU8hMdmMGPkQnukLvjJfBjQ2wqfEIM4t/2'
    'PBeoUXpNcFBZBwgF1X1dfkqhgxHNg2OwQleg0VUMe0G92+gVKCTAX7XvdcTqmgAdGkgBM+pXbV79ZKe+coFlNgJdiIQOqKglKBKYHujICjczvlOzbPMZ4pV7'
    'NJGoJnOdFhbMcwmP6zZ2qg47FyViTSAL2gdAYaBsTZFYBSoScaynWvhCZhY6XgHmgI6xrgzRw80C3ISYlPjlA2l60BAqZW3nudKhOUTMiPvgtID+QgNEgX1+'
    'eykw9ojhPhpcx2AMFzvWElwGGiQ2CWAn/A0oeEyn5Uz2YwpCcUNWXFviYFPXBCMATMHUgEqOBXN4AWQAgNoQlOxJWyNUjYkfQNGlxEIGzHAKHIVNg0FR09Wo'
    'd60jzwEin6atiwiY58E7EQ5YotEZAGgglgW7QrwNXLiOP0IJ6xjLxmlGi0vCRbPVXepisWm1/u22cOKUgW0vGxyHlAxKPI2Bq8ch8GnPFoKmh/+DoRGDPgnU'
    'gZ+8OQelE9kChCArwfiVcdzWts8Ir4QR3hEjsNlXM/B9AA+bTUf/nc7uRQeBeUPoQbMixPE/kDg1MGVm5k1U+43FaQ1yDTYOnAbgMY1aC3meG8GdAkqU+Ngk'
    'C5Y+2FiKPWFEVPUobhqGkLP3tnL9iD0FWIbgkB8QkABqyNMRGH0RWPQDibTcrSf5MoQ/OPOJ9Ahg3xVqRFytyStQKfZemCWOs5bUPRC+Aj/AdC/D6WRwXPAq'
    'Hge7JCCc5JDC2dyPNOofYsh21jyxAmIRYgte919bP0hfOxz2iAAgGIZtWlBfKfnS8KQkLBXSIEktCCRoXUuwxQKuAJoA/1YG+C2x4Yq8BJB7Di5FW7Y2W/U5'
    '62vhrGPiLMTkCkD5JpY6RghMUgAk0zUg6wVtil0L0DVoyBtC84iK5oCtkaFAp4BfJg32BfUiLqpZhcHPmWlQS7FpoTMHVSMjFbBXXL5x7Hbgm4TtmDLQAtoy'
    'geOJ0uKhzRDbAo9EyzRJEMDTK9AJJOl9CycQjTOEnhiGYM1iGxdFgI1PZgRc8dfdFY3/vk2jH3Ff1ljbESLQXWUBjIUqGKiTFmhvENQBQETkH+Ee3wZv9nbn'
    'fM5OD1q0LeT3MKWVTnN2akgVK3BkkZiWQi0ATeCcVK0r6C7jA3iJ700tzjSNJMSKBkRRdcv6wJDIGG9IHbfAIRHIJzVpUbuig4EH3ALq1WT6hnz3WvjuhPju'
    'g3h8jA6esGU3oCEFPoDnEN/TkMBe+LJrQKHYBTKhm88mi1rx8Ut5bEEvcQTvgQ0uWSSOJAEnPqK/h7aiRMcQ9TDw1W2Bzkol7ia/vzQZTgEM9Q7GzU2oKoCy'
    'SZSUjyiZvd5rXFIpDmgB3dI8N0mKBC9KCnmI/0u80njPGGNgKIlombgH+qUxLIzMUclOMoWxaLUxICZgMAl34D6pDfwsK0OFM4BdqttCP2o3OBslPcfzbJkM'
    'EbMFWVETeuNxCeuDXXtVDQywBBOIBlAcXhg/SWuMgrGHqBKdazAarudKAgF9bnkj3DImbrnZ5NhvYhp6RzSP07adkoFlE4AHOnYmELx+F1Qg/yCwerBDRnHl'
    'fG4NkwuIx+KH2gnf5cWwVLnzhAmGugoMS5s1aZU5lWm9zlznEl6mt9foK8P5pRnhyQJoaUPFQaC8m9LbJenLRrBT1bEusLXR94iUAOvFhJn4VGBBOXUGrYJM'
    'ozHk1S1/JGN0c7CNcBzqhinZ47IY7PvQ5roAB5MjR6w+7ZWpP6TNFCe588wzA3QDgGANVctJAi+n5IKjmG4g8E9sRiKgYPJbi67u//y3B2iDWPKOMN8pq6og'
    'WvQUz8kKRYyX4uwBdnhYRaxa5hhbXcpKOYKUABQVfNojbrfaa4OKAtzS+RwPXU0u6fEHjqqqyenpOu/I3gvwjQII1Tludom+IWgsDLE6y6DtUgnMEE7GeIEi'
    'GE2ul0VkXogU0b4oiobIzEpYzZ0C7WrQQlYQXC0fZq10vr5xrxjxzDh0rKo2wzAOeqAteYzg9TOFXjDqL7jV2/t1qgENQFFjLBE2wQNGuLOIpxiSVN0bU1kX'
    'LXAnLxzJvYC3c7DMD2Iknz8P48Bo9Z8/JwsEhw5DdMHKAZ+5pMV74rPJWvRxwF3vstZEZzFhGHKPM8fi4sMyDHQ0iE5B7YKNApdXFBD96c4WvILC8RlBuwTj'
    'YX6s1hqkdM8tZgS10WOWMCZFLTd2ENFgBQ76LV8faJ2Xc/1JHYCeTFCsS+HNBBdboxB3dIhkNzgmbOYeEfiMuwNwLR8xCgM2D40l2E2yRt6Z2bCyoXoD9WWN'
    'ACdZSwjMKbjHZ6bI2tiN5PuurMGYX+j6HnsgpwH8QhbKMvf2YKtDTmbOTIs5LpldzLbx/E2cPWCxPWGxDxJQGESuJVmYzlfOWpZ5joGxzGVorok16M+LjpUI'
    'UXdYOnj2nXM2B3A7eNaBdXp4jraODu8E1NB3QIK26kLgjEmGrOFDpOYTWSif7bg+unw/PuHkw8Xk+mZ8dj3hX//7Hz/8s/r2dvzueqwmU3V8fTa9OTqbciP/'
    'Ogci/Zfrc3V9djF4+2R8fT25odent1c4urz+5V//QY3Pz27G8vPf/lONp9/enn0MHpxdXB0d38hw7ybTKbkQx0xv5FbQhbYRhS3aB4w6wC9MzQGDoF/uI1ho'
    'QVIzAE27+3LaZ3Ta110G4gmAfewyWhpErUiQ8VZd7I3BNgeUZKwzCgwwzp5UwPXHmL9y8XnC1YQvKe70rixASF2jC21hIA6HRI0hGVnYKCZJwHcYUWSSpn4V'
    'LO+aAhP76wpCkiyVLgzF2Bxii1wsaWT1nNmMVoqz8bIABYH5x9ApcDrl1UyKmUdOr9Eb4mHAsOJTSlypR4t+zMDDYBcCYdBz9PHo8i//eHR9xy7hjNwHb2Li'
    'tqakM/hvDnfPSqAfrc26tDG7XLMV5kiM7QB4ngva4Dcpy8pPX4A4TG4vT9Slen8EgnFzdjK565l5oSsrRzBrJW0M5W7AWAdyeL8ixroESzriGJFPZP0EMuoC'
    'umnh8qj9lLTqP0b//5PsDMMJ+IMXXVbIOBjIx/SW6MngRMJsW4jImT7SNaAbqRnOl5fA0i4m2+OzLnjnE3fCDGI9glgjzyO7gZW+cK8WumlrEmr0z3Vmgx34'
    'TVEaw7GRi6JuDjuxP+9d2I5CfXI0BrWGrlOYGFw1zh34xL/fD0heS5kuYaMhmTAnDfbE1WDwMNbonM0fUdExtnb6I+QhpwB+TTwU5Dd/gnWufbLxCIfVjUMt'
    'R8I35KvV3jWVxxlmerunzpdKSmf3p/erOZzGRwzjSna1hkVNgZhsf6olRggQTwSFFQxvNwSvOWyzJezEWrwXuDRF2S6WasFR1kEagdPtQNpFraslH+Pp5CNx'
    'JAEdzllRlJOUqwsjUc9HhFEuNAAA/1GwLoDTQrsAuIRovK7CCBPpFI5egGoJAWQ//yxHjl5E4UWpC42DeHCoBfF9WklI1IJdpQG2j0+x7ONuwBAuxn0exLh9'
    'ajsSkfT1DJRLLriexmeyJVJNnHJ3d4cp9Gdb76WSSJDWs60vP/zw5YfvBzPAc6XUlx/+HZuu6jTX9Sp8xL0pBXNaxq1db5s41fVE+xgEMmyiRfRy87RoSlFK'
    'aUiQRbzrL3dQWUE9emNt6kB4jxL8x5hyAr/wF7u+VfaMfJAWwoZRURYjVxPjOhINIt5thJsCZo1b66wGekASwPZk3LTAm7YuTjD3auwd2Wp0i1zXGUgZZihR'
    'h4HrB/LLx08zRYjZ06SsO24QdyytKxSzUpKcKyd4qH1BUaBgIUImZDWjjCkozRQDQGAVFgUoDoqsojqF9etswKEuVn5BHHoVYgrx4S0St8ebAdEtc/ymw/3x'
    '6gt/RpxizomRgSx28OJHKdwbvFWU7hWbUpyJDocIQydxLOQMc50Ydp/5qeB4OGjXhZVwkTSpf8s/iThR6VQS1QZSvKBxYasqTFDn4gHJWVlT6a4sBTt0wbmI'
    'Y20xqEzhtD6yIlq+h838bfSb6LeSHlc6+X1LVRiuJI7Z5aPAraWJOVVGlY3aMRAqzjZLhrobz6BwtZACuzFMXjddQDnkGRfnviSeOQqz3K4YAQAyKtRmc7kC'
    'mBWuoLg96xhGKqw4GT6wHZ4S3mhXKzQzjx3JmVmBbgZQBzYFSXRyPDc1SeafoQ1yOqEEybHbMMHH6z3mpKjtVu0QdIF+NBgQP/SPlwwEeT+wWyTEINmSZWvz'
    'WVeT2HOPu3k52e8iWCGb64JKHRK3b/KZww4SdqK4CkGende+ed4WscA0iTc4JnYrWnPxg6qQLrzTefldFMGNEASievvBaNtDOqNK0k4E5WwChmCvkSohLdXs'
    'uGPqONTF1iccW/cVXDYv77kYMaid9SeFxUsYP7EGWJVSg6CPj4AWK1ov4Res85UyLprzGEXNxf2PunIUzpAQSAAibqxU9MtiOPdUTaHvNuWSnilnfO7g4B2/'
    'PfECpon6vV3iBhoc1zw1GacCf3SIrSAi+cQw4CyDNrdToM4dCwmlVwVeYb4ftBkRckre3o8TivvImOF4b3/GS7+ncIp/mat9KBX7R1OXPlHkwvx31/DPeQq+'
    'gUnuJCHkSqpyQhVB8VFVVlw0gqV3GBF1NbbrAX6qW/LBYfGtEMt1sWGsdVW+ypAQGKb2tThSQUEiZausk5HNsf69nW11wYkZwu8WFAQraqweFBlgIqm/UsfE'
    'yczbFymokjaXpe8Jl7siY3ScON8blJtReSOh9wPX3RkWgdhsp8Sqy9CoBJ17IXmjBM4B/q9wcXyXl40+3J5499kXI/QrraxpGtJcSUlyrUl5qhKDH3b95bXA'
    'JFlhmjZMBErW4ek0YN8n5XwiVm+z5gAE0KzXvYI2kTxFyVRgog3OWTjP4wle+gjRWDpP48F5725TKbsL1nfVonKewGjovXLtFmNmd0Z4t8HVah8GRZzIxo9I'
    'lc9difegWpPKHa+xUPMiTSLwvUfkmfraS1cs+RvDhZ7qGuslU6mVBD7ENAoFDjrG4n77/YLLqOFySlxKrysV4lL0CYesu2p+pLIHVS9wkSn79rkQJLx04cJ1'
    'z7aIX7paQypBNBLD7DBfVz0pdBNAjMlrYW+8V8OsNJlKUGqWYdl2VWE4zzpzt17WX7Dsc9ClK2NEtdlQOSwxGUIXRGvsKC8NrVu2/qgx+s73V+AE8wGv7PV5'
    'havhnX08YfHBul8iK+fVGl2xergyNUbpZZMvkZqkDEWn1S2ve3/HFyl0JTthNMnngJ3b3jNSgrCo51xT+JgOK8JrM0YwN77KwMnHivxoVJFDJLk96xI5RLee'
    '1uAIa54mI7fy9SgoiS4ZdaYAnL/Piyqq01yF60U0FscpqjGqyhXTwjPJMtzx8uoxZkuY0FUqAJ3mGBCfSenqhiiHT4BKxR7BSaYhD+JMvb8JgkGEsN7U5y4x'
    '+IFpwz+WZe7ewsCglHjWLPtYf4rixTdpwN5h+hMOI07tWgZwb7/PYXJdJnQa0WhqsKoVipmvCd/uxchAp/Uyz8C3PkXLtVW9NCs/PdgOsSZXU63nm9dP0s2j'
    'FikmnbrUMPA+5yRdmV2QK8aiJFPHpkKffBWkhblYFJgchcVtk2AxyEIn3j9afOBhcYccwnQuQuwZ1jOlm9PDQbu7sCC1fLSoSM4mKDikIkM5qxfDRPFQBQ5O'
    '/KB/4hWrCXKbUcG6KwjDWw1SDkYLC17xRTQ0ywT8+91DcSROO2eF6daJoq8hdHfusPKifERldHrFSrirk/W3q1LrK030DFUKd386EB4CRorG2qZtKDsqr0jE'
    'MnrUD4LV4ZUg1gnMvqi1u+dDoNhiRASmMQXFBIzUzcpSKLeLzJdgMkP9aX9/e39f5Ta4dub8LPKALAiZkeQFCNEcXl6CxgXKLVmM9jq9DURYOIUEErXvcGW3'
    'kreSAevrRRArnfANtJA8WEVGyfKaEC2sZpSVOgkumviBoffX265yi+6uuPjBn3Z3/AKbspH4Vc+8NquKtNrg4h1AL9v44LOt0ns5AT8raNvWSr1zLqFvuTOZ'
    'Vxh9bWtKu+cAZ5vaFFzshqj5Io3rUm621KC/HK9TnkDzZLKdoXS8HKAzvh7oBIMyjid4za3Eko9jUDJlZqKOZNJfYnukAaQSiZGjvw6CyvVBY+lvsGHHDUGl'
    'FpDLDlWgTEKGiK6oIqLOUFMTWdJe2gEY2pUc5SVIcFmAUcAoC1CNOTpYCl0C48h8gmq1XElQzIuRJN28jIT172HJL7yBIq6wevD2LEIOo5IyGxHc8sImYGoy'
    'VXz9k0UNWExAmLjuca0tO6JnxQMCOb7rOHe0oMvAtuFKanaEZXMUv9xIbdjHsy2/eKbhgBswQcCXQaPuMqjnhiOBXK92RpJ8oBubFM627Rygvz/yTjFyomaj'
    'BEl9R5y1iQl0ZE+hNcZDSBaomsrNSE1R3ZJPjniEWed2o7OL1w3wrkCM/sWCnKYYDaR2QWuXTKsQBDvitgWun/rwPDjBWhByD/TFpdyO7TxaUnmE/kEC4JhF'
    'YwuwdrbP5RxfOI2jhc5WXG2+Zfto9L2powddc02eXMZlcnMxtbsZLHkp8Td9jCopW9qqQUVDpZTh5d6bEiAV1+D66Bb6xaHT2bn/nTfYcRSqmRCpci7TWdJu'
    'Ga5qMBn4lTO5atX3k/01dXcLLDGmovOetYsFlaXhbvRAC7q7yjGghraWui0OLwDAsPdNWQ2O8PW2Ona3iLpFUelEhdIdGEXke0p0sf7lTO1rhW+gCqSbPxg9'
    'AaKkC7BC/lK3fB5AgstSj4mhnauYK9wH4g4gQQ41qHoNkoYOoIW5SV8zbsEqOdgMQAB+oD3MtIcvwwVJlM2lrtyazgGpMICnSu9rpAQXaWBgCA4BVmwlCuDq'
    'hzyG11JCzyvdOC0Hw0IqTHuJAURKaREGp1i+cXoYvDUuWOKrkvpXY8GooBrLU0vZCqfgiQnxmwHM9Km1rSvhBrNkG1fWjWcJcpNvXPuG6lriivByE9GJXSms'
    'QqAQ/AhgBeB5WhdBbQL4ch1l80wUFxojFgZ+dpTqiMBOLGlQinhVJd07RDWGm5R4ES7DUau7/+Wus9TPtjhx4b+F4DY/xA1vgop+SmezNIiPXmFlAUevw+9T'
    'iPFjq8H39sq5XHfhsz4cpjIizFP4pAWVLwWX/Ux3VZTE3ofphzsLCvqlXrB39YeSZFSOKCXPq6dKnrEnXRHwDjFhgKCMg4jSpeycMNLNEBhXikisK0rvMjS+'
    'ylKKQ50al/LxGX9dwvcPis34CGyIUny3LkYgxY+DmgfsM8zuk9W0g/R91MstR5SH9OnhIKETOCXiLz4VQvZKttvTbi9QJpigc4MCY9yhgeAEGbxS+WkPnOkY'
    'C002wiIbJMGGkScJNHAEti264IeJMOTAxfFdashxJTuqUT+e05SLRRY4teXMgHHBfC2Hhwe37Xe2e/FElKIRyY0DY/Ili1m7Ipeh1oi/nCsafjblopWvaohs'
    'jXe5MnSf/3n5Fh+TxgB4erXjxLn3GZKlBFx743lM58qGdvmCOIAdTqFsiKG6rnuc+4p6L8BsQWZg09r3RoKP6T0GWrSNA9fAUuVRZMRSEpEUcP/OHxXu8xPJ'
    'x0B6uRE8+7q7WUPM7TIveIzIgKOM8zLygRXGAL28ywRharOka0/8FZ9NH/nhby90H/fBG9M1hRP4dAcsQve1AHjs7VBaMXHxA0I6TfgFICrWed/CvMkZcvQd'
    'OzxZOiOxx/iQlATwy3dXWIi1s3vnP9DgKiYx19j7rBDSAMsL/FLw2pz7xJB8euGUivIlWofP+9VDYAmCtbkS1ET96RcKc5CHVMyjzsvZbKVGfxP2BWuV2X4H'
    'B135qHy5z4WhWoIGvx2RgE5avlB6BpquLMjIsaVs6wItFg9EQSVxlILawm2+sCj08dPxxeWa4sGIUQJ3kYva2M4RmN1+lvysb2ddj6e35zdT+HFxdX50M/6J'
    'b2ht6P6zvqX16uBr88rE/79vaW2aLPim1puDpz+pRU7RtbEg6RZ+5Bj2Y42G7B+x03DIzhNlYE84M3eFkAT+fUeFS4e970SxxHIl9skh/i3hvGgNIhyyg+I+'
    'x0A/J90Vcv49PdycF6HH4ueF0wQRGp/++JF2IwV0pF6REPjhA1MkvI2ro+mUqhGPzs4pyn8+Of71+ISmjo7CaFrNVOTMGD357Ab8rC5LtLyR/54XmdxNWbKj'
    'wWcPtnpX6j8r+i92fDe8Fh82HndQJ3h6Mrh3GraNN98yDLuc9u6ChS3vN9zeCds/rF+9CJvPevApaPjVxlrrsMevexnToOF8CJi4yCnocTGoaONatrDHZb9+'
    'KWyaBIUj4ZhrufSwdT2bFtJIYvbBo6sg1B1OwsgqeCJhot7axeP2j7hgNxgRwzlSNHQjUdLTq2nURUoP5dYO8bZE4CisQA1jh9noV9/dd24+XrIsfskdeNG6'
    '8fHCTi5dm2B2maoDhYdcnaztMuqH6n55OIQP9CEDuywl3N8vi6FxBn7+IRd3D/1G7grSQv6167fukosCC1xmHnDoHh52aZn+LHwsOz2/bZeunmCc3bXvskO8'
    'uZUteiIpts5nQ9VFSr4DMQUm9wi5AvUXxvVE5UY98cNTbiVsQn0F3uTy5OzmbHJ5xD0d9H9BwTpXbYArxe9YWAcwEo7IY6IcOeX/AFBLAwQUAAAACADutgdd'
    'IjD7qvAOAAArOAAANQAAAHBhdGNoZXMvMDIxXzIwXzM1XzYwX05FV19HVUlERURfSU5UUk9fRklMRVMuZ2l0LnBhdGNoxRvZbhs58tn+Cq6eZFju6LItB/Ag'
    'iuMkwsaxIdnJ7AwGAdVNSRy3mpo+HHuDBPsR+4X7JVvFo8ludUvyDBY7Dx6brCrWxWIdnYDPZuToaM5TQl8ksf/CDzmL0hdvsmjORPQu4wELRlEaC0/teGFG'
    'MzLdHXY/Yl/JjIeMLEXASKfdPun393kUsEfSVv95Xrszm7an0/2joyPyImAPL6IsDPcPDw+fddKrV+So3WqTw06re3xMXr3aPwR6tzS5J902+c+//k0cTLKK'
    'WQKoNOUi8hBSQS94Qu5GBH66AEciCp88MkpJxB5YTOYxjdKE+GK5CllOAbAZSViMECsWJzwBGOfMCwXOAoLkCJ2lAJgCzozHSUrG7CuNAzJKQhoFkt6CJoT6'
    'aUZDAJ8yFuGJS54CCThw/zAUPg3JTUif4DRyTuZ0yV6+Y+kEeOA+azb0VuPAwI6zSG9WgdtdxDA4K0kE4DU17wMuqz+KMCArgKnfX36mPH0r4osFDwPDCQC4'
    'lD9djiej64+A03DUdOMo/lOnYYCvrj9dXl1+vP3y7nr4AVAGZuPu5s3w9vLL6OPt5fiT3Gp7na49ZZ5x8yuPkjTOfKRslgKWUh7mcsRiDscn5u8kpXF6IxLu'
    'okxpwkIesaHvsxWaE04s773nqFYOK84mC+kqKcLDAXO0ReNKPLCGZXqWRZJNtD9/YE3Q2l7M0iyOjH7BcMM0jfk0S8F0jv6GEqNxQM7PCUjL9g8Z+tMa5ViI'
    'VNJV6/6CxnCYtLQ6wrswS/ZwCwVOav96+Rau9Ft0Y23v99mSRoIHYzjkBnSIZq9mwxdZBBSaEXijI+WSpgtvSR+b7RZJRZQtpwBTJbrEOyAiJu3aM5ZiCiFo'
    'qxJ1gLmS0FcQr7Yr0Y8ZTRloXxLnM/Q2qRr4vweCgyPjFQff2dNHw2+a1N5c3pcROCWNfOZBqGw2JkCRRfqiIIT3EQRED1kPf3ejhoYZw5VJr6PJin6NAHZG'
    'w4TprdE8EjFyCOewlBhx5N4bnqAiruNAmv2sq9d/GWGAfs0W9IEL3LkEA5RWvQmfgqfPNcplRKeh9G33cK2BcxsgpODa4zDcleV/G4O4Unbc9oaRvxDxjeCS'
    'yifmpyLuSsi2d9winRzQXFKAunvDlw4MOFCnRY46nUEOPOH/ZAVABOgOFKwD95r69/MYHDS4EKGIe4CjfvFmsViO371udgCje9oi/W4F0i08E8kKVeA/ybDU'
    '7udAAnWOfNzwR6ajhNpSakZz9HLhjBrnRQUKjGdU6aaoxrsR0r7IAZRG8z+9Kx5pJbg67Q5Qp+1BGZg+VgD3T1Fb3X4JOOcVOS8wG0fSy8qMXsgNzSD+6qmV'
    'MQ14lmgzKXPCeccOXN1RwIq4Z1U6kRvyKAXjSXNWmbUPdu3ij+NjB3zNot2us7ng/n0ErwfsdLye3ajjM+VpuM7mLXtMP9ApCyWfEmbdu5HR69kMbnSz00eb'
    'WdhNzt114Gr9tJODICsYem7Go6vL0fiafLq+bhR26+/FGSrwNFegQnkrpB5kOMHfvXciXdDl6xB4KdDVQuA77qz+PAz5PFoyS6S46n1gszTHsBepbxW5Zgon'
    'J9hiCgdyq0F6/TLGJrP0TsvQG43jAm4yQrePDtxHSxx3yyfUmUKEQcURrj3Ke59julrJ0K+fljLArmYr4/2jEs+uerdiVUIr2rxgsTXLq9Rvi9EV0FZ7n/Yd'
    '4O03UANutLKG2XjLjsG2nQHeMhW0NU6Nba8YRNRlkbTm9ay4umZSZ29Xa2qUokWMOteMYTLvLeYwYBsSg45OC3LQytRApgQ9lRoMCuAF6zlmPu4C9GkBdKP9'
    'cqjNcRJe3G4PeT7pF2hvCZUF6o4RC+tbTTXm80XqYhWtZVVYtFd1LgxKmmA504yQJfxN58SqyPlxTvKNPCc29U++g4s6OZ/UVThuhSiRGi11xoFJrqsZzFYB'
    'JOsXYvXULHB2buqvnK1yJAIOnRpibw8z/MZdwoiAZJ+GYs59QcD8FJQAkKoDEFLCwwX1GhIF0gyJ8Xk4ebMZ1Llr+PhePq7AZZhHhlCypRRqVB75fAWCheyB'
    'kgcBxTzFhgZfMh4LIqa/M6gAhSJW8Ack1yEvSB+3GKTpBRWAssG3nqmEIRzwCCcfgTQBI9mSJCH8SbATMs9iRoa3w4vh2FFCPQZN6R8ZwyYHSTJKGFyooFon'
    '14RmjzzkAiksOSiT/p4FlPyRAVOgAqj0+ZLPBdCQGsMDBZ4gCc/QmVmNfrq1+rkGxaraepOKGqbNQ6wpQG+YHgNnkYBqdiUqhRoKzOj9MONxC5B9uuTRQrsV'
    'JTHDdhOLEnQcWAk5VMRAskaMXq0Yqs+0WYbhFE4QCQkET8iUZslLcnE9vgQNvr7+eDepZh+UDpczyHzwxgTkZDEIkNuEJo4ICZmBSy9R3hmPl2DmpEaOvitH'
    'Hbsje7DWYED/VsnjXKBg5IOYTp+kj2ZkkU3xbt0saMLaHSSQ8ihDLUu2zcUCtwEAkIGGNaxe/72xOf5g2MKemGTXbb1kMXok9kqATt6XKTSfMPY6YLL7Yv+2'
    'bxzcsAj7WXsVXSrTamlMvkL5OZGdSrM9ZnD1klT2CvequlhF5HxHF1PFLtZfi+DFML0plJswHqFGdKMs9+vqrkRlF8aBU/mOIrut03aR938n9IEFbrdIhjpQ'
    '1D3EMJ9V95kqKEXzApH8lTQvax5cpNpLmqqQDYTYwoSKBqrpvN453EWMMeY/iswNnLtdBh2Adpag7pHeeHkQsXxh0E2Kl8qQ2nTXPNv/3TPRtEy5hqpuMfPZ'
    'jGFmyGoIk6NyoznHnYXU5rc9mblact7PsqRwFn5RLzNwiIjeFZ1HPM3gjfzpvNRAz3l0DKMTAEVDGsD8r9IaGhyhUAdNibZbjCE/rXXRTX5QG2ccnHwVkQ4q'
    'ncw+1gcO/5WhpdDDfU7kGjMaPEHkQk9/JuonnA+JCJD1EESORSoCzsWCwi0LJpCx07Cyz//yQkQRyNo0wdFExbWIuP7+KOvaYAp/O4zYAcAwgFN3Pyilyb0X'
    'MPDKZuFMNz+X59iJk/eewQ2YgiXWjwlYmNJbruYDZohyeE7ydcWG2QFfL8+EDGOFCcyeI3iRrQqZ1nQnEXICQXmSGmKGYSaXjtXGUINDHpRWDFSfg7LTXPWE'
    'Ddrd6UntXPVZBzrj1U67VzVeTbEGVgEtkVMM8nWBHFKCzOoxIsc0UJEHO6TCHZA+e6j5vx9Rbh3RuBOaChXKEU39hGbDgKZiPtNrt9X68+YzlYlQ/XTGDDL9'
    '+yAWq/oBjYFYb5hMgAAzfZgcbPsw5RQbLC3SHVSjVY5TLFzVRCXfzfsaHWexPFbZZSy1y1QKfhjIyr6h0k8ZtLJr2DtRQ6nTtgHbYSYFOuwNWuQ4J12pm+Kw'
    'qWsYNjoxWrKKSRSD2wdNCFg7YUJpTto5VPVoqY9QgxxqrV2480hph4nSwILVnLPDPGnbOOmsME6qmyZ1BnavMEw6ztdrWNxhlLTDJGmg+9MbBknaIeV8Y/sc'
    'qThGmlzekdIoaYdJUucEdXdmdLfLIGltjtRtu4vl7nZpXNTLdVWt66kInjarGiG2avqkayA3KfqkZ6A26VkC5E0OyJ8TbIz5IlowH26Ibni0VLNwhg2lbEnd'
    'fg1ohAeUyAbKcgo5DTbLCh0bbHrkx9ROnHpop/6pmThJhI2TppykM2HK18qGkhuunZSi624tTbMt8wQFs8tXBhpy+2cGfQu8ya7droXbZFkNsvGGnOAE+EwO'
    'l84s1S1DIIewUX07X3V1bCSv1rLT3JpBjrxw2lomz4MkxOZctc2UsYUu9A9MqDffzp3v2pYpNWSKWZDLm2kN5Gc4I3oWxyLWF2tXCS4Rx/TFjI7Rh59WrJkT'
    'lLw1IKqjwJIHe9YP2MnravBYKBoj2Tx+oEvZuvZUCxLb6VBVYodY9SrtjVYgusKdAeCXFsFPpQCE8BXlcdL8BiTqLNAq7VmdtmqwlNSw+/2ABML2AOuLWfnl'
    'Vl7taf+xZbl1qJriSn1q+UKGtgqGTGEJ1Uuh3tkdbacia3p67J8MuluKrGcc6hRaZ4Ntn7GqRrYhQ+6ilIfkovhdqiTgIkENljwlKVseqQ9RsYElnQjCPgYV'
    '0wtXX7V+lkVc5XesP9TtahFG/QV5oCEPTGsdAJ/yW5ZgFS2J6UotRWdNIIwV+Eog3Skw/Zby8CihM/aSALcrEVMgqklA4U3B0eClw7trTiJT5tMsYc63udhR'
    'CtUHtQg5ZebjXBAAaYfwLkKhCgJIQCxjV/KzXFOxRsBrmsGTgI3wUEDh8GfrVLX0Bji3X+HG7I8MWG9CycxX5vMpT2pxDTz/jveWhQzUAU8CZPY8oqnMOqtJ'
    'VcA6LNU7IxD89t0CMjBvRlUEhhRmySC2YTRtfvveIt/Ily/yjkDgum+Q7weFD2jdunPt3VhlUKYmi0mKjRSl8pYNxQc7DBOc2OS+E+emL7eVwFjprYj/I8c3'
    'QdRwvOH+XmolaUGc8YR2JrCT7q3p9/RH3rQofSeqFNYi2o/uIvoAtwE1nk+ZZNPLmOVXRfe3OjLDMMZ2peEwwE/dpZdd4lW1NNcJOkMR3dDGq3e+7s0euL+R'
    'HCVdB/ggaLCuG0nPsL3dWErlr4GXe+wp00T2URv2NFdXB7UaLUM6beL1nANZ9CpjoM0wtnqyktiSfa7I8mFWUhz8FVVFPHTVokK4cRB7m4p9/8rsx2ry1sRn'
    'm3T93+SrZgspfqVxpOYUjV8dQr/ZF3SqaOF8mqhvFvY8z9xZbPTlaw33UZIu7NNIXnX1vLj/PKRhBhX1rmg5dfT+Fy28K7rO3Z6Lpuy1McrKCDPCgQ6VwfMN'
    'T2QK/trNgiwRHOXY2UFhzmB9cD10mtnRn6sM8umRnT7mBjBfFGe+D8lJiyzhp5p1Vzyr3sRfsCALmXOkE+1MuNPEZN5VlOh8/TH405fn2cZPhSpGmlrGg4PC'
    '/E9Zpxgy8udPyx00nvVaTjA5cD7Fit2g6JyUv002m8hfJDucrnC8irNLM7s6fORgjcaNCLn/JCugvVz2S8jrn+xDKjNwm4DLf8C0d/AMRmXuPcJcxDVW4zkk'
    'oKRKwZ0cSjqhbxwUTejUWnKt3lb7/wVQSwECFAMUAAAACADutgddqN5mtDA9AADE2gAADQAAAAAAAAAAAAAApIEAAAAAbWFuaWZlc3QuanNvblBLAQIUAxQA'
    'AAAIAO62B10TEBdnhAUAAFAQAAAxAAAAAAAAAAAAAACkgVs9AABwYXRjaGVzLzAwMV8wMV8wMV9UQVNLXzAxX0lOUFVUX1BST0ZJTEUuZ2l0LnBhdGNoUEsB'
    'AhQDFAAAAAgA7rYHXY6DzbtNDAAAcTAAADsAAAAAAAAAAAAAAKSBLkMAAHBhdGNoZXMvMDAyXzAyXzAxX1RBU0tfMDJfRFVOR0VPTl9QT1JUUkFJVF9DQU1F'
    'UkEuZ2l0LnBhdGNoUEsBAhQDFAAAAAgA7rYHXVhfso7mGwAAknIAADcAAAAAAAAAAAAAAKSB1E8AAHBhdGNoZXMvMDAzXzAzXzAxX1RBU0tfMDNfUE9SVFJB'
    'SVRfQ09NQkFUX0hVRC5naXQucGF0Y2hQSwECFAMUAAAACADutgddVYneJ1QNAAC0NAAAOwAAAAAAAAAAAAAApIEPbAAAcGF0Y2hlcy8wMDRfMDRfMDFfVEFT'
    'S18wNF9TT0ZUX0FJTV9UQVJHRVRfU0NPUklORy5naXQucGF0Y2hQSwECFAMUAAAACADutgddAuaSGVEJAAAiHwAAMgAAAAAAAAAAAAAApIG8eQAAcGF0Y2hl'
    'cy8wMDVfMDVfMDFfVEFTS18wNV9IT0xEX1RPX0FUVEFDSy5naXQucGF0Y2hQSwECFAMUAAAACADutgddRe4GZ3kLAADOKAAAPAAAAAAAAAAAAAAApIFdgwAA'
    'cGF0Y2hlcy8wMDZfMDZfMDFfVEFTS18wNl9TRVJWRVJfQ09NQkFUX1ZBTElEQVRJT04uZ2l0LnBhdGNoUEsBAhQDFAAAAAgA7rYHXcJQ5TwHBQAAOw0AADkA'
    'AAAAAAAAAAAAAKSBMI8AAHBhdGNoZXMvMDA3XzA3XzAxX1RBU0tfMDdfVE9MRVJBTlRfTUVMRUVfSElUQk9YLmdpdC5wYXRjaFBLAQIUAxQAAAAIAO62B13/'
    'hjNo1AkAACkgAAA/AAAAAAAAAAAAAACkgY6UAABwYXRjaGVzLzAwOF8wOF8wMV9UQVNLXzA4X1NUUk9OR19ISVRfRkVFREJBQ0tfSEFQVElDUy5naXQucGF0'
    'Y2hQSwECFAMUAAAACADutgddJBNLgkoUAACQSAAAPwAAAAAAAAAAAAAApIG/ngAAcGF0Y2hlcy8wMDlfMDlfMDFfVEFTS18wOV9PRkZTQ1JFRU5fVEhSRUFU'
    'X0lORElDQVRPUlMuZ2l0LnBhdGNoUEsBAhQDFAAAAAgA7rYHXXrnp6uLDgAA6TYAAD4AAAAAAAAAAAAAAKSBZrMAAHBhdGNoZXMvMDEwXzEwXzAxX1RBU0tf'
    'MTBfUE9SVFJBSVRfRU5FTVlfUkVBREFCSUxJVFkuZ2l0LnBhdGNoUEsBAhQDFAAAAAgA7rYHXeMQcsb9EgAAwUYAAEIAAAAAAAAAAAAAAKSBTcIAAHBhdGNo'
    'ZXMvMDExXzExXzAxX1RBU0tfMTFfUE9SVFJBSVRfT0JKRUNUSVZFX1JFV0FSRF9GTE9XLmdpdC5wYXRjaFBLAQIUAxQAAAAIAO62B13DpfqPrA0AAIk1AAA/'
    'AAAAAAAAAAAAAACkgarVAABwYXRjaGVzLzAxMl8xMl8wMV9UQVNLXzEyX05FWFRfSVNMQU5EX0NBTUVSQV9HVUlEQU5DRS5naXQucGF0Y2hQSwECFAMUAAAA'
    'CADutgddyFRnilUNAACFMgAAOwAAAAAAAAAAAAAApIGz4wAAcGF0Y2hlcy8wMTNfMTNfMDFfVEFTS18xM19CT1NTX0NBTUVSQV9JTlRFR1JBVElPTi5naXQu'
    'cGF0Y2hQSwECFAMUAAAACADutgddLFweQOYLAAAWMAAAOAAAAAAAAAAAAAAApIFh8QAAcGF0Y2hlcy8wMTRfMTRfMDFfQ0FNRVJBX1NBRkVfWk9ORV9TRVJW'
    'SUNFX05FVy5naXQucGF0Y2hQSwECFAMUAAAACADutgddYrSP8TsRAAAaRwAANQAAAAAAAAAAAAAApIGd/QAAcGF0Y2hlcy8wMTVfMTVfMDFfUE9SVFJBSVRf'
    'Uk9VVEVfR0VORVJBVElPTi5naXQucGF0Y2hQSwECFAMUAAAACADutgddF0dSpe0AAAD0AQAAOQAAAAAAAAAAAAAApIErDwEAcGF0Y2hlcy8wMTZfMTZfMDFf'
    'Q0FNRVJBX1NBRkVfWk9ORV9SRVRVUk5fUk9VVEUuZ2l0LnBhdGNoUEsBAhQDFAAAAAgA7rYHXXk//NcvEQAAL0gAADoAAAAAAAAAAAAAAKSBbxABAHBhdGNo'
    'ZXMvMDE3XzE2XzAyX1BPUlRSQUlUX1NBRkVfU1BBV05fUE9MSUNZX05FVy5naXQucGF0Y2hQSwECFAMUAAAACADutgddXzvm5ioaAADUYwAAQAAAAAAAAAAA'
    'AAAApIH2IQEAcGF0Y2hlcy8wMThfMTdfMDFfVEFTS18xN19ERVZJQ0VfU0NBTElOR19BQ0NFU1NJQklMSVRZLmdpdC5wYXRjaFBLAQIUAxQAAAAIAO62B13h'
    'SFE1xhMAAFJUAAA7AAAAAAAAAAAAAACkgX48AQBwYXRjaGVzLzAxOV8xOF8wMV9UQVNLXzE4X01PQklMRV9DT01CQVRfVEVMRU1FVFJZLmdpdC5wYXRjaFBL'
    'AQIUAxQAAAAIAO62B11lUPQjBx8AAKhSAABGAAAAAAAAAAAAAACkgZ1QAQBwYXRjaGVzLzAyMF8xOV8wMV9UQVNLXzE5X0VNVUxBVE9SX1JFQUxfREVWSUNF'
    'X1RFU1RfUFJPVE9DT0wuZ2l0LnBhdGNoUEsBAhQDFAAAAAgA7rYHXSIw+6rwDgAAKzgAADUAAAAAAAAAAAAAAKSBCHABAHBhdGNoZXMvMDIxXzIwXzM1XzYw'
    'X05FV19HVUlERURfSU5UUk9fRklMRVMuZ2l0LnBhdGNoUEsFBgAAAAAWABYA1AgAAEt/AQAAAA=='
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

    if ([int]$Manifest.installer_version -ne $InstallerVersion) {
        throw "Versao do manifest nao corresponde ao instalador."
    }

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
    Write-Host ' INSTALACAO V5 CONCLUIDA COM SUCESSO' -ForegroundColor Green
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
