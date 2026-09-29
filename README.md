# LAB — Conteneurisation, de la page web à la plateforme

Deux laboratoires successifs, dans un même dépôt.

| Laboratoire | Objet                                                   | Support          |
| ----------- | -------------------------------------------------------- | ---------------- |
| **1**       | une page web statique servie par **nginx**, sans privilège | ce document      |
| **2**       | **Moodle**, plateforme de gestion, avec sa base de données | `moodle/README.md` |

Le premier est délibérément minuscule : une page, un conteneur, une seule
décision à prendre. Le second applique la même méthode à un logiciel qui ne
tient pas en un conteneur, qui ne démarre pas en trois secondes, et qui ne peut
fonctionner correctement que si quelqu'un a pensé à la persistance, à l'ordre de
démarrage et à la langue.

Les deux labs partagent la même exigence : **chaque décision est écrite, sa
raison est expliquée, chaque commande est vérifiée avant d'être publiée.**

---

# LAB 1 — Page web conteneurisée

Page web statique minimaliste, servie par **nginx** dans un conteneur
**Docker**, exécutée sans aucun privilège et sans aucune dépendance
temporelle (en anglais : *runtime dependency*) côté navigateur.

Chaque fichier du dépôt est commenté en détail. Les commentaires expliquent
**pourquoi**, jamais la mécanique évidente.

---

## 1. Démarrage rapide

Prérequis : Docker et Docker Compose, version récente.

```bash
docker compose up --build
```

Puis ouvrir <http://127.0.0.1:8080/> dans un navigateur.

Arrêter et supprimer le conteneur :

```bash
docker compose down
```

Le service est limité à la boucle locale. Il n'est **pas** joignable depuis
le réseau du laboratoire.

---

## 2. Arborescence

```
projet-mdi/
├── Dockerfile              # Construction de l'image
├── compose.yaml            # Description du service et de son exécution
├── .dockerignore           # Fichiers exclus du contexte de construction
├── .gitignore              # Fichiers exclus du suivi de version
├── README.md
├── nginx/
│   ├── nginx.conf          # Configuration principale (processus, HTTP)
│   └── conf.d/
│       └── app.conf        # Comportement des adresses (routes, cache)
├── site/                   # Contenu servi (le site lui-même)
│   ├── index.html
│   ├── erreurs/
│   │   └── 404.html
│   └── assets/
│       ├── styles.css
│       └── app.js
└── moodle/                 # LAB 2 — plateforme Moodle, documentation dans
    └── README.md             moodle/README.md
```

Le découpage du site en trois fichiers (`index.html`, `styles.css`, `app.js`)
n'est pas un caprice : c'est la **séparation des responsabilités**. Le HTML
décrit la structure, le CSS l'apparence, le JavaScript le comportement.
Conséquence pratique : remplacer la feuille de style ne casse ni le contenu
ni le comportement.

---

## 3. Chaîne de responsabilité

Comprendre qui fait quoi, dans quel ordre, est la clé du laboratoire.

| Étape | Acteur | Produit |
|---|---|---|
| 1 | `docker compose up --build` | Une image Docker, puis un conteneur |
| 2 | Le conteneur démarre la commande `nginx` | Un processus, sans privilège |
| 3 | nginx lit `nginx/nginx.conf` | Les réglages généraux |
| 4 | nginx inclut `nginx/conf.d/app.conf` | Les routes et les en-têtes |
| 5 | Le navigateur demande `/` | Une requête HTTP |
| 6 | nginx sert `index.html` et `assets/*` | La page |
| 7 | Le bouton interroge `/api/infos` | Une réponse JSON |

Le point essentiel : **l'image ne dépend pas de la machine**. Une machine
vierge, une university, un portable : même résultat.

---

## 4. Vérifier que tout fonctionne

Chaque commande ci-dessous a été exécutée sur ce dépôt. Les résultats
indiqués sont les résultats réellement obtenus.

