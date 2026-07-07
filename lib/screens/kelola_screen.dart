import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:excel/excel.dart';
import 'package:intl/intl.dart';
import '../widgets/animated_dialog.dart';
import 'kelola_jenis_servis_screen.dart';
import 'kelola_merk_screen.dart';
import 'kelola_seri_screen.dart';
import 'kelola_kupon_screen.dart';
import 'kelola_voucher_screen.dart';
import 'kelola_pelanggan_screen.dart';
import 'penukaran_screen.dart';
import 'kelola_garansi_screen.dart';

class KelolaScreen extends StatefulWidget {
  const KelolaScreen({super.key});

  @override
  State<KelolaScreen> createState() => _KelolaScreenState();
}

class _KelolaScreenState extends State<KelolaScreen> {
  late List<Map<String, dynamic>> menuItems;
  late List<List<Color>> iconGradients;
  String? _selectedDataMenu;

  Future<String> _getDownloadsPath() async {
    try {
      // Use same location as kupon & voucher PDFs: /storage/emulated/0/Documents
      final baseDir = Directory('/storage/emulated/0/Documents/PilotFinance');
      
      // Create folder if it doesn't exist
      if (!await baseDir.exists()) {
        await baseDir.create(recursive: true);
      }
      
      return baseDir.path;
    } catch (e) {
      // Fallback to Documents folder without subfolder
      return '/storage/emulated/0/Documents';
    }
  }

