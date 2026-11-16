# Tests Pester 5 de Santé PC. Ce fichier n'est jamais chargé par sante.ps1.

Describe 'Santé PC' {
BeforeAll {
function New-SanteEvt {
    param(
        [string]$Log = 'System',
        [string]$Provider = 'Test',
        [int]$Id = 1,
        [int]$Level = 2,
        [string]$Message = '',
        $Properties = @(),
        $TimeCreated = (Get-Date)
    )
    [pscustomobject]@{
        LogName      = $Log
        ProviderName = $Provider
        Id           = $Id
        Level        = $Level
        Message      = $Message
        TimeCreated  = $TimeCreated
        Properties   = $Properties
    }
}

function New-SanteVolume {
    param([string]$Lettre, [double]$Taille, [double]$Libre)
    [pscustomobject]@{
        DriveLetter   = $Lettre
        Size          = $Taille
        SizeRemaining = $Libre
    }
}

function New-SanteBatterie {
    param($Charge, $Design = $null, $Plein = $null)
    $bat = [pscustomobject]@{
        Name                     = 'BAT'
        EstimatedChargeRemaining = $Charge
        DesignCapacity           = $null
        FullChargeCapacity       = $null
    }
    $statique = $null
    $pleine = $null
    if ($null -ne $Design) { $statique = [pscustomobject]@{ DesignedCapacity = $Design } }
    if ($null -ne $Plein) { $pleine = [pscustomobject]@{ FullChargedCapacity = $Plein } }
    [pscustomobject]@{ Batterie = $bat; Statique = $statique; Pleine = $pleine }
}

function Install-SanteStubs {
    $signatures = @{
        'Get-Volume'                     = '[CmdletBinding()] param()'
        'Get-CimInstance'                = '[CmdletBinding()] param([string]$ClassName, [string]$Namespace, [string]$Filter, $Property, [string]$Query, [Parameter(ValueFromPipeline=$true)]$InputObject)'
        'Get-ComputerInfo'               = '[CmdletBinding()] param()'
        'Get-PnpDevice'                  = '[CmdletBinding()] param()'
        'Get-Service'                    = '[CmdletBinding()] param()'
        'Get-WinEvent'                   = '[CmdletBinding()] param($FilterHashtable, [int]$MaxEvents)'
        'Get-MpComputerStatus'           = '[CmdletBinding()] param()'
        'Confirm-SecureBootUEFI'         = '[CmdletBinding()] param()'
        'Repair-WindowsImage'            = '[CmdletBinding()] param([switch]$Online, [switch]$CheckHealth, [switch]$ScanHealth)'
        'Get-PhysicalDisk'               = '[CmdletBinding()] param()'
        'Get-StorageReliabilityCounter'  = '[CmdletBinding()] param($PhysicalDisk)'
        'Get-WindowsPackage'             = '[CmdletBinding()] param([switch]$Online)'
        'Unblock-File'                   = '[CmdletBinding()] param([string]$LiteralPath)'
    }
    foreach ($nom in $signatures.Keys) {
        if (Get-Command -Name $nom -ErrorAction SilentlyContinue) { continue }
        $corps = "function global:$nom { $($signatures[$nom]) }"
        Invoke-Expression $corps
    }
}

    $script:SanteRoot = Split-Path -Parent $PSScriptRoot
    $script:SantePath = Join-Path $script:SanteRoot 'sante.ps1'
    Install-SanteStubs
    . $script:SantePath

    Mock Write-Host { }
    Mock Test-SanteAdministrator { $true }
    Mock Get-ComputerInfo {
        if ($script:InfoThrow) { throw $script:InfoThrow }
        $script:ComputerInfo
    }
    Mock Get-Volume {
        if ($script:VolumeThrow) { throw $script:VolumeThrow }
        $script:Volumes
    }
    Mock Get-CimInstance {
        $cle = [string]$ClassName
        if ($script:CimData.ContainsKey($cle)) { return $script:CimData[$cle] }
        $null
    }
    Mock Get-PnpDevice {
        if ($script:PnpThrow) { throw $script:PnpThrow }
        $script:Pnp
    }
    Mock Get-Service {
        if ($script:ServiceThrow) { throw $script:ServiceThrow }
        $script:Services
    }
    Mock Get-WinEvent {
        if ($script:WinThrow) { throw $script:WinThrow }
        $fh = $FilterHashtable
        $out = New-Object System.Collections.Generic.List[object]
        foreach ($evenement in @($script:WinEvents)) {
            if ($null -eq $evenement) { continue }
            if ($null -ne $fh.LogName -and [string]$evenement.LogName -ne [string]$fh.LogName) { continue }
            if ($null -ne $fh.ProviderName) {
                $ok = $false
                foreach ($nom in @($fh.ProviderName)) {
                    if ([string]$evenement.ProviderName -eq [string]$nom) { $ok = $true }
                }
                if (-not $ok) { continue }
            }
            if ($null -ne $fh.Id) {
                $ok = $false
                foreach ($id in @($fh.Id)) {
                    if ([int]$evenement.Id -eq [int]$id) { $ok = $true }
                }
                if (-not $ok) { continue }
            }
            if ($null -ne $fh.Level) {
                $ok = $false
                foreach ($niveau in @($fh.Level)) {
                    if ([int]$evenement.Level -eq [int]$niveau) { $ok = $true }
                }
                if (-not $ok) { continue }
            }
            [void]$out.Add($evenement)
        }
        if ($out.Count -eq 0) { throw 'No events were found that match the specified selection criteria.' }
        $out.ToArray()
    }
    Mock Get-MpComputerStatus {
        if ($script:MpThrow) { throw $script:MpThrow }
        $script:Mp
    }
    Mock Confirm-SecureBootUEFI {
        if ($null -eq $script:SecureBoot) { throw 'Secure Boot indisponible.' }
        $script:SecureBoot
    }
    Mock Repair-WindowsImage {
        if ($script:ImageThrow) { throw $script:ImageThrow }
        [pscustomobject]@{
            ImageHealthState = [string]$script:ImageEtat
            HealthState      = [string]$script:ImageSecondaire
        }
    }
    Mock Get-PhysicalDisk { $script:Physical }
    Mock Get-StorageReliabilityCounter { $script:Compteur }
    Mock Get-WindowsPackage { $script:Packages }
    Mock Invoke-SanteProcess { $script:ProcessusTexte } -ParameterFilter { $Fichier -match 'sfc|powercfg' }
    Mock Read-SanteAjout { $script:AjoutSfc } -ParameterFilter { $Chemin -eq 'C:\Windows\Logs\CBS\CBS.log' }
    Mock Test-Path { [bool]$script:RebootPresent } -ParameterFilter { "$LiteralPath" -like '*Component Based Servicing*' }
    Mock Test-Path { [bool]$script:MinidumpPresent } -ParameterFilter { "$LiteralPath" -eq 'C:\Windows\Minidump' }
    Mock Get-ChildItem { $script:Minidumps } -ParameterFilter { "$LiteralPath" -eq 'C:\Windows\Minidump' }
}

BeforeEach {
    if (-not $env:TEMP) { $env:TEMP = [IO.Path]::GetTempPath().TrimEnd('\', '/') }
    $env:SystemDrive = 'C:'
    $env:SANTE_PASSE = $null
    $env:SANTE_RELAUNCHED = $null
    $script:CimData = @{}
    $script:WinEvents = @()
    $script:WinThrow = $null
    $script:ComputerInfo = $null
    $script:InfoThrow = $null
    $script:Volumes = $null
    $script:VolumeThrow = $null
    $script:Pnp = $null
    $script:PnpThrow = $null
    $script:Services = $null
    $script:ServiceThrow = $null
    $script:Mp = $null
    $script:MpThrow = $null
    $script:SecureBoot = $null
    $script:ImageEtat = $null
    $script:ImageSecondaire = $null
    $script:ImageThrow = $null
    $script:Physical = $null
    $script:Compteur = $null
    $script:Packages = $null
    $script:ProcessusTexte = $null
    $script:AjoutSfc = ''
    $script:RebootPresent = $false
    $script:MinidumpPresent = $false
    $script:Minidumps = @()
}

Describe 'Fichier' {
    It 'porte le BOM UTF-8 et des fins CRLF' {
        $octets = [IO.File]::ReadAllBytes($script:SantePath)
        $octets[0] | Should -Be 0xEF
        $octets[1] | Should -Be 0xBB
        $octets[2] | Should -Be 0xBF
        $texte = [IO.File]::ReadAllText($script:SantePath)
        $texte | Should -Match "`r`n"
        [regex]::IsMatch($texte, "(?<!`r)`n") | Should -BeFalse
    }

    It 'ne commence pas par param, n appelle pas exit, n importe rien et ne charge pas un voisin' {
        $texte = [IO.File]::ReadAllText($script:SantePath)
        $texte | Should -Not -Match '(?m)\A\s*param\s*\('
        $texte | Should -Not -Match '(?i)\bexit\b'
        $texte | Should -Not -Match 'Import-Module'
        $texte | Should -Not -Match '(?m)^\s*\.\s+\S'
    }

    It 'publie une empreinte égale aux octets du fichier' {
        $hashPath = Join-Path $script:SanteRoot 'sante.ps1.sha256'
        $ligne = [IO.File]::ReadAllText($hashPath)
        $ligne.Trim().Split()[0] | Should -Be (Get-FileHash -LiteralPath $script:SantePath -Algorithm SHA256).Hash
        $octets = [IO.File]::ReadAllBytes($hashPath)
        $octets[0] | Should -Not -Be 0xEF
        $ligne | Should -Match '^[0-9A-F]{64}  sante\.ps1'
    }

    It 'fige la version et l URL canonique dans le fichier' {
        $texte = [IO.File]::ReadAllText($script:SantePath)
        $texte | Should -Match '1\.0\.0'
        $texte | Should -Match 'https://raw\.githubusercontent\.com/eraldinho/sante-pc/v1\.0\.0/sante\.ps1'
    }
}

Describe 'Démarrage' {
    It 'affiche la version et l URL canonique' {
        Mock Write-Host { }
        Invoke-SantePc -Passe Rapide | Out-Null
        Should -Invoke Write-Host -ParameterFilter { $Object -eq 'Santé PC 1.0.0' } -Times 1 -Scope It
        Should -Invoke Write-Host -ParameterFilter { $Object -eq 'https://raw.githubusercontent.com/eraldinho/sante-pc/v1.0.0/sante.ps1' } -Times 1 -Scope It
    }

    It 'un point-source ne lance pas la passe' {
        Mock Write-Host { }
        . $script:SantePath
        Should -Invoke Write-Host -Times 0 -Scope It
    }

    It 'lit la passe demandée' {
        $env:SANTE_PASSE = 'Complete'
        Get-SantePasseDemandee -Arguments @() | Should -Be 'Complete'
        $env:SANTE_PASSE = $null
        Get-SantePasseDemandee -Arguments @('Complete', '-DejaRelance') | Should -Be 'Complete'
        $env:SANTE_RELAUNCHED | Should -Be '1'
        Get-SantePasseDemandee -Arguments @('Rapide') | Should -Be 'Rapide'
    }
}

Describe 'Récapitulatif' {
    It 'prend le pire état et ignore NonExécuté' {
        $lignes = @(
            (New-SanteRow -Controle 'A' -Etat 'OK' -Message 'a'),
            (New-SanteRow -Controle 'B' -Etat 'Attention' -Message 'b'),
            (New-SanteRow -Controle 'C' -Etat 'NonExécuté' -Message 'c')
        )
        $resume = Get-SanteSummary -Lignes $lignes
        $resume.Etat | Should -Be 'Attention'
        $resume.Controle | Should -Be 'Récapitulatif'
        $resume.Message | Should -Match "n'innocente pas le matériel"
    }

    It 'omet la phrase quand un contrôle est en Erreur' {
        $lignes = @(
            (New-SanteRow -Controle 'A' -Etat 'Erreur' -Message 'a'),
            (New-SanteRow -Controle 'B' -Etat 'NonExécuté' -Message 'b')
        )
        $resume = Get-SanteSummary -Lignes $lignes
        $resume.Etat | Should -Be 'Erreur'
        $resume.Message | Should -Not -Match 'innocente'
    }

    It 'reste NonExécuté si rien n a été noté et rappelle la phrase' {
        $lignes = @(New-SanteRow -Controle 'A' -Etat 'NonExécuté' -Message 'a')
        $resume = Get-SanteSummary -Lignes $lignes
        $resume.Etat | Should -Be 'NonExécuté'
        $resume.Message | Should -Match "n'innocente pas le matériel"
    }
}

Describe 'Identité' {
    It 'est OK quand la lecture a fourni le modèle, le BIOS et Windows' {
        $script:CimData['Win32_ComputerSystem'] = [pscustomobject]@{ Model = 'OMEN' }
        $script:CimData['Win32_BIOS'] = [pscustomobject]@{ SMBIOSBIOSVersion = 'F.12' }
        $script:CimData['Win32_OperatingSystem'] = [pscustomobject]@{
            Caption        = 'Windows 11'
            LastBootUpTime = (Get-Date).AddHours(-5)
        }
        $resultat = Get-SanteIdentite
        $resultat.Etat | Should -Be 'OK'
        $resultat.Message | Should -Match 'OMEN'
        $resultat.Message | Should -Match 'F\.12'
        $resultat.Message | Should -Match 'Windows 11'
        $resultat.Message | Should -Match '0 j 5 h'
    }

    It 'est NonExécuté quand rien n est lisible' {
        $resultat = Get-SanteIdentite
        $resultat.Etat | Should -Be 'NonExécuté'
    }
}

Describe 'Disque' {
    It 'est OK au-dessus des seuils' {
        $script:Volumes = @(New-SanteVolume -Lettre 'C' -Taille 100GB -Libre 50GB)
        $resultat = Get-SanteDisque
        $resultat.Etat | Should -Be 'OK'
        $resultat.Message | Should -Match '50\.0 Go libres \(50\.0 %\), système'
    }

    It 'est Attention sous 10 pour cent' {
        $script:Volumes = @(New-SanteVolume -Lettre 'C' -Taille 100GB -Libre 8GB)
        (Get-SanteDisque).Etat | Should -Be 'Attention'
    }

    It 'est Erreur sous 5 pour cent' {
        $script:Volumes = @(New-SanteVolume -Lettre 'C' -Taille 100GB -Libre 4GB)
        (Get-SanteDisque).Etat | Should -Be 'Erreur'
    }

    It 'est Attention sous 20 Go sur le volume système même au-dessus de 10 pour cent' {
        $script:Volumes = @(New-SanteVolume -Lettre 'C' -Taille 100GB -Libre 15GB)
        $resultat = Get-SanteDisque
        $resultat.Etat | Should -Be 'Attention'
        $resultat.Message | Should -Match '15\.0'
    }

    It 'n applique pas le seuil de 20 Go à un autre volume' {
        $script:Volumes = @(
            (New-SanteVolume -Lettre 'C' -Taille 200GB -Libre 100GB),
            (New-SanteVolume -Lettre 'D' -Taille 30GB -Libre 15GB)
        )
        (Get-SanteDisque).Etat | Should -Be 'OK'
    }

    It 'retombe sur Win32_LogicalDisk' {
        $script:VolumeThrow = 'pas de Get-Volume'
        $script:CimData['Win32_LogicalDisk'] = [pscustomobject]@{
            DeviceID  = 'C:'
            DriveType = 3
            Size      = 100GB
            FreeSpace = 50GB
        }
        (Get-SanteDisque).Etat | Should -Be 'OK'
    }

    It 'est NonExécuté sans volume' {
        (Get-SanteDisque).Etat | Should -Be 'NonExécuté'
    }

    It 'garde le point décimal même si la culture courante est fr-FR' {
        $culture = $null
        try { $culture = [Globalization.CultureInfo]::GetCultureInfo('fr-FR') }
        catch { Set-ItResult -Skipped -Because 'culture fr-FR indisponible'; return }
        $fil = [Threading.Thread]::CurrentThread
        $sauve = $fil.CurrentCulture
        $fil.CurrentCulture = $culture
        try {
            $script:Volumes = @(New-SanteVolume -Lettre 'C' -Taille 100GB -Libre 50GB)
            (Get-SanteDisque).Message | Should -Match '50\.0'
        }
        finally { $fil.CurrentCulture = $sauve }
    }
}

Describe 'Batterie' {
    It 'est NonExécuté sans batterie' {
        $resultat = Get-SanteBatterie
        $resultat.Etat | Should -Be 'NonExécuté'
        $resultat.Message | Should -Be 'aucune batterie'
    }

    It 'est OK à 20 pour cent d usure' {
        $jeu = New-SanteBatterie -Charge 80 -Design 100 -Plein 80
        $script:CimData['Win32_Battery'] = $jeu.Batterie
        $script:CimData['BatteryStaticData'] = $jeu.Statique
        $script:CimData['BatteryFullChargedCapacity'] = $jeu.Pleine
        $resultat = Get-SanteBatterie
        $resultat.Etat | Should -Be 'OK'
        $resultat.Message | Should -Match '20\.0 %'
    }

    It 'est Attention au-dessus de 20 pour cent et à 40 pour cent' {
        $jeu = New-SanteBatterie -Charge 70 -Design 100 -Plein 70
        $script:CimData['Win32_Battery'] = $jeu.Batterie
        $script:CimData['BatteryStaticData'] = $jeu.Statique
        $script:CimData['BatteryFullChargedCapacity'] = $jeu.Pleine
        (Get-SanteBatterie).Etat | Should -Be 'Attention'
        $jeu = New-SanteBatterie -Charge 60 -Design 100 -Plein 60
        $script:CimData['Win32_Battery'] = $jeu.Batterie
        $script:CimData['BatteryStaticData'] = $jeu.Statique
        $script:CimData['BatteryFullChargedCapacity'] = $jeu.Pleine
        (Get-SanteBatterie).Etat | Should -Be 'Attention'
    }

    It 'est Erreur au-dessus de 40 pour cent' {
        $jeu = New-SanteBatterie -Charge 40 -Design 100 -Plein 50
        $script:CimData['Win32_Battery'] = $jeu.Batterie
        $script:CimData['BatteryStaticData'] = $jeu.Statique
        $script:CimData['BatteryFullChargedCapacity'] = $jeu.Pleine
        (Get-SanteBatterie).Etat | Should -Be 'Erreur'
    }

    It 'est Erreur quand la charge est impossible' {
        $jeu = New-SanteBatterie -Charge $null -Design 50000 -Plein 0
        $script:CimData['Win32_Battery'] = $jeu.Batterie
        $script:CimData['BatteryStaticData'] = $jeu.Statique
        $script:CimData['BatteryFullChargedCapacity'] = $jeu.Pleine
        $resultat = Get-SanteBatterie
        $resultat.Etat | Should -Be 'Erreur'
        $resultat.Message | Should -Match 'Charge impossible'
    }
}

Describe 'Périphériques et pilotes' {
    It 'est OK sans appareil en défaut et ne juge pas une date ancienne' {
        $script:Pnp = @([pscustomobject]@{ FriendlyName = 'Carte saine'; Problem = 0; Status = 'OK'; InstanceId = 'PCI\OK' })
        $script:CimData['Win32_PnPSignedDriver'] = @([pscustomobject]@{
                DeviceID           = 'PCI\OK'
                DriverVersion      = '1.0'
                DriverDate         = [datetime]'2012-01-01'
                DriverProviderName = 'Vieux'
            })
        (Get-SantePeripheriques).Etat | Should -Be 'OK'
        $pilotes = Get-SantePilotes
        $pilotes.Etat | Should -Be 'OK'
        $pilotes.Message | Should -Not -Match '2012'
    }

    It 'met le code 22 en Attention et les codes 10, 28, 31, 39, 43 en Erreur' {
        foreach ($code in @(22)) {
            $script:Pnp = @([pscustomobject]@{ FriendlyName = 'X'; Problem = $code; Status = 'Error'; InstanceId = 'ID' })
            (Get-SantePeripheriques).Etat | Should -Be 'Attention'
        }
        foreach ($code in @(10, 28, 31, 39, 43)) {
            $script:Pnp = @([pscustomobject]@{ FriendlyName = 'X'; Problem = $code; Status = 'Error'; InstanceId = 'ID' })
            (Get-SantePeripheriques).Etat | Should -Be 'Erreur'
        }
    }

    It 'comprend le nom d enum CM_PROB_FAILED_START' {
        $script:Pnp = @([pscustomobject]@{ FriendlyName = 'X'; Problem = 'CM_PROB_FAILED_START'; Status = 'Error'; InstanceId = 'ID' })
        (Get-SantePeripheriques).Etat | Should -Be 'Erreur'
    }

    It 'cite version, date, éditeur et fichier sys de l appareil en défaut' {
        $script:Pnp = @([pscustomobject]@{ FriendlyName = 'Gpu'; Problem = 10; Status = 'Error'; InstanceId = 'PCI\GPU' })
        $script:CimData['Win32_PnPSignedDriver'] = @([pscustomobject]@{
                DeviceID           = 'PCI\GPU'
                DriverVersion      = '32.0.1'
                DriverDate         = [datetime]'2020-05-01'
                DriverProviderName = 'Contoso'
            })
        $script:CimData['Win32_PnPEntity'] = @([pscustomobject]@{ DeviceID = 'PCI\GPU'; Service = 'gpu' })
        $script:CimData['Win32_SystemDriver'] = @([pscustomobject]@{ Name = 'gpu'; PathName = 'C:\Windows\System32\drivers\gpu.sys' })
        $resultat = Get-SantePilotes
        $resultat.Etat | Should -Be 'Erreur'
        $resultat.Message | Should -Match '32\.0\.1'
        $resultat.Message | Should -Match '2020-05-01'
        $resultat.Message | Should -Match 'Contoso'
        $resultat.Message | Should -Match 'gpu\.sys'
    }

    It 'est NonExécuté quand la lecture des périphériques échoue' {
        $script:PnpThrow = 'Access is denied.'
        (Get-SantePeripheriques).Etat | Should -Be 'NonExécuté'
        (Get-SantePilotes).Etat | Should -Be 'NonExécuté'
    }
}

Describe 'Services' {
    It 'ignore Manual et Automatique différé, et signale un Automatique arrêté' {
        $script:Services = @(
            [pscustomobject]@{ Name = 'bon'; Status = 'Running'; StartType = 'Automatic' },
            [pscustomobject]@{ Name = 'arrete'; Status = 'Stopped'; StartType = 'Automatic' },
            [pscustomobject]@{ Name = 'manuel'; Status = 'Stopped'; StartType = 'Manual' },
            [pscustomobject]@{ Name = 'differe'; Status = 'Stopped'; StartType = 'Automatic' }
        )
        $script:CimData['Win32_Service'] = @(
            [pscustomobject]@{ Name = 'differe'; DelayedAutoStart = $true }
        )
        $resultat = Get-SanteServices
        $resultat.Etat | Should -Be 'Attention'
        $resultat.Message | Should -Match 'arrete'
        $resultat.Message | Should -Not -Match 'manuel'
        $resultat.Message | Should -Not -Match 'differe'
    }

    It 'est OK quand les services Automatique tournent' {
        $script:Services = @([pscustomobject]@{ Name = 'bon'; Status = 'Running'; StartType = 'Automatic' })
        (Get-SanteServices).Etat | Should -Be 'OK'
    }

    It 'est NonExécuté si la liste est illisible' {
        $script:ServiceThrow = 'Access is denied.'
        (Get-SanteServices).Etat | Should -Be 'NonExécuté'
    }
}

Describe 'Journal' {
    It 'est OK sans Critique ni Erreur' {
        $resultat = Get-SanteJournal
        $resultat.Etat | Should -Be 'OK'
        $resultat.Message | Should -Match '48 h'
    }

    It 'est Attention pour une Erreur et Erreur pour une Critique' {
        $script:WinEvents = @(New-SanteEvt -Log 'Application' -Provider 'App' -Id 1000 -Level 2 -Message 'boom')
        (Get-SanteJournal).Etat | Should -Be 'Attention'
        $script:WinEvents = @(New-SanteEvt -Log 'System' -Provider 'Sys' -Id 41 -Level 1 -Message 'critique')
        (Get-SanteJournal).Etat | Should -Be 'Erreur'
    }

    It 'ignore un événement plus vieux que 48 heures' {
        $script:WinEvents = @(New-SanteEvt -Level 1 -TimeCreated (Get-Date).AddHours(-80) -Message 'vieux')
        (Get-SanteJournal).Etat | Should -Be 'OK'
    }

    It 'est NonExécuté si le journal est refusé' {
        $script:WinThrow = 'Access is denied.'
        (Get-SanteJournal).Etat | Should -Be 'NonExécuté'
    }
}

Describe 'Defender et Secure Boot' {
    It 'est OK avec le temps réel actif et des signatures récentes' {
        $script:Mp = [pscustomobject]@{
            AMEngineVersion               = '1.1.1'
            AntivirusSignatureVersion     = '1.2.3'
            AntivirusSignatureLastUpdated = (Get-Date).AddDays(-1)
            RealTimeProtectionEnabled     = $true
            QuickScanEndTime              = (Get-Date).AddDays(-40)
        }
        $resultat = Get-SanteDefender
        $resultat.Etat | Should -Be 'OK'
        $resultat.Message | Should -Match '1\.1\.1'
        $resultat.Message | Should -Match '40\.0'
    }

    It 'est Attention si le temps réel est inactif ou si les signatures ont plus de 7 jours' {
        $script:Mp = [pscustomobject]@{
            AMEngineVersion               = '1.1.1'
            AntivirusSignatureVersion     = '1.2.3'
            AntivirusSignatureLastUpdated = (Get-Date).AddDays(-1)
            RealTimeProtectionEnabled     = $false
            QuickScanEndTime              = (Get-Date)
        }
        (Get-SanteDefender).Etat | Should -Be 'Attention'
        $script:Mp.RealTimeProtectionEnabled = $true
        $script:Mp.AntivirusSignatureLastUpdated = (Get-Date).AddDays(-8)
        (Get-SanteDefender).Etat | Should -Be 'Attention'
    }

    It 'est NonExécuté sans état Defender' {
        (Get-SanteDefender).Etat | Should -Be 'NonExécuté'
        $script:MpThrow = 'mp indisponible'
        (Get-SanteDefender).Etat | Should -Be 'NonExécuté'
    }

    It 'lit Secure Boot' {
        $script:SecureBoot = $true
        (Get-SanteSecureBoot).Etat | Should -Be 'OK'
        $script:SecureBoot = $false
        $resultat = Get-SanteSecureBoot
        $resultat.Etat | Should -Be 'Attention'
        $resultat.Message | Should -Match 'désactivé'
        $script:SecureBoot = $null
        (Get-SanteSecureBoot).Etat | Should -Be 'NonExécuté'
    }
}

Describe 'Image et redémarrage' {
    It 'CheckHealth Healthy dit que le magasin n a pas été parcouru' {
        $script:ImageEtat = 'Healthy'
        $resultat = Get-SanteCheckHealth
        $resultat.Etat | Should -Be 'OK'
        $resultat.Message | Should -Match "n'a pas été parcouru"
    }

    It 'ScanHealth Healthy dit que le magasin a été parcouru' {
        $script:ImageEtat = 'Healthy'
        $resultat = Get-SanteScanHealth
        $resultat.Etat | Should -Be 'OK'
        $resultat.Message | Should -Match 'a été parcouru'
        $resultat.Message | Should -Not -Match "n'a pas été parcouru"
    }

    It 'Repairable et NonRepairable sont des Erreurs' {
        foreach ($etat in @('Repairable', 'NonRepairable')) {
            $script:ImageEtat = $etat
            (Get-SanteCheckHealth).Etat | Should -Be 'Erreur'
            (Get-SanteScanHealth).Etat | Should -Be 'Erreur'
        }
    }

    It 'retombe sur HealthState' {
        $script:ImageEtat = ''
        $script:ImageSecondaire = 'Healthy'
        (Get-SanteCheckHealth).Etat | Should -Be 'OK'
    }

    It 'redémarrage en attente est Attention, sinon OK' {
        $script:RebootPresent = $true
        $resultat = Get-SanteRedemarrage
        $resultat.Etat | Should -Be 'Attention'
        $resultat.Message | Should -Be 'redémarrage en attente'
        $script:RebootPresent = $false
        (Get-SanteRedemarrage).Etat | Should -Be 'OK'
    }
}

Describe 'Échecs de paquets' {
    It 'cite le HRESULT connu, le delta et laisse un code inconnu en numérique' {
        (Format-SanteHresult -Texte 'échec 0x80073712') | Should -Match '0x80073712 Magasin de composants incohérent'
        (Format-SanteHresult -Texte '0x800F0831') | Should -Match '0x800f0831 Magasin CBS corrompu'
        (Format-SanteHresult -Texte '0x800f081f') | Should -Match 'Fichiers sources introuvables'
        (Format-SanteHresult -Texte '0x80073701') | Should -Match 'Composant manquant'
        (Format-SanteHresult -Texte '0x800736CC') | Should -Match 'Empreinte de fichier différente du manifeste'
        (Format-SanteHresult -Texte '0x800f0830') | Should -Match "Image plus réparable par l'entretien"
        (Format-SanteHresult -Texte '0x800f0982') | Should -Match 'delta de mise à jour cumulative'
        (Format-SanteHresult -Texte '0x800f0988') | Should -Match 'delta de mise à jour cumulative'
        (Format-SanteHresult -Texte '0x800f0981') | Should -Be '0x800f0981'
        (Format-SanteHresult -Texte '0x800f0989') | Should -Be '0x800f0989'
        (ConvertTo-SanteHex -Valeur ([int]0x80073712)) | Should -Be '0x80073712'
    }

    It 'fait une Erreur par événement 3' {
        $script:WinEvents = @(
            (New-SanteEvt -Log 'Setup' -Provider 'Microsoft-Windows-Servicing' -Id 3 -Level 2 -Message '0x80073712' -Properties @([pscustomobject]@{ Value = 'Package_for_KB1' })),
            (New-SanteEvt -Log 'Setup' -Provider 'Microsoft-Windows-Servicing' -Id 3 -Level 2 -Message '0x80070002' -Properties @([pscustomobject]@{ Value = 'Package_for_KB2' }))
        )
        $lignes = @(Get-SanteEchecsPaquets)
        $lignes.Count | Should -Be 2
        $lignes[0].Etat | Should -Be 'Erreur'
        $lignes[0].Message | Should -Match 'Package_for_KB1'
        $lignes[0].Message | Should -Match 'Magasin de composants incohérent'
        $lignes[1].Message | Should -Match '0x80070002'
    }

    It 'est OK sans événement et NonExécuté si le journal est refusé' {
        (Get-SanteEchecsPaquets).Etat | Should -Be 'OK'
        $script:WinThrow = 'Access is denied.'
        (Get-SanteEchecsPaquets).Etat | Should -Be 'NonExécuté'
    }
}

Describe 'Passe complète' {
    It 'grade les compteurs du disque' {
        $script:Physical = @([pscustomobject]@{ FriendlyName = 'SSD'; HealthStatus = 'Healthy' })
        $script:Compteur = [pscustomobject]@{ Wear = 10; Temperature = 40; ReadErrorsUncorrected = 0; WriteErrorsUncorrected = 0 }
        (Get-SanteCompteursDisque).Etat | Should -Be 'OK'
        $script:Compteur.Wear = 80
        (Get-SanteCompteursDisque).Etat | Should -Be 'OK'
        $script:Compteur.Wear = 81
        (Get-SanteCompteursDisque).Etat | Should -Be 'Attention'
        $script:Compteur.Wear = 10
        $script:Compteur.ReadErrorsUncorrected = 2
        (Get-SanteCompteursDisque).Etat | Should -Be 'Erreur'
        $script:Compteur.ReadErrorsUncorrected = 0
        $script:Physical[0].HealthStatus = 'Unhealthy'
        (Get-SanteCompteursDisque).Etat | Should -Be 'Erreur'
        $script:Compteur = $null
        (Get-SanteCompteursDisque).Etat | Should -Be 'NonExécuté'
    }

    It 'grade le journal disque' {
        (Get-SanteJournalDisque).Etat | Should -Be 'OK'
        $script:WinEvents = @(New-SanteEvt -Provider 'stornvme' -Id 11 -Level 2 -Message 'disk')
        (Get-SanteJournalDisque).Etat | Should -Be 'Erreur'
        $script:WinThrow = 'Access is denied.'
        (Get-SanteJournalDisque).Etat | Should -Be 'NonExécuté'
    }

    It 'grade WHEA' {
        (Get-SanteWhea).Etat | Should -Be 'OK'
        $script:WinEvents = @(New-SanteEvt -Provider 'Microsoft-Windows-WHEA-Logger' -Level 3 -Message 'A corrected hardware error has occurred')
        (Get-SanteWhea).Etat | Should -Be 'Attention'
        $script:WinEvents = @(New-SanteEvt -Provider 'Microsoft-Windows-WHEA-Logger' -Level 2 -Message 'An uncorrected fatal error')
        (Get-SanteWhea).Etat | Should -Be 'Erreur'
        $script:WinEvents = @(New-SanteEvt -Provider 'Microsoft-Windows-WHEA-Logger' -Level 1 -Message 'hardware')
        (Get-SanteWhea).Etat | Should -Be 'Erreur'
        $script:WinThrow = 'Access is denied.'
        (Get-SanteWhea).Etat | Should -Be 'NonExécuté'
    }

    It 'grade les arrêts et cite un sys ou un bugcheck' {
        (Get-SanteArrets).Etat | Should -Be 'OK'
        $script:WinEvents = @(New-SanteEvt -Provider 'Microsoft-Windows-Kernel-Power' -Id 41 -Level 1 -Message 'driver nvlddmkm.sys bugcheck 0xD1')
        $resultat = Get-SanteArrets
        $resultat.Etat | Should -Be 'Attention'
        $resultat.Message | Should -Match 'nvlddmkm\.sys'
        $resultat.Message | Should -Match '0xD1'
        $script:WinEvents = @(
            (New-SanteEvt -Provider 'Kernel-Power' -Id 41 -Level 1 -Message 'un'),
            (New-SanteEvt -Provider 'Kernel-Power' -Id 41 -Level 1 -Message 'deux')
        )
        (Get-SanteArrets).Etat | Should -Be 'Erreur'
        $script:WinEvents = @(New-SanteEvt -Provider 'Microsoft-Windows-WER-SystemErrorReporting' -Id 1001 -Level 2 -Message 'bluescreen')
        (Get-SanteArrets).Etat | Should -Be 'Erreur'
        $script:WinEvents = @()
        $script:MinidumpPresent = $true
        $script:Minidumps = @([pscustomobject]@{ Name = 'a.dmp'; LastWriteTime = (Get-Date) })
        (Get-SanteArrets).Etat | Should -Be 'Erreur'
        $script:WinThrow = 'Access is denied.'
        (Get-SanteArrets).Etat | Should -Be 'NonExécuté'
    }

    It 'compte 4101 et LiveKernelEvent 141 ensemble' {
        (Get-SantePiloteGraphique).Etat | Should -Be 'OK'
        $script:WinEvents = @(New-SanteEvt -Provider 'Display' -Id 4101 -Level 2 -Message 'tdr')
        (Get-SantePiloteGraphique).Etat | Should -Be 'Attention'
        $script:CimData['Win32_ReliabilityRecords'] = @([pscustomobject]@{
                SourceName      = 'LiveKernelEvent'
                EventIdentifier = 141
                TimeGenerated   = Get-Date
            })
        (Get-SantePiloteGraphique).Etat | Should -Be 'Erreur'
        $script:WinThrow = 'Access is denied.'
        (Get-SantePiloteGraphique).Etat | Should -Be 'NonExécuté'
    }

    It 'grade un pilote non chargé ou bloqué' {
        (Get-SantePiloteNonCharge).Etat | Should -Be 'OK'
        $script:WinEvents = @(New-SanteEvt -Provider 'Service Control Manager' -Id 7000 -Level 2 -Message 'no')
        (Get-SantePiloteNonCharge).Etat | Should -Be 'Erreur'
        $script:WinEvents = @(New-SanteEvt -Provider 'Kernel-PnP' -Id 219 -Level 2 -Message 'no')
        (Get-SantePiloteNonCharge).Etat | Should -Be 'Erreur'
        $script:WinEvents = @()
        (Get-SantePiloteBloque).Etat | Should -Be 'OK'
        $script:WinEvents = @(New-SanteEvt -Log 'Microsoft-Windows-CodeIntegrity/Operational' -Provider 'Microsoft-Windows-CodeIntegrity' -Id 3077 -Level 2 -Message 'blocked')
        (Get-SantePiloteBloque).Etat | Should -Be 'Erreur'
        $script:WinEvents = @(New-SanteEvt -Log 'Microsoft-Windows-CodeIntegrity/Operational' -Provider 'Microsoft-Windows-CodeIntegrity' -Id 3001 -Level 4 -Message 'info')
        (Get-SantePiloteBloque).Etat | Should -Be 'OK'
    }

    It 'grade la fiabilité' {
        $script:CimData['Win32_ReliabilityStabilityMetrics'] = @(
            [pscustomobject]@{ SystemStabilityIndex = 3.2; TimeGenerated = (Get-Date).AddDays(-5) },
            [pscustomobject]@{ SystemStabilityIndex = 8.5; TimeGenerated = (Get-Date).AddDays(-1) }
        )
        $resultat = Get-SanteFiabilite
        $resultat.Etat | Should -Be 'OK'
        $resultat.Message | Should -Match '8\.5'
        $script:CimData['Win32_ReliabilityStabilityMetrics'] = @([pscustomobject]@{ SystemStabilityIndex = 4.5; TimeGenerated = Get-Date })
        (Get-SanteFiabilite).Etat | Should -Be 'Attention'
        $script:CimData['Win32_ReliabilityStabilityMetrics'] = @()
        (Get-SanteFiabilite).Etat | Should -Be 'NonExécuté'
    }

    It 'lit une sonde et dit quand aucune n est exposée' {
        $script:CimData['MSAcpi_ThermalZoneTemperature'] = @([pscustomobject]@{ InstanceName = 'TZ01'; CurrentTemperature = 3102 })
        $resultat = Get-SanteTemperatures
        $resultat.Etat | Should -Be 'OK'
        $resultat.Message | Should -Match 'TZ01'
        $script:CimData['MSAcpi_ThermalZoneTemperature'] = @([pscustomobject]@{ InstanceName = 'TZ00'; CurrentTemperature = 0 })
        $script:CimData['Win32_Fan'] = @([pscustomobject]@{ Name = 'Fan'; DesiredSpeed = 0 })
        $vide = Get-SanteTemperatures
        $vide.Etat | Should -Be 'NonExécuté'
        $vide.Message | Should -Be 'aucune sonde exposée'
        $script:CimData['Win32_Fan'] = @([pscustomobject]@{ Name = 'Fan1'; DesiredSpeed = 1200 })
        (Get-SanteTemperatures).Message | Should -Match '1200'
    }

    It 'juge sfc d après le texte' {
        $absent = Join-Path $env:TEMP 'sante-cbs-absent.log'
        $script:ProcessusTexte = 'Windows Resource Protection did not find any integrity violations.'
        (Get-SanteFichiersProteges -JournalCbs $absent).Etat | Should -Be 'OK'
        $script:ProcessusTexte = 'Windows Resource Protection found integrity violations.'
        (Get-SanteFichiersProteges -JournalCbs $absent).Etat | Should -Be 'Erreur'
        $script:ProcessusTexte = "La Protection des ressources Windows n'a trouvé aucune violation d'intégrité."
        (Get-SanteFichiersProteges -JournalCbs $absent).Etat | Should -Be 'OK'
        $script:ProcessusTexte = "La Protection des ressources Windows a trouvé des violations d'intégrité."
        (Get-SanteFichiersProteges -JournalCbs $absent).Etat | Should -Be 'Erreur'
        $script:ProcessusTexte = ''
        (Get-SanteFichiersProteges -JournalCbs $absent).Etat | Should -Be 'NonExécuté'
    }

    It 'lit un complément UTF-16 ajouté après le départ' {
        $chemin = Join-Path $env:TEMP ('sante-cbs-' + [guid]::NewGuid().ToString() + '.log')
        $encodage = [Text.Encoding]::Unicode
        $avant = $encodage.GetPreamble() + $encodage.GetBytes("avant`r`n")
        [IO.File]::WriteAllBytes($chemin, $avant)
        $ajout = $encodage.GetBytes("Windows Resource Protection did not find any integrity violations.`r`n")
        $flux = [IO.File]::Open($chemin, 'Append')
        try { $flux.Write($ajout, 0, $ajout.Length) }
        finally { $flux.Dispose() }
        $texte = Read-SanteAjout -Chemin $chemin -Depart $avant.Length
        $texte | Should -Match 'did not find any integrity violations'
        Remove-Item -LiteralPath $chemin -Force
    }

    It 'ignore Superseded et grade les paquets en attente' {
        $script:Packages = @(
            [pscustomobject]@{ PackageName = 'Bon'; PackageState = 'Installed' },
            [pscustomobject]@{ PackageName = 'Vieux'; PackageState = 'Superseded' }
        )
        $resultat = Get-SanteEtatPaquets
        $resultat.Etat | Should -Be 'OK'
        $resultat.Message | Should -Not -Match 'Vieux'
        $script:Packages += [pscustomobject]@{ PackageName = 'Partiel'; PackageState = 'PartiallyInstalled' }
        (Get-SanteEtatPaquets).Etat | Should -Be 'Erreur'
        $script:Packages = @([pscustomobject]@{ PackageName = 'Attente'; PackageState = 'InstallPending' })
        $attente = Get-SanteEtatPaquets
        $attente.Etat | Should -Be 'Erreur'
        $script:RebootPresent = $true
        $avec = Get-SanteEtatPaquets
        $avec.Etat | Should -Be 'Attention'
        $avec.Message | Should -Match 'redémarrage en attente'
    }

    It 'indique le chemin du rapport de batterie' {
        $script:ProcessusTexte = 'Battery life report saved to file path C:\Windows\Temp\sante-battery-report.html'
        $resultat = Get-SanteRapportBatterie
        $resultat.Etat | Should -Be 'OK'
        $resultat.Message | Should -Match 'sante-battery-report\.html'
        $script:ProcessusTexte = $null
        Mock Invoke-SanteProcess { throw 'powercfg absent' } -ParameterFilter { $Fichier -match 'powercfg' }
        (Get-SanteRapportBatterie).Etat | Should -Be 'NonExécuté'
    }
}

Describe 'Droits administrateur' {
    It 'ne marque jamais OK un contrôle qui n a pas pu tourner' {
        Mock Test-SanteAdministrator { $false }
        foreach ($appel in @(
                { Get-SanteCheckHealth },
                { Get-SanteScanHealth },
                { Get-SanteFichiersProteges },
                { Get-SanteEtatPaquets },
                { Get-SanteCompteursDisque }
            )) {
            $resultat = & $appel
            $resultat.Etat | Should -Be 'NonExécuté'
            $resultat.Etat | Should -Not -Be 'OK'
            $resultat.Message | Should -Match 'administrateur'
        }
    }

    It 'relance la passe complète sans droits et ne boucle pas' {
        Mock Test-SanteAdministrator { $false }
        Mock Start-SanteElevation { $true }
        $vide = @(Invoke-SantePc -Passe Complete -Relancer)
        $vide.Count | Should -Be 0
        Should -Invoke Start-SanteElevation -Times 1 -Scope It
        $env:SANTE_RELAUNCHED = '1'
        $lignes = @(Invoke-SantePc -Passe Complete -Relancer)
        $lignes.Count | Should -BeGreaterThan 0
        Should -Invoke Start-SanteElevation -Times 1 -Scope It
    }

    It 'ne relance pas la passe rapide' {
        Mock Test-SanteAdministrator { $false }
        Mock Start-SanteElevation { $true }
        Invoke-SantePc -Passe Rapide -Relancer | Out-Null
        Should -Invoke Start-SanteElevation -Times 0 -Scope It
    }
}

Describe 'Passe assemblée' {
    It 'résume sans Erreur avec la phrase, puis avec Erreur sans la phrase' {
        $script:Pnp = @([pscustomobject]@{ FriendlyName = 'Ok'; Problem = 0; Status = 'OK'; InstanceId = 'OK' })
        $script:Services = @([pscustomobject]@{ Name = 'bon'; Status = 'Running'; StartType = 'Automatic' })
        $script:SecureBoot = $true
        $script:Mp = [pscustomobject]@{
            AMEngineVersion               = '1.1'
            AntivirusSignatureVersion     = '1.2'
            AntivirusSignatureLastUpdated = (Get-Date).AddDays(-1)
            RealTimeProtectionEnabled     = $true
            QuickScanEndTime              = Get-Date
        }
        $script:CimData['Win32_ComputerSystem'] = [pscustomobject]@{ Model = 'Test' }
        $script:CimData['Win32_BIOS'] = [pscustomobject]@{ SMBIOSBIOSVersion = '1.0' }
        $script:CimData['Win32_OperatingSystem'] = [pscustomobject]@{ Caption = 'Windows'; LastBootUpTime = Get-Date }
        $script:Volumes = @(New-SanteVolume -Lettre 'C' -Taille 100GB -Libre 40GB)
        $lignes = @(Invoke-SantePc -Passe Rapide)
        $resume = $lignes | Where-Object { $_.Controle -eq 'Récapitulatif' }
        $resume.Etat | Should -Be 'OK'
        $resume.Message | Should -Match "n'innocente pas le matériel"
        $script:WinEvents = @(New-SanteEvt -Log 'System' -Provider 'Sys' -Id 1 -Level 1 -Message 'critique')
        $lignes = @(Invoke-SantePc -Passe Rapide)
        $resume = $lignes | Where-Object { $_.Controle -eq 'Récapitulatif' }
        $resume.Etat | Should -Be 'Erreur'
        $resume.Message | Should -Not -Match 'innocente'
    }
}

Describe 'Empreinte' {
    It 'recalcule le fichier sha256' {
        $outil = Join-Path (Join-Path $script:SanteRoot 'tools') 'update-hash.ps1'
        & $outil | Out-Null
        $ligne = [IO.File]::ReadAllText((Join-Path $script:SanteRoot 'sante.ps1.sha256'))
        $ligne.Trim().Split()[0] | Should -Be (Get-FileHash -LiteralPath $script:SantePath -Algorithm SHA256).Hash
    }
}
}
