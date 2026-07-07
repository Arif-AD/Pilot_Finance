import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../services/connectivity_service.dart';
import '../services/pricing_service.dart';
import '../utils/service_validation.dart';
import '../widgets/animated_dialog.dart';

class RiwayatScreen extends StatefulWidget {
  const RiwayatScreen({super.key});

  @override
  State<RiwayatScreen> createState() => _RiwayatScreenState();
}

class GaransiResult {
  final DateTime? endDate;
  final String displayString;
  final bool isExpired;

  GaransiResult({
    required this.endDate,
    required this.displayString,
    required this.isExpired,
  });
}

/// Stream yang emit setiap detik untuk countdown real-time
Stream<int> _countdownStream() async* {
  while (true) {
    await Future.delayed(const Duration(seconds: 1));
    yield DateTime.now().second;
  }
}

/// Widget untuk menampilkan countdown garansi real-time (hanya ketika sisa ≤ 60 detik)
class _GaransiCountdownWidget extends StatelessWidget {
  final DateTime tanggalServis;
  final String garansi;
  final TextStyle textStyle;

  const _GaransiCountdownWidget({
    required this.tanggalServis,
    required this.garansi,
    required this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _countdownStream(),
      builder: (context, snapshot) {
        final garansiStatus = ServiceValidation.hitungMasaGaransi(tanggalServis, garansi);
        final remaining = garansiStatus['endDate'] != null
            ? (garansiStatus['endDate'] as DateTime).difference(DateTime.now()).inSeconds
            : -1;

        // Hanya tampilkan stream countdown jika sisa ≤ 60 detik
        // Jika > 60 detik atau expired, tampil static text (tidak perlu stream)
        if (remaining > 60) {
          return Text(garansiStatus['displayString'], style: textStyle);
        }

        // Jika countdown, tampil real-time
        return Text(garansiStatus['displayString'], style: textStyle);
      },
    );
  }
}

class _RiwayatScreenState extends State<RiwayatScreen> {
  String _searchText = "";
  final TextEditingController _searchController = TextEditingController();

  void _lihatDetail(BuildContext context, DocumentSnapshot doc) {
    final tanggal = (doc['tanggal'] as Timestamp).toDate();
    final format = DateFormat('dd MMM yyyy, HH:mm');
    final NumberFormat currencyFormat = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                  borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Detail Riwayat Servis',
                        style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildDetailRow("Kode Pelanggan", doc['kode_pelanggan']),
                        const SizedBox(height: 12),
                        _buildDetailRow("Kode Pesanan", doc['kode_pesanan']),
                        const SizedBox(height: 12),
                        _buildDetailRow("Jenis Servis", doc['jenis_servis']),
                        const SizedBox(height: 12),
                        _buildDetailRow("Merk", doc['merk']),
                        const SizedBox(height: 12),
                        _buildDetailRow("Seri", doc['seri']),
                        const SizedBox(height: 12),
                        _buildDetailRow("Garansi", doc['garansi']),
                        const SizedBox(height: 12),
                        _buildDetailRow("Harga Servis", currencyFormat.format(doc['harga_servis'] ?? 0)),
                        const SizedBox(height: 12),
                        _buildDetailRow("Harga Akhir", currencyFormat.format(doc['harga_servis_final'] ?? 0), isBold: true),
                        if (doc['harga_sparepart'] != null) ...[const SizedBox(height: 12), _buildDetailRow("Harga Sparepart", currencyFormat.format(doc['harga_sparepart']))],
                        const SizedBox(height: 12),
                        _buildDetailRow("Tanggal Input/Edit", format.format(tanggal)),
                        if (doc['kode_kupon'] != null && doc['kode_kupon'] != "") ...[const SizedBox(height: 12), _buildDetailRow("Kode Kupon", doc['kode_kupon'])],
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                child: SizedBox(
                  width: double.infinity,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(context),
                        borderRadius: BorderRadius.circular(8),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Tutup',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, dynamic value, {bool isBold = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F5FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF666666)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value.toString(),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
                color: isBold ? const Color(0xFF0B63D4) : const Color(0xFF1a1a1a),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _editRiwayat(BuildContext context, DocumentSnapshot doc) {
    showDialog(
      context: context,
      builder: (_) => _EditServiceDialog(doc: doc),
    );
  }

  InputDecoration _buildSearchInputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: Colors.grey[500], fontSize: 14),
      filled: true,
      fillColor: const Color(0xFFF0F5FF),
      prefixIcon: const Icon(Icons.search, color: Color(0xFF0B63D4)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF0B63D4), width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // ✅ IMMEDIATE navigation: Quick unmount before Firestore queries complete
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      },
      child: Scaffold(
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(70),
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
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Riwayat Servis', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: _buildSearchInputDecoration(
                      "Cari servis, merk, seri, kode kupon, harga...",
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchText = value.toLowerCase();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 12),
                // Single Unified Search (removed dual filter dropdown)
              ],
            ),
          ),

          // List Riwayat
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('riwayat')
                  .orderBy('tanggal', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text("Terjadi kesalahan"));
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = snapshot.data?.docs ?? [];

                // Unified Filtering: Search across all fields, now including nama pelanggan & kode pelanggan
                final filteredData = data.where((doc) {
                  final jenis = (doc['jenis_servis'] ?? '').toString().toLowerCase();
                  final merk = (doc['merk'] ?? '').toString().toLowerCase();
                  final seri = (doc['seri'] ?? '').toString().toLowerCase();
                  final kodeVoucher = (doc['kode_kupon'] ?? '').toString().toLowerCase();
                  final harga = (doc['harga_servis_final'] ?? doc['harga_servis'] ?? '').toString().toLowerCase();

                  // Aman: cek field ada sebelum akses
                  String namaPelanggan = '';
                  String kodePelanggan = '';
                  try {
                    if (doc.data() != null && (doc.data() as Map<String, dynamic>).containsKey('nama_pelanggan')) {
                      namaPelanggan = (doc['nama_pelanggan'] ?? '').toString().toLowerCase();
                    }
                    if (doc.data() != null && (doc.data() as Map<String, dynamic>).containsKey('kode_pelanggan')) {
                      kodePelanggan = (doc['kode_pelanggan'] ?? '').toString().toLowerCase();
                    }
                  } catch (_) {
                    namaPelanggan = '';
                    kodePelanggan = '';
                  }

                  if (_searchText.isEmpty) return true;

                  // Search across all fields with single unified search
                  return jenis.contains(_searchText) ||
                      merk.contains(_searchText) ||
                      seri.contains(_searchText) ||
                      kodeVoucher.contains(_searchText) ||
                      harga.contains(_searchText) ||
                      namaPelanggan.contains(_searchText) ||
                      kodePelanggan.contains(_searchText);
                });

                if (filteredData.isEmpty) {
                  return const Center(child: Text("Tidak ada data yang cocok"));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: filteredData.length,
                itemBuilder: (context, index) {
                    final doc = filteredData.toList()[index];
                    final jenis = doc['jenis_servis'];
                    final merk = doc['merk'];
                    final seri = doc['seri'];
                    final harga = doc['harga_servis_final'] ?? doc['harga_servis'];
                    final garansi = doc['garansi'];
                    final tanggal = (doc['tanggal'] as Timestamp).toDate();

                    return _RiwayatItemWidget(
                      jenis: jenis,
                      merk: merk,
                      seri: seri,
                      harga: harga,
                      garansi: garansi,
                      tanggalServis: tanggal,
                      doc: doc,
                      onEdit: () => _editRiwayat(context, doc),
                      onDetail: () => _lihatDetail(context, doc),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      ),
    );
  }
}

