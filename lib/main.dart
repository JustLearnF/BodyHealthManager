import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('weight');
  await Hive.openBox('food');
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('健康记录'),
          bottom: const TabBar(tabs: [Tab(text: '体重'), Tab(text: '食量')]),
        ),
        body: const TabBarView(children: [WeightPage(), FoodPage()]),
      ),
    );
  }
}

class WeightPage extends StatefulWidget {
  const WeightPage({super.key});
  @override
  State<WeightPage> createState() => _WeightPageState();
}

class _WeightPageState extends State<WeightPage> {
  final c = TextEditingController();
  Box get box => Hive.box('weight');

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 1. 读取原始记录
    final List<Map<String, dynamic>> allRecords = [];
    for (int i = 0; i < box.length; i++) {
      final item = Map<String, dynamic>.from(box.getAt(i));
      item['key'] = box.keyAt(i);
      allRecords.add(item);
    }

    // 2. 按日期分组
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (var item in allRecords) {
      final String dateKey = DateFormat('yyyy-MM-dd').format(DateTime.parse(item['time']));
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(item);
    }

    // 获取排序后的日期列表
    final sortedDates = grouped.keys.toList()..sort((a, b) => a.compareTo(b));

    // 3. 计算每日最低体重用于折线图绘制
    final List<Map<String, dynamic>> dailyMinData = sortedDates.map((date) {
      final dayItems = grouped[date]!;
      final minWeight = dayItems
          .map((e) => (e['weight'] as num).toDouble())
          .reduce((a, b) => a < b ? a : b);
      return {
        'date': date,
        'weight': minWeight,
      };
    }).toList();

    // 截取最近15天的最低点用于展示
    final recentChartData = dailyMinData.length > 15
        ? dailyMinData.sublist(dailyMinData.length - 15)
        : dailyMinData;

    List<LineChartBarData> lines = [];
    for (int i = 1; i < recentChartData.length; i++) {
      final p = recentChartData[i - 1]['weight'] as double;
      final n = recentChartData[i]['weight'] as double;
      lines.add(LineChartBarData(
        spots: [FlSpot((i - 1).toDouble(), p), FlSpot(i.toDouble(), n)],
        color: n >= p ? Colors.red : Colors.green,
        barWidth: 4,
        dotData: const FlDotData(show: true),
      ));
    }

    return Column(children: [
      // 输入区
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: c,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: '体重(斤)', border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: () {
              if (c.text.isEmpty) return;
              box.add({
                'id': DateTime.now().millisecondsSinceEpoch.toString(),
                'weight': double.parse(c.text),
                'time': DateTime.now().toIso8601String()
              });
              c.clear();
              setState(() {});
            },
            child: const Text('保存'),
          )
        ]),
      ),
      // 图表区 (展示每日最低点)
      SizedBox(
        height: 200,
        child: recentChartData.length < 2
            ? const Center(child: Text('记录多天数据以查看最低体重趋势'))
            : Padding(
          padding: const EdgeInsets.only(right: 20, top: 10, left: 10),
          child: LineChart(LineChartData(
            lineBarsData: lines,
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 30,
                  getTitlesWidget: (value, meta) {
                    int i = value.toInt();
                    if (i < 0 || i >= recentChartData.length) return const SizedBox();
                    final dateStr = recentChartData[i]['date'].toString().substring(5); // 截取 MM-dd
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text(dateStr, style: const TextStyle(fontSize: 9)),
                    );
                  },
                ),
              ),
            ),
          )),
        ),
      ),
      const Divider(),
      // 历史记录列表 (按天分组)
      Expanded(
        child: ListView(
          children: sortedDates.reversed.map((date) {
            final items = grouped[date]!;
            final dayMin = items.map((e) => (e['weight'] as num).toDouble()).reduce((a, b) => a < b ? a : b);

            return ExpansionTile(
              title: Text(date, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('记录 ${items.length} 次 | 当天最低: $dayMin 斤'),
              initiallyExpanded: date == sortedDates.last, // 默认展开今天
              children: items.reversed.map((item) {
                return ListTile(
                  dense: true,
                  title: Text('${item["weight"]} 斤'),
                  subtitle: Text(DateFormat('HH:mm').format(DateTime.parse(item['time']))),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.edit, size: 20),
                          onPressed: () {
                            final ec = TextEditingController(text: item['weight'].toString());
                            showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('修改体重'),
                                  content: TextField(
                                    controller: ec,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  ),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
                                    TextButton(
                                        onPressed: () {
                                          if (ec.text.isEmpty) return;
                                          box.put(item['key'], {
                                            ...item,
                                            'weight': double.parse(ec.text)
                                          });
                                          Navigator.pop(context);
                                          setState(() {});
                                        },
                                        child: const Text('保存'))
                                  ],
                                ));
                          }),
                      IconButton(
                          icon: const Icon(Icons.delete, size: 20),
                          onPressed: () {
                            box.delete(item['key']);
                            setState(() {});
                          })
                    ],
                  ),
                );
              }).toList(),
            );
          }).toList(),
        ),
      )
    ]);
  }
}

