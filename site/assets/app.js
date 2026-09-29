/* ==========================================================================
   app.js — comportement de la page
   --------------------------------------------------------------------------
   RÔLE DU FICHIER
   Ce fichier n'ajoute que DEUX comportements :
     1. la bascule du thème clair / sombre ;
     2. l'appel à la route /api/infos du serveur.
   Tout le reste de la page fonctionne sans lui. C'est un principe de robustesse
   : une page doit rester lisible même si le JavaScript est désactivé ou échoue.

   CHOIX TECHNIQUE MAJEUR : aucune dépendance.
   Pas de jQuery, pas de framework, pas de CDN. On utilise uniquement l'API
   standard du navigateur, disponible partout depuis plus de dix ans. Pour ce
   volume de code (moins de 100 lignes), une bibliothèque coûterait plus
   volumineuse que le problème qu'elle résout — et c'est un excellent sujet
   de discussion avec les étudiants.

   LES DEUX API UTILISÉES
     - localStorage : stockage persistant clé/valeur, limité à quelques
       kilo-octets, propre à un navigateur et à un domaine.
     - fetch      : requête HTTP asynchrone, avec une promesse (Promise) en
       retour. Une promesse représente une valeur qui n'est pas encore
       connue, et fournit then/catch pour traiter sa résolution ou son échec.
   ========================================================================== */

/* --------------------------------------------------------------------------
   1. CONSTANTES ET SÉLECTEURS
   --------------------------------------------------------------------------
   Toute valeur « magic string » (une chaîne écrite en dur, répétée) est
   remontée ici. Deux raisons : la correction devient triviale, et le
   typage d'une faute de frappe devient une erreur immédiate au chargement
   plutôt qu'un comportement silencieux faux. */
const CLE_THEME = "lab-theme"; // clé du thème dans localStorage
const URL_INFOS = "/api/infos"; // route interrogée par le bouton

/* document.querySelector renvoie le PREMIER élément correspondant au
   sélecteur, ou null si aucun ne correspond. Le sélecteur peut être un
   identifiant (#zone), une classe (.bouton) ou une balise. */
const boutonTheme = document.querySelector('[data-action="basculer-theme"]');
const zoneStatut = document.querySelector("[data-zone-statut]");
const boutonInterroger = document.querySelector(
  '[data-action="interroger-serveur"]'
);

/* --------------------------------------------------------------------------
   2. THÈME CLAIR / SOMBRE
   --------------------------------------------------------------------------
   PRINCIPE
   La feuille de style définit le thème sombre dans une requête de média
   @media (prefers-color-scheme: dark). Cette règle respecte donc déjà le
   réglage du système d'exploitation.

   Pour permettre un choix forcé par l'utilisateur, on ne modifie jamais la
   feuille de style : on pose un attribut data-theme sur <html> et le CSS y
   répond. Modifier des règles CSS depuis le JavaScript ferait perdre la
   traçabilité de l'état : il deviendrait impossible de savoir, en lisant le
   CSS seul, ce que fait la page.

   Pourquoi cet ordre est important : le thème enregistré doit s'appliquer
   AVANT le premier rendu, sinon l'utilisateur voit un éclair de la mauvaise
   couleur. On rétablit donc le thème dès le chargement du script — c'est la
   raison pour laquelle le script est chargé avec l'attribut defer en fin de
   document : le DOM existe déjà, et rien n'a encore été peint. */
function appliquerTheme(theme) {
  document.documentElement.setAttribute("data-theme", theme);

  // aria-pressed décrit l'ÉTAT du bouton, pas l'action à venir.
  // true = thème sombre actif, donc le bouton sert à revenir en clair.
  if (boutonTheme) {
    boutonTheme.setAttribute("aria-pressed", String(theme === "sombre"));
  }

  // Le libellé annonce l'action, donc il décrit toujours le thème opposé.
  const libelle = theme === "sombre" ? "Thème clair" : "Thème sombre";
  const cible = boutonTheme.querySelector("[data-theme-libelle]");
  if (cible) cible.textContent = libelle;
}

