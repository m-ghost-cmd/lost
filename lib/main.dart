import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Generate firebase_options.dart using `flutterfire configure` (see README).
import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const LostPhoneApp());
}

class LostPhoneApp extends StatelessWidget {
  const LostPhoneApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Retrouve mon téléphone',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const AuthGate(),
      );
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return snapshot.data == null
              ? const SignInPage()
              : DeviceDashboard(user: snapshot.data!);
        },
      );
}

class SignInPage extends StatefulWidget {
  const SignInPage({super.key});

  @override
  State<SignInPage> createState() => _SignInPageState();
}

class _SignInPageState extends State<SignInPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _isCreatingAccount = false;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() { _busy = true; _error = null; });
    try {
      final auth = FirebaseAuth.instance;
      if (_isCreatingAccount) {
        await auth.createUserWithEmailAndPassword(
          email: _email.text.trim(), password: _password.text,
        );
      } else {
        await auth.signInWithEmailAndPassword(
          email: _email.text.trim(), password: _password.text,
        );
      }
    } on FirebaseAuthException catch (e) {
      setState(() => _error = switch (e.code) {
        'email-already-in-use' => 'Cette adresse est déjà utilisée.',
        'invalid-email' => 'Adresse e-mail invalide.',
        'weak-password' => 'Choisissez un mot de passe plus robuste.',
        'user-not-found' || 'wrong-password' || 'invalid-credential' => 'Identifiants incorrects.',
        _ => 'Connexion impossible (${e.code}).',
      });
    } catch (_) {
      setState(() => _error = 'Une erreur est survenue. Réessayez.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Retrouve mon téléphone')),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Icon(Icons.location_searching, size: 64),
                const SizedBox(height: 12),
                Text(_isCreatingAccount ? 'Créer un compte' : 'Connexion',
                    style: Theme.of(context).textTheme.headlineSmall,
                    textAlign: TextAlign.center),
                const SizedBox(height: 24),
                TextFormField(
                  controller: _email,
                  decoration: const InputDecoration(labelText: 'Adresse e-mail', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  validator: (v) => v == null || !v.contains('@') ? 'Entrez une adresse e-mail valide.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _password,
                  decoration: const InputDecoration(labelText: 'Mot de passe', border: OutlineInputBorder()),
                  obscureText: true,
                  validator: (v) => v == null || v.length < 8 ? '8 caractères minimum.' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ],
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _busy ? null : _submit,
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
                      : Text(_isCreatingAccount ? 'Créer mon compte' : 'Se connecter'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(() {
                    _isCreatingAccount = !_isCreatingAccount;
                    _error = null;
                  }),
                  child: Text(_isCreatingAccount ? 'J’ai déjà un compte' : 'Créer un compte'),
                ),
                const Text('La position ne sera partagée qu’après votre action et votre autorisation.',
                    textAlign: TextAlign.center),
              ]),
            ),
          ),
        ),
      );
}

class DeviceDashboard extends StatefulWidget {
  const DeviceDashboard({required this.user, super.key});
  final User user;

  @override
  State<DeviceDashboard> createState() => _DeviceDashboardState();
}

class _DeviceDashboardState extends State<DeviceDashboard> {
  StreamSubscription<Position>? _locationSubscription;
  String? _selectedDeviceId;
  String? _localDeviceId;
  bool _busy = false;
  DateTime? _lastWriteAt;
  Position? _lastWrittenPosition;

  CollectionReference<Map<String, dynamic>> get _devices => FirebaseFirestore.instance
      .collection('users').doc(widget.user.uid).collection('devices');

  @override
  void initState() {
    super.initState();
    _loadLocalDevice();
  }

