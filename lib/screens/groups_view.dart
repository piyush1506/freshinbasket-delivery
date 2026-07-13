import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/delivery_provider.dart';
import '../models/delivery_group.dart';
import '../models/order.dart';
import 'stats_view.dart';

class GroupsView extends StatefulWidget {
  const GroupsView({super.key});

  @override
  State<GroupsView> createState() => _GroupsViewState();
}

class _GroupsViewState extends State<GroupsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DeliveryProvider>(context, listen: false).fetchGroups();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DeliveryProvider>(context);
    final theme = Theme.of(context);

    Widget groupsBody = provider.loading
          ? Center(child: CircularProgressIndicator())
          : provider.error != null
              ? Center(child: Text(provider.error!, style: TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: () => provider.fetchGroups(),
                  child: ListView(
                    padding: EdgeInsets.all(16),
                    children: [
                      _buildSectionTitle('Active Groups', Icons.local_shipping, theme),
                      if (provider.activeGroups.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text('No active groups.', style: TextStyle(color: Colors.grey)),
                        ),
                      ...provider.activeGroups.map((g) => _buildGroupCard(g, theme, isActive: true)),
                      
                      SizedBox(height: 24),
                      
                      _buildSectionTitle('Past Groups', Icons.history, theme),
                      if (provider.pastGroups.isEmpty)
                        Padding(
                          padding: EdgeInsets.symmetric(vertical: 20),
                          child: Text('No past groups.', style: TextStyle(color: Colors.grey)),
                        ),
                      ...provider.pastGroups.map((g) => _buildGroupCard(g, theme, isActive: false)),
                    ],
                  ),
                );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Groups & Stats'),
          centerTitle: true,
          bottom: TabBar(
            tabs: [
              Tab(text: 'Groups'),
              Tab(text: 'Stats'),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.refresh),
              onPressed: () {
                provider.fetchGroups();
                provider.fetchStats();
              },
            ),
          ],
        ),
        body: TabBarView(
          children: [
            groupsBody,
            StatsView(),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, IconData icon, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          SizedBox(width: 8),
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildGroupCard(DeliveryGroup group, ThemeData theme, {required bool isActive}) {
    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: isActive ? 4 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        title: Text(group.groupName, style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Text('Date: ${group.date.split('T')[0]}'),
            SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.inventory, size: 16, color: Colors.grey),
                SizedBox(width: 4),
                Text('${group.totalOrders} Orders'),
                SizedBox(width: 16),
                Icon(Icons.check_circle, size: 16, color: Colors.green),
                SizedBox(width: 4),
                Text('${group.deliveredCount} Delivered'),
              ],
            ),
            if (group.undeliveredCount > 0) ...[
              SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.cancel, size: 16, color: Colors.red),
                  SizedBox(width: 4),
                  Text('${group.undeliveredCount} Undelivered', style: TextStyle(color: Colors.red)),
                ],
              ),
            ],
            SizedBox(height: 8),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(51),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.amber),
              ),
              child: Text(
                '₹${group.codCollected.toStringAsFixed(2)} COD Collected',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800]),
              ),
            ),
          ],
        ),
        children: group.orders.map<Widget>((o) => _buildOrderTile(o, theme)).toList(),
      ),
    );
  }

  Widget _buildOrderTile(DeliveryOrder order, ThemeData theme) {
    Color statusColor;
    switch (order.status) {
      case 'DELIVERED':
        statusColor = Colors.green;
        break;
      case 'UNDELIVERED':
        statusColor = Colors.red;
        break;
      case 'OUT_FOR_DELIVERY':
        statusColor = Colors.blue;
        break;
      default:
        statusColor = Colors.grey;
    }

    return ListTile(
      title: Text(order.orderNumber, style: TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text('${order.customerName} • ${order.paymentMethod}'),
      trailing: Container(
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: statusColor.withAlpha(26),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: statusColor),
        ),
        child: Text(order.status, style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