function lireThemeEnregistre() {
  try {
    return localStorage.getItem(CLE_THEME);
  } catch {
    // En navigation privée stricte, l'accès à localStorage lève une
    // SecurityError. On ne casse pas la page pour autant : on renvoie null,
    // ce qui fait retomber le site sur le thème du système.
    return null;
  }
}

function enregistrerTheme(theme) {
  try {
    localStorage.setItem(CLE_THEME, theme);
  } catch {
    /* Le thème ne sera pas mémorisé. Sans conséquence fonctionnelle. */
  }
}

function basculerTheme() {
  const themeActuel = lireThemeEnregistre();
  const themeSuivant = themeActuel === "sombre" ? "clair" : "sombre";
  enregistrerTheme(themeSuivant);
  appliquerTheme(themeSuivant);
}

if (boutonTheme) {
  appliquerTheme(lireThemeEnregistre() || "clair");
  boutonTheme.addEventListener("click", basculerTheme);
}

/* --------------------------------------------------------------------------
   3. INTERROGATION DE L'API
   --------------------------------------------------------------------------
   PRINCIPE
   Le bouton déclenche un appel HTTP GET vers /api/infos. Le serveur répond du
   JSON. On affiche le résultat (ou l'erreur) dans la zone de statut.

   Le point important : la zone de statut contient aria-live="polite" dans le
   HTML. Le lecteur d'écran annoncera donc automatiquement la modification,
   sans que l'utilisateur ait à deviner qu'un résultat vient d'arriver. */

async function interrogerServeur() {
  if (!zoneStatut || !boutonInterroger) return;

  // On désactive le bouton pendant la requête : cela empêche les doubles
  // clics, et le libellé « Interroger… » rend l'attente visible.
  boutonInterroger.disabled = true;
  boutonInterroger.textContent = "Interrogation en cours…";
  zoneStatut.textContent = "Requête vers " + URL_INFOS + "…";

  try {
    const reponse = await fetch(URL_INFOS, {
      // Envoi de l'horodatage de la page comme en-tête personnalisé.
      // nginx ne le refuse pas : cela prouve, en direct, que la requête
      // atteint bien le serveur et revient par un chemin non mis en cache.
      headers: { "X-Client": "lab-page" },
      // Pas de cache : chaque clic doit réellement interroger le serveur.
      cache: "no-store",
    });

    // HTTP sépare les deux familles de résultats : 2xx = succès,
    // 4xx/5xx = échec applicatif. fetch ne lève PAS d'exception sur un 404,
    // il faut donc vérifier explicitement. C'est le piège le plus courant.
    if (!reponse.ok) {
      throw new Error("Réponse HTTP " + reponse.status);
    }

    const donnees = await reponse.json(); // JSON -> objet JavaScript

    // On affiche le nombre de clés reçues, pas le JSON brut : c'est court,
    // lisible en ligne, et cela prouve que l'analyse a réussi.
    const cles = Object.keys(donnees);
    zoneStatut.textContent =
      "Succès — " +
      cles.length +
      " champ(s) reçu(s) : " +
      cles.join(", ");
  } catch (erreur) {
    // Un échec réseau (conteneur arrêté, page hors ligne) et une erreur
    // applicative (404, 500) arrivent ici. Le message reste utile sans
    // révéler de détail technique à l'utilisateur final.
    zoneStatut.textContent = "Échec de la requête — " + erreur.message;
  } finally {
    // finally s'exécute dans les deux cas (succès ou échec) : c'est le
    // endroit fiable pour remettre l'interface dans son état normal.
    boutonInterroger.disabled = false;
    boutonInterroger.textContent = "Interroger le serveur";
  }
}

if (boutonInterroger) {
  boutonInterroger.addEventListener("click", interrogerServeur);
}
