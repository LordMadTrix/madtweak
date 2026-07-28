# Instructions pour les agents — MadTweak

Ce fichier s'adresse aux assistants de code (Antigravity, Claude Code, Copilot,
Gemini…) qui travaillent sur ce dépôt. Il ne remplace pas le [README](README.md),
qui explique *ce que fait* l'outil ; il dit **ce qu'il ne faut pas casser**.

Chaque règle ci-dessous vient d'un incident réel. Ce ne sont pas des préférences
de style.

---

## La règle qui prime sur toutes les autres

> **Un outil d'optimisation qui casse une machine n'a rien optimisé.**

MadTweak tourne **en administrateur, sur les PC d'inconnus, dans le registre**.
Tout le reste en découle.

---

## 1. Les quatre portes de la simulation

**Aucune modification du système ne doit exister ailleurs que derrière l'une de
ces portes :**

| Type de modification | Porte obligatoire |
|---|---|
| Registre | `Set-RegValue` / `Remove-RegValue` / `Remove-RegKey` |
| Exécutables externes | `Invoke-Externe` |
| Services | `Set-ServiceEtat` |
| **Tout le reste** (fichiers, apps, tâches planifiées, winget…) | `Invoke-Action` |

Un `Remove-Item`, `Set-ItemProperty`, `Stop-Service` ou `Remove-AppxPackage` écrit
en direct **fait de vrais dégâts en mode simulation**. L'utilisateur qui coche
« simuler avant d'appliquer » attend que rien ne soit écrit — c'est la promesse
centrale de l'outil.

**C'est déjà arrivé.** Des fonctions de nettoyage ajoutées en v1.5–v1.7
supprimaient fichiers et clés de registre sans passer par les portes. Mesuré :
mode simulation actif, **cinq fichiers sur cinq effacés**, zéro ligne de
simulation émise. Une de ces fonctions supprime des installeurs dans le dossier
*Téléchargements* de l'utilisateur, sans confirmation ni corbeille.

Pour un traitement de masse (des milliers de fichiers), ne pas appeler
`Invoke-Action` fichier par fichier : tester `$script:Simulation` une fois, émettre
un seul `Write-Simu` avec le volume mesuré, et sortir. Voir `Clear-Contenu`.

## 2. Encodage : ce n'est pas un détail

| Fichier | Encodage exigé |
|---|---|
| `src/*.ps1` et `dist/MadTweak.ps1` | **UTF-8 AVEC BOM**, fins de ligne LF |
| `tests/*.ps1` | **UTF-8 AVEC BOM** |
| `Lancer.bat` | ASCII, CRLF, sans BOM |
| `autounattend.xml` généré | **UTF-8 SANS BOM** — convention inverse, exigée par Windows Setup |
| Blocs `run:` des workflows GitHub | **ASCII pur** |

Windows PowerShell 5.1 lit un fichier sans BOM en **ANSI**. Un accent ou un tiret
cadratin casse alors la chaîne, avec une erreur incompréhensible du genre
`Le terminateur " est manquant`. Le coureur GitHub écrit les blocs `run:` sans BOM :
**n'y mettre aucun caractère non-ASCII**.

Ce piège a mordu au moins cinq fois, y compris dans des scripts jetables.
`build.ps1` refuse de construire si un module perd son BOM.

## 3. Construction

`src/` est la source, `dist/MadTweak.ps1` le produit — **un seul fichier autonome**.

```powershell
.\build.ps1            # reconstruit dist/
.\build.ps1 -Verifier  # échoue si dist/ ne correspond plus à src/
```

**Toujours reconstruire avant de commiter.** La CI compare les deux et échoue
sinon. Ne jamais modifier `dist/` à la main.

## 4. Les filets de sécurité

Ils attrapent les pannes que le silence cacherait — une clé mal orthographiée ne
produit aucune erreur, juste un tweak qui ne se déclenche jamais.

| Filet | Quand | Attrape |
|---|---|---|
| `Test-ClesProfils` | démarrage | une clé de profil ne correspondant à aucun tweak |
| `Test-CoherenceAudit` | démarrage | un audit testant une clé qu'aucun tweak ne pose |
| `Test-Explications` | démarrage | un tweak sélectionnable **sans explication** |
| relevé `$script:ClesJouees` | fin de profil | une clé valide mais **hors d'atteinte** |
| `Test-AutounattendXml` | à chaque fichier de réponses | un réglage dans un passage où Windows l'ignorerait |
| CI | à chaque push | `dist/` ne correspondant plus à `src/` |

