import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pilot_finance/providers/theme_provider.dart';
import '../services/connectivity_service.dart';
import '../widgets/animated_dialog.dart';

// ==================== THEME COLORS ====================
class AppTheme {
  static const Color darkBackground = Color(0xFF0D0D19);
  static const Color darkCardBg = Color(0xFF1E1E2E);
  static final Color darkAccent = Colors.tealAccent[400]!;
  static const Color darkText = Color(0xFFFFFFFF);
  static const Color darkSecondaryText = Color(0xFF999999);

  static const Color lightBackground = Color(0xFFFAFAFA);
  static const Color lightCardBg = Color(0xFFFFFFFF);
  static final Color lightAccent = Colors.teal.shade600;
  static const Color lightText = Color(0xFF1A1A1A);
  static const Color lightSecondaryText = Color(0xFF666666);
  static const Color lightBorder = Color(0xFFE0E0E0);

  static Color bgColor(bool isDark) => isDark ? darkBackground : lightBackground;
  static Color cardColor(bool isDark) => isDark ? darkCardBg : lightCardBg;
  static Color accentColor(bool isDark) => isDark ? darkAccent : lightAccent;
  static Color textColor(bool isDark) => isDark ? darkText : lightText;
  static Color secondaryTextColor(bool isDark) => isDark ? darkSecondaryText : lightSecondaryText;
  static Color borderColor(bool isDark) => isDark ? Colors.white12 : lightBorder;
}

// ==================== MAIN SCREEN ====================
class RekapScreen extends StatefulWidget {
  const RekapScreen({super.key});
  @override
  State<RekapScreen> createState() => _RekapScreenState();
}

class _RekapScreenState extends State<RekapScreen> {
  late StreamSubscription<QuerySnapshot> _riwayatSubscription;
  late ThemeProvider _themeProvider;

  double totalPendapatanFinal = 0.0;
  double totalPengeluaranSparepart = 0.0;
  double totalMarginKotor = 0.0;
  double totalMarginBersih = 0.0;
  double baseDarurat = 0.0;
  double baseBebas = 0.0;
  double baseAman = 0.0;
  double adjustmentDarurat = 0.0;
  double adjustmentBebas = 0.0;
  double adjustmentAman = 0.0;
  double saldoDaruratFinal = 0.0;
  double saldoBebasFinal = 0.0;
  double saldoAmanFinal = 0.0;
  Map<String, int> layananTerlaris = {};
  Map<String, double> profitPerLayanan = {};
  bool isLoading = true;
  bool isAdjustmentLoaded = false;

  final currencyFormat = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
  final numberFormat = NumberFormat('#,##0', 'id_ID');

  // Format currency - gunakan K/JT hanya jika terpotong untuk menghemat ruang
  String formatCurrencyWithSuffix(double value, {bool forceAbbreviate = false}) {
    final fullFormat = currencyFormat.format(value);
    
    // Jika sudah diminta untuk abbreviate atau jika panjang text > 15 char
    if (forceAbbreviate || fullFormat.length > 15) {
      if (value.abs() >= 1000000) {
        final millions = value / 1000000;
        if (millions.abs() >= 10) {
          return '${millions.toStringAsFixed(0)}JT';
        } else {
          final formatted = millions.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');
          return '${formatted}JT';
        }
      } else if (value.abs() >= 1000) {
        final thousands = value / 1000;
        if (thousands.abs() >= 10) {
          return '${thousands.toStringAsFixed(0)}K';
        } else {
          final formatted = thousands.toStringAsFixed(1).replaceAll(RegExp(r'\.?0+$'), '');
          return '${formatted}K';
        }
      }
    }
    return fullFormat;
  }

  @override
  void initState() {
    super.initState();
    _themeProvider = ThemeProvider();
    _themeProvider.addListener(_onThemeChanged);
    _loadAdjustmentsAndStartListener();
  }

  void _onThemeChanged() {
    setState(() {});
  }

  @override
  void dispose() {
    _riwayatSubscription.cancel();
    _themeProvider.removeListener(_onThemeChanged);
    super.dispose();
  }

