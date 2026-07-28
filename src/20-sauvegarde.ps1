# ------------------------------------------------------------------------------
# SAUVEGARDE DE L'ÉTAT D'ORIGINE
# Sans ça, "Annuler" ne peut que deviner les défauts de Windows. Ici on note la
# valeur exacte AVANT de la toucher, une seule fois (le tout premier état vu),
# pour pouvoir rendre la machine exactement telle qu'on l'a trouvée.
# ------------------------------------------------------------------------------
function Get-IdentiteMachine {
    # MachineGuid est unique par installation de Windows : c'est ce qui permet de
    # ne JAMAIS appliquer la sauvegarde d'un PC sur un autre.
    $guid = (Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Cryptography" -Name MachineGuid -ErrorAction SilentlyContinue).MachineGuid
    if (-not $guid) { $guid = "$((Get-CimInstance Win32_ComputerSystemProduct -ErrorAction SilentlyContinue).UUID)" }
    if (-not $guid) { $guid = "inconnu-$env:COMPUTERNAME" }
    return [pscustomobject]@{ Nom = $env:COMPUTERNAME; Guid = "$guid" }
}

function Get-DossierDonnees {
    # %LOCALAPPDATA% EN PREMIER, le dossier du script seulement en secours.
    #
    # L'ordre était inverse, et il tenait tant que le script vivait à la racine du
    # projet. Depuis qu'il est CONSTRUIT dans dist\ -- un dossier explicitement
    # jetable et régénérable -- la sauvegarde y atterrissait : supprimer dist\
    # aurait détruit le seul moyen d'annuler exactement les tweaks. Une donnée
    # précieuse n'a rien à faire dans un dossier qu'on invite à supprimer.
    #
    # Garder la sauvegarde « près du script » pour la transporter n'apportait de
    # toute façon rien : elle est verrouillée par MachineGuid, donc inutilisable
    # sur une autre machine par construction.
    $candidats = @()
    if ($env:LOCALAPPDATA) { $candidats += (Join-Path $env:LOCALAPPDATA "MadTweak") }
    # Secours : $PSScriptRoot est VIDE si le script est collé dans une console ou
    # lancé via « irm ... | iex ». Et %LOCALAPPDATA% peut manquer sur un compte
    # système ou dans un environnement d'installation (WinPE).
    if ($PSScriptRoot) { $candidats += (Join-Path $PSScriptRoot "madtweak-donnees") }
    if ($env:TEMP) { $candidats += (Join-Path $env:TEMP "MadTweak") }

    foreach ($c in $candidats) {
        try {
            if (-not (Test-Path $c)) { New-Item -ItemType Directory -Path $c -Force -ErrorAction Stop | Out-Null }
            $sonde = Join-Path $c ".ecriture"
            [System.IO.File]::WriteAllText($sonde, "x")
            [System.IO.File]::Delete($sonde)
            return $c
        }
        catch { continue }
    }
    throw "Aucun dossier accessible en écriture pour la sauvegarde."
}

$script:Machine = Get-IdentiteMachine
$script:DossierDonnees = $null
$script:DossierCles = $null
$script:FichierSauvegarde = $null
$script:Sauvegarde = @{}
$script:SauvegardeActive = $true

function Initialize-Sauvegarde {
    $script:DossierDonnees = Get-DossierDonnees
    # Les clés entières ne tiennent pas dans le JSON : elles sont exportées ici en .reg.
    $script:DossierCles = Join-Path $script:DossierDonnees "cles-sauvegardees"
    if (-not (Test-Path $script:DossierCles)) { New-Item -ItemType Directory -Path $script:DossierCles -Force | Out-Null }
    # Le nom du fichier porte la machine : emporter le script sur une clé USB ne
    # peut donc pas mélanger les sauvegardes de deux PC différents.
    $court = if ($script:Machine.Guid.Length -ge 8) { $script:Machine.Guid.Substring(0, 8) } else { $script:Machine.Guid }
    $script:FichierSauvegarde = Join-Path $script:DossierDonnees "sauvegarde-$($script:Machine.Nom)-$court.json"
    $script:Sauvegarde = @{}

    if (Test-Path $script:FichierSauvegarde) {
        try {
            $json = Get-Content $script:FichierSauvegarde -Raw -Encoding UTF8 | ConvertFrom-Json
            # Double sécurité : on revérifie l'identité STOCKÉE dans le fichier.
            if ($json.Machine.Guid -ne $script:Machine.Guid) {
                Write-Etat "Sauvegarde ignorée : elle provient d'une AUTRE machine ($($json.Machine.Nom))." -Niveau Avert
                Write-Etat "Restaurer ses valeurs ici écraserait ce PC avec les réglages d'un autre. Une sauvegarde neuve sera créée." -Niveau Avert
                $script:FichierSauvegarde = Join-Path $script:DossierDonnees "sauvegarde-$($script:Machine.Nom)-$court-$(Get-Date -Format 'yyyyMMddHHmmss').json"
                return
            }
            foreach ($p in $json.Valeurs.PSObject.Properties) { $script:Sauvegarde[$p.Name] = $p.Value }
            Write-Etat "Sauvegarde de CE PC chargée : $($script:Sauvegarde.Count) valeur(s) d'origine mémorisée(s)." -Niveau Info
        }
        catch {
            Write-Etat "Sauvegarde illisible ($($_.Exception.Message)). Elle sera reconstruite." -Niveau Avert
            $script:Sauvegarde = @{}
        }
    }
    Write-Etat "Données de session : $script:DossierDonnees" -Niveau Info
}

function Write-Sauvegarde {
    try {
        [ordered]@{
            Machine = @{ Nom = $script:Machine.Nom; Guid = $script:Machine.Guid; OS = "$($script:InfosOS.DisplayVersion) build $($script:InfosOS.CurrentBuild)" }
            Ecrit   = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
            Valeurs = $script:Sauvegarde
        } | ConvertTo-Json -Depth 6 | Set-Content -Path $script:FichierSauvegarde -Encoding UTF8 -Force
    }
    catch { Write-Etat "Impossible d'écrire la sauvegarde : $($_.Exception.Message)" -Niveau Avert }
}

function Save-EtatAvant {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Name)
    if (-not $script:SauvegardeActive) { return }
    $cle = "$Path|$Name"
    # On ne réécrit JAMAIS une entrée : le premier état vu est le vrai état d'origine.
    if ($script:Sauvegarde.ContainsKey($cle)) { return }

    $entree = [ordered]@{ Path = $Path; Name = $Name; Existait = $false; Valeur = $null; Type = $null }
    if (Test-Path $Path) {
        try {
            $item = Get-Item -Path $Path
            if ($Name -eq "(default)" -or $Name -eq "") {
                $val = $item.GetValue("")
                if ($null -ne $val) {
                    $entree.Existait = $true
                    $entree.Valeur = $val
                    $entree.Type = "String"
                }
            }
            elseif ($Name -in $item.GetValueNames()) {
                $entree.Existait = $true
                $entree.Valeur = $item.GetValue($Name)
                $entree.Type = $item.GetValueKind($Name).ToString()
            }
        }
        catch { }
    }
    $script:Sauvegarde[$cle] = $entree
    Write-Sauvegarde
}

