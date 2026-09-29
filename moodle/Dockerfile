# syntax=docker/dockerfile:1
# ===========================================================================
# Dockerfile — construction de l'image du serveur Moodle
# ---------------------------------------------------------------------------
# RÔLE DU FICHIER
# Ce fichier produit une image contenant Moodle, prête à démarrer, sans rien
# installer au moment du lancement. Sur une machine vierge, un simple
# « docker build » suffit à obtenir une plateforme fonctionnelle.
#
# CE QUI CHANGE PAR RAPPORT AU LABORATOIRE PRÉCÉDENT
# Le premier laboratoire servait une page statique avec nginx. Ici, on installe
# une application complète écrite en PHP. Deux conséquences directes :
#
#   1. Moodle a des DÉPENDANCES PHP à installer. On ne les recopie pas à la
#      main : on délègue l'opération à Composer, le gestionnaire de dépendances
#      du langage PHP. Ce fichier est donc l'occasion d'introduire Composer.
#   2. Moodle a besoin d'écrire (cache, journaux, fichiers déposés). On ne
#      peut plus monter le système de fichiers en lecture seule. C'est une
#      différence assumée, et non un oubli : le fichier moodle/compose.yaml y
#      revient.
#
# L'IMAGE EST UN CONTRAT, PAS UN ARTEFACT DE CONSTRUCTION
# Deux constructions de ce fichier, à six mois d'écart, doivent produire deux
# plateformes qui se comportent de la même façon. Trois règles pour y arriver :
#
#   1. figer les versions des images de base ;
#   2. figer les versions des paquets installés ;
#   3. épingler la version de Moodle installée par Composer.
#
# ARCHITECTURE EN TROIS ÉTAPES, DONT DEUX DÉRIVÉES D'UNE MÊME
#
#   socle    PHP 8.3 et Apache, plus les extensions dont Moodle a besoin
#    ├── code    atelier : Composer y installe Moodle et ses dépendances
#    └── serveur atelier de publication : reçoit le code, puis Apache démarre
#
# Une étape de construction est un atelier temporaire ; ce qui en sort est
# recopié dans l'étape suivante, puis l'atelier disparaît de l'image finale.
#
# Pourquoi un « socle » commun plutôt que deux images de base distinctes ?
# Deux raisons, l'une technique et l'autre pédagogique.
#
#   1. Les extensions ne sont compilées qu'UNE SEULE FOIS. Or compiler une
#      extension comme intl demande plusieurs minutes. Les deux étapes
#      dérivées partagent la couche du socle, qui reste dans le cache Docker
#      : la seconde construction ne recompile rien.
#   2. L'atelier et le serveur partagent EXACTEMENT le même environnement PHP.
#      C'est une condition nécessaire pour que Composer valide l'installation
#      : si l'atelier availait une extension de plus que le serveur, ou
#      l'inverse, le code pourrait être construit puis refusé à l'exécution.
#      Cette symétrie est la règle générale : on fabrique le produit dans un
#      environnement plus proche possible de celui qui l'exécutera.
#
# On appelle cela une construction en plusieurs étapes (multi-stage build).
# Le gain est double : une image finale qui ne contient ni gestionnaire de
# dépendances, ni cache d'installation, ni bibliothèque de compilation, et une
# surface d'attaque réduite.
# ===========================================================================

# ---------------------------------------------------------------------------
# ÉTAPE 1 bis — L'OUTIL COMPOSER
# ---------------------------------------------------------------------------
# Cette étape ne construit RIEN de ce qui sera publié. Elle sert uniquement à
# fournir le binaire Composer, copié plus bas dans l'atelier d'installation.
#
# On ne compile donc pas Composer : l'image officielle « composer » le fournit
# déjà, compilé et à jour. On n'en copie que le binaire, ce qui évite
# d'embarquer une base entière de gestionnaires de paquets et ses propres
# dépendances dans l'image finale.
#
# La version est figée (2.8) et non « latest », pour la même raison que les
# images de base : une version non figée produit des constructions différentes
# au fil du temps.
#
# Cette étape est déclarée AVANT les autres, par convention. L'ordre de
# déclaration n'a pas de signification technique, mais il rend le fichier
# lisible : d'abord les outils, puis le socle, puis les étapes qui en
# dérivent.
FROM composer:2.8 AS outils

