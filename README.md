# Polyglotte 🇷🇺 🇨🇳

Application Android (Flutter) pour apprendre le **russe** et le **mandarin**, avec un parcours quotidien de 10 à 15 minutes.

## Fonctionnalités

- **Session du jour** : révisions programmées par répétition espacée (type SM-2) et nouveaux éléments (8 par jour par défaut, réglable).
- **Exercices variés** : présentation, QCM (sens, sens inverse), écoute, cartes mémoire auto-évaluées, remise en ordre de phrases, reconnaissance des tons, son des lettres.
- **Prononciation** : tu parles dans le micro et la reconnaissance vocale d'Android vérifie ce que tu dis.
- **Tracé au doigt** des lettres cyrilliques et des caractères chinois, avec un score de précision.
- **Tons colorés** en chinois (1 rouge, 2 vert, 3 bleu, 4 violet), pinyin et translittération avec l'accent tonique.
- **Tuteur IA** : jeux de rôle (café, restaurant, hôtel, taxi…) avec corrections et traductions. Fournisseurs : **Google Gemini (gratuit)**, **Groq (gratuit)** ou **Claude (payant)**.
- **Rappel quotidien** par notification, **série de jours** 🔥, XP et statistiques.
- **Contenu** : 12 unités en russe (alphabet, 9 thèmes de vocabulaire, 2 unités de phrases) et 13 en mandarin (tons, caractères de base, 9 thèmes, 2 unités de phrases), soit 353 éléments en tout. Tout fonctionne hors ligne, sauf le tuteur IA.

## Obtenir l'APK

### Option A : GitHub Actions (rien à installer)
1. Crée un dépôt sur GitHub et pousses-y ce dossier (branche `main`).
2. L'onglet **Actions** lance automatiquement « Construire l'APK Android ».
3. À la fin du build, télécharge l'artefact **polyglotte-apk**, dézippe-le et copie `app-release.apk` sur ton téléphone.
4. Ouvre le fichier sur le téléphone (autorise « Installer des applis inconnues »).

### Option B : sur ton ordinateur
1. Installe [Flutter](https://docs.flutter.dev/get-started/install) et Android Studio (pour le SDK Android).
2. Dans ce dossier :
   ```bash
   flutter pub get
   flutter build apk --release
   ```
3. L'APK se trouve dans `build/app/outputs/flutter-apk/app-release.apk`.
   Avec le téléphone branché en USB (débogage activé), `flutter install` l'installe directement.

## Réglages à faire sur le téléphone

- **Voix** : Paramètres Android › Synthèse vocale › moteur Google › installer les voix **russe** et **chinois (Mandarin)**.
- **Reconnaissance vocale** : dans l'appli Google, *Saisie vocale › Langues hors connexion*, ajoute le russe et le chinois (facultatif mais plus rapide).
- **Tuteur IA gratuit** : crée une clé sur <https://aistudio.google.com/apikey>, puis colle-la dans *Réglages › Tuteur IA*.

## Structure du code

```
lib/
  main.dart                 démarrage, thème
  app_state.dart            progression, réglages, série (SharedPreferences)
  models.dart               Item, CardState (algorithme SM-2), outils pinyin
  session.dart              construction des sessions et choix des exercices
  data/russian.dart         contenu russe   ← ajoute tes propres mots ici
  data/mandarin.dart        contenu mandarin
  services/ai_tutor.dart    tuteur IA (Gemini, Groq, Claude)
  services/speech.dart      synthèse et reconnaissance vocales
  services/reminders.dart   notification quotidienne
  screens/…                 écrans (accueil, leçons, session, tuteur, progrès, réglages)
  widgets/exercises.dart    tous les types d'exercices
  widgets/trace_pad.dart    zone de tracé et calcul du score
test/logic_test.dart        tests (contenu, SRS, sessions…)
```

### Ajouter du vocabulaire
Ajoute des lignes `['texte', 'prononciation', 'français']` dans une unité de `lib/data/*.dart`.
Ajoute-les **à la fin** d'une unité ou dans une nouvelle unité placée à la fin de la liste, sinon tu perds la progression des mots existants (les identifiants dépendent de la position).
En chinois, mets une syllabe pinyin par caractère et sépare les mots des phrases par des espaces. `flutter test` vérifie que les deux correspondent.
