import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/providers/app_providers.dart';
import '../../../core/models/zone_model.dart';
import '../../../core/enums/zone_type.dart';

class DrawZoneScreen extends ConsumerStatefulWidget {
  final ZoneModel? existingZone;

  const DrawZoneScreen({super.key, this.existingZone});

  @override
  ConsumerState<DrawZoneScreen> createState() => _DrawZoneScreenState();
}

class _DrawZoneScreenState extends ConsumerState<DrawZoneScreen> {
  final MapController _mapController = MapController();
  
  // Form State
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _radiusController = TextEditingController();
  ZoneType _selectedType = ZoneType.safe;
  List<String> _selectedVehicleIds = [];
  
  // Map State
  static const _initialCenter = LatLng(9.0820, 8.6753);
  LatLng? _zoneCenter;
  double _radiusKm = 1.0;
  @override
  void initState() {
    super.initState();
    if (widget.existingZone != null) {
      final z = widget.existingZone!;
      _nameController.text = z.zoneName;
      _radiusKm = z.radiusMeters / 1000;
      _radiusController.text = _radiusKm.toStringAsFixed(1);
      _selectedType = z.zoneType;
      _selectedVehicleIds = List.from(z.assignedVehicleIds);
      _zoneCenter = LatLng(z.centerLatitude, z.centerLongitude);
    } else {
      _radiusController.text = '1.0';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  void _saveZone() async {
    if (_formKey.currentState!.validate()) {
      if (_zoneCenter == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please tap the map to set a zone center!')),
        );
        return;
      }

      final zoneModel = ZoneModel(
        zoneId: widget.existingZone?.zoneId ?? 'ZONE-${DateTime.now().millisecondsSinceEpoch}',
        zoneName: _nameController.text,
        centerLatitude: _zoneCenter!.latitude,
        centerLongitude: _zoneCenter!.longitude,
        radiusMeters: _radiusKm * 1000,
        zoneType: _selectedType,
        shapeType: ShapeType.circle,
        assignedVehicleIds: _selectedVehicleIds,
        createdAt: widget.existingZone?.createdAt ?? DateTime.now(),
      );

      try {
        if (widget.existingZone != null) {
          await ref.read(zonesProvider.notifier).updateZone(zoneModel);
        } else {
          await ref.read(zonesProvider.notifier).addZone(zoneModel);
        }
        
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${zoneModel.zoneName} saved successfully!'), backgroundColor: AppColors.success),
        );
        Navigator.pop(context);
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save zone: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vehiclesAsync = ref.watch(vehiclesProvider);
    final allVehicles = vehiclesAsync.value ?? [];
    final zonesAsync = ref.watch(zonesProvider);
    final existingZones = zonesAsync.value ?? [];

    final List<CircleMarker> circles = [];
    
    // Add existing zones to map
    for (final zone in existingZones) {
      // Skip the one we are currently editing so it doesn't double-render
      if (widget.existingZone?.zoneId == zone.zoneId) continue;

      circles.add(
        CircleMarker(
          point: LatLng(zone.centerLatitude, zone.centerLongitude),
          radius: zone.radiusMeters,
          color: zone.zoneType.color.withOpacity(0.15),
          borderColor: zone.zoneType.color.withOpacity(0.5),
          borderStrokeWidth: 2,
          useRadiusInMeter: true,
        ),
      );
    }

    // Add the active preview zone we are drawing/editing
    if (_zoneCenter != null) {
      circles.add(
        CircleMarker(
          point: _zoneCenter!,
          radius: _radiusKm * 1000,
          color: _selectedType.color.withOpacity(0.2),
          borderColor: _selectedType.color,
          borderStrokeWidth: 2,
          useRadiusInMeter: true,
        ),
      );
    }

    final List<Marker> markers = [];
    if (_zoneCenter != null) {
      markers.add(
        Marker(
          point: _zoneCenter!,
          width: 40,
          height: 40,
          child: Icon(
            Icons.location_on,
            size: 40,
            color: _selectedType == ZoneType.safe ? Colors.green : Colors.red,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existingZone != null ? 'Edit Zone' : 'Draw Zone'),
        backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
        foregroundColor: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
        iconTheme: IconThemeData(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
        elevation: 0,
        actions: [
          TextButton(
            onPressed: _saveZone,
            child: Text(
              'Save',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // Map View
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: _zoneCenter ?? _initialCenter,
                    initialZoom: _zoneCenter != null ? 14.0 : 6.0,
                    onTap: (tapPosition, latLng) {
                      setState(() {
                        _zoneCenter = latLng;
                      });
                    },
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.pathfinder.app',
                    ),
                    if (circles.isNotEmpty) CircleLayer(circles: circles),
                    if (markers.isNotEmpty) MarkerLayer(markers: markers),
                  ],
                ),
                
                // Instructions Overlay
                if (_zoneCenter == null)
                  Positioned(
                    top: 16,
                    left: 16,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceDark.withOpacity(0.9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        'Tap anywhere on the map to place the zone center.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                // Map controls
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'zoomInDrawZone',
                        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                        onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom + 1),
                        child: Icon(Icons.add, color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'zoomOutDrawZone',
                        backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                        onPressed: () => _mapController.move(_mapController.camera.center, _mapController.camera.zoom - 1),
                        child: Icon(Icons.remove, color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Scrollable Settings Panel
          Expanded(
            flex: 3,
            child: Container(
              color: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Name & Type
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _nameController,
                              style: TextStyle(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                              decoration: InputDecoration(
                                labelText: 'Zone Name',
                                filled: true,
                                fillColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              validator: (value) => value == null || value.isEmpty ? 'Required' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: DropdownButton<ZoneType>(
                                value: _selectedType,
                                dropdownColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                                items: ZoneType.values.map((type) {
                                  return DropdownMenuItem(
                                    value: type,
                                    child: Text(
                                      type.displayName,
                                      style: TextStyle(
                                        color: type.color,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                }).toList(),
                                onChanged: (val) {
                                  if (val != null) setState(() => _selectedType = val);
                                },
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Editable Radius
                      Text(
                        'Zone Radius (KM)',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Builder(
                              builder: (context) {
                                double sliderVal = _radiusKm;
                                if (sliderVal < 1.0) sliderVal = 1.0;
                                if (sliderVal > 10000.0) sliderVal = 10000.0;
                                
                                return Slider(
                                  value: sliderVal,
                                  min: 1.0,
                                  max: 10000.0,
                                  activeColor: _selectedType.color,
                                  onChanged: (value) {
                                    setState(() {
                                      _radiusKm = value;
                                      _radiusController.text = value.toStringAsFixed(1);
                                    });
                                  },
                                );
                              }
                            ),
                          ),
                          SizedBox(
                            width: 80,
                            child: TextFormField(
                              controller: _radiusController,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: TextStyle(color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (val) {
                                final d = double.tryParse(val);
                                // Minimum 0.05 KM (50 meters) so it doesn't completely break
                                if (d != null && d >= 0.05) {
                                  setState(() {
                                    _radiusKm = d;
                                  });
                                }
                              },
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Vehicle Assignment
                      Text(
                        'Assigned Vehicles',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? AppColors.dividerDark : AppColors.dividerLight),
                        ),
                        child: ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: allVehicles.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1, 
                            color: isDark ? AppColors.dividerDark : AppColors.dividerLight
                          ),
                          itemBuilder: (context, index) {
                            final v = allVehicles[index];
                            final isSelected = _selectedVehicleIds.contains(v.vehicleId);
                            return CheckboxListTile(
                              title: Text(
                                v.vehicleName,
                                style: TextStyle(
                                  color: isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                v.plateNumber,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight,
                                ),
                              ),
                              activeColor: AppColors.primary,
                              value: isSelected,
                              onChanged: (val) {
                                setState(() {
                                  if (val == true) {
                                    _selectedVehicleIds.add(v.vehicleId);
                                  } else {
                                    _selectedVehicleIds.remove(v.vehicleId);
                                  }
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),
            ),
          )
        ],
      ),
    );
  }
}
