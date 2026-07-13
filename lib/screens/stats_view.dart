import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/delivery_provider.dart';
import '../models/delivery_stats.dart';

class StatsView extends StatefulWidget {
  const StatsView({super.key});

  @override
  State<StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<StatsView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<DeliveryProvider>(context, listen: false).fetchStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<DeliveryProvider>(context);
    final theme = Theme.of(context);

    return provider.loading
          ? Center(child: CircularProgressIndicator())
          : provider.error != null
              ? Center(child: Text(provider.error!, style: TextStyle(color: Colors.red)))
              : provider.stats == null
                  ? Center(child: Text('No stats available.'))
                  : RefreshIndicator(
                      onRefresh: () => provider.fetchStats(),
                      child: ListView(
                        padding: EdgeInsets.all(16),
                        children: [
                          _buildSummaryCards(provider.stats!, theme),
                          SizedBox(height: 24),
                          _buildDailyBreakdown(provider.stats!.dailyBreakdown, theme),
                          SizedBox(height: 24),
                          _buildMonthlyBreakdown(provider.stats!.monthlyBreakdown, theme),
                        ],
                      ),
                    );
  }

  Widget _buildSummaryCards(DeliveryStats stats, ThemeData theme) {
    return Column(
      children: [
        _buildStatCard('Today', stats.today, theme, isPrimary: true),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: _buildStatCard('This Week', stats.thisWeek, theme)),
            SizedBox(width: 12),
            Expanded(child: _buildStatCard('This Month', stats.thisMonth, theme)),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, PeriodStats stat, ThemeData theme, {bool isPrimary = false}) {
    return Card(
      elevation: isPrimary ? 4 : 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: isPrimary ? 18 : 16)),
            SizedBox(height: 12),
            _buildStatRow('Total Orders', '${stat.totalOrders}', Icons.list_alt, theme),
            SizedBox(height: 4),
            _buildStatRow('Delivered', '${stat.delivered}', Icons.check_circle, theme, color: Colors.green),
            SizedBox(height: 4),
            _buildStatRow('Undelivered', '${stat.undelivered}', Icons.cancel, theme, color: Colors.red),
            SizedBox(height: 12),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.withAlpha(51),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '₹${stat.codCollected.toStringAsFixed(0)} COD',
                style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, String value, IconData icon, ThemeData theme, {Color? color}) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color ?? Colors.grey[600]),
        SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
        Spacer(),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }

  Widget _buildDailyBreakdown(List<PeriodStats> daily, ThemeData theme) {
    if (daily.isEmpty) return SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Daily Breakdown', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListView.separated(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: daily.length,
            separatorBuilder: (c, i) => Divider(height: 1),
            itemBuilder: (context, index) {
              final d = daily[index];
              return ListTile(
                title: Text('${d.day}, ${d.date?.split('T')[0]}'),
                subtitle: Text('Delivered: ${d.delivered} / ${d.totalOrders}'),
                trailing: Text('₹${d.codCollected.toStringAsFixed(0)} COD', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800])),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlyBreakdown(List<PeriodStats> monthly, ThemeData theme) {
    if (monthly.isEmpty) return SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Monthly Breakdown', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        SizedBox(height: 8),
        Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListView.separated(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            itemCount: monthly.length,
            separatorBuilder: (c, i) => Divider(height: 1),
            itemBuilder: (context, index) {
              final m = monthly[index];
              return ListTile(
                title: Text(m.label ?? m.month ?? ''),
                subtitle: Text('Delivered: ${m.delivered} / ${m.totalOrders}'),
                trailing: Text('₹${m.codCollected.toStringAsFixed(0)} COD', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange[800])),
              );
            },
          ),
        ),
      ],
    );
  }
}
