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

