# LAB — Moodle conteneurisé

Moodle, la plateforme d'enseignement en ligne, servie par **Apache** dans un
conteneur **Docker**, adossée à une base **MariaDB** dans un second conteneur.
Rien n'est installé sur la machine : deux conteneurs, un réseau privé, un
fichier de configuration.

Ce laboratoire est la suite directe du laboratoire de la page web servie par
nginx. Il reprend exactement la même méthode — chaque décision est écrite, son
raison est expliquée, chaque commande est vérifiée — et il l'applique à un
programme qui, lui, ne se lance pas en trois secondes.

---

## 1. Ce que ce laboratoire démontre

1. **Une application de gestion réelle tient en deux conteneurs**, et non un
   seul. Moodle n'écrit jamais ses données lui-même : il parle à une base, et la
   base a son propre cycle de vie.
2. **L'ordre de démarrage se déclare, il ne se devine pas.** Un serveur qui
   démarre trop vite est un serveur qui échoue ; l'attente se describe dans le
   fichier Compose.
3. **Un état tient dans des volumes, pas dans un conteneur.** Un conteneur se
   détruit et se recrée ; ce qui doit survivre doit être ailleurs.
4. **Une interface en français ne se négocie pas.** Moodle se sert dans la
   langue de l'interface qu'on lui demande, et cette langue se prouve.
5. **La sécurité se mesure en capacités retirées**, pas en intentions.

---

## 2. Démarrage rapide

### 2.1 Préalable

Docker et Docker Compose, version récente. Vérification :

```bash
docker --version
docker compose version
```

### 2.2 Renseigner les trois mots de passe

Le laboratoire ne fonctionne qu'après cette étape, et **elle est obligatoire** :
les fichiers de configuration refusent de démarrer tant qu'une valeur manque,
plutôt que d'échouer dix minutes plus tard sur une erreur incompréhensible.

```bash
cd moodle
cp .env.example .env
nano .env
```

Trois lignes sont à compléter, dans le fichier `.env` :

| Variable                 | Rôle                                              | Contrainte                       |
| ------------------------ | ------------------------------------------------- | -------------------------------- |
| `MOODLE_ADMIN_PASSWORD`  | mot de passe du compte d'administration           | long, plusieurs mots            |
| `MOODLE_ADMIN_EMAIL`     | adresse du compte d'administration                 | adresse de laboratoire           |
| `MOODLE_DB_PASSWORD`     | mot de passe du compte applicatif de la base      | valeur de laboratoire            |
| `MOODLE_DB_ROOT_PASSWORD`| mot de passe d'administration de la base          | valeur **différente** de la précédente |

Inventez ces valeurs. Elles ne quittent jamais la machine : le réseau du
laboratoire est déclaré interne, donc sans accès à Internet, et la base n'est
publiée sur aucun port. Un mot de passe réel serait une erreur.

### 2.3 Construire et démarrer

```bash
docker compose up --build -d
```

Puis, dans un second terminal, suivre le démarrage :

```bash
docker compose logs -f moodle
```

Puis ouvrir <http://127.0.0.1:8081/> dans un navigateur.

### 2.4 Repères de temps

| Étape                                        | Durée constatée      |
| -------------------------------------------- | -------------------- |
| Construction de l'image (première fois)      | 4 à 6 minutes        |
| Premier démarrage : installation de Moodle   | 2 à 3 minutes        |
| Redémarrages suivants                        | 10 à 20 secondes     |
| Arrêt et suppression des conteneurs          | 5 à 10 secondes      |

La construction est lente pour une raison précise : **Composer télécharge
Moodle depuis Internet**, environ deux cents mégaoctets. C'est le prix d'une
image qui reproduit exactement la version demandée, plutôt qu'une image
préconstruite dont personne ne connaît le contenu.

### 2.5 Arrêter

```bash
docker compose down
```

Les volumes sont conservés : le site rouvre avec les mêmes cours, les mêmes
comptes, le même mot de passe. C'est le comportement attendu entre deux
séances de laboratoire.

---

## 3. Arborescence du laboratoire

```
moodle/
├── Dockerfile              # Construction de l'image Moodle, en quatre étapes
├── compose.yaml            # Les deux services, le réseau, les volumes
├── entrypoint.sh           # Préparation au démarrage, puis lancement
├── .env.example            # Modèle de configuration, sans aucun secret
├── .env                    # La copie que l'étudiant remplit (jamais versionnée)
├── .dockerignore           # Fichiers exclus du contexte de construction
├── php/
│   └── zz-laboratoire.ini  # Réglages PHP du laboratoire
├── apache/
│   └── 000-default.conf    # Hôte virtuel Apache et en-têtes de sécurité
└── README.md               # Ce document
```