/// Widget reusable untuk display item riwayat dengan real-time garansi status
class _RiwayatItemWidget extends StatelessWidget {
  final String jenis;
  final String merk;
  final String seri;
  final dynamic harga;
  final String garansi;
  final DateTime tanggalServis;
  final DocumentSnapshot doc;
  final VoidCallback onEdit;
  final VoidCallback onDetail;

  const _RiwayatItemWidget({
    required this.jenis,
    required this.merk,
    required this.seri,
    required this.harga,
    required this.garansi,
    required this.tanggalServis,
    required this.doc,
    required this.onEdit,
    required this.onDetail,
  });

  @override
  Widget build(BuildContext context) {
    final NumberFormat currencyFormat = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return StreamBuilder<int>(
      stream: _countdownStream(),
      builder: (context, snapshot) {
        // Recalculate warranty status every time stream emits
        final garansiStatus = ServiceValidation.hitungMasaGaransi(tanggalServis, garansi);
        final isExpired = garansiStatus['isExpired'] as bool;

        final garansiTextStyle = TextStyle(
          color: isExpired ? Colors.red : Colors.green.shade700,
          fontWeight: isExpired ? FontWeight.bold : FontWeight.w600,
          fontSize: 13,
        );

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header: Jenis Servis, Merk, Seri
                Text(
                  "$jenis - $merk $seri",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: Color(0xFF1a1a1a),
                  ),
                ),
                const SizedBox(height: 10),

                // Garansi Info (with real-time background color update)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: (isExpired ? Colors.red : Colors.green).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Garansi: $garansi",
                        style: const TextStyle(fontSize: 13, color: Color(0xFF555555)),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Text(
                            "Masa Garansi: ",
                            style: TextStyle(fontSize: 13, color: Color(0xFF555555)),
                          ),
                          _GaransiCountdownWidget(
                            tanggalServis: tanggalServis,
                            garansi: garansi,
                            textStyle: garansiTextStyle,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Harga
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Harga Akhir:",
                      style: TextStyle(fontSize: 13, color: Color(0xFF666666)),
                    ),
                    Text(
                      currencyFormat.format(harga),
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0B63D4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Buttons di bawah
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onEdit,
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.edit, color: Colors.white, size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    "Edit",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F5FF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF0B63D4), width: 1.2),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: onDetail,
                            borderRadius: BorderRadius.circular(8),
                            child: const Padding(
                              padding: EdgeInsets.symmetric(vertical: 10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.visibility, color: Color(0xFF0B63D4), size: 18),
                                  SizedBox(width: 6),
                                  Text(
                                    "Lihat",
                                    style: TextStyle(
                                      color: Color(0xFF0B63D4),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
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
        );
      },
    );
  }
}

class _EditServiceDialog extends StatefulWidget {
  final DocumentSnapshot doc;
  const _EditServiceDialog({required this.doc});

  @override
  State<_EditServiceDialog> createState() => _EditServiceDialogState();
}

