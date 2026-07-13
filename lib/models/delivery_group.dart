import 'order.dart';

class DeliveryGroup {
  final String groupId;
  final String deliverySlot;
  final String groupName;
  final String date;
  final int totalOrders;
  final int deliveredCount;
  final int undeliveredCount;
  final int pendingCount;
  final double codCollected;
  final List<DeliveryOrder> orders;
  final bool isActive;

  DeliveryGroup({
    required this.groupId,
    required this.deliverySlot,
    required this.groupName,
    required this.date,
    required this.totalOrders,
    required this.deliveredCount,
    required this.undeliveredCount,
    required this.pendingCount,
    required this.codCollected,
    required this.orders,
    required this.isActive,
  });

  factory DeliveryGroup.fromJson(Map<String, dynamic> json) {
    var ordersList = json['orders'] as List? ?? [];
    List<DeliveryOrder> orders = ordersList.map((i) => DeliveryOrder.fromJson(i)).toList();

    return DeliveryGroup(
      groupId: json['group_id']?.toString() ?? '',
      deliverySlot: json['delivery_slot'] ?? '',
      groupName: json['group_name'] ?? '',
      date: json['date'] ?? '',
      totalOrders: json['total_orders'] ?? 0,
      deliveredCount: json['delivered_count'] ?? 0,
      undeliveredCount: json['undelivered_count'] ?? 0,
      pendingCount: json['pending_count'] ?? 0,
      codCollected: double.tryParse(json['cod_collected']?.toString() ?? '0.0') ?? 0.0,
      orders: orders,
      isActive: json['is_active'] ?? false,
    );
  }
}
