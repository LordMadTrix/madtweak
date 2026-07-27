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
