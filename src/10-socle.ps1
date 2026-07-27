# ------------------------------------------------------------------------------
# SOCLE : affichage, questions, écriture registre, exécution sécurisée
# ------------------------------------------------------------------------------

# Quand l'interface graphique est active, elle place ici un scriptblock qui reçoit
# (message, niveau). Toute la sortie du script passe alors dans son panneau de log
# au lieu d'une console que personne ne regarde. $null = mode console normal.
# C'est le SEUL point de bascule : aucun tweak n'a besoin de savoir qui l'affiche.
$script:SortieGui = $null

function Write-Etat {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("Info", "OK", "Echec", "Avert")][string]$Niveau = "Info"
    )
    if ($script:SortieGui) { & $script:SortieGui $Message $Niveau; return }
    $couleur = switch ($Niveau) { "OK" { "Green" } "Echec" { "Red" } "Avert" { "Yellow" } default { "Gray" } }
    $prefixe = switch ($Niveau) { "OK" { "  [OK]    " } "Echec" { "  [ÉCHEC] " } "Avert" { "  [!]     " } default { "  [..]    " } }
    Write-Host "$prefixe$Message" -ForegroundColor $couleur
}

function Write-Ligne {
    # Ligne libre, sans préfixe d'état : titres de tweak sous profil, séparateurs.
    param([Parameter(Mandatory)][string]$Message, [string]$Couleur = "Gray")
    if ($script:SortieGui) { & $script:SortieGui $Message "Titre"; return }
    Write-Host $Message -ForegroundColor $Couleur
}

function Write-Explication {
    # Une explication est un paragraphe, pas une étiquette : sans repli, elle sortirait
    # en une seule ligne illisible qui déborde de la console. On se cale sur la largeur
    # réelle de la fenêtre, en retombant sur 100 si elle est indisponible (script
    # redirigé, tâche planifiée, console sans hôte).
    param([Parameter(Mandatory)][string]$Texte)
    $largeur = 100
    try { if ($Host.UI.RawUI.WindowSize.Width -gt 20) { $largeur = [Math]::Min($Host.UI.RawUI.WindowSize.Width - 6, 110) } } catch { }

    $ligne = ""
    foreach ($mot in ($Texte -split '\s+')) {
        if ($ligne.Length -eq 0) { $ligne = $mot }
        elseif (($ligne.Length + 1 + $mot.Length) -le $largeur) { $ligne += " $mot" }
        else { Write-Host "     $ligne" -ForegroundColor DarkGray; $ligne = $mot }
    }
    if ($ligne) { Write-Host "     $ligne" -ForegroundColor DarkGray }
}

function Demander-Option {
    param([Parameter(Mandatory)][string]$Message)
    # Mode sans question, posé par -Profil : le script tourne alors à la première
    # ouverture de session d'une installation automatisée, où PERSONNE n'a demandé
    # à répondre à quoi que ce soit. Un Read-Host y serait une impasse silencieuse.
    if ($script:SansQuestion) { return $true }
    $Reponse = Read-Host "$Message (O/N)"
    return ($Reponse -match '^\s*(o|oui|y|yes)\s*$')
}

# Détection de l'édition et de la version : plusieurs tweaks n'ont AUCUN effet
# sur Windows Famille, et il vaut mieux le dire que d'écrire dans le vide.
$script:InfosOS = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
$script:EstFamille = $script:InfosOS.EditionID -in @("Core", "CoreN", "CoreSingleLanguage", "CoreCountrySpecific")
$script:BuildOS = [int]$script:InfosOS.CurrentBuild

function Test-NPU {
    # Détection des PC Copilot+. ATTENTION : une première version de ce script
    # cherchait 'NPU' dans le nom des périphériques -- ce qui matchait joyeusement
    # "Microsoft I-N-P-U-t Configuration Device" et annonçait un NPU inexistant.
    # D'où les délimiteurs de mot et le test sur la classe de périphérique.
    $npu = Get-CimInstance Win32_PnPEntity -ErrorAction SilentlyContinue | Where-Object {
        $_.PNPClass -eq 'ComputeAccelerator' -or $_.Name -match 'AI Boost|Neural Processing|\bNPU\b'
    }
    return [bool]$npu
}

function Get-TachesTelemetrie {
    # Les noms de ces tâches ne sont PAS stables d'une version de Windows à l'autre.
    # Mesuré sur 25H2 (build 26200) : « Microsoft Compatibility Appraiser » s'appelle
    # désormais « Microsoft Compatibility Appraiser Exp », et ProgramDataUpdater a
    # purement disparu du dossier Application Experience. Cibler des noms EXACTS,
    # comme le faisait ce script, revenait donc à rater la tâche de collecte la plus
    # importante sur les builds récents -- tout en annonçant un succès, puisque les
    # trois autres, elles, répondaient.
    # On résout donc par MOTIF, à l'exécution, et un seul endroit décide de la liste :
    # le tweak, son annulation et l'audit appellent tous cette fonction.
    $cibles = @(
        @{ Chemin = "\Microsoft\Windows\Application Experience\"; Motif = "Microsoft Compatibility Appraiser*" }
        @{ Chemin = "\Microsoft\Windows\Application Experience\"; Motif = "ProgramDataUpdater" }
        @{ Chemin = "\Microsoft\Windows\Customer Experience Improvement Program\"; Motif = "Consolidator" }
        @{ Chemin = "\Microsoft\Windows\Customer Experience Improvement Program\"; Motif = "UsbCeip" }
        @{ Chemin = "\Microsoft\Windows\Autochk\"; Motif = "Proxy" }
    )
    $trouvees = @()
    foreach ($c in $cibles) {
        $trouvees += @(Get-ScheduledTask -TaskPath $c.Chemin -ErrorAction SilentlyContinue |
            Where-Object { $_.TaskName -like $c.Motif })
    }
    return $trouvees
}

function Get-PlanAlimentationActif {
    try {
        $s = (powercfg /getactivescheme | Out-String)
        if ($s -match '\(([^)]+)\)') { return $Matches[1] }
    }
    catch { }
    return "inconnu"
}

function Assert-EditionPro {
    # À appeler dans un tweak qui repose sur une stratégie réservée à Pro/Entreprise.
    param([Parameter(Mandatory)][string]$Fonction)
    if ($script:EstFamille) {
        throw "$Fonction n'est pas honoré par Windows Famille (édition $($script:InfosOS.EditionID)) : cette stratégie est réservée aux éditions Pro/Entreprise. Rien n'a été écrit."
    }
}

