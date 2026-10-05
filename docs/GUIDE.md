# Guide d'utilisation

Tout ce que Plume sait faire, en détail. Pour l'essentiel, voir le [README](../README.md).

## Les gestes

| Geste | Effet |
|---|---|
| `⌃⇧` (appui bref) | Démarre un enregistrement. Second appui : le texte est collé dans le champ actif. |
| `⌃⇧` (maintenu) | Parle tant que les touches sont tenues ; relâche pour coller. |
| Survol de l'encoche | La touche **Réunion** (elle s'enclenche et reste allumée), annuler, terminer. |
| `⌃⇧⌘` | Démarre directement une réunion (ou y passe en cours de dictée). |
| `Échap` | Annule la dictée en cours (raccourci modifiable). L'enregistrement annulé reste récupérable, voir [Enregistrements annulés](#enregistrements-annulés). |
| Survol de l'encoche › `⏸` | Met l'enregistrement en pause (le micro se ferme) ; `▶` reprend. |
| Clic sur l'icône de la barre de menus | Ouvre la fenêtre de Plume (clic droit : menu court, avec les dernières dictées à recopier). |
| `1` `2` `3` `4` `5`, `T`, `S` dans la fenêtre | Accueil, historique, vocabulaire, applications, réglages ; thème clair / sombre ; sons. |

