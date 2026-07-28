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
    # désigner des suspects. Lecture seule.
    $depuis = (Get-Date).AddDays(-21)
    $crashes = @()
    $crashingDrivers = @()
    try {
        $events = Get-WinEvent -FilterHashtable @{ LogName = 'System'; Id = 41, 1001; StartTime = $depuis } -ErrorAction Stop
        $crashes = @($events | Select-Object -First 10 TimeCreated, Id, Message)
        foreach ($evt in $events) {
            if ($evt.Id -eq 1001 -and $evt.Message -and $evt.Message -match '([a-zA-Z0-9_-]+\.sys)') {
                $crashingDrivers += $Matches[1]
            }
        }
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
    return @{
        Crashes = @($crashes)
        Suspects = @($suspects)
        PilotesSuspects = @($crashingDrivers | Select-Object -Unique)
    }
}

function Export-RapportAuditJson {
    param([string]$CheminSortie = "rapport-audit.json")
    $catalogue = Get-CatalogueAudit
    $resultats = @()
    $oui = 0; $non = 0

    foreach ($a in $catalogue) {
        $r = $null
        try { $r = & $a.Test } catch { $r = $null }
        $etatStr = switch ($r) { $true { $oui++; "Applique" } $false { $non++; "Absent" } default { "Indetermine" } }
        $resultats += @{
            Categorie = $a.Cat
            Cle = $a.Cle
            Nom = (Get-NomAudit $a.Nom)
            Etat = $etatStr
        }
    }

    $base = $oui + $non
    $score = if ($base -gt 0) { [int](100 * $oui / $base) } else { 0 }
    $mention = if ($score -ge 80) { "excellent" } elseif ($score -ge 60) { "bon" } elseif ($score -ge 40) { "moyen" } else { "a optimiser" }

    $export = @{
        DateGenere = (Get-Date -Format "o")
        WindowsDisplayVersion = $script:InfosOS.DisplayVersion
        BuildOS = $script:BuildOS
        Edition = $script:InfosOS.EditionID
        ScoreSante = $score
        Mention = $mention
        AuditResults = $resultats
    }

    $json = $export | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($CheminSortie, $json, [System.Text.Encoding]::UTF8)
    return $CheminSortie
}

function Export-RapportAuditMarkdown {
    param([string]$CheminSortie = "rapport-audit.md")
    $catalogue = Get-CatalogueAudit
    $oui = 0; $non = 0
    $lignesResultats = New-Object System.Collections.Generic.List[string]

    foreach ($a in $catalogue) {
        $r = $null
        try { $r = & $a.Test } catch { $r = $null }
        $etatStr = switch ($r) { $true { $oui++; "Appliqué" } $false { $non++; "Absent" } default { "Indéterminé" } }
        $catNom = (Get-CatAudit $a.Cat)
        $nomAudit = (Get-NomAudit $a.Nom)
        $lignesResultats.Add("| $catNom | $nomAudit | $etatStr |")
    }

    $base = $oui + $non
    $score = if ($base -gt 0) { [int](100 * $oui / $base) } else { 0 }
    $mentionKey = if ($score -ge 80) { "sante.excellent" } elseif ($score -ge 60) { "sante.bon" } elseif ($score -ge 40) { "sante.moyen" } else { "sante.faible" }
    $mention = T $mentionKey

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# " + (T 'audit.rapport.md.titre'))
    $lines.Add("")
    $lines.Add("**" + (T 'audit.rapport.md.date') + "** " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"))
    $lines.Add("**" + (T 'audit.rapport.md.score') + "** " + $score + "/100 (" + $mention + ")")
    $lines.Add("")
    $lines.Add("| Catégorie | Réglage | État |")
    $lines.Add("|---|---|---|")
    foreach ($l in $lignesResultats) { $lines.Add($l) }

    $md = ($lines -join "`n") + "`n"
    [System.IO.File]::WriteAllText($CheminSortie, $md, [System.Text.Encoding]::UTF8)
    return $CheminSortie
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

    if (-not (Test-SansInteraction)) { Read-Host "`nAppuie sur Entrée pour revenir au menu principal" }
}

