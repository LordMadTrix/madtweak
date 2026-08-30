# ------------------------------------------------------------------------------
# MODE SIMULATION
# Règle du jeu : AUCUNE modification du système ne doit exister ailleurs que
# derrière un de ces points de passage. Le registre passe par Set-RegValue /
# Remove-RegValue / Remove-RegKey, les .exe par Invoke-Externe, et tout le reste
# (services, apps, tâches planifiées, winget...) par Invoke-Action.
# Si une action contourne ces quatre portes, la simulation ferait de vrais dégâts.
# ------------------------------------------------------------------------------
# La simulation peut être demandée AVANT le chargement des modules, par une suite
# de tests ou un appel programmatique. Deux précautions pour que cette demande
# survive : on n'écrase pas une valeur déjà posée, et on accepte un drapeau global.
#
# Sans cela, charger ce module remettait systématiquement la simulation à faux —
# et une suite de tests qui l'avait activée nettoyait la machine pour de bon.
if ($global:Simulation) { $script:Simulation = $true }
elseif ($null -eq $script:Simulation) { $script:Simulation = $false }
$script:SimuCompteur = 0

function Write-Simu {
    param([Parameter(Mandatory)][string]$Message)
    # Le compteur s'incrémente dans les DEUX cas : c'est lui qui alimente le bilan
    # « n modifications auraient été faites », en console comme dans l'interface.
    if ($script:SortieGui) { & $script:SortieGui $Message "Simu" }
    else { Write-Host "  [SIMU]  $Message" -ForegroundColor Cyan }
    $script:SimuCompteur++
}

function Get-ValeurLisible {
    param($Valeur)
    if ($null -eq $Valeur) { return "(absente)" }
    if ($Valeur -is [byte[]]) { return "(binaire : $(($Valeur | ForEach-Object { '{0:X2}' -f $_ }) -join ' '))" }
    return "$Valeur"
}

function Get-ValeurActuelle {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $i = Get-Item -Path $Path
        if ($Name -in $i.GetValueNames()) { return $i.GetValue($Name) }
    }
    catch { }
    return $null
}

function Invoke-Action {
    # Passage obligé de toute action NON-registre qui modifie la machine.
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if ($script:Simulation) { Write-Simu $Description; return }
    & $Action
}

function Set-ServiceEtat {
    param(
        [Parameter(Mandatory)][string]$Nom,
        [ValidateSet("Automatic", "Manual", "Disabled")][string]$Demarrage,
        [switch]$Arreter,
        [switch]$Demarrer
    )
    $svc = Get-Service -Name $Nom -ErrorAction SilentlyContinue
    if (-not $svc) { throw "Service '$Nom' introuvable sur cette machine." }
    if ($script:Simulation) {
        Write-Simu "service $Nom : démarrage $($svc.StartType) -> $Demarrage$(if ($Arreter) { ', et serait arrêté' })$(if ($Demarrer) { ', et serait démarré' })"
        return
    }
    Save-EtatService -Nom $Nom
    if ($Arreter) { Stop-Service -Name $Nom -Force -ErrorAction SilentlyContinue }
    if ($Demarrage) { Set-Service -Name $Nom -StartupType $Demarrage }
    if ($Demarrer) { Start-Service -Name $Nom -ErrorAction SilentlyContinue }
}

function Set-RegValue {
    # Crée la clé si elle n'existe pas : c'est ce qui manquait dans la V3 et qui
    # faisait échouer silencieusement les tweaks VBS, Windows Update et USB.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Microsoft.Win32.RegistryValueKind]$Type = 'DWord'
    )
    if ($script:Simulation) {
        $avant = Get-ValeurLisible (Get-ValeurActuelle -Path $Path -Name $Name)
        $apres = Get-ValeurLisible $Value
        if ($avant -eq $apres) { Write-Simu "$Path\$Name : déjà à $apres, rien à changer" }
        else { Write-Simu "$Path\$Name : $avant  ->  $apres" }
        return
    }
    Save-EtatAvant -Path $Path -Name $Name
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    if ($Name -eq "(default)" -or $Name -eq "") {
        Set-Item -Path $Path -Value $Value -Force
    } else {
        Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force
    }
}

