# syntax=docker/dockerfile:1
# ===========================================================================
# Dockerfile — construction de l'image du serveur web
# ---------------------------------------------------------------------------
# RÔLE DU FICHIER
# Ce fichier décrit, de façon déclarative et reproductible, l'ensemble de ce
# dont l'application a besoin pour fonctionner. Sur une machine vierge, un
# simple « docker build » suffit à obtenir un serveur opérationnel : aucune
# installation manuelle, aucun paquet oublié.
#
# L'IMAGE EST UN CONTRAT, PAS UN ARTEFACT DE CONSTRUCTION
# Ce qui compte n'est pas la taille de l'image finale, mais le fait qu'elle
# soit DÉTERMINISTE : deux constructions de ce fichier, à six mois d'écart,
# doivent produire deux serveurs qui se comportent de la même façon. On y
# arrive en appliquant trois règles :
#
#   1. figer les versions des images de base ;
#   2. figer les versions des paquets installés ;
#   3. ne jamais récupérer de code au moment du build autrement que par COPY
#      d'un fichier présent dans le contexte de construction.
#
# LIGNE EN TÊTE
# « # syntax=… » est une directive d'interpréteur, lue par BuildKit. Elle
# indique le frontend de construction à utiliser. Elle n'est pas un commentaire
# ordinaire : la retirer force le moteur legacy, qui ignore les fonctionnalités
# modernes (cache mounts, HEREDOC, secrets). On la conserve.
# ===========================================================================

# ---------------------------------------------------------------------------
# ÉTAPE 1 — Image de base
# ---------------------------------------------------------------------------
# On part de l'image officielle nginx, version alpine.
#
#   - « version-alpine » épingle une version majeure. C'est le compromis
#     habituel entre sécurité (correctifs reçus) et stabilité (pas de
#     changement majeur non maîtrisé). On ne va pas jusqu'à un SHA précis :
#     ce niveau de rigidité est réservé aux images de production critiques.
#   - « alpine » : distribution minimaliste, donc image nettement plus légère
#     que celle fondée sur Debian.
#
# La ligne « AS base » nomme l'étape. Un nom n'est utile qu'à partir de
# plusieurs étapes ; sur une étape unique, il est facultatif, mais on le pose
# pour que l'ajout d'une étape de construction ultérieure reste lisible.
FROM nginx:1.27-alpine AS base

# ---------------------------------------------------------------------------
# ÉTAPE 2 — Configuration du serveur
# ---------------------------------------------------------------------------
# On retire les deux fichiers de configuration livrés dans l'image officielle :
#   - /etc/nginx/conf.d/default.conf : un bloc server qui écoute sur le port 80 ;
#   - /etc/nginx/nginx.conf          : une configuration qui écrit son fichier
#     d'identifiant dans /run et déclare « user nginx ».
#
# Ce retrait est LE PIÈGE CLASSIQUE du sujet, et il ne produit AUCUNE erreur.
# Le conteneur démarre, la page s'affiche… sur le mauvais port et avec les
# mauvais droits. En effet, l'instruction « include » charge les fichiers par
# ordre alphabétique : en conservant default.conf, le conteneur écouterait sur
# 80 en root, et toute la démonstration « non-root / non privilégié »
# s'effondrerait sans le moindre message.
RUN rm -f /etc/nginx/conf.d/default.conf \
             /etc/nginx/nginx.conf

# On installe la configuration du laboratoire.
COPY nginx/nginx.conf         /etc/nginx/nginx.conf
COPY nginx/conf.d/app.conf    /etc/nginx/conf.d/app.conf

# ---------------------------------------------------------------------------
# ÉTAPE 3 — Fichiers statiques du site
# ---------------------------------------------------------------------------
# COPY du contexte de construction. Le premier argument est la source RELATIVE
# au contexte (on ne peut pas remonter en arrière), le second est la destination
# dans l'image.
#
# L'option --chown fixe le propriétaire. Combinée à l'instruction USER ci-dessous,
# elle garantit que le processus peut lire les fichiers sans disposer des droits
# d'écriture. C'est le principe du moindre privilège appliqué au système de
# fichiers : le contenu servi est en lecture seule pour le serveur.
#
# Le fichier .dockerignore du contexte limite ce qui est envoyé au démon
# Docker ; le contexte n'est donc pas transmis en entier. L'exclure de
# l'IMAGE évite simplement de l'embarquer inutilement.
COPY --chown=nginx:nginx site/ /usr/share/nginx/html/