function ConvertTo-CheminNatif {
    # reg.exe ne comprend ni les lecteurs PowerShell (HKLM:\...) ni les chemins
    # qualifiés par le provider (Microsoft.PowerShell.Core\Registry::HKEY_...),
    # or les deux formes circulent dans ce script : les tweaks écrivent la
    # première, Get-ChildItem renvoie la seconde via .PSPath.
    param([Parameter(Mandatory)][string]$Path)
    $p = $Path -replace '^Microsoft\.PowerShell\.Core\\Registry::', ''
    $p = $p -replace '^HKLM:', 'HKEY_LOCAL_MACHINE'
    $p = $p -replace '^HKCU:', 'HKEY_CURRENT_USER'
    $p = $p -replace '^HKCR:', 'HKEY_CLASSES_ROOT'
    $p = $p -replace '^HKU:', 'HKEY_USERS'
    $p = $p -replace '^HKCC:', 'HKEY_CURRENT_CONFIG'
    if ($p -notmatch '^HKEY_') { throw "Chemin de registre non reconnu : $Path" }
    return $p
}

function Save-EtatCle {
    # Pendant qu'une VALEUR tient dans le JSON, une CLÉ entière et son arborescence
    # ne s'y prêtent pas. On l'exporte donc en .reg à côté du JSON, qui ne garde
    # que le pointeur. Sans ça, Remove-RegKey détruisait sans filet : la clé de
    # stratégie Windows Update et la CLSID du clic droit partaient définitivement,
    # et « Restauration EXACTE » ne pouvait pas les faire revenir.
    param([Parameter(Mandatory)][string]$Path)
    # Un tweak peut appeler Save-EtatCle directement (et pas seulement via
    # Remove-RegKey) : la garde de simulation doit donc être ici aussi, sinon une
    # simulation écrirait des .reg et polluerait le fichier de sauvegarde.
    if ($script:Simulation) { return }
    if (-not $script:SauvegardeActive) { return }
    $cle = "CLE|$Path"
    if ($script:Sauvegarde.ContainsKey($cle)) { return }

    $entree = [ordered]@{ Type = "CleRegistre"; Path = $Path; Existait = $false; Fichier = $null }
    if (Test-Path $Path) {
        $nom = "cle-" + ($Path -replace '[^A-Za-z0-9]', '_') + ".reg"
        # Un chemin de registre profond dépasse vite la limite de nom de fichier.
        if ($nom.Length -gt 150) { $nom = "cle-" + [System.IO.Path]::GetRandomFileName() + ".reg" }
        $fichier = Join-Path $script:DossierCles $nom
        $natif = ConvertTo-CheminNatif $Path
        reg.exe export "$natif" "$fichier" /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $fichier)) {
            throw "Impossible d'exporter la clé $Path (reg.exe a renvoyé $LASTEXITCODE). Sans cet export, la suppression serait irréversible : rien n'a été supprimé."
        }
        $entree.Existait = $true
        $entree.Fichier = $fichier
    }
    $script:Sauvegarde[$cle] = $entree
    Write-Sauvegarde
}