### 4.1 L'état du conteneur

```bash
docker compose ps
```

```
  projet-mdi-web-1 (lab-page-web:1.0.0) Up 8 seconds (healthy) [8080]
```

`healthy` signifie que la sonde de santé définie dans le `Dockerfile` a
réussi. Ce n'est pas la même chose que « le conteneur existe » : un processus
peut tourner tout en refusant de répondre.

### 4.2 Le serveur répond, et avec le bon code

```bash
curl -I http://127.0.0.1:8080/
```

```
HTTP/1.1 200 OK
Content-Type: text/html; charset=utf-8
Cache-Control: no-cache
X-Content-Type-Options: nosniff
X-Frame-Options: SAMEORIGIN
Referrer-Policy: strict-origin-when-cross-origin
```

`X-Content-Type-Options` est l'en-tête de sécurité du navigateur : il
interdit au navigateur de deviner le type d'un fichier téléchargé.

### 4.3 L'oracle de santé

```bash
curl http://127.0.0.1:8080/healthz
```

```
ok
```

C'est exactement la route que Docker interroge toutes les 30 secondes.

### 4.4 L'API JSON, sans code serveur

```bash
curl http://127.0.0.1:8080/api/infos
```

```json
{"serveur":"nginx","role":"page statique + api minimale","conteneur":"non-root","dependances-front":"aucune"}
```

Aucun programme serveur n'a été écrit. La directive `return` de nginx produit
la réponse.

### 4.5 L'erreur 404 est honnête

```bash
curl -o /dev/null -s -w '%{http_code}\n' http://127.0.0.1:8080/adresse-inexistante
```

```
404
```

C'est un point sur lequel la construction initiale était **fausse** : la
règle par défaut renvoyait la page d'accueil pour toute adresse inconnue, avec
un code `200`. Une adresse mal orthographiée affichait donc l'accueil, sans
la moindre erreur visible. Le site étant statique, le code `404` est la seule
réponse correcte.

### 4.6 La compression fonctionne

```bash
curl -I -H 'Accept-Encoding: gzip' http://127.0.0.1:8080/assets/styles.css
```

```
Content-Encoding: gzip
Vary: Accept-Encoding
```

La feuille de style passe de 17 191 à 5 902 octets, soit une division par
trois. `Vary: Accept-Encoding` indique aux caches que la réponse dépend de
l'encodage accepté par le client.

### 4.7 Le conteneur est bien isolé

```bash
docker exec projet-mdi-web-1 ps -o user,pid,args
```

```
USER     PID   COMMAND
nginx        1 nginx: master process nginx -g daemon off;
nginx       20 nginx: worker process
```

Le processus maître est bien le processus numéro 1, et il appartient à
l'utilisateur `nginx`, pas à `root`.

```bash
docker exec projet-mdi-web-1 touch /essai
```

```
touch: /essai: Read-only file system
```

L'échec est **voulu**. La racine du conteneur est montée en lecture seule
(`read_only: true`). Une écriture non prévue échoue au lieu de modifier le
système.

```bash
docker inspect projet-mdi-web-1 \
  --format 'User={{.Config.User}} CapDrop={{.HostConfig.CapDrop}} Readonly={{.HostConfig.ReadonlyRootfs}}'
```

```
User=nginx CapDrop=[ALL] Readonly=true
```

- `User=nginx` : aucun privilège.
- `CapDrop=[ALL]` : toutes les capacités Linux retirées. Une page web n'en a
  besoin d'aucune.
- `Readonly=true` : système de fichiers non modifiable.

---

## 5. Les décisions, et leur raison

Un choix sans raison s'apprend par cœur et se casse au premier changement.
Voici les décisions du laboratoire, avec leur justification.

### 5.1 Pourquoi le port 8080 et pas 80 ?

Un processus non privilégié ne peut pas ouvrir un port inférieur à 1024. Le
port 80 exige d'être `root`. En utilisant 8080, le serveur peut tourner en
utilisateur ordinaire — c'est la condition pour que le conteneur fonctionne
sans privilège.

