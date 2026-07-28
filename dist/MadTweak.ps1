# ==============================================================================
# FICHIER GÉNÉRÉ AUTOMATIQUEMENT — NE PAS ÉDITER
#
# Ce script est le PRODUIT de build.ps1, qui concatène les modules de src\.
# Toute modification faite ici sera PERDUE au prochain build.
#
#   Pour le modifier :  édite le module concerné dans src\, puis .\build.ps1
#   Pour l'utiliser  :  ce fichier est autonome — c'est le SEUL dont tu aies
#                       besoin, copie-le où tu veux (clé USB, autre PC...).
#
# Volontairement SANS date de génération : elle changerait à chaque build et
# rendrait « build.ps1 -Verifier » incapable de repérer une vraie divergence.
# ==============================================================================

#Requires -RunAsAdministrator
# ==============================================================================
# LE WINDOWS UTILITY INTÉGRAL V4 (VERSION FRANÇAISE)
# Inspiré de Chris Titus Tech - Version Système Intégral Maximale
#
# IMPORTANT : les modules de src\ ET le fichier construit DOIVENT rester en
#             UTF-8 AVEC BOM et en fins de ligne LF, sinon les accents seront
#             illisibles sous Windows PowerShell 5.1. build.ps1 s'en charge.
#
# Principe de la V4 : aucune action ne se déclare "appliquée" si elle a échoué.
# ==============================================================================

# param() DOIT être la première instruction exécutable du script : les commentaires
# et #Requires peuvent la précéder, rien d'autre. D'où sa place ici, en tête du
# tout premier module.
param(
    # Force l'ancien menu console. Par défaut le script ouvre l'interface graphique,
    # qui retombe d'elle-même sur la console si WPF est indisponible.
    # L'interface graphique permet désormais d'appliquer tous les tweaks, y compris
    # les plus lourds (Edge, OneDrive, Windows Update, VBS, DISM/SFC, winget, nettoyage).
    [switch]$Console,
    # Mode non interactif : exécute le nettoyage léger et sort. Utilisé par la tâche
    # planifiée « MadTweak-Maintenance ». N'ouvre ni interface ni menu.
    [switch]$Maintenance,
    # Force la langue. Sans ce paramètre, elle suit celle de Windows.
    # Tout est traduit : interface, profils, onglets, les 150 tweaks et les 104
    # tests d'audit. Le français reste la langue d'écriture du projet et le repli.
    [ValidateSet('fr', 'en')]
    [string]$Langue,
    # Applique un profil complet SANS poser de question, puis rend la main.
    # Écrit pour les installations automatisées : le fichier de réponses généré
    # par le menu « Clé d'installation » appelle le script ainsi à la première
    # ouverture de session. Le nom attendu est celui affiché dans le menu Profils
    # (« Minimal / sûr », « Gamer ROG »...). Un nom inconnu est signalé, pas deviné.
    [string]$Profil,
    # Répétition à blanc : montre tout ce qui changerait, n'écrit RIEN. Sans elle,
    # la seule façon d'éprouver un profil non interactif était de l'appliquer pour
    # de bon — donc de ne pas pouvoir l'éprouver du tout.
    [switch]$Simulation
)

$ErrorActionPreference = 'Stop'

# Version de l'outil, affichée dans le titre de la fenêtre, l'en-tête et les rapports.
$script:Version = "1.3.1"

# Compteurs de la session (remis à zéro à chaque entrée de menu)
$script:CompteurOK = 0
$script:CompteurEchec = 0

# ------------------------------------------------------------------------------
# LANGUE
#
# Le projet est né en français et le reste par défaut : c'est son identité, et les
# francophones sont mal servis par ce type d'outil. L'anglais s'ajoute pour être
# utilisable ailleurs, pas pour remplacer.
#
# Principe : AUCUN texte affiché n'est écrit en dur ailleurs qu'ici. Un texte se
# demande par sa clé, `T 'ma-cle'`, et la table décide de la langue. Une clé absente
# renvoie la clé elle-même plutôt que du vide -- un texte manquant doit se VOIR, pas
# se traduire par une interface trouée.
#
# La langue est détectée depuis Windows, et forçable par -Langue fr|en.
#
# NB : la variable d'état s'appelle $script:LangueActive et NON $script:Langue :
# le paramètre -Langue du script vit lui aussi en portée script, et une variable
# homonyme l'écraserait au chargement (le paramètre serait silencieusement perdu).
# ------------------------------------------------------------------------------

function Get-LangueSysteme {
    # 'fr' si l'interface Windows est francophone, 'en' sinon. On lit l'interface
    # (UICulture) et non le format régional : un Belge en anglais avec des dates
    # françaises veut une interface anglaise.
    try {
        $c = [System.Globalization.CultureInfo]::CurrentUICulture.TwoLetterISOLanguageName
        if ($c -eq 'fr') { return 'fr' }
        return 'en'
    }
    catch { return 'fr' }
}

$script:LangueActivesConnues = @('fr', 'en')
$script:LangueActive = Get-LangueSysteme

function Set-Langue {
    param([Parameter(Mandatory)][string]$Code)
    $c = "$Code".ToLower()
    if ($c -notin $script:LangueActivesConnues) { throw "Langue inconnue : $Code (attendu : $($script:LangueActivesConnues -join ', '))" }
    $script:LangueActive = $c
}

function T {
    # Renvoie le texte de la clé dans la langue courante.
    # Repli en cascade : langue courante -> français -> la clé elle-même.
    param([Parameter(Mandatory)][string]$Cle)
    $e = $script:Textes[$Cle]
    if (-not $e) { return $Cle }
    $v = $e[$script:LangueActive]
    if ($v) { return $v }
    if ($e['fr']) { return $e['fr'] }
    return $Cle
}

function Expand-Textes {
    # Remplace les marqueurs {{cle}} d'un texte (typiquement le XAML de l'interface)
    # par leur traduction. Fait AVANT l'analyse du XAML : l'interface est donc
    # construite directement dans la bonne langue, sans repasser sur les contrôles.
    param([Parameter(Mandatory)][string]$Texte)
    return [regex]::Replace($Texte, '\{\{([a-zA-Z0-9_.-]+)\}\}', {
            param($m)
            $t = T $m.Groups[1].Value
            # Le résultat part dans du XAML : les caractères réservés doivent être échappés.
            $t -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;'
        })
}

function Get-TitreMenu {
    # Titre COMPLET d'un menu console. Le paramètre reste le titre français : c'est
    # lui la clé de catégorie. Un titre non traduit s'affiche tel quel.
    param([Parameter(Mandatory)][string]$Titre)
    if ($script:LangueActive -ne 'en') { return $Titre }
    $t = $script:TitresMenus[$Titre]
    if ($t) { return $t }
    return $Titre
}

$script:TitresMenus = @{
    "TWEAKS DE BASE"                                   = "BASIC TWEAKS"
    "TWEAKS AVANCÉS"                                   = "ADVANCED TWEAKS"
    "EXPLORATEUR DE FICHIERS & CONFIGURATION PRIVÉE"   = "FILE EXPLORER & PRIVACY SETTINGS"
    "OPTIMISATION DU MATÉRIEL, DU RÉSEAU ET DE LA RAM" = "HARDWARE, NETWORK AND RAM OPTIMISATION"
    "CONFIGURATION SÉCURITÉ & MISES À JOUR"            = "SECURITY & UPDATE SETTINGS"
    "LOGICIELS EXPRESS (via winget)"                   = "QUICK SOFTWARE (via winget)"
    "OUTILS DE DIAGNOSTIC ET DE RÉPARATION"            = "DIAGNOSTIC AND REPAIR TOOLS"
    "NOUVEAUTÉS WINDOWS 11 (24H2 ET PLUS)"             = "WINDOWS 11 NEWCOMERS (24H2 AND LATER)"
    "NETTOYAGE DU DISQUE"                              = "DISK CLEANUP"
    "DÉMARRAGE & SERVICES"                             = "STARTUP & SERVICES"
    "APPARENCE & CONFORT VISUEL"                       = "APPEARANCE & VISUAL COMFORT"
    "ANNULER LES TWEAKS / REVENIR AUX DÉFAUTS WINDOWS" = "UNDO TWEAKS / RETURN TO WINDOWS DEFAULTS"
}

# ------------------------------------------------------------------------------
# TABLE DES TEXTES
#
# Une entrée = une clé, deux langues. Trié par zone d'affichage pour qu'ajouter un
# texte reste évident. Les textes des TWEAKS (titres et explications) ne sont pas
# encore ici : ils suivront, c'est le gros du volume.
# ------------------------------------------------------------------------------
$script:Textes = @{

    # --- En-tête de l'interface ---
    'app.soustitre'        = @{ fr = "Configuration système"; en = "System configuration" }
    'entete.fond'          = @{ fr = "Fond d'écran : "; en = "Wallpaper: " }
    'entete.accent'        = @{ fr = "Accent Windows : "; en = "Windows accent: " }
    'entete.theme'         = @{ fr = "Thème appli : "; en = "App theme: " }
    'entete.ecran'         = @{ fr = "Écran : "; en = "Screen: " }
    'entete.score.info'    = @{ fr = "Note de santé de la machine, calculée depuis l'audit : part des réglages applicables ici qui sont déjà en place."
        en = "Machine health score, computed from the audit: the share of applicable settings already in place." }
    'entete.fond.info'     = @{ fr = "Génère un fond d'écran « MadTrix » à ta résolution réelle et l'applique. Ton fond précédent est mémorisé."
        en = "Generates a « MadTrix » wallpaper at your real resolution and applies it. Your previous wallpaper is remembered." }
    'entete.accent.info'   = @{ fr = "Colore les barres de titre, la barre des tâches et le menu Démarrer, et synchronise le clavier RGB ASUS sur la même couleur. Réversible."
        en = "Colours the title bars, taskbar and Start menu, and syncs the ASUS RGB keyboard to the same colour. Reversible." }
    'entete.theme.info'    = @{ fr = "Change les couleurs de CETTE fenêtre uniquement (pas Windows). 6 thèmes intégrés."
        en = "Changes the colours of THIS window only (not Windows). 6 built-in themes." }
    'entete.ecran.info'    = @{ fr = "Luminosité de l'écran (0-100 %). Réglage natif Windows."
        en = "Screen brightness (0-100%). Native Windows setting." }

    # --- Zone des profils ---
    'profils.entete'       = @{ fr = "PROFILS — un clic coche un lot cohérent. Tu peux ensuite ajuster case par case."
        en = "PROFILES — one click ticks a coherent batch. You can then adjust box by box." }

    # --- Barre d'outils ---
    'barre.filtrer'        = @{ fr = "Filtrer : "; en = "Filter: " }
    'barre.filtrer.info'   = @{ fr = "Filtre les tweaks par mot-clé (nom ou explication), à travers tous les onglets."
        en = "Filters tweaks by keyword (name or explanation), across every tab." }
    'menu.analyser'        = @{ fr = "Analyser  ▾"; en = "Analyse  ▾" }
    'menu.analyser.info'   = @{ fr = "Tout ce qui LIT la machine sans rien modifier."; en = "Everything that READS the machine without changing anything." }
    'menu.annuler'         = @{ fr = "Annuler  ▾"; en = "Undo  ▾" }
    'menu.annuler.info'    = @{ fr = "Revenir en arrière, totalement ou en partie."; en = "Roll back, fully or partially." }
    'menu.config'          = @{ fr = "Configuration  ▾"; en = "Configuration  ▾" }
    'menu.config.info'     = @{ fr = "Enregistrer, transporter et automatiser ta configuration."; en = "Save, carry over and automate your configuration." }
    'menu.affichage'       = @{ fr = "Affichage  ▾"; en = "View  ▾" }
    'menu.affichage.info'  = @{ fr = "Gagner de la place pour la liste des tweaks."; en = "Free up room for the tweak list." }

    'act.etat'             = @{ fr = "État actuel + score de santé"; en = "Current state + health score" }
    'act.etat.info'        = @{ fr = "Lit l'état réel de la machine et colore en VERT les tweaks déjà appliqués. Calcule la note /100. Ne modifie rien."
        en = "Reads the machine's real state and colours already-applied tweaks GREEN. Computes the score out of 100. Changes nothing." }
    'act.derive'           = @{ fr = "Vérifier la dérive (après MAJ Windows)"; en = "Check for drift (after a Windows update)" }
    'act.derive.info'      = @{ fr = "Coche les réglages que tu avais appliqués mais qu'une mise à jour a fait revenir au défaut."
        en = "Ticks the settings you had applied but a Windows update reverted to default." }
    'act.demarrage'        = @{ fr = "Analyse du démarrage"; en = "Startup analysis" }
    'act.demarrage.info'   = @{ fr = "Durée réelle du démarrage et coût de chaque programme lancé avec Windows."
        en = "Real boot duration and the cost of each program launched with Windows." }
    'act.disque'           = @{ fr = "Analyse du disque"; en = "Disk analysis" }
    'act.disque.info'      = @{ fr = "Pèse chaque poste récupérable AVANT de nettoyer quoi que ce soit."
        en = "Weighs every reclaimable item BEFORE cleaning anything." }
    'act.indesirables'     = @{ fr = "Logiciels indésirables"; en = "Unwanted software" }
    'act.indesirables.info' = @{ fr = "Repère antivirus d'essai OEM, faux optimiseurs et barres d'outils. Signale seulement."
        en = "Spots OEM trial antivirus, fake optimisers and toolbars. Reports only." }
    'act.diagnostic'       = @{ fr = "Diagnostic des plantages"; en = "Crash diagnosis" }
    'act.diagnostic.info'  = @{ fr = "Plantages récents + tweaks d'alimentation suspects. Corrige le pire automatiquement."
        en = "Recent crashes plus suspect power tweaks. Fixes the worst one automatically." }
    'act.rapport'          = @{ fr = "Rapport HTML complet"; en = "Full HTML report" }
    'act.rapport.info'     = @{ fr = "Génère un rapport d'état autonome et l'ouvre dans le navigateur."
        en = "Generates a self-contained status report and opens it in the browser." }
    'act.restaurer'        = @{ fr = "Restauration exacte (tout)"; en = "Exact restore (everything)" }
    'act.restaurer.info'   = @{ fr = "Remet chaque valeur modifiée par ce script telle qu'elle était avant. Demande confirmation."
        en = "Puts every value this script changed back exactly as it was. Asks for confirmation." }
    'act.restaurer.sel'    = @{ fr = "Restauration sélective (au choix)"; en = "Selective restore (pick and choose)" }
    'act.restaurer.sel.info' = @{ fr = "Choisis, valeur par valeur, ce que tu veux remettre à son état d'origine."
        en = "Choose, value by value, what you want returned to its original state." }
    'act.points'           = @{ fr = "Points de restauration Windows"; en = "Windows restore points" }
    'act.points.info'      = @{ fr = "Liste les points de restauration et permet d'y revenir (la machine redémarre)."
        en = "Lists restore points and lets you roll back to one (the machine reboots)." }
    'act.profil.enr'       = @{ fr = "Enregistrer la sélection comme profil"; en = "Save selection as a profile" }
    'act.profil.enr.info'  = @{ fr = "Enregistre les cases cochées comme profil personnalisé nommé, rechargeable en un clic."
        en = "Saves the ticked boxes as a named custom profile, reloadable in one click." }
    'act.export'           = @{ fr = "Exporter ma config…"; en = "Export my config…" }
    'act.export.info'      = @{ fr = "Réunit tweaks appliqués, profils perso et liste d'apps dans un seul fichier."
        en = "Bundles applied tweaks, custom profiles and app list into a single file." }
    'act.import'           = @{ fr = "Importer une config…"; en = "Import a config…" }
    'act.import.info'      = @{ fr = "Charge un fichier de config exporté depuis un autre PC."
        en = "Loads a config file exported from another PC." }
    'act.maintenance'      = @{ fr = "Maintenance auto (hebdomadaire)"; en = "Auto maintenance (weekly)" }
    'act.maintenance.on'   = @{ fr = "Maintenance auto : ACTIVÉE"; en = "Auto maintenance: ENABLED" }
    'act.maintenance.info' = @{ fr = "Planifie ou retire une tâche hebdomadaire de nettoyage silencieux."
        en = "Schedules or removes a weekly silent cleanup task." }
    'act.profils.cacher'   = @{ fr = "Cacher les profils"; en = "Hide profiles" }
    'act.profils.voir'     = @{ fr = "Afficher les profils"; en = "Show profiles" }
    'act.profils.info'     = @{ fr = "Replie la zone des profils (en haut)."; en = "Collapses the profiles area (top)." }
    'act.journal.cacher'   = @{ fr = "Cacher le journal"; en = "Hide log" }
    'act.journal.voir'     = @{ fr = "Afficher le journal"; en = "Show log" }
    'act.journal.info'     = @{ fr = "Replie le journal (en bas)."; en = "Collapses the log (bottom)." }
    'act.gamer'            = @{ fr = "Gamer ROG"; en = "Gamer ROG" }
    'act.gamer.info'       = @{ fr = "En un clic : mode d'alimentation Performances + clavier rouge + coche le profil Gamer (rien n'est appliqué tant que tu ne cliques pas « Appliquer »)."
        en = "One click: Performance power mode + red keyboard + ticks the Gamer profile (nothing is applied until you click Apply)." }

    # --- Boutons d'action ---
    'act.cocher'           = @{ fr = "Tout cocher (onglet)"; en = "Tick all (tab)" }
    'act.cocher.info'      = @{ fr = "Coche tous les tweaks de l'onglet actuellement affiché."; en = "Ticks every tweak in the currently shown tab." }
    'act.decocher'         = @{ fr = "Tout décocher"; en = "Untick all" }
    'act.decocher.info'    = @{ fr = "Décoche tous les tweaks, tous onglets confondus."; en = "Unticks every tweak, across all tabs." }
    'act.pointresto'       = @{ fr = "Point de restauration avant d'appliquer"; en = "Restore point before applying" }
    'act.pointresto.info'  = @{ fr = "Crée un point de restauration Windows juste avant d'appliquer (30-60 s). Filet de sécurité pour tout annuler au pire."
        en = "Creates a Windows restore point just before applying (30-60 s). A safety net to undo everything at worst." }
    'act.simuler'          = @{ fr = "Simuler"; en = "Simulate" }
    'act.simuler.info'     = @{ fr = "Montre, valeur par valeur, ce qui changerait — sans rien écrire. À faire au moins une fois."
        en = "Shows, value by value, what would change — without writing anything. Do this at least once." }
    'act.appliquer'        = @{ fr = "Appliquer"; en = "Apply" }
    'act.appliquer.info'   = @{ fr = "Applique pour de vrai les tweaks cochés. Chaque valeur touchée est sauvegardée avant, donc annulable."
        en = "Actually applies the ticked tweaks. Every value touched is backed up first, so it stays reversible." }
    'act.redemarrer'       = @{ fr = "Redémarrer"; en = "Restart" }
    'act.redemarrer.info'  = @{ fr = "Redémarre le PC maintenant (après confirmation) pour finaliser les tweaks qui l'exigent."
        en = "Restarts the PC now (after confirmation) to finalise tweaks that require it." }

    # --- Sélecteurs de l'en-tête ---
    'sel.choisir'          = @{ fr = "— choisir —"; en = "— choose —" }
    'sel.fond.precedent'   = @{ fr = "Remettre le précédent"; en = "Restore the previous one" }
    'sel.accent.defaut'    = @{ fr = "Retirer l'accent (défaut Windows)"; en = "Remove accent (Windows default)" }
    'entete.langue'        = @{ fr = "Langue : "; en = "Language: " }
    'entete.langue.info'   = @{ fr = "Change la langue de cette fenêtre. Les tweaks eux-mêmes restent en français pour l'instant."
        en = "Changes this window's language. The tweaks themselves are still in French for now." }
    'langue.redemarrer'    = @{ fr = "Langue changée. Ferme et rouvre l'outil pour l'appliquer partout."
        en = "Language changed. Close and reopen the tool to apply it everywhere." }

    # --- Onglets ---
    'onglet.materiel'      = @{ fr = "Matériel"; en = "Hardware" }
    'onglet.installation'  = @{ fr = "Clé d'installation"; en = "Install media" }

    # --- Page « Clé d'installation » ---
    'inst.titre' = @{ fr = "Générer un fichier de réponses Windows"
        en = "Generate a Windows answer file" }
    'inst.expl1' = @{ fr = "Produit un autounattend.xml à déposer À LA RACINE de ta clé USB Windows, à côté de setup.exe. L'installation ne pose alors plus de questions."
        en = "Produces an autounattend.xml to drop AT THE ROOT of your Windows USB stick, next to setup.exe. Setup then stops asking questions." }
    'inst.expl2' = @{ fr = "MadTweak ne fournit aucune image Windows : la licence Microsoft interdit de la redistribuer. Tu télécharges l'ISO officielle toi-même ; ce fichier vient se poser à côté. C'est du texte, relis-le."
        en = "MadTweak ships no Windows image: the Microsoft licence forbids redistributing it. You download the official ISO yourself; this file simply sits next to it. It is plain text, read it." }
    'inst.avert' = @{ fr = "À savoir sur Windows 11 24H2 et 25H2 : le nouvel installeur applique bien le disque, l'édition et la langue, mais ignore souvent la partie « compte utilisateur » — l'écran de création de compte peut réapparaître. Un contournement est inclus, sans garantie possible. Windows 10 et Windows 11 jusqu'à 23H2 ne sont pas concernés."
        en = "Note for Windows 11 24H2 and 25H2: the new setup engine applies disk, edition and language correctly, but often ignores the user-account part - the account creation screen may come back. A workaround is included, with no possible guarantee. Windows 10 and Windows 11 up to 23H2 are unaffected." }
    'inst.version'   = @{ fr = "Version de Windows"; en = "Windows version" }
    'inst.edition'   = @{ fr = "Édition"; en = "Edition" }
    'inst.edition.demander'   = @{ fr = "Laisser l'installeur demander (le plus sûr)"; en = "Let setup ask (safest)" }
    'inst.edition.famille'    = @{ fr = "Famille"; en = "Home" }
    'inst.edition.entreprise' = @{ fr = "Entreprise"; en = "Enterprise" }
    'inst.edition.lire'   = @{ fr = "Lire les éditions dans mon ISO…"; en = "Read editions from my ISO…" }
    'inst.edition.filtre' = @{ fr = "Image Windows (*.iso;*.wim;*.esd)|*.iso;*.wim;*.esd|Tous les fichiers|*.*"
        en = "Windows image (*.iso;*.wim;*.esd)|*.iso;*.wim;*.esd|All files|*.*" }
    'inst.edition.vide'   = @{ fr = "Aucune édition trouvée dans cette image."; en = "No edition found in this image." }
    'inst.jrn.edition.ok' = @{ fr = "Clé d'installation : {0} édition(s) lue(s) dans l'image. La liste ne contient plus que ce qu'elle contient vraiment."
        en = "Install media: {0} edition(s) read from the image. The list now holds only what it really contains." }
    'inst.jrn.edition.echec' = @{ fr = "Clé d'installation : lecture de l'image impossible — {0}"; en = "Install media: could not read the image - {0}" }
    'inst.langue'    = @{ fr = "Langue et clavier"; en = "Language and keyboard" }
    'inst.fuseau'    = @{ fr = "Fuseau horaire"; en = "Time zone" }
    'inst.compte'    = @{ fr = "Nom du compte à créer"; en = "Account name to create" }
    'inst.mdp'       = @{ fr = "Mot de passe (vide = aucun)"; en = "Password (empty = none)" }
    'inst.mdp.avert' = @{ fr = "Dans un fichier de réponses, un mot de passe n'est PAS chiffré : il est encodé en base64, que quiconque a la clé USB relit en une commande. Laisser vide est plus sûr."
        en = "In an answer file a password is NOT encrypted: it is base64-encoded, which anyone holding the USB stick can read back in one command. Leaving it empty is safer." }
    'inst.machine'   = @{ fr = "Nom de la machine (vide = généré)"; en = "Computer name (empty = generated)" }
    'inst.profil'    = @{ fr = "Profil appliqué au premier démarrage"; en = "Profile applied at first boot" }
    'inst.profil.aucun' = @{ fr = "Aucun (ne rien appliquer)"; en = "None (apply nothing)" }
    'inst.apps'      = @{ fr = "Applications à installer au premier démarrage"; en = "Applications to install at first boot" }
    'inst.tpm'       = @{ fr = "Contourner TPM / Secure Boot / RAM (machine ancienne, Windows 11)"; en = "Bypass TPM / Secure Boot / RAM checks (older machine, Windows 11)" }
    'inst.disque'    = @{ fr = "Effacer entièrement le disque 0 (destructif)"; en = "Wipe disk 0 entirely (destructive)" }
    'inst.disque.titre'   = @{ fr = "Effacement du disque"; en = "Disk wipe" }
    'inst.disque.numero'  = @{ fr = "Numéro du disque à effacer (0 = le premier)"; en = "Disk number to wipe (0 = the first)" }
    'inst.disque.confirm' = @{ fr = "Cette option détruit TOUTES les partitions du disque 0, sans confirmation au moment de l'installation.`n`nSans elle, l'installeur demandera où installer Windows, comme d'habitude.`n`nActiver l'effacement ?"
        en = "This option destroys ALL partitions on disk 0, with no confirmation during setup.`n`nWithout it, setup will ask where to install Windows, as usual.`n`nEnable the wipe?" }
    'inst.generer'   = @{ fr = "Générer le fichier de réponses"; en = "Generate the answer file" }
    'inst.jrn.sansnom' = @{ fr = "Clé d'installation : indique d'abord un nom de compte."; en = "Install media: enter an account name first." }
    'inst.jrn.simu'  = @{ fr = "SIMULATION : générerait {0} ({1} application(s))."; en = "SIMULATION: would generate {0} ({1} application(s))." }
    'inst.jrn.ok'    = @{ fr = "Fichier de réponses généré : {0}"; en = "Answer file generated: {0}" }
    'inst.jrn.suite' = @{ fr = "  Prépare la clé avec l'ISO officielle, puis copie autounattend.xml à sa racine, à côté de setup.exe."
        en = "  Prepare the stick with the official ISO, then copy autounattend.xml to its root, next to setup.exe." }
    'inst.jrn.profil' = @{ fr = "  Copie AUSSI MadTweak.ps1 à la racine de la clé : sans lui, le profil ne sera pas appliqué."
        en = "  ALSO copy MadTweak.ps1 to the root of the stick: without it the profile will not be applied." }
    'inst.jrn.mdp'   = @{ fr = "  Rappel : le mot de passe est lisible dans ce fichier. Ne prête pas la clé."
        en = "  Reminder: the password is readable in this file. Do not lend the stick." }
    'inst.jrn.echec' = @{ fr = "Clé d'installation : échec — {0}"; en = "Install media: failed - {0}" }
    'inst.cle.titre'   = @{ fr = "Clé d'installation détectée"; en = "Install media detected" }
    'inst.cle.confirm' = @{ fr = "Une clé d'installation Windows est branchée :`n`n    {0}: — {1} — {2} Go`n`nY copier le fichier de réponses (et MadTweak si un profil est prévu) ?`n`nRien ne sera effacé : seuls des fichiers sont ajoutés."
        en = "A Windows install stick is plugged in:`n`n    {0}: - {1} - {2} GB`n`nCopy the answer file there (and MadTweak if a profile is set)?`n`nNothing will be erased: files are only added." }
    'inst.jrn.cle.aucune' = @{ fr = "  Aucune clé d'installation prête détectée. Prépare-la avec Rufus ou le Media Creation Tool, puis relance la génération : la copie sera proposée."
        en = "  No prepared install stick detected. Prepare it with Rufus or the Media Creation Tool, then generate again: the copy will be offered." }
    'inst.jrn.cle.ok'    = @{ fr = "  Copié sur la clé : {0}"; en = "  Copied to the stick: {0}" }
    'inst.jrn.cle.echec' = @{ fr = "  Copie sur la clé impossible — {0}"; en = "  Could not copy to the stick - {0}" }

    # --- Journal / états ---
    'jrn.pret'             = @{ fr = "Interface prête. {0} tweaks pilotables, {1} profils."; en = "Interface ready. {0} controllable tweaks, {1} profiles." }
    'jrn.conseil'          = @{ fr = "Conseil : commence par « Simuler ». Rien ne sera écrit, et tu verras exactement quelle valeur changerait, et en quoi."
        en = "Tip: start with Simulate. Nothing will be written, and you'll see exactly which value would change, and how." }
    'etat.pret'            = @{ fr = "Prêt. Données de session : {0}"; en = "Ready. Session data: {0}" }
    'etat.audit'           = @{ fr = "Analyse de l'état réel de la machine (quelques secondes)..."; en = "Analysing the machine's real state (a few seconds)..." }
    'etat.sante'           = @{ fr = "Santé : {0}/100  ·  {1}"; en = "Health: {0}/100  ·  {1}" }

    # --- Menu console ---
    # Les entrées sont affichées ; les TITRES de menu (Start-Menu -Titre) restent
    # français car ils servent de clé de catégorie à l'inventaire et aux onglets.
    'c.titre'    = @{ fr = "CONFIGURATION SYSTÈME INTÉGRALE"; en = "COMPLETE SYSTEM CONFIGURATION" }
    'c.1'        = @{ fr = "PROFILS"; en = "PROFILES" }
    'c.1d'       = @{ fr = "Appliquer un lot cohérent d'un coup"; en = "Apply a coherent batch in one go" }
    'c.2'        = @{ fr = "AUDIT"; en = "AUDIT" }
    'c.2d'       = @{ fr = "Que vaut ma machine ? (ne modifie rien)"; en = "How does my machine score? (changes nothing)" }
    'c.3'        = @{ fr = "TWEAKS DE BASE"; en = "BASIC TWEAKS" }
    'c.3d'       = @{ fr = "Télémétrie, Pubs, Bloatwares & Interface"; en = "Telemetry, ads, bloatware and interface" }
    'c.4'        = @{ fr = "TWEAKS AVANCÉS"; en = "ADVANCED TWEAKS" }
    'c.4d'       = @{ fr = "Clic Droit, Services & Mémoire"; en = "Right-click, services and memory" }
    'c.5'        = @{ fr = "EXPLORATEUR & PRIVÉ"; en = "EXPLORER & PRIVACY" }
    'c.5d'       = @{ fr = "Épurer l'explorateur, Confidentialité"; en = "Declutter Explorer, privacy" }
    'c.6'        = @{ fr = "MATÉRIEL & RÉSEAU"; en = "HARDWARE & NETWORK" }
    'c.6d'       = @{ fr = "Télémétrie GPU, USB, Latence, LLMNR"; en = "GPU telemetry, USB, latency, LLMNR" }
    'c.7'        = @{ fr = "MAJ, SÉCURITÉ & IA"; en = "UPDATES, SECURITY & AI" }
    'c.7d'       = @{ fr = "Windows Update, VBS, Copilot & Recall"; en = "Windows Update, VBS, Copilot and Recall" }
    'c.8'        = @{ fr = "WINDOWS 11 24H2+"; en = "WINDOWS 11 24H2+" }
    'c.8d'       = @{ fr = "Pubs Démarrer, Verrouillage, Widgets, IA"; en = "Start menu ads, lock screen, Widgets, AI" }
    'c.9'        = @{ fr = "APPARENCE & VISUEL"; en = "APPEARANCE & VISUALS" }
    'c.9d'       = @{ fr = "Thème sombre, Explorateur, Barre des tâches"; en = "Dark theme, Explorer, taskbar" }
    'c.10'       = @{ fr = "SIGNATURE MADTRIX"; en = "MADTRIX SIGNATURE" }
    'c.10d'      = @{ fr = "Fond d'écran perso généré à la volée"; en = "Custom wallpaper generated on the fly" }
    'c.11'       = @{ fr = "NETTOYAGE DISQUE"; en = "DISK CLEANUP" }
    'c.11d'      = @{ fr = "Caches et temporaires (mesurés d'abord)"; en = "Caches and temp files (weighed first)" }
    'c.12'       = @{ fr = "DÉMARRAGE & SERV."; en = "STARTUP & SERVICES" }
    'c.12d'      = @{ fr = "Démarrage, services rarement utiles"; en = "Startup, rarely useful services" }
    'c.13'       = @{ fr = "LOGICIELS EXTRA"; en = "EXTRA SOFTWARE" }
    'c.13d'      = @{ fr = "Catalogue d'installation Winget"; en = "Winget installation catalogue" }
    'c.14'       = @{ fr = "MAINTENANCE & FIX"; en = "MAINTENANCE & REPAIR" }
    'c.14d'      = @{ fr = "Réparation système (DISM / SFC)"; en = "System repair (DISM / SFC)" }
    'c.15'       = @{ fr = "CLÉ D'INSTALLATION"; en = "INSTALL MEDIA" }
    'c.15d'      = @{ fr = "Fichier de réponses pour installer Windows"; en = "Answer file to install Windows" }
    'c.16'       = @{ fr = "ANNULER"; en = "UNDO" }
    'c.16d'      = @{ fr = "Revenir aux défauts Windows"; en = "Return to Windows defaults" }
    'c.17'       = @{ fr = "QUITTER"; en = "QUIT" }
    'c.17d'      = @{ fr = "Quitter l'utilitaire"; en = "Leave the utility" }
    'c.simu.on'  = @{ fr = "  S [SIMULATION] : ACTIVE - rien ne sera écrit sur le système"
        en = "  S [SIMULATION]: ON - nothing will be written to the system" }
    'c.simu.off' = @{ fr = "  S [SIMULATION] : inactive - les tweaks seront RÉELLEMENT appliqués"
        en = "  S [SIMULATION]: off - tweaks will be REALLY applied" }
    'c.systeme'  = @{ fr = " Système : "; en = " System: " }
    'c.choix'    = @{ fr = "Entre ton choix (1-17, ou S)"; en = "Enter your choice (1-17, or S)" }

    # --- Mentions de santé ---
    'sante.excellent'      = @{ fr = "excellent"; en = "excellent" }
    'sante.bon'            = @{ fr = "bon"; en = "good" }
    'sante.moyen'          = @{ fr = "moyen"; en = "fair" }
    'sante.faible'         = @{ fr = "à optimiser"; en = "needs work" }
}
# ------------------------------------------------------------------------------
# TEXTES DES TWEAKS — traductions anglaises
#
# Le FRANÇAIS n'est pas ici : il reste écrit en clair à l'appel d'Invoke-Tweak,
# pour que le code se lise sans dictionnaire. C'est aussi lui le repli.
#
# Cette table ne contient donc que l'anglais, retrouvé par la CLÉ du tweak :
#   <cle>.t  le titre         <cle>.e  l'explication
#
# Conséquence utile : traduire est ADDITIF. Un tweak absent de cette table
# s'affiche en français, sans rien casser — on peut donc avancer par lots.
#
# Règle de traduction : l'explication doit dire ce que le réglage FAIT *et CE
# QU'IL COÛTE*. Une traduction qui perd la contrepartie trahit le projet.
# ------------------------------------------------------------------------------
$script:TextesTweaks = @{

    # --- 50 : Tweaks de base ---
    'telemetrie.t' = "Disable Windows telemetry, the advertising ID and suggestions?"
    'telemetrie.e' = "Windows regularly sends Microsoft data about how you use your PC, and uses an advertising ID to target you. This setting cuts both, and removes the « suggestions » from the Start menu and Settings. On Windows Home, telemetry drops to the lowest allowed level (Required) but cannot be switched off entirely: only Windows Enterprise permits that."

    'desinstaller-onedrive.t' = "Thoroughly uninstall Microsoft OneDrive?"
    'desinstaller-onedrive.e' = "Completely removes Microsoft OneDrive from the system, stops it running and cleans up its installation files."

    'widgets-chat.t' = "Remove Widgets, the Chat icon and cut Bing out of the Start menu?"
    'widgets-chat.e' = "Removes the Widgets panel (weather and news) and the Chat/Teams icon from the taskbar, and stops the Start menu sending what you type to Bing for web results. You keep local search for your files and apps."

    'bloatwares.t' = "Uninstall the usual bloatware (TikTok, Disney+, Spotify, Weather...)?"
    'bloatwares.e' = "Removes the preinstalled apps almost nobody uses: TikTok, Disney+, Spotify, News, Weather, Solitaire, LinkedIn, Clipchamp, Skype... They are removed from your account AND from future accounts created on this PC. The Microsoft Store, Defender and Terminal are never touched: removing those would break Windows. You can reinstall anything from the Store if you change your mind."

    'apps-oem.t' = "Uninstall OEM and Xbox apps (Dolby, Xbox, Family Safety, Phone Link)?"
    'apps-oem.e' = "Kept separate from the previous list because it is debatable: keep Xbox if you use Game Pass, and Dolby if your laptop has genuine Dolby Atmos audio hardware (otherwise you would lose sound quality). « Phone Link » is what receives Android texts and notifications on the PC."

    # --- 51 : Tweaks avancés ---
    'clic-droit-classique.t' = "Restore the classic Windows 10 right-click menu?"
    'clic-droit-classique.e' = "Windows 11 replaced the right-click menu with a shortened version that hides half the options behind « Show more options ». This setting brings back the full Windows 10 menu in one go. Explorer must be restarted (offered at the end of the menu) to see it."

    'animations.t' = "Disable window animations (snappier)?"
    'animations.e' = "Removes the opening, closing and minimising animations. Nothing actually runs faster, but everything RESPONDS faster: you no longer wait for the animation to finish. Most noticeable on a modest machine."

    'desinstaller-edge.t' = "Fully uninstall Microsoft Edge? (often blocked by Microsoft, and Edge can return via Windows Update)"
    'desinstaller-edge.e' = "Completely uninstalls Microsoft Edge. Note: Microsoft tends to reinstall it during major updates."

    'qos.t' = "Free the bandwidth Windows reserves (QoS Packet Scheduler)?"
    'qos.e' = "By default Windows reserves 20% of your bandwidth for so-called priority traffic that almost no application uses. This setting lifts that reservation. The gain is real but modest: do not expect your throughput to double."

    'wer.t' = "Disable the Windows Error Reporting service (WerSvc)?"
    'wer.e' = "The error reporting service collects crash details and offers to send them to Microsoft. Turning it off frees a little memory and stops those uploads. In exchange, you lose the reports that sometimes help you understand a recurring crash."

    'tuer-applis-figees.t' = "Make Windows kill unresponsive applications instantly?"
    'tuer-applis-figees.e' = "When an application stops responding, Windows waits several seconds before offering to close it. This setting shortens that wait considerably and closes frozen apps at shutdown. Downside: an application that is merely SLOW (a large save in progress) will be killed sooner, with a risk of losing your work."

    'noyau-en-ram.t' = "Keep the Windows kernel in RAM instead of the page file? (needs at least 8 GB)"
    'noyau-en-ram.e' = "Stops Windows paging the core of the system out to disk, keeping it in memory instead. Improves responsiveness if you have RAM to spare. Automatically refused below 8 GB, where it would be counterproductive."

    'ntfs-lastaccess.t' = "Stop timestamping every file when it is read (NTFS last access)? (speeds up large folders)"
    'ntfs-lastaccess.e' = "By default Windows records the date and time on every file READ: it writes to disk even when you are only browsing. Turning it off speeds up navigating large folders. Careful: if you use incremental backups based on access time, they will be thrown off."

    'longpaths.t' = "Lift the 260-character limit on file paths (LongPaths)?"
    'longpaths.e' = "Lifts the old 260-character limit on file paths. Useful if you hit « path too long » errors copying deep folder trees. No downside: applications that cannot handle long paths simply carry on as before."

    'sudo.t' = "Enable 'sudo' for Windows? (elevate one command without opening an admin terminal)"
    'sudo.e' = "Enables the Windows « sudo » command (24H2 and later), which elevates a single command without reopening an administrator terminal. Configured in « inline » mode: the elevated command runs in your current terminal. Usage: sudo <command>."

    'demarrage-rapide.t' = "Disable Fast Startup?"
    'demarrage-rapide.e' = "Disables fast startup so Windows shuts down completely every time. Avoids driver state corruption and fixes incomplete shutdowns (fans that keep spinning, for instance)."

    'clic-droit-possession.t' = "Add « Take Ownership » to the right-click menu?"
    'clic-droit-possession.e' = "Adds a « Take Ownership » entry to the right-click menu on files and folders, so you can grant yourself modify rights easily."

    'explorer-separate-process.t' = "Isolate Explorer windows in separate processes (SeparateProcess)?"
    'explorer-separate-process.e' = "Makes Windows Explorer open each folder in its own system process. Improves stability: if one folder window crashes or freezes, it no longer takes the taskbar and desktop down with it."

    'disable-low-disk-warning.t' = "Disable low disk space warnings?"
    'disable-low-disk-warning.e' = "Disables the recurring Windows notifications warning that one of your drives or partitions is nearly full. Handy for storage drives you intend to fill on purpose."

    'disable-lock-screen.t' = "Disable the lock screen?"
    'disable-lock-screen.e' = "Disables the welcome and lock screen at startup and on lock, going straight to the sign-in and password prompt."

    'kill-timeouts.t' = "Shorten the shutdown wait (kill timeouts)?"
    'kill-timeouts.e' = "Makes Windows close and kill stubborn or frozen applications and services far quicker (2 seconds instead of 20) when they block or slow down shutdown."

    'auto-restart-shell.t' = "Restart Explorer automatically after a crash (AutoRestartShell)?"
    'auto-restart-shell.e' = "Forces Windows to relaunch the File Explorer process (taskbar, desktop) automatically if it crashes or stops unexpectedly, so you are not left staring at a black screen."

    # --- 52 : Explorateur & vie privée ---
    'explorateur-accueil.t' = "Hide 'Recent files' and 'Frequent folders' from Explorer Home?"
    'explorateur-accueil.e' = "Hides the « Recent files » and « Frequent folders » lists shown when Explorer opens. Useful if someone else can see your screen: those lists tell the story of what you opened recently."

    'extensions-fichiers.t' = "Show file extensions by default (.txt, .exe, .ps1)?"
    'extensions-fichiers.e' = "Shows each file's real extension (.txt, .exe, .ps1). Windows hides them by default, which lets « photo.jpg.exe » pass itself off as an image. As much a security setting as a convenience one."

    'taches-telemetrie.t' = "Disable the scheduled data-collection tasks (telemetry tasks)?"
    'taches-telemetrie.e' = "Disables the scheduled tasks that collect usage data in the background (Compatibility Appraiser, Customer Experience Improvement Program, UsbCeip). They run periodically without giving you anything. Their names change between Windows versions: the script resolves them at runtime rather than guessing."

    'presse-papiers.t' = "Disable cloud clipboard history?"
    'presse-papiers.e' = "Turns off clipboard history (Win+V) and its sync to your other devices via your Microsoft account. Everything you copy — including passwords — stops being remembered and uploaded. Downside: Win+V will no longer bring back what you copied ten minutes ago."

    'recherche-bing.t' = "Cut Bing/web results and 'highlights' out of Windows Search?"
    'recherche-bing.e' = "Start menu search sends what you type to Bing to show web results and « highlights ». This setting cuts all of that: search becomes purely local, faster, and never leaves your PC."

    'delivery-optimization.t' = "Stop sharing your Windows updates with other PCs over the internet (Delivery Optimization)?"
    'delivery-optimization.e' = "By default your PC HOSTS pieces of Windows updates and uploads them to strangers over the internet, using your upload bandwidth. This setting stops that sharing: updates come from Microsoft servers only."

    'autoplay.t' = "Disable AutoPlay for USB sticks and external drives?"
    'autoplay.e' = "Stops Windows automatically running or opening the contents of a USB stick or external drive the moment it is plugged in. Convenient, but above all it closes a classic infection route via a booby-trapped USB stick."

    'historique-activite.t' = "Disable activity history and its upload to Microsoft (Timeline)?"
    'historique-activite.e' = "Windows keeps a history of what you opened (the « Timeline ») and can upload it to your Microsoft account. This setting cuts all three layers at once: the feature, the local collection and the upload. Most guides disable only one and leave the others running."

    'experiences-personnalisees.t' = "Disable 'tailored experiences' based on your diagnostic data?"
    'experiences-personnalisees.e' = "Stops Microsoft using your diagnostic data to suggest tips, ads and personalised apps inside Windows. This is the per-user setting, the only one genuinely honoured on every edition, Home included."

    'feedback.t' = "Never ask for feedback again (Windows Feedback)?"
    'feedback.e' = "Windows periodically asks for your opinion through pop-up windows. This setting tells it never to ask again. No downside: you can still give feedback yourself whenever you want."

    'saisie-personnalisation.t' = "Stop the collection of your typing and handwriting (input personalisation)?"
    'saisie-personnalisation.e' = "Windows analyses what you type and handwrite to improve its suggestions, and collects your contacts' names. This setting stops that collection. In exchange, typing suggestions and handwriting recognition will become less accurate."

    'service-diagtrack.t' = "Disable the DiagTrack telemetry service (Connected User Experiences)?"
    'service-diagtrack.e' = "Cuts the service that actually sends the telemetry, instead of merely asking it politely to hold back. This is more radical than the telemetry setting — and it is what counts on Windows Home, where the level cannot drop to zero. Downside: Feedback Hub and some Microsoft Support diagnostics will stop working."

    'defender-echantillons.t' = "Stop sending file samples to Microsoft Defender?"
    'defender-echantillons.e' = "Defender sends suspicious files to Microsoft for analysis by default — so potentially YOUR files. This setting stops those uploads. Important: Defender's cloud protection stays ACTIVE. Your security is not reduced, only the sharing of your files is."

    'geolocalisation.t' = "Deny location access to every application?"
    'geolocalisation.e' = "Denies location access to every application. Only enable this if you know what you lose: Weather, Maps and « Find my device » will stop working, and the time zone will no longer set itself automatically when you travel."

    'apps-arriere-plan.t' = "Stop Store apps running in the background? (saves RAM and battery)"
    'apps-arriere-plan.e' = "Stops Store apps running in the background when you are not using them. Saves memory and battery, especially on a laptop. Downside: those apps will no longer receive push notifications while this is on."

    'bloquer-sug-store.t' = "Block the automatic install of Store-suggested apps?"
    'bloquer-sug-store.e' = "Stops Windows and the Microsoft Store silently downloading and installing suggested or partner apps and games (Candy Crush, Spotify, TikTok and the like) in the background."

    'edge-telemetrie.t' = "Disable Microsoft Edge telemetry and sponsored suggestions?"
    'edge-telemetrie.e' = "Disables browsing telemetry, personalisation and sponsored suggestions in the Microsoft Edge browser."

    'dev-telemetrie.t' = "Disable VS Code and Visual Studio telemetry?"
    'dev-telemetrie.e' = "Disables the background upload of usage, diagnostic and user-experience data in VS Code (by editing the user settings.json) and in Visual Studio (via machine policy)."

    'browsers-telemetrie.t' = "Disable Google Chrome and Mozilla Firefox telemetry?"
    'browsers-telemetrie.e' = "Disables telemetry, usage reporting and built-in experimental studies in Chrome and Firefox through machine registry policies."

    'office-telemetrie.t' = "Disable Microsoft Office telemetry?"
    'office-telemetrie.e' = "Disables background feedback, diagnostics and client telemetry in the Microsoft Office suite."

    'disable-web-search-start.t' = "Disable Bing web search in the Start menu?"
    'disable-web-search-start.e' = "Disables Bing search in the local search box of the taskbar and Start menu. Stops everything you type locally to find an app or a file from being sent online to Bing."

    'thirdparty-telemetrie.t' = "Disable auto-start and telemetry of third-party services (Google Update, Adobe)?"
    'thirdparty-telemetrie.e' = "Configures Adobe (Adobe Update, Genuine Integrity) and Google Update's update and telemetry services so they do not start automatically in the background when the PC boots."

    # --- 53 : Matériel & réseau ---
    'nvidia-telemetrie.t' = "Disable the hidden NVIDIA graphics telemetry?"
    'nvidia-telemetrie.e' = "The NVIDIA driver installs a service and scheduled tasks that report usage data back to NVIDIA. Neither the driver nor your games need them. No effect if you have no NVIDIA card."

    'sysmain.t' = "Disable SysMain / Superfetch? (good on SSD - AVOID on a mechanical hard drive)"
    'sysmain.e' = "SysMain (formerly Superfetch) preloads into memory the applications it thinks you are about to open. On an SSD that guesswork is pointless and sometimes causes stutter. On a mechanical HARD DRIVE, however, it genuinely helps: the script checks your system drive and refuses the setting if it is a hard drive."

    'usb-suspension.t' = "Disable USB selective suspend? (prevents disconnections)"
    'usb-suspension.e' = "Windows cuts power to idle USB ports to save energy, which causes mice, keyboards, headsets or external drives to drop out. This setting stops it. On a desktop it is all upside; on a LAPTOP it costs battery life."

    'net-crawling.t' = "Disable automatic scanning for shared network folders?"
    'net-crawling.e' = "Stops Explorer automatically going looking for shared folders on your local network. Purely cosmetic: it avoids lag when Explorer opens. You can still reach your shares by typing their address."

    'hibernation.t' = "Disable hibernation and reclaim the hiberfil.sys space? (also disables Fast Startup)"
    'hibernation.e' = "Disables hibernation and deletes hiberfil.sys, a hidden file several GB in size. WARNING: this also disables « fast startup », so your PC will boot more slowly. On a laptop it is a bad idea: you lose the hibernation that saves your session when the battery runs out."

    'nagle.t' = "Disable Nagle's algorithm? (lowers gaming latency, may reduce download throughput)"
    'nagle.e' = "Nagle's algorithm bundles small network packets before sending them, which adds a few milliseconds of latency. Disabling it helps in online gaming. Real downside: it can REDUCE your download throughput. Only take it if latency matters more than bandwidth."

    'souris-acceleration.t' = "Disable mouse acceleration ('enhance pointer precision')? (consistent aim in games)"
    'souris-acceleration.e' = "Windows accelerates the pointer when you move the mouse quickly: the same gesture does not always travel the same distance. Turning it off makes your aim consistent, which is what every gamer wants. Expect an adjustment period: your in-game sensitivity will change. Takes effect at your next sign-in."

    'spouleur.t' = "Disable the print spooler? (closes a known attack surface)"
    'spouleur.e' = "The print spooler is a known attack surface (the PrintNightmare family of flaws) and runs permanently even without a printer. The script first checks that no real printer is installed and refuses if it finds one: without the spooler, printing becomes impossible."

    'llmnr-netbios.t' = "Disable LLMNR and NetBIOS? (closes two classic local-network attack surfaces)"
    'llmnr-netbios.e' = "LLMNR and NetBIOS are used to find machines on the local network when DNS fails. They are exploited by classic local-network spoofing attacks (Responder and friends), and a home PC with working DNS has no need for them. Downside: if you reach an old NAS or a share by name and it breaks, undo this setting."

    'doh.t' = "Allow encrypted DNS (DNS over HTTPS)?"
    'doh.e' = "Lets Windows encrypt your DNS queries (DNS over HTTPS), so your ISP no longer sees in the clear which sites you visit. Set to « allowed » rather than « required »: Windows encrypts if your DNS server supports it, and falls back to plaintext otherwise. « Required » with a DNS that lacks DoH would cut you off from the internet. Only effective with a compatible DNS (Cloudflare, Google, Quad9)."

    'carte-reseau-veille.t' = "Stop Windows powering down the network adapter to save energy? (Wi-Fi drops, latency)"
    'carte-reseau-veille.e' = "Windows powers down the network adapter to save energy, which causes Wi-Fi drops and latency spikes. This setting forbids it, on your physical adapters only (VPN virtual adapters are left alone). On a LAPTOP it costs battery life."

    'game-dvr.t' = "Disable Game DVR / Game Bar background recording? (FPS gain)"
    'game-dvr.e' = "The Game Bar records your game in the background permanently, in case you want to keep the last 30 seconds. That costs FPS for a feature few people use. The Game Bar (Win+G) stays usable: only background recording is cut."

    'plan-performances-ultimes.t' = "Enable the hidden 'Ultimate Performance' power plan?"
    'plan-performances-ultimes.e' = "Adds Microsoft's hidden power plan, which forbids any component from going to sleep. Reserved for DESKTOPS: the script refuses it on a laptop, where Microsoft hides it for good reason — it runs hot and drains the battery. Once added, you must select it in Settings > System > Power."

    'bridage-multimedia.t' = "Lift the network throttling reserved for multimedia (NetworkThrottlingIndex)?"
    'bridage-multimedia.e' = "Windows throttles the network and CPU priorities to reserve resources for multimedia, a trade-off designed for 2008-era machines. This setting lifts the throttle. Useful for gaming and streaming; no visible effect in office use."

    'modern-standby.t' = "Disable modern standby (S0) and restore classic S3 sleep?"
    'modern-standby.e' = "Forces classic S3 sleep instead of modern standby S0. RESERVED for machines whose firmware GENUINELY supports S3: on a laptop designed for S0 (most recent ROG models), forcing S3 causes crashes on wake and on RESUME FROM HIBERNATION. The tweak detects this and REFUSES to apply."

    'hags-gpu.t' = "Enable hardware-accelerated GPU scheduling (HAGS)?"
    'hags-gpu.e' = "Enables hardware-accelerated GPU scheduling to reduce display latency and improve performance in compatible games (required for Nvidia DLSS 3 / AMD FSR 3 frame generation)."

    'amd-telemetrie.t' = "Disable AMD Radeon Software telemetry?"
    'amd-telemetrie.e' = "Disables telemetry and analytics collection in AMD Radeon Software."

    'pcie-power-management.t' = "Disable PCIe power saving (Link State Power Management)?"
    'pcie-power-management.e' = "Configures the active power plan to disable PCIe Link State power management. Stops graphics cards and NVMe SSDs having their power reduced, eliminating wake-up micro-stutters."

    'xbox-gamebar.t' = "Disable Xbox Game Bar background features?"
    'xbox-gamebar.e' = "Disables background recording and the Xbox Game Bar app to free CPU and memory while gaming."

    'delivery-optimization-p2p.t' = "Disable P2P sharing of Windows Update downloads (Delivery Optimization)?"
    'delivery-optimization-p2p.e' = "Configures Windows to fetch Windows Update packages directly from Microsoft servers (HTTP) without using or sharing your upload bandwidth with other computers on the local network or the internet."

    'ntfs-performance.t' = "Disable 8.3 short-name creation (NTFS performance)?"
    'ntfs-performance.e' = "Disables the generation of DOS-style 8.3 short filenames on NTFS. Improves read/write performance, especially in directories holding very large numbers of files."

    # --- 61 : Apparence & visuel ---
    'mode-sombre.t' = "Enable DARK mode (Windows and apps)?"
    'mode-sombre.e' = "Switches Windows and applications to the dark theme. BOTH settings are written: one dresses the apps, the other the taskbar and Start menu. Many guides set only one and leave you with a half-dark theme."

    'transparence.t' = "Disable transparency effects (Acrylic / Mica)?"
    'transparence.e' = "Turns off the transparency effects (Acrylic, Mica) on windows and the Start menu. Unlike the other settings in this tab, this one genuinely affects performance: transparency costs GPU time, which matters on a laptop with integrated graphics."

    'accent-barres-titre.t' = "Apply your accent colour to title bars and borders?"
    'accent-barres-titre.e' = "Applies your accent colour to window title bars and borders. Without this setting they stay grey whatever colour you pick in Settings. The colour used is the one from Settings > Personalisation > Colours."

    'qualite-fond-ecran.t' = "Improve wallpaper quality (no JPEG recompression)?"
    'qualite-fond-ecran.e' = "Windows recompresses your wallpaper to roughly 85% quality, which shows on gradients and flat areas. This setting switches to maximum quality. Only effective when you SET a wallpaper again: the current one is already recompressed."

    'fichiers-caches.t' = "Show HIDDEN files and folders?"
    'fichiers-caches.e' = "Shows files and folders marked as hidden. Handy for reaching AppData or a .gitignore without a detour. Harmless: these are mostly configuration files."

    'fichiers-systeme.t' = "Also show protected SYSTEM files? (pagefile.sys, hiberfil.sys...)"
    'fichiers-systeme.e' = "ALSO shows protected system files (pagefile.sys, hiberfil.sys, bootmgr). Only take this if you know what you are doing: these files are hidden for a reason, and deleting one can leave Windows unbootable."

    'explorateur-ce-pc.t' = "Open Explorer on « This PC » rather than « Home »?"
    'explorateur-ce-pc.e' = "Explorer opens on « This PC » (your drives) instead of « Home », the Windows 11 page that mixes recent files with OneDrive files."

    'explorateur-compact.t' = "Enable COMPACT view in Explorer (tighter rows, like Windows 10)?"
    'explorateur-compact.e' = "Tightens the spacing between Explorer rows, as in Windows 10. Windows 11 spaces everything out for touch; on a desktop screen that just makes you scroll for nothing."

    'explorateur-galerie.t' = "Remove « Gallery » from the Explorer navigation pane?"
    'explorateur-galerie.e' = "Removes the « Gallery » entry from the Explorer navigation pane. It is a photo view added in 23H2, redundant with the Photos app. Reversible: the script exports the key before deleting it, so Exact restore can put it back."

    'explorateur-volet-accueil.t' = "Remove « Home » from the Explorer navigation pane?"
    'explorateur-volet-accueil.e' = "Removes the « Home » entry from the navigation pane. Explorer will automatically fall back to « This PC » on opening: it cannot open on a location that no longer exists."

    'suffixe-raccourci.t' = "Remove the « - Shortcut » suffix on new shortcuts?"
    'suffixe-raccourci.e' = "Windows appends « - Shortcut » to the name of every new shortcut. This setting stops that. It does not rename existing shortcuts: only new ones are affected."

    'recherche-barre-taches.t' = "Shrink the taskbar search box to a single icon?"
    'recherche-barre-taches.e' = "Shrinks the large taskbar search box to a single icon, freeing a lot of room. To hide it entirely: right-click the taskbar > Search > Hide."

    'bouton-vue-taches.t' = "Hide the « Task view » button from the taskbar?"
    'bouton-vue-taches.e' = "Hides the « Task view » button from the taskbar. The Win+Tab shortcut keeps working: only the button disappears."

    'horloge-secondes.t' = "Show SECONDS in the taskbar clock?"
    'horloge-secondes.e' = "Shows seconds in the taskbar clock. Microsoft removed it to save battery: on a laptop the clock redraws every second, which has a real if small cost. Negligible on a desktop."

    'demarrer-plus-epingles.t' = "Show MORE pins and less « Recommended » in the Start menu?"
    'demarrer-plus-epingles.e' = "Enlarges the pinned apps area of the Start menu at the expense of the « Recommended » area. Best combined with cutting the Start menu ads, in the Windows 11 tab."

    'aero-shake.t' = "Disable Aero Shake (shaking a window minimises all others)?"
    'aero-shake.e' = "Disables Aero Shake, the feature that minimises all your other windows when you shake the top one. Mostly useful if you trigger it by accident while moving a window."

    'snap-layouts.t' = "Disable the Snap Layouts flyout?"
    'snap-layouts.e' = "Disables the flyout menu that pops up when you hover the Maximise button. Snapping keeps working normally (Win+arrows, drag to an edge): only the automatic menu disappears."

    'barres-defilement.t' = "Keep scrollbars always visible (instead of letting them fade out)?"
    'barres-defilement.e' = "Keeps scrollbars permanently visible instead of having them fade out and reappear on hover. You always see where you are in a page, and you can aim at the bar without making it appear first."

    'photo-classique.t' = "Restore the classic Windows Photo Viewer?"
    'photo-classique.e' = "Brings back the old, very fast and lightweight Windows Photo Viewer from Windows 7/8. Associates JPG, JPEG, PNG, GIF, BMP, TIFF and ICO files with it."

    'god-mode.t' = "Add the « God Mode » shortcut to the Desktop?"
    'god-mode.e' = "Creates a special « full Control Panel » folder (God Mode) on your Desktop gathering more than 200 Windows administration and settings tools in one place."

    'menu-delay.t' = "Remove the menu display delay (MenuShowDelay)?"
    'menu-delay.e' = "Reduces the delay before menus appear on hover (from 400 ms by default to 20 ms). Makes submenus and context menus appear instantly, improving the overall feeling of responsiveness."

    'disable-login-blur.t' = "Disable the background blur on the sign-in screen?"
    'disable-login-blur.e' = "Disables the acrylic blur Windows applies to the background image of the password screen, for a sharp and more responsive display."

    # --- 54 : Mises à jour, sécurité & IA ---
    'copilot.t' = "Disable Windows Copilot?"
    'copilot.e' = "Removes the Copilot button and sets the policy that disables it. Since that old policy does not cover the modern Copilot shipped from 24H2 onwards (now a plain Store app), the script also UNINSTALLS that app: it is the only reliable way. You can reinstall it from the Store."

    'recall.t' = "Disable Recall and AI data analysis?"
    'recall.e' = "Recall periodically captures your screen and indexes it so you can « go back in time ». This setting disables it, removes its files and deletes the snapshots already recorded. On a Copilot+ PC, where Recall is a genuine Windows feature, the component is removed outright (restart required)."

    'update-defer.t' = "Defer feature updates by 365 days (security fixes keep arriving)?"
    'update-defer.e' = "Defers feature updates by 365 days to keep the system stable. Critical security fixes keep arriving. Requires Windows Pro edition."

    'update-block.t' = "Completely disable the Windows Update service?"
    'update-block.e' = "Disables and fully blocks the Windows Update service (wuauserv). Warning: no security fix will be able to install."

    'update-restore.t' = "Restore the default Windows Update settings?"
    'update-restore.e' = "Puts the Windows Update service settings back to their defaults."

    'vbs-desactiver.t' = "Disable virtualisation-based security (VBS) / Core Isolation?"
    'vbs-desactiver.e' = "Disables VBS and core isolation to improve gaming and GPU compute performance. Reduces overall system security."

    'update-pilotes.t' = "Stop Windows Update installing or updating drivers?"
    'update-pilotes.e' = "Stops Windows Update automatically overwriting your hardware drivers (such as Nvidia/AMD graphics drivers) with generic or older versions of its own choosing. You will have to update your drivers manually."

    'regback-backup.t' = "Enable periodic Windows Registry backups (RegBack)?"
    'regback-backup.e' = "Configures Windows to make regular automatic registry backups into System32\config\RegBack (disabled by default by Microsoft to save 50 MB of disk). Adds a safety margin should the registry become corrupted."

    'defender-cpu-limit.t' = "Cap Windows Defender CPU usage during scans?"
    'defender-cpu-limit.e' = "Caps Windows Defender's maximum CPU usage at 30% during its automatic background scans. Avoids temperature spikes and sudden slowdowns while you are gaming or working."

    # --- 57 : Windows 11 24H2+ ---
    'pubs-demarrer.t' = "Remove ads and 'recommendations' from the Start menu? (24H2+)"
    'pubs-demarrer.e' = "The Start menu shows « recommendations » that are really ads for Store apps, mixed in with your recent files and applications. This setting cuts all three. The Recommended area will empty out: see the « more pins » setting in the Appearance tab to reclaim the space."

    'pubs-scoobe.t' = "Cut the 'Let's finish setting up your device' screens after updates?"
    'pubs-scoobe.e' = "After every major update, Windows shows a full-page « Let's finish setting up your device » screen pushing you towards Edge, Bing and OneDrive. This setting stops it appearing."

    'pubs-explorateur.t' = "Remove OneDrive/Store ads disguised as notifications in Explorer?"
    'pubs-explorateur.e' = "Explorer shows banners that look like system notifications but are advertisements for OneDrive and Microsoft 365. This setting removes them. If you genuinely use OneDrive, you also lose its sync notifications."

    'pubs-verrouillage.t' = "Cut lock screen ads and Spotlight?"
    'pubs-verrouillage.e' = "The lock screen (Windows Spotlight) shows attractive photos accompanied by suggestions and advertisements. This setting cuts the advertising overlays."

    'widgets-dsh.t' = "Fully disable Widgets? ('Dsh' policy, the one that works since 24H2)"
    'widgets-dsh.e' = "Fully disables the Widgets panel. This is the policy that actually works from 24H2 onwards: the old « Windows Feeds » key that most guides recommend no longer even exists."

    'barre-taches-gauche.t' = "Align the taskbar LEFT (like Windows 10)?"
    'barre-taches-gauche.e' = "Aligns the taskbar to the left, as in Windows 10 and every earlier version, instead of the Windows 11 centring. Purely a matter of habit."

    'fin-de-tache.t' = "ADD 'End task' to the taskbar right-click menu? (kill an app without Task Manager)"
    'fin-de-tache.e' = "Adds « End task » to the right-click menu on a taskbar icon, so you can kill a frozen application without opening Task Manager. This one ENABLES a useful feature rather than cutting one."

    'panneau-telephone.t' = "Hide the 'Phone' panel from the Start menu? (new in 25H2)"
    'panneau-telephone.e' = "Hides the « Phone » panel added to the Start menu by 25H2. Undocumented by Microsoft and found by the community: if it reappears after an update, the key has changed."

    'paint-ia.t' = "Disable Paint's AI features (Cocreator, Generative fill, Image Creator)?"
    'paint-ia.e' = "Disables Paint's generative AI features (Cocreator, Generative fill, Image Creator). Paint keeps working normally for everything else."

    'click-to-do.t' = "Disable 'Click to Do' (AI screen analysis)?"
    'click-to-do.e' = "Click to Do analyses your screen contents with AI to offer contextual actions. Honestly: Microsoft only documents this policy for Insider builds, so its effect on a stable release is not guaranteed. It is set as a precaution. The feature only runs on Copilot+ PCs with an NPU anyway."

    # --- 55 : Logiciels (winget) ---
    'winget-export.t' = "EXPORT the list of apps installed on this PC (to reinstall them elsewhere)?"
    'winget-export.e' = "Exports the list of all your currently installed applications as JSON into the data folder."

    'winget-import.t' = "IMPORT and reinstall apps from a previous export?"
    'winget-import.e' = "Automatically imports and reinstalls your applications from a previously exported mes-apps.json file."

    'winget-upgrade-all.t' = "Update ALL installed apps (winget upgrade --all)?"
    'winget-upgrade-all.e' = "Automatically updates every application installed on the machine using winget."

    # --- 56 : Maintenance ---
    'maintenance-dism.t' = "Run DISM to repair the Windows system image? (several minutes)"
    'maintenance-dism.e' = "Scans the Windows system image for damage and repairs it by downloading healthy files through Windows Update (internet required)."

    'maintenance-sfc.t' = "Run an SFC scan to repair corrupted system files? (several minutes)"
    'maintenance-sfc.e' = "Scans all protected Windows system files and replaces corrupted versions with healthy copies."

    'maintenance-winsxs-cleanup.t' = "Clean and compress the component store (WinSxS)? (several minutes)"
    'maintenance-winsxs-cleanup.e' = "Runs the DISM cleanup with StartComponentCleanup and ResetBase. Permanently removes old system component versions made obsolete or superseded by recent updates. Frees a lot of space in C:\Windows\WinSxS, but makes the updates currently installed impossible to uninstall."

    'maintenance-purger-journaux.t' = "Purge every Windows event log?"
    'maintenance-purger-journaux.e' = "Empties all the Windows Event Viewer logs to free space."

    # --- 59 : Nettoyage disque ---
    'nettoyage-temp-user.t' = "Empty the temporary files (user account)"
    'nettoyage-temp-user.e' = "Empties the current user account's temporary folder (TEMP). Frees disk space."

    'nettoyage-temp-system.t' = "Empty the temporary files (Windows system)"
    'nettoyage-temp-system.e' = "Empties the Windows system temporary folder (System Temp) used by services and installers."

    'nettoyage-update-cache.t' = "Empty the Windows Update cache"
    'nettoyage-update-cache.e' = "Deletes the installers and temporary files of Windows updates already applied."

    'nettoyage-wer.t' = "Empty the Windows Error Reporting files (WER)"
    'nettoyage-wer.e' = "Deletes crash report files and system memory dumps."

    'nettoyage-delivery-optimization.t' = "Empty the Delivery Optimization cache"
    'nettoyage-delivery-optimization.e' = "Deletes the temporary files used for peer-to-peer distribution of updates."

    'nettoyage-miniatures.t' = "Empty the Explorer thumbnail cache"
    'nettoyage-miniatures.e' = "Deletes the thumbnail cache files (rebuilt automatically as you browse)."

    'nettoyage-windows-old.t' = "Delete the Windows.old rollback folder"
    'nettoyage-windows-old.e' = "Permanently deletes the Windows.old folder holding the previous system installation (gives up the ability to roll back)."

    # --- 60 : Démarrage & services ---
    'delai-demarrage.t' = "Remove the artificial 10 s delay before startup programs launch?"
    'delai-demarrage.e' = "Windows deliberately delays your startup programs by 10 seconds to make the desktop usable sooner. On an SSD that delay no longer serves a purpose. Affects YOUR programs only, not Windows services."

    'service-fax.t' = "Disable the Fax service?"
    'service-fax.e' = "The Fax service is loaded on every Windows installation, including the millions of PCs that have never seen a modem. No downside, unless you genuinely send faxes."

    'service-registre-distant.t' = "Disable Remote Registry? (attack surface, useless outside a company)"
    'service-registre-distant.e' = "Lets another machine read and modify your registry remotely. It is an attack surface, and it is useless outside a corporate network. Windows already leaves it disabled by default on a home PC."

    'service-retaildemo.t' = "Disable retail demo mode (RetailDemo)?"
    'service-retaildemo.e' = "Retail demo mode is for PCs on display in a shop. On your machine it will never do anything useful."

    'service-cartes.t' = "Disable offline map downloads (MapsBroker)?"
    'service-cartes.e' = "MapsBroker handles offline map downloads. Useless if you do not use the Maps app. Downside: it will no longer be able to download maps for offline use."

    'service-bluetooth.t' = "Disable Bluetooth? (only if this PC has NO Bluetooth device)"
    'service-bluetooth.e' = "Turns off the Bluetooth service. Only take this if this PC has no Bluetooth device: the script detects active devices and refuses if it finds any, since your keyboard, mouse or headset would stop working after a restart."

    'service-search.t' = "Disable Windows Search file indexing (WSearch)?"
    'service-search.e' = "Disables the Windows Search file indexing service. Recommended on machines with a good SSD, to save RAM and pointless disk activity. Explorer's search keeps working, but directly, without a prebuilt index."
}
# ------------------------------------------------------------------------------
# TEXTES DE L'AUDIT — traductions anglaises
#
# Même principe que les tweaks : le français reste écrit en clair dans le catalogue
# d'audit (70-audit.ps1), et sert de CLÉ ici. Un nom absent de cette table s'affiche
# donc en français, sans rien casser.
#
# Ces noms apparaissent dans le rapport HTML, dans le menu AUDIT de la console et
# dans le détail du score de santé — c'est-à-dire dans tout ce qui se partage.
# ------------------------------------------------------------------------------
$script:CatsAudit = @{
    "Vie privée"  = "Privacy"
    "IA"          = "AI"
    "Interface"   = "Interface"
    "Apparence"   = "Appearance"
    "Performance" = "Performance"
    "Réseau"      = "Network"
    "Services"    = "Services"
}

$script:TextesAudit = @{
    # --- Vie privée ---
    "Télémétrie Windows coupée"                                  = "Windows telemetry cut"
    "Identifiant publicitaire désactivé"                         = "Advertising ID disabled"
    "Tâches planifiées de collecte désactivées"                  = "Scheduled collection tasks disabled"
    "Recherche Bing / web coupée"                                = "Bing / web search cut"
    "Presse-papiers cloud désactivé"                             = "Cloud clipboard disabled"
    "Partage P2P des mises à jour coupé"                         = "P2P update sharing cut"
    "Lecture automatique (AutoPlay) désactivée"                  = "AutoPlay disabled"
    "Apps du Store bloquées en arrière-plan"                     = "Store apps blocked in the background"
    "Bloatwares du Store désinstallés"                           = "Store bloatware uninstalled"
    "Historique d'activité (Timeline) désactivé"                 = "Activity history (Timeline) disabled"
    "Expériences personnalisées désactivées"                     = "Tailored experiences disabled"
    "Demandes d'avis (Feedback) coupées"                         = "Feedback prompts cut"
    "Collecte de la frappe / écriture coupée"                    = "Typing / handwriting collection cut"
    "Envoi d'échantillons à Defender coupé"                      = "Sample submission to Defender cut"
    "Géolocalisation refusée aux applications"                   = "Location denied to applications"
    "Installation automatique d'applications suggérées bloquée"  = "Automatic install of suggested apps blocked"
    "Télémétrie et suggestions Microsoft Edge désactivées"       = "Microsoft Edge telemetry and suggestions disabled"
    "Télémétrie AMD Radeon Software désactivée"                  = "AMD Radeon Software telemetry disabled"
    "Télémétrie VS Code / Visual Studio désactivée"              = "VS Code / Visual Studio telemetry disabled"
    "Télémétrie Chrome / Firefox désactivée"                     = "Chrome / Firefox telemetry disabled"
    "Télémétrie Microsoft Office désactivée"                     = "Microsoft Office telemetry disabled"
    "Recherche Web Bing locale désactivée"                       = "Local Bing web search disabled"
    "Services tiers (Google Update, Adobe) en manuel"            = "Third-party services (Google Update, Adobe) set to manual"

    # --- IA ---
    "Windows Copilot désactivé (stratégie)"                      = "Windows Copilot disabled (policy)"
    "App Copilot absente de la machine"                          = "Copilot app absent from the machine"
    "Recall / analyse IA désactivée"                             = "Recall / AI analysis disabled"
    "Fonctions IA de Paint désactivées"                          = "Paint AI features disabled"
    "Click to Do désactivé"                                      = "Click to Do disabled"

    # --- Interface ---
    "Extensions de fichiers affichées"                           = "File extensions shown"
    "Menu clic droit classique (Windows 10)"                     = "Classic right-click menu (Windows 10)"
    "Pubs / recommandations du menu Démarrer coupées"            = "Start menu ads / recommendations cut"
    "Pubs de l'écran de verrouillage coupées"                    = "Lock screen ads cut"
    "Widgets désactivés (stratégie Dsh)"                         = "Widgets disabled (Dsh policy)"
    "Barre des tâches alignée à gauche"                          = "Taskbar aligned left"
    "'Fin de tâche' ajouté au clic droit de la barre"            = "'End task' added to the taskbar right-click menu"
    "Dossiers de l'Explorateur isolés dans des processus séparés" = "Explorer folders isolated in separate processes"
    "Relancement automatique de l'Explorateur activé"            = "Automatic Explorer restart enabled"
    "Écran de verrouillage (Lock Screen) désactivé"              = "Lock screen disabled"
    "Animations des fenêtres désactivées"                        = "Window animations disabled"
    "Fichiers récents masqués de l'Explorateur"                  = "Recent files hidden from Explorer"
    "Icône Chat retirée de la barre des tâches"                  = "Chat icon removed from the taskbar"
    "Écrans 'Tirez le meilleur parti de Windows' coupés"         = "'Finish setting up your device' screens cut"
    "Pubs OneDrive/Store de l'Explorateur coupées"               = "OneDrive/Store ads in Explorer cut"
    "Panneau 'Téléphone' du menu Démarrer masqué (25H2)"         = "Start menu 'Phone' panel hidden (25H2)"
    "Recherche auto des partages réseau désactivée"              = "Automatic network share discovery disabled"

    # --- Apparence ---
    "Mode sombre (Windows et applications)"                      = "Dark mode (Windows and apps)"
    "Effets de transparence désactivés"                          = "Transparency effects disabled"
    "Couleur d'accentuation sur les barres de titre"             = "Accent colour on title bars"
    "Fond d'écran en qualité maximale"                           = "Wallpaper at maximum quality"
    "Fichiers cachés affichés"                                   = "Hidden files shown"
    "Fichiers système protégés affichés"                         = "Protected system files shown"
    "Explorateur ouvre sur « Ce PC »"                            = "Explorer opens on « This PC »"
    "Explorateur en affichage compact"                           = "Explorer in compact view"
    "« Galerie » retirée du volet de navigation"                 = "« Gallery » removed from the navigation pane"
    "« Accueil » retiré du volet de navigation"                  = "« Home » removed from the navigation pane"
    "Suffixe « - Raccourci » supprimé"                           = "« - Shortcut » suffix removed"
    "Barre de recherche réduite (icône ou masquée)"              = "Search box shrunk (icon or hidden)"
    "Bouton « Vue des tâches » masqué"                           = "« Task view » button hidden"
    "Secondes affichées dans l'horloge"                          = "Seconds shown in the clock"
    "Menu Démarrer : plus d'épingles"                            = "Start menu: more pins"
    "Aero Shake désactivé"                                       = "Aero Shake disabled"
    "Menu volant des dispositions d'ancrage désactivé"           = "Snap Layouts flyout disabled"
    "Barres de défilement toujours visibles"                     = "Scrollbars always visible"
    "Délai d'affichage des menus réduit"                         = "Menu display delay reduced"
    "Flou de l'arrière-plan de connexion désactivé"              = "Sign-in background blur disabled"

    # --- Performance ---
    "Noyau maintenu en RAM"                                      = "Kernel kept in RAM"
    "Game DVR (enregistrement de fond) coupé"                    = "Game DVR (background recording) cut"
    "Accélération de la souris désactivée"                       = "Mouse acceleration disabled"
    "Applications figées tuées automatiquement"                  = "Frozen applications killed automatically"
    "Limite des 260 caractères levée"                            = "260-character limit lifted"
    "Horodatage NTFS à la lecture désactivé"                     = "NTFS last-access timestamping disabled"
    "'sudo' activé (24H2+)"                                      = "'sudo' enabled (24H2+)"
    "Hibernation et démarrage rapide désactivés"                 = "Hibernation and Fast Startup disabled"
    "Démarrage rapide (Fast Startup) désactivé"                  = "Fast Startup disabled"
    "Veille moderne (Modern Standby S0) désactivée"              = "Modern standby (S0) disabled"
    "Sauvegardes périodiques du Registre (RegBack) activées"     = "Periodic registry backups (RegBack) enabled"
    "Usage CPU de Defender limité à 30% lors des scans"          = "Defender CPU usage capped at 30% during scans"
    "Planification GPU accélérée par le matériel (HAGS) activée" = "Hardware-accelerated GPU scheduling (HAGS) enabled"
    "Économie d'énergie PCIe (Link State) désactivée"            = "PCIe power saving (Link State) disabled"
    "Fonctions de fond Xbox Game Bar désactivées"                = "Xbox Game Bar background features disabled"
    "Alertes d'espace disque faible désactivées"                 = "Low disk space warnings disabled"
    "Délais d'arrêt des applications réduits (Kill Timeouts)"    = "Application shutdown timeouts reduced"
    "Création des noms courts 8.3 NTFS désactivée"               = "NTFS 8.3 short-name creation disabled"
    "Plan 'Performances ultimes' présent"                        = "'Ultimate Performance' plan present"
    "Délai de démarrage des programmes supprimé"                 = "Startup program delay removed"

    # --- Réseau ---
    "Bridage QoS (20% réservés) levé"                            = "QoS throttling (20% reserved) lifted"
    "Bridage réseau multimédia levé"                             = "Multimedia network throttling lifted"
    "Algorithme de Nagle désactivé"                              = "Nagle's algorithm disabled"
    "LLMNR désactivé"                                            = "LLMNR disabled"
    "NetBIOS désactivé sur toutes les interfaces"                = "NetBIOS disabled on every interface"
    "DNS chiffré (DoH) autorisé"                                 = "Encrypted DNS (DoH) allowed"
    "Mise en veille des cartes réseau interdite"                 = "Network adapter power-down forbidden"
    "Partage de mises à jour P2P désactivé"                      = "P2P update sharing disabled"

    # --- Services ---
    "SysMain / Superfetch désactivé"                             = "SysMain / Superfetch disabled"
    "Service de télémétrie DiagTrack désactivé"                  = "DiagTrack telemetry service disabled"
    "Service Fax désactivé"                                      = "Fax service disabled"
    "Registre distant désactivé"                                 = "Remote Registry disabled"
    "Mode démonstration magasin désactivé"                       = "Retail demo mode disabled"
    "Téléchargement des cartes (MapsBroker) désactivé"           = "Map downloads (MapsBroker) disabled"
    "Service Bluetooth désactivé"                                = "Bluetooth service disabled"
    "Rapport d'erreurs Windows désactivé"                        = "Windows Error Reporting disabled"
    "Spouleur d'impression désactivé"                            = "Print spooler disabled"
    "Télémétrie NVIDIA désactivée"                               = "NVIDIA telemetry disabled"
    "Indexation de fichiers Windows Search désactivée"           = "Windows Search file indexing disabled"
}

function Get-NomAudit {
    param([Parameter(Mandatory)][string]$Nom)
    if ($script:LangueActive -eq 'en') {
        $t = $script:TextesAudit[$Nom]
        if ($t) { return $t }
    }
    return $Nom
}

function Get-CatAudit {
    param([Parameter(Mandatory)][string]$Cat)
    if ($script:LangueActive -eq 'en') {
        $t = $script:CatsAudit[$Cat]
        if ($t) { return $t }
    }
    return $Cat
}
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

# ------------------------------------------------------------------------------
# SAUVEGARDE DE L'ÉTAT D'ORIGINE
# Sans ça, "Annuler" ne peut que deviner les défauts de Windows. Ici on note la
# valeur exacte AVANT de la toucher, une seule fois (le tout premier état vu),
# pour pouvoir rendre la machine exactement telle qu'on l'a trouvée.
# ------------------------------------------------------------------------------
function Get-IdentiteMachine {
    # MachineGuid est unique par installation de Windows : c'est ce qui permet de
    # ne JAMAIS appliquer la sauvegarde d'un PC sur un autre.
    $guid = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -ErrorAction SilentlyContinue).MachineGuid
    if (-not $guid) { $guid = "$((Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).UUID)" }
    if (-not $guid) { $guid = "inconnu-$env:COMPUTERNAME" }
    return [pscustomobject]@{ Nom = $env:COMPUTERNAME; Guid = "$guid" }
}

function Get-DossierDonnees {
    # %LOCALAPPDATA% EN PREMIER, le dossier du script seulement en secours.
    #
    # L'ordre était inverse, et il tenait tant que le script vivait à la racine du
    # projet. Depuis qu'il est CONSTRUIT dans dist\ -- un dossier explicitement
    # jetable et régénérable -- la sauvegarde y atterrissait : supprimer dist\
    # aurait détruit le seul moyen d'annuler exactement les tweaks. Une donnée
    # précieuse n'a rien à faire dans un dossier qu'on invite à supprimer.
    #
    # Garder la sauvegarde « près du script » pour la transporter n'apportait de
    # toute façon rien : elle est verrouillée par MachineGuid, donc inutilisable
    # sur une autre machine par construction.
    $candidats = @()
    if ($env:LOCALAPPDATA) { $candidats += (Join-Path $env:LOCALAPPDATA "MadTweak") }
    # Secours : $PSScriptRoot est VIDE si le script est collé dans une console ou
    # lancé via « irm ... | iex ». Et %LOCALAPPDATA% peut manquer sur un compte
    # système ou dans un environnement d'installation (WinPE).
    if ($PSScriptRoot) { $candidats += (Join-Path $PSScriptRoot "madtweak-donnees") }
    if ($env:TEMP) { $candidats += (Join-Path $env:TEMP "MadTweak") }

    foreach ($c in $candidats) {
        try {
            if (-not (Test-Path $c)) { New-Item -ItemType Directory -Path $c -Force -ErrorAction Stop | Out-Null }
            $sonde = Join-Path $c ".ecriture"
            [System.IO.File]::WriteAllText($sonde, "x")
            [System.IO.File]::Delete($sonde)
            return $c
        }
        catch { continue }
    }
    throw "Aucun dossier accessible en écriture pour la sauvegarde."
}

$script:Machine = Get-IdentiteMachine
$script:DossierDonnees = $null
$script:DossierCles = $null
$script:FichierSauvegarde = $null
$script:Sauvegarde = @{}
$script:SauvegardeActive = $true

function Initialize-Sauvegarde {
    $script:DossierDonnees = Get-DossierDonnees
    # Les clés entières ne tiennent pas dans le JSON : elles sont exportées ici en .reg.
    $script:DossierCles = Join-Path $script:DossierDonnees "cles-sauvegardees"
    if (-not (Test-Path $script:DossierCles)) { New-Item -ItemType Directory -Path $script:DossierCles -Force | Out-Null }
    # Le nom du fichier porte la machine : emporter le script sur une clé USB ne
    # peut donc pas mélanger les sauvegardes de deux PC différents.
    $court = if ($script:Machine.Guid.Length -ge 8) { $script:Machine.Guid.Substring(0, 8) } else { $script:Machine.Guid }
    $script:FichierSauvegarde = Join-Path $script:DossierDonnees "sauvegarde-$($script:Machine.Nom)-$court.json"
    $script:Sauvegarde = @{}

    if (Test-Path $script:FichierSauvegarde) {
        try {
            $json = Get-Content $script:FichierSauvegarde -Raw -Encoding UTF8 | ConvertFrom-Json
            # Double sécurité : on revérifie l'identité STOCKÉE dans le fichier.
            if ($json.Machine.Guid -ne $script:Machine.Guid) {
                Write-Etat "Sauvegarde ignorée : elle provient d'une AUTRE machine ($($json.Machine.Nom))." -Niveau Avert
                Write-Etat "Restaurer ses valeurs ici écraserait ce PC avec les réglages d'un autre. Une sauvegarde neuve sera créée." -Niveau Avert
                $script:FichierSauvegarde = Join-Path $script:DossierDonnees "sauvegarde-$($script:Machine.Nom)-$court-$(Get-Date -Format 'yyyyMMddHHmmss').json"
                return
            }
            foreach ($p in $json.Valeurs.PSObject.Properties) { $script:Sauvegarde[$p.Name] = $p.Value }
            Write-Etat "Sauvegarde de CE PC chargée : $($script:Sauvegarde.Count) valeur(s) d'origine mémorisée(s)." -Niveau Info
        }
        catch {
            Write-Etat "Sauvegarde illisible ($($_.Exception.Message)). Elle sera reconstruite." -Niveau Avert
            $script:Sauvegarde = @{}
        }
    }
    Write-Etat "Données de session : $script:DossierDonnees" -Niveau Info
}

function Write-Sauvegarde {
    try {
        [ordered]@{
            Machine = @{ Nom = $script:Machine.Nom; Guid = $script:Machine.Guid; OS = "$($script:InfosOS.DisplayVersion) build $($script:InfosOS.CurrentBuild)" }
            Ecrit   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            Valeurs = $script:Sauvegarde
        } | ConvertTo-Json -Depth 6 | Set-Content -Path $script:FichierSauvegarde -Encoding UTF8 -Force
    }
    catch { Write-Etat "Impossible d'écrire la sauvegarde : $($_.Exception.Message)" -Niveau Avert }
}

function Save-EtatAvant {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    if (-not $script:SauvegardeActive) { return }
    $cle = "$Path|$Name"
    # On ne réécrit JAMAIS une entrée : le premier état vu est le vrai état d'origine.
    if ($script:Sauvegarde.ContainsKey($cle)) { return }

    $entree = [ordered]@{ Path = $Path; Name = $Name; Existait = $false; Valeur = $null; Type = $null }
    if (Test-Path $Path) {
        try {
            $item = Get-Item -Path $Path
            if ($Name -eq "(default)" -or $Name -eq "") {
                $val = $item.GetValue("")
                if ($null -ne $val) {
                    $entree.Existait = $true
                    $entree.Valeur = $val
                    $entree.Type = "String"
                }
            }
            elseif ($Name -in $item.GetValueNames()) {
                $entree.Existait = $true
                $entree.Valeur = $item.GetValue($Name)
                $entree.Type = $item.GetValueKind($Name).ToString()
            }
        }
        catch { }
    }
    $script:Sauvegarde[$cle] = $entree
    Write-Sauvegarde
}

function ConvertTo-CheminNatif {
    # reg.exe ne comprend ni les lecteurs PowerShell (HKLM:\...) ni les chemins
    # qualifiés par le provider (Microsoft.PowerShell.Core\Registry::HKEY_...),
    # or les deux formes circulent dans ce script : les tweaks écrivent la
    # première, Get-ChildItem renvoie la seconde via .PSPath.
    param([Parameter(Mandatory)][string]$Path)
    $p = $Path -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
    $p = $p -replace '^HKLM:', 'HKEY_LOCAL_MACHINE'
    $p = $p -replace '^HKCU:', 'HKEY_CURRENT_USER'
    $p = $p -replace '^HKCR:', 'HKEY_CLASSES_ROOT'
    $p = $p -replace '^HKU:', 'HKEY_USERS'
    $p = $p -replace '^HKCC:', 'HKEY_CURRENT_CONFIG'
    if ($p -notmatch '^HKEY_') { throw "Chemin de registre non reconnu : $Path" }
    return $p
}

function Save-EtatCle {
    # Pendant qu'une VALEUR tient dans le JSON, une CLÉ entière et son arborescence
    # ne s'y prêtent pas. On l'exporte donc en .reg à côté du JSON, qui ne garde
    # que le pointeur. Sans ça, Remove-RegKey détruisait sans filet : la clé de
    # stratégie Windows Update et la CLSID du clic droit partaient définitivement,
    # et « Restauration EXACTE » ne pouvait pas les faire revenir.
    param([Parameter(Mandatory)][string]$Path)
    # Un tweak peut appeler Save-EtatCle directement (et pas seulement via
    # Remove-RegKey) : la garde de simulation doit donc être ici aussi, sinon une
    # simulation écrirait des .reg et polluerait le fichier de sauvegarde.
    if ($script:Simulation) { return }
    if (-not $script:SauvegardeActive) { return }
    $cle = "CLE|$Path"
    if ($script:Sauvegarde.ContainsKey($cle)) { return }

    $entree = [ordered]@{ Type = "CleRegistre"; Path = $Path; Existait = $false; Fichier = $null }
    if (Test-Path $Path) {
        $nom = "cle-" + ($Path -replace '[^A-Za-z0-9]', '_') + ".reg"
        # Un chemin de registre profond dépasse vite la limite de nom de fichier.
        if ($nom.Length -gt 150) { $nom = "cle-" + [System.IO.Path]::GetRandomFileName() + ".reg" }
        $fichier = Join-Path $script:DossierCles $nom
        $natif = ConvertTo-CheminNatif $Path
        reg.exe export "$natif" "$fichier" /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $fichier)) {
            throw "Impossible d'exporter la clé $Path (reg.exe a renvoyé $LASTEXITCODE). Sans cet export, la suppression serait irréversible : rien n'a été supprimé."
        }
        $entree.Existait = $true
        $entree.Fichier = $fichier
    }
    $script:Sauvegarde[$cle] = $entree
    Write-Sauvegarde
}

function Restore-UneEntree {
    # Restaure UNE entrée de sauvegarde (valeur, service ou clé entière). Renvoie 'R'
    # (remise) ou 'S' (retirée) ; lève en cas d'échec. Partagée par la restauration
    # complète ET la restauration sélective, pour que les deux se comportent à l'identique.
    param([Parameter(Mandatory)]$e)
    # Les entrées "Service" ne sont pas des valeurs de registre : Set-Service, pas Set-ItemProperty.
    if ($e.Type -eq "Service") {
        if (Get-Service -Name $e.Nom -ErrorAction SilentlyContinue) {
            Set-Service -Name $e.Nom -StartupType $e.Demarrage
            if ($e.Etat -eq "Running") { Start-Service -Name $e.Nom -ErrorAction SilentlyContinue }
        }
        return 'R'
    }
    # Les clés entières se restaurent depuis leur export .reg.
    if ($e.Type -eq "CleRegistre") {
        if (-not $e.Existait) {
            # La clé n'existait pas avant nous (cas du clic droit classique) : on la retire.
            if (Test-Path $e.Path) { Remove-Item -Path $e.Path -Recurse -Force }
            return 'S'
        }
        if (-not (Test-Path $e.Fichier)) { throw "Export introuvable : $($e.Fichier). La clé ne peut pas être restaurée." }
        # reg import FUSIONNE au lieu de remplacer : sans cette suppression préalable,
        # les valeurs ajoutées depuis l'export survivraient.
        if (Test-Path $e.Path) { Remove-Item -Path $e.Path -Recurse -Force }
        reg.exe import "$($e.Fichier)" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "reg import a renvoyé le code $LASTEXITCODE." }
        return 'R'
    }
    if ($e.Existait) {
        $valeur = $e.Valeur
        # Le JSON transforme un byte[] en tableau d'entiers : il faut le recaster.
        if ($e.Type -eq "Binary") { $valeur = [byte[]]@($valeur) }
        if (-not (Test-Path $e.Path)) { New-Item -Path $e.Path -Force | Out-Null }
        if ($e.Name -eq "(default)" -or $e.Name -eq "") { Set-Item -Path $e.Path -Value $valeur -Force }
        else { Set-ItemProperty -Path $e.Path -Name $e.Name -Value $valeur -Type $e.Type -Force }
        return 'R'
    }
    # La valeur n'existait pas avant nous : on la retire.
    if (Test-Path $e.Path) {
        if ($e.Name -eq "(default)" -or $e.Name -eq "") { Set-Item -Path $e.Path -Value "" -Force }
        else { Remove-ItemProperty -Path $e.Path -Name $e.Name -Force -ErrorAction SilentlyContinue | Out-Null }
    }
    return 'S'
}

function Restore-Sauvegarde {
    if ($script:Simulation) {
        Write-Simu "restaurerait $($script:Sauvegarde.Count) valeur(s)/service(s) à leur état d'origine"
        return
    }
    if ($script:Sauvegarde.Count -eq 0) {
        throw "Aucune sauvegarde disponible : ce script n'a encore rien modifié sur cette machine (ou le fichier a été supprimé)."
    }
    # Pendant la restauration, on ne veut évidemment pas re-sauvegarder.
    $script:SauvegardeActive = $false
    $restaurees = 0; $supprimees = 0; $echecs = 0
    try {
        foreach ($cle in @($script:Sauvegarde.Keys)) {
            $e = $script:Sauvegarde[$cle]
            try {
                if ((Restore-UneEntree $e) -eq 'R') { $restaurees++ } else { $supprimees++ }
            }
            catch {
                Write-Etat "Échec sur $($e.Path)\$($e.Name) : $($_.Exception.Message)" -Niveau Echec
                $echecs++
            }
        }
    }
    finally { $script:SauvegardeActive = $true }

    Write-Etat "$restaurees valeur(s) remise(s) à leur état d'origine, $supprimees retirée(s), $echecs échec(s)." -Niveau Info
    if ($echecs -gt 0) { throw "$echecs valeur(s) n'ont pas pu être restaurées." }
}

function Get-EntreesSauvegarde {
    # Liste lisible des modifications sauvegardées, pour la restauration SÉLECTIVE :
    # clé interne + description + valeur d'avant.
    $res = @()
    foreach ($cle in @($script:Sauvegarde.Keys | Sort-Object)) {
        $e = $script:Sauvegarde[$cle]
        $desc = switch ($e.Type) {
            "Service" { "Service : $($e.Nom)" }
            "CleRegistre" { "Clé : $($e.Path)" }
            default {
                $court = "$($e.Path)" -replace '^HKEY_CURRENT_USER|^HKCU:', 'HKCU' -replace '^HKEY_LOCAL_MACHINE|^HKLM:', 'HKLM'
                "$court\$($e.Name)"
            }
        }
        $avant = if ($e.Type -eq 'Service') { "$($e.Demarrage)" } elseif ($e.Existait) { "$($e.Valeur)" } else { "(absente)" }
        $res += [pscustomobject]@{ Cle = $cle; Desc = $desc; Avant = $avant }
    }
    return $res
}

function Restore-SauvegardePartielle {
    # Restaure UNIQUEMENT les entrées de sauvegarde listées (restauration sélective).
    param([Parameter(Mandatory)][string[]]$Cles)
    if ($script:Simulation) { Write-Simu "restaurerait $(@($Cles).Count) entrée(s) sélectionnée(s)"; return @{ OK = 0; Echecs = 0 } }
    $script:SauvegardeActive = $false
    $ok = 0; $echecs = 0
    try {
        foreach ($cle in $Cles) {
            if (-not $script:Sauvegarde.ContainsKey($cle)) { continue }
            try { Restore-UneEntree $script:Sauvegarde[$cle] | Out-Null; $ok++ }
            catch { Write-Etat "Échec sur $cle : $($_.Exception.Message)" -Niveau Echec; $echecs++ }
        }
    }
    finally { $script:SauvegardeActive = $true }
    Write-Etat "$ok entrée(s) restaurée(s), $echecs échec(s)." -Niveau Info
    return @{ OK = $ok; Echecs = $echecs }
}

# ------------------------------------------------------------------------------
# MODE SIMULATION
# Règle du jeu : AUCUNE modification du système ne doit exister ailleurs que
# derrière un de ces points de passage. Le registre passe par Set-RegValue /
# Remove-RegValue / Remove-RegKey, les .exe par Invoke-Externe, et tout le reste
# (services, apps, tâches planifiées, winget...) par Invoke-Action.
# Si une action contourne ces quatre portes, la simulation ferait de vrais dégâts.
# ------------------------------------------------------------------------------
$script:Simulation = $false
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
    # sous profil (le lot s'applique sans question) et en inventaire (on ne fait
    # que recenser). Dans les deux cas, ni Clear-Host, ni décor, ni Read-Host.
    return ([bool]$script:ProfilActif -or $script:ModeInventaire)
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
        [int[]]$CodesOK = @(0)
    )
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
        Read-Host "`nAppuie sur Entrée pour revenir au menu principal"
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
    Read-Host "`nAppuie sur Entrée pour revenir au menu principal"
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
# ------------------------------------------------------------------------------
# TWEAKS DE BASE
# ------------------------------------------------------------------------------
function Menu-Tweaks-Base {
    Start-Menu -Titre "TWEAKS DE BASE"

    # Sous profil, le point de restauration est déjà proposé une seule fois par le
    # lanceur de profil : le reproposer à chaque menu traversé serait pénible.
    # En inventaire, personne ne peut répondre -- et il n'y a rien à protéger,
    # puisqu'on ne fait que recenser.
    if (-not (Test-SansInteraction) -and -not (Confirmer-Filet-Securite)) { return }

    Invoke-Tweak "Désactiver la télémétrie Windows, l'ID pub et les suggestions ?" -Cle "telemetrie" `
        -Explication "Windows envoie régulièrement à Microsoft des données sur ton usage du PC, et se sert d'un identifiant publicitaire pour te cibler. Ce réglage coupe les deux, et retire les « suggestions » du menu Démarrer et des paramètres. Sur Windows Famille, la télémétrie descend au niveau minimal autorisé (Requis) mais ne peut pas être coupée totalement : seul Windows Entreprise le permet." {
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry" -Value 0
        if ($script:EstFamille) {
            # Le niveau 0 (Sécurité) n'existe que sur Entreprise/Éducation. Sur Famille,
            # Windows plafonne à 1 (Requis) quoi qu'on écrive : autant le dire.
            Write-Etat "Sur Windows Famille, la télémétrie descend au niveau 1 (Requis), pas 0 (Sécurité) : le 0 est ignoré." -Niveau Avert
        }
        $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        foreach ($v in @("SoftLandingEnabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-310093Enabled", "SystemPaneSuggestionsEnabled")) {
            Set-RegValue -Path $cdm -Name $v -Value 0
        }
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 0
    }

    Invoke-Tweak "Désinstaller radicalement Microsoft OneDrive ?" -Cle "desinstaller-onedrive" `
        -Explication "Désinstalle complètement Microsoft OneDrive du système, arrête son exécution et nettoie ses fichiers d'installation." {
        Invoke-Action "arrêterait le processus OneDrive" {
            Stop-Process -Name "OneDrive" -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
        }
        $trouve = $false
        foreach ($exe in @("$env:SystemRoot\System32\OneDriveSetup.exe", "$env:SystemRoot\SysWOW64\OneDriveSetup.exe")) {
            if (Test-Path $exe) {
                $trouve = $true
                Invoke-Externe -Fichier $exe -Arguments @("/uninstall") -CodesOK @(0, 1, -2147219813)
            }
        }
        if (-not $trouve) { throw "OneDriveSetup.exe introuvable : OneDrive est peut-être déjà désinstallé." }
    }

    Invoke-Tweak "Enlever les Widgets, l'icône Chat et couper Bing dans le menu Démarrer ?" -Cle "widgets-chat" `
        -Explication "Retire de la barre des tâches le panneau Widgets (météo et actualités) et l'icône Chat/Teams, et empêche le menu Démarrer d'envoyer ce que tu tapes à Bing pour te proposer des résultats web. Tu gardes la recherche locale de tes fichiers et de tes applications." {
        # V3 : le chemin était HKCU:\...\CurrentVersion\Advanced -> cette clé N'EXISTE PAS.
        # Le bon chemin passe par \Explorer\ ; c'est pour ça que ce tweak ne faisait rien.
        $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-RegValue -Path $adv -Name "TaskbarDa" -Value 0
        Set-RegValue -Path $adv -Name "TaskbarMn" -Value 0
        Set-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions" -Value 1
    }

    Invoke-Tweak "Désinstaller les Bloatwares de base (TikTok, Disney+, Spotify, Météo...) ?" -Cle "bloatwares" `
        -Explication "Désinstalle les applications préinstallées que presque personne n'utilise : TikTok, Disney+, Spotify, Actualités, Météo, Solitaire, LinkedIn, Clipchamp, Skype... Elles sont retirées de ton compte ET des futurs comptes créés sur ce PC. Le Microsoft Store, Defender et le Terminal ne sont jamais touchés : les retirer casserait Windows. Tu peux tout réinstaller depuis le Store si tu changes d'avis." {
        # V3 : les noms étaient exacts ("TikTok") alors que le vrai paquet s'appelle
        # BytedancePte.Ltd.TikTok -> aucun match. On passe en jokers.
        $BloatList = @(
            "*BingNews*", "*BingWeather*", "*Clipchamp*", "*Disney*", "*SpotifyMusic*",
            "*TikTok*", "*SolitaireCollection*", "*YourPhone*", "Microsoft.People",
            "*Microsoft.GetHelp*", "*MicrosoftOfficeHub*", "*3DBuilder*", "*MixedReality.Portal*",
            "*Microsoft.Getstarted*", "*WindowsFeedbackHub*", "*BingFinance*", "*BingSports*",
            "*Microsoft.Office.OneNote*", "*Microsoft.SkypeApp*", "*Microsoft.Wallet*",
            "*Microsoft.MicrosoftStickyNotes*", "*Microsoft.Todos*", "*LinkedIn*",
            "*Microsoft.OutlookForWindows*", "*Microsoft.Copilot*", "*Microsoft.549981C3F5F10*"
        )
        # NB : Microsoft.549981C3F5F10 = l'ancienne app Cortana.
        # Volontairement ABSENTS de cette liste, car les retirer casse Windows :
        # *WindowsStore* (plus aucun moyen d'installer d'apps), *SecHealthUI* (interface
        # de Defender), *WindowsTerminal*, *DesktopAppInstaller* (c'est winget lui-même).
        # GARDE-FOU : on lit le catalogue UNE fois, en erreur bloquante, avant de
        # conclure quoi que ce soit. Objectif : ne jamais confondre "aucun bloatware
        # n'est installé" et "je n'ai pas réussi à regarder".
        # (Mesuré : en PS7 l'échec de -AllUsers remonte déjà comme erreur terminante
        # et serait attrapé de toute façon ; mais ça dépend de l'édition de PowerShell
        # et des sémantiques d'erreur. Ce garde-fou rend le comportement explicite
        # au lieu de reposer sur un détail d'implémentation.)
        try { $catalogue = @(Get-AppxPackage -AllUsers -ErrorAction Stop) }
        catch {
            throw "Impossible de lire la liste des paquets installés : $($_.Exception.Message). Sans cette lecture, impossible d'affirmer quoi que ce soit sur les bloatwares. Rien n'a été tenté. Vérifie que le script tourne bien en administrateur."
        }
        if ($catalogue.Count -eq 0) {
            throw "Le catalogue des paquets est revenu vide, ce qui est impossible sur un Windows fonctionnel : la lecture n'est pas fiable, on s'arrête plutôt que de conclure à tort."
        }
        Write-Etat "$($catalogue.Count) paquets installés lus. Recherche des $($BloatList.Count) bloatwares ciblés..." -Niveau Info

        $supprimes = 0
        foreach ($App in $BloatList) {
            $paquets = @($catalogue | Where-Object { $_.Name -like $App })
            foreach ($p in $paquets) {
                try {
                    Invoke-Action "désinstallerait le paquet $($p.Name)" { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop }
                    if (-not $script:Simulation) { Write-Etat "Supprimé : $($p.Name)" -Niveau OK }
                    $supprimes++
                }
                catch { Write-Etat "Non supprimé : $($p.Name) ($($_.Exception.Message))" -Niveau Avert }
            }
            Get-AppxProvisionedPackage -Online | Where-Object { $_.DisplayName -like $App } |
                ForEach-Object {
                    try {
                        Invoke-Action "retirerait $($_.DisplayName) des futurs comptes (paquet provisionné)" { Remove-AppxProvisionedPackage -Online -PackageName $_.PackageName -ErrorAction Stop | Out-Null }
                        if (-not $script:Simulation) { Write-Etat "Retiré des futurs comptes : $($_.DisplayName)" -Niveau OK }
                    }
                    catch { }
                }
        }
        # On peut maintenant affirmer ceci, puisqu'on a VRAIMENT lu le catalogue.
        if ($supprimes -eq 0) { Write-Etat "Vérifié : aucun de ces bloatwares n'était installé. Rien à faire." -Niveau Info }
    }

    Invoke-Tweak "Désinstaller les apps OEM et Xbox (Dolby, Xbox, Family Safety, Lien avec le téléphone) ?" -Cle "apps-oem" `
        -Explication "Liste séparée de la précédente parce qu'elle est discutable : garde Xbox si tu utilises le Game Pass, et Dolby si ton portable a un vrai matériel audio Dolby Atmos (sinon tu perdrais du son). « Lien avec le téléphone » sert à recevoir SMS et notifications Android sur le PC." {
        # Liste séparée car discutable : garde Xbox si tu utilises le Game Pass,
        # garde Dolby si ton portable a un DAC Dolby Atmos.
        $Optionnels = @("*DolbyAccess*", "*Microsoft.GamingApp*", "*Xbox.TCUI*",
                        "*XboxSpeechToTextOverlay*", "*MicrosoftFamily*", "*CrossDevice*")
        try { $catalogue = @(Get-AppxPackage -AllUsers -ErrorAction Stop) }
        catch { throw "Impossible de lire la liste des paquets : $($_.Exception.Message). Rien n'a été tenté." }

        $n = 0
        foreach ($App in $Optionnels) {
            foreach ($p in @($catalogue | Where-Object { $_.Name -like $App })) {
                try {
                    Invoke-Action "désinstallerait le paquet $($p.Name)" { Remove-AppxPackage -Package $p.PackageFullName -AllUsers -ErrorAction Stop }
                    if (-not $script:Simulation) { Write-Etat "Supprimé : $($p.Name)" -Niveau OK }
                    $n++
                }
                catch { Write-Etat "Non supprimé : $($p.Name) ($($_.Exception.Message))" -Niveau Avert }
            }
        }
        if ($n -eq 0) { Write-Etat "Vérifié : aucune de ces apps n'était installée." -Niveau Info }
    }

    Fin-De-Menu -RedemarrerExplorateur
}

# ------------------------------------------------------------------------------
# TWEAKS AVANCÉS
# ------------------------------------------------------------------------------
function Menu-Tweaks-Avances {
    Start-Menu -Titre "TWEAKS AVANCÉS"

    Invoke-Tweak "Restaurer l'ancien menu clic droit classique de Windows 10 ?" -Cle "clic-droit-classique" `
        -Explication "Windows 11 a remplacé le menu du clic droit par une version courte, qui cache la moitié des options derrière « Afficher plus d'options ». Ce réglage rétablit le menu complet de Windows 10, d'un seul coup. Il faut redémarrer l'Explorateur (proposé en fin de menu) pour le voir." {
        # On sauvegarde la CLSID PARENTE, pas la seule InprocServer32 : annuler ce
        # tweak veut dire faire disparaître toute l'arborescence. Une InprocServer32
        # qui subsisterait sans sa valeur par défaut laisserait le clic droit dans
        # un état bâtard que Windows n'a jamais produit lui-même.
        $racine = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
        Save-EtatCle -Path $racine
        Set-RegValue -Path "$racine\InprocServer32" -Name "(Default)" -Value "" -Type String
    }

    Invoke-Tweak "Désactiver les animations visuelles des fenêtres (plus réactif) ?" -Cle "animations" `
        -Explication "Supprime les animations d'ouverture, de fermeture et de réduction des fenêtres. Rien ne va plus vite en réalité, mais tout RÉPOND plus vite : tu n'attends plus la fin de l'animation. C'est surtout net sur une machine modeste." {
        Set-RegValue -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" `
            -Value ([byte[]](0x90, 0x12, 0x03, 0x80, 0x10, 0x00, 0x00, 0x00)) -Type Binary
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Value 0
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "EnableAeroPeek" -Value 0
    }

    Invoke-Tweak "Désinstaller complètement Microsoft Edge ? (souvent bloqué par Microsoft, et Edge peut revenir via Windows Update)" -Cle "desinstaller-edge" `
        -Explication "Désinstalle complètement Microsoft Edge. Note : Microsoft a tendance à le réinstaller lors de mises à jour majeures." {
        $base = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application"
        if (-not (Test-Path $base)) { throw "Edge n'est pas installé à l'emplacement attendu." }
        # V3 : Get-Item avec joker pouvait renvoyer PLUSIEURS setup.exe -> Start-Process plantait.
        $setup = Get-ChildItem -Path $base -Filter "setup.exe" -Recurse -ErrorAction SilentlyContinue |
            Sort-Object { [version]$_.VersionInfo.FileVersion } -Descending | Select-Object -First 1
        if (-not $setup) { throw "setup.exe d'Edge introuvable." }
        Invoke-Externe -Fichier $setup.FullName -Arguments @("--uninstall", "--system-level", "--force-uninstall") -CodesOK @(0, 19, 20)
    }

    Invoke-Tweak "Libérer la bande passante bridée par Windows (QoS Packet Scheduler) ?" -Cle "qos" `
        -Explication "Windows réserve par défaut 20 % de ta bande passante à du trafic dit prioritaire, que presque aucune application n'utilise. Ce réglage lève cette réserve. Le gain est réel mais modeste : ne t'attends pas à doubler ton débit." {
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" -Name "NonBestEffortLimit" -Value 0
    }

    Invoke-Tweak "Désactiver le service de rapport d'erreurs Windows (WerSvc) ?" -Cle "wer" `
        -Explication "Le service de rapport d'erreurs collecte les détails des plantages et propose de les envoyer à Microsoft. Le couper libère un peu de mémoire et cesse ces envois. En échange, tu perds les rapports qui servent parfois à comprendre un plantage qui revient." {
        Set-ServiceEtat -Nom "WerSvc" -Demarrage Disabled -Arreter
    }

    Invoke-Tweak "Forcer Windows à tuer instantanément les applications qui ne répondent plus ?" -Cle "tuer-applis-figees" `
        -Explication "Quand une application ne répond plus, Windows attend plusieurs secondes avant de proposer de la fermer. Ce réglage raccourcit fortement cette attente et ferme les applications figées à l'extinction du PC. Revers : une application simplement LENTE (un gros enregistrement en cours) sera tuée plus vite, avec un risque de perdre ton travail." {
        # Ces trois valeurs sont des REG_SZ (chaînes), pas des DWord : c'est voulu.
        Set-RegValue -Path "HKCU:\Control Panel\Desktop" -Name "AutoEndTasks" -Value "1" -Type String
        Set-RegValue -Path "HKCU:\Control Panel\Desktop" -Name "WaitToKillAppTimeout" -Value "2000" -Type String
        Set-RegValue -Path "HKCU:\Control Panel\Desktop" -Name "HungAppTimeout" -Value "1000" -Type String
    }

    # --- Gestion de la mémoire (le libellé du menu promettait "RAM") ---

    # Le besoin de redémarrage n'est plus annoncé à la main dans chaque tweak :
    # -Redemarrage le fait remonter dans le bilan cumulé de fin de session.
    Invoke-Tweak "Garder le noyau Windows en RAM au lieu de l'envoyer dans le fichier d'échange ? (nécessite au moins 8 Go)" -Cle "noyau-en-ram" `
        -Explication "Empêche Windows d'envoyer le coeur du système dans le fichier d'échange sur le disque, pour le garder en mémoire vive. Améliore la réactivité si tu as de la RAM à revendre. Refusé automatiquement en dessous de 8 Go, où ce serait contre-productif." -Redemarrage {
        $ramGo = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB, 1)
        if ($ramGo -lt 8) { throw "Seulement $ramGo Go de RAM détectés : ce réglage dégraderait les performances. Ignoré." }
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisablePagingExecutive" -Value 1
        Write-Etat "$ramGo Go de RAM détectés." -Niveau Info
    }

    Invoke-Tweak "Remettre le fichier d'échange en gestion automatique par Windows ? (répare un pagefile mal réglé)" -Redemarrage {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem
        if ($cs.AutomaticManagedPagefile) { throw "Le fichier d'échange est déjà géré automatiquement : rien à changer." }
        Invoke-Action "remettrait le fichier d'échange en gestion automatique" { Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $true } }
    }

    Invoke-Tweak "Arrêter d'horodater chaque fichier à sa lecture (NTFS last access) ? (accélère les gros dossiers)" -Cle "ntfs-lastaccess" `
        -Explication "Par défaut, Windows note la date et l'heure à chaque LECTURE de fichier : il écrit sur le disque même quand tu ne fais que consulter. Le couper accélère la navigation dans les gros dossiers. Attention : si tu utilises une sauvegarde incrémentale basée sur la date d'accès, elle sera faussée." {
        # Actuellement à 2 = "géré par le système, horodatage ACTIVÉ". 1 = désactivé.
        # Attention : certains outils de sauvegarde incrémentale s'appuient dessus.
        Invoke-Externe -Fichier "fsutil.exe" -Arguments @("behavior", "set", "disablelastaccess", "1")
        Write-Etat "Si tu utilises une sauvegarde incrémentale basée sur la date d'accès, annule ce tweak." -Niveau Avert
    }

    Invoke-Tweak "Lever la limite des 260 caractères sur les chemins de fichiers (LongPaths) ?" -Cle "longpaths" `
        -Explication "Lève la vieille limite des 260 caractères sur les chemins de fichiers. Utile si tu croises des erreurs « chemin trop long » en copiant des dossiers profonds. Sans revers : les applications qui ne savent pas gérer les chemins longs continuent simplement comme avant." -Redemarrage {
        # Déjà à 1 sur certaines machines ; sur une installation neuve, non.
        # C'est justement pour ça qu'il est proposé plutôt qu'omis.
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1
    }

    Invoke-Tweak "Activer 'sudo' pour Windows ? (élever une commande sans rouvrir un terminal admin)" -Cle "sudo" `
        -Explication "Active la commande « sudo » de Windows (24H2 et plus), qui élève une seule commande sans rouvrir un terminal administrateur. Configurée en mode « inline » : la commande élevée s'exécute dans ton terminal courant. Usage : sudo <commande>." {
        $sudo = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo"
        if (-not (Test-Path $sudo)) { throw "Sudo n'existe pas sur cette version de Windows (24H2+ requis)." }
        # 3 = "inline" : la commande élevée s'exécute dans le terminal courant.
        # (0 = désactivé, 1 = nouvelle fenêtre, 2 = entrée désactivée, 3 = inline)
        Set-RegValue -Path $sudo -Name "Enabled" -Value 3
        Write-Etat "Utilisation : sudo <commande> depuis un terminal normal." -Niveau Info
    }

    Invoke-Tweak "Désactiver le Démarrage Rapide (Fast Startup) ?" -Cle "demarrage-rapide" `
        -Explication "Désactive le démarrage rapide pour forcer Windows à s'éteindre complètement à chaque arrêt. Évite les corruptions d'état de pilotes et résout les problèmes d'extinction complète (par exemple, ventilateurs qui continuent de tourner)." {
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 0
    }

    Invoke-Tweak "Ajouter l'option « Prendre possession » (Take Ownership) au menu clic droit ?" -Cle "clic-droit-possession" `
        -Explication "Ajoute une option « Prendre possession » dans le menu contextuel du clic droit sur les fichiers et dossiers pour s'attribuer facilement les droits de modification dessus." {
        # Fichiers
        $fShell = "HKLM:\SOFTWARE\Classes\*\shell\TakeOwnership"
        Set-RegValue -Path $fShell -Name "(default)" -Value "Prendre possession" -Type String
        Set-RegValue -Path $fShell -Name "HasLUAShield" -Value "" -Type String
        $fCmd = "HKLM:\SOFTWARE\Classes\*\shell\TakeOwnership\command"
        Set-RegValue -Path $fCmd -Name "(default)" -Value 'cmd.exe /c takeown /f "%1" && icacls "%1" /grant *S-1-5-32-544:F' -Type String

        # Dossiers
        $dShell = "HKLM:\SOFTWARE\Classes\Directory\shell\TakeOwnership"
        Set-RegValue -Path $dShell -Name "(default)" -Value "Prendre possession" -Type String
        Set-RegValue -Path $dShell -Name "HasLUAShield" -Value "" -Type String
        $dCmd = "HKLM:\SOFTWARE\Classes\Directory\shell\TakeOwnership\command"
        Set-RegValue -Path $dCmd -Name "(default)" -Value 'cmd.exe /c takeown /f "%1" /r /d y && icacls "%1" /grant *S-1-5-32-544:F /t /c' -Type String
    }

    Invoke-Tweak "Activer l'isolation des processus de l'Explorateur (SeparateProcess) ?" -Cle "explorer-separate-process" `
        -Explication "Configure l'Explorateur Windows pour ouvrir chaque dossier dans un processus système séparé. Améliore la stabilité : si une fenêtre de dossier plante ou se fige, elle n'entraîne pas le plantage de la barre des tâches ni du bureau." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "SeparateProcess" -Value 1
    }

    Invoke-Tweak "Désactiver les alertes d'espace disque faible ?" -Cle "disable-low-disk-warning" `
        -Explication "Désactive les notifications récurrentes de Windows signalant qu'un de tes disques ou partitions de stockage est presque plein. Pratique pour les disques de stockage que tu souhaites remplir volontairement." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoLowDiskSpaceChecks" -Value 1
    }

    Invoke-Tweak "Désactiver l'écran de verrouillage de transition (Lock Screen) ?" -Cle "disable-lock-screen" `
        -Explication "Désactive l'écran d'accueil d'accueil et de verrouillage (Lock Screen) au démarrage et lors du verrouillage pour afficher directement l'écran de connexion et de saisie du mot de passe." {
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreen" -Value 1
    }

    Invoke-Tweak "Réduire le temps d'attente à l'arrêt du PC (Kill Timeouts) ?" -Cle "kill-timeouts" `
        -Explication "Configure Windows pour fermer et tuer beaucoup plus rapidement (2 secondes au lieu de 20) les applications et les services récalcitrants ou figés qui bloquent ou ralentissent l'arrêt de la machine." {
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "WaitToKillServiceTimeout" -Value "2000" -Type String
        Set-RegValue -Path "HKCU:\Control Panel\Desktop" -Name "WaitToKillAppTimeout" -Value "2000" -Type String
        Set-RegValue -Path "HKCU:\Control Panel\Desktop" -Name "HungAppTimeout" -Value "2000" -Type String
    }

    Invoke-Tweak "Redémarrer automatiquement l'Explorateur après un crash (AutoRestartShell) ?" -Cle "auto-restart-shell" `
        -Explication "Force Windows à relancer automatiquement le processus de l'Explorateur de fichiers (barre des tâches, bureau) s'il plante ou s'arrête de manière imprévue, évitant de se retrouver bloqué face à un écran noir." {
        Set-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoRestartShell" -Value 1
    }

    # NOTE : le tweak "LargeSystemCache = 1" que l'on voit partout n'est PAS inclus.
    # Il est prévu pour les serveurs de fichiers ; sur un poste de travail Microsoft
    # recommande de le laisser à 0. L'ajouter serait le même genre de placebo que
    # le "vidage de la standby list" de la V3.

    Fin-De-Menu -RedemarrerExplorateur
}

# ------------------------------------------------------------------------------
# EXPLORATEUR & VIE PRIVÉE
# ------------------------------------------------------------------------------
function Menu-Explorateur-Prive {
    Start-Menu -Titre "EXPLORATEUR DE FICHIERS & CONFIGURATION PRIVÉE"

    Invoke-Tweak "Masquer 'Fichiers récents' et 'Dossiers fréquents' de l'Accueil de l'Explorateur ?" -Cle "explorateur-accueil" `
        -Explication "Masque les listes « Fichiers récents » et « Dossiers fréquents » qui s'affichent à l'ouverture de l'Explorateur. Utile si quelqu'un d'autre peut voir ton écran : ces listes racontent ce que tu as ouvert récemment." {
        $exp = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"
        Set-RegValue -Path $exp -Name "ShowRecent" -Value 0
        Set-RegValue -Path $exp -Name "ShowFrequent" -Value 0
    }

    Invoke-Tweak "Afficher par défaut les extensions de fichiers (.txt, .exe, .ps1) ?" -Cle "extensions-fichiers" `
        -Explication "Affiche la vraie extension de chaque fichier (.txt, .exe, .ps1). Windows les masque par défaut, ce qui permet à « photo.jpg.exe » de se faire passer pour une image. C'est autant un réglage de confort que de sécurité." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "HideFileExt" -Value 0
    }

    Invoke-Tweak "Désactiver les tâches planifiées de collecte de données clients (Telemetry Tasks) ?" -Cle "taches-telemetrie" `
        -Explication "Désactive les tâches planifiées qui collectent des données d'usage en arrière-plan (Compatibility Appraiser, Customer Experience Improvement Program, UsbCeip). Elles tournent périodiquement sans rien t'apporter. Leurs noms changent d'une version de Windows à l'autre : le script les retrouve à l'exécution plutôt que de deviner." {
        $taches = @(Get-TachesTelemetrie)
        if ($taches.Count -eq 0) {
            throw "Aucune des tâches de collecte connues n'existe sur ce build de Windows. Rien à désactiver (ou Microsoft les a de nouveau renommées : voir Get-TachesTelemetrie)."
        }
        $ko = @()
        foreach ($t in $taches) {
            try { Invoke-Action "désactiverait la tâche planifiée $($t.TaskPath)$($t.TaskName)" { Disable-ScheduledTask -InputObject $t -ErrorAction Stop | Out-Null } }
            catch { $ko += $t.TaskName }
        }
        if ($ko.Count -eq $taches.Count) { throw "Les $($taches.Count) tâches trouvées ont toutes refusé d'être désactivées (verrouillées par une stratégie ?)." }
        if ($ko.Count -gt 0) { Write-Etat "Tâches verrouillées : $($ko -join ', ')" -Niveau Avert }
        # On nomme ce qui a VRAIMENT été traité : c'est la seule façon de voir qu'une
        # tâche attendue manque à l'appel après un changement de build.
        $faites = @($taches | Where-Object { $_.TaskName -notin $ko }).TaskName
        Write-Etat "$($faites.Count) tâche(s) de collecte désactivée(s) : $($faites -join ', ')" -Niveau Info
    }

    Invoke-Tweak "Désactiver l'historique du presse-papiers cloud ?" -Cle "presse-papiers" `
        -Explication "Coupe l'historique du presse-papiers (Win+V) et sa synchronisation vers tes autres appareils via ton compte Microsoft. Tout ce que tu copies — y compris des mots de passe — cesse d'être mémorisé et envoyé. Revers : Win+V ne te ressortira plus ce que tu as copié il y a dix minutes." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 0
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "AllowCrossDeviceClipboard" -Value 0
    }

    Invoke-Tweak "Couper les résultats Bing / web et les 'temps forts' dans la recherche Windows ?" -Cle "recherche-bing" `
        -Explication "La recherche du menu Démarrer envoie ce que tu tapes à Bing pour te montrer des résultats web et des « temps forts ». Ce réglage coupe tout ça : la recherche redevient purement locale, plus rapide, et ne quitte plus ton PC." {
        # On reste sur les réglages UTILISATEUR : les stratégies "Windows Search" de
        # HKLM sont réservées à Pro+ et seraient sans effet sur cette édition Famille.
        $rech = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        Set-RegValue -Path $rech -Name "BingSearchEnabled" -Value 0
        Set-RegValue -Path $rech -Name "CortanaConsent" -Value 0
        $param = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
        Set-RegValue -Path $param -Name "IsDynamicSearchBoxEnabled" -Value 0    # "temps forts" de la recherche
        Set-RegValue -Path $param -Name "IsMSACloudSearchEnabled" -Value 0      # recherche dans OneDrive perso
        Set-RegValue -Path $param -Name "IsDeviceSearchHistoryEnabled" -Value 0
    }

    Invoke-Tweak "Arrêter de partager tes mises à jour Windows avec d'autres PC sur Internet (Delivery Optimization) ?" -Cle "delivery-optimization" `
        -Explication "Par défaut, ton PC HÉBERGE des morceaux de mises à jour Windows et les envoie à des inconnus sur Internet, en consommant ton débit montant. Ce réglage arrête ce partage : les mises à jour viennent uniquement des serveurs Microsoft." {
        # Source : Microsoft Learn, DeliveryOptimization Policy CSP.
        # 0 = HTTP seul, aucun échange pair-à-pair. Ton PC cesse d'héberger et
        # d'envoyer des bouts de mises à jour à des inconnus.
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Value 0
    }

    Invoke-Tweak "Désactiver la lecture automatique des clés USB et disques externes (AutoPlay) ?" -Cle "autoplay" `
        -Explication "Empêche Windows d'exécuter ou d'ouvrir automatiquement le contenu d'une clé USB ou d'un disque externe dès son branchement. C'est du confort, mais surtout la fermeture d'une voie d'infection classique par clé USB piégée." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name "DisableAutoplay" -Value 1
        Write-Etat "Réduit aussi le risque d'exécution automatique depuis une clé USB piégée." -Niveau Info
    }

    # --- Confidentialité approfondie ---

    Invoke-Tweak "Désactiver l'historique d'activité et son envoi à Microsoft (Timeline) ?" -Cle "historique-activite" `
        -Explication "Windows tient un historique de ce que tu as ouvert (la « Timeline ») et peut l'envoyer à ton compte Microsoft. Ce réglage coupe les trois étages d'un coup : la fonction, la collecte locale et l'envoi. La plupart des guides n'en désactivent qu'un et laissent les autres actifs." {
        # Les trois valeurs vont ensemble : la première coupe la fonction, la deuxième
        # la collecte locale, la troisième l'envoi vers le compte Microsoft. N'en poser
        # qu'une (ce que font la plupart des guides) laisse les autres actives.
        $sys = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        Set-RegValue -Path $sys -Name "EnableActivityFeed" -Value 0
        Set-RegValue -Path $sys -Name "PublishUserActivities" -Value 0
        Set-RegValue -Path $sys -Name "UploadUserActivities" -Value 0
    }

    Invoke-Tweak "Désactiver les 'expériences personnalisées' basées sur tes données de diagnostic ?" -Cle "experiences-personnalisees" `
        -Explication "Empêche Microsoft de se servir de tes données de diagnostic pour te suggérer des astuces, des pubs et des applications personnalisées dans Windows. C'est le réglage de portée utilisateur, le seul réellement honoré sur toutes les éditions, Famille comprise." {
        # Portée utilisateur : c'est celle qui est réellement honorée sur toutes les
        # éditions, y compris Famille. L'équivalent HKLM (CloudContent) ne l'est pas.
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 0
    }

    Invoke-Tweak "Ne plus jamais demander d'avis (Feedback Windows) ?" -Cle "feedback" `
        -Explication "Windows te demande périodiquement ton avis via des fenêtres surgissantes. Ce réglage lui dit de ne plus jamais demander. Aucun revers : tu peux toujours donner ton avis toi-même si tu le souhaites." {
        # 0 demande sur une période de 0 ns = Windows cesse de solliciter.
        $siuf = "HKCU:\Software\Microsoft\Siuf\Rules"
        Set-RegValue -Path $siuf -Name "NumberOfSIUFInPeriod" -Value 0
        Set-RegValue -Path $siuf -Name "PeriodInNanoSeconds" -Value 0
    }

    Invoke-Tweak "Arrêter la collecte de ta frappe et de ton écriture manuscrite (personnalisation de la saisie) ?" -Cle "saisie-personnalisation" `
        -Explication "Windows analyse ce que tu tapes et écris à la main pour améliorer ses suggestions, et collecte les noms de tes contacts. Ce réglage arrête cette collecte. En échange, les suggestions de saisie et la reconnaissance d'écriture deviendront moins pertinentes." {
        $ip = "HKCU:\Software\Microsoft\InputPersonalization"
        Set-RegValue -Path $ip -Name "RestrictImplicitInkCollection" -Value 1
        Set-RegValue -Path $ip -Name "RestrictImplicitTextCollection" -Value 1
        Set-RegValue -Path "$ip\TrainedDataStore" -Name "HarvestContacts" -Value 0
        Set-RegValue -Path "HKCU:\Software\Microsoft\Personalization\Settings" -Name "AcceptedPrivacyPolicy" -Value 0
        Write-Etat "Les suggestions de saisie et la reconnaissance d'écriture deviendront moins pertinentes : c'est le prix de ce réglage." -Niveau Avert
    }

    Invoke-Tweak "Désactiver le service de télémétrie DiagTrack (Expériences des utilisateurs connectés) ?" -Cle "service-diagtrack" `
        -Explication "Coupe le service qui envoie effectivement la télémétrie, au lieu de simplement lui demander poliment de se limiter. C'est plus radical que le réglage de télémétrie — et c'est ce qui compte sur Windows Famille, où le niveau ne peut pas descendre à zéro. Revers : le Hub de commentaires et certains diagnostics du Support Microsoft cesseront de fonctionner." {
        # C'est LE service qui remonte la télémétrie. Le couper va plus loin que la
        # stratégie AllowTelemetry, qui sur Famille est de toute façon plafonnée à 1.
        Set-ServiceEtat -Nom "DiagTrack" -Demarrage Disabled -Arreter
        Write-Etat "Le Hub de commentaires et certains diagnostics du Support Microsoft cesseront de fonctionner." -Niveau Avert
    }

    Invoke-Tweak "Ne plus envoyer d'échantillons de fichiers à Microsoft Defender ?" -Cle "defender-echantillons" `
        -Explication "Defender envoie par défaut des fichiers suspects à Microsoft pour analyse — donc potentiellement TES fichiers. Ce réglage arrête cet envoi. Important : la protection cloud de Defender reste ACTIVE. Ta sécurité n'est pas réduite, seul le partage de tes fichiers l'est." {
        # 2 = « ne jamais envoyer ». On ne touche PAS à SpynetReporting : le couper
        # désactiverait la protection cloud de Defender, donc dégraderait ta sécurité.
        # Ici on garde la protection et on cesse seulement d'envoyer TES fichiers.
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SubmitSamplesConsent" -Value 2
        Write-Etat "La protection cloud de Defender reste ACTIVE : seul l'envoi de tes fichiers est coupé." -Niveau Info
    }

    Invoke-Tweak "Refuser la géolocalisation à toutes les applications ?" -Cle "geolocalisation" `
        -Explication "Refuse la géolocalisation à toutes les applications. À n'activer que si tu sais ce que tu perds : Météo, Cartes et « Localiser mon appareil » cesseront de fonctionner, et le fuseau horaire ne se règlera plus automatiquement en voyage." {
        Set-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Value "Deny" -Type String
        Write-Etat "Météo, Cartes et « Localiser mon appareil » cesseront de fonctionner. Le fuseau horaire automatique aussi." -Niveau Avert
    }

    # --- Tâches de fond (annoncées dans le libellé du menu, absentes du code jusqu'ici) ---

    Invoke-Tweak "Empêcher les applications du Store de tourner en arrière-plan ? (gain de RAM et de batterie)" -Cle "apps-arriere-plan" `
        -Explication "Empêche les applications du Store de tourner en arrière-plan quand tu ne les utilises pas. Gain de mémoire et de batterie, surtout sur un portable. Revers : ces applications ne recevront plus de notifications push tant que le réglage est actif." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 1
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BackgroundAppGlobalToggle" -Value 0
        # 2 = "Force Deny" : la stratégie machine verrouille le réglage pour tous les comptes.
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsRunInBackground" -Value 2
        Write-Etat "Les apps du Store ne recevront plus de notifications push tant que ce réglage est actif." -Niveau Avert
    }

    Invoke-Tweak "Bloquer l'installation automatique d'applications suggérées par le Store ?" -Cle "bloquer-sug-store" `
        -Explication "Empêche Windows et le Microsoft Store de télécharger et d'installer automatiquement des applications et jeux suggérés ou partenaires (comme Candy Crush, Spotify, TikTok...) en arrière-plan." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "SilentInstalledAppsEnabled" -Value 0
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "PreInstalledAppsEnabled" -Value 0
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" -Name "PreInstalledAppsEverywhereEnabled" -Value 0
    }

    Invoke-Tweak "Désactiver la télémétrie et les suggestions publicitaires de Microsoft Edge ?" -Cle "edge-telemetrie" `
        -Explication "Désactive la télémétrie de navigation, la personnalisation et les suggestions sponsorisées dans le navigateur Microsoft Edge pour protéger ta vie privée." {
        $edgePath = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
        Set-RegValue -Path $edgePath -Name "MetricsReportingEnabled" -Value 0
        Set-RegValue -Path $edgePath -Name "PersonalizationServicesEnabled" -Value 0
        Set-RegValue -Path $edgePath -Name "ShowRecommendationsEnabled" -Value 0
    }

    Invoke-Tweak "Désactiver la télémétrie de VS Code et de Visual Studio ?" -Cle "dev-telemetrie" `
        -Explication "Désactive l'envoi en arrière-plan des données d'utilisation, de diagnostic et d'expérience utilisateur dans VS Code (via la modification du fichier settings.json utilisateur) et dans Visual Studio (via la stratégie machine)." {
        # Visual Studio Telemetry
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\Telemetry" -Name "TurnOffTelemetry" -Value 1
        
        # VS Code Telemetry
        $vscodeSettings = "$env:APPDATA\Code\User\settings.json"
        if (Test-Path $vscodeSettings) {
            Invoke-Action "désactiverait la télémétrie dans VS Code" {
                try {
                    $json = Get-Content $vscodeSettings -Raw | ConvertFrom-Json
                    if (-not $json) { $json = @{} }
                    $json | Add-Member -NotePropertyName "telemetry.telemetryLevel" -NotePropertyValue "off" -Force
                    $json | ConvertTo-Json -Depth 10 | Set-Content $vscodeSettings -Encoding UTF8
                } catch {}
            }
        }
    }

    Invoke-Tweak "Désactiver la télémétrie de Google Chrome et Mozilla Firefox ?" -Cle "browsers-telemetrie" `
        -Explication "Désactive la télémétrie, la collecte de rapports d'utilisation et les études expérimentales intégrées dans Chrome et Firefox via des stratégies de registre machine." {
        # Chrome Telemetry
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name "MetricsReportingEnabled" -Value 0
        # Firefox Telemetry
        $ff = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
        Set-RegValue -Path $ff -Name "DisableTelemetry" -Value 1
        Set-RegValue -Path $ff -Name "DisableFirefoxStudies" -Value 1
    }

    Invoke-Tweak "Désactiver la télémétrie de Microsoft Office ?" -Cle "office-telemetrie" `
        -Explication "Désactive les retours d'expérience, les diagnostics et la télémétrie client en arrière-plan de la suite bureautique Microsoft Office." {
        Set-RegValue -Path "HKCU:\Software\Policies\Microsoft\Office\Common\ClientTelemetry" -Name "DisableTelemetry" -Value 1
        Set-RegValue -Path "HKCU:\Software\Policies\Microsoft\office\16.0\common\feedback" -Name "Enabled" -Value 0
    }

    Invoke-Tweak "Désactiver la recherche Web Bing locale dans le menu Démarrer ?" -Cle "disable-web-search-start" `
        -Explication "Désactive la recherche Bing dans le champ de recherche locale de la barre des tâches et du menu Démarrer. Évite que tout ce que tu tapes localement pour chercher une application ou un fichier ne soit envoyé en ligne à Bing." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "DisableWebSearch" -Value 1
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BingSearchEnabled" -Value 0
    }

    Invoke-Tweak "Désactiver le démarrage automatique et la télémétrie de services tiers (Google Update, Adobe) ?" -Cle "thirdparty-telemetrie" `
        -Explication "Configure les services de mise à jour et de télémétrie d'Adobe (Adobe Update, Genuine Integrity) et de Google Update pour qu'ils ne se lancent pas automatiquement en arrière-plan au démarrage du PC." {
        # Google Update
        foreach ($s in @("gupdate", "gupdatem")) {
            if (Get-Service -Name $s -ErrorAction SilentlyContinue) {
                Set-ServiceEtat -Nom $s -Demarrage Manual
            }
        }
        # Adobe services
        foreach ($s in @("AdobeARMservice", "AGSService")) {
            if (Get-Service -Name $s -ErrorAction SilentlyContinue) {
                Set-ServiceEtat -Nom $s -Demarrage Manual
            }
        }
    }

    Fin-De-Menu -RedemarrerExplorateur
}

# ------------------------------------------------------------------------------
# MATÉRIEL, RÉSEAU & RAM
# ------------------------------------------------------------------------------
function Menu-Materiel-Cpu {
    Start-Menu -Titre "OPTIMISATION DU MATÉRIEL, DU RÉSEAU ET DE LA RAM" -Couleur Green

    Invoke-Tweak "Désactiver la télémétrie cachée de la carte graphique NVIDIA ?" -Cle "nvidia-telemetrie" `
        -Explication "Le pilote NVIDIA installe un service et des tâches planifiées qui remontent des données d'usage à NVIDIA. Ni le pilote ni tes jeux n'en ont besoin. Sans effet si tu n'as pas de carte NVIDIA." {
        $svc = Get-Service -Name "NvTelemetryContainer" -ErrorAction SilentlyContinue
        if (-not $svc) { throw "Service NvTelemetryContainer absent (pas de pilote NVIDIA, ou télémétrie déjà retirée)." }
        Set-ServiceEtat -Nom "NvTelemetryContainer" -Demarrage Disabled -Arreter
        Invoke-Action "désactiverait les tâches planifiées NVIDIA (NvTmRep*)" {
            Get-ScheduledTask -TaskPath "\NvTmRep*" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
        }
    }

    # V3 : cette option prétendait vider la "standby list" via ClearPageFileAtShutdown=0.
    # Les deux n'ont aucun rapport, et 0 est déjà la valeur par défaut : c'était un no-op total.
    # Vider réellement la standby list demande un outil externe (RAMMap / EmptyStandbyList).
    # On la remplace par un réglage réel qui, lui, agit sur les saccades.
    Invoke-Tweak "Désactiver SysMain / Superfetch ? (utile sur SSD - à ÉVITER sur disque dur mécanique)" -Cle "sysmain" `
        -Explication "SysMain (ex-Superfetch) précharge en mémoire les applications qu'il pense que tu vas ouvrir. Sur SSD, ce travail de devinette ne sert plus à rien et provoque parfois des saccades. Sur DISQUE DUR mécanique en revanche il aide vraiment : le script vérifie ton disque système et refuse le réglage si c'est un disque dur." {
        # Le libellé disait « à éviter sur disque dur » et s'en remettait à toi. Ça
        # suffit quand tu lis la question ; ça ne suffit plus depuis qu'un PROFIL peut
        # appliquer ce tweak sans que personne ne lise. On vérifie donc nous-mêmes.
        # On cible le disque QUI PORTE Windows et pas « un SSD quelque part dans la
        # machine » : un PC avec SSD système + HDD de données doit passer, et un HDD
        # système + SSD secondaire doit être refusé.
        $type = $null
        try {
            $disque = Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop | Get-Disk -ErrorAction Stop
            $type = (Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq $disque.Number }).MediaType
        }
        catch { }

        if ($type -eq 'HDD') {
            throw "Le disque système est un disque dur MÉCANIQUE : SysMain y accélère réellement le chargement des applications, le couper dégraderait la machine. Refusé."
        }
        if ($type -ne 'SSD') {
            # Les disques externes et certains contrôleurs RAID renvoient 'Unspecified'.
            Write-Etat "Type du disque système indéterminé (『$type』) : impossible de confirmer qu'il s'agit d'un SSD. Vérifie-le avant de garder ce réglage." -Niveau Avert
        }
        Set-ServiceEtat -Nom "SysMain" -Demarrage Disabled -Arreter
    }

    Invoke-Tweak "Désactiver la suspension sélective des ports USB (évite les déconnexions) ?" -Cle "usb-suspension" `
        -Explication "Windows coupe l'alimentation des ports USB inactifs pour économiser l'énergie, ce qui provoque des déconnexions de souris, clavier, casque ou disque externe. Ce réglage l'en empêche. Sur un PC fixe, c'est tout bénéfice ; sur un PORTABLE, ça coûte de la batterie." {
        # V3 : écrivait dans HKLM:\SYSTEM\CurrentControlSet\Services\USB, une clé qui
        # n'existe pas sur beaucoup de machines -> tweak silencieusement sauté.
        # Le vrai levier est le plan d'alimentation, via powercfg.
        $sousGroupeUSB = "2a737441-1930-4402-8d77-b2bebba308a3"
        $parametre = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
        Invoke-Externe -Fichier "powercfg.exe" -Arguments @("/setacvalueindex", "SCHEME_CURRENT", $sousGroupeUSB, $parametre, "0")
        Invoke-Externe -Fichier "powercfg.exe" -Arguments @("/setdcvalueindex", "SCHEME_CURRENT", $sousGroupeUSB, $parametre, "0")
        Invoke-Externe -Fichier "powercfg.exe" -Arguments @("/setactive", "SCHEME_CURRENT")
    }

    Invoke-Tweak "Désactiver la recherche automatique de dossiers réseau partagés ?" -Cle "net-crawling" `
        -Explication "Empêche l'Explorateur de partir automatiquement à la recherche de dossiers partagés sur ton réseau local. Purement cosmétique : ça évite les latences à l'ouverture de l'Explorateur. Tu peux toujours accéder à tes partages en tapant leur adresse." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NoNetCrawling" -Value 1
    }

    Invoke-Tweak "Désactiver l'hibernation et libérer l'espace de hiberfil.sys ? (désactive aussi le démarrage rapide)" -Cle "hibernation" `
        -Explication "Désactive l'hibernation et supprime hiberfil.sys, un fichier caché qui pèse plusieurs Go. ATTENTION : ça désactive aussi le « démarrage rapide », donc ton PC démarrera plus lentement. Sur un portable, c'est une mauvaise idée : tu perds la mise en veille prolongée qui sauve ta session quand la batterie se vide." {
        Invoke-Externe -Fichier "powercfg.exe" -Arguments @("/hibernate", "off")
    }

    # --- Réseau : le NoNetCrawling ci-dessus est cosmétique, voici les vrais leviers ---

    Invoke-Tweak "Désactiver l'algorithme de Nagle ? (baisse la latence en jeu, peut réduire le débit en téléchargement)" -Cle "nagle" `
        -Explication "L'algorithme de Nagle regroupe les petits paquets réseau avant de les envoyer, ce qui ajoute quelques millisecondes de latence. Le désactiver aide en jeu en ligne. Revers réel : ça peut RÉDUIRE ton débit en téléchargement. À ne prendre que si la latence compte plus que le débit." {
        $base = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        if (-not (Test-Path $base)) { throw "Clé des interfaces TCP/IP introuvable." }
        # Inutile d'écrire dans les ~7 sous-clés : seules celles qui portent une adresse
        # IP correspondent à une carte réseau réellement active.
        $actives = Get-ChildItem $base | Where-Object {
            $p = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).PSObject.Properties.Name
            $p -match 'DhcpIPAddress|^IPAddress$'
        }
        if (-not $actives) { throw "Aucune interface réseau active trouvée." }
        foreach ($i in $actives) {
            Set-RegValue -Path $i.PSPath -Name "TcpAckFrequency" -Value 1
            Set-RegValue -Path $i.PSPath -Name "TCPNoDelay" -Value 1
        }
        Write-Etat "$($actives.Count) interface(s) active(s) modifiée(s)." -Niveau Info
    }

    Invoke-Tweak "Désactiver l'accélération de la souris ('précision du pointeur') ? (visée constante en jeu)" -Cle "souris-acceleration" `
        -Explication "Windows accélère le pointeur quand tu bouges la souris vite : le même geste ne donne pas toujours la même distance. Le couper rend ta visée constante, ce que veulent tous les joueurs. Prévois un temps d'adaptation : ta sensibilité en jeu va changer. Effectif à la prochaine ouverture de session." {
        # Ces trois valeurs sont des REG_SZ. MouseSpeed=0 coupe l'accélération ;
        # les seuils doivent tomber à 0 avec, sinon le réglage est incohérent.
        $m = "HKCU:\Control Panel\Mouse"
        Set-RegValue -Path $m -Name "MouseSpeed" -Value "0" -Type String
        Set-RegValue -Path $m -Name "MouseThreshold1" -Value "0" -Type String
        Set-RegValue -Path $m -Name "MouseThreshold2" -Value "0" -Type String
        Write-Etat "Effectif à la prochaine ouverture de session. Ta sensibilité en jeu changera : c'est normal." -Niveau Info
    }

    Invoke-Tweak "Désactiver le spouleur d'impression ? (ferme une surface d'attaque connue)" -Cle "spouleur" `
        -Explication "Le spouleur d'impression est une surface d'attaque connue (la famille de failles PrintNightmare) et tourne en permanence même sans imprimante. Le script vérifie d'abord qu'aucune vraie imprimante n'est installée et refuse si c'en trouve une : sans lui, plus aucune impression possible." {
        # On ne coupe pas le spouleur à l'aveugle : sans lui, plus aucune impression.
        # On vérifie donc d'abord qu'aucune vraie imprimante n'est installée.
        $vraies = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'OneNote|PDF|XPS|Fax' }
        if ($vraies) {
            throw "Des imprimantes sont installées ($(($vraies.Name) -join ', ')) : couper le spouleur les rendrait inutilisables. Refusé."
        }
        Set-ServiceEtat -Nom "Spooler" -Demarrage Disabled -Arreter
        Write-Etat "Aucune imprimante détectée. Si tu en installes une plus tard, réactive le spouleur via le menu ANNULER." -Niveau Avert
    }

    Invoke-Tweak "Désactiver LLMNR et NetBIOS ? (ferme deux surfaces d'attaque classiques du réseau local)" -Cle "llmnr-netbios" `
        -Explication "LLMNR et NetBIOS servent à retrouver des machines sur le réseau local quand le DNS échoue. Ils sont exploités par des attaques classiques d'usurpation en réseau local (type Responder), et un PC domestique avec un DNS qui marche n'en a aucun besoin. Revers : si tu accèdes à un vieux NAS ou à un partage par son nom et que ça casse, annule ce réglage." {
        # LLMNR et NetBIOS servent à résoudre des noms sur le réseau local quand le DNS
        # échoue. Ils sont exploités par les attaques de type relais/empoisonnement
        # (Responder). Sur un PC domestique avec un DNS qui marche, ils ne servent à rien.
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -Value 0

        $nb = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces"
        if (-not (Test-Path $nb)) { throw "Clé NetBT introuvable : NetBIOS ne peut pas être désactivé ici." }
        # 2 = désactivé. (0 = suivre le DHCP, 1 = activé.)
        $n = 0
        foreach ($i in Get-ChildItem $nb) {
            Set-RegValue -Path $i.PSPath -Name "NetbiosOptions" -Value 2
            $n++
        }
        Write-Etat "$n interface(s) NetBT traitée(s)." -Niveau Info
        Write-Etat "Si tu accèdes à un vieux NAS ou un partage réseau par son nom et que ça casse, annule ce tweak." -Niveau Avert
    }

    Invoke-Tweak "Autoriser le DNS chiffré (DNS over HTTPS) ?" -Cle "doh" `
        -Explication "Autorise Windows à chiffrer tes requêtes DNS (DNS over HTTPS), pour que ton fournisseur d'accès ne voie plus en clair les sites que tu visites. Réglé sur « autorisé » et non « obligatoire » : Windows chiffre si ton serveur DNS le sait, et retombe en clair sinon. « Obligatoire » avec un DNS qui ne gère pas DoH te couperait d'Internet. Effectif seulement avec un DNS compatible (Cloudflare, Google, Quad9)." {
        # 2 = « autorisé » : Windows utilise DoH si le serveur DNS configuré le
        # supporte, et retombe en clair sinon. On n'écrit délibérément PAS 3
        # (« obligatoire ») : avec un DNS qui ne gère pas DoH, 3 te couperait
        # purement et simplement d'Internet.
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "DoHPolicy" -Value 2
        Write-Etat "Effectif seulement si ton serveur DNS gère DoH (Cloudflare 1.1.1.1, Google 8.8.8.8, Quad9...). Sinon, sans effet." -Niveau Info
    }

    Invoke-Tweak "Empêcher Windows d'éteindre la carte réseau pour économiser l'énergie ? (coupures Wi-Fi, latence)" -Cle "carte-reseau-veille" `
        -Explication "Windows éteint la carte réseau pour économiser l'énergie, ce qui cause des coupures Wi-Fi et des pics de latence. Ce réglage le lui interdit, uniquement sur tes cartes physiques (les cartes virtuelles de VPN ne sont pas touchées). Sur un PORTABLE, ça consomme de la batterie." {
        # Le réglage vit dans la classe de périphériques réseau, une sous-clé par
        # carte (0001, 0002...). On fait le lien via DriverDesc, qui correspond à
        # l'InterfaceDescription remontée par Get-NetAdapter : écrire dans toutes
        # les sous-clés toucherait aussi les cartes virtuelles (VPN, Hyper-V...).
        $cartes = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
        if ($cartes.Count -eq 0) { throw "Aucune carte réseau physique détectée." }
        $classe = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
        if (-not (Test-Path $classe)) { throw "Classe de périphériques réseau introuvable dans le registre." }

        $traitees = @()
        foreach ($sk in (Get-ChildItem $classe | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
            $desc = (Get-ItemProperty $sk.PSPath -Name "DriverDesc" -ErrorAction SilentlyContinue).DriverDesc
            if (-not $desc) { continue }
            if ($desc -notin $cartes.InterfaceDescription) { continue }
            # 24 (0x18) = interdit à Windows d'éteindre la carte et de la réveiller.
            Set-RegValue -Path $sk.PSPath -Name "PnPCapabilities" -Value 24
            $traitees += $desc
        }
        if ($traitees.Count -eq 0) { throw "Aucune carte physique n'a pu être reliée à sa clé de registre : rien n'a été modifié." }
        Write-Etat "$($traitees.Count) carte(s) traitée(s) : $($traitees -join ', ')" -Niveau Info
    }

    # NON INCLUS À DESSEIN, malgré leur popularité sur les forums :
    #  - « autotuninglevel=disabled » : l'auto-tuning TCP est justement ce qui permet
    #    d'atteindre le débit maximal sur une connexion moderne. Le couper est un
    #    conseil daté de Windows Vista qui RÉDUIT le débit aujourd'hui.
    #  - « Désactiver IPv6 » : Microsoft déconseille explicitement de le faire, et
    #    certains composants de Windows le supposent présent.

    # --- Jeu et alimentation ---

    Invoke-Tweak "Désactiver Game DVR / l'enregistrement en arrière-plan de la Game Bar ? (gain de FPS)" -Cle "game-dvr" `
        -Explication "La Game Bar enregistre ton jeu en arrière-plan en permanence, au cas où tu voudrais garder les 30 dernières secondes. Ça coûte des FPS pour une fonction que peu de gens utilisent. La Game Bar (Win+G) reste utilisable : seul l'enregistrement de fond est coupé." {
        # Le service d'enregistrement tourne en fond dès qu'un jeu est détecté.
        Set-RegValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0
        Set-RegValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Value 2
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0
        Write-Etat "La Game Bar (touche Win+G) reste utilisable, seul l'enregistrement de fond est coupé." -Niveau Info
    }

    Invoke-Tweak "Activer le plan d'alimentation caché 'Performances ultimes' ?" -Cle "plan-performances-ultimes" `
        -Explication "Ajoute le plan d'alimentation caché de Microsoft, qui interdit toute mise en veille des composants. Réservé aux PC FIXES : le script le refuse sur un portable, où Microsoft le masque à raison — il fait chauffer et vide la batterie. Une fois ajouté, il faut le sélectionner dans Paramètres > Système > Alimentation." {
        # Ce plan est masqué par Microsoft sur les machines à batterie, et pour cause :
        # il interdit toute mise en veille des composants. Sur un portable = chauffe
        # et autonomie en chute libre. On refuse plutôt que de dégrader la machine.
        $portable = $null -ne (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
        if ($portable) {
            # Le nom du plan est LU, pas supposé : ce script tourne aussi ailleurs.
            throw "Cette machine est un PC portable (batterie détectée). Microsoft masque ce plan sur les portables : il empêche toute mise en veille des composants, fait chauffer et vide la batterie. Refusé. Ton plan actuel est « $(Get-PlanAlimentationActif) »."
        }
        Invoke-Externe -Fichier "powercfg.exe" -Arguments @("-duplicatescheme", "e9a42b02-d5df-448d-aa00-03f14749eb61")
        Write-Etat "Plan ajouté. Sélectionne-le dans Paramètres > Système > Alimentation." -Niveau Info
    }

    Invoke-Tweak "Lever le bridage réseau réservé au multimédia (NetworkThrottlingIndex) ?" -Cle "bridage-multimedia" `
        -Explication "Windows bride le réseau et les priorités processeur pour réserver des ressources au multimédia, un compromis pensé pour des machines de 2008. Ce réglage lève le bridage. Utile en jeu et en streaming ; sans effet visible en usage bureautique." -Redemarrage {
        $profil = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        # 0xffffffff = throttling désactivé. On écrit [int]-1 et non 4294967295 :
        # un DWord est un entier 32 bits SIGNÉ côté PowerShell 5.1, qui refuse la
        # valeur non signée. [int]-1 produit exactement le même 0xFFFFFFFF.
        Set-RegValue -Path $profil -Name "NetworkThrottlingIndex" -Value ([int]-1)
        Set-RegValue -Path $profil -Name "SystemResponsiveness" -Value 0
        Write-Etat "Défauts Windows remplacés (ils étaient 10 et 20). Le menu ANNULER les remet." -Niveau Info
    }

    Invoke-Tweak "Désactiver la veille moderne (Modern Standby S0) et restaurer la veille classique S3 ?" -Cle "modern-standby" `
        -Explication "Force la veille classique S3 à la place de la veille moderne S0. RÉSERVÉ aux machines dont le firmware supporte VRAIMENT le S3 : sur un portable conçu pour le S0 (la plupart des ROG récents), forcer le S3 provoque des plantages au réveil et en SORTIE D'HIBERNATION. Le tweak le détecte et REFUSE alors de s'appliquer." -Redemarrage {
        # Refuse de nuire : forcer le S3 sur une plateforme à veille moderne S0 casse le
        # réveil (plantages Kernel-Power au retour de veille/hibernation -- constaté sur
        # ROG Strix 12e gen). La présence de « S0 » dans powercfg /a signe une plateforme
        # S0 ; une machine à vrai S3 ne la liste jamais.
        if (((powercfg /a) -join ' ') -match 'S0') {
            throw "Cette machine gère la veille moderne S0 : forcer le S3 y provoque des plantages au réveil et en sortie d'hibernation. Réglage ignoré (c'est volontaire)."
        }
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "PlatformAoAcOverride" -Value 0
    }

    Invoke-Tweak "Activer la planification GPU accélérée par le matériel (HAGS) ?" -Cle "hags-gpu" -Redemarrage `
        -Explication "Active la planification GPU accélérée par le matériel pour réduire la latence d'affichage et améliorer les performances dans les jeux compatibles (nécessaire pour utiliser la génération d'images Nvidia DLSS 3 / AMD FSR 3)." {
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2
    }

    Invoke-Tweak "Désactiver la télémétrie AMD Radeon Software ?" -Cle "amd-telemetrie" `
        -Explication "Désactive la télémétrie et la collecte de données analytiques d'AMD Radeon Software pour préserver ta vie privée." {
        Set-RegValue -Path "HKLM:\SOFTWARE\AMD\CN\ANALYTICS" -Name "ReportAnalytics" -Value 0
    }

    Invoke-Tweak "Désactiver l'économie d'énergie PCIe (Link State Power Management) ?" -Cle "pcie-power-management" `
        -Explication "Configure le plan d'alimentation actif pour désactiver la mise en veille PCIe Link State (PCI Express). Empêche les baisses d'alimentation des cartes graphiques et SSD NVMe pour éliminer les micro-saccades de réveil." {
        Invoke-Action "désactiverait l'économie d'énergie PCIe" {
            powercfg.exe /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a821a03c4f3d ee12f2c1-98ac-4be7-9e4c-1c778ca13c9b 0
            powercfg.exe /setdcvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a821a03c4f3d ee12f2c1-98ac-4be7-9e4c-1c778ca13c9b 0
            powercfg.exe /setactive SCHEME_CURRENT
        }
    }

    Invoke-Tweak "Désactiver les fonctions d'arrière-plan de la Xbox Game Bar ?" -Cle "xbox-gamebar" `
        -Explication "Désactive l'enregistrement en arrière-plan et l'application Xbox Game Bar pour libérer des ressources processeur et mémoire en jeu." {
        Set-RegValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0
        Set-RegValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Value 2
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0
        Set-RegValue -Path "HKCU:\Software\Microsoft\GameBar" -Name "UseNexusForGameBarEnabled" -Value 0
    }

    Invoke-Tweak "Désactiver le partage P2P des mises à jour Windows Update (Delivery Optimization) ?" -Cle "delivery-optimization-p2p" `
        -Explication "Configure Windows pour obtenir les mises à jour Windows Update directement depuis les serveurs de Microsoft (HTTP) sans utiliser ni partager ta bande passante internet en amont (upload) avec d'autres ordinateurs du réseau local ou d'internet." {
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Value 0
    }

    Invoke-Tweak "Désactiver la création des noms courts 8.3 (NTFS Performance) ?" -Cle "ntfs-performance" `
        -Explication "Désactive la génération de noms de fichiers courts au format DOS 8.3 sur le système de fichiers NTFS. Améliore les performances de lecture/écriture, surtout dans les répertoires contenant un très grand nombre de fichiers." {
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsDisable8dot3NameCreation" -Value 1
    }

    Fin-De-Menu -RedemarrerExplorateur
}

# ------------------------------------------------------------------------------
# MISES À JOUR, SÉCURITÉ & IA
# ------------------------------------------------------------------------------
# Copilot et Recall vivaient dans le switch d'un menu piloté par Read-Host, donc
# inaccessibles à un profil (qui ne peut pas répondre à une invite). Les voici en
# fonctions autonomes : le menu les appelle, les profils aussi, sans duplication.
function Invoke-TweakCopilot {
    Invoke-Tweak "Désactiver Windows Copilot ?" -Cle "copilot" `
        -Explication "Retire le bouton Copilot et pose la stratégie qui le désactive. Comme cette ancienne stratégie ne couvre pas le Copilot moderne livré depuis 24H2 (devenu une simple application du Store), le script DÉSINSTALLE aussi cette application : c'est le seul moyen fiable. Tu peux la réinstaller depuis le Store." {
        # Source : Microsoft Learn, WindowsAI Policy CSP (maj 23/06/2026).
        # TurnOffWindowsCopilot est de portée UTILISATEUR uniquement (Scope :
        # Device = non, User = oui) : écrire dans HKLM ne sert donc à rien.
        # Microsoft la marque aussi "deprecated", et elle ne couvre PAS le
        # nouveau Copilot (l'app du Store) livré depuis 24H2.
        Set-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0

        # Le seul moyen fiable contre le Copilot moderne : désinstaller l'app.
        $app = Get-AppxPackage -Name "Microsoft.Copilot" -ErrorAction SilentlyContinue
        if ($app) {
            Invoke-Action "désinstallerait l'app Microsoft.Copilot" { Remove-AppxPackage -Package $app.PackageFullName -ErrorAction Stop }
            if (-not $script:Simulation) { Write-Etat "App Copilot désinstallée." -Niveau OK }
        }
        else {
            Write-Etat "L'app Copilot n'est pas installée ici : seule l'ancienne stratégie a été posée." -Niveau Info
        }
        if ($script:EstFamille) {
            Write-Etat "Microsoft ne documente cette stratégie que pour Pro/Entreprise/Éducation : son effet sur Famille n'est pas garanti." -Niveau Avert
        }
    }
}

function Invoke-TweakRecall {
    Invoke-Tweak "Désactiver Recall et l'analyse de données par l'IA ?" -Cle "recall" `
        -Explication "Recall capture périodiquement ton écran et l'indexe pour te permettre de « remonter le temps ». Ce réglage le désactive, retire ses fichiers et supprime les captures déjà enregistrées. Sur un PC Copilot+, où Recall est une vraie fonctionnalité Windows, le composant est carrément retiré (redémarrage nécessaire)." {
        # Source : Microsoft Learn, WindowsAI Policy CSP (maj 23/06/2026).
        # DisableAIDataAnalysis est de portée Device ET User : les deux servent.
        # Requiert 24H2 build 26100.3915+ (KB5055627).
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1
        Set-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1

        # Plus radical que le précédent : met le composant Recall à l'état
        # désactivé, RETIRE ses fichiers de la machine et supprime les captures
        # déjà enregistrées. Portée Device.
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "AllowRecallEnablement" -Value 0

        # Sur les PC Copilot+, Recall est une fonctionnalité Windows à part entière :
        # la stratégie ne suffit pas, il faut retirer le composant.
        $f = Get-WindowsOptionalFeature -Online -FeatureName "Recall" -ErrorAction SilentlyContinue
        if ($f -and $f.State -eq "Enabled") {
            Invoke-Action "retirerait le composant Windows Recall" { Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -NoRestart -ErrorAction Stop | Out-Null }
            # Le besoin de redémarrage est ici CONDITIONNEL (seulement si le composant
            # était présent), ce que le switch -Redemarrage ne sait pas exprimer :
            # on l'ajoute donc à la main au bilan cumulé.
            Write-Etat "Composant Recall retiré." -Niveau Info
            $t = "Retrait du composant Windows Recall"
            if ($t -notin $script:RedemarrageRequis) { $script:RedemarrageRequis += $t }
        }
        else {
            Write-Etat "Le composant Recall n'est pas présent sur ce PC (normal hors machines Copilot+) : seule la stratégie a été posée." -Niveau Info
        }
    }
}

function Menu-Maj-Securite {
    Start-Menu -Titre "CONFIGURATION SÉCURITÉ & MISES À JOUR"

    $t1 = {
        Invoke-Tweak "Reporter les mises à jour de fonctionnalités de 365 jours (les correctifs de sécurité continuent d'arriver) ?" -Cle "update-defer" `
            -Explication "Reporte les mises à jour de fonctionnalités de 365 jours pour stabiliser le système. Les correctifs de sécurité critiques continuent d'arriver. Nécessite Windows Édition Professionnelle." {
            Assert-EditionPro -Fonction "Le report des mises à jour de fonctionnalités"
            $wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            Set-RegValue -Path $wu -Name "DeferFeatureUpdates" -Value 1
            Set-RegValue -Path $wu -Name "DeferFeatureUpdatesPeriodInDays" -Value 365
            Set-RegValue -Path $wu -Name "DeferQualityUpdates" -Value 1
            Set-RegValue -Path $wu -Name "DeferQualityUpdatesPeriodInDays" -Value 4
            Set-RegValue -Path $wu -Name "BranchReadinessLevel" -Value 20
        }
    }

    $t2 = {
        Invoke-Tweak "Désactiver totalement le service de mise à jour Windows Update ?" -Cle "update-block" `
            -Explication "Désactive et bloque totalement le service Windows Update (wuauserv). Attention : aucun correctif de sécurité ne pourra être installé." {
            Set-ServiceEtat -Nom "wuauserv" -Demarrage Disabled -Arreter
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value 1
        }
    }

    $t3 = {
        Invoke-Tweak "Restaurer les réglages Windows Update par défaut ?" -Cle "update-restore" `
            -Explication "Remet les réglages du service de mise à jour Windows Update par défaut." {
            $wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            if (Test-Path $wu) { Remove-RegKey -Path $wu }
            Set-ServiceEtat -Nom "wuauserv" -Demarrage Manual -Demarrer
        }
    }

    $t4 = {
        Invoke-Tweak "Désactiver la sécurité basée sur la virtualisation (VBS) / Isolation du noyau ?" -Cle "vbs-desactiver" -Redemarrage `
            -Explication "Désactive VBS et l'isolation du noyau pour améliorer les performances en jeu et calculs GPU. Réduit la sécurité système globale." {
            Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name "EnableVirtualizationBasedSecurity" -Value 0
            Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled" -Value 0
            Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard" -Name "Enabled" -Value 0
        }
    }

    $t5 = {
        Invoke-Tweak "Empêcher Windows Update d'installer ou de mettre à jour les pilotes ?" -Cle "update-pilotes" `
            -Explication "Empêche Windows Update d'écraser automatiquement tes pilotes matériels (comme les pilotes graphiques Nvidia/AMD) par des versions génériques ou plus anciennes de son choix. Tu devras mettre à jour tes pilotes manuellement." {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Settings" -Name "ExcludeWUDriversInQualityUpdate" -Value 1
            Set-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Value 0
        }
    }

    $t6 = {
        Invoke-Tweak "Activer les sauvegardes périodiques du Registre Windows (RegBack) ?" -Cle "regback-backup" `
            -Explication "Configure Windows pour effectuer des sauvegardes régulières et automatiques de la base de registre vers le dossier System32\config\RegBack (désactivé par défaut par Microsoft pour économiser 50 Mo de disque). Apporte une sécurité supplémentaire en cas de corruption du registre." {
            Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager" -Name "EnablePeriodicalBackup" -Value 1
        }
    }

    $t7 = {
        Invoke-Tweak "Limiter l'usage CPU de Windows Defender pendant les analyses de fichiers ?" -Cle "defender-cpu-limit" `
            -Explication "Limite l'utilisation maximale du processeur (CPU) par Windows Defender à 30% pendant ses analyses automatiques en arrière-plan. Évite les hausses de température et les ralentissements soudains pendant que tu joues ou travailles." {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan" -Name "AvgCPULimit" -Value 30
        }
    }

    if (Test-SansInteraction) {
        & $t1
        & $t2
        & $t3
        & $t4
        & $t5
        & $t6
        & $t7
        return
    }

    Write-Host " 1 - Windows Update : reporter les mises à jour de FONCTIONNALITÉS (sécurité conservée)"
    Write-Host " 2 - Windows Update : TOUT bloquer (service désactivé)" -ForegroundColor Red
    Write-Host " 3 - Windows Update : remettre les réglages par défaut"
    Write-Host " 4 - Désactiver l'Isolation du Noyau / VBS  [gain en jeu et calcul GPU]" -ForegroundColor Yellow
    Write-Host " 5 - Empêcher Windows Update d'installer/mettre à jour les pilotes" -ForegroundColor Yellow
    Write-Host " 6 - Activer les sauvegardes périodiques du Registre (RegBack)" -ForegroundColor Green
    Write-Host " 7 - Limiter l'usage CPU de Windows Defender lors des scans" -ForegroundColor Green
    Write-Host " 8 - Désactiver Windows Copilot" -ForegroundColor Yellow
    Write-Host " 9 - Désactiver Recall (les captures d'écran périodiques de l'IA)" -ForegroundColor Yellow
    Write-Host " 10 - Retour au menu principal"
    Write-Host ""

    $ChoixSec = Read-Host "Choisis une option (1-10)"
    switch ($ChoixSec) {
        "1" { & $t1 }
        "2" {
            Write-Etat "Bloquer toutes les mises à jour te prive aussi des correctifs de FAILLES DE SÉCURITÉ." -Niveau Avert
            & $t2
        }
        "3" { & $t3 }
        "4" {
            Write-Etat "VBS protège contre certaines attaques mémoire. Le désactiver = moins de sécurité." -Niveau Avert
            if (Confirmer-Filet-Securite) {
                & $t4
            }
        }
        "5" { & $t5 }
        "6" { & $t6 }
        "7" { & $t7 }
        "8" { Invoke-TweakCopilot }
        "9" {
            Write-Etat "Recall capture périodiquement ton écran et l'indexe localement." -Niveau Info
            Invoke-TweakRecall
        }
        "10" { return }
        default { Write-Etat "Choix invalide." -Niveau Avert }
    }
    Fin-De-Menu
}

# ------------------------------------------------------------------------------
# LOGICIELS EXTRA (winget)
# ------------------------------------------------------------------------------

# Le catalogue vit au niveau du module, et non dans la fonction : le menu « Clé
# d'installation » propose exactement les mêmes applications, et deux listes qui
# dérivent l'une de l'autre finiraient par ne plus dire la même chose.
$script:CatalogueApps = [ordered]@{
    # Navigateurs
    "Google Chrome"       = "Google.Chrome"
    "Mozilla Firefox"     = "Mozilla.Firefox"
    "Brave"               = "Brave.Brave"
    # Essentiels
    "7-Zip"               = "7zip.7zip"
    "VLC Media Player"    = "VideoLAN.VLC"
    "Notepad++"           = "Notepad++.Notepad++"
    "PowerToys"           = "Microsoft.PowerToys"
    "Windows Terminal"    = "Microsoft.WindowsTerminal"
    # Communication et jeu
    "Discord"             = "Discord.Discord"
    "Steam"               = "Valve.Steam"
    # --- Matériel / gaming (optionnel) : monitoring, overlay, pilotes ---
    # G-Helper : le SEUL moyen de piloter ventilateurs et modes Turbo/Silencieux ASUS
    # ROG (le driver ASUS ignore ces commandes hors de son écosystème). Léger, libre.
    "G-Helper (ventilos + modes ASUS ROG)"           = "seerge.g-helper"
    "HWiNFO (vraies températures / capteurs)"        = "REALiX.HWiNFO"
    "MSI Afterburner (courbe ventilo GPU)"           = "Guru3D.Afterburner"
    "RivaTuner Statistics Server (overlay FPS)"      = "Guru3D.RTSS"
    "Display Driver Uninstaller (MAJ pilote propre)" = "Wagnardsoft.DisplayDriverUninstaller"
    "Nilesoft Shell (menu clic droit moderne)"       = "Nilesoft.Shell"
    # Développement
    "Visual Studio Code"  = "Microsoft.VisualStudioCode"
    "Git"                 = "Git.Git"
    "PowerShell 7"        = "Microsoft.PowerShell"
    # Utilitaires
    "ShareX (captures)"   = "ShareX.ShareX"
    "Everything (recherche instantanée)" = "voidtools.Everything"
    "qBittorrent"         = "qBittorrent.qBittorrent"
    "Adobe Acrobat Reader" = "Adobe.Acrobat.Reader.64-bit"
}

function Menu-Logiciels-Extra {
    Start-Menu -Titre "LOGICIELS EXPRESS (via winget)"

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Etat "winget est introuvable. Installe 'Programme d'installation d'application' depuis le Microsoft Store." -Niveau Echec
        if (-not (Test-SansInteraction)) {
            Read-Host "`nAppuie sur Entrée pour revenir au menu principal"
        }
        return
    }

    $Catalogue = $script:CatalogueApps

    # --- Cas "nouveau PC" : transporter sa liste d'apps d'une machine à l'autre ---

    $fichierApps = Join-Path $script:DossierDonnees "mes-apps.json"

    Invoke-Tweak "EXPORTER la liste des apps installées sur ce PC (pour la réinstaller ailleurs) ?" -Cle "winget-export" `
        -Explication "Exporte la liste de toutes vos applications actuellement installées au format JSON dans le dossier de données." {
        Invoke-Action "exporterait la liste des apps vers $fichierApps" {
            winget export -o $fichierApps --accept-source-agreements 2>&1 | Out-Null
            if (-not (Test-Path $fichierApps)) { throw "winget n'a produit aucun fichier." }
            $n = (Get-Content $fichierApps -Raw | ConvertFrom-Json).Sources.Packages.Count
            Write-Etat "$n app(s) exportée(s) vers $fichierApps" -Niveau OK
            Write-Etat "Copie ce fichier sur le nouveau PC, à côté du script, puis utilise l'import." -Niveau Info
        }
    }

    Invoke-Tweak "IMPORTER et réinstaller les apps depuis un export précédent ?" -Cle "winget-import" `
        -Explication "Importe et réinstalle automatiquement vos applications à partir d'un fichier mes-apps.json d'export précédent." {
        if (-not (Test-Path $fichierApps)) {
            throw "Aucun fichier $fichierApps trouvé. Fais d'abord un export sur l'ancien PC, puis copie le fichier ici."
        }
        $n = (Get-Content $fichierApps -Raw | ConvertFrom-Json).Sources.Packages.Count
        Invoke-Action "réinstallerait les $n app(s) listées dans $fichierApps" {
            # --ignore-unavailable : une app absente du dépôt ne doit pas tout arrêter.
            winget import -i $fichierApps --accept-source-agreements --accept-package-agreements --ignore-unavailable
            Write-Etat "Import terminé (code winget : $LASTEXITCODE)." -Niveau Info
        }
    }

    Invoke-Tweak "Mettre à jour TOUTES les apps installées (winget upgrade --all) ?" -Cle "winget-upgrade-all" `
        -Explication "Met à jour automatiquement toutes les applications installées sur la machine à l'aide de winget." {
        Invoke-Action "mettrait à jour toutes les apps via winget" {
            winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
            Write-Etat "Mise à jour terminée (code winget : $LASTEXITCODE)." -Niveau Info
        }
    }

    if (-not (Test-SansInteraction)) {
        Write-Host ""
        Write-Host "  --- Ou installer à la carte : ---" -ForegroundColor DarkGray
        Write-Host ""
    }

    foreach ($nom in $Catalogue.Keys) {
        $id = $Catalogue[$nom]
        $cleApp = "winget-" + ($id -replace '[^a-zA-Z0-9]', '-').ToLower()
        # Ces 23 entrées sont GÉNÉRÉES : leur libellé ne dépend que du nom de l'appli.
        # Traduire le gabarit une fois vaut mieux que 23 entrées dans la table.
        $titreApp = if ($script:LangueActive -eq 'fr') { "Installer $nom ?" } else { "Install $nom?" }
        $explApp = if ($script:LangueActive -eq 'fr') { "Télécharge et installe le logiciel $nom via winget." }
        else { "Downloads and installs $nom using winget." }
        Invoke-Tweak $titreApp -Cle $cleApp -Explication $explApp {
            # V3 : sans --accept-*-agreements, winget pouvait rester bloqué sur un prompt,
            # et sans "-e --id" il pouvait installer un paquet homonyme.
            Invoke-Action "installerait $nom via winget (id : $id)" {
                winget install -e --id $id --silent --accept-source-agreements --accept-package-agreements | Out-Null
                # 0 = ok, -1978335189 = déjà installé / rien à faire
                if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
                    throw "winget a renvoyé le code $LASTEXITCODE."
                }
            }
        }.GetNewClosure()
    }

    Fin-De-Menu
}

# ------------------------------------------------------------------------------
# MAINTENANCE & RÉPARATION
# ------------------------------------------------------------------------------
function Menu-Maintenance {
    Start-Menu -Titre "OUTILS DE DIAGNOSTIC ET VÉRIFICATION SYSTÈME" -Couleur Green `
        -SousTitre @("Note : l'ordre correct est DISM d'abord, SFC ensuite.")

    Invoke-Tweak "Lancer DISM pour restaurer l'image de santé de Windows ? (plusieurs minutes)" -Cle "maintenance-dism" `
        -Explication "Analyse l'image système Windows pour y détecter d'éventuels dommages et la réparer en téléchargeant les fichiers sains via Windows Update (requiert Internet)." {
        Invoke-Externe -Fichier "DISM.exe" -Arguments @("/Online", "/Cleanup-Image", "/RestoreHealth")
    }

    Invoke-Tweak "Lancer un scan SFC pour réparer les fichiers système corrompus ? (plusieurs minutes)" -Cle "maintenance-sfc" `
        -Explication "Analyse l'intégralité des fichiers système protégés de Windows et remplace les versions corrompues par des copies saines." {
        # SFC renvoie 0 s'il n'y a rien à réparer OU s'il a réparé avec succès.
        Invoke-Externe -Fichier "sfc.exe" -Arguments @("/scannow")
    }

    Invoke-Tweak "Nettoyer et compresser le magasin des composants système (WinSxS) ? (plusieurs minutes)" -Cle "maintenance-winsxs-cleanup" `
        -Explication "Exécute le nettoyage DISM avec StartComponentCleanup et ResetBase. Supprime définitivement les anciennes versions des composants système obsolètes ou remplacés par des mises à jour récentes. Libère beaucoup d'espace sur C:\Windows\WinSxS mais rend les mises à jour en cours non désinstallables." {
        Invoke-Externe -Fichier "DISM.exe" -Arguments @("/Online", "/Cleanup-Image", "/StartComponentCleanup", "/ResetBase")
    }

    if (-not (Test-SansInteraction)) {
        Write-Etat "La purge des journaux efface l'historique qui sert à diagnostiquer les pannes." -Niveau Avert
    }
    Invoke-Tweak "Purger tous les journaux d'événements Windows ?" -Cle "maintenance-purger-journaux" `
        -Explication "Vide l'intégralité des journaux d'événements de l'Observateur d'événements de Windows pour libérer de l'espace." {
        if ($script:Simulation) { Write-Simu "purgerait les $(@(wevtutil el).Count) journaux d'événements Windows"; return }
        $journaux = @(wevtutil el)
        $efface = 0; $ko = 0
        foreach ($j in $journaux) {
            wevtutil cl "$j" 2>$null
            if ($LASTEXITCODE -eq 0) { $efface++ } else { $ko++ }
        }
        Write-Etat "$efface journal(aux) purgé(s), $ko protégé(s) par le système." -Niveau Info
        if ($efface -eq 0) { throw "Aucun journal n'a pu être purgé." }
    }

    Fin-De-Menu
}

# ------------------------------------------------------------------------------
# NOUVEAUTÉS WINDOWS 11 24H2 / 25H2
# Ces réglages ciblent des choses qui n'existaient pas dans les versions
# précédentes de Windows 11. Le script vérifie le build avant de les proposer.
# ------------------------------------------------------------------------------
function Menu-Windows11-Recent {
    Start-Menu -Titre "NOUVEAUTÉS WINDOWS 11 (24H2 / 25H2)" `
        -SousTitre @("Détecté : $($script:InfosOS.DisplayVersion) - build $($script:BuildOS).$($script:InfosOS.UBR) - édition $($script:InfosOS.EditionID)")

    if ($script:BuildOS -lt 22621) {
        Write-Etat "Ce menu vise Windows 11 22H2 et plus récent. Ton build ($script:BuildOS) est antérieur : rien à faire ici." -Niveau Avert
        # Sous profil ou en inventaire, personne n'est là pour appuyer sur Entrée.
        if (-not (Test-SansInteraction)) { Read-Host "`nAppuie sur Entrée pour revenir au menu principal" }
        return
    }

    Invoke-Tweak "Supprimer les publicités et 'recommandations' du menu Démarrer ? (24H2+)" -Cle "pubs-demarrer" `
        -Explication "Le menu Démarrer affiche des « recommandations » qui sont en réalité des publicités pour des applications du Store, mêlées à tes fichiers et applications récents. Ce réglage coupe les trois. La zone Recommandé se videra : vois le réglage « plus d'épingles » dans l'onglet Apparence pour récupérer la place." {
        $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-RegValue -Path $adv -Name "Start_IrisRecommendations" -Value 0   # pubs pour des apps du Store
        Set-RegValue -Path $adv -Name "Start_TrackDocs" -Value 0             # fichiers récents dans "Recommandé"
        Set-RegValue -Path $adv -Name "Start_TrackProgs" -Value 0            # apps récentes dans "Recommandé"
    }

    Invoke-Tweak "Couper les écrans de pub 'Tirez le meilleur parti de Windows' après les mises à jour ?" -Cle "pubs-scoobe" `
        -Explication "Après chaque grosse mise à jour, Windows affiche un écran plein page « Tirez le meilleur parti de Windows » qui te pousse vers Edge, Bing et OneDrive. Ce réglage l'empêche d'apparaître." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" -Name "ScoobeSystemSettingEnabled" -Value 0
        $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        Set-RegValue -Path $cdm -Name "SubscribedContent-310093Enabled" -Value 0
        Set-RegValue -Path $cdm -Name "SubscribedContent-353694Enabled" -Value 0
        Set-RegValue -Path $cdm -Name "SubscribedContent-353696Enabled" -Value 0
    }

    Invoke-Tweak "Enlever les pubs OneDrive/Store déguisées en notifications dans l'Explorateur ?" -Cle "pubs-explorateur" `
        -Explication "L'Explorateur affiche des bandeaux qui ressemblent à des notifications système mais sont des publicités pour OneDrive et Microsoft 365. Ce réglage les supprime. Si tu utilises vraiment OneDrive, tu perds aussi ses notifications de synchronisation." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSyncProviderNotifications" -Value 0
    }

    Invoke-Tweak "Couper les pubs et Spotlight de l'écran de verrouillage ?" -Cle "pubs-verrouillage" `
        -Explication "L'écran de verrouillage (Windows Spotlight) affiche de jolies photos accompagnées de suggestions et de publicités. Ce réglage coupe les incrustations publicitaires." {
        $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        Set-RegValue -Path $cdm -Name "RotatingLockScreenOverlayEnabled" -Value 0
        Set-RegValue -Path $cdm -Name "SubscribedContent-338387Enabled" -Value 0
    }

    Invoke-Tweak "Désactiver complètement les Widgets ? (stratégie 'Dsh', celle qui marche depuis 24H2)" -Cle "widgets-dsh" `
        -Explication "Désactive complètement le panneau Widgets. C'est la stratégie qui fonctionne réellement depuis 24H2 : l'ancienne clé « Windows Feeds » que recommandent la plupart des guides n'existe même plus." {
        # Depuis 24H2 les Widgets sont pilotés par la stratégie Dsh et non plus par
        # l'ancienne clé "Windows Feeds", qui n'existe même plus sur cette machine.
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests" -Value 0
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarDa" -Value 0
    }

    Invoke-Tweak "Aligner la barre des tâches à GAUCHE (comme Windows 10) ?" -Cle "barre-taches-gauche" `
        -Explication "Aligne la barre des tâches à gauche, comme dans Windows 10 et toutes les versions précédentes, au lieu du centrage de Windows 11. Purement une question d'habitude." {
        # Sur une installation neuve de Windows 11, elle est centrée.
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAl" -Value 0
    }

    Invoke-Tweak "AJOUTER 'Fin de tâche' au clic droit de la barre des tâches ? (tuer une appli sans le Gestionnaire)" -Cle "fin-de-tache" `
        -Explication "Ajoute « Fin de tâche » au clic droit sur une icône de la barre des tâches, pour tuer une application figée sans ouvrir le Gestionnaire des tâches. Celui-ci ACTIVE une fonctionnalité utile au lieu d'en couper une." {
        # Celui-ci ACTIVE une fonctionnalité utile au lieu d'en couper une.
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" -Name "TaskbarEndTask" -Value 1
    }

    Invoke-Tweak "Masquer le panneau 'Téléphone' du menu Démarrer ? (nouveauté 25H2)" -Cle "panneau-telephone" `
        -Explication "Masque le panneau « Téléphone » ajouté au menu Démarrer par la 25H2. Réglage non documenté par Microsoft, trouvé par la communauté : s'il réapparaît après une mise à jour, c'est que la clé a changé." {
        # Source : communauté ElevenForum (Microsoft ne documente pas cette clé).
        # La sous-clé Companions existe déjà ; on désactive le compagnon Phone Link.
        $comp = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start\Companions\Microsoft.YourPhone_8wekyb3d8bbwe"
        Set-RegValue -Path $comp -Name "IsEnabled" -Value 0
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start" -Name "RightCompanionToggledOpen" -Value 0
        Write-Etat "Réglage non documenté par Microsoft : si le panneau revient, c'est que 25H2 a changé la clé." -Niveau Avert
    }

    Invoke-Tweak "Désactiver les fonctions IA de Paint (Cocreator, Remplissage génératif, Image Creator) ?" -Cle "paint-ia" `
        -Explication "Désactive les fonctions d'IA générative de Paint (Cocreator, Remplissage génératif, Image Creator). Paint continue de fonctionner normalement pour tout le reste." {
        # Source : Microsoft Learn, WindowsAI Policy CSP. Attention, le chemin n'est
        # PAS sous Policies\Microsoft\Windows mais sous CurrentVersion\Policies\Paint.
        $paint = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint"
        Set-RegValue -Path $paint -Name "DisableCocreator" -Value 1
        Set-RegValue -Path $paint -Name "DisableGenerativeFill" -Value 1
        Set-RegValue -Path $paint -Name "DisableImageCreator" -Value 1
    }

    Invoke-Tweak "Désactiver 'Click to Do' (l'analyse IA de l'écran) ?" -Cle "click-to-do" `
        -Explication "Click to Do analyse le contenu de ton écran par IA pour proposer des actions contextuelles. Honnêtement : Microsoft ne documente cette stratégie que pour les builds Insider, son effet sur une version stable n'est pas garanti. Elle est posée par précaution. Cette fonction ne tourne de toute façon que sur les PC Copilot+ équipés d'un NPU." {
        # Source : Microsoft Learn. ATTENTION : la doc ne liste cette stratégie que
        # pour "Windows Insider Preview" -- elle n'a probablement AUCUN effet sur une
        # 25H2 stable. On la pose par anticipation, sans prétendre qu'elle agit.
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableClickToDo" -Value 1
        Set-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" -Name "DisableClickToDo" -Value 1
        Write-Etat "Stratégie documentée pour les builds Insider uniquement : effet non garanti sur une version stable." -Niveau Avert
        # On DÉTECTE au lieu d'affirmer : ce script peut tourner sur un PC Copilot+.
        if (Test-NPU) {
            Write-Etat "NPU détecté : ce PC est un Copilot+, Click to Do y est bien actif. La stratégie a du sens ici." -Niveau Info
        }
        else {
            Write-Etat "Aucun NPU détecté : Click to Do ne tourne pas sur ce PC. Stratégie posée par précaution." -Niveau Info
        }
    }

    # NON INCLUS À DESSEIN : "DisableWindowsConsumerFeatures" (CloudContent), le tweak
    # le plus recopié du web. Microsoft Learn est formel : sa table d'éditions dit
    # "Pro : NON, Entreprise : OUI, Éducation : OUI" -- il est donc sans effet sur
    # Famille ET sur Pro. Au passage, la moitié des forums donnent un nom de valeur
    # erroné ("DisableConsumerFeatures" au lieu de "DisableWindowsConsumerFeatures").

    Fin-De-Menu -RedemarrerExplorateur
}

# ------------------------------------------------------------------------------
# ANNULER (revenir en arrière tweak par tweak)
# ------------------------------------------------------------------------------
function Menu-Annuler {
    Start-Menu -Titre "ANNULER LES TWEAKS / REVENIR AUX DÉFAUTS WINDOWS" -Couleur Magenta

    # --- Option privilégiée : restaurer l'état EXACT depuis la sauvegarde ---
    Write-Host "  Deux façons d'annuler :" -ForegroundColor DarkGray
    Write-Host "   A) Restauration EXACTE  - remet chaque valeur telle qu'elle était avant" -ForegroundColor DarkGray
    Write-Host "      que ce script n'y touche. Précis, mais limité à ce qu'il a modifié." -ForegroundColor DarkGray
    Write-Host "   B) Retour aux défauts   - réécrit les défauts Windows tweak par tweak." -ForegroundColor DarkGray
    Write-Host "      Plus large, mais approximatif : ça devine les défauts." -ForegroundColor DarkGray
    Write-Host ""

    if ($script:Sauvegarde.Count -gt 0) {
        Write-Etat "Sauvegarde disponible : $($script:Sauvegarde.Count) valeur(s) modifiée(s) par ce script." -Niveau Info
        if (Demander-Option "Afficher le détail de ce que le script a modifié ?") {
            Write-Host ""
            Write-Host ("  {0,-58} {1,-14} {2}" -f "VALEUR", "AVANT", "MAINTENANT") -ForegroundColor DarkGray
            foreach ($cle in ($script:Sauvegarde.Keys | Sort-Object)) {
                $e = $script:Sauvegarde[$cle]
                $court = ($e.Path -replace '^HKEY_CURRENT_USER|^HKCU:', 'HKCU' -replace '^HKEY_LOCAL_MACHINE|^HKLM:', 'HKLM')
                $court = if ($court.Length -gt 44) { "..." + $court.Substring($court.Length - 41) } else { $court }
                $avant = if ($e.Existait) { "$($e.Valeur)" } else { "(absente)" }
                $maintenant = try {
                    $v = (Get-ItemProperty -Path $e.Path -Name $e.Name -ErrorAction Stop).($e.Name)
                    if ($v -is [byte[]]) { "(binaire)" } else { "$v" }
                } catch { "(absente)" }
                $couleur = if ($avant -eq $maintenant) { "DarkGray" } else { "Yellow" }
                Write-Host ("  {0,-58} {1,-14} {2}" -f "$court\$($e.Name)", $avant, $maintenant) -ForegroundColor $couleur
            }
            Write-Host ""
        }
        Invoke-Tweak "RESTAURATION EXACTE : remettre ces $($script:Sauvegarde.Count) valeur(s) comme avant ?" {
            Restore-Sauvegarde
        }
        Write-Host ""
        Write-Host "  --- Ou, tweak par tweak, le retour aux défauts Windows : ---" -ForegroundColor DarkGray
        Write-Host ""
    }
    else {
        Write-Etat "Aucune sauvegarde : ce script n'a rien modifié ici, ou le fichier madtweak-donnees a été supprimé." -Niveau Avert
        Write-Etat "Seul le retour aux défauts (approximatif) est disponible ci-dessous." -Niveau Info
        Write-Host ""
    }

    Invoke-Tweak "Réactiver la télémétrie (Windows, Store, Edge, Chrome, Firefox, Office) et les suggestions ?" {
        Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" -Name "AllowTelemetry"
        $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        foreach ($v in @("SoftLandingEnabled", "SubscribedContent-338388Enabled", "SubscribedContent-338389Enabled", "SubscribedContent-310093Enabled", "SystemPaneSuggestionsEnabled", "SilentInstalledAppsEnabled", "PreInstalledAppsEnabled", "PreInstalledAppsEverywhereEnabled")) {
            Set-RegValue -Path $cdm -Name $v -Value 1
        }
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" -Name "Enabled" -Value 1
        
        # Chrome Telemetry rollback
        Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Google\Chrome" -Name "MetricsReportingEnabled"
        # Firefox Telemetry rollback
        $ff = "HKLM:\SOFTWARE\Policies\Mozilla\Firefox"
        if (Test-Path $ff) {
            Remove-RegValue -Path $ff -Name "DisableTelemetry"
            Remove-RegValue -Path $ff -Name "DisableFirefoxStudies"
        }
        # Office Telemetry rollback
        Remove-RegValue -Path "HKCU:\Software\Policies\Microsoft\Office\Common\ClientTelemetry" -Name "DisableTelemetry"
        Remove-RegValue -Path "HKCU:\Software\Policies\Microsoft\office\16.0\common\feedback" -Name "Enabled"
    }

    Invoke-Tweak "Réactiver les mises à jour de Windows Update, les pilotes, régler Defender, Edge et les outils de dév ?" {
        $wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
        if (Test-Path $wu) { Remove-RegKey -Path $wu }
        Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Settings" -Name "ExcludeWUDriversInQualityUpdate"
        Remove-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig"
        Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan" -Name "AvgCPULimit"
        Remove-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager" -Name "EnablePeriodicalBackup"
        
        $edge = "HKLM:\SOFTWARE\Policies\Microsoft\Edge"
        if (Test-Path $edge) {
            foreach ($v in @("MetricsReportingEnabled", "PersonalizationServicesEnabled", "ShowRecommendationsEnabled")) {
                Remove-RegValue -Path $edge -Name $v
            }
        }

        # Visual Studio Telemetry rollback
        Remove-RegKey -Path "HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio"

        # VS Code Telemetry rollback
        $vscodeSettings = "$env:APPDATA\Code\User\settings.json"
        if (Test-Path $vscodeSettings) {
            try {
                $json = Get-Content $vscodeSettings -Raw | ConvertFrom-Json
                if ($json -and $json."telemetry.telemetryLevel") {
                    $json.PSObject.Properties.Remove("telemetry.telemetryLevel")
                    $json | ConvertTo-Json -Depth 10 | Set-Content $vscodeSettings -Encoding UTF8
                }
            } catch {}
        }
        Set-ServiceEtat -Nom "wuauserv" -Demarrage Manual -Demarrer
    }

    Invoke-Tweak "Remettre les Widgets, l'icône Chat et les suggestions Bing ?" {
        $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-RegValue -Path $adv -Name "TaskbarDa" -Value 1
        Set-RegValue -Path $adv -Name "TaskbarMn" -Value 1
        Remove-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\Explorer" -Name "DisableSearchBoxSuggestions"
    }

    Invoke-Tweak "Remettre le menu clic droit MODERNE de Windows 11 ?" {
        $clsid = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}"
        if (-not (Test-Path $clsid)) { throw "Le tweak du clic droit classique n'est pas actif : rien à annuler." }
        Remove-RegKey -Path $clsid
    }

    Invoke-Tweak "Réactiver les animations visuelles des fenêtres ?" {
        # Valeur par défaut de Windows pour UserPreferencesMask.
        Set-RegValue -Path "HKCU:\Control Panel\Desktop" -Name "UserPreferencesMask" `
            -Value ([byte[]](0x9E, 0x1E, 0x07, 0x80, 0x12, 0x00, 0x00, 0x00)) -Type Binary
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "TaskbarAnimations" -Value 1
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "EnableAeroPeek" -Value 1
    }

    Invoke-Tweak "Annuler le 'tuer les applis qui ne répondent pas' ?" {
        foreach ($v in @("AutoEndTasks", "WaitToKillAppTimeout", "HungAppTimeout")) {
            Remove-RegValue -Path "HKCU:\Control Panel\Desktop" -Name $v
        }
    }

    Invoke-Tweak "RÉACTIVER l'Isolation du Noyau / VBS et le Démarrage Rapide ? (recommandé pour la sécurité)" -Redemarrage {
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name "EnableVirtualizationBasedSecurity" -Value 1
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled" -Value 1
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" -Name "HiberbootEnabled" -Value 1
    }

    Invoke-Tweak "Réactiver Windows Copilot, Recall et les IA de Paint ?" {
        Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot"
        Remove-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot"
        Remove-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton"
        foreach ($v in @("DisableAIDataAnalysis", "AllowRecallEnablement", "DisableClickToDo")) {
            Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name $v
            Remove-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" -Name $v
        }
        $paint = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint"
        foreach ($v in @("DisableCocreator", "DisableGenerativeFill", "DisableImageCreator")) {
            Remove-RegValue -Path $paint -Name $v
        }
        # Si le composant Recall a été retiré, il faut le réinstaller explicitement.
        $f = Get-WindowsOptionalFeature -Online -FeatureName "Recall" -ErrorAction SilentlyContinue
        if ($f -and $f.State -ne "Enabled") {
            Invoke-Action "réinstallerait le composant Windows Recall" { Enable-WindowsOptionalFeature -Online -FeatureName "Recall" -NoRestart -ErrorAction Stop | Out-Null }
        }
        Write-Etat "L'app Copilot désinstallée n'est PAS réinstallée : passe par le Microsoft Store." -Niveau Info
    }

    Invoke-Tweak "Réautoriser les applications en arrière-plan ?" {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications" -Name "GlobalUserDisabled" -Value 0
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "BackgroundAppGlobalToggle" -Value 1
        Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" -Name "LetAppsRunInBackground"
    }

    Invoke-Tweak "Annuler les tweaks de confidentialité approfondie (historique, saisie, feedback, Defender) ?" {
        $sys = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System"
        foreach ($v in @("EnableActivityFeed", "PublishUserActivities", "UploadUserActivities")) {
            Remove-RegValue -Path $sys -Name $v
        }
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" -Name "TailoredExperiencesWithDiagnosticDataEnabled" -Value 1
        foreach ($v in @("NumberOfSIUFInPeriod", "PeriodInNanoSeconds")) {
            Remove-RegValue -Path "HKCU:\Software\Microsoft\Siuf\Rules" -Name $v
        }
        $ip = "HKCU:\Software\Microsoft\InputPersonalization"
        Set-RegValue -Path $ip -Name "RestrictImplicitInkCollection" -Value 0
        Set-RegValue -Path $ip -Name "RestrictImplicitTextCollection" -Value 0
        Set-RegValue -Path "$ip\TrainedDataStore" -Name "HarvestContacts" -Value 1
        Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" -Name "SubmitSamplesConsent"
        # « Allow » est le défaut Windows pour la géolocalisation.
        Set-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" -Name "Value" -Value "Allow" -Type String
    }

    Invoke-Tweak "Annuler les tweaks matériel et réseau récents (LLMNR, NetBIOS, DoH, veille carte réseau, Modern Standby, HAGS, AMD, PCIe, Xbox) ?" {
        $dns = "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient"
        Remove-RegValue -Path $dns -Name "EnableMulticast"
        Remove-RegValue -Path $dns -Name "DoHPolicy"
        # 0 = « suivre le serveur DHCP », qui est le défaut de Windows pour NetBIOS.
        $nb = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces"
        if (Test-Path $nb) {
            foreach ($i in Get-ChildItem $nb) { Set-RegValue -Path $i.PSPath -Name "NetbiosOptions" -Value 0 }
        }
        # Supprimer PnPCapabilities rend la main à Windows (gestion d'énergie par défaut).
        $classe = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
        if (Test-Path $classe) {
            foreach ($sk in (Get-ChildItem $classe | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
                Remove-RegValue -Path $sk.PSPath -Name "PnPCapabilities"
            }
        }
        # Veille moderne (Modern Standby) rollback
        Remove-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "PlatformAoAcOverride"
        # HAGS rollback
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 1
        # AMD Telemetry rollback
        Remove-RegValue -Path "HKLM:\SOFTWARE\AMD\CN\ANALYTICS" -Name "ReportAnalytics"

        # PCIe rollback (1 = Moderate power savings on AC, 2 = Maximum on DC)
        powercfg.exe /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a821a03c4f3d ee12f2c1-98ac-4be7-9e4c-1c778ca13c9b 1
        powercfg.exe /setdcvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a821a03c4f3d ee12f2c1-98ac-4be7-9e4c-1c778ca13c9b 2
        powercfg.exe /setactive SCHEME_CURRENT

        # Xbox Game Bar rollback
        Set-RegValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 1
        Set-RegValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Value 0
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 1
        Set-RegValue -Path "HKCU:\Software\Microsoft\GameBar" -Name "UseNexusForGameBarEnabled" -Value 1

        # Delivery Optimization rollback
        Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode"
    }

    Invoke-Tweak "Réactiver les services désactivés (SysMain, rapport d'erreurs, télémétrie NVIDIA, DiagTrack, Fax, WSearch, Adobe, Google...) ?" {
        # Les valeurs sont les démarrages PAR DÉFAUT de Windows, service par service.
        # Un service absent de la machine est simplement ignoré (pas d'échec).
        $services = @{
            "SysMain" = "Automatic"; "WerSvc" = "Manual"; "NvTelemetryContainer" = "Automatic"
            "DiagTrack" = "Automatic"; "Fax" = "Manual"; "RemoteRegistry" = "Disabled"
            "RetailDemo" = "Manual"; "MapsBroker" = "Automatic"; "bthserv" = "Manual"
            "WSearch" = "Automatic"; "gupdate" = "Automatic"; "gupdatem" = "Manual"
            "AdobeARMservice" = "Automatic"; "AGSService" = "Automatic"
        }
        $faits = 0
        foreach ($nom in $services.Keys) {
            if (-not (Get-Service -Name $nom -ErrorAction SilentlyContinue)) { continue }
            $defaut = $services[$nom]
            # RemoteRegistry est désactivé PAR DÉFAUT sur un Windows client : le
            # « réactiver » veut dire le remettre à Disabled, surtout pas le démarrer.
            if ($defaut -eq "Disabled") { Set-ServiceEtat -Nom $nom -Demarrage $defaut }
            else { Set-ServiceEtat -Nom $nom -Demarrage $defaut -Demarrer }
            Write-Etat "$nom remis en $defaut." -Niveau OK
            $faits++
        }
        if ($faits -eq 0) { throw "Aucun de ces services n'est présent sur la machine." }
    }

    Invoke-Tweak "Réactiver les tâches planifiées de télémétrie ?" {
        # Même source de vérité que le tweak qui les désactive : sans ça, l'annulation
        # réactivait des noms de tâches qui n'existent plus depuis 25H2, donc rien.
        $taches = @(Get-TachesTelemetrie)
        if ($taches.Count -eq 0) { throw "Aucune tâche de collecte connue n'existe sur ce build : rien à réactiver." }
        foreach ($t in $taches) {
            Invoke-Action "réactiverait la tâche planifiée $($t.TaskName)" { Enable-ScheduledTask -InputObject $t -ErrorAction SilentlyContinue | Out-Null }
        }
        if (-not $script:Simulation) { Write-Etat "$($taches.Count) tâche(s) réactivée(s) : $(($taches.TaskName) -join ', ')" -Niveau Info }
    }

    Invoke-Tweak "Annuler les tweaks réseau (Nagle et bridage multimédia) ?" {
        $base = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        if (Test-Path $base) {
            foreach ($i in Get-ChildItem $base) {
                Remove-RegValue -Path $i.PSPath -Name "TcpAckFrequency"
                Remove-RegValue -Path $i.PSPath -Name "TCPNoDelay"
            }
        }
        # Ici on REMET les défauts observés plutôt que de supprimer : Windows crée
        # ces deux valeurs lui-même et s'attend à les trouver.
        $profil = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        Set-RegValue -Path $profil -Name "NetworkThrottlingIndex" -Value 10
        Set-RegValue -Path $profil -Name "SystemResponsiveness" -Value 20
    }

    Invoke-Tweak "Annuler les tweaks mémoire (noyau en RAM) ?" -Redemarrage {
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" -Name "DisablePagingExecutive" -Value 0
    }

    Invoke-Tweak "Réactiver Game DVR / l'enregistrement de la Game Bar ?" {
        Set-RegValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 1
        Remove-RegValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode"
        Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR"
    }

    Invoke-Tweak "Réactiver l'accélération de la souris (défauts Windows) ?" {
        $m = "HKCU:\Control Panel\Mouse"
        Set-RegValue -Path $m -Name "MouseSpeed" -Value "1" -Type String
        Set-RegValue -Path $m -Name "MouseThreshold1" -Value "6" -Type String
        Set-RegValue -Path $m -Name "MouseThreshold2" -Value "10" -Type String
    }

    Invoke-Tweak "Réactiver le spouleur d'impression ? (indispensable pour installer une imprimante)" {
        Set-ServiceEtat -Nom "Spooler" -Demarrage Automatic -Demarrer
    }

    Invoke-Tweak "Rétablir le comportement NTFS par défaut (last access, noms courts 8.3) ?" {
        # 2 = géré par le système, qui est le défaut de Windows.
        Invoke-Externe -Fichier "fsutil.exe" -Arguments @("behavior", "set", "disablelastaccess", "2")
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsDisable8dot3NameCreation" -Value 2
    }

    Invoke-Tweak "Réactiver la recherche Bing/web, les temps forts et la lecture automatique ?" {
        $rech = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search"
        Set-RegValue -Path $rech -Name "BingSearchEnabled" -Value 1
        Set-RegValue -Path $rech -Name "DisableWebSearch" -Value 0
        $param = "HKCU:\Software\Microsoft\Windows\CurrentVersion\SearchSettings"
        foreach ($v in @("IsDynamicSearchBoxEnabled", "IsMSACloudSearchEnabled", "IsDeviceSearchHistoryEnabled")) {
            Set-RegValue -Path $param -Name $v -Value 1
        }
        Remove-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" -Name "DisableAutoplay"
        Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode"
    }

    Invoke-Tweak "Réactiver l'hibernation et le démarrage rapide ?" {
        Invoke-Externe -Fichier "powercfg.exe" -Arguments @("/hibernate", "on")
    }

    Invoke-Tweak "Réactiver la suspension sélective des ports USB (défaut Windows) ?" {
        $sousGroupeUSB = "2a737441-1930-4402-8d77-b2bebba308a3"
        $parametre = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
        Invoke-Externe -Fichier "powercfg.exe" -Arguments @("/setacvalueindex", "SCHEME_CURRENT", $sousGroupeUSB, $parametre, "1")
        Invoke-Externe -Fichier "powercfg.exe" -Arguments @("/setdcvalueindex", "SCHEME_CURRENT", $sousGroupeUSB, $parametre, "1")
        Invoke-Externe -Fichier "powercfg.exe" -Arguments @("/setactive", "SCHEME_CURRENT")
    }

    Invoke-Tweak "Annuler les tweaks Windows 11 24H2/25H2 (pubs Démarrer, verrouillage, Widgets) ?" {
        $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-RegValue -Path $adv -Name "Start_IrisRecommendations" -Value 1
        Set-RegValue -Path $adv -Name "Start_TrackDocs" -Value 1
        Set-RegValue -Path $adv -Name "Start_TrackProgs" -Value 1
        Set-RegValue -Path $adv -Name "ShowSyncProviderNotifications" -Value 1
        Remove-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" -Name "ScoobeSystemSettingEnabled"
        $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
        foreach ($v in @("RotatingLockScreenOverlayEnabled", "SubscribedContent-338387Enabled", "SubscribedContent-353694Enabled", "SubscribedContent-353696Enabled")) {
            Set-RegValue -Path $cdm -Name $v -Value 1
        }
        Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" -Name "AllowNewsAndInterests"
        Remove-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" -Name "TaskbarEndTask"
        # Panneau Téléphone du menu Démarrer (25H2)
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start\Companions\Microsoft.YourPhone_8wekyb3d8bbwe" -Name "IsEnabled" -Value 1
        Remove-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start" -Name "RightCompanionToggledOpen"
    }

    Invoke-Tweak "Annuler les tweaks Explorateur et presse-papiers ?" {
        $exp = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer"
        Set-RegValue -Path $exp -Name "ShowRecent" -Value 1
        Set-RegValue -Path $exp -Name "ShowFrequent" -Value 1
        Set-RegValue -Path "HKCU:\Software\Microsoft\Clipboard" -Name "EnableClipboardHistory" -Value 1
        Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "AllowCrossDeviceClipboard"
        Remove-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NoNetCrawling"
    }

    Invoke-Tweak "Annuler les tweaks d'APPARENCE et de menu contextuel (thème clair, Explorateur, barre des tâches, clic droit) ?" {
        # Ce sont les défauts d'une installation neuve de Windows 11.
        $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        Set-RegValue -Path $p -Name "AppsUseLightTheme" -Value 1
        Set-RegValue -Path $p -Name "SystemUsesLightTheme" -Value 1
        Set-RegValue -Path $p -Name "EnableTransparency" -Value 1
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "ColorPrevalence" -Value 0

        $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        Set-RegValue -Path $adv -Name "Hidden" -Value 2          # 2 = ne pas afficher les cachés
        Set-RegValue -Path $adv -Name "ShowSuperHidden" -Value 0
        Set-RegValue -Path $adv -Name "LaunchTo" -Value 2        # 2 = Accueil
        Set-RegValue -Path $adv -Name "ShowTaskViewButton" -Value 1
        Set-RegValue -Path $adv -Name "Start_Layout" -Value 0
        foreach ($v in @("UseCompactMode", "ShowSecondsInSystemClock", "DisallowShaking", "EnableSnapAssistFlyout")) {
            Remove-RegValue -Path $adv -Name $v
        }
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 2
        Set-RegValue -Path "HKCU:\Control Panel\Accessibility" -Name "DynamicScrollbars" -Value 1
        Remove-RegValue -Path "HKCU:\Control Panel\Desktop" -Name "JPEGImportQuality"
        Remove-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "link"
        Set-RegValue -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "400" -Type String
        Set-RegValue -Path $adv -Name "SeparateProcess" -Value 0
        Remove-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" -Name "NoLowDiskSpaceChecks"
        Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" -Name "NoLockScreen"
        Remove-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "DisableLogonBackgroundImage"
        
        # AutoRestartShell rollback
        Remove-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" -Name "AutoRestartShell"
        # Kill Timeouts rollback
        Remove-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control" -Name "WaitToKillServiceTimeout"
        Remove-RegValue -Path "HKCU:\Control Panel\Desktop" -Name "WaitToKillAppTimeout"
        Remove-RegValue -Path "HKCU:\Control Panel\Desktop" -Name "HungAppTimeout"
        Write-Etat "« Galerie » et « Accueil » retirés du volet de l'Explorateur ne sont PAS remis ici : leur clé a été supprimée, seule la RESTAURATION EXACTE (en haut de ce menu) sait la reconstruire depuis son export .reg." -Niveau Avert

        # Visionneuse classique
        $assocPath = "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations"
        if (Test-Path $assocPath) {
            foreach ($ext in @(".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".ico")) {
                Remove-RegValue -Path $assocPath -Name $ext
            }
        }
        $cmdPath = "HKLM:\SOFTWARE\Classes\Applications\photoviewer.dll\shell\open\command"
        if (Test-Path $cmdPath) { Remove-RegKey -Path "HKLM:\SOFTWARE\Classes\Applications\photoviewer.dll" }

        # God Mode
        $bureau = [Environment]::GetFolderPath("Desktop")
        $chemin = Join-Path $bureau "Configuration complète.{ED7BA470-8E54-465E-825C-99712043E01C}"
        if (Test-Path $chemin) { Remove-Item -Path $chemin -Recurse -Force -ErrorAction SilentlyContinue }

        # Take Ownership
        Remove-RegKey -Path "HKLM:\SOFTWARE\Classes\*\shell\TakeOwnership"
        Remove-RegKey -Path "HKLM:\SOFTWARE\Classes\Directory\shell\TakeOwnership"
    }

    # Le fond d'écran signature se remet à son état d'avant, avec effet immédiat.
    $memoireFond = Join-Path $script:DossierDonnees "fond-precedent.txt"
    if (Test-Path $memoireFond) {
        Invoke-Tweak "Remettre le fond d'écran qui était là avant la signature MadTrix ?" {
            Restore-FondPrecedent
        }
    }

    Write-Host ""
    Write-Etat "Les bloatwares et logiciels désinstallés ne sont PAS réinstallés par ce menu." -Niveau Info
    Write-Etat "Pour eux, passe par le Microsoft Store ou le menu 6." -Niveau Info

    Fin-De-Menu -RedemarrerExplorateur
}

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

# ------------------------------------------------------------------------------
# DÉMARRAGE & SERVICES
# ------------------------------------------------------------------------------
function Menu-Demarrage {
    Start-Menu -Titre "DÉMARRAGE & SERVICES" -Couleur Green

    # D'abord CONSTATER, ensuite proposer : on ne touche à rien tant que tu n'as pas
    # vu ce qui se lance réellement chez toi. Sous profil, ce listing n'a pas sa
    # place : personne ne le lit, et il noierait le bilan du profil.
    if (-not (Test-SansInteraction)) {
        Write-Host "  PROGRAMMES LANCÉS AU DÉMARRAGE" -ForegroundColor White
        $demarrage = @()
        foreach ($ruche in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run", "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run")) {
            if (-not (Test-Path $ruche)) { continue }
            $item = Get-Item $ruche
            foreach ($n in $item.GetValueNames()) {
                if (-not $n) { continue }
                $demarrage += [pscustomobject]@{ Nom = $n; Ruche = $(if ($ruche -like "HKLM*") { "Tous" } else { "Toi" }) }
            }
        }
        $dossiersDemarrage = @(
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
            "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
        )
        foreach ($d in $dossiersDemarrage) {
            foreach ($f in (Get-ChildItem -Path $d -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne "desktop.ini" })) {
                $demarrage += [pscustomobject]@{ Nom = $f.BaseName; Ruche = "Dossier" }
            }
        }
        if ($demarrage.Count -eq 0) { Write-Host "    (aucun)" -ForegroundColor DarkGray }
        else { foreach ($d in $demarrage) { Write-Host ("    [{0,-6}] {1}" -f $d.Ruche, $d.Nom) -ForegroundColor Gray } }
        Write-Host "    -> Pour en désactiver : Gestionnaire des tâches > Applications de démarrage." -ForegroundColor DarkGray
        Write-Host "       Ce script ne les touche pas : ce sont TES logiciels, pas ceux de Windows." -ForegroundColor DarkGray
        Write-Host ""
    }

    Invoke-Tweak "Supprimer le délai artificiel de 10 s avant le lancement des programmes de démarrage ?" -Cle "delai-demarrage" `
        -Explication "Windows retarde volontairement de 10 secondes le lancement de tes programmes de démarrage, pour rendre le bureau utilisable plus tôt. Sur un SSD, ce délai n'a plus lieu d'être. Ne concerne que TES programmes, pas les services Windows." {
        # Windows retarde volontairement les programmes de démarrage pour rendre le
        # bureau utilisable plus vite. Sur un SSD, ce délai n'a plus lieu d'être.
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" -Name "StartupDelayInMSec" -Value 0
    }

    if (-not (Test-SansInteraction)) {
        Write-Host ""
        Write-Host "  SERVICES RAREMENT UTILES" -ForegroundColor White
        Write-Host "  Chacun est vérifié AVANT : un service déjà désactivé, ou dont le matériel" -ForegroundColor DarkGray
        Write-Host "  est présent, ne sera pas touché." -ForegroundColor DarkGray
        Write-Host ""
    }

    Invoke-Tweak "Désactiver le service Fax ?" -Cle "service-fax" `
        -Explication "Le service Fax est chargé sur toutes les installations de Windows, y compris les millions de PC qui n'ont jamais vu un modem. Aucun revers, sauf si tu envoies vraiment des fax." {
        Set-ServiceEtat -Nom "Fax" -Demarrage Disabled -Arreter
    }

    Invoke-Tweak "Désactiver le Registre distant (RemoteRegistry) ? (surface d'attaque, inutile hors entreprise)" -Cle "service-registre-distant" `
        -Explication "Permet à une autre machine de lire et modifier ton registre à distance. C'est une surface d'attaque, et c'est inutile hors d'un réseau d'entreprise. Windows le laisse d'ailleurs déjà désactivé par défaut sur un PC particulier." {
        Set-ServiceEtat -Nom "RemoteRegistry" -Demarrage Disabled -Arreter
    }

    Invoke-Tweak "Désactiver le mode démonstration magasin (RetailDemo) ?" -Cle "service-retaildemo" `
        -Explication "Le mode démonstration magasin sert aux PC exposés en rayon chez un revendeur. Sur ta machine, il ne fera jamais rien d'utile." {
        Set-ServiceEtat -Nom "RetailDemo" -Demarrage Disabled -Arreter
    }

    Invoke-Tweak "Désactiver le téléchargement des cartes hors connexion (MapsBroker) ?" -Cle "service-cartes" `
        -Explication "MapsBroker gère le téléchargement des cartes hors connexion. Inutile si tu n'utilises pas l'application Cartes. Revers : elle ne pourra plus télécharger de cartes pour un usage sans Internet." {
        Set-ServiceEtat -Nom "MapsBroker" -Demarrage Disabled -Arreter
        Write-Etat "L'app Cartes ne pourra plus télécharger de cartes hors connexion." -Niveau Avert
    }

    Invoke-Tweak "Désactiver le Bluetooth ? (uniquement si ce PC n'a AUCUN périphérique Bluetooth)" -Cle "service-bluetooth" `
        -Explication "Coupe le service Bluetooth. À ne prendre QUE si ce PC n'a aucun périphérique Bluetooth : le script détecte les périphériques actifs et refuse s'il en trouve, car ton clavier, ta souris ou ton casque cesseraient de fonctionner au redémarrage." {
        # On refuse plutôt que de couper à l'aveugle : sur un portable, le clavier ou
        # le casque Bluetooth de l'utilisateur cesseraient de fonctionner au reboot.
        $radios = @(Get-CimInstance -ClassName Win32_PnPEntity -ErrorAction SilentlyContinue |
                    Where-Object { $_.PNPClass -eq 'Bluetooth' -and $_.Status -eq 'OK' })
        if ($radios.Count -gt 0) {
            throw "$($radios.Count) périphérique(s) Bluetooth actif(s) détecté(s) sur ce PC (ex. « $($radios[0].Name) »). Couper le service les rendrait inutilisables. Refusé."
        }
        Set-ServiceEtat -Nom "bthserv" -Demarrage Disabled -Arreter
    }

    Invoke-Tweak "Désactiver l'Indexation de fichiers Windows Search (WSearch) ?" -Cle "service-search" `
        -Explication "Désactive le service d'indexation de fichiers Windows Search. Recommandé sur les machines équipées d'un bon SSD pour économiser de la RAM et de l'usage disque inutile. L'outil de recherche de l'explorateur continuera de fonctionner mais de manière directe, sans index préalable." {
        Set-ServiceEtat -Nom "WSearch" -Demarrage Disabled -Arreter
    }

    Fin-De-Menu
}

# ------------------------------------------------------------------------------
# APPARENCE & VISUEL
#
# Ce menu ne cherche PAS à gagner des performances : il change ce que tu vois.
# Les tweaks de perf visuelle (animations, Aero Peek) restent dans TWEAKS AVANCÉS,
# parce qu'ils se paient en fluidité perçue et ne relèvent pas du goût.
# Ici, tout est affaire de préférence : aucun de ces réglages n'est « meilleur »
# qu'un autre, et aucun ne casse quoi que ce soit.
# ------------------------------------------------------------------------------
function Menu-Visuel {
    Start-Menu -Titre "APPARENCE & VISUEL" -Couleur Cyan -SousTitre @(
        "Affaire de goût : rien ici n'améliore les performances, rien ne casse rien.",
        "La plupart demandent un redémarrage de l'Explorateur (proposé en fin de menu)."
    )

    # --- Thème ---

    Invoke-Tweak "Activer le mode SOMBRE (Windows et applications) ?" -Cle "mode-sombre" `
        -Explication "Passe Windows et les applications en thème sombre. Les DEUX réglages sont posés : l'un habille les applications, l'autre la barre des tâches et le menu Démarrer. Beaucoup de guides n'en posent qu'un et laissent un thème à moitié sombre." {
        # Les deux valeurs sont distinctes : la première habille les apps, la seconde
        # la barre des tâches et le menu Démarrer. N'en poser qu'une donne un thème
        # à moitié sombre, ce que font beaucoup de guides.
        $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
        Set-RegValue -Path $p -Name "AppsUseLightTheme" -Value 0
        Set-RegValue -Path $p -Name "SystemUsesLightTheme" -Value 0
    }

    Invoke-Tweak "Désactiver les effets de transparence (Acrylique / Mica) ?" -Cle "transparence" `
        -Explication "Coupe les effets de transparence (Acrylique, Mica) des fenêtres et du menu Démarrer. Contrairement aux autres réglages de cet onglet, celui-ci a un effet réel sur les performances : la transparence coûte du GPU, ce qui compte sur un portable à carte graphique intégrée." {
        # Contrairement aux animations, la transparence coûte un peu de GPU : c'est
        # le seul tweak de ce menu qui a un effet mesurable, surtout sur un portable
        # à carte graphique intégrée.
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "EnableTransparency" -Value 0
    }

    Invoke-Tweak "Appliquer ta couleur d'accentuation aux barres de titre et aux bordures ?" -Cle "accent-barres-titre" `
        -Explication "Applique ta couleur d'accentuation aux barres de titre et aux bordures des fenêtres. Sans ce réglage, elles restent grises quelle que soit la couleur choisie dans les Paramètres. La couleur utilisée est celle de Paramètres > Personnalisation > Couleurs." {
        # Sans ça, les barres de titre restent grises quelle que soit la couleur choisie
        # dans Paramètres > Personnalisation > Couleurs.
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "ColorPrevalence" -Value 1
        Write-Etat "La couleur utilisée est celle de Paramètres > Personnalisation > Couleurs." -Niveau Info
    }

    Invoke-Tweak "Améliorer la qualité du fond d'écran (JPEG non recompressé) ?" -Cle "qualite-fond-ecran" `
        -Explication "Windows recompresse ton fond d'écran à environ 85 % de qualité, ce qui se voit sur les dégradés et les aplats. Ce réglage passe à la qualité maximale. Effectif seulement quand tu REPOSERAS un fond d'écran : l'actuel est déjà recompressé." {
        # Windows recompresse le fond d'écran à ~85% par défaut, ce qui se voit sur
        # les dégradés. 100 = qualité maximale. Effectif au prochain changement de
        # fond d'écran : le fond actuel est déjà recompressé, il faut le reposer.
        Set-RegValue -Path "HKCU:\Control Panel\Desktop" -Name "JPEGImportQuality" -Value 100
        Write-Etat "Effectif seulement quand tu REPOSERAS un fond d'écran : l'actuel est déjà recompressé." -Niveau Avert
    }

    # --- Explorateur de fichiers ---

    Invoke-Tweak "Afficher les fichiers et dossiers CACHÉS ?" -Cle "fichiers-caches" `
        -Explication "Affiche les fichiers et dossiers marqués comme cachés. Pratique pour accéder à AppData ou à un .gitignore sans détour. Sans danger : ce sont surtout des fichiers de configuration." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Hidden" -Value 1
    }

    Invoke-Tweak "Afficher aussi les fichiers SYSTÈME protégés ? (pagefile.sys, hiberfil.sys...)" -Cle "fichiers-systeme" `
        -Explication "Affiche EN PLUS les fichiers système protégés (pagefile.sys, hiberfil.sys, bootmgr). À ne prendre que si tu sais ce que tu fais : ces fichiers sont masqués pour une raison, et en supprimer un peut rendre Windows non démarrable." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSuperHidden" -Value 1
        Write-Etat "Ces fichiers sont masqués pour une raison : en supprimer un peut rendre Windows non démarrable. À n'activer que si tu sais ce que tu fais." -Niveau Avert
    }

    Invoke-Tweak "Ouvrir l'Explorateur sur « Ce PC » plutôt que sur « Accueil » ?" -Cle "explorateur-ce-pc" `
        -Explication "L'Explorateur s'ouvre sur « Ce PC » (tes disques) au lieu de « Accueil », la page de Windows 11 qui mélange fichiers récents et fichiers OneDrive." {
        # 1 = Ce PC, 2 = Accueil (défaut Windows 11), 3 = Téléchargements.
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1
    }

    Invoke-Tweak "Activer l'affichage COMPACT de l'Explorateur (lignes resserrées, comme Windows 10) ?" -Cle "explorateur-compact" `
        -Explication "Resserre l'espacement entre les lignes de l'Explorateur, comme dans Windows 10. Windows 11 espace tout pour le tactile ; sur un écran de PC, ça oblige à faire défiler pour rien." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "UseCompactMode" -Value 1
    }

    Invoke-Tweak "Retirer « Galerie » du volet de navigation de l'Explorateur ?" -Cle "explorateur-galerie" `
        -Explication "Retire l'entrée « Galerie » du volet de navigation de l'Explorateur. C'est une vue photos ajoutée par la 23H2, redondante avec l'application Photos. Réversible : le script exporte la clé avant de la supprimer, donc la Restauration exacte sait la remettre." {
        # Retirer une entrée du volet = supprimer sa clé d'espace de noms. C'est
        # réversible : Remove-RegKey exporte la clé en .reg avant de la supprimer,
        # donc « Restauration EXACTE » sait la remettre.
        # Les deux ruches comptent : un Explorateur 32 bits lit la WOW6432Node.
        $trouve = $false
        foreach ($ruche in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace",
                             "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace")) {
            $cle = "$ruche\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}"
            if (Test-Path $cle) { Remove-RegKey -Path $cle; $trouve = $true }
        }
        if (-not $trouve) { throw "L'entrée « Galerie » n'est pas présente dans le volet (déjà retirée, ou build de Windows antérieur à 23H2)." }
    }

    Invoke-Tweak "Retirer « Accueil » du volet de navigation de l'Explorateur ?" -Cle "explorateur-volet-accueil" `
        -Explication "Retire l'entrée « Accueil » du volet de navigation. L'Explorateur basculera automatiquement sur « Ce PC » à l'ouverture : il ne peut pas s'ouvrir sur un emplacement qui n'existe plus." {
        $trouve = $false
        foreach ($ruche in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace",
                             "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace")) {
            $cle = "$ruche\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}"
            if (Test-Path $cle) { Remove-RegKey -Path $cle; $trouve = $true }
        }
        if (-not $trouve) { throw "L'entrée « Accueil » n'est pas présente dans le volet (déjà retirée)." }
        # Sans ça, l'Explorateur s'ouvrirait sur un emplacement qu'on vient de retirer.
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "LaunchTo" -Value 1
        Write-Etat "L'Explorateur ouvrira désormais sur « Ce PC » : il ne peut plus s'ouvrir sur un Accueil qui n'existe plus." -Niveau Info
    }

    Invoke-Tweak "Supprimer le suffixe « - Raccourci » sur les nouveaux raccourcis ?" -Cle "suffixe-raccourci" `
        -Explication "Windows ajoute « - Raccourci » au nom de chaque nouveau raccourci créé. Ce réglage arrête ça. Ne renomme pas les raccourcis existants : seuls les nouveaux sont concernés." {
        # REG_BINARY à zéro = pas de suffixe. Ne renomme pas les raccourcis existants.
        Set-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "link" `
            -Value ([byte[]](0x00, 0x00, 0x00, 0x00)) -Type Binary
        Write-Etat "Ne concerne que les raccourcis créés APRÈS ce réglage : les anciens gardent leur nom." -Niveau Info
    }

    # --- Barre des tâches & menu Démarrer ---

    Invoke-Tweak "Réduire la barre de recherche de la barre des tâches à une simple icône ?" -Cle "recherche-barre-taches" `
        -Explication "Réduit la grande barre de recherche de la barre des tâches à une simple icône, ce qui libère beaucoup de place. Pour la masquer complètement : clic droit sur la barre des tâches > Rechercher > Masquer." {
        # 0 = masquée, 1 = icône seule, 2 = champ de saisie, 3 = champ + libellé.
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode" -Value 1
        Write-Etat "Pour la masquer COMPLÈTEMENT, mets SearchboxTaskbarMode à 0 (clic droit sur la barre > Rechercher > Masquer)." -Niveau Info
    }

    Invoke-Tweak "Masquer le bouton « Vue des tâches » de la barre des tâches ?" -Cle "bouton-vue-taches" `
        -Explication "Masque le bouton « Vue des tâches » de la barre des tâches. Le raccourci Win+Tab continue de fonctionner : seul le bouton disparaît." {
        # Win+Tab continue de fonctionner : seul le bouton disparaît.
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowTaskViewButton" -Value 0
    }

    Invoke-Tweak "Afficher les SECONDES dans l'horloge de la barre des tâches ?" -Cle "horloge-secondes" `
        -Explication "Affiche les secondes dans l'horloge de la barre des tâches. Microsoft l'avait retiré pour économiser la batterie : sur un portable, l'horloge se redessine chaque seconde, ce qui a un coût réel quoique faible. Négligeable sur un PC fixe." {
        # Microsoft l'avait retiré pour économiser la batterie : sur un portable, ça
        # réveille l'affichage chaque seconde. Négligeable sur un fixe.
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowSecondsInSystemClock" -Value 1
        if ($null -ne (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)) {
            Write-Etat "Ce PC est un portable : afficher les secondes consomme un peu de batterie (l'horloge se redessine chaque seconde)." -Niveau Avert
        }
    }

    Invoke-Tweak "Afficher PLUS d'épingles et moins de « Recommandé » dans le menu Démarrer ?" -Cle "demarrer-plus-epingles" `
        -Explication "Agrandit la zone des applications épinglées du menu Démarrer au détriment de la zone « Recommandé ». À combiner avec la coupure des pubs du menu Démarrer, dans l'onglet Windows 11." {
        # 0 = par défaut, 1 = plus d'épingles, 2 = plus de recommandations.
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "Start_Layout" -Value 1
    }

    # --- Comportement des fenêtres ---

    Invoke-Tweak "Désactiver Aero Shake (secouer une fenêtre réduit toutes les autres) ?" -Cle "aero-shake" `
        -Explication "Désactive Aero Shake, la fonction qui réduit toutes tes autres fenêtres quand tu secoues celle du dessus. Utile surtout si tu la déclenches par accident en déplaçant une fenêtre." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "DisallowShaking" -Value 1
    }

    Invoke-Tweak "Désactiver le menu volant des dispositions d'ancrage (Snap Layouts) ?" -Cle "snap-layouts" `
        -Explication "Désactive le menu volant qui surgit quand tu survoles le bouton Agrandir. L'ancrage continue de fonctionner normalement (Win+flèches, glisser au bord) : seul le menu automatique disparaît." {
        # L'ancrage continue de marcher (Win+flèches, glisser au bord) : seul le
        # menu qui surgit au survol du bouton Agrandir disparaît.
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "EnableSnapAssistFlyout" -Value 0
    }

    Invoke-Tweak "Garder les barres de défilement toujours visibles (au lieu de les faire disparaître) ?" -Cle "barres-defilement" `
        -Explication "Garde les barres de défilement toujours visibles au lieu de les faire disparaître puis réapparaître au survol. Tu vois en permanence où tu en es dans une page, et tu peux viser la barre sans la faire apparaître d'abord." {
        Set-RegValue -Path "HKCU:\Control Panel\Accessibility" -Name "DynamicScrollbars" -Value 0
    }

    Invoke-Tweak "Restaurer la Visionneuse de photos classique de Windows ?" -Cle "photo-classique" `
        -Explication "Rétablit l'ancienne visionneuse de photos classique (Windows Photo Viewer) ultra-rapide et légère de Windows 7/8. Associe les fichiers JPG, JPEG, PNG, GIF, BMP, TIFF et ICO à celle-ci." {
        $assocPath = "HKLM:\SOFTWARE\Microsoft\Windows Photo Viewer\Capabilities\FileAssociations"
        foreach ($ext in @(".jpg", ".jpeg", ".png", ".gif", ".bmp", ".tiff", ".ico")) {
            Set-RegValue -Path $assocPath -Name $ext -Value "PhotoViewer.FileAssoc.Tiff" -Type String
        }
        # Enregistrer la commande d'ouverture classique
        $cmdPath = "HKLM:\SOFTWARE\Classes\Applications\photoviewer.dll\shell\open\command"
        Set-RegValue -Path $cmdPath -Name "(default)" -Value 'C:\Windows\System32\rundll32.exe "C:\Program Files\Windows Photo Viewer\PhotoViewer.dll", ImageView_Fullscreen %1' -Type String
    }

    Invoke-Tweak "Ajouter le raccourci « God Mode » sur le Bureau ?" -Cle "god-mode" `
        -Explication "Crée un dossier spécial « Panneau de configuration complet » (God Mode) sur ton Bureau qui regroupe plus de 200 outils d'administration et de paramétrage de Windows en un seul endroit." {
        $bureau = [Environment]::GetFolderPath("Desktop")
        $chemin = Join-Path $bureau "Configuration complète.{ED7BA470-8E54-465E-825C-99712043E01C}"
        if (-not (Test-Path $chemin)) {
            Invoke-Action "créerait le dossier God Mode sur le Bureau" {
                New-Item -ItemType Directory -Path $chemin -Force | Out-Null
            }
        }
    }

    Invoke-Tweak "Désactiver le délai d'affichage des menus (MenuShowDelay) ?" -Cle "menu-delay" `
        -Explication "Réduit le délai d'apparition des menus au survol (de 400ms par défaut à 20ms). Rend l'affichage des sous-menus et des menus contextuels instantané, améliorant la sensation de réactivité globale de l'interface." {
        Set-RegValue -Path "HKCU:\Control Panel\Desktop" -Name "MenuShowDelay" -Value "20" -Type String
    }

    Invoke-Tweak "Désactiver le flou de l'arrière-plan sur l'écran de connexion ?" -Cle "disable-login-blur" `
        -Explication "Désactive l'effet de flou (acrylique) appliqué par Windows sur l'image d'arrière-plan de l'écran de saisie du mot de passe pour un affichage net et plus réactif." {
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" -Name "DisableLogonBackgroundImage" -Value 1
    }

    Fin-De-Menu -RedemarrerExplorateur
}
# ------------------------------------------------------------------------------
# SIGNATURE — fonds d'écran « MadTrix » générés à la volée
#
# Aucune image n'est stockée dans le script : ce serait des mégaoctets de binaire
# encodés en base64, à contre-courant de tout le reste. À la place, le fond est
# DESSINÉ par du code (WPF, le même moteur que l'interface), régénéré à la
# résolution réelle de l'écran au moment où tu le demandes. Le script reste un
# seul fichier texte, et le rendu est net sur n'importe quel écran.
#
# WPF exige un thread STA : powershell.exe le fournit. Sous un hôte non-STA (rare
# en console), la génération lève, et on le dit au lieu de planter.
# ------------------------------------------------------------------------------

function Get-ResolutionPhysique {
    # La résolution « logique » (Screen.Bounds) est réduite quand Windows applique
    # une mise à l'échelle (150 % ici). Pour un fond NET, on veut la résolution
    # physique réelle, que seul GetDeviceCaps expose.
    try {
        Add-Type -Namespace MadTweak -Name Ecran -MemberDefinition @'
[DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
[DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
[DllImport("gdi32.dll")]  public static extern int GetDeviceCaps(IntPtr h, int i);
'@ -ErrorAction SilentlyContinue
        $dc = [MadTweak.Ecran]::GetDC([IntPtr]::Zero)
        try {
            $l = [MadTweak.Ecran]::GetDeviceCaps($dc, 118)  # DESKTOPHORZRES
            $h = [MadTweak.Ecran]::GetDeviceCaps($dc, 117)  # DESKTOPVERTRES
        }
        finally { [MadTweak.Ecran]::ReleaseDC([IntPtr]::Zero, $dc) | Out-Null }
        if ($l -ge 640 -and $h -ge 480) { return @{ L = $l; H = $h } }
    }
    catch { }
    # Repli : résolution logique, ou 1920x1080 en dernier recours.
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction SilentlyContinue
        $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
        if ($b.Width -ge 640) { return @{ L = $b.Width; H = $b.Height } }
    }
    catch { }
    return @{ L = 1920; H = 1080 }
}

# --- Petites fabriques WPF (préfixe Sig- pour ne heurter aucun autre nom) ------
function New-SigPinceau { param([string]$Hex)
    New-Object System.Windows.Media.SolidColorBrush ([System.Windows.Media.ColorConverter]::ConvertFromString($Hex))
}
function New-SigGlow { param([string]$Couleur = "#FFE01008", [double]$Rayon = 40, [double]$Opacite = 1)
    $e = New-Object System.Windows.Media.Effects.DropShadowEffect
    $e.Color = [System.Windows.Media.ColorConverter]::ConvertFromString($Couleur)
    $e.BlurRadius = $Rayon; $e.ShadowDepth = 0; $e.Opacity = $Opacite
    $e
}
function New-SigCanvas { param([int]$L, [int]$H)
    $c = New-Object System.Windows.Controls.Canvas; $c.Width = $L; $c.Height = $H; $c
}
function Add-SigTexte {
    param($Canvas, [string]$Texte, [double]$Taille, [string]$Police, [string]$CouleurHex,
          [double]$X, [double]$Y, $Effet = $null, [double]$Opacite = 1, [string]$Poids = "Bold")
    $tb = New-Object System.Windows.Controls.TextBlock
    $tb.Text = $Texte
    $tb.FontFamily = New-Object System.Windows.Media.FontFamily $Police
    $tb.FontSize = $Taille
    $tb.FontWeight = [System.Windows.FontWeights]::$Poids
    $tb.Foreground = New-SigPinceau $CouleurHex
    $tb.Opacity = $Opacite
    if ($Effet) { $tb.Effect = $Effet }
    [System.Windows.Controls.Canvas]::SetLeft($tb, $X)
    [System.Windows.Controls.Canvas]::SetTop($tb, $Y)
    $Canvas.Children.Add($tb) | Out-Null
    $tb
}
function Add-SigLigne {
    param($Canvas, [double]$X1, [double]$Y1, [double]$X2, [double]$Y2, $Pinceau, [double]$Epaisseur = 3, $Effet = $null)
    $ln = New-Object System.Windows.Shapes.Line
    $ln.X1 = $X1; $ln.Y1 = $Y1; $ln.X2 = $X2; $ln.Y2 = $Y2
    $ln.Stroke = $Pinceau; $ln.StrokeThickness = $Epaisseur
    if ($Effet) { $ln.Effect = $Effet }
    $Canvas.Children.Add($ln) | Out-Null
}
function Add-SigFond {
    param($Canvas, [int]$L, [int]$H, [string]$Centre, [string]$Bord)
    $r = New-Object System.Windows.Shapes.Rectangle; $r.Width = $L; $r.Height = $H
    $g = New-Object System.Windows.Media.RadialGradientBrush
    $g.GradientOrigin = [System.Windows.Point]::new(0.5, 0.42)
    $g.Center = [System.Windows.Point]::new(0.5, 0.42)
    $g.RadiusX = 0.75; $g.RadiusY = 0.85
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($Centre), 0)))
    $g.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString($Bord), 1)))
    $r.Fill = $g
    $Canvas.Children.Add($r) | Out-Null
}
function Add-SigGrille {
    param($Canvas, [int]$L, [int]$H, [int]$Pas, [string]$Couleur)
    $p = New-SigPinceau $Couleur
    for ($x = 0; $x -le $L; $x += $Pas) { Add-SigLigne $Canvas $x 0 $x $H $p 1 }
    for ($y = 0; $y -le $H; $y += $Pas) { Add-SigLigne $Canvas 0 $y $L $y $p 1 }
}
function Add-SigPluie {
    # Pluie de code façon Matrix. Graine fixe = signature reproductible. Les couleurs
    # viennent de la palette (dérivée d'une couleur de base), pour un fond assorti au thème.
    param($Canvas, [int]$L, [int]$H, [int]$Graine, [hashtable]$Palette)
    $rand = New-Object System.Random $Graine
    $glyphes = @()
    0x30A0..0x30FF | ForEach-Object { $glyphes += [char]$_ }   # katakana
    "0123456789ABCDEF".ToCharArray() | ForEach-Object { $glyphes += $_ }
    $taille = 22; $pas = 26
    for ($x = 10; $x -lt $L; $x += $pas) {
        $depart = $rand.Next(-40, $H); $long = $rand.Next(8, 34)
        for ($i = 0; $i -lt $long; $i++) {
            $y = $depart - $i * $taille
            if ($y -lt -$taille -or $y -gt $H) { continue }
            $g = $glyphes[$rand.Next(0, $glyphes.Count)]
            if ($i -eq 0) { $c = $Palette.RainHead; $o = 1.0 }
            elseif ($i -lt 3) { $c = $Palette.RainMid; $o = 0.95 }
            else { $c = $Palette.RainBody; $o = [Math]::Max(0.08, 0.9 - $i * 0.04) }
            Add-SigTexte $Canvas "$g" $taille "Consolas" $c $x $y $null $o "Normal" | Out-Null
        }
    }
}
function Add-SigCrochets {
    param($Canvas, [int]$L, [int]$H, [int]$Marge, [int]$Taille, [string]$Couleur)
    $p = New-SigPinceau $Couleur; $e = New-SigGlow $Couleur 10 0.8
    $ga = $Marge; $dr = $L - $Marge; $ht = $Marge; $bs = $H - $Marge
    Add-SigLigne $Canvas $ga $ht ($ga + $Taille) $ht $p 3 $e; Add-SigLigne $Canvas $ga $ht $ga ($ht + $Taille) $p 3 $e
    Add-SigLigne $Canvas $dr $ht ($dr - $Taille) $ht $p 3 $e; Add-SigLigne $Canvas $dr $ht $dr ($ht + $Taille) $p 3 $e
    Add-SigLigne $Canvas $ga $bs ($ga + $Taille) $bs $p 3 $e; Add-SigLigne $Canvas $ga $bs $ga ($bs - $Taille) $p 3 $e
    Add-SigLigne $Canvas $dr $bs ($dr - $Taille) $bs $p 3 $e; Add-SigLigne $Canvas $dr $bs $dr ($bs - $Taille) $p 3 $e
}
function Add-SigNom {
    # « MadTrix » + filet + « R O G » + tagline, centrés. Taille proportionnelle à
    # la largeur pour rester juste sur toutes les résolutions. Couleurs = palette.
    param($Canvas, [int]$L, [int]$H, [hashtable]$Palette)
    $cx = $L / 2; $cy = $H / 2
    $tailleNom = [Math]::Round($L * 0.094)   # ~240 px sur 2560
    $halo = Add-SigTexte $Canvas "MadTrix" $tailleNom "Segoe UI Black" $Palette.Glow 0 0 (New-SigGlow $Palette.Halo ($tailleNom*0.38) 0.9) 0.9 "Black"
    $halo.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    $w = $halo.DesiredSize.Width; $h = $halo.DesiredSize.Height
    [System.Windows.Controls.Canvas]::SetLeft($halo, $cx - $w/2); [System.Windows.Controls.Canvas]::SetTop($halo, $cy - $h/2)
    Add-SigTexte $Canvas "MadTrix" $tailleNom "Segoe UI Black" $Palette.NomNet ($cx - $w/2) ($cy - $h/2) (New-SigGlow $Palette.Glow ($tailleNom*0.1) 1) 1 "Black" | Out-Null

    $filet = New-Object System.Windows.Shapes.Rectangle
    $filet.Width = $w * 0.9; $filet.Height = [Math]::Max(3, $L*0.0016)
    $filet.Fill = New-SigPinceau $Palette.Filet; $filet.Effect = New-SigGlow $Palette.Glow 16 1
    [System.Windows.Controls.Canvas]::SetLeft($filet, $cx - ($w*0.9)/2)
    [System.Windows.Controls.Canvas]::SetTop($filet, $cy + $h/2 - 10)
    $Canvas.Children.Add($filet) | Out-Null

    $rog = Add-SigTexte $Canvas "R  O  G" ($tailleNom*0.19) "Bahnschrift" $Palette.Rog 0 0 (New-SigGlow $Palette.Glow 18 0.9) 1 "SemiBold"
    $rog.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    [System.Windows.Controls.Canvas]::SetLeft($rog, $cx - $rog.DesiredSize.Width/2)
    [System.Windows.Controls.Canvas]::SetTop($rog, $cy + $h/2 + 8)

    $tag = Add-SigTexte $Canvas "// REPUBLIC OF GAMERS  -  SYSTEME OPTIMISE" ($tailleNom*0.083) "Consolas" $Palette.Tagline 0 0 $null 0.85 "Normal"
    $tag.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    [System.Windows.Controls.Canvas]::SetLeft($tag, $cx - $tag.DesiredSize.Width/2)
    [System.Windows.Controls.Canvas]::SetTop($tag, $cy + $h/2 + 8 + $rog.DesiredSize.Height + 14)
}

function ConvertTo-HexSig {
    param([int]$R, [int]$G, [int]$B, [string]$Alpha = "FF")
    "#{0}{1:X2}{2:X2}{3:X2}" -f $Alpha,
        [int][Math]::Min(255, [Math]::Max(0, $R)),
        [int][Math]::Min(255, [Math]::Max(0, $G)),
        [int][Math]::Min(255, [Math]::Max(0, $B))
}

function Get-PaletteSignature {
    # Dérive TOUTES les couleurs du fond à partir d'une seule couleur de base.
    # C'est ce qui permet un fond assorti à chaque thème sans dupliquer le dessin.
    param([Parameter(Mandatory)][string]$Base)   # "#RRGGBB" ou "#AARRGGBB"
    $col = [System.Windows.Media.ColorConverter]::ConvertFromString($Base)
    $r = [int]$col.R; $g = [int]$col.G; $b = [int]$col.B
    $tint  = { param($t) $n = Get-Nuance $r $g $b (1 + $t); ConvertTo-HexSig $n[0] $n[1] $n[2] }
    $shade = { param($s) $n = Get-Nuance $r $g $b (1 - $s); ConvertTo-HexSig $n[0] $n[1] $n[2] }
    # Tagline : version douce, mélangée vers un gris moyen.
    $tag = ConvertTo-HexSig ([int]($r*0.45 + 144*0.55)) ([int]($g*0.45 + 144*0.55)) ([int]($b*0.45 + 144*0.55))
    @{
        FondCentre = (& $shade 0.88)                 # fond radial : centre très sombre teinté
        FondBord   = "#FF040405"                     # bords quasi noirs
        RainHead   = (& $tint 0.85)                  # tête de goutte : presque blanche
        RainMid    = (& $tint 0.30)                  # corps clair
        RainBody   = (ConvertTo-HexSig $r $g $b)     # corps = couleur de base
        Halo       = (& $shade 0.20)
        Glow       = (ConvertTo-HexSig $r $g $b)
        NomNet     = "#FFF6F2F2"                      # « MadTrix » net : blanc cassé
        Filet      = (ConvertTo-HexSig $r $g $b)
        Rog        = (& $tint 0.14)
        Tagline    = $tag
        GrilleArgb = (ConvertTo-HexSig $r $g $b "22") # grille faible (alpha 0x22)
        Crochets   = (ConvertTo-HexSig $r $g $b)
    }
}

$script:StylesSignature = @("matrix", "hud", "neon")

function New-FondSignature {
    # Dessine un fond et l'enregistre en PNG. Retourne le chemin.
    param(
        [Parameter(Mandatory)][ValidateSet("matrix", "hud", "neon")][string]$Style,
        [Parameter(Mandatory)][int]$Largeur,
        [Parameter(Mandatory)][int]$Hauteur,
        [Parameter(Mandatory)][string]$Chemin,
        # Couleur de base du fond. Défaut = rouge MadTrix historique.
        [string]$Couleur = "#E01008"
    )
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase -ErrorAction Stop
    $pal = Get-PaletteSignature -Base $Couleur

    $c = New-SigCanvas $Largeur $Hauteur
    switch ($Style) {
        "matrix" {
            Add-SigFond $c $Largeur $Hauteur $pal.FondCentre $pal.FondBord
            Add-SigPluie $c $Largeur $Hauteur 7 $pal
        }
        "hud" {
            Add-SigFond $c $Largeur $Hauteur $pal.FondCentre $pal.FondBord
            Add-SigGrille $c $Largeur $Hauteur 64 $pal.GrilleArgb
            Add-SigPluie $c $Largeur $Hauteur 21 $pal
            Add-SigCrochets $c $Largeur $Hauteur 70 90 $pal.Crochets
        }
        "neon" {
            Add-SigFond $c $Largeur $Hauteur $pal.FondCentre $pal.FondBord
            Add-SigGrille $c $Largeur $Hauteur 90 $pal.GrilleArgb
        }
    }
    Add-SigNom $c $Largeur $Hauteur $pal

    $c.Measure([System.Windows.Size]::new($Largeur, $Hauteur))
    $c.Arrange([System.Windows.Rect]::new(0, 0, $Largeur, $Hauteur))
    $c.UpdateLayout()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($Largeur, $Hauteur, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($c)
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [System.IO.File]::Create($Chemin)
    try { $enc.Save($fs) } finally { $fs.Dispose() }
    return $Chemin
}

function Set-FondEcran {
    # Applique le fond via SystemParametersInfo (effet immédiat), après avoir noté
    # le fond précédent pour pouvoir le remettre. On sauvegarde AUSSI dans le JSON
    # via Save-EtatAvant, pour que la « Restauration EXACTE » le connaisse.
    param([Parameter(Mandatory)][string]$Chemin)
    Add-Type -Namespace MadTweak -Name Bureau -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@ -ErrorAction SilentlyContinue

    # Mémorise le fond d'avant, une seule fois (le premier vu est le vrai).
    $memoire = Join-Path $script:DossierDonnees "fond-precedent.txt"
    if (-not (Test-Path $memoire)) {
        $ancien = (Get-ItemProperty "HKCU:\Control Panel\Desktop" -Name WallPaper -ErrorAction SilentlyContinue).WallPaper
        [System.IO.File]::WriteAllText($memoire, "$ancien")
    }
    Save-EtatAvant -Path "HKCU:\Control Panel\Desktop" -Name "WallPaper"
    Save-EtatAvant -Path "HKCU:\Control Panel\Desktop" -Name "WallpaperStyle"
    Save-EtatAvant -Path "HKCU:\Control Panel\Desktop" -Name "TileWallpaper"

    # 10 = « Remplir », 0 = pas de mosaïque : le fond couvre tout l'écran.
    Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name WallpaperStyle -Value "10"
    Set-ItemProperty "HKCU:\Control Panel\Desktop" -Name TileWallpaper -Value "0"
    # 0x0014 = SPI_SETDESKWALLPAPER ; 3 = met à jour le registre ET rafraîchit.
    $r = [MadTweak.Bureau]::SystemParametersInfo(0x0014, 0, $Chemin, 3)
    if ($r -eq 0) { throw "Windows a refusé d'appliquer le fond d'écran (SystemParametersInfo a renvoyé 0)." }
}

function Restore-FondPrecedent {
    # Remet le fond d'écran d'avant, avec effet immédiat.
    $memoire = Join-Path $script:DossierDonnees "fond-precedent.txt"
    if (-not (Test-Path $memoire)) { throw "Aucun fond précédent mémorisé : ce script n'a pas encore changé ton fond d'écran." }
    $ancien = [System.IO.File]::ReadAllText($memoire).Trim()
    Add-Type -Namespace MadTweak -Name Bureau -MemberDefinition @'
[DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
'@ -ErrorAction SilentlyContinue
    [MadTweak.Bureau]::SystemParametersInfo(0x0014, 0, $ancien, 3) | Out-Null
    if ($ancien) { Write-Etat "Fond d'écran précédent restauré." -Niveau OK }
    else { Write-Etat "Il n'y avait pas de fond d'écran avant (fond uni) : l'écran est remis ainsi." -Niveau Info }
}

# ------------------------------------------------------------------------------
# ACCENT WINDOWS — couleur des barres de titre, de la barre des tâches et du Démarrer
#
# Différent du sélecteur de thème de CETTE fenêtre : ici on repeint Windows lui-même.
# Tout passe par Set-RegValue, donc « Annuler » sait tout remettre (Save-EtatAvant).
# ------------------------------------------------------------------------------
$script:AccentsWindows = [ordered]@{
    "ROG Rouge"      = @{ R = 226; G = 0;   B = 24  }
    "ROG Bleu"       = @{ R = 0;   G = 120; B = 215 }
    "Cyan Cyber"     = @{ R = 0;   G = 200; B = 235 }
    "Vert Émeraude"  = @{ R = 16;  G = 185; B = 129 }
    "Violet Néon"    = @{ R = 160; G = 90;  B = 220 }
    "Orange"         = @{ R = 255; G = 130; B = 0   }
    "Rose Néon"      = @{ R = 255; G = 0;   B = 120 }
}

function ConvertTo-DwordCouleur {
    # Un DWORD de registre est un entier 32 bits SIGNÉ côté PowerShell : une couleur
    # avec alpha 0xFF déborde de int32. On passe par les OCTETS (little-endian) pour
    # écrire exactement les bons bits sans exception d'overflow.
    #   ABGR (accent)      -> octets R, G, B, FF
    #   ARGB (colorization)-> octets B, G, R, FF
    param([byte]$O0, [byte]$O1, [byte]$O2, [byte]$O3 = 0xFF)
    return [System.BitConverter]::ToInt32([byte[]]@($O0, $O1, $O2, $O3), 0)
}

function Get-Nuance {
    # Éclaircit (facteur > 1, mélange vers le blanc) ou assombrit (facteur < 1).
    param([int]$R, [int]$G, [int]$B, [double]$Facteur)
    if ($Facteur -ge 1) {
        $t = [Math]::Min(1, $Facteur - 1)
        return @([int]($R + (255 - $R) * $t), [int]($G + (255 - $G) * $t), [int]($B + (255 - $B) * $t))
    }
    return @([int]($R * $Facteur), [int]($G * $Facteur), [int]($B * $Facteur))
}

# ------------------------------------------------------------------------------
# CLAVIER RGB ASUS ROG (Aura) — pilotage HID direct, sans logiciel tiers.
#
# Les claviers des portables ROG (contrôleur ITE, VID_0B05/PID_19B6) exposent une
# interface vendeur en page d'usage 0xFF31 : on y écrit un rapport 0x5D
# (b3 = effet + couleur, b4 = appliquer, b5 = mémoriser). C'est le canal qu'utilisent
# G-Helper et asusctl. Windows NE SAIT PAS piloter ce clavier (aucune interface
# LampArray / Éclairage dynamique) et OpenRGB ne le reconnaît pas : le HID direct
# est la seule voie. La luminosité, elle, passe par l'ACPI WMI ASUS (admin requis).
# NB : le rétroéclairage doit être allumé pour voir la couleur (Fn + F3/F4).
# ------------------------------------------------------------------------------
function Initialize-TypeClavierAura {
    # Compile (une seule fois) le pilote HID. Séparé pour que la détection, la
    # couleur, les effets et la luminosité partagent le même type compilé.
    if (([System.Management.Automation.PSTypeName]'MadTweak.ClavierAura').Type) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MadTweak {
  public static class ClavierAura {
    [StructLayout(LayoutKind.Sequential)]
    struct SP_DEVICE_INTERFACE_DATA { public int cbSize; public Guid InterfaceClassGuid; public int Flags; public IntPtr Reserved; }
    [StructLayout(LayoutKind.Sequential)]
    struct HIDD_ATTRIBUTES { public int Size; public ushort VendorID; public ushort ProductID; public ushort VersionNumber; }
    [StructLayout(LayoutKind.Sequential)]
    struct HIDP_CAPS {
      public ushort Usage; public ushort UsagePage;
      public ushort InputReportByteLength; public ushort OutputReportByteLength; public ushort FeatureReportByteLength;
      [MarshalAs(UnmanagedType.ByValArray, SizeConst = 17)] public ushort[] Reserved;
      public ushort NumberLinkCollectionNodes;
      public ushort a1,a2,a3,a4,a5,a6,a7,a8,a9;
    }
    [DllImport("hid.dll")] static extern void HidD_GetHidGuid(out Guid g);
    [DllImport("setupapi.dll", CharSet=CharSet.Auto)] static extern IntPtr SetupDiGetClassDevs(ref Guid g, IntPtr e, IntPtr h, int f);
    [DllImport("setupapi.dll", CharSet=CharSet.Auto)] static extern bool SetupDiEnumDeviceInterfaces(IntPtr h, IntPtr d, ref Guid g, int i, ref SP_DEVICE_INTERFACE_DATA a);
    [DllImport("setupapi.dll", CharSet=CharSet.Auto)] static extern bool SetupDiGetDeviceInterfaceDetail(IntPtr h, ref SP_DEVICE_INTERFACE_DATA a, IntPtr d, int ds, ref int rq, IntPtr dd);
    [DllImport("setupapi.dll")] static extern bool SetupDiDestroyDeviceInfoList(IntPtr h);
    [DllImport("kernel32.dll", CharSet=CharSet.Auto)] static extern IntPtr CreateFile(string n, uint acc, uint sh, IntPtr sec, uint disp, uint fl, IntPtr t);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    [DllImport("hid.dll")] static extern bool HidD_GetAttributes(IntPtr h, ref HIDD_ATTRIBUTES a);
    [DllImport("hid.dll")] static extern bool HidD_GetPreparsedData(IntPtr h, out IntPtr p);
    [DllImport("hid.dll")] static extern bool HidD_FreePreparsedData(IntPtr p);
    [DllImport("hid.dll")] static extern int  HidP_GetCaps(IntPtr p, out HIDP_CAPS c);
    [DllImport("hid.dll")] static extern bool HidD_SetFeature(IntPtr h, byte[] b, int len);
    [DllImport("hid.dll")] static extern bool HidD_SetOutputReport(IntPtr h, byte[] b, int len);
    const int DIGCF_PRESENT = 0x2, DIGCF_DEVICEINTERFACE = 0x10;
    const uint GENERIC_WRITE = 0x40000000, GENERIC_READ = 0x80000000, FILE_SHARE_RW = 0x3, OPEN_EXISTING = 3;

    static IntPtr OpenAura() { return OpenByUsage(0x0079); }
    static IntPtr OpenByUsage(ushort want) {
      Guid hid; HidD_GetHidGuid(out hid);
      IntPtr set = SetupDiGetClassDevs(ref hid, IntPtr.Zero, IntPtr.Zero, DIGCF_PRESENT | DIGCF_DEVICEINTERFACE);
      var da = new SP_DEVICE_INTERFACE_DATA(); da.cbSize = Marshal.SizeOf(da);
      int idx = 0; IntPtr found = (IntPtr)(-1);
      while (SetupDiEnumDeviceInterfaces(set, IntPtr.Zero, ref hid, idx++, ref da)) {
        int req = 0;
        SetupDiGetDeviceInterfaceDetail(set, ref da, IntPtr.Zero, 0, ref req, IntPtr.Zero);
        if (req <= 0) continue;
        IntPtr buf = Marshal.AllocHGlobal(req);
        Marshal.WriteInt32(buf, IntPtr.Size == 8 ? 8 : 6);
        string path = null;
        if (SetupDiGetDeviceInterfaceDetail(set, ref da, buf, req, ref req, IntPtr.Zero))
          path = Marshal.PtrToStringAuto(new IntPtr(buf.ToInt64() + 4));
        Marshal.FreeHGlobal(buf);
        if (path == null) continue;
        IntPtr h = CreateFile(path, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_RW, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (h == (IntPtr)(-1)) continue;
        var at = new HIDD_ATTRIBUTES(); at.Size = Marshal.SizeOf(at);
        bool match = false;
        if (HidD_GetAttributes(h, ref at) && at.VendorID == 0x0B05 && at.ProductID == 0x19B6) {
          IntPtr pp;
          if (HidD_GetPreparsedData(h, out pp)) {
            HIDP_CAPS caps; HidP_GetCaps(pp, out caps); HidD_FreePreparsedData(pp);
            if (caps.UsagePage == 0xFF31 && caps.Usage == want) match = true;
          }
        }
        if (match) { found = h; break; }
        CloseHandle(h);
      }
      SetupDiDestroyDeviceInfoList(set);
      return found;
    }

    static byte[] Frame(byte[] payload) { var b = new byte[64]; Array.Copy(payload, b, payload.Length); return b; }
    static bool Send(IntPtr h, byte[] payload) {
      var b = Frame(payload);
      bool ok = HidD_SetFeature(h, b, b.Length);
      if (!ok) ok = HidD_SetOutputReport(h, b, b.Length);
      return ok;
    }

    public static bool SetEffect(byte mode, byte r, byte g, byte b, byte speed) {
      IntPtr h = OpenAura();
      if (h == (IntPtr)(-1)) return false;
      try {
        bool ok = Send(h, new byte[]{0x5d, 0xb3, 0x00, mode, r, g, b, speed, 0x00, 0x00, r, g, b}); // effet + couleur
        Send(h, new byte[]{0x5d, 0xb4});   // appliquer
        Send(h, new byte[]{0x5d, 0xb5});   // mémoriser
        return ok;
      } finally { CloseHandle(h); }
    }
    public static bool SetColor(byte r, byte g, byte b) { return SetEffect(0x00, r, g, b, 0x00); }
    public static bool Present() {
      IntPtr h = OpenAura();
      if (h == (IntPtr)(-1)) return false;
      CloseHandle(h); return true;
    }
  }
}
'@ -ErrorAction Stop
}

# Effets supportés par le contrôleur N-Key (nom affiché -> octet « mode »). On s'en
# tient au socle universel de ces claviers (statique, respiration, stroboscope,
# arc-en-ciel) : les effets exotiques (comète, pluie...) varient selon le modèle et
# ne seraient qu'un placebo s'ils ne s'animent pas.
$script:EffetsClavier = [ordered]@{
    "Statique"    = 0x00
    "Respiration" = 0x01
    "Stroboscope" = 0x02
    "Arc-en-ciel" = 0x03
}
$script:VitessesClavier = [ordered]@{ "Lent" = 0xE1; "Moyen" = 0xEB; "Rapide" = 0xF5 }

# Luminosité du clavier en % : appliquée en ATTÉNUANT la couleur envoyée (la commande
# de niveau du firmware est ignorée sur ce matériel). Mémorisée ici pour que la
# synchronisation sur l'accent respecte le dernier réglage choisi.
$script:LuminositeClavier = 100

function Test-ClavierAura {
    # $true si un clavier RGB ASUS ROG compatible (N-Key ITE) répond présent.
    # C'est ce test qui décide d'AFFICHER ou non la page « Clavier RGB » de l'interface.
    try { Initialize-TypeClavierAura } catch { return $false }
    try { return [MadTweak.ClavierAura]::Present() } catch { return $false }
}

function Set-ClavierAura {
    # Pose une couleur et/ou un effet sur le clavier Aura. Best-effort : renvoie
    # $false si aucun clavier compatible n'est présent, sans faire échouer l'appelant.
    # -Luminosite (0-100 %) atténue la couleur : c'est notre réglage de luminosité,
    # la commande de niveau du firmware étant ignorée sur ce clavier.
    param(
        [Parameter(Mandatory)][int]$R, [Parameter(Mandatory)][int]$G, [Parameter(Mandatory)][int]$B,
        [string]$Mode = "Statique", [string]$Vitesse = "Moyen",
        [ValidateRange(0, 100)][int]$Luminosite = $script:LuminositeClavier
    )
    if (-not $script:EffetsClavier.Contains($Mode)) { $Mode = "Statique" }
    if (-not $script:VitessesClavier.Contains($Vitesse)) { $Vitesse = "Moyen" }
    $R = [int]($R * $Luminosite / 100)
    $G = [int]($G * $Luminosite / 100)
    $B = [int]($B * $Luminosite / 100)
    if ($script:Simulation) {
        Write-Simu "poserait le clavier RGB ASUS : effet « $Mode », couleur RVB $R,$G,$B, vitesse $Vitesse, luminosité $Luminosite%"
        return $true
    }
    try { Initialize-TypeClavierAura } catch { return $false }
    $m = [byte]$script:EffetsClavier[$Mode]
    $v = [byte]$script:VitessesClavier[$Vitesse]
    return [MadTweak.ClavierAura]::SetEffect($m, [byte]$R, [byte]$G, [byte]$B, $v)
}

# NOTE : la commande de NIVEAU de rétroéclairage du firmware et les modes de
# performance (Turbo/Silencieux) restent écartés : sur ce matériel, les commandes
# ASUS correspondantes (WMI DEVS, pilote \\.\ATKACPI) sont ACCEPTÉES mais SANS effet
# hors écosystème ASUS complet -- ce ne serait qu'un placebo (a fortiori sur du
# thermique). La luminosité du CLAVIER est donc obtenue en atténuant la couleur
# (Set-ClavierAura -Luminosite), ce qui fonctionne. Les courbes de ventilateur
# relèvent d'un outil dédié (G-Helper).

# ------------------------------------------------------------------------------
# LUMINOSITÉ DE L'ÉCRAN — via WMI (WmiMonitorBrightnessMethods) : natif et fiable,
# ne dépend d'aucun pilote tiers. Disponible sur les écrans pilotables (portables).
# ------------------------------------------------------------------------------
function Test-EcranReglable {
    try { $null = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop; return $true }
    catch { return $false }
}

function Get-LuminositeEcran {
    try { return [int](Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightness -ErrorAction Stop).CurrentBrightness }
    catch { return -1 }
}

function Set-LuminositeEcran {
    param([Parameter(Mandatory)][ValidateRange(0, 100)][int]$Niveau)
    if ($script:Simulation) { Write-Simu "réglerait la luminosité de l'écran sur $Niveau%"; return $true }
    try {
        $m = Get-CimInstance -Namespace root/wmi -ClassName WmiMonitorBrightnessMethods -ErrorAction Stop
        Invoke-CimMethod -InputObject $m -MethodName WmiSetBrightness -Arguments @{ Brightness = [byte]$Niveau; Timeout = [uint32]0 } -ErrorAction Stop | Out-Null
        return $true
    }
    catch { return $false }
}

# ------------------------------------------------------------------------------
# MODE D'ALIMENTATION WINDOWS — le curseur « Mode d'alimentation » des Paramètres.
# Natif (PowerSetActiveOverlayScheme), fiable, sans aucun ASUS.
#
# ATTENTION : ce n'est PAS le « Turbo » ASUS. Le Turbo ASUS pilote les ventilateurs
# et le TDP via l'EC, et il est INACCESSIBLE à un script isolé -- mesuré sur ce
# matériel : sous charge CPU, la fréquence est IDENTIQUE en Silencieux et en Turbo
# (le driver ASUS ignore la commande hors Armoury Crate / G-Helper). Ce réglage-ci
# agit sur le boost et l'EPP du CPU côté Windows, ce qui est réel mais différent.
# ------------------------------------------------------------------------------
$script:ModesAlimentation = [ordered]@{
    "Économie d'énergie" = "961cc777-2547-4f9d-8174-7d86181b8a7a"
    "Équilibré"          = "00000000-0000-0000-0000-000000000000"
    "Performances"       = "ded574b5-45a0-4f42-8737-46345c09c238"
}

function Initialize-TypeAlimentation {
    if (([System.Management.Automation.PSTypeName]'MadTweak.Alim').Type) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MadTweak {
  public static class Alim {
    [DllImport("powrprof.dll")] public static extern uint PowerSetActiveOverlayScheme(Guid overlay);
  }
}
'@ -ErrorAction Stop
}

function Set-ModeAlimentation {
    # Applique un mode d'alimentation Windows (overlay). Best-effort : $false si l'API
    # échoue. NB : « Équilibré » = GUID nul, qui retire tout overlay (= défaut).
    param([Parameter(Mandatory)][string]$Mode)
    if (-not $script:ModesAlimentation.Contains($Mode)) { throw "Mode d'alimentation « $Mode » inconnu." }
    if ($script:Simulation) { Write-Simu "réglerait le mode d'alimentation Windows sur « $Mode »"; return $true }
    try {
        Initialize-TypeAlimentation
        return ([MadTweak.Alim]::PowerSetActiveOverlayScheme([Guid]$script:ModesAlimentation[$Mode]) -eq 0)
    }
    catch { return $false }
}

# ------------------------------------------------------------------------------
# CAPTEURS (lecture seule) — GPU via nvidia-smi (sans admin, fiable) et ventilateurs
# via l'ACPI ASUS (ATKACPI DSTS, admin requis). La vraie température des cœurs CPU
# n'est PAS exposée sans pilote dédié (HWiNFO/LibreHardwareMonitor) : on ne l'invente
# pas. La zone thermique ACPI, elle, ne reflète qu'un point carte mère générique.
# ------------------------------------------------------------------------------
function Initialize-TypeAcpi {
    if (([System.Management.Automation.PSTypeName]'MadTweak.Acpi').Type) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
namespace MadTweak {
  public static class Acpi {
    [DllImport("kernel32.dll", CharSet=CharSet.Auto, SetLastError=true)]
    static extern IntPtr CreateFile(string n, uint a, uint s, IntPtr se, uint d, uint f, IntPtr t);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool DeviceIoControl(IntPtr h, uint c, byte[] i, uint isz, byte[] o, uint osz, out uint r, IntPtr ov);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);
    const uint GR=0x80000000, GW=0x40000000, OPEN=3, IOCTL=0x0022240C, DSTS=0x53545344;
    public static long Dsts(uint id) {
      IntPtr h = CreateFile(@"\\.\ATKACPI", GR|GW, 0, IntPtr.Zero, OPEN, 0, IntPtr.Zero);
      if (h == (IntPtr)(-1)) return -2;
      try {
        byte[] b = new byte[12];
        BitConverter.GetBytes(DSTS).CopyTo(b,0); BitConverter.GetBytes((uint)4).CopyTo(b,4); BitConverter.GetBytes(id).CopyTo(b,8);
        byte[] o = new byte[16]; uint r;
        if (!DeviceIoControl(h, IOCTL, b, (uint)b.Length, o, (uint)o.Length, out r, IntPtr.Zero)) return -3;
        return BitConverter.ToUInt32(o, 0);
      } finally { CloseHandle(h); }
    }
  }
}
'@ -ErrorAction Stop
}

function Get-CapteursMateriel {
    # Renvoie @{ GpuTemp; GpuLoad; FanCpu; FanGpu } ; $null pour l'indisponible.
    $r = @{ GpuTemp = $null; GpuLoad = $null; FanCpu = $null; FanGpu = $null }
    try {
        $exe = (Get-Command nvidia-smi -ErrorAction SilentlyContinue).Source
        if (-not $exe -and (Test-Path "$env:SystemRoot\System32\nvidia-smi.exe")) { $exe = "$env:SystemRoot\System32\nvidia-smi.exe" }
        if ($exe) {
            $o = @(& $exe --query-gpu=temperature.gpu,utilization.gpu --format=csv,noheader,nounits 2>$null)[0]
            if ($o) { $p = ($o -split ',').Trim(); $r.GpuTemp = [int]$p[0]; $r.GpuLoad = [int]$p[1] }
        }
    }
    catch { }
    try {
        Initialize-TypeAcpi
        $c = [MadTweak.Acpi]::Dsts(0x00110013); if ($c -gt 0) { $r.FanCpu = ($c -band 0xFF) * 100 }
        $g = [MadTweak.Acpi]::Dsts(0x00110014); if ($g -gt 0) { $r.FanGpu = ($g -band 0xFF) * 100 }
    }
    catch { }
    return $r
}

function Set-AccentWindows {
    param([Parameter(Mandatory)][string]$Nom)
    if (-not $script:AccentsWindows.Contains($Nom)) { throw "Accent « $Nom » inconnu." }
    $c = $script:AccentsWindows[$Nom]
    $R = $c.R; $G = $c.G; $B = $c.B

    $accent = ConvertTo-DwordCouleur $R $G $B 0xFF           # ABGR
    $coloriz = ConvertTo-DwordCouleur $B $G $R 0xFF          # ARGB
    $sombre = Get-Nuance $R $G $B 0.60
    $startDword = ConvertTo-DwordCouleur $sombre[0] $sombre[1] $sombre[2] 0xFF

    # Palette des 8 nuances (clair -> foncé), la couleur choisie au centre.
    $facteurs = @(1.6, 1.4, 1.2, 1.0, 0.82, 0.66, 0.52, 0.40)
    $palette = New-Object System.Collections.Generic.List[byte]
    foreach ($f in $facteurs) {
        $n = Get-Nuance $R $G $B $f
        $palette.Add([byte][Math]::Min(255, $n[0]))
        $palette.Add([byte][Math]::Min(255, $n[1]))
        $palette.Add([byte][Math]::Min(255, $n[2]))
        $palette.Add([byte]0xFF)
    }

    $kAccent = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Accent"
    $kDWM = "HKCU:\Software\Microsoft\Windows\DWM"
    $kPerso = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"

    if ($script:Simulation) {
        Write-Simu "appliquerait l'accent Windows « $Nom » (RVB $R,$G,$B) : barres de titre, barre des tâches, Démarrer, et synchroniserait le clavier RGB ASUS"
        return
    }

    Set-RegValue -Path $kAccent -Name "AccentColorMenu" -Value $accent
    Set-RegValue -Path $kAccent -Name "StartColorMenu" -Value $startDword
    Set-RegValue -Path $kAccent -Name "AccentPalette" -Value ([byte[]]$palette.ToArray()) -Type Binary
    Set-RegValue -Path $kDWM -Name "AccentColor" -Value $accent
    Set-RegValue -Path $kDWM -Name "ColorizationColor" -Value $coloriz
    Set-RegValue -Path $kDWM -Name "ColorizationAfterglow" -Value $coloriz
    Set-RegValue -Path $kDWM -Name "ColorPrevalence" -Value 1          # accent sur les barres de titre
    # La barre des tâches et le menu Démarrer ne prennent l'accent qu'en thème SOMBRE.
    Set-RegValue -Path $kPerso -Name "ColorPrevalence" -Value 1
    Set-RegValue -Path $kPerso -Name "SystemUsesLightTheme" -Value 0
    Set-RegValue -Path $kPerso -Name "AppsUseLightTheme" -Value 0

    Publish-ChangementCouleur

    # Synchronise le clavier RGB ASUS (Aura) sur la même couleur, en HID direct.
    # Best-effort : sur une machine sans clavier ROG compatible, on ignore sans
    # faire échouer l'accent. Le RGB clavier n'est PAS dans la sauvegarde JSON
    # (c'est du matériel, pas du registre) : « Retour au défaut » le remet en blanc.
    try {
        if (Set-ClavierAura -R $R -G $G -B $B) {
            Write-Etat "Clavier RGB ASUS synchronisé sur l'accent (RVB $R,$G,$B)." -Niveau OK
        }
        else {
            Write-Etat "Aucun clavier RGB ASUS compatible détecté : synchronisation du clavier ignorée." -Niveau Info
        }
    }
    catch {
        Write-Etat "Synchronisation du clavier ignorée : $($_.Exception.Message)" -Niveau Avert
    }

    Write-Etat "Accent « $Nom » appliqué (RVB $R,$G,$B). Thème sombre activé pour que la barre des tâches se colore aussi." -Niveau OK
}

function Restore-AccentWindows {
    # Remet l'accent Windows à un état neutre : plus de couleur sur les barres.
    # La RESTAURATION EXACTE (menu Annuler) rend l'état précis d'avant ; ceci est
    # le retour « défaut Windows » immédiat.
    if ($script:Simulation) { Write-Simu "retirerait l'accent des barres, et remettrait le clavier RGB en blanc statique"; return }
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\DWM" -Name "ColorPrevalence" -Value 0
    Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" -Name "ColorPrevalence" -Value 0
    Publish-ChangementCouleur
    # Le clavier ne se « lit » pas : on ne peut pas restaurer l'effet Aura exact
    # d'avant (arc-en-ciel, respiration...). On le remet en blanc statique, neutre.
    try { Set-ClavierAura -R 255 -G 255 -B 255 | Out-Null } catch { }
    Write-Etat "Accent retiré des barres, clavier remis en blanc. Pour l'état EXACT d'avant, utilise « Restauration EXACTE » (menu Annuler). L'effet Aura d'origine du clavier (animé) n'est pas récupérable par cette voie." -Niveau Info
}

function Publish-ChangementCouleur {
    # Diffuse le changement pour qu'il s'applique sans fermer la session.
    Add-Type -Namespace MadTweak -Name Couleur -MemberDefinition @'
[DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Auto)]
public static extern System.IntPtr SendMessageTimeout(System.IntPtr hWnd, uint Msg, System.IntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out System.IntPtr lpdwResult);
'@ -ErrorAction SilentlyContinue
    $HWND_BROADCAST = [System.IntPtr]0xFFFF
    $WM_SETTINGCHANGE = 0x001A
    $out = [System.IntPtr]::Zero
    foreach ($sig in @("ImmersiveColorSet", "WindowsThemeElement")) {
        [MadTweak.Couleur]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [System.IntPtr]::Zero, $sig, 2, 200, [ref]$out) | Out-Null
    }

    # Les barres de TITRE se recolorent tout de suite via DWM. Mais la BARRE DES
    # TÂCHES et le menu Démarrer ne relisent la couleur d'accent qu'au redémarrage
    # du shell : sans ça, la barre garde l'ancienne couleur (bug « barre rouge
    # alors que l'accent est bleu »). On relance donc l'Explorateur. La fenêtre
    # MadTweak (autre processus) n'est pas touchée ; seuls la barre et le bureau
    # clignotent une seconde.
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 900
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Start-Process explorer.exe
    }
}

function Menu-AccentWindows {
    Clear-Host
    Write-Host "=== ACCENT WINDOWS (couleur des barres) ===" -ForegroundColor Cyan
    Write-Host "  Colore les barres de titre, la barre des tâches et le menu Démarrer." -ForegroundColor DarkGray
    Write-Host "  + synchronise le clavier RGB ASUS (Aura) sur la même couleur." -ForegroundColor DarkGray
    Write-Host "  Réversible : « Annuler » remet l'état exact d'avant." -ForegroundColor DarkGray
    Write-Host ""
    $noms = @($script:AccentsWindows.Keys)
    for ($i = 0; $i -lt $noms.Count; $i++) {
        $c = $script:AccentsWindows[$noms[$i]]
        Write-Host ("  {0} - {1,-16} (RVB {2},{3},{4})" -f ($i + 1), $noms[$i], $c.R, $c.G, $c.B) -ForegroundColor Gray
    }
    Write-Host ("  {0} - Retour au défaut (retirer l'accent des barres)" -f ($noms.Count + 1)) -ForegroundColor Yellow
    Write-Host ("  {0} - Retour" -f ($noms.Count + 2))
    Write-Host ""
    $choix = Read-Host "Choisis (1-$($noms.Count + 2))"

    $n = 0
    if (-not [int]::TryParse($choix, [ref]$n)) { return }
    try {
        if ($n -ge 1 -and $n -le $noms.Count) {
            Set-AccentWindows -Nom $noms[$n - 1]
            $script:CompteurOK++
        }
        elseif ($n -eq $noms.Count + 1) {
            Restore-AccentWindows
            $script:CompteurOK++
        }
    }
    catch {
        Write-Etat "Échec : $($_.Exception.Message)" -Niveau Echec
        $script:CompteurEchec++
    }
}

function Menu-Signature {
    Clear-Host
    Write-Host "=== SIGNATURE : FOND D'ÉCRAN MADTRIX ===" -ForegroundColor Red
    Write-Host "  Génère un fond d'écran à ta résolution exacte, puis l'applique." -ForegroundColor DarkGray
    Write-Host "  Ton fond actuel est mémorisé : l'option 5 le remet quand tu veux." -ForegroundColor DarkGray
    Write-Host ""
    $script:CompteurOK = 0; $script:CompteurEchec = 0

    $res = Get-ResolutionPhysique
    Write-Host "  Résolution détectée : $($res.L) x $($res.H)" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  1 - Style MATRIX  (pluie de code katakana rouge)" -ForegroundColor Red
    Write-Host "  2 - Style HUD     (pluie + grille + crochets gaming)" -ForegroundColor Red
    Write-Host "  3 - Style NEON    (sobre, gros nom néon)" -ForegroundColor Red
    Write-Host "  4 - Générer les TROIS dans un dossier, sans les appliquer" -ForegroundColor Yellow
    Write-Host "  5 - Remettre mon fond d'écran d'avant" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  6 - ACCENT WINDOWS : couleur des barres (ROG rouge, bleu, cyan...)" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  7 - Retour au menu principal"
    Write-Host ""
    $choix = Read-Host "Choisis (1-7)"

    try {
        switch ($choix) {
            { $_ -in "1", "2", "3" } {
                $style = $script:StylesSignature[[int]$choix - 1]
                if ($script:Simulation) { Write-Simu "générerait et appliquerait le fond « $style » en $($res.L)x$($res.H)"; break }
                $chemin = Join-Path $script:DossierDonnees "fond-madtrix-$style.png"
                Write-Etat "Génération du fond « $style »..." -Niveau Info
                New-FondSignature -Style $style -Largeur $res.L -Hauteur $res.H -Chemin $chemin | Out-Null
                Set-FondEcran -Chemin $chemin
                Write-Etat "Fond « $style » appliqué. Fichier : $chemin" -Niveau OK
                $script:CompteurOK++
            }
            "4" {
                $dossier = Join-Path ([Environment]::GetFolderPath("Desktop")) "signatures-madtrix"
                if (-not (Test-Path $dossier)) { New-Item -ItemType Directory -Path $dossier -Force | Out-Null }
                if ($script:Simulation) { Write-Simu "générerait les 3 fonds dans $dossier"; break }
                foreach ($style in $script:StylesSignature) {
                    $chemin = Join-Path $dossier "madtrix-$style.png"
                    New-FondSignature -Style $style -Largeur $res.L -Hauteur $res.H -Chemin $chemin | Out-Null
                    Write-Etat "Généré : $chemin" -Niveau OK
                }
                Write-Etat "Les trois fonds sont dans : $dossier" -Niveau Info
                $script:CompteurOK++
            }
            "5" {
                if ($script:Simulation) { Write-Simu "remettrait le fond d'écran précédent"; break }
                Restore-FondPrecedent
                $script:CompteurOK++
            }
            "6" { Menu-AccentWindows }
            "7" { return }
            default { Write-Etat "Choix invalide." -Niveau Avert }
        }
    }
    catch {
        Write-Etat "Échec : $($_.Exception.Message)" -Niveau Echec
        $script:CompteurEchec++
    }

    Fin-De-Menu
}
# ------------------------------------------------------------------------------
# CLÉ D'INSTALLATION — génération d'un autounattend.xml
#
# Windows ne peut PAS être redistribué : la licence Microsoft l'interdit. MadTweak
# ne fournit donc aucune ISO. Il génère le fichier de réponses que l'utilisateur
# dépose sur SA clé, à côté de l'ISO officielle qu'il a téléchargée lui-même.
#
# Même logique que les fonds d'écran : on GÉNÈRE, on n'embarque pas. Le fichier
# produit est du texte, il reste lisible et vérifiable avant d'être utilisé.
#
# WINDOWS 10 ET 11 : le schema « unattend » est le meme pour les deux, il n'a pas
# change depuis Vista. Les contournements TPM/SecureBoot sont des ecritures de
# registre INERTES sous Windows 10 (sans effet, pas en echec). En revanche le NOM
# de l'edition dans l'image differe (« Windows 11 Pro » / « Windows 10 Pro ») :
# c'est la seule vraie divergence, d'ou le parametre -Version.
#
# Le compte local est cree par le bloc LocalAccount du passage oobeSystem, qui est
# le chemin DOCUMENTE par Microsoft. BypassNRO n'est qu'une ceinture-bretelles :
# Microsoft a retire le SCRIPT bypassnro.cmd en 24H2, mais pas la valeur de
# registre, qui marche toujours. Ce n'est pas elle qui cree le compte local.
#
# LIMITE CONNUE, WINDOWS 11 24H2 ET 25H2 : le nouvel installeur (SetupPrep.exe,
# dit « ConX ») lit le passage windowsPE — disque, edition, langue — mais ignore
# souvent oobeSystem. Le compte local n'est alors pas cree et l'OOBE repose ses
# questions. D'ou la recopie du fichier vers C:\Windows\Panther\unattend.xml en
# specialize, qui est le chemin de relecture historique. Ce contournement vient de
# la pratique, pas de la documentation Microsoft : il ne peut pas etre garanti.
# Windows 10 et Windows 11 jusqu'a 23H2 utilisent l'ancien installeur et ne sont
# pas concernes.
#
# Le fichier n'installe pas les tweaks : au premier démarrage, il APPELLE MadTweak
# avec un profil. Les 150 tweaks, la sauvegarde et l'annulation exacte continuent
# donc de fonctionner à l'identique — rien n'est dupliqué.
# ------------------------------------------------------------------------------

function Get-EditionsImage {
    <#
        Lit les éditions RÉELLEMENT contenues dans une image Windows.
        Accepte une .iso (montée puis démontée), un install.wim ou un install.esd.
        Retourne une liste de @{ Index; Nom }. Ne modifie rien.

        Pourquoi : jusqu'ici, choisir une édition revenait à parier. Un nom absent
        de l'image fait échouer l'installation, et on ne le découvre que devant la
        machine. Or l'image, on peut la LIRE. Même principe que partout ailleurs
        dans cet outil : on mesure au lieu de deviner.
    #>
    param([Parameter(Mandatory)][string]$Chemin)

    if (-not (Test-Path -LiteralPath $Chemin)) { throw "Fichier introuvable : $Chemin" }
    $ext = [System.IO.Path]::GetExtension($Chemin).ToLowerInvariant()
    if ($ext -notin '.iso', '.wim', '.esd') {
        throw "Format non reconnu ($ext). Attendu : .iso, .wim ou .esd."
    }

    $monte = $null
    try {
        $imagePath = $Chemin
        if ($ext -eq '.iso') {
            # Montage en LECTURE SEULE : on inspecte le fichier de quelqu'un d'autre,
            # on n'y touche pas. Le démontage est dans le finally, sans quoi une ISO
            # resterait montée après la moindre erreur.
            $monte = Mount-DiskImage -ImagePath $Chemin -StorageType ISO -Access ReadOnly -PassThru -ErrorAction Stop
            $lettre = ($monte | Get-Volume).DriveLetter
            if (-not $lettre) { throw "L'image a été montée mais aucune lettre de lecteur n'a été attribuée." }
            $candidats = @("${lettre}:\sources\install.wim", "${lettre}:\sources\install.esd")
            $imagePath = $candidats | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if (-not $imagePath) {
                throw "Ni sources\install.wim ni sources\install.esd dans cette image : ce n'est pas un support d'installation Windows."
            }
        }

        try { $images = @(Get-WindowsImage -ImagePath $imagePath -ErrorAction Stop) }
        catch {
            # Cas de loin le plus fréquent, et le message natif ne le dit pas clairement.
            if ($_.Exception.Message -match 'l.vation|elevation|denied|refus') {
                throw "La lecture d'une image Windows exige des droits administrateur. Relance MadTweak en administrateur."
            }
            throw "Lecture de l'image impossible : $($_.Exception.Message)"
        }

        $sortie = New-Object System.Collections.Generic.List[object]
        foreach ($im in $images) {
            $sortie.Add([pscustomobject]@{ Index = $im.ImageIndex; Nom = $im.ImageName })
        }
        return $sortie
    }
    finally {
        if ($monte) { try { Dismount-DiskImage -ImagePath $Chemin | Out-Null } catch { } }
    }
}

function Get-ClesInstallation {
    <#
        Liste les volumes amovibles, en signalant ceux qui portent déjà un support
        d'installation Windows (présence de setup.exe à la racine). Lecture seule.
    #>
    $liste = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($v in (Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Removable' })) {
            $racine = "$($v.DriveLetter):\"
            $liste.Add([pscustomobject]@{
                    Lettre    = $v.DriveLetter
                    Nom       = $v.FileSystemLabel
                    Go        = [math]::Round($v.Size / 1GB, 1)
                    EstSupport = (Test-Path (Join-Path $racine 'setup.exe'))
                })
        }
    }
    catch { }
    return $liste
}

function Copy-FichiersVersCle {
    <#
        Dépose le fichier de réponses — et MadTweak lui-même si un profil est prévu —
        à la RACINE d'une clé d'installation déjà préparée. Retourne la liste de ce
        qui a été copié.

        Cette fonction ne formate rien, n'efface rien et n'écrit pas d'image : elle
        copie deux fichiers. L'écriture de l'ISO sur la clé reste le travail de Rufus
        ou du Media Creation Tool, et il n'y a aucune raison de la réimplémenter.

        Le garde-fou du setup.exe n'est pas une formalité : sans lui, une lettre de
        lecteur mal saisie déposerait ces fichiers à la racine d'un disque de données,
        voire de C:, où un autounattend.xml traînant n'a rien à faire.
    #>
    param(
        [Parameter(Mandatory)][string]$Lettre,
        [Parameter(Mandatory)][string]$CheminXml,
        [string]$CheminMadTweak,
        [switch]$Forcer
    )

    $racine = ($Lettre.TrimEnd(':', '\')) + ":\"
    if (-not (Test-Path $racine)) { throw "Le lecteur $racine n'existe pas." }
    if (-not (Test-Path $CheminXml)) { throw "Fichier de réponses introuvable : $CheminXml" }

    if (-not (Test-Path (Join-Path $racine 'setup.exe')) -and -not $Forcer) {
        throw "Aucun setup.exe à la racine de $racine : ce lecteur ne ressemble pas à une clé d'installation Windows. Prépare-la d'abord avec Rufus ou le Media Creation Tool."
    }

    $copies = New-Object System.Collections.Generic.List[string]
    $cible = Join-Path $racine 'autounattend.xml'
    Copy-Item -LiteralPath $CheminXml -Destination $cible -Force -ErrorAction Stop
    $copies.Add($cible)

    if ($CheminMadTweak) {
        if (-not (Test-Path $CheminMadTweak)) { throw "MadTweak.ps1 introuvable : $CheminMadTweak" }
        $cible2 = Join-Path $racine 'MadTweak.ps1'
        Copy-Item -LiteralPath $CheminMadTweak -Destination $cible2 -Force -ErrorAction Stop
        $copies.Add($cible2)
    }

    # On relit ce qu'on vient de deposer : une copie vers une cle defaillante ou
    # pleine peut « reussir » et produire un fichier tronque. Le fichier de reponses
    # d'une machine qu'on va formater merite cette verification.
    $pbs = Test-AutounattendXml -Chemin $cible
    if ($pbs.Count -gt 0) {
        throw "Le fichier copié sur $racine est illisible ou incomplet : $($pbs[0])"
    }

    return $copies
}

function Get-DisquesUSB {
    # Ne renvoie QUE des disques USB, jamais le disque système. C'est la source de
    # la liste proposée à l'utilisateur : ce qui n'apparaît pas ici ne peut pas
    # être effacé par erreur.
    $liste = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($d in (Get-Disk -ErrorAction Stop | Where-Object { $_.BusType -eq 'USB' })) {
            if ($d.IsBoot -or $d.IsSystem) { continue }
            $vols = @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue |
                Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter)
            $liste.Add([pscustomobject]@{
                    Numero  = $d.Number
                    Nom     = $d.FriendlyName
                    Go      = [math]::Round($d.Size / 1GB, 1)
                    Lettres = (($vols | ForEach-Object { "$($_.DriveLetter):" }) -join ' ')
                    Contenu = (($vols | ForEach-Object { $_.FileSystemLabel }) -join ' ')
                })
        }
    }
    catch { }
    return $liste
}

function Convert-EsdVersWim {
    <#
        Convertit une image .esd en .wim en n'en extrayant qu'UNE édition.
        Retourne le chemin du .wim produit. Ne touche pas à la source.

        Pourquoi cette fonction existe seule : c'est l'étape longue et risquée de
        la préparation d'une clé, et elle était jusqu'ici enfouie dans une fonction
        destructive — donc impossible à éprouver sans effacer un disque. Ici, elle
        s'exécute seule, en lecture sur la source et en écriture dans un dossier
        temporaire.

        Un .esd ne se découpe pas ; un .wim, si. C'est le seul chemin pour poser
        une image de plus de 4 Go sur du FAT32, seul système de fichiers que tout
        micrologiciel UEFI sait lire au démarrage.

        Attendre un fichier plus petit serait une erreur : le .esd est compressé
        en LZMS, plus agressif que le LZX d'un .wim. La conversion FAIT GROSSIR le
        fichier — 6,57 Go donnent 9,02 Go sur une image mesurée. N'extraire qu'une
        édition compense quand l'image en contient plusieurs, mais beaucoup n'en
        contiennent qu'une : ne pas compter dessus.
    #>
    param(
        [Parameter(Mandatory)][string]$CheminEsd,
        [string]$Edition = '',
        # Clé produit. Sans elle, l'installeur affiche son écran « Clé de produit »
        # et il faut cliquer « Je n'ai pas de clé » — constaté sur un vrai essai.
        # La doc interdit une valeur VIDE (« does not support empty elements ») :
        # on omet donc l'élément Key entièrement plutôt que d'en écrire un vide,
        # et WillShowUI=Never demande à Windows de ne pas poser la question.
        [string]$CleProduit = '',
        [string]$DossierSortie
    )

    if (-not (Test-Path -LiteralPath $CheminEsd)) { throw "Image introuvable : $CheminEsd" }

    $images = @(Get-WindowsImage -ImagePath $CheminEsd -ErrorAction Stop)
    $index = 1
    if ($Edition) {
        $trouve = $images | Where-Object { $_.ImageName -eq $Edition } | Select-Object -First 1
        if (-not $trouve) {
            throw "L'édition « $Edition » n'est pas dans cette image. Présentes : $(($images.ImageName) -join ' | ')."
        }
        $index = $trouve.ImageIndex
    }
    else {
        Write-Etat "Aucune édition précisée : l'index 1 (« $($images[0].ImageName) ») sera extrait." -Niveau Avert
    }
    $nomGarde = ($images | Where-Object { $_.ImageIndex -eq $index }).ImageName

    if (-not $DossierSortie) {
        $DossierSortie = Join-Path $env:TEMP "madtweak-image-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    }
    if (-not (Test-Path $DossierSortie)) { New-Item -ItemType Directory -Path $DossierSortie -Force | Out-Null }

    # La place se vérifie AVANT, pas au bout de sept minutes de travail.
    #
    # Et il en faut PLUS que la taille de la source : un .esd est compressé en LZMS,
    # bien plus agressif que le LZX maximal d'un .wim. La conversion GROSSIT le
    # fichier. Mesuré sur une image réelle : 6,57 Go de .esd donnent 9,02 Go de
    # .wim, soit +37 %. Le facteur 2 laisse la marge nécessaire — une première
    # version de ce contrôle comparait à la taille de la source et aurait laissé
    # démarrer une conversion vouée à finir sur un disque plein.
    $taille = (Get-Item $CheminEsd).Length
    $requis = $taille * 2
    $libre = (Get-PSDrive -Name ($DossierSortie.Substring(0, 1))).Free
    if ($libre -lt $requis) {
        throw "Place insuffisante sur $($DossierSortie.Substring(0,2)) : $([math]::Round($libre/1GB,1)) Go libres, $([math]::Round($requis/1GB,1)) Go nécessaires (le .wim produit est plus gros que le .esd source)."
    }

    $sortie = Join-Path $DossierSortie 'install.wim'
    Write-Etat "Conversion vers .wim, édition « $nomGarde » (compter 5 à 15 minutes selon le disque)..." -Niveau Info
    Export-WindowsImage -SourceImagePath $CheminEsd -SourceIndex $index `
        -DestinationImagePath $sortie -CompressionType Max -ErrorAction Stop | Out-Null
    Write-Etat "Converti : $([math]::Round((Get-Item $sortie).Length/1GB,2)) Go (source : $([math]::Round($taille/1GB,2)) Go)." -Niveau OK
    return $sortie
}

function Get-OutilsSupport {
    # Outils officiels ou reconnus pour obtenir une ISO et ecrire une cle.
    # MadTweak ne telecharge aucune image lui-meme : il installe l'outil qui le
    # fait, et laisse l'utilisateur decider.
    return [ordered]@{
        "Media Creation Tool (Microsoft, Windows 11)" = "Microsoft.MediaCreationTool"
        "Media Creation Tool (Microsoft, Windows 10)" = "Microsoft.MediaCreationTool.Windows10"
        "Rufus (ecrit la cle, sait aussi telecharger)" = "Rufus.Rufus"
        "Ventoy (une cle, plusieurs ISO)"             = "Ventoy.Ventoy"
    }
}

function Start-MediaCreationTool {
    <#
        Lance le Media Creation Tool, SANS AUCUN COMMUTATEUR.

        AVERTISSEMENT, appris a la dure : les commutateurs qu'on trouve partout
        sur le web — /Eula Accept /Retail /MediaArch /MediaLangCode /MediaEdition —
        ne mettent PAS l'outil en mode « creation de support ». Ils le basculent
        en mode MISE A NIVEAU DE LA MACHINE COURANTE. Essaye sur une machine
        reelle : l'outil ouvre « Configuration de Windows 11 » et reclame une cle
        produit pour installer Windows sur le PC ou on se trouve.

        Sur un outil dont le role est de preparer une cle pour une AUTRE machine,
        declencher par megarde la mise a niveau de celle-ci serait la pire des
        surprises. On lance donc l'assistant nu, et l'utilisateur choisit
        « Creer un support d'installation » puis « Fichier ISO » lui-meme.
    #>
    $chemins = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Microsoft.MediaCreationTool_Microsoft.Winget.Source_8wekyb3d8bbwe\MediaCreationTool.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\MediaCreationTool.exe')
    )
    $exe = $chemins | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $exe) {
        $c = Get-Command MediaCreationTool -ErrorAction SilentlyContinue
        if ($c) { $exe = $c.Source }
    }
    if (-not $exe) {
        Write-Etat "Media Creation Tool introuvable. Installe-le d'abord depuis ce menu." -Niveau Avert
        return $false
    }

    Write-Etat "Lancement du Media Creation Tool." -Niveau Info
    Write-Etat "Choisis « Creer un support d'installation », PAS la mise a niveau de ce PC." -Niveau Avert
    Write-Etat "Puis « Fichier ISO », et note ou tu l'enregistres." -Niveau Info
    Start-Process -FilePath $exe | Out-Null
    return $true
}

function Get-LienIsoWindows {
    <#
        Obtient un lien de telechargement OFFICIEL d'une ISO Windows, depuis les
        serveurs de Microsoft, en refaisant les memes appels que sa propre page
        de telechargement. Retourne @{ Nom; Uri; Langue }.

        Comment ca marche, parce que ce n'est pas evident :

        La page publique ne contient aucun lien direct. Elle fait travailler le
        navigateur en quatre temps. On enregistre une session aupres de
        vlscppe.microsoft.com, qui pose deux cookies de reconnaissance. On
        demande ensuite mdt.js, un fragment de JavaScript contenant trois
        valeurs a usage unique : un jeton « w », un horodatage serveur
        « rticks » et un identifiant client. La page les renvoie a
        ov-df.microsoft.com dans une iframe invisible : c'est cette etape qui
        valide la session. Alors seulement l'API accepte de rendre la liste des
        langues, puis les liens.

        Sans cette sequence, l'API repond « Sentinel marked this request as
        rejected ». C'est ce qui arrive quand on attaque directement le dernier
        appel, et c'est exactement l'erreur par laquelle j'ai commence.

        Deux pieges m'ont coute plusieurs essais, notes ici pour la prochaine
        fois. « CustomerId » n'est PAS l'org_id des cookies mais l'instanceId.
        Et « rticks » n'est pas un parametre d'URL dans le JavaScript mais une
        concatenation — &rticks=" + 1785204326859 — donc une expression qui
        cherche un parametre d'URL revient vide, sans erreur, et la session
        n'est jamais validee.

        FRAGILITE ASSUMEE : rien de tout ceci n'est documente par Microsoft, qui
        peut le changer sans preavis. La fonction echoue alors proprement, avec
        un message explicite, et le menu propose l'outil officiel en repli. Elle
        ne contourne aucune protection de contenu : elle demande, comme le
        ferait un navigateur, une image que Microsoft distribue gratuitement et
        publiquement.
    #>
    param(
        [ValidateSet('11', '10')][string]$Version = '11',
        [string]$Langue = 'Francais',
        [ValidateSet('x64', 'ARM64')][string]$Arch = 'x64'
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36'
    $page = if ($Version -eq '11') {
        'https://www.microsoft.com/software-download/windows11'
    }
    else {
        'https://www.microsoft.com/software-download/windows10ISO'
    }
    $sid = [guid]::NewGuid().ToString()
    $instance = '560dc9f3-1aa5-4a2f-b63c-9e18f8d0e175'

    try {
        # 1. La page, pour y LIRE l'identifiant d'edition courant plutot que de
        #    le coder en dur : Microsoft l'incremente a chaque version.
        Write-Etat "Interrogation de la page officielle Microsoft..." -Niveau Info
        $r = Invoke-WebRequest -Uri $page -UserAgent $ua -UseBasicParsing -TimeoutSec 30 -SessionVariable ws
        $edId = ([regex]::Match($r.Content, 'value="(\d{3,5})"[^>]*>\s*Windows ' + $Version)).Groups[1].Value
        if (-not $edId) { $edId = ([regex]::Match($r.Content, '<option[^>]*value="(\d{3,5})"')).Groups[1].Value }
        if (-not $edId) { throw "Identifiant d'edition introuvable : Microsoft a change sa mise en page." }

        # 2. Enregistrement de la session (pose les cookies de reconnaissance).
        Invoke-WebRequest -Uri "https://vlscppe.microsoft.com/tags?org_id=y6jn8c31&session_id=$sid" `
            -UserAgent $ua -UseBasicParsing -WebSession $ws -TimeoutSec 30 | Out-Null

        # 3. Les trois valeurs a usage unique.
        $m = Invoke-WebRequest -Uri "https://ov-df.microsoft.com/mdt.js?instanceId=$instance&PageId=si&session_id=$sid" `
            -UserAgent $ua -UseBasicParsing -WebSession $ws -TimeoutSec 30
        $w = ([regex]::Match($m.Content, '[?&]w=([A-Za-z0-9]+)')).Groups[1].Value
        $rticks = ([regex]::Match($m.Content, 'rticks="\s*\+\s*(\d+)')).Groups[1].Value
        $cid = ([regex]::Match($m.Content, 'customerId:"([^"]+)"')).Groups[1].Value
        if (-not $w -or -not $rticks -or -not $cid) {
            throw "Jetons de session illisibles : le mecanisme de validation a change."
        }

        # 4. Le renvoi qui valide la session, celui que fait l'iframe invisible.
        $mdt = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
        Invoke-WebRequest -Uri "https://ov-df.microsoft.com/?session_id=$sid&CustomerId=$cid&PageId=si&w=$w&mdt=$mdt&rticks=$rticks" `
            -UserAgent $ua -UseBasicParsing -WebSession $ws -Headers @{ 'Referer' = $page } -TimeoutSec 30 | Out-Null
        Start-Sleep -Seconds 3

        # 5. Les langues reellement proposees pour cette edition.
        $sku = Invoke-RestMethod -UserAgent $ua -WebSession $ws -Headers @{ 'Referer' = $page } -TimeoutSec 30 `
            -Uri "https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile=606624d44113&productEditionId=$edId&SKU=undefined&friendlyFileName=undefined&Locale=fr-FR&sessionID=$sid"
        if (-not $sku.Skus) { throw "Aucune langue retournee : $($sku.Errors | ConvertTo-Json -Compress)" }

        # Comparaison insensible aux accents : Microsoft renvoie « Français » avec
        # sa cédille. Même piège que les noms de profils, même remède.
        $cible = ConvertTo-CleComparable $Langue
        $choix = $sku.Skus | Where-Object { (ConvertTo-CleComparable $_.LocalizedLanguage) -like "*$cible*" } | Select-Object -First 1
        if (-not $choix) {
            throw "Langue « $Langue » indisponible. Proposees : $((($sku.Skus.LocalizedLanguage) | Select-Object -First 12) -join ', ')..."
        }

        # 6. Les liens, enfin.
        $dl = Invoke-RestMethod -UserAgent $ua -WebSession $ws -Headers @{ 'Referer' = $page } -TimeoutSec 30 `
            -Uri "https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku?profile=606624d44113&productEditionId=undefined&SKU=$($choix.Id)&friendlyFileName=undefined&Locale=fr-FR&sessionID=$sid"
        if (-not $dl.ProductDownloadOptions) {
            throw "Lien refuse par Microsoft : $($dl.Errors | ConvertTo-Json -Compress)"
        }

        # DownloadType : 1 = x64, 2 = ARM64 (constate sur les reponses reelles).
        $type = if ($Arch -eq 'x64') { 1 } else { 2 }
        $opt = $dl.ProductDownloadOptions | Where-Object { $_.DownloadType -eq $type } | Select-Object -First 1
        if (-not $opt) { $opt = $dl.ProductDownloadOptions | Select-Object -First 1 }

        $nom = ([regex]::Match($opt.Uri, '/([^/?]+\.iso)')).Groups[1].Value
        if (-not $nom) { $nom = "Windows$Version-$Arch.iso" }
        Write-Etat "Lien officiel obtenu : $nom" -Niveau OK
        return @{ Nom = $nom; Uri = $opt.Uri; Langue = $choix.LocalizedLanguage }
    }
    catch {
        Write-Etat "Lien indisponible : $($_.Exception.Message)" -Niveau Echec
        Write-Etat "Repli : utilise le Media Creation Tool depuis ce menu." -Niveau Info
        return $null
    }
}

function Save-IsoWindows {
    <#
        Telecharge l'ISO depuis le lien officiel, avec progression.
        Retourne le chemin ecrit, ou $null.

        Le lien expire au bout de quelques heures : on ne le conserve pas, on le
        redemande a chaque fois. Un telechargement interrompu laisse un fichier
        tronque, qui produirait un support silencieusement inutilisable : on
        ecrit donc dans un fichier temporaire et on ne le renomme QU'A LA FIN,
        apres avoir verifie que le compte d'octets correspond.
    #>
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Chemin
    )

    $partiel = "$Chemin.partiel"
    $dossier = Split-Path $Chemin -Parent
    if ($dossier -and -not (Test-Path $dossier)) { New-Item -ItemType Directory -Path $dossier -Force | Out-Null }
    if (Test-Path $partiel) { Remove-Item $partiel -Force }

    try {
        Write-Etat "Telechargement en cours (plusieurs gigaoctets, compter 10 a 40 minutes)..." -Niveau Info
        $req = [System.Net.HttpWebRequest]::Create($Uri)
        $req.UserAgent = 'Mozilla/5.0'
        $req.Timeout = 60000
        $rep = $req.GetResponse()
        $total = $rep.ContentLength
        $flux = $rep.GetResponseStream()
        $sortie = [System.IO.File]::Create($partiel)
        $tampon = New-Object byte[] 1048576
        $fait = 0L
        $dernier = Get-Date
        while (($lu = $flux.Read($tampon, 0, $tampon.Length)) -gt 0) {
            $sortie.Write($tampon, 0, $lu)
            $fait += $lu
            if (((Get-Date) - $dernier).TotalSeconds -ge 10) {
                $pc = if ($total -gt 0) { [math]::Round($fait * 100 / $total) } else { 0 }
                Write-Etat "  $pc %  ($([math]::Round($fait / 1GB, 2)) Go sur $([math]::Round($total / 1GB, 2)) Go)" -Niveau Info
                $dernier = Get-Date
            }
        }
        $sortie.Close(); $flux.Close(); $rep.Close()

        if ($total -gt 0 -and $fait -ne $total) {
            throw "Telechargement incomplet : $fait octets sur $total attendus."
        }
        Move-Item $partiel $Chemin -Force
        Write-Etat "ISO telechargee : $Chemin ($([math]::Round((Get-Item $Chemin).Length / 1GB, 2)) Go)" -Niveau OK
        return $Chemin
    }
    catch {
        if (Test-Path $partiel) { Remove-Item $partiel -Force -ErrorAction SilentlyContinue }
        Write-Etat "Telechargement echoue : $($_.Exception.Message)" -Niveau Echec
        return $null
    }
}

function Wait-IsoTelechargee {
    <#
        Surveille l'apparition d'une ISO Windows et renvoie son chemin.
        Rend la main tout seul des que le fichier a fini de grossir.

        Pourquoi cette fonction plutot qu'un telechargement automatique : l'API
        de telechargement de Microsoft est protegee par un anti-robot (elle
        repond « Sentinel marked this request as rejected »). Le contourner
        demanderait une course perpetuelle, et casserait chez les utilisateurs a
        chaque changement cote Microsoft. Quant a telecharger un script tiers
        pour le faire, MadTweak tourne en administrateur sur des machines qui ne
        sont pas les miennes : executer du code recupere sur internet au moment
        ou il tourne n'est pas une option.

        On laisse donc l'outil officiel faire son travail, et on reprend la main
        automatiquement des que le fichier existe. L'utilisateur ne fait que
        quelques clics chez Microsoft ; MadTweak s'occupe de tout le reste.
    #>
    param(
        [string[]]$Dossiers = @(),
        [int]$MinutesMax = 90
    )

    if ($Dossiers.Count -eq 0) {
        $Dossiers = @(
            (Join-Path $env:USERPROFILE 'Downloads'),
            [Environment]::GetFolderPath('Desktop'),
            'D:', 'C:'
        ) | Where-Object { Test-Path $_ }
    }

    # On ne retient que les ISO APPARUES apres le debut de l'attente : une image
    # deja presente n'est pas celle que l'utilisateur telecharge maintenant.
    $connues = @{}
    foreach ($d in $Dossiers) {
        foreach ($f in (Get-ChildItem $d -Filter *.iso -File -ErrorAction SilentlyContinue)) {
            $connues[$f.FullName] = $true
        }
    }

    Write-Etat "En attente d'une ISO dans : $($Dossiers -join ' | ')" -Niveau Info
    Write-Etat "Choisis « Creer un support d'installation » puis « Fichier ISO »." -Niveau Info

    $fin = (Get-Date).AddMinutes($MinutesMax)
    while ((Get-Date) -lt $fin) {
        foreach ($d in $Dossiers) {
            foreach ($f in (Get-ChildItem $d -Filter *.iso -File -ErrorAction SilentlyContinue)) {
                if ($connues.ContainsKey($f.FullName)) { continue }
                if ($f.Length -lt 1GB) { continue }

                # Le fichier existe, mais il grossit peut-etre encore. On attend
                # qu'il cesse de bouger : copier une ISO a moitie ecrite
                # produirait un support silencieusement inutilisable.
                $t1 = $f.Length
                Start-Sleep -Seconds 15
                $t2 = (Get-Item $f.FullName -ErrorAction SilentlyContinue).Length
                if ($t1 -ne $t2) {
                    Write-Etat "Telechargement en cours : $([math]::Round($t2/1GB,2)) Go..." -Niveau Info
                    continue
                }
                Write-Etat "ISO detectee : $($f.FullName) ($([math]::Round($t2/1GB,2)) Go)" -Niveau OK
                return $f.FullName
            }
        }
        Start-Sleep -Seconds 10
    }
    Write-Etat "Aucune ISO apparue en $MinutesMax minutes." -Niveau Avert
    return $null
}

function New-CleInstallation {
    <#
        Efface un disque USB, le formate et y écrit une ISO Windows officielle,
        puis y dépose le fichier de réponses (et MadTweak si un profil est prévu).

        C'EST LA SEULE FONCTION DESTRUCTIVE DE TOUT MADTWEAK. Tout le reste de
        l'outil sauvegarde avant d'écrire et sait revenir en arrière ; ici, non :
        les données du disque choisi sont perdues. D'où les verrous ci-dessous,
        qui s'exécutent TOUS avant la moindre écriture :

          - -Confirme est obligatoire ; sans lui, la fonction refuse de démarrer ;
          - le disque doit être de type USB. Un disque interne est refusé, même
            explicitement demandé : c'est la ligne qui empêche d'effacer un disque
            de données sur une faute de frappe ;
          - un disque marqué démarrage ou système est refusé.

        Le formatage est en FAT32, seul système de fichiers que tous les micrologiciels
        UEFI savent lire au démarrage. Cela impose deux contraintes que la fonction
        gère au lieu de les subir : une partition d'au plus 32 Go (Windows refuse de
        formater davantage en FAT32) et un install.wim découpé en .swm s'il dépasse
        4 Go, ce qui est le cas courant. Windows Setup lit nativement les .swm.
    #>
    param(
        [Parameter(Mandatory)][int]$NumeroDisque,
        [Parameter(Mandatory)][string]$CheminIso,
        [string]$CheminXml,
        [string]$CheminMadTweak,
        [string]$Etiquette = 'MADTWEAK',
        # Édition à conserver quand une image .esd doit être convertie : on n'en
        # extrait qu'une, pas les onze. Nom exact, tel que Get-EditionsImage le rend.
        [string]$Edition = '',
        # FAT32 : démarre sur tous les UEFI, mais plafonne les fichiers à 4 Go, d'où
        # le découpage de install.wim. NTFS : aucun découpage, préparation bien plus
        # rapide — mais la plupart des micrologiciels UEFI n'ont pas de pilote NTFS
        # et ne démarreront pas dessus. Rufus contourne ça avec son propre chargeur ;
        # nous n'en avons pas, donc NTFS ne convient qu'à une machine en BIOS/CSM ou
        # à une clé destinée à Ventoy. FAT32 reste le défaut, exprès.
        [ValidateSet('FAT32', 'NTFS')][string]$SystemeFichiers = 'FAT32',
        [switch]$Confirme
    )

    if (-not $Confirme) {
        throw "New-CleInstallation efface entièrement un disque : appelle-la avec -Confirme."
    }
    if (-not (Test-Path -LiteralPath $CheminIso)) { throw "ISO introuvable : $CheminIso" }
    if ([System.IO.Path]::GetExtension($CheminIso).ToLowerInvariant() -ne '.iso') {
        throw "Attendu un fichier .iso."
    }
    if ($CheminXml -and -not (Test-Path -LiteralPath $CheminXml)) {
        throw "Fichier de réponses introuvable : $CheminXml"
    }

    # Cohérence entre les deux usages du nom d'édition. Quand une image .esd est
    # convertie, le .wim produit ne contient QUE l'édition extraite ; si le fichier
    # de réponses en réclame une autre, Windows Setup ne la trouvera pas et
    # l'installation s'arrêtera — après le formatage de la clé, et devant une
    # machine qu'on vient peut-être d'effacer.
    if ($CheminXml -and $Edition) {
        try {
            $xv = [xml](Get-Content $CheminXml -Raw)
            $nsv = New-Object System.Xml.XmlNamespaceManager($xv.NameTable)
            $nsv.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
            $voulu = $xv.SelectSingleNode('//u:MetaData/u:Value', $nsv)
            if ($voulu -and $voulu.InnerText -ne $Edition) {
                throw "Incohérence : le fichier de réponses demande « $($voulu.InnerText) » alors que la clé recevra « $Edition »."
            }
        }
        catch [System.Management.Automation.RuntimeException] { throw }
        catch { }
    }

    $disque = Get-Disk -Number $NumeroDisque -ErrorAction SilentlyContinue
    if (-not $disque) { throw "Aucun disque numéro $NumeroDisque." }
    if ($disque.BusType -ne 'USB') {
        throw "Le disque $NumeroDisque est de type « $($disque.BusType) », pas USB. MadTweak refuse d'effacer autre chose qu'une clé USB."
    }
    if ($disque.IsBoot -or $disque.IsSystem) {
        throw "Le disque $NumeroDisque porte le système : refus catégorique."
    }

    $monte = $null
    try {
        Write-Etat "Ouverture de l'ISO..." -Niveau Info
        $monte = Mount-DiskImage -ImagePath $CheminIso -StorageType ISO -Access ReadOnly -PassThru -ErrorAction Stop
        $src = ($monte | Get-Volume).DriveLetter
        if (-not $src) { throw "L'ISO a été montée mais sans lettre de lecteur." }
        $srcRacine = "${src}:\"
        if (-not (Test-Path (Join-Path $srcRacine 'setup.exe'))) {
            throw "Pas de setup.exe dans cette ISO : ce n'est pas un support d'installation Windows."
        }

        # On repère le gros fichier AVANT d'effacer quoi que ce soit : si l'image est
        # un .esd trop volumineux, on ne saura pas la découper, et il vaut mieux le
        # découvrir maintenant que la clé une fois effacée.
        $wim = Join-Path $srcRacine 'sources\install.wim'
        $esd = Join-Path $srcRacine 'sources\install.esd'
        $gros = $null; $decouper = $false; $wimTemp = $null; $nomExclu = $null
        if (Test-Path $wim) { $gros = $wim; $nomExclu = 'install.wim' }
        elseif (Test-Path $esd) { $gros = $esd; $nomExclu = 'install.esd' }

        if ($gros) {
            $tailleGo = (Get-Item $gros).Length / 1GB
            if ($tailleGo -gt 3.9 -and $SystemeFichiers -eq 'FAT32') {
                $decouper = $true
                $aDecouper = $gros

                if ($gros -eq $esd) {
                    # Un .esd ne se découpe pas, mais il se convertit. Toute la
                    # mécanique est dans Convert-EsdVersWim, éprouvable seule.
                    $wimTemp = Convert-EsdVersWim -CheminEsd $esd -Edition $Edition
                    $aDecouper = $wimTemp
                }
                else {
                    Write-Etat "install.wim fait $([math]::Round($tailleGo,1)) Go : il sera découpé en .swm (FAT32 plafonne à 4 Go par fichier)." -Niveau Info
                }
            }
        }

        # --- À partir d'ici, on écrit. Tout ce qui pouvait être vérifié l'a été. ---
        Write-Etat "Effacement du disque $NumeroDisque ($($disque.FriendlyName))..." -Niveau Info
        Clear-Disk -Number $NumeroDisque -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop
        Initialize-Disk -Number $NumeroDisque -PartitionStyle MBR -ErrorAction SilentlyContinue | Out-Null

        # 32 Go maximum en FAT32 : au-delà, Windows refuse de formater. Un support
        # d'installation n'a de toute façon besoin que de 8 à 10 Go. NTFS n'a pas
        # cette limite, on prend alors toute la clé.
        $tailleMax = if ($SystemeFichiers -eq 'FAT32') { [math]::Min($disque.Size - 8MB, 32GB) } else { $disque.Size - 8MB }
        $part = New-Partition -DiskNumber $NumeroDisque -Size $tailleMax -AssignDriveLetter -IsActive -ErrorAction Stop
        Start-Sleep -Seconds 2
        Write-Etat "Formatage en $SystemeFichiers..." -Niveau Info
        if ($SystemeFichiers -eq 'NTFS') {
            Write-Etat "NTFS : pas de decoupage, mais beaucoup d'UEFI ne demarrent pas sur du NTFS. A reserver au BIOS/CSM ou a Ventoy." -Niveau Avert
        }
        Format-Volume -Partition $part -FileSystem $SystemeFichiers -NewFileSystemLabel $Etiquette -Confirm:$false -Force -ErrorAction Stop | Out-Null
        $dst = "$($part.DriveLetter):\"

        Write-Etat "Copie de l'image vers $dst (plusieurs minutes)..." -Niveau Info
        # robocopy plutôt que Copy-Item : il reprend, il journalise, et il sait
        # exclure un fichier. Ses codes de sortie sous 8 signalent un succès.
        $exclu = if ($decouper) { @('/XF', $nomExclu) } else { @() }
        & robocopy $srcRacine $dst /E /NFL /NDL /NJH /NJS /NP @exclu | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "La copie a échoué (robocopy code $LASTEXITCODE)." }

        if ($decouper) {
            Write-Etat "Découpage en .swm (long)..." -Niveau Info
            Split-WindowsImage -ImagePath $aDecouper -SplitImagePath (Join-Path $dst 'sources\install.swm') -FileSize 3800 -ErrorAction Stop | Out-Null
            Write-Etat "$((Get-ChildItem (Join-Path $dst 'sources') -Filter *.swm).Count) fichier(s) .swm posé(s)." -Niveau OK
        }

        if ($CheminXml) {
            Copy-Item -LiteralPath $CheminXml -Destination (Join-Path $dst 'autounattend.xml') -Force -ErrorAction Stop
            $pbs = Test-AutounattendXml -Chemin (Join-Path $dst 'autounattend.xml')
            if ($pbs.Count -gt 0) { throw "Le fichier de réponses copié est illisible : $($pbs[0])" }
        }
        if ($CheminMadTweak -and (Test-Path $CheminMadTweak)) {
            Copy-Item -LiteralPath $CheminMadTweak -Destination (Join-Path $dst 'MadTweak.ps1') -Force -ErrorAction Stop
        }

        Write-Etat "Clé prête sur $dst" -Niveau OK
        return $dst
    }
    finally {
        if ($monte) { try { Dismount-DiskImage -ImagePath $CheminIso | Out-Null } catch { } }
        # Le .wim converti peut peser plusieurs gigaoctets : le laisser dans %TEMP%
        # serait un cadeau empoisonné.
        if ($wimTemp -and (Test-Path $wimTemp)) {
            try { Remove-Item (Split-Path $wimTemp -Parent) -Recurse -Force -ErrorAction Stop }
            catch { Write-Etat "Fichier temporaire à supprimer soi-même : $wimTemp" -Niveau Avert }
        }
    }
}

function Test-AutounattendXml {
    <#
        Relit un fichier de réponses et renvoie la liste de ses problèmes.
        Liste vide = rien à signaler. Ne modifie rien.

        Pourquoi ce contrôle existe : un réglage placé dans le mauvais passage de
        configuration ne fait PAS échouer l'installation — Windows l'ignore, en
        silence. On se retrouve avec un clavier QWERTY ou un écran de compte qui
        réapparaît, sans le moindre message. C'est exactement le genre de panne
        qu'un test automatique attrape et qu'une relecture humaine laisse passer.

        Le projet a déjà cinq filets de ce type (Test-ClesProfils, Test-CoherenceAudit,
        Test-Explications, le décompte des clés jouées, la CI). Celui-ci est le sixième.
    #>
    param([Parameter(Mandatory)][string]$Chemin)

    $pbs = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path $Chemin)) { $pbs.Add("Fichier introuvable : $Chemin"); return $pbs }

    # Windows Setup lit le fichier en UTF-8 ; un BOM peut le faire échouer.
    $octets = [System.IO.File]::ReadAllBytes($Chemin)
    if ($octets.Length -ge 3 -and $octets[0] -eq 0xEF -and $octets[1] -eq 0xBB -and $octets[2] -eq 0xBF) {
        $pbs.Add("Le fichier commence par un BOM UTF-8 : Windows Setup peut le refuser.")
    }

    try { $x = [xml](Get-Content $Chemin -Raw) }
    catch { $pbs.Add("XML mal formé : $($_.Exception.Message)"); return $pbs }

    $ns = New-Object System.Xml.XmlNamespaceManager($x.NameTable)
    $ns.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
    if (-not $x.SelectSingleNode('/u:unattend', $ns)) {
        $pbs.Add("Racine « unattend » absente ou mauvais espace de noms.")
        return $pbs
    }

    # Passages où chaque composant est réellement valide, d'après la documentation
    # Microsoft. On ne liste que ceux qu'on écrit : inventer une règle serait pire
    # que ne pas en avoir.
    $passagesValides = @{
        'Microsoft-Windows-International-Core-WinPE' = @('windowsPE')
        'Microsoft-Windows-International-Core'       = @('specialize', 'oobeSystem')
        'Microsoft-Windows-Setup'                    = @('windowsPE')
        'Microsoft-Windows-Deployment'               = @('specialize', 'windowsPE', 'auditUser', 'oobeSystem')
        'Microsoft-Windows-Shell-Setup'              = @('specialize', 'oobeSystem', 'auditSystem', 'generalize')
    }

    $vus = @{}
    foreach ($s in $x.SelectNodes('/u:unattend/u:settings', $ns)) {
        $passage = $s.pass
        foreach ($c in $s.SelectNodes('u:component', $ns)) {
            $nom = $c.name
            $vus["$nom|$passage"] = $true
            if ($passagesValides.ContainsKey($nom) -and $passage -notin $passagesValides[$nom]) {
                $pbs.Add("« $nom » est place dans le passage « $passage », ou il sera IGNORE en silence. Passages valides : $($passagesValides[$nom] -join ', ').")
            }
        }
    }

    # Réglages dépréciés : Microsoft demande explicitement de ne pas s'en servir.
    foreach ($mort in 'SkipMachineOOBE', 'SkipUserOOBE') {
        if ($x.SelectSingleNode("//u:$mort", $ns)) {
            $pbs.Add("« $mort » est deprecie depuis Windows 10 1709 et ne doit pas servir a automatiser l'OOBE.")
        }
    }

    # Sans ces deux blocs, l'installation « automatique » repose ses questions.
    if (-not $vus['Microsoft-Windows-International-Core|oobeSystem']) {
        $pbs.Add("Aucun « Microsoft-Windows-International-Core » en oobeSystem : le Windows INSTALLE gardera la disposition clavier par defaut.")
    }
    if (-not $x.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:UserAccounts', $ns)) {
        $pbs.Add("Aucun compte declare en oobeSystem : l'ecran de creation de compte reapparaitra.")
    }

    # Effacer le disque sans dire où installer laisse l'installeur sans cible,
    # APRÈS avoir tout effacé. C'est la combinaison la plus coûteuse du fichier.
    if ($x.SelectSingleNode('//u:WillWipeDisk', $ns) -and
        -not ($x.SelectSingleNode('//u:InstallTo', $ns) -or $x.SelectSingleNode('//u:InstallToAvailablePartition', $ns))) {
        $pbs.Add("Le disque est efface mais aucune cible d'installation n'est indiquee (InstallTo).")
    }

    # Effacer un disque et installer sur un AUTRE est la pire issue possible : on
    # detruit des donnees ET on installe ailleurs que prevu. Les deux numeros doivent
    # concorder.
    $dEfface = $x.SelectSingleNode('//u:DiskConfiguration/u:Disk/u:DiskID', $ns)
    $dCible = $x.SelectSingleNode('//u:InstallTo/u:DiskID', $ns)
    if ($dEfface -and $dCible -and $dEfface.InnerText -ne $dCible.InnerText) {
        $pbs.Add("Le disque efface ($($dEfface.InnerText)) n'est pas celui ou Windows serait installe ($($dCible.InnerText)).")
    }

    # FirstLogonCommands n'existe qu'en oobeSystem ; ailleurs il ne joue jamais.
    foreach ($f in $x.SelectNodes('//u:FirstLogonCommands', $ns)) {
        $p = $f.SelectSingleNode('ancestor::u:settings', $ns)
        if ($p -and $p.pass -ne 'oobeSystem') {
            $pbs.Add("FirstLogonCommands se trouve en « $($p.pass) » : il ne s'executera jamais.")
        }
    }

    # Limite documentée, et unicité des ordres d'exécution.
    foreach ($c in $x.SelectNodes('//u:CommandLine', $ns)) {
        if ($c.InnerText.Length -gt 1024) {
            $pbs.Add("Une commande depasse 1024 caracteres ($($c.InnerText.Length)) : Windows la refusera.")
        }
    }
    foreach ($groupe in @('FirstLogonCommands', 'RunSynchronous')) {
        foreach ($parent in $x.SelectNodes("//u:$groupe", $ns)) {
            $ordres = @($parent.SelectNodes('.//u:Order', $ns) | ForEach-Object { $_.InnerText })
            $doublons = @($ordres | Group-Object | Where-Object Count -gt 1)
            if ($doublons) {
                $pbs.Add("Ordres d'execution en double dans $groupe : $(($doublons.Name) -join ', ').")
            }
        }
    }

    return $pbs
}

function Get-FuseauxCourants {
    # Les identifiants attendus par Windows Setup sont ceux de .NET (« Romance
    # Standard Time »), pas des noms IANA. Plutôt que de recopier à la main une
    # poignée de fuseaux — avec le risque d'en écrire un qui n'existe pas — on
    # énumère ceux que la machine connaît réellement. Le fuseau courant vient en
    # tête : dans l'immense majorité des cas, on réinstalle là où on se trouve.
    $liste = [ordered]@{}
    try {
        $courant = [System.TimeZoneInfo]::Local
        $liste["$($courant.DisplayName)  (ce PC)"] = $courant.Id
        foreach ($tz in ([System.TimeZoneInfo]::GetSystemTimeZones() | Sort-Object DisplayName)) {
            if ($tz.Id -ne $courant.Id) { $liste[$tz.DisplayName] = $tz.Id }
        }
    }
    catch {
        # Repli minimal si l'énumération échoue : mieux vaut un choix que rien.
        $liste["Europe de l'Ouest (Paris, Bruxelles)"] = "Romance Standard Time"
        $liste["Royaume-Uni (Londres)"] = "GMT Standard Time"
    }
    return $liste
}

function Get-LangueCePC {
    # Relit la configuration régionale RÉELLE de la machine courante. C'est la seule
    # source qui ne se trompe pas de disposition clavier : un identifiant recopié de
    # travers (080c contre 040c) donne un AZERTY belge là où on voulait un français,
    # et cela ne se découvre qu'une fois devant la machine installée.
    try {
        $ui = (Get-UICulture).Name
        $loc = (Get-WinSystemLocale).Name
        $clavier = $null
        try {
            $premiere = @(Get-WinUserLanguageList)[0]
            if ($premiere.InputMethodTips.Count -gt 0) { $clavier = $premiere.InputMethodTips[0] }
        }
        catch { }
        if (-not $clavier) { return $null }
        return @{ UI = $ui; Locale = $loc; Clavier = $clavier }
    }
    catch { return $null }
}

function Get-LanguesInstallation {
    $liste = [ordered]@{}
    $cePc = Get-LangueCePC
    if ($cePc) { $liste["Identique a ce PC ($($cePc.Locale), clavier $($cePc.Clavier))"] = $cePc }
    $liste["Francais (Belgique)"] = @{ UI = "fr-FR"; Locale = "fr-BE"; Clavier = "080c:0000080c" }
    $liste["Francais (France)"] = @{ UI = "fr-FR"; Locale = "fr-FR"; Clavier = "040c:0000040c" }
    $liste["Francais (Suisse)"] = @{ UI = "fr-FR"; Locale = "fr-CH"; Clavier = "100c:0000100c" }
    $liste["Francais (Canada)"] = @{ UI = "fr-CA"; Locale = "fr-CA"; Clavier = "0c0c:00001009" }
    $liste["English (US)"] = @{ UI = "en-US"; Locale = "en-US"; Clavier = "0409:00000409" }
    $liste["English (UK)"] = @{ UI = "en-GB"; Locale = "en-GB"; Clavier = "0809:00000809" }
    return $liste
}

function ConvertTo-MotDePasseUnattend {
    # Windows attend le mot de passe en base64 de (mot de passe + "Password"),
    # en UTF-16LE. Ce n'est PAS du chiffrement : n'importe qui lisant la clé USB
    # le retrouve en une commande. L'appelant DOIT en avertir l'utilisateur.
    param([string]$MotDePasse)
    $octets = [System.Text.Encoding]::Unicode.GetBytes($MotDePasse + "Password")
    return [Convert]::ToBase64String($octets)
}

function New-AutounattendXml {
    <#
        Génère le fichier de réponses. Retourne le chemin écrit.

        -Profil     : clé d'un profil MadTweak rejoué au premier démarrage ($null = aucun)
        -Apps       : identifiants winget installés au premier démarrage
        -SansTPM    : ajoute les contournements TPM/SecureBoot/RAM (matériel ancien)
        -MotDePasse : laissé vide = compte SANS mot de passe, à définir au 1er démarrage
        -Version    : 11 ou 10 — ne sert qu'à nommer l'édition dans l'image
        -Edition    : Pro / Famille / Entreprise. Vide = l'installeur pose la question.
                      Ne la remplir que si on est sûr de ce que contient l'ISO : un
                      nom d'édition absent de l'image fait échouer l'installation.
    #>
    param(
        [Parameter(Mandatory)][string]$Chemin,
        [Parameter(Mandatory)][string]$NomUtilisateur,
        [ValidateSet('11', '10')][string]$Version = '11',
        # Raccourci (Pro / Famille / Entreprise) OU nom exact d'édition lu dans
        # l'image par Get-EditionsImage. Un nom exact l'emporte toujours : c'est
        # une valeur mesurée, elle vaut mieux que ma table de correspondance.
        [string]$Edition = '',
        [string]$MotDePasse = "",
        [string]$NomMachine = "",
        [string]$Langue = "Francais (Belgique)",
        [string]$Fuseau = "Romance Standard Time",
        [string]$Profil,
        [string[]]$Apps = @(),
        [switch]$SansTPM,
        [switch]$EffacerDisque,
        # Numéro du disque à effacer. 0 est le défaut habituel, mais PAS une garantie :
        # sur une machine à plusieurs disques, le 0 peut être celui des données. Ce
        # paramètre n'a d'effet qu'avec -EffacerDisque.
        [int]$Disque = 0
    )

    $langues = Get-LanguesInstallation
    if (-not $langues.Contains($Langue)) { throw "Langue « $Langue » inconnue." }
    $L = $langues[$Langue]

    if ($NomUtilisateur -match '[\\/:*?"<>|]') { throw "Le nom d'utilisateur contient un caractere interdit." }
    if (-not $NomMachine) { $NomMachine = "PC-" + ($NomUtilisateur -replace '[^a-zA-Z0-9]', '') }
    if ($NomMachine.Length -gt 15) { $NomMachine = $NomMachine.Substring(0, 15) }

    $esc = {
        param($t)
        "$t" -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&apos;'
    }

    # Un compte local AVEC mot de passe déclenche trois questions de sécurité pendant
    # l'OOBE — trois écrans de plus dans une installation censée n'en poser aucun.
    # La stratégie NoLocalPasswordResetQuestions les supprime… sous Windows 10.
    # Sous Windows 11, plusieurs rapports décrivent une erreur OOBELOCAL qui bloque
    # l'installation. On ne la pose donc QUE sous Windows 10 : gagner trois écrans ne
    # vaut pas le risque de planter une installation qu'on ne verra pas échouer.
    $blocQuestions = ""
    if ($MotDePasse -and $Version -eq '10') {
        $blocQuestions = @"
                <RunSynchronousCommand wcm:action="add">
                    <Order>3</Order>
                    <Path>reg add HKLM\SOFTWARE\Policies\Microsoft\Windows\System /v NoLocalPasswordResetQuestions /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
"@
    }

    # Recopie du fichier de réponses vers Panther (voir le passage specialize).
    # On le cherche sur TOUS les lecteurs : une clé USB n'a aucune lettre garantie.
    $copiePanther = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=Get-ChildItem -Path (Get-PSDrive -PSProvider FileSystem).Root -Filter autounattend.xml -ErrorAction SilentlyContinue | Select-Object -First 1; if ($f) { Copy-Item $f.FullName ''C:\Windows\Panther\unattend.xml'' -Force }"'

    # --- Commandes de première ouverture de session -------------------------------
    # Elles s'exécutent une fois, en tant que l'utilisateur créé, session ouverte.
    $cmds = New-Object System.Collections.Generic.List[string]
    $ordre = 1
    # Toutes les traces de la première ouverture de session vont dans un seul fichier,
    # dans un dossier accessible à tous. Sans lui, une installation d'application qui
    # échoue ne laisse RIEN : on découvre l'absence du logiciel des jours plus tard,
    # sans le moindre indice sur la cause.
    $journal = 'C:\Users\Public\madtweak-premier-demarrage.log'

    $ajouteCmd = {
        param($description, $ligne)
        # La documentation fixe la limite à 1024 caractères. Au-delà, Windows tronque
        # ou refuse la commande — et cela ne se verrait qu'au premier démarrage d'une
        # machine déjà formatée. Mieux vaut échouer ici, devant l'utilisateur.
        if ($ligne.Length -gt 1024) {
            throw "Commande de première ouverture trop longue ($($ligne.Length) caractères, maximum 1024) : $description"
        }
        $cmds.Add(@"
                <SynchronousCommand wcm:action="add">
                    <Order>$ordre</Order>
                    <Description>$(& $esc $description)</Description>
                    <CommandLine>$(& $esc $ligne)</CommandLine>
                </SynchronousCommand>
"@)
    }

    if ($Apps.Count -gt 0) {
        # winget n'est PAS disponible tout de suite sur une installation neuve : le
        # paquet « App Installer » est approvisionné en tâche de fond, et la première
        # ouverture de session le précède souvent de plusieurs minutes. Sans cette
        # attente, les installations échouent toutes, en silence, et l'utilisateur
        # conclut que l'outil ne marche pas. On attend donc le RÉSEAU puis winget,
        # avec une borne : mieux vaut continuer sans les applications que bloquer
        # indéfiniment la première session de quelqu'un.
        # Tout est en chaînes SIMPLEMENT quotées : le code ci-dessous doit arriver
        # littéralement dans le fichier, pas être évalué ici. Une seule interpolation
        # au mauvais endroit et c'est la date de génération qui se retrouve gravée
        # dans le fichier de réponses, au lieu de la date d'exécution.
        $attendre = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "' +
        '$fin=(Get-Date).AddMinutes(10); ' +
        'while((Get-Date) -lt $fin -and -not (Get-NetConnectionProfile | Where-Object IPv4Connectivity -eq ''Internet'')) { Start-Sleep 15 }; ' +
        'while((Get-Date) -lt $fin -and -not (Get-Command winget -ErrorAction SilentlyContinue)) { Start-Sleep 15 }; ' +
        'Add-Content ''' + $journal + ''' ((Get-Date).ToString(''s'') + '' | winget disponible : '' + [bool](Get-Command winget -ErrorAction SilentlyContinue))' +
        '"'
        & $ajouteCmd "Attendre le reseau et winget" $attendre
        $ordre++
    }

    foreach ($id in $Apps) {
        # La redirection vers le journal transforme un échec muet en échec lisible.
        & $ajouteCmd "Installer $id" "cmd /c winget install -e --id $id --silent --accept-source-agreements --accept-package-agreements >> `"$journal`" 2>&1"
        $ordre++
    }

    if ($Profil) {
        # MadTweak est attendu a la racine de la cle, montee en general sur D:.
        # On le cherche sur tous les lecteurs plutot que de parier sur une lettre.
        # Le nom du profil voyage en ASCII pur, sans espace ni accent (« Minimal / sur »
        # devient « minimalsur ») : il traverse un XML puis une ligne de commande, et
        # Resolve-NomProfil le retrouve a l'arrivee. Un accent mal transcode ici se
        # solderait par un « profil inconnu » sur une machine fraichement installee,
        # ou personne ne lirait le message.
        $cleProfil = ConvertTo-CleComparable $Profil
        # Le « else » n'est pas decoratif : si MadTweak.ps1 n'a pas ete copie sur la
        # cle, rien ne se passerait et rien ne le dirait. Le journal tranche entre
        # « le profil a echoue » et « le script n'etait pas la ».
        $chercher = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "' +
        '$s=Get-ChildItem -Path (Get-PSDrive -PSProvider FileSystem).Root -Filter MadTweak.ps1 -ErrorAction SilentlyContinue | Select-Object -First 1; ' +
        'if ($s) { Add-Content ''' + $journal + ''' (''MadTweak trouve : '' + $s.FullName); & $s.FullName -Profil ' + $cleProfil + ' } ' +
        'else { Add-Content ''' + $journal + ''' ''MadTweak.ps1 introuvable sur les lecteurs : profil NON applique.'' }"'
        & $ajouteCmd "Appliquer le profil MadTweak $cleProfil" $chercher
        $ordre++
    }

    if ($MotDePasse) {
        # La copie qu'on a posee dans Panther contient le mot de passe en base64.
        # Windows nettoie le fichier qu'il y met LUI-MEME, pas forcement celui qu'on
        # y a depose : sans cette ligne, le mot de passe resterait lisible sur le
        # disque de la machine installee. C'est la derniere commande jouee.
        & $ajouteCmd "Effacer la copie du fichier de reponses" 'cmd /c del /q "C:\Windows\Panther\unattend.xml"'
        $ordre++
    }

    $blocCmds = if ($cmds.Count -gt 0) {
        "            <FirstLogonCommands>`r`n" + ($cmds -join "`r`n") + "`r`n            </FirstLogonCommands>"
    }
    else { "" }

    # --- Contournements matériels (specialize) ------------------------------------
    $blocTPM = ""
    if ($SansTPM) {
        $blocTPM = @"
            <RunSynchronousCommand wcm:action="add">
                <Order>1</Order>
                <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path>
            </RunSynchronousCommand>
            <RunSynchronousCommand wcm:action="add">
                <Order>2</Order>
                <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f</Path>
            </RunSynchronousCommand>
            <RunSynchronousCommand wcm:action="add">
                <Order>3</Order>
                <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path>
            </RunSynchronousCommand>
"@
    }

    # --- Disque : on n'efface RIEN sans demande explicite -------------------------
    # Sans -EffacerDisque, aucune section DiskConfiguration n'est ecrite : Windows
    # pose alors sa question habituelle, et l'utilisateur choisit sa partition.
    # Automatiser un formatage qu'on n'a pas demande serait la pire des surprises.
    $blocDisque = ""
    if ($EffacerDisque) {
        $blocDisque = @"
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <DiskID>$Disque</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                    <CreatePartitions>
                        <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>300</Size></CreatePartition>
                        <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
                        <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>System</Label></ModifyPartition>
                        <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>3</PartitionID><Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter></ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>
"@
    }

    # --- Choix de l'image et cible d'installation ---------------------------------
    # « For unattended installations, you must specify either the InstallTo or the
    # InstallToAvailablePartition setting » (doc Microsoft). Sans ce bloc, effacer
    # le disque laisse l'installeur sans cible : il efface, puis se bloque.
    $blocMeta = ""
    if ($Edition) {
        # ATTENTION aux trois raccourcis : ils fabriquent des noms ANGLAIS, et les
        # ISO localisées traduisent les noms d'édition. Une image française contient
        # « Windows 11 Professionnel », pas « Windows 11 Pro » — constaté sur une
        # vraie image. Le nom fabriqué ne correspondrait alors à rien et
        # l'installation échouerait. Les raccourcis ne valent que pour une image en
        # anglais ; partout ailleurs, il faut lire l'image (Get-EditionsImage).
        $nomEdition = switch ($Edition) {
            'Pro' { "Windows $Version Pro" }
            'Famille' { "Windows $Version Home" }
            'Entreprise' { "Windows $Version Enterprise" }
            # Tout le reste est pris tel quel : c'est un nom lu dans l'image.
            default { $Edition }
        }
        $blocMeta = @"
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <Key>/IMAGE/NAME</Key>
                            <Value>$(& $esc $nomEdition)</Value>
                        </MetaData>
                    </InstallFrom>
"@
    }

    $blocImage = ""
    if ($EffacerDisque -or $blocMeta) {
        # Partition 3 = la partition Windows creee plus haut (1=EFI, 2=MSR, 3=Windows).
        # Sans effacement, on ne fixe PAS de cible : l'utilisateur choisit la sienne.
        $cible = if ($EffacerDisque) {
            @"
                    <InstallTo>
                        <DiskID>$Disque</DiskID>
                        <PartitionID>3</PartitionID>
                    </InstallTo>
"@
        }
        else { "" }
        $blocImage = @"
            <ImageInstall>
                <OSImage>
$blocMeta$cible                    <WillShowUI>OnError</WillShowUI>
                </OSImage>
            </ImageInstall>
"@
    }

    # --- Clé produit --------------------------------------------------------------
    $blocCleProduit = if ($CleProduit) {
        @"
                <ProductKey>
                    <Key>$(& $esc $CleProduit)</Key>
                    <WillShowUI>Never</WillShowUI>
                </ProductKey>
"@
    }
    else {
        # Pas de Key : la documentation interdit d'en écrire une vide. WillShowUI
        # seul reste la seule façon documentée de demander le silence sur ce point.
        @"
                <ProductKey>
                    <WillShowUI>Never</WillShowUI>
                </ProductKey>
"@
    }

    # --- Mot de passe : vide = compte sans mot de passe ---------------------------
    $blocMdp = if ($MotDePasse) {
        @"
                        <Password>
                            <Value>$(ConvertTo-MotDePasseUnattend $MotDePasse)</Value>
                            <PlainText>false</PlainText>
                        </Password>
"@
    }
    else { "" }

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<!--
    Fichier de reponses genere par MadTweak.
    A DEPOSER A LA RACINE de la cle d'installation Windows, a cote de setup.exe.

    Il ne contient aucun composant Microsoft : c'est un fichier de configuration.
    Relis-le avant usage, c'est du texte.
-->
<unattend xmlns="urn:schemas-microsoft-com:unattend">

    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <SetupUILanguage><UILanguage>$($L.UI)</UILanguage></SetupUILanguage>
            <InputLocale>$($L.Clavier)</InputLocale>
            <SystemLocale>$($L.Locale)</SystemLocale>
            <UILanguage>$($L.UI)</UILanguage>
            <UserLocale>$($L.Locale)</UserLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
$blocDisque
$blocImage
            <UserData>
                <AcceptEula>true</AcceptEula>
$blocCleProduit
            </UserData>
$(if ($SansTPM) { "            <RunSynchronous>`r`n$blocTPM`r`n            </RunSynchronous>" })
        </component>
    </settings>

    <!-- wasPassProcessed="false" : une image DEJA personnalisee et sysprepee
         embarque son propre unattend.xml dans C:\Windows\Panther, avec ses
         passages marques comme traites. Le fichier pose sur le support ne
         reprend alors pas la main : constate sur une vraie installation, ou
         les FirstLogonCommands n'ont jamais tourne. Cet attribut redit a
         Windows que ces passages restent a jouer. Il vient de la pratique,
         pas de la documentation, et il est sans effet sur une image vierge. -->
    <settings pass="specialize" wasPassProcessed="false">
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <ComputerName>$(& $esc $NomMachine)</ComputerName>
            <TimeZone>$(& $esc $Fuseau)</TimeZone>
        </component>
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <RunSynchronous>
                <!-- Ceinture-bretelles pour le compte local. Le compte est en fait
                     cree par le bloc LocalAccount du passage oobeSystem, plus bas.
                     Microsoft a retire le SCRIPT bypassnro.cmd en 24H2, mais pas
                     cette valeur de registre, qui fonctionne toujours (25H2 inclus). -->
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE /v BypassNRO /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
                <!-- Recopie du fichier de reponses dans Panther. Depuis 24H2, et
                     surtout en 25H2, le nouvel installeur (SetupPrep.exe, dit
                     « ConX ») lit bien le passage windowsPE mais ignore souvent
                     oobeSystem : le compte local n'est alors pas cree et l'OOBE
                     repose ses questions. Relire le fichier depuis Panther est le
                     chemin historique, et cette copie ne coute rien la ou l'ancien
                     installeur fonctionnait deja. -->
                <RunSynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <Path>$(& $esc $copiePanther)</Path>
                </RunSynchronousCommand>
$blocQuestions
            </RunSynchronous>
        </component>
    </settings>

    <settings pass="oobeSystem" wasPassProcessed="false">
        <!-- Langue du Windows INSTALLE. Le composant « -WinPE » plus haut ne regle
             que l'installeur : sans ce bloc-ci, la machine installee repart en
             disposition par defaut, et on decouvre son clavier en QWERTY. -->
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <InputLocale>$($L.Clavier)</InputLocale>
            <SystemLocale>$($L.Locale)</SystemLocale>
            <UILanguage>$($L.UI)</UILanguage>
            <UserLocale>$($L.Locale)</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <!-- Liste exacte des reglages que Microsoft documente pour automatiser
                 l'OOBE (page « Automate OOBE »). SkipMachineOOBE et SkipUserOOBE en
                 sont volontairement ABSENTS : ils sont deprecies depuis Windows 10
                 1709 et la doc dit noir sur blanc de ne pas s'en servir pour ca.
                 HideWirelessSetupInOOBE reste a false EXPRES : sans reseau, les
                 installations winget de la premiere ouverture de session echouent. -->
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideLocalAccountScreen>true</HideLocalAccountScreen>
                <HideWirelessSetupInOOBE>false</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Name>$(& $esc $NomUtilisateur)</Name>
                        <DisplayName>$(& $esc $NomUtilisateur)</DisplayName>
                        <Group>Administrators</Group>
$blocMdp
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
$blocCmds
        </component>
    </settings>

</unattend>
"@

    # UTF-8 SANS BOM : Windows Setup lit le fichier de reponses en UTF-8 et un BOM
    # peut le faire echouer. C'est la convention INVERSE des modules du projet.
    [System.IO.File]::WriteAllText($Chemin, $xml, (New-Object System.Text.UTF8Encoding($false)))

    # Verification immediate. On ne se contente PAS de verifier que le XML est bien
    # forme : un fichier parfaitement valide peut placer un reglage dans un passage
    # ou Windows l'ignorera sans rien dire. Test-AutounattendXml relit ce qu'on vient
    # d'ecrire et le juge sur le fond. Un probleme se voit ici, devant l'utilisateur,
    # et pas devant l'ecran d'installation d'une machine qu'on vient de formater.
    $pbs = Test-AutounattendXml -Chemin $Chemin
    if ($pbs.Count -gt 0) {
        throw "Le fichier genere est incorrect :`n  - $($pbs -join "`n  - ")"
    }

    return $Chemin
}


# ------------------------------------------------------------------------------
# MENU CONSOLE
# ------------------------------------------------------------------------------

function Read-ChoixListe {
    # Affiche une table ordonnée numérotée et renvoie la CLÉ choisie.
    # Entrée vide = la valeur par défaut : on peut dérouler tout le questionnaire
    # à coups d'Entrée et obtenir un fichier cohérent.
    param(
        [Parameter(Mandatory)]$Liste,
        [Parameter(Mandatory)][string]$Question,
        [int]$Defaut = 1,
        # Au-delà de ce nombre d'entrées, on n'affiche qu'un aperçu : la liste des
        # fuseaux horaires en compte près de 140, et les dérouler noierait la question.
        [int]$Apercu = 0
    )
    $cles = @($Liste.Keys)
    $tronque = ($Apercu -gt 0 -and $cles.Count -gt $Apercu)
    $fin = if ($tronque) { $Apercu } else { $cles.Count }
    for ($i = 0; $i -lt $fin; $i++) {
        $marque = if (($i + 1) -eq $Defaut) { "*" } else { " " }
        Write-Host ("   {0}{1,2} - {2}" -f $marque, ($i + 1), $cles[$i]) -ForegroundColor Gray
    }
    if ($tronque) {
        Write-Host ("    ... et " + ($cles.Count - $Apercu) + " autres — tape 0 pour tout voir.") -ForegroundColor DarkGray
    }
    $r = (Read-Host "  $Question [$Defaut]").Trim()
    if ($tronque -and $r -eq '0') {
        for ($i = 0; $i -lt $cles.Count; $i++) {
            Write-Host ("   {0,3} - {1}" -f ($i + 1), $cles[$i]) -ForegroundColor Gray
        }
        $r = (Read-Host "  $Question [$Defaut]").Trim()
    }
    if (-not $r) { $r = "$Defaut" }
    $n = 0
    if (-not [int]::TryParse($r, [ref]$n) -or $n -lt 1 -or $n -gt $cles.Count) {
        Write-Etat "Choix hors liste : on garde « $($cles[$Defaut - 1]) »." -Niveau Avert
        return $cles[$Defaut - 1]
    }
    return $cles[$n - 1]
}

function Menu-Installation {
    Clear-Host
    Write-Host "=== CLÉ D'INSTALLATION : FICHIER DE RÉPONSES ===" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Génère un fichier autounattend.xml à déposer À LA RACINE de ta clé USB" -ForegroundColor Gray
    Write-Host "  Windows, à côté de setup.exe. L'installation ne pose alors plus de" -ForegroundColor Gray
    Write-Host "  questions : langue, compte, applications et tweaks sont déjà décidés." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  MadTweak ne fournit AUCUNE image Windows : la licence Microsoft interdit" -ForegroundColor Yellow
    Write-Host "  de la redistribuer. Tu télécharges l'ISO officielle toi-même, et ce" -ForegroundColor Yellow
    Write-Host "  fichier vient simplement se poser à côté. C'est du texte, relis-le." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  À SAVOIR sur Windows 11 24H2 et 25H2 : le nouvel installeur de Microsoft" -ForegroundColor Cyan
    Write-Host "  applique bien le disque, l'édition et la langue, mais ignore souvent la" -ForegroundColor Cyan
    Write-Host "  partie « compte utilisateur » — l'écran de création de compte peut donc" -ForegroundColor Cyan
    Write-Host "  réapparaître. Un contournement est inclus, sans garantie possible." -ForegroundColor Cyan
    Write-Host "  Windows 10 et Windows 11 jusqu'à 23H2 ne sont pas concernés." -ForegroundColor Cyan
    Write-Host ""
    $script:CompteurOK = 0; $script:CompteurEchec = 0

    if (-not (Demander-Option "Créer un fichier de réponses maintenant ?")) { return }
    Write-Host ""

    # --- Cible ----------------------------------------------------------------
    $versions = [ordered]@{ "Windows 11" = "11"; "Windows 10" = "10" }
    $version = $versions[(Read-ChoixListe $versions "Quelle version de Windows ?" 1)]
    Write-Host ""

    $editions = [ordered]@{
        "Laisser l'installeur demander (le plus sûr)"    = ""
        "LIRE les éditions dans mon ISO / install.wim"   = "@LIRE"
        "Pro"                                           = "Pro"
        "Famille / Home"                                = "Famille"
        "Entreprise / Enterprise"                       = "Entreprise"
    }
    Write-Host "  Un nom d'édition absent de l'image fait échouer l'installation. Plutôt que" -ForegroundColor DarkGray
    Write-Host "  de deviner, l'option 2 ouvre ton ISO et lit les éditions qu'elle contient." -ForegroundColor DarkGray
    $edition = $editions[(Read-ChoixListe $editions "Quelle édition ?" 1)]

    if ($edition -eq "@LIRE") {
        $edition = ""
        $chemImage = (Read-Host "  Chemin de l'ISO, du install.wim ou du install.esd").Trim().Trim('"')
        try {
            Write-Etat "Lecture de l'image (le montage prend quelques secondes)..." -Niveau Info
            $trouvees = Get-EditionsImage -Chemin $chemImage
            if ($trouvees.Count -eq 0) { throw "Aucune édition trouvée dans cette image." }
            $choix = [ordered]@{}
            foreach ($e in $trouvees) { $choix["$($e.Nom)  (index $($e.Index))"] = $e.Nom }
            Write-Host ""
            Write-Etat "$($trouvees.Count) édition(s) réellement présente(s) dans cette image :" -Niveau OK
            $edition = $choix[(Read-ChoixListe $choix "Laquelle installer ?" 1)]
        }
        catch {
            Write-Etat "Lecture impossible : $($_.Exception.Message)" -Niveau Avert
            Write-Etat "On continue sans préciser l'édition : l'installeur posera la question." -Niveau Info
        }
    }
    Write-Host ""

    # --- Langue et fuseau -----------------------------------------------------
    $langues = Get-LanguesInstallation
    $langue = Read-ChoixListe $langues "Langue et clavier ?" 1
    Write-Host ""
    $fuseaux = Get-FuseauxCourants
    $fuseau = $fuseaux[(Read-ChoixListe $fuseaux "Fuseau horaire ?" 1 -Apercu 6)]
    Write-Host ""

    # --- Compte ---------------------------------------------------------------
    $utilisateur = (Read-Host "  Nom du compte à créer").Trim()
    if (-not $utilisateur) {
        Write-Etat "Aucun nom d'utilisateur : abandon." -Niveau Avert
        if (-not (Test-SansInteraction)) { Read-Host "`nEntrée pour revenir" }
        return
    }

    Write-Host ""
    Write-Host "  ATTENTION : dans un fichier de réponses, un mot de passe n'est PAS" -ForegroundColor Red
    Write-Host "  chiffré. Il est encodé en base64, ce qui se relit en une commande par" -ForegroundColor Red
    Write-Host "  quiconque a la clé USB en main. Laisse VIDE pour créer un compte sans" -ForegroundColor Red
    Write-Host "  mot de passe et en définir un au premier démarrage : c'est plus sûr." -ForegroundColor Red
    $motDePasse = (Read-Host "  Mot de passe (vide = aucun)")
    Write-Host ""

    $machine = (Read-Host "  Nom de la machine (vide = généré)").Trim()

    # --- Profil MadTweak ------------------------------------------------------
    Write-Host ""
    $profils = [ordered]@{ "Aucun (ne rien appliquer)" = "" }
    foreach ($k in $script:Profils.Keys) { $profils[$k] = $k }
    Write-Host "  Le profil sera appliqué à la première ouverture de session, à condition" -ForegroundColor DarkGray
    Write-Host "  que MadTweak.ps1 soit copié à la racine de la même clé USB." -ForegroundColor DarkGray
    $profil = $profils[(Read-ChoixListe $profils "Quel profil appliquer ?" 1)]
    Write-Host ""

    # --- Applications ---------------------------------------------------------
    $apps = @()
    if (Demander-Option "Installer des applications au premier démarrage ?") {
        $noms = @($script:CatalogueApps.Keys)
        for ($i = 0; $i -lt $noms.Count; $i++) {
            Write-Host ("   {0,2} - {1}" -f ($i + 1), $noms[$i]) -ForegroundColor Gray
        }
        $rep = (Read-Host "  Numéros séparés par une virgule (ex : 2,4,10)").Trim()
        foreach ($m in ($rep -split ',')) {
            $n = 0
            if ([int]::TryParse($m.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $noms.Count) {
                $apps += $script:CatalogueApps[$noms[$n - 1]]
            }
        }
        $apps = @($apps | Select-Object -Unique)
        Write-Etat "$($apps.Count) application(s) retenue(s)." -Niveau Info
    }
    Write-Host ""

    # --- Matériel ancien ------------------------------------------------------
    $sansTpm = $false
    if ($version -eq '11') {
        $sansTpm = Demander-Option "Contourner les contrôles TPM / Secure Boot / RAM (machine ancienne) ?"
        Write-Host ""
    }

    # --- Disque : la seule question réellement destructrice -------------------
    Write-Host "  Par défaut, l'installeur demandera OÙ installer Windows, comme d'habitude." -ForegroundColor Gray
    Write-Host "  Tu peux aussi lui dire d'effacer entièrement le premier disque. Dans ce" -ForegroundColor Gray
    Write-Host "  cas il ne demandera plus rien et TOUT le disque 0 sera perdu." -ForegroundColor Gray
    $effacer = $false
    $numDisque = 0
    if (Demander-Option "Effacer automatiquement un disque entier ?") {
        Write-Host ""
        # Les disques affichés sont ceux de CETTE machine. Sur la machine à installer,
        # la numérotation peut différer — c'est dit, parce que se tromper de disque
        # ici efface les données de quelqu'un.
        Write-Host "  Disques de CETTE machine, à titre indicatif :" -ForegroundColor Gray
        try {
            foreach ($dq in (Get-Disk -ErrorAction Stop | Sort-Object Number)) {
                Write-Host ("    disque {0} — {1} Go — {2}" -f $dq.Number,
                    [math]::Round($dq.Size / 1GB), $dq.FriendlyName) -ForegroundColor DarkGray
            }
        }
        catch { Write-Host "    (liste indisponible)" -ForegroundColor DarkGray }
        Write-Host "  ATTENTION : la numérotation de la machine à installer peut être" -ForegroundColor Yellow
        Write-Host "  différente. Vérifie-la là-bas (Maj+F10, puis diskpart, list disk)." -ForegroundColor Yellow
        Write-Host "  Et surtout : selon le micrologiciel, la CLÉ USB elle-même peut" -ForegroundColor Yellow
        Write-Host "  apparaître comme disque 0. L'effacer effacerait le support depuis" -ForegroundColor Yellow
        Write-Host "  lequel l'installation tourne. Dans le doute, laisse cette option de" -ForegroundColor Yellow
        Write-Host "  côté : l'installeur posera simplement la question, ce qui ne coûte" -ForegroundColor Yellow
        Write-Host "  qu'un clic et supprime tout risque de se tromper de disque." -ForegroundColor Yellow
        $rep = (Read-Host "  Numéro du disque à effacer [0]").Trim()
        if ($rep -and -not [int]::TryParse($rep, [ref]$numDisque)) { $numDisque = 0 }
        if (-not $rep) { $numDisque = 0 }

        Write-Host ""
        Write-Host "  Cette option détruit TOUTES les partitions du disque $numDisque, sans" -ForegroundColor Red
        Write-Host "  confirmation au moment de l'installation. Tape EFFACER pour l'activer." -ForegroundColor Red
        $effacer = ((Read-Host "  Confirmation").Trim() -ceq "EFFACER")
        if (-not $effacer) { Write-Etat "Effacement NON activé : l'installeur posera la question." -Niveau Info }
    }
    Write-Host ""

    # --- Génération -----------------------------------------------------------
    $dossier = Join-Path ([Environment]::GetFolderPath("Desktop")) "madtweak-installation"
    $chemin = Join-Path $dossier "autounattend.xml"

    if ($script:Simulation) {
        Write-Simu "générerait $chemin (Windows $version, compte « $utilisateur », $($apps.Count) app(s), effacement : $effacer)"
        if (-not (Test-SansInteraction)) { Read-Host "`nEntrée pour revenir" }
        return
    }

    try {
        if (-not (Test-Path $dossier)) { New-Item -ItemType Directory -Path $dossier -Force | Out-Null }
        $params = @{
            Chemin         = $chemin
            NomUtilisateur = $utilisateur
            MotDePasse     = $motDePasse
            NomMachine     = $machine
            Langue         = $langue
            Fuseau         = $fuseau
            Version        = $version
            Edition        = $edition
            Apps           = $apps
        }
        if ($profil) { $params.Profil = $profil }
        if ($sansTpm) { $params.SansTPM = $true }
        if ($effacer) { $params.EffacerDisque = $true }

        New-AutounattendXml @params | Out-Null

        Write-Host ""
        Write-Etat "Fichier généré : $chemin" -Niveau OK
        Write-Host ""
        Write-Host "  Le parcours complet :" -ForegroundColor Cyan
        Write-Host "   1. Télécharger l'ISO officielle (Media Creation Tool ou Rufus)." -ForegroundColor Gray
        Write-Host "   2. Écrire l'ISO sur la clé avec l'un de ces deux outils." -ForegroundColor Gray
        Write-Host "   3. Déposer les fichiers à la racine de la clé — MadTweak sait le faire." -ForegroundColor Gray
        Write-Host ""

        # --- Préparer la clé de A à Z : la seule opération destructive de l'outil ---
        $usb = @(Get-DisquesUSB)
        if ($usb.Count -gt 0 -and (Demander-Option "Préparer entièrement une clé USB à partir d'une ISO (EFFACE la clé) ?")) {
            Write-Host ""
            Write-Host "  Seules les clés USB sont proposées. Les disques internes n'apparaissent" -ForegroundColor Gray
            Write-Host "  pas dans cette liste et ne peuvent pas être effacés par cette fonction." -ForegroundColor Gray
            Write-Host ""
            $choixUsb = [ordered]@{}
            foreach ($u in $usb) {
                $choixUsb["Disque $($u.Numero) — $($u.Nom) — $($u.Go) Go — $($u.Lettres) $($u.Contenu)"] = $u
            }
            $cible = $choixUsb[(Read-ChoixListe $choixUsb "Quelle clé préparer ?" 1)]
            $iso = (Read-Host "  Chemin de l'ISO Windows officielle").Trim().Trim('"')

            # Si l'édition n'a pas encore été fixée, c'est le moment : on tient l'ISO,
            # autant lui demander ce qu'elle contient plutôt que de le supposer. Les
            # noms sont traduits dans les images localisées (« Windows 11 Professionnel »
            # et non « Windows 11 Pro »), donc les deviner ne marche pas.
            if (-not $edition -and (Test-Path -LiteralPath $iso)) {
                try {
                    Write-Etat "Lecture des éditions de l'image..." -Niveau Info
                    $dispo = Get-EditionsImage -Chemin $iso
                    $choixEd = [ordered]@{}
                    foreach ($e in $dispo) { $choixEd["$($e.Nom)  (index $($e.Index))"] = $e.Nom }
                    $edition = $choixEd[(Read-ChoixListe $choixEd "Quelle édition installer ?" 1 -Apercu 12)]

                    # Le fichier de réponses a été écrit sans édition : on le régénère
                    # avec celle-ci, sinon la clé et le fichier ne diraient pas la
                    # même chose et l'installation s'arrêterait.
                    New-AutounattendXml -Chemin $chemin -NomUtilisateur $utilisateur -MotDePasse $motDePasse `
                        -NomMachine $machine -Langue $langue -Fuseau $fuseau -Version $version `
                        -Edition $edition -Apps $apps -Profil $profil `
                        -SansTPM:$sansTpm -EffacerDisque:$effacer -Disque $numDisque | Out-Null
                    Write-Etat "Fichier de réponses réaligné sur « $edition »." -Niveau OK
                }
                catch { Write-Etat "Lecture des éditions impossible : $($_.Exception.Message)" -Niveau Avert }
            }

            Write-Host ""
            Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Red
            Write-Host "   TOUT LE CONTENU de cette clé va être DÉFINITIVEMENT SUPPRIMÉ :" -ForegroundColor Red
            Write-Host ("     Disque {0} — {1}" -f $cible.Numero, $cible.Nom) -ForegroundColor Red
            Write-Host ("     {0} Go — {1} {2}" -f $cible.Go, $cible.Lettres, $cible.Contenu) -ForegroundColor Red
            Write-Host "   C'est la seule opération de MadTweak qui ne s'annule pas." -ForegroundColor Red
            Write-Host "   Vérifie que c'est la bonne clé, et qu'elle ne contient rien d'utile." -ForegroundColor Red
            Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Tape EFFACER en majuscules pour confirmer, autre chose pour renoncer." -ForegroundColor Yellow
            if ((Read-Host "  Confirmation").Trim() -ceq "EFFACER") {
                $srcMt = $null
                if ($profil) {
                    foreach ($cand in @($PSCommandPath, $MyInvocation.MyCommand.Path)) {
                        if ($cand -and $cand.EndsWith('.ps1') -and (Test-Path $cand)) { $srcMt = $cand; break }
                    }
                }
                try {
                    New-CleInstallation -NumeroDisque $cible.Numero -CheminIso $iso `
                        -CheminXml $chemin -CheminMadTweak $srcMt -Edition $edition -Confirme | Out-Null
                    Write-Etat "La clé est prête : ISO, fichier de réponses et MadTweak sont dessus." -Niveau OK
                }
                catch { Write-Etat "Préparation impossible : $($_.Exception.Message)" -Niveau Echec }
            }
            else { Write-Etat "Renoncé. La clé n'a pas été touchée." -Niveau Info }
            if (-not (Test-SansInteraction)) { Read-Host "`nEntrée pour revenir" }
            return
        }

        # --- Sinon : déposer les fichiers sur une clé DÉJÀ préparée ---------------
        $cles = @(Get-ClesInstallation)
        $pretes = @($cles | Where-Object EstSupport)
        if ($pretes.Count -eq 0) {
            if ($cles.Count -gt 0) {
                Write-Etat "Support amovible détecté, mais aucun ne porte de setup.exe : la clé n'est pas encore préparée." -Niveau Info
            }
            Write-Etat "Prépare la clé avec l'ISO, puis reviens ici : la copie te sera proposée." -Niveau Info
        }
        elseif (Demander-Option "Copier maintenant les fichiers sur la clé d'installation ?") {
            $choixCle = [ordered]@{}
            foreach ($c in $pretes) {
                $choixCle["$($c.Lettre): — $($c.Nom) — $($c.Go) Go"] = $c.Lettre
            }
            $lettre = $choixCle[(Read-ChoixListe $choixCle "Quelle clé ?" 1)]

            # Sans MadTweak.ps1 sur la clé, le profil ne s'appliquera jamais. On ne
            # le copie donc que s'il y a un profil, mais alors on y tient.
            $srcMadTweak = $null
            if ($profil) {
                foreach ($cand in @($PSCommandPath, $MyInvocation.MyCommand.Path)) {
                    if ($cand -and $cand.EndsWith('.ps1') -and (Test-Path $cand)) { $srcMadTweak = $cand; break }
                }
                if (-not $srcMadTweak) {
                    Write-Etat "Impossible de localiser MadTweak.ps1 : seul le fichier de réponses sera copié." -Niveau Avert
                    Write-Etat "Copie-le toi-même à la racine de la clé, sinon le profil ne s'appliquera pas." -Niveau Avert
                }
            }
            try {
                $faits = Copy-FichiersVersCle -Lettre $lettre -CheminXml $chemin -CheminMadTweak $srcMadTweak
                foreach ($fic in $faits) { Write-Etat "Copié : $fic" -Niveau OK }
                Write-Etat "La clé est prête. L'installation ne posera plus de questions." -Niveau OK
            }
            catch {
                Write-Etat "Copie impossible : $($_.Exception.Message)" -Niveau Echec
            }
        }
        Write-Host ""
        if ($motDePasse) {
            Write-Etat "Rappel : le mot de passe est lisible dans ce fichier. Ne prête pas la clé." -Niveau Avert
        }
        $script:CompteurOK++
    }
    catch {
        Write-Etat "Génération impossible : $($_.Exception.Message)" -Niveau Echec
        $script:CompteurEchec++
    }

    if (-not (Test-SansInteraction)) {
        Read-Host "`nAppuie sur Entrée pour revenir au menu principal"
    }
}
# ------------------------------------------------------------------------------
# AUDIT : que vaut cette machine, ici et maintenant ?
#
# À ne pas confondre avec le tableau du menu ANNULER : celui-ci ne connaît que ce
# que CE script a modifié sur CETTE machine. L'audit, lui, lit l'état réel du
# système sans rien présupposer — il voit donc aussi ce qu'un autre outil, une
# stratégie d'entreprise ou une réinstallation de Windows ont laissé derrière eux.
# Il ne modifie STRICTEMENT rien : aucun appel à Set-RegValue ici.
# ------------------------------------------------------------------------------
function Test-RegEgal {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)]$Attendu)
    $v = Get-ValeurActuelle -Path $Path -Name $Name
    if ($null -eq $v) { return $false }
    return "$v" -eq "$Attendu"
}

function Test-ServiceDesactive {
    # $null (et pas $false) quand le service n'existe pas : « absent » et « présent
    # mais actif » sont deux réponses différentes, et les confondre ferait dire à
    # l'audit « pas appliqué » pour un service qui n'a jamais existé ici.
    param([Parameter(Mandatory)][string]$Nom)
    $s = Get-Service -Name $Nom -ErrorAction SilentlyContinue
    if (-not $s) { return $null }
    return ($s.StartType -eq 'Disabled')
}

function Get-CatalogueAudit {
    # Les clés reprennent celles des tweaks (-Cle) : c'est ce qui permet à
    # Test-CoherenceAudit de vérifier que les deux listes ne divergent pas.
    return @(
        @{ Cat = "Vie privée"; Cle = "telemetrie"; Nom = "Télémétrie Windows coupée"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection" "AllowTelemetry" 0 } }
        @{ Cat = "Vie privée"; Cle = "telemetrie"; Nom = "Identifiant publicitaire désactivé"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo" "Enabled" 0 } }
        @{ Cat = "Vie privée"; Cle = "taches-telemetrie"; Nom = "Tâches planifiées de collecte désactivées"
           Test = {
                $t = @(Get-TachesTelemetrie)
                if ($t.Count -eq 0) { return $null }
                # Appliqué seulement si TOUTES sont désactivées : il en reste une
                # active = la collecte continue, donc le tweak n'est pas en place.
                return (@($t | Where-Object { $_.State -ne 'Disabled' }).Count -eq 0)
           } }
        @{ Cat = "Vie privée"; Cle = "recherche-bing"; Nom = "Recherche Bing / web coupée"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "BingSearchEnabled" 0 } }
        @{ Cat = "Vie privée"; Cle = "presse-papiers"; Nom = "Presse-papiers cloud désactivé"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Clipboard" "EnableClipboardHistory" 0 } }
        @{ Cat = "Vie privée"; Cle = "delivery-optimization"; Nom = "Partage P2P des mises à jour coupé"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 0 } }
        @{ Cat = "Vie privée"; Cle = "autoplay"; Nom = "Lecture automatique (AutoPlay) désactivée"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\AutoplayHandlers" "DisableAutoplay" 1 } }
        @{ Cat = "Vie privée"; Cle = "apps-arriere-plan"; Nom = "Apps du Store bloquées en arrière-plan"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy" "LetAppsRunInBackground" 2 } }
        @{ Cat = "Vie privée"; Cle = "bloatwares"; Nom = "Bloatwares du Store désinstallés"
           Test = {
                # On ne teste pas une valeur de registre mais une réalité : reste-t-il
                # un seul de ces paquets ? Un échantillon suffit à trancher.
                $temoins = @("*BingNews*", "*BingWeather*", "*TikTok*", "*Disney*", "*SolitaireCollection*", "*LinkedIn*", "*Clipchamp*")
                $installes = @(Get-AppxPackage -ErrorAction SilentlyContinue)
                if ($installes.Count -eq 0) { return $null }
                foreach ($t in $temoins) {
                    if ($installes | Where-Object { $_.Name -like $t }) { return $false }
                }
                return $true
           } }

        @{ Cat = "Vie privée"; Cle = "historique-activite"; Nom = "Historique d'activité (Timeline) désactivé"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "PublishUserActivities" 0 } }
        @{ Cat = "Vie privée"; Cle = "experiences-personnalisees"; Nom = "Expériences personnalisées désactivées"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Privacy" "TailoredExperiencesWithDiagnosticDataEnabled" 0 } }
        @{ Cat = "Vie privée"; Cle = "feedback"; Nom = "Demandes d'avis (Feedback) coupées"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Siuf\Rules" "NumberOfSIUFInPeriod" 0 } }
        @{ Cat = "Vie privée"; Cle = "saisie-personnalisation"; Nom = "Collecte de la frappe / écriture coupée"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\InputPersonalization" "RestrictImplicitTextCollection" 1 } }
        @{ Cat = "Vie privée"; Cle = "defender-echantillons"; Nom = "Envoi d'échantillons à Defender coupé"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Spynet" "SubmitSamplesConsent" 2 } }
        @{ Cat = "Vie privée"; Cle = "geolocalisation"; Nom = "Géolocalisation refusée aux applications"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location" "Value" "Deny" } }
        @{ Cat = "Vie privée"; Cle = "bloquer-sug-store"; Nom = "Installation automatique d'applications suggérées bloquée"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "SilentInstalledAppsEnabled" 0 } }
        @{ Cat = "Vie privée"; Cle = "edge-telemetrie"; Nom = "Télémétrie et suggestions Microsoft Edge désactivées"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Edge" "MetricsReportingEnabled" 0 } }
        @{ Cat = "Vie privée"; Cle = "amd-telemetrie"; Nom = "Télémétrie AMD Radeon Software désactivée"
           Test = {
                # S'applique uniquement si la clé AMD existe
                if (-not (Test-Path "HKLM:\SOFTWARE\AMD")) { return $null }
                return (Test-RegEgal "HKLM:\SOFTWARE\AMD\CN\ANALYTICS" "ReportAnalytics" 0)
           } }
        @{ Cat = "Vie privée"; Cle = "dev-telemetrie"; Nom = "Télémétrie VS Code / Visual Studio désactivée"
           Test = {
                $vs = Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\VisualStudio\Telemetry" "TurnOffTelemetry" 1
                $vscodeSettings = "$env:APPDATA\Code\User\settings.json"
                $vsc = $true
                if (Test-Path $vscodeSettings) {
                    try {
                        $json = Get-Content $vscodeSettings -Raw | ConvertFrom-Json
                        $vsc = ($json -and $json."telemetry.telemetryLevel" -eq "off")
                    } catch { $vsc = $false }
                }
                return ($vs -and $vsc)
           } }
        @{ Cat = "Vie privée"; Cle = "browsers-telemetrie"; Nom = "Télémétrie Chrome / Firefox désactivée"
           Test = {
                $gc = Test-RegEgal "HKLM:\SOFTWARE\Policies\Google\Chrome" "MetricsReportingEnabled" 0
                $ff = Test-RegEgal "HKLM:\SOFTWARE\Policies\Mozilla\Firefox" "DisableTelemetry" 1
                return ($gc -and $ff)
           } }
        @{ Cat = "Vie privée"; Cle = "office-telemetrie"; Nom = "Télémétrie Microsoft Office désactivée"
           Test = { Test-RegEgal "HKCU:\Software\Policies\Microsoft\Office\Common\ClientTelemetry" "DisableTelemetry" 1 } }
        @{ Cat = "Vie privée"; Cle = "disable-web-search-start"; Nom = "Recherche Web Bing locale désactivée"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" "DisableWebSearch" 1 } }
        @{ Cat = "Vie privée"; Cle = "thirdparty-telemetrie"; Nom = "Services tiers (Google Update, Adobe) en manuel"
           Test = {
                $g1 = $true; $g2 = $true; $a1 = $true; $a2 = $true
                if (Get-Service -Name "gupdate" -ErrorAction SilentlyContinue) { $g1 = (Get-Service "gupdate").StartType -eq "Manual" }
                if (Get-Service -Name "gupdatem" -ErrorAction SilentlyContinue) { $g2 = (Get-Service "gupdatem").StartType -eq "Manual" }
                if (Get-Service -Name "AdobeARMservice" -ErrorAction SilentlyContinue) { $a1 = (Get-Service "AdobeARMservice").StartType -eq "Manual" }
                if (Get-Service -Name "AGSService" -ErrorAction SilentlyContinue) { $a2 = (Get-Service "AGSService").StartType -eq "Manual" }
                return ($g1 -and $g2 -and $a1 -and $a2)
           } }

        @{ Cat = "IA"; Cle = "copilot"; Nom = "Windows Copilot désactivé (stratégie)"
           Test = { Test-RegEgal "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" "TurnOffWindowsCopilot" 1 } }
        @{ Cat = "IA"; Cle = "copilot"; Nom = "App Copilot absente de la machine"
           Test = { $null -eq (Get-AppxPackage -Name "Microsoft.Copilot" -ErrorAction SilentlyContinue) } }
        @{ Cat = "IA"; Cle = "recall"; Nom = "Recall / analyse IA désactivée"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableAIDataAnalysis" 1 } }
        @{ Cat = "IA"; Cle = "paint-ia"; Nom = "Fonctions IA de Paint désactivées"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Paint" "DisableCocreator" 1 } }
        @{ Cat = "IA"; Cle = "click-to-do"; Nom = "Click to Do désactivé"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" "DisableClickToDo" 1 } }

        @{ Cat = "Interface"; Cle = "extensions-fichiers"; Nom = "Extensions de fichiers affichées"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "HideFileExt" 0 } }
        @{ Cat = "Interface"; Cle = "clic-droit-classique"; Nom = "Menu clic droit classique (Windows 10)"
           Test = { Test-Path "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32" } }
        @{ Cat = "Interface"; Cle = "pubs-demarrer"; Nom = "Pubs / recommandations du menu Démarrer coupées"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_IrisRecommendations" 0 } }
        @{ Cat = "Interface"; Cle = "pubs-verrouillage"; Nom = "Pubs de l'écran de verrouillage coupées"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager" "RotatingLockScreenOverlayEnabled" 0 } }
        @{ Cat = "Interface"; Cle = "widgets-dsh"; Nom = "Widgets désactivés (stratégie Dsh)"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Dsh" "AllowNewsAndInterests" 0 } }
        @{ Cat = "Interface"; Cle = "barre-taches-gauche"; Nom = "Barre des tâches alignée à gauche"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAl" 0 } }
        @{ Cat = "Interface"; Cle = "fin-de-tache"; Nom = "'Fin de tâche' ajouté au clic droit de la barre"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings" "TaskbarEndTask" 1 } }
        @{ Cat = "Interface"; Cle = "explorer-separate-process"; Nom = "Dossiers de l'Explorateur isolés dans des processus séparés"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "SeparateProcess" 1 } }
        @{ Cat = "Interface"; Cle = "auto-restart-shell"; Nom = "Relancement automatique de l'Explorateur activé"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon" "AutoRestartShell" 1 } }
        @{ Cat = "Interface"; Cle = "disable-lock-screen"; Nom = "Écran de verrouillage (Lock Screen) désactivé"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Personalization" "NoLockScreen" 1 } }
        @{ Cat = "Interface"; Cle = "animations"; Nom = "Animations des fenêtres désactivées"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarAnimations" 0 } }
        @{ Cat = "Interface"; Cle = "explorateur-accueil"; Nom = "Fichiers récents masqués de l'Explorateur"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer" "ShowRecent" 0 } }
        @{ Cat = "Interface"; Cle = "widgets-chat"; Nom = "Icône Chat retirée de la barre des tâches"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "TaskbarMn" 0 } }
        @{ Cat = "Interface"; Cle = "pubs-scoobe"; Nom = "Écrans 'Tirez le meilleur parti de Windows' coupés"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement" "ScoobeSystemSettingEnabled" 0 } }
        @{ Cat = "Interface"; Cle = "pubs-explorateur"; Nom = "Pubs OneDrive/Store de l'Explorateur coupées"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSyncProviderNotifications" 0 } }
        @{ Cat = "Interface"; Cle = "panneau-telephone"; Nom = "Panneau 'Téléphone' du menu Démarrer masqué (25H2)"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Start\Companions\Microsoft.YourPhone_8wekyb3d8bbwe" "IsEnabled" 0 } }
        @{ Cat = "Interface"; Cle = "net-crawling"; Nom = "Recherche auto des partages réseau désactivée"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "NoNetCrawling" 1 } }

        @{ Cat = "Apparence"; Cle = "mode-sombre"; Nom = "Mode sombre (Windows et applications)"
           Test = {
                $p = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize"
                # Les deux doivent être à 0 : un seul donne un thème à moitié sombre.
                return ((Test-RegEgal $p "AppsUseLightTheme" 0) -and (Test-RegEgal $p "SystemUsesLightTheme" 0))
           } }
        @{ Cat = "Apparence"; Cle = "transparence"; Nom = "Effets de transparence désactivés"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize" "EnableTransparency" 0 } }
        @{ Cat = "Apparence"; Cle = "accent-barres-titre"; Nom = "Couleur d'accentuation sur les barres de titre"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\DWM" "ColorPrevalence" 1 } }
        @{ Cat = "Apparence"; Cle = "qualite-fond-ecran"; Nom = "Fond d'écran en qualité maximale"
           Test = { Test-RegEgal "HKCU:\Control Panel\Desktop" "JPEGImportQuality" 100 } }
        @{ Cat = "Apparence"; Cle = "fichiers-caches"; Nom = "Fichiers cachés affichés"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Hidden" 1 } }
        @{ Cat = "Apparence"; Cle = "fichiers-systeme"; Nom = "Fichiers système protégés affichés"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSuperHidden" 1 } }
        @{ Cat = "Apparence"; Cle = "explorateur-ce-pc"; Nom = "Explorateur ouvre sur « Ce PC »"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "LaunchTo" 1 } }
        @{ Cat = "Apparence"; Cle = "explorateur-compact"; Nom = "Explorateur en affichage compact"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "UseCompactMode" 1 } }
        @{ Cat = "Apparence"; Cle = "explorateur-galerie"; Nom = "« Galerie » retirée du volet de navigation"
           Test = {
                # Retiré = la clé d'espace de noms n'existe plus dans aucune ruche.
                foreach ($r in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace",
                                 "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace")) {
                    if (Test-Path "$r\{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}") { return $false }
                }
                return $true
           } }
        @{ Cat = "Apparence"; Cle = "explorateur-volet-accueil"; Nom = "« Accueil » retiré du volet de navigation"
           Test = {
                foreach ($r in @("HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace",
                                 "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Explorer\Desktop\NameSpace")) {
                    if (Test-Path "$r\{f874310e-b6b7-47dc-bc84-b9e6b38f5903}") { return $false }
                }
                return $true
           } }
        @{ Cat = "Apparence"; Cle = "suffixe-raccourci"; Nom = "Suffixe « - Raccourci » supprimé"
           Test = {
                $v = Get-ValeurActuelle -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer" -Name "link"
                if ($null -eq $v) { return $false }
                return (@($v | Where-Object { $_ -ne 0 }).Count -eq 0)
           } }
        @{ Cat = "Apparence"; Cle = "recherche-barre-taches"; Nom = "Barre de recherche réduite (icône ou masquée)"
           Test = {
                $v = Get-ValeurActuelle -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Search" -Name "SearchboxTaskbarMode"
                if ($null -eq $v) { return $false }
                return ($v -in @(0, 1))
           } }
        @{ Cat = "Apparence"; Cle = "bouton-vue-taches"; Nom = "Bouton « Vue des tâches » masqué"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowTaskViewButton" 0 } }
        @{ Cat = "Apparence"; Cle = "horloge-secondes"; Nom = "Secondes affichées dans l'horloge"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "ShowSecondsInSystemClock" 1 } }
        @{ Cat = "Apparence"; Cle = "demarrer-plus-epingles"; Nom = "Menu Démarrer : plus d'épingles"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "Start_Layout" 1 } }
        @{ Cat = "Apparence"; Cle = "aero-shake"; Nom = "Aero Shake désactivé"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "DisallowShaking" 1 } }
        @{ Cat = "Apparence"; Cle = "snap-layouts"; Nom = "Menu volant des dispositions d'ancrage désactivé"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" "EnableSnapAssistFlyout" 0 } }
        @{ Cat = "Apparence"; Cle = "barres-defilement"; Nom = "Barres de défilement toujours visibles"
            Test = { Test-RegEgal "HKCU:\Control Panel\Accessibility" "DynamicScrollbars" 0 } }
        @{ Cat = "Apparence"; Cle = "menu-delay"; Nom = "Délai d'affichage des menus réduit"
            Test = { Test-RegEgal "HKCU:\Control Panel\Desktop" "MenuShowDelay" "20" } }
        @{ Cat = "Apparence"; Cle = "disable-login-blur"; Nom = "Flou de l'arrière-plan de connexion désactivé"
            Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\System" "DisableLogonBackgroundImage" 1 } }

        @{ Cat = "Performance"; Cle = "noyau-en-ram"; Nom = "Noyau maintenu en RAM"
           Test = { Test-RegEgal "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management" "DisablePagingExecutive" 1 } }
        @{ Cat = "Performance"; Cle = "game-dvr"; Nom = "Game DVR (enregistrement de fond) coupé"
           Test = { Test-RegEgal "HKCU:\System\GameConfigStore" "GameDVR_Enabled" 0 } }
        @{ Cat = "Performance"; Cle = "souris-acceleration"; Nom = "Accélération de la souris désactivée"
           Test = { Test-RegEgal "HKCU:\Control Panel\Mouse" "MouseSpeed" "0" } }
        @{ Cat = "Performance"; Cle = "tuer-applis-figees"; Nom = "Applications figées tuées automatiquement"
           Test = { Test-RegEgal "HKCU:\Control Panel\Desktop" "AutoEndTasks" "1" } }
        @{ Cat = "Performance"; Cle = "longpaths"; Nom = "Limite des 260 caractères levée"
           Test = { Test-RegEgal "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "LongPathsEnabled" 1 } }
        @{ Cat = "Performance"; Cle = "ntfs-lastaccess"; Nom = "Horodatage NTFS à la lecture désactivé"
           Test = {
                $s = (fsutil.exe behavior query disablelastaccess 2>&1 | Out-String)
                if ($s -match '=\s*([0-9])') { return ($Matches[1] -in @('1', '3')) }
                return $null
           } }

        @{ Cat = "Performance"; Cle = "sudo"; Nom = "'sudo' activé (24H2+)"
           Test = {
                # « Sudo indisponible sur cette version » et « Sudo disponible mais
                # laissé désactivé » sont deux réponses différentes : c'est la
                # présence de la CLÉ qui tranche, pas celle de la valeur (absente
                # tant que personne n'a activé la fonction).
                $sudo = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Sudo"
                if (-not (Test-Path $sudo)) { return $null }
                $v = Get-ValeurActuelle -Path $sudo -Name "Enabled"
                return ($null -ne $v -and $v -ne 0)
           } }
        @{ Cat = "Performance"; Cle = "hibernation"; Nom = "Hibernation et démarrage rapide désactivés"
            Test = { Test-RegEgal "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "HibernateEnabled" 0 } }
        @{ Cat = "Performance"; Cle = "demarrage-rapide"; Nom = "Démarrage rapide (Fast Startup) désactivé"
            Test = { Test-RegEgal "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power" "HiberbootEnabled" 0 } }
        @{ Cat = "Performance"; Cle = "modern-standby"; Nom = "Veille moderne (Modern Standby S0) désactivée"
            Test = { Test-RegEgal "HKLM:\SYSTEM\CurrentControlSet\Control\Power" "PlatformAoAcOverride" 0 } }
        @{ Cat = "Performance"; Cle = "regback-backup"; Nom = "Sauvegardes périodiques du Registre (RegBack) activées"
            Test = { Test-RegEgal "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager" "EnablePeriodicalBackup" 1 } }
        @{ Cat = "Performance"; Cle = "defender-cpu-limit"; Nom = "Usage CPU de Defender limité à 30% lors des scans"
            Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan" "AvgCPULimit" 30 } }
        @{ Cat = "Performance"; Cle = "hags-gpu"; Nom = "Planification GPU accélérée par le matériel (HAGS) activée"
            Test = { Test-RegEgal "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" "HwSchMode" 2 } }
        @{ Cat = "Performance"; Cle = "pcie-power-management"; Nom = "Économie d'énergie PCIe (Link State) désactivée"
            Test = {
                 $s = (powercfg.exe /q SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a821a03c4f3d 501a4d13-42af-4429-9fd1-a821a03c4f3d 2>&1 | Out-String)
                 if ($s -match '0x00000000') { return $true }
                 return $false
            } }
        @{ Cat = "Performance"; Cle = "xbox-gamebar"; Nom = "Fonctions de fond Xbox Game Bar désactivées"
            Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" "AppCaptureEnabled" 0 } }
        @{ Cat = "Performance"; Cle = "disable-low-disk-warning"; Nom = "Alertes d'espace disque faible désactivées"
            Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Policies\Explorer" "NoLowDiskSpaceChecks" 1 } }
        @{ Cat = "Performance"; Cle = "kill-timeouts"; Nom = "Délais d'arrêt des applications réduits (Kill Timeouts)"
            Test = { Test-RegEgal "HKLM:\SYSTEM\CurrentControlSet\Control" "WaitToKillServiceTimeout" "2000" } }
        @{ Cat = "Performance"; Cle = "ntfs-performance"; Nom = "Création des noms courts 8.3 NTFS désactivée"
            Test = { Test-RegEgal "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" "NtfsDisable8dot3NameCreation" 1 } }
        @{ Cat = "Performance"; Cle = "plan-performances-ultimes"; Nom = "Plan 'Performances ultimes' présent"
            Test = {
                 # Le GUID du plan est stable ; son NOM est traduit, donc inutilisable.
                 $s = (powercfg.exe /list 2>&1 | Out-String)
                 if (-not $s) { return $null }
                 return ($s -match 'e9a42b02-d5df-448d-aa00-03f14749eb61')
            } }

        @{ Cat = "Réseau"; Cle = "qos"; Nom = "Bridage QoS (20% réservés) levé"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\Psched" "NonBestEffortLimit" 0 } }
        @{ Cat = "Réseau"; Cle = "bridage-multimedia"; Nom = "Bridage réseau multimédia levé"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile" "NetworkThrottlingIndex" ([int]-1) } }
        @{ Cat = "Réseau"; Cle = "nagle"; Nom = "Algorithme de Nagle désactivé"
           Test = {
                $base = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
                if (-not (Test-Path $base)) { return $null }
                $actives = @(Get-ChildItem $base | Where-Object {
                    $p = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).PSObject.Properties.Name
                    $p -match 'DhcpIPAddress|^IPAddress$'
                })
                if ($actives.Count -eq 0) { return $null }
                # Vrai seulement si TOUTES les interfaces actives le portent : une
                # seule carte réglée sur deux, c'est un tweak à moitié appliqué.
                foreach ($i in $actives) {
                    if (-not (Test-RegEgal $i.PSPath "TCPNoDelay" 1)) { return $false }
                }
                return $true
           } }

        @{ Cat = "Réseau"; Cle = "llmnr-netbios"; Nom = "LLMNR désactivé"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" "EnableMulticast" 0 } }
        @{ Cat = "Réseau"; Cle = "llmnr-netbios"; Nom = "NetBIOS désactivé sur toutes les interfaces"
           Test = {
                $nb = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces"
                if (-not (Test-Path $nb)) { return $null }
                $i = @(Get-ChildItem $nb -ErrorAction SilentlyContinue)
                if ($i.Count -eq 0) { return $null }
                foreach ($x in $i) { if (-not (Test-RegEgal $x.PSPath "NetbiosOptions" 2)) { return $false } }
                return $true
           } }
        @{ Cat = "Réseau"; Cle = "doh"; Nom = "DNS chiffré (DoH) autorisé"
           Test = {
                $v = Get-ValeurActuelle -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "DoHPolicy"
                if ($null -eq $v) { return $false }
                return ($v -in @(2, 3))
           } }
        @{ Cat = "Réseau"; Cle = "carte-reseau-veille"; Nom = "Mise en veille des cartes réseau interdite"
           Test = {
                $cartes = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
                if ($cartes.Count -eq 0) { return $null }
                $classe = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
                if (-not (Test-Path $classe)) { return $null }
                $vues = 0
                foreach ($sk in (Get-ChildItem $classe -ErrorAction SilentlyContinue | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
                    $d = (Get-ItemProperty $sk.PSPath -Name "DriverDesc" -ErrorAction SilentlyContinue).DriverDesc
                    if (-not $d -or $d -notin $cartes.InterfaceDescription) { continue }
                    $vues++
                    if (-not (Test-RegEgal $sk.PSPath "PnPCapabilities" 24)) { return $false }
                }
                if ($vues -eq 0) { return $null }
                return $true
           } }
        @{ Cat = "Réseau"; Cle = "delivery-optimization-p2p"; Nom = "Partage de mises à jour P2P désactivé"
           Test = { Test-RegEgal "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" "DODownloadMode" 0 } }

        @{ Cat = "Performance"; Cle = "delai-demarrage"; Nom = "Délai de démarrage des programmes supprimé"
           Test = { Test-RegEgal "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize" "StartupDelayInMSec" 0 } }

        @{ Cat = "Services"; Cle = "sysmain"; Nom = "SysMain / Superfetch désactivé"
           Test = { Test-ServiceDesactive "SysMain" } }
        @{ Cat = "Services"; Cle = "service-diagtrack"; Nom = "Service de télémétrie DiagTrack désactivé"
           Test = { Test-ServiceDesactive "DiagTrack" } }
        @{ Cat = "Services"; Cle = "service-fax"; Nom = "Service Fax désactivé"
           Test = { Test-ServiceDesactive "Fax" } }
        @{ Cat = "Services"; Cle = "service-registre-distant"; Nom = "Registre distant désactivé"
           Test = { Test-ServiceDesactive "RemoteRegistry" } }
        @{ Cat = "Services"; Cle = "service-retaildemo"; Nom = "Mode démonstration magasin désactivé"
           Test = { Test-ServiceDesactive "RetailDemo" } }
        @{ Cat = "Services"; Cle = "service-cartes"; Nom = "Téléchargement des cartes (MapsBroker) désactivé"
           Test = { Test-ServiceDesactive "MapsBroker" } }
        @{ Cat = "Services"; Cle = "service-bluetooth"; Nom = "Service Bluetooth désactivé"
           Test = { Test-ServiceDesactive "bthserv" } }
        @{ Cat = "Services"; Cle = "wer"; Nom = "Rapport d'erreurs Windows désactivé"
           Test = { Test-ServiceDesactive "WerSvc" } }
        @{ Cat = "Services"; Cle = "spouleur"; Nom = "Spouleur d'impression désactivé"
           Test = { Test-ServiceDesactive "Spooler" } }
        @{ Cat = "Services"; Cle = "nvidia-telemetrie"; Nom = "Télémétrie NVIDIA désactivée"
           Test = { Test-ServiceDesactive "NvTelemetryContainer" } }
        @{ Cat = "Services"; Cle = "service-search"; Nom = "Indexation de fichiers Windows Search désactivée"
           Test = { Test-ServiceDesactive "WSearch" } }
    )
}

function Get-EtatAudit {
    # Renvoie un état par CLÉ à partir du catalogue d'audit : 'OUI' (appliqué),
    # 'NON' (laissé au défaut) ou '?' (non applicable / indéterminable ici).
    # Plusieurs tests peuvent porter la même clé : la clé n'est 'OUI' que si aucun
    # de ses tests n'est 'NON'. Sert à colorer les cases de l'interface selon l'état
    # réel de la machine (et pas seulement ce que ce script a fait).
    $res = @{}
    foreach ($a in Get-CatalogueAudit) {
        $r = $null
        try { $r = & $a.Test } catch { $r = $null }
        $prec = $res[$a.Cle]
        if ($r -eq $false) { $res[$a.Cle] = 'NON' }              # un NON l'emporte et reste
        elseif ($r -eq $true) { if ($prec -ne 'NON') { $res[$a.Cle] = 'OUI' } }
        else { if (-not $prec) { $res[$a.Cle] = '?' } }          # null : n'écrase pas un vrai verdict
    }
    return $res
}

function Get-AuditComplet {
    # Exécute le catalogue d'audit UNE SEULE FOIS et en tire les deux vues dont
    # l'interface a besoin : l'état par clé (pour colorer les cases) et le score de
    # santé (pour la note). Les calculer séparément lançait les ~104 tests deux fois,
    # dont plusieurs interrogent le disque ou les paquets Appx : c'était le double du
    # temps d'attente pour exactement le même résultat.
    $etat = @{}
    $parCat = [ordered]@{}
    $oui = 0; $total = 0
    foreach ($a in Get-CatalogueAudit) {
        $r = $null
        try { $r = & $a.Test } catch { $r = $null }

        # --- Vue 1 : état par clé (un NON l'emporte et reste) ---
        $prec = $etat[$a.Cle]
        if ($r -eq $false) { $etat[$a.Cle] = 'NON' }
        elseif ($r -eq $true) { if ($prec -ne 'NON') { $etat[$a.Cle] = 'OUI' } }
        else { if (-not $prec) { $etat[$a.Cle] = '?' } }

        # --- Vue 2 : score (les non applicables sont hors barème) ---
        if ($null -eq $r) { continue }
        if (-not $parCat.Contains($a.Cat)) { $parCat[$a.Cat] = @{ OK = 0; Total = 0 } }
        $parCat[$a.Cat].Total++
        $total++
        if ($r -eq $true) { $parCat[$a.Cat].OK++; $oui++ }
    }
    $detail = [ordered]@{}
    foreach ($c in $parCat.Keys) {
        $t = $parCat[$c].Total
        $detail[$c] = if ($t -gt 0) { [int](100 * $parCat[$c].OK / $t) } else { 0 }
    }
    $note = if ($total -gt 0) { [int](100 * $oui / $total) } else { 0 }
    $mention = if ($note -ge 80) { "excellent" } elseif ($note -ge 60) { "bon" } elseif ($note -ge 40) { "moyen" } else { "à optimiser" }
    return @{
        Etat  = $etat
        Score = @{ Note = $note; Mention = $mention; Appliques = $oui; Total = $total; Detail = $detail }
    }
}

function Get-AnalyseDemarrage {
    # Ce qui se lance au démarrage, avec son COÛT RÉEL en millisecondes quand Windows
    # l'a mesuré. Le journal Diagnostics-Performance (event 101) contient ce chiffre :
    # c'est la même source que le Gestionnaire des tâches, pas une estimation.
    $cout = @{}
    try {
        Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 101 } -MaxEvents 120 -ErrorAction Stop |
            ForEach-Object {
                $x = [xml]$_.ToXml()
                $nom = ($x.Event.EventData.Data | Where-Object { $_.Name -eq 'Name' }).'#text'
                $ms = ($x.Event.EventData.Data | Where-Object { $_.Name -eq 'TotalTime' }).'#text'
                if ($nom -and $ms) {
                    $v = [int]$ms
                    # On garde le pire relevé : c'est celui qu'on subit au pire démarrage.
                    if (-not $cout.ContainsKey($nom) -or $cout[$nom] -lt $v) { $cout[$nom] = $v }
                }
            }
    }
    catch { }

    $res = @()
    $cles = @(
        @{ P = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"; Zone = "Utilisateur" }
        @{ P = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"; Zone = "Machine" }
    )
    foreach ($k in $cles) {
        if (-not (Test-Path $k.P)) { continue }
        $item = Get-Item $k.P -ErrorAction SilentlyContinue
        if (-not $item) { continue }
        foreach ($n in $item.GetValueNames()) {
            if (-not $n) { continue }
            # Le coût est indexé par nom d'exécutable : on rapproche par correspondance.
            $ms = 0
            foreach ($c in $cout.Keys) { if ($c -like "*$n*" -or $n -like "*$c*") { $ms = $cout[$c]; break } }
            $res += [pscustomobject]@{ Nom = $n; Zone = $k.Zone; CoutMs = $ms; Commande = "$($item.GetValue($n))" }
        }
    }
    # Durée du dernier démarrage (event 100), pour donner un ordre de grandeur.
    $boot = 0
    try {
        $e = Get-WinEvent -FilterHashtable @{ LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'; Id = 100 } -MaxEvents 1 -ErrorAction Stop
        $x = [xml]$e.ToXml()
        $boot = [int](($x.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' }).'#text')
    }
    catch { }
    return @{ Programmes = @($res | Sort-Object CoutMs -Descending); BootMs = $boot }
}

function Get-AnalyseDisque {
    # Où part l'espace, MESURÉ avant de proposer quoi que ce soit. On ne devine pas :
    # chaque poste est parcouru et pesé, et on affiche ce qui est réellement récupérable.
    $postes = @(
        @{ Nom = "Temporaires utilisateur"; Chemin = "$env:TEMP" }
        @{ Nom = "Temporaires Windows"; Chemin = "$env:SystemRoot\Temp" }
        @{ Nom = "Cache Windows Update"; Chemin = "$env:SystemRoot\SoftwareDistribution\Download" }
        @{ Nom = "Rapports d'erreurs"; Chemin = "$env:ProgramData\Microsoft\Windows\WER" }
        @{ Nom = "Miniatures / cache Explorateur"; Chemin = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer" }
        @{ Nom = "Livraison optimisée (P2P)"; Chemin = "$env:SystemRoot\SoftwareDistribution\DeliveryOptimization" }
        @{ Nom = "Windows.old (ancienne install)"; Chemin = "$env:SystemDrive\Windows.old" }
        @{ Nom = "Téléchargements"; Chemin = "$env:USERPROFILE\Downloads" }
    )
    $res = @()
    foreach ($p in $postes) {
        if (-not (Test-Path $p.Chemin)) { continue }
        $o = 0
        try {
            $o = (Get-ChildItem -Path $p.Chemin -Recurse -Force -File -ErrorAction SilentlyContinue |
                    Measure-Object -Property Length -Sum).Sum
        }
        catch { }
        if (-not $o) { $o = 0 }
        $res += [pscustomobject]@{ Nom = $p.Nom; Mo = [math]::Round($o / 1MB, 1); Chemin = $p.Chemin }
    }
    # hiberfil.sys ne se parcourt pas (fichier verrouillé) : on le pèse directement.
    $hib = "$env:SystemDrive\hiberfil.sys"
    try {
        $f = Get-Item $hib -Force -ErrorAction Stop
        $res += [pscustomobject]@{ Nom = "Fichier d'hibernation"; Mo = [math]::Round($f.Length / 1MB, 1); Chemin = $hib }
    }
    catch { }
    $libre = 0; $totalDisque = 0
    try {
        $d = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop
        $libre = [math]::Round($d.Free / 1GB, 1); $totalDisque = [math]::Round(($d.Free + $d.Used) / 1GB, 1)
    }
    catch { }
    return @{ Postes = @($res | Sort-Object Mo -Descending); LibreGo = $libre; TotalGo = $totalDisque }
}

function Get-LogicielsIndesirables {
    # Repère les logiciels notoirement indésirables (antivirus OEM en essai, faux
    # « boosters », barres d'outils). On ne supprime RIEN ici : on signale, avec la
    # commande de désinstallation que Windows a enregistrée. C'est à l'utilisateur de
    # décider -- un antivirus, même mauvais, ne se retire pas dans son dos.
    $motifs = @(
        @{ Regex = 'McAfee|Norton Security|Norton 360|Avast|AVG (Antivirus|Protection)|Kaspersky'; Categorie = "Antivirus préinstallé (essai)"; Pourquoi = "Souvent une version d'essai OEM : ralentit la machine et harcèle de pop-ups. Windows Defender suffit." }
        @{ Regex = 'Driver ?(Booster|Updater|Easy)|PC ?(Booster|Cleaner|Optimizer|Accelerate)|Advanced SystemCare|CCleaner Browser|Reimage|MyPC|WinZip Driver'; Categorie = "Faux optimiseur / nettoyeur"; Pourquoi = "Ces outils promettent des gains fictifs, s'installent en profondeur et poussent à l'achat. À retirer." }
        @{ Regex = 'Toolbar|Web Companion|Search App|Ask\.com|Yahoo! ?Search'; Categorie = "Barre d'outils / détournement de recherche"; Pourquoi = "Détourne ton navigateur et ta recherche par défaut." }
        @{ Regex = 'Booking\.com|ExpressFiles|Wondershare|Bonjour\b'; Categorie = "Logiciel OEM superflu"; Pourquoi = "Installé par le constructeur, rarement utilisé." }
    )
    $chemins = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $apps = @()
    try {
        $apps = @(Get-ItemProperty $chemins -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName -and -not $_.SystemComponent })
    }
    catch { }
    $res = @()
    foreach ($a in $apps) {
        foreach ($m in $motifs) {
            if ($a.DisplayName -match $m.Regex) {
                $res += [pscustomobject]@{
                    Nom = $a.DisplayName; Editeur = "$($a.Publisher)"
                    Categorie = $m.Categorie; Pourquoi = $m.Pourquoi
                    Desinstalleur = "$($a.UninstallString)"
                }
                break
            }
        }
    }
    return @($res | Sort-Object Nom -Unique)
}

function Get-DeriveTweaks {
    # « Dérive » : clés que cet outil a DÉJÀ appliquées mais que l'audit voit
    # maintenant NON appliquées -- typiquement réactivées par une mise à jour Windows
    # (télémétrie, Copilot, pubs qui reviennent). On ne peut la détecter que pour les
    # tweaks audités ; les autres n'ont pas de test d'état.
    $appliquees = @(Get-ClesAppliquees)
    if ($appliquees.Count -eq 0) { return @() }
    $etat = Get-EtatAudit
    return @($appliquees | Where-Object { $etat[$_] -eq 'NON' } | Select-Object -Unique)
}

function New-RapportHTML {
    # Écrit un rapport HTML AUTONOME (un seul fichier, styles en ligne) de l'état
    # actuel de la machine : infos système + chaque réglage audité avec son verdict.
    # Retourne le chemin.
    param([string]$Chemin)
    if (-not $Chemin) {
        $Chemin = Join-Path $script:DossierDonnees ("rapport-madtweak-{0}.html" -f (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'))
    }
    $esc = { param($s) ("$s" -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;') }
    $oui = 0; $non = 0; $ind = 0; $cat = $null
    $corps = New-Object System.Text.StringBuilder
    [void]$corps.Append("<table>")
    foreach ($a in Get-CatalogueAudit) {
        $r = $null; try { $r = & $a.Test } catch { $r = $null }
        if ($a.Cat -ne $cat) { $cat = $a.Cat; [void]$corps.Append("<tr class='cat'><td colspan='2'>$(& $esc (Get-CatAudit $cat))</td></tr>") }
        switch ($r) {
            $true { $cls = 'oui'; $lbl = 'Actif'; $oui++ }
            $false { $cls = 'non'; $lbl = 'Au défaut'; $non++ }
            default { $cls = 'ind'; $lbl = 'N/A'; $ind++ }
        }
        [void]$corps.Append("<tr><td>$(& $esc (Get-NomAudit $a.Nom))</td><td class='$cls'>$lbl</td></tr>")
    }
    [void]$corps.Append("</table>")

    $os = "$($script:InfosOS.DisplayVersion) — build $($script:BuildOS).$($script:InfosOS.UBR) — $($script:InfosOS.EditionID)"
    $date = Get-Date -Format 'dd/MM/yyyy HH:mm'
    $total = $oui + $non + $ind
    $html = @"
<!doctype html><html lang="fr"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Rapport MadTweak</title>
<style>
 :root { color-scheme: dark; }
 body { font-family: 'Segoe UI', system-ui, sans-serif; background:#1b1b1f; color:#d8d8dc; margin:0; padding:24px; }
 .wrap { max-width: 900px; margin: 0 auto; }
 h1 { color:#e01008; font-size: 22px; margin:0 0 4px; }
 .meta { color:#8a8a92; font-size:13px; margin-bottom:18px; }
 .sum { display:flex; gap:10px; margin:18px 0; flex-wrap:wrap; }
 .card { background:#232329; border:1px solid #3f3f46; border-radius:8px; padding:10px 16px; }
 .card b { font-size:20px; display:block; }
 .oui-c b { color:#5cc86e; } .non-c b { color:#d8d8dc; } .ind-c b { color:#caa24a; }
 .score-c { border-color:#e01008; } .score-c b { color:#e01008; font-size:26px; }
 table { width:100%; border-collapse:collapse; margin-top:8px; }
 td { padding:7px 10px; border-bottom:1px solid #2a2a30; font-size:14px; }
 tr.cat td { background:#232329; color:#4fa6e8; font-weight:bold; text-transform:uppercase; font-size:12px; letter-spacing:.5px; border:0; padding-top:16px; }
 td.oui { color:#5cc86e; font-weight:600; text-align:right; white-space:nowrap; }
 td.non { color:#8a8a92; text-align:right; white-space:nowrap; }
 td.ind { color:#caa24a; text-align:right; white-space:nowrap; }
 .foot { color:#5a5a62; font-size:11px; margin-top:24px; }
</style></head><body><div class="wrap">
<h1>MadTweak — rapport d'état</h1>
<div class="meta">$(& $esc $env:COMPUTERNAME) · $(& $esc $os) · généré le $date</div>
<div class="sum">
 <div class="card score-c"><b>$(if (($oui + $non) -gt 0) { [int](100 * $oui / ($oui + $non)) } else { 0 })/100</b>score de santé</div>
 <div class="card oui-c"><b>$oui</b>actifs</div>
 <div class="card non-c"><b>$non</b>au défaut</div>
 <div class="card ind-c"><b>$ind</b>non applicables</div>
 <div class="card"><b>$total</b>réglages testés</div>
</div>
$($corps.ToString())
<div class="foot">Lecture seule : ce rapport reflète l'état réel du système, pas seulement ce que ce script a modifié. Généré par MadTweak v$($script:Version).</div>
</div></body></html>
"@
    Set-Content -Path $Chemin -Value $html -Encoding UTF8
    return $Chemin
}

function Get-DiagnosticPlantages {
    # Lit les plantages récents (Kernel-Power 41 = arrêt inattendu, BugCheck 1001 =
    # écran bleu) et croise avec les tweaks d'alim/matériel ACTUELLEMENT actifs pour
    # désigner des suspects. Né du bug « modern-standby » : automatise le diagnostic
    # qu'on a fait à la main. Lecture seule.
    $depuis = (Get-Date).AddDays(-21)
    $crashes = @()
    try {
        $crashes = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41, 1001; StartTime = $depuis } -ErrorAction Stop |
                Select-Object -First 10 TimeCreated, Id)
    }
    catch { }

    $suspects = @()
    # Le pire, et de loin : forcer la veille S3 sur une plateforme à veille moderne S0.
    $aoac = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name PlatformAoAcOverride -ErrorAction SilentlyContinue).PlatformAoAcOverride
    if ($aoac -eq 0 -and (((powercfg /a) -join ' ') -match 'S0')) {
        $suspects += @{ Cle = 'modern-standby'; Gravite = 'ÉLEVÉ'
            Nom = "Veille S3 forcée sur une plateforme à veille moderne S0 (PlatformAoAcOverride=0)"
            Conseil = "Cause classique de plantage au réveil et en sortie d'hibernation. À annuler en priorité."
        }
    }
    # Suspects mineurs : ne les signaler que s'il y a réellement eu des plantages.
    if ($crashes.Count -gt 0) {
        $hags = (Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name HwSchMode -ErrorAction SilentlyContinue).HwSchMode
        if ($hags -eq 2) {
            $suspects += @{ Cle = 'hags-gpu'; Gravite = 'faible'
                Nom = "Planification GPU matérielle (HAGS) activée"
                Conseil = "Peut causer des instabilités sur certains pilotes GPU. À tester en dernier recours."
            }
        }
    }
    return @{ Crashes = @($crashes); Suspects = @($suspects) }
}

function Test-CoherenceAudit {
    # Même logique que Test-ClesProfils : l'audit et les tweaks doivent parler des
    # mêmes clés. Un audit qui teste une clé qu'aucun tweak ne pose signalerait un
    # réglage impossible à appliquer depuis ce script.
    $source = Get-Content -Path $PSCommandPath -Raw -ErrorAction SilentlyContinue
    if (-not $source) { return }
    $reelles = [regex]::Matches($source, '-Cle\s+"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }
    $orphelines = @(Get-CatalogueAudit | Where-Object { $_.Cle -notin $reelles } | ForEach-Object { $_.Cle } | Select-Object -Unique)
    if ($orphelines.Count -gt 0) {
        Write-Etat "INCOHÉRENCE : l'audit teste des clés qu'aucun tweak ne pose : $($orphelines -join ', ')" -Niveau Echec
    }
}

function Show-InfosMachine {
    $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue).TotalPhysicalMemory / 1GB, 1)
    $portable = $null -ne (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
    $typeDisque = "?"
    try {
        $d = Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop | Get-Disk -ErrorAction Stop
        $typeDisque = "$((Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq $d.Number }).MediaType) ($($d.FriendlyName))"
    }
    catch { }

    Write-Host "  MACHINE" -ForegroundColor White
    Write-Host "    Windows        : $($script:InfosOS.DisplayVersion) - build $($script:BuildOS).$($script:InfosOS.UBR) - $($script:InfosOS.EditionID)" -ForegroundColor Gray
    Write-Host "    Édition        : $(if ($script:EstFamille) { 'Famille -> plusieurs stratégies HKLM y sont ignorées par Windows' } else { 'Pro/Entreprise -> toutes les stratégies sont honorées' })" -ForegroundColor Gray
    Write-Host "    RAM            : $ram Go" -ForegroundColor Gray
    Write-Host "    Disque système : $typeDisque" -ForegroundColor Gray
    Write-Host "    Type de PC     : $(if ($portable) { 'Portable (batterie détectée)' } else { 'Fixe' })" -ForegroundColor Gray
    Write-Host "    NPU / Copilot+ : $(if (Test-NPU) { 'OUI -> Recall et Click to Do sont réellement actifs ici' } else { 'non' })" -ForegroundColor Gray
    Write-Host "    Plan d'alim.   : $(Get-PlanAlimentationActif)" -ForegroundColor Gray
    Write-Host "    PowerShell     : $($PSVersionTable.PSVersion) ($($PSVersionTable.PSEdition))" -ForegroundColor Gray
    Write-Host ""
}

function Menu-Audit {
    Clear-Host
    Write-Host "=== AUDIT : ÉTAT ACTUEL DE LA MACHINE ===" -ForegroundColor White
    Write-Host "  Lecture seule : ce menu ne modifie RIEN." -ForegroundColor DarkGray
    Write-Host "  Il lit l'état réel du système, pas ce que ce script a fait : il voit" -ForegroundColor DarkGray
    Write-Host "  donc aussi les réglages posés par un autre outil ou une stratégie." -ForegroundColor DarkGray
    Write-Host ""

    Show-InfosMachine

    $catalogue = Get-CatalogueAudit
    $applique = 0; $absent = 0; $indetermine = 0
    $categorie = $null

    foreach ($a in $catalogue) {
        if ($a.Cat -ne $categorie) {
            $categorie = $a.Cat
            Write-Host ""
            Write-Host "  $((Get-CatAudit $categorie).ToUpper())" -ForegroundColor White
        }
        # Un test qui plante ne doit pas arrêter l'audit : il devient « indéterminé ».
        $r = $null
        try { $r = & $a.Test } catch { $r = $null }

        switch ($r) {
            $true { Write-Host ("    [OUI] {0}" -f (Get-NomAudit $a.Nom)) -ForegroundColor Green; $applique++ }
            $false { Write-Host ("    [ - ] {0}" -f (Get-NomAudit $a.Nom)) -ForegroundColor DarkGray; $absent++ }
            default { Write-Host ("    [ ? ] {0}  (non applicable ou indéterminable ici)" -f (Get-NomAudit $a.Nom)) -ForegroundColor Yellow; $indetermine++ }
        }
    }

    Write-Host ""
    Write-Host "  ----------------------------------------------------" -ForegroundColor DarkGray
    # Le score se déduit de ce qui vient d'être affiché : les [ ? ] sont hors barème,
    # une machine n'ayant pas à être pénalisée pour un réglage qui ne la concerne pas.
    $base = $applique + $absent
    if ($base -gt 0) {
        $note = [int](100 * $applique / $base)
        $mention = if ($note -ge 80) { "excellent" } elseif ($note -ge 60) { "bon" } elseif ($note -ge 40) { "moyen" } else { "à optimiser" }
        $couleur = if ($note -ge 80) { "Green" } elseif ($note -ge 60) { "Cyan" } elseif ($note -ge 40) { "Yellow" } else { "Red" }
        Write-Host "  SCORE DE SANTÉ : $note/100 ($mention)" -ForegroundColor $couleur
    }
    Write-Host "  $applique appliqué(s), $absent non appliqué(s), $indetermine indéterminé(s) sur $($catalogue.Count) réglages testés." -ForegroundColor Cyan
    Write-Host "  [OUI] = actif. [ - ] = laissé au défaut Windows. [ ? ] = ne s'applique pas à cette machine." -ForegroundColor DarkGray
    Write-Host "  Un [ - ] n'est pas un problème : c'est un choix que tu n'as pas (encore) fait." -ForegroundColor DarkGray

    Read-Host "`nAppuie sur Entrée pour revenir au menu principal"
}

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
            "clic-droit-possession", "photo-classique", "god-mode"
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
            "disable-web-search-start", "thirdparty-telemetrie"
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
            "ntfs-performance", "disable-web-search-start"
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
        Read-Host "`nAppuie sur Entrée pour revenir au menu principal"
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
    Read-Host "`nAppuie sur Entrée pour revenir au menu principal"
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

# ------------------------------------------------------------------------------
# MENU PRINCIPAL (boucle, et non plus récursion)
# ------------------------------------------------------------------------------
function Afficher-Menu-Principal {
    # V3 : chaque sous-menu se rappelait mutuellement -> la pile d'appels grandissait
    # indéfiniment à chaque navigation. Une simple boucle règle le problème.
    while ($true) {
        Clear-Host
        Write-Host "==========================================================" -ForegroundColor Cyan
        Write-Host ("     MADTWEAK v$($script:Version) : " + (T 'c.titre') + "   ") -ForegroundColor Cyan
        Write-Host "==========================================================" -ForegroundColor Cyan
        # Une table plutôt que 16 Write-Host : le libellé vient de la langue courante,
        # et la mise en forme (numéro, crochets, alignement) reste écrite une seule fois.
        $entrees = @(
            @{ N = ' 1'; C = 'White' },   @{ N = ' 2'; C = 'White' },  @{ Sep = $true }
            @{ N = ' 3'; C = 'Yellow' },  @{ N = ' 4'; C = 'Yellow' }
            @{ N = ' 5'; C = 'Yellow' },  @{ N = ' 6'; C = 'Yellow' }
            @{ N = ' 7'; C = 'Yellow' },  @{ N = ' 8'; C = 'Cyan' }
            @{ N = ' 9'; C = 'Cyan' },    @{ N = '10'; C = 'Red' },    @{ Sep = $true }
            @{ N = '11'; C = 'Green' },   @{ N = '12'; C = 'Green' }
            @{ N = '13'; C = 'Yellow' },  @{ N = '14'; C = 'Green' },  @{ Sep = $true }
            @{ N = '15'; C = 'Magenta' }, @{ N = '16'; C = 'Magenta' }
            @{ N = '17'; C = 'Red' }
        )
        foreach ($e in $entrees) {
            if ($e.Sep) {
                Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
                continue
            }
            $i = $e.N.Trim()
            $etiquette = "[" + (T "c.$i") + "]"
            Write-Host ("{0} {1,-22}- {2}" -f $e.N, $etiquette, (T "c.$i`d")) -ForegroundColor $e.C
        }
        Write-Host "==========================================================" -ForegroundColor Cyan
        if ($script:Simulation) {
            Write-Host (T 'c.simu.on') -ForegroundColor Cyan
        }
        else {
            Write-Host (T 'c.simu.off') -ForegroundColor DarkGray
        }
        Write-Host ((T 'c.systeme') + "$($script:InfosOS.DisplayVersion) / build $script:BuildOS / $($script:InfosOS.EditionID)") -ForegroundColor DarkGray

        switch (Read-Host (T 'c.choix')) {
            { $_ -match '^\s*[sS]\s*$' } {
                $script:Simulation = -not $script:Simulation
                $script:SimuCompteur = 0
            }
            "1" { Menu-Profils }
            "2" { Menu-Audit }
            "3" { Menu-Tweaks-Base }
            "4" { Menu-Tweaks-Avances }
            "5" { Menu-Explorateur-Prive }
            "6" { Menu-Materiel-Cpu }
            "7" { Menu-Maj-Securite }
            "8" { Menu-Windows11-Recent }
            "9" { Menu-Visuel }
            "10" { Menu-Signature }
            "11" { Menu-Nettoyage }
            "12" { Menu-Demarrage }
            "13" { Menu-Logiciels-Extra }
            "14" { Menu-Maintenance }
            "15" { Menu-Installation }
            "16" { Menu-Annuler }
            "17" { return }
            default { }
        }
    }
}

# ------------------------------------------------------------------------------
# INTERFACE GRAPHIQUE (WPF)
#
# Ce module n'est qu'une FAÇADE : il ne contient aucun tweak, aucune connaissance
# du registre, aucune règle métier. Il fait trois choses :
#   1. il demande à Get-Inventaire la liste des tweaks pilotables (donc au CODE,
#      jamais à une liste tenue en parallèle) ;
#   2. il coche des cases ;
#   3. il pose les clés cochées dans $script:ProfilActif et rejoue les menus.
#
# Autrement dit : une interface graphique, ici, c'est UN PROFIL QUE TU COMPOSES
# TOI-MÊME. Tout le mécanisme existait déjà pour les profils ; on ne fait que lui
# donner des cases à cocher au lieu d'une liste écrite en dur.
#
# RESPONSIVITÉ : l'application des tweaks tourne sur un FIL D'ARRIÈRE-PLAN
# (Start-ApplyArrierePlan), pas sur le thread de l'interface. La fenêtre ne se fige
# donc jamais, même pendant un point de restauration (30-60 s) ou l'énumération des
# bloatwares. Une première version faisait tout sur le thread de l'interface : elle
# « tournait dans le vide », fenêtre gelée. Le repli synchrone (qui fige) ne sert
# que si le fichier source est illisible -- cas d'un script collé dans une console.
# ------------------------------------------------------------------------------

function Update-InterfaceGui {
    # L'équivalent WPF de DoEvents : on laisse le Dispatcher traiter ce qui est en
    # attente (redessin, log) avant de reprendre. Sans ça, Windows marquerait la
    # fenêtre « ne répond pas » dès le premier tweak un peu long.
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [System.Windows.Threading.DispatcherOperationCallback] { param($f) $f.Continue = $false; return $null },
        $frame) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function Start-ApplyArrierePlan {
    # Exécute l'application des tweaks sur un FIL D'ARRIÈRE-PLAN (runspace), pour
    # que la fenêtre ne se fige JAMAIS -- même pendant un point de restauration
    # (30-60 s) ou l'énumération des bloatwares. Le fil pousse ses messages dans
    # une file thread-safe ; une minuterie sur le thread de l'interface la vide
    # dans le journal et détecte la fin. Le fond d'écran figé, c'était toute
    # l'application qui tournait sur le thread de l'interface : ici, plus rien.
    #
    # Lève si le code source n'est pas lisible (script collé dans une console) :
    # l'appelant retombe alors sur l'exécution directe (qui fige, mais marche).
    param(
        [Parameter(Mandatory)]$Journal,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Cles,
        [bool]$EnSimulation,
        [bool]$PointResto,
        [Parameter(Mandatory)][scriptblock]$OnFini
    )
    $src = $null
    if ($PSCommandPath -and (Test-Path $PSCommandPath)) {
        try { $src = [System.IO.File]::ReadAllText($PSCommandPath) } catch { }
    }
    if (-not $src) { throw "source-indisponible" }
    # On coupe AVANT la section LANCEMENT (l'appel « Initialize-Sauvegarde » en
    # début de ligne) : le fil définit toutes les fonctions sans relancer l'interface.
    $m = [regex]::Match($src, '(?m)^Initialize-Sauvegarde\b')
    if (-not $m.Success) { throw "source-indisponible" }
    $defs = $src.Substring(0, $m.Index)

    $sync = [hashtable]::Synchronized(@{
        File = (New-Object 'System.Collections.Concurrent.ConcurrentQueue[object]')
        Fini = $false; OK = 0; Echec = 0; Simu = 0; Redem = @(); Jouees = @(); Progress = 0
    })

    # Le pilote tourne DANS le fil, après les définitions. Guillemets simples :
    # rien ne s'expanse ici, ces $variables sont résolues côté runspace.
    $pilote = @'
$script:DossierDonnees   = $SeedDossier
$script:DossierCles      = $SeedDossierCles
$script:FichierSauvegarde = $SeedFichierSauvegarde
$script:Sauvegarde       = $SeedSauvegarde
$script:Machine          = $SeedMachine
$script:InfosOS          = $SeedInfosOS
$script:EstFamille       = $SeedEstFamille
$script:BuildOS          = $SeedBuildOS
$script:SauvegardeActive = $true
$script:Simulation       = $SeedSimu
$script:CompteurOK = 0; $script:CompteurEchec = 0; $script:SimuCompteur = 0
$script:ClesJouees = @(); $script:RedemarrageRequis = @()
$script:Sync = $SeedSync
# Toute la sortie du script part désormais dans la file, pas dans une console.
$script:SortieGui = {
    param($m, $n)
    $script:Sync.File.Enqueue(@($n, $m))
    $script:Sync.Progress = $script:ClesJouees.Count
}
try {
    if ($SeedPointResto -and -not $SeedSimu) {
        $script:Sync.File.Enqueue(@('Info', 'Creation du point de restauration (30 a 60 s, la fenetre reste reactive)...'))
        if (-not (New-PointRestauration -Description 'MadTweak (interface)')) {
            $script:Sync.File.Enqueue(@('Avert', 'Point de restauration NON cree : aucun filet de securite.'))
        }
    }
    $script:ProfilActif = $SeedCles
    Invoke-TousLesMenus
}
catch {
    $script:Sync.File.Enqueue(@('Echec', "ERREUR INATTENDUE : $($_.Exception.Message)"))
}
finally {
    $script:ProfilActif = $null
    $script:Sync.OK     = $script:CompteurOK
    $script:Sync.Echec  = $script:CompteurEchec
    $script:Sync.Simu   = $script:SimuCompteur
    $script:Sync.Redem  = @($script:RedemarrageRequis)
    $script:Sync.Jouees = @($script:ClesJouees)
    $script:Sync.Fini   = $true
}
'@

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $ssp = $rs.SessionStateProxy
    # $script:Sauvegarde est partagé PAR RÉFÉRENCE : les sauvegardes écrites par le
    # fil sont visibles du thread principal, donc « Annuler » les connaîtra. Aucun
    # accès concurrent : pendant l'application, le thread principal ne fait que
    # vider la file.
    $ssp.SetVariable('SeedSync', $sync)
    $ssp.SetVariable('SeedDossier', $script:DossierDonnees)
    $ssp.SetVariable('SeedDossierCles', $script:DossierCles)
    $ssp.SetVariable('SeedFichierSauvegarde', $script:FichierSauvegarde)
    $ssp.SetVariable('SeedSauvegarde', $script:Sauvegarde)
    $ssp.SetVariable('SeedMachine', $script:Machine)
    $ssp.SetVariable('SeedInfosOS', $script:InfosOS)
    $ssp.SetVariable('SeedEstFamille', $script:EstFamille)
    $ssp.SetVariable('SeedBuildOS', $script:BuildOS)
    $ssp.SetVariable('SeedCles', [string[]]$Cles)
    $ssp.SetVariable('SeedSimu', $EnSimulation)
    $ssp.SetVariable('SeedPointResto', $PointResto)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $ps.AddScript($defs + "`n" + $pilote) | Out-Null
    $handle = $ps.BeginInvoke()

    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(120)
    $timer.Add_Tick({
        $item = $null
        while ($sync.File.TryDequeue([ref]$item)) {
            $prefixe = switch ($item[0]) {
                'OK' { '  [OK]    ' } 'Echec' { '  [ÉCHEC] ' } 'Avert' { '  [!]     ' }
                'Simu' { '  [SIMU]  ' } 'Titre' { '' } default { '  [..]    ' }
            }
            $Journal.AppendText("$prefixe$($item[1])`r`n")
        }
        $Journal.ScrollToEnd()
        if ($script:GuiProgress -and $Cles.Count -gt 0) {
            $val = [math]::Round(($sync.Progress / $Cles.Count) * 100)
            $script:GuiProgress.Value = [math]::Min(100, [math]::Max(0, $val))
        }
        if ($sync.Fini) {
            $timer.Stop()
            try { $ps.EndInvoke($handle) } catch { }
            $ps.Dispose(); $rs.Dispose()
            & $OnFini $sync
        }
    }.GetNewClosure())
    $timer.Start()
}

function Get-NomOnglet {
    # Les titres de menu sont écrits pour une console en majuscules : ils sont bien
    # trop longs pour un onglet. On les raccourcit ici, et seulement pour l'affichage.
    param([Parameter(Mandatory)][string]$Categorie)
    # Le motif reste FRANÇAIS : c'est le titre du menu console qui sert de clé, et il
    # ne dépend pas de la langue d'affichage. Seul le libellé rendu est traduit.
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
    # Nom d'affichage d'un profil. La CLÉ du profil reste française : elle sert
    # d'identifiant dans tout le code (boutons, Tag, journal). Seul l'affichage change.
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

$script:XamlInterface = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="MadTweak — Configuration système" Height="740" Width="1060"
        WindowStartupLocation="CenterScreen" Background="{DynamicResource WindowBgBrush}"
        WindowState="Maximized">
  <Window.Resources>
    <SolidColorBrush x:Key="WindowBgBrush" Color="#FF1B1B1F"/>
    <SolidColorBrush x:Key="PanelBgBrush" Color="#FF232329"/>
    <SolidColorBrush x:Key="TextPrimaryBrush" Color="#FFD8D8DC"/>
    <SolidColorBrush x:Key="TextMutedBrush" Color="#FF8A8A92"/>
    <SolidColorBrush x:Key="AccentBrush" Color="#FF4FA6E8"/>
    <SolidColorBrush x:Key="BorderBrush" Color="#FF3F3F46"/>
    <SolidColorBrush x:Key="ButtonBgBrush" Color="#FF2D2D33"/>
    <SolidColorBrush x:Key="JournalBgBrush" Color="#FF141417"/>
    <SolidColorBrush x:Key="JournalFgBrush" Color="#FFC8C8CE"/>

    <Style TargetType="TextBlock">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>
    <Style TargetType="CheckBox">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Margin" Value="2,5,2,5"/>
      <!-- Sans template custom, WPF dessine une case BLANCHE système qui jure avec
           le thème sombre (« les carrés blancs »). On la redessine : case sombre,
           bordure thème, coche en couleur d'accent quand cochée. -->
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="CheckBox">
            <StackPanel Orientation="Horizontal" Background="Transparent">
              <Border x:Name="case" Width="18" Height="18" CornerRadius="3"
                      Background="{DynamicResource ButtonBgBrush}"
                      BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1"
                      VerticalAlignment="Center" SnapsToDevicePixels="True">
                <Path x:Name="coche" Stretch="Uniform" Margin="3,4,3,3"
                      Data="M 0,5 L 4,9 L 11,0"
                      Stroke="{DynamicResource AccentBrush}" StrokeThickness="2"
                      StrokeStartLineCap="Round" StrokeEndLineCap="Round"
                      Visibility="Collapsed"/>
              </Border>
              <ContentPresenter Margin="8,0,0,0" VerticalAlignment="Center"/>
            </StackPanel>
            <ControlTemplate.Triggers>
              <Trigger Property="IsChecked" Value="True">
                <Setter TargetName="coche" Property="Visibility" Value="Visible"/>
                <Setter TargetName="case" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="case" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Button">
      <Setter Property="Background" Value="{DynamicResource ButtonBgBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="12,6"/>
      <Setter Property="Margin" Value="0,0,8,0"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
    <!-- Champs de saisie : sans style explicite, WPF les peint en blanc sur blanc
         dès que le thème est sombre. Même remède que pour les cases et les onglets. -->
    <Style TargetType="TextBox">
      <Setter Property="Background" Value="{DynamicResource ButtonBgBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="CaretBrush" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="6,4"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>
    <Style TargetType="PasswordBox">
      <Setter Property="Background" Value="{DynamicResource ButtonBgBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="CaretBrush" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource BorderBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="6,4"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
    </Style>
    <Style TargetType="TabItem">
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <!-- Le template Aero peint l'onglet SÉLECTIONNÉ en blanc. On le redessine :
           onglet actif = fond panneau + trait d'accent dessous ; inactif = bouton. -->
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabItem">
            <Border x:Name="onglet" Background="{DynamicResource ButtonBgBrush}"
                    BorderThickness="0,0,0,2" BorderBrush="Transparent" Margin="0,0,2,0" CornerRadius="3,3,0,0">
              <ContentPresenter ContentSource="Header" Margin="12,6"
                                HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="onglet" Property="Background" Value="{DynamicResource PanelBgBrush}"/>
                <Setter TargetName="onglet" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="onglet" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBox">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Height" Value="26"/>
      <!-- Comme pour les cases, le template Aero dessine un fond BLANC système que
           le Setter Background ne remplace pas. On redessine toute la ComboBox :
           fond sombre, flèche au thème, liste déroulante sombre. -->
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBox">
            <Grid>
              <ToggleButton x:Name="bouton" Focusable="False" ClickMode="Press"
                            IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}">
                <ToggleButton.Template>
                  <ControlTemplate TargetType="ToggleButton">
                    <Border x:Name="bord" Background="{DynamicResource ButtonBgBrush}"
                            BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="3">
                      <Grid>
                        <Grid.ColumnDefinitions>
                          <ColumnDefinition/>
                          <ColumnDefinition Width="22"/>
                        </Grid.ColumnDefinitions>
                        <Path Grid.Column="1" HorizontalAlignment="Center" VerticalAlignment="Center"
                              Data="M 0,0 L 4,4 L 8,0" Stroke="{DynamicResource TextPrimaryBrush}" StrokeThickness="1.5"/>
                      </Grid>
                    </Border>
                    <ControlTemplate.Triggers>
                      <Trigger Property="IsMouseOver" Value="True">
                        <Setter TargetName="bord" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
                      </Trigger>
                    </ControlTemplate.Triggers>
                  </ControlTemplate>
                </ToggleButton.Template>
              </ToggleButton>
              <ContentPresenter x:Name="contenu" Content="{TemplateBinding SelectionBoxItem}"
                                ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}"
                                Margin="8,0,26,0" VerticalAlignment="Center" IsHitTestVisible="False"
                                TextElement.Foreground="{DynamicResource TextPrimaryBrush}"/>
              <Popup x:Name="liste" IsOpen="{TemplateBinding IsDropDownOpen}" Placement="Bottom"
                     AllowsTransparency="True" Focusable="False" PopupAnimation="Slide">
                <Border Background="{DynamicResource PanelBgBrush}" BorderBrush="{DynamicResource BorderBrush}"
                        BorderThickness="1" CornerRadius="3" MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                  <ScrollViewer MaxHeight="320">
                    <ItemsPresenter/>
                  </ScrollViewer>
                </Border>
              </Popup>
            </Grid>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="ComboBoxItem">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Padding" Value="8,5"/>
      <!-- On REMPLACE le template Aero : sinon son survol bleu clair par défaut
           écrase notre couleur et rend l'item illisible (texte clair sur fond
           clair). Avec ce template, le fond de l'item est à nous : sombre au
           repos, accent + texte blanc au survol/sélection. -->
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="ComboBoxItem">
            <Border x:Name="bordure" Background="{DynamicResource PanelBgBrush}"
                    Padding="{TemplateBinding Padding}" SnapsToDevicePixels="True">
              <ContentPresenter x:Name="contenu" HorizontalAlignment="Left" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="bordure" Property="Background" Value="{DynamicResource AccentBrush}"/>
                <Setter Property="Foreground" Value="#FFFFFFFF"/>
              </Trigger>
              <Trigger Property="IsSelected" Value="True">
                <Setter TargetName="bordure" Property="Background" Value="{DynamicResource AccentBrush}"/>
                <Setter Property="Foreground" Value="#FFFFFFFF"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <!-- MENUS. Comme pour les cases et les listes, le template par défaut de WPF
         dessine un fond BLANC système : on le remplace entièrement, sinon les menus
         seraient illisibles sur un thème sombre (le fameux « carré blanc »).
         Deux styles : « MenuTop » pour les entrées de la barre (bouton + popup),
         et le style implicite pour les lignes du menu déroulant. -->
    <Style x:Key="MenuTop" TargetType="MenuItem">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="MenuItem">
            <Border x:Name="bord" Background="{DynamicResource ButtonBgBrush}"
                    BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1"
                    CornerRadius="3" Padding="12,6" Margin="0,0,8,0">
              <Grid>
                <ContentPresenter ContentSource="Header" VerticalAlignment="Center"/>
                <Popup x:Name="popup" IsOpen="{TemplateBinding IsSubmenuOpen}" Placement="Bottom"
                       AllowsTransparency="True" Focusable="False" PopupAnimation="Fade" StaysOpen="False">
                  <Border Background="{DynamicResource PanelBgBrush}" BorderBrush="{DynamicResource BorderBrush}"
                          BorderThickness="1" CornerRadius="3" Margin="0,3,0,0" MinWidth="210">
                    <StackPanel IsItemsHost="True" KeyboardNavigation.DirectionalNavigation="Cycle"/>
                  </Border>
                </Popup>
              </Grid>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="bord" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
              <Trigger Property="IsSubmenuOpen" Value="True">
                <Setter TargetName="bord" Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="MenuItem">
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="FontFamily" Value="Segoe UI"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="MenuItem">
            <Border x:Name="ligne" Background="Transparent" Padding="14,7">
              <ContentPresenter ContentSource="Header" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsHighlighted" Value="True">
                <Setter TargetName="ligne" Property="Background" Value="{DynamicResource ButtonBgBrush}"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Menu">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
    </Style>
    <Style TargetType="Separator">
      <Setter Property="Height" Value="1"/>
      <Setter Property="Margin" Value="8,4,8,4"/>
      <Setter Property="Background" Value="{DynamicResource BorderBrush}"/>
    </Style>

    <!-- Info-bulles assorties au thème sombre (la bulle système jaune jurerait). -->
    <Style TargetType="ToolTip">
      <Setter Property="Background" Value="{DynamicResource PanelBgBrush}"/>
      <Setter Property="Foreground" Value="{DynamicResource TextPrimaryBrush}"/>
      <Setter Property="BorderBrush" Value="{DynamicResource AccentBrush}"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="9,6"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="MaxWidth" Value="320"/>
      <Setter Property="HasDropShadow" Value="True"/>
    </Style>
  </Window.Resources>

  <Grid x:Name="GridPrincipal" Margin="12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="190"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- En-tête -->
    <Grid Grid.Row="0" Margin="0,0,0,10">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel Grid.Column="0">
        <StackPanel Orientation="Horizontal">
          <TextBlock x:Name="TxtTitre" Text="MADTWEAK" FontSize="21" FontWeight="SemiBold" Foreground="{DynamicResource AccentBrush}"/>
          <Border x:Name="BorderScore" Background="{DynamicResource ButtonBgBrush}" BorderBrush="{DynamicResource BorderBrush}"
                  BorderThickness="1" CornerRadius="4" Padding="9,2" Margin="14,0,0,0" VerticalAlignment="Center"
                  Visibility="Collapsed"
                  ToolTip="{{entete.score.info}}">
            <TextBlock x:Name="TxtScore" FontSize="13" FontWeight="SemiBold"/>
          </Border>
        </StackPanel>
        <TextBlock x:Name="TxtSysteme" FontSize="11" Foreground="{DynamicResource TextMutedBrush}" Margin="0,3,0,0"/>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
        <TextBlock Text="{{entete.fond}}" VerticalAlignment="Center" Margin="0,0,5,0" Foreground="{DynamicResource TextMutedBrush}"/>
        <ComboBox x:Name="ComboFond" Width="160" Height="26" VerticalContentAlignment="Center" Margin="0,0,16,0"
                  ToolTip="{{entete.fond.info}}"/>
        <TextBlock Text="{{entete.accent}}" VerticalAlignment="Center" Margin="0,0,5,0" Foreground="{DynamicResource TextMutedBrush}"/>
        <ComboBox x:Name="ComboAccent" Width="170" Height="26" VerticalContentAlignment="Center" Margin="0,0,16,0"
                  ToolTip="{{entete.accent.info}}"/>
        <TextBlock Text="{{entete.theme}}" VerticalAlignment="Center" Margin="0,0,5,0" Foreground="{DynamicResource TextMutedBrush}"/>
        <ComboBox x:Name="ComboTheme" Width="160" Height="26" VerticalContentAlignment="Center"
                  ToolTip="{{entete.theme.info}}"/>
        <TextBlock Text="{{entete.langue}}" VerticalAlignment="Center" Margin="16,0,5,0" Foreground="{DynamicResource TextMutedBrush}"/>
        <ComboBox x:Name="ComboLangue" Width="118" Height="26" VerticalContentAlignment="Center"
                  ToolTip="{{entete.langue.info}}"/>
        <StackPanel x:Name="PanelEcran" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="{{entete.ecran}}" VerticalAlignment="Center" Margin="16,0,5,0" Foreground="{DynamicResource TextMutedBrush}"/>
          <Slider x:Name="SliderEcran" Width="110" Minimum="10" Maximum="100" TickFrequency="5" IsSnapToTickEnabled="True" VerticalAlignment="Center"
                  ToolTip="{{entete.ecran.info}}"/>
          <TextBlock x:Name="TxtEcran" Width="38" VerticalAlignment="Center" Margin="6,0,0,0" Foreground="{DynamicResource TextMutedBrush}"/>
        </StackPanel>
      </StackPanel>
    </Grid>

    <!-- Profils -->
    <Border x:Name="BorderProfils" Grid.Row="1" Background="{DynamicResource PanelBgBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1"
            CornerRadius="4" Padding="10" Margin="0,0,0,10">
      <StackPanel>
        <TextBlock Text="{{profils.entete}}"
                   FontSize="11" Foreground="{DynamicResource TextMutedBrush}" Margin="0,0,0,8"/>
        <StackPanel x:Name="PanelProfils"/>
      </StackPanel>
    </Border>

    <!-- Onglets de tweaks -->
    <TabControl x:Name="TabsCategories" Grid.Row="2" Background="{DynamicResource PanelBgBrush}" BorderBrush="{DynamicResource BorderBrush}"/>

    <!-- Actions -->
    <StackPanel Grid.Row="3" Margin="0,10,0,10">
      <!-- Barre d'outils. Les actions sont REGROUPÉES par intention dans des menus :
           15 boutons alignés obligeaient à lire toute la barre pour trouver le bon.
           Seuls restent visibles le filtre (usage constant) et « Gamer ROG ». -->
      <WrapPanel Margin="0,0,0,6">
        <TextBlock Text="{{barre.filtrer}}" VerticalAlignment="Center" Foreground="{DynamicResource TextMutedBrush}"/>
        <TextBox x:Name="TxtRecherche" Width="180" Height="28" VerticalContentAlignment="Center"
                 Background="{DynamicResource ButtonBgBrush}" Foreground="{DynamicResource TextPrimaryBrush}"
                 CaretBrush="{DynamicResource TextPrimaryBrush}"
                 BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" Padding="6,0" Margin="0,0,14,0"
                 ToolTip="{{barre.filtrer.info}}"/>

        <Menu Background="Transparent" VerticalAlignment="Center">
          <MenuItem Header="{{menu.analyser}}" Style="{StaticResource MenuTop}"
                    ToolTip="{{menu.analyser.info}}">
            <MenuItem x:Name="BtnEtatActuel" Header="{{act.etat}}"
                      ToolTip="{{act.etat.info}}"/>
            <MenuItem x:Name="BtnDerive" Header="{{act.derive}}"
                      ToolTip="{{act.derive.info}}"/>
            <Separator/>
            <MenuItem x:Name="BtnDemarrage" Header="{{act.demarrage}}"
                      ToolTip="{{act.demarrage.info}}"/>
            <MenuItem x:Name="BtnDisque" Header="{{act.disque}}"
                      ToolTip="{{act.disque.info}}"/>
            <MenuItem x:Name="BtnIndesirables" Header="{{act.indesirables}}"
                      ToolTip="{{act.indesirables.info}}"/>
            <Separator/>
            <MenuItem x:Name="BtnDiagnostic" Header="{{act.diagnostic}}"
                      ToolTip="{{act.diagnostic.info}}"/>
            <MenuItem x:Name="BtnRapport" Header="{{act.rapport}}"
                      ToolTip="{{act.rapport.info}}"/>
          </MenuItem>

          <MenuItem Header="{{menu.annuler}}" Style="{StaticResource MenuTop}"
                    ToolTip="{{menu.annuler.info}}">
            <MenuItem x:Name="BtnRestaurer" Header="{{act.restaurer}}"
                      ToolTip="{{act.restaurer.info}}"/>
            <MenuItem x:Name="BtnRestaurerSelectif" Header="{{act.restaurer.sel}}"
                      ToolTip="{{act.restaurer.sel.info}}"/>
            <Separator/>
            <MenuItem x:Name="BtnPointsResto" Header="{{act.points}}"
                      ToolTip="{{act.points.info}}"/>
          </MenuItem>

          <MenuItem Header="{{menu.config}}" Style="{StaticResource MenuTop}"
                    ToolTip="{{menu.config.info}}">
            <MenuItem x:Name="BtnEnregistrerProfil" Header="{{act.profil.enr}}"
                      ToolTip="{{act.profil.enr.info}}"/>
            <Separator/>
            <MenuItem x:Name="BtnExportConfig" Header="{{act.export}}"
                      ToolTip="{{act.export.info}}"/>
            <MenuItem x:Name="BtnImportConfig" Header="{{act.import}}"
                      ToolTip="{{act.import.info}}"/>
            <Separator/>
            <MenuItem x:Name="BtnMaintenance" Header="{{act.maintenance}}"
                      ToolTip="{{act.maintenance.info}}"/>
          </MenuItem>

          <MenuItem Header="{{menu.affichage}}" Style="{StaticResource MenuTop}"
                    ToolTip="{{menu.affichage.info}}">
            <MenuItem x:Name="BtnToggleProfils" Header="{{act.profils.cacher}}"
                      ToolTip="{{act.profils.info}}"/>
            <MenuItem x:Name="BtnToggleJournal" Header="{{act.journal.cacher}}"
                      ToolTip="{{act.journal.info}}"/>
          </MenuItem>
        </Menu>

        <Button x:Name="BtnGamerRog" Content="{{act.gamer}}" Background="#FF5A1220" BorderBrush="#FF8A1E33"
                FontWeight="SemiBold" Margin="8,0,0,0" VerticalAlignment="Center"
                ToolTip="{{act.gamer.info}}"/>
      </WrapPanel>
      <Grid>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Left">
          <Button x:Name="BtnToutCocher" Content="{{act.cocher}}"
                  ToolTip="{{act.cocher.info}}"/>
          <Button x:Name="BtnToutDecocher" Content="{{act.decocher}}"
                  ToolTip="{{act.decocher.info}}"/>
          <CheckBox x:Name="ChkPointRestauration" Content="{{act.pointresto}}"
                    IsChecked="True" VerticalAlignment="Center" Margin="12,0,0,0"
                    ToolTip="{{act.pointresto.info}}"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
          <TextBlock x:Name="TxtSelection" VerticalAlignment="Center" Margin="0,0,14,0"
                     FontSize="12" Foreground="{DynamicResource TextMutedBrush}"/>
          <Button x:Name="BtnSimuler" Content="{{act.simuler}}" Background="#FF1F4A63" BorderBrush="#FF2E6F94"
                  ToolTip="{{act.simuler.info}}"/>
          <Button x:Name="BtnAppliquer" Content="{{act.appliquer}}" Background="#FF16603A" BorderBrush="#FF1F8A52"
                  FontWeight="SemiBold" Margin="0,0,8,0"
                  ToolTip="{{act.appliquer.info}}"/>
          <Button x:Name="BtnRedemarrer" Content="{{act.redemarrer}}" Background="#FF7D2323" BorderBrush="#FFA32E2E"
                  FontWeight="SemiBold" Margin="0"
                  ToolTip="{{act.redemarrer.info}}"/>
        </StackPanel>
      </Grid>
    </StackPanel>

    <!-- Journal -->
    <Border x:Name="BorderJournal" Grid.Row="4" Background="{DynamicResource JournalBgBrush}" BorderBrush="{DynamicResource BorderBrush}" BorderThickness="1" CornerRadius="4">
      <TextBox x:Name="TxtJournal" IsReadOnly="True" Background="Transparent" BorderThickness="0"
               Foreground="{DynamicResource JournalFgBrush}" FontFamily="Consolas" FontSize="12"
               VerticalScrollBarVisibility="Auto" TextWrapping="NoWrap" Padding="8"/>
    </Border>

    <StackPanel Grid.Row="5" Margin="0,8,0,0">
      <ProgressBar x:Name="BarreProgression" Height="6" Minimum="0" Maximum="100" Value="0"
                   Foreground="{DynamicResource AccentBrush}" Background="{DynamicResource ButtonBgBrush}"
                   BorderThickness="0" Visibility="Collapsed" Margin="0,0,0,5"/>
      <TextBlock x:Name="TxtEtat" FontSize="11" Foreground="{DynamicResource TextMutedBrush}"/>
    </StackPanel>
  </Grid>
</Window>
'@

function Invoke-BilanFinal {
    param($sync, [bool]$EnSimulation, [string[]]$Cles)
    # Filet habituel : une clé cochée qu'aucun tweak n'a atteinte = son menu
    # manque à Invoke-TousLesMenus.
    $jamais = @($Cles | Where-Object { $_ -notin $sync.Jouees })
    if ($jamais.Count -gt 0) {
        $script:JournalGui.AppendText("ANOMALIE INTERNE : $($jamais.Count) tweak(s) jamais atteint(s) : $($jamais -join ', ')`r`n")
        $script:JournalGui.AppendText("Leur menu n'est pas appelé par Invoke-TousLesMenus. C'est un défaut du script.`r`n")
    }
    $script:JournalGui.AppendText(("-" * 70) + "`r`n")
    if ($EnSimulation) {
        $bilan = "SIMULATION terminée : $($sync.Simu) modification(s) auraient été faites. Rien n'a été écrit."
    }
    else {
        $bilan = "Terminé : $($sync.OK) réussi(s), $($sync.Echec) échec(s)."
        if ($sync.Echec -gt 0) {
            $bilan += " Un échec est souvent un tweak qui REFUSE de s'appliquer parce qu'il serait nuisible ici."
        }
        # Mémorise les clés réellement appliquées : c'est ce qui permet ensuite de
        # détecter la « dérive » (tweaks revenus au défaut après une MAJ Windows).
        try { Save-ClesAppliquees @($sync.Jouees) } catch { }
    }
    $script:JournalGui.AppendText("$bilan`r`n")
    # Les redémarrages détectés dans le fil remontent dans l'état principal, pour
    # qu'Invoke-RedemarrageFinal les propose à la fermeture de l'interface.
    if (@($sync.Redem).Count -gt 0) {
        $script:JournalGui.AppendText("`r`n$(@($sync.Redem).Count) tweak(s) n'auront d'effet qu'APRÈS un redémarrage :`r`n")
        foreach ($t in $sync.Redem) {
            $script:JournalGui.AppendText("   - $t`r`n")
            if ($t -notin $script:RedemarrageRequis) { $script:RedemarrageRequis += $t }
        }
    }
    $script:JournalGui.ScrollToEnd()
    $script:GuiTxtEtat.Text = $bilan
    $script:GuiOccupe = $false
    # La barre atteint 100 %, puis disparaît : le travail est fini.
    if ($script:GuiProgress) {
        $script:GuiProgress.Value = 100
        $script:GuiProgress.Visibility = 'Collapsed'
    }
    $script:GuiFenetre.FindName("BtnAppliquer").IsEnabled = $true
    $script:GuiFenetre.FindName("BtnSimuler").IsEnabled = $true
    $script:GuiFenetre.FindName("BtnRedemarrer").IsEnabled = $true
}

function Invoke-LancerGui {
    param([bool]$EnSimulation)
    $cles = @($script:GuiCases.Keys | Where-Object { $script:GuiCases[$_].IsChecked })
    if ($cles.Count -eq 0) {
        $script:JournalGui.AppendText("`r`nAucun tweak coché : rien à faire.`r`n")
        $script:JournalGui.ScrollToEnd()
        return
    }

    $script:GuiOccupe = $true
    $script:GuiFenetre.FindName("BtnAppliquer").IsEnabled = $false
    $script:GuiFenetre.FindName("BtnSimuler").IsEnabled = $false
    $script:GuiFenetre.FindName("BtnRedemarrer").IsEnabled = $false
    # Barre de progression : repartie de zéro et rendue visible pour ce lot.
    if ($script:GuiProgress) {
        $script:GuiProgress.Value = 0
        $script:GuiProgress.Visibility = 'Visible'
    }
    $script:GuiTxtEtat.Text = if ($EnSimulation) { "Simulation en arrière-plan — la fenêtre reste réactive." } else { "Application en arrière-plan — la fenêtre reste réactive, laisse-la travailler." }
    $script:JournalGui.AppendText("`r`n" + ("=" * 70) + "`r`n")
    $script:JournalGui.AppendText($(if ($EnSimulation) {
        "SIMULATION de $($cles.Count) tweak(s) — RIEN ne sera écrit sur la machine.`r`n" }
        else { "APPLICATION de $($cles.Count) tweak(s).`r`n" }))
    $script:JournalGui.AppendText(("=" * 70) + "`r`n")

    $pointResto = (-not $EnSimulation) -and [bool]$script:GuiFenetre.FindName("ChkPointRestauration").IsChecked

    # À la fin du fil (sur le thread de l'interface), on affiche le bilan.
    $onFini = {
        param($sync)
        Invoke-BilanFinal $sync $EnSimulation $cles
    }.GetNewClosure()

    try {
        Start-ApplyArrierePlan -Journal $script:JournalGui -Cles $cles -EnSimulation $EnSimulation -PointResto $pointResto -OnFini $onFini
    }
    catch {
        # Repli : aucun fil possible (script sans fichier source). On exécute en
        # direct -- la fenêtre se fige, mais le travail se fait. Cas très rare :
        # Lancer.bat passe toujours par -File, donc le fichier existe.
        $script:JournalGui.AppendText("(Arrière-plan indisponible : exécution directe, la fenêtre peut se figer.)`r`n")
        Update-InterfaceGui
        $script:Simulation = $EnSimulation
        $script:CompteurOK = 0; $script:CompteurEchec = 0
        $script:SimuCompteur = 0; $script:ClesJouees = @()
        $redAvant = @($script:RedemarrageRequis)
        try {
            if ($pointResto) { New-PointRestauration -Description "MadTweak (interface)" | Out-Null }
            $script:ProfilActif = $cles
            Invoke-TousLesMenus
        }
        catch { $script:JournalGui.AppendText("ERREUR : $($_.Exception.Message)`r`n") }
        finally { $script:ProfilActif = $null; $script:Simulation = $false }
        $faux = @{
            OK = $script:CompteurOK; Echec = $script:CompteurEchec; Simu = $script:SimuCompteur
            Jouees = @($script:ClesJouees); Redem = @($script:RedemarrageRequis | Where-Object { $_ -notin $redAvant })
        }
        Invoke-BilanFinal $faux $EnSimulation $cles
    }
}

$script:Themes = [ordered]@{
    "Sombre Moderne" = @{
        WindowBg      = "#FF1B1B1F"
        PanelBg       = "#FF232329"
        TextPrimary   = "#FFD8D8DC"
        TextMuted     = "#FF8A8A92"
        Accent        = "#FF4FA6E8"
        Border        = "#FF3F3F46"
        ButtonBg      = "#FF2D2D33"
        JournalBg     = "#FF141417"
        JournalFg     = "#FFC8C8CE"
    }
    "Abysse" = @{
        WindowBg      = "#FF0A0F1D"
        PanelBg       = "#FF11192E"
        TextPrimary   = "#FFE0E6ED"
        TextMuted     = "#FF6B7C96"
        Accent        = "#FF00D2FF"
        Border        = "#FF233554"
        ButtonBg      = "#FF1B2A4A"
        JournalBg     = "#FF070B14"
        JournalFg     = "#FF90A4AE"
    }
    "Dracula" = @{
        WindowBg      = "#FF282A36"
        PanelBg       = "#FF1E1F29"
        TextPrimary   = "#FFF8F8F2"
        TextMuted     = "#FF6272A4"
        Accent        = "#FFBD93F9"
        Border        = "#FF44475A"
        ButtonBg      = "#FF343746"
        JournalBg     = "#FF1A1A24"
        JournalFg     = "#FF50FA7B"
    }
    "Foret Emeraude" = @{
        WindowBg      = "#FF0F1715"
        PanelBg       = "#FF16221F"
        TextPrimary   = "#FFE2E8F0"
        TextMuted     = "#FF64748B"
        Accent        = "#FF10B981"
        Border        = "#FF2D3F3A"
        ButtonBg      = "#FF1E2E2A"
        JournalBg     = "#FF0A0F0E"
        JournalFg     = "#FF34D399"
    }
    "Cyberpunk" = @{
        WindowBg      = "#FF0D0211"
        PanelBg       = "#FF1A0524"
        TextPrimary   = "#FFFFF5FA"
        TextMuted     = "#FFA131B6"
        Accent        = "#FFFF007F"
        Border        = "#FF520775"
        ButtonBg      = "#FF330647"
        JournalBg     = "#FF050007"
        JournalFg     = "#FF39FF14"
    }
    "Clair Elegant" = @{
        WindowBg      = "#FFF0F2F5"
        PanelBg       = "#FFFFFFFF"
        TextPrimary   = "#FF1A1D20"
        TextMuted     = "#FF70757A"
        Accent        = "#FF0066CC"
        Border        = "#FFD1D5DB"
        ButtonBg      = "#FFE5E7EB"
        JournalBg     = "#FFF9FAFB"
        JournalFg     = "#FF374151"
    }
}

function Set-Theme {
    param(
        [Parameter(Mandatory)]
        $Fenetre,
        [Parameter(Mandatory)]
        [string]$NomTheme
    )
    if (-not $script:Themes.Contains($NomTheme)) { return }
    $t = $script:Themes[$NomTheme]
    
    $keys = @("WindowBg", "PanelBg", "TextPrimary", "TextMuted", "Accent", "Border", "ButtonBg", "JournalBg", "JournalFg")
    foreach ($k in $keys) {
        $brushKey = $k + "Brush"
        # Piège vérifié : « New-Object SolidColorBrush -ArgumentList $couleur » avec
        # une couleur BOXÉE (ce que renvoie ConvertFromString) crée un pinceau
        # malformé. Quand WPF ré-évalue les DynamicResource, il échoue avec
        # « #XXXXXX n'est pas une valeur valide pour Background » -- ce qui faisait
        # planter TOUTE l'interface au démarrage. La parade : caster explicitement
        # en [Color], construire via ::new(), et geler le pinceau.
        $color = [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($t[$k])
        $brush = [System.Windows.Media.SolidColorBrush]::new($color)
        $brush.Freeze()
        $Fenetre.Resources[$brushKey] = $brush
    }
    
    if ($script:DossierDonnees) {
        try {
            [System.IO.File]::WriteAllText((Join-Path $script:DossierDonnees "theme.txt"), $NomTheme, [System.Text.Encoding]::UTF8)
        } catch {}
    }
}

function Add-LigneComboClavier {
    # Ajoute au panneau une étiquette + une liste déroulante thémée, et la retourne.
    # Le style de ComboBox (template qui tue les « carrés blancs ») est assigné
    # explicitement, comme pour les cases : le style implicite ne suffit pas toujours
    # sur un contrôle créé par code.
    param($Panneau, $Style, [string]$Etiquette, [object[]]$Elements, [int]$IndexSel = 0)
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = $Etiquette
    $lbl.Margin = "0,10,0,3"
    $lbl.FontWeight = "SemiBold"
    $Panneau.Children.Add($lbl) | Out-Null
    $cb = New-Object System.Windows.Controls.ComboBox
    if ($Style) { $cb.Style = $Style }
    $cb.Width = 260
    $cb.HorizontalAlignment = "Left"
    foreach ($el in $Elements) { $cb.Items.Add($el) | Out-Null }
    if ($cb.Items.Count -gt 0) { $cb.SelectedIndex = [Math]::Min($IndexSel, $cb.Items.Count - 1) }
    $Panneau.Children.Add($cb) | Out-Null
    return $cb
}

function Add-LigneSliderClavier {
    # Ajoute une étiquette + un curseur 0-100 %. L'étiquette affiche la valeur en direct.
    # Pas de closure : la référence de l'étiquette et le libellé voyagent dans le Tag
    # du curseur (GetNewClosure casserait la portée $script: -- à proscrire ici).
    param($Panneau, [string]$Etiquette, [int]$Valeur)
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Margin = "0,10,0,3"
    $lbl.FontWeight = "SemiBold"
    $lbl.Text = "$Etiquette : $([int]$Valeur) %"
    $Panneau.Children.Add($lbl) | Out-Null
    $sl = New-Object System.Windows.Controls.Slider
    $sl.Minimum = 0; $sl.Maximum = 100; $sl.Width = 260; $sl.HorizontalAlignment = "Left"
    $sl.TickFrequency = 5; $sl.IsSnapToTickEnabled = $true; $sl.Value = $Valeur
    $sl.Tag = @{ Label = $lbl; Nom = $Etiquette }
    $sl.Add_ValueChanged({ $this.Tag.Label.Text = "$($this.Tag.Nom) : $([int]$this.Value) %" }) | Out-Null
    $Panneau.Children.Add($sl) | Out-Null
    return $sl
}

function Add-PageMateriel {
    # Ajoute l'onglet « Matériel » : le mode d'alimentation Windows (toujours) et, si
    # un clavier ASUS ROG compatible répond, les réglages RGB. L'onglet s'adapte au
    # matériel : la section clavier n'apparaît que si le clavier est là.
    # Suppose $script:GuiTabs déjà défini par Show-Gui.
    param($Fenetre)

    $styleCombo = $null
    try { $styleCombo = $Fenetre.FindResource([System.Windows.Controls.ComboBox]) } catch { }

    $pile = New-Object System.Windows.Controls.StackPanel
    $pile.Margin = "16"

    # --- Section CAPTEURS (en direct) : GPU (nvidia-smi) + ventilateurs (ACPI ASUS) ---
    $aGpu = [bool](Get-Command nvidia-smi -ErrorAction SilentlyContinue) -or (Test-Path "$env:SystemRoot\System32\nvidia-smi.exe")
    if ($aGpu -or (Test-ClavierAura)) {
        $tCap = New-Object System.Windows.Controls.TextBlock
        $tCap.Text = "Capteurs (en direct)"
        $tCap.FontWeight = "Bold"; $tCap.FontSize = 15; $tCap.Margin = "0,0,0,4"
        $pile.Children.Add($tCap) | Out-Null

        $script:MatLblGpu = New-Object System.Windows.Controls.TextBlock
        $script:MatLblGpu.FontSize = 13; $script:MatLblGpu.Margin = "0,2,0,2"
        $pile.Children.Add($script:MatLblGpu) | Out-Null
        $script:MatLblFans = New-Object System.Windows.Controls.TextBlock
        $script:MatLblFans.FontSize = 13; $script:MatLblFans.Margin = "0,2,0,2"
        $pile.Children.Add($script:MatLblFans) | Out-Null

        $majCapteurs = {
            $c = Get-CapteursMateriel
            $script:MatLblGpu.Text = if ($null -ne $c.GpuTemp) { "GPU : $($c.GpuTemp) °C   ·   charge $($c.GpuLoad) %" } else { "GPU : —" }
            $fc = if ($c.FanCpu) { "$($c.FanCpu) tr/min" } else { "—" }
            $fg = if ($c.FanGpu) { "$($c.FanGpu) tr/min" } else { "—" }
            $suffixe = if (-not $c.FanCpu) { "   (ventilos lisibles seulement en admin, via Lancer.bat)" } else { "" }
            $script:MatLblFans.Text = "Ventilateurs : CPU $fc   ·   GPU $fg$suffixe"
        }
        & $majCapteurs
        $script:GuiTimerCapteurs = New-Object System.Windows.Threading.DispatcherTimer
        $script:GuiTimerCapteurs.Interval = [TimeSpan]::FromMilliseconds(2500)
        $script:GuiTimerCapteurs.Add_Tick($majCapteurs) | Out-Null
        $script:GuiTimerCapteurs.Start()
        # La minuterie doit mourir avec la fenêtre, sinon elle tourne dans le vide.
        $Fenetre.Add_Closed({ if ($script:GuiTimerCapteurs) { $script:GuiTimerCapteurs.Stop() } }) | Out-Null

        $noteCap = New-Object System.Windows.Controls.TextBlock
        $noteCap.Text = "Température des cœurs CPU non affichée : Windows ne l'expose pas sans pilote dédié (HWiNFO, G-Helper). Le GPU, lui, est lu directement."
        $noteCap.TextWrapping = "Wrap"; $noteCap.FontSize = 11; $noteCap.Margin = "0,4,0,0"
        $noteCap.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextMutedBrush")
        $pile.Children.Add($noteCap) | Out-Null

        $sepC = New-Object System.Windows.Controls.Border
        $sepC.Height = 1; $sepC.Margin = "0,14,0,14"
        $sepC.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BorderBrush")
        $pile.Children.Add($sepC) | Out-Null
    }

    # --- Section ALIMENTATION (toujours présente) ---
    $tAlim = New-Object System.Windows.Controls.TextBlock
    $tAlim.Text = "Mode d'alimentation Windows"
    $tAlim.FontWeight = "Bold"; $tAlim.FontSize = 15; $tAlim.Margin = "0,0,0,4"
    $pile.Children.Add($tAlim) | Out-Null

    $sAlim = New-Object System.Windows.Controls.TextBlock
    $sAlim.Text = "Agit sur le boost et l'EPP du CPU côté Windows. Ce n'est PAS le Turbo ASUS (ventilateurs + TDP) : celui-ci n'est pas pilotable depuis un script — mesuré, la fréquence CPU sous charge est identique en Silencieux et Turbo. Pour un vrai contrôle des ventilateurs, utilise G-Helper."
    $sAlim.TextWrapping = "Wrap"; $sAlim.FontSize = 11; $sAlim.Margin = "0,0,0,6"
    $sAlim.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextMutedBrush")
    $pile.Children.Add($sAlim) | Out-Null

    $script:MatComboAlim = Add-LigneComboClavier $pile $styleCombo "Profil" @($script:ModesAlimentation.Keys) 1
    $script:MatComboAlim.ToolTip = "Mode d'alimentation Windows : agit sur le boost et l'EPP du CPU. Ce n'est PAS le Turbo ASUS (ventilateurs), qui n'est pas pilotable depuis un script."
    $script:MatComboAlim.Add_SelectionChanged({
        $m = [string]$script:MatComboAlim.SelectedItem
        if (-not $m) { return }
        if (Set-ModeAlimentation -Mode $m) { $script:JournalGui.AppendText("Mode d'alimentation Windows : « $m ».`r`n") }
        else { $script:JournalGui.AppendText("Mode d'alimentation : échec (« $m »).`r`n") }
        $script:JournalGui.ScrollToEnd()
    }) | Out-Null

    # --- Section CLAVIER RGB (seulement si le matériel répond) ---
    if (Test-ClavierAura) {
        $sep = New-Object System.Windows.Controls.Border
        $sep.Height = 1; $sep.Margin = "0,18,0,14"
        $sep.SetResourceReference([System.Windows.Controls.Border]::BackgroundProperty, "BorderBrush")
        $pile.Children.Add($sep) | Out-Null

        $tKb = New-Object System.Windows.Controls.TextBlock
        $tKb.Text = "Clavier RGB ASUS ROG"
        $tKb.FontWeight = "Bold"; $tKb.FontSize = 15; $tKb.Margin = "0,0,0,4"
        $pile.Children.Add($tKb) | Out-Null

        $sKb = New-Object System.Windows.Controls.TextBlock
        $sKb.Text = "Effet, couleur et luminosité s'appliquent au bouton ci-dessous. La couleur suit aussi l'accent Windows du haut. La luminosité atténue la couleur envoyée ; le niveau matériel du rétroéclairage se règle avec Fn + F3/F4."
        $sKb.TextWrapping = "Wrap"; $sKb.FontSize = 11; $sKb.Margin = "0,0,0,6"
        $sKb.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextMutedBrush")
        $pile.Children.Add($sKb) | Out-Null

        $script:KbComboEffet   = Add-LigneComboClavier $pile $styleCombo "Effet"                   @($script:EffetsClavier.Keys) 0
        $script:KbComboEffet.ToolTip = "Effet du rétroéclairage : statique, respiration, stroboscope ou arc-en-ciel."
        $script:KbComboCouleur = Add-LigneComboClavier $pile $styleCombo "Couleur"                 @($script:AccentsWindows.Keys) 0
        $script:KbComboCouleur.ToolTip = "Couleur du clavier (7 presets ROG). Ignorée par l'effet arc-en-ciel."
        $script:KbComboVitesse = Add-LigneComboClavier $pile $styleCombo "Vitesse (effets animés)" @($script:VitessesClavier.Keys) 1
        $script:KbComboVitesse.ToolTip = "Vitesse des effets animés (respiration, arc-en-ciel...)."
        $script:KbSliderLum    = Add-LigneSliderClavier $pile "Luminosité du clavier" $script:LuminositeClavier
        $script:KbSliderLum.ToolTip = "Luminosité du clavier (0-100 %), obtenue en atténuant la couleur envoyée. Le niveau matériel se règle avec Fn + F3/F4."

        $btnKb = New-Object System.Windows.Controls.Button
        $btnKb.Content = "Appliquer au clavier"
        $btnKb.Width = 200
        $btnKb.HorizontalAlignment = "Left"
        $btnKb.Margin = "0,18,0,0"
        $btnKb.ToolTip = "Envoie l'effet, la couleur, la vitesse et la luminosité choisis au clavier RGB."
        $btnKb.Add_Click({
            try {
                $eff = [string]$script:KbComboEffet.SelectedItem
                $nomCoul = [string]$script:KbComboCouleur.SelectedItem
                $vit = [string]$script:KbComboVitesse.SelectedItem
                $lum = [int]$script:KbSliderLum.Value
                $script:LuminositeClavier = $lum
                $c = $script:AccentsWindows[$nomCoul]
                if (Set-ClavierAura -R $c.R -G $c.G -B $c.B -Mode $eff -Vitesse $vit -Luminosite $lum) {
                    $script:JournalGui.AppendText("Clavier RGB : effet « $eff », couleur « $nomCoul », vitesse $vit, luminosité $lum %.`r`n")
                }
                else {
                    $script:JournalGui.AppendText("Clavier RGB : le clavier n'a pas répondu.`r`n")
                }
                $script:JournalGui.ScrollToEnd()
            }
            catch {
                $script:JournalGui.AppendText("Clavier RGB : échec — $($_.Exception.Message)`r`n")
                $script:JournalGui.ScrollToEnd()
            }
        }) | Out-Null
        $pile.Children.Add($btnKb) | Out-Null
    }

    $def = New-Object System.Windows.Controls.ScrollViewer
    $def.VerticalScrollBarVisibility = "Auto"
    $def.Content = $pile
    $onglet = New-Object System.Windows.Controls.TabItem
    $onglet.Header = T 'onglet.materiel'
    $onglet.Content = $def
    $script:GuiTabs.Items.Add($onglet) | Out-Null
}

function Add-LigneTexte {
    # Étiquette + champ de saisie. -Secret produit un PasswordBox (points au lieu
    # des lettres) : même géométrie, contrôle différent, d'où le retour polymorphe.
    param($Panneau, [string]$Etiquette, [string]$Valeur = "", [switch]$Secret, [int]$Largeur = 300)
    $lbl = New-Object System.Windows.Controls.TextBlock
    $lbl.Text = $Etiquette
    $lbl.Margin = "0,10,0,3"
    $lbl.FontWeight = "SemiBold"
    $Panneau.Children.Add($lbl) | Out-Null
    $ctl = if ($Secret) { New-Object System.Windows.Controls.PasswordBox }
    else { New-Object System.Windows.Controls.TextBox }
    if (-not $Secret) { $ctl.Text = $Valeur }
    $ctl.Width = $Largeur
    $ctl.HorizontalAlignment = "Left"
    $Panneau.Children.Add($ctl) | Out-Null
    return $ctl
}

function Add-PageInstallation {
    # Onglet « Clé d'installation » : les mêmes questions que le menu console, mais
    # toutes visibles d'un coup. Aucune logique n'est dupliquée -- la page se contente
    # de remplir les paramètres de New-AutounattendXml, qui reste le seul endroit où
    # le XML est écrit.
    param($Fenetre)

    $styleCombo = $null
    try { $styleCombo = $Fenetre.FindResource([System.Windows.Controls.ComboBox]) } catch { }
    $styleCase = $null
    try { $styleCase = $Fenetre.FindResource([System.Windows.Controls.CheckBox]) } catch { }

    $pile = New-Object System.Windows.Controls.StackPanel
    $pile.Margin = "16"

    $titre = New-Object System.Windows.Controls.TextBlock
    $titre.Text = T 'inst.titre'
    $titre.FontWeight = "Bold"; $titre.FontSize = 15; $titre.Margin = "0,0,0,6"
    $pile.Children.Add($titre) | Out-Null

    foreach ($cle in 'inst.expl1', 'inst.expl2', 'inst.avert') {
        $t = New-Object System.Windows.Controls.TextBlock
        $t.Text = T $cle
        $t.TextWrapping = "Wrap"; $t.FontSize = 12; $t.Margin = "0,0,0,4"
        $t.MaxWidth = 720
        if ($cle -ne 'inst.expl1') { $t.Opacity = 0.85 }
        $pile.Children.Add($t) | Out-Null
    }

    # --- Cible ----------------------------------------------------------------
    $script:InstVersions = [ordered]@{ "Windows 11" = "11"; "Windows 10" = "10" }
    $script:InstCbVersion = Add-LigneComboClavier $pile $styleCombo (T 'inst.version') @($script:InstVersions.Keys) 0

    $script:InstEditions = [ordered]@{}
    $script:InstEditions[(T 'inst.edition.demander')] = ""
    $script:InstEditions["Pro"] = "Pro"
    $script:InstEditions[(T 'inst.edition.famille')] = "Famille"
    $script:InstEditions[(T 'inst.edition.entreprise')] = "Entreprise"
    $script:InstCbEdition = Add-LigneComboClavier $pile $styleCombo (T 'inst.edition') @($script:InstEditions.Keys) 0

    # Un nom d'édition absent de l'image fait échouer l'installation. Plutôt que de
    # faire parier l'utilisateur sur le contenu de son ISO, on la lit. Le menu console
    # propose la même chose : les deux interfaces doivent savoir faire la même chose.
    $btnIso = New-Object System.Windows.Controls.Button
    $btnIso.Content = T 'inst.edition.lire'
    $btnIso.Margin = "0,6,0,0"
    $btnIso.HorizontalAlignment = "Left"
    $btnIso.Add_Click({
            $dlg = New-Object Microsoft.Win32.OpenFileDialog
            $dlg.Filter = (T 'inst.edition.filtre')
            $dlg.Title = T 'inst.edition.lire'
            if (-not $dlg.ShowDialog()) { return }
            # Le montage prend quelques secondes et fige la fenêtre : sans ce curseur,
            # on croit à un blocage et on reclique.
            [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
            try {
                $trouvees = Get-EditionsImage -Chemin $dlg.FileName
                if ($trouvees.Count -eq 0) { throw (T 'inst.edition.vide') }
                $script:InstEditions = [ordered]@{}
                $script:InstEditions[(T 'inst.edition.demander')] = ""
                foreach ($e in $trouvees) { $script:InstEditions["$($e.Nom)  (index $($e.Index))"] = $e.Nom }
                $script:InstCbEdition.Items.Clear()
                foreach ($k in $script:InstEditions.Keys) { $script:InstCbEdition.Items.Add($k) | Out-Null }
                $script:InstCbEdition.SelectedIndex = if ($script:InstCbEdition.Items.Count -gt 1) { 1 } else { 0 }
                $script:JournalGui.AppendText(((T 'inst.jrn.edition.ok') -f $trouvees.Count) + "`r`n")
            }
            catch {
                $script:JournalGui.AppendText(((T 'inst.jrn.edition.echec') -f $_.Exception.Message) + "`r`n")
            }
            finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
            $script:JournalGui.ScrollToEnd()
        }) | Out-Null
    $pile.Children.Add($btnIso) | Out-Null

    $script:InstLangues = Get-LanguesInstallation
    $script:InstCbLangue = Add-LigneComboClavier $pile $styleCombo (T 'inst.langue') @($script:InstLangues.Keys) 0

    $script:InstFuseaux = Get-FuseauxCourants
    $script:InstCbFuseau = Add-LigneComboClavier $pile $styleCombo (T 'inst.fuseau') @($script:InstFuseaux.Keys) 0

    # --- Compte ---------------------------------------------------------------
    $script:InstTxtUser = Add-LigneTexte $pile (T 'inst.compte')
    $script:InstTxtMdp = Add-LigneTexte $pile (T 'inst.mdp') -Secret
    $tMdp = New-Object System.Windows.Controls.TextBlock
    $tMdp.Text = T 'inst.mdp.avert'
    $tMdp.TextWrapping = "Wrap"; $tMdp.FontSize = 11; $tMdp.Margin = "0,3,0,0"; $tMdp.MaxWidth = 720
    $tMdp.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString('#FFD86A5A'))
    $pile.Children.Add($tMdp) | Out-Null
    $script:InstTxtMachine = Add-LigneTexte $pile (T 'inst.machine')

    # --- Profil ---------------------------------------------------------------
    $script:InstProfils = [ordered]@{}
    $script:InstProfils[(T 'inst.profil.aucun')] = ""
    foreach ($k in $script:Profils.Keys) { $script:InstProfils[(Get-NomProfil $k)] = $k }
    $script:InstCbProfil = Add-LigneComboClavier $pile $styleCombo (T 'inst.profil') @($script:InstProfils.Keys) 0

    # --- Applications ---------------------------------------------------------
    $lblApps = New-Object System.Windows.Controls.TextBlock
    $lblApps.Text = T 'inst.apps'
    $lblApps.Margin = "0,12,0,3"; $lblApps.FontWeight = "SemiBold"
    $pile.Children.Add($lblApps) | Out-Null

    $pileApps = New-Object System.Windows.Controls.StackPanel
    $script:InstAppsCases = @{}
    foreach ($nom in $script:CatalogueApps.Keys) {
        $c = New-Object System.Windows.Controls.CheckBox
        if ($styleCase) { $c.Style = $styleCase }
        $c.Content = $nom
        $c.Margin = "0,2,0,2"
        $pileApps.Children.Add($c) | Out-Null
        $script:InstAppsCases[$script:CatalogueApps[$nom]] = $c
    }
    $boiteApps = New-Object System.Windows.Controls.ScrollViewer
    $boiteApps.VerticalScrollBarVisibility = "Auto"
    $boiteApps.Height = 170; $boiteApps.Width = 420
    $boiteApps.HorizontalAlignment = "Left"
    $boiteApps.Padding = "8"
    $boiteApps.BorderThickness = "1"
    $boiteApps.SetResourceReference([System.Windows.Controls.Control]::BorderBrushProperty, "BorderBrush")
    $boiteApps.Content = $pileApps
    $pile.Children.Add($boiteApps) | Out-Null

    # --- Options ---------------------------------------------------------------
    $script:InstCaseTpm = New-Object System.Windows.Controls.CheckBox
    if ($styleCase) { $script:InstCaseTpm.Style = $styleCase }
    $script:InstCaseTpm.Content = T 'inst.tpm'
    $script:InstCaseTpm.Margin = "0,14,0,4"
    $pile.Children.Add($script:InstCaseTpm) | Out-Null

    $script:InstCaseDisque = New-Object System.Windows.Controls.CheckBox
    if ($styleCase) { $script:InstCaseDisque.Style = $styleCase }
    $script:InstCaseDisque.Content = T 'inst.disque'
    $script:InstCaseDisque.Margin = "0,4,0,4"
    $script:InstCaseDisque.Foreground = [System.Windows.Media.SolidColorBrush]::new(
        [System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString('#FFD86A5A'))
    $pile.Children.Add($script:InstCaseDisque) | Out-Null

    # Le disque 0 est l'habitude, pas une garantie : sur une machine à plusieurs
    # disques, ce peut être celui des données. Se tromper ici efface le mauvais.
    $script:InstTxtDisque = Add-LigneTexte $pile (T 'inst.disque.numero') "0" -Largeur 80

    # La case la plus destructrice de tout l'outil : on redemande, explicitement,
    # au moment où elle est cochée. Décocher ne demande évidemment rien.
    $script:InstCaseDisque.Add_Checked({
            $r = [System.Windows.MessageBox]::Show(
                (T 'inst.disque.confirm'), (T 'inst.disque.titre'),
                [System.Windows.MessageBoxButton]::YesNo,
                [System.Windows.MessageBoxImage]::Warning)
            if ($r -ne [System.Windows.MessageBoxResult]::Yes) { $this.IsChecked = $false }
        }) | Out-Null

    # --- Génération ------------------------------------------------------------
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = T 'inst.generer'
    $btn.Margin = "0,16,0,0"
    $btn.HorizontalAlignment = "Left"
    $btn.Add_Click({
            try {
                $user = $script:InstTxtUser.Text.Trim()
                if (-not $user) {
                    $script:JournalGui.AppendText((T 'inst.jrn.sansnom') + "`r`n")
                    $script:JournalGui.ScrollToEnd()
                    return
                }
                $apps = @()
                foreach ($id in $script:InstAppsCases.Keys) {
                    if ($script:InstAppsCases[$id].IsChecked) { $apps += $id }
                }
                $profil = $script:InstProfils[$script:InstCbProfil.SelectedItem]
                $dossier = Join-Path ([Environment]::GetFolderPath("Desktop")) "madtweak-installation"
                $chemin = Join-Path $dossier "autounattend.xml"

                if ($script:Simulation) {
                    $script:JournalGui.AppendText(((T 'inst.jrn.simu') -f $chemin, $apps.Count) + "`r`n")
                    $script:JournalGui.ScrollToEnd()
                    return
                }
                if (-not (Test-Path $dossier)) { New-Item -ItemType Directory -Path $dossier -Force | Out-Null }

                $p = @{
                    Chemin         = $chemin
                    NomUtilisateur = $user
                    MotDePasse     = $script:InstTxtMdp.Password
                    NomMachine     = $script:InstTxtMachine.Text.Trim()
                    Langue         = $script:InstCbLangue.SelectedItem
                    Fuseau         = $script:InstFuseaux[$script:InstCbFuseau.SelectedItem]
                    Version        = $script:InstVersions[$script:InstCbVersion.SelectedItem]
                    Edition        = $script:InstEditions[$script:InstCbEdition.SelectedItem]
                    Apps           = $apps
                }
                if ($profil) { $p.Profil = $profil }
                if ($script:InstCaseTpm.IsChecked) { $p.SansTPM = $true }
                if ($script:InstCaseDisque.IsChecked) {
                    $p.EffacerDisque = $true
                    $nd = 0
                    if ([int]::TryParse($script:InstTxtDisque.Text.Trim(), [ref]$nd)) { $p.Disque = $nd }
                }

                New-AutounattendXml @p | Out-Null
                $script:JournalGui.AppendText(((T 'inst.jrn.ok') -f $chemin) + "`r`n")

                # Étape que l'outil sait faire lui-même : déposer les fichiers sur une
                # clé DÉJÀ préparée. On ne formate rien et on n'écrit aucune image ;
                # c'est le travail de Rufus, et il n'y a pas lieu de le refaire.
                $pretes = @(Get-ClesInstallation | Where-Object EstSupport)
                if ($pretes.Count -eq 0) {
                    $script:JournalGui.AppendText((T 'inst.jrn.cle.aucune') + "`r`n")
                }
                else {
                    foreach ($k in $pretes) {
                        $r = [System.Windows.MessageBox]::Show(
                            ((T 'inst.cle.confirm') -f $k.Lettre, $k.Nom, $k.Go),
                            (T 'inst.cle.titre'),
                            [System.Windows.MessageBoxButton]::YesNo,
                            [System.Windows.MessageBoxImage]::Question)
                        if ($r -ne [System.Windows.MessageBoxResult]::Yes) { continue }
                        $src = $null
                        if ($profil -and $PSCommandPath -and $PSCommandPath.EndsWith('.ps1')) { $src = $PSCommandPath }
                        try {
                            foreach ($fait in (Copy-FichiersVersCle -Lettre $k.Lettre -CheminXml $chemin -CheminMadTweak $src)) {
                                $script:JournalGui.AppendText(((T 'inst.jrn.cle.ok') -f $fait) + "`r`n")
                            }
                        }
                        catch {
                            $script:JournalGui.AppendText(((T 'inst.jrn.cle.echec') -f $_.Exception.Message) + "`r`n")
                        }
                        break
                    }
                }
                $script:JournalGui.AppendText((T 'inst.jrn.suite') + "`r`n")
                if ($profil) { $script:JournalGui.AppendText((T 'inst.jrn.profil') + "`r`n") }
                if ($script:InstTxtMdp.Password) { $script:JournalGui.AppendText((T 'inst.jrn.mdp') + "`r`n") }
                try { Start-Process explorer.exe $dossier } catch { }
            }
            catch {
                $script:JournalGui.AppendText(((T 'inst.jrn.echec') -f $_.Exception.Message) + "`r`n")
            }
            $script:JournalGui.ScrollToEnd()
        }) | Out-Null
    $pile.Children.Add($btn) | Out-Null

    $def = New-Object System.Windows.Controls.ScrollViewer
    $def.VerticalScrollBarVisibility = "Auto"
    $def.Content = $pile
    $onglet = New-Object System.Windows.Controls.TabItem
    $onglet.Header = T 'onglet.installation'
    $onglet.Content = $def
    $script:GuiTabs.Items.Add($onglet) | Out-Null
}

function Update-ScoreGui {
    # Affiche la note de santé dans l'en-tête, colorée selon le niveau.
    param($Score)
    if (-not $script:GuiTxtScore) { return }
    $script:GuiTxtScore.Text = "Santé : $($Score.Note)/100  ·  $($Score.Mention)"
    $couleur = if ($Score.Note -ge 80) { '#FF5CC86E' } elseif ($Score.Note -ge 60) { '#FF8FC85C' } elseif ($Score.Note -ge 40) { '#FFCAA24A' } else { '#FFD86A5A' }
    $b = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color][System.Windows.Media.ColorConverter]::ConvertFromString($couleur))
    $b.Freeze()
    $script:GuiTxtScore.Foreground = $b
    if ($script:GuiBorderScore) { $script:GuiBorderScore.Visibility = 'Visible' }
}

function Show-ListeModaleGui {
    # Fenêtre modale générique : un titre, des lignes de texte, un bouton Fermer.
    # Sert aux analyses (démarrage, disque, indésirables) : elles n'ont rien à
    # modifier, juste beaucoup à montrer -- et le journal serait trop étroit.
    param([string]$Titre, [string[]]$Lignes)
    $win = New-Object System.Windows.Window
    $win.Title = $Titre; $win.Width = 780; $win.Height = 560
    $win.WindowStartupLocation = 'CenterOwner'
    if ($script:GuiFenetre) { $win.Owner = $script:GuiFenetre; $win.Resources = $script:GuiFenetre.Resources; $win.Background = $script:GuiFenetre.Background }
    $grille = New-Object System.Windows.Controls.Grid; $grille.Margin = "12"
    foreach ($h in '*', 'Auto') { $rd = New-Object System.Windows.Controls.RowDefinition; $rd.Height = $h; $grille.RowDefinitions.Add($rd) }
    $box = New-Object System.Windows.Controls.TextBox
    $box.IsReadOnly = $true; $box.FontFamily = "Consolas"; $box.FontSize = 12
    $box.VerticalScrollBarVisibility = 'Auto'; $box.TextWrapping = 'NoWrap'; $box.BorderThickness = 0
    $box.Text = ($Lignes -join "`r`n")
    $box.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, "JournalBgBrush")
    $box.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "JournalFgBrush")
    [System.Windows.Controls.Grid]::SetRow($box, 0); $grille.Children.Add($box) | Out-Null
    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = "Fermer"; $btn.HorizontalAlignment = 'Right'; $btn.Margin = "0,10,0,0"
    $btn.Add_Click({ $script:ListeModaleWin.Close() }) | Out-Null
    [System.Windows.Controls.Grid]::SetRow($btn, 1); $grille.Children.Add($btn) | Out-Null
    $win.Content = $grille
    $script:ListeModaleWin = $win
    $win.ShowDialog() | Out-Null
}

function New-IconeApp {
    # Dessine l'icône de la fenêtre (carré rouge arrondi + « M » blanc) à la volée.
    # Pas de fichier .ico binaire embarqué : même principe que les fonds « MadTrix ».
    param([int]$Taille = 64)
    $canvas = New-Object System.Windows.Controls.Canvas
    $canvas.Width = $Taille; $canvas.Height = $Taille
    $fond = New-Object System.Windows.Shapes.Rectangle
    $fond.Width = $Taille; $fond.Height = $Taille; $fond.RadiusX = $Taille * 0.22; $fond.RadiusY = $Taille * 0.22
    $grad = New-Object System.Windows.Media.LinearGradientBrush
    $grad.StartPoint = "0,0"; $grad.EndPoint = "1,1"
    $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString("#FFE01008"), 0)))
    $grad.GradientStops.Add((New-Object System.Windows.Media.GradientStop ([System.Windows.Media.ColorConverter]::ConvertFromString("#FF7A0A0A"), 1)))
    $fond.Fill = $grad
    $canvas.Children.Add($fond) | Out-Null
    $m = New-Object System.Windows.Controls.TextBlock
    $m.Text = "M"
    $m.FontFamily = New-Object System.Windows.Media.FontFamily "Segoe UI Black"
    $m.FontSize = $Taille * 0.62
    $m.FontWeight = [System.Windows.FontWeights]::Black
    $m.Foreground = [System.Windows.Media.Brushes]::White
    $m.Measure([System.Windows.Size]::new([double]::PositiveInfinity, [double]::PositiveInfinity))
    [System.Windows.Controls.Canvas]::SetLeft($m, ($Taille - $m.DesiredSize.Width) / 2)
    [System.Windows.Controls.Canvas]::SetTop($m, ($Taille - $m.DesiredSize.Height) / 2)
    $canvas.Children.Add($m) | Out-Null
    $canvas.Measure([System.Windows.Size]::new($Taille, $Taille))
    $canvas.Arrange([System.Windows.Rect]::new(0, 0, $Taille, $Taille))
    $canvas.UpdateLayout()
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap($Taille, $Taille, 96, 96, [System.Windows.Media.PixelFormats]::Pbgra32)
    $rtb.Render($canvas)
    $rtb.Freeze()
    return $rtb
}

function Add-BoutonProfilPerso {
    # Ajoute à la zone Profils une ligne pour un profil personnalisé, chargée comme
    # un profil intégré (coche ses clés). Lit les clés dans $script:ProfilsPersoCache
    # (rafraîchi à chaque enregistrement), donc pas de closure fragile.
    param([string]$Nom)
    $cles = @($script:ProfilsPersoCache[$Nom])
    $ligne = New-Object System.Windows.Controls.DockPanel
    $ligne.Margin = "0,0,0,6"; $ligne.LastChildFill = $true
    $b = New-Object System.Windows.Controls.Button
    $b.Content = "$Nom  ($($cles.Count))"
    $b.Width = 180; $b.VerticalAlignment = 'Top'; $b.Margin = "0,0,10,0"; $b.Tag = $Nom
    $b.Add_Click({
        param($emetteur, $evt)
        if ($script:GuiOccupe) { return }
        $c = @($script:ProfilsPersoCache[$emetteur.Tag])
        foreach ($x in $script:GuiCases.Values) { $x.IsChecked = $false }
        $n = 0
        foreach ($cle in $c) { if ($script:GuiCases.ContainsKey($cle)) { $script:GuiCases[$cle].IsChecked = $true; $n++ } }
        $script:JournalGui.AppendText("`r`n=== Profil perso « $($emetteur.Tag) » : $n tweak(s) cochés. Ajuste puis « Appliquer ». ===`r`n")
        $script:JournalGui.ScrollToEnd()
    }) | Out-Null
    [System.Windows.Controls.DockPanel]::SetDock($b, 'Left')
    $ligne.Children.Add($b) | Out-Null
    $desc = New-Object System.Windows.Controls.TextBlock
    $desc.Text = "Profil personnalisé — $($cles.Count) tweak(s), enregistré par toi."
    $desc.TextWrapping = 'Wrap'; $desc.FontSize = 11; $desc.VerticalAlignment = 'Center'
    $desc.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextMutedBrush")
    $ligne.Children.Add($desc) | Out-Null
    $script:PanelProfilsRef.Children.Add($ligne) | Out-Null
}

function Show-Gui {
    # Levée ici = repli sur la console (voir le lancement). On charge WPF avant tout
    # le reste : si l'assembly manque, rien n'a encore été construit pour rien.
    Add-Type -AssemblyName PresentationFramework -ErrorAction Stop
    Add-Type -AssemblyName PresentationCore, WindowsBase -ErrorAction Stop

    $fenetre = [System.Windows.Markup.XamlReader]::Parse((Expand-Textes $script:XamlInterface))

    # Finition « produit » : icône dessinée, titre et en-tête versionnés.
    try { $fenetre.Icon = New-IconeApp 64 } catch { }
    $fenetre.Title = "MadTweak v$($script:Version) — $(T 'app.soustitre')"
    $titreHaut = $fenetre.FindName("TxtTitre")
    if ($titreHaut) { $titreHaut.Text = "MADTWEAK  v$($script:Version)" }
    # Le score reste caché tant que l'audit n'a pas tourné : afficher « 0/100 » avant
    # d'avoir mesuré serait un mensonge.
    $script:GuiTxtScore = $fenetre.FindName("TxtScore")
    $script:GuiBorderScore = $fenetre.FindName("BorderScore")

    # --- Sélecteur de langue. Le choix est ENREGISTRÉ (il survit à la fermeture) mais
    # ne redessine pas la fenêtre : reconstruire tout l'arbre WPF à chaud coûterait
    # bien plus qu'un redémarrage de l'outil, pour un réglage qu'on change une fois.
    $script:GuiComboLangue = $fenetre.FindName("ComboLangue")
    $noms = [ordered]@{ 'fr' = 'Français'; 'en' = 'English' }
    foreach ($n in $noms.Values) { $script:GuiComboLangue.Items.Add($n) | Out-Null }
    $script:GuiComboLangue.SelectedIndex = @($noms.Keys).IndexOf($script:LangueActive)
    $script:GuiComboLangue.Add_SelectionChanged({
        $codes = @('fr', 'en')
        $c = $codes[$script:GuiComboLangue.SelectedIndex]
        if (-not $c -or $c -eq $script:LangueActive) { return }
        try {
            Set-Langue $c
            $f = Join-Path $script:DossierDonnees "langue.txt"
            [System.IO.File]::WriteAllText($f, $c, [System.Text.Encoding]::UTF8)
            $script:JournalGui.AppendText("`r`n" + (T 'langue.redemarrer') + "`r`n")
            $script:JournalGui.ScrollToEnd()
        }
        catch { }
    }) | Out-Null

    $comboTheme = $fenetre.FindName("ComboTheme")
    foreach ($tName in $script:Themes.Keys) {
        $comboTheme.Items.Add($tName) | Out-Null
    }
    
    $themeParDefaut = "Sombre Moderne"
    $fichierTheme = Join-Path $script:DossierDonnees "theme.txt"
    if (Test-Path $fichierTheme) {
        try {
            $sauvegarde = [System.IO.File]::ReadAllText($fichierTheme, [System.Text.Encoding]::UTF8).Trim()
            if ($script:Themes.Contains($sauvegarde)) {
                $themeParDefaut = $sauvegarde
            }
        } catch {}
    }
    
    $comboTheme.SelectedItem = $themeParDefaut
    Set-Theme -Fenetre $fenetre -NomTheme $themeParDefaut

    $comboTheme.Add_SelectionChanged({
        $themeSelection = $comboTheme.SelectedItem
        if ($themeSelection) {
            Set-Theme -Fenetre $script:GuiFenetre -NomTheme $themeSelection
        }
    }) | Out-Null

    # --- Accent Windows : colore les barres de titre, la barre des tâches et le
    # menu Démarrer. Appelle Set-AccentWindows (module Signature), donc réversible
    # via « Annuler » (chaque valeur passe par Save-EtatAvant). L'application est
    # rapide (registre + diffusion), donc directe sur le thread de l'interface.
    $script:GuiComboAccent = $fenetre.FindName("ComboAccent")
    $script:AccentPlaceholder = T 'sel.choisir'
    $script:AccentDefaut = T 'sel.accent.defaut'
    $script:GuiComboAccent.Items.Add($script:AccentPlaceholder) | Out-Null
    foreach ($nomAcc in $script:AccentsWindows.Keys) { $script:GuiComboAccent.Items.Add($nomAcc) | Out-Null }
    $script:GuiComboAccent.Items.Add($script:AccentDefaut) | Out-Null
    # SelectedIndex AVANT de brancher le gestionnaire : sinon la sélection initiale
    # déclencherait un « changement » et appliquerait un accent au démarrage.
    $script:GuiComboAccent.SelectedIndex = 0
    $script:GuiComboAccent.Add_SelectionChanged({
        # Lié au vrai scope (pas de GetNewClosure) : $script: y résout.
        $sel = $script:GuiComboAccent.SelectedItem
        if (-not $sel -or $sel -eq $script:AccentPlaceholder) { return }
        if ($script:GuiOccupe) {
            $script:JournalGui.AppendText("Attends la fin de l'application en cours avant de changer l'accent Windows.`r`n")
            $script:JournalGui.ScrollToEnd()
            return
        }
        # Set-Accent/Restore-Accent écrivent déjà leur bilan via Write-Etat, qui va
        # dans le journal. On enveloppe juste pour attraper une éventuelle erreur.
        try {
            if ($sel -eq $script:AccentDefaut) {
                Restore-AccentWindows
            }
            else {
                # 1) Le fond MadTrix D'ABORD, assorti à la couleur de l'accent : bureau,
                #    barres et accent seront tous coordonnés. On génère avant l'accent
                #    car Set-AccentWindows relance l'Explorateur à la fin.
                $c = $script:AccentsWindows[$sel]
                $hex = "#{0:X2}{1:X2}{2:X2}" -f [int]$c.R, [int]$c.G, [int]$c.B
                # Style = celui choisi dans « Fond d'écran », sinon Matrix par défaut.
                $style = "matrix"
                $selFond = $script:GuiComboFond.SelectedItem
                if ($selFond -and $selFond -match '—\s*(Matrix|HUD|Neon)') { $style = $Matches[1].ToLower() }
                $res = Get-ResolutionPhysique
                $script:JournalGui.AppendText("`r`nGénération du fond MadTrix « $style » assorti à l'accent « $sel » ($hex)...`r`n")
                $script:JournalGui.ScrollToEnd(); Update-InterfaceGui
                $chemin = Join-Path $script:DossierDonnees "fond-madtrix-$style.png"
                New-FondSignature -Style $style -Largeur $res.L -Hauteur $res.H -Chemin $chemin -Couleur $hex | Out-Null
                Set-FondEcran -Chemin $chemin
                $script:JournalGui.AppendText("Fond assorti appliqué.`r`n")
                $script:JournalGui.ScrollToEnd(); Update-InterfaceGui
                # 2) Puis l'accent (barres de titre + barre des tâches).
                Set-AccentWindows -Nom $sel
            }
        }
        catch {
            $script:JournalGui.AppendText("Échec de l'accent/fond : $($_.Exception.Message)`r`n")
            $script:JournalGui.ScrollToEnd()
        }
    }) | Out-Null

    # --- Fond d'écran « MadTrix » : mêmes styles que le menu Signature (Matrix, HUD,
    # Neon). Régénéré à la résolution réelle et appliqué directement. Réversible :
    # Set-FondEcran mémorise le fond précédent (Save-EtatAvant + fichier).
    $script:GuiComboFond = $fenetre.FindName("ComboFond")
    $script:FondPlaceholder = T 'sel.choisir'
    $script:FondPrecedent = T 'sel.fond.precedent'
    $script:GuiComboFond.Items.Add($script:FondPlaceholder) | Out-Null
    $script:GuiComboFond.Items.Add("MadTrix — Matrix") | Out-Null
    $script:GuiComboFond.Items.Add("MadTrix — HUD") | Out-Null
    $script:GuiComboFond.Items.Add("MadTrix — Neon") | Out-Null
    $script:GuiComboFond.Items.Add($script:FondPrecedent) | Out-Null
    $script:GuiComboFond.SelectedIndex = 0
    $script:GuiComboFond.Add_SelectionChanged({
        $sel = $script:GuiComboFond.SelectedItem
        if (-not $sel -or $sel -eq $script:FondPlaceholder) { return }
        if ($script:GuiOccupe) {
            $script:JournalGui.AppendText("Attends la fin de l'application en cours avant de changer le fond d'écran.`r`n")
            $script:JournalGui.ScrollToEnd()
            return
        }
        try {
            if ($sel -eq $script:FondPrecedent) {
                Restore-FondPrecedent
            }
            else {
                # "MadTrix — Matrix" -> "matrix"
                $style = ($sel -split '—')[-1].Trim().ToLower()
                # Le fond prend la COULEUR DU THÈME sélectionné : chaque thème a donc
                # sa propre image assortie. On lit l'accent du thème courant.
                $themeActuel = $script:GuiFenetre.FindName("ComboTheme").SelectedItem
                $couleurFond = "#E01008"
                if ($themeActuel -and $script:Themes.Contains($themeActuel)) {
                    $couleurFond = $script:Themes[$themeActuel].Accent
                }
                $res = Get-ResolutionPhysique
                $script:JournalGui.AppendText("`r`nGénération du fond « $style » assorti au thème « $themeActuel » en $($res.L)x$($res.H) (quelques secondes)...`r`n")
                $script:JournalGui.ScrollToEnd()
                Update-InterfaceGui
                $chemin = Join-Path $script:DossierDonnees "fond-madtrix-$style.png"
                New-FondSignature -Style $style -Largeur $res.L -Hauteur $res.H -Chemin $chemin -Couleur $couleurFond | Out-Null
                Set-FondEcran -Chemin $chemin
                $script:JournalGui.AppendText("Fond « $style » ($couleurFond) appliqué.`r`n")
                $script:JournalGui.ScrollToEnd()
            }
        }
        catch {
            $script:JournalGui.AppendText("Échec du fond d'écran : $($_.Exception.Message)`r`n")
            $script:JournalGui.ScrollToEnd()
        }
    }) | Out-Null

    # TOUT ce que touchent les gestionnaires d'événements vit en $script:. C'est
    # VITAL et pas cosmétique : un gestionnaire créé avec .GetNewClosure() est lié à
    # un module dynamique où $script: pointe dans le vide -> $script:Profils y est
    # NULL, d'où le « Indexation impossible dans un tableau Null » qui figeait la
    # fenêtre. La règle est donc : état partagé en $script:, et AUCUN GetNewClosure
    # sur les blocs qui lisent du $script: (ils sont alors liés au vrai scope).
    $script:GuiFenetre = $fenetre
    $script:GuiTabs = $fenetre.FindName("TabsCategories")
    $panelProfils = $fenetre.FindName("PanelProfils")
    $script:JournalGui = $fenetre.FindName("TxtJournal")
    $script:GuiTxtEtat = $fenetre.FindName("TxtEtat")
    $script:GuiTxtSelection = $fenetre.FindName("TxtSelection")
    $script:GuiProgress = $fenetre.FindName("BarreProgression")
    $script:GuiCases = @{}

    $fenetre.FindName("TxtSysteme").Text =
        "$($script:InfosOS.DisplayVersion) — build $($script:BuildOS).$($script:InfosOS.UBR) — $($script:InfosOS.EditionID)" +
        $(if ($script:EstFamille) { "  (Famille : plusieurs stratégies HKLM y sont ignorées par Windows)" } else { "" })

    # Vrai pendant une application/simulation : empêche un re-clic et coupe les
    # boutons. État par-application, lu par le bilan de fin.
    $script:GuiOccupe = $false
    $script:GuiEnSim = $false
    $script:GuiClesAppliquees = @()

    # --- Journal : c'est ici que toute la sortie du script atterrit ---
    $script:SortieGui = {
        param($Message, $Niveau)
        $prefixe = switch ($Niveau) {
            "OK" { "  [OK]    " } "Echec" { "  [ÉCHEC] " } "Avert" { "  [!]     " }
            "Simu" { "  [SIMU]  " } "Titre" { "" } default { "  [..]    " }
        }
        $script:JournalGui.AppendText("$prefixe$Message`r`n")
        $script:JournalGui.ScrollToEnd()
        # LA correction du « ça tourne dans le vide » : chaque tweak qui écrit une
        # ligne rend la main à l'affichage. Sans ce pompage, toute l'application se
        # déroulait fenêtre gelée, et le journal n'apparaissait qu'à la toute fin.
        # Un tweak lent isolé (énumération des bloatwares, point de restauration)
        # fige encore le temps de SON exécution -- inévitable sans thread séparé --
        # mais on n'a plus une seule longue congélation opaque.
        Update-InterfaceGui
    }

    # --- Luminosité de l'écran (barre d'en-tête) : native (WMI), donc universelle,
    # contrairement au clavier. Masquée si l'écran n'est pas pilotable (poste fixe).
    $script:GuiSliderEcran = $fenetre.FindName("SliderEcran")
    $script:GuiTxtEcran = $fenetre.FindName("TxtEcran")
    $panelEcran = $fenetre.FindName("PanelEcran")
    if (Test-EcranReglable) {
        $curEcran = Get-LuminositeEcran
        if ($curEcran -lt 10) { $curEcran = 75 }
        $script:GuiSliderEcran.Value = $curEcran
        $script:GuiTxtEcran.Text = "$curEcran %"
        # Attaché APRÈS la valeur initiale : la mise en place ne déclenche pas de réglage.
        $script:GuiSliderEcran.Add_ValueChanged({
            $v = [int]$this.Value
            $script:GuiTxtEcran.Text = "$v %"
            Set-LuminositeEcran -Niveau $v | Out-Null
        }) | Out-Null
    }
    elseif ($panelEcran) { $panelEcran.Visibility = 'Collapsed' }

    # --- Cases à cocher, construites depuis l'inventaire (donc depuis le code) ---
    $inventaire = Get-Inventaire
    $script:GuiCases = @{}
    $script:GuiExplications = @{}   # cle -> TextBlock d'explication, pour que la recherche masque les deux

    # Le style de case (avec le template qui remplace la case BLANCHE système) est
    # assigné EXPLICITEMENT à chaque case. Le style implicite (TargetType) devrait
    # suffire, mais l'assignation directe ne laisse AUCUN doute : c'est ce qui tue
    # définitivement les « carrés blancs ».
    $styleCase = $null
    try { $styleCase = $fenetre.FindResource([System.Windows.Controls.CheckBox]) } catch { }

    foreach ($groupe in ($inventaire | Group-Object Categorie)) {
        $pile = New-Object System.Windows.Controls.StackPanel
        $pile.Margin = "10"
        foreach ($t in $groupe.Group) {
            $cb = New-Object System.Windows.Controls.CheckBox
            if ($styleCase) { $cb.Style = $styleCase }
            # Les titres sont des QUESTIONS (« Désactiver X ? ») : le point
            # d'interrogation n'a plus de sens à côté d'une case à cocher.
            $cb.Content = ($t.Titre -replace '\s*\?\s*$', '')
            $cb.Tag = $t.Cle
            $cb.FontWeight = 'SemiBold'
            if ($t.Redemarrage) {
                $cb.ToolTip = "Ce réglage ne prendra effet qu'après un redémarrage."
                $cb.Content = "$($cb.Content)   ⟳"
            }
            $pile.Children.Add($cb) | Out-Null

            # L'explication est affichée EN PERMANENCE sous la case, pas rangée dans
            # une infobulle : une infobulle ne se découvre qu'en survolant, donc
            # personne ne la lit -- surtout pas celui qui coche vite. Un réglage
            # qu'on ne comprend pas est un réglage qu'on applique mal.
            if ($t.Explication) {
                $texte = New-Object System.Windows.Controls.TextBlock
                $texte.Text = $t.Explication
                $texte.TextWrapping = 'Wrap'
                $texte.FontSize = 11
                $texte.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextMutedBrush")
                $texte.Margin = '26,0,10,10'
                $pile.Children.Add($texte) | Out-Null
                $script:GuiExplications[$t.Cle] = $texte
            }
            $script:GuiCases[$t.Cle] = $cb
        }
        $defilement = New-Object System.Windows.Controls.ScrollViewer
        $defilement.VerticalScrollBarVisibility = 'Auto'
        $defilement.Content = $pile
        $onglet = New-Object System.Windows.Controls.TabItem
        $onglet.Header = "$(Get-NomOnglet $groupe.Name)  ($($groupe.Count))"
        $onglet.Content = $defilement
        $script:GuiTabs.Items.Add($onglet) | Out-Null
    }

    # Page MATÉRIEL : mode d'alimentation Windows (toujours) + réglages du clavier RGB
    # si le matériel répond. Comme le sous-titre OS, l'interface s'adapte au matériel.
    Add-PageMateriel $fenetre

    # Page CLÉ D'INSTALLATION : génère le fichier de réponses d'une installation
    # automatisée. Rien à cocher parmi les tweaks ici, uniquement de la saisie.
    Add-PageInstallation $fenetre

    $majSelection = {
        $n = @($script:GuiCases.Values | Where-Object { $_.IsChecked }).Count
        $script:GuiTxtSelection.Text = "$n tweak(s) sélectionné(s) sur $($script:GuiCases.Count)"
    }
    foreach ($cb in $script:GuiCases.Values) {
        $cb.Add_Checked($majSelection) | Out-Null
        $cb.Add_Unchecked($majSelection) | Out-Null
    }

    # --- Profils : ils ne font que cocher. Rien n'est appliqué avant « Appliquer ». ---
    # Chaque profil est une LIGNE : bouton à gauche, description toujours visible à
    # droite. La description vivait dans une infobulle, donc elle ne se lisait qu'au
    # survol -- exactement le défaut qu'on reproche aux infobulles pour les tweaks.
    # Un profil applique un gros lot d'un coup : c'est le pire endroit pour cacher
    # ce qu'il fait derrière un survol.
    foreach ($nomProfil in $script:Profils.Keys) {
        $profil = $script:Profils[$nomProfil]

        $ligne = New-Object System.Windows.Controls.DockPanel
        $ligne.Margin = "0,0,0,6"
        $ligne.LastChildFill = $true

        $bouton = New-Object System.Windows.Controls.Button
        $bouton.Content = "$(Get-NomProfil $nomProfil)  ($($profil.Cles.Count))"
        $bouton.Width = 180
        $bouton.VerticalAlignment = 'Top'
        $bouton.Margin = "0,0,10,0"
        $bouton.Tag = $nomProfil
        $bouton.Add_Click({
            param($emetteur, $evt)
            if ($script:GuiOccupe) { return }   # une application est en cours
            $p = $script:Profils[$emetteur.Tag]
            foreach ($c in $script:GuiCases.Values) { $c.IsChecked = $false }
            foreach ($cle in $p.Cles) { if ($script:GuiCases.ContainsKey($cle)) { $script:GuiCases[$cle].IsChecked = $true } }
            $script:JournalGui.AppendText("`r`n=== Profil « $($emetteur.Tag) » : $($p.Cles.Count) tweaks cochés ===`r`n")
            $script:JournalGui.AppendText("$($p.Description)`r`n")
            $script:JournalGui.AppendText("Rien n'est encore appliqué : ajuste les cases, puis Simuler ou Appliquer.`r`n")
            $script:JournalGui.ScrollToEnd()
        }) | Out-Null
        [System.Windows.Controls.DockPanel]::SetDock($bouton, 'Left')
        $ligne.Children.Add($bouton) | Out-Null

        $desc = New-Object System.Windows.Controls.TextBlock
        $desc.Text = Get-DescriptionProfil $nomProfil
        $desc.TextWrapping = 'Wrap'
        $desc.FontSize = 11
        $desc.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextMutedBrush")
        $desc.VerticalAlignment = 'Center'
        $ligne.Children.Add($desc) | Out-Null

        $panelProfils.Children.Add($ligne) | Out-Null
    }

    # --- Profils PERSONNALISÉS (enregistrés par l'utilisateur), sous les intégrés ---
    $script:PanelProfilsRef = $panelProfils
    $script:ProfilsPersoCache = Get-ProfilsPerso
    $script:ProfilsPersoAffiches = New-Object System.Collections.Generic.HashSet[string]
    foreach ($nomPP in @($script:ProfilsPersoCache.Keys)) {
        Add-BoutonProfilPerso $nomPP
        [void]$script:ProfilsPersoAffiches.Add($nomPP)
    }

    # --- Tout cocher / décocher ---
    $script:GuiFenetre.FindName("BtnToutCocher").Add_Click({
        if ($script:GuiOccupe) { return }
        if ($script:GuiTabs.SelectedItem) {
            # Le panneau contient aussi les TextBlock d'explication : sans ce filtre,
            # on tenterait de cocher un bloc de texte.
            foreach ($c in $script:GuiTabs.SelectedItem.Content.Content.Children) {
                if ($c -is [System.Windows.Controls.CheckBox]) { $c.IsChecked = $true }
            }
        }
    }) | Out-Null
    $script:GuiFenetre.FindName("BtnToutDecocher").Add_Click({
        if ($script:GuiOccupe) { return }
        foreach ($c in $script:GuiCases.Values) { $c.IsChecked = $false }
    }) | Out-Null

    $script:GuiFenetre.FindName("BtnSimuler").Add_Click({ Invoke-LancerGui $true }) | Out-Null
    $script:GuiFenetre.FindName("BtnAppliquer").Add_Click({ Invoke-LancerGui $false }) | Out-Null
    $script:GuiFenetre.FindName("BtnRedemarrer").Add_Click({
        if ($script:GuiOccupe) { return }
        $result = [System.Windows.MessageBox]::Show(
            "Es-tu sûr de vouloir redémarrer le PC maintenant pour appliquer tous les tweaks ?",
            "Confirmation de redémarrage",
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        if ($result -eq [System.Windows.MessageBoxResult]::Yes) {
            $script:GuiFenetre.Close()
            Restart-Computer -Force
        }
    }) | Out-Null

    # --- Recherche / filtre des tweaks : masque cases + explications qui ne correspondent pas ---
    $script:GuiRecherche = $fenetre.FindName("TxtRecherche")
    $script:GuiRecherche.Add_TextChanged({
        $q = $script:GuiRecherche.Text.Trim().ToLower()
        foreach ($cle in $script:GuiCases.Keys) {
            $cb = $script:GuiCases[$cle]
            $texte = "$($cb.Content) $cle"
            if ($script:GuiExplications.ContainsKey($cle)) { $texte += " " + $script:GuiExplications[$cle].Text }
            $vis = if (-not $q -or $texte.ToLower().Contains($q)) { 'Visible' } else { 'Collapsed' }
            $cb.Visibility = $vis
            if ($script:GuiExplications.ContainsKey($cle)) { $script:GuiExplications[$cle].Visibility = $vis }
        }
    }) | Out-Null

    # --- État actuel : lit l'audit et COLORE en vert les cases déjà appliquées ---
    $fenetre.FindName("BtnEtatActuel").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Analyse de l'état réel de la machine (quelques secondes)..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        try {
            # Un seul passage sur le catalogue : il alimente à la fois la coloration
            # des cases et le score (les calculer à part doublait le temps d'attente).
            $audit = Get-AuditComplet
            $etat = $audit.Etat
            $vert = [System.Windows.Media.SolidColorBrush]::new([System.Windows.Media.Color]::FromRgb(0x5C, 0xC8, 0x6E)); $vert.Freeze()
            $oui = 0; $non = 0
            foreach ($cle in $script:GuiCases.Keys) {
                $cb = $script:GuiCases[$cle]
                switch ($etat[$cle]) {
                    'OUI' { $cb.Foreground = $vert; $oui++ }
                    'NON' { $cb.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "TextPrimaryBrush"); $non++ }
                    '?' { $cb.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "TextMutedBrush") }
                    default { $cb.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, "TextPrimaryBrush") }
                }
            }
            $script:JournalGui.AppendText("`r`n=== État actuel : $oui réglage(s) déjà actif(s), $non au défaut (sur les tweaks audités) ===`r`n")
            $script:JournalGui.AppendText("En vert = déjà appliqué sur cette machine. Coche ce qui manque, puis « Appliquer ».`r`n")
            # Score de santé : déjà calculé par le même passage, rien à relancer.
            $sc = $audit.Score
            Update-ScoreGui $sc
            $script:JournalGui.AppendText("`r`nSCORE DE SANTÉ : $($sc.Note)/100 ($($sc.Mention)) — $($sc.Appliques) réglages en place sur $($sc.Total) applicables ici.`r`n")
            foreach ($c in $sc.Detail.Keys) { $script:JournalGui.AppendText(("   {0,-22} {1,3}/100`r`n" -f $c, $sc.Detail[$c])) }
            $script:JournalGui.ScrollToEnd()
            $script:GuiTxtEtat.Text = "Audit terminé : score $($sc.Note)/100 — $oui actif(s), $non au défaut."
        }
        catch { $script:GuiTxtEtat.Text = "Audit impossible : $($_.Exception.Message)" }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    }) | Out-Null

    # --- Restauration exacte (Annuler dans la GUI) : remet l'état d'avant depuis la sauvegarde ---
    $fenetre.FindName("BtnRestaurer").Add_Click({
        if ($script:GuiOccupe) { return }
        $n = $script:Sauvegarde.Count
        if ($n -eq 0) {
            $script:JournalGui.AppendText("`r`nRestauration exacte : rien à remettre (ce script n'a modifié aucune valeur ici).`r`n")
            $script:JournalGui.ScrollToEnd(); return
        }
        $rep = [System.Windows.MessageBox]::Show(
            "Remettre les $n valeur(s) modifiées par ce script telles qu'elles étaient avant ?",
            "Restauration exacte", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Question)
        if ($rep -ne [System.Windows.MessageBoxResult]::Yes) { return }
        try {
            Restore-Sauvegarde
            $script:JournalGui.AppendText("`r`n=== Restauration exacte : $n valeur(s) remises comme avant. ===`r`n")
        }
        catch { $script:JournalGui.AppendText("Restauration : échec — $($_.Exception.Message)`r`n") }
        $script:JournalGui.ScrollToEnd()
    }) | Out-Null

    # --- Combo « Gamer ROG » : alimentation Performances + clavier rouge + coche le profil Gamer ---
    $fenetre.FindName("BtnGamerRog").Add_Click({
        if ($script:GuiOccupe) { return }
        Set-ModeAlimentation -Mode "Performances" | Out-Null
        try { Set-ClavierAura -R 226 -G 0 -B 24 -Mode "Statique" | Out-Null } catch { }
        $n = 0
        $profil = $script:Profils["Gamer"]
        if ($profil) {
            foreach ($c in $script:GuiCases.Values) { $c.IsChecked = $false }
            foreach ($cle in $profil.Cles) { if ($script:GuiCases.ContainsKey($cle)) { $script:GuiCases[$cle].IsChecked = $true; $n++ } }
        }
        $script:JournalGui.AppendText("`r`n=== Gamer ROG : alimentation « Performances », clavier rouge, $n tweak(s) Gamer cochés. ===`r`n")
        $script:JournalGui.AppendText("Rien d'appliqué côté tweaks pour l'instant : vérifie la sélection, puis « Appliquer ».`r`n")
        $script:JournalGui.ScrollToEnd()
    }) | Out-Null

    # --- Replier les zones haut (profils) et bas (journal) pour agrandir la liste ---
    # La rangée profils est en Auto : masquer son cadre suffit à la réduire à 0. La
    # rangée journal est en hauteur fixe (190) : on remet aussi sa hauteur à 0 pour
    # que les onglets (rangée *) récupèrent la place.
    $script:GuiGrid = $fenetre.FindName("GridPrincipal")
    $script:GuiBorderProfils = $fenetre.FindName("BorderProfils")
    $script:GuiBorderJournal = $fenetre.FindName("BorderJournal")
    $script:GuiBtnToggleProfils = $fenetre.FindName("BtnToggleProfils")
    $script:GuiBtnToggleJournal = $fenetre.FindName("BtnToggleJournal")
    # Ce sont désormais des MenuItem : leur libellé est .Header (un MenuItem n'a pas
    # de propriété .Content -- y écrire lèverait).
    $script:GuiBtnToggleProfils.Add_Click({
        if ($script:GuiBorderProfils.Visibility -eq 'Visible') {
            $script:GuiBorderProfils.Visibility = 'Collapsed'
            $script:GuiBtnToggleProfils.Header = 'Afficher les profils'
        }
        else {
            $script:GuiBorderProfils.Visibility = 'Visible'
            $script:GuiBtnToggleProfils.Header = 'Cacher les profils'
        }
    }) | Out-Null
    $script:GuiBtnToggleJournal.Add_Click({
        if ($script:GuiBorderJournal.Visibility -eq 'Visible') {
            $script:GuiBorderJournal.Visibility = 'Collapsed'
            $script:GuiGrid.RowDefinitions[4].Height = [System.Windows.GridLength]::new(0)
            $script:GuiBtnToggleJournal.Header = 'Afficher le journal'
        }
        else {
            $script:GuiBorderJournal.Visibility = 'Visible'
            $script:GuiGrid.RowDefinitions[4].Height = [System.Windows.GridLength]::new(190)
            $script:GuiBtnToggleJournal.Header = 'Cacher le journal'
        }
    }) | Out-Null

    # --- Vérifier la dérive : réglages appliqués mais revenus au défaut (post-MAJ) ---
    $fenetre.FindName("BtnDerive").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Recherche des réglages revenus en arrière..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        try {
            $drift = @(Get-DeriveTweaks)
            if ($drift.Count -eq 0) {
                $script:JournalGui.AppendText("`r`n=== Dérive : aucun réglage déjà appliqué n'est revenu en arrière. ===`r`n")
                $script:JournalGui.AppendText("(La dérive se compare à ce que tu as appliqué via cet outil ; applique au moins une fois pour l'alimenter.)`r`n")
            }
            else {
                foreach ($x in $script:GuiCases.Values) { $x.IsChecked = $false }
                $n = 0
                foreach ($cle in $drift) { if ($script:GuiCases.ContainsKey($cle)) { $script:GuiCases[$cle].IsChecked = $true; $n++ } }
                $script:JournalGui.AppendText("`r`n=== Dérive : $n réglage(s) que tu avais appliqués sont revenus au défaut (souvent après une MAJ Windows). Cochés — clique « Appliquer » pour les remettre. ===`r`n")
            }
            $script:JournalGui.ScrollToEnd()
            $script:GuiTxtEtat.Text = "Dérive : $($drift.Count) réglage(s) à réappliquer."
        }
        catch { $script:GuiTxtEtat.Text = "Dérive : $($_.Exception.Message)" }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    }) | Out-Null

    # --- Rapport HTML : état actuel, fichier autonome ouvert dans le navigateur ---
    $fenetre.FindName("BtnRapport").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Génération du rapport HTML..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        try {
            $chemin = New-RapportHTML
            $script:JournalGui.AppendText("`r`n=== Rapport HTML généré : $chemin ===`r`n")
            $script:JournalGui.ScrollToEnd()
            Start-Process $chemin
            $script:GuiTxtEtat.Text = "Rapport ouvert dans le navigateur."
        }
        catch { $script:GuiTxtEtat.Text = "Rapport : $($_.Exception.Message)" }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    }) | Out-Null

    # --- Enregistrer la sélection comme profil personnalisé ---
    $fenetre.FindName("BtnEnregistrerProfil").Add_Click({
        if ($script:GuiOccupe) { return }
        $cles = @($script:GuiCases.GetEnumerator() | Where-Object { $_.Value.IsChecked } | ForEach-Object { $_.Key })
        if ($cles.Count -eq 0) {
            $script:JournalGui.AppendText("`r`nEnregistrer : coche d'abord des tweaks, puis réessaie.`r`n"); $script:JournalGui.ScrollToEnd(); return
        }
        Add-Type -AssemblyName Microsoft.VisualBasic -ErrorAction SilentlyContinue
        $nom = [Microsoft.VisualBasic.Interaction]::InputBox("Nom du profil personnalisé ($($cles.Count) tweak(s) cochés) :", "Enregistrer la sélection", "Mon profil")
        if (-not $nom -or -not $nom.Trim()) { return }
        $nom = $nom.Trim()
        try {
            Save-ProfilPerso -Nom $nom -Cles $cles
            $script:ProfilsPersoCache = Get-ProfilsPerso
            if (-not $script:ProfilsPersoAffiches.Contains($nom)) {
                Add-BoutonProfilPerso $nom
                [void]$script:ProfilsPersoAffiches.Add($nom)
            }
            $script:JournalGui.AppendText("`r`n=== Profil « $nom » enregistré ($($cles.Count) tweaks). Il apparaît dans la zone Profils, rechargeable en un clic. ===`r`n")
            $script:JournalGui.ScrollToEnd()
        }
        catch {
            $script:JournalGui.AppendText("Enregistrement impossible : $($_.Exception.Message)`r`n"); $script:JournalGui.ScrollToEnd()
        }
    }) | Out-Null

    # --- Analyse du démarrage : durée réelle + coût de chaque programme ---
    $fenetre.FindName("BtnDemarrage").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Analyse du démarrage..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        try {
            $a = Get-AnalyseDemarrage
            $L = @()
            if ($a.BootMs -gt 0) { $L += "Dernier démarrage mesuré par Windows : $([math]::Round($a.BootMs / 1000, 1)) secondes." }
            else { $L += "Durée de démarrage non mesurée par Windows (journal Diagnostics-Performance vide)." }
            $L += ""
            if ($a.Programmes.Count -eq 0) { $L += "Aucun programme de démarrage dans les clés Run." }
            else {
                $L += ("{0,-38} {1,-12} {2}" -f "PROGRAMME", "ZONE", "COÛT")
                $L += ("-" * 70)
                foreach ($p in $a.Programmes) {
                    $c = if ($p.CoutMs -gt 0) { "$([math]::Round($p.CoutMs / 1000, 1)) s" } else { "non mesuré" }
                    $L += ("{0,-38} {1,-12} {2}" -f $p.Nom, $p.Zone, $c)
                }
                $L += ""
                $L += "Pour retirer un programme du démarrage : onglet « Démarrage & services »,"
                $L += "ou Gestionnaire des tâches > Applications de démarrage."
            }
            Show-ListeModaleGui "Analyse du démarrage" $L
            $script:GuiTxtEtat.Text = "Démarrage : $($a.Programmes.Count) programme(s) au lancement."
        }
        catch { $script:GuiTxtEtat.Text = "Analyse démarrage : $($_.Exception.Message)" }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    }) | Out-Null

    # --- Analyse disque : on PÈSE avant de proposer de nettoyer ---
    $fenetre.FindName("BtnDisque").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Mesure de l'espace disque (quelques secondes)..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        try {
            $d = Get-AnalyseDisque
            $L = @("Disque système : $($d.LibreGo) Go libres sur $($d.TotalGo) Go", "")
            $L += ("{0,-36} {1,12}" -f "POSTE", "TAILLE")
            $L += ("-" * 50)
            $tot = 0
            foreach ($p in $d.Postes) {
                $tot += $p.Mo
                $taille = if ($p.Mo -ge 1024) { "$([math]::Round($p.Mo / 1024, 2)) Go" } else { "$($p.Mo) Mo" }
                $L += ("{0,-36} {1,12}" -f $p.Nom, $taille)
            }
            $L += ("-" * 50)
            $L += ("{0,-36} {1,12}" -f "TOTAL mesuré", "$([math]::Round($tot / 1024, 2)) Go")
            $L += ""
            $L += "Note : « Téléchargements » et « Windows.old » ne sont PAS touchés par le"
            $L += "nettoyage automatique -- ce sont tes fichiers. Le fichier d'hibernation"
            $L += "n'est libérable qu'en désactivant l'hibernation (déconseillé sur portable)."
            $L += "Pour nettoyer le reste : onglet « Nettoyage »."
            Show-ListeModaleGui "Analyse du disque" $L
            $script:GuiTxtEtat.Text = "Disque : $([math]::Round($tot / 1024, 2)) Go mesurés, $($d.LibreGo) Go libres."
        }
        catch { $script:GuiTxtEtat.Text = "Analyse disque : $($_.Exception.Message)" }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    }) | Out-Null

    # --- Logiciels indésirables : on SIGNALE, on ne désinstalle rien dans le dos ---
    $fenetre.FindName("BtnIndesirables").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Recherche de logiciels indésirables..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        try {
            $pups = @(Get-LogicielsIndesirables)
            if ($pups.Count -eq 0) {
                $L = @("Aucun logiciel indésirable connu détecté.", "",
                    "Sont recherchés : antivirus d'essai préinstallés (McAfee, Norton, Avast...),",
                    "faux optimiseurs (Driver Booster, Advanced SystemCare...), barres d'outils",
                    "et détourneurs de recherche, logiciels OEM superflus.")
            }
            else {
                $L = @("$($pups.Count) logiciel(s) à examiner. RIEN n'a été désinstallé :", "")
                foreach ($p in $pups) {
                    $L += "  $($p.Nom)"
                    $L += "     Éditeur   : $($p.Editeur)"
                    $L += "     Catégorie : $($p.Categorie)"
                    $L += "     Pourquoi  : $($p.Pourquoi)"
                    $L += ""
                }
                $L += "Pour les retirer : Paramètres > Applications > Applications installées."
                $L += "Un antivirus se désinstalle avec SON propre outil de suppression (éditeur)."
            }
            Show-ListeModaleGui "Logiciels indésirables" $L
            $script:GuiTxtEtat.Text = "Indésirables : $($pups.Count) détecté(s)."
        }
        catch { $script:GuiTxtEtat.Text = "Recherche indésirables : $($_.Exception.Message)" }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    }) | Out-Null

    # --- Points de restauration Windows : lister, et éventuellement y revenir ---
    $fenetre.FindName("BtnPointsResto").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Lecture des points de restauration..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        $pts = @()
        try { $pts = @(Get-PointsRestauration) } catch { }
        [System.Windows.Input.Mouse]::OverrideCursor = $null
        if ($pts.Count -eq 0) {
            $script:JournalGui.AppendText("`r`nAucun point de restauration : la protection système est peut-être désactivée. Coche « Point de restauration avant d'appliquer » pour en créer un.`r`n")
            $script:JournalGui.ScrollToEnd()
            $script:GuiTxtEtat.Text = "Aucun point de restauration trouvé."
            return
        }
        $script:JournalGui.AppendText("`r`n=== $($pts.Count) point(s) de restauration ===`r`n")
        foreach ($p in $pts) {
            $d = if ($p.Date) { $p.Date.ToString('dd/MM/yyyy HH:mm') } else { "date inconnue" }
            $script:JournalGui.AppendText(("   #{0}  {1}  {2}  [{3}]`r`n" -f $p.Numero, $d, $p.Description, $p.Type))
        }
        $script:JournalGui.ScrollToEnd()
        $recent = $pts[0]
        $dr = if ($recent.Date) { $recent.Date.ToString('dd/MM/yyyy HH:mm') } else { "date inconnue" }
        $rep = [System.Windows.MessageBox]::Show(
            "Restaurer le système au point le plus récent ?`n`n   #$($recent.Numero) — $dr`n   $($recent.Description)`n`nWindows REDÉMARRERA la machine pour l'appliquer. Enregistre ton travail avant de confirmer.`n`n(La liste complète est dans le journal.)",
            "Points de restauration", [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning)
        if ($rep -eq [System.Windows.MessageBoxResult]::Yes) {
            try {
                Restore-PointRestauration -Numero $recent.Numero | Out-Null
                $script:JournalGui.AppendText("Restauration lancée : la machine va redémarrer.`r`n")
            }
            catch { $script:JournalGui.AppendText("Restauration refusée : $($_.Exception.Message)`r`n") }
            $script:JournalGui.ScrollToEnd()
        }
        $script:GuiTxtEtat.Text = "$($pts.Count) point(s) de restauration listé(s) dans le journal."
    }) | Out-Null

    # --- Diagnostic plantages : crashes récents + tweaks suspects, corrige le pire ---
    $fenetre.FindName("BtnDiagnostic").Add_Click({
        if ($script:GuiOccupe) { return }
        $script:GuiTxtEtat.Text = "Analyse des plantages récents..."
        [System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
        Update-InterfaceGui
        try {
            $d = Get-DiagnosticPlantages
            $script:JournalGui.AppendText("`r`n=== DIAGNOSTIC PLANTAGES ===`r`n")
            if ($d.Crashes.Count -eq 0) {
                $script:JournalGui.AppendText("Aucun arrêt inattendu / écran bleu dans les 21 derniers jours.`r`n")
            }
            else {
                $script:JournalGui.AppendText("$($d.Crashes.Count) plantage(s) récent(s) :`r`n")
                foreach ($c in $d.Crashes) { $script:JournalGui.AppendText("   - $($c.TimeCreated) (Event $($c.Id))`r`n") }
            }
            if ($d.Suspects.Count -eq 0) {
                $script:JournalGui.AppendText("Aucun tweak suspect actif.`r`n")
            }
            else {
                foreach ($s in $d.Suspects) {
                    $script:JournalGui.AppendText("   [$($s.Gravite)] $($s.Nom)`r`n         -> $($s.Conseil)`r`n")
                    if ($s.Cle -eq 'modern-standby') {
                        try {
                            Remove-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "PlatformAoAcOverride" -Force -ErrorAction Stop
                            $script:JournalGui.AppendText("         >> CORRIGÉ : veille moderne S0 restaurée. REDÉMARRE pour finaliser.`r`n")
                        }
                        catch { $script:JournalGui.AppendText("         >> Correction auto impossible : $($_.Exception.Message)`r`n") }
                    }
                }
            }
            $script:JournalGui.ScrollToEnd()
            $script:GuiTxtEtat.Text = "Diagnostic : $($d.Crashes.Count) plantage(s), $($d.Suspects.Count) suspect(s)."
        }
        catch { $script:GuiTxtEtat.Text = "Diagnostic : $($_.Exception.Message)" }
        finally { [System.Windows.Input.Mouse]::OverrideCursor = $null }
    }) | Out-Null

    # --- Restauration sélective : fenêtre modale, une case par valeur modifiée ---
    $fenetre.FindName("BtnRestaurerSelectif").Add_Click({
        if ($script:GuiOccupe) { return }
        $entrees = @(Get-EntreesSauvegarde)
        if ($entrees.Count -eq 0) {
            $script:JournalGui.AppendText("`r`nRestauration sélective : aucune modification enregistrée à annuler.`r`n"); $script:JournalGui.ScrollToEnd(); return
        }
        $win = New-Object System.Windows.Window
        $win.Title = "Restauration sélective"; $win.Width = 720; $win.Height = 560
        $win.WindowStartupLocation = 'CenterOwner'; $win.Owner = $script:GuiFenetre
        $win.Resources = $script:GuiFenetre.Resources   # partage les styles => tout est thémé
        $win.Background = $script:GuiFenetre.Background
        $grille = New-Object System.Windows.Controls.Grid; $grille.Margin = "12"
        foreach ($h in 'Auto', '*', 'Auto') { $rd = New-Object System.Windows.Controls.RowDefinition; $rd.Height = $h; $grille.RowDefinitions.Add($rd) }
        $entete = New-Object System.Windows.Controls.TextBlock
        $entete.Text = "Coche les réglages à remettre à leur état d'origine ($($entrees.Count) modifiés) :"
        $entete.Margin = "0,0,0,8"; $entete.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, "TextPrimaryBrush")
        [System.Windows.Controls.Grid]::SetRow($entete, 0); $grille.Children.Add($entete) | Out-Null
        $sv = New-Object System.Windows.Controls.ScrollViewer; $sv.VerticalScrollBarVisibility = 'Auto'
        [System.Windows.Controls.Grid]::SetRow($sv, 1)
        $pile = New-Object System.Windows.Controls.StackPanel
        $script:RestoreCases = @{}
        foreach ($en in $entrees) {
            $cb = New-Object System.Windows.Controls.CheckBox
            $cb.Content = "$($en.Desc)   (avant : $($en.Avant))"
            $cb.Tag = $en.Cle; $cb.Margin = "0,3,0,3"
            $pile.Children.Add($cb) | Out-Null
            $script:RestoreCases[$en.Cle] = $cb
        }
        $sv.Content = $pile; $grille.Children.Add($sv) | Out-Null
        $barre = New-Object System.Windows.Controls.StackPanel; $barre.Orientation = 'Horizontal'; $barre.HorizontalAlignment = 'Right'; $barre.Margin = "0,10,0,0"
        [System.Windows.Controls.Grid]::SetRow($barre, 2)
        $btnOk = New-Object System.Windows.Controls.Button; $btnOk.Content = "Restaurer la sélection"; $btnOk.Margin = "0,0,8,0"
        $btnFerm = New-Object System.Windows.Controls.Button; $btnFerm.Content = "Fermer"
        $btnOk.Add_Click({
            $sel = @($script:RestoreCases.GetEnumerator() | Where-Object { $_.Value.IsChecked } | ForEach-Object { $_.Key })
            if ($sel.Count -eq 0) { return }
            $res = Restore-SauvegardePartielle -Cles $sel
            $script:JournalGui.AppendText("`r`n=== Restauration sélective : $($res.OK) valeur(s) remise(s), $($res.Echecs) échec(s). ===`r`n")
            $script:JournalGui.ScrollToEnd()
            $script:RestoreWin.Close()
        }) | Out-Null
        $btnFerm.Add_Click({ $script:RestoreWin.Close() }) | Out-Null
        $barre.Children.Add($btnOk) | Out-Null; $barre.Children.Add($btnFerm) | Out-Null
        $grille.Children.Add($barre) | Out-Null
        $win.Content = $grille
        $script:RestoreWin = $win
        $win.ShowDialog() | Out-Null
    }) | Out-Null

    # --- Exporter / importer un bundle de config ---
    $fenetre.FindName("BtnExportConfig").Add_Click({
        if ($script:GuiOccupe) { return }
        $dlg = New-Object Microsoft.Win32.SaveFileDialog
        $dlg.Filter = "Config MadTweak (*.json)|*.json"; $dlg.FileName = "ma-config-madtweak.json"
        if ($dlg.ShowDialog()) {
            try { $c = Export-ConfigBundle -Chemin $dlg.FileName; $script:JournalGui.AppendText("`r`n=== Config exportée : $c ===`r`n") }
            catch { $script:JournalGui.AppendText("Export : $($_.Exception.Message)`r`n") }
            $script:JournalGui.ScrollToEnd()
        }
    }) | Out-Null
    $fenetre.FindName("BtnImportConfig").Add_Click({
        if ($script:GuiOccupe) { return }
        $dlg = New-Object Microsoft.Win32.OpenFileDialog
        $dlg.Filter = "Config MadTweak (*.json)|*.json"
        if ($dlg.ShowDialog()) {
            try {
                $r = Import-ConfigBundle -Chemin $dlg.FileName
                $script:ProfilsPersoCache = Get-ProfilsPerso
                foreach ($nomPP in @($script:ProfilsPersoCache.Keys)) {
                    if (-not $script:ProfilsPersoAffiches.Contains($nomPP)) { Add-BoutonProfilPerso $nomPP; [void]$script:ProfilsPersoAffiches.Add($nomPP) }
                }
                foreach ($x in $script:GuiCases.Values) { $x.IsChecked = $false }
                $n = 0
                foreach ($cle in $r.Cles) { if ($script:GuiCases.ContainsKey($cle)) { $script:GuiCases[$cle].IsChecked = $true; $n++ } }
                $appsTxt = if ($r.Apps) { ", liste d'apps récupérée (menu Logiciels > importer)" } else { "" }
                $script:JournalGui.AppendText("`r`n=== Config importée : $($r.NbProfils) profil(s) perso, $n tweak(s) cochés$appsTxt. Clique « Appliquer » pour poser les tweaks. ===`r`n")
            }
            catch { $script:JournalGui.AppendText("Import : $($_.Exception.Message)`r`n") }
            $script:JournalGui.ScrollToEnd()
        }
    }) | Out-Null

    # --- Maintenance auto : bascule la tâche planifiée hebdomadaire ---
    $script:GuiBtnMaintenance = $fenetre.FindName("BtnMaintenance")
    if (Test-MaintenanceHebdo) { $script:GuiBtnMaintenance.Header = "Maintenance auto : ACTIVÉE" }
    $script:GuiBtnMaintenance.Add_Click({
        if ($script:GuiOccupe) { return }
        try {
            if (Test-MaintenanceHebdo) {
                Unregister-MaintenanceHebdo
                $script:GuiBtnMaintenance.Header = "Maintenance auto (hebdomadaire)"
                $script:JournalGui.AppendText("`r`nMaintenance hebdomadaire désactivée.`r`n")
            }
            else {
                Register-MaintenanceHebdo
                $script:GuiBtnMaintenance.Header = "Maintenance auto : ACTIVÉE"
                $script:JournalGui.AppendText("`r`nMaintenance planifiée (dimanche midi) : nettoyage léger des fichiers temporaires, en silence.`r`n")
            }
            $script:JournalGui.ScrollToEnd()
        }
        catch { $script:JournalGui.AppendText("Maintenance : $($_.Exception.Message)`r`n"); $script:JournalGui.ScrollToEnd() }
    }) | Out-Null

    & $majSelection
    $script:JournalGui.AppendText("Interface prête. $($script:GuiCases.Count) tweaks pilotables, $($script:Profils.Count) profils.`r`n")
    $script:JournalGui.AppendText("Tous les tweaks (y compris Edge, OneDrive, Windows Update, VBS, DISM/SFC, logiciels et nettoyage) sont désormais disponibles directement via cette interface.`r`n`r`n")
    $script:JournalGui.AppendText("Conseil : commence par « Simuler ». Rien ne sera écrit, et tu verras`r`n")
    $script:JournalGui.AppendText("exactement quelle valeur changerait, et en quoi.`r`n")
    $script:GuiTxtEtat.Text = "Prêt. Données de session : $script:DossierDonnees"

    # Minimisation de la console pendant que l'IHM est affichée
    $hwnd = [IntPtr]::Zero
    try {
        if (-not ([System.Management.Automation.PSTypeName]"Win32.NativeMethods").Type) {
            $sig = @'
            [DllImport("user32.dll")]
            public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
            [DllImport("kernel32.dll")]
            public static extern IntPtr GetConsoleWindow();
'@
            Add-Type -MemberDefinition $sig -Name NativeMethods -Namespace Win32 -ErrorAction SilentlyContinue | Out-Null
        }
        $hwnd = [Win32.NativeMethods]::GetConsoleWindow()
        if ($hwnd -ne [IntPtr]::Zero) {
            [Win32.NativeMethods]::ShowWindow($hwnd, 2) | Out-Null # 2 = SW_SHOWMINIMIZED
        }
    } catch {}

    $fenetre.ShowDialog() | Out-Null

    # Restauration de la console après fermeture de l'IHM
    try {
        if ($hwnd -ne [IntPtr]::Zero) {
            [Win32.NativeMethods]::ShowWindow($hwnd, 9) | Out-Null # 9 = SW_RESTORE
        }
    } catch {}

    # La console reprend la main une fois la fenêtre fermée.
    $script:SortieGui = $null
}
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

if ($Simulation) { $script:Simulation = $true }

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
