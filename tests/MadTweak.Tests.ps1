# ==============================================================================
# TESTS AUTOMATISÉS PESTER POUR MADTWEAK (Pester 5+, syntaxe "Should -Be")
# ==============================================================================

# Pester 5+ exige que les variables partagées soient dans $global: pour survivre à la passe Discovery
$global:racine = if ($PSScriptRoot) { (Resolve-Path (Join-Path $PSScriptRoot "..")).Path } else { (Get-Location).Path }
if (-not (Test-Path (Join-Path $global:racine "src"))) {
    $global:racine = (Get-Item ".").FullName
}
$global:buildScript = Join-Path $global:racine "build.ps1"

# MODE SIMULATION POUR TOUTE LA SUITE.
#
# Plusieurs tests appellent directement des fonctions qui MODIFIENT la machine :
# Clear-TelechargementsAnciens supprime des installeurs de plus de 30 jours dans
# le dossier Telechargements, Clear-FichiersMajWindowsOld lance un DISM
# /resetbase irreversible, Clear-RegistreOrphelin vide des historiques.
#
# Constate : lancer cette suite sur une machine de developpement lui appliquait
# reellement ces nettoyages. Un test doit verifier un comportement, pas
# reconfigurer l'ordinateur de qui le lance.
$global:Simulation = $true
$script:Simulation = $true
$global:srcDir = Join-Path $global:racine "src"

Describe "Build Verification" {
    It "Doit valider que dist\MadTweak.ps1 est parfaitement à jour avec src\" {
        { & $global:buildScript -Verifier } | Should -Not -Throw
    }

    It "Chaque module src\*.ps1 doit posséder un BOM UTF-8 (0xEF, 0xBB, 0xBF)" {
        $modules = Get-ChildItem -Path $global:srcDir -Filter "*.ps1"
        $modules.Count | Should -BeGreaterThan 0

        foreach ($m in $modules) {
            $tete = [byte[]]::new(3)
            $fs = [System.IO.File]::OpenRead($m.FullName)
            try { $lu = $fs.Read($tete, 0, 3) } finally { $fs.Dispose() }
            $lu | Should -Be 3
            $tete[0] | Should -Be 0xEF
            $tete[1] | Should -Be 0xBB
            $tete[2] | Should -Be 0xBF
        }
    }
}

Describe "Dictionnaire de langues (i18n)" {
    BeforeAll {
        $langueFile = Join-Path $global:srcDir "05-langue.ps1"
        . $langueFile
    }

    It "Chaque clé de traduction dans `$script:Textes doit posséder des entrées FR et EN" {
        $script:Textes | Should -Not -BeNullOrEmpty
        $clesManquantes = @()

        foreach ($cle in $script:Textes.Keys) {
            $entree = $script:Textes[$cle]
            if (-not $entree['fr'] -or -not $entree['en']) {
                $clesManquantes += $cle
            }
        }

        $clesManquantes.Count | Should -Be 0
    }
}

Describe "Fonctions du Socle" {
    BeforeAll {
        . (Join-Path $global:srcDir "05-langue.ps1")
        . (Join-Path $global:srcDir "10-socle.ps1")
    }

    It "Get-LangueSysteme doit renvoyer 'fr' ou 'en'" {
        $langue = Get-LangueSysteme
        ($langue -in @('fr', 'en')) | Should -Be $true
    }

    It "Test-NPU doit s'exécuter sans erreur et renvoyer un booléen" {
        $res = Test-NPU
        $res -is [bool] | Should -Be $true
    }

    It "Get-TemperatureCPU doit s'exécuter sans lever d'exception" {
        { Get-TemperatureCPU } | Should -Not -Throw
    }
}