function Restore-UneEntree {
    # Restaure UNE entrée de sauvegarde (valeur, service ou clé entière). Renvoie 'R'
    # (remise) ou 'S' (retirée) ; lève en cas d'échec. Partagée par la restauration
    # complète ET la restauration sélective, pour que les deux se comportent à l'identique.
    param([Parameter(Mandatory)]$e)
    # Les entrées "Service" ne sont pas des valeurs de registre : Set-Service, pas Set-ItemProperty.
    if ($e.Type -eq "Service") {
        if (Get-Service -Name $e.Nom -ErrorAction SilentlyContinue) {
            Set-Service -Name $e.Nom -StartupType $e.Demarrage
            if ($e.Etat -eq "Running") { Start-Service -Name $e.Nom -ErrorAction SilentlyContinue }
        }
        return 'R'
    }
    # Les clés entières se restaurent depuis leur export .reg.
    if ($e.Type -eq "CleRegistre") {
        if (-not $e.Existait) {
            # La clé n'existait pas avant nous (cas du clic droit classique) : on la retire.
            if (Test-Path $e.Path) { Remove-Item -Path $e.Path -Recurse -Force }
            return 'S'
        }
        if (-not (Test-Path $e.Fichier)) { throw "Export introuvable : $($e.Fichier). La clé ne peut pas être restaurée." }
        # reg import FUSIONNE au lieu de remplacer : sans cette suppression préalable,
        # les valeurs ajoutées depuis l'export survivraient.
        if (Test-Path $e.Path) { Remove-Item -Path $e.Path -Recurse -Force }
        reg.exe import "$($e.Fichier)" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "reg import a renvoyé le code $LASTEXITCODE." }
        return 'R'
    }
    if ($e.Existait) {
        $valeur = $e.Valeur
        # Le JSON transforme un byte[] en tableau d'entiers : il faut le recaster.
        if ($e.Type -eq "Binary") { $valeur = [byte[]]@($valeur) }
        if (-not (Test-Path $e.Path)) { New-Item -Path $e.Path -Force | Out-Null }
        if ($e.Name -eq "(default)" -or $e.Name -eq "") { Set-Item -Path $e.Path -Value $valeur -Force }
        else { Set-ItemProperty -Path $e.Path -Name $e.Name -Value $valeur -Type $e.Type -Force }
        return 'R'
    }
    # La valeur n'existait pas avant nous : on la retire.
    if (Test-Path $e.Path) {
        if ($e.Name -eq "(default)" -or $e.Name -eq "") { Set-Item -Path $e.Path -Value "" -Force }
        else { Remove-ItemProperty -Path $e.Path -Name $e.Name -Force -ErrorAction SilentlyContinue | Out-Null }
    }
    return 'S'
}

