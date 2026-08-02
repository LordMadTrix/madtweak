# ------------------------------------------------------------------------------
# IMAGE SYSTÈME DE RÉFÉRENCE (CHECKPOINT)
#
# Principe : après avoir optimisé une machine, figer un état de référence complet
# (image disque via wbadmin, pas juste un point de restauration registre) pour
# pouvoir y revenir si le système se dégrade plus tard. Contrairement aux tweaks
# habituels, la « restauration » ne peut PAS se faire depuis Windows : elle exige
# de redémarrer sur un environnement de récupération (WinRE) ou une clé USB.
# Certaines installations (notamment depuis une image Windows modifiée/allégée)
# n'ont PAS de partition WinRE -- ce module le détecte et le dit clairement,
# plutôt que de laisser croire qu'un simple redémarrage suffira toujours.
#
# On nettoie et on répare AVANT de figer l'image, pour ne pas y congeler la
# crasse en même temps que l'optimisation -- mais jamais le nettoyage irréversible
# (WinSxS /resetbase) : un checkpoint est le filet de sécurité qu'on veut AVANT
# une action sans retour, pas un endroit où en glisser une par défaut.
# ------------------------------------------------------------------------------

function Get-CibleImageValide {
    # Vérifie qu'un disque peut recevoir l'image AVANT de lancer quoi que ce soit :
    # refuser après 20 minutes de nettoyage/réparation serait bien pire que
    # refuser tout de suite.
    param([Parameter(Mandatory)][string]$LettreCible)

    $lettre = $LettreCible.TrimEnd(':').ToUpperInvariant()
    $systeme = $env:SystemDrive.TrimEnd(':').ToUpperInvariant()

    if ($lettre -eq $systeme) {
        return @{ Valide = $false; Motif = (T 'img.erreur.cible.systeme'); LibreGo = 0; TotalGo = 0; EstimeGo = 0 }
    }

    $vol = Get-Volume -DriveLetter $lettre -ErrorAction SilentlyContinue
    if (-not $vol) {
        return @{ Valide = $false; Motif = ((T 'img.erreur.cible.introuvable') -f $lettre); LibreGo = 0; TotalGo = 0; EstimeGo = 0 }
    }

    $libreGo = [math]::Round($vol.SizeRemaining / 1GB, 1)
    $totalGo = [math]::Round($vol.Size / 1GB, 1)

    # Estimation = espace UTILISÉ sur le disque système (wbadmin copie les blocs
    # occupés, pas les blocs libres), + 15 % de marge pour le journal VSS et les
    # métadonnées. Une estimation, jamais un chiffre exact.
    $disque = Get-AnalyseDisque
    $utiliseGo = [math]::Max(0, $disque.TotalGo - $disque.LibreGo)
    $requisGo = [math]::Round($utiliseGo * 1.15, 1)

    if ($libreGo -lt $requisGo) {
        return @{
            Valide = $false; Motif = ((T 'img.erreur.cible.espace') -f $requisGo, $libreGo)
            LibreGo = $libreGo; TotalGo = $totalGo; EstimeGo = $requisGo
        }
    }

    return @{ Valide = $true; Motif = ""; LibreGo = $libreGo; TotalGo = $totalGo; EstimeGo = $requisGo }
}

function Get-DisquesCiblesPossibles {
    # Disques candidats pour recevoir l'image : tout sauf le disque système.
    # Contrairement à New-CleInstallation (qui DOIT cibler un disque USB, car elle
    # l'efface entièrement), une image système est un usage parfaitement valable
    # sur un disque interne secondaire -- pas de filtre de bus ici.
    $systeme = $env:SystemDrive.TrimEnd(':').ToUpperInvariant()
    $vols = @(Get-Volume -ErrorAction SilentlyContinue | Where-Object {
        $_.DriveLetter -and $_.DriveLetter.ToString().ToUpperInvariant() -ne $systeme -and $_.DriveType -in @('Fixed', 'Removable')
    })
    return @($vols | ForEach-Object {
        $libreGo = [math]::Round($_.SizeRemaining / 1GB, 1)
        $etiquette = if ($_.FileSystemLabel) { " ($($_.FileSystemLabel))" } else { "" }
        [pscustomobject]@{
            Lettre    = "$($_.DriveLetter)"
            Etiquette = "$($_.DriveLetter):$etiquette — $libreGo Go libres"
        }
    })
}

