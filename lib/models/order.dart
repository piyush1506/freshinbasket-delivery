class OrderItem {
  final int id;
  final String productName;
  final double quantity;
  final String unitName;
  final double unitPrice;
  final double totalPrice;

  OrderItem({
    required this.id,
    required this.productName,
    required this.quantity,
    required this.unitName,
    required this.unitPrice,
    required this.totalPrice,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] ?? 0,
      productName: json['product_name'] ?? '',
      quantity: double.tryParse(json['quantity']?.toString() ?? '0.0') ?? 0.0,
      unitName: json['unit_name'] ?? 'kg',
      unitPrice: double.tryParse(json['unit_price']?.toString() ?? '0.0') ?? 0.0,
      totalPrice: double.tryParse(json['total_price']?.toString() ?? '0.0') ?? 0.0,
    );
  }
}

class DeliveryOrder {
  final int assignmentId;
  final int orderId;
  final String orderNumber;
  final String customerName;
  final String customerPhone;
  final String deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String status;
  final double subtotal;
  final double deliveryCharge;
  final double totalAmount;
  final bool isPaid;
  final String paymentMethod;
  final String? createdAt;
  final String? assignedAt;
  final String? deliveredAt;
  final String notes;
  final String? undeliveredReason;
  final List<OrderItem> items;

  DeliveryOrder({
    required this.assignmentId,
    required this.orderId,
    required this.orderNumber,
    required this.customerName,
    required this.customerPhone,
    required this.deliveryAddress,
    this.deliveryLatitude,
    this.deliveryLongitude,
    required this.status,
    required this.subtotal,
    required this.deliveryCharge,
    required this.totalAmount,
    required this.isPaid,
    required this.paymentMethod,
    this.createdAt,
    this.assignedAt,
    this.deliveredAt,
    required this.notes,
    this.undeliveredReason,
    required this.items,
  });

  factory DeliveryOrder.fromJson(Map<String, dynamic> json) {
    var itemsList = json['items'] as List? ?? [];
    List<OrderItem> items = itemsList.map((i) => OrderItem.fromJson(i)).toList();

    return DeliveryOrder(
      assignmentId: json['assignment_id'] ?? 0,
      orderId: json['order_id'] ?? 0,
      orderNumber: json['order_number'] ?? '',
      customerName: json['customer_name'] ?? '',
      customerPhone: json['customer_phone'] ?? '',
      deliveryAddress: json['delivery_address'] ?? '',
      deliveryLatitude: double.tryParse(json['delivery_latitude']?.toString() ?? ''),
      deliveryLongitude: double.tryParse(json['delivery_longitude']?.toString() ?? ''),
      status: json['status'] ?? 'PENDING',
      subtotal: double.tryParse(json['subtotal']?.toString() ?? '0.0') ?? 0.0,
      deliveryCharge: double.tryParse(json['delivery_charge']?.toString() ?? '0.0') ?? 0.0,
      totalAmount: double.tryParse(json['total_amount']?.toString() ?? '0.0') ?? 0.0,
      isPaid: json['is_paid'] ?? false,
      paymentMethod: json['payment_method'] ?? 'COD',
      createdAt: json['created_at'],
      assignedAt: json['assigned_at'],
      deliveredAt: json['delivered_at'],
      notes: json['notes'] ?? '',
      undeliveredReason: json['undelivered_reason'],
      items: items,
    );
  }
}
