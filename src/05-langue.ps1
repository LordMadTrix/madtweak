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
