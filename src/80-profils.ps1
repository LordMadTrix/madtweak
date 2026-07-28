# ------------------------------------------------------------------------------
# PROFILS : appliquer un lot cohérent de tweaks sans répondre à 30 questions.
#
# Un profil n'est QU'UNE LISTE DE CLÉS. Il ne contient aucun code de tweak : il
# rejoue ceux des menus via $script:ProfilActif, que Invoke-Tweak consulte pour
# décider s'il s'exécute sans poser de question. Ajouter un tweak à un profil =
# ajouter sa clé ici. Les tweaks lourds ou irréversibles (désinstallation d'Edge
# ou de OneDrive, blocage de Windows Update, VBS, DISM/SFC) n'ont volontairement
# pas de clé : ils ne sont applicables qu'à la main, en connaissance de cause.
# ------------------------------------------------------------------------------
$script:Profils = [ordered]@{
    "Minimal / sûr" = @{
        Nom_en      = "Minimal / safe"
        Couleur     = "Green"
        Description = "Le strict nécessaire : pubs, télémétrie de base et confort d'affichage. Ne touche à AUCUN service, à aucun réglage de performance, et n'installe ni ne désinstalle rien. Le plus sûr et le plus facile à annuler."
        Description_en = "The bare essentials: ads, basic telemetry and display comfort. Touches NO service, no performance setting, and installs or uninstalls nothing. The safest and the easiest to undo."
        Cles        = @(
            "telemetrie", "extensions-fichiers", "explorateur-accueil", "widgets-chat",
            "widgets-dsh", "recherche-bing", "delivery-optimization", "autoplay",
            "pubs-demarrer", "pubs-scoobe", "pubs-explorateur", "pubs-verrouillage",
            "fin-de-tache", "barre-taches-gauche", "historique-activite",
            "experiences-personnalisees", "feedback",
            "bloquer-sug-store", "disable-login-blur", "delivery-optimization-p2p",
            "disable-web-search-start"
        )
    }
    "Interface épurée" = @{
        Nom_en      = "Clean interface"
        Couleur     = "White"
        Description = "Purement visuel : mode sombre, Explorateur compact ouvrant sur Ce PC, sans Galerie ni Accueil, barre des tâches allégée, menu clic droit de Windows 10. Ne touche à AUCUN service, réglage réseau ou de confidentialité. La transparence est incluse (c'est le seul de ces réglages qui coûte du GPU)."
        Description_en = "Purely visual: dark mode, compact Explorer opening on This PC, no Gallery or Home, lighter taskbar, Windows 10 right-click menu. Touches NO service, network or privacy setting. Transparency is included (it is the only one of these settings that costs GPU time)."
        Cles        = @(
            "mode-sombre", "transparence", "explorateur-compact", "explorateur-ce-pc",
            "explorateur-galerie", "explorateur-volet-accueil", "fichiers-caches",
            "extensions-fichiers", "explorateur-accueil", "suffixe-raccourci",
            "recherche-barre-taches", "bouton-vue-taches", "demarrer-plus-epingles",
            "barre-taches-gauche", "fin-de-tache", "clic-droit-classique",
            "aero-shake", "snap-layouts", "barres-defilement", "qualite-fond-ecran",
            "pubs-demarrer", "pubs-explorateur", "widgets-chat",
            "menu-delay", "disable-lock-screen", "disable-login-blur",
            "clic-droit-possession", "photo-classique", "god-mode",
            "widgets-paquet"
        )
    }
    "Vie privée" = @{
        Nom_en      = "Privacy"
        Couleur     = "Cyan"
        Description = "Coupe tout ce qui remonte des données : télémétrie et son service, tâches de collecte, historique d'activité, personnalisation de la saisie, recherche Bing, presse-papiers cloud, Copilot, Recall. Ne touche pas aux performances. La géolocalisation N'EST PAS incluse (elle casserait Météo et le fuseau horaire automatique) : à faire à la main si tu y tiens."
        Description_en = "Cuts everything that reports data: telemetry and its service, collection tasks, activity history, input personalisation, Bing search, cloud clipboard, Copilot, Recall. Does not touch performance. Location is NOT included (it would break Weather and automatic time zone): do that by hand if you insist."
        Cles        = @(
            "telemetrie", "service-diagtrack", "taches-telemetrie", "nvidia-telemetrie", "wer",
            "recherche-bing", "presse-papiers", "delivery-optimization", "autoplay",
            "apps-arriere-plan", "explorateur-accueil", "widgets-chat", "widgets-dsh",
            "pubs-demarrer", "pubs-scoobe", "pubs-explorateur", "pubs-verrouillage",
            "copilot", "recall", "paint-ia", "click-to-do",
            "historique-activite", "experiences-personnalisees", "feedback",
            "saisie-personnalisation", "defender-echantillons", "llmnr-netbios",
            "service-registre-distant", "service-retaildemo",
            "edge-telemetrie", "amd-telemetrie", "browsers-telemetrie",
            "office-telemetrie", "bloquer-sug-store", "dev-telemetrie",
            "disable-web-search-start", "thirdparty-telemetrie",
            "widgets-paquet"
        )
    }
    "Gamer" = @{
        Nom_en      = "Gamer"
        Couleur     = "Magenta"
        Description = "Latence et FPS : Game DVR, accélération souris, Nagle, bridage multimédia, animations, plan Performances ultimes. Attention : Nagle peut réduire ton débit en téléchargement, et le plan Performances ultimes sera refusé sur un portable."
        Description_en = "Latency and FPS: Game DVR, mouse acceleration, Nagle, multimedia throttling, animations, Ultimate Performance plan. Careful: Nagle can reduce your download throughput, and the Ultimate Performance plan will be refused on a laptop."
        Cles        = @(
            "game-dvr", "souris-acceleration", "nagle", "bridage-multimedia",
            "animations", "tuer-applis-figees", "sysmain", "usb-suspension",
            "plan-performances-ultimes", "noyau-en-ram", "telemetrie", "bloatwares",
            "apps-arriere-plan", "pubs-demarrer", "widgets-dsh", "nvidia-telemetrie",
            "carte-reseau-veille", "delai-demarrage", "service-diagtrack",
            "historique-activite", "service-retaildemo", "service-fax",
            "hags-gpu", "pcie-power-management", "xbox-gamebar", "menu-delay",
            "demarrage-rapide", "defender-cpu-limit",
            "explorer-separate-process", "kill-timeouts", "auto-restart-shell",
            "ntfs-performance", "disable-web-search-start",
            "widgets-paquet", "bloquer-sug-store"
        )
    }
    "Portable / batterie" = @{
        Nom_en      = "Laptop / battery"
        Couleur     = "Yellow"
        Description = "Autonomie et silence. Volontairement SANS l'hibernation (un portable en a besoin), sans la suspension USB et sans « carte réseau toujours alimentée » (les deux économisent la batterie), et sans le plan Performances ultimes (il la vide)."
        Description_en = "Battery life and quiet. Deliberately WITHOUT hibernation (a laptop needs it), without USB selective suspend and without « keep the network adapter powered » (both save battery), and without the Ultimate Performance plan (it drains it)."
        Cles        = @(
            "telemetrie", "service-diagtrack", "taches-telemetrie", "apps-arriere-plan",
            "delivery-optimization", "recherche-bing", "bloatwares", "wer", "game-dvr",
            "animations", "widgets-dsh", "pubs-demarrer", "pubs-verrouillage",
            "explorateur-accueil", "historique-activite", "experiences-personnalisees",
            "feedback", "service-retaildemo", "service-fax",
            "bloquer-sug-store", "edge-telemetrie", "delivery-optimization-p2p",
            "disable-web-search-start", "thirdparty-telemetrie"
        )
    }
}