  Future<void> _loadLocalDevice() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    if (prefs.getString('device_owner') == widget.user.uid) {
      setState(() => _localDeviceId = prefs.getString('local_device_id'));
    }
  }

  Future<void> _registerThisPhone() async {
    final name = TextEditingController(text: 'Mon téléphone');
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Associer cet appareil'),
        content: TextField(controller: name, maxLength: 40, decoration: const InputDecoration(labelText: 'Nom de l’appareil')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, name.text.trim()), child: const Text('Associer')),
        ],
      ),
    );
    name.dispose();
    if (label == null || label.trim().isEmpty) return;
    try {
      final ref = _devices.doc();
      await ref.set({
        'ownerUid': widget.user.uid,
        'label': label.trim(),
        'createdAt': FieldValue.serverTimestamp(),
        'sharingEnabled': false,
      });
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('local_device_id', ref.id);
      await prefs.setString('device_owner', widget.user.uid);
      if (mounted) setState(() { _localDeviceId = ref.id; _selectedDeviceId = ref.id; });
    } catch (_) {
      _showMessage('Impossible d’associer l’appareil. Vérifiez la configuration Firebase.');
    }
  }

  Future<void> _startSharing() async {
    final id = _selectedDeviceId;
    if (id == null || id != _localDeviceId) {
      _showMessage('Pour partager, associez d’abord cet appareil sur ce téléphone.');
      return;
    }
    if (!await Geolocator.isLocationServiceEnabled()) {
      _showMessage('Activez la localisation dans les réglages.');
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
      _showMessage('Autorisation de localisation non accordée.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _devices.doc(id).update({'sharingEnabled': true});
      await _locationSubscription?.cancel();
      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 25),
      ).listen((position) => _writePosition(id, position), onError: (_) => _showMessage('Position indisponible.'));
    } catch (_) {
      _showMessage('Impossible de démarrer le partage.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _writePosition(String deviceId, Position position) async {
    final now = DateTime.now();
    final last = _lastWrittenPosition;
    if (_lastWriteAt != null && now.difference(_lastWriteAt!) < const Duration(seconds: 15) &&
        last != null && Geolocator.distanceBetween(last.latitude, last.longitude, position.latitude, position.longitude) < 25) return;
    _lastWriteAt = now;
    _lastWrittenPosition = position;
    final devices = _devices.doc(deviceId);
    final point = {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'timestamp': Timestamp.fromDate(now.toUtc()),
    };
    try {
      await devices.update({'latest': point, 'lastSeenAt': FieldValue.serverTimestamp()});
      await devices.collection('locations').add(point);
    } catch (_) {
      _showMessage('Échec de l’enregistrement de la position.');
    }
  }

  Future<void> _stopSharing(String deviceId) async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    try {
      await _devices.doc(deviceId).update({'sharingEnabled': false});
      if (mounted) _showMessage('Partage de position arrêté.');
    } catch (_) {
      _showMessage('Impossible de mettre à jour le partage.');
    }
  }

  Future<void> _clearHistory(String deviceId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Effacer l’historique ?'),
        content: const Text('Cette action supprime l’historique de position de cet appareil. La dernière position affichée est conservée.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Effacer')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final locations = _devices.doc(deviceId).collection('locations');
      while (true) {
        final page = await locations.limit(400).get();
        if (page.docs.isEmpty) break;
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in page.docs) { batch.delete(doc.reference); }
        await batch.commit();
      }
      if (mounted) _showMessage('Historique effacé.');
    } catch (_) {
      _showMessage('Impossible d’effacer l’historique.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _locationSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mes appareils'),
        actions: [IconButton(tooltip: 'Se déconnecter', onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout))],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _devices.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Erreur de chargement. Vérifiez les règles Firestore.'));
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          final devices = snapshot.data!.docs;
          if (devices.isEmpty) return _emptyState();
          final selected = devices.any((d) => d.id == _selectedDeviceId) ? _selectedDeviceId! : devices.first.id;
          if (_selectedDeviceId != selected) WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _selectedDeviceId = selected);
          });
          final selectedDoc = devices.firstWhere((d) => d.id == selected);
          final data = selectedDoc.data();
          final sharing = data['sharingEnabled'] == true;
          final isThisPhone = selected == _localDeviceId;
          return ListView(padding: const EdgeInsets.all(16), children: [
            Text('Connecté : ${widget.user.email ?? widget.user.uid}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: selected,
              decoration: const InputDecoration(labelText: 'Appareil', border: OutlineInputBorder()),
              items: devices.map((d) => DropdownMenuItem(value: d.id, child: Text((d.data()['label'] as String?) ?? 'Appareil'))).toList(),
              onChanged: (value) => setState(() => _selectedDeviceId = value),
            ),
            const SizedBox(height: 12),
            if (data['latest'] is Map<String, dynamic>) _LocationMap(latest: Map<String, dynamic>.from(data['latest'] as Map))
            else const Card(child: SizedBox(height: 220, child: Center(child: Text('Aucune position connue')))),
            const SizedBox(height: 8),
            Text(sharing ? 'Partage activé' : 'Partage arrêté', style: TextStyle(color: sharing ? Colors.green : null)),
            TextButton.icon(
              onPressed: isThisPhone ? () => _clearHistory(selected) : null,
              icon: const Icon(Icons.delete_sweep), label: const Text('Effacer l’historique de cet appareil'),
            ),
            Text('Historique récent', style: Theme.of(context).textTheme.titleMedium),
            _HistoryList(locations: _devices.doc(selected).collection('locations')),
            const SizedBox(height: 16),
            if (isThisPhone && !sharing)
              FilledButton.icon(onPressed: _busy ? null : _startSharing, icon: const Icon(Icons.share_location), label: const Text('Activer le partage de cet appareil')),
            if (isThisPhone && sharing)
              OutlinedButton.icon(onPressed: () => _stopSharing(selected), icon: const Icon(Icons.stop), label: const Text('Arrêter et révoquer le partage')),
            if (!isThisPhone)
              const Text('Consultation uniquement. Pour partager un autre appareil, connectez-vous dessus et associez-le volontairement.'),
            const SizedBox(height: 8),
            OutlinedButton.icon(onPressed: _registerThisPhone, icon: const Icon(Icons.add), label: const Text('Associer cet appareil')),
            const SizedBox(height: 20),
            const Text('Le partage fonctionne lorsque cette application est ouverte. Pas de suivi caché ni de localisation en arrière-plan dans ce prototype.'),
          ]);
        },
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.phone_android, size: 56),
            const SizedBox(height: 12),
            const Text('Associez ce téléphone pour commencer. Chaque appareil doit être ajouté depuis l’appareil concerné.'),
            const SizedBox(height: 16),
            FilledButton.icon(onPressed: _registerThisPhone, icon: const Icon(Icons.add), label: const Text('Associer cet appareil')),
          ]),
        ),
      );
}

