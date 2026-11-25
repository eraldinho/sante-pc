# Santé PC 1.2.0
# Lecture seule des traces déjà enregistrées par Windows.
# Pas de paramètre en tête : iex ne le relie pas aux arguments.
# Le script ne s'arrête pas par un code de sortie : le résultat est l'objet récapitulatif.

$script:SanteVersion = '1.2.0'
$script:SanteUrl = 'https://raw.githubusercontent.com/eraldinho/sante-pc/v1.2.0/sante.ps1'
$script:SanteIngestUrl = 'https://sante-pc-eg.web.app/api/ingestReport'
$script:SanteAvertissement = "Un rapport sans trace n'innocente pas le matériel."

function New-SanteRow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Controle,
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'Attention', 'Erreur', 'NonExécuté')][string]$Etat,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Message
    )
    [pscustomobject]@{
        Controle = $Controle
        Etat     = $Etat
        Message  = $Message
    }
}

function Format-SanteNombre {
    [CmdletBinding()]
    param(
        [double]$Nombre,
        [string]$Modele = '{0:0.0}'
    )
    [string]::Format([Globalization.CultureInfo]::InvariantCulture, $Modele, $Nombre)
}

function Format-SanteDate {
    [CmdletBinding()]
    param($Valeur)
    if ($null -eq $Valeur -or [string]$Valeur -eq '') { return 'date inconnue' }
    try {
        $date = [datetime]$Valeur
        return $date.ToString('yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        return [string]$Valeur
    }
}

function Get-SantePireEtat {
    [CmdletBinding()]
    param([string[]]$Etats)
    $pire = 'OK'
    foreach ($etat in @($Etats)) {
        if ($etat -eq 'Erreur') { return 'Erreur' }
        if ($etat -eq 'Attention') { $pire = 'Attention' }
    }
    $pire
}

function Test-SanteAdministrator {
    [CmdletBinding()]
    param()
    $identite = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal -ArgumentList $identite
    [bool]$principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SantePorteAdmin {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Controle)
    $admin = $false
    try { $admin = [bool](Test-SanteAdministrator) }
    catch { $admin = $false }
    if ($admin) { return $null }
    New-SanteRow -Controle $Controle -Etat 'NonExécuté' -Message 'Droits administrateur requis.'
}

function Add-SanteLignes {
    [CmdletBinding()]
    param($Liste, $Valeur)
    foreach ($ligne in @($Valeur)) {
        if ($null -eq $ligne) { continue }
        if ($null -eq $ligne.PSObject.Properties['Controle']) { continue }
        [void]$Liste.Add($ligne)
    }
}

function Get-SanteSummary {
    [CmdletBinding()]
    param($Lignes)
    $pire = 'OK'
    $note = $false
    $erreur = $false
    foreach ($ligne in @($Lignes)) {
        if ($null -eq $ligne) { continue }
        if ([string]$ligne.Controle -eq 'Récapitulatif') { continue }
        if ([string]$ligne.Etat -eq 'NonExécuté') { continue }
        if ([string]$ligne.Etat -eq 'OK') {
            $note = $true
            continue
        }
        if ([string]$ligne.Etat -eq 'Attention') {
            $note = $true
            if ($pire -ne 'Erreur') { $pire = 'Attention' }
            continue
        }
        if ([string]$ligne.Etat -eq 'Erreur') {
            $note = $true
            $erreur = $true
            $pire = 'Erreur'
        }
    }
    if (-not $note) {
        $etat = 'NonExécuté'
        $message = 'Aucun contrôle noté.'
    }
    else {
        $etat = $pire
        $message = 'Pire état : ' + $etat + '.'
    }
    if (-not $erreur) {
        $message = $message + ' ' + $script:SanteAvertissement
    }
    New-SanteRow -Controle 'Récapitulatif' -Etat $etat -Message $message
}

function Test-SanteAucunEvenement {
    [CmdletBinding()]
    param($Erreur)
    $texte = [string]$Erreur.Exception.Message + ' ' + [string]$Erreur.FullyQualifiedErrorId
    $texte -match 'No events were found|Aucun événement|NoMatchingEventsFound'
}

function Get-SanteWinEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Journal,
        [string[]]$Fournisseur,
        [int[]]$Identifiant,
        [int[]]$Niveau,
        [Parameter(Mandatory = $true)][int]$Heures,
        [int]$Max = 40
    )
    $seuil = (Get-Date).AddHours(0 - $Heures)
    $filtre = @{
        LogName   = $Journal
        StartTime = $seuil
    }
    $noms = @()
    if ($Fournisseur) { $noms = @($Fournisseur | Where-Object { $_ }) }
    if ($noms.Count -gt 1) {
        $vus = New-Object 'System.Collections.Generic.HashSet[string]'
        $collecte = New-Object System.Collections.Generic.List[object]
        $refus = $null
        foreach ($nom in $noms) {
            try {
                foreach ($evenement in @(Get-SanteWinEvent -Journal $Journal -Fournisseur @($nom) -Identifiant $Identifiant -Niveau $Niveau -Heures $Heures -Max $Max)) {
                    if ($null -eq $evenement) { continue }
                    $cle = [string]$evenement.RecordId
                    if ($cle -and -not $vus.Add($cle)) { continue }
                    [void]$collecte.Add($evenement)
                    if ($collecte.Count -ge $Max) { break }
                }
            }
            catch {
                if (Test-SanteAucunEvenement $_) { }
                else { $refus = $_ }
            }
            if ($collecte.Count -ge $Max) { break }
        }
        if ($collecte.Count -eq 0 -and $null -ne $refus) { throw $refus }
        return $collecte.ToArray()
    }
    if ($noms.Count -eq 1) { $filtre['ProviderName'] = $noms[0] }
    if ($Identifiant -and @($Identifiant).Count -gt 0) { $filtre['Id'] = @($Identifiant) }
    if ($Niveau -and @($Niveau).Count -gt 0) { $filtre['Level'] = @($Niveau) }
    try {
        $brut = Get-WinEvent -FilterHashtable $filtre -MaxEvents $Max -ErrorAction Stop
    }
    catch {
        if (Test-SanteAucunEvenement $_) { return }
        throw
    }
    foreach ($evenement in @($brut)) {
        if ($null -eq $evenement) { continue }
        if ($null -ne $evenement.TimeCreated) {
            try {
                if ([datetime]$evenement.TimeCreated -lt $seuil) { continue }
            }
            catch { $null = $_.Exception.Message }
        }
        $evenement
    }
}

function ConvertTo-SanteHex {
    [CmdletBinding()]
    param($Valeur)
    if ($null -eq $Valeur) { return '' }
    $texte = [string]$Valeur
    if ($texte -match '0x[0-9A-Fa-f]{8}') { return $Matches[0].ToLower() }
    $nombre = $null
    if ($Valeur -is [int] -or $Valeur -is [long] -or $Valeur -is [uint32] -or $Valeur -is [decimal]) {
        $nombre = [int64]$Valeur
    }
    else {
        $parse = 0L
        $styles = [Globalization.NumberStyles]::Integer
        $ok = [long]::TryParse($texte, $styles, [Globalization.CultureInfo]::InvariantCulture, [ref]$parse)
        if (-not $ok) { return '' }
        $nombre = $parse
    }
    if ($nombre -eq 0) { return '' }
    $modulo = $nombre -band [int64]4294967295
    '0x{0:x8}' -f $modulo
}

function Get-SanteLibelleHresult {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Hex)
    $table = @{
        '0x80073712' = 'Magasin de composants incohérent'
        '0x800f0831' = 'Magasin CBS corrompu'
        '0x800f081f' = 'Fichiers sources introuvables'
        '0x80073701' = 'Composant manquant'
        '0x800736cc' = 'Empreinte de fichier différente du manifeste'
        '0x800f0830' = "Image plus réparable par l'entretien"
    }
    $cle = $Hex.ToLower()
    if ($table.ContainsKey($cle)) { return [string]$table[$cle] }
    $valeur = [Convert]::ToInt64($cle.Substring(2), 16)
    $bas = [Convert]::ToInt64('800f0982', 16)
    $haut = [Convert]::ToInt64('800f0988', 16)
    if ($valeur -ge $bas -and $valeur -le $haut) {
        return "Échec d'un delta de mise à jour cumulative"
    }
    ''
}

function Format-SanteHresult {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Texte)
    if ([string]::IsNullOrWhiteSpace($Texte)) { return '' }
    $vus = @{}
    $parts = New-Object System.Collections.Generic.List[string]
    $trouves = [regex]::Matches($Texte, '0x[0-9A-Fa-f]{8}')
    foreach ($trouve in @($trouves)) {
        $hex = [string]$trouve.Value
        $hex = $hex.ToLower()
        if ($vus.ContainsKey($hex)) { continue }
        $vus[$hex] = $true
        $libelle = Get-SanteLibelleHresult -Hex $hex
        if ($libelle) { [void]$parts.Add($hex + ' ' + $libelle) }
        else { [void]$parts.Add($hex) }
    }
    if ($parts.Count -eq 0) { return '' }
    $parts -join ' ; '
}