# ------------------------------------------------------------------------------
# PERSISTANCE — clés déjà appliquées (pour la détection de dérive) et profils perso.
# Tout vit dans le dossier de données, à côté des sauvegardes.
# ------------------------------------------------------------------------------
function Get-ClesAppliquees {
    # Liste des clés que cet outil a déjà appliquées sur cette machine (cumulée).
    $f = Join-Path $script:DossierDonnees "cles-appliquees.json"
    if (-not (Test-Path $f)) { return @() }
    try { return @((Get-Content $f -Raw -ErrorAction Stop | ConvertFrom-Json)) } catch { return @() }
}

function Save-ClesAppliquees {
    # Ajoute des clés à la mémoire des tweaks appliqués (union, sans doublon).
    param([string[]]$Cles)
    $nouvelles = @($Cles | Where-Object { $_ })
    if ($nouvelles.Count -eq 0) { return }
    $union = @((Get-ClesAppliquees) + $nouvelles | Select-Object -Unique | Sort-Object)
    $f = Join-Path $script:DossierDonnees "cles-appliquees.json"
    try { ConvertTo-Json $union | Set-Content -Path $f -Encoding UTF8 } catch { }
}

function Get-ProfilsPerso {
    # Profils enregistrés par l'utilisateur : nom -> liste de clés. Ordonné.
    $f = Join-Path $script:DossierDonnees "profils-perso.json"
    if (-not (Test-Path $f)) { return [ordered]@{} }
    try {
        $o = Get-Content $f -Raw -ErrorAction Stop | ConvertFrom-Json
        $h = [ordered]@{}
        foreach ($p in $o.PSObject.Properties) { $h[$p.Name] = @($p.Value | Where-Object { $_ }) }
        return $h
    }
    catch { return [ordered]@{} }
}