function Remove-RegValue {
    # Supprime une valeur pour revenir au comportement par défaut de Windows.
    # Une valeur absente n'est PAS une erreur : c'est déjà l'état voulu.
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name
    )
    if ($script:Simulation) {
        $avant = Get-ValeurActuelle -Path $Path -Name $Name
        if ($null -eq $avant) { Write-Simu "$Path\$Name : déjà absente, rien à supprimer" }
        else { Write-Simu "$Path\$Name : $(Get-ValeurLisible $avant)  ->  (supprimée)" }
        return
    }
    Save-EtatAvant -Path $Path -Name $Name
    if (Test-Path $Path) { Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue }
}

function Remove-RegKey {
    param([Parameter(Mandatory)][string]$Path)
    if ($script:Simulation) {
        Write-Simu "clé $Path : $(if (Test-Path $Path) { 'serait SUPPRIMÉE avec son contenu' } else { 'déjà absente' })"
        return
    }
    # L'export vient AVANT la suppression, et lève si elle échoue : on ne détruit
    # jamais une arborescence qu'on serait incapable de reconstruire.
    Save-EtatCle -Path $Path
    if (Test-Path $Path) { Remove-Item -Path $Path -Recurse -Force }
}

function Save-EtatService {
    # Comble le trou signalé : la sauvegarde JSON ne couvrait que le registre,
    # donc "Restauration exacte" ignorait les services qu'on avait désactivés.
    param([Parameter(Mandatory)][string]$Nom)
    if (-not $script:SauvegardeActive) { return }
    $cle = "SERVICE|$Nom"
    if ($script:Sauvegarde.ContainsKey($cle)) { return }
    $svc = Get-Service -Name $Nom -ErrorAction SilentlyContinue
    if (-not $svc) { return }
    $script:Sauvegarde[$cle] = [ordered]@{
        Type = "Service"; Nom = $Nom
        Demarrage = "$($svc.StartType)"; Etat = "$($svc.Status)"
    }
    Write-Sauvegarde
}

# Liste des clés à appliquer sans poser de question ($null = mode interactif).
# C'est ce qui permet aux PROFILS de réutiliser exactement les mêmes tweaks que
# les menus, sans dupliquer une seule ligne : les menus SONT le catalogue.
$script:ProfilActif = $null
$script:RedemarrageRequis = @()
# Clés réellement ATTEINTES pendant un profil. Sans ce relevé, un tweak dont le
# menu n'est pas appelé par Invoke-Profil ne s'appliquerait jamais, en silence :
# la clé existe, le contrôle de démarrage la valide, et pourtant rien ne se passe.
# C'est arrivé pour de vrai. Invoke-Profil compare cette liste à celle du profil.
$script:ClesJouees = @()

# MODE INVENTAIRE : recenser les tweaks sans en exécuter aucun.
# C'est ce qui permet à l'interface graphique de construire ses cases à cocher à
# partir du CODE lui-même plutôt que d'une liste tenue en parallèle. Une liste
# parallèle finirait par diverger en silence -- c'est exactement le problème que
# Test-ClesProfils et Test-CoherenceAudit passent leur temps à rattraper.
$script:ModeInventaire = $false
$script:Inventaire = @()
# Renseignée par Start-Menu : sert de nom d'onglet dans l'interface.
$script:CategorieCourante = "Divers"

