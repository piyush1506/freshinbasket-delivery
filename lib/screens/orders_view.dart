import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/delivery_provider.dart';
import '../models/order.dart';
import '../theme/app_theme.dart';

class OrdersView extends StatefulWidget {
  const OrdersView({super.key});

  @override
  State<OrdersView> createState() => _OrdersViewState();
}

class _OrdersViewState extends State<OrdersView> {
  String _selectedTab = 'All'; // 'All', 'Active', 'Delivered', 'Undelivered'

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        Provider.of<DeliveryProvider>(context, listen: false).fetchAssignedOrders();
      }
    });
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'DELIVERED':
        return const Color(0xFFE2F0EC); // light green
      case 'UNDELIVERED':
        return Colors.red.shade50;
      case 'OUT_FOR_DELIVERY':
        return Colors.blue.shade50;
      case 'CONFIRMED':
      case 'PENDING':
        return Colors.orange.shade50;
      default:
        return Colors.grey.shade100;
    }
  }

  Color _getStatusTextColor(String status) {
    switch (status) {
      case 'DELIVERED':
        return AppTheme.primaryColor;
      case 'UNDELIVERED':
        return Colors.red.shade700;
      case 'OUT_FOR_DELIVERY':
        return Colors.blue.shade700;
      case 'CONFIRMED':
      case 'PENDING':
        return Colors.orange.shade800;
      default:
        return Colors.grey.shade700;
    }
  }

  String _getStatusLabel(String status) {
    switch (status) {
      case 'DELIVERED':
        return 'Completed';
      case 'UNDELIVERED':
        return 'Undelivered';
      case 'OUT_FOR_DELIVERY':
        return 'In Transit';
      case 'CONFIRMED':
        return 'Assigned';
      case 'PENDING':
        return 'Pending';
      default:
        return status;
    }
  }


  void _showRejectDialog(DeliveryOrder order) {
    String? selectedReason = 'Not at home';
    final TextEditingController otherReasonController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Customer Not Received'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select reason for non-delivery:'),
                  DropdownButton<String>(
                    isExpanded: true,
                    value: selectedReason,
                    items: ['Not at home', 'Refused delivery', 'Wrong address', 'Other']
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (val) {
                      setState(() {
                        selectedReason = val;
                      });
                    },
                  ),
                  if (selectedReason == 'Other') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: otherReasonController,
                      decoration: const InputDecoration(
                        labelText: 'Enter reason',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    String reason = selectedReason == 'Other' ? otherReasonController.text : selectedReason!;
                    final provider = Provider.of<DeliveryProvider>(context, listen: false);
                    Navigator.pop(context); // close dialog
                    Navigator.pop(context); // close details modal
                    await provider.markUndelivered(order.orderId, reason);
                  },
                  child: const Text('Confirm'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  void _showOrderDetailsModal(DeliveryOrder order) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.4,
          expand: false,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _getStatusColor(order.status),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _getStatusLabel(order.status),
                          style: TextStyle(
                            color: _getStatusTextColor(order.status),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32),
                  const Text(
                    'DELIVERY DETAILS',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
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
                  if (order.notes.isNotEmpty) ...[
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.notes_outlined, color: Colors.redAccent),
                      title: const Text('Special Note', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.redAccent)),
                      subtitle: Text(order.notes, style: const TextStyle(color: Colors.redAccent)),
                    ),
                  ],
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
                  const Divider(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Amount', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('₹${order.totalAmount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppTheme.primaryColor)),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (order.status == 'OUT_FOR_DELIVERY' || order.status == 'CONFIRMED')
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                        label: const Text('Customer Not Received', style: TextStyle(color: Colors.red)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.red),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () => _showRejectDialog(order),
                      ),
                    ),
                  const SizedBox(height: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final delivery = Provider.of<DeliveryProvider>(context);

    // Filter assignments based on toggle tab
    final List<DeliveryOrder> filteredOrders = delivery.assignedOrders.where((order) {
      if (_selectedTab == 'Active') {
        return order.status == 'CONFIRMED' || order.status == 'OUT_FOR_DELIVERY' || order.status == 'PENDING';
      } else if (_selectedTab == 'Delivered') {
        return order.status == 'DELIVERED';
      } else if (_selectedTab == 'Undelivered') {
        return order.status == 'UNDELIVERED';
      }
      return true; // 'All'
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Orders',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search, color: AppTheme.primaryColor),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.notifications_none, color: AppTheme.primaryColor),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Capsule Toggle Tabs Row
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0), // Reduced from 20.0 to 8.0
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: ['All', 'Active', 'Delivered', 'Undelivered'].map((tab) {
                  final isSelected = _selectedTab == tab;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedTab = tab;
                        });
                      },
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 4.0), // Reduced horizontal margin
                        decoration: BoxDecoration(
                          color: isSelected ? Colors.white : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withAlpha(13),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            tab,
                            style: TextStyle(
                              color: isSelected ? AppTheme.primaryColor : Colors.grey.shade600,
                              fontWeight: FontWeight.bold,
                              fontSize: 13, // Slightly reduced to ensure it fits perfectly
                              letterSpacing: -0.2, // Tighter letter spacing
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Orders List
          Expanded(
            child: delivery.loading
                ? const Center(child: CircularProgressIndicator())
                : filteredOrders.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inventory_2_outlined, size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            Text(
                              'No $_selectedTab orders found',
                              style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: () => delivery.fetchAssignedOrders(),
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
                          itemCount: filteredOrders.length,
                          itemBuilder: (context, index) {
                            final order = filteredOrders[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 16.0),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          'ORDER ID',
                                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.bold),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: _getStatusColor(order.status),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            _getStatusLabel(order.status).toUpperCase(),
                                            style: TextStyle(
                                              color: _getStatusTextColor(order.status),
                                              fontWeight: FontWeight.bold,
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '#${order.orderNumber}',
                                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: AppTheme.primaryColor,
                                          ),
                                    ),
                                    const SizedBox(height: 16),
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade50,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.location_on_outlined, size: 18, color: AppTheme.primaryColor),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text(
                                                  'Delivery Address',
                                                  style: TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  order.deliveryAddress,
                                                  style: const TextStyle(fontSize: 13, height: 1.3),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        // Preview items count/images
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: AppTheme.successBgColor,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(Icons.shopping_bag_outlined, size: 16, color: AppTheme.primaryColor),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '${order.items.length} items',
                                              style: TextStyle(color: Colors.grey.shade600, fontSize: 13, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                        ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppTheme.primaryColor,
                                            foregroundColor: Colors.white,
                                            elevation: 0,
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                          ),
                                          onPressed: () => _showOrderDetailsModal(order),
                                          child: const Text('View Details'),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
