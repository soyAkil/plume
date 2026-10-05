# Plume — consignes pour les assistants IA

Ce fichier s'adresse aux agents de code (Claude Code, Codex, Cursor…). Les humains trouveront
l'essentiel dans le README.

## Le projet

App macOS (barre de menus + « île » dans l'encoche) de dictée vocale et de transcription de
réunions, entièrement locale. Swift 6 (mode de langage 5), SwiftPM seul : **pas de projet
Xcode**, tout se compile avec les Command Line Tools. Mac Apple Silicon, macOS 15+.

- `Sources/PlumeKit/` : cœur sans interface (moteur FluidAudio/CoreML, pipeline, bibliothèque,
  réglages). Testé.
- `Sources/Plume/` : l'app (interface SwiftUI/AppKit, raccourcis, capture audio, sons, CLI,
  serveur MCP, mises à jour Sparkle).
- Carte fichier par fichier : `docs/DEVELOPPEMENT.md` ; choix techniques : `docs/PLAN.md` ;
  fonctionnalités : `docs/GUIDE.md` ; publication : `docs/PUBLIER.md`.

## Commandes

```sh
swift build -c release          # compile (sans Xcode, SDK macOS 27 : voir docs/DEVELOPPEMENT.md)
./scripts/test.sh               # tests (Swift Testing ; le script règle les chemins sans Xcode)
./scripts/build.sh --install    # app complète dans /Applications, relancée
.build/release/Plume doctor     # état des autorisations, du modèle, des écrans
.build/release/Plume render <dossier> --demo   # captures de l'interface, données inventées
```

Avant de dire qu'une modification marche : compiler, lancer les tests, et si l'interface
change, regarder un rendu `plume render … --demo`.

## Conventions

- Code, commentaires, messages et interface **en français**, tutoiement dans l'interface.
  Commentaires en `///`, qui expliquent le pourquoi. Calque-toi sur le style du fichier.
- Pas de nouvelle dépendance sans en discuter dans une issue.
- Les réglages passent par `PlumeSettings` (PlumeKit) et `SettingsModel` (app).
- Les sons : `Sounds.swift` (synthèse) et `SoundPack` (packs enregistrés, `Resources/Sounds`).
- Variables d'environnement d'essai (`PLUME_LIBRARY`, `PLUME_CHANNEL`, `PLUME_HEADLESS`,
  `PLUME_FAKE_MIC`, `PLUME_FAKE_SYSTEM`, `PLUME_NO_PASTE`, `PLUME_VERBOSE`…) : voir
  `docs/DEVELOPPEMENT.md`, section « Essais sans micro ». Elles permettent de tout tester sans
  toucher à l'app installée ni à la vraie bibliothèque.
- Chaque PR ajoute une ligne en haut de « Non publié » dans `CHANGELOG.md` :
  `- Domaine : effet, en quelques mots (#numéro)`. L'effet, pas la façon ; une PR sans effet
  notable (coquille, refacto) n'en ajoute pas. À la publication, « Non publié » devient
  `## <version> — <date>`.

## À ne jamais faire

- Committer un enregistrement, une transcription ou le contenu de `~/Plume` : ce sont des
  données personnelles. Les tests utilisent des phrases inventées.
- Publier un rendu `plume render` sans `--demo` : il montre la vraie bibliothèque.
- Modifier `scripts/release.env` (dépôt, clé publique des mises à jour) ou l'identifiant
  `studio.brigode.plume` : les apps déjà installées ne recevraient plus de mises à jour.
- Lancer `scripts/release.sh` ou `scripts/publish.sh` sans qu'on te le demande : ils signent
  et mettent en ligne une version.
