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

