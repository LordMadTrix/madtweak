# ------------------------------------------------------------------------------
# POINT DE RESTAURATION (via CIM : fonctionne en PS 5.1 ET PS 7)
# ------------------------------------------------------------------------------
function New-PointRestauration {
    param([string]$Description = "MadTweak")

    if ($script:Simulation) {
        Write-Simu "créerait un point de restauration « $Description » (rien n'étant modifié en simulation, il est inutile ici)"
        return $true
    }
    $freqPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SystemRestore"
    $freqOrig = $null
    $freqModifiee = $false

    try {
        Write-Etat "Activation de la protection système sur $env:SystemDrive si nécessaire..."
        Invoke-CimMethod -Namespace 'root/default' -ClassName SystemRestore `
            -MethodName Enable -Arguments @{ Drive = "$env:SystemDrive\" } | Out-Null

        # Windows refuse un 2e point dans les 24 h : on lève la limite temporairement.
        $freqOrig = (Get-ItemProperty -Path $freqPath -Name "SystemRestorePointCreationFrequency" -ErrorAction SilentlyContinue).SystemRestorePointCreationFrequency
        Set-RegValue -Path $freqPath -Name "SystemRestorePointCreationFrequency" -Value 0
        $freqModifiee = $true

        $pointsAvant = Get-CimInstance -Namespace 'root/default' -ClassName SystemRestore -ErrorAction SilentlyContinue
        $avant = if ($null -ne $pointsAvant) { @($pointsAvant).Count } else { $null }

        Write-Etat "Création du point de restauration (peut prendre 30 à 60 secondes)..."
        $r = Invoke-CimMethod -Namespace 'root/default' -ClassName SystemRestore -MethodName CreateRestorePoint `
            -Arguments @{ Description = $Description; RestorePointType = [uint32]12; EventType = [uint32]100 }

        if ($r.ReturnValue -ne 0) { throw "Windows a refusé la création (code $($r.ReturnValue))." }

        # On ne croit pas Windows sur parole : on vérifie que le point existe vraiment (si possible).
        $pointsApres = Get-CimInstance -Namespace 'root/default' -ClassName SystemRestore -ErrorAction SilentlyContinue
        $apres = if ($null -ne $pointsApres) { @($pointsApres).Count } else { $null }

        if ($null -ne $avant -and $null -ne $apres) {
            if ($apres -le $avant) {
                throw "Aucune erreur signalée, mais aucun point n'apparaît dans la liste."
            }
            Write-Etat "Point de restauration créé ET vérifié ($apres point(s) au total)." -Niveau OK
        } else {
            Write-Etat "Point de restauration créé (vérification de liste non disponible)." -Niveau OK
        }
        return $true
    }
    catch {
        Write-Etat "Point de restauration NON créé : $($_.Exception.Message)" -Niveau Echec
        return $false
    }
    finally {
        # On remet la limite des 24 h comme on l'a trouvée.
        if ($freqModifiee) {
            try {
                if ($null -ne $freqOrig) { Set-RegValue -Path $freqPath -Name "SystemRestorePointCreationFrequency" -Value $freqOrig }
                else { Remove-ItemProperty -Path $freqPath -Name "SystemRestorePointCreationFrequency" -ErrorAction SilentlyContinue }
            }
            catch { Write-Etat "Impossible de restaurer la fréquence des points de restauration." -Niveau Avert }
        }
    }
}

function Confirmer-Filet-Securite {
    # Utilisé avant les menus qui touchent à des choses lourdes.
    if (Demander-Option "Créer un point de restauration de sécurité (fortement recommandé) ?") {
        if (New-PointRestauration -Description "MadTweak") { return $true }
        Write-Host ""
        Write-Etat "ATTENTION : tu n'as AUCUN filet de sécurité." -Niveau Avert
        return (Demander-Option "  Continuer quand même malgré l'absence de point de restauration ?")
    }
    return $true
}


function Get-PointsRestauration {
    # Liste les points de restauration existants, du plus récent au plus ancien.
    # Lecture seule. Sert à l'interface : jusqu'ici le script savait en CRÉER un,
    # mais pas montrer ceux qui existent -- il fallait sortir de l'outil pour ça.
    try {
        $pts = @(Get-CimInstance -Namespace 'root/default' -ClassName SystemRestore -ErrorAction Stop)
    }
    catch { return @() }
    $res = @()
    foreach ($p in $pts) {
        # CreationTime est au format WMI (yyyyMMddHHmmss.xxxxxx±UUU).
        $date = $null
        try { $date = [Management.ManagementDateTimeConverter]::ToDateTime($p.CreationTime) } catch { }
        $res += [pscustomobject]@{
            Numero      = $p.SequenceNumber
            Description = "$($p.Description)"
            Date        = $date
            Type        = switch ([int]$p.RestorePointType) {
                0 { "Installation d'application" } 1 { "Désinstallation d'application" }
                10 { "Installation de pilote" } 12 { "Modification manuelle" } 13 { "Windows Update" }
                default { "Type $($p.RestorePointType)" }
            }
        }
    }
    return @($res | Sort-Object Numero -Descending)
}

function Restore-PointRestauration {
    # Lance la restauration système vers un point donné. Windows REDÉMARRE la machine
    # pour l'appliquer : c'est le comportement normal, et c'est pour ça que l'appelant
    # doit confirmer explicitement avant d'arriver ici.
    param([Parameter(Mandatory)][int]$Numero)
    if ($script:Simulation) {
        Write-Simu "restaurerait le système au point $Numero (la machine redémarrerait)"
        return $true
    }
    $r = Invoke-CimMethod -Namespace 'root/default' -ClassName SystemRestore `
        -MethodName Restore -Arguments @{ SequenceNumber = [uint32]$Numero } -ErrorAction Stop
    if ($r.ReturnValue -ne 0) { throw "Windows a refusé la restauration (code $($r.ReturnValue))." }
    return $true
}