Trois volumes, invisible dans l'arborescence parce qu'ils vivent dans Docker,
et non dans le dépôt :

| Volume                | Monté sur          | Contenu                                        |
| --------------------- | ------------------ | ---------------------------------------------- |
| `lab-moodle-code`     | `/srv/moodle`      | le code de l'application et son `config.php`   |
| `lab-moodle-donnees`  | `/srv/moodledata`  | fichiers déposés, cache, sauvegardes           |
| `lab-moodle-bd-donnees` | `/var/lib/mysql` | les tables de la base                          |

---

## 4. La chaîne de responsabilité

```
navigateur
    │  http://127.0.0.1:8081
    ▼
conteneur « moodle » — Apache sert /srv/moodle, PHP exécute Moodle
    │  réseau interne « lab-moodle-reseau », nom « bd », port 3306
    ▼
conteneur « bd » — MariaDB répond, port non publié
```

Trois conséquences, chacune vérifiable :

- **La base n'a pas de port publié.** On ne peut pas l'atteindre depuis la
  machine, seulement depuis le réseau du laboratoire. Une base de données
  joignable depuis le poste de l'étudiant n'est pas une base de laboratoire,
  c'est une cible.
- **Moodle connaît la base par son nom, pas par son adresse.** Le fichier
  Compose donne à la base le nom `bd` dans le réseau. Les adresses IP de
  conteneurs changent d'un démarrage à l'autre ; un nom, non.
- **Moodle ne démarre pas avant que la base réponde.** Deux mécanismes
  complémentaires : Compose attend l'état « sain » du service `bd`, et le
  script d'entrée vérifie lui-même la connexion.

---

## 5. Vérifier que tout fonctionne

Une affirmation sans preuve n'est pas une affirmation, c'est une promesse. Voici
les quatre vérifications, de la plus rapide à la plus complète.

### 5.1 L'état des deux services

```bash
docker compose ps
```

Les deux lignes doivent indiquer un état **healthy**, c'est-à-dire « sain », et
non seulement « démarré ». « Démarré » prouve qu'un processus existe. « Sain »
prouve qu'une sonde a réussi.

### 5.2 Le journal, ligne par ligne

```bash
docker compose logs moodle
```

Le script d'entrée annonce chaque étape, préfixée par `[preparation]`. Chaque
ligne est une preuve, et il faut savoir la lire :

| Ligne annoncée                                  | Ce qu'elle prouve                                                  |
| ----------------------------------------------- | ------------------------------------------------------------------ |
| `plateforme : … langue fr`                       | les variables du fichier `.env` ont été lues et comprises          |
| `adresse publique : http://localhost:8081`      | l'adresse servie correspond à celle du fichier `.env`              |
| `dépose du code de Moodle dans le volume`       | le volume était vide : c'est un tout premier démarrage             |
| `code de Moodle déjà présent dans le volume`    | le volume était déjà peuplé : c'est un redémarrage                 |
| `base de données disponible`                    | la connexion à la base a réussi, avec les identifiants du `.env`   |
| `paquet de langue « fr » installé`              | l'interface sera en français                                        |
| `Moodle est déjà installé`                      | aucune réinstallation : les données précédentes sont intactes       |
| `Installation terminée avec succès`             | les centaines de tables ont été créées                             |
| `config.php protégé`                            | le fichier de connexion à la base n'est lisible que par le serveur  |
| `démarrage du serveur`                          | le conteneur cède la main à Apache, qui devient le processus principal |

Une ligne qui manque n'est pas anodine : elle désigne l'étape qui n'a pas eu
lieu.

### 5.3 L'interface est bien en français

Ouvrir <http://127.0.0.1:8081/> doit afficher une page de connexion dont le
titre est « Se connecter sur le site » et dont les champs sont « Nom
d'utilisateur » et « Mot de passe ». Ni « Username », ni « Log in ». Si la page
est en anglais, le paquet de langue n'a pas été installé.

### 5.4 Se connecter : la preuve qui ne trompe pas

Se connecter avec le compte d'administration du fichier `.env` doit ouvrir une
page dont le titre est « Tableau de bord ». C'est la seule vérification qui
traverse vraiment toute la chaîne : le mot de passe saisi est comparé au
condensat obtenu par hachage, qui est stocké en base. La session est ensuite
ouverte, et la page est rendue à partir des tables. Un site qui affiche la
page de connexion mais refuse toute connexion est un site à moitié mort.

