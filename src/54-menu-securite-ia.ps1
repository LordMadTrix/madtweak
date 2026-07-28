# ------------------------------------------------------------------------------
# MISES À JOUR, SÉCURITÉ & IA
# ------------------------------------------------------------------------------
# Copilot et Recall vivaient dans le switch d'un menu piloté par Read-Host, donc
# inaccessibles à un profil (qui ne peut pas répondre à une invite). Les voici en
# fonctions autonomes : le menu les appelle, les profils aussi, sans duplication.
function Invoke-TweakCopilot {
    Invoke-Tweak "Désactiver Windows Copilot ?" -Cle "copilot" `
        -Explication "Retire le bouton Copilot et pose la stratégie qui le désactive. Comme cette ancienne stratégie ne couvre pas le Copilot moderne livré depuis 24H2 (devenu une simple application du Store), le script DÉSINSTALLE aussi cette application : c'est le seul moyen fiable. Tu peux la réinstaller depuis le Store." {
        # Source : Microsoft Learn, WindowsAI Policy CSP (maj 23/06/2026).
        # TurnOffWindowsCopilot est de portée UTILISATEUR uniquement (Scope :
        # Device = non, User = oui) : écrire dans HKLM ne sert donc à rien.
        # Microsoft la marque aussi "deprecated", et elle ne couvre PAS le
        # nouveau Copilot (l'app du Store) livré depuis 24H2.
        Set-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot" -Name "TurnOffWindowsCopilot" -Value 1
        Set-RegValue -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced" -Name "ShowCopilotButton" -Value 0

        # Le seul moyen fiable contre le Copilot moderne : désinstaller l'app.
        $app = Get-AppxPackage -Name "Microsoft.Copilot" -ErrorAction SilentlyContinue
        if ($app) {
            Invoke-Action "désinstallerait l'app Microsoft.Copilot" { Remove-AppxPackage -Package $app.PackageFullName -ErrorAction Stop }
            if (-not $script:Simulation) { Write-Etat "App Copilot désinstallée." -Niveau OK }
        }
        else {
            Write-Etat "L'app Copilot n'est pas installée ici : seule l'ancienne stratégie a été posée." -Niveau Info
        }
        if ($script:EstFamille) {
            Write-Etat "Microsoft ne documente cette stratégie que pour Pro/Entreprise/Éducation : son effet sur Famille n'est pas garanti." -Niveau Avert
        }
    }
}

function Invoke-TweakRecall {
    Invoke-Tweak "Désactiver Recall et l'analyse de données par l'IA ?" -Cle "recall" `
        -Explication "Recall capture périodiquement ton écran et l'indexe pour te permettre de « remonter le temps ». Ce réglage le désactive, retire ses fichiers et supprime les captures déjà enregistrées. Sur un PC Copilot+, où Recall est une vraie fonctionnalité Windows, le composant est carrément retiré (redémarrage nécessaire)." {
        # Source : Microsoft Learn, WindowsAI Policy CSP (maj 23/06/2026).
        # DisableAIDataAnalysis est de portée Device ET User : les deux servent.
        # Requiert 24H2 build 26100.3915+ (KB5055627).
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1
        Set-RegValue -Path "HKCU:\Software\Policies\Microsoft\Windows\WindowsAI" -Name "DisableAIDataAnalysis" -Value 1

        # Plus radical que le précédent : met le composant Recall à l'état
        # désactivé, RETIRE ses fichiers de la machine et supprime les captures
        # déjà enregistrées. Portée Device.
        Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsAI" -Name "AllowRecallEnablement" -Value 0

        # Sur les PC Copilot+, Recall est une fonctionnalité Windows à part entière :
        # la stratégie ne suffit pas, il faut retirer le composant.
        $f = Get-WindowsOptionalFeature -Online -FeatureName "Recall" -ErrorAction SilentlyContinue
        if ($f -and $f.State -eq "Enabled") {
            Invoke-Action "retirerait le composant Windows Recall" { Disable-WindowsOptionalFeature -Online -FeatureName "Recall" -NoRestart -ErrorAction Stop | Out-Null }
            # Le besoin de redémarrage est ici CONDITIONNEL (seulement si le composant
            # était présent), ce que le switch -Redemarrage ne sait pas exprimer :
            # on l'ajoute donc à la main au bilan cumulé.
            Write-Etat "Composant Recall retiré." -Niveau Info
            $t = "Retrait du composant Windows Recall"
            if ($t -notin $script:RedemarrageRequis) { $script:RedemarrageRequis += $t }
        }
        else {
            Write-Etat "Le composant Recall n'est pas présent sur ce PC (normal hors machines Copilot+) : seule la stratégie a été posée." -Niveau Info
        }
    }
}

