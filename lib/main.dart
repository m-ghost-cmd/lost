import 'dart:async';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

void main() => runApp(const LostPhoneApp());

class LostPhoneApp extends StatelessWidget {
  const LostPhoneApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Retrouve mon téléphone',
        theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
        home: const LocationPage(),
      );
}

class LocationPage extends StatefulWidget {
  const LocationPage({super.key});

  @override
  State<LocationPage> createState() => _LocationPageState();
}

class _LocationPageState extends State<LocationPage> {
  StreamSubscription<Position>? _subscription;
  Position? _position;
  String _status = 'La localisation est arrêtée.';
  bool _isTracking = false;

  Future<void> _startLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      setState(() => _status = 'Activez la localisation dans les réglages.');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      setState(() => _status = 'Autorisation de localisation non accordée.');
      return;
    }

    await _subscription?.cancel();
    setState(() {
      _isTracking = true;
      _status = 'Partage actif sur cet appareil.';
    });
    _subscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen(
      (position) {
        if (mounted) setState(() => _position = position);
      },
      onError: (_) {
        if (mounted) setState(() => _status = 'Position indisponible.');
      },
    );
  }

  Future<void> _stopLocation() async {
    await _subscription?.cancel();
    _subscription = null;
    if (mounted) {
      setState(() {
        _isTracking = false;
        _status = 'La localisation est arrêtée.';
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    return Scaffold(
      appBar: AppBar(title: const Text('Retrouve mon téléphone')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.location_searching,
                  size: 64, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 16),
              Text(_status, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: position == null
                      ? const Text('Aucune position reçue. Démarrez le partage pour afficher la position de cet appareil.', textAlign: TextAlign.center)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Position actuelle', style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text('Latitude : ${position.latitude.toStringAsFixed(6)}'),
                            Text('Longitude : ${position.longitude.toStringAsFixed(6)}'),
                            Text('Précision : ${position.accuracy.toStringAsFixed(0)} m'),
                            Text('Mise à jour : ${position.timestamp.toLocal()}'),
                          ],
                        ),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed: _isTracking ? null : _startLocation,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Démarrer ma localisation'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _isTracking ? _stopLocation : null,
                icon: const Icon(Icons.stop),
                label: const Text('Arrêter le partage'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