**Ajouter un tweak, c'est aussi :** lui donner une clé stable (`-Cle`), une
explication (`-Explication`), et une traduction anglaise dans `06-textes-tweaks.ps1`
(`<cle>.t` pour le titre, `<cle>.e` pour l'explication). Sans quoi les filets
protestent au démarrage.

## 5. Tests

```powershell
Import-Module Pester -RequiredVersion 3.4.0 -Force
Invoke-Pester .\tests\MadTweak.Tests.ps1
```

**Pester 3.4.0**, celui livré avec Windows — syntaxe `Should Be`, pas `Should -Be`.
Installer Pester 5 fait échouer la totalité des tests. Une conversion vers Pester 5
serait souhaitable, mais c'est une réécriture complète des assertions.

**Un test ne doit jamais modifier la machine de qui le lance.** Les tests qui
appellent des fonctions de nettoyage doivent activer la simulation *après* le
chargement des modules — voir le `BeforeAll` de « Fonctionnalités Phase 3 ».

## 6. Langue

Le français est la **langue d'écriture** : code, commentaires, messages, noms de
fonctions (`Invoke-Profil`, `Get-EditionsImage`). L'anglais est une **couche
d'affichage** ajoutée par `05-langue.ps1` et `06-textes-tweaks.ps1`.

Ne pas traduire le code en anglais. Ne pas laisser une chaîne visible sans sa
traduction : le filet `Test-Explications` la signalera.

## 7. Commentaires

Le projet documente **pourquoi**, pas quoi. Un commentaire utile explique une
contrainte non évidente, un piège rencontré, ou une décision et son coût :

```powershell
# Split-WindowsImage refuse une source en LECTURE SEULE, ce qu'est toujours une
# ISO montée. Sur une image contenant un .wim, le découpage direct échoue avec
# « Accès refusé », APRÈS la copie des fichiers — donc tard.
```

Ne pas écrire `# incrémente le compteur`.

## 8. Ce qu'il ne faut pas faire

- **Ne pas récupérer et exécuter du code depuis internet à l'exécution.** MadTweak
  tourne en administrateur sur des machines qui ne sont pas les nôtres. Un
  `Invoke-RestMethod | Invoke-Expression` ferait de chaque utilisateur une cible de
  chaîne d'approvisionnement.
- **Ne pas intégrer de code sous licence copyleft** : le projet est en MIT.
- **Ne pas ajouter de tweak « placebo ».** Les réglages populaires mais inertes ou
  nuisibles sont exclus *avec la raison en commentaire* : `LargeSystemCache`, la
  purge de la liste standby, la désactivation d'IPv6.
- **Ne pas supposer le matériel.** Type de disque, présence d'un NPU, édition de
  Windows, plateforme à veille moderne : tout se mesure à l'exécution. Un tweak
  doit **refuser de nuire** plutôt que de s'appliquer aveuglément — forcer la
  veille S3 sur une plateforme S0 provoquait des plantages au réveil.
- **Ne pas annoncer un succès non vérifié.** Un tweak qui échoue affiche `[ÉCHEC]`
  et sa raison. Il n'y a pas de succès silencieux.

## 9. Pièges vérifiés sur du vrai matériel

À connaître avant de toucher au générateur de clé d'installation
(`63-installation.ps1`) :

- `Split-WindowsImage` **refuse une source en lecture seule** — donc toute ISO
  montée. Toujours exporter l'édition vers un WIM temporaire d'abord.
- Un `.esd` converti en `.wim` **grossit d'environ 37 %**. Prévoir le double de la
  taille source en espace disque.
- `Clear-Disk` **ne ramène pas un disque à l'état brut** : une clé faite par Rufus
  reste en GPT, et l'indicateur « actif » (propre au MBR) fait alors échouer la
  création de partition — *après* l'effacement.
- Les **noms d'édition sont traduits** dans les images localisées : une ISO
  française contient « Windows 11 Professionnel », pas « Windows 11 Pro ». Lire
  l'image, ne jamais deviner.
- `FirstLogonCommands` est **synchrone** et s'exécute derrière l'écran de l'OOBE.
  Un `Read-Host` y bloque l'installation indéfiniment, sans que personne ne voie
  la console. Vérifier `Test-SansInteraction`.
- Les commutateurs du Media Creation Tool trouvés sur le web (`/MediaEdition`…) le
  basculent en **mise à niveau de la machine courante**, pas en création de support.

---

## Repères

| | |
|---|---|
| Cible | Windows 10 22H2 et Windows 11 22H2 → 25H2 |
| Moteur | Windows PowerShell **5.1** (pas 7 : les cmdlets Appx y sont lentes) |
| Modules | 28 dans `src/` |
| Tweaks à clé | 132 |
| Interface | WPF, thémable, avec repli console si WPF manque |
| Licence | MIT |
