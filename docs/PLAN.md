# Plume — choix techniques et feuille de route

## L'idée

Une alternative libre à Superwhisper, pensée de zéro : dictée par raccourci, modèle local à
la pointe, séparation des interlocuteurs, transcription en direct, double source (micro + son
de l'ordinateur), bibliothèque centralisée lisible par une IA, texte collé dans le champ
actif, interface minimale.

## Choix techniques

| Sujet | Choix | Pourquoi |
|---|---|---|
| Forme | App macOS native (Swift, barre de menus) | Légère, intégrée, pas de runtime à installer. |
| Outillage | SwiftPM seul | Tout se compile avec les Command Line Tools, sans Xcode. |
| Moteur | FluidAudio 0.17.5 (CoreML, Neural Engine) | Seule pile Swift qui réunit transcription, direct et diarisation, et qui se compile sans Xcode (MLX exige Xcode). |
| Modèle | Parakeet Ultra (septembre 2026) | Meilleur compromis précision / vitesse en français exécutable en local : FLEURS fr ≈ 4,3 % d'erreur, ~150× le temps réel. Cohere Transcribe est un peu plus précis mais 70× plus lent en CoreML ; Whisper large-v3-turbo est en retrait. |
| Direct | Fenêtre glissante re-transcrite ~2 fois par seconde | Même modèle que le résultat final, pour 6 à 7 % du temps réel. Le texte validé se fige aux fins de phrase. |
| Interlocuteurs | Diarisation hors ligne (pyannote community-1) en fin d'enregistrement, par canal | Plus fiable que la diarisation en flux. Le micro et le son système sont traités séparément puis fusionnés par horodatage. |
| « Moi » | Empreinte vocale apprise sur les dictées | Une dictée ne contient que la voix de l'utilisateur : c'est un échantillon d'entraînement gratuit. |
| Son système | Process tap Core Audio | Ne demande que l'autorisation « audio du système », pas l'enregistrement d'écran. |
| Raccourcis | Accord de modificateurs `⌃⇧` (le même que Superwhisper), lu par interrogation de l'état du clavier | Sans autorisation spéciale ; ne se déclenche pas sur `⌃⇧`+touche. Quitter Superwhisper pour éviter un double déclenchement. |
| Interface | Une île qui sort de l'encoche + une seule fenêtre (accueil, historique, vocabulaire, réglages) | Discret pendant la dictée, tout au même endroit ensuite. |
| Écho en réunion | Annulation d'écho neuronale (LocalVQE) sur le micro, avec le son de l'ordinateur comme référence, seulement si l'écho est détecté | Sans casque, les voix distantes apparaissaient en double et masquaient la voix locale. |
| Tours de parole | Changements de voix recalés sur la pause ou la fin de phrase la plus proche ; pas de fusion de voix « ressemblantes » | Une fusion trop zélée confond deux personnes à la voix proche, et les frontières tombaient un ou deux mots à côté. |
| Mode réunion | Bascule dans l'île, en cours d'enregistrement | On ne sait pas toujours à l'avance qu'on est en réunion ; le canal « son de l'ordinateur » démarre à la bascule. |
| Bibliothèque | Dossier `~/Plume` : Markdown + JSON + audio | Lisible par un humain, par `grep`, par n'importe quelle IA ; pas de base de données. |
| Accès IA | Dossier, commande `plume`, serveur MCP | Du plus universel au plus intégré. |
| Signature | Certificat auto-signé dans un trousseau dédié (en attendant un certificat Developer ID) | Les autorisations macOS survivent aux recompilations. |
| Distribution | Image disque sur les releases GitHub, mises à jour Sparkle | Un lien unique, et les mises à jour arrivent toutes seules (voir `docs/PUBLIER.md`). |
| Mise en forme | Chaîne déterministe (nettoyage → commandes vocales → vocabulaire → style → insertion), l'IA après et en option | Le reproche n° 1 fait aux concurrents : une IA qui change les mots ou les chiffres. Le brut reste toujours dans l'historique. |
| IA locale | Modèle de langage d'Apple Intelligence (FoundationModels), sur l'appareil | Aucune dépendance, aucun compte, rien n'est envoyé. Fenêtre de 4 096 jetons : les longues réunions sont résumées par morceaux puis fusionnées. |
| Profils | Une règle par application (style, Entrée, IA, frappe), reconnue au premier plan | Les « modes » à configurer sont le reproche n° 2 fait à Superwhisper ; ici une liste, et rien à choisir avant de parler. |
| Réunion détectée | Liste des processus Core Audio qui lisent une entrée (`kAudioHardwarePropertyProcessObjectList`) | Sans écouter : on ne lit que « qui tient le micro ». Une visio connue déclenche une proposition dans l'île. |
| Pause | Le micro se ferme vraiment (voyant orange éteint), le silence manquant est comblé à la reprise | Demandée depuis deux ans chez Superwhisper (196 votes) sans être livrée. |
| Son coupé en dictée | Réglage « muet » de la sortie par défaut (Core Audio), pas MediaRemote | MediaRemote est privé et cassé depuis macOS 15.4 ; le muet se rétablit sans rien mémoriser. |
| Insertion | Lecture du champ actif par l'accessibilité (`AXSelectedTextRange`, `AXStringForRange`) | Les apps natives l'exposent ; les apps web ou Electron souvent pas, alors Plume colle tel quel. |

## Feuille de route

1. **App iOS native** avec le même moteur embarqué (PlumeKit est déjà séparé de l'interface,
   et FluidAudio tourne sur iOS 17+). Demande Xcode et un compte développeur Apple. Contenu :
   enregistrement, transcription sur le téléphone, historique, action « Dicter » pour le
   bouton Action.
2. **Vocabulaire acoustique** (noms propres, jargon) par le « CTC boosting » de FluidAudio, en
   plus des remplacements de mots. Le modèle CTC est entraîné sur l'anglais : à évaluer sur
   des noms français avant de l'exposer.
3. **Vocabulaire appris des corrections** : relire le champ quelques secondes après le collage
   et proposer un remplacement quand un mot a été corrigé à la main.
4. **Fin d'appel** : quand l'app de visio lâche le micro, proposer de terminer la réunion.
5. **Pré-roll** du micro pour ne pas perdre la première syllabe en « parler en maintenant ».
6. **Synchronisation** de la bibliothèque (la placer dans iCloud Drive suffit déjà, via
   Réglages › Bibliothèque).
7. **Notarisation** Apple, pour supprimer le blocage à la première ouverture.
8. **Autres traductions** de l'interface : l'anglais (par défaut) et le français sont dans
   `PlumeKit/L10nTable.swift` ; une langue de plus est une table de plus.