function Test-SansInteraction {
    # Vrai quand personne n'est là pour lire l'écran ni répondre à une invite :
    # sous profil (le lot s'applique sans question), en inventaire (on ne fait
    # que recenser), et en mode silencieux (-Profil depuis un fichier de réponses).
    # Dans tous ces cas, ni Clear-Host, ni décor, ni Read-Host.
    #
    # Le troisième cas vient d'une installation réelle : appelé par
    # FirstLogonCommands, le script s'est arrêté sur « Appuie sur Entrée pour
    # revenir au menu principal », derrière l'écran bleu de l'OOBE. Personne ne
    # voyait cette console, donc personne ne pouvait appuyer, et l'installation
    # ne se terminait jamais.
    return ([bool]$script:ProfilActif -or $script:ModeInventaire -or $script:SansQuestion)
}

function Invoke-Tweak {
    # Pose la question, exécute, et dit la VÉRITÉ sur le résultat.
    param(
        [Parameter(Mandatory, Position = 0)][string]$Titre,
        [Parameter(Mandatory, Position = 1)][scriptblock]$Action,
        # Identifiant stable, utilisé par les profils. Un tweak sans clé n'est
        # jamais applicable en profil : c'est volontaire (les plus lourds en sont).
        [string]$Cle,
        # Explication en français simple, destinée à l'utilisateur : ce que le tweak
        # fait, et surtout CE QU'IL COÛTE. Elle doit tenir sans jargon.
        #
        # Elle existe parce que tout le savoir de ce script vivait dans ses
        # commentaires -- que personne n'ouvre jamais. Le code savait que la
        # télémétrie plafonne à 1 sur Famille, que Nagle coûte du débit, que SysMain
        # aide sur disque dur ; l'utilisateur, lui, ne voyait qu'une question de six
        # mots. Un réglage qu'on ne comprend pas est un réglage qu'on applique mal.
        [string]$Explication,
        # Déclare que ce tweak n'a d'effet qu'après un redémarrage.
        [switch]$Redemarrage
    )
    # --- Traduction ---
    # Le français reste écrit EN CLAIR à l'appel : le code se lit sans dictionnaire,
    # et c'est lui le repli. L'anglais vient de la table, retrouvé par la CLÉ du
    # tweak -- ce qui évite de toucher aux 150 appels existants. Une clé sans
    # traduction affiche donc le français, plutôt que du vide.
    if ($Cle -and $script:LangueActive -ne 'fr') {
        $tr = $script:TextesTweaks["$Cle.t"]
        if ($tr) { $Titre = $tr }
        $ex = $script:TextesTweaks["$Cle.e"]
        if ($ex) { $Explication = $ex }
    }

    # L'inventaire passe AVANT tout le reste : on recense et on sort, sans jamais
    # toucher à la machine ni poser de question.
    if ($script:ModeInventaire) {
        # Un tweak sans clé n'est pas pilotable depuis l'interface : c'est délibéré
        # (ce sont les lourds et les irréversibles). Il reste accessible en console.
        if ($Cle) {
            $script:Inventaire += [pscustomobject]@{
                Cle         = $Cle
                Titre       = $Titre
                Explication = $Explication
                Redemarrage = [bool]$Redemarrage
                Categorie   = $script:CategorieCourante
                # Le CORPS du tweak, gardé tel quel. C'est lui qu'Export-ScriptAutonome
                # recopie dans le script généré. Sans ce champ, l'export interrogeait un
                # catalogue qui n'existait nulle part et rendait un fichier vide.
                Action      = $Action
            }
        }
        return
    }

    if ($script:ProfilActif) {
        if (-not $Cle -or $Cle -notin $script:ProfilActif) { return }
        $script:ClesJouees += $Cle
        Write-Ligne "  --- $Titre" -Couleur White
    }
    else {
        # En console, l'explication précède la question : la lire APRÈS avoir
        # répondu ne servirait à rien.
        if ($Explication) { Write-Explication $Explication }
        if (-not (Demander-Option $Titre)) { return }
    }

    try {
        if ($script:Simulation) {
            # En mode profil (ou interface), le titre a DÉJÀ été affiché par la
            # branche ci-dessus, et de façon routée. Le réafficher ici avec un
            # Write-Host brut le doublait et, pire, l'envoyait dans la console cachée
            # derrière l'interface. On ne l'affiche donc que hors profil, et via
            # Write-Ligne pour qu'il suive le bon canal.
            if (-not $script:ProfilActif) { Write-Ligne "  --- $Titre" -Couleur White }
            $avant = $script:SimuCompteur
            & $Action
            if ($script:SimuCompteur -eq $avant) { Write-Simu "(ce tweak n'aurait rien modifié)" }
            return
        }
        & $Action
        Write-Etat $Titre -Niveau OK
        $script:CompteurOK++
        # On ne signale un redémarrage que si le tweak a VRAIMENT réussi.
        if ($Redemarrage -and $Titre -notin $script:RedemarrageRequis) {
            $script:RedemarrageRequis += $Titre
        }
    }
    catch {
        Write-Etat "$Titre`n           -> $($_.Exception.Message)" -Niveau Echec
        $script:CompteurEchec++
    }
}

