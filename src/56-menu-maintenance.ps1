# ------------------------------------------------------------------------------
# MAINTENANCE & RÉPARATION
# ------------------------------------------------------------------------------
function Menu-Maintenance {
    Start-Menu -Titre "OUTILS DE DIAGNOSTIC ET VÉRIFICATION SYSTÈME" -Couleur Green `
        -SousTitre @("Note : l'ordre correct est DISM d'abord, SFC ensuite.")

    Invoke-Tweak "Lancer DISM pour restaurer l'image de santé de Windows ? (plusieurs minutes)" -Cle "maintenance-dism" `
        -Explication "Analyse l'image système Windows pour y détecter d'éventuels dommages et la réparer en téléchargeant les fichiers sains via Windows Update (requiert Internet)." {
        Invoke-Externe -Fichier "DISM.exe" -Arguments @("/Online", "/Cleanup-Image", "/RestoreHealth")
    }

    Invoke-Tweak "Lancer un scan SFC pour réparer les fichiers système corrompus ? (plusieurs minutes)" -Cle "maintenance-sfc" `
        -Explication "Analyse l'intégralité des fichiers système protégés de Windows et remplace les versions corrompues par des copies saines." {
        # SFC renvoie 0 s'il n'y a rien à réparer OU s'il a réparé avec succès.
        Invoke-Externe -Fichier "sfc.exe" -Arguments @("/scannow")
    }

    Invoke-Tweak "Nettoyer et compresser le magasin des composants système (WinSxS) ? (plusieurs minutes)" -Cle "maintenance-winsxs-cleanup" `
        -Explication "Exécute le nettoyage DISM avec StartComponentCleanup et ResetBase. Supprime définitivement les anciennes versions des composants système obsolètes ou remplacés par des mises à jour récentes. Libère beaucoup d'espace sur C:\Windows\WinSxS mais rend les mises à jour en cours non désinstallables." {
        Invoke-Externe -Fichier "DISM.exe" -Arguments @("/Online", "/Cleanup-Image", "/StartComponentCleanup", "/ResetBase")
    }

    if (-not (Test-SansInteraction)) {
        Write-Etat "La purge des journaux efface l'historique qui sert à diagnostiquer les pannes." -Niveau Avert
    }
    Invoke-Tweak "Purger tous les journaux d'événements Windows ?" -Cle "maintenance-purger-journaux" `
        -Explication "Vide l'intégralité des journaux d'événements de l'Observateur d'événements de Windows pour libérer de l'espace." {
        if ($script:Simulation) { Write-Simu "purgerait les $(@(wevtutil el).Count) journaux d'événements Windows"; return }
        $journaux = @(wevtutil el)
        $efface = 0; $ko = 0
        foreach ($j in $journaux) {
            wevtutil cl "$j" 2>$null
            if ($LASTEXITCODE -eq 0) { $efface++ } else { $ko++ }
        }
        Write-Etat "$efface journal(aux) purgé(s), $ko protégé(s) par le système." -Niveau Info
        if ($efface -eq 0) { throw "Aucun journal n'a pu être purgé." }
    }

    Fin-De-Menu
}

