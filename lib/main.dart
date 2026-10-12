import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

void main() {
  runApp(const BomCostApp());
}

class BomCostApp extends StatelessWidget {
  const BomCostApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'حساب كلفة القالب والتركيبة الكيميائية',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blueGrey,
        useMaterial3: false,
        scaffoldBackgroundColor: const Color(0xFFE6E6E6),
      ),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: HomeScreen(),
      ),
    );
  }
}

class BomItemRowData {
  String selectedMaterial;
  String weight;
  String price;

  BomItemRowData({
    required this.selectedMaterial,
    required this.weight,
    required this.price,
  });

  Map<String, dynamic> toJson() => {
    'selectedMaterial': selectedMaterial,
    'weight': weight,
    'price': price,
  };

  factory BomItemRowData.fromJson(Map<String, dynamic> json) => BomItemRowData(
    selectedMaterial: json['selectedMaterial'] ?? 'اختر المادة',
    weight: json['weight'] ?? '0',
    price: json['price'] ?? '0',
  );
}

class SavedBomModel {
  final String moldNumber;
  final String clientName;
  final String moldName;
  final String laborCost;
  final List<BomItemRowData> rows;

  final double totalWeight;
  final double rawMaterialCost;
  final double totalCost;

  SavedBomModel({
    required this.moldNumber,
    required this.clientName,
    required this.moldName,
    required this.laborCost,
    required this.rows,
    required this.totalWeight,
    required this.rawMaterialCost,
    required this.totalCost,
  });

  Map<String, dynamic> toJson() => {
    'moldNumber': moldNumber,
    'clientName': clientName,
    'moldName': moldName,
    'laborCost': laborCost,
    'rows': rows.map((e) => e.toJson()).toList(),
    'totalWeight': totalWeight,
    'rawMaterialCost': rawMaterialCost,
    'totalCost': totalCost,
  };

  factory SavedBomModel.fromJson(Map<String, dynamic> json) => SavedBomModel(
    moldNumber: json['moldNumber'] ?? '',
    clientName: json['clientName'] ?? '',
    moldName: json['moldName'] ?? '',
    laborCost: json['laborCost'] ?? '0',
    rows: (json['rows'] as List?)?.map((e) => BomItemRowData.fromJson(e)).toList() ?? [],
    totalWeight: (json['totalWeight'] ?? 0.0).toDouble(),
    rawMaterialCost: (json['rawMaterialCost'] ?? 0.0).toDouble(),
    totalCost: (json['totalCost'] ?? 0.0).toDouble(),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final _moldNumCtrl = TextEditingController();
  final _clientNameCtrl = TextEditingController();
  final _moldNameCtrl = TextEditingController();
  final _laborCostCtrl = TextEditingController(text: '0');

  final List<String> availableMaterials = [
    'اختر المادة',
    'استيريك',
    'اشقر طري جدا',
    'اشقر غامق',
    'اشقر كاشف',
    'اي بي دي ام',
    'بربونات',
    'بربونات طراحي',
    'بودرة بيضاء',
    'بودرة طرية',
    'تيتان',
    'خفيف',
    'دارنيت',
    'دوا TMQ',
    'دوا اوكس 54',
    'دوا TMTD',
    'دوا CBS',
    'دوا D P G',
    'دوا MBT',
    'دوا MBTS',
    'دوا ZDEC',
    'دوا سلكون',
    'دوا مبطئ P V I / CTP',
    'دوا مخلط',
    'روزين',
    'زنك اصلي',
    'زنك عادي',
    'زهرة',
    'زهرة حب',
    'زيت اسود',
    'زيت اصفر',
    'زيت ضد الزيت',
    'سيليكون',
    'شحوار 330',
    'شحوار 550',
    'شمع',
    'صابون قوالب',
    'صباع',
    'عطر',
    'قهوة مضاض اكسده',
    'كريب',
    'كومة اجنبية',
    'كومة اشقر',
    'كومة زيت اجنبية',
    'كومة فيها درس',
    'مجدد',
  ];

  Map<String, String> materialPricesReference = {};

  final List<String> _selectedMaterials = List.filled(15, 'اختر المادة');
  final List<TextEditingController> _weightControllers = List.generate(15, (_) => TextEditingController(text: '0'));
  final List<TextEditingController> _priceControllers = List.generate(15, (_) => TextEditingController(text: '0'));

  double _totalWeight = 0.0;
  List<double> _ratios = List.filled(15, 0.0);
  double _rawMaterialCost = 0.0;
  double _totalCost = 0.0;

  List<SavedBomModel> _savedMoldsList = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadPricesReference();
    _loadMoldsFromDisk();
  }

