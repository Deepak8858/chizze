import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';
import '../../core/services/map_config.dart';
import '../../core/theme/theme.dart';

/// Map marker type
enum MapMarkerType {
  restaurant('🍽️', 'Restaurant'),
  rider('🛵', 'Delivery Partner'),
  customer('📍', 'Delivery Location');

  final String emoji;
  final String label;
  const MapMarkerType(this.emoji, this.label);
}

/// Map marker data
class MapMarker {
  final MapMarkerType type;
  final double latitude;
  final double longitude;
  final String? label;

  const MapMarker({
    required this.type,
    required this.latitude,
    required this.longitude,
    this.label,
  });
}

/// Reusable delivery map widget — dark-themed Mapbox map
/// with animated markers for restaurant, rider, and customer
class DeliveryMap extends StatefulWidget {
  /// List of markers to display
  final List<MapMarker> markers;

  /// Route coordinates (list of [lng, lat] pairs)
  final List<List<double>>? routeCoordinates;

  /// Map height
  final double height;

  /// Whether to track rider marker (auto-center)
  final bool trackRider;

  /// Callback when map is ready
  final VoidCallback? onMapReady;

  const DeliveryMap({
    super.key,
    required this.markers,
    this.routeCoordinates,
    this.height = 250,
    this.trackRider = false,
    this.onMapReady,
  });

  @override
  State<DeliveryMap> createState() => _DeliveryMapState();
}

class _DeliveryMapState extends State<DeliveryMap> {
  MapboxMap? _mapboxMap;
  PointAnnotationManager? _annotationManager;
  bool _mapError = false;

