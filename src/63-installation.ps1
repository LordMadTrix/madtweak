# ------------------------------------------------------------------------------
# CLÉ D'INSTALLATION — génération d'un autounattend.xml
#
# Windows ne peut PAS être redistribué : la licence Microsoft l'interdit. MadTweak
# ne fournit donc aucune ISO. Il génère le fichier de réponses que l'utilisateur
# dépose sur SA clé, à côté de l'ISO officielle qu'il a téléchargée lui-même.
#
# Même logique que les fonds d'écran : on GÉNÈRE, on n'embarque pas. Le fichier
# produit est du texte, il reste lisible et vérifiable avant d'être utilisé.
#
# WINDOWS 10 ET 11 : le schema « unattend » est le meme pour les deux, il n'a pas
# change depuis Vista. Les contournements TPM/SecureBoot sont des ecritures de
# registre INERTES sous Windows 10 (sans effet, pas en echec). En revanche le NOM
# de l'edition dans l'image differe (« Windows 11 Pro » / « Windows 10 Pro ») :
# c'est la seule vraie divergence, d'ou le parametre -Version.
#
# Le compte local est cree par le bloc LocalAccount du passage oobeSystem, qui est
# le chemin DOCUMENTE par Microsoft. BypassNRO n'est qu'une ceinture-bretelles :
# Microsoft a retire le SCRIPT bypassnro.cmd en 24H2, mais pas la valeur de
# registre, qui marche toujours. Ce n'est pas elle qui cree le compte local.
#
# LIMITE CONNUE, WINDOWS 11 24H2 ET 25H2 : le nouvel installeur (SetupPrep.exe,
# dit « ConX ») lit le passage windowsPE — disque, edition, langue — mais ignore
# souvent oobeSystem. Le compte local n'est alors pas cree et l'OOBE repose ses
# questions. D'ou la recopie du fichier vers C:\Windows\Panther\unattend.xml en
# specialize, qui est le chemin de relecture historique. Ce contournement vient de
# la pratique, pas de la documentation Microsoft : il ne peut pas etre garanti.
# Windows 10 et Windows 11 jusqu'a 23H2 utilisent l'ancien installeur et ne sont
# pas concernes.
#
# Le fichier n'installe pas les tweaks : au premier démarrage, il APPELLE MadTweak
# avec un profil. Les 155 tweaks, la sauvegarde et l'annulation exacte continuent
# donc de fonctionner à l'identique — rien n'est dupliqué.
# ------------------------------------------------------------------------------

function Get-EditionsImage {
    <#
        Lit les éditions RÉELLEMENT contenues dans une image Windows.
        Accepte une .iso (montée puis démontée), un install.wim ou un install.esd.
        Retourne une liste de @{ Index; Nom }. Ne modifie rien.

        Pourquoi : jusqu'ici, choisir une édition revenait à parier. Un nom absent
        de l'image fait échouer l'installation, et on ne le découvre que devant la
        machine. Or l'image, on peut la LIRE. Même principe que partout ailleurs
        dans cet outil : on mesure au lieu de deviner.
    #>
    param([Parameter(Mandatory)][string]$Chemin)

    if (-not (Test-Path -LiteralPath $Chemin)) { throw "Fichier introuvable : $Chemin" }
    $ext = [System.IO.Path]::GetExtension($Chemin).ToLowerInvariant()
    if ($ext -notin '.iso', '.wim', '.esd') {
        throw "Format non reconnu ($ext). Attendu : .iso, .wim ou .esd."
    }

    $monte = $null
    try {
        $imagePath = $Chemin
        if ($ext -eq '.iso') {
            # Montage en LECTURE SEULE : on inspecte le fichier de quelqu'un d'autre,
            # on n'y touche pas. Le démontage est dans le finally, sans quoi une ISO
            # resterait montée après la moindre erreur.
            $monte = Mount-DiskImage -ImagePath $Chemin -StorageType ISO -Access ReadOnly -PassThru -ErrorAction Stop
            $lettre = ($monte | Get-Volume).DriveLetter
            if (-not $lettre) { throw "L'image a été montée mais aucune lettre de lecteur n'a été attribuée." }
            $candidats = @("${lettre}:\sources\install.wim", "${lettre}:\sources\install.esd")
            $imagePath = $candidats | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if (-not $imagePath) {
                throw "Ni sources\install.wim ni sources\install.esd dans cette image : ce n'est pas un support d'installation Windows."
            }
        }

        try { $images = @(Get-WindowsImage -ImagePath $imagePath -ErrorAction Stop) }
        catch {
            # Cas de loin le plus fréquent, et le message natif ne le dit pas clairement.
            if ($_.Exception.Message -match 'l.vation|elevation|denied|refus') {
                throw "La lecture d'une image Windows exige des droits administrateur. Relance MadTweak en administrateur."
            }
            throw "Lecture de l'image impossible : $($_.Exception.Message)"
        }

        $sortie = New-Object System.Collections.Generic.List[object]
        foreach ($im in $images) {
            $sortie.Add([pscustomobject]@{ Index = $im.ImageIndex; Nom = $im.ImageName })
        }
        return $sortie
    }
    finally {
        if ($monte) { try { Dismount-DiskImage -ImagePath $Chemin | Out-Null } catch { } }
    }
}

function Get-ClesInstallation {
    <#
        Liste les volumes amovibles, en signalant ceux qui portent déjà un support
        d'installation Windows (présence de setup.exe à la racine). Lecture seule.
    #>
    $liste = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($v in (Get-Volume -ErrorAction Stop | Where-Object { $_.DriveLetter -and $_.DriveType -eq 'Removable' })) {
            $racine = "$($v.DriveLetter):\"
            $liste.Add([pscustomobject]@{
                    Lettre    = $v.DriveLetter
                    Nom       = $v.FileSystemLabel
                    Go        = [math]::Round($v.Size / 1GB, 1)
                    EstSupport = (Test-Path (Join-Path $racine 'setup.exe'))
                })
        }
    }
    catch { }
    return $liste
}

