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
    // 读取时将原始物理 key 保存起来，防止错位
    final data = [];
    for (int i = 0; i < box.length; i++) {
      final item = Map<String, dynamic>.from(box.getAt(i));
      item['key'] = box.keyAt(i);
      data.add(item);
    }

    // 【修改】：截取最近15次记录用于折线图绘制
    final recentData = data.length > 15 ? data.sublist(data.length - 15) : data;

    List<LineChartBarData> lines = [];
    for (int i = 1; i < recentData.length; i++) {
      final p = (recentData[i - 1]['weight'] as num).toDouble();
      final n = (recentData[i]['weight'] as num).toDouble();
      lines.add(LineChartBarData(
        spots: [FlSpot((i - 1).toDouble(), p), FlSpot(i.toDouble(), n)],
        color: n >= p ? Colors.red : Colors.green,
        barWidth: 4,
      ));
    }

    return Column(children: [
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
      SizedBox(
        height: 250,
        child: recentData.length < 2
            ? const Center(child: Text('至少两条记录'))
            : Padding(
          padding: const EdgeInsets.only(right: 20, top: 10),
          child: LineChart(LineChartData(
            lineBarsData: lines,
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    int i = value.toInt();
                    if (i < 0 || i >= recentData.length) return const SizedBox();
                    final dt = DateTime.parse(recentData[i]['time']);
                    return SideTitleWidget(
                      axisSide: meta.axisSide,
                      child: Text(DateFormat('MM-dd\nHH:mm').format(dt),
                          style: const TextStyle(fontSize: 9),
                          textAlign: TextAlign.center),
                    );
                  },
                ),
              ),
            ),
          )),
        ),
      ),
      Expanded(
        child: ListView.builder(
          itemCount: data.length,
          itemBuilder: (cxt, i) {
            final item = data[i];
            return ListTile(
              title: Text('${item["weight"]}斤'),
              subtitle: Text(DateFormat('yyyy-MM-dd HH:mm')
                  .format(DateTime.parse(item['time']))),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () {
                        final ec = TextEditingController(text: item['weight'].toString());
                        showDialog(
                            context: context,
                            builder: (_) => AlertDialog(
                              content: TextField(
                                controller: ec,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              ),
                              actions: [
                                TextButton(
                                    onPressed: () {
                                      if (ec.text.isEmpty) return;
                                      // 使用精确的 key 更新
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
                      icon: const Icon(Icons.delete),
                      onPressed: () {
                        // 使用精确的 key 删除
                        box.delete(item['key']);
                        setState(() {});
                      })
                ],
              ),
            );
          },
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
      // 【修复核心】：如果数据库里的旧数据没有 'date' 字段，提供一个默认值，防止 Null 崩溃
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