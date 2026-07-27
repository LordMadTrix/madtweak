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
# avec un profil. Les 150 tweaks, la sauvegarde et l'annulation exacte continuent
# donc de fonctionner à l'identique — rien n'est dupliqué.
# ------------------------------------------------------------------------------

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
        [ValidateSet('', 'Pro', 'Famille', 'Entreprise')][string]$Edition = '',
        [string]$MotDePasse = "",
        [string]$NomMachine = "",
        [string]$Langue = "Francais (Belgique)",
        [string]$Fuseau = "Romance Standard Time",
        [string]$Profil,
        [string[]]$Apps = @(),
        [switch]$SansTPM,
        [switch]$EffacerDisque
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

    # Recopie du fichier de réponses vers Panther (voir le passage specialize).
    # On le cherche sur TOUS les lecteurs : une clé USB n'a aucune lettre garantie.
    $copiePanther = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "$f=Get-ChildItem -Path (Get-PSDrive -PSProvider FileSystem).Root -Filter autounattend.xml -ErrorAction SilentlyContinue | Select-Object -First 1; if ($f) { Copy-Item $f.FullName ''C:\Windows\Panther\unattend.xml'' -Force }"'

    # --- Commandes de première ouverture de session -------------------------------
    # Elles s'exécutent une fois, en tant que l'utilisateur créé, session ouverte.
    $cmds = New-Object System.Collections.Generic.List[string]
    $ordre = 1
    $ajouteCmd = {
        param($description, $ligne)
        $cmds.Add(@"
                <SynchronousCommand wcm:action="add">
                    <Order>$ordre</Order>
                    <Description>$(& $esc $description)</Description>
                    <CommandLine>$(& $esc $ligne)</CommandLine>
                </SynchronousCommand>
"@)
    }

    foreach ($id in $Apps) {
        & $ajouteCmd "Installer $id" "cmd /c winget install -e --id $id --silent --accept-source-agreements --accept-package-agreements"
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
        $cleProfil = ConvertTo-CleComparable $Profil
        $chercher = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=Get-ChildItem -Path (Get-PSDrive -PSProvider FileSystem).Root -Filter MadTweak.ps1 -ErrorAction SilentlyContinue | Select-Object -First 1; if ($s) { & $s.FullName -Profil ' + $cleProfil + ' }"'
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
                    <DiskID>0</DiskID>
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
        $nomEdition = switch ($Edition) {
            'Pro'        { "Windows $Version Pro" }
            'Famille'    { "Windows $Version Home" }
            'Entreprise' { "Windows $Version Enterprise" }
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
                        <DiskID>0</DiskID>
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
            </UserData>
$(if ($SansTPM) { "            <RunSynchronous>`r`n$blocTPM`r`n            </RunSynchronous>" })
        </component>
    </settings>

    <settings pass="specialize">
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
                <!-- Recopie du fichier de reponses dans Panther. Depuis 24H2, et
                     surtout en 25H2, le nouvel installeur (SetupPrep.exe, dit
                     « ConX ») lit bien le passage windowsPE mais ignore souvent
                     oobeSystem : le compte local n'est alors pas cree et l'OOBE
                     repose ses questions. Relire le fichier depuis Panther est le
                     chemin historique, et cette copie ne coute rien la ou l'ancien
                     installeur fonctionnait deja. -->
                <RunSynchronousCommand wcm:action="add">
                    <Order>2</Order>
                    <Path>$(& $esc $copiePanther)</Path>
                </RunSynchronousCommand>
$blocQuestions
            </RunSynchronous>
        </component>
    </settings>

    <settings pass="oobeSystem">
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

    # Verification immediate : un XML mal forme se voit ici, pas devant l'ecran
    # d'installation d'une machine qu'on vient de formater.
    try { [xml](Get-Content $Chemin -Raw) | Out-Null }
    catch { throw "Le fichier genere n'est pas un XML valide : $($_.Exception.Message)" }

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
        "Laisser l'installeur demander (le plus sûr)" = ""
        "Pro"                                        = "Pro"
        "Famille / Home"                             = "Famille"
        "Entreprise / Enterprise"                    = "Entreprise"
    }
    Write-Host "  L'édition n'est à préciser que si tu es SÛR de ce que contient l'ISO :" -ForegroundColor DarkGray
    Write-Host "  un nom d'édition absent de l'image fait échouer l'installation." -ForegroundColor DarkGray
    $edition = $editions[(Read-ChoixListe $editions "Quelle édition ?" 1)]
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
    $profils = [ordered]@{ "Aucun (ne rien appliquer)" = "" }
    foreach ($k in $script:Profils.Keys) { $profils[$k] = $k }
    Write-Host "  Le profil sera appliqué à la première ouverture de session, à condition" -ForegroundColor DarkGray
    Write-Host "  que MadTweak.ps1 soit copié à la racine de la même clé USB." -ForegroundColor DarkGray
    $profil = $profils[(Read-ChoixListe $profils "Quel profil appliquer ?" 1)]
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
    if (Demander-Option "Effacer automatiquement le disque 0 ?") {
        Write-Host ""
        Write-Host "  Cette option détruit toutes les partitions du disque 0, sans confirmation" -ForegroundColor Red
        Write-Host "  au moment de l'installation. Tape EFFACER en majuscules pour l'activer." -ForegroundColor Red
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
        Write-Host "  Ce qu'il reste à faire :" -ForegroundColor Cyan
        Write-Host "   1. Prépare ta clé USB avec l'ISO officielle (Rufus, ou l'outil Microsoft)." -ForegroundColor Gray
        Write-Host "   2. Copie autounattend.xml À LA RACINE de la clé, à côté de setup.exe." -ForegroundColor Gray
        if ($profil) {
            Write-Host "   3. Copie AUSSI MadTweak.ps1 à la racine de la clé : sans lui, le profil" -ForegroundColor Yellow
            Write-Host "      « $profil » ne sera pas appliqué." -ForegroundColor Yellow
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
        Read-Host "`nAppuie sur Entrée pour revenir au menu principal"
    }
}