La publication vers l'extérieur se fait par Docker, **pas** par le processus :
c'est le démon qui relie le port de la machine au port du conteneur.

### 5.2 Pourquoi une image à une seule étape ?

La construction en plusieurs étapes (en anglais : *multi-stage build*) sert
à laisser un outil de compilation dans une étape intermediate, absent de
l'image finale. Ici, il n'y a rien à compiler : seulement des fichiers à
copier. Une étape intermédiaire serait donc du bruit. La règle : utiliser
plusieurs étapes quand on construit quelque chose, une seule quand on
assemble.

### 5.3 Pourquoi supprimer `default.conf` et `nginx.conf` ?

L'image officielle nginx contient une configuration qui écrit son fichier
d'identifiant dans `/run`, un répertoire inaccessible à un utilisateur non
privilégié. Sans ce retrait, le conteneur **refuse de démarrer** avec :

```
open() "/tmp/nginx.pid" failed (30: Read-only file system)
```

C'est le premier obstacle réel rencontré pendant la construction de ce
laboratoire. Le message est peu parlant : il désigne un chemin temporaire,
alors que la cause est un conflit entre la configuration d'origine et les
contraintes du conteneur.

### 5.4 Pourquoi remplacer `nginx.conf` plutôt que le compléter ?

`nginx.conf` de l'image déclare `user nginx ;`. Cette directive n'a de sens
que si le processus maître est `root`. Elle produit un avertissement
permanent, sans conséquences, mais trompeur.

Remplacer le fichier entier supprime le problème à la racine. Cela reste
gérable tant que le laboratoire est court ; sur un serveur réel, on
privilégierait la surcharge pour conserver les mises à jour de l'image de
base. Le choix dépend de la contrainte dominante : **reproductibilité** ou
**mises à jour**.

### 5.5 Pourquoi zéro dépendance côté navigateur ?

Ni bibliothèque, ni cadre de travail (framework), ni feuille de style
externe. Pour moins de cent lignes de JavaScript, une bibliothèque serait
plus volumineuse que le problème à résoudre. Et elle pourrait échouer
silencieusement, coupant la page entière.

Le navigateur rend la page sans JavaScript. Seuls le thème et l'appel à
l'API sont conditionnels. C'est le principe de **dégradation gracieuse** :
la fonction s'ajoute, elle ne conditionne pas l'accès au contenu.

### 5.6 Pourquoi nginx produit-il du JSON ?

Pour montrer qu'un serveur web n'est pas limité au service de fichiers. La
directive `return` produit une réponse complète, avec son code et son type
MIME, sans une seule ligne de langage serveur. Comprendre cette frontière
évite de surdimensionner : on n'installe pas un environnement complet
d'exécution pour renvoyer trois valeurs.

---

## 6. Pièges réels rencontrés

Ces trois pièges ont été rencontrés **pendant** la construction, pas
recopiés dans une documentation. Ils sont listés ici parce qu'ils ne
produisent aucun message d'erreur.

### 6.1 Le `add_header` qui remplace au lieu de s'ajouter

Dans nginx, un `add_header` déclaré dans un bloc enfant **remplace** tous
ceux du bloc parent. Il ne s'y ajoute pas.

Conséquence mesurée : `/assets/styles.css` renvoyait ses trois en-têtes de
sécurité, et `/` n'en renvoyait aucun. Aucun avertissement, aucune erreur.
La page d'accueil était simplement non protégée.

La parade : redéclarer les en-têtes dans **chaque** bloc qui en a besoin, et
vérifier par `curl -I`, jamais à l'œil nu.

### 6.2 Le `200` sur une adresse inexistante

`try_files $uri $uri/ /index.html` est le réglage des applications à page
unique : le routeur JavaScript lit l'adresse et affiche le bon écran. Sur un
site statique, ce routeur n'existe pas, et toute adresse inconnue renvoie
l'accueil avec un code `200`.

