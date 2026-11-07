# Retrouve mon téléphone — prototype

Prototype Flutter Android/iOS de localisation consentie. Cette première version affiche en continu la position du téléphone utilisé, uniquement lorsque l'application est ouverte et après autorisation explicite. Elle n'envoie pas de position à un serveur et ne localise pas un autre téléphone.

## Démarrage

Prérequis : Flutter SDK installé. Le dépôt contient le code Dart et ses dépendances ; générez les fichiers de plateforme Flutter depuis la racine du projet :

```bash
flutter create --project-name lost_phone --platforms android,ios .
flutter pub get
flutter run
```

Sur iOS, la compilation nécessite macOS et Xcode. Testez sur un appareil réel pour vérifier les autorisations et le GPS.

## Permissions de localisation

Android : dans `android/app/src/main/AndroidManifest.xml`, ajoutez avant `<application>` :

```xml
<uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
```

iOS : dans `ios/Runner/Info.plist`, ajoutez dans le dictionnaire principal :

```xml
<key>NSLocationWhenInUseUsageDescription</key>
<string>Votre position sert à retrouver cet appareil lorsque vous le demandez.</string>
```

## Limites et prochaine étape

La position en temps réel à distance n'est pas encore implémentée. Elle nécessitera un compte, l'association volontaire d'appareils, une API sécurisée et un partage révocable. La disponibilité dépendra du réseau, de la batterie, des réglages système et des autorisations. Le suivi en arrière-plan n'est pas activé dans ce prototype.
