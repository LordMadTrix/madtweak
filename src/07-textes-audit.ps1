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
