# ==============================================================================
# BUILD : recompose src\*.ps1 en un dist\MadTweak.ps1 unique et distribuable.
#
# Pourquoi un build plutôt qu'un simple dot-sourcing des modules ?
# Parce que ce script doit rester COPIABLE SUR UNE CLÉ USB et exécutable tel quel
# sur une machine qu'on vient de réinstaller — y compris collé dans une console
# ou lancé via « irm ... | iex », deux cas où $PSScriptRoot est vide et où aucun
# fichier voisin n'existe. Un monofichier est la seule forme qui survit à ça.
# On édite donc les modules, et on distribue le fichier construit.
#
# Pourquoi la sortie va-t-elle dans dist\ et non à côté des sources ?
# Parce que src\ a une SÉMANTIQUE : c'est ce que ce script avale. Y écrire le
# fichier construit reviendrait à lui donner sa propre sortie en entrée au build
# suivant, et le résultat contiendrait son code en double. La séparation
# source / produit n'est donc pas cosmétique, elle est structurelle.
#
# Utilisation :   .\build.ps1            construit dist\MadTweak.ps1
#                 .\build.ps1 -Verifier  contrôle qu'il est à jour, sans écrire
# ==============================================================================
[CmdletBinding()]
param(
    # Contrôle que le fichier existant est bien à jour vis-à-vis des modules,
    # sans rien réécrire. Renvoie un code de sortie non nul s'il ne l'est pas :
    # utilisable tel quel dans un hook de pré-commit ou une CI.
    [switch]$Verifier
)

$ErrorActionPreference = 'Stop'

$racine = if ($PSScriptRoot) { $PSScriptRoot } else { (Get-Location).Path }
$src = Join-Path $racine "src"
$dist = Join-Path $racine "dist"
$sortie = Join-Path $dist "MadTweak.ps1"

if (-not (Test-Path $src)) { throw "Dossier src\ introuvable dans $racine." }

# L'ordre vient du NOM des fichiers (00-, 10-, 20-...). C'est volontaire : le
# socle doit être présent avant les menus qui s'en servent, et le lancement en
# dernier. Renommer un module suffit donc à le déplacer dans le fichier final.
$modules = @(Get-ChildItem -Path $src -Filter "*.ps1" | Sort-Object Name)
if ($modules.Count -eq 0) { throw "Aucun module .ps1 dans $src." }

# Contrôle d'ordre : 00-entete doit être le premier (il porte param() et
# l'auto-élévation, qui doivent précéder tout le reste) et 99-lancement le
# dernier (il exécute).
if ($modules[0].Name -notlike "00-*") { throw "Le premier module doit être 00-* (il porte param()), or c'est $($modules[0].Name)." }
if ($modules[-1].Name -notlike "99-*") { throw "Le dernier module doit être 99-* (il lance le script), or c'est $($modules[-1].Name)." }

# Contrôle du BOM sur chaque module. Ce n'est pas de la coquetterie : un module
# sans BOM est lu en ANSI par Windows PowerShell 5.1, et tous ses accents partent
# en « GÃ‰NÃ‰RÃ‰ ». Le cas s'est produit -- plusieurs éditeurs et outils écrivent
# de l'UTF-8 sans BOM par défaut, et le fichier a l'air parfaitement normal tant
# qu'on ne le relit pas en 5.1. On refuse de construire à partir d'une source
# dont on sait qu'elle sera mal lue.
$sansBom = @()
foreach ($m in $modules) {
    $tete = [byte[]]::new(3)
    $fs = [System.IO.File]::OpenRead($m.FullName)
    try { $lu = $fs.Read($tete, 0, 3) } finally { $fs.Dispose() }
    if ($lu -lt 3 -or $tete[0] -ne 0xEF -or $tete[1] -ne 0xBB -or $tete[2] -ne 0xBF) { $sansBom += $m.Name }
}
if ($sansBom.Count -gt 0) {
    Write-Host "ERREUR : ces modules ne sont pas en UTF-8 AVEC BOM :" -ForegroundColor Red
    foreach ($n in $sansBom) { Write-Host "  - $n" -ForegroundColor Red }
    Write-Host "Sous Windows PowerShell 5.1 leurs accents seraient illisibles. Rien n'a été écrit." -ForegroundColor Red
    Write-Host "Réenregistre-les en « UTF-8 avec BOM » (VS Code : cliquer sur l'encodage en bas à droite)." -ForegroundColor Yellow
    exit 1
}

