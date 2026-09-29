#!/bin/sh
# ===========================================================================
# entrypoint.sh — préparation et démarrage du conteneur Moodle
# ---------------------------------------------------------------------------
# RÔLE DU FICHIER
# ENTRYPOINT est la première chose exécutée au démarrage d'un conteneur. Ce
# script est donc le point de contrôle de tout ce qui doit être fait AVANT que
# le serveur ne réponde : préparer le répertoire de données, attendre la base,
# installer Moodle s'il ne l'est pas encore, puis transmettre la main au
# serveur.
#
# LE PRINCIPE : IDEMPOTENCE
# Un conteneur redémarre. Docker peut redémarrer un conteneur après un arrêt du
# système, après un plantage de la machine, ou simplement parce que
# l'ordinateur du laboratoire a redémarré. Le script doit donc pouvoir
# s'exécuter dix fois de suite sans jamais casser la plateforme ni la
# réinstaller.
#
# Concrètement, cela signifie : vérifier l'état avant d'agir. Si le fichier de
# configuration existe déjà, on ne touche à rien. On ne crée pas ce qui existe
# et on ne supprime pas ce qui est utile.
#
# UNE SEULE RÈGLE DE SÉCURITÉ À RETENIR
# Ce script démarre en root, parce qu'il a deux besoins temporaires : donner
# son propriétaire au volume de données, et écrire le fichier de configuration
# de Moodle. Il rend ensuite la main et ne s'exécute plus jamais. Le serveur
# Apache, lui, ne travaille jamais en root : ses processus fils tournent sous
# le compte www-data.
# ===========================================================================

# « set -eu » transforme les erreurs en arrêts.
#   -e : dès qu'une commande échoue, le script s'interrompt. Sans lui, une
#        étape ratée serait suivie des suivantes, et l'échec n'apparaîtrait
#        qu'à la fin, masqué par d'autres messages.
#   -u : une variable non définie est une erreur, pas une chaîne vide. Un mot
#        de passe oublié deviendrait sinon une chaîne vide acceptée par MySQL.
# Le « pipefail » n'existe pas dans /bin/sh : c'est une fonctionnalité propre à bash, d'où le
# choix de « sh » et non « bash » dans l'interpréteur déclaré plus bas.
set -eu

# ---------------------------------------------------------------------------
# Journalisation
# ---------------------------------------------------------------------------
# Toute information écrite par ce script part sur la sortie standard, donc
# dans « docker compose logs ». On n'écrit JAMAIS dans un fichier : un journal
# contenu dans un conteneur disparaît avec lui.
#
# On n'affiche jamais une valeur de mot de passe. Les messages disent QUELLE
# variable est concernée, jamais ce qu'elle contient.
log() {
    printf '[preparation] %s\n' "$1"
}

erreur() {
    printf '[preparation] ERREUR : %s\n' "$1" >&2
}

# ---------------------------------------------------------------------------
# Étape 1 — Valeurs de configuration, vérifiées une par une
# ---------------------------------------------------------------------------
# Docker ne transmet au conteneur que ce que la clé « environment » déclare.
# Une variable absente se retrouve donc vide, silencieusement. Or une variable
# vide dans une chaîne de connexion produit une erreur de connexion incompréhensible
# dix minutes plus tard. On contrôle donc chaque valeur ici, à la source.
#
# La syntaxe « ${VARIABLE:?message} » est une vérification intégrée au shell :
# si la variable est absente OU vide, le shell affiche le message et interrompt
# le script. C'est plus sûr qu'un test classique, car aucune étape ne peut être
# oubliée.
#
# Aucune de ces valeurs n'est écrite en clair dans le dépôt : elles viennent du
# fichier .env, que le fichier .gitignore exclut du suivi de version.
: "${MOODLE_DB_NAME:?la variable MOODLE_DB_NAME est absente ou vide}"
: "${MOODLE_DB_USER:?la variable MOODLE_DB_USER est absente ou vide}"
: "${MOODLE_DB_PASSWORD:?la variable MOODLE_DB_PASSWORD est absente ou vide}"
: "${MOODLE_DATAROOT:=/srv/moodledata}"
: "${MOODLE_DBNAME_HOST:=bd}"
: "${MOODLE_DBNAME_PORT:=3306}"
: "${MOODLE_WWWROOT:?la variable MOODLE_WWWROOT est absente ou vide}"
: "${MOODLE_LANG:=fr}"
: "${MOODLE_FULLNAME:=Plateforme du laboratoire}"
: "${MOODLE_SHORTNAME:=labo}"
: "${MOODLE_ADMIN_USER:?la variable MOODLE_ADMIN_USER est absente ou vide}"
: "${MOODLE_ADMIN_PASSWORD:?la variable MOODLE_ADMIN_PASSWORD est absente ou vide}"
: "${MOODLE_ADMIN_EMAIL:?la variable MOODLE_ADMIN_EMAIL est absente ou vide}"
: "${MOODLE_SUMMARY:?la variable MOODLE_SUMMARY est absente ou vide}"

