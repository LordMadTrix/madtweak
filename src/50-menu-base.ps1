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

