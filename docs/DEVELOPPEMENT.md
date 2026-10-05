# Développer Plume

Compiler, tester, comprendre le code et publier une version. Pour contribuer, voir aussi
[CONTRIBUTING.md](../CONTRIBUTING.md).

## Commandes

```sh
./scripts/build.sh             # compile et assemble build/Plume.app
./scripts/build.sh --install   # … puis installe dans /Applications et relance
./scripts/test.sh              # tests de la logique
./scripts/release.sh 1.0.1     # version publiable, ou pour testeurs (voir docs/PUBLIER.md)
./scripts/icon.sh              # refait l'icône de l'app à partir de Resources/Icone.jpg
```

Aucun Xcode requis : SwiftPM et les Command Line Tools suffisent. Il faut un Mac Apple
Silicon sous macOS 15 ou plus récent.

Avec le SDK macOS 27, les macros de SwiftUI (`@State`) ne sont livrées qu'avec Xcode : sans lui,
les scripts se rabattent tout seuls sur un SDK macOS 26 installé (`scripts/sdk.sh`). Pour un
`swift build` lancé à la main :
`SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk swift build -c release`.

## Carte du code

```
Sources/PlumeKit/      cœur indépendant de l'interface (réutilisable pour une app iOS)
  Engine.swift           moteur local : transcription + séparation des voix (FluidAudio / CoreML)
  LiveTranscriber.swift  transcription en direct par fenêtre glissante
  Pipeline.swift         traitement final : dictée, réunion multi-canaux, empreinte vocale
  TranscriptBuilder.swift mots horodatés + diarisation → tours de parole
  TextCleanup.swift      nettoyage léger (hésitations, mots bégayés)
  VoiceCommands.swift    « à la ligne », « efface ça », « appuie sur Entrée »… exécutés après coup
  Styles.swift           style du texte (standard, message, décontracté) et règles par application
  SmartInsert.swift      espace, minuscule et point final adaptés à ce qui entoure le curseur
  Replacements.swift     vocabulaire : remplacements de mots et raccourcis
  LocalAI.swift          l'IA locale (Apple Intelligence) : mise au propre, résumé, transformation
  Exporter.swift         export en Markdown, texte, SRT, WebVTT, JSON
  SettingsBackup.swift   sauvegarde et restauration de tous les réglages en JSON
  Localization.swift, L10nTable.swift   langue de l'interface : `tr("…")` et la table français → anglais
  Library.swift          bibliothèque sur disque (md + json + index), entretien de l'audio
  Stats.swift            chiffres de la page d'accueil
  Recovery.swift         reprise des enregistrements interrompus
  Importer.swift         transcription d'un fichier existant
Sources/Plume/         l'app macOS
  SessionController.swift chef d'orchestre d'un enregistrement (dictée ↔ réunion, pause, consigne IA)
  AudioCapture.swift     micro et son système, lus directement par Core Audio
  AudioDevices.swift     liste des micros, choix de celui à utiliser
  MeetingDetector.swift  repère une app de visio qui ouvre le micro (proposition de réunion)
  SystemVolume.swift     coupe le son de l'ordinateur le temps d'une dictée
  Paster.swift           collage, frappe, Entrée, lecture du champ actif par l'accessibilité
  Hotkeys.swift          raccourcis globaux
  Island.swift           l'île de l'encoche
  Sounds.swift           les sons : synthèse (kit « Bois ») et packs enregistrés
  Design.swift           couleurs, typographie (Geist, Geist Mono), composants et mouvements
  Icons.swift            icônes du portfolio (Lucide au trait de 1,6) et lecteur de tracés SVG
  Updates.swift          mises à jour automatiques (Sparkle)
  Integrations.swift     commande `plume`, connexion à Claude Code et Claude Desktop
  AppShell.swift, AppPages.swift, AppRulesPage.swift, AppModels.swift   la fenêtre : accueil, historique, vocabulaire, applications, réglages
  AppDelegate.swift      barre de menus, fenêtre, liens plume://, câblage
  MCPServer.swift, CLI.swift, Remote.swift, Doctor.swift   côté IA et scripts
```