Describe "Fonctionnalités Phase 2" {
    BeforeAll {
        . (Join-Path $global:srcDir "05-langue.ps1")
        . (Join-Path $global:srcDir "10-socle.ps1")
        . (Join-Path $global:srcDir "06-textes-tweaks.ps1")
        . (Join-Path $global:srcDir "07-textes-audit.ps1")
        . (Join-Path $global:srcDir "20-sauvegarde.ps1")
        . (Join-Path $global:srcDir "70-audit.ps1")
        . (Join-Path $global:srcDir "80-profils.ps1")
    }

    It "Compare-Profils doit comparer deux profils et retourner les tweaks communs et uniques" {
        $keys = @($script:Profils.Keys)
        $comp = Compare-Profils -NomProfilA $keys[0] -NomProfilB $keys[3]
        $comp | Should -Not -BeNullOrEmpty
        $comp.ProfilA | Should -Be $keys[0]
        $comp.ProfilB | Should -Be $keys[3]
        $comp.TweaksCommuns.Count | Should -BeGreaterThan 0
    }

    It "Export-RapportAuditJson doit exporter un fichier JSON d'audit valide" {
        $tmp = Join-Path $env:TEMP "test-audit.json"
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        $out = Export-RapportAuditJson -CheminSortie $tmp
        (Test-Path $tmp) | Should -Be $true
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
    }

    It "Export-RapportAuditMarkdown doit exporter un rapport Markdown lisible" {
        $tmp = Join-Path $env:TEMP "test-audit.md"
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        $out = Export-RapportAuditMarkdown -CheminSortie $tmp
        (Test-Path $tmp) | Should -Be $true
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
    }
}

Describe "Installation USB & Autounattend" {
    BeforeAll {
        . (Join-Path $global:srcDir "05-langue.ps1")
        . (Join-Path $global:srcDir "10-socle.ps1")
        . (Join-Path $global:srcDir "63-installation.ps1")
    }

    It "Test-VitesseCleUSB doit s'exécuter sur le lecteur système C: sans lever d'exception" {
        $res = Test-VitesseCleUSB -Lettre "C:"
        $res | Should -Not -BeNullOrEmpty
        $res.MoParSeconde | Should -BeGreaterThan 0
    }

    It "New-AutounattendXml doit générer un fichier XML valide sans avertissements" {
        $tmpXml = Join-Path $env:TEMP "test-autounattend.xml"
        if (Test-Path $tmpXml) { Remove-Item $tmpXml -Force }
        $out = New-AutounattendXml -Chemin $tmpXml -NomUtilisateur "TestUser" -SansTPM
        (Test-Path $tmpXml) | Should -Be $true
        $pbs = Test-AutounattendXml -Chemin $tmpXml
        $pbs.Count | Should -Be 0
        if (Test-Path $tmpXml) { Remove-Item $tmpXml -Force }
    }

    It "Export-AutounattendConfig et Import-AutounattendConfig doivent sérialiser et désérialiser la configuration" {
        $tmpJson = Join-Path $env:TEMP "unattend-test.json"
        if (Test-Path $tmpJson) { Remove-Item $tmpJson -Force }
        $cfg = @{ NomUtilisateur = "TestUser"; Version = "11"; SansTPM = $true }
        Export-AutounattendConfig -CheminSortieJson $tmpJson -Configuration $cfg | Out-Null
        (Test-Path $tmpJson) | Should -Be $true
        $read = Import-AutounattendConfig -CheminJsonSource $tmpJson
        $read.NomUtilisateur | Should -Be "TestUser"
        if (Test-Path $tmpJson) { Remove-Item $tmpJson -Force }
    }
}

