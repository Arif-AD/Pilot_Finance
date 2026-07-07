import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import '../services/connectivity_service.dart';
import '../widgets/animated_dialog.dart';

class KelolaGaransiScreen extends StatefulWidget {
  const KelolaGaransiScreen({super.key});

  @override
  State<KelolaGaransiScreen> createState() => _KelolaGaransiScreenState();
}

class _KelolaGaransiScreenState extends State<KelolaGaransiScreen> {
  final TextEditingController _lamaController = TextEditingController();
  String? _selectedSatuan;
  final List<String> _satuanOptions = ['menit','Jam', 'Hari', 'Minggu', 'Bulan', 'Tahun'];

  // --- CRUD FUNCTIONS ---

  // 1. Tambah Data Garansi
  Future<void> _tambahGaransi() async {
    final lama = int.tryParse(_lamaController.text);
    final satuan = _selectedSatuan;

    if (lama == null || satuan == null || satuan.isEmpty || lama <= 0) {
      _showWarningMessage("Mohon isi Lama Garansi (angka positif) dan Satuan dengan benar.");
      return;
    }

    // ✅ NEW: Check internet connection BEFORE attempting Firestore operations
    final hasInternet = await ConnectivityService.hasInternetConnection();
    if (!hasInternet) {
      _showErrorMessage("Tidak ada koneksi internet. Silakan cek koneksi Anda dan coba lagi.");
      return;
    }

    try {
      // Cek apakah kombinasi Lama dan Satuan sudah ada
      final existingDocs = await FirebaseFirestore.instance
          .collection('garansi')
          .where('lama', isEqualTo: lama)
          .where('satuan', isEqualTo: satuan)
          .limit(1)
          .get();

      if (existingDocs.docs.isNotEmpty) {
        _showWarningMessage("Garansi $lama $satuan sudah ada.");
        return;
      }

      await FirebaseFirestore.instance.collection('garansi').add({
        'lama': lama,
        'satuan': satuan,
      });

      _lamaController.clear();
      setState(() {
        _selectedSatuan = null;
      });
      _showSuccessMessage("Berhasil menambahkan Garansi: $lama $satuan");
    } catch (e) {
      _showErrorMessage("Gagal menambahkan data: $e");
    }
  }

  // 2. Hapus Data Garansi
  Future<void> _hapusGaransi(String docId, int lama, String satuan) async {
    // Tampilkan konfirmasi
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Konfirmasi Hapus"),
        content: Text("Yakin ingin menghapus garansi: $lama $satuan?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Batal"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Hapus", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // ✅ NEW: Check internet connection BEFORE attempting Firestore operations
      final hasInternet = await ConnectivityService.hasInternetConnection();
      if (!hasInternet) {
        _showErrorMessage("Tidak ada koneksi internet. Silakan cek koneksi Anda dan coba lagi.");
        return;
      }

      try {
        await FirebaseFirestore.instance.collection('garansi').doc(docId).delete();
        _showSuccessMessage("Berhasil menghapus garansi: $lama $satuan");
      } catch (e) {
        _showErrorMessage("Gagal menghapus data: $e");
      }
    }
  }

  // Helper untuk menampilkan dialog
  void _showSuccessMessage(String message) {
    showSuccessDialog(context, title: 'Sukses', message: message);
  }

  void _showErrorMessage(String message) {
    showErrorDialog(context, title: 'Gagal', message: message);
  }

  void _showWarningMessage(String message) {
    showWarningDialog(context, title: 'Perhatian', message: message);
  }

  @override
  void dispose() {
    _lamaController.dispose();
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
              children: const [
                CircleAvatar(radius: 24, backgroundColor: Colors.white24, child: Icon(Icons.timer_outlined, color: Colors.white)),
                SizedBox(width: 12),
                Expanded(child: Text('Kelola Garansi', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold))),
              ],
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0,4))],
              ),
              child: Row(
                children: const [
                  Icon(Icons.info_outline, color: Color(0xFF0B63D4)),
                  SizedBox(width: 10),
                  Expanded(child: Text('Kelola Garansi. Tambah atau hapus entri garansi.', style: TextStyle(fontSize: 13))),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Input form (responsive)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0,3))]),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  if (constraints.maxWidth < 520) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _lamaController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(hintText: 'Lama Garansi', filled: true, fillColor: const Color(0xFFF6F8FB), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF6F8FB), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                          value: _selectedSatuan,
                          hint: const Text('Satuan'),
                          items: _satuanOptions.map((String value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                          onChanged: (String? newValue) => setState(() => _selectedSatuan = newValue),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 48,
                          child: ElevatedButton(
                            onPressed: _tambahGaransi,
                            style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), backgroundColor: Colors.transparent, elevation: 2),
                            child: Ink(
                              decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]), borderRadius: BorderRadius.all(Radius.circular(8))),
                              child: Container(alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 16), child: const Text('Tambah', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                            ),
                          ),
                        ),
                      ],
                    );
                  }

                  return Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _lamaController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(hintText: 'Lama Garansi', filled: true, fillColor: const Color(0xFFF6F8FB), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: DropdownButtonFormField<String>(
                          decoration: InputDecoration(filled: true, fillColor: const Color(0xFFF6F8FB), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
                          value: _selectedSatuan,
                          hint: const Text('Satuan'),
                          items: _satuanOptions.map((String value) => DropdownMenuItem(value: value, child: Text(value))).toList(),
                          onChanged: (String? newValue) => setState(() => _selectedSatuan = newValue),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 100,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _tambahGaransi,
                          style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), backgroundColor: Colors.transparent, elevation: 2),
                          child: Ink(
                            decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]), borderRadius: BorderRadius.all(Radius.circular(8))),
                            child: Container(alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 16), child: const Text('Tambah', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),

            const SizedBox(height: 14),

            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance.collection('garansi').orderBy('lama').snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) return Center(child: Text('Terjadi kesalahan: ${snapshot.error}'));
                  if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                  final docs = snapshot.data?.docs ?? [];
                  if (docs.isEmpty) return const Center(child: Text('Belum ada data Garansi.'));
                  return ListView.builder(
                    itemCount: docs.length,
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>;
                      final lama = data['lama'] is int ? data['lama'] : (data['lama'] is String ? int.tryParse(data['lama']) ?? 0 : 0);
                      final satuan = data['satuan'] ?? 'N/A';
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0,3))]),
                        child: Row(
                          children: [
                            Expanded(child: Text('$lama $satuan', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500))),
                            IconButton(onPressed: () => _hapusGaransi(doc.id, lama, satuan), icon: const Icon(Icons.delete, color: Colors.red)),
                          ],
                        ),
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

