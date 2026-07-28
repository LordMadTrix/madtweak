# ------------------------------------------------------------------------------
# LOGICIELS EXTRA (winget)
# ------------------------------------------------------------------------------

# Le catalogue vit au niveau du module, et non dans la fonction : le menu « Clé
# d'installation » propose exactement les mêmes applications, et deux listes qui
# dérivent l'une de l'autre finiraient par ne plus dire la même chose.
$script:CatalogueApps = [ordered]@{
    # Navigateurs
    "Google Chrome"       = "Google.Chrome"
    "Mozilla Firefox"     = "Mozilla.Firefox"
    "Brave"               = "Brave.Brave"
    # Essentiels
    "7-Zip"               = "7zip.7zip"
    "VLC Media Player"    = "VideoLAN.VLC"
    "Notepad++"           = "Notepad++.Notepad++"
    "PowerToys"           = "Microsoft.PowerToys"
    "Windows Terminal"    = "Microsoft.WindowsTerminal"
    # Communication et jeu
    "Discord"             = "Discord.Discord"
    "Steam"               = "Valve.Steam"
    # --- Matériel / gaming (optionnel) : monitoring, overlay, pilotes ---
    # G-Helper : le SEUL moyen de piloter ventilateurs et modes Turbo/Silencieux ASUS
    # ROG (le driver ASUS ignore ces commandes hors de son écosystème). Léger, libre.
    "G-Helper (ventilos + modes ASUS ROG)"           = "seerge.g-helper"
    "HWiNFO (vraies températures / capteurs)"        = "REALiX.HWiNFO"
    "MSI Afterburner (courbe ventilo GPU)"           = "Guru3D.Afterburner"
    "RivaTuner Statistics Server (overlay FPS)"      = "Guru3D.RTSS"
    "Display Driver Uninstaller (MAJ pilote propre)" = "Wagnardsoft.DisplayDriverUninstaller"
    "Nilesoft Shell (menu clic droit moderne)"       = "Nilesoft.Shell"
    # Développement
    "Visual Studio Code"  = "Microsoft.VisualStudioCode"
    "Git"                 = "Git.Git"
    "PowerShell 7"        = "Microsoft.PowerShell"
    # Utilitaires
    "ShareX (captures)"   = "ShareX.ShareX"
    "Everything (recherche instantanée)" = "voidtools.Everything"
    "qBittorrent"         = "qBittorrent.qBittorrent"
    "Adobe Acrobat Reader" = "Adobe.Acrobat.Reader.64-bit"
}