function Copy-FichiersVersCle {
    <#
        Dépose le fichier de réponses — et MadTweak lui-même si un profil est prévu —
        à la RACINE d'une clé d'installation déjà préparée. Retourne la liste de ce
        qui a été copié.

        Cette fonction ne formate rien, n'efface rien et n'écrit pas d'image : elle
        copie deux fichiers. L'écriture de l'ISO sur la clé reste le travail de Rufus
        ou du Media Creation Tool, et il n'y a aucune raison de la réimplémenter.

        Le garde-fou du setup.exe n'est pas une formalité : sans lui, une lettre de
        lecteur mal saisie déposerait ces fichiers à la racine d'un disque de données,
        voire de C:, où un autounattend.xml traînant n'a rien à faire.
    #>
    param(
        [Parameter(Mandatory)][string]$Lettre,
        [Parameter(Mandatory)][string]$CheminXml,
        [string]$CheminMadTweak,
        [switch]$Forcer
    )

    $racine = ($Lettre.TrimEnd(':', '\')) + ":\"
    if (-not (Test-Path $racine)) { throw "Le lecteur $racine n'existe pas." }
    if (-not (Test-Path $CheminXml)) { throw "Fichier de réponses introuvable : $CheminXml" }

    if (-not (Test-Path (Join-Path $racine 'setup.exe')) -and -not $Forcer) {
        throw "Aucun setup.exe à la racine de $racine : ce lecteur ne ressemble pas à une clé d'installation Windows. Prépare-la d'abord avec Rufus ou le Media Creation Tool."
    }

    $copies = New-Object System.Collections.Generic.List[string]
    $cible = Join-Path $racine 'autounattend.xml'
    Copy-Item -LiteralPath $CheminXml -Destination $cible -Force -ErrorAction Stop
    $copies.Add($cible)

    if ($CheminMadTweak) {
        if (-not (Test-Path $CheminMadTweak)) { throw "MadTweak.ps1 introuvable : $CheminMadTweak" }
        $cible2 = Join-Path $racine 'MadTweak.ps1'
        Copy-Item -LiteralPath $CheminMadTweak -Destination $cible2 -Force -ErrorAction Stop
        $copies.Add($cible2)
    }

    # On relit ce qu'on vient de deposer : une copie vers une cle defaillante ou
    # pleine peut « reussir » et produire un fichier tronque. Le fichier de reponses
    # d'une machine qu'on va formater merite cette verification.
    $pbs = Test-AutounattendXml -Chemin $cible
    if ($pbs.Count -gt 0) {
        throw "Le fichier copié sur $racine est illisible ou incomplet : $($pbs[0])"
    }

    return $copies
}

function Get-DisquesUSB {
    # Ne renvoie QUE des disques USB, jamais le disque système. C'est la source de
    # la liste proposée à l'utilisateur : ce qui n'apparaît pas ici ne peut pas
    # être effacé par erreur.
    $liste = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($d in (Get-Disk -ErrorAction Stop | Where-Object { $_.BusType -eq 'USB' })) {
            if ($d.IsBoot -or $d.IsSystem) { continue }
            $vols = @(Get-Partition -DiskNumber $d.Number -ErrorAction SilentlyContinue |
                Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter)
            $liste.Add([pscustomobject]@{
                    Numero  = $d.Number
                    Nom     = $d.FriendlyName
                    Go      = [math]::Round($d.Size / 1GB, 1)
                    Lettres = (($vols | ForEach-Object { "$($_.DriveLetter):" }) -join ' ')
                    Contenu = (($vols | ForEach-Object { $_.FileSystemLabel }) -join ' ')
                })
        }
    }
    catch { }
    return $liste
}

function Test-VitesseCleUSB {
    # Effectue un test d'écriture rapide (64 Mo) pour mesurer le débit du lecteur USB.
    param([Parameter(Mandatory)][string]$Lettre)
    $racine = ($Lettre.TrimEnd(':', '\')) + ":\"
    if (-not (Test-Path $racine)) { throw "Lecteur introuvable : $racine" }

    $fichier = Join-Path $racine "madtweak-speedtest.tmp"
    if ($racine.StartsWith("C:", [System.StringComparison]::OrdinalIgnoreCase) -and $env:TEMP) {
        $fichier = Join-Path $env:TEMP "madtweak-speedtest.tmp"
    }
    if (Test-Path $fichier) { Remove-Item $fichier -Force -ErrorAction SilentlyContinue }


    try {
        Write-Etat (T 'install.vitesse.debut') -Niveau Info
        $tailleMo = 64
        $buffer = New-Object byte[] (1MB)
        (New-Object Random).NextBytes($buffer)

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $fs = [System.IO.File]::Create($fichier)
        try {
            for ($i = 0; $i -lt $tailleMo; $i++) {
                $fs.Write($buffer, 0, $buffer.Length)
            }
            $fs.Flush()
        } finally {
            $fs.Dispose()
        }
        $sw.Stop()

        $secondes = [math]::Max($sw.Elapsed.TotalSeconds, 0.001)
        $debitMoS = [math]::Round($tailleMo / $secondes, 1)

        if (Test-Path $fichier) { Remove-Item $fichier -Force -ErrorAction SilentlyContinue }

        $performant = ($debitMoS -ge 5.0)
        if ($performant) {
            Write-Etat ((T 'install.vitesse.ok') -f $debitMoS) -Niveau OK
        } else {
            Write-Etat ((T 'install.vitesse.lente') -f $debitMoS) -Niveau Avert
        }

        return @{
            MoParSeconde = $debitMoS
            EstPerformant = $performant
        }
    } catch {
        if (Test-Path $fichier) { Remove-Item $fichier -Force -ErrorAction SilentlyContinue }
        return @{ MoParSeconde = 0; EstPerformant = $false }
    }
}

function Get-HashIsoWindows {
    # Calcule l'empreinte SHA-256 d'un fichier ISO.
    param([Parameter(Mandatory)][string]$CheminIso)
    if (-not (Test-Path -LiteralPath $CheminIso)) { throw "Fichier ISO introuvable : $CheminIso" }

    try {
        Write-Etat (T 'install.hash.calcul') -Niveau Info
        $hashObj = Get-FileHash -LiteralPath $CheminIso -Algorithm SHA256 -ErrorAction Stop
        $hashStr = $hashObj.Hash
        Write-Etat ((T 'install.hash.ok') -f $hashStr) -Niveau OK
        return $hashStr
    } catch {
        Write-Etat "Erreur calcul SHA-256 : $($_.Exception.Message)" -Niveau Avert
        return $null
    }
}

function Convert-ImageVersWim {
    <#
        Convertit une image .esd en .wim en n'en extrayant qu'UNE édition.
        Retourne le chemin du .wim produit. Ne touche pas à la source.

        Pourquoi cette fonction existe seule : c'est l'étape longue et risquée de
        la préparation d'une clé, et elle était jusqu'ici enfouie dans une fonction
        destructive — donc impossible à éprouver sans effacer un disque. Ici, elle
        s'exécute seule, en lecture sur la source et en écriture dans un dossier
        temporaire.

        Un .esd ne se découpe pas ; un .wim, si. C'est le seul chemin pour poser
        une image de plus de 4 Go sur du FAT32, seul système de fichiers que tout
        micrologiciel UEFI sait lire au démarrage.

        Attendre un fichier plus petit serait une erreur : le .esd est compressé
        en LZMS, plus agressif que le LZX d'un .wim. La conversion FAIT GROSSIR le
        fichier — 6,57 Go donnent 9,02 Go sur une image mesurée. N'extraire qu'une
        édition compense quand l'image en contient plusieurs, mais beaucoup n'en
        contiennent qu'une : ne pas compter dessus.
    #>
    param(
        [Parameter(Mandatory)][string]$CheminImage,
        [string]$Edition = '',
        # Clé produit. Sans elle, l'installeur affiche son écran « Clé de produit »
        # et il faut cliquer « Je n'ai pas de clé » — constaté sur un vrai essai.
        # La doc interdit une valeur VIDE (« does not support empty elements ») :
        # on omet donc l'élément Key entièrement plutôt que d'en écrire un vide,
        # et WillShowUI=Never demande à Windows de ne pas poser la question.
        [string]$CleProduit = '',
        [string]$DossierSortie
    )

    if (-not (Test-Path -LiteralPath $CheminImage)) { throw "Image introuvable : $CheminImage" }

    $images = @(Get-WindowsImage -ImagePath $CheminImage -ErrorAction Stop)
    $index = 1
    if ($Edition) {
        $trouve = $images | Where-Object { $_.ImageName -eq $Edition } | Select-Object -First 1
        if (-not $trouve) {
            throw "L'édition « $Edition » n'est pas dans cette image. Présentes : $(($images.ImageName) -join ' | ')."
        }
        $index = $trouve.ImageIndex
    }
    else {
        Write-Etat "Aucune édition précisée : l'index 1 (« $($images[0].ImageName) ») sera extrait." -Niveau Avert
    }
    $nomGarde = ($images | Where-Object { $_.ImageIndex -eq $index }).ImageName

    if (-not $DossierSortie) {
        $DossierSortie = Join-Path $env:TEMP "madtweak-image-$([guid]::NewGuid().ToString('N').Substring(0,8))"
    }
    if (-not (Test-Path $DossierSortie)) { New-Item -ItemType Directory -Path $DossierSortie -Force | Out-Null }

    # La place se vérifie AVANT, pas au bout de sept minutes de travail.
    #
    # Et il en faut PLUS que la taille de la source : un .esd est compressé en LZMS,
    # bien plus agressif que le LZX maximal d'un .wim. La conversion GROSSIT le
    # fichier. Mesuré sur une image réelle : 6,57 Go de .esd donnent 9,02 Go de
    # .wim, soit +37 %. Le facteur 2 laisse la marge nécessaire — une première
    # version de ce contrôle comparait à la taille de la source et aurait laissé
    # démarrer une conversion vouée à finir sur un disque plein.
    $taille = (Get-Item $CheminImage).Length
    $requis = $taille * 2
    $libre = (Get-PSDrive -Name ($DossierSortie.Substring(0, 1))).Free
    if ($libre -lt $requis) {
        throw "Place insuffisante sur $($DossierSortie.Substring(0,2)) : $([math]::Round($libre/1GB,1)) Go libres, $([math]::Round($requis/1GB,1)) Go nécessaires (le .wim produit est plus gros que le .esd source)."
    }

    $sortie = Join-Path $DossierSortie 'install.wim'
    Write-Etat "Conversion vers .wim, édition « $nomGarde » (compter 5 à 15 minutes selon le disque)..." -Niveau Info
    Export-WindowsImage -SourceImagePath $CheminImage -SourceIndex $index `
        -DestinationImagePath $sortie -CompressionType Max -ErrorAction Stop | Out-Null
    Write-Etat "Converti : $([math]::Round((Get-Item $sortie).Length/1GB,2)) Go (source : $([math]::Round($taille/1GB,2)) Go)." -Niveau OK
    return $sortie
}

function Get-OutilsSupport {
    # Outils officiels ou reconnus pour obtenir une ISO et ecrire une cle.
    # MadTweak ne telecharge aucune image lui-meme : il installe l'outil qui le
    # fait, et laisse l'utilisateur decider.
    return [ordered]@{
        "Media Creation Tool (Microsoft, Windows 11)" = "Microsoft.MediaCreationTool"
        "Media Creation Tool (Microsoft, Windows 10)" = "Microsoft.MediaCreationTool.Windows10"
        "Rufus (ecrit la cle, sait aussi telecharger)" = "Rufus.Rufus"
        "Ventoy (une cle, plusieurs ISO)"             = "Ventoy.Ventoy"
    }
}

function Start-MediaCreationTool {
    <#
        Lance le Media Creation Tool, SANS AUCUN COMMUTATEUR.

        AVERTISSEMENT, appris a la dure : les commutateurs qu'on trouve partout
        sur le web — /Eula Accept /Retail /MediaArch /MediaLangCode /MediaEdition —
        ne mettent PAS l'outil en mode « creation de support ». Ils le basculent
        en mode MISE A NIVEAU DE LA MACHINE COURANTE. Essaye sur une machine
        reelle : l'outil ouvre « Configuration de Windows 11 » et reclame une cle
        produit pour installer Windows sur le PC ou on se trouve.

        Sur un outil dont le role est de preparer une cle pour une AUTRE machine,
        declencher par megarde la mise a niveau de celle-ci serait la pire des
        surprises. On lance donc l'assistant nu, et l'utilisateur choisit
        « Creer un support d'installation » puis « Fichier ISO » lui-meme.
    #>
    $chemins = @(
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Microsoft.MediaCreationTool_Microsoft.Winget.Source_8wekyb3d8bbwe\MediaCreationTool.exe'),
        (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\MediaCreationTool.exe')
    )
    $exe = $chemins | Where-Object { Test-Path $_ } | Select-Object -First 1
    if (-not $exe) {
        $c = Get-Command MediaCreationTool -ErrorAction SilentlyContinue
        if ($c) { $exe = $c.Source }
    }
    if (-not $exe) {
        Write-Etat "Media Creation Tool introuvable. Installe-le d'abord depuis ce menu." -Niveau Avert
        return $false
    }

    Write-Etat "Lancement du Media Creation Tool." -Niveau Info
    Write-Etat "Choisis « Creer un support d'installation », PAS la mise a niveau de ce PC." -Niveau Avert
    Write-Etat "Puis « Fichier ISO », et note ou tu l'enregistres." -Niveau Info
    Start-Process -FilePath $exe | Out-Null
    return $true
}

function Get-LienIsoWindows {
    <#
        Obtient un lien de telechargement OFFICIEL d'une ISO Windows, depuis les
        serveurs de Microsoft, en refaisant les memes appels que sa propre page
        de telechargement. Retourne @{ Nom; Uri; Langue }.

        Comment ca marche, parce que ce n'est pas evident :

        La page publique ne contient aucun lien direct. Elle fait travailler le
        navigateur en quatre temps. On enregistre une session aupres de
        vlscppe.microsoft.com, qui pose deux cookies de reconnaissance. On
        demande ensuite mdt.js, un fragment de JavaScript contenant trois
        valeurs a usage unique : un jeton « w », un horodatage serveur
        « rticks » et un identifiant client. La page les renvoie a
        ov-df.microsoft.com dans une iframe invisible : c'est cette etape qui
        valide la session. Alors seulement l'API accepte de rendre la liste des
        langues, puis les liens.

        Sans cette sequence, l'API repond « Sentinel marked this request as
        rejected ». C'est ce qui arrive quand on attaque directement le dernier
        appel, et c'est exactement l'erreur par laquelle j'ai commence.

        Deux pieges m'ont coute plusieurs essais, notes ici pour la prochaine
        fois. « CustomerId » n'est PAS l'org_id des cookies mais l'instanceId.
        Et « rticks » n'est pas un parametre d'URL dans le JavaScript mais une
        concatenation — &rticks=" + 1785204326859 — donc une expression qui
        cherche un parametre d'URL revient vide, sans erreur, et la session
        n'est jamais validee.

        FRAGILITE ASSUMEE : rien de tout ceci n'est documente par Microsoft, qui
        peut le changer sans preavis. La fonction echoue alors proprement, avec
        un message explicite, et le menu propose l'outil officiel en repli. Elle
        ne contourne aucune protection de contenu : elle demande, comme le
        ferait un navigateur, une image que Microsoft distribue gratuitement et
        publiquement.
    #>
    param(
        [ValidateSet('11', '10')][string]$Version = '11',
        [string]$Langue = 'Francais',
        [ValidateSet('x64', 'ARM64')][string]$Arch = 'x64'
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    $ua = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36'
    $page = if ($Version -eq '11') {
        'https://www.microsoft.com/software-download/windows11'
    }
    else {
        'https://www.microsoft.com/software-download/windows10ISO'
    }
    $sid = [guid]::NewGuid().ToString()
    $instance = '560dc9f3-1aa5-4a2f-b63c-9e18f8d0e175'

    try {
        # 1. La page, pour y LIRE l'identifiant d'edition courant plutot que de
        #    le coder en dur : Microsoft l'incremente a chaque version.
        Write-Etat "Interrogation de la page officielle Microsoft..." -Niveau Info
        $r = Invoke-WebRequest -Uri $page -UserAgent $ua -UseBasicParsing -TimeoutSec 30 -SessionVariable ws
        $edId = ([regex]::Match($r.Content, 'value="(\d{3,5})"[^>]*>\s*Windows ' + $Version)).Groups[1].Value
        if (-not $edId) { $edId = ([regex]::Match($r.Content, '<option[^>]*value="(\d{3,5})"')).Groups[1].Value }
        if (-not $edId) { throw "Identifiant d'edition introuvable : Microsoft a change sa mise en page." }

        # 2. Enregistrement de la session (pose les cookies de reconnaissance).
        Invoke-WebRequest -Uri "https://vlscppe.microsoft.com/tags?org_id=y6jn8c31&session_id=$sid" `
            -UserAgent $ua -UseBasicParsing -WebSession $ws -TimeoutSec 30 | Out-Null

        # 3. Les trois valeurs a usage unique.
        $m = Invoke-WebRequest -Uri "https://ov-df.microsoft.com/mdt.js?instanceId=$instance&PageId=si&session_id=$sid" `
            -UserAgent $ua -UseBasicParsing -WebSession $ws -TimeoutSec 30
        $w = ([regex]::Match($m.Content, '[?&]w=([A-Za-z0-9]+)')).Groups[1].Value
        $rticks = ([regex]::Match($m.Content, 'rticks="\s*\+\s*(\d+)')).Groups[1].Value
        $cid = ([regex]::Match($m.Content, 'customerId:"([^"]+)"')).Groups[1].Value
        if (-not $w -or -not $rticks -or -not $cid) {
            throw "Jetons de session illisibles : le mecanisme de validation a change."
        }

        # 4. Le renvoi qui valide la session, celui que fait l'iframe invisible.
        $mdt = [long]([DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds())
        Invoke-WebRequest -Uri "https://ov-df.microsoft.com/?session_id=$sid&CustomerId=$cid&PageId=si&w=$w&mdt=$mdt&rticks=$rticks" `
            -UserAgent $ua -UseBasicParsing -WebSession $ws -Headers @{ 'Referer' = $page } -TimeoutSec 30 | Out-Null
        Start-Sleep -Seconds 3

        # 5. Les langues reellement proposees pour cette edition.
        $sku = Invoke-RestMethod -UserAgent $ua -WebSession $ws -Headers @{ 'Referer' = $page } -TimeoutSec 30 `
            -Uri "https://www.microsoft.com/software-download-connector/api/getskuinformationbyproductedition?profile=606624d44113&productEditionId=$edId&SKU=undefined&friendlyFileName=undefined&Locale=fr-FR&sessionID=$sid"
        if (-not $sku.Skus) { throw "Aucune langue retournee : $($sku.Errors | ConvertTo-Json -Compress)" }

        # Comparaison insensible aux accents : Microsoft renvoie « Français » avec
        # sa cédille. Même piège que les noms de profils, même remède.
        $cible = ConvertTo-CleComparable $Langue
        $choix = $sku.Skus | Where-Object { (ConvertTo-CleComparable $_.LocalizedLanguage) -like "*$cible*" } | Select-Object -First 1
        if (-not $choix) {
            throw "Langue « $Langue » indisponible. Proposees : $((($sku.Skus.LocalizedLanguage) | Select-Object -First 12) -join ', ')..."
        }

        # 6. Les liens, enfin.
        $dl = Invoke-RestMethod -UserAgent $ua -WebSession $ws -Headers @{ 'Referer' = $page } -TimeoutSec 30 `
            -Uri "https://www.microsoft.com/software-download-connector/api/GetProductDownloadLinksBySku?profile=606624d44113&productEditionId=undefined&SKU=$($choix.Id)&friendlyFileName=undefined&Locale=fr-FR&sessionID=$sid"
        if (-not $dl.ProductDownloadOptions) {
            throw "Lien refuse par Microsoft : $($dl.Errors | ConvertTo-Json -Compress)"
        }

        # DownloadType : 1 = x64, 2 = ARM64 (constate sur les reponses reelles).
        $type = if ($Arch -eq 'x64') { 1 } else { 2 }
        $opt = $dl.ProductDownloadOptions | Where-Object { $_.DownloadType -eq $type } | Select-Object -First 1
        if (-not $opt) { $opt = $dl.ProductDownloadOptions | Select-Object -First 1 }

        $nom = ([regex]::Match($opt.Uri, '/([^/?]+\.iso)')).Groups[1].Value
        if (-not $nom) { $nom = "Windows$Version-$Arch.iso" }
        Write-Etat "Lien officiel obtenu : $nom" -Niveau OK
        return @{ Nom = $nom; Uri = $opt.Uri; Langue = $choix.LocalizedLanguage }
    }
    catch {
        Write-Etat "Lien indisponible : $($_.Exception.Message)" -Niveau Echec
        Write-Etat "Repli : utilise le Media Creation Tool depuis ce menu." -Niveau Info
        return $null
    }
}

function Save-IsoWindows {
    <#
        Telecharge l'ISO depuis le lien officiel, avec progression.
        Retourne le chemin ecrit, ou $null.

        Le lien expire au bout de quelques heures : on ne le conserve pas, on le
        redemande a chaque fois. Un telechargement interrompu laisse un fichier
        tronque, qui produirait un support silencieusement inutilisable : on
        ecrit donc dans un fichier temporaire et on ne le renomme QU'A LA FIN,
        apres avoir verifie que le compte d'octets correspond.
    #>
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Chemin
    )

    $partiel = "$Chemin.partiel"
    $dossier = Split-Path $Chemin -Parent
    if ($dossier -and -not (Test-Path $dossier)) { New-Item -ItemType Directory -Path $dossier -Force | Out-Null }
    if (Test-Path $partiel) { Remove-Item $partiel -Force }

    try {
        Write-Etat "Telechargement en cours (plusieurs gigaoctets, compter 10 a 40 minutes)..." -Niveau Info
        $req = [System.Net.HttpWebRequest]::Create($Uri)
        $req.UserAgent = 'Mozilla/5.0'
        $req.Timeout = 60000
        $rep = $req.GetResponse()
        $total = $rep.ContentLength
        $flux = $rep.GetResponseStream()
        $sortie = [System.IO.File]::Create($partiel)
        $tampon = New-Object byte[] 1048576
        $fait = 0L
        $dernier = Get-Date
        while (($lu = $flux.Read($tampon, 0, $tampon.Length)) -gt 0) {
            $sortie.Write($tampon, 0, $lu)
            $fait += $lu
            if (((Get-Date) - $dernier).TotalSeconds -ge 10) {
                $pc = if ($total -gt 0) { [math]::Round($fait * 100 / $total) } else { 0 }
                Write-Etat "  $pc %  ($([math]::Round($fait / 1GB, 2)) Go sur $([math]::Round($total / 1GB, 2)) Go)" -Niveau Info
                $dernier = Get-Date
            }
        }
        $sortie.Close(); $flux.Close(); $rep.Close()

        if ($total -gt 0 -and $fait -ne $total) {
            throw "Telechargement incomplet : $fait octets sur $total attendus."
        }
        Move-Item $partiel $Chemin -Force
        Write-Etat "ISO telechargee : $Chemin ($([math]::Round((Get-Item $Chemin).Length / 1GB, 2)) Go)" -Niveau OK
        return $Chemin
    }
    catch {
        if (Test-Path $partiel) { Remove-Item $partiel -Force -ErrorAction SilentlyContinue }
        Write-Etat "Telechargement echoue : $($_.Exception.Message)" -Niveau Echec
        return $null
    }
}

function Wait-IsoTelechargee {
    <#
        Surveille l'apparition d'une ISO Windows et renvoie son chemin.
        Rend la main tout seul des que le fichier a fini de grossir.

        Pourquoi cette fonction plutot qu'un telechargement automatique : l'API
        de telechargement de Microsoft est protegee par un anti-robot (elle
        repond « Sentinel marked this request as rejected »). Le contourner
        demanderait une course perpetuelle, et casserait chez les utilisateurs a
        chaque changement cote Microsoft. Quant a telecharger un script tiers
        pour le faire, MadTweak tourne en administrateur sur des machines qui ne
        sont pas les miennes : executer du code recupere sur internet au moment
        ou il tourne n'est pas une option.

        On laisse donc l'outil officiel faire son travail, et on reprend la main
        automatiquement des que le fichier existe. L'utilisateur ne fait que
        quelques clics chez Microsoft ; MadTweak s'occupe de tout le reste.
    #>
    param(
        [string[]]$Dossiers = @(),
        [int]$MinutesMax = 90
    )

    if ($Dossiers.Count -eq 0) {
        $Dossiers = @(
            (Join-Path $env:USERPROFILE 'Downloads'),
            [Environment]::GetFolderPath('Desktop'),
            'D:', 'C:'
        ) | Where-Object { Test-Path $_ }
    }

    # On ne retient que les ISO APPARUES apres le debut de l'attente : une image
    # deja presente n'est pas celle que l'utilisateur telecharge maintenant.
    $connues = @{}
    foreach ($d in $Dossiers) {
        foreach ($f in (Get-ChildItem $d -Filter *.iso -File -ErrorAction SilentlyContinue)) {
            $connues[$f.FullName] = $true
        }
    }

    Write-Etat "En attente d'une ISO dans : $($Dossiers -join ' | ')" -Niveau Info
    Write-Etat "Choisis « Creer un support d'installation » puis « Fichier ISO »." -Niveau Info

    $fin = (Get-Date).AddMinutes($MinutesMax)
    while ((Get-Date) -lt $fin) {
        foreach ($d in $Dossiers) {
            foreach ($f in (Get-ChildItem $d -Filter *.iso -File -ErrorAction SilentlyContinue)) {
                if ($connues.ContainsKey($f.FullName)) { continue }
                if ($f.Length -lt 1GB) { continue }

                # Le fichier existe, mais il grossit peut-etre encore. On attend
                # qu'il cesse de bouger : copier une ISO a moitie ecrite
                # produirait un support silencieusement inutilisable.
                $t1 = $f.Length
                Start-Sleep -Seconds 15
                $t2 = (Get-Item $f.FullName -ErrorAction SilentlyContinue).Length
                if ($t1 -ne $t2) {
                    Write-Etat "Telechargement en cours : $([math]::Round($t2/1GB,2)) Go..." -Niveau Info
                    continue
                }
                Write-Etat "ISO detectee : $($f.FullName) ($([math]::Round($t2/1GB,2)) Go)" -Niveau OK
                return $f.FullName
            }
        }
        Start-Sleep -Seconds 10
    }
    Write-Etat "Aucune ISO apparue en $MinutesMax minutes." -Niveau Avert
    return $null
}

function New-CleInstallation {
    <#
        Efface un disque USB, le formate et y écrit une ISO Windows officielle,
        puis y dépose le fichier de réponses (et MadTweak si un profil est prévu).

        C'EST LA SEULE FONCTION DESTRUCTIVE DE TOUT MADTWEAK. Tout le reste de
        l'outil sauvegarde avant d'écrire et sait revenir en arrière ; ici, non :
        les données du disque choisi sont perdues. D'où les verrous ci-dessous,
        qui s'exécutent TOUS avant la moindre écriture :

          - -Confirme est obligatoire ; sans lui, la fonction refuse de démarrer ;
          - le disque doit être de type USB. Un disque interne est refusé, même
            explicitement demandé : c'est la ligne qui empêche d'effacer un disque
            de données sur une faute de frappe ;
          - un disque marqué démarrage ou système est refusé.

        Le formatage est en FAT32, seul système de fichiers que tous les micrologiciels
        UEFI savent lire au démarrage. Cela impose deux contraintes que la fonction
        gère au lieu de les subir : une partition d'au plus 32 Go (Windows refuse de
        formater davantage en FAT32) et un install.wim découpé en .swm s'il dépasse
        4 Go, ce qui est le cas courant. Windows Setup lit nativement les .swm.
    #>
    param(
        [Parameter(Mandatory)][int]$NumeroDisque,
        [Parameter(Mandatory)][string]$CheminIso,
        [string]$CheminXml,
        [string]$CheminMadTweak,
        [string]$Etiquette = 'MADTWEAK',
        # Édition à conserver quand une image .esd doit être convertie : on n'en
        # extrait qu'une, pas les onze. Nom exact, tel que Get-EditionsImage le rend.
        [string]$Edition = '',
        # FAT32 : démarre sur tous les UEFI, mais plafonne les fichiers à 4 Go, d'où
        # le découpage de install.wim. NTFS : aucun découpage, préparation bien plus
        # rapide — mais la plupart des micrologiciels UEFI n'ont pas de pilote NTFS
        # et ne démarreront pas dessus. Rufus contourne ça avec son propre chargeur ;
        # nous n'en avons pas, donc NTFS ne convient qu'à une machine en BIOS/CSM ou
        # à une clé destinée à Ventoy. FAT32 reste le défaut, exprès.
        [ValidateSet('FAT32', 'NTFS')][string]$SystemeFichiers = 'FAT32',
        [switch]$Confirme
    )

    if (-not $Confirme) {
        throw "New-CleInstallation efface entièrement un disque : appelle-la avec -Confirme."
    }
    if (-not (Test-Path -LiteralPath $CheminIso)) { throw "ISO introuvable : $CheminIso" }
    if ([System.IO.Path]::GetExtension($CheminIso).ToLowerInvariant() -ne '.iso') {
        throw "Attendu un fichier .iso."
    }
    if ($CheminXml -and -not (Test-Path -LiteralPath $CheminXml)) {
        throw "Fichier de réponses introuvable : $CheminXml"
    }

    # Cohérence entre les deux usages du nom d'édition. Quand une image .esd est
    # convertie, le .wim produit ne contient QUE l'édition extraite ; si le fichier
    # de réponses en réclame une autre, Windows Setup ne la trouvera pas et
    # l'installation s'arrêtera — après le formatage de la clé, et devant une
    # machine qu'on vient peut-être d'effacer.
    if ($CheminXml -and $Edition) {
        try {
            $xv = [xml](Get-Content $CheminXml -Raw)
            $nsv = New-Object System.Xml.XmlNamespaceManager($xv.NameTable)
            $nsv.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
            $voulu = $xv.SelectSingleNode('//u:MetaData/u:Value', $nsv)
            if ($voulu -and $voulu.InnerText -ne $Edition) {
                throw "Incohérence : le fichier de réponses demande « $($voulu.InnerText) » alors que la clé recevra « $Edition »."
            }
        }
        catch [System.Management.Automation.RuntimeException] { throw }
        catch { }
    }

    $disque = Get-Disk -Number $NumeroDisque -ErrorAction SilentlyContinue
    if (-not $disque) { throw "Aucun disque numéro $NumeroDisque." }
    if ($disque.BusType -ne 'USB') {
        throw "Le disque $NumeroDisque est de type « $($disque.BusType) », pas USB. MadTweak refuse d'effacer autre chose qu'une clé USB."
    }
    if ($disque.IsBoot -or $disque.IsSystem) {
        throw "Le disque $NumeroDisque porte le système : refus catégorique."
    }

    $monte = $null
    try {
        Write-Etat "Ouverture de l'ISO..." -Niveau Info
        $monte = Mount-DiskImage -ImagePath $CheminIso -StorageType ISO -Access ReadOnly -PassThru -ErrorAction Stop
        $src = ($monte | Get-Volume).DriveLetter
        if (-not $src) { throw "L'ISO a été montée mais sans lettre de lecteur." }
        $srcRacine = "${src}:\"
        if (-not (Test-Path (Join-Path $srcRacine 'setup.exe'))) {
            throw "Pas de setup.exe dans cette ISO : ce n'est pas un support d'installation Windows."
        }

        # On repère le gros fichier AVANT d'effacer quoi que ce soit : si l'image est
        # un .esd trop volumineux, on ne saura pas la découper, et il vaut mieux le
        # découvrir maintenant que la clé une fois effacée.
        $wim = Join-Path $srcRacine 'sources\install.wim'
        $esd = Join-Path $srcRacine 'sources\install.esd'
        $gros = $null; $decouper = $false; $wimTemp = $null; $nomExclu = $null
        if (Test-Path $wim) { $gros = $wim; $nomExclu = 'install.wim' }
        elseif (Test-Path $esd) { $gros = $esd; $nomExclu = 'install.esd' }

        if ($gros) {
            $tailleGo = (Get-Item $gros).Length / 1GB
            if ($tailleGo -gt 3.9 -and $SystemeFichiers -eq 'FAT32') {
                $decouper = $true

                # On exporte TOUJOURS vers un WIM temporaire, que la source soit un
                # .esd ou un .wim. Deux raisons, la premiere apprise a la dure :
                #
                # 1. Split-WindowsImage refuse une source en LECTURE SEULE. Or une
                #    ISO montee l'est toujours. Sur une image contenant un .wim, le
                #    decoupage direct echoue avec « Acces refuse (E_ACCESSDENIED) »,
                #    apres la copie des fichiers, donc tard.
                # 2. On n'emporte alors qu'une edition sur les onze que contient une
                #    image officielle : le fichier produit est bien plus petit.
                Write-Etat "$nomExclu fait $([math]::Round($tailleGo,1)) Go : extraction de l'edition choisie, puis decoupage en .swm." -Niveau Info
                $wimTemp = Convert-ImageVersWim -CheminImage $gros -Edition $Edition
                $aDecouper = $wimTemp
            }
        }

        # --- À partir d'ici, on écrit. Tout ce qui pouvait être vérifié l'a été. ---
        $volsTest = @(Get-Partition -DiskNumber $NumeroDisque -ErrorAction SilentlyContinue | Get-Volume -ErrorAction SilentlyContinue | Where-Object DriveLetter)
        if ($volsTest -and $volsTest.Count -gt 0 -and $volsTest[0].DriveLetter) {
            try { Test-VitesseCleUSB -Lettre $volsTest[0].DriveLetter | Out-Null } catch { }
        }

        Write-Etat "Effacement du disque $NumeroDisque ($($disque.FriendlyName))..." -Niveau Info

        Clear-Disk -Number $NumeroDisque -RemoveData -RemoveOEM -Confirm:$false -ErrorAction Stop

        # On VISE le MBR, mais on ne le suppose pas. Clear-Disk ne ramène pas
        # toujours le disque à l'état brut : une clé faite par Rufus reste en GPT,
        # et Initialize-Disk echoue alors sans bruit. C'est ce qui s'est passé au
        # premier essai reel — le style restait GPT, et -IsActive, qui n'existe
        # qu'en MBR, faisait echouer la creation de partition APRES l'effacement.
        $etat = Get-Disk -Number $NumeroDisque
        if ($etat.PartitionStyle -eq 'RAW') {
            Initialize-Disk -Number $NumeroDisque -PartitionStyle MBR -ErrorAction SilentlyContinue | Out-Null
        }
        elseif ($etat.PartitionStyle -eq 'GPT') {
            try { Set-Disk -Number $NumeroDisque -PartitionStyle MBR -ErrorAction Stop }
            catch { }
        }
        $style = (Get-Disk -Number $NumeroDisque).PartitionStyle
        Write-Etat "Table de partition : $style" -Niveau Info

        # 32 Go maximum en FAT32 : au-delà, Windows refuse de formater. Un support
        # d'installation n'a de toute façon besoin que de 8 à 10 Go. NTFS n'a pas
        # cette limite, on prend alors toute la clé.
        $tailleMax = if ($SystemeFichiers -eq 'FAT32') { [math]::Min($disque.Size - 8MB, 32GB) } else { $disque.Size - 8MB }

        # « Actif » est une notion propre au MBR. En GPT elle n'existe pas — et
        # elle n'y sert a rien : l'UEFI demarre sur une partition FAT32 sans
        # aucun indicateur d'activite. On ne la pose donc que la ou elle a un sens.
        if ($style -eq 'MBR') {
            $part = New-Partition -DiskNumber $NumeroDisque -Size $tailleMax -AssignDriveLetter -IsActive -ErrorAction Stop
        }
        else {
            $part = New-Partition -DiskNumber $NumeroDisque -Size $tailleMax -AssignDriveLetter -ErrorAction Stop
        }
        Start-Sleep -Seconds 2
        Write-Etat "Formatage en $SystemeFichiers..." -Niveau Info
        if ($SystemeFichiers -eq 'NTFS') {
            Write-Etat "NTFS : pas de decoupage, mais beaucoup d'UEFI ne demarrent pas sur du NTFS. A reserver au BIOS/CSM ou a Ventoy." -Niveau Avert
        }
        Format-Volume -Partition $part -FileSystem $SystemeFichiers -NewFileSystemLabel $Etiquette -Confirm:$false -Force -ErrorAction Stop | Out-Null
        $dst = "$($part.DriveLetter):\"

        Write-Etat "Copie de l'image vers $dst (plusieurs minutes)..." -Niveau Info
        # robocopy plutôt que Copy-Item : il reprend, il journalise, et il sait
        # exclure un fichier. Ses codes de sortie sous 8 signalent un succès.
        $exclu = if ($decouper) { @('/XF', $nomExclu) } else { @() }
        & robocopy $srcRacine $dst /E /NFL /NDL /NJH /NJS /NP @exclu | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "La copie a échoué (robocopy code $LASTEXITCODE)." }

        if ($decouper) {
            Write-Etat "Découpage en .swm (long)..." -Niveau Info
            Split-WindowsImage -ImagePath $aDecouper -SplitImagePath (Join-Path $dst 'sources\install.swm') -FileSize 3800 -ErrorAction Stop | Out-Null
            Write-Etat "$((Get-ChildItem (Join-Path $dst 'sources') -Filter *.swm).Count) fichier(s) .swm posé(s)." -Niveau OK
        }

        if ($CheminXml) {
            Copy-Item -LiteralPath $CheminXml -Destination (Join-Path $dst 'autounattend.xml') -Force -ErrorAction Stop
            $pbs = Test-AutounattendXml -Chemin (Join-Path $dst 'autounattend.xml')
            if ($pbs.Count -gt 0) { throw "Le fichier de réponses copié est illisible : $($pbs[0])" }
        }
        if ($CheminMadTweak -and (Test-Path $CheminMadTweak)) {
            Copy-Item -LiteralPath $CheminMadTweak -Destination (Join-Path $dst 'MadTweak.ps1') -Force -ErrorAction Stop
        }

        Write-Etat "Clé prête sur $dst" -Niveau OK
        return $dst
    }
    finally {
        if ($monte) { try { Dismount-DiskImage -ImagePath $CheminIso | Out-Null } catch { } }
        # Le .wim converti peut peser plusieurs gigaoctets : le laisser dans %TEMP%
        # serait un cadeau empoisonné.
        if ($wimTemp -and (Test-Path $wimTemp)) {
            try { Remove-Item (Split-Path $wimTemp -Parent) -Recurse -Force -ErrorAction Stop }
            catch { Write-Etat "Fichier temporaire à supprimer soi-même : $wimTemp" -Niveau Avert }
        }
    }
}

