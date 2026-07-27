# Contribuer à MadTweak

Merci de vouloir participer. Ce document dit l'essentiel ; le [README](README.md)
contient le détail technique (architecture, encodage, filets de sécurité).

## La règle qui prime sur toutes les autres

> **Un outil d'optimisation qui casse une machine n'a rien optimisé.**

MadTweak tourne sur des PC que je ne possède pas, en administrateur, dans le registre.
Tout le reste découle de là.

## Signaler un bug ou proposer un tweak

Utilise les [modèles d'issue](https://github.com/LordMadTrix/madtweak/issues/new/choose) :
ils demandent exactement ce dont j'ai besoin pour reproduire ou évaluer.

Pour un tweak, trois questions décident de son admission :

1. **Son effet est-il réel et vérifiable ?** Les réglages populaires mais inertes sont
   exclus volontairement, motif documenté en commentaire.
2. **Qu'est-ce qu'on perd ?** Un tweak sans contrepartie annoncée est un tweak qu'on
   applique mal.
3. **Sur quelles machines serait-il néfaste ?** S'il en existe, il devra les détecter
   et **refuser de s'appliquer**.

## Proposer du code

### Ne modifie jamais `dist/`

`dist/MadTweak.ps1` est **généré**. Édite les modules de `src/`, puis reconstruis :

```powershell
.\build.ps1              # construit dist\MadTweak.ps1
.\build.ps1 -Verifier    # vérifie qu'il est à jour (code 1 sinon)
```

Une intégration continue rejette toute PR où `dist/` ne correspond plus à `src/`.

### L'encodage n'est pas un détail

Tout `.ps1` doit être en **UTF-8 AVEC BOM** et en **fins de ligne LF**. Sans le BOM,
Windows PowerShell 5.1 lit le fichier en ANSI et `GÉNÉRÉ` devient `GÃ‰NÃ‰RÃ‰`.
`Lancer.bat` suit la convention **inverse** : ASCII, CRLF, sans BOM.

Le `.gitattributes` et `build.ps1` font respecter tout ça — ne les contourne pas.

### Ajouter un tweak

```powershell
Invoke-Tweak "Question posée à l'utilisateur ?" -Cle "identifiant-stable" `
    -Explication "Ce que ça fait, en français simple. Et surtout CE QUE ÇA COÛTE." {
    Set-RegValue -Path "HKCU:\..." -Name "Valeur" -Value 0
}
```

Puis, dans l'ordre :

1. Ajouter la clé aux profils pertinents (`src/80-profils.ps1`)
2. Ajouter un test d'audit (`src/70-audit.ps1`)
3. Ajouter son annulation (`src/58-menu-annuler.ps1`)
4. Si le tweak vit dans un menu neuf, **ajouter ce menu à `Invoke-TousLesMenus`** —
   sinon sa clé ne sera jamais atteinte

### Les portes obligatoires

Toute modification passe par l'une d'elles, sinon la **simulation ferait de vrais dégâts** :

| Type | Fonction |
|---|---|
| Registre | `Set-RegValue` / `Remove-RegValue` / `Remove-RegKey` |
| Exécutable | `Invoke-Externe` |
| Tout le reste | `Invoke-Action` |

### Un tweak refuse de nuire

Plutôt qu'appliquer un réglage néfaste sur *cette* machine-ci, il lève une erreur
explicative :

```powershell
if ($type -eq 'HDD') {
    throw "Le disque système est un disque dur MÉCANIQUE : SysMain y accélère réellement le chargement des applications. Refusé."
}
```

Un refus **n'est pas un échec** : c'est le comportement attendu.

## Avant d'ouvrir une PR

- [ ] `.\build.ps1 -Verifier` passe
- [ ] L'outil se lance et le tweak apparaît dans l'interface
- [ ] `Simuler` montre le bon changement, **sans rien écrire**
- [ ] `Appliquer` puis *Restauration exacte* remet la machine dans son état d'origine
- [ ] Les messages sont **en français**, et disent ce que le réglage coûte

## Langue

Le code, les commentaires, les messages et la documentation sont **en français** —
c'est un choix assumé du projet. Les noms de fonctions suivent la convention
PowerShell (`Verbe-Nom` en anglais : `Set-RegValue`, `Invoke-Tweak`).

## Licence

En contribuant, tu acceptes que ton apport soit publié sous licence [MIT](LICENSE).