function Invoke-Externe {
    # Les .exe ne lèvent pas d'exception : on vérifie le code de sortie à la main.
    param(
        [Parameter(Mandatory)][string]$Fichier,
        [string[]]$Arguments = @(),
        [int[]]$CodesOK = @(0),
        # CaptureSortie : pour les commandes qu'on interroge (reagentc /info, wbadmin
        # get versions...) plutôt que celles qui modifient la machine -- celles-là
        # doivent quand même s'exécuter EN SIMULATION (on ne modifie rien en lisant
        # un statut), donc ce chemin ignore $script:Simulation volontairement.
        [switch]$CaptureSortie
    )
    if ($CaptureSortie) {
        try {
            $sortie = & $Fichier @Arguments 2>&1 | Out-String
        } catch {
            return [pscustomobject]@{ CodeSortie = -1; Sortie = ""; Erreur = $_.Exception.Message }
        }
        return [pscustomobject]@{ CodeSortie = $LASTEXITCODE; Sortie = $sortie; Erreur = $null }
    }
    if ($script:Simulation) {
        Write-Simu "commande : $([System.IO.Path]::GetFileName($Fichier)) $($Arguments -join ' ')"
        return
    }
    $p = Start-Process -FilePath $Fichier -ArgumentList $Arguments -Wait -NoNewWindow -PassThru
    if ($p.ExitCode -notin $CodesOK) {
        throw "$([System.IO.Path]::GetFileName($Fichier)) a renvoyé le code d'erreur $($p.ExitCode)."
    }
}

function Start-Menu {
    # Pendant qu'un menu ouvert à la main veut un écran propre et ses compteurs à
    # zéro, un profil enchaîne PLUSIEURS menus d'affilée : un Clear-Host y effacerait
    # le bilan des précédents, et remettre les compteurs à zéro à chaque menu rendrait
    # le bilan global du profil faux. Sous profil, on ne fait donc ni l'un ni l'autre.
    param(
        [Parameter(Mandatory)][string]$Titre,
        [string]$Couleur = "Cyan",
        [string[]]$SousTitre = @()
    )
    # Renseigné AVANT toute sortie anticipée : c'est ce titre qui nomme l'onglet
    # de l'interface graphique, et l'inventaire s'arrête justement ici.
    $script:CategorieCourante = $Titre
    if (Test-SansInteraction) { return }
    Clear-Host
    # La CLÉ reste $Titre (français) : elle nomme la catégorie de l'inventaire et
    # l'onglet de l'interface. Seul le libellé AFFICHÉ suit la langue courante.
    Write-Host "=== $(Get-TitreMenu $Titre) ===" -ForegroundColor $Couleur
    foreach ($l in $SousTitre) { Write-Host "  $l" -ForegroundColor DarkGray }
    if ($SousTitre.Count -gt 0) { Write-Host "" }
    $script:CompteurOK = 0; $script:CompteurEchec = 0
}

