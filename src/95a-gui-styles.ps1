# ------------------------------------------------------------------------------
# INTERFACE GRAPHIQUE (WPF) — HELPER STYLES & TRADUCTIONS
# ------------------------------------------------------------------------------

function Update-InterfaceGui {
    # L'équivalent WPF de DoEvents : on laisse le Dispatcher traiter ce qui est en
    # attente (redessin, log) avant de reprendre.
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [System.Windows.Threading.DispatcherOperationCallback] { param($f) $f.Continue = $false; return $null },
        $frame) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function Get-NomOnglet {
    # Les titres de menu sont écrits pour une console en majuscules : ils sont bien
    # trop longs pour un onglet. On les raccourcit ici, et seulement pour l'affichage.
    param([Parameter(Mandatory)][string]$Categorie)
    $en = $script:LangueActive -eq 'en'
    switch -Wildcard ($Categorie) {
        "TWEAKS DE BASE*" { if ($en) { "Basics" } else { "Base" } }
        "TWEAKS AVANCÉS*" { if ($en) { "Advanced" } else { "Avancés" } }
        "EXPLORATEUR*" { if ($en) { "Privacy" } else { "Vie privée" } }
        "OPTIMISATION DU MATÉRIEL*" { if ($en) { "Hardware & Network" } else { "Matériel & Réseau" } }
        "SÉCURITÉ & IA*" { if ($en) { "Security & AI" } else { "Sécurité & IA" } }
        "NOUVEAUTÉS WINDOWS 11*" { if ($en) { "Windows 11" } else { "Windows 11" } }
        "APPARENCE*" { if ($en) { "Appearance" } else { "Apparence" } }
        "DÉMARRAGE*" { if ($en) { "Startup & Services" } else { "Démarrage & Services" } }
        "CONFIGURATION SÉCURITÉ*" { if ($en) { "Updates & Security" } else { "Mises à jour & Sécurité" } }
        "LOGICIELS EXPRESS*" { if ($en) { "Software (winget)" } else { "Logiciels (winget)" } }
        "OUTILS DE DIAGNOSTIC*" { if ($en) { "Maintenance" } else { "Maintenance" } }
        "NETTOYAGE DU DISQUE*" { if ($en) { "Cleanup" } else { "Nettoyage" } }
        default { $Categorie }
    }
}

function Get-NomProfil {
    param([Parameter(Mandatory)][string]$Nom)
    if ($script:LangueActive -eq 'en' -and $script:Profils[$Nom].Nom_en) { return $script:Profils[$Nom].Nom_en }
    return $Nom
}

function Get-DescriptionProfil {
    param([Parameter(Mandatory)][string]$Nom)
    $p = $script:Profils[$Nom]
    if ($script:LangueActive -eq 'en' -and $p.Description_en) { return $p.Description_en }
    return $p.Description
}