class _LocationMap extends StatelessWidget {
  const _LocationMap({required this.latest});
  final Map<String, dynamic> latest;

  @override
  Widget build(BuildContext context) {
    final latitude = (latest['latitude'] as num?)?.toDouble();
    final longitude = (latest['longitude'] as num?)?.toDouble();
    if (latitude == null || longitude == null) return const SizedBox(height: 220, child: Center(child: Text('Position invalide')));
    final point = LatLng(latitude, longitude);
    return SizedBox(
      height: 260,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: FlutterMap(
          options: MapOptions(initialCenter: point, initialZoom: 15),
          children: [
            TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.lost_phone'),
            MarkerLayer(markers: [Marker(point: point, width: 48, height: 48, child: const Icon(Icons.location_pin, color: Colors.red, size: 44))]),
            RichAttributionWidget(attributions: [TextSourceAttribution('© OpenStreetMap contributors')]),
          ],
        ),
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.locations});
  final CollectionReference<Map<String, dynamic>> locations;

  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: locations.orderBy('timestamp', descending: true).limit(20).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Text('Historique indisponible.');
          if (!snapshot.hasData) return const LinearProgressIndicator();
          if (snapshot.data!.docs.isEmpty) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Text('Aucun historique pour le moment.'));
          return Column(children: snapshot.data!.docs.map((doc) {
            final data = doc.data();
            final lat = (data['latitude'] as num?)?.toDouble();
            final lon = (data['longitude'] as num?)?.toDouble();
            final timestamp = data['timestamp'];
            final time = timestamp is Timestamp ? timestamp.toDate().toLocal().toString() : 'Heure inconnue';
            return ListTile(dense: true, leading: const Icon(Icons.place), title: Text('${lat?.toStringAsFixed(5) ?? '—'}, ${lon?.toStringAsFixed(5) ?? '—'}'), subtitle: Text(time));
          }).toList());
        },
      );
}
