import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:geolocator/geolocator.dart';

import '../../domain/entities/geo_trigger.dart';
import '../../domain/entities/geo_path.dart';
// service locator not required here; triggers are passed in via constructor

/// Widget reutilizable que pinta triggers (marcadores) y los radios como polígonos
/// además de mostrar la posición actual del dispositivo.
class TriggerMapWidget extends StatefulWidget {
  final List<GeoPath> paths;
  final List<GeoTrigger> triggers;
  /// Radio global usado para pintar triggers (ignora el guardado en BD si se provee).
  final double? triggerRadius;
  /// Radio de activación del usuario (círculo morado).
  final double activationRadius;
  const TriggerMapWidget({required this.paths, required this.triggers, this.triggerRadius, this.activationRadius = 15.0, super.key});

  @override
  State<TriggerMapWidget> createState() => _TriggerMapWidgetState();
}

class _TriggerMapWidgetState extends State<TriggerMapWidget> {
  final MapController _mapController = MapController();
  ll.LatLng? _userPos;
  double _userAccuracy = 0;
  StreamSubscription<Position>? _posSub;
  bool _hasLocationPermission = false;
  bool _permissionPermanentlyDenied = false;
  ll.LatLng? _initialCenter;
  final double _initialZoom = 15;
  bool _userInteracted = false;