### 5.5 Ce que la sonde de santé prouve, et ce qu'elle ne prouve pas

La sonde interroge la page de connexion depuis l'intérieur du conteneur, puis
exige une page **rendue**, et non un simple code de réponse. Elle prouve donc que
PHP exécute Moodle, que la session ouvre une connexion vers la base, et que le
paquet de langue est en place.

Elle ne prouve pas que la page s'affiche correctement dans un navigateur, ni que
le port est publié sur la machine, ni que la base accepte les écritures. Une
sonde est une garantie minimale, pas un garantie de fabrication.

---

## 6. Les décisions, et leur raison

### 6.1 Pourquoi Moodle 4.5 et pas 5 ?

Moodle 5 a déplacé le code servi dans un sous-dossier `public/`. Un hôte
virtuel qui pointe vers la racine du code ne sert plus rien. Moodle 4.5 est une
version de support long, à l'arborescence classique, et c'est un critère
distingué : **le laboratoire est construit, exécuté et vérifié**.

### 6.2 Pourquoi Composer dans l'image

Composer est l'outil officiel de PHP, et c'est lui qui installe Moodle à la
bonne version. Le faire pendant la construction plutôt qu'au démarrage a trois
avantages : le démarrage est rapide, le versionnement est vérifiable dans le
journal, et l'image ne dépend pas du réseau au moment de démarrer.

### 6.3 Pourquoi `mysqli` et pas `pdo_mysql`

Moodle déclare une base de type `mariadb`. Ce type est un alias d'un pilote
historique bâti sur **mysqli**, le moteur d'accès aux bases de données de PHP
le plus ancien. Installer la seule extension moderne `pdo_mysql` ne suffit pas :
Moodle reconnaît le type, puis échoue à se connecter. L'erreur affichée est
`incorrect value "mariadb" for "dbtype"`, qui ne désigne pas une cause
évidente. L'extension `mysqli` est donc compilée explicitement, et le
laboratoire ne prétend pas que l'autre était inutile : elle sert à d'autres
applications.

### 6.4 Pourquoi le code est dans un volume, et pas dans l'image

Au moment de s'installer, Moodle écrit un fichier `config.php` à la racine de son
code. Ce fichier contient le lien avec la base de données.

Ce fichier doit survivre à la destruction du conteneur. Un fichier écrit dans la
couche inscriptible d'un conteneur disparaît dès que le conteneur est recréé, ce
qui arrive à chaque `docker compose up` après un arrêt, et après n'importe quel
redémarrage de la machine. La base, elle, reste intacte dans son volume. Moodle
se retrouve alors avec des tables mais sans configuration, et refuse de démarrer
en annonçant que les tables existent déjà — un message qui désigne un problème
d'installation alors que la cause est un fichier disparu.