function Save-ProfilPerso {
    # Enregistre (ou remplace) un profil personnalisé. Refuse d'écraser un profil intégré.
    param([Parameter(Mandatory)][string]$Nom, [string[]]$Cles)
    $Nom = $Nom.Trim()
    if (-not $Nom) { throw "Donne un nom au profil." }
    if ($Nom -in @($script:Profils.Keys)) { throw "« $Nom » est déjà un profil intégré : choisis un autre nom." }
    $cl = @($Cles | Where-Object { $_ } | Select-Object -Unique)
    if ($cl.Count -eq 0) { throw "Aucune case cochée : rien à enregistrer." }
    $profils = Get-ProfilsPerso
    $profils[$Nom] = $cl
    $f = Join-Path $script:DossierDonnees "profils-perso.json"
    ConvertTo-Json $profils | Set-Content -Path $f -Encoding UTF8
}

# ------------------------------------------------------------------------------
# BUNDLE DE CONFIG PORTABLE — réunit clés appliquées + profils perso + apps dans un
# seul fichier, pour cloner une config d'un PC à l'autre.
# ------------------------------------------------------------------------------
function Export-ConfigBundle {
    param([Parameter(Mandatory)][string]$Chemin)
    $apps = $null
    $fApps = Join-Path $script:DossierDonnees "mes-apps.json"
    if (Test-Path $fApps) { try { $apps = Get-Content $fApps -Raw | ConvertFrom-Json } catch { } }
    $bundle = [ordered]@{
        format         = "madtweak-config"
        version        = $script:Version
        date           = (Get-Date -Format 's')
        machine        = $env:COMPUTERNAME
        clesAppliquees = @(Get-ClesAppliquees)
        profilsPerso   = (Get-ProfilsPerso)
        apps           = $apps
    }
    ConvertTo-Json $bundle -Depth 8 | Set-Content -Path $Chemin -Encoding UTF8
    return $Chemin
}

function Import-ConfigBundle {
    # Fusionne un bundle dans la config locale. Renvoie un résumé.
    param([Parameter(Mandatory)][string]$Chemin)
    if (-not (Test-Path $Chemin)) { throw "Fichier introuvable : $Chemin" }
    $b = Get-Content $Chemin -Raw | ConvertFrom-Json
    if ($b.format -ne 'madtweak-config') { throw "Ce fichier n'est pas un bundle de config MadTweak." }
    $nbProfils = 0
    if ($b.profilsPerso) {
        foreach ($p in $b.profilsPerso.PSObject.Properties) {
            try { Save-ProfilPerso -Nom $p.Name -Cles @($p.Value); $nbProfils++ } catch { }
        }
    }
    $cles = @($b.clesAppliquees | Where-Object { $_ })
    if ($cles.Count -gt 0) { Save-ClesAppliquees $cles }
    $aApps = $false
    if ($b.apps) {
        try { ConvertTo-Json $b.apps -Depth 10 | Set-Content -Path (Join-Path $script:DossierDonnees "mes-apps.json") -Encoding UTF8; $aApps = $true } catch { }
    }
    return @{ Cles = $cles; NbProfils = $nbProfils; Apps = $aApps }
}

