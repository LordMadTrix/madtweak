# ------------------------------------------------------------------------------
# MATÉRIEL, RÉSEAU & RAM
# ------------------------------------------------------------------------------
function Menu-Materiel-Cpu {
    Start-Menu -Titre "OPTIMISATION DU MATÉRIEL, DU RÉSEAU ET DE LA RAM" -Couleur Green

    Invoke-Tweak "Désactiver la télémétrie cachée de la carte graphique NVIDIA ?" -Cle "nvidia-telemetrie" `
        -Explication "Le pilote NVIDIA installe un service et des tâches planifiées qui remontent des données d'usage à NVIDIA. Ni le pilote ni tes jeux n'en ont besoin. Sans effet si tu n'as pas de carte NVIDIA." {
        $svc = Get-Service -Name "NvTelemetryContainer" -ErrorAction SilentlyContinue
        if (-not $svc) { throw "Service NvTelemetryContainer absent (pas de pilote NVIDIA, ou télémétrie déjà retirée)." }
        Set-ServiceEtat -Nom "NvTelemetryContainer" -Demarrage Disabled -Arreter
        Invoke-Action "désactiverait les tâches planifiées NVIDIA (NvTmRep*)" {
            Get-ScheduledTask -TaskPath "\NvTmRep*" -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
        }
    }

    # V3 : cette option prétendait vider la "standby list" via ClearPageFileAtShutdown=0.
    # Les deux n'ont aucun rapport, et 0 est déjà la valeur par défaut : c'était un no-op total.
    # Vider réellement la standby list demande un outil externe (RAMMap / EmptyStandbyList).
    # On la remplace par un réglage réel qui, lui, agit sur les saccades.
    Invoke-Tweak "Désactiver SysMain / Superfetch ? (utile sur SSD - à ÉVITER sur disque dur mécanique)" -Cle "sysmain" `
        -Explication "SysMain (ex-Superfetch) précharge en mémoire les applications qu'il pense que tu vas ouvrir. Sur SSD, ce travail de devinette ne sert plus à rien et provoque parfois des saccades. Sur DISQUE DUR mécanique en revanche il aide vraiment : le script vérifie ton disque système et refuse le réglage si c'est un disque dur." {
        # Le libellé disait « à éviter sur disque dur » et s'en remettait à toi. Ça
        # suffit quand tu lis la question ; ça ne suffit plus depuis qu'un PROFIL peut
        # appliquer ce tweak sans que personne ne lise. On vérifie donc nous-mêmes.
        # On cible le disque QUI PORTE Windows et pas « un SSD quelque part dans la
        # machine » : un PC avec SSD système + HDD de données doit passer, et un HDD
        # système + SSD secondaire doit être refusé.
        $type = $null
        try {
            $disque = Get-Partition -DriveLetter ($env:SystemDrive.TrimEnd(':')) -ErrorAction Stop | Get-Disk -ErrorAction Stop
            $type = (Get-PhysicalDisk -ErrorAction Stop | Where-Object { $_.DeviceId -eq $disque.Number }).MediaType
        }
        catch { }

        if ($type -eq 'HDD') {
            throw "Le disque système est un disque dur MÉCANIQUE : SysMain y accélère réellement le chargement des applications, le couper dégraderait la machine. Refusé."
        }
        if ($type -ne 'SSD') {
            # Les disques externes et certains contrôleurs RAID renvoient 'Unspecified'.
            Write-Etat "Type du disque système indéterminé (『$type』) : impossible de confirmer qu'il s'agit d'un SSD. Vérifie-le avant de garder ce réglage." -Niveau Avert
        }
        Set-ServiceEtat -Nom "SysMain" -Demarrage Disabled -Arreter
    }

    Invoke-Tweak "Désactiver la suspension sélective des ports USB (évite les déconnexions) ?" -Cle "usb-suspension" `
        -Explication "Windows coupe l'alimentation des ports USB inactifs pour économiser l'énergie, ce qui provoque des déconnexions de souris, clavier, casque ou disque externe. Ce réglage l'en empêche. Sur un PC fixe, c'est tout bénéfice ; sur un PORTABLE, ça coûte de la batterie." {
        # V3 : écrivait dans HKLM:\SYSTEM\CurrentControlSet\Services\USB, une clé qui
        # n'existe pas sur beaucoup de machines -> tweak silencieusement sauté.
        # Le vrai levier est le plan d'alimentation, via powercfg.
        $sousGroupeUSB = "2a737441-1930-4402-8d77-b2bebba308a3"
        $parametre = "48e6b7a6-50f5-4782-a5d4-53bb8f07e226"
        Invoke-Externe -Fichier "powercfg.exe" -Arguments @("/setacvalueindex", "SCHEME_CURRENT", $sousGroupeUSB, $parametre, "0")
        Invoke-Externe -Fichier "powercfg.exe" -Arguments @("/setdcvalueindex", "SCHEME_CURRENT", $sousGroupeUSB, $parametre, "0")
        Invoke-Externe -Fichier "powercfg.exe" -Arguments @("/setactive", "SCHEME_CURRENT")
    }

    Invoke-Tweak "Désactiver la recherche automatique de dossiers réseau partagés ?" -Cle "net-crawling" `
        -Explication "Empêche l'Explorateur de partir automatiquement à la recherche de dossiers partagés sur ton réseau local. Purement cosmétique : ça évite les latences à l'ouverture de l'Explorateur. Tu peux toujours accéder à tes partages en tapant leur adresse." {
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "NoNetCrawling" -Value 1
    }

    Invoke-Tweak "Désactiver l'hibernation et libérer l'espace de hiberfil.sys ? (désactive aussi le démarrage rapide)" -Cle "hibernation" `
        -Explication "Désactive l'hibernation et supprime hiberfil.sys, un fichier caché qui pèse plusieurs Go. ATTENTION : ça désactive aussi le « démarrage rapide », donc ton PC démarrera plus lentement. Sur un portable, c'est une mauvaise idée : tu perds la mise en veille prolongée qui sauve ta session quand la batterie se vide." {
        Invoke-Externe -Fichier "powercfg.exe" -Arguments @("/hibernate", "off")
    }

    # --- Réseau : le NoNetCrawling ci-dessus est cosmétique, voici les vrais leviers ---

    Invoke-Tweak "Désactiver l'algorithme de Nagle ? (baisse la latence en jeu, peut réduire le débit en téléchargement)" -Cle "nagle" `
        -Explication "L'algorithme de Nagle regroupe les petits paquets réseau avant de les envoyer, ce qui ajoute quelques millisecondes de latence. Le désactiver aide en jeu en ligne. Revers réel : ça peut RÉDUIRE ton débit en téléchargement. À ne prendre que si la latence compte plus que le débit." {
        $base = "HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces"
        if (-not (Test-Path $base)) { throw "Clé des interfaces TCP/IP introuvable." }
        # Inutile d'écrire dans les ~7 sous-clés : seules celles qui portent une adresse
        # IP correspondent à une carte réseau réellement active.
        $actives = Get-ChildItem $base | Where-Object {
            $p = (Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue).PSObject.Properties.Name
            $p -match 'DhcpIPAddress|^IPAddress$'
        }
        if (-not $actives) { throw "Aucune interface réseau active trouvée." }
        foreach ($i in $actives) {
            Set-RegValue -Path $i.PSPath -Name "TcpAckFrequency" -Value 1
            Set-RegValue -Path $i.PSPath -Name "TCPNoDelay" -Value 1
        }
        Write-Etat "$($actives.Count) interface(s) active(s) modifiée(s)." -Niveau Info
    }

    Invoke-Tweak "Désactiver l'accélération de la souris ('précision du pointeur') ? (visée constante en jeu)" -Cle "souris-acceleration" `
        -Explication "Windows accélère le pointeur quand tu bouges la souris vite : le même geste ne donne pas toujours la même distance. Le couper rend ta visée constante, ce que veulent tous les joueurs. Prévois un temps d'adaptation : ta sensibilité en jeu va changer. Effectif à la prochaine ouverture de session." {
        # Ces trois valeurs sont des REG_SZ. MouseSpeed=0 coupe l'accélération ;
        # les seuils doivent tomber à 0 avec, sinon le réglage est incohérent.
        $m = "HKCU:\Control Panel\Mouse"
        Set-RegValue -Path $m -Name "MouseSpeed" -Value "0" -Type String
        Set-RegValue -Path $m -Name "MouseThreshold1" -Value "0" -Type String
        Set-RegValue -Path $m -Name "MouseThreshold2" -Value "0" -Type String
        Write-Etat "Effectif à la prochaine ouverture de session. Ta sensibilité en jeu changera : c'est normal." -Niveau Info
    }

    Invoke-Tweak "Désactiver le spouleur d'impression ? (ferme une surface d'attaque connue)" -Cle "spouleur" `
        -Explication "Le spouleur d'impression est une surface d'attaque connue (la famille de failles PrintNightmare) et tourne en permanence même sans imprimante. Le script vérifie d'abord qu'aucune vraie imprimante n'est installée et refuse si c'en trouve une : sans lui, plus aucune impression possible." {
        # On ne coupe pas le spouleur à l'aveugle : sans lui, plus aucune impression.
        # On vérifie donc d'abord qu'aucune vraie imprimante n'est installée.
        $vraies = Get-Printer -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch 'OneNote|PDF|XPS|Fax' }
        if ($vraies) {
            throw "Des imprimantes sont installées ($(($vraies.Name) -join ', ')) : couper le spouleur les rendrait inutilisables. Refusé."
        }
        Set-ServiceEtat -Nom "Spooler" -Demarrage Disabled -Arreter
        Write-Etat "Aucune imprimante détectée. Si tu en installes une plus tard, réactive le spouleur via le menu ANNULER." -Niveau Avert
    }

    Invoke-Tweak "Désactiver LLMNR et NetBIOS ? (ferme deux surfaces d'attaque classiques du réseau local)" -Cle "llmnr-netbios" `
        -Explication "LLMNR et NetBIOS servent à retrouver des machines sur le réseau local quand le DNS échoue. Ils sont exploités par des attaques classiques d'usurpation en réseau local (type Responder), et un PC domestique avec un DNS qui marche n'en a aucun besoin. Revers : si tu accèdes à un vieux NAS ou à un partage par son nom et que ça casse, annule ce réglage." {
        # LLMNR et NetBIOS servent à résoudre des noms sur le réseau local quand le DNS
        # échoue. Ils sont exploités par les attaques de type relais/empoisonnement
        # (Responder). Sur un PC domestique avec un DNS qui marche, ils ne servent à rien.
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "EnableMulticast" -Value 0

        $nb = "HKLM:\SYSTEM\CurrentControlSet\Services\NetBT\Parameters\Interfaces"
        if (-not (Test-Path $nb)) { throw "Clé NetBT introuvable : NetBIOS ne peut pas être désactivé ici." }
        # 2 = désactivé. (0 = suivre le DHCP, 1 = activé.)
        $n = 0
        foreach ($i in Get-ChildItem $nb) {
            Set-RegValue -Path $i.PSPath -Name "NetbiosOptions" -Value 2
            $n++
        }
        Write-Etat "$n interface(s) NetBT traitée(s)." -Niveau Info
        Write-Etat "Si tu accèdes à un vieux NAS ou un partage réseau par son nom et que ça casse, annule ce tweak." -Niveau Avert
    }

    Invoke-Tweak "Autoriser le DNS chiffré (DNS over HTTPS) ?" -Cle "doh" `
        -Explication "Autorise Windows à chiffrer tes requêtes DNS (DNS over HTTPS), pour que ton fournisseur d'accès ne voie plus en clair les sites que tu visites. Réglé sur « autorisé » et non « obligatoire » : Windows chiffre si ton serveur DNS le sait, et retombe en clair sinon. « Obligatoire » avec un DNS qui ne gère pas DoH te couperait d'Internet. Effectif seulement avec un DNS compatible (Cloudflare, Google, Quad9)." {
        # 2 = « autorisé » : Windows utilise DoH si le serveur DNS configuré le
        # supporte, et retombe en clair sinon. On n'écrit délibérément PAS 3
        # (« obligatoire ») : avec un DNS qui ne gère pas DoH, 3 te couperait
        # purement et simplement d'Internet.
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient" -Name "DoHPolicy" -Value 2
        Write-Etat "Effectif seulement si ton serveur DNS gère DoH (Cloudflare 1.1.1.1, Google 8.8.8.8, Quad9...). Sinon, sans effet." -Niveau Info
    }

    Invoke-Tweak "Empêcher Windows d'éteindre la carte réseau pour économiser l'énergie ? (coupures Wi-Fi, latence)" -Cle "carte-reseau-veille" `
        -Explication "Windows éteint la carte réseau pour économiser l'énergie, ce qui cause des coupures Wi-Fi et des pics de latence. Ce réglage le lui interdit, uniquement sur tes cartes physiques (les cartes virtuelles de VPN ne sont pas touchées). Sur un PORTABLE, ça consomme de la batterie." {
        # Le réglage vit dans la classe de périphériques réseau, une sous-clé par
        # carte (0001, 0002...). On fait le lien via DriverDesc, qui correspond à
        # l'InterfaceDescription remontée par Get-NetAdapter : écrire dans toutes
        # les sous-clés toucherait aussi les cartes virtuelles (VPN, Hyper-V...).
        $cartes = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue)
        if ($cartes.Count -eq 0) { throw "Aucune carte réseau physique détectée." }
        $classe = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e972-e325-11ce-bfc1-08002be10318}"
        if (-not (Test-Path $classe)) { throw "Classe de périphériques réseau introuvable dans le registre." }

        $traitees = @()
        foreach ($sk in (Get-ChildItem $classe | Where-Object { $_.PSChildName -match '^\d{4}$' })) {
            $desc = (Get-ItemProperty $sk.PSPath -Name "DriverDesc" -ErrorAction SilentlyContinue).DriverDesc
            if (-not $desc) { continue }
            if ($desc -notin $cartes.InterfaceDescription) { continue }
            # 24 (0x18) = interdit à Windows d'éteindre la carte et de la réveiller.
            Set-RegValue -Path $sk.PSPath -Name "PnPCapabilities" -Value 24
            $traitees += $desc
        }
        if ($traitees.Count -eq 0) { throw "Aucune carte physique n'a pu être reliée à sa clé de registre : rien n'a été modifié." }
        Write-Etat "$($traitees.Count) carte(s) traitée(s) : $($traitees -join ', ')" -Niveau Info
    }

    # NON INCLUS À DESSEIN, malgré leur popularité sur les forums :
    #  - « autotuninglevel=disabled » : l'auto-tuning TCP est justement ce qui permet
    #    d'atteindre le débit maximal sur une connexion moderne. Le couper est un
    #    conseil daté de Windows Vista qui RÉDUIT le débit aujourd'hui.
    #  - « Désactiver IPv6 » : Microsoft déconseille explicitement de le faire, et
    #    certains composants de Windows le supposent présent.

    # --- Jeu et alimentation ---

    Invoke-Tweak "Désactiver Game DVR / l'enregistrement en arrière-plan de la Game Bar ? (gain de FPS)" -Cle "game-dvr" `
        -Explication "La Game Bar enregistre ton jeu en arrière-plan en permanence, au cas où tu voudrais garder les 30 dernières secondes. Ça coûte des FPS pour une fonction que peu de gens utilisent. La Game Bar (Win+G) reste utilisable : seul l'enregistrement de fond est coupé." {
        # Le service d'enregistrement tourne en fond dès qu'un jeu est détecté.
        Set-RegValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0
        Set-RegValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Value 2
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR" -Name "AllowGameDVR" -Value 0
        Write-Etat "La Game Bar (touche Win+G) reste utilisable, seul l'enregistrement de fond est coupé." -Niveau Info
    }

    Invoke-Tweak "Activer le plan d'alimentation caché 'Performances ultimes' ?" -Cle "plan-performances-ultimes" `
        -Explication "Ajoute le plan d'alimentation caché de Microsoft, qui interdit toute mise en veille des composants. Réservé aux PC FIXES : le script le refuse sur un portable, où Microsoft le masque à raison — il fait chauffer et vide la batterie. Une fois ajouté, il faut le sélectionner dans Paramètres > Système > Alimentation." {
        # Ce plan est masqué par Microsoft sur les machines à batterie, et pour cause :
        # il interdit toute mise en veille des composants. Sur un portable = chauffe
        # et autonomie en chute libre. On refuse plutôt que de dégrader la machine.
        $portable = $null -ne (Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
        if ($portable) {
            # Le nom du plan est LU, pas supposé : ce script tourne aussi ailleurs.
            throw "Cette machine est un PC portable (batterie détectée). Microsoft masque ce plan sur les portables : il empêche toute mise en veille des composants, fait chauffer et vide la batterie. Refusé. Ton plan actuel est « $(Get-PlanAlimentationActif) »."
        }
        Invoke-Externe -Fichier "powercfg.exe" -Arguments @("-duplicatescheme", "e9a42b02-d5df-448d-aa00-03f14749eb61")
        Write-Etat "Plan ajouté. Sélectionne-le dans Paramètres > Système > Alimentation." -Niveau Info
    }

    Invoke-Tweak "Lever le bridage réseau réservé au multimédia (NetworkThrottlingIndex) ?" -Cle "bridage-multimedia" `
        -Explication "Windows bride le réseau et les priorités processeur pour réserver des ressources au multimédia, un compromis pensé pour des machines de 2008. Ce réglage lève le bridage. Utile en jeu et en streaming ; sans effet visible en usage bureautique." -Redemarrage {
        $profil = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        # 0xffffffff = throttling désactivé. On écrit [int]-1 et non 4294967295 :
        # un DWord est un entier 32 bits SIGNÉ côté PowerShell 5.1, qui refuse la
        # valeur non signée. [int]-1 produit exactement le même 0xFFFFFFFF.
        Set-RegValue -Path $profil -Name "NetworkThrottlingIndex" -Value ([int]-1)
        Set-RegValue -Path $profil -Name "SystemResponsiveness" -Value 0
        Write-Etat "Défauts Windows remplacés (ils étaient 10 et 20). Le menu ANNULER les remet." -Niveau Info
    }

    Invoke-Tweak "Désactiver la veille moderne (Modern Standby S0) et restaurer la veille classique S3 ?" -Cle "modern-standby" `
        -Explication "Force la veille classique S3 à la place de la veille moderne S0. RÉSERVÉ aux machines dont le firmware supporte VRAIMENT le S3 : sur un portable conçu pour le S0 (la plupart des ROG récents), forcer le S3 provoque des plantages au réveil et en SORTIE D'HIBERNATION. Le tweak le détecte et REFUSE alors de s'appliquer." -Redemarrage {
        # Refuse de nuire : forcer le S3 sur une plateforme à veille moderne S0 casse le
        # réveil (plantages Kernel-Power au retour de veille/hibernation -- constaté sur
        # ROG Strix 12e gen). La présence de « S0 » dans powercfg /a signe une plateforme
        # S0 ; une machine à vrai S3 ne la liste jamais.
        if (((powercfg /a) -join ' ') -match 'S0') {
            throw "Cette machine gère la veille moderne S0 : forcer le S3 y provoque des plantages au réveil et en sortie d'hibernation. Réglage ignoré (c'est volontaire)."
        }
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Power" -Name "PlatformAoAcOverride" -Value 0
    }

    Invoke-Tweak "Activer la planification GPU accélérée par le matériel (HAGS) ?" -Cle "hags-gpu" -Redemarrage `
        -Explication "Active la planification GPU accélérée par le matériel pour réduire la latence d'affichage et améliorer les performances dans les jeux compatibles (nécessaire pour utiliser la génération d'images Nvidia DLSS 3 / AMD FSR 3)." {
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Name "HwSchMode" -Value 2
    }

    Invoke-Tweak "Désactiver la télémétrie AMD Radeon Software ?" -Cle "amd-telemetrie" `
        -Explication "Désactive la télémétrie et la collecte de données analytiques d'AMD Radeon Software pour préserver ta vie privée." {
        Set-RegValue -Path "HKLM:\SOFTWARE\AMD\CN\ANALYTICS" -Name "ReportAnalytics" -Value 0
    }

    Invoke-Tweak "Désactiver l'économie d'énergie PCIe (Link State Power Management) ?" -Cle "pcie-power-management" `
        -Explication "Configure le plan d'alimentation actif pour désactiver la mise en veille PCIe Link State (PCI Express). Empêche les baisses d'alimentation des cartes graphiques et SSD NVMe pour éliminer les micro-saccades de réveil." {
        Invoke-Action "désactiverait l'économie d'énergie PCIe" {
            powercfg.exe /setacvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a821a03c4f3d ee12f2c1-98ac-4be7-9e4c-1c778ca13c9b 0
            powercfg.exe /setdcvalueindex SCHEME_CURRENT 501a4d13-42af-4429-9fd1-a821a03c4f3d ee12f2c1-98ac-4be7-9e4c-1c778ca13c9b 0
            powercfg.exe /setactive SCHEME_CURRENT
        }
    }

    Invoke-Tweak "Désactiver les fonctions d'arrière-plan de la Xbox Game Bar ?" -Cle "xbox-gamebar" `
        -Explication "Désactive l'enregistrement en arrière-plan et l'application Xbox Game Bar pour libérer des ressources processeur et mémoire en jeu." {
        Set-RegValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_Enabled" -Value 0
        Set-RegValue -Path "HKCU:\System\GameConfigStore" -Name "GameDVR_FSEBehaviorMode" -Value 2
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR" -Name "AppCaptureEnabled" -Value 0
        Set-RegValue -Path "HKCU:\Software\Microsoft\GameBar" -Name "UseNexusForGameBarEnabled" -Value 0
    }

    Invoke-Tweak "Désactiver le partage P2P des mises à jour Windows Update (Delivery Optimization) ?" -Cle "delivery-optimization-p2p" `
        -Explication "Configure Windows pour obtenir les mises à jour Windows Update directement depuis les serveurs de Microsoft (HTTP) sans utiliser ni partager ta bande passante internet en amont (upload) avec d'autres ordinateurs du réseau local ou d'internet." {
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization" -Name "DODownloadMode" -Value 0
    }

    Invoke-Tweak "Désactiver la création des noms courts 8.3 (NTFS Performance) ?" -Cle "ntfs-performance" `
        -Explication "Désactive la génération de noms de fichiers courts au format DOS 8.3 sur le système de fichiers NTFS. Améliore les performances de lecture/écriture, surtout dans les répertoires contenant un très grand nombre de fichiers." {
        Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "NtfsDisable8dot3NameCreation" -Value 1
    }

    Fin-De-Menu -RedemarrerExplorateur
}

function Test-SanteReseau {
    # Mesure la santé de la connexion réseau (ping, DNS, et réglages TCP/IP).
    $res = @{
        PingMs = -1
        DnsOk = $false
        NetworkThrottlingIndex = $null
        SystemResponsiveness = $null
    }

    try {
        $ping = New-Object System.Net.NetworkInformation.Ping
        $reply = $ping.Send("8.8.8.8", 2000)
        if ($reply.Status -eq 'Success') {
            $res.PingMs = $reply.RoundtripTime
        }
    } catch { }

    try {
        $ip = [System.Net.Dns]::GetHostAddresses("www.microsoft.com")
        if ($ip.Count -gt 0) { $res.DnsOk = $true }
    } catch { }

    try {
        $profil = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile"
        $p = Get-ItemProperty -Path $profil -ErrorAction SilentlyContinue
        $res.NetworkThrottlingIndex = $p.NetworkThrottlingIndex
        $res.SystemResponsiveness = $p.SystemResponsiveness
    } catch { }

    $pingDisplay = if ($res.PingMs -ge 0) { "$($res.PingMs)" } else { "ÉCHEC" }
    $niveauPing = if ($res.PingMs -ge 0 -and $res.PingMs -lt 100) { "OK" } else { "Avert" }
    Write-Etat ((T 'reseau.sante.ping') -f $pingDisplay) -Niveau $niveauPing
    return $res
}



