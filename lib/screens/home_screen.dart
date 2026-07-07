import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:async';
import 'dart:math';
import '../services/connectivity_service.dart';
import '../services/pricing_service.dart';
import '../widgets/animated_dialog.dart';
import 'penukaran_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // State untuk Data Servis
  String? jenisServis;
  String? merkHp;
  String? seriHp;
  DateTime? tglServis;

  String? garansi;
  double? hargaSparepart;
  double? hargaServis; // Harga kotor (sebelum diskon voucher/kupon)

  // State untuk Pelanggan dan Pesanan
  String? kodePelanggan; 
  Map<String, dynamic>? _selectedCustomer; // Data pelanggan yang divalidasi
  String? _selectedCustomerDocId; // ID Dokumen Pelanggan
  String? kodePesanan; // Kode yang diawali 'T'

  // State untuk Diskon/Voucher
  String? kodeKupon; // Kupon diinput manual (Jika tidak menggunakan voucher)
  DocumentSnapshot? _selectedCouponDoc; // Snapshot dokumen kupon manual

  // NEW STATE: Data voucher yang dipilih dari transaksi_penukaran
  Map<String, dynamic>? _selectedRedeemedVoucher; 
  // NEW STATE: Harga servis final setelah diskon/kupon (Inilah yang akan dibayarkan)
  double? _finalHargaServis; 
  // NEW STATE: Custom harga total untuk jenis servis custom (bukan LCD/Baterai)
  double? _customHargaTotal;

  // Controller & Debounce untuk Validasi
  final TextEditingController _kodePelangganController = TextEditingController();
  final TextEditingController _tglServisController = TextEditingController();
  final TextEditingController _hargaSparepartController = TextEditingController();
  final TextEditingController _kodeKuponController = TextEditingController();
  final TextEditingController _customHargaTotalController = TextEditingController();
  final FocusNode _kodePelangganFocus = FocusNode();
  final FocusNode _kodePesananFocus = FocusNode();
  final FocusNode _hargaSparepartFocus = FocusNode();
  final FocusNode _kodeKuponFocus = FocusNode();
  final FocusNode _customHargaTotalFocus = FocusNode();
  Timer? _debounce;
  Timer? _couponDebounce;

  bool isInputMode = false;
  bool _loadingSeri = false;
  bool _isLoading = false; // NEW: Prevent multiple submissions while saving
  String _appVersion = 'v1.0.2'; // Versi aplikasi
  List<String> jenisServisList = [];
  List<String> merkList = [];
  List<String> seriList = [];
  List<String> garansiList = [];

  final NumberFormat currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _loadDropdownData();
    _loadGaransi();
    _loadAppVersion(); // Load versi aplikasi

    // Default behavior: generate Kode Pesanan (T-code) for new input flow
    kodePesanan = _generateOrderCode();
  }

  /// Load versi aplikasi
  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _appVersion = 'v${packageInfo.version}';
        });
      }
    } catch (e) {
      _appVersion = 'v1.0.2';
    }
  }

  

  // Bersihkan controller dan timer saat widget dibuang
  @override
  void dispose() {
    _kodePelangganController.dispose();
    _hargaSparepartController.dispose();
    _kodeKuponController.dispose();
    _customHargaTotalController.dispose();
    _kodePelangganFocus.dispose();
    _kodePesananFocus.dispose();
    _hargaSparepartFocus.dispose();
    _kodeKuponFocus.dispose();
    _customHargaTotalFocus.dispose();
    _debounce?.cancel();
    _couponDebounce?.cancel();
    super.dispose();
  }
  
  // Fungsi untuk menghasilkan Kode Pesanan
  String _generateOrderCode() {
    const String letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const String numbers = '0123456789';
    const String allChars = letters + numbers;
    Random rnd = Random();
    
    String result = 'T'; // Diawali dengan 'T'
    List<String> fiveChars = [];

    // Memastikan campuran huruf dan angka
    fiveChars.add(letters[rnd.nextInt(letters.length)]);
    fiveChars.add(numbers[rnd.nextInt(numbers.length)]);
    for (int i = 0; i < 3; i++) {
      fiveChars.add(allChars[rnd.nextInt(allChars.length)]);
    }
    fiveChars.shuffle(rnd);
    result += fiveChars.join('');

    return result;
  }

  // Fungsi untuk memvalidasi Kode Pelanggan di Firestore
  Future<void> _validateCustomerCode(String code) async {
    // Reset data pelanggan setiap kali validasi
    setState(() {
      _selectedCustomer = null; 
      _selectedCustomerDocId = null;
    });

    if (code.isEmpty) {
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('pelanggan')
          .where('kode_pelanggan', isEqualTo: code)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        setState(() {
          _selectedCustomer = doc.data();
          _selectedCustomerDocId = doc.id;
        });
      }
      // Jika tidak ditemukan, tidak perlu tampilkan dialog - icon silang sudah ditampilkan di UI
    } catch (e) {
      // Error silently handled
    }
  }

  Future<void> _pickDateTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: tglServis ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF0B63D4),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF0B63D4),
              ),
            ),
          ),
          child: child!,
        );
      },
    );

    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: tglServis != null 
            ? TimeOfDay(hour: tglServis!.hour, minute: tglServis!.minute)
            : TimeOfDay.now(),
        builder: (context, child) {
          return Theme(
            data: Theme.of(context).copyWith(
              colorScheme: const ColorScheme.light(
                primary: Color(0xFF0B63D4),
                onPrimary: Colors.white,
                surface: Colors.white,
                onSurface: Colors.black87,
              ),
              textButtonTheme: TextButtonThemeData(
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0B63D4),
                ),
              ),
            ),
            child: child!,
          );
        },
      );

      if (pickedTime != null) {
        final DateTime combined = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        if (!mounted) return;
        setState(() {
          tglServis = combined;
          _tglServisController.text = DateFormat('dd/MM/yyyy HH:mm').format(combined);
        });
      }
    }
  }

  void _setNow() {
    final now = DateTime.now();
    setState(() {
      tglServis = now;
      _tglServisController.text = DateFormat('dd/MM/yyyy HH:mm').format(now);
    });
  }

  Future<void> _loadGaransi() async {
    try {
      FirebaseFirestore.instance.collection('garansi').snapshots().listen((snapshot) {
        setState(() {
          garansiList = snapshot.docs.map((doc) {
            final lama = doc['lama'].toString();
            final satuan = doc['satuan'].toString();
            return "$lama $satuan";   // contoh: "30 Hari"
          }).toList();
        });
      });
    } catch (e) {
      // Error silently handled
    }
  }
  
  // Fungsi untuk memvalidasi Kode Kupon Manual di Firestore
  Future<void> _validateCouponCode(String code) async {
    // Validasi bisa berjalan baik dengan atau tanpa voucher
    // Kode kupon dan kode voucher adalah 2 hal yang terpisah
    
    setState(() {
      _selectedCouponDoc = null;
    });

    if (code.isEmpty) {
      return;
    }

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('kupon')
          .where('kode', isEqualTo: code)
          .where('status', isEqualTo: 'tersedia') 
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        if (!mounted) return;
        setState(() {
          _selectedCouponDoc = doc;
        });
      }
      // Jika tidak ditemukan, tidak perlu tampilkan dialog - icon silang sudah ditampilkan di UI
    } catch (e) {
      // Error silently handled
    }
  }


  // Fungsi untuk menghitung Harga Final setelah diskon Voucher
  void _calculateFinalPrice() {
    // Untuk custom service type, gunakan custom harga total sebagai base
    // Untuk LCD/Baterai, gunakan harga yang dihitung dari formula
    if (_isCustomServiceType()) {
      // Custom type: gunakan manual harga total yang diinput
      final basePrice = _customHargaTotal ?? hargaServis ?? 0.0;
      
      // Hitung diskon voucher jika ada
      double finalPrice = basePrice;
      if (_selectedRedeemedVoucher != null) {
        final discountPercent = (_selectedRedeemedVoucher!['discount_percent'] as num?)?.toDouble() ?? 0.0;
        final maxDiscount = (_selectedRedeemedVoucher!['max_discount'] as num?)?.toDouble() ?? 0.0;
        
        double discountAmount = basePrice * (discountPercent / 100.0);
        if (discountAmount > maxDiscount) {
          discountAmount = maxDiscount;
        }
        finalPrice = basePrice - discountAmount;
      }
      
      // Bulatkan ke ribuan
      final roundedFinalPrice = PricingService.roundToThousand(finalPrice);
      
      setState(() {
        hargaServis = basePrice;
        _finalHargaServis = roundedFinalPrice;
      });
    } else {
      // LCD/Baterai: gunakan formula pricing
      final prices = PricingService.calculateServicePrices(
        hargaSparepart: hargaSparepart ?? 0.0,
        jenisServis: jenisServis ?? "LCD",
        redeemedVoucher: _selectedRedeemedVoucher,
        voucherData: null,
      );

      final roundedFinalPrice = PricingService.roundToThousand(prices['hargaServisFinal'] ?? 0.0);

      setState(() {
        hargaServis = prices['hargaServisKotor'];
        _finalHargaServis = roundedFinalPrice;
      });
    }
  }

  // NEW FUNCTION: Menampilkan dialog dan memilih voucher yang tersedia
  Future<void> _showVoucherDialog() async {
    if (_selectedCustomer == null || kodePelanggan == null) {
      showWarningDialog(
        context,
        title: 'Perhatian',
        message: 'Harap masukkan dan validasi Kode Pelanggan terlebih dahulu.',
      );
      return;
    }

    try {
      // Ambil voucher langsung dari koleksi 'vouchers' berdasarkan kode pelanggan
      final snapshot = await FirebaseFirestore.instance
          .collection('vouchers')
          .where('kode_pelanggan_penukar', isEqualTo: kodePelanggan)
          .where('status', isEqualTo: 'siap pakai')
          .get();

      if (snapshot.docs.isEmpty) {
        if (mounted) {
          showWarningDialog(
            context,
            title: 'Info',
            message: 'Tidak ada voucher siap pakai untuk pelanggan ini.',
          );
        }
        return;
      }

      // Buat daftar voucher siap pakai
      List<Map<String, dynamic>> availableVouchers = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'code': (data['kode'] ?? data['code'])?.toString(),
          'name': data['name'] ?? data['nama'] ?? '',
          'discount_percent': (data['discount_percent'] as num?)?.toDouble() ?? 0.0,
          'max_discount': (data['max_discount'] as num?)?.toDouble() ?? 0.0,
        };
      }).toList();

      if (mounted) {
        await showDialog(
          context: context,
          builder: (context) {
            final dialogWidth = MediaQuery.of(context).size.width > 800 
              ? MediaQuery.of(context).size.width * 0.5 
              : MediaQuery.of(context).size.width * 0.95;
            
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: SizedBox(
                width: dialogWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header dengan gradient seperti dialogs lainnya
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.card_giftcard, color: Colors.white),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Pilih Voucher Siap Pakai',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.white),
                          )
                        ],
                      ),
                    ),
                    // Content list
                    SizedBox(
                      height: (availableVouchers.length * 70).clamp(100, 350).toDouble(),
                      child: ListView.separated(
                        padding: const EdgeInsets.all(12),
                        shrinkWrap: true,
                        itemCount: availableVouchers.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final voucher = availableVouchers[index];
                          // ✅ Cek apakah voucher ini sudah dipilih
                          final isSelected = _selectedRedeemedVoucher != null && 
                              _selectedRedeemedVoucher!['code'] == voucher['code'];
                          
                          return ListTile(
                            leading: Icon(
                              Icons.card_giftcard, 
                              color: isSelected ? Colors.grey.shade400 : const Color(0xFF0B63D4)
                            ),
                            title: Text(
                              voucher['name'],
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.grey.shade400 : Colors.black,
                              ),
                            ),
                            subtitle: Text(
                              "Kode: ${voucher['code']} • Diskon ${voucher['discount_percent'].toStringAsFixed(0)}%",
                              style: TextStyle(
                                fontSize: 12,
                                color: isSelected ? Colors.grey.shade300 : Colors.grey.shade600,
                              ),
                            ),
                            trailing: isSelected 
                              ? Icon(Icons.check_circle, color: Colors.green.shade600)
                              : const Icon(Icons.chevron_right, color: Color(0xFF0B63D4)),
                            enabled: !isSelected,
                            onTap: isSelected ? null : () async {
                              Navigator.pop(context);
                              setState(() {
                                _selectedRedeemedVoucher = voucher;
                              });
                              _calculateFinalPrice();
                              showSuccessDialog(
                                context,
                                title: '✅ Voucher Dipilih',
                                message: 'Voucher ${voucher['name']} berhasil diterapkan',
                              );
                            },
                          );
                        },
                      ),
                    ),
                    // Footer dengan tombol
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Batal'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          title: 'Gagal',
          message: 'Gagal memuat voucher.',
        );
      }
    }
  }

  Future<void> _loadDropdownData() async {
    // (Fungsi tetap sama)
    try {
      FirebaseFirestore.instance.collection('jenis_servis').snapshots().listen((snapshot) {
      setState(() {
        jenisServisList = snapshot.docs.map((doc) => doc['nama'] as String).toList();
      });
    });

    FirebaseFirestore.instance.collection('merk').snapshots().listen((snapshot) {
      setState(() {
        merkList = snapshot.docs.map((doc) => doc['nama'] as String).toList();
      });
    });
    } catch (e) {
      // Error silently handled
    }
  }

  Future<void> _loadSeriByMerk(String merk) async {
    setState(() {
      _loadingSeri = true;
      seriList = [];
    });

    try {
      FirebaseFirestore.instance
          .collection('seri')
          .where('merk_nama', isEqualTo: merk)
          .snapshots()
          .listen((snapshot) {
        final fetched = snapshot.docs
            .map((doc) => doc['nama']?.toString() ?? '')
            .where((s) => s.isNotEmpty)
            .toList();

        setState(() {
          seriList = fetched;
          _loadingSeri = false;

          // Jika seriHp lama masih ada di list, tetap gunakan
          if (seriHp != null && !seriList.contains(seriHp)) {
            seriHp = null;
          }
        });
      });
    } catch (e) {
      setState(() {
        seriList = [];
        seriHp = null;
        _loadingSeri = false;
      });
    }
  }

  // Small helper to create full-width gradient buttons
  Widget _buildGradientButton({required String label, required Gradient gradient, VoidCallback? onPressed}) {
    return Container(
      decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(10)),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(child: Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
          ),
        ),
      ),
    );
  }

  

  // Menggunakan PricingService dari utility
  double hitungHargaJual(double hs) {
    return PricingService.hitungHargaJual(hs, jenisServis: jenisServis ?? "LCD");
  }

  void hitungDanTampilkan() {
    // Validasi semua data harus lengkap
    if (jenisServis == null || merkHp == null || seriHp == null || garansi == null) {
      showWarningDialog(
        context,
        title: 'Perhatian',
        message: 'Lengkapi semua data: Jenis Servis, Merk HP, Seri HP, dan Garansi.',
      );
      return;
    }

    // Untuk semua jenis servis, harga sparepart harus ada
    if (hargaSparepart == null) {
      showWarningDialog(
        context,
        title: 'Perhatian',
        message: 'Masukkan Harga Sparepart.',
      );
      return;
    }

    // Untuk custom service type (bukan LCD/Baterai), harga total juga harus dari input custom
    if (_isCustomServiceType() && (_finalHargaServis == null || _finalHargaServis == 0)) {
      showWarningDialog(
        context,
        title: 'Perhatian',
        message: 'Masukkan Harga Total untuk layanan ini.',
      );
      return;
    }

    // Gunakan harga yang sudah ada (sudah dihitung secara real-time)
    // Jangan recalculate ulang
    final displayHarga = _finalHargaServis ?? hargaServis ?? 0;
    final hargaFormat = currencyFormat.format(displayHarga);


    final hasil = """
📱✨ 𝗦𝗲𝗿𝘃𝗶𝘀 𝗣𝗲𝗿𝗴𝗮𝗻𝘁𝗶𝗮𝗻 ${jenisServis ?? '-'} *${merkHp ?? '-'} ${seriHp ?? '-'}* ✨📱
___________________________________

💸 𝗛𝗮𝗿𝗴𝗮       : $hargaFormat
🛡️ 𝗚𝗮𝗿𝗮𝗻𝘀𝗶    : ${garansi ?? '-'}
🎁 𝗕𝗼𝗻𝘂𝘀      : Tempered Glass

🎫 𝗕𝗼𝗻𝘂𝘀 𝗣𝗲𝗹𝗮𝗻𝗴𝗴𝗮𝗻 𝗕𝗮𝗿𝘂 :
Dapat 1 Voucher potongan 15% (𝗺𝗮𝘅 𝘀/𝗱 𝗥𝗽 𝟰𝟬.𝟬𝟬𝟬), berlaku untuk servis berikutnya! 🤩
___________________________________
""";

    showDialog(
      context: context,
      builder: (context) {
        final dialogWidth = MediaQuery.of(context).size.width > 800 ? MediaQuery.of(context).size.width * 0.5 : MediaQuery.of(context).size.width * 0.95;
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: SizedBox(
            width: dialogWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Header with gradient
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.receipt_long, color: Colors.white),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('Hasil Perhitungan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
                      IconButton(
                        padding: EdgeInsets.zero,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close, color: Colors.white),
                      )
                    ],
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SelectableText(hasil, style: const TextStyle(fontSize: 13, height: 1.3)),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildGradientButton(
                                label: 'Salin',
                                gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: hasil));
                                  Navigator.pop(context);
                                  showSuccessDialog(context, title: 'Berhasil', message: 'Teks berhasil disalin');
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Tutup'),
                            ),
                          ],
                        )
                      ],
                    ),
                  ),
                )
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _simpanKeRiwayat() async {
    // Validasi
    if (_selectedCustomer == null || kodePelanggan == null || _selectedCustomerDocId == null) {
      showWarningDialog(
        context,
        title: 'Validasi Data',
        message: 'Pastikan Kode Pelanggan valid!',
      );
      return;
    }
    // Kode kupon wajib diisi pada tampilan input data servis
    if (kodeKupon == null || kodeKupon!.isEmpty) {
      showWarningDialog(
        context,
        title: 'Validasi Data',
        message: 'Kode Kupon wajib diisi.',
      );
      return;
    }
    if (_kodeKuponController.text.isNotEmpty && _selectedCouponDoc == null) {
      showWarningDialog(
        context,
        title: 'Validasi Data',
        message: 'Kode Kupon manual diisi tetapi tidak valid. Harap perbaiki atau hapus kode kupon.',
      );
      return;
    }
    if (jenisServis == null || merkHp == null || seriHp == null || garansi == null || hargaSparepart == null || hargaServis == null || tglServis == null || _finalHargaServis == null) {
      showWarningDialog(
        context,
        title: 'Validasi Data',
        message: 'Lengkapi semua data servis.',
      );
      return;
    }

    // ✅ NEW: Check if already loading (prevent multiple clicks)
    if (_isLoading) {
      return;
    }

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

    // Set loading state AFTER confirming connectivity
    setState(() {
      _isLoading = true;
    });

    // Tentukan kode kupon dan kode voucher yang akan disimpan
    String? couponCodeFromDoc;
    if (_selectedCouponDoc != null) {
      final docData = _selectedCouponDoc!.data();
      if (docData is Map<String, dynamic>) {
        couponCodeFromDoc = (docData['kode'] ?? docData['code'])?.toString();
      }
    }

    String? kodeVoucherUntukRiwayat = _selectedRedeemedVoucher?['code'];
    String? kodeKuponUntukRiwayat = couponCodeFromDoc ?? kodeKupon;

    try {
      // 1️⃣ Simpan ke koleksi 'riwayat'
      await FirebaseFirestore.instance.collection('riwayat').add({
        'kode_pelanggan': kodePelanggan,
        'kode_pesanan': kodePesanan,
        'kode_kupon': kodeKuponUntukRiwayat,
        'kode_voucher': kodeVoucherUntukRiwayat,
        'jenis_servis': jenisServis,
        'merk': merkHp,
        'seri': seriHp,
        'garansi': garansi,
        'harga_sparepart': hargaSparepart,
        'harga_servis': hargaServis,
        'harga_servis_final': _finalHargaServis,
        'tanggal': Timestamp.now(),
      });

      // 2️⃣ Jika voucher digunakan → ubah status voucher jadi "hangus"
      // 2️⃣ Jika voucher digunakan → ubah status voucher jadi "hangus" + simpan ke used_vouchers
      if (_selectedRedeemedVoucher != null) {
        final voucherSnapshot = await FirebaseFirestore.instance
          .collection('vouchers')
          .where('kode', isEqualTo: _selectedRedeemedVoucher!['code'])
          .limit(1)
          .get();

        if (voucherSnapshot.docs.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('vouchers')
              .doc(voucherSnapshot.docs.first.id)
              .update({'status': 'hangus'});
        }

        // Tambahkan ke pelanggan → used_vouchers
        await FirebaseFirestore.instance
            .collection('pelanggan')
            .doc(_selectedCustomerDocId!)
            .update({
              'used_vouchers': FieldValue.arrayUnion([_selectedRedeemedVoucher!['code']])
            });
      }

      // 3️⃣ Jika kupon manual atau hasil scan digunakan → update status kupon jadi 'siap pakai' + simpan ke pelanggan
      if (_selectedCouponDoc != null) {
        final couponData = (_selectedCouponDoc!.data() as Map<String, dynamic>?);
        final couponCode = couponData != null ? (couponData['kode'] ?? couponData['kode']) : null;

        // Update status kupon jadi siap pakai
        await FirebaseFirestore.instance
            .collection('kupon')
            .doc(_selectedCouponDoc!.id)
            .update({
              'status': 'siap pakai',
            });

        // Tambahkan ke pelanggan
        if (couponCode != null) {
          await FirebaseFirestore.instance
              .collection('pelanggan')
              .doc(_selectedCustomerDocId!)
              .update({
                'used_coupon_codes': FieldValue.arrayUnion([couponCode])
              });
        }
      }

      // 4️⃣ Konfirmasi sukses
      if (!mounted) return;
      showSuccessDialog(
        context,
        title: 'Sukses',
        message: 'Data berhasil disimpan ke riwayat',
      );

      // 5️⃣ Reset state (bersihkan semua input agar tampilan tidak menyisakan data)
      setState(() {
        isInputMode = false;
        kodePelanggan = null;
        _selectedCustomer = null;
        _selectedCustomerDocId = null;
        kodePesanan = _generateOrderCode();
        jenisServis = null;
        merkHp = null;
        seriHp = null;
        garansi = null;
        hargaSparepart = null;
        hargaServis = null;
        _finalHargaServis = null;
        _customHargaTotal = null;
        kodeKupon = null;
        _selectedCouponDoc = null;
        _selectedRedeemedVoucher = null;
        _kodePelangganController.clear();
        _hargaSparepartController.clear();
        _kodeKuponController.clear();
        _customHargaTotalController.clear();
        _tglServisController.clear();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          title: 'Gagal Menyimpan',
          message: 'Gagal menyimpan data: $e',
        );
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  

  bool get _seriEnabled => merkHp != null && !_loadingSeri;

  // Helper: Cek apakah jenis servis adalah custom (bukan LCD/Baterai)
  bool _isCustomServiceType() {
    if (jenisServis == null) return false;
    final normalized = jenisServis!.toLowerCase().trim();
    return normalized != 'lcd' && normalized != 'baterai';
  }

  // Dialog untuk ubah total harga
  Future<void> _showEditHargaTotalDialog() async {
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return _EditHargaTotalDialog(
          initialValue: _customHargaTotal ?? hargaServis ?? 0,
          onSave: (newHarga) {
            setState(() {
              _customHargaTotal = newHarga;
              hargaServis = newHarga;
              _finalHargaServis = newHarga;
            });
          },
        );
      },
    );
  }

  // Fungsi untuk mengecek apakah ada draft data (data inputan yang belum disimpan ke DB)
  bool _hasDraftData() {
    // Cek apakah ada inputan di textbox atau dropdown (selain tanggal)
    final hasCustomerCode = _kodePelangganController.text.isNotEmpty;
    final hasJenisServis = jenisServis != null;
    final hasMerk = merkHp != null;
    final hasSeri = seriHp != null;
    final hasGaransi = garansi != null;
    final hasHargaSparepart = _hargaSparepartController.text.isNotEmpty;
    final hasKodeKupon = _kodeKuponController.text.isNotEmpty;
    final hasVoucher = _selectedRedeemedVoucher != null;

    return hasCustomerCode || hasJenisServis || hasMerk || hasSeri || 
           hasGaransi || hasHargaSparepart || hasKodeKupon || hasVoucher;
  }

  



  @override
  Widget build(BuildContext context) {
    // Normalize form width so all textboxes and dropdowns match
    final double formWidth = MediaQuery.of(context).size.width > 800
      ? 520
      : (MediaQuery.of(context).size.width - 64);
    // Modern UI layout (keindahan visual hanya — logic/backend tetap tidak diubah)
    DateTime? lastBackPress;
    return WillPopScope(
      onWillPop: () async {
        // Jika MainScreen ada di pohon dan tab yang aktif bukan Home (index 0),
        // jangan tangani back di sini — biarkan nav utama mengatur perilaku.
        // Cari ancestor state yang punya properti `currentIndex` (IndexedStack nav).
        int? foundIndex;
        context.visitAncestorElements((element) {
          if (element is StatefulElement) {
            final state = element.state;
            try {
              final ci = (state as dynamic).currentIndex;
              if (ci is int) {
                foundIndex = ci;
                return false; // stop traversal
              }
            } catch (_) {
              // ignore and continue
            }
          }
          return true; // continue traversal
        });
        if (foundIndex != null && foundIndex != 0) return true;

        // Hanya tampilkan dialog simpan draft jika sedang di input mode dan halaman ini aktif
        if (ModalRoute.of(context)?.isCurrent != true) return true;
        if (isInputMode) {
          final hasDraft = _hasDraftData();
          if (!hasDraft) {
            if (mounted) setState(() => isInputMode = false);
            return false;
          }
          final result = await showDialog<String>(
            context: context,
            barrierDismissible: true,
            builder: (context) {
              return Dialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                child: SizedBox(
                  width: MediaQuery.of(context).size.width > 800 ? 400 : MediaQuery.of(context).size.width * 0.85,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Colors.white),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Keluar dari Input Data?',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Data inputan Anda masih dalam bentuk draft. Apa yang ingin Anda lakukan?',
                              style: TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => Navigator.pop(context, 'simpan'),
                                    icon: const Icon(Icons.check),
                                    label: const Text('Simpan Draft'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0B63D4),
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton.icon(
                                    onPressed: () => Navigator.pop(context, 'hapus'),
                                    icon: const Icon(Icons.delete_outline),
                                    label: const Text('Hapus'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red.shade600,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
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
            },
          );
          if (result == 'simpan') {
            if (mounted) setState(() => isInputMode = false);
          } else if (result == 'hapus') {
            setState(() {
              isInputMode = false;
              kodePelanggan = null;
              _selectedCustomer = null;
              _selectedCustomerDocId = null;
              kodePesanan = _generateOrderCode();
              jenisServis = null;
              merkHp = null;
              seriHp = null;
              garansi = null;
              hargaSparepart = null;
              hargaServis = null;
              _finalHargaServis = null;
              kodeKupon = null;
              _selectedCouponDoc = null;
              _selectedRedeemedVoucher = null;
              _kodePelangganController.clear();
              _hargaSparepartController.clear();
              _kodeKuponController.clear();
              _tglServisController.clear();
            });
          }
          return false;
        }
        // Di tampilan utama (bukan input mode): tekan kembali dua kali untuk keluar
        if (!isInputMode) {
          DateTime now = DateTime.now();
          if (lastBackPress == null || now.difference(lastBackPress!) > Duration(seconds: 2)) {
            lastBackPress = now;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Kembali sekali lagi untuk menutup aplikasi'),
                duration: Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
            return false;
          }
          // Tutup aplikasi
          await SystemNavigator.pop();
          return false;
        }
        return true;
      },
      child: Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(65),
        child: AppBar(
          backgroundColor: Colors.white,
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
                    'assets/images/logo_tematerang.png',
                    height: 26,
                    fit: BoxFit.contain,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 0),
                  child: Text(
                    'kelola & rekap semua data',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
          centerTitle: false,
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12, top: 8),
              child: Align(
                alignment: Alignment.topRight,
                child: Text(
                  _appVersion,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade400,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top summary band
              GestureDetector(
                onTap: _finalHargaServis != null ? _showEditHargaTotalDialog : null,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0,4))],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Ringkasan Pesanan', style: TextStyle(color: Colors.white70, fontSize: 12)),
                            const SizedBox(height: 6),
                            Text(kodePesanan ?? '-', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            Text(_selectedCustomer != null ? (_selectedCustomer!['nama'] ?? '') : 'Belum pilih pelanggan', style: const TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: _finalHargaServis != null ? _showEditHargaTotalDialog : null,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            children: [
                              const Icon(Icons.receipt_long, color: Colors.white),
                              const SizedBox(height: 8),
                              Text(_finalHargaServis != null ? currencyFormat.format(_finalHargaServis) : '-', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      )
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Form area: show compact calculator when not inputting, otherwise show full input form
              if (!isInputMode) ...[
                // Compact calculator (only a few inputs)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0,3))]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Quick Calculator', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      Wrap(spacing: 12, runSpacing: 12, children: [
                        // Jenis Servis: full width (single column) — uses custom rounded selector
                        SizedBox(
                          width: formWidth,
                          child: InputDecorator(
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.build_circle, color: Color(0xFF0B63D4)),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                  filled: true,
                                  fillColor: const Color(0xFFF4F8FF),
                                  hintText: 'Pilih jenis',
                                  hintStyle: TextStyle(color: Colors.grey.shade500),
                                  isDense: true,
                                  contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              ),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(6),
                              onTap: () async {
                                final sel = await _showSelectionDialog('Pilih Jenis Servis', jenisServisList, jenisServis, leadingIcon: Icons.build_circle);
                                if (sel != null) {
                                  setState(() {
                                    jenisServis = sel;
                                    hargaSparepart = null;
                                    hargaServis = null;
                                    _finalHargaServis = null;
                                    _hargaSparepartController.clear();
                                    _customHargaTotalController.clear();
                                  });
                                }
                              },
                              child: Row(
                                children: [
                                  Expanded(child: Text(jenisServis ?? 'Pilih jenis', style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)),
                                  const Icon(Icons.arrow_drop_down, color: Color(0xFF0B63D4))
                                ],
                              ),
                            ),
                          ),
                        ),

                        // Merk (stacked single column)
                        SizedBox(
                          width: formWidth,
                          child: InputDecorator(
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.phone_android, color: Color(0xFF0B63D4)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                filled: true,
                                fillColor: const Color(0xFFF4F8FF),
                                hintText: 'Pilih merk',
                                hintStyle: TextStyle(color: Colors.grey.shade500),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              ),
                            child: InkWell(
                              onTap: () async {
                                final sel = await _showSelectionDialog('Pilih Merk', merkList, merkHp, leadingIcon: Icons.phone_android);
                                if (sel != null) {
                                  setState(() {
                                    merkHp = sel;
                                    seriList = [];
                                    seriHp = null;
                                  });
                                  _loadSeriByMerk(sel);
                                }
                              },
                              child: Row(children: [Expanded(child: Text(merkHp ?? 'Pilih merk', overflow: TextOverflow.ellipsis)), const Icon(Icons.arrow_drop_down, color: Color(0xFF0B63D4))]),
                            ),
                          ),
                        ),

                        // Seri (stacked single column)
                        SizedBox(
                          width: formWidth,
                          child: InputDecorator(
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.list, color: Color(0xFF0B63D4)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                filled: true,
                                fillColor: const Color(0xFFF4F8FF),
                                hintText: 'Pilih seri',
                                hintStyle: TextStyle(color: Colors.grey.shade500),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              ),
                            child: InkWell(
                              onTap: _seriEnabled
                                  ? () async {
                                      final sel = await _showSelectionDialog('Pilih Seri', seriList, seriHp, leadingIcon: Icons.list);
                                      if (sel != null) setState(() => seriHp = sel);
                                    }
                                  : null,
                              child: Row(children: [Expanded(child: Text(seriHp ?? 'Pilih seri', overflow: TextOverflow.ellipsis)), const Icon(Icons.arrow_drop_down, color: Color(0xFF0B63D4))]),
                            ),
                          ),
                        ),

                        // Garansi: placed above Harga Sparepart (full width) — use rounded selection dialog
                        SizedBox(
                          width: formWidth,
                          child: InputDecorator(
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.shield_outlined, color: Color(0xFF0B63D4)),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                filled: true,
                                fillColor: const Color(0xFFF4F8FF),
                                hintText: 'Pilih garansi',
                                hintStyle: TextStyle(color: Colors.grey.shade500),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              ),
                            child: InkWell(
                              onTap: () async {
                                final sel = await _showSelectionDialog('Pilih Garansi', garansiList, garansi, leadingIcon: Icons.shield_outlined);
                                if (sel != null) setState(() => garansi = sel);
                              },
                              child: Row(children: [Expanded(child: Text(garansi ?? 'Pilih garansi', style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)), const Icon(Icons.arrow_drop_down, color: Color(0xFF0B63D4))]),
                            ),
                          ),
                        ),

                        // Harga sparepart: single column
                        SizedBox(
                          width: formWidth,
                          child: TextField(
                              controller: _hargaSparepartController,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                filled: true,
                                fillColor: const Color(0xFFF4F8FF),
                                hintText: 'Harga Sparepart (Rp)',
                                hintStyle: TextStyle(color: Colors.grey.shade500),
                                prefixIcon: const Icon(Icons.monetization_on_outlined, color: Color(0xFF0B63D4)),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              ),
                            style: const TextStyle(fontSize: 14),
                            keyboardType: TextInputType.number,
                            focusNode: _hargaSparepartFocus,
                            onChanged: (v) {
                              hargaSparepart = double.tryParse(v);
                              // Hitung otomatis hanya untuk LCD/Baterai, tidak untuk custom service type
                              if (hargaSparepart != null && jenisServis != null && !_isCustomServiceType()) {
                                setState(() {
                                  final hargaJual = hitungHargaJual(hargaSparepart!);
                                  hargaServis = (hargaJual / 1000).round() * 1000.toDouble();
                                  _calculateFinalPrice();
                                });
                              }
                            },
                          ),
                        ),

                        // Tampilkan custom harga total untuk jenis servis custom (bukan LCD/Baterai)
                        if (_isCustomServiceType())
                          SizedBox(
                            width: formWidth,
                            child: TextField(
                              controller: _customHargaTotalController,
                              decoration: InputDecoration(
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                filled: true,
                                fillColor: const Color(0xFFF4F8FF),
                                hintText: 'Harga Total (Rp)',
                                hintStyle: TextStyle(color: Colors.grey.shade500),
                                prefixIcon: const Icon(Icons.attach_money, color: Color(0xFF0B63D4)),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                              ),
                              style: const TextStyle(fontSize: 14),
                              keyboardType: TextInputType.number,
                              focusNode: _customHargaTotalFocus,
                              onChanged: (v) {
                                final customValue = double.tryParse(v);
                                if (customValue != null) {
                                  setState(() {
                                    hargaServis = customValue;
                                    _finalHargaServis = customValue;
                                  });
                                }
                              },
                            ),
                          ),

                        // Buttons stacked: Hitung Harga (blue gradient) + Input Data Servis (orange gradient)
                        SizedBox(
                          width: formWidth,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: 5),
                              _buildGradientButton(
                                label: 'Hitung Harga',
                                gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                                onPressed: () {
                                  hitungDanTampilkan();
                                },
                              ),
                              const SizedBox(height: 5),
                              _buildGradientButton(
                                label: 'Input Data Servis',
                                gradient: const LinearGradient(colors: [Color(0xFFF2994A), Color(0xFFFBAC66)]),
                                onPressed: () {
                                  final now = DateTime.now();
                                  setState(() {
                                    isInputMode = true;
                                    tglServis = now;
                                    _tglServisController.text = DateFormat('dd/MM/yyyy HH:mm').format(now);
                                  });
                                },
                              ),
                            ],
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
              ] else ...[
                // Full input form (styled like Quick Calculator fields) — wrapped in white card like Quick Calculator
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0,3))]),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text('Input Data Servis', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                    // Kode Pelanggan
                        SizedBox(
                      width: formWidth,
                      child: TextField(
                        controller: _kodePelangganController,
                        focusNode: _kodePelangganFocus,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.person_outline, color: Color(0xFF0B63D4)),
                          suffixIcon: _kodePelangganController.text.isEmpty 
                            ? null
                            : (_selectedCustomer != null 
                              ? const Icon(Icons.check_circle, color: Colors.green) 
                              : const Icon(Icons.cancel, color: Colors.red)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: const Color(0xFFF4F8FF),
                          hintText: 'Kode Pelanggan',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        ),
                        onChanged: (v) {
                          kodePelanggan = v.trim().toUpperCase();
                          setState(() {}); // Update UI untuk suffix icon
                          if (_debounce?.isActive ?? false) _debounce!.cancel();
                          _debounce = Timer(const Duration(milliseconds: 700), () {
                            _validateCustomerCode(kodePelanggan!);
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Jenis Servis
                    SizedBox(
                      width: formWidth,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.build_circle, color: Color(0xFF0B63D4)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: const Color(0xFFF4F8FF),
                          hintText: 'Pilih jenis',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        ),
                        child: InkWell(
                          onTap: () async {
                            _kodePelangganFocus.unfocus();
                            _hargaSparepartFocus.unfocus();
                            _kodeKuponFocus.unfocus();
                            final sel = await _showSelectionDialog('Pilih Jenis Servis', jenisServisList, jenisServis, leadingIcon: Icons.build_circle);
                            if (sel != null) {
                              setState(() {
                                jenisServis = sel;
                                hargaSparepart = null;
                                hargaServis = null;
                                _customHargaTotal = null;
                                _hargaSparepartController.clear();
                                _customHargaTotalController.clear();
                                // Jangan clear _finalHargaServis jika voucher sudah dipilih
                                // agar tidak perlu pilih voucher lagi
                                if (_selectedRedeemedVoucher == null) {
                                  _finalHargaServis = null;
                                }
                              });
                            }
                          },
                          child: Row(children: [Expanded(child: Text(jenisServis ?? 'Pilih jenis', overflow: TextOverflow.ellipsis)), const Icon(Icons.arrow_drop_down, color: Color(0xFF0B63D4))]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Merk
                    SizedBox(
                      width: formWidth,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.phone_android, color: Color(0xFF0B63D4)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: const Color(0xFFF4F8FF),
                          hintText: 'Pilih merk',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        ),
                          child: InkWell(
                          onTap: () async {
                            _kodePelangganFocus.unfocus();
                            _hargaSparepartFocus.unfocus();
                            _kodeKuponFocus.unfocus();
                            final sel = await _showSelectionDialog('Pilih Merk', merkList, merkHp, leadingIcon: Icons.phone_android);
                            if (sel != null) {
                              setState(() {
                                merkHp = sel;
                                seriList = [];
                                seriHp = null;
                              });
                              _loadSeriByMerk(sel);
                            }
                          },
                          child: Row(children: [Expanded(child: Text(merkHp ?? 'Pilih merk', overflow: TextOverflow.ellipsis)), const Icon(Icons.arrow_drop_down, color: Color(0xFF0B63D4))]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Seri
                    SizedBox(
                      width: formWidth,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.list, color: Color(0xFF0B63D4)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: const Color(0xFFF4F8FF),
                          hintText: 'Pilih seri',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        ),
                          child: InkWell(
                          onTap: _seriEnabled
                              ? () async {
                                  _kodePelangganFocus.unfocus();
                                  _hargaSparepartFocus.unfocus();
                                  _kodeKuponFocus.unfocus();
                                  final sel = await _showSelectionDialog('Pilih Seri', seriList, seriHp, leadingIcon: Icons.list);
                                  if (sel != null) setState(() => seriHp = sel);
                                }
                              : null,
                          child: Row(children: [Expanded(child: Text(seriHp ?? 'Pilih seri', overflow: TextOverflow.ellipsis)), const Icon(Icons.arrow_drop_down, color: Color(0xFF0B63D4))]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Garansi
                    SizedBox(
                      width: formWidth,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.shield_outlined, color: Color(0xFF0B63D4)),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: const Color(0xFFF4F8FF),
                          hintText: 'Pilih garansi',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        ),
                          child: InkWell(
                          onTap: () async {
                            _kodePelangganFocus.unfocus();
                            _hargaSparepartFocus.unfocus();
                            _kodeKuponFocus.unfocus();
                            final sel = await _showSelectionDialog('Pilih Garansi', garansiList, garansi, leadingIcon: Icons.shield_outlined);
                            if (sel != null) setState(() => garansi = sel);
                          },
                          child: Row(children: [Expanded(child: Text(garansi ?? 'Pilih garansi', overflow: TextOverflow.ellipsis)), const Icon(Icons.arrow_drop_down, color: Color(0xFF0B63D4))]),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Harga Sparepart
                    SizedBox(
                      width: formWidth,
                      child: TextField(
                        controller: _hargaSparepartController,
                        focusNode: _hargaSparepartFocus,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: const Color(0xFFF4F8FF),
                          hintText: 'Harga Sparepart (Rp)',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          prefixIcon: const Icon(Icons.monetization_on_outlined, color: Color(0xFF0B63D4)),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        ),
                        style: const TextStyle(fontSize: 14),
                        keyboardType: TextInputType.number,
                        onChanged: (v) {
                          hargaSparepart = double.tryParse(v);
                          // Hanya hitung otomatis jika:
                          // 1. Mode input aktif
                          // 2. Harga sparepart valid
                          // 3. Jenis servis sudah dipilih
                          // 4. Jenis servis BUKAN custom type (LCD atau Baterai saja)
                          if (isInputMode && hargaSparepart != null && jenisServis != null && !_isCustomServiceType()) {
                            final hj = hitungHargaJual(hargaSparepart!); // Wrapper ini sudah meneruskan jenisServis
                            setState(() => hargaServis = (hj / 1000).round() * 1000);
                            _calculateFinalPrice();
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Tampilkan custom harga total untuk jenis servis custom (bukan LCD/Baterai)
                    if (_isCustomServiceType())
                      SizedBox(
                        width: formWidth,
                        child: TextField(
                          controller: _customHargaTotalController,
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            filled: true,
                            fillColor: const Color(0xFFF4F8FF),
                            hintText: 'Harga Total (Rp)',
                            hintStyle: TextStyle(color: Colors.grey.shade500),
                            prefixIcon: const Icon(Icons.attach_money, color: Color(0xFF0B63D4)),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          ),
                          style: const TextStyle(fontSize: 14),
                          keyboardType: TextInputType.number,
                          focusNode: _customHargaTotalFocus,
                          onChanged: (v) {
                            _customHargaTotal = double.tryParse(v);
                            if (_customHargaTotal != null) {
                              setState(() {
                                hargaServis = _customHargaTotal;
                              });
                              // Hitung final price dengan voucher jika ada
                              _calculateFinalPrice();
                            }
                          },
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Kode Kupon + Scan
                    SizedBox(
                      width: formWidth,
                      child: TextField(
                        controller: _kodeKuponController,
                        focusNode: _kodeKuponFocus,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.card_giftcard, color: Color(0xFF0B63D4)),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_kodeKuponController.text.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Center(
                                    child: _selectedCouponDoc != null
                                      ? const Icon(Icons.check_circle, color: Colors.green)
                                      : const Icon(Icons.cancel, color: Colors.red),
                                  ),
                                ),
                              IconButton(
                                icon: const Icon(Icons.qr_code_scanner, color: Color(0xFF0B63D4)),
                                onPressed: () async {
                                  _kodeKuponFocus.unfocus();
                                  final scanned = await showQrScannerDialog(
                                    context,
                                    title: 'Scan Kode Kupon',
                                    scanType: 'kupon',
                                    expectedStatus: 'tersedia',
                                  );
                                  if (scanned != null && scanned.isNotEmpty) {
                                    final code = scanned.trim().toUpperCase();
                                    _kodeKuponController.text = code;
                                    kodeKupon = code;
                                    _validateCouponCode(code);
                                    _calculateFinalPrice();
                                  }
                                },
                              )
                            ],
                          ),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          filled: true,
                          fillColor: const Color(0xFFF4F8FF),
                          hintText: 'Kode Kupon',
                          hintStyle: TextStyle(color: Colors.grey.shade500),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        ),
                        style: const TextStyle(fontSize: 14),
                        onChanged: (v) {
                          kodeKupon = v.trim().toUpperCase();
                          setState(() {}); // Update UI untuk suffix icons
                          if (_couponDebounce?.isActive ?? false) _couponDebounce!.cancel();
                          _couponDebounce = Timer(const Duration(milliseconds: 500), () {
                            _validateCouponCode(kodeKupon!);
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Tanggal Servis
                    SizedBox(
                      width: formWidth,
                      child: GestureDetector(
                        onTap: () {
                          _kodePelangganFocus.unfocus();
                          _hargaSparepartFocus.unfocus();
                          _kodeKuponFocus.unfocus();
                          _pickDateTime();
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.calendar_today, color: Color(0xFF0B63D4)),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.access_time, color: Color(0xFF0B63D4)),
                              onPressed: () {
                                _kodePelangganFocus.unfocus();
                                _hargaSparepartFocus.unfocus();
                                _kodeKuponFocus.unfocus();
                                _setNow();
                              },
                            ),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            filled: true,
                            fillColor: const Color(0xFFF4F8FF),
                            hintText: 'Tanggal Servis',
                            hintStyle: TextStyle(color: Colors.grey.shade500),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                          ),
                          child: Text(_tglServisController.text.isNotEmpty ? _tglServisController.text : '', style: const TextStyle(fontSize: 14)),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Display selected voucher above button (if any)
                    if (_selectedRedeemedVoucher != null)
                      Container(
                        width: formWidth,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.card_giftcard, color: Colors.orange),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _selectedRedeemedVoucher!['name'],
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    'Diskon ${_selectedRedeemedVoucher!['discount_percent'].toStringAsFixed(0)}%',
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              tooltip: 'Hapus Voucher',
                              onPressed: () {
                                setState(() {
                                  _selectedRedeemedVoucher = null;
                                });
                                _calculateFinalPrice();
                                showSuccessDialog(
                                  context,
                                  title: 'Voucher Dihapus',
                                  message: 'Voucher telah dibatalkan.',
                                );
                              },
                            ),
                          ],
                        ),
                      ),

                    const SizedBox(height: 12),

                    // Action buttons: Gunakan Voucher (blue) + Input ke Riwayat (orange)
                    SizedBox(
                      width: formWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: 10),
                          _buildGradientButton(
                            label: 'Gunakan Voucher',
                            gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                            onPressed: (_selectedCustomer != null) ? _showVoucherDialog : null,
                          ),
                          const SizedBox(height: 10),
                          _buildGradientButton(
                            label: 'Input ke Riwayat',
                            gradient: const LinearGradient(colors: [Color(0xFFF2994A), Color(0xFFFBAC66)]),
                            onPressed: (_selectedCustomer != null && _finalHargaServis != null && !_isLoading) ? _simpanKeRiwayat : null,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              ],

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    ));
  }

  // Updated selection dialog to accept an optional leading icon to better match each dropdown's semantic
  Future<String?> _showSelectionDialog(String title, List<String> items, String? current, {IconData? leadingIcon}) async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        // Estimate width by longest item length so dialog isn't overly wide
        final int maxChars = items.fold<int>(0, (p, e) => e.length > p ? e.length : p);
        final double estimatedWidth = (maxChars * 7.0) + 120; // slightly tighter per-char estimate
        final double maxAllowed = MediaQuery.of(context).size.width * 0.85;
        final double dialogCap = maxAllowed < 520.0 ? maxAllowed : 520.0;
        final double dialogWidth = estimatedWidth.clamp(280.0, dialogCap);

        // Compute list height based on a max visible items threshold to avoid overly tall dialogs
        final int maxVisibleItems = 6;
        final double itemHeight = 52.0;
        final double headerHeight = 56.0;
        final int visibleCount = items.isEmpty ? 1 : (items.length > maxVisibleItems ? maxVisibleItems : items.length);
        final double listHeight = visibleCount * itemHeight;
        // Add a small cushion to avoid off-by-a-few-pixels overflow from dividers/padding
        final double totalHeight = headerHeight + listHeight + 16.0;

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: totalHeight,
              maxWidth: dialogWidth,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // gradient header (blue) with icon like the calculation dialog
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      Icon(leadingIcon ?? Icons.list, color: Colors.white),
                      const SizedBox(width: 12),
                      Expanded(child: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                      IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close, color: Colors.white))
                    ],
                  ),
                ),
                // SizedBox wrapping ListView to control height precisely
                SizedBox(
                  height: listHeight,
                  child: ListView.separated(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final v = items[index];
                      final selected = v == current;
                      return ListTile(
                        leading: leadingIcon != null ? Icon(leadingIcon, color: const Color(0xFF0B63D4)) : null,
                        title: Text(v, overflow: TextOverflow.ellipsis, maxLines: 1),
                        trailing: selected ? const Icon(Icons.check, color: Colors.green) : null,
                        onTap: () => Navigator.pop(context, v),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// StatefulWidget untuk Edit Harga Total Dialog
class _EditHargaTotalDialog extends StatefulWidget {
  final double initialValue;
  final Function(double) onSave;

  const _EditHargaTotalDialog({
    required this.initialValue,
    required this.onSave,
  });

  @override
  State<_EditHargaTotalDialog> createState() => _EditHargaTotalDialogState();
}

class _EditHargaTotalDialogState extends State<_EditHargaTotalDialog> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue > 0
          ? (widget.initialValue % 1 == 0
              ? widget.initialValue.toInt().toString()
              : widget.initialValue.toString())
          : '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: MediaQuery.of(context).size.width > 800
            ? 400
            : MediaQuery.of(context).size.width * 0.85,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.edit, color: Colors.white),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Ubah Total Harga',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  IconButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  )
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: 'Masukkan harga total (Rp)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      filled: true,
                      fillColor: const Color(0xFFF4F8FF),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    autofocus: true,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Batal'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () {
                                final harga = double.tryParse(_controller.text);
                                if (harga != null && harga > 0) {
                                  widget.onSave(harga);
                                  Navigator.pop(context);
                                }
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: Text(
                                    'Simpan',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
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