  @override
  void initState() {
    super.initState();
    // Safety: re-set Mapbox access token before every map instance to
    // guard against native SDK losing the token on rebuilds / backgrounding.
    MapboxOptions.setAccessToken(MapConfig.accessToken);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.divider.withValues(alpha: 0.3)),
      ),
      clipBehavior: Clip.antiAlias,
      child: _mapError
          ? _buildMapFallback()
          : Stack(
        children: [
          MapWidget(
            key: const ValueKey('delivery_map'),
            mapOptions: MapOptions(
              pixelRatio: MediaQuery.of(context).devicePixelRatio,
            ),
            styleUri: MapConfig.darkStyleUrl,
            cameraOptions: _initialCamera(),
            onMapCreated: _onMapCreated,
                  onMapLoadErrorListener: (MapLoadingErrorEventData error) {
                    debugPrint(
                      '[DeliveryMap] Map load error: ${error.type}, ${error.message}',
                    );
                    if (mounted) setState(() => _mapError = true);
                  },
          ),

          // ─── Gradient overlay at top ───
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 40,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.background.withValues(alpha: 0.6),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // ─── Marker Legend ───
          Positioned(
            bottom: 8,
            left: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: widget.markers.map((m) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          m.type.emoji,
                          style: const TextStyle(fontSize: 12),
                        ),
                        const SizedBox(width: 2),
                        Text(
                          m.label ?? m.type.label,
                          style: AppTypography.caption.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  CameraOptions _initialCamera() {
    // Center on rider if available, else first marker, else default
    MapMarker? center;
    for (final m in widget.markers) {
      if (m.type == MapMarkerType.rider) {
        center = m;
        break;
      }
    }
    center ??= widget.markers.isNotEmpty ? widget.markers.first : null;

    return CameraOptions(
      center: Point(
        coordinates: Position(
          center?.longitude ?? MapConfig.defaultLongitude,
          center?.latitude ?? MapConfig.defaultLatitude,
        ),
      ),
      zoom: widget.trackRider ? MapConfig.trackingZoom : MapConfig.defaultZoom,
    );
  }

  void _onMapCreated(MapboxMap mapboxMap) async {
    _mapboxMap = mapboxMap;

    // Create annotation manager for markers
    _annotationManager = await mapboxMap.annotations
        .createPointAnnotationManager();

    // Add markers
    await _addMarkers();

    // Add route line if provided
    if (widget.routeCoordinates != null &&
        widget.routeCoordinates!.isNotEmpty) {
      await _addRouteLine();
    }

    // Fit camera to show all markers
    if (widget.markers.length > 1) {
      await _fitBounds();
    }

    widget.onMapReady?.call();
  }

  Future<void> _addMarkers() async {
    if (_annotationManager == null) return;

    for (final marker in widget.markers) {
      await _annotationManager!.create(
        PointAnnotationOptions(
          geometry: Point(
            coordinates: Position(marker.longitude, marker.latitude),
          ),
          textField: marker.type.emoji,
          textSize: 24,
          textOffset: [0, -1.5],
          textColor: Colors.white.toARGB32(),
        ),
      );
    }
  }

  Future<void> _addRouteLine() async {
    if (_mapboxMap == null || widget.routeCoordinates == null) return;

    final coordinates = widget.routeCoordinates!
        .map((coord) => Position(coord[0], coord[1]))
        .toList();

    if (coordinates.length < 2) return;

    // Add GeoJSON source for route
    final sourceId = 'route-source';
    final layerId = 'route-layer';

    final geoJson = {
      'type': 'Feature',
      'geometry': {
        'type': 'LineString',
        'coordinates': coordinates.map((p) => [p.lng, p.lat]).toList(),
      },
    };

    await _mapboxMap!.style.addSource(
      GeoJsonSource(id: sourceId, data: jsonEncode(geoJson)),
    );

    await _mapboxMap!.style.addLayer(
      LineLayer(
        id: layerId,
        sourceId: sourceId,
        lineColor: MapConfig.routeLineColor,
        lineWidth: MapConfig.routeLineWidth,
        lineCap: LineCap.ROUND,
        lineJoin: LineJoin.ROUND,
      ),
    );
  }

  Future<void> _fitBounds() async {
    if (_mapboxMap == null || widget.markers.length < 2) return;

    double minLat = 90, maxLat = -90, minLng = 180, maxLng = -180;
    for (final m in widget.markers) {
      if (m.latitude < minLat) minLat = m.latitude;
      if (m.latitude > maxLat) maxLat = m.latitude;
      if (m.longitude < minLng) minLng = m.longitude;
      if (m.longitude > maxLng) maxLng = m.longitude;
    }

    await _mapboxMap!.flyTo(
      CameraOptions(
        center: Point(
          coordinates: Position((minLng + maxLng) / 2, (minLat + maxLat) / 2),
        ),
        zoom: MapConfig.defaultZoom - 1,
        padding: MbxEdgeInsets(top: 60, left: 40, bottom: 60, right: 40),
      ),
      MapAnimationOptions(duration: MapConfig.markerAnimationMs),
    );
  }

  @override
  void didUpdateWidget(DeliveryMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    // When markers change (e.g. rider moves), update annotations
    if (widget.markers != oldWidget.markers) {
      _refreshMarkers();
    }
    // When route coordinates change, refresh the route line
    if (widget.routeCoordinates != oldWidget.routeCoordinates) {
      _refreshRoute();
    }
  }

  Future<void> _refreshRoute() async {
    if (_mapboxMap == null || !mounted) return;
    try {
      // Remove existing route layer and source if present
      final style = _mapboxMap!.style;
      if (await style.styleLayerExists('route-layer')) {
        await style.removeStyleLayer('route-layer');
      }
      if (await style.styleSourceExists('route-source')) {
        await style.removeStyleSource('route-source');
      }
      // Re-add if new coordinates are provided
      if (widget.routeCoordinates != null &&
          widget.routeCoordinates!.isNotEmpty) {
        await _addRouteLine();
      }
    } catch (e) {
      debugPrint('[DeliveryMap] _refreshRoute error: $e');
    }
  }

  Future<void> _refreshMarkers() async {
    if (_annotationManager == null || !mounted) return;
    try {
      await _annotationManager!.deleteAll();
      if (!mounted) return;
      await _addMarkers();
    } catch (e) {
      // Mapbox platform channel can fail if the map surface is disposed
      // while annotations are being updated (FLUTTER-D on Sentry).
      debugPrint('[DeliveryMap] _refreshMarkers error: $e');
      if (mounted) {
        setState(() => _mapError = true);
      }
      return;
    }

    // Re-center on rider if tracking
    if (widget.trackRider && mounted) {
      final rider = widget.markers
          .where((m) => m.type == MapMarkerType.rider)
          .firstOrNull;
      if (rider != null) {
        await _mapboxMap?.flyTo(
          CameraOptions(
            center: Point(
              coordinates: Position(rider.longitude, rider.latitude),
            ),
            zoom: MapConfig.trackingZoom,
          ),
          MapAnimationOptions(duration: MapConfig.markerAnimationMs),
        );
      }
    }
  }

  /// Fallback UI when the native map cannot be loaded (e.g. invalid token).
  Widget _buildMapFallback() {
    return Container(
      color: AppColors.surfaceElevated,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.map_outlined, color: AppColors.textSecondary, size: 48),
            const SizedBox(height: 8),
            Text(
              'Map unavailable',
              style: AppTypography.body2.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Route info is shown below',
              style: AppTypography.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
