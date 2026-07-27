# ------------------------------------------------------------------------------
# MENU PRINCIPAL (boucle, et non plus récursion)
# ------------------------------------------------------------------------------
function Afficher-Menu-Principal {
    # V3 : chaque sous-menu se rappelait mutuellement -> la pile d'appels grandissait
    # indéfiniment à chaque navigation. Une simple boucle règle le problème.
    while ($true) {
        Clear-Host
        Write-Host "==========================================================" -ForegroundColor Cyan
        Write-Host "     MADTWEAK v$($script:Version) : CONFIGURATION SYSTÈME INTÉGRALE   " -ForegroundColor Cyan
        Write-Host "==========================================================" -ForegroundColor Cyan
        Write-Host " 1 [PROFILS]            - Appliquer un lot cohérent d'un coup" -ForegroundColor White
        Write-Host " 2 [AUDIT]              - Que vaut ma machine ? (ne modifie rien)" -ForegroundColor White
        Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host " 3 [TWEAKS DE BASE]     - Télémétrie, Pubs, Bloatwares & Interface" -ForegroundColor Yellow
        Write-Host " 4 [TWEAKS AVANCÉS]     - Clic Droit, Services & Mémoire" -ForegroundColor Yellow
        Write-Host " 5 [EXPLORATEUR & PRIVÉ]- Épurer l'explorateur, Confidentialité" -ForegroundColor Yellow
        Write-Host " 6 [MATÉRIEL & RÉSEAU]  - Télémétrie GPU, USB, Latence, LLMNR" -ForegroundColor Yellow
        Write-Host " 7 [MAJ, SÉCURITÉ & IA] - Windows Update, VBS, Copilot & Recall" -ForegroundColor Yellow
        Write-Host " 8 [WINDOWS 11 24H2+]   - Pubs Démarrer, Verrouillage, Widgets, IA" -ForegroundColor Cyan
        Write-Host " 9 [APPARENCE & VISUEL] - Thème sombre, Explorateur, Barre des tâches" -ForegroundColor Cyan
        Write-Host "10 [SIGNATURE MADTRIX]  - Fond d'écran perso généré à la volée" -ForegroundColor Red
        Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "11 [NETTOYAGE DISQUE]   - Caches et temporaires (mesurés d'abord)" -ForegroundColor Green
        Write-Host "12 [DÉMARRAGE & SERV.]  - Démarrage, services rarement utiles" -ForegroundColor Green
        Write-Host "13 [LOGICIELS EXTRA]    - Catalogue d'installation Winget" -ForegroundColor Yellow
        Write-Host "14 [MAINTENANCE & FIX]  - Réparation système (DISM / SFC)" -ForegroundColor Green
        Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
        Write-Host "15 [ANNULER]            - Revenir aux défauts Windows" -ForegroundColor Magenta
        Write-Host "16 [QUITTER]            - Quitter l'utilitaire" -ForegroundColor Red
        Write-Host "==========================================================" -ForegroundColor Cyan
        if ($script:Simulation) {
            Write-Host "  S [SIMULATION] : ACTIVE - rien ne sera écrit sur le système" -ForegroundColor Cyan
        }
        else {
            Write-Host "  S [SIMULATION] : inactive - les tweaks seront RÉELLEMENT appliqués" -ForegroundColor DarkGray
        }
        Write-Host " Système : $($script:InfosOS.DisplayVersion) / build $script:BuildOS / $($script:InfosOS.EditionID)" -ForegroundColor DarkGray

        switch (Read-Host "Entre ton choix (1-16, ou S)") {
            { $_ -match '^\s*[sS]\s*$' } {
                $script:Simulation = -not $script:Simulation
                $script:SimuCompteur = 0
            }
            "1" { Menu-Profils }
            "2" { Menu-Audit }
            "3" { Menu-Tweaks-Base }
            "4" { Menu-Tweaks-Avances }
            "5" { Menu-Explorateur-Prive }
            "6" { Menu-Materiel-Cpu }
            "7" { Menu-Maj-Securite }
            "8" { Menu-Windows11-Recent }
            "9" { Menu-Visuel }
            "10" { Menu-Signature }
            "11" { Menu-Nettoyage }
            "12" { Menu-Demarrage }
            "13" { Menu-Logiciels-Extra }
            "14" { Menu-Maintenance }
            "15" { Menu-Annuler }
            "16" { return }
            default { }
        }
    }
}