# Le seul vrai piège qui reste : ouvrir MadTweak.ps1, l'éditer, et voir son
# travail disparaître au build suivant. Le README le dit, mais un avertissement
# qu'il faut aller chercher ne protège personne : celui-ci est sous les yeux de
# quiconque ouvre le fichier.
$banniere = @(
    "# =============================================================================="
    "# FICHIER GÉNÉRÉ AUTOMATIQUEMENT — NE PAS ÉDITER"
    "#"
    "# Ce script est le PRODUIT de build.ps1, qui concatène les modules de src\."
    "# Toute modification faite ici sera PERDUE au prochain build."
    "#"
    "#   Pour le modifier :  édite le module concerné dans src\, puis .\build.ps1"
    "#   Pour l'utiliser  :  ce fichier est autonome — c'est le SEUL dont tu aies"
    "#                       besoin, copie-le où tu veux (clé USB, autre PC...)."
    "#"
    "# Volontairement SANS date de génération : elle changerait à chaque build et"
    "# rendrait « build.ps1 -Verifier » incapable de repérer une vraie divergence."
    "# =============================================================================="
    ""
)

$lignes = New-Object System.Collections.Generic.List[string]
foreach ($l in $banniere) { $lignes.Add($l) }
foreach ($m in $modules) {
    # ReadAllLines mange le BOM de chaque module : c'est ce qu'on veut, un seul
    # BOM sera réécrit en tête du fichier final.
    $contenu = [System.IO.File]::ReadAllLines($m.FullName, [System.Text.Encoding]::UTF8)
    foreach ($l in $contenu) { $lignes.Add($l) }
}

# UTF-8 AVEC BOM, impérativement : sans lui, Windows PowerShell 5.1 lit le fichier
# en ANSI et tous les accents deviennent illisibles. C'est écrit en tête du script.
$utf8bom = [System.Text.UTF8Encoding]::new($true)
# LF et non CRLF : c'est la convention du fichier d'origine, et PowerShell l'exécute
# indifféremment. Écrire du CRLF ferait apparaître l'intégralité du fichier comme
# modifiée au premier diff, pour zéro changement réel.
$texte = ($lignes -join "`n") + "`n"

if ($Verifier) {
    if (-not (Test-Path $sortie)) { Write-Host "dist\MadTweak.ps1 n'existe pas : il faut le construire (.\build.ps1)." -ForegroundColor Red; exit 1 }
    $actuel = [System.IO.File]::ReadAllText($sortie, [System.Text.Encoding]::UTF8)
    if ($actuel -ceq $texte) {
        Write-Host "À JOUR : dist\MadTweak.ps1 correspond exactement aux $($modules.Count) modules." -ForegroundColor Green
        exit 0
    }
    Write-Host "OBSOLÈTE : dist\MadTweak.ps1 ne correspond plus aux modules. Lance .\build.ps1" -ForegroundColor Red
    exit 1
}

# On refuse de produire un fichier qui ne s'analyse pas : mieux vaut échouer ici
# que livrer un script cassé sur la clé USB.
$err = $null
[System.Management.Automation.Language.Parser]::ParseInput($texte, [ref]$null, [ref]$err) | Out-Null
if ($err -and $err.Count -gt 0) {
    Write-Host "ERREUR DE SYNTAXE dans le fichier construit : rien n'a été écrit." -ForegroundColor Red
    foreach ($e in $err) { Write-Host "  ligne $($e.Extent.StartLineNumber) : $($e.Message)" -ForegroundColor Red }
    exit 1
}

# dist\ n'est qu'un réceptacle de fichiers générés : il peut légitimement ne pas
# exister (dossier fraîchement récupéré, dist\ effacé pour repartir propre).
if (-not (Test-Path $dist)) { New-Item -ItemType Directory -Path $dist -Force | Out-Null }
[System.IO.File]::WriteAllText($sortie, $texte, $utf8bom)

Write-Host "Construit : $sortie" -ForegroundColor Green
Write-Host "  $($modules.Count) modules, $($lignes.Count) lignes, UTF-8 avec BOM." -ForegroundColor Gray
foreach ($m in $modules) {
    $n = [System.IO.File]::ReadAllLines($m.FullName, [System.Text.Encoding]::UTF8).Count
    Write-Host ("    {0,-34} {1,5} lignes" -f $m.Name, $n) -ForegroundColor DarkGray
}
