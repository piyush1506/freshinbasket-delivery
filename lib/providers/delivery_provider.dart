import 'package:flutter/material.dart';
import '../models/order.dart';
import '../models/delivery_group.dart';
import '../models/delivery_stats.dart';
import '../services/api_service.dart';

class DeliveryProvider extends ChangeNotifier {
  // Bug 12: Separate error state per operation
  String? _dashboardError;
  String? _ordersError;
  String? _groupsError;
  String? _statsError;
  String? _statusError;

  double _todayEarnings = 0.0;
  int _todayDeliveriesCount = 0;
  int _weekDeliveriesCount = 0;
  int _totalDeliveriesCount = 0;
  double _avgRating = 0.0;

  DeliveryOrder? _activeOrder;
  List<DeliveryOrder> _assignedOrders = [];

  List<DeliveryGroup> _activeGroups = [];
  List<DeliveryGroup> _pastGroups = [];
  DeliveryStats? _stats;
  bool _groupsLoading = false;
  bool _statsLoading = false;

  List<DeliveryGroup> get activeGroups => _activeGroups;
  List<DeliveryGroup> get pastGroups => _pastGroups;
  DeliveryStats? get stats => _stats;

  bool _dashboardLoading = false;
  bool _ordersLoading = false;
  bool _statusUpdating = false;

  bool get loading => _dashboardLoading || _ordersLoading || _statusUpdating || _groupsLoading || _statsLoading;

  // Bug 12: Per-operation error getters
  String? get error => _dashboardError ?? _ordersError ?? _statusError ?? _groupsError ?? _statsError;
  String? get dashboardError => _dashboardError;
  String? get ordersError => _ordersError;
  String? get groupsError => _groupsError;
  String? get statsError => _statsError;
  String? get statusError => _statusError;

  double get todayEarnings => _todayEarnings;
  int get todayDeliveriesCount => _todayDeliveriesCount;
  int get weekDeliveriesCount => _weekDeliveriesCount;
  int get totalDeliveriesCount => _totalDeliveriesCount;
  double get avgRating => _avgRating;

  DeliveryOrder? get activeOrder => _activeOrder;
  List<DeliveryOrder> get assignedOrders => _assignedOrders;

  Future<void> fetchDashboard() async {
    _dashboardLoading = true;
    _dashboardError = null;
    notifyListeners();

    try {
      final data = await ApiService.get('/delivery/dashboard/');
      _todayEarnings = double.tryParse(data['today_earnings']?.toString() ?? '0.0') ?? 0.0;
      _todayDeliveriesCount = data['today_deliveries'] ?? 0;
      _weekDeliveriesCount = data['week_deliveries'] ?? 0;
      _totalDeliveriesCount = data['total_deliveries'] ?? 0;
      _avgRating = double.tryParse(data['avg_rating']?.toString() ?? '0.0') ?? 0.0;

      // Bug 9: Only fetchDashboard sets _activeOrder
      DeliveryOrder? backendActive;
      if (data['active_delivery'] != null) {
        backendActive = DeliveryOrder.fromJson(data['active_delivery']);
      }

      if (backendActive != null && backendActive.status == 'OUT_FOR_DELIVERY') {
        _activeOrder = backendActive;
      } else {
        // Fallback scan local list
        final outForDeliveryOrder = _assignedOrders.firstWhere(
          (o) => o.status == 'OUT_FOR_DELIVERY',
          orElse: () => backendActive ?? DeliveryOrder(
            assignmentId: 0, orderId: 0, orderNumber: '', customerName: '',
            customerPhone: '', deliveryAddress: '', status: 'PENDING',
            subtotal: 0, deliveryCharge: 0, totalAmount: 0, isPaid: false,
            paymentMethod: 'COD', notes: '', items: []
          ),
        );
        if (outForDeliveryOrder.status == 'OUT_FOR_DELIVERY') {
          _activeOrder = outForDeliveryOrder;
        } else {
          _activeOrder = null;
        }
      }

      // Sync with assigned orders list to get correct unit names
      if (_activeOrder != null) {
        final matchedOrder = _assignedOrders.firstWhere(
          (o) => o.orderId == _activeOrder!.orderId,
          orElse: () => _activeOrder!,
        );
        if (matchedOrder.orderId == _activeOrder!.orderId && matchedOrder.items.isNotEmpty) {
          _activeOrder = matchedOrder;
        }
      }

      _dashboardLoading = false;
      notifyListeners();
    } catch (e) {
      _dashboardError = e.toString().replaceFirst('Exception: ', '');
      _dashboardLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchAssignedOrders({String? statusFilter}) async {
    _ordersLoading = true;
    _ordersError = null;
    notifyListeners();

    try {
      String path = '/delivery/orders/';
      if (statusFilter != null && statusFilter.isNotEmpty) {
        path += '?status=$statusFilter';
      }
      final List<dynamic> data = await ApiService.get(path);
      _assignedOrders = data.map((o) => DeliveryOrder.fromJson(o)).toList();

      // Bug 9: Don't set _activeOrder here — let fetchDashboard be the single source of truth

      _ordersLoading = false;
      notifyListeners();
    } catch (e) {
      _ordersError = e.toString().replaceFirst('Exception: ', '');
      _ordersLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateOrderStatus(int orderId, String newStatus) async {
    _statusUpdating = true;
    _statusError = null;
    notifyListeners();

    try {
      await ApiService.patch('/delivery/orders/$orderId/status/', {
        'status': newStatus,
      });
      // Refresh all data to keep everything in sync
      await fetchAssignedOrders();
      await fetchDashboard();
      await fetchGroups();
      await fetchStats();
      _statusUpdating = false;
      notifyListeners();
      return true;
    } catch (e) {
      _statusError = e.toString().replaceFirst('Exception: ', '');
      _statusUpdating = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> fetchGroups() async {
    _groupsLoading = true;
    _groupsError = null;
    notifyListeners();

    try {
      final data = await ApiService.get('/delivery/groups/');
      
      var activeList = data['active_groups'] as List? ?? [];
      _activeGroups = activeList.map((g) => DeliveryGroup.fromJson(g)).toList();

      var pastList = data['past_groups'] as List? ?? [];
      _pastGroups = pastList.map((g) => DeliveryGroup.fromJson(g)).toList();

      _groupsLoading = false;
      notifyListeners();
    } catch (e) {
      _groupsError = e.toString().replaceFirst('Exception: ', '');
      _groupsLoading = false;
      notifyListeners();
    }
  }

  Future<void> fetchStats() async {
    _statsLoading = true;
    _statsError = null;
    notifyListeners();

    try {
      final data = await ApiService.get('/delivery/stats/');
      _stats = DeliveryStats.fromJson(data);
      
      _statsLoading = false;
      notifyListeners();
    } catch (e) {
      _statsError = e.toString().replaceFirst('Exception: ', '');
      _statsLoading = false;
      notifyListeners();
    }
  }

  Future<bool> markUndelivered(int orderId, String reason) async {
    _statusUpdating = true;
    _statusError = null;
    notifyListeners();

    try {
      await ApiService.patch('/delivery/orders/$orderId/status/', {
        'status': 'UNDELIVERED',
        'reason': reason,
      });
      await fetchAssignedOrders();
      await fetchDashboard();
      await fetchGroups();
      await fetchStats();
      _statusUpdating = false;
      notifyListeners(); // Bug 8: was missing
      return true;
    } catch (e) {
      _statusError = e.toString().replaceFirst('Exception: ', '');
      _statusUpdating = false;
      notifyListeners();
      return false;
    }
  }

}