function Test-AutounattendXml {
    <#
        Relit un fichier de réponses et renvoie la liste de ses problèmes.
        Liste vide = rien à signaler. Ne modifie rien.

        Pourquoi ce contrôle existe : un réglage placé dans le mauvais passage de
        configuration ne fait PAS échouer l'installation — Windows l'ignore, en
        silence. On se retrouve avec un clavier QWERTY ou un écran de compte qui
        réapparaît, sans le moindre message. C'est exactement le genre de panne
        qu'un test automatique attrape et qu'une relecture humaine laisse passer.

        Le projet a déjà cinq filets de ce type (Test-ClesProfils, Test-CoherenceAudit,
        Test-Explications, le décompte des clés jouées, la CI). Celui-ci est le sixième.
    #>
    param([Parameter(Mandatory)][string]$Chemin)

    $pbs = New-Object System.Collections.Generic.List[string]
    if (-not (Test-Path $Chemin)) { $pbs.Add("Fichier introuvable : $Chemin"); return $pbs }

    # Windows Setup lit le fichier en UTF-8 ; un BOM peut le faire échouer.
    $octets = [System.IO.File]::ReadAllBytes($Chemin)
    if ($octets.Length -ge 3 -and $octets[0] -eq 0xEF -and $octets[1] -eq 0xBB -and $octets[2] -eq 0xBF) {
        $pbs.Add("Le fichier commence par un BOM UTF-8 : Windows Setup peut le refuser.")
    }

    try { $x = [xml](Get-Content $Chemin -Raw) }
    catch { $pbs.Add("XML mal formé : $($_.Exception.Message)"); return $pbs }

    $ns = New-Object System.Xml.XmlNamespaceManager($x.NameTable)
    $ns.AddNamespace('u', 'urn:schemas-microsoft-com:unattend')
    if (-not $x.SelectSingleNode('/u:unattend', $ns)) {
        $pbs.Add("Racine « unattend » absente ou mauvais espace de noms.")
        return $pbs
    }

    # Passages où chaque composant est réellement valide, d'après la documentation
    # Microsoft. On ne liste que ceux qu'on écrit : inventer une règle serait pire
    # que ne pas en avoir.
    $passagesValides = @{
        'Microsoft-Windows-International-Core-WinPE' = @('windowsPE')
        'Microsoft-Windows-International-Core'       = @('specialize', 'oobeSystem')
        'Microsoft-Windows-Setup'                    = @('windowsPE')
        'Microsoft-Windows-Deployment'               = @('specialize', 'windowsPE', 'auditUser', 'oobeSystem')
        'Microsoft-Windows-Shell-Setup'              = @('specialize', 'oobeSystem', 'auditSystem', 'generalize')
    }

    $vus = @{}
    foreach ($s in $x.SelectNodes('/u:unattend/u:settings', $ns)) {
        $passage = $s.pass
        foreach ($c in $s.SelectNodes('u:component', $ns)) {
            $nom = $c.name
            $vus["$nom|$passage"] = $true
            if ($passagesValides.ContainsKey($nom) -and $passage -notin $passagesValides[$nom]) {
                $pbs.Add("« $nom » est place dans le passage « $passage », ou il sera IGNORE en silence. Passages valides : $($passagesValides[$nom] -join ', ').")
            }
        }
    }

    # Réglages dépréciés : Microsoft demande explicitement de ne pas s'en servir.
    foreach ($mort in 'SkipMachineOOBE', 'SkipUserOOBE') {
        if ($x.SelectSingleNode("//u:$mort", $ns)) {
            $pbs.Add("« $mort » est deprecie depuis Windows 10 1709 et ne doit pas servir a automatiser l'OOBE.")
        }
    }

    # Sans ces deux blocs, l'installation « automatique » repose ses questions.
    if (-not $vus['Microsoft-Windows-International-Core|oobeSystem']) {
        $pbs.Add("Aucun « Microsoft-Windows-International-Core » en oobeSystem : le Windows INSTALLE gardera la disposition clavier par defaut.")
    }
    if (-not $x.SelectSingleNode('//u:settings[@pass="oobeSystem"]//u:UserAccounts', $ns)) {
        $pbs.Add("Aucun compte declare en oobeSystem : l'ecran de creation de compte reapparaitra.")
    }

    # Effacer le disque sans dire où installer laisse l'installeur sans cible,
    # APRÈS avoir tout effacé. C'est la combinaison la plus coûteuse du fichier.
    if ($x.SelectSingleNode('//u:WillWipeDisk', $ns) -and
        -not ($x.SelectSingleNode('//u:InstallTo', $ns) -or $x.SelectSingleNode('//u:InstallToAvailablePartition', $ns))) {
        $pbs.Add("Le disque est efface mais aucune cible d'installation n'est indiquee (InstallTo).")
    }

    # Effacer un disque et installer sur un AUTRE est la pire issue possible : on
    # detruit des donnees ET on installe ailleurs que prevu. Les deux numeros doivent
    # concorder.
    $dEfface = $x.SelectSingleNode('//u:DiskConfiguration/u:Disk/u:DiskID', $ns)
    $dCible = $x.SelectSingleNode('//u:InstallTo/u:DiskID', $ns)
    if ($dEfface -and $dCible -and $dEfface.InnerText -ne $dCible.InnerText) {
        $pbs.Add("Le disque efface ($($dEfface.InnerText)) n'est pas celui ou Windows serait installe ($($dCible.InnerText)).")
    }

    # FirstLogonCommands n'existe qu'en oobeSystem ; ailleurs il ne joue jamais.
    foreach ($f in $x.SelectNodes('//u:FirstLogonCommands', $ns)) {
        $p = $f.SelectSingleNode('ancestor::u:settings', $ns)
        if ($p -and $p.pass -ne 'oobeSystem') {
            $pbs.Add("FirstLogonCommands se trouve en « $($p.pass) » : il ne s'executera jamais.")
        }
    }

    # Limite documentée, et unicité des ordres d'exécution.
    foreach ($c in $x.SelectNodes('//u:CommandLine', $ns)) {
        if ($c.InnerText.Length -gt 1024) {
            $pbs.Add("Une commande depasse 1024 caracteres ($($c.InnerText.Length)) : Windows la refusera.")
        }
    }
    foreach ($groupe in @('FirstLogonCommands', 'RunSynchronous')) {
        foreach ($parent in $x.SelectNodes("//u:$groupe", $ns)) {
            $ordres = @($parent.SelectNodes('.//u:Order', $ns) | ForEach-Object { $_.InnerText })
            $doublons = @($ordres | Group-Object | Where-Object Count -gt 1)
            if ($doublons) {
                $pbs.Add("Ordres d'execution en double dans $groupe : $(($doublons.Name) -join ', ').")
            }
        }
    }

    return $pbs
}