  @override
  void initState() {
    super.initState();
    if (widget.triggers.isNotEmpty) {
      final avgLat = widget.triggers.map((t) => t.latitude).reduce((a, b) => a + b) / widget.triggers.length;
      final avgLon = widget.triggers.map((t) => t.longitude).reduce((a, b) => a + b) / widget.triggers.length;
      _initialCenter = ll.LatLng(avgLat, avgLon);
    }
    _initLocation();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      if (perm == LocationPermission.denied) {
        // Temporarily denied
        if (mounted) {
          setState(() {
            _hasLocationPermission = false;
          });
        }
        return;
      }
        if (perm == LocationPermission.deniedForever) {
          // Permanently denied -> guide user to settings
          if (mounted) {
            setState(() {
              _hasLocationPermission = false;
              _permissionPermanentlyDenied = true;
            });
          }
          return;
        }

      // granted (either whileInUse or always)
      if (mounted) {
        setState(() {
          _hasLocationPermission = true;
          _permissionPermanentlyDenied = false;
        });
      }

      final pos = await Geolocator.getCurrentPosition();
      if (mounted) {
        setState(() {
          _userPos = ll.LatLng(pos.latitude, pos.longitude);
          _userAccuracy = pos.accuracy;
          _initialCenter ??= _userPos;
        });
        if (!_userInteracted && _userPos != null) {
          _mapController.move(_userPos!, _initialZoom);
        }
      }

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 5),
      ).listen((p) {
        if (!mounted) {
          return;
        }
        setState(() {
          _userPos = ll.LatLng(p.latitude, p.longitude);
          _userAccuracy = p.accuracy;
        });
        if (!_userInteracted && _userPos != null) {
          _mapController.move(_userPos!, _initialZoom);
        }
      }, onError: (_) {});
    } catch (_) {}
  }

  Future<void> _requestPermission() async {
    final perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.deniedForever) {
      if (mounted) {
        setState(() {
          _hasLocationPermission = false;
          _permissionPermanentlyDenied = true;
        });
      }
      return;
    }
    if (perm == LocationPermission.denied) {
      if (mounted) {
        setState(() {
          _hasLocationPermission = false;
        });
      }
      return;
    }
    // granted
    if (mounted) {
      setState(() {
        _hasLocationPermission = true;
        _permissionPermanentlyDenied = false;
      });
    }
    await _initLocation();
  }

  // Convierte grados a radianes
  double _degToRad(double deg) => deg * math.pi / 180.0;
  double _radToDeg(double rad) => rad * 180.0 / math.pi;

  /// Aproxima un círculo geodésico como una poligonal en lat/lon
  List<ll.LatLng> _circlePolygon(double lat, double lon, double radiusMeters, {int points = 40}) {
    final List<ll.LatLng> pts = [];
    const double R = 6371000.0; // radio medio tierra en metros
    final double latRad = _degToRad(lat);
    final double lonRad = _degToRad(lon);
    final double dDivR = radiusMeters / R;
    for (int i = 0; i < points; i++) {
      final double bearing = 2 * math.pi * i / points;
      final double lat2 = math.asin(math.sin(latRad) * math.cos(dDivR) + math.cos(latRad) * math.sin(dDivR) * math.cos(bearing));
      final double lon2 = lonRad + math.atan2(
        math.sin(bearing) * math.sin(dDivR) * math.cos(latRad),
        math.cos(dDivR) - math.sin(latRad) * math.sin(lat2),
      );
      pts.add(ll.LatLng(_radToDeg(lat2), _radToDeg(lon2)));
    }
    return pts;
  }

  @override
  Widget build(BuildContext context) {
    // Polígonos para radios de triggers
    final polygons = <Polygon>[];
    // Índice de paths para lookup rápido al tocar marcador
    final pathByUuid = {for (final p in widget.paths) p.uuid: p};
    for (final t in widget.triggers) {
      final radius = widget.triggerRadius ?? t.radiusMeters;
      final poly = _circlePolygon(t.latitude, t.longitude, radius, points: 32);
      polygons.add(Polygon(points: poly, color: const Color.fromRGBO(33, 150, 243, 0.12), borderColor: const Color.fromRGBO(33, 150, 243, 0.6), borderStrokeWidth: 1.0));
    }

    // Marcadores de triggers
    final markers = <Marker>[];
    for (final t in widget.triggers) {
      markers.add(Marker(
        width: 36,
        height: 36,
        point: ll.LatLng(t.latitude, t.longitude),
        child: GestureDetector(
          onTap: () {
            final pathName = pathByUuid[t.pathUuid]?.name ?? 'Path ${t.pathUuid}';
            final triggerName = t.name.isNotEmpty ? t.name : 'Trigger ${t.uuid}';
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$triggerName • $pathName'), duration: const Duration(seconds: 2)),
            );
          },
          child: const Icon(Icons.location_on, color: Colors.red, size: 28),
        ),
      ));
    }

    // marcador y precisión del usuario
    if (_userPos != null) {
      // Radio de activación (morado)
      final activationPoly = _circlePolygon(_userPos!.latitude, _userPos!.longitude, widget.activationRadius, points: 32);
      polygons.add(Polygon(
        points: activationPoly, 
        color: const Color.fromRGBO(156, 39, 176, 0.15), 
        borderColor: const Color.fromRGBO(156, 39, 176, 0.8),
        borderStrokeWidth: 2.0,
      ));
      
      markers.add(Marker(
        width: 36,
        height: 36,
        point: ll.LatLng(_userPos!.latitude, _userPos!.longitude),
        child: const Icon(Icons.my_location, color: Colors.green, size: 26),
      ));
  final accPoly = _circlePolygon(_userPos!.latitude, _userPos!.longitude, _userAccuracy, points: 24);
  polygons.add(Polygon(points: accPoly, color: const Color.fromRGBO(76, 175, 80, 0.12), borderColor: const Color.fromRGBO(76, 175, 80, 0.5)));
    }

    // Centro inicial: usuario cuando esté disponible; si no, promedio de triggers o (0,0)
    final ll.LatLng initialCenter = _initialCenter ?? _userPos ?? const ll.LatLng(0, 0);

    final permissionBanner = !_hasLocationPermission
        ? Container(
            width: double.infinity,
            color: Colors.orange.shade50,
            padding: const EdgeInsets.all(8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(
                child: Text(
                  _permissionPermanentlyDenied
                      ? 'Permiso de ubicación denegado permanentemente. Abra ajustes para permitir.'
                      : 'La app necesita permiso de ubicación para mostrar tu posición.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              if (!_permissionPermanentlyDenied)
                ElevatedButton(onPressed: _requestPermission, child: const Text('Permitir'))
              else
                ElevatedButton(onPressed: () => Geolocator.openAppSettings(), child: const Text('Abrir ajustes'))
            ]),
          )
        : const SizedBox.shrink();

    return Column(children: [
      permissionBanner,
      Card(
        child: SizedBox(
          height: 180,
          child: FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: initialCenter,
              initialZoom: _initialZoom,
              onMapEvent: (event) {
                if (event.source == MapEventSource.onDrag || 
                    event.source == MapEventSource.onMultiFinger ||
                    event.source == MapEventSource.scrollWheel) {
                  setState(() => _userInteracted = true);
                }
              },
            ),
            children: [
              TileLayer(urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', subdomains: const ['a', 'b', 'c'], userAgentPackageName: 'com.tropicalponcho.cingula_app'),
              if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
              if (markers.isNotEmpty) MarkerLayer(markers: markers),
            ],
          ),
        ),
      ),
    ]);
  }
}