# ------------------------------------------------------------------------------
# MAINTENANCE PLANIFIÉE — tâche hebdomadaire de nettoyage léger et SÛR.
# ------------------------------------------------------------------------------
function Invoke-MaintenanceSilencieuse {
    # Nettoyage léger, sûr et NON interactif (pour la tâche planifiée). Pas de DISM
    # (trop lourd pour de l'hebdo), rien de risqué : temporaires vieux d'un jour + corbeille.
    $cibles = @("$env:TEMP", "$env:SystemRoot\Temp", "$env:SystemRoot\SoftwareDistribution\Download")
    $n = 0
    foreach ($c in $cibles) {
        if (-not (Test-Path $c)) { continue }
        Get-ChildItem -Path $c -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -lt (Get-Date).AddDays(-1) } |
            ForEach-Object { try { Remove-Item $_.FullName -Force -ErrorAction Stop; $n++ } catch { } }
    }
    try { Clear-RecycleBin -Force -ErrorAction SilentlyContinue } catch { }
    return $n
}

function Test-MaintenanceHebdo {
    return [bool](Get-ScheduledTask -TaskName "MadTweak-Maintenance" -ErrorAction SilentlyContinue)
}

function Register-MaintenanceHebdo {
    # Planifie une tâche hebdomadaire (dimanche midi) qui relance CE script en mode
    # -Maintenance, en SYSTEM. Exige les droits admin (la GUI les a).
    $cible = if ($PSCommandPath -and (Test-Path $PSCommandPath)) { $PSCommandPath } else { $null }
    if (-not $cible) { throw "Chemin du script introuvable (collé en console ?) : planification impossible." }
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$cible`" -Maintenance"
    $trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At ([datetime]"12:00")
    $principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
    Register-ScheduledTask -TaskName "MadTweak-Maintenance" -Description "MadTweak : nettoyage hebdomadaire léger." -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
}

function Unregister-MaintenanceHebdo {
    Unregister-ScheduledTask -TaskName "MadTweak-Maintenance" -Confirm:$false -ErrorAction SilentlyContinue
}

function Test-ClesProfils {
    # Un profil qui référence une clé inexistante échoue en SILENCE : le tweak ne se
    # déclenche jamais et rien ne le signale. Ce contrôle compare les clés déclarées
    # dans les profils à celles réellement portées par un Invoke-Tweak du fichier.
    # Il tourne au démarrage : une faute de frappe se voit tout de suite, pas six
    # mois plus tard en se demandant pourquoi un profil « ne fait pas tout ».
    $source = Get-Content -Path $PSCommandPath -Raw -ErrorAction SilentlyContinue
    if (-not $source) { return }   # script collé dans une console : rien à vérifier
    $reelles = [regex]::Matches($source, '-Cle\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
    $orphelines = @()
    foreach ($nom in $script:Profils.Keys) {
        foreach ($c in $script:Profils[$nom].Cles) {
            if ($c -notin $reelles) { $orphelines += "$nom -> $c" }
        }
    }
    if ($orphelines.Count -gt 0) {
        Write-Etat "INCOHÉRENCE : $($orphelines.Count) clé(s) de profil ne correspondent à aucun tweak :" -Niveau Echec
        foreach ($o in $orphelines) { Write-Ligne "        - $o" -Couleur Red }
    }
}

function Invoke-TousLesMenus {
    # UN SEUL endroit décide des menus traversés « sans interaction ». Invoke-Profil
    # ET l'inventaire de l'interface graphique passent par ici.
    # Tous les menus supportent désormais Test-SansInteraction pour fonctionner de façon non-interactive.
    Menu-Tweaks-Base
    Menu-Tweaks-Avances
    Menu-Explorateur-Prive
    Menu-Materiel-Cpu
    Menu-Maj-Securite
    Menu-Logiciels-Extra
    Menu-Maintenance
    Menu-Nettoyage
    # Ces deux-là ne vivent dans aucun menu : il faut nommer leur catégorie à la main.
    $script:CategorieCourante = "SÉCURITÉ & IA"
    Invoke-TweakCopilot
    Invoke-TweakRecall
    Menu-Windows11-Recent
    Menu-Visuel
    Menu-Demarrage
}

function Test-Explications {
    # Quatrième filet, même esprit que les trois autres : un tweak pilotable sans
    # explication apparaîtrait dans l'interface comme une case à cocher NUE, et
    # l'utilisateur devrait deviner ce qu'elle fait. C'est précisément ce qu'on
    # cherche à supprimer -- autant que l'oubli se voie au démarrage plutôt qu'en
    # production, six mois plus tard.
    $sans = @(Get-Inventaire | Where-Object { -not $_.Explication })
    if ($sans.Count -eq 0) { return }
    # Write-Ligne et non Write-Host : ces lignes doivent suivre le même chemin que
    # le reste, sinon elles disparaîtraient du journal de l'interface graphique.
    Write-Etat "INCOHÉRENCE : $($sans.Count) tweak(s) pilotable(s) n'ont aucune explication :" -Niveau Echec
    foreach ($t in $sans) { Write-Ligne "        - $($t.Cle)" -Couleur Red }
}

$script:InventaireCache = $null
function Get-Inventaire {
    # Recense les tweaks pilotables SANS en exécuter aucun : c'est ce qui peuple
    # les cases de l'interface. La liste vient du code, jamais d'une copie.
    #
    # Mise en cache : l'inventaire est appelé plusieurs fois au démarrage (le filet
    # Test-Explications, puis la construction de l'interface). Le catalogue ne change
    # pas au sein d'une session, donc on ne parcourt les menus qu'UNE fois.
    if ($null -ne $script:InventaireCache) { return $script:InventaireCache }
    $script:Inventaire = @()
    $script:ModeInventaire = $true
    try { Invoke-TousLesMenus }
    finally { $script:ModeInventaire = $false }
    $script:InventaireCache = $script:Inventaire
    return $script:InventaireCache
}

function ConvertTo-CleComparable {
    # Réduit un texte à sa forme la plus robuste : sans accent, sans ponctuation,
    # sans espace, en minuscules. « Minimal / sûr » devient « minimalsur ».
    param([Parameter(Mandatory)][string]$Texte)
    $decompose = $Texte.Normalize([Text.NormalizationForm]::FormD)
    $sb = New-Object System.Text.StringBuilder
    foreach ($c in $decompose.ToCharArray()) {
        # Un caractère accentué décomposé = la lettre nue + un signe diacritique
        # « sans chasse ». On garde la lettre, on jette le signe.
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($c) -ne [Globalization.UnicodeCategory]::NonSpacingMark) {
            [void]$sb.Append($c)
        }
    }
    return ($sb.ToString() -replace '[^a-zA-Z0-9]', '').ToLowerInvariant()
}

function Resolve-NomProfil {
    # Retrouve le nom EXACT d'un profil à partir d'une écriture approchante.
    #
    # Les noms de profils contiennent espaces, barre oblique et accents. Quand le
    # nom arrive d'une ligne de commande -- et surtout du fichier de réponses d'une
    # installation automatisée, où il traverse un XML puis une console dont la page
    # de codes n'est pas garantie -- il en revient parfois abîmé. Répondre « profil
    # inconnu » à un nom visiblement juste serait absurde, et sur une machine qu'on
    # vient d'installer, l'échec passerait inaperçu.
    param([Parameter(Mandatory)][string]$Nom)
    # On renvoie toujours la clé TELLE QU'ELLE EST ÉCRITE dans le catalogue, jamais
    # ce qu'a tapé l'appelant : c'est ce nom-là qui sera affiché à l'écran ensuite.
    # La correspondance exacte l'emporte sur toute approximation.
    foreach ($k in $script:Profils.Keys) { if ($k -ceq $Nom) { return $k } }
    $cible = ConvertTo-CleComparable $Nom
    foreach ($k in $script:Profils.Keys) {
        if ((ConvertTo-CleComparable $k) -eq $cible) { return $k }
    }
    return $null
}

function Invoke-Profil {
    param([Parameter(Mandatory)][string]$Nom)
    $profil = $script:Profils[$Nom]

    Clear-Host
    Write-Host "=== PROFIL : $Nom ===" -ForegroundColor $profil.Couleur
    Write-Host ""
    Write-Host "  $($profil.Description)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  $($profil.Cles.Count) tweak(s) seront appliqués SANS te poser de question." -ForegroundColor Yellow
    if ($script:Simulation) {
        Write-Host "  SIMULATION ACTIVE : rien ne sera écrit, tu verras seulement ce qui changerait." -ForegroundColor Cyan
    }
    Write-Host ""
    if (-not (Demander-Option "Appliquer le profil « $Nom » ?")) { return }

    # Le point de restauration est proposé UNE fois ici, et non à chaque menu traversé.
    if (-not $script:Simulation -and -not (Confirmer-Filet-Securite)) { return }

    $script:CompteurOK = 0; $script:CompteurEchec = 0; $script:SimuCompteur = 0
    $script:ClesJouees = @()
    $script:ProfilActif = $profil.Cles
    try {
        # Chaque menu ne joue que les tweaks dont la clé est dans le profil, et
        # ignore les autres en silence. Voir Invoke-TousLesMenus pour la liste
        # et pour les menus volontairement exclus.
        Invoke-TousLesMenus
    }
    finally { $script:ProfilActif = $null }

    # Filet de sécurité : une clé du profil qui n'a été atteinte par AUCUN tweak
    # signifie que le menu qui la porte n'est pas appelé ci-dessus. Le tweak ne
    # s'appliquerait alors jamais, sans le moindre message. Le contrôle de démarrage
    # ne voit pas ce cas : la clé existe bel et bien, elle est juste hors d'atteinte.
    $jamais = @($profil.Cles | Where-Object { $_ -notin $script:ClesJouees })
    if ($jamais.Count -gt 0) {
        Write-Host ""
        Write-Etat "ANOMALIE INTERNE : $($jamais.Count) tweak(s) de ce profil n'ont jamais été atteints :" -Niveau Echec
        foreach ($j in $jamais) { Write-Ligne "        - $j" -Couleur Red }
        Write-Etat "Le menu qui les porte n'est pas appelé par Invoke-Profil. C'est un défaut du script, pas de ta machine." -Niveau Echec
    }

    Write-Host ""
    Write-Host "  ----------------------------------------------------" -ForegroundColor DarkGray
    if ($script:Simulation) {
        Write-Host "  SIMULATION du profil « $Nom » : $script:SimuCompteur modification(s) auraient été faites. Rien n'a été écrit." -ForegroundColor Cyan
        if (-not (Test-SansInteraction)) { Read-Host "`nAppuie sur Entrée pour revenir au menu principal" }
        return
    }
    Write-Host "  Profil « $Nom » : $script:CompteurOK réussi(s), $script:CompteurEchec échec(s)." -ForegroundColor $(if ($script:CompteurEchec -gt 0) { "Yellow" } else { "Green" })
    if ($script:CompteurEchec -gt 0) {
        Write-Etat "Un échec n'est pas forcément un problème : un tweak peut refuser de s'appliquer parce qu'il serait nuisible ici (plan Performances ultimes sur portable, SysMain sur disque dur...)." -Niveau Info
    }
    if ($script:CompteurOK -gt 0 -and (Demander-Option "  Redémarrer l'Explorateur pour appliquer les changements visuels ?")) {
        Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
        Write-Etat "Explorateur redémarré." -Niveau OK
    }
    Show-RedemarrageRequis
    if (-not (Test-SansInteraction)) { Read-Host "`nAppuie sur Entrée pour revenir au menu principal" }
}