function Restore-Sauvegarde {
    if ($script:Simulation) {
        Write-Simu "restaurerait $($script:Sauvegarde.Count) valeur(s)/service(s) à leur état d'origine"
        return
    }
    if ($script:Sauvegarde.Count -eq 0) {
        throw "Aucune sauvegarde disponible : ce script n'a encore rien modifié sur cette machine (ou le fichier a été supprimé)."
    }
    # Pendant la restauration, on ne veut évidemment pas re-sauvegarder.
    $script:SauvegardeActive = $false
    $restaurees = 0; $supprimees = 0; $echecs = 0
    try {
        foreach ($cle in @($script:Sauvegarde.Keys)) {
            $e = $script:Sauvegarde[$cle]
            try {
                if ((Restore-UneEntree $e) -eq 'R') { $restaurees++ } else { $supprimees++ }
            }
            catch {
                Write-Etat "Échec sur $($e.Path)\$($e.Name) : $($_.Exception.Message)" -Niveau Echec
                $echecs++
            }
        }
    }
    finally { $script:SauvegardeActive = $true }

    Write-Etat "$restaurees valeur(s) remise(s) à leur état d'origine, $supprimees retirée(s), $echecs échec(s)." -Niveau Info
    if ($echecs -gt 0) { throw "$echecs valeur(s) n'ont pas pu être restaurées." }
}

function Get-EntreesSauvegarde {
    # Liste lisible des modifications sauvegardées, pour la restauration SÉLECTIVE :
    # clé interne + description + valeur d'avant.
    $res = @()
    foreach ($cle in @($script:Sauvegarde.Keys | Sort-Object)) {
        $e = $script:Sauvegarde[$cle]
        $desc = switch ($e.Type) {
            "Service" { "Service : $($e.Nom)" }
            "CleRegistre" { "Clé : $($e.Path)" }
            default {
                $court = "$($e.Path)" -replace '^HKEY_CURRENT_USER|^HKCU:', 'HKCU' -replace '^HKEY_LOCAL_MACHINE|^HKLM:', 'HKLM'
                "$court\$($e.Name)"
            }
        }
        $avant = if ($e.Type -eq 'Service') { "$($e.Demarrage)" } elseif ($e.Existait) { "$($e.Valeur)" } else { "(absente)" }
        $res += [pscustomobject]@{ Cle = $cle; Desc = $desc; Avant = $avant }
    }
    return $res
}

function Restore-SauvegardePartielle {
    # Restaure UNIQUEMENT les entrées de sauvegarde listées (restauration sélective).
    param([Parameter(Mandatory)][string[]]$Cles)
    if ($script:Simulation) { Write-Simu "restaurerait $(@($Cles).Count) entrée(s) sélectionnée(s)"; return @{ OK = 0; Echecs = 0 } }
    $script:SauvegardeActive = $false
    $ok = 0; $echecs = 0
    try {
        foreach ($cle in $Cles) {
            if (-not $script:Sauvegarde.ContainsKey($cle)) { continue }
            try { Restore-UneEntree $script:Sauvegarde[$cle] | Out-Null; $ok++ }
            catch { Write-Etat "Échec sur $cle : $($_.Exception.Message)" -Niveau Echec; $echecs++ }
        }
    }
    finally { $script:SauvegardeActive = $true }
    Write-Etat "$ok entrée(s) restaurée(s), $echecs échec(s)." -Niveau Info
    return @{ OK = $ok; Echecs = $echecs }
}

function Backup-PositionsIconesBureau {
    # Sauvegarde l'agencement binaire des icônes du bureau dans le dossier de données local.
    $keyPath = "HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop"
    $fichier = Join-Path $script:DossierDonnees "bureau-icones.bin"

    if (-not (Test-Path $keyPath)) { return $false }
    try {
        $props = Get-ItemProperty -Path $keyPath -ErrorAction Stop
        $val = $null
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -like "ItemPos*") { $val = $p.Value; break }
        }
        if ($val) {
            if (-not (Test-Path $script:DossierDonnees)) { New-Item -ItemType Directory -Path $script:DossierDonnees -Force | Out-Null }
            [System.IO.File]::WriteAllBytes($fichier, [byte[]]$val)
            Write-Etat (T 'icones.bureau.sauvegarde') -Niveau OK
            return $true
        }
    } catch { }
    return $false
}

function Restore-PositionsIconesBureau {
    # Restaure l'agencement binaire des icônes du bureau.
    $keyPath = "HKCU:\Software\Microsoft\Windows\Shell\Bags\1\Desktop"
    $fichier = Join-Path $script:DossierDonnees "bureau-icones.bin"

    if (-not (Test-Path $fichier) -or -not (Test-Path $keyPath)) { return $false }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($fichier)
        $props = Get-ItemProperty -Path $keyPath -ErrorAction Stop
        foreach ($p in $props.PSObject.Properties) {
            if ($p.Name -like "ItemPos*") {
                Set-ItemProperty -Path $keyPath -Name $p.Name -Value $bytes -ErrorAction SilentlyContinue
            }
        }
        Write-Etat (T 'icones.bureau.restauree') -Niveau OK
        return $true
    } catch { }
    return $false
}


