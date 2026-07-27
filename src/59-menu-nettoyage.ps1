# ------------------------------------------------------------------------------
# NETTOYAGE DU DISQUE
#
# Principe : on MESURE avant de proposer. Un menu qui propose de vider un dossier
# déjà vide fait perdre du temps et donne l'illusion d'avoir gagné de la place.
# Rien n'est supprimé hors de ces dossiers, et aucun document personnel n'est visé.
# ------------------------------------------------------------------------------
function Get-TailleDossier {
    param([Parameter(Mandatory)][string]$Chemin)
    if (-not (Test-Path $Chemin)) { return [long]0 }
    try {
        $s = (Get-ChildItem -Path $Chemin -Recurse -Force -ErrorAction SilentlyContinue |
              Measure-Object -Property Length -Sum).Sum
        if ($null -eq $s) { return [long]0 }
        return [long]$s
    }
    catch { return [long]0 }
}

function Format-Taille {
    param([double]$Octets)
    if ($Octets -ge 1GB) { return "{0:N1} Go" -f ($Octets / 1GB) }
    if ($Octets -ge 1MB) { return "{0:N0} Mo" -f ($Octets / 1MB) }
    if ($Octets -ge 1KB) { return "{0:N0} Ko" -f ($Octets / 1KB) }
    return "$([int]$Octets) o"
}

function Clear-Contenu {
    # Vide un dossier SANS le supprimer lui-même : Windows recrée mal certains de
    # ces dossiers (Temp notamment) s'ils disparaissent.
    # Les fichiers en cours d'utilisation refusent d'être supprimés : c'est NORMAL
    # et ce n'est pas un échec. On compte ce qui résiste au lieu de lever.
    param([Parameter(Mandatory)][string]$Chemin)
    if (-not (Test-Path $Chemin)) { return @{ Supprimes = 0; Resistants = 0 } }
    $ok = 0; $ko = 0
    foreach ($e in (Get-ChildItem -Path $Chemin -Force -ErrorAction SilentlyContinue)) {
        try {
            Remove-Item -Path $e.FullName -Recurse -Force -ErrorAction Stop
            $ok++
        }
        catch { $ko++ }
    }
    return @{ Supprimes = $ok; Resistants = $ko }
}

function Get-CiblesNettoyage {
    return [ordered]@{
        "Fichiers temporaires (ton compte)" = @{
            Chemin = $env:TEMP
            Note   = "Vidé automatiquement par Windows, mais rarement en totalité."
        }
        "Fichiers temporaires (Windows)" = @{
            Chemin = "$env:SystemRoot\Temp"
            Note   = "Temporaires des services et des installeurs."
        }
        "Cache de Windows Update" = @{
            Chemin = "$env:SystemRoot\SoftwareDistribution\Download"
            Note   = "Installeurs déjà appliqués. Windows les retélécharge si besoin."
            Service = "wuauserv"
        }
        "Rapports d'erreurs Windows" = @{
            Chemin = "$env:ProgramData\Microsoft\Windows\WER"
            Note   = "Vidages mémoire des plantages passés."
        }
        "Cache de Delivery Optimization" = @{
            Chemin = "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization"
            Note   = "Morceaux de mises à jour mis en cache pour le partage P2P."
        }
        "Cache des miniatures" = @{
            Chemin = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
            Note   = "Reconstruit à la demande. L'Explorateur sera brièvement plus lent après."
        }
    }
}