Trois raccourcis de plus, sans touche par défaut (à choisir dans **Réglages › Raccourcis**) :
**Recoller la dernière dictée** (quand le collage a raté, ou pour la réutiliser ailleurs),
**Récupérer le dernier enregistrement annulé** et **Transformer la sélection** (voir
[IA locale](#ia-locale)).

Le raccourci **Annuler la dictée** accepte une touche seule ou avec modificateurs, Échap
compris (`⎋`, `⇧⎋`, `⌃⎋`…) : une combinaison évite de couper une dictée en pressant Échap
par réflexe dans une autre app.
Il n'est intercepté que pendant une dictée ; le reste du temps, la touche garde son rôle.

Les raccourcis se changent dans **Réglages**. Un raccourci peut être un accord de
modificateurs seuls (`⌃⇧`) ou une touche avec modificateurs (`⌥Espace`). Un accord ne se
déclenche que s'il est « propre » : `⌃⇧Tab` ou `⌃⇧` + clic ne lancent rien.

## Ce qui arrive au texte dicté

Dans l'ordre, à la fin de chaque dictée :

1. **Nettoyage** : hésitations (« euh ») et mots bégayés retirés. Le texte brut du modèle est
   conservé dans l'historique.
2. **Commandes vocales** (Réglages › Dictée) : « à la ligne », « nouveau paragraphe »,
   « nouvelle puce » (ou « tiret » après un saut de ligne), « point d'interrogation », « point
   d'exclamation », « deux points » (suivi d'une pause), « points de suspension », « ouvrez /
   fermez les guillemets », « ouvrez / fermez la parenthèse », « efface ça » (retire la phrase
   qui précède), « efface tout », et « appuie sur Entrée » tout à la fin pour envoyer le message.
   En anglais : *new line*, *new paragraph*, *bullet point*, *scratch that*, *press enter*…
   Plume ne confond pas « la pêche à la ligne » ni « à la ligne 42 » avec une commande.
3. **Vocabulaire** : les remplacements de la page Vocabulaire. Une entrée dont la colonne
   « Écrit » tient sur plusieurs lignes (`⌥↩`) fait un raccourci vocal : « ma signature »
   devient ta signature complète.
4. **Style de l'application** (page Applications) : *Standard*, *Message* (sans point final),
   *Décontracté* (sans majuscule de début de phrase ni point final).
5. **Mise au propre par l'IA locale**, si elle est demandée (voir plus bas).
6. **Écrire au fur et à mesure** (Réglages › Dictée, inactif par défaut, marqué « bêta ») : les mots se tapent
   dans le champ pendant que tu parles, cinq fois par seconde, tels que le direct les entend ;
   quand le modèle se corrige, Plume efface les quelques caractères qui changent et retape.
   Le dernier mot entendu attend le suivant (c'est le moins sûr). À l'arrêt, ce qui reste est
   tapé tout de suite. Le texte passe par le nettoyage, les commandes vocales (« efface ça »
   efface aussi ce qui est déjà tapé), le vocabulaire et le style de l'app ; la mise au propre
   par l'IA ne s'applique pas, et l'historique garde la version complète retranscrite d'un
   bloc. Ne déplace pas le curseur pendant que ça écrit.
7. **Insertion intelligente** (Réglages › Dictée) : Plume regarde ce qui entoure le curseur
   (par l'accessibilité, quand l'app le permet) et ajoute une espace si le curseur touche un
   mot, met une minuscule si la phrase est déjà commencée, retire le point final si elle
   continue après le curseur.

## Applications

La page **Applications** donne à chaque app sa règle de dictée : le style du texte, **Valider
avec Entrée** (le message part dès qu'il est collé — pour Slack, Messages, un terminal), la
**mise au propre par l'IA locale** avec ses consignes (« vouvoie », « pas d'émojis »), et
**Taper le texte au lieu de le coller** pour les rares apps qui refusent `⌘V` (bureau à
distance, certains terminaux). « Toutes les autres applications » fixe la règle par défaut.
Plume reconnaît l'app au premier plan au moment où la dictée commence.

## IA locale

Sur un Mac avec Apple Intelligence (macOS 26 ou plus récent, Apple Intelligence activée dans
les Réglages Système), Plume peut utiliser le modèle de langage d'Apple, qui tourne sur
l'appareil : rien ne quitte le Mac. Tout est en option, désactivé par défaut.

- **Mettre les dictées au propre** (Réglages › IA locale, ou par application) : ponctuation,
  faux départs et auto-corrections (« non pardon, à 16 h ») repris, sans changer le sens. Si
  la réponse paraît douteuse (vide, bien plus longue ou plus courte), Plume garde le texte
  déterministe. Le brut reste dans l'historique.
- **Résumer une réunion** : dans l'historique, le bouton **Résumer** écrit les points clés,
  les décisions et les actions, et propose un titre. Le résumé est rangé dans le fichier
  Markdown de la transcription (section « Résumé »), donc visible par les IA qui lisent la
  bibliothèque. **Réglages › IA locale › Résumer chaque réunion** le fait tout seul.
- **Transformer la sélection** (raccourci à choisir) : sélectionne un texte dans n'importe
  quelle app, appuie sur le raccourci, dicte une consigne (« traduis en anglais », « plus
  court », « mets en liste », « rends ça plus formel ») ; l'IA réécrit et le résultat remplace
  la sélection. Sans sélection, elle rédige à partir de la consigne (« un message pour prévenir
  Marc que je serai en retard »).

Sans Apple Intelligence, ces réglages sont grisés et en expliquent la raison.

## Réunions

Quand **Zoom, Teams, FaceTime, Webex, Slack, Discord** ou **un navigateur** (Meet, Teams
web) se met à utiliser le micro, l'encoche propose d'enregistrer la réunion : un clic sur
**Enregistrer** suffit. La proposition disparaît d'elle-même au bout de vingt secondes.
Réglages › Réunion › *Proposer d'enregistrer quand un appel démarre* la désactive. Plume ne
fait que lire la liste des processus audio : rien n'est écouté avant que tu l'aies demandé.

Pendant un enregistrement, si le micro ne capte rien pendant quinze secondes, l'onde de
l'encoche s'éteint et un « zZ » bleuté se pose dessus : micro coupé, mauvais
périphérique. Tout rentre dans l'ordre dès qu'un son arrive.

L'audio est écrit sur disque au fil de l'eau, pour une réunion comme pour une dictée : si
l'app s'arrête en plein enregistrement, il est transcrit au prochain lancement.

En mode réunion, Plume capte aussi le son de l'ordinateur, sépare les voix à la fin, et
range le dialogue dans l'historique au lieu de le coller. Sans casque, le son des
haut-parleurs repasse dans le micro : Plume le détecte et retire cet écho avant de
transcrire, sinon les voix distantes apparaîtraient en double et masqueraient la tienne.
Si les voix restent mal séparées, « Refaire la séparation des voix » (dans l'historique)
réécoute l'audio en imposant le nombre de personnes. « Moi » désigne ta voix : Plume
l'apprend à partir de tes dictées (une empreinte vocale stockée localement). Dans
l'historique, un clic sur un nom le renomme partout ; un clic sur un horodatage lance
l'écoute à cet endroit.

Plume n'écoute pas l'entrée audio par défaut du système mais le micro choisi dans
**Réglages › Micro et sons** — par défaut celui du Mac. Connecter des écouteurs ou une enceinte
Bluetooth ne change donc rien ; pour dicter avec leur micro, il faut le choisir soi-même.

**Réglages › Dictée › Couper le son de l'ordinateur pendant la dictée** coupe la musique ou
la vidéo en cours le temps de parler, puis la rétablit (jamais en réunion).

## Historique

Chaque transcription peut recevoir un **titre** (clic sur le titre) ; sinon, la date en tient
lieu. Le bouton **Exporter** l'enregistre en Markdown, texte brut, sous-titres SRT ou WebVTT
(pour les réunions) ou JSON. **Retranscrire** refait la transcription à partir de l'audio
conservé, avec le modèle actuel. Le presse-papiers est toujours rétabli après le collage, et la
dictée est marquée « transitoire » : les gestionnaires de presse-papiers (Paste, Maccy,
Raycast…) ne la gardent pas dans leur historique.

**Réglages › Bibliothèque › Conserver de chaque dictée** : *le texte et l'audio* (par
défaut), *le texte seulement*, ou *rien* — la dictée est collée puis oubliée, sans texte, sans
audio, sans fichier de secours (les réunions, qui n'ont pas d'autre débouché, restent dans
l'historique). **Garder l'audio** limite la conservation des enregistrements (90, 30 ou 7
jours) : l'audio plus ancien est supprimé au lancement, le texte reste.
### Enregistrements annulés

Une dictée ou une réunion annulée (raccourci, bouton de l'encoche, menu) n'est pas jetée tout de
suite : elle est mise de côté dans `~/Plume/.annules/`, hors de l'historique et de l'index.
Elle se retrouve par le bouton `↶` en haut de l'historique (on peut l'écouter, la copier, la récupérer ou la supprimer), par le
raccourci **Récupérer le dernier enregistrement annulé**, le menu de la barre, `plume restore` ou
`plume://recuperer`. Une dictée annulée est transcrite en arrière-plan (la récupérer la colle
aussitôt, depuis l'encoche ou le raccourci) ; une réunion ne l'est qu'au moment où on la récupère.
**Réglages › Bibliothèque › Garder les enregistrements annulés** : *ne pas garder*, 1 heure,
24 heures, 7 jours (par défaut) ou 30 jours ; passé ce délai, ils sont supprimés. Un appui de
moins d'une seconde n'est pas gardé.

**Tous les réglages › Exporter…** écrit raccourcis, options, vocabulaire et règles par
application dans un fichier JSON, à importer sur un autre Mac.

## Langue

L'interface est en anglais par défaut ; **Réglages › Général › Langue** la passe en français
(ou l'inverse), sans tenir compte de la langue du système. Le choix vaut pour la fenêtre,
l'encoche, les menus, les titres des transcriptions (« Réunion du 2 oct. 2026 à 11:30 » /
« Meeting, Oct 2, 2026 at 11:30 AM »), les noms des interlocuteurs (« Moi », « Interlocuteur
1 » / « Me », « Speaker 1 ») et les notes de réunion écrites par l'IA locale. Les commandes
vocales marchent dans les deux langues quel que soit le réglage. La ligne de commande reste
en français.

## Modèles de transcription

**Réglages › Modèle** propose toute la famille Parakeet que FluidAudio sait
faire tourner sur le Neural Engine, chacun avec ses langues, sa taille et sa précision :
Parakeet Ultra (recommandé, 25 langues), Parakeet TDT v3, Parakeet Redux (compact, 220 Mo),
Parakeet TDT v2 et Phonon-2 (anglais), Parakeet TDT-CTC 110M (anglais, le plus rapide),
Parakeet japonais. Chaque modèle est téléchargé une fois depuis Hugging Face, puis tout se
passe hors ligne. **Dossier personnalisé…** charge ton propre modèle : un dossier au format
Parakeet (quatre `.mlmodelc` — Preprocessor, Encoder, Decoder, JointDecision — et
`parakeet_vocab.json`), par exemple un Parakeet ré-entraîné sur ton vocabulaire et converti
avec les outils de FluidAudio. Le bouton **Retranscrire** de l'historique permet de comparer
deux modèles sur le même enregistrement.

## Sons

Un son au début et à la fin de chaque enregistrement, au choix dans **Réglages › Micro et
sons › Pack de sons** : Pluck (par défaut), Bips, Clics, Mélodie, Glisse, ou Bois. Les packs sont des
sons enregistrés (`Resources/Sounds`), raccourcis et adoucis par l'app ; Bois est synthétisé à
la volée avec la recette du kit du portfolio (marimba très sobre, gamme pentatonique). Les
gestes dans la fenêtre (survols, onglets, interrupteurs) ont leurs propres notes synthétisées.
Volume et coupure dans **Réglages › Micro et sons** ou avec la touche `S`. `plume sounds <dossier>`
écrit tous les sons en WAV, un sous-dossier par pack.

## Autorisations macOS

| Autorisation | Pourquoi | Quand |
|---|---|---|
| Microphone | T'entendre | Première dictée, ou depuis l'accueil |
| Accessibilité | Simuler ⌘V pour coller le texte | Depuis l'accueil ; sans elle le texte est seulement copié |
| Enregistrement audio du système | Capter le son de l'ordinateur en réunion | Première réunion |

L'app est signée avec un certificat local stable : les autorisations survivent aux mises à jour.

## La bibliothèque : `~/Plume`

```
~/Plume/
  LISEZMOI.md                          mode d'emploi du dossier, pour les IA
  dernier.md                           la transcription la plus récente
  index.jsonl                          une ligne JSON par transcription
  2026-10/
    2026-10-02_14-31-05_dictee.md      texte, avec en-tête (date, durée, interlocuteurs)
    2026-10-02_14-31-05_dictee.json    données complètes (segments horodatés, texte brut)
    2026-10-02_14-31-05_mic.m4a        audio d'origine (mic = micro, sys = son de l'ordinateur)
```

## Accès pour une IA

1. **Le dossier.** « Lis `~/Plume/dernier.md` » suffit à tout agent qui a accès aux fichiers.
2. **La ligne de commande** `plume` :
   ```sh
   plume last                 # dernière transcription
   plume last --mode reunion  # dernière réunion
   plume list -n 10           # les dix dernières
   plume search budget site   # recherche plein texte
   plume show 2026-10-02_14-31-05
   plume transcribe audio.m4a --mode reunion --save
   plume export 2026-10-02_14-31-05 --format srt -o reunion.srt
   plume summarize 2026-10-02_14-31-05       # résumé par l'IA locale
   plume listen                              # dicte dans l'app, le texte revient ici
   ```
   Ajoute `--json` pour une sortie structurée.
3. **Le serveur MCP** (`plume mcp`), déclaré dans Claude Code. Outils : `get_latest_transcript`,
   `list_transcripts`, `get_transcript`, `search_transcripts`, `summarize_transcript`, et
   **`listen`** : l'agent ouvre le micro, tu réponds à la voix, tu termines avec ton raccourci,
   il reçoit le texte. De quoi dire à Claude Code « demande-moi à l'oral » plutôt que de taper.

`plume toggle dictee|reunion`, `plume stop`, `plume cancel`, `plume pause`, `plume paste`
(recoller la dernière dictée), `plume restore` (récupérer le dernier enregistrement annulé ;
`plume cancelled` les liste) et `plume open` pilotent l'app ouverte depuis un script, Raycast
ou un Stream Deck. Les liens `plume://dictee`, `plume://reunion`, `plume://stop`,
`plume://pause`, `plume://recoller`, `plume://recuperer`, `plume://transformer` et `plume://ouvrir` font de même
depuis Raccourcis ou n'importe quelle app. `plume doctor` affiche l'état des autorisations, du
modèle, de l'IA locale et des écrans ; `plume format "texte"` montre ce que la mise en forme
fait d'un texte brut ; `plume polish` et `plume transform` essaient l'IA locale.
