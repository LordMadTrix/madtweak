# 🔧 MadTweak 1.5.2 — version fiabilité

Posts prêts à copier-coller.

**Angle choisi :** factuel et mesuré. La version corrige un défaut réel du mode
simulation ; le dire sans dramatiser vaut mieux que de le noyer dans une liste de
nouveautés, et mieux aussi que d'en faire un mea culpa. L'argument qui suit —
« ce n'est plus une promesse, c'est un test » — est vérifiable par n'importe qui,
ce qui le rend plus solide qu'un slogan.

---

## 📘 Pour Facebook

🔧 **MadTweak 1.5.2 est en ligne — version fiabilité.** 🔧

Salut l'équipe ! Pas de nouvelle fonctionnalité cette fois. J'ai passé le projet
au peigne fin, ligne par ligne, et cette version corrige six choses que l'audit a
sorties du bois.

**La principale concerne le mode « simuler avant d'appliquer ».** 🔍

Vous cochez la case, l'outil vous montre ce qu'il *changerait* sans rien toucher.
C'est la promesse, et elle tenait presque partout. Une exception s'était
glissée : dans le nettoyage de disque, la suppression du dossier `Windows.old`
s'exécutait quand même. Si vous avez lancé ce nettoyage en simulation avec la
1.5.1, jetez un œil à votre `Windows.old` — c'est la copie de votre ancienne
installation de Windows.

C'est corrigé, et vérifié dans les deux sens : plus rien ne bouge en simulation,
tout s'applique toujours en exécution réelle.

**Le vrai correctif est ailleurs, et j'y tiens.** ✅

La règle « aucune modification en dehors des passages obligés » était une
consigne écrite en commentaire, que rien ne contrôlait. Maintenant, un test relit
le code tout seul et refuse la moindre suppression de fichier ou coupure de
service qui essaierait de passer à côté. Si j'écris un jour un réglage distrait,
c'est l'intégration continue qui me le refuse — pas vous qui le découvrez.

**Corrigé aussi :**
👉 Le bouton Télécharger servait un fichier du 2 août, sans le dernier réglage de
confidentialité : le site annonçait 156 réglages, vous en receviez 155. Réglé.
👉 L'export de script autonome générait un fichier vide en affichant « réussi ».
Il fonctionne vraiment.
👉 La construction de l'outil n'était pas reproductible d'une version de
PowerShell à l'autre.

**Ce qui n'a pas bougé, et que j'ai revérifié :**
✅ La sauvegarde fonctionne exactement : ce qui existait revient à sa valeur
d'origine, ce qu'un réglage a créé disparaît vraiment.
✅ **Aucun réglage n'affaiblit Defender, l'UAC ou le pare-feu.** Jamais.
✅ Les réglages risqués sont annoncés comme tels, réversibles, et absents des
profils automatiques.

42 tests au vert, 156 réglages, gratuit, libre, en français et en anglais 🇫🇷🇬🇧

👇 C'est ici :
https://lordmadtrix.github.io/madtweak/

💛 Si vous voulez soutenir le projet :
https://www.patreon.com/cw/LordMad

Dites-moi ce que ça donne sur vos machines — c'est comme ça que le projet
avance. ❤️🖤

#MadTweak #Windows11 #Optimisation #OpenSource #PowerShell #LogicielLibre

---

## 🐦 Pour X (Twitter)

🔧 **MadTweak 1.5.2 — version fiabilité**

Six correctifs issus d'un audit complet, pas de nouvelle fonctionnalité.

✅ Le mode simulation avait une exception : la suppression de `Windows.old`
   s'exécutait quand même. Corrigé, vérifié dans les deux sens.
✅ Un test vérifie désormais la règle au lieu de la promettre
✅ Le téléchargement servait un fichier périmé — réglé

42 tests au vert. Libre & gratuit 👇
Soutien : https://www.patreon.com/cw/LordMad

#Windows11 #OpenSource #PowerShell

---

## 💬 Version courte (commentaire, Discord, story)

MadTweak 1.5.2 est sortie 🔧
Version fiabilité : six correctifs issus d'un audit complet.
Le mode simulation avait une exception sur la suppression de `Windows.old` —
corrigé, et un test l'empêche maintenant de revenir, au lieu d'une consigne en
commentaire que rien ne vérifiait.
Le bouton Télécharger servait aussi un fichier périmé : réglé.
👉 https://lordmadtrix.github.io/madtweak/
💛 Soutenir : https://www.patreon.com/cw/LordMad

---

## ⚠️ À savoir avant de publier

- **Tous les chiffres sont mesurés**, pas estimés : 7 fichiers sur 7 détruits en
  bac à sable, 2 551 octets d'écart entre le dépôt et la release, 156 réglages
  comptés en lançant le mode inventaire, 42 tests au vert.
- **Le ton reste factuel.** Le défaut est nommé sans dramatisation : quelqu'un
  finira par relire le journal des modifications, et mieux vaut l'avoir dit
  soi-même — mais un mea culpa appuyé dessert le projet autant qu'un silence.
- **L'invitation à vérifier son `Windows.old`** ne doit pas sauter au montage :
  c'est la seule action concrète que les utilisateurs de 1.5.1 peuvent
  entreprendre.
- **Ne pas promettre que tout est parfait.** L'audit a trouvé six choses ; il en
  reste sûrement d'autres.