function Menu-Nettoyage {
    Start-Menu -Titre "NETTOYAGE DU DISQUE" -Couleur Green -SousTitre @(
        "Les tailles sont MESURÉES avant de te proposer quoi que ce soit.",
        "Aucun document personnel n'est visé : uniquement des caches et des temporaires."
    )

    if (Test-SansInteraction) {
        Invoke-Tweak "Vider les fichiers temporaires (compte utilisateur)" -Cle "nettoyage-temp-user" `
            -Explication "Vide le dossier temporaire du compte utilisateur courant (TEMP). Libère de l'espace disque." {
            $c = (Get-CiblesNettoyage)["Fichiers temporaires (ton compte)"]
            $r = Clear-Contenu -Chemin $c.Chemin
            Write-Etat "Fichiers temporaires utilisateur nettoyés. $($r.Supprimes) supprimé(s), $($r.Resistants) verrouillé(s)." -Niveau Info
        }
        Invoke-Tweak "Vider les fichiers temporaires (système Windows)" -Cle "nettoyage-temp-system" `
            -Explication "Vide le dossier temporaire système de Windows (System Temp) utilisé par les services et installeurs." {
            $c = (Get-CiblesNettoyage)["Fichiers temporaires (Windows)"]
            $r = Clear-Contenu -Chemin $c.Chemin
            Write-Etat "Fichiers temporaires système nettoyés. $($r.Supprimes) supprimé(s), $($r.Resistants) verrouillé(s)." -Niveau Info
        }
        Invoke-Tweak "Vider le cache de Windows Update" -Cle "nettoyage-update-cache" `
            -Explication "Supprime les installeurs et fichiers temporaires des mises à jour Windows déjà appliquées." {
            $c = (Get-CiblesNettoyage)["Cache de Windows Update"]
            $svc = Get-Service -Name $c.Service -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') { Stop-Service -Name $c.Service -Force -ErrorAction SilentlyContinue }
            try {
                $r = Clear-Contenu -Chemin $c.Chemin
                Write-Etat "Cache Windows Update nettoyé. $($r.Supprimes) supprimé(s), $($r.Resistants) verrouillé(s)." -Niveau Info
            }
            finally {
                if ($svc -and $svc.Status -eq 'Running') { Start-Service -Name $c.Service -ErrorAction SilentlyContinue }
            }
        }
        Invoke-Tweak "Vider les rapports d'erreurs Windows (WER)" -Cle "nettoyage-wer" `
            -Explication "Supprime les fichiers de rapport de plantage et les vidages de mémoire système." {
            $c = (Get-CiblesNettoyage)["Rapports d'erreurs Windows"]
            $r = Clear-Contenu -Chemin $c.Chemin
            Write-Etat "Rapports d'erreurs WER nettoyés. $($r.Supprimes) supprimé(s), $($r.Resistants) verrouillé(s)." -Niveau Info
        }
        Invoke-Tweak "Vider le cache Delivery Optimization" -Cle "nettoyage-delivery-optimization" `
            -Explication "Supprime les fichiers temporaires de distribution des mises à jour réseau peer-to-peer." {
            $c = (Get-CiblesNettoyage)["Cache de Delivery Optimization"]
            $r = Clear-Contenu -Chemin $c.Chemin
            Write-Etat "Cache Delivery Optimization nettoyé. $($r.Supprimes) supprimé(s), $($r.Resistants) verrouillé(s)." -Niveau Info
        }
        Invoke-Tweak "Vider le cache des miniatures de l'Explorateur" -Cle "nettoyage-miniatures" `
            -Explication "Supprime les fichiers de cache des miniatures (reconstruit automatiquement lors de la navigation)." {
            $c = (Get-CiblesNettoyage)["Cache des miniatures"]
            $r = Clear-Contenu -Chemin $c.Chemin
            Write-Etat "Cache des miniatures nettoyé. $($r.Supprimes) supprimé(s), $($r.Resistants) verrouillé(s)." -Niveau Info
        }
        Invoke-Tweak "Supprimer le dossier de restauration Windows.old" -Cle "nettoyage-windows-old" `
            -Explication "Supprime définitivement le dossier Windows.old contenant l'ancienne installation système (renonce au retour en arrière)." {
            $wold = "$env:SystemDrive\Windows.old"
            if (Test-Path $wold) {
                Invoke-Externe -Fichier "takeown.exe" -Arguments @("/F", $wold, "/R", "/D", "O") -CodesOK @(0, 1)
                Invoke-Externe -Fichier "icacls.exe" -Arguments @($wold, "/grant", "*S-1-5-32-544:F", "/T", "/C") -CodesOK @(0, 1332)
                $r = Clear-Contenu -Chemin $wold
                Remove-Item -Path $wold -Recurse -Force -ErrorAction SilentlyContinue
                Write-Etat "Dossier Windows.old supprimé. $($r.Supprimes) supprimé(s), $($r.Resistants) verrouillé(s)." -Niveau Info
            } else {
                Write-Etat "Dossier Windows.old inexistant : rien à nettoyer." -Niveau Info
            }
        }
        return
    }

    $libre = $null
    try { $libre = (Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop).Free } catch { }
    if ($null -ne $libre) { Write-Host "  Espace libre sur $($env:SystemDrive) : $(Format-Taille $libre)" -ForegroundColor Gray }

    Write-Host "  Mesure en cours (quelques secondes)..." -ForegroundColor DarkGray
    $cibles = Get-CiblesNettoyage
    $tailles = [ordered]@{}
    $total = [long]0
    foreach ($nom in $cibles.Keys) {
        $t = Get-TailleDossier $cibles[$nom].Chemin
        $tailles[$nom] = $t
        $total += $t
    }

    Write-Host ""
    foreach ($nom in $cibles.Keys) {
        $couleur = if ($tailles[$nom] -gt 100MB) { "Yellow" } elseif ($tailles[$nom] -gt 0) { "Gray" } else { "DarkGray" }
        Write-Host ("  {0,-38} {1,10}" -f $nom, (Format-Taille $tailles[$nom])) -ForegroundColor $couleur
    }
    Write-Host ("  {0,-38} {1,10}" -f "TOTAL RÉCUPÉRABLE", (Format-Taille $total)) -ForegroundColor Cyan
    Write-Host ""

    if ($total -lt 50MB) {
        Write-Etat "Moins de 50 Mo à récupérer : ta machine est déjà propre, ça n'en vaut pas la peine." -Niveau Info
        Read-Host "`nAppuie sur Entrée pour revenir au menu principal"
        return
    }

    foreach ($nom in $cibles.Keys) {
        $c = $cibles[$nom]
        $taille = $tailles[$nom]
        # On ne propose PAS de vider ce qui est déjà vide : ça n'a aucun sens et ça
        # ferait croire à un gain.
        if ($taille -lt 1MB) { continue }

        Invoke-Tweak "Vider « $nom » ($(Format-Taille $taille)) ? $($c.Note)" {
            if ($script:Simulation) {
                Write-Simu "viderait $($c.Chemin) et récupérerait environ $(Format-Taille $taille)"
                return
            }
            # Le cache de Windows Update ne peut pas être vidé pendant que le service
            # le tient ouvert : on l'arrête, on nettoie, on le remet comme il était.
            $svc = $null
            if ($c.Service) {
                $svc = Get-Service -Name $c.Service -ErrorAction SilentlyContinue
                if ($svc -and $svc.Status -eq 'Running') { Stop-Service -Name $c.Service -Force -ErrorAction SilentlyContinue }
            }
            try {
                $r = Clear-Contenu -Chemin $c.Chemin
                $apres = Get-TailleDossier $c.Chemin
                $gagne = $taille - $apres
                Write-Etat "$(Format-Taille $gagne) récupéré(s). $($r.Supprimes) élément(s) supprimé(s), $($r.Resistants) en cours d'utilisation (normal)." -Niveau Info
            }
            finally {
                if ($svc -and $svc.Status -eq 'Running') { Start-Service -Name $c.Service -ErrorAction SilentlyContinue }
            }
        }.GetNewClosure()
    }

    # Windows.old est à part : ce n'est pas un cache, c'est ton billet de retour.
    $wold = "$env:SystemDrive\Windows.old"
    if (Test-Path $wold) {
        $t = Get-TailleDossier $wold
        Write-Host ""
        Write-Etat "Windows.old détecté ($(Format-Taille $t)). C'est ta copie de l'ancienne installation : elle permet de REVENIR EN ARRIÈRE après une mise à jour de fonctionnalités." -Niveau Avert
        Write-Etat "Windows le supprime tout seul au bout de 10 jours." -Niveau Info
        Invoke-Tweak "Supprimer Windows.old maintenant et renoncer au retour arrière ?" {
            # Ce dossier appartient à TrustedInstaller : sans reprise de possession,
            # Remove-Item échoue sur la quasi-totalité de son contenu.
            Invoke-Externe -Fichier "takeown.exe" -Arguments @("/F", $wold, "/R", "/D", "O") -CodesOK @(0, 1)
            Invoke-Externe -Fichier "icacls.exe" -Arguments @($wold, "/grant", "*S-1-5-32-544:F", "/T", "/C") -CodesOK @(0, 1332)
            $r = Clear-Contenu -Chemin $wold
            Remove-Item -Path $wold -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path $wold) {
                throw "Windows.old résiste encore ($($r.Resistants) élément(s)). Utilise le Nettoyage de disque de Windows (cleanmgr) : lui seul sait le supprimer entièrement."
            }
            Write-Etat "Windows.old supprimé : $(Format-Taille $t) récupéré(s)." -Niveau Info
        }.GetNewClosure()
    }

    Fin-De-Menu
}