function Get-FuseauxCourants {
    # Les identifiants attendus par Windows Setup sont ceux de .NET (« Romance
    # Standard Time »), pas des noms IANA. Plutôt que de recopier à la main une
    # poignée de fuseaux — avec le risque d'en écrire un qui n'existe pas — on
    # énumère ceux que la machine connaît réellement. Le fuseau courant vient en
    # tête : dans l'immense majorité des cas, on réinstalle là où on se trouve.
    $liste = [ordered]@{}
    try {
        $courant = [System.TimeZoneInfo]::Local
        $liste["$($courant.DisplayName)  (ce PC)"] = $courant.Id
        foreach ($tz in ([System.TimeZoneInfo]::GetSystemTimeZones() | Sort-Object DisplayName)) {
            if ($tz.Id -ne $courant.Id) { $liste[$tz.DisplayName] = $tz.Id }
        }
    }
    catch {
        # Repli minimal si l'énumération échoue : mieux vaut un choix que rien.
        $liste["Europe de l'Ouest (Paris, Bruxelles)"] = "Romance Standard Time"
        $liste["Royaume-Uni (Londres)"] = "GMT Standard Time"
    }
    return $liste
}

function Get-LangueCePC {
    # Relit la configuration régionale RÉELLE de la machine courante. C'est la seule
    # source qui ne se trompe pas de disposition clavier : un identifiant recopié de
    # travers (080c contre 040c) donne un AZERTY belge là où on voulait un français,
    # et cela ne se découvre qu'une fois devant la machine installée.
    try {
        $ui = (Get-UICulture).Name
        $loc = (Get-WinSystemLocale).Name
        $clavier = $null
        try {
            $premiere = @(Get-WinUserLanguageList)[0]
            if ($premiere.InputMethodTips.Count -gt 0) { $clavier = $premiere.InputMethodTips[0] }
        }
        catch { }
        if (-not $clavier) { return $null }
        return @{ UI = $ui; Locale = $loc; Clavier = $clavier }
    }
    catch { return $null }
}