log "plateforme : ${MOODLE_FULLNAME} (${MOODLE_SHORTNAME}), langue ${MOODLE_LANG}"
log "adresse publique : ${MOODLE_WWWROOT}"

# ---------------------------------------------------------------------------
# Étape 2 — Code de Moodle, déposé dans le volume
# ---------------------------------------------------------------------------
# Le code de l'application n'est pas dans l'image : il est dans un volume, ce
# qui est expliqué en détail dans le Dockerfile. L'image conserve une copie de
# référence intacte sous /usr/share/moodle-image, et c'est cette copie qui est
# déposée ici au premier démarrage.
#
# Le test porte sur version.php, le fichier que Moodle crée à la racine de son
# code et dont la présence signifie « le code est là ». Un volume peut être
# vide, un volume neuf, un volume déjà peuplé, ou un volume abîmé : dans
# les trois derniers cas, on ne touche à rien.
#
# La copie est faite par root, et non par www-data, pour une raison précise :
# ainsi les fichiers restent la propriété de root, donc non modifiables par
# le serveur web. Cette propriété est rétablie par le passage sous
# www-data, puis rendue à root, uniquement pendant l'installation (étape 6).
#
# L'opération est idempotente : la relancer un million de fois donne le même
# résultat. C'est indispensable ici, car un redémarrage de la machine relance
# ce script sans que personne ne l'ait demandé.
if [ -f /srv/moodle/version.php ]; then
    log "code de Moodle déjà présent dans le volume"
else
    log "dépose du code de Moodle dans le volume (première rencontre)"
    cp -a /usr/share/moodle-image/. /srv/moodle/
    log "code déposé : $(find /srv/moodle -maxdepth 1 -type d | wc -l) entrées à la racine"
fi

# Étape 3 — Répertoire de données
# ---------------------------------------------------------------------------
# MOODLE_DATAROOT est le répertoire qui reçoit les fichiers déposés, les
# sauvegardes et le cache. Il est fourni par un volume (voir compose.yaml).
#
# Le volume est créé par Docker avec les droits de root. Or Apache travaille
# sous www-data et ne pourrait donc rien y écrire : Moodle refuserait de créer
# le premier fichier déposé. On rend donc le volume à www-data avant tout
# démarrage du serveur.
#
# chown -R plutôt que chown : un volume peut être réutilisé d'un volume déjà
# peuplé, et le contenu doit être corrigé aussi, pas seulement la racine.
mkdir -p "${MOODLE_DATAROOT}"
chown -R www-data:www-data "${MOODLE_DATAROOT}"
log "répertoire de données prêt : ${MOODLE_DATAROOT}"

