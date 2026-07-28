#Requires -RunAsAdministrator
# ==============================================================================
# LE WINDOWS UTILITY INTÉGRAL V4 (VERSION FRANÇAISE)
# Inspiré de Chris Titus Tech - Version Système Intégral Maximale
#
# IMPORTANT : les modules de src\ ET le fichier construit DOIVENT rester en
#             UTF-8 AVEC BOM et en fins de ligne LF, sinon les accents seront
#             illisibles sous Windows PowerShell 5.1. build.ps1 s'en charge.
#
# Principe de la V4 : aucune action ne se déclare "appliquée" si elle a échoué.
# ==============================================================================

# param() DOIT être la première instruction exécutable du script : les commentaires
# et #Requires peuvent la précéder, rien d'autre. D'où sa place ici, en tête du
# tout premier module.
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
    # Tout est traduit : interface, profils, onglets, les 150 tweaks et les 104
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

$ErrorActionPreference = 'Stop'

# Version de l'outil, affichée dans le titre de la fenêtre, l'en-tête et les rapports.
$script:Version = "1.5"


# Compteurs de la session (remis à zéro à chaque entrée de menu)
$script:CompteurOK = 0
$script:CompteurEchec = 0