function Test-CapaciteWbadmin {
    # Sonde NON destructive : wbadmin.exe est absent ou bridé sur certaines
    # éditions de Windows (Famille, notamment). Vérifié AVANT de nettoyer/réparer
    # quoi que ce soit -- un échec à la toute dernière étape aurait gâché du temps
    # pour rien. Note : le texte exact renvoyé par wbadmin quand la fonctionnalité
    # est absente n'a pas été vérifié sur toutes les éditions/langues de Windows ;
    # le repli "Inconnu -> on laisse tenter" est volontairement prudent plutôt que
    # de bloquer une machine qui, en réalité, supporte wbadmin.
    if (-not (Get-Command "wbadmin.exe" -ErrorAction SilentlyContinue)) {
        return @{ Disponible = $false; Motif = (T 'img.erreur.wbadmin.absent') }
    }
    $r = Invoke-Externe -Fichier "wbadmin.exe" -Arguments @("get", "versions") -CaptureSortie
    if ($r.CodeSortie -eq -1) {
        return @{ Disponible = $false; Motif = (T 'img.erreur.wbadmin.indisponible') }
    }
    if ($r.Sortie -match '(?i)ne reconnaît pas|is not recognized|not supported|pas pris en charge') {
        return @{ Disponible = $false; Motif = (T 'img.erreur.wbadmin.indisponible') }
    }
    return @{ Disponible = $true; Motif = "" }
}

function Parse-SortieReagentc {
    # Fonction PURE (aucun appel système) : sépare le parsing de l'exécution pour
    # rester testable sans avoir une machine réelle dans chaque état (WinRE actif /
    # désactivé / absent). reagentc.exe n'a pas de sortie structurée -- juste du
    # texte console, en français ou en anglais selon la langue de Windows.
    param([int]$CodeSortie, [string]$Sortie)

    if ($null -eq $Sortie) { $Sortie = "" }

    if ($Sortie -match '(?im)^\s*(État de Windows RE|Windows RE status)\s*:\s*(.+?)\s*$') {
        $valeur = $Matches[2]
        if ($valeur -match '(?i)^(Activ|Enable)') {
            return @{ Statut = 'Active'; Message = (T 'img.winre.active'); SortieBrute = $Sortie }
        }
        if ($valeur -match '(?i)^(Désactiv|Disable)') {
            return @{ Statut = 'Desactivee'; Message = (T 'img.winre.desactivee'); SortieBrute = $Sortie }
        }
    }

    # Pas de ligne de statut reconnaissable : sur une machine sans AUCUNE partition
    # de récupération (ISO modifiée/allégée), reagentc /info échoue plutôt que
    # d'afficher proprement "désactivé" -- un code de sortie non nul est le signal.
    if ($CodeSortie -ne 0) {
        return @{ Statut = 'Absente'; Message = (T 'img.winre.absente'); SortieBrute = $Sortie }
    }

    return @{ Statut = 'Inconnu'; Message = (T 'img.winre.inconnu'); SortieBrute = $Sortie }
}

function Get-StatutWinRE {
    if (-not (Get-Command "reagentc.exe" -ErrorAction SilentlyContinue)) {
        return @{ Statut = 'Absente'; Message = (T 'img.winre.absente'); SortieBrute = "" }
    }
    $r = Invoke-Externe -Fichier "reagentc.exe" -Arguments @("/info") -CaptureSortie
    return Parse-SortieReagentc -CodeSortie $r.CodeSortie -Sortie $r.Sortie
}

