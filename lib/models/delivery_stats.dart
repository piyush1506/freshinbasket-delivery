class PeriodStats {
  final int totalOrders;
  final int delivered;
  final int undelivered;
  final int pending;
  final double codCollected;
  final String? date;
  final String? day;
  final String? month;
  final String? label;

  PeriodStats({
    required this.totalOrders,
    required this.delivered,
    required this.undelivered,
    required this.pending,
    required this.codCollected,
    this.date,
    this.day,
    this.month,
    this.label,
  });

  factory PeriodStats.fromJson(Map<String, dynamic> json) {
    return PeriodStats(
      totalOrders: json['total_orders'] ?? 0,
      delivered: json['delivered'] ?? 0,
      undelivered: json['undelivered'] ?? 0,
      pending: json['pending'] ?? 0,
      codCollected: double.tryParse(json['cod_collected']?.toString() ?? '0.0') ?? 0.0,
      date: json['date'],
      day: json['day'],
      month: json['month'],
      label: json['label'],
    );
  }
}

class DeliveryStats {
  final PeriodStats today;
  final PeriodStats thisWeek;
  final PeriodStats thisMonth;
  final List<PeriodStats> dailyBreakdown;
  final List<PeriodStats> monthlyBreakdown;

  DeliveryStats({
    required this.today,
    required this.thisWeek,
    required this.thisMonth,
    required this.dailyBreakdown,
    required this.monthlyBreakdown,
  });

  factory DeliveryStats.fromJson(Map<String, dynamic> json) {
    var dailyList = json['daily_breakdown'] as List? ?? [];
    List<PeriodStats> daily = dailyList.map((i) => PeriodStats.fromJson(i)).toList();

    var monthlyList = json['monthly_breakdown'] as List? ?? [];
    List<PeriodStats> monthly = monthlyList.map((i) => PeriodStats.fromJson(i)).toList();

    return DeliveryStats(
      today: PeriodStats.fromJson(json['today'] ?? {}),
      thisWeek: PeriodStats.fromJson(json['this_week'] ?? {}),
      thisMonth: PeriodStats.fromJson(json['this_month'] ?? {}),
      dailyBreakdown: daily,
      monthlyBreakdown: monthly,
    );
  }
}