function Get-LanguesInstallation {
    $liste = [ordered]@{}
    $cePc = Get-LangueCePC
    if ($cePc) { $liste["Identique a ce PC ($($cePc.Locale), clavier $($cePc.Clavier))"] = $cePc }
    $liste["Francais (Belgique)"] = @{ UI = "fr-FR"; Locale = "fr-BE"; Clavier = "080c:0000080c" }
    $liste["Francais (France)"] = @{ UI = "fr-FR"; Locale = "fr-FR"; Clavier = "040c:0000040c" }
    $liste["Francais (Suisse)"] = @{ UI = "fr-FR"; Locale = "fr-CH"; Clavier = "100c:0000100c" }
    $liste["Francais (Canada)"] = @{ UI = "fr-CA"; Locale = "fr-CA"; Clavier = "0c0c:00001009" }
    $liste["English (US)"] = @{ UI = "en-US"; Locale = "en-US"; Clavier = "0409:00000409" }
    $liste["English (UK)"] = @{ UI = "en-GB"; Locale = "en-GB"; Clavier = "0809:00000809" }
    return $liste
}

function ConvertTo-MotDePasseUnattend {
    # Windows attend le mot de passe en base64 de (mot de passe + "Password"),
    # en UTF-16LE. Ce n'est PAS du chiffrement : n'importe qui lisant la clé USB
    # le retrouve en une commande. L'appelant DOIT en avertir l'utilisateur.
    param([string]$MotDePasse)
    $octets = [System.Text.Encoding]::Unicode.GetBytes($MotDePasse + "Password")
    return [Convert]::ToBase64String($octets)
}

