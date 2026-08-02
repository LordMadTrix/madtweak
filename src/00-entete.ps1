# ==============================================================================
# LE WINDOWS UTILITY INTÉGRAL V4 (VERSION FRANÇAISE)
# Inspiré de Chris Titus Tech - Version Système Intégral Maximale
#
# IMPORTANT : les modules de src\ ET le fichier construit DOIVENT rester en
#             UTF-8 AVEC BOM et en fins de ligne LF, sinon les accents seront
#             illisibles sous Windows PowerShell 5.1. build.ps1 s'en charge.
#
# Principe de la V4 : aucune action ne se déclare "appliquée" si elle a échoué.
#
# PAS de #Requires -RunAsAdministrator ICI, volontairement : cette directive est
# évaluée par PowerShell AVANT la moindre ligne du script, donc un lancement
# sans droits admin refusait tout net avec un mur d'erreur rouge -- constaté en
# vrai : un simple "powershell.exe -File .\MadTweak.ps1" depuis une console
# normale (exactement la commande du site) s'arrêtait là, sans jamais proposer
# d'élévation. À la place : le bloc juste après param() se relance lui-même en
# administrateur (une seule fenêtre UAC), pas un message d'erreur à interpréter.
# ==============================================================================

# param() DOIT être la première instruction exécutable du script : seuls des
# commentaires peuvent la précéder. D'où sa place ici, en tête du tout premier
# module.
param(
    # Force l'ancien menu console. Par défaut le script ouvre l'interface graphique,
    # qui retombe d'elle-même sur la console si WPF est indisponible.
    # L'interface graphique permet désormais d'appliquer tous les tweaks, y compris
    # les plus lourds (Edge, OneDrive, Windows Update, VBS, DISM/SFC, winget, nettoyage).
    [switch]$Console,
    # Mode non interactif : exécute le nettoyage léger et sort. Utilisé par la tâche
    # planifiée « MadTweak-Maintenance ». N'ouvre ni interface ni menu.
    [switch]$Maintenance,
    # Force la langue. Sans ce paramètre, elle suit celle de Windows.
    # Tout est traduit : interface, profils, onglets, les 155 tweaks et les 104
    # tests d'audit. Le français reste la langue d'écriture du projet et le repli.
    [ValidateSet('fr', 'en')]
    [string]$Langue,
    # Applique un ou PLUSIEURS profils SANS poser de question, puis rend la main.
    # Écrit pour les installations automatisées : le fichier de réponses généré
    # par le menu « Clé d'installation » appelle le script ainsi à la première
    # ouverture de session. Les noms attendus sont ceux du menu Profils
    # (« Minimal / sûr », « Gamer »...), séparés par des virgules. Un nom inconnu
    # est signalé, pas deviné.
    #
    # Plusieurs profils, parce qu'un seul ne suffit pas sur une machine neuve :
    # « Gamer » s'occupe de latence et de FPS, pas d'apparence. Le thème sombre et
    # la barre des tâches à gauche vivent dans « Interface épurée ». Constaté après
    # une vraie installation, où il manquait visiblement la moitié du travail.
    [string]$Profil,
    # Répétition à blanc : montre tout ce qui changerait, n'écrit RIEN. Sans elle,
    # la seule façon d'éprouver un profil non interactif était de l'appliquer pour
    # de bon — donc de ne pas pouvoir l'éprouver du tout.
    [switch]$Simulation
)

# Auto-élévation : relance le script en administrateur si besoin, une seule fois.
# Doit rester ici, juste après param() et avant tout le reste -- $PSCommandPath
# n'est fiable qu'une fois le param() passé, et rien avant ce point ne doit
# supposer des droits admin.
$estAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $estAdmin) {
    $argumentsElevation = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$PSCommandPath`"")
    if ($Console) { $argumentsElevation += '-Console' }
    if ($Maintenance) { $argumentsElevation += '-Maintenance' }
    if ($Langue) { $argumentsElevation += @('-Langue', $Langue) }
    if ($Profil) { $argumentsElevation += @('-Profil', "`"$Profil`"") }
    if ($Simulation) { $argumentsElevation += '-Simulation' }
    try {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $argumentsElevation -Verb RunAs | Out-Null
    } catch {
        Write-Host "Élévation refusée ou impossible : $($_.Exception.Message)" -ForegroundColor Red
        Write-Host 'Relance manuellement depuis un PowerShell ouvert « en tant qu''administrateur ».' -ForegroundColor Yellow
    }
    exit
}

$ErrorActionPreference = 'Stop'

# Version de l'outil, affichée dans le titre de la fenêtre, l'en-tête et les rapports.
$script:Version = "1.5.1"


# Compteurs de la session (remis à zéro à chaque entrée de menu)
$script:CompteurOK = 0
$script:CompteurEchec = 0