# ---------------------------------------------------------------------------
# Étape 4 — Attente de la base de données
# ---------------------------------------------------------------------------
# Le fichier Compose déclare déjà une dépendance à la santé du conteneur « bd ».
# Cette étape n'est donc pas redondante : elle traite le cas où la base est
# redémarrée APRÈS le démarrage de Moodle, ce que Compose ne peut pas prévoir.
#
# On n'utilise PAS mysqladmin, qui n'est pas installé dans cette image : on
# appelle PHP, dont le pilote mysqli est déjà présent. Aucune dépendance
# supplémentaire n'est ajoutée pour une simple vérification.
#
# Trente tentatives espacées de deux secondes, soit au plus une minute : si la
# base ne répond pas dans ce délai, il ne s'agit pas d'un simple retard de
# démarrage. Continuer à boucler masquerait un vrai problème derrière une
# impression d'attente. Le script échoue alors bruyamment, et le journal
# indique où regarder.
tentative=1
max_tentatives=30
log "attente de la base de données ${MOODLE_DBNAME_HOST}:${MOODLE_DBNAME_PORT}"
while [ "${tentative}" -le "${max_tentatives}" ]; do
    if php -r '
        $h = getenv("MOODLE_DBNAME_HOST");
        $p = (int) getenv("MOODLE_DBNAME_PORT");
        mysqli_report(MYSQLI_REPORT_OFF);
        $connexion = @mysqli_connect(
            $h,
            getenv("MOODLE_DB_USER"),
            getenv("MOODLE_DB_PASSWORD"),
            "",
            $p
        );
        if ($connexion instanceof mysqli) {
            mysqli_close($connexion);
            exit(0);
        }
        exit(1);
    ' 2>/dev/null; then
        log "base de données disponible"
        break
    fi

    if [ "${tentative}" -eq "${max_tentatives}" ]; then
        erreur "la base de données ne répond pas après ${max_tentatives} tentatives"
        erreur "vérifier que le service bd est démarré et que les identifiants du fichier .env correspondent"
        exit 1
    fi

    tentative=$((tentative + 1))
    sleep 2
done

# ---------------------------------------------------------------------------
# Étape 5 — Paquet de langue français
# ---------------------------------------------------------------------------
# Moodle ne traduit pas son code : il distribue des fichiers de langue
# séparés, dans une archive publiée par Moodle et déposée dans le répertoire de
# données, à l'emplacement dataroot/lang.
#
# L'archive est déjà dans l'image (voir le Dockerfile), mais elle n'est pas
# encore au bon endroit. On la décompresse donc ici, une fois pour toutes.
#
# Trois précautions.
#
#   1. On ne le fait QUE si le répertoire de la langue est absent. Un
#      redémarrage ne doit pas réécrire des centaines de fichiers, et le
#      script doit pouvoir être rejoué sans effet de bord.
#   2. On ne le fait QUE si la langue demandée n'est pas déjà l'anglais.
#      L'anglais est fourni avec le code de Moodle : il n'y a rien à installer.
#   3. La décompression se fait sous www-data, comme l'installation. Les
#      fichiers produits appartiennent ainsi au compte du serveur web, qui
#      pourra les lire, et le répertoire de données garde un propriétaire
#      unique.
MOODLE_LANGPAQUETS=/srv/moodle-langpacks
if [ "${MOODLE_LANG}" = "en" ]; then
    log "langue anglaise : aucun paquet de langue à installer"
elif [ -d "${MOODLE_DATAROOT}/lang/${MOODLE_LANG}" ]; then
    log "paquet de langue « ${MOODLE_LANG} » déjà installé"
elif [ ! -f "${MOODLE_LANGPAQUETS}/${MOODLE_LANG}.zip" ]; then
    erreur "le paquet de langue « ${MOODLE_LANG} » est absent de l'image"
    erreur "l'image a été construite sans lui ; reconstruire avec « --build »"
    exit 1