  double _parse(String text) => double.tryParse(text) ?? 0.0;

  Future<void> _loadPricesReference() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('material_prices_ref_key');
    if (data != null) {
      setState(() {
        materialPricesReference = Map<String, String>.from(json.decode(data));
      });
    }
  }

  Future<void> _savePricesReference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('material_prices_ref_key', json.encode(materialPricesReference));
  }

  void _calculateTotal() {
    double sumWeight = 0.0;
    List<double> parsedWeights = [];
    List<double> parsedPrices = [];

    for (int i = 0; i < 15; i++) {
      double w = _parse(_weightControllers[i].text);
      double p = _parse(_priceControllers[i].text);
      parsedWeights.add(w);
      parsedPrices.add(p);
      sumWeight += w;
    }

    _totalWeight = sumWeight;

    _rawMaterialCost = 0.0;
    if (_totalWeight > 0) {
      for (int i = 0; i < 15; i++) {
        _ratios[i] = (parsedWeights[i] / _totalWeight) * 100;
        _rawMaterialCost += (_ratios[i] / 100) * parsedPrices[i];
      }
    } else {
      _ratios = List.filled(15, 0.0);
      _rawMaterialCost = 0.0;
    }

    double labor = _parse(_laborCostCtrl.text);
    _totalCost = _rawMaterialCost + labor;

    setState(() {});
  }

  Future<void> _saveMoldsToDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final String encodedData = json.encode(_savedMoldsList.map((e) => e.toJson()).toList());
    await prefs.setString('saved_chemical_molds_v12_key', encodedData);
  }

  Future<void> _loadMoldsFromDisk() async {
    final prefs = await SharedPreferences.getInstance();
    final String? encodedData = prefs.getString('saved_chemical_molds_v12_key');
    if (encodedData != null) {
      final List decoded = json.decode(encodedData);
      setState(() {
        _savedMoldsList = decoded.map((e) => SavedBomModel.fromJson(e)).toList();
      });
    }
  }

  void _saveCurrentMold() {
    _calculateTotal();

    List<BomItemRowData> rowsData = [];
    for (int i = 0; i < 15; i++) {
      rowsData.add(BomItemRowData(
        selectedMaterial: _selectedMaterials[i],
        weight: _weightControllers[i].text,
        price: _priceControllers[i].text,
      ));
    }

    final mold = SavedBomModel(
      moldNumber: _moldNumCtrl.text.isEmpty ? '-' : _moldNumCtrl.text,
      clientName: _clientNameCtrl.text.isEmpty ? '-' : _clientNameCtrl.text,
      moldName: _moldNameCtrl.text.isEmpty ? 'قالب جديد' : _moldNameCtrl.text,
      laborCost: _laborCostCtrl.text,
      rows: rowsData,
      totalWeight: _totalWeight,
      rawMaterialCost: _rawMaterialCost,
      totalCost: _totalCost,
    );

    setState(() {
      _savedMoldsList.removeWhere((e) => e.moldNumber == mold.moldNumber && e.moldName == mold.moldName);
      _savedMoldsList.add(mold);
    });

    _savePricesReference();
    _saveMoldsToDisk();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم حفظ القالب بنجاح')),
    );
  }

  void _loadMoldToScreen(SavedBomModel mold) {
    setState(() {
      _moldNumCtrl.text = mold.moldNumber;
      _clientNameCtrl.text = mold.clientName;
      _moldNameCtrl.text = mold.moldName;
      _laborCostCtrl.text = mold.laborCost;

      for (int i = 0; i < 15; i++) {
        if (i < mold.rows.length) {
          _selectedMaterials[i] = mold.rows[i].selectedMaterial;
          _weightControllers[i].text = mold.rows[i].weight;
          _priceControllers[i].text = mold.rows[i].price;
        } else {
          _selectedMaterials[i] = 'اختر المادة';
          _weightControllers[i].text = '0';
          _priceControllers[i].text = '0';
        }
      }
    });

    _calculateTotal();
    _tabController.animateTo(0);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('تم استرجاع بيانات القالب "${mold.moldName}"')),
    );
  }

  void _deleteMold(int index) {
    setState(() {
      _savedMoldsList.removeAt(index);
    });
    _saveMoldsToDisk();
  }

  void _showImageReportDialog(SavedBomModel mold) {
    final GlobalKey repKey = GlobalKey();

    List<Map<String, String>> activeRows = [];
    int counter = 1;
    for (var r in mold.rows) {
      if (r.selectedMaterial != 'اختر المادة' && r.selectedMaterial.isNotEmpty) {
        double w = double.tryParse(r.weight) ?? 0.0;
        if (w > 0) {
          activeRows.add({
            'num': counter.toString(),
            'name': r.selectedMaterial,
            'weight': w.toStringAsFixed(2),
          });
          counter++;
        }
      }
    }

    while (activeRows.length < 16) {
      activeRows.add({
        'num': counter.toString(),
        'name': '0',
        'weight': '0',
      });
      counter++;
    }

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            contentPadding: const EdgeInsets.all(8),
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('معاينة التقرير', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(dialogContext).pop(),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: RepaintBoundary(
                key: repKey,
                child: Container(
                  color: Colors.white,
                  padding: const EdgeInsets.all(12),
                  width: 340,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Table(
                        border: TableBorder.all(color: Colors.black, width: 1),
                        columnWidths: const {
                          0: FlexColumnWidth(2),
                          1: FlexColumnWidth(1),
                        },
                        children: [
                          TableRow(
                            children: [
                              Padding(padding: const EdgeInsets.all(6), child: Text(mold.clientName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black))),
                              const Padding(padding: EdgeInsets.all(6), child: Text('اسم الزبون', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black))),
                            ],
                          ),
                          TableRow(
                            children: [
                              Padding(padding: const EdgeInsets.all(6), child: Text(mold.moldName, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black))),
                              const Padding(padding: const EdgeInsets.all(6), child: Text('اسم القالب', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black))),
                            ],
                          ),
                          TableRow(
                            children: [
                              Padding(padding: const EdgeInsets.all(6), child: Text(mold.moldNumber, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black))),
                              const Padding(padding: const EdgeInsets.all(6), child: Text('رقم القالب', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black))),
                            ],
                          ),
                        ],
                      ),
                      Table(
                        border: TableBorder.all(color: Colors.black, width: 1),
                        columnWidths: const {
                          0: FlexColumnWidth(1.2),
                          1: FlexColumnWidth(2.5),
                          2: FlexColumnWidth(0.8),
                        },
                        children: activeRows.map((row) {
                          return TableRow(
                            children: [
                              Padding(padding: const EdgeInsets.all(5), child: Text(row['weight']!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.black))),
                              Padding(padding: const EdgeInsets.all(5), child: Text(row['name']!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.black))),
                              Padding(padding: const EdgeInsets.all(5), child: Text(row['num']!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.black))),
                            ],
                          );
                        }).toList(),
                      ),
                      Table(
                        border: TableBorder.all(color: Colors.black, width: 1),
                        columnWidths: const {
                          0: FlexColumnWidth(1.2),
                          1: FlexColumnWidth(3.3),
                        },
                        children: [
                          TableRow(
                            children: [
                              Padding(padding: const EdgeInsets.all(6), child: Text(mold.totalWeight.toStringAsFixed(2), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black))),
                              const Padding(padding: const EdgeInsets.all(6), child: Text('الوزن الكلي', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black))),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                icon: const Icon(Icons.share, size: 16),
                label: const Text('مشاركة الصورة أو حفظها'),
                onPressed: () async {
                  try {
                    RenderRepaintBoundary boundary = repKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
                    ui.Image image = await boundary.toImage(pixelRatio: 3.0);
                    ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                    Uint8List pngBytes = byteData!.buffer.asUint8List();

                    await Printing.sharePdf(bytes: pngBytes, filename: 'Mold_Report.jpg');
                  } catch (e) {
                    if (dialogContext.mounted) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                        SnackBar(content: Text('حدث خطأ أثناء المشاركة: $e')),
                      );
                    }
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCenteredInput(String label, TextEditingController controller, {bool isNumber = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 130,
            child: Text(':$label', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          ),
          SizedBox(
            width: 160,
            height: 32,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.center,
              keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                border: OutlineInputBorder(),
                fillColor: Colors.white,
                filled: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('حساب كلفة القالب والتركيبة الكيميائية', style: TextStyle(fontSize: 13)),
        backgroundColor: const Color(0xFFDCDCDC),
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: const Color(0xFFDCDCDC),
              child: TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.black,
                unselectedLabelColor: Colors.black87,
                indicator: const BoxDecoration(color: Color(0xFFC0C0C0)),
                tabs: const [
                  Tab(text: 'البيانات والتكاليف الأساسية'),
                  Tab(text: 'جدول المواد الكيميائية (15)'),
                  Tab(text: 'مرجعية الأسعار'),
                  Tab(text: 'القوالب المحفوظة'),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(6.0),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade500),
                    color: const Color(0xFFD9D9D9),
                  ),
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(12.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('معلومات القالب والعميل', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            _buildCenteredInput('رقم القالب', _moldNumCtrl, isNumber: true),
                            _buildCenteredInput('اسم العميل', _clientNameCtrl),
                            _buildCenteredInput('اسم القالب', _moldNameCtrl),
                            const Divider(),
                            const Text('التكاليف المباشرة والأجور', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            _buildCenteredInput('أجور التشغيل', _laborCostCtrl, isNumber: true),
                          ],
                        ),
                      ),
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('المواد الكيميائية (اختر المادة من القائمة المنسدلة):', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Table(
                                defaultColumnWidth: const FixedColumnWidth(130),
                                border: TableBorder.all(color: Colors.grey.shade600),
                                children: [
                                  TableRow(
                                    decoration: const BoxDecoration(color: Color(0xFFC0C0C0)),
                                    children: [
                                      const Padding(padding: EdgeInsets.all(4), child: Text('نوع الخصلة', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold))),
                                      ...List.generate(15, (i) => Padding(padding: const EdgeInsets.all(4), child: Text('مادة ${i + 1}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)))),
                                    ],
                                  ),
                                  TableRow(
                                    children: [
                                      const Padding(padding: EdgeInsets.all(4), child: Text('المادة الكيميائية', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                      ...List.generate(15, (i) => Container(
                                        height: 32,
                                        color: Colors.white,
                                        child: DropdownButtonHideUnderline(
                                          child: DropdownButton<String>(
                                            value: availableMaterials.contains(_selectedMaterials[i]) ? _selectedMaterials[i] : 'اختر المادة',
                                            isExpanded: true,
                                            alignment: Alignment.center,
                                            style: const TextStyle(fontSize: 11, color: Colors.black, fontWeight: FontWeight.bold),
                                            items: availableMaterials.map((String mat) {
                                              return DropdownMenuItem<String>(
                                                value: mat,
                                                child: Text(mat, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis),
                                              );
                                            }).toList(),
                                            onChanged: (String? val) {
                                              setState(() {
                                                if (val != null) {
                                                  _selectedMaterials[i] = val;
                                                  if (materialPricesReference.containsKey(val)) {
                                                    _priceControllers[i].text = materialPricesReference[val]!;
                                                  }
                                                }
                                              });
                                            },
                                          ),
                                        ),
                                      )),
                                    ],
                                  ),
                                  TableRow(
                                    children: [
                                      const Padding(padding: EdgeInsets.all(4), child: Text('الوزن (kg)', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                      ...List.generate(15, (i) => SizedBox(
                                        height: 28,
                                        child: TextField(
                                          controller: _weightControllers[i],
                                          textAlign: TextAlign.center,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          decoration: const InputDecoration(contentPadding: EdgeInsets.zero, border: InputBorder.none, filled: true, fillColor: Colors.white),
                                        ),
                                      )),
                                    ],
                                  ),
                                  TableRow(
                                    children: [
                                      const Padding(padding: EdgeInsets.all(4), child: Text('النسبة (%)', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                      ...List.generate(15, (i) => Padding(padding: const EdgeInsets.all(4), child: Text('${_ratios[i].toStringAsFixed(2)}%', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)))),
                                    ],
                                  ),
                                  TableRow(
                                    children: [
                                      const Padding(padding: EdgeInsets.all(4), child: Text('السعر', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold))),
                                      ...List.generate(15, (i) => SizedBox(
                                        height: 28,
                                        child: TextField(
                                          controller: _priceControllers[i],
                                          textAlign: TextAlign.center,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                          decoration: const InputDecoration(contentPadding: EdgeInsets.zero, border: InputBorder.none, filled: true, fillColor: Colors.white),
                                        ),
                                      )),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: availableMaterials.length - 1,
                        itemBuilder: (context, index) {
                          final matName = availableMaterials[index + 1];
                          final priceCtrl = TextEditingController(text: materialPricesReference[matName] ?? '0');
                          return Card(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(matName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  SizedBox(
                                    width: 120,
                                    height: 30,
                                    child: TextField(
                                      controller: priceCtrl,
                                      textAlign: TextAlign.center,
                                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                      decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.zero, filled: true, fillColor: Colors.white),
                                      onChanged: (val) {
                                        materialPricesReference[matName] = val;
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      Column(
                        children: [
                          Expanded(
                            child: _savedMoldsList.isEmpty
                                ? const Center(child: Text('لا يوجد قوالب محفوظة حالياً'))
                                : ListView.builder(
                              itemCount: _savedMoldsList.length,
                              itemBuilder: (context, index) {
                                final item = _savedMoldsList[index];
                                return Card(
                                  margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  child: ListTile(
                                    title: Text('${item.moldName} (رقم: ${item.moldNumber}) - العميل: ${item.clientName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                    subtitle: Text('التكلفة الإجمالية: ${item.totalCost.toStringAsFixed(4)} | الوزن: ${item.totalWeight.toStringAsFixed(2)} kg'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.print, color: Colors.teal),
                                          tooltip: 'طباعة/تصدير التقرير',
                                          onPressed: () => _showImageReportDialog(item),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.download, color: Colors.blue),
                                          tooltip: 'تحميل للشاشة',
                                          onPressed: () => _loadMoldToScreen(item),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.delete, color: Colors.red),
                                          tooltip: 'حذف',
                                          onPressed: () => _deleteMold(index),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(8),
              margin: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade500),
                color: const Color(0xFFD9D9D9),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('الوزن الكلي: ${_totalWeight.toStringAsFixed(2)} kg', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Text('سعر الخامة: ${_rawMaterialCost.toStringAsFixed(4)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            Text('التكلفة الإجمالية: ${_totalCost.toStringAsFixed(4)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal)),
                          ],
                        ),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDCDCDC), foregroundColor: Colors.black),
                        onPressed: () {
                          _savePricesReference();
                          _saveCurrentMold();
                        },
                        child: const Text('حفظ القالب', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDCDCDC), foregroundColor: Colors.black),
                        onPressed: _calculateTotal,
                        child: const Text('حساب التكلفة', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}