function Fin-De-Menu {
    param([switch]$RedemarrerExplorateur)
    # Un profil traverse plusieurs menus avec des compteurs qui CUMULENT : afficher
    # un « bilan » à la sortie de chacun donnerait une série de totaux intermédiaires
    # que le lecteur prendrait pour des bilans de menu. Le profil affiche le sien,
    # une fois, à la fin. En inventaire, il n'y a même rien à raconter.
    if (Test-SansInteraction) { return }
    Write-Host ""
    Write-Host "  ----------------------------------------------------" -ForegroundColor DarkGray
    if ($script:Simulation) {
        Write-Host "  SIMULATION : $script:SimuCompteur modification(s) auraient été faites. Rien n'a été écrit." -ForegroundColor Cyan
        if (-not (Test-SansInteraction)) { Read-Host "`nAppuie sur Entrée pour revenir au menu principal" }
        return
    }
    Write-Host "  Bilan : $script:CompteurOK réussi(s), $script:CompteurEchec échec(s)." -ForegroundColor $(if ($script:CompteurEchec -gt 0) { "Yellow" } else { "Green" })
    if ($RedemarrerExplorateur -and $script:CompteurOK -gt 0) {
        if (Demander-Option "  Redémarrer l'Explorateur pour appliquer les changements visuels ?") {
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process explorer.exe }
            Write-Etat "Explorateur redémarré." -Niveau OK
        }
    }
    Show-RedemarrageRequis
    if (-not (Test-SansInteraction)) { Read-Host "`nAppuie sur Entrée pour revenir au menu principal" }
}

function Show-RedemarrageRequis {
    # Plusieurs tweaks n'ont d'effet qu'après un redémarrage. Le script le savait
    # tweak par tweak mais ne le cumulait nulle part : à toi de t'en souvenir.
    if ($script:RedemarrageRequis.Count -eq 0) { return }
    Write-Host ""
    Write-Etat "$($script:RedemarrageRequis.Count) tweak(s) n'auront d'effet qu'APRÈS un redémarrage :" -Niveau Avert
    foreach ($t in $script:RedemarrageRequis) { Write-Host "        - $t" -ForegroundColor Yellow }
}

function Invoke-RedemarrageFinal {
    if ($script:RedemarrageRequis.Count -eq 0) { return }
    Write-Host ""
    Show-RedemarrageRequis
    if (Demander-Option "`nRedémarrer le PC maintenant pour les appliquer ?") {
        Invoke-Action "redémarrerait le PC" {
            Write-Etat "Redémarrage dans 10 secondes... (Ctrl+C pour annuler)" -Niveau Avert
            Start-Sleep -Seconds 10
            Restart-Computer -Force
        }
    }
    else {
        Write-Etat "Pense à redémarrer : tant que tu ne l'as pas fait, ces tweaks ne servent à rien." -Niveau Info
    }
}

# Fonctions que le script généré emporte avec lui. Un tweak qui n'appelle QUE
# celles-là est exportable tel quel ; tout autre appel maison le rendrait
# increportable, et on préfère le dire que livrer un script qui plantera.
$script:FonctionsPortables = @(
    'Write-Etat', 'Write-Simu', 'T', 'Invoke-Action', 'Set-RegValue',
    'Remove-RegValue', 'Remove-RegKey', 'Set-ServiceEtat', 'Invoke-Externe',
    'Get-ValeurActuelle', 'Get-ValeurLisible'
)

