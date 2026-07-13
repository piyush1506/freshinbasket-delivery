import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../providers/auth_provider.dart';
import '../providers/delivery_provider.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';
import 'main_shell.dart';
import 'dart:async';
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:math' as math;

class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  LatLng _driverLocation = const LatLng(20.5937, 78.9629); // Default India center
  List<LatLng> _routePoints = [];
  StreamSubscription<Position>? _positionStreamSubscription;
  int? _lastActiveOrderId;
  final MapController _mapController = MapController();
  DeliveryProvider? _deliveryProvider; // Bug 3: store ref for dispose
  Timer? _routeDebounceTimer; // Bug 11: debounce route fetches

  @override
  void initState() {     
    super.initState();
    Future.microtask(() {
      if (mounted) {
        Provider.of<DeliveryProvider>(context, listen: false).fetchDashboard();
        Provider.of<DeliveryProvider>(context, listen: false).fetchAssignedOrders();
        _getDriverLocation();
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _deliveryProvider = Provider.of<DeliveryProvider>(context, listen: false);
      _deliveryProvider!.addListener(_onDeliveryProviderChanged);
      _onDeliveryProviderChanged();
    });
  }

  @override
  void dispose() {
    _positionStreamSubscription?.cancel();
    _routeDebounceTimer?.cancel();
    _mapController.dispose();
    _deliveryProvider?.removeListener(_onDeliveryProviderChanged);
    super.dispose();
  }

  void _fitMapToRouteOrPoints() {
    if (!mounted) return;
    final activeOrder = Provider.of<DeliveryProvider>(context, listen: false).activeOrder;
    final remainingOrders = Provider.of<DeliveryProvider>(context, listen: false).assignedOrders.where((o) => o.status == 'CONFIRMED').toList();

    final List<LatLng> points = [_driverLocation];
    if (activeOrder != null && activeOrder.deliveryLatitude != null && activeOrder.deliveryLongitude != null) {
      points.add(LatLng(activeOrder.deliveryLatitude!, activeOrder.deliveryLongitude!));
      if (_routePoints.isNotEmpty) {
        points.addAll(_routePoints);
      }
    } else {
      for (var o in remainingOrders) {
        if (o.deliveryLatitude != null && o.deliveryLongitude != null) {
          points.add(LatLng(o.deliveryLatitude!, o.deliveryLongitude!));
        }
      }
    }

    if (points.length > 1) {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) {
          try {
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                padding: const EdgeInsets.all(50.0),
              ),
            );
          } catch (e) {
            debugPrint('Error fitting camera: $e');
          }
        }
      });
    }
  }

  void _onDeliveryProviderChanged() {
    if (!mounted) return;
    final activeOrder = Provider.of<DeliveryProvider>(context, listen: false).activeOrder;

    // Bug 4: Removed location tracking toggle — AuthProvider controls it via toggleActiveStatus

    if (activeOrder?.orderId != _lastActiveOrderId) {
      _lastActiveOrderId = activeOrder?.orderId;
      if (activeOrder != null) {
        _fetchRoute();
      } else {
        setState(() {
          _routePoints = [];
        });
        _fitMapToRouteOrPoints();
      }
    }
  }

  Future<void> _fetchRoute() async {
    final activeOrder = Provider.of<DeliveryProvider>(context, listen: false).activeOrder;
    if (activeOrder == null ||
        activeOrder.deliveryLatitude == null ||
        activeOrder.deliveryLongitude == null) {
      return;
    }

    try {
      final startLng = _driverLocation.longitude;
      final startLat = _driverLocation.latitude;
      final endLng = activeOrder.deliveryLongitude;
      final endLat = activeOrder.deliveryLatitude;

      final url = 'https://router.project-osrm.org/route/v1/driving/$startLng,$startLat;$endLng,$endLat?overview=full&geometries=geojson';
      final response = await http.get(Uri.parse(url));

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
          _fitMapToRouteOrPoints();
        }
      }
    } catch (e) {
      debugPrint('Error fetching dashboard route: $e');
    }
  }

  // Bug 11: Debounced route fetch to avoid OSRM API abuse
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
        distanceFilter: 5,
      ),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _driverLocation = LatLng(position.latitude, position.longitude);
        });
        _debouncedFetchRoute();
        _fitMapToRouteOrPoints();
      }
    });
  }

  Future<void> _getDriverLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }

      if (permission == LocationPermission.deniedForever) return;

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _driverLocation = LatLng(position.latitude, position.longitude);
        });
        _fetchRoute();
        _startLiveLocationListening();
        _fitMapToRouteOrPoints();
      }
    } catch (e) {
      debugPrint('Error getting driver location on dashboard: $e');
    }
  }

  Future<void> _makePhoneCall(String phoneNumber) async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: phoneNumber,
    );
    if (await canLaunchUrl(launchUri)) {
      await launchUrl(launchUri);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not launch phone call')),
        );
      }
    }
  }

  void _showOrderItemsDialog(DeliveryOrder order) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Order ${order.orderNumber} Items'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: order.items.length,
            itemBuilder: (context, index) {
              final item = order.items[index];
              return ListTile(
                title: Text(item.productName),
                trailing: Text('${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} ${item.unitName}'),
                subtitle: Text('₹${item.unitPrice} / unit'),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleMarkDelivered(BuildContext context, DeliveryOrder activeOrder, DeliveryProvider delivery) async {
    final bool isCod = activeOrder.paymentMethod == 'COD';
    
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isCod ? 'Confirm Cash Payment' : 'Confirm Delivery'),
        content: Text(isCod
            ? 'Did you receive ₹${activeOrder.totalAmount.toStringAsFixed(2)} in cash from ${activeOrder.customerName}?'
            : 'Are you sure you want to mark order #${activeOrder.orderNumber} as delivered?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: isCod ? Colors.amber.shade800 : AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(isCod ? 'Yes, Received' : 'Yes, Delivered'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final completed = await delivery.updateOrderStatus(activeOrder.orderId, 'DELIVERED');
      if (completed && mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Order delivered successfully!'),
            backgroundColor: AppTheme.primaryColor,
          ),
        );
        _getDriverLocation();
      }
    }
  }

  String _getDistanceText(DeliveryOrder order) {
    if (order.deliveryLatitude == null || order.deliveryLongitude == null) {
      return '';
    }
    final distanceInMeters = Geolocator.distanceBetween(
      _driverLocation.latitude,
      _driverLocation.longitude,
      order.deliveryLatitude!,
      order.deliveryLongitude!,
    );
    if (distanceInMeters < 1000) {
      return '${distanceInMeters.toStringAsFixed(0)} m away';
    } else {
      return '${(distanceInMeters / 1000).toStringAsFixed(1)} km away';
    }
  }

  void _showUnassignedOrderDetails(DeliveryOrder order, DeliveryProvider delivery) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Order #${order.orderNumber}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                  Text(
                    _getDistanceText(order),
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const Divider(height: 32),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline, color: AppTheme.primaryColor),
                title: Text(order.customerName, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(order.customerPhone),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.location_on_outlined, color: AppTheme.primaryColor),
                title: const Text('Address', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(order.deliveryAddress),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.payment_outlined, color: AppTheme.primaryColor),
                title: const Text('Payment', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('${order.paymentMethod} - ₹${order.totalAmount.toStringAsFixed(2)}'),
              ),
              const Divider(height: 32),
              const Text(
                'ITEMS',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: order.items.length,
                itemBuilder: (context, index) {
                  final item = order.items[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('${item.productName} (${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity}x ${item.unitName})'),
                        Text('₹${item.totalPrice.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    delivery.updateOrderStatus(order.orderId, 'OUT_FOR_DELIVERY');
                  },
                  child: const Text('START DELIVERY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  MapOptions _getMapOptions(LatLng driverLoc, List<DeliveryOrder> orders, {LatLng? activeLoc}) {
    final List<LatLng> points = [driverLoc];
    if (activeLoc != null) {
      points.add(activeLoc);
    }
    for (var o in orders) {
      if (o.deliveryLatitude != null && o.deliveryLongitude != null) {
        points.add(LatLng(o.deliveryLatitude!, o.deliveryLongitude!));
      }
    }

    if (points.length > 1) {
      return MapOptions(
        initialCameraFit: CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(50.0),
        ),
      );
    } else {
      return MapOptions(
        initialCenter: driverLoc,
        initialZoom: 14.5,
      );
    }
  }

  List<Marker> _buildOrderMarkers(List<DeliveryOrder> orders, DeliveryProvider delivery, {LatLng? activeLoc}) {
    final List<Marker> markers = [];
    final Map<String, int> coordinateCounts = {};

    if (activeLoc != null) {
      final key = '${activeLoc.latitude.toStringAsFixed(6)}_${activeLoc.longitude.toStringAsFixed(6)}';
      coordinateCounts[key] = 1;
    }

    for (var o in orders) {
      if (o.deliveryLatitude == null || o.deliveryLongitude == null) continue;
      
      final lat = o.deliveryLatitude!;
      final lng = o.deliveryLongitude!;
      final key = '${lat.toStringAsFixed(6)}_${lng.toStringAsFixed(6)}';
      
      final count = coordinateCounts[key] ?? 0;
      coordinateCounts[key] = count + 1;
      
      double offsetLat = lat;
      double offsetLng = lng;
      if (count > 0) {
        final angle = (count * 2 * 3.14159) / 8;
        final radius = 0.00012 * ((count - 1) ~/ 8 + 1);
        offsetLat += radius * math.sin(angle);
        offsetLng += radius * math.cos(angle);
      }
      
      markers.add(
        Marker(
          point: LatLng(offsetLat, offsetLng),
          width: 40,
          height: 40,
          child: GestureDetector(
            onTap: () {
              _showUnassignedOrderDetails(o, delivery);
            },
            child: Container(
              decoration: BoxDecoration(
                color: Colors.red.shade600,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2))
                ],
              ),
              child: Center(
                child: Text(
                  o.customerName.isNotEmpty ? o.customerName[0].toUpperCase() : 'O',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final delivery = Provider.of<DeliveryProvider>(context);

    final String driverName = auth.user?.username ?? 'Delivery Agent';
    final activeOrder = delivery.activeOrder;
    final remainingOrders = delivery.assignedOrders.where((o) => o.status == 'CONFIRMED' || o.status == 'PENDING').toList();
    final totalStops = delivery.assignedOrders.length;
    final completedStops = delivery.assignedOrders.where((o) => o.status == 'DELIVERED').length;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'FreshInBasket',
          style: TextStyle(
            color: AppTheme.primaryColor,
            fontWeight: FontWeight.bold,
            fontFamily: Theme.of(context).textTheme.titleLarge?.fontFamily,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: GestureDetector(
              onTap: () => MainShell.selectTab(context, 4),
              child: CircleAvatar(
                radius: 18,
                backgroundColor: AppTheme.successBgColor,
                backgroundImage: auth.user?.avatar != null
                    ? NetworkImage(auth.user!.avatar!)
                    : null,
                child: auth.user?.avatar == null
                    ? const Icon(Icons.person, size: 18, color: AppTheme.primaryColor)
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await delivery.fetchDashboard();
          await delivery.fetchAssignedOrders();
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Welcome & On Duty Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Hello, $driverName',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () async {
                      final newStatus = !(auth.user?.isActive ?? true);
                      try {
                        await auth.toggleActiveStatus(newStatus);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(newStatus ? 'You are now Online / On Duty' : 'You are now Offline / Off Duty'),
                              backgroundColor: AppTheme.primaryColor,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to update status: $e'),
                              backgroundColor: AppTheme.errorColor,
                            ),
                          );
                        }
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: (auth.user?.isActive ?? true) ? AppTheme.successBgColor : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircleAvatar(
                            radius: 4,
                            backgroundColor: (auth.user?.isActive ?? true) ? AppTheme.primaryColor : Colors.grey.shade600,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            (auth.user?.isActive ?? true) ? 'ON DUTY' : 'OFF DUTY',
                            style: TextStyle(
                              color: (auth.user?.isActive ?? true) ? AppTheme.primaryColor : Colors.grey.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Active Route: Morning Delivery Slot',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 28),

              // Current Order Section
              Text(
                'CURRENT ORDER',
                style: TextStyle(
                  color: Colors.grey.shade500,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),

              if (activeOrder != null) ...[
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mini Map
                      SizedBox(
                        height: 300,
                        child: activeOrder.deliveryLatitude != null && activeOrder.deliveryLongitude != null
                            ? FlutterMap(
                                mapController: _mapController,
                                options: _getMapOptions(_driverLocation, remainingOrders, activeLoc: LatLng(activeOrder.deliveryLatitude!, activeOrder.deliveryLongitude!)),
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
                                          strokeWidth: 4.0,
                                        ),
                                      ],
                                    ),
                                  MarkerLayer(
                                    markers: [
                                      // Customer Destination Marker
                                      Marker(
                                        point: LatLng(activeOrder.deliveryLatitude!, activeOrder.deliveryLongitude!),
                                        width: 40,
                                        height: 40,
                                        child: const Icon(
                                          Icons.location_on,
                                          color: Colors.red,
                                          size: 36,
                                        ),
                                      ),
                                      // Driver Live Location Marker
                                      Marker(
                                        point: _driverLocation,
                                        width: 40,
                                        height: 40,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: AppTheme.primaryColor.withAlpha(51),
                                            shape: BoxShape.circle,
                                            border: Border.all(color: AppTheme.primaryColor, width: 2),
                                          ),
                                          child: const Center(
                                            child: Icon(Icons.navigation, color: AppTheme.primaryColor, size: 20),
                                          ),
                                        ),
                                      ),
                                      // Remaining Orders Markers
                                      ..._buildOrderMarkers(remainingOrders, delivery, activeLoc: LatLng(activeOrder.deliveryLatitude!, activeOrder.deliveryLongitude!)),
                                    ],
                                  ),
                                ],
                              )
                            : Container(
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: Icon(Icons.map_outlined, size: 48, color: Colors.grey),
                                ),
                              ),
                      ),

                      // Order Stop Info
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppTheme.successBgColor,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    'STOP #${completedStops + 1} OF $totalStops',
                                    style: const TextStyle(
                                      color: AppTheme.primaryColor,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  style: IconButton.styleFrom(
                                    backgroundColor: Colors.grey.shade100,
                                    padding: const EdgeInsets.all(10),
                                  ),
                                  icon: const Icon(Icons.phone_outlined, color: AppTheme.primaryColor),
                                  onPressed: () => _makePhoneCall(activeOrder.customerPhone),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              activeOrder.customerName,
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              activeOrder.deliveryAddress,
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            if (activeOrder.notes.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Note: ${activeOrder.notes}',
                                style: const TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppTheme.primaryColor,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      elevation: 0,
                                    ),
                                    icon: const Icon(Icons.navigation_outlined, size: 18),
                                    label: const Text('NAVIGATE'),
                                    onPressed: () {
                                      // If order is PENDING or CONFIRMED, transition to OUT_FOR_DELIVERY
                                      if (activeOrder.status == 'CONFIRMED') {
                                        delivery.updateOrderStatus(activeOrder.orderId, 'OUT_FOR_DELIVERY');
                                      }
                                      // Switch to Map Tab (index 2)
                                      MainShell.selectTab(context, 3);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: OutlinedButton(
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: AppTheme.primaryColor,
                                      side: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                    ),
                                    onPressed: () {
                                      _showOrderItemsDialog(activeOrder);
                                    },
                                    child: const Text('VIEW ITEMS'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            const Divider(),
                            const SizedBox(height: 8),
                            // Order Details Block
                            Row(
                              children: [
                                const Icon(Icons.person_outline, size: 20, color: Colors.grey),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Customer: ${activeOrder.customerName}',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.payment, size: 20, color: Colors.grey),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: RichText(
                                    text: TextSpan(
                                      style: TextStyle(
                                        color: Colors.grey.shade800,
                                        fontSize: 14,
                                        height: 1.4,
                                      ),
                                      children: [
                                        const TextSpan(text: 'Payment Mode: '),
                                        TextSpan(
                                          text: activeOrder.paymentMethod == 'COD' ? 'Cash on Delivery (COD)' : 'Prepaid / Online',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            if (activeOrder.paymentMethod == 'COD')
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.amber.shade200),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.monetization_on_outlined, color: Colors.amber.shade800, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          style: TextStyle(
                                            color: Colors.amber.shade900,
                                            fontSize: 14,
                                          ),
                                          children: [
                                            const TextSpan(text: 'Receive payment: '),
                                            TextSpan(
                                              text: '₹${activeOrder.totalAmount.toStringAsFixed(2)}',
                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                            ),
                                            const TextSpan(text: ' from user.'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            else
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(top: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppTheme.successBgColor,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.primaryColor.withAlpha(51)),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(Icons.check_circle_outline, color: AppTheme.primaryColor, size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Payment Received: ₹${activeOrder.totalAmount.toStringAsFixed(2)} (Paid Online)',
                                        style: const TextStyle(
                                          color: AppTheme.primaryColor,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 16),
                            if (activeOrder.status == 'OUT_FOR_DELIVERY')
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.amber.shade800,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    elevation: 0,
                                  ),
                                  onPressed: () => _handleMarkDelivered(context, activeOrder, delivery),
                                  child: const Text('MARK DELIVERED', style: TextStyle(fontWeight: FontWeight.bold)),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (remainingOrders.isNotEmpty) ...[
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 300,
                        child: FlutterMap(
                          mapController: _mapController,
                          options: _getMapOptions(_driverLocation, remainingOrders),
                          children: [
                            TileLayer(
                              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                              userAgentPackageName: 'com.freshinbasket.delivery',
                            ),
                            MarkerLayer(
                              markers: [
                                // Driver Location
                                Marker(
                                  point: _driverLocation,
                                  width: 40,
                                  height: 40,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppTheme.primaryColor.withAlpha(51),
                                      shape: BoxShape.circle,
                                      border: Border.all(color: AppTheme.primaryColor, width: 2),
                                    ),
                                    child: const Center(
                                      child: Icon(Icons.navigation, color: AppTheme.primaryColor, size: 20),
                                    ),
                                  ),
                                ),
                                // Order Locations
                                ..._buildOrderMarkers(remainingOrders, delivery),
                              ],
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'You have ${remainingOrders.length} assigned orders pending.',
                          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(
                            'No assigned orders.',
                            style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Stat Row
              Row(
                children: [
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'COMPLETED',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '$completedStops / $totalStops',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppTheme.primaryColor),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Stops finished',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'PROGRESS',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            LinearProgressIndicator(
                              value: totalStops > 0 ? (completedStops / totalStops) : 0.0,
                              backgroundColor: Colors.grey.shade200,
                              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              totalStops > 0 ? '${((completedStops / totalStops) * 100).toInt()}% completed' : '0% completed',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 28),

              // Remaining stops
              if (remainingOrders.isNotEmpty) ...[
                Text(
                  'REMAINING ORDERS',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 12),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: remainingOrders.length,
                  itemBuilder: (context, index) {
                    final order = remainingOrders[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.grey.shade100,
                          foregroundColor: AppTheme.primaryColor,
                          child: Text('${index + 1}'),
                        ),
                        title: Text(
                          order.customerName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              order.deliveryAddress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _getDistanceText(order),
                              style: const TextStyle(color: AppTheme.primaryColor, fontWeight: FontWeight.w600, fontSize: 12),
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                        onTap: () {
                          _showUnassignedOrderDetails(order, delivery);
                        },
                      ),
                    );
                  },
                ),
              ],

              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }
}

extension CountExtension<T> on Iterable<T> {
  int count() => length;
}