  // expose current theme mode so parent widgets (like a navbar) can read it
  bool get currentIsDark => _themeProvider.isDarkMode;

  Future<void> _loadAdjustments() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('keuangan_servis').doc('penyesuaian_manual').get();
      if (doc.exists) {
        final data = doc.data();
        if (mounted) {
          setState(() {
            adjustmentDarurat = (data?['adjustment_darurat'] as num?)?.toDouble() ?? 0.0;
            adjustmentBebas = (data?['adjustment_bebas'] as num?)?.toDouble() ?? 0.0;
            adjustmentAman = (data?['adjustment_aman'] as num?)?.toDouble() ?? 0.0;
          });
        }
      }
      if (mounted) setState(() => isAdjustmentLoaded = true);
    } catch (e) {
      if (mounted) setState(() => isAdjustmentLoaded = true);
    }
  }

  Future<void> _saveAdjustment() async {
    // ✅ NEW: Check internet connection BEFORE attempting Firestore operations
    final hasInternet = await ConnectivityService.hasInternetConnection();
    if (!hasInternet) {
      if (mounted) {
        showErrorDialog(
          context,
          title: 'Koneksi Tidak Tersedia',
          message: 'Tidak ada koneksi internet. Silakan cek koneksi Anda dan coba lagi.',
        );
      }
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('keuangan_servis').doc('penyesuaian_manual').set({
        'adjustment_darurat': adjustmentDarurat,
        'adjustment_bebas': adjustmentBebas,
        'adjustment_aman': adjustmentAman,
        'timestamp_update': FieldValue.serverTimestamp(),
      });
      _updateFinalBalancesInSummary();
    } catch (e) {
      // Error silently handled
    }
  }

  void _updateFinalBalancesInSummary() {
    if (!isLoading) {
      final finalDarurat = baseDarurat + adjustmentDarurat;
      final finalBebas = baseBebas + adjustmentBebas;
      final finalAman = baseAman + adjustmentAman;
      final totalFinalSaldo = finalDarurat + finalBebas + finalAman;
      _saveFinancialSummaryToFirestore(
        totalPendapatanFinal, totalPengeluaranSparepart, totalMarginKotor, totalFinalSaldo, totalMarginBersih,
        baseDarurat, baseBebas, baseAman, finalDarurat, finalBebas, finalAman,
      );
    }
  }

  void _loadAdjustmentsAndStartListener() async {
    if (mounted) setState(() => isLoading = true);
    await _loadAdjustments();
    _riwayatSubscription = FirebaseFirestore.instance.collection('riwayat').snapshots().listen((snapshot) {
      _processSnapshot(snapshot);
    }, onError: (error) {
      if (mounted) setState(() => isLoading = false);
    });
  }

  void _processSnapshot(QuerySnapshot snapshot) {
    double tempPendapatan = 0.0;
    double tempPengeluaran = 0.0;
    Map<String, int> tempLayananCount = {};
    Map<String, double> tempLayananPendapatan = {};
    Map<String, double> tempLayananPengeluaran = {};

    for (var doc in snapshot.docs) {
      final data = doc.data() as Map<String, dynamic>;
      final hargaFinal = (data['harga_servis_final'] as num?)?.toDouble() ?? 0.0;
      final hargaSparepart = (data['harga_sparepart'] as num?)?.toDouble() ?? 0.0;
      final jenisServis = data['jenis_servis'] as String? ?? 'Tidak Diketahui';
      tempPendapatan += hargaFinal;
      tempPengeluaran += hargaSparepart;
      tempLayananCount.update(jenisServis, (value) => value + 1, ifAbsent: () => 1);
      tempLayananPendapatan.update(jenisServis, (value) => value + hargaFinal, ifAbsent: () => hargaFinal);
      tempLayananPengeluaran.update(jenisServis, (value) => value + hargaSparepart, ifAbsent: () => hargaSparepart);
    }

    Map<String, double> tempProfitPerLayanan = {};
    tempLayananPendapatan.forEach((service, revenue) {
      final cost = tempLayananPengeluaran[service] ?? 0.0;
      tempProfitPerLayanan[service] = revenue - cost;
    });

    double marginKotor = tempPendapatan - tempPengeluaran;
    int totalTransaksi = snapshot.docs.length;
    double marginBersih = marginKotor - (10000 * totalTransaksi);
    final effectiveMarginBersih = marginBersih > 0 ? marginBersih : 0.0;
    final baseDaruratCalculated = effectiveMarginBersih * 0.15;
    final baseBebasCalculated = effectiveMarginBersih * 0.10;
    final baseAmanCalculated = effectiveMarginBersih - (baseDaruratCalculated + baseBebasCalculated);
    final finalDarurat = baseDaruratCalculated + adjustmentDarurat;
    final finalBebas = baseBebasCalculated + adjustmentBebas;
    final finalAman = baseAmanCalculated + adjustmentAman;
    final totalFinalSaldo = finalDarurat + finalBebas + finalAman;

    if (mounted) {
      setState(() {
        totalPendapatanFinal = tempPendapatan;
        totalPengeluaranSparepart = tempPengeluaran;
        totalMarginKotor = marginKotor;
        totalMarginBersih = marginBersih;
        baseDarurat = baseDaruratCalculated;
        baseBebas = baseBebasCalculated;
        baseAman = baseAmanCalculated;
        saldoDaruratFinal = finalDarurat;
        saldoBebasFinal = finalBebas;
        saldoAmanFinal = finalAman;
        layananTerlaris = tempLayananCount;
        profitPerLayanan = tempProfitPerLayanan;
        isLoading = false;
      });
      _saveFinancialSummaryToFirestore(
        tempPendapatan, tempPengeluaran, marginKotor, totalFinalSaldo, marginBersih,
        baseDaruratCalculated, baseBebasCalculated, baseAmanCalculated, finalDarurat, finalBebas, finalAman,
      );
    }
  }

  Future<void> _saveFinancialSummaryToFirestore(
    double pendapatan, double pengeluaran, double marginKotor, double saldoTotalAkhir, double marginBersih,
    double saldoDaruratBase, double saldoBebasBase, double saldoAmanBase,
    double saldoDaruratFinal, double saldoBebasFinal, double saldoAmanFinal,
  ) async {
    // ✅ NEW: Check internet connection BEFORE attempting Firestore operations
    final hasInternet = await ConnectivityService.hasInternetConnection();
    if (!hasInternet) {
      // Silently fail if offline - this is a background operation
      return;
    }

    try {
      await FirebaseFirestore.instance.collection('keuangan_servis').doc('rekap_total').set({
        'timestamp_rekap': FieldValue.serverTimestamp(),
        'pendapatan': pendapatan,
        'pengeluaran': pengeluaran,
        'margin_kotor': marginKotor,
        'saldo_akhir_total': saldoTotalAkhir,
        'margin_bersih': marginBersih,
        'saldo_darurat_base': saldoDaruratBase,
        'saldo_bebas_base': saldoBebasBase,
        'saldo_aman_base': saldoAmanBase,
        'saldo_darurat_final': saldoDaruratFinal,
        'saldo_bebas_final': saldoBebasFinal,
        'saldo_aman_final': saldoAmanFinal,
      });
    } catch (e) {
      // Error silently handled
    }
  }

  // ==================== UI BUILDERS ====================

  Widget _buildGlassCard({required Widget child, double padding = 16.0, double blur = 15.0, bool isDark = true}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20.0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: Container(
          decoration: BoxDecoration(
            color: isDark 
              ? Colors.white.withValues(alpha: 0.08) 
              : Colors.white,
            borderRadius: BorderRadius.circular(20.0),
            border: Border.all(
              color: isDark 
                ? Colors.white.withValues(alpha: 0.15) 
                : Colors.grey.shade200,
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.3 : 0.08),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          padding: EdgeInsets.all(padding),
          child: child,
        ),
      ),
    );
  }

  void _showAdjustmentDialog(String title, double baseValue, double currentAdjustment, double currentFinalBalance, Function(double) onSave) {
    final isDark = _themeProvider.isDarkMode;
    final TextEditingController controller = TextEditingController(text: numberFormat.format(currentAdjustment.abs()));
    ValueNotifier<bool> isPositive = ValueNotifier(currentAdjustment >= 0);

    double parseInput(String text) {
      try {
        String cleanText = text.replaceAll('.', '');
        return double.tryParse(cleanText) ?? 0.0;
      } catch (e) {
        return 0.0;
      }
    }

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Theme(
          data: ThemeData(
            useMaterial3: true,
            brightness: isDark ? Brightness.dark : Brightness.light,
            scaffoldBackgroundColor: AppTheme.bgColor(isDark),
            dialogBackgroundColor: AppTheme.cardColor(isDark),
            colorScheme: ColorScheme(
              brightness: isDark ? Brightness.dark : Brightness.light,
              primary: AppTheme.accentColor(isDark),
              onPrimary: Colors.white,
              secondary: AppTheme.accentColor(isDark),
              onSecondary: Colors.black,
              error: Colors.redAccent,
              onError: Colors.white,
              surface: AppTheme.cardColor(isDark),
              onSurface: AppTheme.textColor(isDark),
            ),
            inputDecorationTheme: InputDecorationTheme(
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.borderColor(isDark))),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.borderColor(isDark))),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppTheme.accentColor(isDark), width: 2)),
              labelStyle: TextStyle(color: AppTheme.secondaryTextColor(isDark)),
            ),
          ),
          child: StatefulBuilder(
            builder: (context, setState) {
              double getCurrentAdjustmentDelta() {
                final nominal = parseInput(controller.text);
                return isPositive.value ? nominal : -nominal;
              }

              double projectedFinalValue = currentFinalBalance + getCurrentAdjustmentDelta();

              return AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Text('Penyesuaian Saldo: $title', style: TextStyle(color: AppTheme.textColor(isDark))),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Saldo Terakhir: ${formatCurrencyWithSuffix(currentFinalBalance)}',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppTheme.secondaryTextColor(isDark))),
                      const SizedBox(height: 10),
                      Divider(color: AppTheme.borderColor(isDark)),
                      Text('Saldo Baru: ${formatCurrencyWithSuffix(projectedFinalValue)}',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppTheme.accentColor(isDark))),
                      ValueListenableBuilder<bool>(
                        valueListenable: isPositive,
                        builder: (context, isPos, child) {
                          final adjustmentValue = getCurrentAdjustmentDelta();
                          return Text('${currencyFormat.format(adjustmentValue)}',
                              style: TextStyle(fontSize: 14, color: adjustmentValue >= 0 ? AppTheme.accentColor(isDark) : Colors.redAccent));
                        },
                      ),
                      const SizedBox(height: 10),
                      TextFormField(
                        controller: controller,
                        keyboardType: TextInputType.number,
                        style: TextStyle(color: AppTheme.textColor(isDark), fontSize: 18, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'Nominal Penyesuaian (Nilai Absolut)',
                          hintText: 'Masukkan nominal tanpa tanda +/-',
                          prefixText: 'Rp ',
                          prefixStyle: TextStyle(color: AppTheme.secondaryTextColor(isDark), fontSize: 18),
                          suffixIcon: IconButton(
                            icon: Icon(Icons.clear, color: AppTheme.secondaryTextColor(isDark)),
                            onPressed: () => setState(() => controller.text = numberFormat.format(0.0)),
                          ),
                        ),
                        onChanged: (text) => setState(() {}),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.remove_circle),
                              label: const Text('KURANG (-)'),
                              onPressed: () {
                                isPositive.value = false;
                                setState(() {});
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isPositive.value ? (isDark ? const Color(0xFF333344) : Colors.grey.shade200) : Colors.redAccent.shade700,
                                foregroundColor: isPositive.value ? (isDark ? Colors.grey : Colors.grey.shade600) : Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.add_circle),
                              label: const Text('TAMBAH (+)'),
                              onPressed: () {
                                isPositive.value = true;
                                setState(() {});
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: isPositive.value ? AppTheme.accentColor(isDark) : (isDark ? const Color(0xFF333344) : Colors.grey.shade200),
                                foregroundColor: isPositive.value ? (isDark ? Colors.black : Colors.white) : (isDark ? Colors.grey : Colors.grey.shade600),
                                padding: const EdgeInsets.symmetric(vertical: 15),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text('Batal', style: TextStyle(color: AppTheme.secondaryTextColor(isDark))),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final newRequiredAdjustment = projectedFinalValue - baseValue;
                      onSave(newRequiredAdjustment);
                      _saveAdjustment();
                      Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accentColor(isDark),
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Simpan Penyesuaian'),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildStatCard({
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    Color valueColor = color;
    if (title.contains('Pendapatan') || title.contains('Margin')) {
      valueColor = amount >= 0 ? AppTheme.accentColor(isDark) : Colors.redAccent;
    } else if (title.contains('Pengeluaran')) {
      valueColor = Colors.orangeAccent;
    }
    if (title.contains('Darurat')) valueColor = Colors.deepOrangeAccent;
    if (title.contains('Bebas')) valueColor = Colors.lightBlueAccent;
    if (title.contains('Aman')) valueColor = AppTheme.accentColor(isDark);

    return _buildGlassCard(
      padding: 12.0,
      blur: 10.0,
      isDark: isDark,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon dan Nominal di baris atas
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark 
                    ? Colors.white.withValues(alpha: 0.1) 
                    : color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  icon, 
                  color: isDark ? Colors.white54 : color, 
                  size: 20
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  formatCurrencyWithSuffix(amount, forceAbbreviate: true),
                  style: TextStyle(
                    color: valueColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
          // Label di bawah
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              color: isDark ? Colors.white70 : Colors.grey.shade700,
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 2,
          ),
        ],
      ),
    );
  }

  Widget _buildFinancialSummary(bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Ringkasan Keuangan', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textColor(isDark))),
        Divider(color: isDark ? Colors.white24 : Colors.grey.shade200, thickness: 0.5),
        _buildGlassCard(
          padding: 10.0,
          blur: 10.0,
          isDark: isDark,
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 1.7,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              _buildStatCard(title: 'Total Pendapatan', amount: totalPendapatanFinal, color: Colors.teal, icon: Icons.ssid_chart, isDark: isDark),
              _buildStatCard(title: 'Total Pengeluaran', amount: totalPengeluaranSparepart, color: Colors.red, icon: Icons.money_off, isDark: isDark),
              _buildStatCard(title: 'Margin Kotor', amount: totalMarginKotor, color: Colors.blue, icon: Icons.analytics, isDark: isDark),
              _buildStatCard(title: 'Total Saldo (Final)', amount: saldoDaruratFinal + saldoBebasFinal + saldoAmanFinal, color: Colors.orange, icon: Icons.account_balance_wallet, isDark: isDark),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildProfitAnalysis(bool isDark) {
    final sortedProfit = (profitPerLayanan.entries.toList())..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Alokasi Saldo & Margin Bersih', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textColor(isDark))),
        Divider(color: isDark ? Colors.white24 : Colors.grey.shade200, thickness: 0.5),
        _buildStatCard(
          title: 'Total Margin Bersih Usaha',
          amount: totalMarginBersih,
          color: Colors.purple,
          icon: Icons.calculate,
          isDark: isDark,
        ),
        const SizedBox(height: 16),
        _buildGlassCard(
          padding: 10.0,
          blur: 10.0,
          isDark: isDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Dompet Alokasi', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textColor(isDark))),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showAdjustmentDialog('Saldo Darurat', baseDarurat, adjustmentDarurat, saldoDaruratFinal, (newValue) {
                        setState(() {
                          adjustmentDarurat = newValue;
                          saldoDaruratFinal = baseDarurat + newValue;
                        });
                      }),
                      child: _buildStatCard(
                        title: 'Saldo Darurat',
                        amount: saldoDaruratFinal,
                        color: Colors.deepOrange,
                        icon: Icons.security,
                        isDark: isDark,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showAdjustmentDialog('Saldo Bebas', baseBebas, adjustmentBebas, saldoBebasFinal, (newValue) {
                        setState(() {
                          adjustmentBebas = newValue;
                          saldoBebasFinal = baseBebas + newValue;
                        });
                      }),
                      child: _buildStatCard(
                        title: 'Saldo Bebas',
                        amount: saldoBebasFinal,
                        color: Colors.teal,
                        icon: Icons.savings,
                        isDark: isDark,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => _showAdjustmentDialog('Saldo Aman', baseAman, adjustmentAman, saldoAmanFinal, (newValue) {
                  setState(() {
                    adjustmentAman = newValue;
                    saldoAmanFinal = baseAman + newValue;
                  });
                }),
                child: _buildStatCard(
                  title: 'Saldo Aman',
                  amount: saldoAmanFinal,
                  color: Colors.indigo,
                  icon: Icons.check_circle,
                  isDark: isDark,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Text('Detail Profit per Layanan', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppTheme.textColor(isDark))),
        const SizedBox(height: 10),
        _buildGlassCard(
          padding: 16.0,
          blur: 10.0,
          isDark: isDark,
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedProfit.length.clamp(0, 10),
            itemBuilder: (context, index) {
              final entry = sortedProfit[index];
              final service = entry.key;
              final profit = entry.value;
              final count = layananTerlaris[service] ?? 0;
              final isPositive = profit >= 0;
              final averageProfit = count > 0 ? profit / count : 0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [AppTheme.accentColor(isDark), AppTheme.accentColor(isDark).withValues(alpha: 0.6)],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Center(
                        child: Text(
                          '#${index + 1}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(service, style: TextStyle(color: AppTheme.textColor(isDark), fontWeight: FontWeight.w600, fontSize: 14)),
                          Text('${count}x Transaksi • Rata-rata: ${formatCurrencyWithSuffix(averageProfit.toDouble())}',
                              style: TextStyle(fontSize: 11, color: AppTheme.secondaryTextColor(isDark))),
                        ],
                      ),
                    ),
                    Text(formatCurrencyWithSuffix(profit),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: isPositive ? AppTheme.accentColor(isDark) : Colors.redAccent)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVisualizations(bool isDark) {
    final layananTerlarisDouble = layananTerlaris.map((key, value) => MapEntry(key, value.toDouble()));
    final profitLossData = {'Pendapatan': totalPendapatanFinal, 'Pengeluaran': totalPengeluaranSparepart};

    Widget _donutCard({
      required String title,
      required Map<String, double> data,
      required Color color,
      required String Function(double) valueFormatter,
      Widget? centerWidget,
    }) {
      final entries = data.entries;
      final total = entries.fold(0.0, (s, e) => s + (e.value < 0 ? 0.0 : e.value));

      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Center(child: Text(title, textAlign: TextAlign.center, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textColor(isDark)))),
          const SizedBox(height: 8),
          SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(140, 140),
                  painter: _DonutPainter(entries: entries.toList(), total: total, baseColor: color, accent: AppTheme.accentColor(isDark), isDark: isDark),
                ),
                centerWidget ?? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(valueFormatter(total), style: TextStyle(color: AppTheme.textColor(isDark), fontWeight: FontWeight.bold, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('Total', style: TextStyle(color: AppTheme.secondaryTextColor(isDark), fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: entries.take(5).map((e) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Row(
                  children: [
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        color: _DonutPainter.colorForKey(e.key, base: color, accent: AppTheme.accentColor(isDark), isDark: isDark),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        e.key,
                        style: TextStyle(
                          color: AppTheme.secondaryTextColor(isDark),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Visualisasi Kinerja', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textColor(isDark))),
        Divider(color: isDark ? Colors.white24 : Colors.grey.shade200, thickness: 0.5),
        _buildGlassCard(
          padding: 12.0,
          blur: 10.0,
          isDark: isDark,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final cardA = _donutCard(
                title: 'Pendapatan vs Pengeluaran',
                data: profitLossData,
                color: Colors.deepOrange,
                valueFormatter: (v) => formatCurrencyWithSuffix(v, forceAbbreviate: true),
                centerWidget: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10, color: AppTheme.accentColor(isDark)),
                        const SizedBox(width: 6),
                        Text(formatCurrencyWithSuffix(totalPendapatanFinal, forceAbbreviate: true),
                            style: TextStyle(color: AppTheme.accentColor(isDark), fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 10, height: 10, color: Colors.redAccent),
                        const SizedBox(width: 6),
                        Text(formatCurrencyWithSuffix(totalPengeluaranSparepart, forceAbbreviate: true),
                            style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                  ],
                ),
              );

              final cardB = _donutCard(
                title: 'Jenis Servis\nTerlaris',
                data: layananTerlarisDouble,
                color: Colors.teal,
                valueFormatter: (v) => v.toInt().toString(),
              );

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Center(child: SizedBox(width: 240, child: cardA))),
                  const SizedBox(width: 12),
                  Expanded(child: Center(child: SizedBox(width: 240, child: cardB))),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = _themeProvider.isDarkMode;
    final isDataReady = !isLoading && isAdjustmentLoaded;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // ✅ IMMEDIATE cleanup: Cancel stream subscription BEFORE navigation to prevent jeda
        _riwayatSubscription.cancel();
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.bgColor(isDark),
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: ClipRect(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: AppBar(
                backgroundColor: AppTheme.cardColor(isDark).withOpacity(isDark ? 0.8 : 0.9),
                elevation: 0,
                title: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(bottom: 0),
                      child: Image.asset(
                        isDark ? 'assets/images/logo_temagelap.png' : 'assets/images/logo_tematerang.png',
                        height: 26,
                        fit: BoxFit.contain,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 0),
                      child: Text(
                        'kelola & rekap semua data',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.secondaryTextColor(isDark),
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              centerTitle: false,
              iconTheme: IconThemeData(color: isDark ? Colors.white70 : Colors.grey.shade700),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Center(
                    child: GestureDetector(
                      onTap: () {
                        _themeProvider.toggleTheme();
                      },
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          isDark ? Icons.light_mode : Icons.dark_mode,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: !isDataReady
          ? Center(child: CircularProgressIndicator(color: AppTheme.accentColor(isDark)))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(18.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildFinancialSummary(isDark),
                  const SizedBox(height: 30),
                  _buildVisualizations(isDark),
                  const SizedBox(height: 30),
                  _buildProfitAnalysis(isDark),
                  const SizedBox(height: 50),
                ],
              ),
            ),
      ),
    );
  }
}

// ==================== DONUT PAINTER ====================
class _DonutPainter extends CustomPainter {
  final List<MapEntry<String, double>> entries;
  final double total;
  final Color baseColor;
  final Color accent;
  final bool isDark;

  _DonutPainter({required this.entries, required this.total, required this.baseColor, required this.accent, required this.isDark});

  static Color colorForKey(String key, {required Color base, required Color accent, required bool isDark}) {
    if (key.toLowerCase().contains('pendapatan')) return accent;
    if (key.toLowerCase().contains('pengeluaran')) return Colors.redAccent;
    final colors = isDark
        ? [base, Colors.deepPurpleAccent, Colors.orangeAccent, Colors.lightBlueAccent, Colors.greenAccent]
        : [base, Colors.purpleAccent, Colors.orange, Colors.lightBlue, Colors.green];
    final idx = key.hashCode.abs() % colors.length;
    return colors[idx];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.shortestSide) / 2;
    final strokeWidth = radius * 0.18;
    final paint = Paint()..style = PaintingStyle.stroke..strokeWidth = strokeWidth..strokeCap = StrokeCap.butt;

    double startAngle = -90 * 3.14159 / 180;
    for (var entry in entries) {
      final value = entry.value < 0 ? 0.0 : entry.value;
      final sweep = total > 0 ? (value / total) * 2 * 3.14159 : 0.0;
      paint.color = colorForKey(entry.key, base: baseColor, accent: accent, isDark: isDark).withValues(alpha: 0.95);
      canvas.drawArc(Rect.fromCircle(center: center, radius: radius - strokeWidth / 2), startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}