class _EditServiceDialogState extends State<_EditServiceDialog> {
  late String _selectedJenisServis;
  late String _selectedMerk;
  late String _selectedSeri;
  late String _selectedGaransi;
  late double _originalHargaServisFinal;
  late double _hargaServisFinal;
  late double _hargaSparepart;
  late double _hargaServis; // Harga kotor sebelum diskon voucher
  double? _customHargaTotal; // Custom harga untuk jenis servis non-LCD/Baterai
  late String? _kodeKupon;
  Map<String, dynamic>? _selectedRedeemedVoucher; // Voucher yang ditukarkan
  late bool _isVoucherOriginal; // Flag: true jika voucher dari data original (tidak bisa diubah)
  late String? _kodePelanggan; // Diambil dari dokumen untuk kebutuhan voucher
  late TextEditingController _hargaServisFinalController;
  late TextEditingController _hargaSparepartController;
  late TextEditingController _customHargaTotalController;
  DateTime? _selectedTanggal;
  late TextEditingController _dateController;
  
  late DateTime _tanggalServis; // Tanggal servis dari dokumen (untuk kalkulasi garansi real-time)
  late String _originalGaransi; // Track garansi original untuk detect perubahan
  bool _garansiChanged = false; // Flag: true jika user ubah garansi dropdown

  late Future<List<QueryDocumentSnapshot>> _jenisServisFuture;
  late Future<List<QueryDocumentSnapshot>> _merkFuture;
  late Future<List<String>> _garansiUniqueFuture;

  @override
  void initState() {
    super.initState();
    final data = widget.doc.data() as Map<String, dynamic>;

    _selectedJenisServis = data['jenis_servis'] ?? '';
    _selectedMerk = data['merk'] ?? '';
    _selectedSeri = data['seri'] ?? '';
    _selectedGaransi = data['garansi'] ?? '';
    _originalGaransi = _selectedGaransi; // Store original untuk detect perubahan

    _originalHargaServisFinal = (data['harga_servis_final'] is num) ? data['harga_servis_final'].toDouble() : 0.0;
    _hargaServisFinal = _originalHargaServisFinal;
    _hargaSparepart = (data['harga_sparepart'] is num) ? data['harga_sparepart'].toDouble() : 0.0;
    _hargaServis = (data['harga_servis'] is num) ? data['harga_servis'].toDouble() : 0.0;
    _kodeKupon = data['kode_kupon'];
    
    // Cek apakah ada voucher yang sudah terpakai di data riwayat ini
    final kodeVoucherTerpakai = data['kode_voucher'];
    if (kodeVoucherTerpakai != null && kodeVoucherTerpakai.toString().isNotEmpty) {
      // Load info voucher yang sudah terpakai
      _loadRedeemedVoucher(kodeVoucherTerpakai);
      _isVoucherOriginal = true; // Flag: voucher dari data original, tidak bisa diubah
    } else {
      _selectedRedeemedVoucher = null; // Initially no redeemed voucher selected
      _isVoucherOriginal = false;
    }
    
    _kodePelanggan = data['kode_pelanggan']; // Untuk kebutuhan fetch voucher

    _hargaServisFinalController = TextEditingController(
      text: NumberFormat.currency(
        locale: 'id_ID', 
        symbol: 'Rp ', 
        decimalDigits: 0,
      ).format(_hargaServisFinal),
    );

    _hargaSparepartController = TextEditingController(
      text: _hargaSparepart > 0 ? _hargaSparepart.toStringAsFixed(0) : '',
    );

    _customHargaTotalController = TextEditingController(
      text: _customHargaTotal != null ? _customHargaTotal!.toStringAsFixed(0) : '',
    );

    _selectedTanggal = null;
    
    _dateController = TextEditingController(
      text: '',
    );

    _jenisServisFuture = _fetchCollection('jenis_servis');
    _merkFuture = _fetchCollection('merk');
    _garansiUniqueFuture = _fetchUniqueGaransi();

    _tanggalServis = (data['tanggal'] as Timestamp).toDate();
    
    // Load voucher data asynchronously
    _loadVoucherData();
  }

  @override
  void dispose() {
    _hargaServisFinalController.dispose();
    _hargaSparepartController.dispose();
    _customHargaTotalController.dispose();
    _dateController.dispose(); 
    super.dispose();
  }

  GaransiResult _hitungMasaGaransi(DateTime tanggal, String garansi) {
    final result = ServiceValidation.hitungMasaGaransi(tanggal, garansi);
    return GaransiResult(
      endDate: result['endDate'],
      displayString: result['displayString'],
      isExpired: result['isExpired'],
    );
  }

  // Getter untuk menghitung status garansi secara real-time (dipanggil setiap kali build)
  GaransiResult get _currentGaransiStatus {
    return _hitungMasaGaransi(_tanggalServis, _selectedGaransi);
  }
  
  Future<List<QueryDocumentSnapshot>> _fetchCollection(String collectionName) async {
    return ServiceValidation.fetchCollection(collectionName);
  }

  Future<List<String>> _fetchUniqueGaransi() async {
    return ServiceValidation.fetchUniqueGaransi();
  }

  Future<List<QueryDocumentSnapshot>> _fetchSeriByMerk(String merkName) async {
    return ServiceValidation.fetchSeriByMerk(merkName);
  }