# ---------------------------------------------------------------------------
# ÉTAPE 4 — Répertoire temporaire inscriptible
# ---------------------------------------------------------------------------
# nginx a besoin d'écrire des fichiers temporaires (voir la directive
# client_body_temp_path et celles de même famille, dans nginx.conf). Avec
# l'utilisateur nginx, le chemin par défaut /var/cache/nginx n'est pas
# inscriptible : le serveur refuserait de démarrer.
#
# On crée donc /tmp/nginx, inscriptible par l'utilisateur nginx. Cette étape
# rend l'image AUTONOME : elle fonctionne aussi bien avec « docker run » seul,
# sans montage tmpfs. Le montage tmpfs de compose.yaml vient en complément,
# pour ne rien écrire du tout sur le disque.
#
# Remarque : on ne crée PAS le fichier d'identifiant. Il est produit par
# nginx au démarrage, dans le répertoire temporaire qu'il choisit.
RUN mkdir -p /tmp/nginx \
    && chown -R nginx:nginx /tmp/nginx

# ---------------------------------------------------------------------------
# ÉTAPE 5 — Changement d'utilisateur
# ---------------------------------------------------------------------------
# Instruction la plus importante du fichier.
#
# L'image nginx alpine démarre normalement en root : le processus maître a
# besoin des privilèges pour ouvrir un port privilégié, puis bascule ses
# processus enfants en utilisateur nginx. Comme notre serveur écoute sur 8080
# (port non privilégié), il n'a besoin de root à aucun moment.
#
# USER s'applique aux instructions SUIVANTES et à l'exécution du conteneur.
# Placée ici, à la fin, elle ne modifie pas l'appartenance des fichiers copiés
# (déjà traitée par --chown) et garantit que le serveur s'exécute sans privilège.
USER nginx

# ---------------------------------------------------------------------------
# ÉTAPE 6 — Métadonnées et configuration du conteneur
# ---------------------------------------------------------------------------
# Documentation de l'image, affichée par « docker inspect ».
LABEL org.opencontainers.image.title="LAB — page web conteneurisée" \
      org.opencontainers.image.description="Page statique servie par nginx, exécutée sans privilège." \
      org.opencontainers.image.licenses="MIT"

# Port d'écoute À L'INTÉRIEUR du conteneur. Il n'ouvre rien : il documente.
# C'est la commande « docker run -p » qui publie réellement le port sur l'hôte.
EXPOSE 8080

# WORKDIR fixe le répertoire courant du processus. On choisit /tmp : c'est un
# répertoire inscriptible par l'utilisateur nginx, contrairement à / (qui
# appartient à root). Le répertoire courant du lanceur du conteneur doit être
# inscriptible ; sinon, un attaquant y déposerait un fichier qui serait exécuté
# avec les droits de l'utilisateur du conteneur — c'est l'« escalade de
# privilèges locale », une famille de failles très répandue.
WORKDIR /tmp

# ---------------------------------------------------------------------------
# ÉTAPE 7 — Oracle de santé
# ---------------------------------------------------------------------------
# Docker exécute cette commande toutes les 30 secondes pendant 3 secondes. Si
# elle échoue, le conteneur est marqué « unhealthy » : c'est le signal sur
# lequel se fondent les orchestrateurs pour ne plus router de trafic vers lui.
#
# Choix d'outils : l'image alpine embarque busybox, qui fournit wget. On n'ajoute
# donc AUCUN paquet supplémentaire rien que pour la supervision — ce qui
# maintient l'image minimale. Sur une image Debian, curl n'est pas présent :
# il faudrait l'installer, ce qui alourdirait l'image pour une sonde de
# quelques octets.
#
# -q  : pas de sortie, seulement le code de retour.
# -O /dev/null : on jette le corps, on ne garde que le statut.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --quiet --output-document=/dev/null http://127.0.0.1:8080/healthz || exit 1

# ---------------------------------------------------------------------------
# ÉTAPE 8 — Commande de démarrage
# ---------------------------------------------------------------------------
# CMD s'exécute au démarrage du conteneur. La forme « exec » (sans shell
# intermédiaire) est la forme RECOMMANDÉE : elle fait du processus nginx le
# PID 1 du conteneur.
#
# Pourquoi c'est important : quand on arrête un conteneur, Docker envoie SIGTERM
# au PID 1. Si un shell se trouvait en interposition, le signal n'atteindrait
# pas nginx, et le conteneur devrait être tué au bout du délai de grâce — arrêt
# brutal, requêtes en cours tronquées. Avec la forme exec, nginx reçoit le
# signal et termine proprement.
#
# -g "daemon off;" : lance nginx au premier plan. Sans ce paramètre, nginx se
# démonise (se détache, rend la main) et le conteneur s'arrêterait aussitôt.
#
# Le point-virgule final est obligatoire : il sépare les directives nginx.
CMD ["nginx", "-g", "daemon off;"]
