@echo off
REM ============================================================================
REM  LANCEUR DE MADTWEAK  --  double-clique sur ce fichier.
REM
REM  Pourquoi un .bat ? Parce qu'un .ps1 ne se lance PAS en double-clic :
REM  Windows l'ouvre dans le Bloc-notes. Ce lanceur regle les trois frictions :
REM
REM    1. ELEVATION : le script exige les droits administrateur (#Requires).
REM    2. EXECUTIONPOLICY : contournee pour CE processus uniquement. Aucun
REM       reglage durable n'est modifie sur la machine.
REM    3. HOTE : powershell.exe (5.1) et NON pwsh (7). Ce n'est pas un oubli.
REM       Windows PowerShell 5.1 est la version FINALE de Windows PowerShell :
REM       c'est un composant de Windows, mis a jour par Windows Update, et il n'y
REM       aura jamais de 5.2. PowerShell 7 ne le remplace pas, il s'installe a
REM       cote. Le script prefere le 5.1 : les cmdlets Appx (suppression des
REM       bloatwares) y sont natives, alors qu'en 7 elles passent par une couche
REM       de compatibilite lente. Lancer ce script en 7 le degraderait.
REM
REM  Ce fichier est volontairement SANS ACCENTS et en ANSI/CRLF, contrairement
REM  aux .ps1 du projet qui sont en UTF-8 BOM. Un .bat est lu dans la page de
REM  codes OEM de la console (850 en France) : des accents UTF-8 y sortiraient
REM  en charabia, et un BOM en tete casserait la premiere commande.
REM ============================================================================

setlocal
REM Le script vit dans dist\ : c'est le PRODUIT du build, separe des sources de
REM src\. Voir build.ps1 pour le pourquoi.
set "SCRIPT=%~dp0dist\MadTweak.ps1"

REM dist\ est JETABLE et regenerable : il peut legitimement manquer (dossier
REM fraichement recupere, dist\ efface pour repartir propre, build jamais lance).
REM Puisque build.ps1 et src\ sont juste a cote, abandonner en renvoyant une
REM ligne de commande a recopier serait absurde : on construit, c'est tout.
REM Construire ne demande PAS les droits admin, d'ou sa place avant l'elevation.
if not exist "%SCRIPT%" (
    if exist "%~dp0src" (
        if exist "%~dp0build.ps1" (
            echo.
            echo  dist\MadTweak.ps1 absent : construction depuis src\...
            echo.
            powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0build.ps1"
        )
    )
)

REM Toujours rien ? Alors il manque vraiment quelque chose, ou le build a echoue.
if not exist "%SCRIPT%" (
    echo.
    echo  ERREUR : dist\MadTweak.ps1 est introuvable et n'a pas pu etre construit.
    echo.
    echo  Ce lanceur a besoin, a cote de lui, soit de :
    echo    - dist\MadTweak.ps1  ^(le script deja construit^)
    echo    - soit src\ + build.ps1  ^(les sources, pour le construire^)
    echo.
    echo  Si tu n'as que le lanceur, recupere le dossier complet du projet.
    echo.
    pause
    exit /b 1
)

REM Deja administrateur ? "net session" echoue si on ne l'est pas.
REM Cette commande DOIT etre sur sa propre ligne : dans "net session & if
REM %errorlevel%...", cmd developpe %errorlevel% au parsing de la ligne, donc
REM AVANT que net session ne s'execute, et le test repond toujours 0.
net session >nul 2>&1
if %errorlevel% equ 0 goto :lancer

echo.
echo  Ce script a besoin des droits administrateur.
echo  Une demande d'elevation (UAC) va s'afficher...
echo.
REM On se relance nous-memes en eleve. Le script PowerShell heritera des droits.
powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
exit /b 0

:lancer
REM -NoProfile : le profil de l'utilisateur pourrait redefinir des cmdlets et
REM fausser le comportement du script. On part d'un environnement neutre.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"

echo.
echo  Session terminee.
pause
exit /b 0