  Future<void> _selectTanggal(BuildContext context) async {
    DateTime initialDate = _selectedTanggal ?? DateTime.now();
    
    // ignore: use_build_context_synchronously
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)), 
    );

    if (pickedDate != null && mounted) {
      final TimeOfDay? pickedTime = await showTimePicker(
        // ignore: use_build_context_synchronously
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedTanggal ?? DateTime.now()), 
      );

      if (pickedTime != null && mounted) {
        final DateTime newDateTime = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );

        setState(() {
          _selectedTanggal = newDateTime;
          _dateController.text = DateFormat('dd MMM yyyy, HH:mm').format(newDateTime);
        });
      }
    }
  }

  void _setTanggalTerkini() {
    final DateTime now = DateTime.now();
    setState(() {
      _selectedTanggal = now;
      _dateController.text = DateFormat('dd MMM yyyy, HH:mm').format(now);
    });
  }

  Future<void> _updateRiwayat() async {
    // ✅ Jika garansi berubah, tanggal wajib diisi
    if (_garansiChanged && _selectedTanggal == null) {
      if (!mounted) return;
      showErrorDialog(
        context,
        title: 'Tanggal Wajib',
        message: 'Karena Anda mengubah garansi, tanggal servis wajib diisi untuk update warranty calculation.',
      );
      return;
    }

    // ✅ Check internet connection BEFORE attempting Firestore operations
    final hasInternet = await ConnectivityService.hasInternetConnection();
    if (!hasInternet) {
      if (!mounted) return;
      showErrorDialog(
        context,
        title: 'Koneksi Tidak Tersedia',
        message: 'Tidak ada koneksi internet. Silakan cek koneksi Anda dan coba lagi.',
      );
      return;
    }
    
    try {
      // Parse harga sparepart dari textbox (untuk memastikan nilai terbaru tersimpan)
      final hargaSparepartText = _hargaSparepartController.text.replaceAll(RegExp(r'[^0-9]'), '');
      final parsedHargaSparepart = hargaSparepartText.isEmpty ? 0.0 : double.parse(hargaSparepartText);
      
      final updateData = <String, dynamic>{
        'jenis_servis': _selectedJenisServis,
        'merk': _selectedMerk,
        'seri': _selectedSeri,
        'garansi': _selectedGaransi,
        'harga_sparepart': parsedHargaSparepart,
        'harga_servis': _hargaServis,
        'harga_servis_final': _hargaServisFinal,
      };
      
      // Simpan kode_voucher jika user menambahkan voucher baru (tidak dari original)
      if (_selectedRedeemedVoucher != null && !_isVoucherOriginal) {
        updateData['kode_voucher'] = _selectedRedeemedVoucher!['code'];
      }
      
      // Hanya update tanggal jika sudah dipilih (tidak wajib untuk edit data biasa)
      if (_selectedTanggal != null) {
        updateData['tanggal'] = Timestamp.fromMicrosecondsSinceEpoch(_selectedTanggal!.microsecondsSinceEpoch);
      }

      await FirebaseFirestore.instance
          .collection('riwayat')
          .doc(widget.doc.id)
          .update(updateData);

      // ✅ Handle voucher status change (jika ada voucher baru yang dipilih)
      // Tidak menyimpan ke field riwayat, hanya ubah status dan catat di pelanggan
      if (_selectedRedeemedVoucher != null) {
        final newVoucherCode = _selectedRedeemedVoucher!['code'];
        
        // 1. Ubah status voucher jadi "hangus"
        final voucherSnapshot = await FirebaseFirestore.instance
            .collection('vouchers')
            .where('kode', isEqualTo: newVoucherCode)
            .limit(1)
            .get();

        if (voucherSnapshot.docs.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('vouchers')
              .doc(voucherSnapshot.docs.first.id)
              .update({'status': 'hangus'});
        }

        // 2. Tambahkan ke used_vouchers di dokumen pelanggan
        if (_kodePelanggan != null && _kodePelanggan!.isNotEmpty) {
          await FirebaseFirestore.instance
              .collection('pelanggan')
              .where('kode_pelanggan', isEqualTo: _kodePelanggan!)
              .limit(1)
              .get()
              .then((snapshot) {
            if (snapshot.docs.isNotEmpty) {
              FirebaseFirestore.instance
                  .collection('pelanggan')
                  .doc(snapshot.docs.first.id)
                  .update({
                    'used_vouchers': FieldValue.arrayUnion([newVoucherCode])
                  });
            }
          });
        }
      }

      if (mounted) {
        _originalHargaServisFinal = _hargaServisFinal;
        
        Navigator.pop(context);
        showSuccessDialog(
          context,
          title: 'Sukses',
          message: 'Berhasil mengupdate riwayat',
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          title: 'Gagal Update',
          message: 'Gagal update: $e',
        );
      }
    }
  }

  void _handleKlaimGaransi(bool isSuccessful) {

    if (mounted) Navigator.pop(context); 
      double newHargaServisFinal;
      String statusMessage;

    if (!isSuccessful) {
      newHargaServisFinal = _originalHargaServisFinal - _hargaSparepart;

      if (newHargaServisFinal < 0) {
        newHargaServisFinal = 0.0;
      }

      statusMessage = "Klaim Gagal. Harga servis akhir dikurangi sebesar ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(_hargaSparepart)}. (Perubahan ini akan disimpan setelah Anda menekan tombol 'Simpan')";
      
    } else {
      newHargaServisFinal = _originalHargaServisFinal;
      statusMessage = "Klaim Berhasil. Harga servis akhir tidak berubah. (Perubahan ini akan disimpan setelah Anda menekan tombol 'Simpan')";
    }

    setState(() {
      _hargaServisFinal = newHargaServisFinal;
      _hargaServisFinalController.text = NumberFormat.currency(
        locale: 'id_ID',
        symbol: 'Rp ',
        decimalDigits: 0,
      ).format(_hargaServisFinal);
    });
    
    if (mounted) {
      showSuccessDialog(
        context,
        title: 'Berhasil',
        message: statusMessage,
      );
    }
  }

  // Rumus yang sama dengan home_screen.dart
  // Menggunakan PricingService dari utility
  double hitungHargaJual(double hs) {
    return PricingService.hitungHargaJual(hs, jenisServis: _selectedJenisServis.isNotEmpty ? _selectedJenisServis : "LCD");
  }

  // Helper: Cek apakah jenis servis adalah custom (bukan LCD/Baterai)
  bool _isCustomServiceType() {
    if (_selectedJenisServis.isEmpty) return false;
    final normalized = _selectedJenisServis.toLowerCase().trim();
    return normalized != 'lcd' && normalized != 'baterai';
  }

  void _recalculateFinalPrice() {
    setState(() {
      // Untuk LCD/Baterai: hitung dari harga sparepart yang baru
      if (!_isCustomServiceType()) {
        // Parse harga sparepart dari textbox
        final hargaSparepartText = _hargaSparepartController.text.replaceAll(RegExp(r'[^0-9]'), '');
        final newHargaSparepart = hargaSparepartText.isEmpty ? 0.0 : double.parse(hargaSparepartText);
        _hargaSparepart = newHargaSparepart;
        
        // Hitung harga servis kotor menggunakan rumus
        final basePrice = hitungHargaJual(newHargaSparepart);
        // Bulatkan ke ribuan terdekat (000)
        final basePriceRounded = (basePrice / 1000).round() * 1000.toDouble();
        _hargaServis = basePriceRounded;
        
        // Hitung final price dengan mempertimbangkan voucher
        if (_selectedRedeemedVoucher != null) {
          final percent = (_selectedRedeemedVoucher!['discount_percent'] as num?)?.toDouble() ?? 0.0;
          final maxDiscount = (_selectedRedeemedVoucher!['max_discount'] as num?)?.toDouble() ?? 0.0;

          double discountAmount = basePriceRounded * (percent / 100.0);
          if (discountAmount > maxDiscount) {
            discountAmount = maxDiscount;
          }

          _hargaServisFinal = basePriceRounded - discountAmount;
          if (_hargaServisFinal < 0) {
            _hargaServisFinal = 0.0;
          }
        } else {
          // Tidak ada voucher, gunakan base price yang sudah dibulatkan
          _hargaServisFinal = basePriceRounded;
        }
      } else {
        // Untuk custom service type: gunakan original final price dengan voucher discount
        if (_selectedRedeemedVoucher != null) {
          final basePrice = _originalHargaServisFinal;
          final percent = (_selectedRedeemedVoucher!['discount_percent'] as num?)?.toDouble() ?? 0.0;
          final maxDiscount = (_selectedRedeemedVoucher!['max_discount'] as num?)?.toDouble() ?? 0.0;

          double discountAmount = basePrice * (percent / 100.0);
          if (discountAmount > maxDiscount) {
            discountAmount = maxDiscount;
          }

          _hargaServisFinal = basePrice - discountAmount;
          if (_hargaServisFinal < 0) {
            _hargaServisFinal = 0.0;
          }
        } else {
          _hargaServisFinal = _originalHargaServisFinal;
        }
      }

      // Update textbox display
      _hargaServisFinalController.text = PricingService.formatCurrency(_hargaServisFinal);
    });
  }

  Future<void> _loadVoucherData() async {
    // Jika ada kode_kupon, ambil data voucher menggunakan PricingService
    if (_kodeKupon != null && _kodeKupon!.isNotEmpty) {
      final voucherData = await PricingService.getVoucherData(_kodeKupon!);
      if (voucherData != null) {
        // Recalculate with voucher data
        _recalculateFinalPrice();
      }
    }
  }

  Future<void> _showVoucherDialog() async {
    if (_kodePelanggan == null || _kodePelanggan!.isEmpty) {
      showWarningDialog(
        context,
        title: 'Perhatian',
        message: 'Kode Pelanggan tidak ditemukan.',
      );
      return;
    }

    try {
      // Ambil voucher siap pakai untuk pelanggan
      final availableVouchers = await ServiceValidation.getAvailableVouchersForCustomer(_kodePelanggan!);

      if (availableVouchers.isEmpty) {
        if (!mounted) return;
        showWarningDialog(
          context,
          title: 'Info',
          message: 'Tidak ada voucher siap pakai untuk pelanggan ini.',
        );
        return;
      }

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
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(14), topRight: Radius.circular(14)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.card_giftcard, color: Colors.white, size: 20),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Pilih Voucher',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(Icons.close, color: Colors.white, size: 20),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        child: ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: availableVouchers.length,
                          itemBuilder: (context, index) {
                            final voucher = availableVouchers[index];
                            final code = voucher['code'] ?? 'N/A';
                            final name = voucher['name'] ?? '';
                            final discountPercent = voucher['discount_percent'] ?? 0.0;
                            final maxDiscount = voucher['max_discount'] ?? 0.0;

                            return Container(
                              margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F5FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF0B63D4), width: 1),
                              ),
                              child: ListTile(
                                onTap: () {
                                  setState(() {
                                    _selectedRedeemedVoucher = voucher;
                                  });
                                  _recalculateFinalPrice();
                                  Navigator.pop(context);

                                  showSuccessDialog(
                                    context,
                                    title: 'Berhasil',
                                    message: 'Voucher $code berhasil dipilih',
                                  );
                                },
                                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                title: Text(
                                  'Kode: $code',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    if (name.isNotEmpty)
                                      Text('Nama: $name', style: const TextStyle(fontSize: 12)),
                                    Text(
                                      'Diskon: ${discountPercent.toStringAsFixed(0)}% (Max: ${PricingService.formatCurrency(maxDiscount)})',
                                      style: const TextStyle(fontSize: 12, color: Colors.green),
                                    ),
                                  ],
                                ),
                                trailing: const Icon(Icons.arrow_forward, color: Color(0xFF0B63D4)),
                              ),
                            );
                          },
                        ),
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
          message: 'Gagal memuat voucher: $e',
        );
      }
    }
  }

  // Fungsi untuk load voucher yang sudah terpakai
  void _loadRedeemedVoucher(String kodeVoucher) async {
    try {
      final voucherSnapshot = await FirebaseFirestore.instance
          .collection('vouchers')
          .where('kode', isEqualTo: kodeVoucher)
          .limit(1)
          .get();

      if (voucherSnapshot.docs.isNotEmpty) {
        final voucherData = voucherSnapshot.docs.first.data();
        setState(() {
          _selectedRedeemedVoucher = {
            'code': voucherData['kode'] ?? '',
            'discount_percent': (voucherData['discount_percent'] as num?)?.toDouble() ?? 0.0,
            'max_discount': (voucherData['max_discount'] as num?)?.toDouble() ?? 0.0,
          };
        });
      }
    } catch (e) {
      // Silent catch - voucher mungkin sudah dihapus
    }
  }

  void _showKlaimGaransiDialog() {
    if (_selectedTanggal == null) {
      if (mounted) {
        showWarningDialog(
          context,
          title: 'Perhatian',
          message: 'Pilih Tanggal (Wajib) terlebih dahulu.',
        );
      }
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Status Klaim Garansi"),
        content: Text("Pilih status hasil dari klaim garansi yang terjadi pada tanggal ${_dateController.text}:"),
        actions: [
          TextButton(
            onPressed: () => _handleKlaimGaransi(true), // Berhasil
            child: const Text("Berhasil"),
          ),
          TextButton(
            onPressed: () => _handleKlaimGaransi(false), // Gagal
            child: const Text("Gagal"),
          ),
        ],
      ),
    );
  }

  InputDecoration _buildDialogInputDecoration(String label, IconData? prefixIcon) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF666666), fontSize: 13),
      filled: true,
      fillColor: const Color(0xFFF0F5FF),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, color: const Color(0xFF0B63D4), size: 20) : null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Color(0xFF0B63D4), width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    );
  }

  Widget _buildDocDropdown(
    String label,
    Future<List<QueryDocumentSnapshot>> dataFuture,
    String? selectedValue,
    void Function(String?) onChanged,
    String fieldName,
  ) {
    IconData? icon;
    if (label.contains("Jenis")) icon = Icons.build;
    if (label.contains("Merk")) icon = Icons.branding_watermark;
    
    return FutureBuilder<List<QueryDocumentSnapshot>>(
      future: dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text("Memuat $label...", style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
          );
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text("Gagal memuat $label atau data kosong.", style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
          );
        }
        
        final items = snapshot.data ?? [];
        final dropdownItems = (items.map((doc) {
          final value = doc[fieldName] as String? ?? 'N/A';
          return DropdownMenuItem<String>(
            value: value,
            child: Text(value, style: const TextStyle(fontSize: 13)),
          );
        }).toList());

        if (selectedValue != null && !dropdownItems.any((item) => item.value == selectedValue)) {
            dropdownItems.insert(0, DropdownMenuItem<String>(value: selectedValue, child: Text("$selectedValue (Lama)", style: const TextStyle(fontSize: 13))));
        }

        return DropdownButtonFormField<String>(
          decoration: _buildDialogInputDecoration(label, icon),
          value: selectedValue,
          items: dropdownItems.isEmpty
              ? [const DropdownMenuItem(child: Text("Tidak ada data"))]
              : dropdownItems,
          onChanged: onChanged,
        );
      },
    );
  }

  Widget _buildStringDropdown(
    String label,
    Future<List<String>> dataFuture,
    String? selectedValue,
    void Function(String?) onChanged,
  ) {
    return FutureBuilder<List<String>>(
      future: dataFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text("Memuat $label...", style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
          );
        }
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text("Gagal memuat $label atau data kosong.", style: const TextStyle(fontSize: 13, color: Color(0xFF666666))),
          );
        }
        
        final items = snapshot.data ?? [];
        
        List<DropdownMenuItem<String>> dropdownItems = items.map((value) {
          return DropdownMenuItem<String>(
            value: value,
            child: Text(value, style: const TextStyle(fontSize: 13)),
          );
        }).toList();

        if (selectedValue != null && selectedValue!.isNotEmpty) {
          final sv = selectedValue;
          if (!dropdownItems.any((item) => item.value == sv)) {
            dropdownItems.insert(
              0,
              DropdownMenuItem<String>(value: sv, child: Text("$sv (Lama)", style: const TextStyle(fontSize: 13))),
            );
          }
        } else {
          selectedValue = null;
        }

        return DropdownButtonFormField<String>(
          decoration: _buildDialogInputDecoration(label, Icons.verified),
          value: selectedValue,
          items: dropdownItems.isEmpty
              ? [const DropdownMenuItem(child: Text("Tidak ada data"))]
              : dropdownItems,
          onChanged: onChanged,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // Tentukan apakah tombol klaim garansi harus dinonaktifkan (real-time)
    final bool isClaimButtonEnabled = !_currentGaransiStatus.isExpired;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_note, color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Edit Data Servis',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: (_currentGaransiStatus.isExpired ? Colors.red : Colors.green).withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (_currentGaransiStatus.isExpired ? Colors.red : Colors.green).withValues(alpha: 0.3),
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          _currentGaransiStatus.isExpired 
                            ? "Masa Garansi: KADALUARSA" 
                            : "Masa Garansi: ${_currentGaransiStatus.displayString}",
                          style: TextStyle(
                            color: _currentGaransiStatus.isExpired ? Colors.red : Colors.green.shade800,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      // 1. Jenis Servis Dropdown
                      _buildDocDropdown(
                        "Jenis Servis",
                        _jenisServisFuture,
                        _selectedJenisServis,
                        (newValue) {
                          setState(() {
                            _selectedJenisServis = newValue!;
                            // Reset harga sparepart saat jenis servis berubah
                            _hargaSparepart = 0.0;
                            _hargaServis = 0.0;
                            _hargaServisFinal = 0.0;
                            _customHargaTotal = null;
                            _hargaSparepartController.clear();
                            _customHargaTotalController.clear();
                            _hargaServisFinalController.clear();
                          });
                        },
                        'nama', 
                      ),
                      const SizedBox(height: 16),

                      // 2. Merk Dropdown
                      _buildDocDropdown(
                        "Merk",
                        _merkFuture,
                        _selectedMerk,
                        (newValue) {
                          setState(() {
                            _selectedMerk = newValue!;
                            _selectedSeri = '';
                          });
                        },
                        'nama', 
                      ),
                      const SizedBox(height: 16),

                      // 3. Seri Dropdown
                      FutureBuilder<List<QueryDocumentSnapshot>>(
                        future: _fetchSeriByMerk(_selectedMerk),
                        builder: (context, snapshot) {
                          if (snapshot.connectionState == ConnectionState.waiting && _selectedMerk.isNotEmpty) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8.0),
                              child: Text("Memuat Seri...", style: TextStyle(fontSize: 13, color: Color(0xFF666666))),
                            );
                          }
                          
                          final items = snapshot.data ?? [];
                          final dropdownItems = (items.map((doc) {
                            final value = doc['nama'] as String? ?? 'N/A';
                            return DropdownMenuItem<String>(
                              value: value,
                              child: Text(value, style: const TextStyle(fontSize: 13)),
                            );
                          }).toList());
                          
                          String? currentSeri = _selectedSeri;
                          
                          if (currentSeri.isNotEmpty && !dropdownItems.any((item) => item.value == currentSeri)) {
                              dropdownItems.insert(0, DropdownMenuItem<String>(value: currentSeri, child: Text("$currentSeri (Lama)", style: const TextStyle(fontSize: 13))));
                          }

                          return DropdownButtonFormField<String>(
                            decoration: _buildDialogInputDecoration("Seri", Icons.devices),
                            value: currentSeri.isNotEmpty ? currentSeri : null,
                            items: dropdownItems.isEmpty
                                ? [const DropdownMenuItem(child: Text("Pilih Merk Dulu"))]
                                : dropdownItems,
                            onChanged: (newValue) {
                              setState(() {
                                _selectedSeri = newValue!;
                              });
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 16),

                      // Garansi Dropdown
                      _buildStringDropdown(
                        "Garansi (Lama Satuan)",
                        _garansiUniqueFuture,
                        _selectedGaransi,
                        (newValue) {
                          setState(() {
                            _selectedGaransi = newValue!;
                            // Detect perubahan garansi: jika berbeda dari original, set flag
                            _garansiChanged = (_selectedGaransi != _originalGaransi);
                          });
                        },
                      ),
                      const SizedBox(height: 16),

                      // Harga Sparepart Textbox
                      TextFormField(
                        controller: _hargaSparepartController,
                        decoration: _buildDialogInputDecoration(
                          "Harga Sparepart",
                          Icons.attach_money,
                        ).copyWith(
                          prefixText: "Rp ",
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        onChanged: (_) => _recalculateFinalPrice(),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 16),

                      // Custom Harga Total untuk jenis servis custom (bukan LCD/Baterai)
                      if (_isCustomServiceType())
                        Column(
                          children: [
                            TextFormField(
                              controller: _customHargaTotalController,
                              decoration: _buildDialogInputDecoration(
                                "Harga Total (Custom)",
                                Icons.attach_money,
                              ).copyWith(
                                prefixText: "Rp ",
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              onChanged: (v) {
                                _customHargaTotal = v.isEmpty ? null : double.tryParse(v);
                                if (_customHargaTotal != null) {
                                  setState(() {
                                    _hargaServis = _customHargaTotal!;
                                    _hargaServisFinal = _customHargaTotal!;
                                    _hargaServisFinalController.text = PricingService.formatCurrency(_customHargaTotal!);
                                  });
                                }
                              },
                              style: const TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                          ],
                        ),

                      // Tanggal
                      TextFormField(
                        controller: _dateController,
                        decoration: _buildDialogInputDecoration(
                          _garansiChanged ? "Tanggal (Wajib)" : "Tanggal (Opsional)",
                          Icons.calendar_today,
                        ).copyWith(
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.calendar_today, color: Color(0xFF0B63D4), size: 18),
                                onPressed: () => _selectTanggal(context),
                                tooltip: 'Pilih Tanggal & Waktu',
                              ),
                              IconButton(
                                icon: const Icon(Icons.timer, color: Color(0xFF0B63D4), size: 18),
                                onPressed: _setTanggalTerkini,
                                tooltip: 'Ambil Waktu Terkini',
                              ),
                            ],
                          ),
                        ),
                        readOnly: true,
                        validator: _garansiChanged ? (value) {
                          if (value == null || value.isEmpty) {
                            return 'Tanggal wajib diisi jika mengubah garansi';
                          }
                          return null;
                        } : null,
                      ),
                      const SizedBox(height: 16), 

                      // Harga Akhir
                      TextFormField(
                        controller: _hargaServisFinalController,
                        decoration: _buildDialogInputDecoration("Harga Servis Akhir (Final)", Icons.money).copyWith(
                          prefixText: "Rp ",
                        ),
                        readOnly: true, 
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0B63D4), fontSize: 13),
                      ),
                      const SizedBox(height: 16),

                      // Section: Voucher (hanya tampil jika belum ada voucher yang ditetapkan)
                      if (_selectedRedeemedVoucher == null)
                        Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF8E1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFFFB74D), width: 1),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _showVoucherDialog,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                                child: Row(
                                  children: [
                                    const Icon(Icons.card_giftcard, color: Color(0xFFFFB74D), size: 20),
                                    const SizedBox(width: 12),
                                    const Expanded(
                                      child: Text(
                                        'Gunakan Voucher',
                                        style: TextStyle(
                                          color: Color(0xFFFFB74D),
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    const Icon(Icons.arrow_forward, color: Color(0xFFFFB74D), size: 16),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.green.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.green, width: 1),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Voucher Aktif',
                                style: TextStyle(
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Kode: ${_selectedRedeemedVoucher!['code'] ?? 'N/A'}',
                                style: const TextStyle(fontSize: 12, color: Colors.black87),
                              ),
                              Text(
                                'Diskon: ${_selectedRedeemedVoucher!['discount_percent']?.toStringAsFixed(0) ?? '0'}% (Max: ${PricingService.formatCurrency(_selectedRedeemedVoucher!['max_discount'] ?? 0.0)})',
                                style: const TextStyle(fontSize: 12, color: Colors.green),
                              ),
                              const SizedBox(height: 8),
                              if (!_isVoucherOriginal)
                                GestureDetector(
                                  onTap: () {
                                    setState(() {
                                      _selectedRedeemedVoucher = null;
                                      _isVoucherOriginal = false;
                                    });
                                    _recalculateFinalPrice();
                                  },
                                  child: const Text(
                                    'Hapus Voucher',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.red,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                )
                              else
                                const Text(
                                  'Voucher dari data lama (tidak bisa diubah)',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.orange,
                                    fontStyle: FontStyle.italic,
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
            // Buttons
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                children: [
                  // Tombol Klaim (1 kolom penuh)
                  SizedBox(
                    width: double.infinity,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isClaimButtonEnabled
                              ? [Colors.green.shade600, Colors.green.shade400]
                              : [Colors.grey.shade400, Colors.grey.shade300],
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: isClaimButtonEnabled ? _showKlaimGaransiDialog : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.receipt_long, color: Colors.white, size: 18),
                                const SizedBox(width: 6),
                                const Text(
                                  'Klaim Garansi',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Tombol Batal dan Simpan (2 kolom)
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF0F5FF),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFF0B63D4), width: 1.2),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.pop(context),
                              borderRadius: BorderRadius.circular(8),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.close, color: Color(0xFF0B63D4), size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      'Batal',
                                      style: TextStyle(color: Color(0xFF0B63D4), fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Container(
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                            borderRadius: BorderRadius.all(Radius.circular(8)),
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: _updateRiwayat,
                              borderRadius: BorderRadius.circular(8),
                              child: const Padding(
                                padding: EdgeInsets.symmetric(vertical: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.check_circle, color: Colors.white, size: 18),
                                    SizedBox(width: 6),
                                    Text(
                                      'Simpan',
                                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14),
                                    ),
                                  ],
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



