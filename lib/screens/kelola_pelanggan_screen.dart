import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as latlng;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import '../services/connectivity_service.dart';
import '../widgets/animated_dialog.dart';

// Asumsi: Anda sudah menginisialisasi Firebase di tempat lain
final FirebaseFirestore _firestore = FirebaseFirestore.instance;

class KelolaPelangganScreen extends StatefulWidget {
  const KelolaPelangganScreen({super.key});

  @override
  State<KelolaPelangganScreen> createState() => _KelolaPelangganScreenState();
}

class _KelolaPelangganScreenState extends State<KelolaPelangganScreen> {
  final TextEditingController _namaController = TextEditingController();
  final TextEditingController _teleponController = TextEditingController();
  final TextEditingController _alamatController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _showSearchBox = false;

  // Fungsi untuk menghasilkan Kode Pelanggan (Total 6 karakter: P + 5 acak alfanumerik)
  String _generateCustomerCode() {
    const String letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const String numbers = '0123456789';
    const String allChars = letters + numbers;
    Random rnd = Random();
    
    // Inisialisasi dengan 'P'
    String result = 'P'; 
    
    // Daftar untuk 5 karakter acak
    List<String> fiveChars = [];

    // 1. Memastikan minimal ada 1 huruf (untuk menjamin "campur")
    fiveChars.add(letters[rnd.nextInt(letters.length)]);
    
    // 2. Memastikan minimal ada 1 angka (untuk menjamin "campur")
    fiveChars.add(numbers[rnd.nextInt(numbers.length)]);
    
    // 3. Menambahkan 3 karakter lagi secara acak dari semuaChars (total 5)
    for (int i = 0; i < 3; i++) {
      fiveChars.add(allChars[rnd.nextInt(allChars.length)]);
    }

    // Acak urutan 5 karakter tersebut agar tidak berurutan L-A-R-R-R
    fiveChars.shuffle(rnd);

    // Gabungkan 'P' dengan 5 karakter yang sudah diacak
    result += fiveChars.join('');

    return result; // Contoh: Px8Yz2
  }