function Get-SanteIdentite {
    [CmdletBinding()]
    param()
    $script:SanteIdentity = [pscustomobject]@{ model = ''; bios = ''; windows = ''; uptime = '' }
    try {
        $modele = ''
        $bios = ''
        $windows = ''
        $uptime = ''
        try {
            $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            foreach ($item in @($cs)) {
                if ($null -eq $item) { continue }
                if ($item.Model) { $modele = [string]$item.Model }
            }
        }
        catch { $null = $_.Exception.Message }
        try {
            $b = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
            foreach ($item in @($b)) {
                if ($null -eq $item) { continue }
                if ($item.SMBIOSBIOSVersion) { $bios = [string]$item.SMBIOSBIOSVersion }
            }
        }
        catch { $null = $_.Exception.Message }
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
            foreach ($item in @($os)) {
                if ($null -eq $item) { continue }
                if ($item.Caption) { $windows = [string]$item.Caption }
                if ($item.LastBootUpTime) {
                    $span = (Get-Date) - [datetime]$item.LastBootUpTime
                    $uptime = (Format-SanteNombre -Nombre ([math]::Floor($span.TotalDays)) -Modele '{0:0}') + ' j ' + [string]$span.Hours + ' h'
                }
            }
        }
        catch { $null = $_.Exception.Message }
        if ((-not $modele) -or (-not $bios) -or (-not $windows) -or (-not $uptime)) {
            try {
                $info = Get-ComputerInfo -ErrorAction Stop
                if ($info) {
                    if (-not $modele -and $info.CsModel) { $modele = [string]$info.CsModel }
                    if (-not $bios -and $info.BiosSMBIOSBIOSVersion) { $bios = [string]$info.BiosSMBIOSBIOSVersion }
                    if (-not $windows -and $info.OsName) { $windows = [string]$info.OsName }
                    if (-not $uptime -and $info.OsUptime) {
                        $span = [timespan]$info.OsUptime
                        $uptime = (Format-SanteNombre -Nombre ([math]::Floor($span.TotalDays)) -Modele '{0:0}') + ' j ' + [string]$span.Hours + ' h'
                    }
                }
            }
            catch { $null = $_.Exception.Message }
        }
        $script:SanteIdentity = [pscustomobject]@{
            model   = [string]$modele
            bios    = [string]$bios
            windows = [string]$windows
            uptime  = [string]$uptime
        }
        if (-not $modele -and -not $bios -and -not $windows) {
            return New-SanteRow -Controle 'Identité' -Etat 'NonExécuté' -Message 'Identité illisible.'
        }
        $message = 'Modèle : ' + $modele + '. BIOS : ' + $bios + '. Windows : ' + $windows + '. Uptime : ' + $uptime + '.'
        New-SanteRow -Controle 'Identité' -Etat 'OK' -Message $message
    }
    catch {
        New-SanteRow -Controle 'Identité' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteLettreSysteme {
    [CmdletBinding()]
    param()
    $lecteur = 'C'
    if ($env:SystemDrive -and $env:SystemDrive.Length -ge 1) {
        $lecteur = $env:SystemDrive.Substring(0, 1)
    }
    $lecteur.ToUpper()
}

function Get-SanteVolumes {
    [CmdletBinding()]
    param()
    $lettreSys = Get-SanteLettreSysteme
    $liste = New-Object System.Collections.Generic.List[object]
    $depuisVolume = $false
    try {
        $volumes = Get-Volume -ErrorAction Stop
        foreach ($volume in @($volumes)) {
            if ($null -eq $volume) { continue }
            if (-not $volume.DriveLetter) { continue }
            if ($null -eq $volume.Size -or [double]$volume.Size -le 0) { continue }
            $lettre = ([string]$volume.DriveLetter).Substring(0, 1).ToUpper()
            $libre = [double]$volume.SizeRemaining
            [void]$liste.Add([pscustomobject]@{
                    Lettre  = $lettre
                    Libre   = $libre
                    Taille  = [double]$volume.Size
                    Systeme = ($lettre -eq $lettreSys)
                })
            $depuisVolume = $true
        }
    }
    catch { $null = $_.Exception.Message }
    if ($depuisVolume) { return $liste.ToArray() }
    $disques = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop
    foreach ($disque in @($disques)) {
        if ($null -eq $disque) { continue }
        if ([int]$disque.DriveType -ne 3) { continue }
        if (-not $disque.DeviceID) { continue }
        if ($null -eq $disque.Size -or [double]$disque.Size -le 0) { continue }
        $lettre = ([string]$disque.DeviceID).Substring(0, 1).ToUpper()
        [void]$liste.Add([pscustomobject]@{
                Lettre  = $lettre
                Libre   = [double]$disque.FreeSpace
                Taille  = [double]$disque.Size
                Systeme = ($lettre -eq $lettreSys)
            })
    }
    $liste.ToArray()
}

function Get-SanteDisque {
    [CmdletBinding()]
    param()
    try {
        $volumes = @(Get-SanteVolumes | Where-Object { $null -ne $_ })
        if ($volumes.Count -eq 0) {
            return New-SanteRow -Controle 'Disque' -Etat 'NonExécuté' -Message 'Aucun volume lisible.'
        }
        $etats = New-Object System.Collections.Generic.List[string]
        $textes = New-Object System.Collections.Generic.List[string]
        foreach ($volume in $volumes) {
            $pourcent = 100.0 * $volume.Libre / $volume.Taille
            $etat = 'OK'
            if ($pourcent -lt 5) { $etat = 'Erreur' }
            elseif ($pourcent -lt 10 -or ($volume.Systeme -and $volume.Libre -lt 20GB)) { $etat = 'Attention' }
            [void]$etats.Add($etat)
            $go = Format-SanteNombre -Nombre ($volume.Libre / 1GB)
            $pct = Format-SanteNombre -Nombre $pourcent
            $morceau = $volume.Lettre + ': ' + $go + ' Go libres (' + $pct + ' %)'
            if ($volume.Systeme) { $morceau = $morceau + ', système' }
            [void]$textes.Add($morceau)
        }
        $pire = Get-SantePireEtat -Etats $etats.ToArray()
        New-SanteRow -Controle 'Disque' -Etat $pire -Message ($textes -join ' ; ')
    }
    catch {
        New-SanteRow -Controle 'Disque' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteObjetsCim {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Classe,
        [string]$Espace
    )
    if ($Espace) {
        @(Get-CimInstance -Namespace $Espace -ClassName $Classe -ErrorAction Stop | Where-Object { $null -ne $_ })
    }
    else {
        @(Get-CimInstance -ClassName $Classe -ErrorAction Stop | Where-Object { $null -ne $_ })
    }
}

function Get-SanteBatterie {
    [CmdletBinding()]
    param()
    try {
        $batteries = @(Get-SanteObjetsCim -Classe 'Win32_Battery')
        if ($batteries.Count -eq 0) {
            return New-SanteRow -Controle 'Batterie' -Etat 'NonExécuté' -Message 'aucune batterie'
        }
        $prevues = @()
        $pleines = @()
        try { $prevues = @(Get-SanteObjetsCim -Classe 'BatteryStaticData' -Espace 'root\wmi') }
        catch { $null = $_.Exception.Message }
        try { $pleines = @(Get-SanteObjetsCim -Classe 'BatteryFullChargedCapacity' -Espace 'root\wmi') }
        catch { $null = $_.Exception.Message }
        $etats = New-Object System.Collections.Generic.List[string]
        $textes = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $batteries.Count; $i++) {
            $bat = $batteries[$i]
            $prevue = $null
            $plein = $null
            if ($i -lt $prevues.Count -and $null -ne $prevues[$i].DesignedCapacity) { $prevue = [double]$prevues[$i].DesignedCapacity }
            if ($null -eq $prevue -and $null -ne $bat.DesignCapacity) { $prevue = [double]$bat.DesignCapacity }
            if ($i -lt $pleines.Count -and $null -ne $pleines[$i].FullChargedCapacity) { $plein = [double]$pleines[$i].FullChargedCapacity }
            if ($null -eq $plein -and $null -ne $bat.FullChargeCapacity) { $plein = [double]$bat.FullChargeCapacity }
            $chargeConnue = $null -ne $bat.EstimatedChargeRemaining
            $pleinNul = ($null -eq $plein -or $plein -le 0)
            $prevueConnue = ($null -ne $prevue -and $prevue -gt 0)
            if (($pleinNul -and $prevueConnue) -or ((-not $chargeConnue) -and $pleinNul)) {
                [void]$etats.Add('Erreur')
                [void]$textes.Add('Charge impossible. Capacité pleine ' + [string]$plein + '. Capacité prévue ' + [string]$prevue + '.')
                continue
            }
            $etat = 'OK'
            $usureTxt = 'usure non exposée'
            if ($null -ne $prevue -and $prevue -gt 0 -and $null -ne $plein -and $plein -gt 0) {
                $usure = 1 - ($plein / $prevue)
                if ($usure -lt 0) { $usure = 0 }
                $usurePct = $usure * 100
                $usureTxt = 'Usure ' + (Format-SanteNombre -Nombre $usurePct) + ' %'
                if ($usure -gt 0.40) { $etat = 'Erreur' }
                elseif ($usure -gt 0.20) { $etat = 'Attention' }
            }
            $chargeTxt = 'charge non lue'
            if ($chargeConnue) {
                $chargeTxt = 'Charge ' + (Format-SanteNombre -Nombre ([double]$bat.EstimatedChargeRemaining)) + ' %'
            }
            [void]$etats.Add($etat)
            [void]$textes.Add($chargeTxt + '. ' + $usureTxt + '. Capacité pleine ' + [string]$plein + '. Capacité prévue ' + [string]$prevue + '.')
        }
        New-SanteRow -Controle 'Batterie' -Etat (Get-SantePireEtat -Etats $etats.ToArray()) -Message ($textes -join ' | ')
    }
    catch {
        New-SanteRow -Controle 'Batterie' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function ConvertTo-SanteCodePnp {
    [CmdletBinding()]
    param($Valeur)
    if ($null -eq $Valeur) { return 0 }
    $texte = [string]$Valeur
    if ($texte -match '^\d+$') { return [int]$texte }
    if ($texte -match '\((\d+)\)') { return [int]$Matches[1] }
    $connus = @{
        'CM_PROB_NONE'               = 0
        'CM_PROB_FAILED_START'       = 10
        'CM_PROB_DISABLED'           = 22
        'CM_PROB_FAILED_INSTALL'     = 28
        'CM_PROB_FAILED_ADD'         = 31
        'CM_PROB_DRIVER_FAILED_LOAD' = 39
        'CM_PROB_FAILED_POST_START'  = 43
    }
    if ($connus.ContainsKey($texte)) { return [int]$connus[$texte] }
    0
}

function Get-SanteInventairePnp {
    [CmdletBinding()]
    param()
    $bruts = New-Object System.Collections.Generic.List[object]
    $erreur = $null
    try {
        foreach ($appareil in @(Get-PnpDevice -ErrorAction Stop)) {
            if ($null -ne $appareil) { [void]$bruts.Add($appareil) }
        }
    }
    catch { $erreur = $_ }
    if ($bruts.Count -eq 0) {
        try {
            foreach ($appareil in @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop)) {
                if ($null -ne $appareil) { [void]$bruts.Add($appareil) }
            }
        }
        catch {
            if ($null -ne $erreur) { throw $erreur }
            throw
        }
    }
    $liste = New-Object System.Collections.Generic.List[object]
    foreach ($appareil in $bruts) {
        $nom = [string]$appareil.FriendlyName
        if (-not $nom) { $nom = [string]$appareil.Name }
        $id = [string]$appareil.InstanceId
        if (-not $id) { $id = [string]$appareil.DeviceID }
        $codeSource = $appareil.Problem
        if ($null -eq $codeSource) { $codeSource = $appareil.ConfigManagerErrorCode }
        $service = [string]$appareil.Service
        [void]$liste.Add([pscustomobject]@{
                Nom     = $nom
                Id      = $id
                Code    = (ConvertTo-SanteCodePnp -Valeur $codeSource)
                Service = $service
                Statut  = [string]$appareil.Status
            })
    }
    $liste.ToArray()
}

function Test-SanteAppareilEnDefaut {
    [CmdletBinding()]
    param($Appareil)
    if ($Appareil.Code -ne 0) { return $true }
    $statut = [string]$Appareil.Statut
    if ($statut -eq 'Error' -or $statut -eq 'Degraded') { return $true }
    $false
}

function Get-SanteEtatAppareil {
    [CmdletBinding()]
    param($Appareil)
    $graves = @(10, 28, 31, 39, 43)
    if ($graves -contains [int]$Appareil.Code) { return 'Erreur' }
    'Attention'
}

function Get-SantePeripheriques {
    [CmdletBinding()]
    param()
    try {
        $appareils = @(Get-SanteInventairePnp | Where-Object { $null -ne $_ })
        if ($appareils.Count -eq 0) {
            return New-SanteRow -Controle 'Périphériques' -Etat 'NonExécuté' -Message 'Aucun périphérique lu.'
        }
        $etats = New-Object System.Collections.Generic.List[string]
        $textes = New-Object System.Collections.Generic.List[string]
        foreach ($appareil in $appareils) {
            if (-not (Test-SanteAppareilEnDefaut -Appareil $appareil)) { continue }
            $etat = Get-SanteEtatAppareil -Appareil $appareil
            [void]$etats.Add($etat)
            if ($textes.Count -lt 12) {
                [void]$textes.Add($appareil.Nom + ' code ' + [string]$appareil.Code)
            }
        }
        if ($etats.Count -eq 0) {
            return New-SanteRow -Controle 'Périphériques' -Etat 'OK' -Message 'Aucun périphérique en défaut.'
        }
        New-SanteRow -Controle 'Périphériques' -Etat (Get-SantePireEtat -Etats $etats.ToArray()) -Message ($textes -join ' ; ')
    }
    catch {
        New-SanteRow -Controle 'Périphériques' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SantePilotes {
    [CmdletBinding()]
    param()
    try {
        $appareils = @(Get-SanteInventairePnp | Where-Object { $null -ne $_ })
        if ($appareils.Count -eq 0) {
            return New-SanteRow -Controle 'Pilotes' -Etat 'NonExécuté' -Message 'Aucun périphérique lu.'
        }
        $defauts = @($appareils | Where-Object { Test-SanteAppareilEnDefaut -Appareil $_ })
        if ($defauts.Count -eq 0) {
            return New-SanteRow -Controle 'Pilotes' -Etat 'OK' -Message "Aucun appareil en défaut. Une date de pilote seule ne change pas l'état."
        }
        $signes = @()
        $services = @()
        $entites = @()
        try { $signes = @(Get-CimInstance -ClassName Win32_PnPSignedDriver -ErrorAction Stop | Where-Object { $null -ne $_ }) }
        catch { $null = $_.Exception.Message }
        try { $services = @(Get-CimInstance -ClassName Win32_SystemDriver -ErrorAction Stop | Where-Object { $null -ne $_ }) }
        catch { $null = $_.Exception.Message }
        try { $entites = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction Stop | Where-Object { $null -ne $_ }) }
        catch { $null = $_.Exception.Message }
        $etats = New-Object System.Collections.Generic.List[string]
        $textes = New-Object System.Collections.Generic.List[string]
        foreach ($appareil in $defauts) {
            [void]$etats.Add((Get-SanteEtatAppareil -Appareil $appareil))
            $signe = $null
            foreach ($candidat in $signes) {
                if ([string]$candidat.DeviceID -eq [string]$appareil.Id) { $signe = $candidat; break }
            }
            $service = [string]$appareil.Service
            if (-not $service) {
                foreach ($entite in $entites) {
                    if ([string]$entite.DeviceID -eq [string]$appareil.Id) { $service = [string]$entite.Service; break }
                }
            }
            $sys = ''
            if ($service) {
                foreach ($drv in $services) {
                    if ([string]$drv.Name -eq $service -and [string]$drv.PathName -match '\.sys') {
                        $sys = [string]$drv.PathName
                        break
                    }
                }
            }
            $version = 'version inconnue'
            $date = 'date inconnue'
            $editeur = 'éditeur inconnu'
            if ($signe) {
                if ($signe.DriverVersion) { $version = [string]$signe.DriverVersion }
                $date = Format-SanteDate -Valeur $signe.DriverDate
                if ($signe.DriverProviderName) { $editeur = [string]$signe.DriverProviderName }
            }
            if (-not $sys) { $sys = 'fichier .sys non indiqué' }
            if ($textes.Count -lt 12) {
                [void]$textes.Add($appareil.Nom + ' (code ' + [string]$appareil.Code + ') : version ' + $version + ', date ' + $date + ', éditeur ' + $editeur + ', ' + $sys)
            }
        }
        New-SanteRow -Controle 'Pilotes' -Etat (Get-SantePireEtat -Etats $etats.ToArray()) -Message ($textes -join ' | ')
    }
    catch {
        New-SanteRow -Controle 'Pilotes' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteServices {
    [CmdletBinding()]
    param()
    try {
        $retard = @{}
        try {
            foreach ($service in @(Get-CimInstance -ClassName Win32_Service -ErrorAction Stop)) {
                if ($null -eq $service) { continue }
                if ($service.DelayedAutoStart) { $retard[[string]$service.Name] = $true }
            }
        }
        catch { $null = $_.Exception.Message }
        $lus = @(Get-Service -ErrorAction Stop | Where-Object { $null -ne $_ })
        if ($lus.Count -eq 0) {
            return New-SanteRow -Controle 'Services' -Etat 'NonExécuté' -Message 'Liste de services vide.'
        }
        $arretes = New-Object System.Collections.Generic.List[string]
        foreach ($service in $lus) {
            if ([string]$service.StartType -ne 'Automatic') { continue }
            if ($retard.ContainsKey([string]$service.Name)) { continue }
            if ([string]$service.Status -eq 'Running') { continue }
            if ($arretes.Count -lt 15) { [void]$arretes.Add([string]$service.Name) }
        }
        if ($arretes.Count -eq 0) {
            return New-SanteRow -Controle 'Services' -Etat 'OK' -Message 'Aucun service en démarrage Automatique arrêté. Les services Manual et les démarrages différés sont ignorés.'
        }
        New-SanteRow -Controle 'Services' -Etat 'Attention' -Message ('Services Automatique arrêtés : ' + ($arretes -join ', ') + '.')
    }
    catch {
        New-SanteRow -Controle 'Services' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteJournal {
    [CmdletBinding()]
    param()
    try {
        $critique = 0
        $erreur = 0
        $extraits = New-Object System.Collections.Generic.List[string]
        foreach ($journal in @('System', 'Application')) {
            foreach ($niveau in @(1, 2)) {
                $evenements = @(Get-SanteWinEvent -Journal $journal -Niveau @($niveau) -Heures 48 -Max 30)
                foreach ($evenement in $evenements) {
                    if ($null -eq $evenement) { continue }
                    if ($niveau -eq 1) { $critique++ } else { $erreur++ }
                    if ($extraits.Count -lt 6) {
                        [void]$extraits.Add($journal + ' ' + [string]$evenement.ProviderName + ' ' + [string]$evenement.Id)
                    }
                }
            }
        }
        if ($critique -gt 0) { $etat = 'Erreur' }
        elseif ($erreur -gt 0) { $etat = 'Attention' }
        else { $etat = 'OK' }
        if ($etat -eq 'OK') {
            $message = 'Journal System et Application, 48 h : aucune entrée Critique ni Erreur.'
        }
        else {
            $message = 'Critique : ' + [string]$critique + '. Erreur : ' + [string]$erreur + '. ' + ($extraits -join ' ; ')
        }
        New-SanteRow -Controle 'Journal' -Etat $etat -Message $message
    }
    catch {
        New-SanteRow -Controle 'Journal' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteDefender {
    [CmdletBinding()]
    param()
    try {
        $etat = Get-MpComputerStatus -ErrorAction Stop
        if ($null -eq $etat) {
            return New-SanteRow -Controle 'Defender' -Etat 'NonExécuté' -Message 'État Defender vide.'
        }
        if ($null -eq $etat.RealTimeProtectionEnabled -or $null -eq $etat.AntivirusSignatureLastUpdated) {
            return New-SanteRow -Controle 'Defender' -Etat 'NonExécuté' -Message 'Protection temps réel ou date de signature illisible.'
        }
        $age = (Get-Date) - [datetime]$etat.AntivirusSignatureLastUpdated
        $attention = $false
        if (-not [bool]$etat.RealTimeProtectionEnabled) { $attention = $true }
        if ($age.TotalDays -gt 7) { $attention = $true }
        $scan = 'scan non daté'
        if ($etat.QuickScanEndTime) {
            $ageScan = (Get-Date) - [datetime]$etat.QuickScanEndTime
            $scan = 'dernier scan ' + (Format-SanteNombre -Nombre $ageScan.TotalDays) + ' j'
        }
        $signature = Format-SanteDate -Valeur $etat.AntivirusSignatureLastUpdated
        $message = 'Moteur ' + [string]$etat.AMEngineVersion + '. Signatures ' + [string]$etat.AntivirusSignatureVersion + ' du ' + $signature + '. Temps réel ' + [string]$etat.RealTimeProtectionEnabled + '. ' + $scan + '.'
        if ($attention) {
            return New-SanteRow -Controle 'Defender' -Etat 'Attention' -Message $message
        }
        New-SanteRow -Controle 'Defender' -Etat 'OK' -Message $message
    }
    catch {
        New-SanteRow -Controle 'Defender' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteSecureBoot {
    [CmdletBinding()]
    param()
    try {
        $actif = Confirm-SecureBootUEFI -ErrorAction Stop
        if ($null -eq $actif) {
            return New-SanteRow -Controle 'SecureBoot' -Etat 'NonExécuté' -Message 'Secure Boot illisible.'
        }
        if ([bool]$actif) {
            return New-SanteRow -Controle 'SecureBoot' -Etat 'OK' -Message 'Secure Boot activé.'
        }
        New-SanteRow -Controle 'SecureBoot' -Etat 'Attention' -Message 'Secure Boot désactivé.'
    }
    catch {
        New-SanteRow -Controle 'SecureBoot' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteImage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Controle,
        [Parameter(Mandatory = $true)][ValidateSet('Check', 'Scan')][string]$Mode
    )
    $porte = Get-SantePorteAdmin -Controle $Controle
    if ($null -ne $porte) { return $porte }
    try {
        if ($Mode -eq 'Check') {
            $resultat = Repair-WindowsImage -Online -CheckHealth -ErrorAction Stop
        }
        else {
            $resultat = Repair-WindowsImage -Online -ScanHealth -ErrorAction Stop
        }
        $etatImage = ''
        if ($resultat) {
            $etatImage = [string]$resultat.ImageHealthState
            if (-not $etatImage) { $etatImage = [string]$resultat.HealthState }
        }
        if ($etatImage -eq 'Healthy') {
            if ($Mode -eq 'Check') {
                $message = "Healthy. Le magasin n'a pas été parcouru."
            }
            else {
                $message = 'Healthy. Le magasin a été parcouru.'
            }
            return New-SanteRow -Controle $Controle -Etat 'OK' -Message $message
        }
        if ($etatImage -eq 'Repairable' -or $etatImage -eq 'NonRepairable') {
            return New-SanteRow -Controle $Controle -Etat 'Erreur' -Message $etatImage
        }
        New-SanteRow -Controle $Controle -Etat 'NonExécuté' -Message ('État image inconnu : ' + $etatImage)
    }
    catch {
        New-SanteRow -Controle $Controle -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteCheckHealth {
    [CmdletBinding()]
    param()
    Get-SanteImage -Controle 'CheckHealth' -Mode 'Check'
}

function Get-SanteScanHealth {
    [CmdletBinding()]
    param()
    Get-SanteImage -Controle 'ScanHealth' -Mode 'Scan'
}

function Test-SanteCleRedemarrage {
    [CmdletBinding()]
    param()
    $cles = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\SessionsPending'
    )
    foreach ($cle in $cles) {
        if (Test-Path -LiteralPath $cle -ErrorAction Stop) { return $true }
    }
    $false
}

function Get-SanteRedemarrage {
    [CmdletBinding()]
    param()
    try {
        if (Test-SanteCleRedemarrage) {
            return New-SanteRow -Controle 'Redémarrage' -Etat 'Attention' -Message 'redémarrage en attente'
        }
        New-SanteRow -Controle 'Redémarrage' -Etat 'OK' -Message 'Aucune clé RebootPending ni SessionsPending.'
    }
    catch {
        New-SanteRow -Controle 'Redémarrage' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteTexteEvenement {
    [CmdletBinding()]
    param($Evenement)
    $morceaux = New-Object System.Collections.Generic.List[string]
    if ($Evenement.Message) { [void]$morceaux.Add([string]$Evenement.Message) }
    foreach ($prop in @($Evenement.Properties)) {
        if ($null -eq $prop) { continue }
        $valeur = $prop.Value
        if ($null -eq $valeur) { $valeur = $prop }
        $hex = ConvertTo-SanteHex -Valeur $valeur
        if ($hex) { [void]$morceaux.Add($hex) }
        elseif ($null -ne $valeur) { [void]$morceaux.Add([string]$valeur) }
    }
    $morceaux -join ' '
}

function Get-SanteNomPaquet {
    [CmdletBinding()]
    param($Evenement)
    foreach ($prop in @($Evenement.Properties)) {
        if ($null -eq $prop) { continue }
        $valeur = $prop.Value
        if ($null -eq $valeur) { $valeur = $prop }
        $texte = [string]$valeur
        if ($texte -match 'Package|KB\d|_for_') { return $texte }
    }
    'paquet non nommé'
}

function Get-SanteEchecsPaquets {
    [CmdletBinding()]
    param()
    try {
        $evenements = @(Get-SanteWinEvent -Journal 'Setup' -Fournisseur @('Microsoft-Windows-Servicing') -Identifiant @(3) -Heures (14 * 24) -Max 40)
        $lignes = New-Object System.Collections.Generic.List[object]
        foreach ($evenement in $evenements) {
            if ($null -eq $evenement) { continue }
            $blob = Get-SanteTexteEvenement -Evenement $evenement
            $nom = Get-SanteNomPaquet -Evenement $evenement
            $hresult = Format-SanteHresult -Texte $blob
            if (-not $hresult) { $hresult = 'HRESULT non indiqué' }
            $extrait = $blob
            if ($extrait.Length -gt 400) { $extrait = $extrait.Substring(0, 400) }
            $message = $nom + '. ' + $hresult + '. ' + $extrait
            [void]$lignes.Add((New-SanteRow -Controle 'ÉchecsPaquets' -Etat 'Erreur' -Message $message))
        }
        if ($lignes.Count -eq 0) {
            return New-SanteRow -Controle 'ÉchecsPaquets' -Etat 'OK' -Message 'Journal Setup, 14 jours : aucun événement 3 de Microsoft-Windows-Servicing.'
        }
        $lignes.ToArray()
    }
    catch {
        New-SanteRow -Controle 'ÉchecsPaquets' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteCompteursDisque {
    [CmdletBinding()]
    param()
    $porte = Get-SantePorteAdmin -Controle 'CompteursDisque'
    if ($null -ne $porte) { return $porte }
    try {
        $disques = @(Get-PhysicalDisk -ErrorAction Stop | Where-Object { $null -ne $_ })
        if ($disques.Count -eq 0) {
            return New-SanteRow -Controle 'CompteursDisque' -Etat 'NonExécuté' -Message 'Aucun disque physique.'
        }
        $etats = New-Object System.Collections.Generic.List[string]
        $textes = New-Object System.Collections.Generic.List[string]
        foreach ($disque in $disques) {
            try { $compteur = Get-StorageReliabilityCounter -PhysicalDisk $disque -ErrorAction Stop }
            catch { $compteur = $null }
            if ($null -eq $compteur) { continue }
            $etat = 'OK'
            $lectures = $compteur.ReadErrorsUncorrected
            $ecritures = $compteur.WriteErrorsUncorrected
            $predit = ([string]$disque.HealthStatus -eq 'Unhealthy')
            if ($compteur.PSObject.Properties['PredictFailure'] -and $compteur.PredictFailure) { $predit = $true }
            if (($null -ne $lectures -and [int64]$lectures -gt 0) -or ($null -ne $ecritures -and [int64]$ecritures -gt 0) -or $predit) {
                $etat = 'Erreur'
            }
            elseif ($null -ne $compteur.Wear -and [double]$compteur.Wear -gt 80) {
                $etat = 'Attention'
            }
            [void]$etats.Add($etat)
            $usure = 'n/d'
            if ($null -ne $compteur.Wear) { $usure = Format-SanteNombre -Nombre ([double]$compteur.Wear) }
            $temperature = 'n/d'
            if ($null -ne $compteur.Temperature) { $temperature = Format-SanteNombre -Nombre ([double]$compteur.Temperature) }
            if ($etat -eq 'OK') {
                [void]$textes.Add('usure ' + $usure + ', température ' + $temperature)
            }
            else {
                [void]$textes.Add([string]$disque.FriendlyName + ' : usure ' + $usure + ', température ' + $temperature + ', lectures non corrigées ' + [string]$lectures + ', écritures non corrigées ' + [string]$ecritures + ', santé ' + [string]$disque.HealthStatus)
            }
        }
        if ($etats.Count -eq 0) {
            return New-SanteRow -Controle 'CompteursDisque' -Etat 'NonExécuté' -Message 'Compteurs de fiabilité non exposés.'
        }
        $pire = Get-SantePireEtat -Etats $etats.ToArray()
        if ($pire -eq 'OK') {
            $message = [string]$etats.Count + ' disque(s), aucune erreur non corrigée, aucun échec prédit. ' + ($textes -join ' ; ')
        }
        else {
            $message = $textes -join ' | '
        }
        New-SanteRow -Controle 'CompteursDisque' -Etat $pire -Message $message
    }
    catch {
        New-SanteRow -Controle 'CompteursDisque' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteJournalDisque {
    [CmdletBinding()]
    param()
    try {
        $fournisseurs = @('NTFS', 'Ntfs', 'Microsoft-Windows-Ntfs', 'disk', 'stornvme', 'storahci')
        $evenements = @(Get-SanteWinEvent -Journal 'System' -Fournisseur $fournisseurs -Niveau @(1, 2) -Heures (14 * 24) -Max 40)
        $n = 0
        $extraits = New-Object System.Collections.Generic.List[string]
        foreach ($evenement in $evenements) {
            if ($null -eq $evenement) { continue }
            $n++
            if ($extraits.Count -lt 6) {
                [void]$extraits.Add([string]$evenement.ProviderName + ' ' + [string]$evenement.Id)
            }
        }
        if ($n -eq 0) {
            return New-SanteRow -Controle 'JournalDisque' -Etat 'OK' -Message 'Aucune erreur NTFS, disk, stornvme ou storahci sur 14 jours.'
        }
        New-SanteRow -Controle 'JournalDisque' -Etat 'Erreur' -Message ('Erreurs disque : ' + [string]$n + '. ' + ($extraits -join ' ; '))
    }
    catch {
        New-SanteRow -Controle 'JournalDisque' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Test-SanteWheaNonCorrige {
    [CmdletBinding()]
    param([string]$Texte, $Niveau)
    if ($Texte -match '(?i)uncorrected|not corrected|non[ -]corrig') { return $true }
    if ($Texte -match '(?i)\bfatal\b') { return $true }
    if ([string]$Niveau -eq '1') { return $true }
    $false
}

function Get-SanteWhea {
    [CmdletBinding()]
    param()
    try {
        $evenements = @(Get-SanteWinEvent -Journal 'System' -Fournisseur @('Microsoft-Windows-WHEA-Logger') -Heures (30 * 24) -Max 40)
        $etat = 'OK'
        $n = 0
        $extraits = New-Object System.Collections.Generic.List[string]
        foreach ($evenement in $evenements) {
            if ($null -eq $evenement) { continue }
            $n++
            $texte = [string]$evenement.Message
            if (Test-SanteWheaNonCorrige -Texte $texte -Niveau $evenement.Level) { $etat = 'Erreur' }
            elseif ($etat -ne 'Erreur') { $etat = 'Attention' }
            if ($extraits.Count -lt 4) { [void]$extraits.Add($texte) }
        }
        if ($n -eq 0) {
            return New-SanteRow -Controle 'WHEA' -Etat 'OK' -Message 'Aucun événement WHEA sur 30 jours.'
        }
        $message = 'WHEA : ' + [string]$n + '. ' + (($extraits | ForEach-Object { if ($_.Length -gt 180) { $_.Substring(0, 180) } else { $_ } }) -join ' | ')
        New-SanteRow -Controle 'WHEA' -Etat $etat -Message $message
    }
    catch {
        New-SanteRow -Controle 'WHEA' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteCitationsCrash {
    [CmdletBinding()]
    param([string]$Texte)
    $cites = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Texte)) { return '' }
    $fichiers = [regex]::Matches($Texte, '(?i)[A-Za-z0-9_.\-]+\.sys\b')
    $vus = @{}
    foreach ($fichier in @($fichiers)) {
        $nom = [string]$fichier.Value
        if ($vus.ContainsKey($nom.ToLower())) { continue }
        $vus[$nom.ToLower()] = $true
        [void]$cites.Add($nom)
    }
    foreach ($code in @('0xD1', '0x9F', '0x116', '0x124', '0x9C', '0x1A')) {
        $motif = '(?i)' + [regex]::Escape($code) + '\b'
        if ($Texte -match $motif) { [void]$cites.Add($code) }
    }
    $cites -join ', '
}

function Get-SanteArrets {
    [CmdletBinding()]
    param()
    try {
        $brutaux = @(Get-SanteWinEvent -Journal 'System' -Fournisseur @('Microsoft-Windows-Kernel-Power', 'Kernel-Power') -Identifiant @(41) -Heures (30 * 24) -Max 40)
        $bleus = @(Get-SanteWinEvent -Journal 'System' -Fournisseur @('Microsoft-Windows-WER-SystemErrorReporting', 'WER-SystemErrorReporting') -Identifiant @(1001) -Heures (30 * 24) -Max 40)
        $n41 = @($brutaux | Where-Object { $null -ne $_ }).Count
        $n1001 = @($bleus | Where-Object { $null -ne $_ }).Count
        $nDump = 0
        $dossier = 'C:\Windows\Minidump'
        if (Test-Path -LiteralPath $dossier -ErrorAction Stop) {
            $fichiers = @(Get-ChildItem -LiteralPath $dossier -Filter '*.dmp' -ErrorAction Stop)
            $seuil = (Get-Date).AddDays(-30)
            foreach ($fichier in $fichiers) {
                if ($null -eq $fichier) { continue }
                if ($fichier.LastWriteTime -ge $seuil) { $nDump++ }
            }
        }
        $citations = New-Object System.Collections.Generic.List[string]
        foreach ($evenement in @($brutaux + $bleus)) {
            if ($null -eq $evenement) { continue }
            $cite = Get-SanteCitationsCrash -Texte ([string]$evenement.Message)
            if ($cite) { [void]$citations.Add($cite) }
        }
        $base = 'Kernel-Power 41 : ' + [string]$n41 + '. WER 1001 : ' + [string]$n1001 + '. Minidumps : ' + [string]$nDump + '.'
        if ($citations.Count -gt 0) { $base = $base + ' ' + ($citations -join ' ; ') }
        if ($n1001 -gt 0 -or $nDump -gt 0 -or $n41 -ge 2) {
            return New-SanteRow -Controle 'Arrêts' -Etat 'Erreur' -Message $base
        }
        if ($n41 -eq 1) {
            return New-SanteRow -Controle 'Arrêts' -Etat 'Attention' -Message ('Un Kernel-Power 41 isolé. ' + $base)
        }
        New-SanteRow -Controle 'Arrêts' -Etat 'OK' -Message 'Aucun Kernel-Power 41, aucun WER 1001, aucun minidump sur 30 jours.'
    }
    catch {
        New-SanteRow -Controle 'Arrêts' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SantePiloteGraphique {
    [CmdletBinding()]
    param()
    try {
        $affichage = @(Get-SanteWinEvent -Journal 'System' -Fournisseur @('Display') -Identifiant @(4101) -Heures (30 * 24) -Max 40)
        $n = @($affichage | Where-Object { $null -ne $_ }).Count
        $records = @(Get-CimInstance -ClassName Win32_ReliabilityRecords -ErrorAction Stop | Where-Object { $null -ne $_ })
        $seuil = (Get-Date).AddDays(-30)
        foreach ($record in $records) {
            $source = [string]$record.SourceName
            $id = 0
            try { $id = [int]$record.EventIdentifier } catch { $id = 0 }
            if ($source -ne 'LiveKernelEvent' -or $id -ne 141) { continue }
            $compter = $true
            if ($record.TimeGenerated) {
                try { if ([datetime]$record.TimeGenerated -lt $seuil) { $compter = $false } }
                catch { $null = $_.Exception.Message }
            }
            if ($compter) { $n++ }
        }
        if ($n -ge 2) { $etat = 'Erreur' }
        elseif ($n -eq 1) { $etat = 'Attention' }
        else { $etat = 'OK' }
        if ($etat -eq 'OK') {
            $message = 'Aucun événement Display 4101 ni LiveKernelEvent 141 sur 30 jours.'
        }
        else {
            $message = 'Display 4101 et LiveKernelEvent 141 : ' + [string]$n + ' occurrence(s) sur 30 jours.'
        }
        New-SanteRow -Controle 'PiloteGraphique' -Etat $etat -Message $message
    }
    catch {
        New-SanteRow -Controle 'PiloteGraphique' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteNombreEvenements {
    [CmdletBinding()]
    param($Evenements)
    @($Evenements | Where-Object { $null -ne $_ }).Count
}

function Get-SantePiloteNonCharge {
    [CmdletBinding()]
    param()
    try {
        $pnp = @(Get-SanteWinEvent -Journal 'System' -Fournisseur @('Microsoft-Windows-Kernel-PnP', 'Kernel-PnP') -Identifiant @(219) -Heures (14 * 24) -Max 40)
        $scm = @(Get-SanteWinEvent -Journal 'System' -Fournisseur @('Service Control Manager') -Identifiant @(7000, 7026) -Heures (14 * 24) -Max 40)
        $n = (Get-SanteNombreEvenements $pnp) + (Get-SanteNombreEvenements $scm)
        if ($n -eq 0) {
            return New-SanteRow -Controle 'PiloteNonChargé' -Etat 'OK' -Message 'Aucun Kernel-PnP 219 ni Service Control Manager 7000 ou 7026 sur 14 jours.'
        }
        New-SanteRow -Controle 'PiloteNonChargé' -Etat 'Erreur' -Message ('Pilotes non chargés : ' + [string]$n + ' événement(s).')
    }
    catch {
        New-SanteRow -Controle 'PiloteNonChargé' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SantePiloteBloque {
    [CmdletBinding()]
    param()
    try {
        $evenements = @(Get-SanteWinEvent -Journal 'Microsoft-Windows-CodeIntegrity/Operational' -Identifiant @(3033, 3034, 3076, 3077, 3089) -Heures (30 * 24) -Max 40)
        $n = Get-SanteNombreEvenements $evenements
        if ($n -eq 0) {
            return New-SanteRow -Controle 'PiloteBloqué' -Etat 'OK' -Message 'Aucun pilote bloqué (événements 3033, 3034, 3076, 3077, 3089) sur 30 jours.'
        }
        New-SanteRow -Controle 'PiloteBloqué' -Etat 'Erreur' -Message ('Pilotes bloqués : ' + [string]$n + ' événement(s) Code Integrity.')
    }
    catch {
        New-SanteRow -Controle 'PiloteBloqué' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteFiabilite {
    [CmdletBinding()]
    param()
    try {
        $mesures = @(Get-CimInstance -ClassName Win32_ReliabilityStabilityMetrics -ErrorAction Stop | Where-Object { $null -ne $_ })
        if ($mesures.Count -eq 0) {
            return New-SanteRow -Controle 'Fiabilité' -Etat 'NonExécuté' -Message 'Indice de fiabilité absent.'
        }
        $recente = $null
        foreach ($mesure in $mesures) {
            if ($null -eq $recente) { $recente = $mesure; continue }
            try {
                if ([datetime]$mesure.TimeGenerated -gt [datetime]$recente.TimeGenerated) { $recente = $mesure }
            }
            catch { $null = $_.Exception.Message }
        }
        if ($null -eq $recente -or $null -eq $recente.SystemStabilityIndex) {
            return New-SanteRow -Controle 'Fiabilité' -Etat 'NonExécuté' -Message 'Indice de fiabilité illisible.'
        }
        $indice = [double]$recente.SystemStabilityIndex
        $message = 'Indice ' + (Format-SanteNombre -Nombre $indice) + '.'
        if ($indice -lt 5) {
            return New-SanteRow -Controle 'Fiabilité' -Etat 'Attention' -Message $message
        }
        New-SanteRow -Controle 'Fiabilité' -Etat 'OK' -Message $message
    }
    catch {
        New-SanteRow -Controle 'Fiabilité' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteTemperatures {
    [CmdletBinding()]
    param()
    $lectures = New-Object System.Collections.Generic.List[string]
    try {
        foreach ($zone in @(Get-CimInstance -Namespace 'root\wmi' -ClassName MSAcpi_ThermalZoneTemperature -ErrorAction Stop)) {
            if ($null -eq $zone -or $null -eq $zone.CurrentTemperature) { continue }
            $celsius = ([double]$zone.CurrentTemperature / 10) - 273.15
            if ($celsius -lt -20 -or $celsius -gt 150) { continue }
            [void]$lectures.Add([string]$zone.InstanceName + ' ' + (Format-SanteNombre -Nombre $celsius) + ' °C')
        }
    }
    catch { $null = $_.Exception.Message }
    try {
        foreach ($ventilateur in @(Get-CimInstance -ClassName Win32_Fan -ErrorAction Stop)) {
            if ($null -eq $ventilateur -or $null -eq $ventilateur.DesiredSpeed) { continue }
            if ([int]$ventilateur.DesiredSpeed -le 0) { continue }
            [void]$lectures.Add('Ventilateur ' + [string]$ventilateur.Name + ' ' + [string]$ventilateur.DesiredSpeed + ' tr/min')
        }
    }
    catch { $null = $_.Exception.Message }
    try {
        foreach ($sonde in @(Get-CimInstance -ClassName Win32_TemperatureProbe -ErrorAction Stop)) {
            if ($null -eq $sonde -or $null -eq $sonde.CurrentReading) { continue }
            if ([int]$sonde.CurrentReading -le 0) { continue }
            [void]$lectures.Add('Sonde ' + [string]$sonde.Name + ' ' + [string]$sonde.CurrentReading)
        }
    }
    catch { $null = $_.Exception.Message }
    if ($lectures.Count -eq 0) {
        return New-SanteRow -Controle 'Températures' -Etat 'NonExécuté' -Message 'aucune sonde exposée'
    }
    New-SanteRow -Controle 'Températures' -Etat 'OK' -Message ($lectures -join ' ; ')
}

function Get-SanteVerdictSfc {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Texte)
    if ([string]::IsNullOrWhiteSpace($Texte)) { return 'NonExécuté' }
    if ($Texte -match '(?i)did not find any integrity violations|n.a trouv. aucune violation|aucune violation d.int.grit') {
        return 'OK'
    }
    if ($Texte -match '(?i)found integrity violations|found corrupt files|corrupt file|a trouv. des violations|fichiers endommag|fichier(s)? endommag|fichier corrompu') {
        return 'Erreur'
    }
    'NonExécuté'
}

function Invoke-SanteProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Fichier,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Arguments
    )
    $info = New-Object System.Diagnostics.ProcessStartInfo
    $info.FileName = $Fichier
    $info.Arguments = $Arguments
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    try {
        $encodage = [Console]::OutputEncoding
        if ($encodage) {
            $info.StandardOutputEncoding = $encodage
            $info.StandardErrorEncoding = $encodage
        }
    }
    catch { $null = $_.Exception.Message }
    $processus = New-Object System.Diagnostics.Process
    $processus.StartInfo = $info
    $demarre = $processus.Start()
    if (-not $demarre) { throw 'Processus non démarré.' }
    $sortie = $processus.StandardOutput.ReadToEndAsync()
    $erreur = $processus.StandardError.ReadToEndAsync()
    $processus.WaitForExit()
    $sortie.Wait()
    $erreur.Wait()
    [string]$sortie.Result + "`r`n" + [string]$erreur.Result
}

function Read-SanteAjout {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Chemin,
        [int64]$Depart = 0
    )
    if (-not (Test-Path -LiteralPath $Chemin -ErrorAction Stop)) { return '' }
    $flux = New-Object System.IO.FileStream($Chemin, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $marque = New-Object byte[] 2
        $lus = $flux.Read($marque, 0, 2)
        $unicode = ($lus -eq 2 -and $marque[0] -eq 255 -and $marque[1] -eq 254)
        if ($unicode) { $encodage = [Text.Encoding]::Unicode } else { $encodage = [Text.Encoding]::UTF8 }
        if ($Depart -lt 0) { $Depart = 0 }
        if ($unicode -and (($Depart % 2) -ne 0)) { $Depart = $Depart - 1 }
        if ($Depart -gt $flux.Length) { return '' }
        $flux.Position = $Depart
        $taille = [int]($flux.Length - $flux.Position)
        if ($taille -le 0) { return '' }
        $reste = New-Object byte[] $taille
        [void]$flux.Read($reste, 0, $taille)
        $encodage.GetString($reste)
    }
    finally {
        $flux.Dispose()
    }
}

function Get-SanteFichiersProteges {
    [CmdletBinding()]
    param([string]$JournalCbs = 'C:\Windows\Logs\CBS\CBS.log')
    $porte = Get-SantePorteAdmin -Controle 'FichiersProtégés'
    if ($null -ne $porte) { return $porte }
    try {
        $taille = 0L
        if (Test-Path -LiteralPath $JournalCbs -ErrorAction SilentlyContinue) {
            $taille = [int64](Get-Item -LiteralPath $JournalCbs -ErrorAction Stop).Length
        }
        $exe = 'sfc.exe'
        if ($env:SystemRoot) {
            $candidat = Join-Path $env:SystemRoot 'System32\sfc.exe'
            if (Test-Path -LiteralPath $candidat -ErrorAction SilentlyContinue) { $exe = $candidat }
        }
        $texte = [string](Invoke-SanteProcess -Fichier $exe -Arguments '/verifyonly')
        try { $texte = $texte + "`r`n" + [string](Read-SanteAjout -Chemin $JournalCbs -Depart $taille) }
        catch { $null = $_.Exception.Message }
        $verdict = Get-SanteVerdictSfc -Texte $texte
        $affiche = $texte.Trim()
        if ($affiche.Length -gt 800) { $affiche = $affiche.Substring($affiche.Length - 800) }
        if (-not $affiche) { $affiche = 'Texte de sfc vide.' }
        New-SanteRow -Controle 'FichiersProtégés' -Etat $verdict -Message $affiche
    }
    catch {
        New-SanteRow -Controle 'FichiersProtégés' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteEtatPaquets {
    [CmdletBinding()]
    param()
    $porte = Get-SantePorteAdmin -Controle 'ÉtatPaquets'
    if ($null -ne $porte) { return $porte }
    try {
        $reboot = Test-SanteCleRedemarrage
        $paquets = @(Get-WindowsPackage -Online -ErrorAction Stop | Where-Object { $null -ne $_ })
        if ($paquets.Count -eq 0) {
            return New-SanteRow -Controle 'ÉtatPaquets' -Etat 'NonExécuté' -Message 'Liste de paquets vide.'
        }
        $erreurs = New-Object System.Collections.Generic.List[string]
        $attentions = New-Object System.Collections.Generic.List[string]
        foreach ($paquet in $paquets) {
            $etat = [string]$paquet.PackageState
            if ($etat -eq 'Superseded') { continue }
            $nom = [string]$paquet.PackageName
            if ($etat -eq 'PartiallyInstalled') {
                [void]$erreurs.Add($nom + ' PartiallyInstalled')
            }
            elseif ($etat -eq 'InstallPending' -or $etat -eq 'UninstallPending') {
                if ($reboot) { [void]$attentions.Add($nom + ' ' + $etat + ', redémarrage en attente') }
                else { [void]$erreurs.Add($nom + ' ' + $etat) }
            }
        }
        if ($erreurs.Count -gt 0) {
            return New-SanteRow -Controle 'ÉtatPaquets' -Etat 'Erreur' -Message (($erreurs | Select-Object -First 8) -join ' ; ')
        }
        if ($attentions.Count -gt 0) {
            return New-SanteRow -Controle 'ÉtatPaquets' -Etat 'Attention' -Message (($attentions | Select-Object -First 8) -join ' ; ')
        }
        New-SanteRow -Controle 'ÉtatPaquets' -Etat 'OK' -Message 'Aucun paquet partiel ou en attente. Les paquets Superseded sont ignorés.'
    }
    catch {
        New-SanteRow -Controle 'ÉtatPaquets' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Get-SanteRapportBatterie {
    [CmdletBinding()]
    param()
    try {
        $dest = Join-Path $env:TEMP 'sante-battery-report.html'
        $exe = 'powercfg.exe'
        if ($env:SystemRoot) {
            $candidat = Join-Path $env:SystemRoot 'System32\powercfg.exe'
            if (Test-Path -LiteralPath $candidat -ErrorAction SilentlyContinue) { $exe = $candidat }
        }
        $arguments = '/batteryreport /output "' + $dest + '"'
        $texte = [string](Invoke-SanteProcess -Fichier $exe -Arguments $arguments)
        if (Test-Path -LiteralPath $dest -ErrorAction SilentlyContinue) {
            return New-SanteRow -Controle 'RapportBatterie' -Etat 'OK' -Message ('Rapport : ' + $dest)
        }
        if ($texte -match '(?i)([A-Za-z]:\\[^"\r\n]+\.html)') {
            return New-SanteRow -Controle 'RapportBatterie' -Etat 'OK' -Message ('Rapport : ' + $Matches[1])
        }
        $affiche = $texte.Trim()
        if (-not $affiche) { $affiche = 'Rapport de batterie absent.' }
        New-SanteRow -Controle 'RapportBatterie' -Etat 'NonExécuté' -Message $affiche
    }
    catch {
        New-SanteRow -Controle 'RapportBatterie' -Etat 'NonExécuté' -Message ([string]$_.Exception.Message)
    }
}

function Test-SanteFichierScript {
    [CmdletBinding()]
    param([string]$Chemin)
    if (-not $Chemin) { return $false }
    if (-not (Test-Path -LiteralPath $Chemin -ErrorAction SilentlyContinue)) { return $false }
    $contenu = [IO.File]::ReadAllText($Chemin)
    $contenu.Contains('function Invoke-SantePc')
}

function Copy-SanteScriptToTemp {
    [CmdletBinding()]
    param()
    $dest = Join-Path $env:TEMP 'sante-pc.ps1'
    $sources = New-Object System.Collections.Generic.List[string]
    if ($PSCommandPath) { [void]$sources.Add([string]$PSCommandPath) }
    $fichierFonction = [string]$MyInvocation.MyCommand.ScriptBlock.File
    if ($fichierFonction) { [void]$sources.Add($fichierFonction) }
    foreach ($source in $sources) {
        if (Test-SanteFichierScript -Chemin $source) {
            Copy-Item -LiteralPath $source -Destination $dest -Force
            return $dest
        }
    }
    foreach ($portee in @(1, 2, 3, 'Global', 'Script')) {
        try { $variable = Get-Variable -Name 'bytes' -Scope $portee -ErrorAction SilentlyContinue }
        catch { $variable = $null }
        if ($null -eq $variable -or $null -eq $variable.Value) { continue }
        if (-not ($variable.Value -is [byte[]])) { continue }
        $texte = [Text.Encoding]::UTF8.GetString($variable.Value).TrimStart([char]0xFEFF)
        if ($texte.Contains('function Invoke-SantePc')) {
            $encodage = New-Object System.Text.UTF8Encoding $true
            [IO.File]::WriteAllText($dest, $texte, $encodage)
            return $dest
        }
    }
    throw 'Source du script introuvable.'
}

function Start-SanteElevation {
    [CmdletBinding()]
    param($Options)
    $etat = $null
    try {
        $dest = Copy-SanteScriptToTemp
        try { Unblock-File -LiteralPath $dest -ErrorAction Stop }
        catch { $null = $_.Exception.Message }
        $exe = 'powershell.exe'
        if ($env:SystemRoot) {
            $candidat = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
            if (Test-Path -LiteralPath $candidat -ErrorAction SilentlyContinue) { $exe = $candidat }
        }
        $etat = Publish-SanteEnvironnementEnfant -Options $Options
        $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $dest + '" Complete -DejaRelance'
        if ($null -ne $Options -and $Options.NoUpload) {
            $arguments = $arguments + ' -NoUpload'
        }
        elseif ($null -ne $Options -and $Options.Upload) {
            $arguments = $arguments + ' -Upload'
        }
        if ($null -ne $Options -and $Options.Label) {
            $propre = ([string]$Options.Label) -replace '["\r\n]', ''
            if ($propre) { $arguments = $arguments + ' -Label "' + $propre + '"' }
        }
        Start-Process -FilePath $exe -ArgumentList $arguments -Verb RunAs
        $true
    }
    catch {
        $false
    }
    finally {
        Restore-SanteEnvironnementEnfant -Etat $etat
    }
}

function Protect-SanteMessage {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Message)
    $texte = [string]$Message
    if ($env:USERPROFILE) {
        $texte = $texte.Replace([string]$env:USERPROFILE, 'C:\Users\<user>')
    }
    if ($env:TEMP) {
        $texte = $texte.Replace([string]$env:TEMP, 'TEMP')
    }
    if ($env:USERNAME) {
        $nom = [regex]::Escape([string]$env:USERNAME)
        $texte = [regex]::Replace($texte, '(?i)(?<=\\)' + $nom + '(?=\\)', '<user>')
    }
    $texte = [regex]::Replace($texte, '(?i)[A-Za-z]:\\Users\\[^\\]+\\', 'C:\Users\<user>\')
    $texte = [regex]::Replace($texte, '(?i)[A-Za-z]:\\[^"\r\n]*sante-battery-report\.html', 'TEMP\sante-battery-report.html')
    $texte
}

function Get-SanteHorodatageLocal {
    [CmdletBinding()]
    param()
    [datetimeoffset]::Now.ToString('yyyy-MM-ddTHH:mm:sszzz', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-SanteSha256Texte {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Texte)
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        $octets = [Text.Encoding]::UTF8.GetBytes($Texte)
        $empreinte = $sha.ComputeHash($octets)
    }
    finally {
        $sha.Dispose()
    }
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($octet in $empreinte) {
        [void]$parts.Add($octet.ToString('x2'))
    }
    -join $parts.ToArray()
}

function Test-SanteMatiereGenerique {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Valeur)
    if (-not $Valeur) { return $true }
    $texte = $Valeur.Trim().ToUpperInvariant()
    if (-not $texte) { return $true }
    $connus = @(
        'TO BE FILLED BY O.E.M.',
        'TO BE FILLED BY O.E.M',
        'DEFAULT STRING',
        'NONE',
        'NOT SPECIFIED',
        'SYSTEM SERIAL NUMBER',
        'CHASSIS SERIAL NUMBER',
        '0'
    )
    foreach ($connu in $connus) {
        if ($texte -eq $connu) { return $true }
    }
    $hex = $texte -replace '[^0-9A-F]', ''
    if (-not $hex) { return $true }
    if ($hex -match '^(0+|F+)$') { return $true }
    $false
}

function Get-SanteMachineId {
    [CmdletBinding()]
    param()
    $uuid = ''
    try {
        $produit = Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop
        foreach ($item in @($produit)) {
            if ($null -eq $item) { continue }
            if ($item.UUID) { $uuid = [string]$item.UUID }
        }
    }
    catch { $null = $_.Exception.Message }
    $matiere = ''
    if (-not (Test-SanteMatiereGenerique -Valeur $uuid)) {
        $matiere = $uuid.Trim().ToUpperInvariant()
    }
    else {
        $serie = ''
        try {
            $biosCim = Get-CimInstance -ClassName Win32_BIOS -ErrorAction Stop
            foreach ($item in @($biosCim)) {
                if ($null -eq $item) { continue }
                if ($item.SerialNumber) { $serie = [string]$item.SerialNumber }
            }
        }
        catch { $null = $_.Exception.Message }
        if (-not (Test-SanteMatiereGenerique -Valeur $serie)) {
            $matiere = $serie.Trim().ToUpperInvariant()
        }
    }
    if ($matiere) {
        return [pscustomobject]@{
            machineId     = (Get-SanteSha256Texte -Texte $matiere)
            machineIdWeak = $false
        }
    }
    $modele = ''
    $biosVersion = ''
    $windows = ''
    if ($null -ne $script:SanteIdentity) {
        $modele = [string]$script:SanteIdentity.model
        $biosVersion = [string]$script:SanteIdentity.bios
        $windows = [string]$script:SanteIdentity.windows
    }
    $faible = 'weak|' + $modele + '|' + $biosVersion + '|' + $windows
    [pscustomobject]@{
        machineId     = (Get-SanteSha256Texte -Texte $faible)
        machineIdWeak = $true
    }
}

function Get-SanteOptions {
    [CmdletBinding()]
    param([string[]]$Arguments)
    $passe = 'Rapide'
    $jeton = $null
    $jetonEnv = $false
    $noUpload = $false
    $upload = $false
    $label = $null
    $labelEnv = $false
    $launch = $null
    $launchEnv = $false
    if ($env:SANTE_PASSE -match '^(?i)complete$') { $passe = 'Complete' }
    if ($env:SANTE_PASSE -match '^(?i)rapide$') { $passe = 'Rapide' }
    if ($env:SANTE_TOKEN) {
        $jeton = [string]$env:SANTE_TOKEN
        $jetonEnv = $true
    }
    if ($env:SANTE_NO_UPLOAD -eq '1') { $noUpload = $true }
    if ($env:SANTE_UPLOAD -eq '1') { $upload = $true }
    if ($env:SANTE_ENVOI -eq '1') { $upload = $true }
    if ($env:SANTE_LABEL) {
        $label = [string]$env:SANTE_LABEL
        $labelEnv = $true
    }
    if ($env:SANTE_LAUNCH) {
        $launch = [string]$env:SANTE_LAUNCH
        $launchEnv = $true
    }
    $liste = @($Arguments)
    $index = 0
    while ($index -lt $liste.Count) {
        $texte = [string]$liste[$index]
        if ($texte -match '^(?i)complete$') { $passe = 'Complete' }
        elseif ($texte -match '^(?i)rapide$') { $passe = 'Rapide' }
        elseif ($texte -eq '-DejaRelance') { $env:SANTE_RELAUNCHED = '1' }
        elseif ($texte -eq '-NoUpload') { $noUpload = $true }
        elseif ($texte -eq '-Upload') { $upload = $true }
        elseif ($texte -eq '-Token') {
            $index = $index + 1
            if (($index -lt $liste.Count) -and (-not $jetonEnv)) { $jeton = [string]$liste[$index] }
        }
        elseif ($texte -eq '-Label') {
            $index = $index + 1
            if (($index -lt $liste.Count) -and (-not $labelEnv)) { $label = [string]$liste[$index] }
        }
        elseif ($texte -eq '-Launch') {
            $index = $index + 1
            if (($index -lt $liste.Count) -and (-not $launchEnv)) { $launch = [string]$liste[$index] }
        }
        elseif ($texte -eq '-TokenFile') {
            $index = $index + 1
            if ($index -lt $liste.Count) {
                $cheminJeton = [string]$liste[$index]
                if ((-not $jeton) -and $cheminJeton -and (Test-Path -LiteralPath $cheminJeton)) {
                    try {
                        $jeton = [IO.File]::ReadAllText($cheminJeton).Trim()
                        Remove-Item -LiteralPath $cheminJeton -Force -ErrorAction SilentlyContinue
                    }
                    catch { $null = $_.Exception.Message }
                }
            }
        }
        $index = $index + 1
    }
    if ($null -ne $label) {
        $label = $label.Trim()
        if ($label.Length -gt 80) { $label = $label.Substring(0, 80) }
        if (-not $label) { $label = $null }
    }
    if ($null -ne $launch) {
        $launch = $launch.Trim()
        if (-not $launch) { $launch = $null }
    }
    if ($noUpload) { $upload = $false }
    elseif ($launch) { $upload = $true }
    [pscustomobject]@{
        Passe    = $passe
        Token    = $jeton
        NoUpload = [bool]$noUpload
        Upload   = [bool]$upload
        Label    = $label
        Launch   = $launch
    }
}

function Get-SantePasseDemandee {
    [CmdletBinding()]
    param([string[]]$Arguments)
    (Get-SanteOptions -Arguments $Arguments).Passe
}

function Get-SanteApercuJeton {
    [CmdletBinding()]
    param([AllowEmptyString()][string]$Jeton)
    $texte = [string]$Jeton
    if ($texte -match '^(spc_[A-Za-z0-9_-]{4})') {
        return ($Matches[1] + [string][char]0x2026)
    }
    if ($texte.Length -ge 8) { return ($texte.Substring(0, 8) + [string][char]0x2026) }
    'spc_' + [string][char]0x2026
}

function New-SanteRapport {
    [CmdletBinding()]
    param(
        $Lignes,
        [Parameter(Mandatory = $true)][string]$Passe,
        $Options
    )
    $machine = Get-SanteMachineId
    $label = $null
    if ($null -ne $Options -and $Options.Label) { $label = [string]$Options.Label }
    $modele = ''
    $bios = ''
    $windows = ''
    $uptime = ''
    if ($null -ne $script:SanteIdentity) {
        $modele = [string]$script:SanteIdentity.model
        $bios = [string]$script:SanteIdentity.bios
        $windows = [string]$script:SanteIdentity.windows
        $uptime = [string]$script:SanteIdentity.uptime
    }
    $etatResume = 'NonExécuté'
    $messageResume = ''
    $controles = New-Object System.Collections.Generic.List[object]
    foreach ($ligne in @($Lignes)) {
        if ($null -eq $ligne) { continue }
        $messageProtege = Protect-SanteMessage -Message ([string]$ligne.Message)
        $element = [pscustomobject]@{
            controle = [string]$ligne.Controle
            etat     = [string]$ligne.Etat
            message  = $messageProtege
        }
        [void]$controles.Add($element)
        if ([string]$ligne.Controle -eq 'Récapitulatif') {
            $etatResume = [string]$ligne.Etat
            $messageResume = $messageProtege
        }
    }
    $corps = [pscustomobject]@{
        schemaVersion = 1
        scriptVersion = [string]$script:SanteVersion
        collectedAt   = (Get-SanteHorodatageLocal)
        pass          = $Passe
        machineId     = [string]$machine.machineId
        machineIdWeak = [bool]$machine.machineIdWeak
        label         = $label
        identity      = [pscustomobject]@{
            model   = $modele
            bios    = $bios
            windows = $windows
            uptime  = $uptime
        }
        summary       = [pscustomobject]@{
            etat    = $etatResume
            message = $messageResume
        }
        controls      = $controles.ToArray()
    }
    $json = ConvertTo-Json -InputObject $corps -Depth 6 -Compress
    [pscustomobject]@{
        Json          = [string]$json
        Pass          = $Passe
        MachineId     = [string]$machine.machineId
        MachineIdWeak = [bool]$machine.machineIdWeak
        Label         = $label
        SummaryEtat   = $etatResume
        ControlCount  = $controles.Count
        Controls      = $controles.ToArray()
    }
}

function Save-SanteRapportLocal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Json)
    try {
        $dossier = $env:TEMP
        if (-not $dossier) { $dossier = [IO.Path]::GetTempPath() }
        $nom = 'sante-pc-report-' + (Get-Date).ToString('yyyyMMdd-HHmmss') + '.json'
        $chemin = Join-Path $dossier $nom
        if (Test-Path -LiteralPath $chemin) {
            $nom = 'sante-pc-report-' + (Get-Date).ToString('yyyyMMdd-HHmmss-fff') + '.json'
            $chemin = Join-Path $dossier $nom
        }
        $encodage = New-Object System.Text.UTF8Encoding $false
        [IO.File]::WriteAllText($chemin, $Json, $encodage)
        $chemin
    }
    catch {
        Write-Warning ('Rapport local non écrit : ' + [string]$_.Exception.Message)
        $null
    }
}

function Read-SanteJeton {
    [CmdletBinding()]
    param()
    try {
        $secure = Read-Host -AsSecureString -Prompt 'Jeton d''enrôlement'
    }
    catch {
        Write-Warning 'Jeton non saisi.'
        return $null
    }
    if ($null -eq $secure -or $secure.Length -eq 0) { return $null }
    $pointeur = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointeur)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointeur)
    }
}

function Test-SanteEnvoiDemande {
    [CmdletBinding()]
    param($Options)
    if ($null -eq $Options) { return $false }
    if ($Options.NoUpload) { return $false }
    if ($Options.Token) { return $true }
    if ($Options.Launch) { return $true }
    [bool]$Options.Upload
}

function Resolve-SanteJetonEnvoi {
    [CmdletBinding()]
    param($Options)
    if ($null -eq $Options) { return $null }
    if ($Options.NoUpload) { return $null }
    $jeton = $null
    if ($Options.Token) { $jeton = ([string]$Options.Token).Trim() }
    if (-not $jeton) { return $null }
    $jeton
}

function Write-SanteApercuEnvoi {
    [CmdletBinding()]
    param(
        $Rapport,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Jeton,
        [AllowEmptyString()][string]$Launch
    )
    Write-Host ('Passe : ' + [string]$Rapport.Pass)
    Write-Host ('Récapitulatif : ' + [string]$Rapport.SummaryEtat)
    Write-Host ('Contrôles : ' + [string]$Rapport.ControlCount)
    $ligneId = 'machineId : ' + [string]$Rapport.MachineId
    if ($Rapport.Label) { $ligneId = $ligneId + ' — ' + [string]$Rapport.Label }
    Write-Host $ligneId
    if ($Rapport.MachineIdWeak) { Write-Host 'Identifiant peu stable' }
    foreach ($controle in @($Rapport.Controls)) {
        Write-Host ([string]$controle.controle + ' : ' + [string]$controle.etat)
    }
    Write-Host ('Destination : ' + $script:SanteIngestUrl)
    if ($Jeton) {
        Write-Host ('Jeton : ' + (Get-SanteApercuJeton -Jeton $Jeton))
    }
    elseif ($Launch) {
        $apercu = [string]$Launch
        if ($apercu.Length -gt 12) { $apercu = $apercu.Substring(0, 12) + [string][char]0x2026 }
        Write-Host ('Autorisation : identifiant de lancement ' + $apercu)
    }
    else {
        Write-Host 'Autorisation : adresse IP publique (liste blanche de la console)'
    }
}

function Send-SanteRapport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Json,
        [AllowEmptyString()][string]$Jeton,
        [AllowEmptyString()][string]$Launch
    )
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor 3072
    $encodage = New-Object System.Text.UTF8Encoding $false
    $corps = $encodage.GetBytes($Json)
    $entetes = @{}
    if ($Jeton) { $entetes['Authorization'] = 'Bearer ' + $Jeton }
    elseif ($Launch) { $entetes['X-Sante-Launch'] = $Launch }
    try {
        $reponse = Invoke-RestMethod -Uri $script:SanteIngestUrl -Method Post -ContentType 'application/json; charset=utf-8' -Headers $entetes -Body $corps -TimeoutSec 30
        $identifiant = ''
        if ($null -ne $reponse -and $null -ne $reponse.reportId) {
            $identifiant = [string]$reponse.reportId
        }
        Write-Host ('Envoyé ' + $identifiant)
    }
    catch {
        $statut = ''
        try {
            if ($null -ne $_.Exception.Response -and $null -ne $_.Exception.Response.StatusCode) {
                $statut = [string]([int]$_.Exception.Response.StatusCode)
            }
        }
        catch { $statut = '' }
        $detail = [string]$_.Exception.Message
        if ($Jeton -and $detail.Contains($Jeton)) {
            $detail = $detail.Replace($Jeton, (Get-SanteApercuJeton -Jeton $Jeton))
        }
        if ($statut) {
            Write-Warning ('Envoi non abouti (' + $statut + '). ' + $detail)
        }
        else {
            Write-Warning ('Envoi non abouti. ' + $detail)
        }
    }
}

function Publish-SanteEnvironnementEnfant {
    [CmdletBinding()]
    param($Options)
    $anciensProcess = @{
        SANTE_TOKEN      = $env:SANTE_TOKEN
        SANTE_LABEL      = $env:SANTE_LABEL
        SANTE_LAUNCH     = $env:SANTE_LAUNCH
        SANTE_NO_UPLOAD  = $env:SANTE_NO_UPLOAD
        SANTE_UPLOAD     = $env:SANTE_UPLOAD
        SANTE_PASSE      = $env:SANTE_PASSE
        SANTE_RELAUNCHED = $env:SANTE_RELAUNCHED
    }
    $env:SANTE_PASSE = 'Complete'
    $env:SANTE_RELAUNCHED = '1'
    if ($null -ne $Options -and $Options.Token) { $env:SANTE_TOKEN = [string]$Options.Token }
    if ($null -ne $Options -and $Options.Label) { $env:SANTE_LABEL = [string]$Options.Label }
    if ($null -ne $Options -and $Options.Launch) { $env:SANTE_LAUNCH = [string]$Options.Launch }
    if ($null -ne $Options -and $Options.NoUpload) {
        $env:SANTE_NO_UPLOAD = '1'
        Remove-Item Env:\SANTE_UPLOAD -ErrorAction SilentlyContinue
    }
    elseif ($null -ne $Options -and ($Options.Upload -or $Options.Token)) {
        Remove-Item Env:\SANTE_NO_UPLOAD -ErrorAction SilentlyContinue
        if ($Options.Upload) { $env:SANTE_UPLOAD = '1' }
    }
    $voulus = @{
        SANTE_TOKEN      = $env:SANTE_TOKEN
        SANTE_LABEL      = $env:SANTE_LABEL
        SANTE_LAUNCH     = $env:SANTE_LAUNCH
        SANTE_NO_UPLOAD  = $env:SANTE_NO_UPLOAD
        SANTE_UPLOAD     = $env:SANTE_UPLOAD
        SANTE_PASSE      = $env:SANTE_PASSE
        SANTE_RELAUNCHED = $env:SANTE_RELAUNCHED
    }
    $anciensUser = @{}
    foreach ($nom in @($voulus.Keys)) {
        try {
            $anciensUser[$nom] = [Environment]::GetEnvironmentVariable($nom, 'User')
            $valeur = $voulus[$nom]
            if ($null -eq $valeur -or [string]$valeur -eq '') {
                [Environment]::SetEnvironmentVariable($nom, $null, 'User')
            }
            else {
                [Environment]::SetEnvironmentVariable($nom, [string]$valeur, 'User')
            }
        }
        catch { $null = $_.Exception.Message }
    }
    [pscustomobject]@{
        Process = $anciensProcess
        User    = $anciensUser
    }
}

function Restore-SanteEnvironnementEnfant {
    [CmdletBinding()]
    param($Etat)
    if ($null -eq $Etat) { return }
    foreach ($nom in @($Etat.User.Keys)) {
        try {
            $valeur = $Etat.User[$nom]
            if ($null -eq $valeur -or [string]$valeur -eq '') {
                [Environment]::SetEnvironmentVariable($nom, $null, 'User')
            }
            else {
                [Environment]::SetEnvironmentVariable($nom, [string]$valeur, 'User')
            }
        }
        catch { $null = $_.Exception.Message }
    }
    foreach ($nom in @($Etat.Process.Keys)) {
        $valeur = $Etat.Process[$nom]
        if ($null -eq $valeur -or [string]$valeur -eq '') {
            Remove-Item -Path ('Env:\' + $nom) -ErrorAction SilentlyContinue
        }
        else {
            Set-Item -Path ('Env:\' + $nom) -Value ([string]$valeur)
        }
    }
}

function Invoke-SantePc {
    [CmdletBinding()]
    param(
        [ValidateSet('Rapide', 'Complete')]
        [string]$Passe = 'Rapide',
        [switch]$Relancer,
        $Options
    )
    $ErrorActionPreference = 'Continue'
    $ProgressPreference = 'SilentlyContinue'
    Write-Host ('Santé PC ' + $script:SanteVersion)
    Write-Host $script:SanteUrl

    if ($null -eq $Options) { $Options = Get-SanteOptions -Arguments @() }

    if (($Passe -eq 'Complete') -and $Relancer) {
        $admin = $false
        try { $admin = [bool](Test-SanteAdministrator) }
        catch { $admin = $false }
        if ((-not $admin) -and ($env:SANTE_RELAUNCHED -ne '1')) {
            $relance = Start-SanteElevation -Options $Options
            if ($relance) { return }
        }
    }

    $lignes = New-Object System.Collections.Generic.List[object]
    Add-SanteLignes $lignes (Get-SanteIdentite)
    Add-SanteLignes $lignes (Get-SanteDisque)
    Add-SanteLignes $lignes (Get-SanteBatterie)
    Add-SanteLignes $lignes (Get-SantePeripheriques)
    Add-SanteLignes $lignes (Get-SantePilotes)
    Add-SanteLignes $lignes (Get-SanteServices)
    Add-SanteLignes $lignes (Get-SanteJournal)
    Add-SanteLignes $lignes (Get-SanteDefender)
    Add-SanteLignes $lignes (Get-SanteSecureBoot)
    Add-SanteLignes $lignes (Get-SanteCheckHealth)
    Add-SanteLignes $lignes (Get-SanteRedemarrage)
    Add-SanteLignes $lignes (Get-SanteEchecsPaquets)
    if ($Passe -eq 'Complete') {
        Add-SanteLignes $lignes (Get-SanteCompteursDisque)
        Add-SanteLignes $lignes (Get-SanteJournalDisque)
        Add-SanteLignes $lignes (Get-SanteWhea)
        Add-SanteLignes $lignes (Get-SanteArrets)
        Add-SanteLignes $lignes (Get-SantePiloteGraphique)
        Add-SanteLignes $lignes (Get-SantePiloteNonCharge)
        Add-SanteLignes $lignes (Get-SantePiloteBloque)
        Add-SanteLignes $lignes (Get-SanteFiabilite)
        Add-SanteLignes $lignes (Get-SanteTemperatures)
        Add-SanteLignes $lignes (Get-SanteScanHealth)
        Add-SanteLignes $lignes (Get-SanteFichiersProteges)
        Add-SanteLignes $lignes (Get-SanteEtatPaquets)
        Add-SanteLignes $lignes (Get-SanteRapportBatterie)
    }
    Add-SanteLignes $lignes (Get-SanteSummary -Lignes $lignes.ToArray())
    try {
        $rapport = New-SanteRapport -Lignes $lignes.ToArray() -Passe $Passe -Options $Options
        $cheminRapport = Save-SanteRapportLocal -Json $rapport.Json
        if ($cheminRapport) { Write-Host ('Rapport local : ' + $cheminRapport) }
        if (Test-SanteEnvoiDemande -Options $Options) {
            $jetonEnvoi = Resolve-SanteJetonEnvoi -Options $Options
            $launchEnvoi = $null
            if ($null -ne $Options -and $Options.Launch) { $launchEnvoi = [string]$Options.Launch }
            Write-SanteApercuEnvoi -Rapport $rapport -Jeton $jetonEnvoi -Launch $launchEnvoi
            Send-SanteRapport -Json $rapport.Json -Jeton $jetonEnvoi -Launch $launchEnvoi
            $jetonEnvoi = $null
            $launchEnvoi = $null
        }
    }
    catch {
        Write-Warning ('Rapport local incomplet : ' + [string]$_.Exception.Message)
    }
    foreach ($ligne in $lignes) { $ligne }
}

$santeInvocation = ''
if ($null -ne $MyInvocation -and $null -ne $MyInvocation.InvocationName) {
    $santeInvocation = [string]$MyInvocation.InvocationName
}
$santeLigne = ''
if ($null -ne $MyInvocation -and $null -ne $MyInvocation.Line) {
    $santeLigne = [string]$MyInvocation.Line
}
$santePoint = $false
if ($santeInvocation -eq '.') { $santePoint = $true }
if ($santeLigne -match '^\s*\.\s') { $santePoint = $true }
if (-not $santePoint) {
    $ErrorActionPreference = 'Continue'
    $santeOptions = Get-SanteOptions -Arguments @($args)
    Invoke-SantePc -Passe $santeOptions.Passe -Relancer -Options $santeOptions
}