function Menu-Logiciels-Extra {
    Start-Menu -Titre "LOGICIELS EXPRESS (via winget)"

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        Write-Etat "winget est introuvable. Installe 'Programme d'installation d'application' depuis le Microsoft Store." -Niveau Echec
        if (-not (Test-SansInteraction)) { Read-Host "`nAppuie sur Entrée pour revenir au menu principal" }
        return
    }

    $Catalogue = $script:CatalogueApps

    # --- Cas "nouveau PC" : transporter sa liste d'apps d'une machine à l'autre ---

    $fichierApps = Join-Path $script:DossierDonnees "mes-apps.json"

    Invoke-Tweak "EXPORTER la liste des apps installées sur ce PC (pour la réinstaller ailleurs) ?" -Cle "winget-export" `
        -Explication "Exporte la liste de toutes vos applications actuellement installées au format JSON dans le dossier de données." {
        Invoke-Action "exporterait la liste des apps vers $fichierApps" {
            winget export -o $fichierApps --accept-source-agreements 2>&1 | Out-Null
            if (-not (Test-Path $fichierApps)) { throw "winget n'a produit aucun fichier." }
            $n = (Get-Content $fichierApps -Raw | ConvertFrom-Json).Sources.Packages.Count
            Write-Etat "$n app(s) exportée(s) vers $fichierApps" -Niveau OK
            Write-Etat "Copie ce fichier sur le nouveau PC, à côté du script, puis utilise l'import." -Niveau Info
        }
    }

    Invoke-Tweak "IMPORTER et réinstaller les apps depuis un export précédent ?" -Cle "winget-import" `
        -Explication "Importe et réinstalle automatiquement vos applications à partir d'un fichier mes-apps.json d'export précédent." {
        if (-not (Test-Path $fichierApps)) {
            throw "Aucun fichier $fichierApps trouvé. Fais d'abord un export sur l'ancien PC, puis copie le fichier ici."
        }
        $n = (Get-Content $fichierApps -Raw | ConvertFrom-Json).Sources.Packages.Count
        Invoke-Action "réinstallerait les $n app(s) listées dans $fichierApps" {
            # --ignore-unavailable : une app absente du dépôt ne doit pas tout arrêter.
            winget import -i $fichierApps --accept-source-agreements --accept-package-agreements --ignore-unavailable
            Write-Etat "Import terminé (code winget : $LASTEXITCODE)." -Niveau Info
        }
    }

    Invoke-Tweak "Mettre à jour TOUTES les apps installées (winget upgrade --all) ?" -Cle "winget-upgrade-all" `
        -Explication "Met à jour automatiquement toutes les applications installées sur la machine à l'aide de winget." {
        Invoke-Action "mettrait à jour toutes les apps via winget" {
            winget upgrade --all --silent --accept-source-agreements --accept-package-agreements
            Write-Etat "Mise à jour terminée (code winget : $LASTEXITCODE)." -Niveau Info
        }
    }

    if (-not (Test-SansInteraction)) {
        Write-Host ""
        Write-Host "  --- Ou installer à la carte : ---" -ForegroundColor DarkGray
        Write-Host ""
    }

    foreach ($nom in $Catalogue.Keys) {
        $id = $Catalogue[$nom]
        $cleApp = "winget-" + ($id -replace '[^a-zA-Z0-9]', '-').ToLower()
        # Ces 23 entrées sont GÉNÉRÉES : leur libellé ne dépend que du nom de l'appli.
        # Traduire le gabarit une fois vaut mieux que 23 entrées dans la table.
        $titreApp = if ($script:LangueActive -eq 'fr') { "Installer $nom ?" } else { "Install $nom?" }
        $explApp = if ($script:LangueActive -eq 'fr') { "Télécharge et installe le logiciel $nom via winget." }
        else { "Downloads and installs $nom using winget." }
        Invoke-Tweak $titreApp -Cle $cleApp -Explication $explApp {
            # V3 : sans --accept-*-agreements, winget pouvait rester bloqué sur un prompt,
            # et sans "-e --id" il pouvait installer un paquet homonyme.
            Invoke-Action "installerait $nom via winget (id : $id)" {
                winget install -e --id $id --silent --accept-source-agreements --accept-package-agreements | Out-Null
                # 0 = ok, -1978335189 = déjà installé / rien à faire
                if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) {
                    throw "winget a renvoyé le code $LASTEXITCODE."
                }
            }
        }.GetNewClosure()
    }

    Fin-De-Menu
}

function Export-ListeApplicationsWinget {
    # Exporte la liste des applications actuellement installées via winget au format JSON.
    param([string]$CheminSortieJson)
    if (-not $CheminSortieJson) { $CheminSortieJson = Join-Path $script:DossierDonnees "mes-apps.json" }

    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
        throw "winget est introuvable."
    }

    $dir = Split-Path $CheminSortieJson -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    winget export -o $CheminSortieJson --accept-source-agreements 2>&1 | Out-Null
    if (-not (Test-Path $CheminSortieJson)) { throw "winget n'a produit aucun fichier." }

    $count = 0
    try {
        $json = Get-Content $CheminSortieJson -Raw | ConvertFrom-Json
        $count = $json.Sources.Packages.Count
    } catch { }

    Write-Etat ((T 'apps.export.ok') -f $CheminSortieJson, $count) -Niveau OK
    return $CheminSortieJson
}

function Import-ListeApplicationsWinget {
    # Importe et réinstalle automatiquement la liste d'applications depuis un fichier JSON.
    param([string]$CheminJsonSource)
    if (-not $CheminJsonSource) { $CheminJsonSource = Join-Path $script:DossierDonnees "mes-apps.json" }

    if (-not (Test-Path $CheminJsonSource)) { throw "Fichier JSON introuvable : $CheminJsonSource" }
    if (-not (Get-Command winget -ErrorAction SilentlyContinue)) { throw "winget est introuvable." }

    $count = 0
    try {
        $json = Get-Content $CheminJsonSource -Raw | ConvertFrom-Json
        $count = $json.Sources.Packages.Count
    } catch { }

    winget import -i $CheminJsonSource --accept-source-agreements --accept-package-agreements --ignore-unavailable
    Write-Etat ((T 'apps.import.ok') -f $CheminJsonSource, $count) -Niveau OK
    return $LASTEXITCODE
}