Le code est donc dans un volume, et l'image conserve une copie de référence,
(`/usr/share/moodle-image`, que le script d'entrée dépose au premier démarrage.
Avantage secondaire : le code du volume est restaurable à l'identique depuis
l'image.

### 6.5 Pourquoi un réseau déclaré interne

Le réseau du laboratoire porte la mention « interne ». Docker lui coupe tout
accès vers Internet, y compris pour les conteneurs qui le rejoignent. Le
paquet de langue est donc téléchargé **pendant la construction**, quand le réseau
externe existe encore, et non au démarrage.

Ce n'est pas une contrainte subiée : c'est ce qui permet d'expliquer qu'un
laboratoire n'a pas besoin d'Internet pour fonctionner une fois construit.

### 6.6 Pourquoi des capacités Linux sont retirées

Un conteneur tourne avec des capacités Unix, c'est-à-dire des droits précis
donnés à `root`. Le laboratoire en retire plusieurs, et en restitue une seule.

Le cas le plus parlant est `DAC_OVERRIDE`. Cette capacité autorise `root` à
écrire dans un répertoire appartenant à quelqu'un d'autre. Le laboratoire
refuse de la rendre : la création du répertoire de langue, par exemple, est
confiée à `www-data`, le compte du serveur web, parce que c'est ce compte qui
en est le propriétaire légitime. Le retrait se voit immédiatement : une tentative
de contournement échoue au lieu de réussir. Une contrainte qui ne se remarque
qu'en cas d'incident n'a jamais protégé quoi que ce soit.

---

## 7. Pièges réels rencontrés

Chacun de ces pièges a réellement été rencontré pendant la construction de ce
laboratoire. Aucun n'est inventé pour l'occasion.

### 7.1 Une dépendance circulaire dans le fichier de construction

**Symptôme.** La construction échoue, et le message d'erreur semble parler d'un
fichier absent alors qu'il est présent.

**Cause.** L'étape qui fournit les outils de construction est construite à
partir de l'image qui contient déjà PHP compilé. L'étape des outils dépend donc
de l'étape du socle, alors qu'elle est censée le précéder.

**Correction.** L'étape des outils est déclarée en premier, et ne dépend que
d'images publiques. L'ordre des étapes devient une question de lecture, pas
d'aléa.

### 7.2 Un téléchargement refusé sans raison visible

**Symptôme.** Le paquet de langue français ne se télécharge pas ; le serveur de
Moodle répond par un refus.

**Cause.** Le serveur de Moodle refuse les clients qui ne s'identifient pas.

**Correction.** La requête déclare un agent d'identification et un délai
d'attente. Le détail est dans le fichier de construction, avec l'explication.

### 7.3 Une base déclarée incompatible avec elle-même

**Symptôme.** L'installation échoue sur une valeur de type de base refusée.

**Cause.** Voir §6.3 : le type `mariadb` exige l'extension `mysqli`, absente de
l'image.

### 7.4 Un répertoire refusé au moment du bon moment

**Symptôme.** L'installation réussit, puis le démarrage échoue sur la création du
répertoire de langue.

**Cause.** Le script d'entrée, exécuté par `root`, tentait de créer un répertoire
dans un volume cédé à `www-data`. Sans la capacité `DAC_OVERRIDE`, la tentative
échoue — à juste titre.

**Correction.** La création est confiée à `www-data`, et c'est cohérent : le
volume lui appartient.

### 7.5 Un fichier que personne n'a le droit de protéger

**Symptôme.** Après une installation réussie, le démarrage s'interrompt sur un
refus de changement de droits.

**Cause.** Le fichier de configuration venait d'être créé par le compte du
serveur web. Le compte `root` ne peut pas modifier les droits d'un fichier
appartenant à un autre compte, et le compte du serveur ne le peut pas non plus
après le premier démarrage, puisque le fichier n'est plus à lui.

**Correction.** L'opération est protégée par un test de propriété, et n'a lieu
que lorsqu'elle reste à faire. C'est ce qui la rend idempotente, c'est-à-dire
rejouable sans effet ni erreur.

### 7.6 Un site sain déclaré malade

**Symptôme.** Le conteneur est en service, la page s'affiche dans le navigateur,
et l'état reste « en cours de vérification ».

**Cause.** Moodle redirige toute requête dont l'adresse ne correspond pas à celle
qu'il a été configurée pour servir. La sonde interrogeait l'adresse interne du
conteneur, donc recevait une redirection vers une adresse qui n'existe pas à
l'intérieur.

**Correction.** La sonde envoie l'en-tête d'hôte attendu par Moodle, déduit du
fichier `.env` et non écrit en dur. Elle suit ensuite la redirection et exige une
page rendue.

### 7.7 Deux messages d'avertissement à chaque démarrage

**Symptôme.** Le journal affiche deux fois un avertissement signalant que le
serveur ne connaît pas son propre nom.

**Cause.** Apache cherche à déduire son nom de l'adresse du conteneur, et n'y
parvient pas.

**Correction.** Le nom est déclaré. Ce n'est pas un problème de fonctionnement,
mais deux lignes de bruit à chaque démarrage masquent les messages utiles du
script d'entrée.

---

## 8. Exercices

Les exercices s'enchaînent : chacun produit un résultat que le suivant consomme.
Comptez quarante-cinq minutes au total.

### Exercice 1 — Vérifier la pile et lire son journal (5 min)

```bash
docker compose up --build -d
docker compose ps
docker compose logs moodle
```

Relever le nom du service qui prend le plus de temps à devenir sain, et dire
lequel des deux explique pourquoi. **Livrable attendu** : les deux lignes d'état,
et le nom du service lent, expliqué.

### Exercice 2 — Prouver que l'interface est française (5 min)

Ouvrir la page de connexion, noter le titre de l'onglet, puis retrouver la
langue déclarée par la page. **Livrable attendu** : la preuve qu'il ne s'agit
pas d'une page simplement traduite à la main, mais d'une plateforme servie dans
la langue demandée.

### Exercice 3 — Se connecter et atteindre le tableau de bord (5 min)

Se connecter avec les identifiants du fichier `.env`. Noter le titre de la page
atteinte. **Livrable attendu** : le titre, et l'explication de ce que cette
navigation prouve sur la base de données.

### Exercice 4 — Changer l'adresse du site (10 min)

Passer la publication à un autre port, par exemple 8082, et en répercuter la
valeur dans le fichier `.env`. **Livrable attendu** : un site qui répond sur la
nouvelle adresse, et la liste des deux endroits à modifier. Question à
répondre : que se passe-t-il si l'on change le port publié sans changer
l'adresse déclarée dans le fichier `.env` ?

### Exercice 5 — Constater la persistance (10 min)

Créer un cours depuis l'interface, puis :

```bash
docker compose down
docker compose up -d
```

Le cours est-il toujours là ? Répondre, puis recommencer avec `down -v` et
conclure sur la différence. **Livrable attendu** : la différence entre arrêter et
réinitialiser, et la raison pour laquelle le code de l'application est lui aussi
dans un volume.

### Exercice 6 — Retirer une garantie de sécurité (10 min)

Dans le fichier `compose.yaml`, rendre au service `moodle` la capacité
`DAC_OVERRIDE`, reconstruire, et constater. Puis retirer plutôt la capacité
`CHOWN`. **Livrable attendu** : le démarrage échoue, et le nom de l'étape
responsable est identifié dans le journal.

---

## 9. Dépannage

| Symptôme                                                | Cause probable                                                | Action                                                                 |
| ------------------------------------------------------- | ------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `la base de données ne répond pas après 30 tentatives`  | service `bd` arrêté, ou mot de passe du `.env` non concordant | `docker compose ps`, puis comparer les deux mots de passe du `.env`   |
| `variable MOODLE_... absente du fichier .env`           | `.env` non créé, ou ligne laissée vide                         | recopier `.env.example` et compléter les trois valeurs                  |
| `le paquet de langue « fr » est absent de l'image`      | image construite avant l'ajout du téléchargement               | reconstruire avec `docker compose build --no-cache moodle`             |
| `Les tables de la base de données sont déjà présentes`   | code recréé sans sa configuration, la base étant conservée     | `docker compose down` puis `up -d`; ne pas utiliser `down -v` par réflexe |
| Page en anglais                                         | paquet de langue non installé                                  | consulter le journal du service `moodle`                               |
| Page blanche ou erreur PHP                              | extension PHP manquante, ou volume de code vide                | `docker compose logs moodle`                                            |
| Le site reste en « en cours de vérification »           | la sonde échoue                                               | `docker inspect` sur le conteneur, puis lire la sortie de la sonde       |

---

## 10. Remise à zéro

Quand la plateforme est dans un état inexploitable — identifiants perdus,
configuration fausse, données abîlées — on ne cherche pas à réparer. On
recommence :

```bash
docker compose down -v
docker compose up --build -d
```

L'option `-v` supprime les trois volumes : le code, les données et les tables.
Tout est reconstruit, et la plateforme revient exactement à son état de premier
démarrage. Comptez six à dix minutes, construction comprise.

---

## 11. Ce qui a été vérifié, et comment

Cette section décrit honnêtement le périmètre des vérifications, parce qu'un
support de laboratoire doit dire jusqu'où va sa garantie.

- **Vérifié par exécution** : construction de l'image, premier démarrage avec
  installation complète, redémarrage sans réinstallation, recréation des
  conteneurs avec conservation des volumes, interface rendue en français,
  connexion réussie au compte d'administration, ouverture de la session et
  affichage du tableau de bord, absence de fuite d'avertissement au démarrage.
- **Vérifié par lecture** : la configuration Compose est valide, la syntaxe du
  script d'entrée est correcte, et les fichiers ne contiennent aucun caractère
  étranger.
- **Limite d'environnement** : la machine de préparation n'exposait pas les
  ports publiés vers l'hôte. Les vérifications de pages ont donc été menées
  depuis un autre conteneur du réseau du laboratoire, avec l'en-tête d'hôte
  attendu. La publication reste déclarée dans le fichier Compose, et c'est
  l'adresse `127.0.0.1:8081` qu'il faut ouvrir.

---

## 12. Licence

Moodle est distribué sous licence GPL. Les fichiers de ce laboratoire sont
libres d'usage pédagogique.
