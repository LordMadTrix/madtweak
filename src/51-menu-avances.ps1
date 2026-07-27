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

