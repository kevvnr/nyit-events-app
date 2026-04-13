import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:map_launcher/map_launcher.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens walking directions in an installed maps app when possible.
Future<void> openWalkingDirections({
  required BuildContext context,
  required double destinationLat,
  required double destinationLng,
  required String destinationTitle,
  bool useCurrentLocationAsOrigin = true,
}) async {
  Coords? originCoords;
  if (useCurrentLocationAsOrigin) {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        originCoords = null;
      } else {
        final pos = await Geolocator.getCurrentPosition();
        originCoords = Coords(pos.latitude, pos.longitude);
      }
    } catch (_) {
      originCoords = null;
    }
  }

  try {
    final maps = await MapLauncher.installedMaps;
    if (maps.isEmpty) {
      if (context.mounted) {
        await _fallbackUrlLaunch(
          destinationLat,
          destinationLng,
          context,
        );
      }
      return;
    }

    if (!context.mounted) return;

    if (maps.length == 1) {
      await maps.first.showDirections(
        destination: Coords(destinationLat, destinationLng),
        destinationTitle: destinationTitle,
        origin: originCoords,
        originTitle: originCoords != null ? 'Your location' : null,
        directionsMode: DirectionsMode.walking,
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Open directions in…',
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
            ),
            ...maps.map(
              (m) => ListTile(
                leading: const Icon(Icons.map_rounded),
                title: Text(m.mapName),
                onTap: () async {
                  Navigator.pop(ctx);
                  await m.showDirections(
                    destination:
                        Coords(destinationLat, destinationLng),
                    destinationTitle: destinationTitle,
                    origin: originCoords,
                    originTitle:
                        originCoords != null ? 'Your location' : null,
                    directionsMode: DirectionsMode.walking,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      await _fallbackUrlLaunch(
        destinationLat,
        destinationLng,
        context,
      );
    }
  }
}

Future<void> _fallbackUrlLaunch(
  double lat,
  double lng,
  BuildContext context,
) async {
  final googleUrl = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=walking',
  );
  final appleUrl = Uri.parse(
    'https://maps.apple.com/?daddr=$lat,$lng&dirflg=d&t=m',
  );
  try {
    if (await canLaunchUrl(googleUrl)) {
      await launchUrl(googleUrl, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(appleUrl)) {
      await launchUrl(appleUrl, mode: LaunchMode.externalApplication);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open any maps app.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps.')),
      );
    }
  }
}
