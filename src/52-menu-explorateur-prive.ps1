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

