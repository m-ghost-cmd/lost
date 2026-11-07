# Retrouve mon téléphone — prototype Firebase

Application Flutter Android/iOS de localisation consentie. Authentification Firebase par e-mail/mot de passe, association manuelle de chaque téléphone depuis l'appareil concerné, partage de position révocable, carte OpenStreetMap et affichage des 20 dernières positions.

## Configuration Firebase (à faire une fois)

1. Installez Flutter, le SDK Firebase et FlutterFire CLI :
   ```bash
   dart pub global activate flutterfire_cli
   firebase login
   ```
2. À la racine du projet, générez les plateformes et la configuration pour vos propres projets Firebase :
   ```bash
   flutter create --project-name lost_phone --platforms android,ios .
   flutterfire configure
   flutter pub get
   ```
   `flutterfire configure` crée `lib/firebase_options.dart` et configure Android/iOS. Ce fichier identifie votre projet Firebase ; ne publiez jamais de clé de compte de service ou de secret serveur dans l'application.
3. Dans Firebase Console, activez **Authentication → Sign-in method → Email/Password**.
4. Créez une base **Cloud Firestore** et publiez les règles du fichier `firestore.rules` (ou déployez avec `firebase deploy --only firestore:rules`). Ne lancez pas la base en mode test/public.
5. Pour Android, assurez-vous que `android/app/src/main/AndroidManifest.xml` contient avant `<application>` :
   ```xml
   <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />
   <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />
   ```
6. Pour iOS, ajoutez dans `ios/Runner/Info.plist` :
   ```xml
   <key>NSLocationWhenInUseUsageDescription</key>
   <string>Votre position sert à retrouver cet appareil lorsque vous le demandez.</string>
   ```
7. Lancez `flutter run`. iOS nécessite macOS et Xcode.

## Utilisation

- Créez un compte ou connectez-vous.
- Sur chaque téléphone que vous possédez, connectez-vous au même compte et appuyez sur **Associer cet appareil** depuis ce téléphone.
- Pour autoriser sa position, choisissez cet appareil et appuyez sur **Activer le partage** puis acceptez la permission système.
- Consultez la carte et l'historique récent depuis un autre appareil connecté au compte.
- **Arrêter et révoquer le partage** coupe le flux GPS et empêche l'écriture de nouvelles positions. L'historique peut être effacé depuis l'écran.

Le partage de localisation s'exécute uniquement au premier plan dans cette version. Il n'y a pas de suivi caché, de localisation d'un tiers sans son accord ni de garantie si le réseau, le GPS ou l'application n'est pas disponible. Le prototype n'inclut pas la récupération de compte, la vérification d'adresse, App Check, l'export ni la suppression complète d'un compte.

## Sécurité et confidentialité

- Les règles Firestore limitent les lectures/écritures au propriétaire authentifié et exigent un partage activé pour créer des points d'historique. Les règles ne remplacent pas un audit avant publication.
- Configurez des mots de passe robustes, les méthodes de récupération de compte et les alertes de budget Firebase. N'ajoutez aucune clé de compte de service à l'application.
- Définissez et publiez une politique de confidentialité et une durée de conservation adaptée avant diffusion. L'historique contient des données de localisation sensibles ; limitez les accès administratifs et supprimez les données lorsqu'elles ne sont plus nécessaires.
- Respectez les demandes de permission et les exigences des boutiques Apple/Google. Cette version ne demande pas l'accès en arrière-plan.
- Les tuiles cartographiques utilisent OpenStreetMap. Consultez les conditions du fournisseur pour un usage en production et envisagez un fournisseur de tuiles adapté à votre trafic.

## Architecture

Firebase Authentication pour les comptes et Cloud Firestore pour les appareils et positions (backend managé, sans API Node.js séparée). Données : `users/{uid}/devices/{deviceId}` et sous-collection `locations`. Aucun secret serveur n'est embarqué dans l'application.
