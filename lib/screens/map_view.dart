import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import '../providers/delivery_provider.dart';
import '../theme/app_theme.dart';
import 'main_shell.dart';

class MapView extends StatefulWidget {
  const MapView({super.key});

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  LatLng _driverLocation = const LatLng(20.5937, 78.9629); // Default India center
  bool _loadingLocation = true;
  MapController? _mapController;
  List<LatLng> _routePoints = [];

  int? _lastActiveOrderId;
  StreamSubscription<Position>? _positionStreamSubscription;
  DeliveryProvider? _deliveryProvider; // Bug 3: store ref for dispose
  Timer? _routeDebounceTimer; // Bug 11: debounce route fetches

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _getDriverLocation();

    // Listen to changes in activeOrder
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deliveryProvider = Provider.of<DeliveryProvider>(context, listen: false);
      _deliveryProvider!.addListener(_onDeliveryProviderChanged);
      _onDeliveryProviderChanged(); // Initial check
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _routeDebounceTimer?.cancel();
    _deliveryProvider?.removeListener(_onDeliveryProviderChanged);
    _mapController?.dispose();
    super.dispose();
  }

  void _onDeliveryProviderChanged() {
    if (!mounted) return;
    final activeOrder = Provider.of<DeliveryProvider>(context, listen: false).activeOrder;
    if (activeOrder?.orderId != _lastActiveOrderId) {
      _lastActiveOrderId = activeOrder?.orderId;
      if (activeOrder != null) {
        _fetchRoute();
      } else {
        setState(() {
          _routePoints = [];
        });
      }
    }
  }

  Future<void> _fetchRoute() async {
    final activeOrder = Provider.of<DeliveryProvider>(context, listen: false).activeOrder;
    if (activeOrder == null ||
        activeOrder.deliveryLatitude == null ||
        activeOrder.deliveryLongitude == null) {
      debugPrint('Cannot fetch route: Active order or coordinates are null.');
      return;
    }

    try {
      final startLng = _driverLocation.longitude;
      final startLat = _driverLocation.latitude;
      final endLng = activeOrder.deliveryLongitude;
      final endLat = activeOrder.deliveryLatitude;

      debugPrint('Fetching route from driver ($startLat, $startLng) to customer ($endLat, $endLng)');

      final url = 'https://router.project-osrm.org/route/v1/driving/$startLng,$startLat;$endLng,$endLat?overview=full&geometries=geojson';
      final response = await http.get(Uri.parse(url));

      debugPrint('OSRM Route Status: ${response.statusCode}');
      debugPrint('OSRM Route Body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['routes'] != null && data['routes'].isNotEmpty) {
          final geometry = data['routes'][0]['geometry'];
          final List<dynamic> coordinates = geometry['coordinates'];
          
          setState(() {
            _routePoints = coordinates.map((coord) {
              return LatLng(coord[1] as double, coord[0] as double);
            }).toList();
          });
          debugPrint('Route loaded successfully: ${_routePoints.length} points.');
        } else {
          debugPrint('No routes found in OSRM response.');
        }
      } else {
        debugPrint('OSRM API returned error code ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching OSRM route: $e');
    }
  }

  // Bug 11: Debounced route fetch
  void _debouncedFetchRoute() {
    _routeDebounceTimer?.cancel();
    _routeDebounceTimer = Timer(const Duration(seconds: 15), () {
      if (mounted) _fetchRoute();
    });
  }

  void _startLiveLocationListening() {
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 5, // Request updates every 5 meters moved
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _driverLocation = LatLng(position.latitude, position.longitude);
        });
        _debouncedFetchRoute();
      }
    });
  }

  Future<void> _getDriverLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location services are disabled. Please enable GPS.'),
              backgroundColor: Colors.red,
            ),
          );
          Geolocator.openLocationSettings();
          setState(() {
            _loadingLocation = false;
          });
        }
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          debugPrint('Location permissions are denied.');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permissions are denied.'),
                backgroundColor: Colors.red,
              ),
            );
            setState(() {
              _loadingLocation = false;
            });
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        debugPrint('Location permissions are permanently denied.');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Location permissions are permanently denied. Please enable in app settings.'),
              backgroundColor: Colors.red,
            ),
          );
          Geolocator.openAppSettings();
          setState(() {
            _loadingLocation = false;
          });
        }
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _driverLocation = LatLng(position.latitude, position.longitude);
          _loadingLocation = false;
        });
        _mapController?.move(_driverLocation, 14.5);
        _fetchRoute();
        _startLiveLocationListening();
      }
    } catch (e) {
      debugPrint('Error getting driver location: $e');
      if (mounted) {
        setState(() {
          _loadingLocation = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final delivery = Provider.of<DeliveryProvider>(context);
    final activeOrder = delivery.activeOrder;

    final markers = <Marker>[];

    // Driver Marker
    if (!_loadingLocation) {
      markers.add(
        Marker(
          point: _driverLocation,
          width: 45,
          height: 45,
          child: Container(
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withAlpha(51),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.primaryColor, width: 2),
            ),
            child: const Center(
              child: Icon(Icons.navigation, color: AppTheme.primaryColor, size: 24),
            ),
          ),
        ),
      );
    }

    // Customer / Stop Marker
    if (activeOrder != null &&
        activeOrder.deliveryLatitude != null &&
        activeOrder.deliveryLongitude != null) {
      final destLatLng = LatLng(activeOrder.deliveryLatitude!, activeOrder.deliveryLongitude!);
      markers.add(
        Marker(
          point: destLatLng,
          width: 45,
          height: 45,
          child: const Icon(
            Icons.location_on,
            color: Colors.red,
            size: 40,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppTheme.primaryColor),
          onPressed: () {
            MainShell.selectTab(context, 0);
          },
        ),
        title: const Text('Active Delivery Map', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _driverLocation,
              initialZoom: 13.0,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.freshinbasket.delivery',
              ),
              if (_routePoints.isNotEmpty)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      color: AppTheme.primaryColor,
                      strokeWidth: 4.5,
                    ),
                  ],
                ),
              if (markers.isNotEmpty) MarkerLayer(markers: markers),
            ],
          ),

          // Active order overlay details card
          if (activeOrder != null)
            Positioned(
              bottom: 20,
              left: 20,
              right: 20,
              child: Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Active Delivery',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade500,
                              letterSpacing: 1.1,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppTheme.successBgColor,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Order #${activeOrder.orderNumber}',
                              style: const TextStyle(
                                color: AppTheme.primaryColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        activeOrder.customerName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        activeOrder.deliveryAddress,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Padding(
        padding: EdgeInsets.only(bottom: activeOrder != null ? 130.0 : 0.0),
        child: FloatingActionButton(
          onPressed: _getDriverLocation,
          backgroundColor: AppTheme.primaryColor,
          child: const Icon(Icons.my_location, color: Colors.white),
        ),
      ),
    );
  }
}