La parade : utiliser `=404`, et tester avec
`curl -o /dev/null -s -w '%{http_code}\n' <adresse>`. Un `200` sur une
adresse qui n'existe pas est un défaut, pas une commodité.

### 6.3 Le montage `tmpfs` mal ciblé

Le montage en mémoire vive porte sur `/tmp/nginx`. Écrire dans `/tmp` ne
suffit pas : `/tmp` lui-même n'est pas monté et reste en lecture seule. Le
fichier d'identifiant doit donc être écrit dans `/tmp/nginx/nginx.pid`, et
non dans `/tmp/nginx.pid`.

La parade : un chemin de montage et un chemin de configuration sont le même
paramètre, écrit à deux endroits. Les modifier ensemble.

---

## 7. Vérifier la syntaxe sans démarrer

```bash
# Configuration nginx, à l'intérieur de l'image
docker run --rm lab-page-web:1.0.0 nginx -t
```

```
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Cette commande est à faire tourner **avant** de reconstruire. Un conteneur
qui démarre et s'arrête est plus lent à diagnostiquer qu'un test qui échoue.

---

## 8. Exercices

Chaque exercice produit un livrable nommé, que le suivant consomme. Les
minutes indiquées sont cumulatives.

### Exercice 1 — Modifier le titre (5 min)

Dans `site/index.html`, remplacer le texte du titre `<h1>`. Reconstruire,
vérifier dans le navigateur.

Livrable produit : un `index.html` modifié.

### Exercice 2 — Ajouter une carte (10 min)

Dans `site/index.html`, dupliquer le bloc `<section class="carte">` et
modifier son contenu. **Sans toucher au CSS** : la mise en forme doit rester
correcte.

Livrable produit : une troisième carte dans la page.
Consommé par : l'exercice 3.

### Exercice 3 — Comprendre la répétition (10 min)

La nouvelle carte s'affiche correctement, alors qu'aucune règle CSS ne la
cible. Expliquer pourquoi, en une phrase, en nommant la classe utilisée.

Livrable produit : une réponse écrite.

### Exercice 4 — Changer un port (10 min)

Passer le service du port 8080 au port 9090. Trois fichiers sont concernés.
Trouver lesquels, et justifier chaque modification.

Livrable produit : un `compose.yaml` et un `app.conf` modifiés.

### Exercice 5 — Supprimer une garantie (10 min)

Retirer l'instruction `USER nginx` du `Dockerfile`. Construire, démarrer,
observer la différence. Comparer les journaux des deux versions.

Livrable produit : une comparaison écrite des deux executions.

### Exercice 6 — Rendre l'écriture impossible (10 min)

Ajouter à `compose.yaml` une seconde entrée dans `tmpfs` pour `/tmp`. Le
conteneur démarre-t-il encore ? Justifier.

Livrable produit : une réponse argumentée.

---

## 9. Pour aller plus loin

- **Versionner les ressources.** Renommer `styles.css` en `styles-v2.css` et
  mettre à jour `index.html`. Observer que le cache du navigateur n'a plus
  besoin d'être vidé.
- **Activer la compression de l'image.** Voir l'étape correspondante du
  guide officiel Docker.
- **Ajouter un second service.** Un serveur d'API séparé, relié par le
  réseau interne de Compose. Le réseau de bridge est privé par défaut.
- **Répartir la charge.** Voir les modes de répartition de trafic de nginx
  (`upstream`, `least_conn`, `ip_hash`).
- **Passer au second laboratoire.** `moodle/README.md` reprend la même méthode
  sur une plateforme complète : deux conteneurs, une base de données, des
  volumes, une interface en français, et les pièges réellement rencontrés.

---

## 10. Licence

MIT. Usage pédagogique libre. Le second laboratoire, `moodle/`, est distribué
sous la même licence ; Moodle lui-même relève de la GPL.