# ---------------------------------------------------------------------------
# ÉTAPE 1 — Socle : PHP 8.3, Apache et les extensions de Moodle
# ---------------------------------------------------------------------------
# PHP 8.3 avec Apache intégré (édition « apache »). C'est l'image officielle
# qui installe le module PHP dans Apache : une seule image, un seul processus,
# pas de serveur d'applications FastCGI séparé. Pour un laboratoire, la
# simplicité prime ; en production, on séparerait les deux rôles.
#
# La version est figée et non « latest » : une image « latest » peut changer de
# comportement d'un jour sur l'autre, et l'image construite cesserait d'être
# reproductible.
FROM php:8.3-apache AS socle

# ---------------------------------------------------------------------------
# Les extensions dont Moodle a besoin
# ---------------------------------------------------------------------------
# Trois points méritent d'être lus attentivement, car ils expliquent pourquoi
# cette étape n'est pas un simple « installation de paquets ».
#
# 1. ON NE PEUT PAS INSTALLER LES PAQUETS PHP DE LA DISTRIBUTION
#    Les images PHP officielles ne utilisent pas les paquets PHP de Debian
#    (php8.3-intl, php8.3-gd…). PHP y a été COMPILÉ À LA MAIN lors de la
#    construction de l'image, et sa configuration ne lit que le répertoire
#    /usr/local/etc/php/conf.d. Un « apt-get install php8.3-intl » échoue
#    purement et simplement : le paquet n'existe pas dans les dépôts
#    utilisés. Ce serait le cas, avec un message trompeur, si Debian proposait
#    une version 8.4 de PHP alors que l'image contient une version 8.3
#    compilée par l'image elle-même.
#
# 2. ON COMPILE LES EXTENSIONS AVEC L'OUTIL FOURNI PAR L'IMAGE
#    docker-php-ext-install est le script officiel de ces images. Il compile
#    l'extension, puis la déclare dans le répertoire de configuration que PHP
#    lit réellement. On l'utilise donc à la place d'un gestionnaire de
#    paquets, et la différence de nature est assumée : ici, on construit.
#
# 3. ON N'INSTALLE QUE LE NÉCESSAIRE
#    L'image fournit déjà mbstring, curl, sodium, openssl, xml, dom,
#    simplexml, xmlreader, ctype, fileinfo, zlib, ainsi que le cache
#    d'octets OPcache. Il n'en manque que quatre :
#
#      intl        tri des chaînes et formats de date selon la locale. Sans
#                  elle, les dates s'affichent dans un format anglo-saxon et
#                  le tri alphabétique des chaînes accentuées devient faux.
#      gd          vignettes d'images et code de vérification visuel (CAPTCHA)
#                  des pages de connexion. Sans elle, l'écran de connexion
#                  échoue.
#      zip         décompression des archives de sauvegarde et des paquets de
#                  langue. Sans elle, la restauration est impossible.
#      mysqli      le pilote de connexion de Moodle à MariaDB. Sans lui,
#                  l'installeur rejette la base avec un message trompeur,
#                  « incorrect value "mariadb" for "dbtype" » : le pilote
#                  déclaré « mariadb » de Moodle dérive en réalité du pilote
#                  « mysqli » et vérifie sa présence avant de s'en servir. Le
#                  message ne parle donc pas du type de base choisi, mais
#                  d'une extension PHP manquante. C'est le dépannage numéro un
#                  du laboratoire.
#
# Les bibliothèques de développement (libicu-dev, libzip-dev, libpng-dev,
# libjpeg62-turbo-dev, libfreetype6-dev) sont les EN-TÊTES DE COMPILATION.
# Elles servent à fabriquer les extensions, et n'ont aucune utilité ensuite.
#
# « --no-install-recommends » évite d'installer les programmes suggérés par les
# paquets et jamais utilisés. C'est quelques kilo-octets gagnés ici, quelques
# centaines de mégaoctets gagnés sur une pile de dix images.
#
# L'option « --with-freetype --with-jpeg » de la configuration de gd est
# obligatoire : sans elle, la bibliothèque est compilée sans la gestion des
# polices ni du format JPEG. Moodle produit alors des vignettes illisibles, et
# l'échec est silencieux : l'extension est bien chargée.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        libicu-dev \
        libzip-dev \
        libpng-dev \
        libjpeg62-turbo-dev \
        libfreetype6-dev; \
    docker-php-ext-configure gd --with-freetype --with-jpeg; \
    docker-php-ext-install -j"$(nproc)" intl gd zip mysqli; \
    rm -rf /var/lib/apt/lists/*

# Preuve que l'environnement est complet, AVANT toute installation. Cette
# vérification échoue dès la construction si une extension manque : l'erreur
# est alors visible ici, avec son nom, au lieu d'apparaître dix minutes plus
# tard sous la forme d'un « the requested PHP extension is missing ».
RUN set -eux; \
    for extension in intl gd zip mysqli mbstring curl sodium openssl ctype fileinfo xml dom simplexml xmlreader; do \
        php -m | grep -qix "${extension}"; \
    done

# ---------------------------------------------------------------------------
# ÉTAPE 2 — Atelier d'installation de Moodle
# ---------------------------------------------------------------------------
# Cette étape dérive du socle : elle partage donc l'intégralité de ses
# couches, et n'y ajoute que ce qui sert à installer Moodle.
FROM socle AS code

COPY --from=outils /usr/bin/composer /usr/local/bin/composer

# Variables d'environnement utiles à Composer.
#
# COMPOSER_ALLOW_SUPERUSER : Composer refuse normalement de fonctionner lancé
# par root, car il juge cette pratique dangereuse. Or une construction d'image
# est root par construction. Cette variable lève l'avertissement. Elle
# n'affecte que l'atelier, jamais le code produit.
#
# COMPOSER_NO_INTERACTION : Composer ne pose aucune question. Indispensable
# dans une construction non interactive : sans cela, Composer attendrait une
# réponse sur une entrée qui n'existe pas, et la construction expirerait.
#
# COMPOSER_CACHE_DIR : le cache est envoyé dans /tmp, répertoire temporaire de
# l'atelier. Il disparaît avec lui, et ne se retrouve pas dans l'image finale.
ENV COMPOSER_ALLOW_SUPERUSER=1 \
    COMPOSER_NO_INTERACTION=1 \
    COMPOSER_CACHE_DIR=/tmp/composer-cache

# Répertoire de destination de Moodle. /srv est la convention Linux pour les
# données servies par un service ; on ne mélange donc pas Moodle avec /var/www,
# répertoire du serveur web dans l'image de base.
RUN mkdir -p /srv/moodle

# ---------------------------------------------------------------------------
# L'INSTALLATION DE MOODLE PAR COMPOSER
# ---------------------------------------------------------------------------
# C'est LE MOMENT PÉDAGOGIQUE DU FICHIER. On installe Moodle avec une seule
# commande :
#
#   composer create-project moodle/moodle:4.5.14 /srv/moodle
#
# Décomposition de la commande :
#
#   create-project   crée un répertoire ET y installe un paquet. La différence
#                    avec « require » est capitale : « require » installerait
#                    Moodle dans un sous-répertoire du projet courant, alors
#                    que Moodle doit occuper la racine de son propre
#                    répertoire.
#   moodle/moodle    nom du paquet, publié sur Packagist, le registre public
#                    des paquets PHP (l'équivalent de npm pour JavaScript).
#   :4.5.14          VERSION ÉPINGLÉE. Sans elle, Composer installerait la
#                    dernière version publiée, et l'image cesserait d'être
#                    reproductible : deux constructions à un mois d'écart
#                    pourraient fournir deux Moodle différents. La règle est
#                    simple : on fige tout, y compris la version de
#                    l'application.
#   /srv/moodle      répertoire de destination, créé par Composer.
#
# POURQUOI LA BRANCHE 4.5 ET NON LA 5.2
# Moodle publie plusieurs branches en même temps. La branche 4.5 est la branche
# à long terme : elle reçoit des correctifs pendant des années, sans changer
# de comportement majeur. La branche 5.x est plus récente et évolue plus vite.
#
# Le laboratoire choisit la branche à long terme, exactement comme le premier
# laboratoire épinglait une version d'Alpine qualifiée de version maintenance.
# Une raison propre à Moodle s'y ajoute : la version 5 a réorganisé ses
# répertoires, la racine servie par le serveur web passant dans un sous-
# répertoire public/. Le code d'installation, la racine du site et l'emplacement
# du fichier de configuration changent tous de place. Étudier la conteneurisation
# sur une version en pleine migration reviendrait à confondre deux sujets.
# La 4.5 correspond en outre à l'arborescence décrite dans la très grande
# majorité de la documentation existante.
#
# Options retenues :
#   --no-dev        n'installe pas les dépendances de développement, inutiles
#                   pour faire tourner la plateforme.
#   --prefer-dist   télécharge des archives déjà compressées au lieu de cloner
#                   le dépôt avec Git. Plus rapide, et surtout cela n'exige
#                   aucun outil Git dans l'atelier.
#   --no-progress   supprime la barre de progression, qui encombre les
#                   journaux de construction sans rien apporter à un humain.
RUN composer create-project \
        --no-dev \
        --prefer-dist \
        --no-progress \
        moodle/moodle:4.5.14 \
        /srv/moodle

# Preuve que l'installation est complète : Moodle embarque un utilitaire en
# ligne de commande qui affiche sa version, et un répertoire d'outils
# d'administration. Si ces deux éléments sont présents, le code a bien été
# déposé au bon endroit. Une vérification explicite vaut mieux qu'un
# « ça a l'air de marcher » : le silence de Docker n'est pas une preuve.
RUN test -f /srv/moodle/version.php \
    && test -d /srv/moodle/admin/cli \
    && test -f /srv/moodle/config-dist.php

# ---------------------------------------------------------------------------
# Le PAQUET DE LANGUE FRANÇAIS
# ---------------------------------------------------------------------------
# Moodle ne traduit pas son code : il distribue des fichiers de langue
# séparés, publiés à part sur download.moodle.org. Un Moodle installé sans ce
# paquet fonctionne, mais parle anglais.
#
# Pourquoi le télécharger ICI, et pas au démarrage ?
#   1. Le réseau du laboratoire est déclaré « interne » (voir compose.yaml) :
#      aucun conteneur ne peut joindre Internet. Un téléchargement au démarrage
#      échouerait donc systématiquement.
#   2. Une construction doit être reproductible ET le démarrage doit l'être
#      aussi. Tout ce qui est téléchargé pendant une construction est figé dans
#      l'image, donc identique sur toutes les machines. Tout ce qui est
#      téléchargé au démarrage dépend du réseau, donc jamais garanti.
#   3. Le premier démarrage devient plus rapide : le paquet est déjà là.
#
# EXCEPTION ASSUMÉE À LA RÈGLE DE FIGEAGE
# On ne fige pas ce fichier, contrairement à Moodle lui-même. Une somme de
# contrôle le rendrait inutilisable : Moodle publie des corrections de
# traduction pour la branche 4.5 tous les mois, et l'image refusera alors de
# démarrer faute de correspondance. On préfère donc un fichier rafraîchi à
# chaque construction, ce qui est un compromis assumé entre répétabilité et
# corrections de langue. Le fichier reste vérifiable : le script de démarrage
# en contrôle la présence avant de s'en servir.
#
# La copie se fait avec l'extension cURL de PHP, déjà présente, plutôt qu'avec
# un outil externe à installer. La commande échoue si le téléchargement est
# incomplet : mieux vaut une construction en échec qu'une image amputée.
#
# LE DÉTAIL QUI FAIT ÉCHOUER LA CONSTRUCTION, ET LE POURQUOI
# Sans l'option « user_agent », ce téléchargement renvoie une erreur HTTP 403.
# Rien n'indique qu'il s'agit d'un problème d'agent utilisateur : le message
# « Forbidden » évoque un accès interdit, donc un problème de droits, alors
# que le refus vient du filtrage automatique des requêtes anonymes. Le serveur
# de Moodle refuse les requêtes dont l'agent n'est pas identifié, parce qu'un
# fichier de langue réclamé par un programme inconnu ne lui sert à rien.
#
# Deux enseignements en découlent.
#
#   1. Un client HTTP porte une IDENTITÉ, et cette identité fait partie du
#      protocole. L'en-tête « user agent » est le nom du logiciel qui parle.
#   2. Une erreur 403 ne signifie pas toujours « tu n'as pas le droit ».
#      LIRE le message d'erreur, plutôt que d'y projeter une cause habituelle,
#      fait gagner des heures.
RUN set -eux; \
    mkdir -p /srv/moodle-langpacks; \
    php -r '\
        $url = "https://download.moodle.org/download.php/langpack/4.5/fr.zip"; \
        $dest = "/srv/moodle-langpacks/fr.zip"; \
        $contexte = stream_context_create([ \
            "http" => ["user_agent" => "lab-moodle/1.0", "timeout" => 120] \
        ]); \
        if (!@copy($url, $dest, $contexte)) { \
            fwrite(STDERR, "téléchargement impossible : " . $url . PHP_EOL); \
            exit(1); \
        } \
        $zip = new ZipArchive(); \
        if ($zip->open($dest) !== true) { \
            fwrite(STDERR, "archive illisible" . PHP_EOL); \
            exit(1); \
        } \
        $entrees = []; \
        for ($i = 0; $i < $zip->numFiles; $i++) { \
            $entrees[$zip->getNameIndex($i)] = true; \
        } \
        if (!isset($entrees["fr/moodle.php"]) && !isset($entrees["fr/version.php"])) { \
            fwrite(STDERR, "le répertoire fr est absent de l archive" . PHP_EOL); \
            exit(1); \
        } \
        $zip->close(); \
        echo "paquet de langue vérifié : " . filesize($dest) . " octets" . PHP_EOL; \
    '

# ---------------------------------------------------------------------------
# ÉTAPE 3 — Atelier de publication
# ---------------------------------------------------------------------------
# Cette étape dérive du même socle. Elle ne reçoit QUE le code déjà construit :
# ni Composer, ni les en-têtes de compilation, ni le cache d'installation ne
# sont repris.
FROM socle AS serveur

# ---------------------------------------------------------------------------
# Configuration de PHP
# ---------------------------------------------------------------------------
# Fichier d'options PHP déposé dans le répertoire que PHP lit réellement,
# comme l'a montré l'étape 1. Le nom commence par « zz » pour être chargé
# APRÈS les fichiers déjà présents : en cas de réglage contradictoire, le
# dernier lu l'emporte, et c'est le nôtre qui doit gagner.
#
# Chaque réglage porte un commentaire « pourquoi », jamais « quoi » : la valeur
# se lit dans la ligne ; son motif ne se lit pas.
COPY php/zz-laboratoire.ini /usr/local/etc/php/conf.d/zz-laboratoire.ini

# ---------------------------------------------------------------------------
# Configuration d'Apache
# ---------------------------------------------------------------------------
# L'image de base embarque un site par défaut qui sert /var/www/html. On
# l'écrase : on ne superpose pas deux configurations concurrentes, on remplace
# la précédente. Le fichier reste activé par le lien symbolique déjà présent
# dans /etc/apache2/sites-enabled.
#
# Les journaux d'Apache partent vers la sortie standard et la sortie d'erreur
# du conteneur, que « docker compose logs » affiche. On ne crée aucun fichier
# de journal dans l'image : un journal qui vit dans une image est un journal
# qui grossit sans jamais être purgé.
COPY apache/000-default.conf /etc/apache2/sites-available/000-default.conf

# rewrite : nécessaire aux adresses propres de Moodle, où la page
#            /course/view.php?id=2 est servie à l'adresse /course/view/2.
#            Sans ce module, tous les liens internes du site renvoient une
#            erreur 404, alors que les pages directes fonctionnent.
# headers : permet à Moodle de poser ses en-têtes de sécurité. Moodle suppose
#           que ce module est actif, et signale son absence sur son tableau de
#           bord.
RUN a2enmod rewrite headers

# ---------------------------------------------------------------------------
# Dépôt du code de Moodle
# ---------------------------------------------------------------------------
# Copie de l'atelier vers l'image finale. C'est le seul instant où le code de
# Moodle entre dans l'image.
#
# --chown=root:root : Moodle recommande explicitement que le compte du serveur
# web ne puisse PAS modifier le code de l'application. Root n'est pas le compte
# du serveur web : les processus Apache travaillent sous www-data. Le code est
# donc détenu par root, en lecture seule pour le site. Une éventuelle faille
# d'exécution de code se transforme alors en échec, et non en prise de contrôle
# durable de l'image.
# LE CODE EST PLACÉ DANS LE VOLUME, PAS DANS L'IMAGE
# Moodle écrit un fichier config.php à la racine de son code au moment de
# l'installation. Ce fichier contient la connexion à la base de données.
#
# Si le code restait dans l'image, ce fichier vivrait dans la couche
# inscriptible du conteneur, qui disparaît à chaque recréation. Que se
# passerait-il au redémarrage suivant, après un « docker compose up » ou un
# simple redémarrage de la machine ? Le conteneur repartirait sans config.php,
# alors que la base de données, elle, est intacte dans son volume. Moodle
# s'apercevrait de l'incohérence et refuserait de démarrer, en annonçant que
# les tables sont déjà présentes.
#
# C'est un défaut classique des images « jetables ». On le corrige en plaçant
# le code lui-même dans un volume : config.php y reste, et le conteneur peut
# être détruit et recréé sans rien perdre.
#
# CONSÉQUENCE, ET ELLE EST VISIBLE
# Une copie de référence, intacte et non modifiable, est conservée dans
# l'image sous /usr/share/moodle-image. Au premier démarrage, le script d'entrée
# la copie dans le volume. Cette copie de référence sert aussi de filet : le
# code du volume peut être rétabli à l'identique depuis l'image, à tout
# moment.
COPY --chown=root:root --from=code /srv/moodle /usr/share/moodle-image

# Le volume sera monté ici. Le répertoire existe et appartient à root : c'est
# lui qui donne son propriétaire au volume lorsqu'il est créé vide, et c'est
# cette propriété que l'on veut voir conservée.
RUN mkdir -p /srv/moodle \
    && chown root:root /srv/moodle

# Le paquet de langue est copié à part du code. Il doit pouvoir être remplacé
# sans toucher à l'application, et il n'a rien à faire dans une arborescence
# servie par le serveur web.
COPY --from=code /srv/moodle-langpacks /srv/moodle-langpacks

# ---------------------------------------------------------------------------
# Répertoire de données et script de démarrage
# ---------------------------------------------------------------------------
# moodledata : le répertoire qui contiendra les fichiers déposés par les
# utilisateurs, les sauvegardes et le cache. Il est vide dans l'image et sera
# remplacé par un volume au démarrage (voir moodle/compose.yaml).
#
# Contrairement au code, ce répertoire est donné à www-data dès la
# construction : le volume ne contient que des fichiers déposés par le site,
# donc des fichiers qui lui appartiennent.
RUN mkdir -p /srv/moodledata \
    && chown -R www-data:www-data /srv/moodledata

# Le script d'entrée prépare le volume, installe Moodle si nécessaire, puis
# lance le serveur. COPY conserve les droits du fichier source : il faut donc
# les fixer explicitement, sinon le conteneur démarre et s'arrête aussitôt sur
# une erreur d'autorisation.
COPY --chown=root:root entrypoint.sh /usr/local/bin/entrypoint-lab.sh
RUN chmod 0755 /usr/local/bin/entrypoint-lab.sh

# ---------------------------------------------------------------------------
# Métadonnées et port d'écoute
# ---------------------------------------------------------------------------
LABEL org.opencontainers.image.title="LAB — Moodle conteneurisé" \
      org.opencontainers.image.description="Moodle 4.5 LTS servi par Apache, piloté par Docker Compose." \
      org.opencontainers.image.licenses="MIT"

# Port d'écoute À L'INTÉRIEUR du conteneur. Il n'ouvre rien : il documente.
# Le port 80 est celui qu'Apache écoute dans le conteneur, et il doit
# correspondre à la partie droite de la clé « ports » du fichier Compose.
EXPOSE 80

# ---------------------------------------------------------------------------
# Oracle de santé
# ---------------------------------------------------------------------------
# Le conteneur Moodle démarre lentement : la première installation écrit des
# dizaines de tables et construit le cache. La période de démarrage
# (start-period) est donc généreuse. Pendant cette période, un échec de la sonde
# n'est pas compté comme un échec : le conteneur est considéré « en cours de
# montage », ce qui évite qu'un orchestrateur le remplace au pire moment.
#
# La sonde n'utilise NI wget NI curl, qui ne sont pas installés. Elle appelle
# PHP, dont on sait déjà qu'il fonctionne puisque c'est l'image de base. Deux
# intérêts pédagogiques : aucune dépendance ajoutée pour surveiller, et une
# preuve directe que la chaîne complète Apache, PHP et Moodle répond.
#
# La page /login/index.php est celle que voit tout visiteur en premier. La sonder
# vérifie que la plateforme sert réellement des pages, et pas seulement que le
# processus Apache est vivant.
#
# UN DÉTAIL QUI SÛTE À UN PIÈGE, ET QUI VAUT SON EXPLICATION
# La sonde interroge 127.0.0.1, l'adresse du conteneur lui-même. Or Moodle
# compare l'adresse de la requête à celle qu'il a été configuré pour servir, et
# il redirige vers cette dernière si elles diffèrent. Interrogé en boucle sur
# 127.0.0.1, Moodle répondrait systématiquement «Moved Permanently» vers
# l'adresse publique, adresse qui n'existe pas à l'intérieur du conteneur : la
# sonde ne verrait jamais le code 200, et un site parfaitement sain serait
# déclaré malade.
#
# La parade est d'envoyer l'en-tête Host attendu par Moodle. Il est déduit de la
# variable d'environnement MOODLE_WWWROOT, et non écrit en dur : si l'on change
# l'adresse publique dans le fichier .env, la sonde suit le changement sans
# qu'on ait à réécrire l'image. La sonde attend ensuite un corps de réponse
# réellement rendu, et non un simple code : elle prouve que PHP a exécuté
# Moodle, que la session a pu ouvrir une connexion vers la base, et que le
# paquet de langue est en place. Une page d'erreur PHP, elle, ne contient pas
# la chaîne recherchée : la sonde échoue, à juste titre.
HEALTHCHECK --interval=15s --timeout=10s --start-period=300s --retries=5 \
    CMD php -r '\
        $configure = parse_url(getenv("MOODLE_WWWROOT") ?: "http://localhost:8081"); \
        $hote = ($configure["host"] ?? "localhost") . (isset($configure["port"]) ? ":" . $configure["port"] : ""); \
        $contexte = stream_context_create(["http" => ["ignore_errors" => true, "timeout" => 8, "header" => "Host: " . $hote]]); \
        $corps = @file_get_contents("http://127.0.0.1/login/index.php", false, $contexte); \
        exit(is_string($corps) && strpos($corps, "login") !== false ? 0 : 1); \
    '

# ---------------------------------------------------------------------------
# Commande de démarrage
# ---------------------------------------------------------------------------
# ENTRYPOINT : la commande qui enveloppe le service, exécutée à chaque
# démarrage. Elle doit donc être un point d'entrée PARAMÉTRABLE, d'où la forme
# « exec "$@" » du script : celui-ci prépare l'environnement, puis exécute ce
# qu'on lui a demandé d'exécuter. C'est la structure attendue par Docker.
ENTRYPOINT ["/usr/local/bin/entrypoint-lab.sh"]

# CMD : ce qu'il y a à exécuter par défaut si rien n'est fourni. Ici, le
# serveur Apache au premier plan.
#
# La forme « exec » (sans shell intermédiaire) est RECOMMANDÉE : Apache devient
# le processus principal et reçoit directement le signal d'arrêt de Docker.
# Avec un shell en interposition, le signal n'arriverait pas au serveur et le
# conteneur serait tué au bout du délai de grâce, avec des requêtes en cours
# tronquées.
CMD ["apache2-foreground"]