function Menu-Profils {
    Clear-Host
    Write-Host "=== PROFILS ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Un profil applique un lot de tweaks cohérents d'un coup, sans question." -ForegroundColor DarkGray
    Write-Host "  Tous restent annulables par le menu ANNULER (restauration exacte)." -ForegroundColor DarkGray
    Write-Host "  Conseil : active la SIMULATION (S au menu principal) pour voir d'abord." -ForegroundColor DarkGray
    Write-Host ""

    $noms = @($script:Profils.Keys)
    for ($i = 0; $i -lt $noms.Count; $i++) {
        $p = $script:Profils[$noms[$i]]
        Write-Host (" {0} - {1}" -f ($i + 1), $noms[$i]) -ForegroundColor $p.Couleur
        Write-Host ("     $($p.Cles.Count) tweaks. $($p.Description)") -ForegroundColor DarkGray
        Write-Host ""
    }
    Write-Host (" {0} - Retour au menu principal" -f ($noms.Count + 1))
    Write-Host ""

    $choix = Read-Host "Choisis un profil (1-$($noms.Count + 1))"
    $n = 0
    if ([int]::TryParse($choix, [ref]$n) -and $n -ge 1 -and $n -le $noms.Count) {
        Invoke-Profil -Nom $noms[$n - 1]
    }
}

