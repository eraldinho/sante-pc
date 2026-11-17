$racine = Split-Path -Parent $PSScriptRoot
$cible = Join-Path $racine 'sante.ps1'
$empreinte = Join-Path $racine 'sante.ps1.sha256'
$hash = (Get-FileHash -LiteralPath $cible -Algorithm SHA256).Hash
$ligne = $hash + '  sante.ps1' + "`n"
$encodage = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($empreinte, $ligne, $encodage)
Write-Output $hash