else
    log "installation du paquet de langue « ${MOODLE_LANG} »"
    su -s /bin/sh www-data -c "php -r '
        \$destination = \"${MOODLE_DATAROOT}/lang\";
        if (!is_dir(\$destination) && !mkdir(\$destination, 0775, true) && !is_dir(\$destination)) {
            fwrite(STDERR, \"répertoire de langue non créé\" . PHP_EOL);
            exit(1);
        }
        \$archive = new ZipArchive();
        if (\$archive->open(\"${MOODLE_LANGPAQUETS}/${MOODLE_LANG}.zip\") !== true) {
            fwrite(STDERR, \"archive illisible\" . PHP_EOL);
            exit(1);
        }
        if (!\$archive->extractTo(\$destination)) {
            fwrite(STDERR, \"décompression impossible\" . PHP_EOL);
            exit(1);
        }
        \$archive->close();
    '"
    if [ ! -d "${MOODLE_DATAROOT}/lang/${MOODLE_LANG}" ]; then
        erreur "le paquet de langue n'a pas produit le répertoire attendu"
        exit 1
    fi
    log "paquet de langue « ${MOODLE_LANG} » installé"
fi

# ---------------------------------------------------------------------------
# Étape 6 — Installation de Moodle, si elle n'a pas encore eu lieu
# ---------------------------------------------------------------------------
# Moodle ne se lance pas tout seul comme une page statique : il faut le
# connecter à la base de données et créer son schéma. Cette étape s'appelle
# l'INSTALLATION, et elle n'a lieu qu'une fois.
#
# Comment savoir si elle a déjà eu lieu ? Moodle dépose un fichier unique,
# config.php, à la racine de son code. Sa présence prouve que la plateforme a
# été configurée ET que la base contient les tables correspondantes. C'est un
# test d'état, pas une supposition.
#
# Pourquoi l'installation est ici et pas dans le Dockerfile ? Parce qu'elle a
# besoin de la base de données, qui n'existe pas au moment de la construction
# de l'image. On distingue ainsi deux moments :
#
#   la CONSTRUCTION (docker build) : ce qui ne dépend de personne. Code, PHP,
#                                    extensions. C'est le seul moment où l'on
#                                    touche au code, donc le seul où l'on peut
#                                    garantir que l'image est identique partout.
#   le DÉMARRAGE (docker up)       : ce qui dépend du contexte. Connexion à la
#                                    base, création du compte d'administration.
#                                    On ne fige jamais dans une image une donnée
#                                    qui dépend de l'environnement.
if [ -f /srv/moodle/config.php ]; then
    log "Moodle est déjà installé : installation ignorée"
else
    log "première installation de Moodle : elle prend une à trois minutes"

    # Moodle écrit config.php à la racine de son code. Ce code appartient à
    # root, en lecture seule pour le serveur web : c'est une précaution
    # volontaire, rappelée dans le Dockerfile.
    #
    # On rend donc temporairement le code accessible au compte www-data, le temps
    # de l'écriture. Trois raisons à cet ordre précis :
    #
    #   1. l'installation se fait sous www-data, et non sous root, pour que le
    #      fichier produit soit directement lisible par le serveur sans avoir à
    #      le modifier après coup ;
    #   2. les droits sont rendus à root juste après, si bien qu'à la fin du
    #      démarrage la protection est rétablie ;
    #   3. l'opération est réversible parce qu'elle ne concerne qu'un seul
    #      fichier. Pour une installation en production, on préfère un volume
    #      dédié pour config.php ; cette variante est évoquée dans le README.
    chown www-data:www-data /srv/moodle

    # La commande d'installation non interactive. Sans elle, l'installeur
    # attend une saisie au clavier : dans un conteneur, il n'y a pas de clavier,
    # et le démarrage resterait bloqué pour toujours.
    #
    # Chaque option a une raison d'être :
    #   --wwwroot     : l'adresse publique du site. Elle est inscrite dans la
    #                   base de données et sert à construire tous les liens.
    #                   Une valeur erronée produit des liens qui pointent
    #                   ailleurs : c'est l'erreur la plus coûteuse en temps de
    #                   débogage de tout le laboratoire.
    #   --dataroot    : le répertoire de données, hors du code.
    #   --dbtype      : mariadb. Moodle parle le protocole MySQL à MariaDB, et
    #                   ce nom active des réglages spécifiques à ce serveur.
    #                   Attention : ce pilote dérive du pilote « mysqli » de
    #                   PHP. Sans l'extension mysqli dans l'image, l'erreur
    #                   affichée parle d'une « valeur incorrecte de dbtype »,
    #                   ce qui oriente vers le mauvais problème : il s'agit
    #                   d'une extension manquante, pas d'un mauvais type.
    #   --dbhost      : le NOM du service, « bd ». C'est le nommage de réseau
    #                   de Docker : il ne s'agit pas d'une adresse IP, et c'est
    #                   tout l'intérêt d'un réseau partagé entre conteneurs.
    #   --agree-license et --non-interactive : sur Moodle 4.0 et ultérieur, le
    #                   refus de la licence de marque fait échouer
    #                   l'installation. Le laboratoire utilise la version open
    #                   source, dont la licence est celle du dépôt.
    su -s /bin/sh www-data -c "php /srv/moodle/admin/cli/install.php \
        --lang=${MOODLE_LANG} \
        --wwwroot=${MOODLE_WWWROOT} \
        --dataroot=${MOODLE_DATAROOT} \
        --dbtype=mariadb \
        --dbhost=${MOODLE_DBNAME_HOST} \
        --dbport=${MOODLE_DBNAME_PORT} \
        --dbname=${MOODLE_DB_NAME} \
        --dbuser=${MOODLE_DB_USER} \
        --dbpass=${MOODLE_DB_PASSWORD} \
        --fullname='${MOODLE_FULLNAME}' \
        --shortname='${MOODLE_SHORTNAME}' \
        --summary='${MOODLE_SUMMARY}' \
        --adminuser='${MOODLE_ADMIN_USER}' \
        --adminpass='${MOODLE_ADMIN_PASSWORD}' \
        --adminemail='${MOODLE_ADMIN_EMAIL}' \
        --agree-license \
        --non-interactive"

    # Protection rétablie immédiatement : le code n'appartient de nouveau qu'à
    # root, et le serveur web ne peut plus le modifier.
    chown root:root /srv/moodle
    log "installation terminée"
fi

# Le fichier de configuration contient les identifiants de la base de données.
# Personne ne doit donc pouvoir le modifier, et le serveur doit pouvoir le lire.
# Deux opérations, dans cet ordre précis, et par deux comptes différents.
#
#   1. chmod 0640, EXÉCUTÉ PAR www-data. Seul le propriétaire d'un fichier peut
#      modifier ses droits. Le fichier vient d'être créé par l'installation,
#      qui tourne sous www-data : c'est donc ce compte, et non root, qui
#      applique le réglage. Cette précision n'est pas cosmétique : le
#      laboratoire a retiré au conteneur la capacité qui permettrait à root de
#      modifier les droits du fichier d'autrui.
#   2. chown root:www-data, EXÉCUTÉ PAR root. Le fichier change de propriétaire
#      et devient lisible par le groupe du serveur web. Le compte root est
#      autorisé à cette opération par la capacité CHOWN, explicitement
#      restituée dans le fichier Compose.
#
# Le résultat : un fichier que le serveur peut lire, que personne ne peut
# modifier, et qu'aucun autre compte du conteneur ne peut lire. C'est la
# protection minimale contre la fuite des identifiants de la base.
#
# ET POURQUOI CE BLOC TESTE LE PROPRIÉTAIRE AVANT D'AGIR
# Cette protection est déjà en place au redémarrage suivant : le fichier
# appartient alors à root, et www-data se contente d'en faire partie. Or un
# membre du groupe ne peut pas modifier les droits d'un fichier : le chmod
# échouerait, et le script s'arrêterait sur une erreur qui n'a aucun rapport
# avec un vrai problème. Le test évite ce piège et rend l'opération
# idempotente : elle ne refait le travail que s'il reste à faire.
if [ -f /srv/moodle/config.php ]; then
    if [ "$(stat -c '%U' /srv/moodle/config.php)" = "www-data" ]; then
        su -s /bin/sh www-data -c "chmod 0640 /srv/moodle/config.php"
        chown root:www-data /srv/moodle/config.php
        log "config.php protégé : lisible par le serveur, modifiable par personne"
    else
        log "config.php déjà protégé : lisible par le serveur, modifiable par personne"
    fi
fi

# ---------------------------------------------------------------------------
# Étape 7 — Transfert au serveur
# ---------------------------------------------------------------------------
# exec remplace le processus courant par le serveur, sans revenir en arrière.
# Le serveur devient alors le processus PRINCIPAL du conteneur : c'est à lui
# que Docker envoie le signal d'arrêt.
#
# Sans exec, le serveur serait un enfant du script. Le signal arriverait au
# script, qui ne le transmettrait pas, et le conteneur devrait être tué au bout
# du délai de grâce : arrêt brutal, requêtes de base de données laissées en
# cours, connexion SSH de l'étudiant coupée net.
#
# Les arguments reçus (« "$@" ») sont transmis : le point d'entrée reste
# ainsi paramétrable, et le CMD de l'image (apache2-foreground) est respecté.
log "démarrage du serveur"
exec "$@"