## Publier

`./scripts/release.sh <version>` fabrique l'app signée (et notarisée, une fois le compte Apple
Developer en place), l'image disque et le flux de mises à jour ; `./scripts/publish.sh
<version>` les met en ligne dans les releases de ce dépôt. Les mises à jour
automatiques passent par Sparkle. Marche à suivre complète : [PUBLIER.md](PUBLIER.md).

## Changer ou mettre à jour le modèle

Le modèle se choisit dans Réglages, parmi toute la famille Parakeet TDT de FluidAudio
(`AsrModelVersion`) ou un dossier personnalisé. Pour profiter d'un nouveau modèle publié par
FluidAudio : monter la version dans `Package.swift`, ajouter un cas à `EngineModel`
(`Engine.swift`) avec son étiquette, sa description et sa `version`, puis
`./scripts/build.sh --install`. Les modèles sont mis en cache dans
`~/Library/Application Support/FluidAudio/Models`. Un dossier personnalisé est chargé par
`AsrModels.loadLocal` ; sa famille (v2, v3, TDT-CTC) est devinée à la taille du vocabulaire
et à la présence d'un encodeur séparé. Les autres moteurs de FluidAudio (Cohere Transcribe,
SenseVoice, Paraformer, Parakeet Unified) ont chacun leur pipeline : les brancher demande une
abstraction au-dessus de `AsrManager`, pas seulement un cas de plus.

## Essais sans micro

Des variables d'environnement rejouent des fichiers à la place des entrées réelles, sur un
canal de commande séparé de l'app installée :

```sh
export PLUME_LIBRARY=/tmp/essai PLUME_CHANNEL=essai PLUME_HEADLESS=1   # invisible, sans raccourcis
export PLUME_DEFAULTS=essai PLUME_SUPPORT=/tmp/essai-support             # réglages, vocabulaire et règles à part
PLUME_FAKE_MIC=moi.wav PLUME_FAKE_SYSTEM=eux.wav PLUME_NO_PASTE=1 PLUME_VERBOSE=1 .build/release/Plume &
.build/release/Plume toggle dictee    # démarre
.build/release/Plume pause            # pause, puis reprise
.build/release/Plume toggle reunion   # passe en réunion
.build/release/Plume stop
.build/release/Plume listen           # dictée sans collage, le texte revient sur la sortie standard
```

`PLUME_DEFAULTS=essai` fait lire et écrire les réglages dans un jeu à part
(`studio.brigode.plume.essai`) : sans lui, le binaire de développement partage les réglages
de l'app installée. `PLUME_FAKE_CALL=zoom.us` simule un appel qui démarre cinq secondes
après le lancement, pour voir la proposition de réunion dans l'île.

`plume transcribe micro.wav --system ordinateur.wav` traite une réunion à deux canaux à
partir de deux fichiers ; `plume aec micro.wav ordinateur.wav propre.wav` isole l'annulation
d'écho. `plume live fichier.wav` rejoue un fichier dans la transcription en direct ;
`plume diarize fichier.wav` affiche les voix détectées ; `plume render dossier/` produit des
aperçus PNG de l'interface. `plume format "texte brut" [--style message]` montre la mise en
forme sans audio ; `plume polish`, `plume transform "consigne"` et `plume summarize <id>`
essaient l'IA locale ; `plume calls` liste les apps qui tiennent le micro. Des dictées
d'essai se fabriquent avec la synthèse vocale du Mac : `say -v Jacques -o d.aiff "Bonjour, à
la ligne, …"` puis `afconvert -f WAVE -d LEI16@16000 -c 1 d.aiff d.wav`. Le journal de l'app
est dans `~/Library/Logs/Plume/plume.log`.

## Captures pour le README

`plume render <dossier> --demo` dessine l'interface hors écran avec une bibliothèque inventée et
un prénom fictif : rien de personnel n'apparaît. Les images du README sont dans `docs/assets/`.
Sans `--demo`, le rendu montre ta vraie bibliothèque : ne le publie pas.