Describe "Fonctionnalités Phase 3 & Supériorité UWT5" {
    BeforeAll {
        . (Join-Path $global:srcDir "05-langue.ps1")
        . (Join-Path $global:srcDir "10-socle.ps1")
        . (Join-Path $global:srcDir "30-simulation-et-tweaks.ps1")
        . (Join-Path $global:srcDir "51-menu-avances.ps1")
        . (Join-Path $global:srcDir "53-menu-materiel-reseau.ps1")
        . (Join-Path $global:srcDir "54-menu-securite-ia.ps1")
        . (Join-Path $global:srcDir "56-menu-maintenance.ps1")
        . (Join-Path $global:srcDir "59-menu-nettoyage.ps1")
        . (Join-Path $global:srcDir "70-audit.ps1")

        # LA LIGNE QUI COMPTE, et elle doit etre ICI, apres le chargement.
        # Posee en tete du fichier elle n'a aucun effet : $script: designe la
        # portee ou la fonction a ete DEFINIE, c'est-a-dire ce bloc-ci.
        # Sans elle, les tests ci-dessous nettoient reellement la machine de qui
        # les lance : suppression d'installeurs de plus de 30 jours dans les
        # Telechargements, DISM /resetbase irreversible, purge d'historiques.
        $script:Simulation = $true
        $script:SimuCompteur = 0
    }

    It "Get-AnalyseCachesApplications doit exécuter une pesée sans lever d'exception" {
        $res = Get-AnalyseCachesApplications
        $res | Should -Not -BeNullOrEmpty
    }

    It "Test-SanteReseau doit s'exécuter et renvoyer un objet de diagnostic" {
        $res = Test-SanteReseau
        $res | Should -Not -BeNullOrEmpty
    }

    It "Clear-MemoireRAM doit s'exécuter sans lever d'exception" {
        { Clear-MemoireRAM } | Should -Not -Throw
    }

    It "Test-BenchmarkPerformance doit mesurer l'état du système et renvoyer un hashtable" {
        . (Join-Path $global:srcDir "70-audit.ps1")
        $res = Test-BenchmarkPerformance
        $res | Should -Not -BeNullOrEmpty
        $res.NombreProcessus | Should -BeGreaterThan 0
    }

    It "Set-ProfilServicesWindows doit analyser le matériel et ajuster les services" {
        . (Join-Path $global:srcDir "80-profils.ps1")
        { Set-ProfilServicesWindows } | Should -Not -Throw
    }

    It "Export-ScriptAutonome doit générer un fichier script PS1 valide" {
        . (Join-Path $global:srcDir "30-simulation-et-tweaks.ps1")
        $tmpPs1 = Join-Path $env:TEMP "test-standalone.ps1"
        if (Test-Path $tmpPs1) { Remove-Item $tmpPs1 -Force }
        Export-ScriptAutonome -CheminSortiePs1 $tmpPs1 -ClesTweaks @() | Out-Null
        (Test-Path $tmpPs1) | Should -Be $true
        if (Test-Path $tmpPs1) { Remove-Item $tmpPs1 -Force }
    }

    It "Set-GamingNetworkOptimizations doit s'exécuter sans lever d'exception" {
        { Set-GamingNetworkOptimizations } | Should -Not -Throw
    }

    It "Clear-RegistreOrphelin doit s'exécuter sans lever d'exception" {
        { Clear-RegistreOrphelin } | Should -Not -Throw
    }

    It "Get-AuditConformiteSecurite doit exécuter l'audit de sécurité sans lever d'exception" {
        . (Join-Path $global:srcDir "70-audit.ps1")
        $res = Get-AuditConformiteSecurite
        $res | Should -Not -BeNullOrEmpty
    }

    It "Set-CpuCoreParkingAndFrequency doit s'exécuter sans lever d'exception" {
        { Set-CpuCoreParkingAndFrequency } | Should -Not -Throw
    }

    It "Clear-TelechargementsAnciens doit s'exécuter sans lever d'exception" {
        { Clear-TelechargementsAnciens } | Should -Not -Throw
    }

    It "Optimize-LecteursStockageSsd doit s'exécuter sans lever d'exception" {
        { Optimize-LecteursStockageSsd } | Should -Not -Throw
    }

    It "Set-ProtectionDefenderViePrivee doit s'exécuter sans lever d'exception" {
        { Set-ProtectionDefenderViePrivee } | Should -Not -Throw
    }

    It "Clear-FichiersMajWindowsOld doit s'exécuter sans lever d'exception" {
        { Clear-FichiersMajWindowsOld } | Should -Not -Throw
    }

    It "Export-RapportAuditPdf doit générer un fichier rapport HTML/PDF valide" {
        $tmpPdf = Join-Path $env:TEMP "test-report.html"
        if (Test-Path $tmpPdf) { Remove-Item $tmpPdf -Force }
        Export-RapportAuditPdf -CheminSortie $tmpPdf | Out-Null
        (Test-Path $tmpPdf) | Should -Be $true
        if (Test-Path $tmpPdf) { Remove-Item $tmpPdf -Force }
    }
}