class FoodPage extends StatefulWidget {
  const FoodPage({super.key});
  @override
  State<FoodPage> createState() => _FoodPageState();
}

class _FoodPageState extends State<FoodPage> {
  final food = TextEditingController();
  final amount = TextEditingController();
  final units = ['g', 'ml', '拳', '个'];
  String unit = 'g';
  Box get box => Hive.box('food');

  @override
  void dispose() {
    food.dispose();
    amount.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final records = [];
    for (int i = 0; i < box.length; i++) {
      final item = Map<String, dynamic>.from(box.getAt(i));
      item['key'] = box.keyAt(i);
      records.add(item);
    }

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final r in records) {
      final String dateKey = r['date']?.toString() ?? '未知日期';
      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(r);
    }

    final dates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          TextField(controller: food, decoration: const InputDecoration(labelText: '食物名称')),
          TextField(controller: amount, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '数量')),
          const SizedBox(height: 8),
          const Align(alignment: Alignment.centerLeft, child: Text('单位:', style: TextStyle(color: Colors.grey))),
          SizedBox(
            height: 80,
            child: CupertinoPicker(
              itemExtent: 35,
              onSelectedItemChanged: (i) {
                setState(() {
                  unit = units[i];
                });
              },
              children: units.map((e) => Center(child: Text(e))).toList(),
            ),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () {
              if (food.text.isEmpty || amount.text.isEmpty) return;
              box.add({
                'id': DateTime.now().microsecondsSinceEpoch.toString(),
                'food': food.text,
                'amount': int.parse(amount.text),
                'unit': unit,
                'date': DateFormat('yyyy-MM-dd').format(DateTime.now())
              });
              food.clear();
              amount.clear();
              setState(() {});
            },
            child: const Text('保存'),
          )
        ]),
      ),
      Expanded(
        child: ListView(
          children: dates.map((d) {
            final items = grouped[d]!;
            return ExpansionTile(
              title: Text(d, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('共 ${items.length} 项'),
              initiallyExpanded: true,
              children: items.map((item) {
                return ListTile(
                  title: Text(item['food'] ?? '未知食物'),
                  subtitle: Text('${item["amount"] ?? 0} ${item["unit"] ?? "g"}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () {
                            final fc = TextEditingController(text: item['food']);
                            final ac = TextEditingController(text: item['amount']?.toString() ?? '0');
                            showDialog(
                                context: context,
                                builder: (_) => AlertDialog(
                                  content: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      TextField(controller: fc, decoration: const InputDecoration(labelText: '食物名称')),
                                      TextField(controller: ac, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '数量'))
                                    ],
                                  ),
                                  actions: [
                                    TextButton(
                                        onPressed: () {
                                          if (fc.text.isEmpty || ac.text.isEmpty) return;
                                          box.put(item['key'], {
                                            ...item,
                                            'food': fc.text,
                                            'amount': int.parse(ac.text)
                                          });
                                          Navigator.pop(context);
                                          setState(() {});
                                        },
                                        child: const Text('保存'))
                                  ],
                                ));
                          }),
                      IconButton(
                          icon: const Icon(Icons.delete),
                          onPressed: () {
                            box.delete(item['key']);
                            setState(() {});
                          })
                    ],
                  ),
                );
              }).toList(),
            );
          }).toList(),
        ),
      )
    ]);
  }
}