function Export-RapportImageSysteme {
    # Même principe qu'Export-RapportAuditPdf (src/70-audit.ps1) : du HTML brut
    # avec @media print, imprimé en PDF par l'utilisateur -- pas un vrai PDF généré
    # ici. Les instructions changent selon la présence de WinRE au moment de la
    # capture : c'est tout l'intérêt de stocker ce statut dans le rapport.
    param(
        [Parameter(Mandatory)][string]$LettreCible,
        [Parameter(Mandatory)]$StatutWinRE,
        [string]$CheminSortie
    )
    if (-not $CheminSortie) { $CheminSortie = Join-Path $script:DossierDonnees "Restauration-Image-MadTweak.html" }

    $winreOk = $StatutWinRE.Statut -eq 'Active'
    $dateJour = Get-Date -Format 'dd/MM/yyyy'
    $instructionsWinRE = if ($winreOk) {
        "<li>Redémarre puis maintiens <b>Maj</b> en cliquant sur Redémarrer, ou va dans Paramètres → Système → Récupération → Démarrage avancé.</li>
    <li>Choisis <b>Dépannage → Options avancées → Récupération de l'image système</b>.</li>
    <li>Sélectionne l'image datée du $dateJour sur le lecteur ${LettreCible}: et suis l'assistant.</li>"
    } else {
        "<li style='color:#ff4444'><b>Aucun environnement de récupération détecté sur cette machine</b> (fréquent sur les installations depuis une image Windows modifiée/allégée) : le redémarrage classique ne proposera pas cette option.</li>
    <li>Utilise une <b>clé de récupération</b> créée via l'outil Windows « Créer un lecteur de récupération » (recoverydrive.exe). Démarre l'ordinateur dessus (touche de démarrage du constructeur, ex. F12/Échap/Suppr selon la marque).</li>
    <li>Une fois démarré sur la clé : <b>Dépannage → Options avancées → Invite de commandes</b>, puis tape :<br><code>wbadmin start sysrecovery</code> (liste les images disponibles avant de choisir).</li>"
    }

    $html = @"
<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8"/>
<title>Restauration Image Système — MadTweak</title>
<style>
  body { font-family: 'Segoe UI', Arial, sans-serif; margin: 40px; background: #0f121a; color: #e0e6ed; }
  h1 { color: #e20018; border-bottom: 2px solid #e20018; padding-bottom: 10px; }
  h2 { color: #00f0ff; margin-top: 30px; }
  .info { background: #151821; border: 1px solid #232838; border-radius: 6px; padding: 16px; margin: 16px 0; }
  li { margin-bottom: 10px; line-height: 1.5; }
  code { background: #232838; padding: 2px 6px; border-radius: 3px; }
  @media print { body { background: #fff; color: #000; } h1, h2 { color: #000; } .info { background: #f5f5f5; } code { background: #eee; } }
</style>
</head>
<body>
  <h1>Instructions de restauration — Image système MadTweak</h1>
  <div class="info">
    <p><b>Capturée le :</b> $(Get-Date -Format 'dd/MM/yyyy HH:mm')</p>
    <p><b>Disque cible :</b> ${LettreCible}:</p>
    <p><b>Machine :</b> $env:COMPUTERNAME</p>
    <p><b>Environnement de récupération (WinRE) au moment de la capture :</b> $($StatutWinRE.Message)</p>
  </div>
  <h2>Comment restaurer</h2>
  <ol>
    $instructionsWinRE
  </ol>
  <h2>Pour les avancés</h2>
  <p>Depuis une invite de commandes en environnement de récupération, <code>wbadmin start sysrecovery</code> liste les images disponibles avant de choisir une version précise.</p>
  <p><b>Conserve ce document</b> : imprime-le (Ctrl+P) ou range-le ailleurs que sur le disque système.</p>
</body>
</html>
"@

    [System.IO.File]::WriteAllText($CheminSortie, $html, [System.Text.Encoding]::UTF8)
    Write-Etat ((T 'img.rapport.ok') -f $CheminSortie) -Niveau OK
    return $CheminSortie
}

function New-ImageSystemeReference {
    <#
        Orchestrateur du checkpoint « Image système de référence » : vérifications,
        nettoyage, réparation, PUIS capture d'image complète via wbadmin, PUIS
        génération d'une fiche de restauration. Chaque étape est journalisée dans
        Etapes même en cas d'échec -- même esprit que Repair-SystemeIntegral : on
        continue et on note, plutôt que d'interrompre tout à la première anicroche
        (sauf pour les deux garde-fous de tout début, qui eux arrêtent net).
    #>
    param(
        [Parameter(Mandatory)][string]$LettreCible,
        [switch]$NettoyagePrealable = $true,
        [switch]$SansReparation,
        [switch]$Confirme
    )

    if (-not $Confirme) {
        throw "New-ImageSystemeReference modifie le disque cible et lance une capture longue : appelle-la avec -Confirme."
    }

    $depart = Get-Date
    $etapes = New-Object System.Collections.Generic.List[hashtable]

    $capacite = Test-CapaciteWbadmin
    $etapes.Add(@{ Nom = "Vérification wbadmin"; Succes = $capacite.Disponible; Message = $capacite.Motif })
    if (-not $capacite.Disponible) {
        Write-Etat $capacite.Motif -Niveau Echec
        return @{ Succes = $false; CheminRapport = $null; StatutWinRE = $null; DureeSecondes = 0; Etapes = $etapes }
    }

    $cible = Get-CibleImageValide -LettreCible $LettreCible
    $etapes.Add(@{ Nom = "Vérification du disque cible"; Succes = $cible.Valide; Message = $cible.Motif })
    if (-not $cible.Valide) {
        Write-Etat $cible.Motif -Niveau Echec
        return @{ Succes = $false; CheminRapport = $null; StatutWinRE = $null; DureeSecondes = 0; Etapes = $etapes }
    }

    if ($NettoyagePrealable) {
        # Sous-ensemble volontairement sûr de Get-CiblesNettoyage : jamais
        # Windows.old ni le /resetbase irréversible, jamais par défaut ici.
        $nomsCibles = @(
            "Fichiers temporaires (ton compte)",
            "Fichiers temporaires (Windows)",
            "Cache de Windows Update",
            "Rapports d'erreurs Windows",
            "Cache de Delivery Optimization",
            "Cache des miniatures"
        )
        $toutesLesCibles = Get-CiblesNettoyage
        foreach ($nom in $nomsCibles) {
            try {
                $c = $toutesLesCibles[$nom]
                $r = Clear-Contenu -Chemin $c.Chemin
                Write-Etat "$nom : $($r.Supprimes) supprimé(s), $($r.Resistants) verrouillé(s)." -Niveau Info
                $etapes.Add(@{ Nom = $nom; Succes = $true; Message = "$($r.Supprimes) supprimé(s)" })
            } catch {
                $etapes.Add(@{ Nom = $nom; Succes = $false; Message = $_.Exception.Message })
            }
        }
    }

    if (-not $SansReparation) {
        try {
            Repair-SystemeIntegral | Out-Null
            $etapes.Add(@{ Nom = "Réparation système (DISM/SFC)"; Succes = $true; Message = "" })
        } catch {
            $etapes.Add(@{ Nom = "Réparation système (DISM/SFC)"; Succes = $false; Message = $_.Exception.Message })
        }
        try {
            Optimize-LecteursStockageSsd | Out-Null
            $etapes.Add(@{ Nom = "Optimisation SSD/TRIM"; Succes = $true; Message = "" })
        } catch {
            $etapes.Add(@{ Nom = "Optimisation SSD/TRIM"; Succes = $false; Message = $_.Exception.Message })
        }
    }

    $statutWinRE = Get-StatutWinRE
    $etapes.Add(@{ Nom = "Statut WinRE"; Succes = $true; Message = $statutWinRE.Message })

    $lettre = $LettreCible.TrimEnd(':').ToUpperInvariant()
    $succesCapture = $true
    $messageCapture = ""
    try {
        Write-Etat "Capture de l'image système vers ${lettre}: — cela peut prendre 20 à 60+ minutes." -Niveau Info
        Invoke-Externe -Fichier "wbadmin.exe" -Arguments @(
            "start", "backup",
            "-backupTarget:${lettre}:",
            "-include:$env:SystemDrive",
            "-allCritical",
            "-quiet"
        ) -CodesOK @(0)
        Write-Etat "Image système capturée avec succès." -Niveau OK
    } catch {
        $succesCapture = $false
        $messageCapture = $_.Exception.Message
        Write-Etat "Échec de la capture d'image : $messageCapture" -Niveau Echec
    }
    $etapes.Add(@{ Nom = "Capture wbadmin"; Succes = $succesCapture; Message = $messageCapture })

    $cheminRapport = $null
    try {
        $cheminRapport = Export-RapportImageSysteme -LettreCible $lettre -StatutWinRE $statutWinRE
        $etapes.Add(@{ Nom = "Fiche de restauration"; Succes = $true; Message = $cheminRapport })
    } catch {
        $etapes.Add(@{ Nom = "Fiche de restauration"; Succes = $false; Message = $_.Exception.Message })
    }

    $duree = [int]((Get-Date) - $depart).TotalSeconds
    return @{
        Succes        = $succesCapture
        CheminRapport = $cheminRapport
        StatutWinRE   = $statutWinRE
        DureeSecondes = $duree
        Etapes        = $etapes
    }
}