function Get-PreambuleAutonome {
    # Versions minimales mais FIDÈLES des portes. Deux différences assumées, écrites
    # noir sur blanc dans l'en-tête du script généré : pas de sauvegarde (donc pas
    # d'annulation) et pas de simulation. Hors de MadTweak, ces deux filets n'existent
    # pas -- prétendre le contraire serait pire que de ne rien générer.
    return @'
$ErrorActionPreference = 'Stop'

function Write-Etat {
    param([string]$Message, [string]$Niveau = 'Info')
    $c = switch ($Niveau) { 'OK' { 'Green' } 'Echec' { 'Red' } 'Avert' { 'Yellow' } default { 'Gray' } }
    Write-Host "  $Message" -ForegroundColor $c
}
function Write-Simu { param([string]$Message) Write-Host "  [SIMU]  $Message" -ForegroundColor Cyan }
function T { param([string]$Cle) return $Cle }

function Invoke-Action {
    param([string]$Description, [scriptblock]$Action)
    & $Action
}

function Get-ValeurActuelle {
    param([string]$Path, [string]$Name)
    if (-not (Test-Path $Path)) { return $null }
    try {
        $i = Get-Item -Path $Path
        if ($Name -in $i.GetValueNames()) { return $i.GetValue($Name) }
    } catch { }
    return $null
}
function Get-ValeurLisible {
    param($Valeur)
    if ($null -eq $Valeur) { return '(absente)' }
    if ($Valeur -is [byte[]]) { return "(binaire : $(($Valeur | ForEach-Object { '{0:X2}' -f $_ }) -join ' '))" }
    return "$Valeur"
}

function Set-RegValue {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)]$Value,
        [Microsoft.Win32.RegistryValueKind]$Type = 'DWord'
    )
    if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
    if ($Name -eq '(default)' -or $Name -eq '') { Set-Item -Path $Path -Value $Value -Force }
    else { Set-ItemProperty -Path $Path -Name $Name -Value $Value -Type $Type -Force }
}
function Remove-RegValue {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    if (Test-Path $Path) { Remove-ItemProperty -Path $Path -Name $Name -Force -ErrorAction SilentlyContinue }
}
function Remove-RegKey {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path $Path) { Remove-Item -Path $Path -Recurse -Force }
}

function Set-ServiceEtat {
    param(
        [Parameter(Mandatory)][string]$Nom,
        [ValidateSet('Automatic', 'Manual', 'Disabled')][string]$Demarrage,
        [switch]$Arreter, [switch]$Demarrer
    )
    $svc = Get-Service -Name $Nom -ErrorAction SilentlyContinue
    if (-not $svc) { throw "Service '$Nom' introuvable sur cette machine." }
    if ($Arreter) { Stop-Service -Name $Nom -Force -ErrorAction SilentlyContinue }
    if ($Demarrage) { Set-Service -Name $Nom -StartupType $Demarrage }
    if ($Demarrer) { Start-Service -Name $Nom -ErrorAction SilentlyContinue }
}

function Invoke-Externe {
    param(
        [Parameter(Mandatory)][string]$Fichier,
        [string[]]$Arguments = @(),
        [int[]]$CodesOK = @(0),
        [switch]$CaptureSortie
    )
    if ($CaptureSortie) {
        try { $sortie = & $Fichier @Arguments 2>&1 | Out-String }
        catch { return [pscustomobject]@{ CodeSortie = -1; Sortie = ''; Erreur = $_.Exception.Message } }
        return [pscustomobject]@{ CodeSortie = $LASTEXITCODE; Sortie = $sortie; Erreur = $null }
    }
    $p = Start-Process -FilePath $Fichier -ArgumentList $Arguments -Wait -NoNewWindow -PassThru
    if ($p.ExitCode -notin $CodesOK) {
        throw "$([System.IO.Path]::GetFileName($Fichier)) a renvoyé le code d'erreur $($p.ExitCode)."
    }
}
'@
}

