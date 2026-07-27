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