function Menu-Maj-Securite {
    Start-Menu -Titre "CONFIGURATION SÉCURITÉ & MISES À JOUR"

    $t1 = {
        Invoke-Tweak "Reporter les mises à jour de fonctionnalités de 365 jours (les correctifs de sécurité continuent d'arriver) ?" -Cle "update-defer" `
            -Explication "Reporte les mises à jour de fonctionnalités de 365 jours pour stabiliser le système. Les correctifs de sécurité critiques continuent d'arriver. Nécessite Windows Édition Professionnelle." {
            Assert-EditionPro -Fonction "Le report des mises à jour de fonctionnalités"
            $wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            Set-RegValue -Path $wu -Name "DeferFeatureUpdates" -Value 1
            Set-RegValue -Path $wu -Name "DeferFeatureUpdatesPeriodInDays" -Value 365
            Set-RegValue -Path $wu -Name "DeferQualityUpdates" -Value 1
            Set-RegValue -Path $wu -Name "DeferQualityUpdatesPeriodInDays" -Value 4
            Set-RegValue -Path $wu -Name "BranchReadinessLevel" -Value 20
        }
    }

    $t2 = {
        Invoke-Tweak "Désactiver totalement le service de mise à jour Windows Update ?" -Cle "update-block" `
            -Explication "Désactive et bloque totalement le service Windows Update (wuauserv). Attention : aucun correctif de sécurité ne pourra être installé." {
            Set-ServiceEtat -Nom "wuauserv" -Demarrage Disabled -Arreter
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name "NoAutoUpdate" -Value 1
        }
    }

    $t3 = {
        Invoke-Tweak "Restaurer les réglages Windows Update par défaut ?" -Cle "update-restore" `
            -Explication "Remet les réglages du service de mise à jour Windows Update par défaut." {
            $wu = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate"
            if (Test-Path $wu) { Remove-RegKey -Path $wu }
            Set-ServiceEtat -Nom "wuauserv" -Demarrage Manual -Demarrer
        }
    }

    $t4 = {
        Invoke-Tweak "Désactiver la sécurité basée sur la virtualisation (VBS) / Isolation du noyau ?" -Cle "vbs-desactiver" -Redemarrage `
            -Explication "Désactive VBS et l'isolation du noyau pour améliorer les performances en jeu et calculs GPU. Réduit la sécurité système globale." {
            Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard" -Name "EnableVirtualizationBasedSecurity" -Value 0
            Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity" -Name "Enabled" -Value 0
            Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\CredentialGuard" -Name "Enabled" -Value 0
        }
    }

    $t5 = {
        Invoke-Tweak "Empêcher Windows Update d'installer ou de mettre à jour les pilotes ?" -Cle "update-pilotes" `
            -Explication "Empêche Windows Update d'écraser automatiquement tes pilotes matériels (comme les pilotes graphiques Nvidia/AMD) par des versions génériques ou plus anciennes de son choix. Tu devras mettre à jour tes pilotes manuellement." {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Settings" -Name "ExcludeWUDriversInQualityUpdate" -Value 1
            Set-RegValue -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DriverSearching" -Name "SearchOrderConfig" -Value 0
        }
    }

    $t6 = {
        Invoke-Tweak "Activer les sauvegardes périodiques du Registre Windows (RegBack) ?" -Cle "regback-backup" `
            -Explication "Configure Windows pour effectuer des sauvegardes régulières et automatiques de la base de registre vers le dossier System32\config\RegBack (désactivé par défaut par Microsoft pour économiser 50 Mo de disque). Apporte une sécurité supplémentaire en cas de corruption du registre." {
            Set-RegValue -Path "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Configuration Manager" -Name "EnablePeriodicalBackup" -Value 1
        }
    }

    $t7 = {
        Invoke-Tweak "Limiter l'usage CPU de Windows Defender pendant les analyses de fichiers ?" -Cle "defender-cpu-limit" `
            -Explication "Limite l'utilisation maximale du processeur (CPU) par Windows Defender à 30% pendant ses analyses automatiques en arrière-plan. Évite les hausses de température et les ralentissements soudains pendant que tu joues ou travailles." {
            Set-RegValue -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows Defender\Scan" -Name "AvgCPULimit" -Value 30
        }
    }

    if (Test-SansInteraction) {
        & $t1
        & $t2
        & $t3
        & $t4
        & $t5
        & $t6
        & $t7
        return
    }

    Write-Host " 1 - Windows Update : reporter les mises à jour de FONCTIONNALITÉS (sécurité conservée)"
    Write-Host " 2 - Windows Update : TOUT bloquer (service désactivé)" -ForegroundColor Red
    Write-Host " 3 - Windows Update : remettre les réglages par défaut"
    Write-Host " 4 - Désactiver l'Isolation du Noyau / VBS  [gain en jeu et calcul GPU]" -ForegroundColor Yellow
    Write-Host " 5 - Empêcher Windows Update d'installer/mettre à jour les pilotes" -ForegroundColor Yellow
    Write-Host " 6 - Activer les sauvegardes périodiques du Registre (RegBack)" -ForegroundColor Green
    Write-Host " 7 - Limiter l'usage CPU de Windows Defender lors des scans" -ForegroundColor Green
    Write-Host " 8 - Désactiver Windows Copilot" -ForegroundColor Yellow
    Write-Host " 9 - Désactiver Recall (les captures d'écran périodiques de l'IA)" -ForegroundColor Yellow
    Write-Host " 10 - Retour au menu principal"
    Write-Host ""

    $ChoixSec = Read-Host "Choisis une option (1-10)"
    switch ($ChoixSec) {
        "1" { & $t1 }
        "2" {
            Write-Etat "Bloquer toutes les mises à jour te prive aussi des correctifs de FAILLES DE SÉCURITÉ." -Niveau Avert
            & $t2
        }
        "3" { & $t3 }
        "4" {
            Write-Etat "VBS protège contre certaines attaques mémoire. Le désactiver = moins de sécurité." -Niveau Avert
            if (Confirmer-Filet-Securite) {
                & $t4
            }
        }
        "5" { & $t5 }
        "6" { & $t6 }
        "7" { & $t7 }
        "8" { Invoke-TweakCopilot }
        "9" {
            Write-Etat "Recall capture périodiquement ton écran et l'indexe localement." -Niveau Info
            Invoke-TweakRecall
        }
        "10" { return }
        default { Write-Etat "Choix invalide." -Niveau Avert }
    }
    Fin-De-Menu
}

function Update-ProtectionHostsViePrivee {
    # Bloque les domaines de télémétrie connus dans le fichier hosts Windows.
    $fichierHosts = "$env:SystemRoot\System32\drivers\etc\hosts"
    if (-not (Test-Path $fichierHosts)) { throw "Fichier hosts introuvable : $fichierHosts" }

    $domaines = @(
        "v10.events.data.microsoft.com",
        "telemetry.microsoft.com",
        "watson.telemetry.microsoft.com",
        "telecommand.telemetry.microsoft.com",
        "g.msn.com",
        "telemetry.nvidia.com"
    )

    $contenu = Get-Content $fichierHosts -ErrorAction SilentlyContinue
    $lignes = @($contenu)
    $ajoutes = 0

    foreach ($d in $domaines) {
        $reg = "0.0.0.0\s+" + [regex]::Escape($d)
        if (-not ($lignes -match $reg)) {
            $lignes += "0.0.0.0 $d # MadTweak Telemetry Block"
            $ajoutes++
        }
    }

    if ($ajoutes -gt 0) {
        Set-Content -Path $fichierHosts -Value $lignes -Encoding UTF8 -Force
    }

    Write-Etat ((T 'hosts.telemetrie.ok') -f $domaines.Count) -Niveau OK
    return $ajoutes
}