  // Fungsi untuk menambahkan pelanggan ke Firestore
  Future<void> _addCustomer() async {
    if (_formKey.currentState!.validate()) {
      // ✅ NEW: Check internet connection BEFORE attempting Firestore operations
      final hasInternet = await ConnectivityService.hasInternetConnection();
      if (!hasInternet) {
        showErrorDialog(
          context,
          title: 'Koneksi Tidak Tersedia',
          message: 'Tidak ada koneksi internet. Silakan cek koneksi Anda dan coba lagi.',
        );
        return;
      }

      try {
        // 1. Generate Kode Pelanggan yang unik
        final String kodePelanggan = _generateCustomerCode();

        // 2. Data yang akan disimpan
        final Map<String, dynamic> customerData = {
          'kode_pelanggan': kodePelanggan, // Kode Pelanggan disimpan sebagai field
          'nama': _namaController.text,
          'telepon': _teleponController.text,
          'alamat': _alamatController.text.trim(),
          'tanggal_ditambahkan': FieldValue.serverTimestamp(),
        };

        // 3. Simpan ke koleksi 'pelanggan'.
        //    Metode 'add()' akan otomatis menghasilkan ID dokumen yang acak dan unik.
        await _firestore.collection('pelanggan').add(customerData);

        // Reset form
        _namaController.clear();
        _teleponController.clear();

        // Tampilkan pesan sukses dengan tombol salin kode pelanggan
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, color: Color(0xFF0B63D4), size: 48),
                    const SizedBox(height: 12),
                    const Text('Sukses', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    const SizedBox(height: 8),
                    Text('Pelanggan berhasil ditambahkan!', style: TextStyle(fontSize: 14)),
                    const SizedBox(height: 12),
                    SelectableText('Kode: $kodePelanggan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0B63D4))),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          icon: const Icon(Icons.copy, size: 18),
                          label: const Text('Salin Kode'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0B63D4),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          ),
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: kodePelanggan));
                            Navigator.pop(ctx);
                            showSuccessDialog(context, title: 'Disalin', message: 'Kode pelanggan berhasil disalin!');
                          },
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton(
                          child: const Text('Tutup'),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      } catch (e) {
        // Tampilkan pesan error
        showErrorDialog(
          context,
          title: 'Gagal Menambahkan',
          message: 'Gagal menambahkan pelanggan: $e',
        );
      }
    }
  }

  Future<void> _useCurrentLocation() async {
    try {
      final pos = await _determinePosition();
      final address = await _getAddressFromLatLng(pos.latitude, pos.longitude);
      setState(() => _alamatController.text = address);
      if (mounted) showSuccessDialog(context, title: 'Berhasil', message: 'Alamat terisi dari lokasi saat ini');
    } catch (e) {
      if (mounted) {
        showErrorDialog(context, title: 'Error', message: 'Error: $e');
      }
    }
  }

  Future<void> _pickLocationManual() async {
    try {
      final pos = await _determinePosition();
      await _openMapPicker(initialLatLng: latlng.LatLng(pos.latitude, pos.longitude));
    } catch (e) {
      // Fallback to Jakarta if location unavailable
      await _openMapPicker(initialLatLng: latlng.LatLng(-6.200, 106.816));
    }
  }

  Future<Position> _determinePosition() async {
    bool serviceEnabled;
    LocationPermission permission;

    try {
      serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Layanan lokasi dinonaktifkan. Silakan aktifkan layanan lokasi di pengaturan perangkat.');
      }

      permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Izin lokasi ditolak');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Izin lokasi ditolak secara permanen. Silakan ubah di pengaturan aplikasi.');
      }

      return await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
    } catch (e) {
      // Re-throw with user-friendly message
      throw Exception('Gagal mendapatkan lokasi: $e');
    }
  }

  Future<String> _getAddressFromLatLng(double lat, double lon) async {
    try {
      final List<geocoding.Placemark> placemarks = await geocoding.placemarkFromCoordinates(lat, lon);
      if (placemarks.isEmpty) return '$lat,$lon';
      final p = placemarks.first;
      final parts = [p.name, p.street, p.subLocality, p.locality, p.administrativeArea, p.postalCode, p.country];
      final address = parts.where((s) => s != null && s.isNotEmpty).join(', ');
      return address;
    } catch (e) {
      return '$lat,$lon';
    }
  }

  Future<void> _openMapPicker({latlng.LatLng? initialLatLng}) async {
    final mapController = MapController();
    latlng.LatLng center = initialLatLng ?? latlng.LatLng(-6.200, 106.816);
    latlng.LatLng? selected;

    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: SizedBox(
                width: double.maxFinite,
                height: 520,
                child: Column(
                  children: [
                    // Header dengan gradient
                    Container(
                      height: 56,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                        borderRadius: BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
                      ),
                      child: Row(children: [
                        const SizedBox(width: 16),
                        const Expanded(child: Text('Tap peta untuk pilih lokasi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14))),
                        IconButton(onPressed: () => Navigator.of(ctx).pop(), icon: const Icon(Icons.close, color: Colors.white))
                      ]),
                    ),
                    
                    // Map dengan gesture detector untuk center marker
                    Expanded(
                      child: Stack(
                        children: [
                          FlutterMap(
                            mapController: mapController,
                            options: MapOptions(
                              center: center,
                              zoom: 13,
                              onTap: (tapPos, latlngPoint) {
                                // Update selected location ketika user tap
                                selected = latlng.LatLng(latlngPoint.latitude, latlngPoint.longitude);
                                setDialogState(() {}); // Refresh UI
                              },
                            ),
                            children: [
                              TileLayer(
                                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                                subdomains: const ['a', 'b', 'c'],
                                userAgentPackageName: 'com.pilotrepair.pilot_finance',
                              ),
                              // Marker layer yang menampilkan selected location
                              if (selected != null)
                                MarkerLayer(markers: [
                                  Marker(
                                    point: selected!,
                                    width: 60,
                                    height: 60,
                                    builder: (ctx) => const Icon(Icons.location_on, color: Color(0xFF0B63D4), size: 56),
                                  )
                                ])
                              else
                                MarkerLayer(markers: [
                                  Marker(
                                    point: center,
                                    width: 60,
                                    height: 60,
                                    builder: (ctx) => const Icon(Icons.location_on, color: Color(0xFF0B63D4), size: 56),
                                  )
                                ]),
                            ],
                          ),
                          
                          // Crosshair di tengah map (opsional visual guide)
                          Center(
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.transparent, width: 2),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Container(width: 2, height: 10, color: Colors.transparent),
                                  Container(
                                    width: 24,
                                    height: 2,
                                    decoration: BoxDecoration(
                                      color: Colors.transparent,
                                      borderRadius: BorderRadius.circular(1),
                                    ),
                                  ),
                                  Container(width: 2, height: 10, color: Colors.transparent),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    
                    // Button controls
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(ctx).pop(),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade300),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Batal', style: TextStyle(color: Color(0xFF0B63D4), fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              if (selected == null) {
                                showWarningDialog(
                                  ctx,
                                  title: 'Perhatian',
                                  message: 'Silakan tap peta untuk memilih lokasi',
                                );
                                return;
                              }
                              // Get address from selected location
                              final address = await _getAddressFromLatLng(selected!.latitude, selected!.longitude);
                              Navigator.of(ctx).pop(address);
                            },
                            style: ElevatedButton.styleFrom(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: const Color(0xFF1AA965),
                            ),
                            child: const Text('Konfirmasi Lokasi', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                          ),
                        )
                      ]),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (picked != null && picked.isNotEmpty) {
      setState(() => _alamatController.text = picked);
      if (mounted) showSuccessDialog(context, title: 'Berhasil', message: 'Alamat diperbarui dari peta');
    }
  }

  // Fungsi untuk menghapus pelanggan
  Future<void> _deleteCustomer(String docId, String kodePelanggan) async {
    // ✅ NEW: Check internet connection BEFORE attempting Firestore operations
    final hasInternet = await ConnectivityService.hasInternetConnection();
    if (!hasInternet) {
      showErrorDialog(
        context,
        title: 'Koneksi Tidak Tersedia',
        message: 'Tidak ada koneksi internet. Silakan cek koneksi Anda dan coba lagi.',
      );
      return;
    }

    try {
      await _firestore.collection('pelanggan').doc(docId).delete();
      if (mounted) {
        showSuccessDialog(
          context,
          title: 'Sukses',
          message: 'Pelanggan $kodePelanggan berhasil dihapus.',
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          title: 'Gagal Menghapus',
          message: 'Gagal menghapus pelanggan: $e',
        );
      }
    }
  }

  @override
  void dispose() {
    _namaController.dispose();
    _teleponController.dispose();
    _alamatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(100),
        child: Container(
          padding: const EdgeInsets.only(top: 28, left: 16, right: 16, bottom: 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                const SizedBox(width: 8),
                const Expanded(child: Text('Kelola Pelanggan', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
                IconButton(
                  icon: const Icon(Icons.search, color: Colors.white, size: 24),
                  onPressed: () {
                    setState(() {
                      _showSearchBox = !_showSearchBox;
                      if (!_showSearchBox) {
                        _searchController.clear();
                      }
                    });
                  },
                ),
              ],
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 4))],
                ),
                padding: const EdgeInsets.all(14),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Name
                      TextFormField(
                        controller: _namaController,
                        decoration: InputDecoration(
                          hintText: 'Nama Pelanggan',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0B63D4), width: 2)),
                          filled: true,
                          fillColor: Colors.grey.shade200,
                          prefixIcon: const Icon(Icons.person),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Nama pelanggan tidak boleh kosong';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Phone
                      TextFormField(
                        controller: _teleponController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          hintText: 'Nomor Telepon',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0B63D4), width: 2)),
                          filled: true,
                          fillColor: Colors.grey.shade200,
                          prefixIcon: const Icon(Icons.phone),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) return 'Nomor telepon tidak boleh kosong';
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),

                      // Address
                      TextFormField(
                        controller: _alamatController,
                        keyboardType: TextInputType.multiline,
                        maxLines: 4,
                        decoration: InputDecoration(
                          hintText: 'Alamat (opsional) — bisa isi otomatis dari lokasi',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0B63D4), width: 2)),
                          filled: true,
                          fillColor: Colors.grey.shade200,
                          prefixIcon: const Icon(Icons.place),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Location buttons
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: OutlinedButton(
                                onPressed: _useCurrentLocation,
                                style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.shade300), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: const [Icon(Icons.location_on, color: Color(0xFF0B63D4), size: 20), SizedBox(width: 6), Expanded(child: Text('Ambil Lokasi', style: TextStyle(color: Color(0xFF0B63D4), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))]),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: SizedBox(
                              height: 44,
                              child: OutlinedButton(
                                onPressed: _pickLocationManual,
                                style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.shade300), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                                child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: const [Icon(Icons.map, color: Color(0xFF0B63D4), size: 20), SizedBox(width: 6), Expanded(child: Text('Titik Lokasi', style: TextStyle(color: Color(0xFF0B63D4), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis))]),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      // Submit
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _addCustomer,
                          style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), backgroundColor: Colors.transparent, elevation: 2),
                          child: Ink(
                            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]), borderRadius: BorderRadius.all(Radius.circular(8))),
                            child: Container(alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 16), child: const Text('Tambah Pelanggan Baru', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Search box (muncul ketika search icon diklik)
            if (_showSearchBox)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Cari berdasarkan nama / kode / nomor telepon...',
                    prefixIcon: const Icon(Icons.search, color: Color(0xFF0B63D4)),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, color: Color(0xFF0B63D4)),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade300)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0B63D4), width: 2)),
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  ),
                  onChanged: (value) {
                    setState(() {});
                  },
                ),
              ),
            
            // Search results
            if (_showSearchBox)
              StreamBuilder<QuerySnapshot>(
                stream: _firestore.collection('pelanggan').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Padding(padding: const EdgeInsets.all(16), child: Text('Terjadi kesalahan: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Padding(padding: EdgeInsets.all(16), child: Text('Belum ada data pelanggan.'));
                  }

                  final List<DocumentSnapshot> allDocs = snapshot.data!.docs;
                  final searchQuery = _searchController.text.toLowerCase();
                  
                  // Filter berdasarkan search query
                  final filteredDocs = allDocs.where((doc) {
                    final data = doc.data() as Map<String, dynamic>;
                    final nama = (data['nama'] ?? '').toString().toLowerCase();
                    final kode = (data['kode_pelanggan'] ?? '').toString().toLowerCase();
                    final telepon = (data['telepon'] ?? '').toString().toLowerCase();
                    
                    return nama.contains(searchQuery) || kode.contains(searchQuery) || telepon.contains(searchQuery);
                  });

                  if (filteredDocs.isEmpty) {
                    return Padding(padding: const EdgeInsets.all(16), child: Text(searchQuery.isEmpty ? 'Ketik untuk mencari...' : 'Tidak ada hasil pencarian'));
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filteredDocs.length,
                    itemBuilder: (context, index) {
                      final doc = filteredDocs.toList()[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final docId = doc.id;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            gradient: LinearGradient(
                              colors: [Colors.white, Colors.grey.shade50],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(12.0),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: const Color(0xFF0B63D4),
                                  radius: 24,
                                  child: Text(
                                    (data['kode_pelanggan'] as String?)?.substring(0, 1) ?? 'P',
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        data['nama'] ?? 'Tanpa Nama',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Kode: ${data['kode_pelanggan'] ?? '-'}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Telepon: ${data['telepon'] ?? '-'}',
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Alamat: ${data['alamat'] ?? '-'}',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                      onPressed: () => _deleteCustomer(docId, data['kode_pelanggan'] ?? 'ini'),
                                      tooltip: 'Hapus',
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}


