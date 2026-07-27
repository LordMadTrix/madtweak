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
