# ------------------------------------------------------------------------------
# LANCEMENT
# ------------------------------------------------------------------------------
if ($script:BypassLancement) { return }

# La langue suit Windows, sauf si -Langue la force. Une préférence enregistrée depuis
# l'interface l'emporte sur la détection, mais pas sur le paramètre explicite.
if ($Langue) { Set-Langue $Langue }
elseif ($env:LOCALAPPDATA) {
    $fLangue = Join-Path $env:LOCALAPPDATA "MadTweak\langue.txt"
    if (Test-Path $fLangue) {
        try { Set-Langue ([System.IO.File]::ReadAllText($fLangue).Trim()) } catch { }
    }
}

# Mode maintenance (tâche planifiée) : nettoyage léger, silencieux, puis on sort.
# Ni interface, ni menu, ni journal -- c'est une tâche de fond.
if ($Maintenance) {
    try { Invoke-MaintenanceSilencieuse | Out-Null } catch { }
    return
}

Initialize-Sauvegarde

# Le journal va dans le même dossier que la sauvegarde : celui-ci est déjà garanti
# accessible en écriture, y compris si le script est lancé depuis une clé USB en
# lecture seule ou collé directement dans une console (où $PSScriptRoot est vide).
$journal = Join-Path $script:DossierDonnees "madtweak-log-$(Get-Date -Format 'yyyy-MM-dd_HH-mm-ss').txt"
try { Start-Transcript -Path $journal -ErrorAction Stop | Out-Null } catch { Write-Etat "Journal désactivé : $($_.Exception.Message)" -Niveau Avert }

if ($PSVersionTable.PSEdition -eq 'Core') {
    Write-Etat "PowerShell $($PSVersionTable.PSVersion) détecté : la suppression des bloatwares passe par une couche de compatibilité et peut être lente." -Niveau Avert
    Write-Etat "Pour un comportement optimal, lance ce script dans Windows PowerShell 5.1 (powershell.exe) en administrateur." -Niveau Avert
    Start-Sleep -Seconds 3
}

# Contrôles d'intégrité : une clé de profil mal orthographiée, un audit qui teste
# dans le vide ou un tweak sans explication ne produisent AUCUNE erreur -- juste un
# comportement silencieusement incomplet. Autant que ça se voie au démarrage.
Test-ClesProfils
Test-CoherenceAudit
Test-Explications

try {
    if ($Profil) {
        # Installation automatisée : on applique le profil et on sort. Ni interface,
        # ni menu -- il n'y a pas de session de travail ici, juste un lot à jouer.
        $nomExact = Resolve-NomProfil $Profil
        if (-not $nomExact) {
            Write-Etat "Profil « $Profil » inconnu." -Niveau Erreur
            Write-Etat "Profils disponibles : $($script:Profils.Keys -join ' | ')" -Niveau Info
        }
        else {
            $script:SansQuestion = $true
            try { Invoke-Profil $nomExact }
            finally {
                # On rend la parole AVANT de parler de redémarrage : quelqu'un vient
                # d'ouvrir sa session, il est devant l'écran. Redémarrer sa machine
                # neuve sans le lui demander serait le pire accueil possible.
                $script:SansQuestion = $false
            }
        }
    }
    else {
        # Interface graphique par défaut ; -Console force l'ancien menu.
        # Le repli n'est pas décoratif : WPF manque sur une installation Server Core, et
        # il exige un thread STA -- ce que powershell.exe fournit, mais pas n'importe
        # quel hôte. Plutôt que d'échouer, on redonne la main à la console, qui sait
        # tout faire (et même davantage : les tweaks lourds n'existent que là).
        $consoleDemandee = [bool]$Console
        if (-not $consoleDemandee) {
            # Le premier chargement de WPF (Add-Type PresentationFramework) prend quelques
            # secondes : sans ce message, la console reste muette et on croit à un blocage.
            Write-Host ""
            Write-Host "  Ouverture de l'interface graphique (chargement de l'affichage, quelques secondes)..." -ForegroundColor Cyan
            try { Show-Gui }
            catch {
                Write-Etat "Interface graphique indisponible : $($_.Exception.Message)" -Niveau Avert
                Write-Etat "Repli sur le menu console." -Niveau Info
                Start-Sleep -Seconds 2
                $consoleDemandee = $true
            }
        }
        if ($consoleDemandee) { Afficher-Menu-Principal }
    }

    # C'est ici que se joue le cumul des redémarrages : les tweaks marqués
    # -Redemarrage ont alimenté $script:RedemarrageRequis tout au long de la session,
    # que l'on soit passé par l'interface ou par la console. On ne le propose qu'une
    # fois, à la sortie.
    Invoke-RedemarrageFinal
}
finally {
    $script:SortieGui = $null   # la console reprend la main quoi qu'il arrive
    try { Stop-Transcript | Out-Null } catch { }
    Write-Host "`nJournal de session : $journal" -ForegroundColor DarkGray
}