function Test-TweakExportable {
    # Un corps de tweak n'est exportable que s'il n'appelle aucune fonction MAISON
    # absente du préambule. On le sait en lisant l'arbre syntaxique, pas en devinant :
    # tout ce qui se résout en « Function » et n'est pas fourni manquerait à l'exécution.
    # Les applets Windows (Set-ItemProperty, Get-Service...) sont des Cmdlet, donc OK.
    param([Parameter(Mandatory)][scriptblock]$Action)
    $noeuds = $Action.Ast.FindAll(
        { param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    $appels = @($noeuds | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique)
    return @($appels | Where-Object {
            $c = Get-Command $_ -ErrorAction SilentlyContinue
            $c -and $c.CommandType -eq 'Function' -and $_ -notin $script:FonctionsPortables
        })
}

function Export-ScriptAutonome {
    # Génère un .ps1 autonome contenant la sélection de tweaks demandée.
    #
    # L'ancienne version lisait $script:RegistreTweaks -- une variable qui n'a JAMAIS
    # existé dans le projet. Résultat : une erreur « indexation impossible dans un
    # tableau Null » par clé demandée, un fichier réduit à son en-tête, et malgré tout
    # un message vert de réussite. Le catalogue vient maintenant de Get-Inventaire,
    # c'est-à-dire du code lui-même, comme les cases de l'interface.
    param(
        [Parameter(Mandatory)][string]$CheminSortiePs1,
        [string[]]$ClesTweaks = @()
    )

    $catalogue = @{}
    foreach ($t in (Get-Inventaire)) { $catalogue[$t.Cle] = $t }

    $inconnues = @($ClesTweaks | Where-Object { -not $catalogue.ContainsKey($_) })
    if ($inconnues.Count -gt 0) {
        # On refuse plutôt que d'écrire un script amputé en silence : une clé fautive
        # ne se remarquerait qu'au moment où le tweak manquerait à l'appel.
        throw "Clé(s) de tweak inconnue(s) : $($inconnues -join ', '). Aucun script n'a été écrit."
    }

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('# ==============================================================================')
    [void]$sb.AppendLine('# SCRIPT D''OPTIMISATION AUTONOME - GENERE PAR MADTWEAK')
    [void]$sb.AppendLine("# $($ClesTweaks.Count) tweak(s), genere depuis MadTweak $($script:Version)")
    [void]$sb.AppendLine('#')
    [void]$sb.AppendLine('# CE QUE CE SCRIPT N''A PAS, contrairement a MadTweak :')
    [void]$sb.AppendLine('#   - AUCUNE sauvegarde : les valeurs d''origine ne sont pas memorisees,')
    [void]$sb.AppendLine('#     donc « Annuler » est impossible. Fais un point de restauration avant.')
    [void]$sb.AppendLine('#   - AUCUN mode simulation : tout s''applique pour de vrai, immediatement.')
    [void]$sb.AppendLine('# ==============================================================================')
    [void]$sb.AppendLine('#Requires -RunAsAdministrator')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine((Get-PreambuleAutonome))
    [void]$sb.AppendLine('')

    $exportes = 0
    $refuses = @()
    foreach ($cle in $ClesTweaks) {
        $tw = $catalogue[$cle]
        if (-not $tw.Action) { $refuses += "$cle (corps absent)"; continue }
        $manquantes = Test-TweakExportable -Action $tw.Action
        if ($manquantes.Count -gt 0) {
            $refuses += "$cle (utilise $($manquantes -join ', '))"
            [void]$sb.AppendLine("# --- $cle : NON EXPORTE, depend de $($manquantes -join ', ') ---")
            [void]$sb.AppendLine('')
            continue
        }
        [void]$sb.AppendLine("# --- $cle : $($tw.Titre) ---")
        [void]$sb.AppendLine('& {')
        [void]$sb.AppendLine($tw.Action.ToString().Trim())
        [void]$sb.AppendLine('}')
        [void]$sb.AppendLine('')
        $exportes++
    }

    [void]$sb.AppendLine('Write-Host ""')
    [void]$sb.AppendLine("Write-Host ""  $exportes tweak(s) applique(s)."" -ForegroundColor Green")

    [System.IO.File]::WriteAllText($CheminSortiePs1, $sb.ToString(), (New-Object System.Text.UTF8Encoding $true))

    if ($refuses.Count -gt 0) {
        Write-Etat "$($refuses.Count) tweak(s) non exportable(s) hors de MadTweak : $($refuses -join ' ; ')" -Niveau Avert
    }
    Write-Etat "Script autonome ecrit ($exportes tweak(s)) : $CheminSortiePs1" -Niveau OK
    return $CheminSortiePs1
}