Describe "Image système de référence" {
    BeforeAll {
        . (Join-Path $global:srcDir "05-langue.ps1")
        . (Join-Path $global:srcDir "10-socle.ps1")
        . (Join-Path $global:srcDir "20-sauvegarde.ps1")
        . (Join-Path $global:srcDir "30-simulation-et-tweaks.ps1")
        . (Join-Path $global:srcDir "53-menu-materiel-reseau.ps1")
        . (Join-Path $global:srcDir "56-menu-maintenance.ps1")
        . (Join-Path $global:srcDir "59-menu-nettoyage.ps1")
        . (Join-Path $global:srcDir "70-audit.ps1")
        . (Join-Path $global:srcDir "64-image-systeme.ps1")

        # Même règle que le bloc Phase 3 ci-dessus : $script:Simulation doit être
        # posée APRÈS le chargement, dans CE bloc -- sinon les fonctions qui
        # modifient la machine (Repair-SystemeIntegral, wbadmin...) le feraient
        # pour de vrai sur la machine qui lance les tests.
        $script:Simulation = $true
        $script:SimuCompteur = 0
    }

    It "Repair-SystemeIntegral doit s'exécuter sans lever d'exception" {
        { Repair-SystemeIntegral } | Should -Not -Throw
    }

    It "Get-CibleImageValide doit refuser le disque système" {
        $r = Get-CibleImageValide -LettreCible $env:SystemDrive
        $r.Valide | Should -Be $false
    }

    It "Get-DisquesCiblesPossibles doit s'exécuter sans lever d'exception et renvoyer un tableau" {
        $res = @(Get-DisquesCiblesPossibles)
        { Get-DisquesCiblesPossibles } | Should -Not -Throw
        $res | Should -Not -Be $null
    }

    It "Test-CapaciteWbadmin doit s'exécuter sans lever d'exception" {
        { Test-CapaciteWbadmin } | Should -Not -Throw
    }

    It "Parse-SortieReagentc doit reconnaître un WinRE activé (FR et EN)" {
        (Parse-SortieReagentc -CodeSortie 0 -Sortie "État de Windows RE : Activé(e)").Statut | Should -Be 'Active'
        (Parse-SortieReagentc -CodeSortie 0 -Sortie "Windows RE status: Enabled").Statut | Should -Be 'Active'
    }

    It "Parse-SortieReagentc doit reconnaître un WinRE désactivé (FR et EN)" {
        (Parse-SortieReagentc -CodeSortie 0 -Sortie "État de Windows RE : Désactivé(e)").Statut | Should -Be 'Desactivee'
        (Parse-SortieReagentc -CodeSortie 0 -Sortie "Windows RE status: Disabled").Statut | Should -Be 'Desactivee'
    }

    It "Parse-SortieReagentc doit signaler une partition WinRE absente (code de sortie non nul, sortie illisible)" {
        (Parse-SortieReagentc -CodeSortie 1 -Sortie "").Statut | Should -Be 'Absente'
    }

    It "Parse-SortieReagentc doit renvoyer Inconnu si rien n'est reconnaissable et le code est 0" {
        (Parse-SortieReagentc -CodeSortie 0 -Sortie "texte inattendu sans rapport").Statut | Should -Be 'Inconnu'
    }

    It "Get-StatutWinRE doit s'exécuter sans lever d'exception" {
        { Get-StatutWinRE } | Should -Not -Throw
    }

    It "Export-RapportImageSysteme doit générer un fichier HTML valide" {
        $tmp = Join-Path $env:TEMP "test-restauration-image.html"
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        $statut = @{ Statut = 'Active'; Message = 'Présent et activé'; SortieBrute = '' }
        Export-RapportImageSysteme -LettreCible "E" -StatutWinRE $statut -CheminSortie $tmp | Out-Null
        (Test-Path $tmp) | Should -Be $true
        (Get-Content $tmp -Raw) | Should -Match 'Restauration'
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
    }

    It "New-ImageSystemeReference doit exiger -Confirme" {
        { New-ImageSystemeReference -LettreCible "E" } | Should -Throw
    }

    It "New-ImageSystemeReference doit refuser net le disque système, avant toute autre étape" {
        $res = New-ImageSystemeReference -LettreCible $env:SystemDrive -Confirme
        $res.Succes | Should -Be $false
        ($res.Etapes | Where-Object { $_.Nom -eq "Vérification du disque cible" }).Succes | Should -Be $false
    }
}
