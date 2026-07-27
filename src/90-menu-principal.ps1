# ------------------------------------------------------------------------------
# MENU PRINCIPAL (boucle, et non plus récursion)
# ------------------------------------------------------------------------------
function Afficher-Menu-Principal {
    # V3 : chaque sous-menu se rappelait mutuellement -> la pile d'appels grandissait
    # indéfiniment à chaque navigation. Une simple boucle règle le problème.
    while ($true) {
        Clear-Host
        Write-Host "==========================================================" -ForegroundColor Cyan
        Write-Host ("     MADTWEAK v$($script:Version) : " + (T 'c.titre') + "   ") -ForegroundColor Cyan
        Write-Host "==========================================================" -ForegroundColor Cyan
        # Une table plutôt que 16 Write-Host : le libellé vient de la langue courante,
        # et la mise en forme (numéro, crochets, alignement) reste écrite une seule fois.
        $entrees = @(
            @{ N = ' 1'; C = 'White' },   @{ N = ' 2'; C = 'White' },  @{ Sep = $true }
            @{ N = ' 3'; C = 'Yellow' },  @{ N = ' 4'; C = 'Yellow' }
            @{ N = ' 5'; C = 'Yellow' },  @{ N = ' 6'; C = 'Yellow' }
            @{ N = ' 7'; C = 'Yellow' },  @{ N = ' 8'; C = 'Cyan' }
            @{ N = ' 9'; C = 'Cyan' },    @{ N = '10'; C = 'Red' },    @{ Sep = $true }
            @{ N = '11'; C = 'Green' },   @{ N = '12'; C = 'Green' }
            @{ N = '13'; C = 'Yellow' },  @{ N = '14'; C = 'Green' },  @{ Sep = $true }
            @{ N = '15'; C = 'Magenta' }, @{ N = '16'; C = 'Red' }
        )
        foreach ($e in $entrees) {
            if ($e.Sep) {
                Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray
                continue
            }
            $i = $e.N.Trim()
            $etiquette = "[" + (T "c.$i") + "]"
            Write-Host ("{0} {1,-22}- {2}" -f $e.N, $etiquette, (T "c.$i`d")) -ForegroundColor $e.C
        }
        Write-Host "==========================================================" -ForegroundColor Cyan
        if ($script:Simulation) {
            Write-Host (T 'c.simu.on') -ForegroundColor Cyan
        }
        else {
            Write-Host (T 'c.simu.off') -ForegroundColor DarkGray
        }
        Write-Host ((T 'c.systeme') + "$($script:InfosOS.DisplayVersion) / build $script:BuildOS / $($script:InfosOS.EditionID)") -ForegroundColor DarkGray

        switch (Read-Host (T 'c.choix')) {
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

