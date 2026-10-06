import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../env.dart';
import '../theme/app_theme.dart';

enum PinKind { you, mechanic, workshop, centre }

class MapPin {
  final LatLng point;
  final PinKind kind;
  final String? label;
  const MapPin(this.point, this.kind, {this.label});
}

/// OpenStreetMap-based map (no Google billing needed). See Env.mapTileUrl.
class AppMap extends StatelessWidget {
  final MapController? controller;
  final LatLng center;
  final double zoom;
  final List<MapPin> pins;
  final List<LatLng>? route;
  final bool interactive;
  final void Function()? onReady;

  const AppMap({
    super.key,
    this.controller,
    required this.center,
    this.zoom = 14,
    this.pins = const [],
    this.route,
    this.interactive = true,
    this.onReady,
  });

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: controller,
      options: MapOptions(
        initialCenter: center,
        initialZoom: zoom,
        backgroundColor: const Color(0xFFE8EAE4),
        onMapReady: onReady,
        interactionOptions: InteractionOptions(
          flags: interactive ? (InteractiveFlag.all & ~InteractiveFlag.rotate) : InteractiveFlag.none,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: Env.mapTileUrl,
          userAgentPackageName: 'io.autowave.app',
          maxZoom: 19,
        ),
        if (route != null && route!.length > 1)
          PolylineLayer(polylines: [
            Polyline(points: route!, strokeWidth: 7, color: Colors.white),
            Polyline(points: route!, strokeWidth: 4.5, color: AppColors.ink),
          ]),
        MarkerLayer(
          markers: [
            for (final p in pins)
              Marker(
                point: p.point,
                width: p.kind == PinKind.mechanic ? 52 : 44,
                height: p.kind == PinKind.mechanic ? 52 : 44,
                child: _PinView(kind: p.kind),
              ),
          ],
        ),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap', style: TextStyle(fontSize: 11)),
          backgroundColor: Color(0xCCFFFFFF),
        ),
      ],
    );
  }
}

class _PinView extends StatelessWidget {
  final PinKind kind;
  const _PinView({required this.kind});

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case PinKind.you:
        return Center(
          child: Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppColors.info,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 4),
              boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8)],
            ),
          ),
        );
      case PinKind.mechanic:
        return Container(
          decoration: BoxDecoration(
            color: AppColors.signal,
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.ink, width: 3),
            boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 10)],
          ),
          child: const Icon(Icons.build_rounded, color: AppColors.ink, size: 24),
        );
      case PinKind.workshop:
        return Container(
          decoration: BoxDecoration(color: AppColors.ink, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
          child: const Icon(Icons.home_repair_service_rounded, color: Colors.white, size: 20),
        );
      case PinKind.centre:
        return Container(
          decoration: BoxDecoration(color: AppColors.go, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3)),
          child: const Icon(Icons.recycling_rounded, color: Colors.white, size: 20),
        );
    }
  }
}