  @override
  void initState() {
    super.initState();
    menuItems = [
      {
        'title': 'Kelola Garansi',
        'subtitle': 'Atur masa garansi',
        'icon': Icons.timer_outlined,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const KelolaGaransiScreen()),
          );
        },
      },
      {
        'title': 'Kelola Perangkat',
        'subtitle': 'Tambah / edit perangkat',
        'icon': Icons.devices,
        'onTap': () => _showPerangkatDialog(),
      },
      {
        'title': 'Kelola\nKupon',
        'subtitle': 'Kartu kupon & status',
        'icon': Icons.card_giftcard,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const KelolaKuponScreen()),
          );
        },
      },
      {
        'title': 'Kelola Voucher',
        'subtitle': 'Tipe & diskon voucher',
        'icon': Icons.redeem,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const KelolaVoucherScreen()),
          );
        },
      },
      {
        'title': 'Kelola Pelanggan',
        'subtitle': 'Data pelanggan',
        'icon': Icons.person_add_alt_1,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const KelolaPelangganScreen()),
          );
        },
      },
      {
        'title': 'Penukaran Voucher',
        'subtitle': 'Tukar kupon menjadi voucher',
        'icon': Icons.qr_code_scanner,
        'onTap': () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const PenukaranScreen()),
          );
        },
      },
    ];
    

    iconGradients = [
      [Color(0xFF0B63D4), Color(0xFF4EA8FF)],
      [Color(0xFF6A5AE0), Color(0xFFB27BFF)],
      [Color(0xFF16A07A), Color(0xFF5BE2B6)],
      [Color(0xFFFF6B6B), Color(0xFFFFC1C1)],
      [Color(0xFF4EA8FF), Color(0xFF70D7FF)],
      [Color(0xFFFF66B0), Color(0xFFFFA3D1)], // pink variant
    ];

    _selectedDataMenu = 'Semua';
  }

  // helper to map titles to collection names (best-effort)
  // returns list of collections for "Kelola Perangkat" (3 sheets), single item list for others
  List<String> _collectionsForTitle(String rawTitle) {
    final title = rawTitle.replaceAll('\n', ' ').toLowerCase();
    if (title == 'semua') return ['semua'];
    if (title.contains('garansi')) return ['garansi'];
    if (title.contains('perangkat') || title.contains('device')) {
      // Special: Perangkat splits into 3 sheets
      return ['merk', 'seri', 'jenis_servis'];
    }
    if (title.contains('kupon')) return ['kupon'];
    if (title.contains('voucher')) return ['vouchers']; // Note: Firebase collection is "vouchers" (plural)
    if (title.contains('pelanggan') || title.contains('customer')) return ['pelanggan'];
    if (title.contains('penukaran')) return ['penukaran'];
    // fallback: use a normalized form
    return [title.split(' ').first];
  }

  DateTime _rangeStartFor(String range) {
    final now = DateTime.now();
    if (range == 'Minggu ini') {
      final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
      return DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
    } else if (range == 'Bulan ini') {
      return DateTime(now.year, now.month, 1);
    } else if (range == 'Tahun ini') {
      return DateTime(now.year, 1, 1);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  Future<void> _confirmAndDownload() async {
    final sel = _selectedDataMenu ?? '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Konfirmasi Download'),
          content: Text('Download "$sel"?'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Batal')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Download')),
          ],
        );
      },
    );
    if (confirmed == true) {
      await _exportExcel(sel, 'Semua'); // Always use 'Semua' to get all data
    }
  }

  Future<void> _exportExcel(String selectedTitle, String range) async {
    // show progress dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Memproses Download'),
        content: const SizedBox(height: 50, child: Center(child: CircularProgressIndicator())),
      ),
    );

    final excel = Excel.createExcel();
    final now = DateTime.now();
    final start = range == 'Semua' ? DateTime.fromMillisecondsSinceEpoch(0) : _rangeStartFor(range);
    
    // Get list of types to process
    List<String> types = [];
    if (selectedTitle == 'Semua') {
      types = menuItems.map((m) => m['title'] as String).toList();
    } else {
      types = [selectedTitle];
    }
    
    try {
      for (final t in types) {
        // Get list of collections for this title (e.g., Perangkat → [merk, seri, jenis_servis])
        final collectionNames = _collectionsForTitle(t);
        
        for (final collectionName in collectionNames) {
          // Fetch all data from Firebase based on collection
          QuerySnapshot<Map<String, dynamic>>? snap;
          try {
            if (range == 'Semua') {
              // Get all documents without date filter
              snap = await FirebaseFirestore.instance.collection(collectionName).get();
            } else {
              // Try to filter by date range - attempt multiple timestamp field names
              final startTs = Timestamp.fromDate(start);
              final endTs = Timestamp.fromDate(now);
              
              // Try timestamp field
              try {
                snap = await FirebaseFirestore.instance.collection(collectionName)
                    .where('timestamp', isGreaterThanOrEqualTo: startTs)
                    .where('timestamp', isLessThanOrEqualTo: endTs)
                    .get();
              } catch (e1) {
                // Try created_at field
                try {
                  snap = await FirebaseFirestore.instance.collection(collectionName)
                      .where('created_at', isGreaterThanOrEqualTo: startTs)
                    .where('created_at', isLessThanOrEqualTo: endTs)
                    .get();
                } catch (e2) {
                  // Try createdAt field
                  try {
                    snap = await FirebaseFirestore.instance.collection(collectionName)
                        .where('createdAt', isGreaterThanOrEqualTo: startTs)
                    .where('createdAt', isLessThanOrEqualTo: endTs)
                    .get();
                  } catch (e3) {
                    // Try tanggal field (Indonesian)
                    try {
                      snap = await FirebaseFirestore.instance.collection(collectionName)
                          .where('tanggal', isGreaterThanOrEqualTo: startTs)
                      .where('tanggal', isLessThanOrEqualTo: endTs)
                      .get();
                    } catch (e4) {
                      // Fallback: fetch all data from this collection
                      snap = await FirebaseFirestore.instance.collection(collectionName).get();
                    }
                  }
                }
              }
            }
          } catch (e) {
            // Create empty snapshot if query fails completely
            snap = await FirebaseFirestore.instance.collection(collectionName).limit(0).get();
          }

          final sheetName = collectionName.length > 30 ? collectionName.substring(0, 30) : collectionName;
          final Sheet sheet = excel[sheetName];

          // Build headers from first document keys, sorted alphabetically
          List<String> headers = [];
          if (snap.docs.isNotEmpty) {
            final firstData = snap.docs.first.data();
            headers = (firstData.keys.toList())..sort();
          } else {
            headers = ['id'];
          }
          sheet.appendRow(headers);

          // Add data rows
          for (final doc in snap.docs) {
            final data = doc.data();
            final row = headers.map((h) {
              final v = data[h];
              if (v is Timestamp) {
                return DateFormat('yyyy-MM-dd HH:mm:ss').format(v.toDate());
              } else if (v is DateTime) {
                return DateFormat('yyyy-MM-dd HH:mm:ss').format(v);
              } else if (v == null) {
                return '';
              }
              return v.toString();
            }).toList();
            sheet.appendRow(row);
          }
        }
      }

      final bytes = excel.encode();
      if (bytes == null) throw Exception('Gagal membangun file Excel');

      // get downloads directory path
      final downloadsPath = await _getDownloadsPath();
      final fileName = 'pilot_finance_export_${DateTime.now().millisecondsSinceEpoch}.xlsx';
      final file = File('$downloadsPath/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      // close progress dialog
      if (mounted) Navigator.of(context).pop();

      // show success message
      if (mounted) {
        showSuccessDialog(
          context,
          title: 'Berhasil',
          message: 'File berhasil diunduh',
        );
      }
    } catch (e) {
      // close progress dialog
      if (mounted) Navigator.of(context).pop();

      // show error message
      if (mounted) {
        showErrorDialog(
          context,
          title: 'Gagal',
          message: 'Gagal membuat file: $e',
        );
      }
    }
  }

  Future<String?> _showSelectionDialog(List<String> options, String title) {
    return showDialog<String>(
      context: context,
      builder: (context) {
        final maxH = min(MediaQuery.of(context).size.height * 0.6, 56.0 * options.length + 56);
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            height: maxH,
            child: Column(
              children: [
                Container(
                  height: 56,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                      IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: Colors.white)),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemBuilder: (context, index) {
                      final v = options[index];
                      return ListTile(
                        title: Text(v),
                        onTap: () => Navigator.of(context).pop(v),
                      );
                    },
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemCount: options.length,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPerangkatDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  height: 56,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 16),
                      const Expanded(child: Text('Kelola Perangkat', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                      IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close, color: Colors.white)),
                    ],
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.build_circle_outlined, color: Color(0xFF0B63D4)),
                  title: const Text('Kelola Jenis Servis'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const KelolaJenisServisScreen()));
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.branding_watermark, color: Color(0xFF4EA8FF)),
                  title: const Text('Kelola Merk HP'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const KelolaMerkScreen()));
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.confirmation_number_outlined, color: Color(0xFF16A07A)),
                  title: const Text('Kelola Seri HP'),
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const KelolaSeriScreen()));
                  },
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // ✅ IMMEDIATE navigation: Don't wait for Excel export to complete
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FB),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Container(
            padding: const EdgeInsets.only(top: 26, left: 16, right: 16, bottom: 12),
            decoration: const BoxDecoration(
              gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
              borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                children: [
                  const CircleAvatar(radius: 26, backgroundColor: Colors.white24, child: Icon(Icons.settings, color: Colors.white, size: 26)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text('Kelola Data', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Atur kupon, voucher, pelanggan, dan lainnya', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(onPressed: () {}, icon: const Icon(Icons.search, color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        // reduce bottom padding so content sits closer to the bottom navbar
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 4))],
                ),
                child: Row(
                  children: const [
                    Icon(Icons.info_outline, color: Color(0xFF0B63D4)),
                    SizedBox(width: 10),
                    Expanded(child: Text('Kelola master data di sini. Sentuh sebuah ikon untuk membuka halaman manajemen.', style: TextStyle(fontSize: 13))),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                itemCount: menuItems.length,
                itemBuilder: (context, index) {
                  final item = menuItems[index];
                  final gradient = iconGradients[index % iconGradients.length];
                  return Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: item['onTap'],
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 4))],
                            ),
                            child: Center(
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(gradient: LinearGradient(colors: gradient), shape: BoxShape.circle),
                                child: Center(child: Icon(item['icon'], color: Colors.white, size: 22)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Builder(builder: (context) {
                            final raw = item['title'] as String;
                            final parts = raw.contains('\n') ? raw.split('\n') : raw.split(' ');
                            final top = parts.isNotEmpty ? parts.first : raw;
                            final bottom = parts.length > 1 ? parts.sublist(1).join(' ') : '';
                            return Column(
                              children: [
                                Text(top, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w300), textAlign: TextAlign.center),
                                if (bottom.isNotEmpty) Text(bottom, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w300), textAlign: TextAlign.center),
                              ],
                            );
                          }),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 10),

              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 4))],
                ),
                child: Column(
                  children: [
                    Align(alignment: Alignment.centerLeft, child: Text('Download Data', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade800))),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () async {
                        final options = ['Semua', ...menuItems.map((m) => m['title'] as String)];
                        final sel = await _showSelectionDialog(options, 'Pilih Nama Data');
                        if (sel != null) setState(() => _selectedDataMenu = sel);
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.all(Radius.circular(8)), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Color(0xFFF6F8FB),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(_selectedDataMenu ?? '', style: const TextStyle(fontSize: 14)), const Icon(Icons.arrow_drop_down)]),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _confirmAndDownload,
                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), elevation: 2, backgroundColor: Colors.transparent, shadowColor: Colors.transparent),
                        child: Ink(
                          decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]), borderRadius: BorderRadius.all(Radius.circular(10))),
                          child: Container(alignment: Alignment.center, child: const Text('Download Data', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)), padding: const EdgeInsets.symmetric(vertical: 14)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}