function New-AutounattendXml {
    <#
        Génère le fichier de réponses. Retourne le chemin écrit.

        -Profil     : clé d'un profil MadTweak rejoué au premier démarrage ($null = aucun)
        -Apps       : identifiants winget installés au premier démarrage
        -SansTPM    : ajoute les contournements TPM/SecureBoot/RAM (matériel ancien)
        -MotDePasse : laissé vide = compte SANS mot de passe, à définir au 1er démarrage
        -Version    : 11 ou 10 — ne sert qu'à nommer l'édition dans l'image
        -Edition    : Pro / Famille / Entreprise. Vide = l'installeur pose la question.
                      Ne la remplir que si on est sûr de ce que contient l'ISO : un
                      nom d'édition absent de l'image fait échouer l'installation.
    #>
    param(
        [Parameter(Mandatory)][string]$Chemin,
        [Parameter(Mandatory)][string]$NomUtilisateur,
        [ValidateSet('11', '10')][string]$Version = '11',
        # Raccourci (Pro / Famille / Entreprise) OU nom exact d'édition lu dans
        # l'image par Get-EditionsImage. Un nom exact l'emporte toujours : c'est
        # une valeur mesurée, elle vaut mieux que ma table de correspondance.
        [string]$Edition = '',
        [string]$MotDePasse = "",
        [string]$NomMachine = "",
        [string]$Langue = "Francais (Belgique)",
        [string]$Fuseau = "Romance Standard Time",
        [string]$Profil,
        [string[]]$Apps = @(),
        [switch]$SansTPM,
        # Ne sert QUE si l'image source embarque déjà son propre fichier de réponses
        # (build « maison » sysprepée). Ajoute wasPassProcessed="false" et recopie le
        # fichier vers C:\Windows\Panther. Sur une image d'origine, cela casse
        # l'installation — constaté. À n'activer qu'en connaissance de cause.
        [switch]$ForcerPassages,
        [switch]$EffacerDisque,
        # Numéro du disque à effacer. 0 est le défaut habituel, mais PAS une garantie :
        # sur une machine à plusieurs disques, le 0 peut être celui des données. Ce
        # paramètre n'a d'effet qu'avec -EffacerDisque.
        [int]$Disque = 0
    )

    $langues = Get-LanguesInstallation
    if (-not $langues.Contains($Langue)) { throw "Langue « $Langue » inconnue." }
    $L = $langues[$Langue]

    if ($NomUtilisateur -match '[\\/:*?"<>|]') { throw "Le nom d'utilisateur contient un caractere interdit." }
    if (-not $NomMachine) { $NomMachine = "PC-" + ($NomUtilisateur -replace '[^a-zA-Z0-9]', '') }
    if ($NomMachine.Length -gt 15) { $NomMachine = $NomMachine.Substring(0, 15) }

    $esc = {
        param($t)
        "$t" -replace '&', '&amp;' -replace '<', '&lt;' -replace '>', '&gt;' -replace '"', '&quot;' -replace "'", '&apos;'
    }

    # Un compte local AVEC mot de passe déclenche trois questions de sécurité pendant
    # l'OOBE — trois écrans de plus dans une installation censée n'en poser aucun.
    # La stratégie NoLocalPasswordResetQuestions les supprime… sous Windows 10.
    # Sous Windows 11, plusieurs rapports décrivent une erreur OOBELOCAL qui bloque
    # l'installation. On ne la pose donc QUE sous Windows 10 : gagner trois écrans ne
    # vaut pas le risque de planter une installation qu'on ne verra pas échouer.
    $blocQuestions = ""
    if ($MotDePasse -and $Version -eq '10') {
        $blocQuestions = @"
                <RunSynchronousCommand wcm:action="add">
                    <Order>3</Order>
                    <Path>reg add HKLM\SOFTWARE\Policies\Microsoft\Windows\System /v NoLocalPasswordResetQuestions /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
"@
    }

    # --- Contournements pour images DÉJÀ personnalisées ---------------------------
    #
    # Ces deux ajouts ne servent QUE lorsque l'image source embarque déjà son propre
    # fichier de réponses (une build sysprepée « maison »). Sur une image Microsoft
    # d'origine ils sont au mieux inutiles, au pire nuisibles : recopier le fichier
    # vers C:\Windows\Panther\unattend.xml écrase celui que Windows Setup est en
    # train d'utiliser, en plein passage specialize. Un essai réel s'est solde par
    # « L'ordinateur a redémarré de manière inattendue ou a rencontré une erreur
    # inattendue » — l'echec classique d'un specialize qui casse.
    #
    # Ils sont donc DESACTIVES par defaut. On ne degrade pas le cas courant pour un
    # cas particulier ; -ForcerPassages les remet, en connaissance de cause.
    $attrPassage = if ($ForcerPassages) { ' wasPassProcessed="false"' } else { '' }
    $blocPanther = ''
    if ($ForcerPassages) {
        # On cherche le fichier sur TOUS les lecteurs : une clé USB n'a aucune
        # lettre garantie.
        $copiePanther = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=Get-ChildItem -Path (Get-PSDrive -PSProvider FileSystem).Root -Filter autounattend.xml -ErrorAction SilentlyContinue | Select-Object -First 1; if ($f) { Copy-Item $f.FullName ''C:\Windows\Panther\unattend.xml'' -Force }"'
        $blocPanther = @"
                <RunSynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <Path>$(& $esc $copiePanther)</Path>
                </RunSynchronousCommand>
"@
    }

    # --- Commandes de première ouverture de session -------------------------------
    # Elles s'exécutent une fois, en tant que l'utilisateur créé, session ouverte.
    $cmds = New-Object System.Collections.Generic.List[string]
    $ordre = 1
    # Toutes les traces de la première ouverture de session vont dans un seul fichier,
    # dans un dossier accessible à tous. Sans lui, une installation d'application qui
    # échoue ne laisse RIEN : on découvre l'absence du logiciel des jours plus tard,
    # sans le moindre indice sur la cause.
    $journal = 'C:\Users\Public\madtweak-premier-demarrage.log'

    $ajouteCmd = {
        param($description, $ligne)
        # La documentation fixe la limite à 1024 caractères. Au-delà, Windows tronque
        # ou refuse la commande — et cela ne se verrait qu'au premier démarrage d'une
        # machine déjà formatée. Mieux vaut échouer ici, devant l'utilisateur.
        if ($ligne.Length -gt 1024) {
            throw "Commande de première ouverture trop longue ($($ligne.Length) caractères, maximum 1024) : $description"
        }
        $cmds.Add(@"
                <SynchronousCommand wcm:action="add">
                    <Order>$ordre</Order>
                    <Description>$(& $esc $description)</Description>
                    <CommandLine>$(& $esc $ligne)</CommandLine>
                </SynchronousCommand>
"@)
    }

    if ($Apps.Count -gt 0) {
        # winget n'est PAS disponible tout de suite sur une installation neuve : le
        # paquet « App Installer » est approvisionné en tâche de fond, et la première
        # ouverture de session le précède souvent de plusieurs minutes. Sans cette
        # attente, les installations échouent toutes, en silence, et l'utilisateur
        # conclut que l'outil ne marche pas. On attend donc le RÉSEAU puis winget,
        # avec une borne : mieux vaut continuer sans les applications que bloquer
        # indéfiniment la première session de quelqu'un.
        # Tout est en chaînes SIMPLEMENT quotées : le code ci-dessous doit arriver
        # littéralement dans le fichier, pas être évalué ici. Une seule interpolation
        # au mauvais endroit et c'est la date de génération qui se retrouve gravée
        # dans le fichier de réponses, au lieu de la date d'exécution.
        $attendre = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "' +
        '$fin=(Get-Date).AddMinutes(10); ' +
        'while((Get-Date) -lt $fin -and -not (Get-NetConnectionProfile | Where-Object IPv4Connectivity -eq ''Internet'')) { Start-Sleep 15 }; ' +
        'while((Get-Date) -lt $fin -and -not (Get-Command winget -ErrorAction SilentlyContinue)) { Start-Sleep 15 }; ' +
        'Add-Content ''' + $journal + ''' ((Get-Date).ToString(''s'') + '' | winget disponible : '' + [bool](Get-Command winget -ErrorAction SilentlyContinue))' +
        '"'
        & $ajouteCmd "Attendre le reseau et winget" $attendre
        $ordre++
    }

    foreach ($id in $Apps) {
        # La redirection vers le journal transforme un échec muet en échec lisible.
        & $ajouteCmd "Installer $id" "cmd /c winget install -e --id $id --silent --accept-source-agreements --accept-package-agreements >> `"$journal`" 2>&1"
        $ordre++
    }

    if ($Profil) {
        # MadTweak est attendu a la racine de la cle, montee en general sur D:.
        # On le cherche sur tous les lecteurs plutot que de parier sur une lettre.
        # Le nom du profil voyage en ASCII pur, sans espace ni accent (« Minimal / sur »
        # devient « minimalsur ») : il traverse un XML puis une ligne de commande, et
        # Resolve-NomProfil le retrouve a l'arrivee. Un accent mal transcode ici se
        # solderait par un « profil inconnu » sur une machine fraichement installee,
        # ou personne ne lirait le message.
        # Plusieurs profils possibles. Chaque nom est réduit SÉPARÉMENT puis rejoint
        # par des virgules : la réduction supprime toute ponctuation, donc réduire la
        # liste entière d'un coup effacerait les séparateurs et fondrait les noms en
        # un seul mot illisible.
        $cleProfil = (($Profil -split ',' | ForEach-Object { $_.Trim() } |
                Where-Object { $_ } | ForEach-Object { ConvertTo-CleComparable $_ }) -join ',')
        # Le « else » n'est pas decoratif : si MadTweak.ps1 n'a pas ete copie sur la
        # cle, rien ne se passerait et rien ne le dirait. Le journal tranche entre
        # « le profil a echoue » et « le script n'etait pas la ».
        $chercher = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "' +
        '$s=Get-ChildItem -Path (Get-PSDrive -PSProvider FileSystem).Root -Filter MadTweak.ps1 -ErrorAction SilentlyContinue | Select-Object -First 1; ' +
        'if ($s) { Add-Content ''' + $journal + ''' (''MadTweak trouve : '' + $s.FullName); & $s.FullName -Profil ' + $cleProfil + ' } ' +
        'else { Add-Content ''' + $journal + ''' ''MadTweak.ps1 introuvable sur les lecteurs : profil NON applique.'' }"'
        & $ajouteCmd "Appliquer le profil MadTweak $cleProfil" $chercher
        $ordre++
    }

    if ($MotDePasse) {
        # La copie qu'on a posee dans Panther contient le mot de passe en base64.
        # Windows nettoie le fichier qu'il y met LUI-MEME, pas forcement celui qu'on
        # y a depose : sans cette ligne, le mot de passe resterait lisible sur le
        # disque de la machine installee. C'est la derniere commande jouee.
        & $ajouteCmd "Effacer la copie du fichier de reponses" 'cmd /c del /q "C:\Windows\Panther\unattend.xml"'
        $ordre++
    }

    $blocCmds = if ($cmds.Count -gt 0) {
        "            <FirstLogonCommands>`r`n" + ($cmds -join "`r`n") + "`r`n            </FirstLogonCommands>"
    }
    else { "" }

    # --- Contournements matériels (specialize) ------------------------------------
    $blocTPM = ""
    if ($SansTPM) {
        $blocTPM = @"
            <RunSynchronousCommand wcm:action="add">
                <Order>1</Order>
                <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassTPMCheck /t REG_DWORD /d 1 /f</Path>
            </RunSynchronousCommand>
            <RunSynchronousCommand wcm:action="add">
                <Order>2</Order>
                <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassSecureBootCheck /t REG_DWORD /d 1 /f</Path>
            </RunSynchronousCommand>
            <RunSynchronousCommand wcm:action="add">
                <Order>3</Order>
                <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassRAMCheck /t REG_DWORD /d 1 /f</Path>
            </RunSynchronousCommand>
            <RunSynchronousCommand wcm:action="add">
                <Order>4</Order>
                <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassCPUCheck /t REG_DWORD /d 1 /f</Path>
            </RunSynchronousCommand>
            <RunSynchronousCommand wcm:action="add">
                <Order>5</Order>
                <Path>reg add HKLM\SYSTEM\Setup\LabConfig /v BypassDiskCheck /t REG_DWORD /d 1 /f</Path>
            </RunSynchronousCommand>
            <RunSynchronousCommand wcm:action="add">
                <Order>6</Order>
                <Path>reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE /v BypassNRO /t REG_DWORD /d 1 /f</Path>
            </RunSynchronousCommand>
"@
    }


    # --- Disque : on n'efface RIEN sans demande explicite -------------------------
    # Sans -EffacerDisque, aucune section DiskConfiguration n'est ecrite : Windows
    # pose alors sa question habituelle, et l'utilisateur choisit sa partition.
    # Automatiser un formatage qu'on n'a pas demande serait la pire des surprises.
    $blocDisque = ""
    if ($EffacerDisque) {
        $blocDisque = @"
            <DiskConfiguration>
                <Disk wcm:action="add">
                    <DiskID>$Disque</DiskID>
                    <WillWipeDisk>true</WillWipeDisk>
                    <CreatePartitions>
                        <CreatePartition wcm:action="add"><Order>1</Order><Type>EFI</Type><Size>300</Size></CreatePartition>
                        <CreatePartition wcm:action="add"><Order>2</Order><Type>MSR</Type><Size>16</Size></CreatePartition>
                        <CreatePartition wcm:action="add"><Order>3</Order><Type>Primary</Type><Extend>true</Extend></CreatePartition>
                    </CreatePartitions>
                    <ModifyPartitions>
                        <ModifyPartition wcm:action="add"><Order>1</Order><PartitionID>1</PartitionID><Format>FAT32</Format><Label>System</Label></ModifyPartition>
                        <ModifyPartition wcm:action="add"><Order>2</Order><PartitionID>3</PartitionID><Format>NTFS</Format><Label>Windows</Label><Letter>C</Letter></ModifyPartition>
                    </ModifyPartitions>
                </Disk>
            </DiskConfiguration>
"@
    }

    # --- Choix de l'image et cible d'installation ---------------------------------
    # « For unattended installations, you must specify either the InstallTo or the
    # InstallToAvailablePartition setting » (doc Microsoft). Sans ce bloc, effacer
    # le disque laisse l'installeur sans cible : il efface, puis se bloque.
    $blocMeta = ""
    if ($Edition) {
        # ATTENTION aux trois raccourcis : ils fabriquent des noms ANGLAIS, et les
        # ISO localisées traduisent les noms d'édition. Une image française contient
        # « Windows 11 Professionnel », pas « Windows 11 Pro » — constaté sur une
        # vraie image. Le nom fabriqué ne correspondrait alors à rien et
        # l'installation échouerait. Les raccourcis ne valent que pour une image en
        # anglais ; partout ailleurs, il faut lire l'image (Get-EditionsImage).
        $nomEdition = switch ($Edition) {
            'Pro' { "Windows $Version Pro" }
            'Famille' { "Windows $Version Home" }
            'Entreprise' { "Windows $Version Enterprise" }
            # Tout le reste est pris tel quel : c'est un nom lu dans l'image.
            default { $Edition }
        }
        $blocMeta = @"
                    <InstallFrom>
                        <MetaData wcm:action="add">
                            <Key>/IMAGE/NAME</Key>
                            <Value>$(& $esc $nomEdition)</Value>
                        </MetaData>
                    </InstallFrom>
"@
    }

    $blocImage = ""
    if ($EffacerDisque -or $blocMeta) {
        # Partition 3 = la partition Windows creee plus haut (1=EFI, 2=MSR, 3=Windows).
        # Sans effacement, on ne fixe PAS de cible : l'utilisateur choisit la sienne.
        $cible = if ($EffacerDisque) {
            @"
                    <InstallTo>
                        <DiskID>$Disque</DiskID>
                        <PartitionID>3</PartitionID>
                    </InstallTo>
"@
        }
        else { "" }
        $blocImage = @"
            <ImageInstall>
                <OSImage>
$blocMeta$cible                    <WillShowUI>OnError</WillShowUI>
                </OSImage>
            </ImageInstall>
"@
    }

    # --- Clé produit --------------------------------------------------------------
    $blocCleProduit = if ($CleProduit) {
        @"
                <ProductKey>
                    <Key>$(& $esc $CleProduit)</Key>
                    <WillShowUI>Never</WillShowUI>
                </ProductKey>
"@
    }
    else {
        # Pas de Key : la documentation interdit d'en écrire une vide. WillShowUI
        # seul reste la seule façon documentée de demander le silence sur ce point.
        @"
                <ProductKey>
                    <WillShowUI>Never</WillShowUI>
                </ProductKey>
"@
    }

    # --- Mot de passe : vide = compte sans mot de passe ---------------------------
    $blocMdp = if ($MotDePasse) {
        @"
                        <Password>
                            <Value>$(ConvertTo-MotDePasseUnattend $MotDePasse)</Value>
                            <PlainText>false</PlainText>
                        </Password>
"@
    }
    else { "" }

    $xml = @"
<?xml version="1.0" encoding="utf-8"?>
<!--
    Fichier de reponses genere par MadTweak.
    A DEPOSER A LA RACINE de la cle d'installation Windows, a cote de setup.exe.

    Il ne contient aucun composant Microsoft : c'est un fichier de configuration.
    Relis-le avant usage, c'est du texte.
-->
<unattend xmlns="urn:schemas-microsoft-com:unattend">

    <settings pass="windowsPE">
        <component name="Microsoft-Windows-International-Core-WinPE" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <SetupUILanguage><UILanguage>$($L.UI)</UILanguage></SetupUILanguage>
            <InputLocale>$($L.Clavier)</InputLocale>
            <SystemLocale>$($L.Locale)</SystemLocale>
            <UILanguage>$($L.UI)</UILanguage>
            <UserLocale>$($L.Locale)</UserLocale>
        </component>
        <component name="Microsoft-Windows-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
$blocDisque
$blocImage
            <UserData>
                <AcceptEula>true</AcceptEula>
$blocCleProduit
            </UserData>
$(if ($SansTPM) { "            <RunSynchronous>`r`n$blocTPM`r`n            </RunSynchronous>" })
        </component>
    </settings>

    <settings pass="specialize"$attrPassage>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <ComputerName>$(& $esc $NomMachine)</ComputerName>
            <TimeZone>$(& $esc $Fuseau)</TimeZone>
        </component>
        <component name="Microsoft-Windows-Deployment" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <RunSynchronous>
                <!-- Ceinture-bretelles pour le compte local. Le compte est en fait
                     cree par le bloc LocalAccount du passage oobeSystem, plus bas.
                     Microsoft a retire le SCRIPT bypassnro.cmd en 24H2, mais pas
                     cette valeur de registre, qui fonctionne toujours (25H2 inclus). -->
                <RunSynchronousCommand wcm:action="add">
                    <Order>1</Order>
                    <Path>reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OOBE /v BypassNRO /t REG_DWORD /d 1 /f</Path>
                </RunSynchronousCommand>
$blocPanther
$blocQuestions
            </RunSynchronous>
        </component>
    </settings>

    <settings pass="oobeSystem"$attrPassage>
        <!-- Langue du Windows INSTALLE. Le composant « -WinPE » plus haut ne regle
             que l'installeur : sans ce bloc-ci, la machine installee repart en
             disposition par defaut, et on decouvre son clavier en QWERTY. -->
        <component name="Microsoft-Windows-International-Core" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <InputLocale>$($L.Clavier)</InputLocale>
            <SystemLocale>$($L.Locale)</SystemLocale>
            <UILanguage>$($L.UI)</UILanguage>
            <UserLocale>$($L.Locale)</UserLocale>
        </component>
        <component name="Microsoft-Windows-Shell-Setup" processorArchitecture="amd64" publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS" xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State">
            <!-- Liste exacte des reglages que Microsoft documente pour automatiser
                 l'OOBE (page « Automate OOBE »). SkipMachineOOBE et SkipUserOOBE en
                 sont volontairement ABSENTS : ils sont deprecies depuis Windows 10
                 1709 et la doc dit noir sur blanc de ne pas s'en servir pour ca.
                 HideWirelessSetupInOOBE reste a false EXPRES : sans reseau, les
                 installations winget de la premiere ouverture de session echouent. -->
            <OOBE>
                <HideEULAPage>true</HideEULAPage>
                <HideOEMRegistrationScreen>true</HideOEMRegistrationScreen>
                <HideOnlineAccountScreens>true</HideOnlineAccountScreens>
                <HideLocalAccountScreen>true</HideLocalAccountScreen>
                <HideWirelessSetupInOOBE>false</HideWirelessSetupInOOBE>
                <ProtectYourPC>3</ProtectYourPC>
            </OOBE>
            <UserAccounts>
                <LocalAccounts>
                    <LocalAccount wcm:action="add">
                        <Name>$(& $esc $NomUtilisateur)</Name>
                        <DisplayName>$(& $esc $NomUtilisateur)</DisplayName>
                        <Group>Administrators</Group>
$blocMdp
                    </LocalAccount>
                </LocalAccounts>
            </UserAccounts>
$blocCmds
        </component>
    </settings>

</unattend>
"@

    # UTF-8 SANS BOM : Windows Setup lit le fichier de reponses en UTF-8 et un BOM
    # peut le faire echouer. C'est la convention INVERSE des modules du projet.
    [System.IO.File]::WriteAllText($Chemin, $xml, (New-Object System.Text.UTF8Encoding($false)))

    # Verification immediate. On ne se contente PAS de verifier que le XML est bien
    # forme : un fichier parfaitement valide peut placer un reglage dans un passage
    # ou Windows l'ignorera sans rien dire. Test-AutounattendXml relit ce qu'on vient
    # d'ecrire et le juge sur le fond. Un probleme se voit ici, devant l'utilisateur,
    # et pas devant l'ecran d'installation d'une machine qu'on vient de formater.
    $pbs = Test-AutounattendXml -Chemin $Chemin
    if ($pbs.Count -gt 0) {
        throw "Le fichier genere est incorrect :`n  - $($pbs -join "`n  - ")"
    }

    return $Chemin
}


# ------------------------------------------------------------------------------
# MENU CONSOLE
# ------------------------------------------------------------------------------

function Read-ChoixListe {
    # Affiche une table ordonnée numérotée et renvoie la CLÉ choisie.
    # Entrée vide = la valeur par défaut : on peut dérouler tout le questionnaire
    # à coups d'Entrée et obtenir un fichier cohérent.
    param(
        [Parameter(Mandatory)]$Liste,
        [Parameter(Mandatory)][string]$Question,
        [int]$Defaut = 1,
        # Au-delà de ce nombre d'entrées, on n'affiche qu'un aperçu : la liste des
        # fuseaux horaires en compte près de 140, et les dérouler noierait la question.
        [int]$Apercu = 0
    )
    $cles = @($Liste.Keys)
    $tronque = ($Apercu -gt 0 -and $cles.Count -gt $Apercu)
    $fin = if ($tronque) { $Apercu } else { $cles.Count }
    for ($i = 0; $i -lt $fin; $i++) {
        $marque = if (($i + 1) -eq $Defaut) { "*" } else { " " }
        Write-Host ("   {0}{1,2} - {2}" -f $marque, ($i + 1), $cles[$i]) -ForegroundColor Gray
    }
    if ($tronque) {
        Write-Host ("    ... et " + ($cles.Count - $Apercu) + " autres — tape 0 pour tout voir.") -ForegroundColor DarkGray
    }
    $r = (Read-Host "  $Question [$Defaut]").Trim()
    if ($tronque -and $r -eq '0') {
        for ($i = 0; $i -lt $cles.Count; $i++) {
            Write-Host ("   {0,3} - {1}" -f ($i + 1), $cles[$i]) -ForegroundColor Gray
        }
        $r = (Read-Host "  $Question [$Defaut]").Trim()
    }
    if (-not $r) { $r = "$Defaut" }
    $n = 0
    if (-not [int]::TryParse($r, [ref]$n) -or $n -lt 1 -or $n -gt $cles.Count) {
        Write-Etat "Choix hors liste : on garde « $($cles[$Defaut - 1]) »." -Niveau Avert
        return $cles[$Defaut - 1]
    }
    return $cles[$n - 1]
}

function Menu-Installation {
    Clear-Host
    Write-Host "=== CLÉ D'INSTALLATION : FICHIER DE RÉPONSES ===" -ForegroundColor Magenta
    Write-Host ""
    Write-Host "  Génère un fichier autounattend.xml à déposer À LA RACINE de ta clé USB" -ForegroundColor Gray
    Write-Host "  Windows, à côté de setup.exe. L'installation ne pose alors plus de" -ForegroundColor Gray
    Write-Host "  questions : langue, compte, applications et tweaks sont déjà décidés." -ForegroundColor Gray
    Write-Host ""
    Write-Host "  MadTweak ne fournit AUCUNE image Windows : la licence Microsoft interdit" -ForegroundColor Yellow
    Write-Host "  de la redistribuer. Tu télécharges l'ISO officielle toi-même, et ce" -ForegroundColor Yellow
    Write-Host "  fichier vient simplement se poser à côté. C'est du texte, relis-le." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  À SAVOIR sur Windows 11 24H2 et 25H2 : le nouvel installeur de Microsoft" -ForegroundColor Cyan
    Write-Host "  applique bien le disque, l'édition et la langue, mais ignore souvent la" -ForegroundColor Cyan
    Write-Host "  partie « compte utilisateur » — l'écran de création de compte peut donc" -ForegroundColor Cyan
    Write-Host "  réapparaître. Un contournement est inclus, sans garantie possible." -ForegroundColor Cyan
    Write-Host "  Windows 10 et Windows 11 jusqu'à 23H2 ne sont pas concernés." -ForegroundColor Cyan
    Write-Host ""
    $script:CompteurOK = 0; $script:CompteurEchec = 0

    if (-not (Demander-Option "Créer un fichier de réponses maintenant ?")) { return }
    Write-Host ""

    # --- Cible ----------------------------------------------------------------
    $versions = [ordered]@{ "Windows 11" = "11"; "Windows 10" = "10" }
    $version = $versions[(Read-ChoixListe $versions "Quelle version de Windows ?" 1)]
    Write-Host ""

    $editions = [ordered]@{
        "Laisser l'installeur demander (le plus sûr)"    = ""
        "LIRE les éditions dans mon ISO / install.wim"   = "@LIRE"
        "Pro"                                           = "Pro"
        "Famille / Home"                                = "Famille"
        "Entreprise / Enterprise"                       = "Entreprise"
    }
    Write-Host "  Un nom d'édition absent de l'image fait échouer l'installation. Plutôt que" -ForegroundColor DarkGray
    Write-Host "  de deviner, l'option 2 ouvre ton ISO et lit les éditions qu'elle contient." -ForegroundColor DarkGray
    $edition = $editions[(Read-ChoixListe $editions "Quelle édition ?" 1)]

    if ($edition -eq "@LIRE") {
        $edition = ""
        $chemImage = (Read-Host "  Chemin de l'ISO, du install.wim ou du install.esd").Trim().Trim('"')
        try {
            Write-Etat "Lecture de l'image (le montage prend quelques secondes)..." -Niveau Info
            $trouvees = Get-EditionsImage -Chemin $chemImage
            if ($trouvees.Count -eq 0) { throw "Aucune édition trouvée dans cette image." }
            $choix = [ordered]@{}
            foreach ($e in $trouvees) { $choix["$($e.Nom)  (index $($e.Index))"] = $e.Nom }
            Write-Host ""
            Write-Etat "$($trouvees.Count) édition(s) réellement présente(s) dans cette image :" -Niveau OK
            $edition = $choix[(Read-ChoixListe $choix "Laquelle installer ?" 1)]
        }
        catch {
            Write-Etat "Lecture impossible : $($_.Exception.Message)" -Niveau Avert
            Write-Etat "On continue sans préciser l'édition : l'installeur posera la question." -Niveau Info
        }
    }
    Write-Host ""

    # --- Langue et fuseau -----------------------------------------------------
    $langues = Get-LanguesInstallation
    $langue = Read-ChoixListe $langues "Langue et clavier ?" 1
    Write-Host ""
    $fuseaux = Get-FuseauxCourants
    $fuseau = $fuseaux[(Read-ChoixListe $fuseaux "Fuseau horaire ?" 1 -Apercu 6)]
    Write-Host ""

    # --- Compte ---------------------------------------------------------------
    $utilisateur = (Read-Host "  Nom du compte à créer").Trim()
    if (-not $utilisateur) {
        Write-Etat "Aucun nom d'utilisateur : abandon." -Niveau Avert
        if (-not (Test-SansInteraction)) { Read-Host "`nEntrée pour revenir" }
        return
    }

    Write-Host ""
    Write-Host "  ATTENTION : dans un fichier de réponses, un mot de passe n'est PAS" -ForegroundColor Red
    Write-Host "  chiffré. Il est encodé en base64, ce qui se relit en une commande par" -ForegroundColor Red
    Write-Host "  quiconque a la clé USB en main. Laisse VIDE pour créer un compte sans" -ForegroundColor Red
    Write-Host "  mot de passe et en définir un au premier démarrage : c'est plus sûr." -ForegroundColor Red
    $motDePasse = (Read-Host "  Mot de passe (vide = aucun)")
    Write-Host ""

    $machine = (Read-Host "  Nom de la machine (vide = généré)").Trim()

    # --- Profil MadTweak ------------------------------------------------------
    Write-Host ""
    Write-Host "  Les profils seront appliqués à la première ouverture de session, à" -ForegroundColor DarkGray
    Write-Host "  condition que MadTweak.ps1 soit copié à la racine de la même clé." -ForegroundColor DarkGray
    Write-Host "  Tu peux en combiner PLUSIEURS : sur une machine neuve, un seul ne" -ForegroundColor DarkGray
    Write-Host "  suffit généralement pas. « Gamer » règle la latence et les FPS mais" -ForegroundColor DarkGray
    Write-Host "  ne touche pas à l'apparence — le thème sombre et la barre des tâches" -ForegroundColor DarkGray
    Write-Host "  à gauche sont dans « Interface épurée »." -ForegroundColor DarkGray
    Write-Host ""
    $nomsProfils = @($script:Profils.Keys)
    for ($i = 0; $i -lt $nomsProfils.Count; $i++) {
        Write-Host ("   {0,2} - {1}" -f ($i + 1), $nomsProfils[$i]) -ForegroundColor Gray
    }
    Write-Host "    0 - Aucun" -ForegroundColor Gray
    $rep = (Read-Host "  Numéros séparés par une virgule (ex : 1,4) [0]").Trim()
    $choisis = @()
    foreach ($m in ($rep -split ',')) {
        $n = 0
        if ([int]::TryParse($m.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $nomsProfils.Count) {
            $choisis += $nomsProfils[$n - 1]
        }
    }
    $choisis = @($choisis | Select-Object -Unique)
    $profil = ($choisis -join ',')
    if ($choisis.Count -gt 0) {
        # Le cumul se voit tout de suite : additionner deux profils ne double pas
        # le nombre de tweaks, ils se recouvrent en partie.
        $cumul = @()
        foreach ($p in $choisis) { $cumul += $script:Profils[$p].Cles }
        Write-Etat "$($choisis.Count) profil(s) : $($choisis -join ' + ') — $((@($cumul | Select-Object -Unique)).Count) tweaks au total." -Niveau OK
    }
    else { Write-Etat "Aucun profil : rien ne sera appliqué au premier démarrage." -Niveau Info }
    Write-Host ""

    # --- Applications ---------------------------------------------------------
    $apps = @()
    if (Demander-Option "Installer des applications au premier démarrage ?") {
        $noms = @($script:CatalogueApps.Keys)
        for ($i = 0; $i -lt $noms.Count; $i++) {
            Write-Host ("   {0,2} - {1}" -f ($i + 1), $noms[$i]) -ForegroundColor Gray
        }
        $rep = (Read-Host "  Numéros séparés par une virgule (ex : 2,4,10)").Trim()
        foreach ($m in ($rep -split ',')) {
            $n = 0
            if ([int]::TryParse($m.Trim(), [ref]$n) -and $n -ge 1 -and $n -le $noms.Count) {
                $apps += $script:CatalogueApps[$noms[$n - 1]]
            }
        }
        $apps = @($apps | Select-Object -Unique)
        Write-Etat "$($apps.Count) application(s) retenue(s)." -Niveau Info
    }
    Write-Host ""

    # --- Matériel ancien ------------------------------------------------------
    $sansTpm = $false
    if ($version -eq '11') {
        $sansTpm = Demander-Option "Contourner les contrôles TPM / Secure Boot / RAM (machine ancienne) ?"
        Write-Host ""
    }

    # --- Disque : la seule question réellement destructrice -------------------
    Write-Host "  Par défaut, l'installeur demandera OÙ installer Windows, comme d'habitude." -ForegroundColor Gray
    Write-Host "  Tu peux aussi lui dire d'effacer entièrement le premier disque. Dans ce" -ForegroundColor Gray
    Write-Host "  cas il ne demandera plus rien et TOUT le disque 0 sera perdu." -ForegroundColor Gray
    $effacer = $false
    $numDisque = 0
    if (Demander-Option "Effacer automatiquement un disque entier ?") {
        Write-Host ""
        # Les disques affichés sont ceux de CETTE machine. Sur la machine à installer,
        # la numérotation peut différer — c'est dit, parce que se tromper de disque
        # ici efface les données de quelqu'un.
        Write-Host "  Disques de CETTE machine, à titre indicatif :" -ForegroundColor Gray
        try {
            foreach ($dq in (Get-Disk -ErrorAction Stop | Sort-Object Number)) {
                Write-Host ("    disque {0} — {1} Go — {2}" -f $dq.Number,
                    [math]::Round($dq.Size / 1GB), $dq.FriendlyName) -ForegroundColor DarkGray
            }
        }
        catch { Write-Host "    (liste indisponible)" -ForegroundColor DarkGray }
        Write-Host "  ATTENTION : la numérotation de la machine à installer peut être" -ForegroundColor Yellow
        Write-Host "  différente. Vérifie-la là-bas (Maj+F10, puis diskpart, list disk)." -ForegroundColor Yellow
        Write-Host "  Et surtout : selon le micrologiciel, la CLÉ USB elle-même peut" -ForegroundColor Yellow
        Write-Host "  apparaître comme disque 0. L'effacer effacerait le support depuis" -ForegroundColor Yellow
        Write-Host "  lequel l'installation tourne. Dans le doute, laisse cette option de" -ForegroundColor Yellow
        Write-Host "  côté : l'installeur posera simplement la question, ce qui ne coûte" -ForegroundColor Yellow
        Write-Host "  qu'un clic et supprime tout risque de se tromper de disque." -ForegroundColor Yellow
        $rep = (Read-Host "  Numéro du disque à effacer [0]").Trim()
        if ($rep -and -not [int]::TryParse($rep, [ref]$numDisque)) { $numDisque = 0 }
        if (-not $rep) { $numDisque = 0 }

        Write-Host ""
        Write-Host "  Cette option détruit TOUTES les partitions du disque $numDisque, sans" -ForegroundColor Red
        Write-Host "  confirmation au moment de l'installation. Tape EFFACER pour l'activer." -ForegroundColor Red
        $effacer = ((Read-Host "  Confirmation").Trim() -ceq "EFFACER")
        if (-not $effacer) { Write-Etat "Effacement NON activé : l'installeur posera la question." -Niveau Info }
    }
    Write-Host ""

    # --- Génération -----------------------------------------------------------
    $dossier = Join-Path ([Environment]::GetFolderPath("Desktop")) "madtweak-installation"
    $chemin = Join-Path $dossier "autounattend.xml"

    if ($script:Simulation) {
        Write-Simu "générerait $chemin (Windows $version, compte « $utilisateur », $($apps.Count) app(s), effacement : $effacer)"
        if (-not (Test-SansInteraction)) { Read-Host "`nEntrée pour revenir" }
        return
    }

    try {
        if (-not (Test-Path $dossier)) { New-Item -ItemType Directory -Path $dossier -Force | Out-Null }
        $params = @{
            Chemin         = $chemin
            NomUtilisateur = $utilisateur
            MotDePasse     = $motDePasse
            NomMachine     = $machine
            Langue         = $langue
            Fuseau         = $fuseau
            Version        = $version
            Edition        = $edition
            Apps           = $apps
        }
        if ($profil) { $params.Profil = $profil }
        if ($sansTpm) { $params.SansTPM = $true }
        if ($effacer) { $params.EffacerDisque = $true }

        New-AutounattendXml @params | Out-Null

        Write-Host ""
        Write-Etat "Fichier généré : $chemin" -Niveau OK
        Write-Host ""
        Write-Host "  Le parcours complet :" -ForegroundColor Cyan
        Write-Host "   1. Télécharger l'ISO officielle (Media Creation Tool ou Rufus)." -ForegroundColor Gray
        Write-Host "   2. Écrire l'ISO sur la clé avec l'un de ces deux outils." -ForegroundColor Gray
        Write-Host "   3. Déposer les fichiers à la racine de la clé — MadTweak sait le faire." -ForegroundColor Gray
        Write-Host ""

        # --- Préparer la clé de A à Z : la seule opération destructive de l'outil ---
        $usb = @(Get-DisquesUSB)
        if ($usb.Count -gt 0 -and (Demander-Option "Préparer entièrement une clé USB à partir d'une ISO (EFFACE la clé) ?")) {
            Write-Host ""
            Write-Host "  Seules les clés USB sont proposées. Les disques internes n'apparaissent" -ForegroundColor Gray
            Write-Host "  pas dans cette liste et ne peuvent pas être effacés par cette fonction." -ForegroundColor Gray
            Write-Host ""
            $choixUsb = [ordered]@{}
            foreach ($u in $usb) {
                $choixUsb["Disque $($u.Numero) — $($u.Nom) — $($u.Go) Go — $($u.Lettres) $($u.Contenu)"] = $u
            }
            $cible = $choixUsb[(Read-ChoixListe $choixUsb "Quelle clé préparer ?" 1)]
            $iso = (Read-Host "  Chemin de l'ISO Windows officielle").Trim().Trim('"')

            # Si l'édition n'a pas encore été fixée, c'est le moment : on tient l'ISO,
            # autant lui demander ce qu'elle contient plutôt que de le supposer. Les
            # noms sont traduits dans les images localisées (« Windows 11 Professionnel »
            # et non « Windows 11 Pro »), donc les deviner ne marche pas.
            if (-not $edition -and (Test-Path -LiteralPath $iso)) {
                try {
                    Write-Etat "Lecture des éditions de l'image..." -Niveau Info
                    $dispo = Get-EditionsImage -Chemin $iso
                    $choixEd = [ordered]@{}
                    foreach ($e in $dispo) { $choixEd["$($e.Nom)  (index $($e.Index))"] = $e.Nom }
                    $edition = $choixEd[(Read-ChoixListe $choixEd "Quelle édition installer ?" 1 -Apercu 12)]

                    # Le fichier de réponses a été écrit sans édition : on le régénère
                    # avec celle-ci, sinon la clé et le fichier ne diraient pas la
                    # même chose et l'installation s'arrêterait.
                    New-AutounattendXml -Chemin $chemin -NomUtilisateur $utilisateur -MotDePasse $motDePasse `
                        -NomMachine $machine -Langue $langue -Fuseau $fuseau -Version $version `
                        -Edition $edition -Apps $apps -Profil $profil `
                        -SansTPM:$sansTpm -EffacerDisque:$effacer -Disque $numDisque | Out-Null
                    Write-Etat "Fichier de réponses réaligné sur « $edition »." -Niveau OK
                }
                catch { Write-Etat "Lecture des éditions impossible : $($_.Exception.Message)" -Niveau Avert }
            }

            Write-Host ""
            Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Red
            Write-Host "   TOUT LE CONTENU de cette clé va être DÉFINITIVEMENT SUPPRIMÉ :" -ForegroundColor Red
            Write-Host ("     Disque {0} — {1}" -f $cible.Numero, $cible.Nom) -ForegroundColor Red
            Write-Host ("     {0} Go — {1} {2}" -f $cible.Go, $cible.Lettres, $cible.Contenu) -ForegroundColor Red
            Write-Host "   C'est la seule opération de MadTweak qui ne s'annule pas." -ForegroundColor Red
            Write-Host "   Vérifie que c'est la bonne clé, et qu'elle ne contient rien d'utile." -ForegroundColor Red
            Write-Host "  ═══════════════════════════════════════════════════════════════" -ForegroundColor Red
            Write-Host ""
            Write-Host "  Tape EFFACER en majuscules pour confirmer, autre chose pour renoncer." -ForegroundColor Yellow
            if ((Read-Host "  Confirmation").Trim() -ceq "EFFACER") {
                $srcMt = $null
                if ($profil) {
                    foreach ($cand in @($PSCommandPath, $MyInvocation.MyCommand.Path)) {
                        if ($cand -and $cand.EndsWith('.ps1') -and (Test-Path $cand)) { $srcMt = $cand; break }
                    }
                }
                try {
                    New-CleInstallation -NumeroDisque $cible.Numero -CheminIso $iso `
                        -CheminXml $chemin -CheminMadTweak $srcMt -Edition $edition -Confirme | Out-Null
                    Write-Etat "La clé est prête : ISO, fichier de réponses et MadTweak sont dessus." -Niveau OK
                }
                catch { Write-Etat "Préparation impossible : $($_.Exception.Message)" -Niveau Echec }
            }
            else { Write-Etat "Renoncé. La clé n'a pas été touchée." -Niveau Info }
            if (-not (Test-SansInteraction)) { Read-Host "`nEntrée pour revenir" }
            return
        }

        # --- Sinon : déposer les fichiers sur une clé DÉJÀ préparée ---------------
        $cles = @(Get-ClesInstallation)
        $pretes = @($cles | Where-Object EstSupport)
        if ($pretes.Count -eq 0) {
            if ($cles.Count -gt 0) {
                Write-Etat "Support amovible détecté, mais aucun ne porte de setup.exe : la clé n'est pas encore préparée." -Niveau Info
            }
            Write-Etat "Prépare la clé avec l'ISO, puis reviens ici : la copie te sera proposée." -Niveau Info
        }
        elseif (Demander-Option "Copier maintenant les fichiers sur la clé d'installation ?") {
            $choixCle = [ordered]@{}
            foreach ($c in $pretes) {
                $choixCle["$($c.Lettre): — $($c.Nom) — $($c.Go) Go"] = $c.Lettre
            }
            $lettre = $choixCle[(Read-ChoixListe $choixCle "Quelle clé ?" 1)]

            # Sans MadTweak.ps1 sur la clé, le profil ne s'appliquera jamais. On ne
            # le copie donc que s'il y a un profil, mais alors on y tient.
            $srcMadTweak = $null
            if ($profil) {
                foreach ($cand in @($PSCommandPath, $MyInvocation.MyCommand.Path)) {
                    if ($cand -and $cand.EndsWith('.ps1') -and (Test-Path $cand)) { $srcMadTweak = $cand; break }
                }
                if (-not $srcMadTweak) {
                    Write-Etat "Impossible de localiser MadTweak.ps1 : seul le fichier de réponses sera copié." -Niveau Avert
                    Write-Etat "Copie-le toi-même à la racine de la clé, sinon le profil ne s'appliquera pas." -Niveau Avert
                }
            }
            try {
                $faits = Copy-FichiersVersCle -Lettre $lettre -CheminXml $chemin -CheminMadTweak $srcMadTweak
                foreach ($fic in $faits) { Write-Etat "Copié : $fic" -Niveau OK }
                Write-Etat "La clé est prête. L'installation ne posera plus de questions." -Niveau OK
            }
            catch {
                Write-Etat "Copie impossible : $($_.Exception.Message)" -Niveau Echec
            }
        }
        Write-Host ""
        if ($motDePasse) {
            Write-Etat "Rappel : le mot de passe est lisible dans ce fichier. Ne prête pas la clé." -Niveau Avert
        }
        $script:CompteurOK++
    }
    catch {
        Write-Etat "Génération impossible : $($_.Exception.Message)" -Niveau Echec
        $script:CompteurEchec++
    }

    if (-not (Test-SansInteraction)) {
        if (-not (Test-SansInteraction)) { Read-Host "`nAppuie sur Entrée pour revenir au menu principal" }
    }
}

function Add-PilotesVersCle {
    # Copie les fichiers de pilotes (.inf, .sys, .cat) d'un dossier vers $WinPEDriver$ à la racine de la clé.
    param(
        [Parameter(Mandatory)][string]$LettreCle,
        [Parameter(Mandatory)][string]$DossierPilotesSource
    )
    $racine = ($LettreCle.TrimEnd(':', '\')) + ":\"
    if (-not (Test-Path $racine)) { throw "Clé USB introuvable : $racine" }
    if (-not (Test-Path $DossierPilotesSource)) { throw "Dossier pilotes introuvable : $DossierPilotesSource" }

    $cibles = Join-Path $racine '$WinPEDriver$'
    if (-not (Test-Path $cibles)) { New-Item -ItemType Directory -Path $cibles -Force | Out-Null }

    Write-Etat (T 'install.drivers.copie') -Niveau Info
    $fichiers = Get-ChildItem -Path $DossierPilotesSource -Recurse -Include *.inf, *.sys, *.cat -ErrorAction SilentlyContinue
    $copies = 0
    foreach ($f in $fichiers) {
        $dest = Join-Path $cibles $f.Name
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force -ErrorAction SilentlyContinue
        $copies++
    }

    Write-Etat ((T 'install.drivers.ok') -f $copies) -Niveau OK
    return $copies
}

function Export-AutounattendConfig {
    # Exporte la configuration d'installation dans un modèle JSON réutilisable.
    param(
        [Parameter(Mandatory)][string]$CheminSortieJson,
        [Parameter(Mandatory)][hashtable]$Configuration
    )
    $json = $Configuration | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText($CheminSortieJson, $json, [System.Text.Encoding]::UTF8)
    Write-Etat ((T 'install.template.export') -f $CheminSortieJson) -Niveau OK
    return $CheminSortieJson
}

function Import-AutounattendConfig {
    # Importe la configuration d'installation depuis un modèle JSON.
    param([Parameter(Mandatory)][string]$CheminJsonSource)
    if (-not (Test-Path $CheminJsonSource)) { throw "Fichier JSON introuvable : $CheminJsonSource" }

    $json = [System.IO.File]::ReadAllText($CheminJsonSource, [System.Text.Encoding]::UTF8)
    $cfg = $json | ConvertFrom-Json
    Write-Etat (T 'install.template.import') -Niveau OK
    return $cfg
}

function Optimize-ImageWim {
    # Extrait une seule édition d'un fichier WIM vers une nouvelle image plus compacte.
    param(
        [Parameter(Mandatory)][string]$CheminWimSource,
        [Parameter(Mandatory)][string]$NomEdition,
        [Parameter(Mandatory)][string]$CheminWimDestination
    )
    if (-not (Test-Path $CheminWimSource)) { throw "Fichier WIM introuvable : $CheminWimSource" }

    $images = @(Get-WindowsImage -ImagePath $CheminWimSource -ErrorAction Stop)
    $trouve = $images | Where-Object { $_.ImageName -eq $NomEdition } | Select-Object -First 1
    if (-not $trouve) { throw "Édition $NomEdition introuvable dans $CheminWimSource." }

    Export-WindowsImage -SourceImagePath $CheminWimSource -SourceIndex $trouve.ImageIndex `
        -DestinationImagePath $CheminWimDestination -CompressionType Max -ErrorAction Stop | Out-Null

    $tailleGo = [math]::Round((Get-Item $CheminWimDestination).Length / 1GB, 2)
    Write-Etat ((T 'install.wim.optimise') -f $tailleGo) -Niveau OK
    return $CheminWimDestination
}

function Optimize-IsoWindows {
    # Monte l'image WIM, supprime les applications provisionnées UWP indésirables et démonte en enregistrant.
    param(
        [Parameter(Mandatory)][string]$CheminWim,
        [int]$IndexImage = 1,
        [string[]]$PackagesASupprimer = @('Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.GetHelp', 'Microsoft.Getstarted', 'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.People', 'Microsoft.WindowsFeedbackHub', 'Microsoft.YourPhone', 'Microsoft.ZuneVideo', 'Microsoft.ZuneMusic')
    )
    if (-not (Test-Path $CheminWim)) { throw "Fichier WIM introuvable : $CheminWim" }

    $dossierMontage = Join-Path $env:TEMP ("wim-mount-" + [guid]::NewGuid().ToString().Substring(0, 8))
    if (-not (Test-Path $dossierMontage)) { New-Item -ItemType Directory -Path $dossierMontage -Force | Out-Null }

    Write-Etat (T 'wim.debloat.debut') -Niveau Info

    try {
        Mount-WindowsImage -ImagePath $CheminWim -Index $IndexImage -Path $dossierMontage -ErrorAction Stop | Out-Null
        $suppr = 0

        $pkgs = @(Get-AppxProvisionedPackage -Path $dossierMontage -ErrorAction SilentlyContinue)
        foreach ($p in $pkgs) {
            foreach ($cible in $PackagesASupprimer) {
                if ($p.DisplayName -like "*$cible*") {
                    Remove-AppxProvisionedPackage -Path $dossierMontage -PackageName $p.PackageName -ErrorAction SilentlyContinue | Out-Null
                    $suppr++
                }
            }
        }

        Dismount-WindowsImage -Path $dossierMontage -Save -ErrorAction Stop | Out-Null
        if (Test-Path $dossierMontage) { Remove-Item $dossierMontage -Force -Recurse -ErrorAction SilentlyContinue }
        Write-Etat ((T 'wim.debloat.ok') -f $suppr) -Niveau OK
        return $suppr
    }
    catch {
        try { Dismount-WindowsImage -Path $dossierMontage -Discard -ErrorAction SilentlyContinue | Out-Null } catch { }
        if (Test-Path $dossierMontage) { Remove-Item $dossierMontage -Force -Recurse -ErrorAction SilentlyContinue }
        throw $_
    }
}

function New-IsoMadTweakBootable {
    # Construit une image ISO .iso bootable UEFI à partir d'un dossier source à l'aide d'oscdimg.exe.
    param(
        [Parameter(Mandatory)][string]$DossierSource,
        [Parameter(Mandatory)][string]$CheminIsoSortie,
        [string]$LabelVolume = "MADTWEAK_WIN11"
    )
    if (-not (Test-Path $DossierSource)) { throw "Dossier source introuvable : $DossierSource" }

    $oscdimg = Get-Command oscdimg.exe -ErrorAction SilentlyContinue
    if (-not $oscdimg) {
        $cands = @("$env:ProgramFiles(x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\amd64\Oscdimg\oscdimg.exe", "$env:SystemRoot\System32\oscdimg.exe")
        foreach ($c in $cands) { if (Test-Path $c) { $oscdimg = $c; break } }
    }
    if (-not $oscdimg) {
        throw "oscdimg.exe est introuvable. Installe Windows ADK (Deployment Tools) pour reconstruire des images ISO."
    }

    $bootFile = Join-Path $DossierSource "boot\etfsboot.com"
    $efisys = Join-Path $DossierSource "efi\microsoft\boot\efisys.bin"
    $bootArg = "-b`"$bootFile`""
    if (Test-Path $efisys) {
        $bootArg = "-p00 -e -b`"$efisys`""
    }

    $args = @("-m", "-o", "-u2", "-udfver102", $bootArg, "-l$LabelVolume", $DossierSource, $CheminIsoSortie)
    Invoke-Externe $oscdimg $args

    if (Test-Path $CheminIsoSortie) {

        $tailleGo = [math]::Round((Get-Item $CheminIsoSortie).Length / 1GB, 2)
        Write-Etat ((T 'iso.bootable.ok') -f $tailleGo, $CheminIsoSortie) -Niveau OK
        return $CheminIsoSortie
    } else {
        throw "Échec de la génération ISO par oscdimg."
    }
}



