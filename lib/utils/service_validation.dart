import 'package:cloud_firestore/cloud_firestore.dart';

class ServiceValidation {
  /// Menghitung masa garansi dan status kadaluarsa
  /// 
  /// Returns: Map dengan keys: endDate (DateTime?), displayString, isExpired
  static Map<String, dynamic> hitungMasaGaransi(DateTime tanggal, String garansi) {
    final garansiLower = garansi.toLowerCase();
    DateTime? masaAktif;
    final now = DateTime.now();

    // Parse format "30 Hari", "1 Tahun", dll
    final regex = RegExp(r'(\d+)\s*(\w+)');
    final match = regex.firstMatch(garansiLower);

    final durasi = match != null ? int.tryParse(match.group(1)!) ?? 0 : 0;
    final satuan = match != null ? match.group(2)!.toLowerCase() : '';

    // Jika tidak ada durasi atau "tidak ada" → tidak ada garansi
    if (durasi == 0 || garansiLower.contains("tidak ada")) {
      return {
        'endDate': null,
        'displayString': "Tidak ada garansi",
        'isExpired': false,
      };
    }

    // Hitung masa aktif garansi berdasarkan satuan
    if (satuan.contains("tahun")) {
      masaAktif = DateTime(
        tanggal.year + durasi,
        tanggal.month,
        tanggal.day,
        tanggal.hour,
        tanggal.minute,
      );
    } else if (satuan.contains("bulan")) {
      masaAktif = DateTime(
        tanggal.year,
        tanggal.month + durasi,
        tanggal.day,
        tanggal.hour,
        tanggal.minute,
      );
    } else if (satuan.contains("minggu")) {
      masaAktif = tanggal.add(Duration(days: 7 * durasi));
    } else if (satuan.contains("hari")) {
      masaAktif = tanggal.add(Duration(days: durasi));
    } else if (satuan.contains("jam")) {
      masaAktif = tanggal.add(Duration(hours: durasi));
    } else if (satuan.contains("menit")) {
      masaAktif = tanggal.add(Duration(minutes: durasi));
    } else if (satuan.contains("detik")) {
      masaAktif = tanggal.add(Duration(seconds: durasi));
    }

    if (masaAktif == null) {
      return {
        'endDate': null,
        'displayString': "Garansi tidak terdefinisi",
        'isExpired': false,
      };
    }

    final isExpired = now.isAfter(masaAktif);
    
    // Cek apakah sisa garansi ≤ 1 menit (untuk menampilkan countdown detik)
    final remainingTime = masaAktif.difference(now);
    final String displayString;
    
    if (remainingTime.inSeconds <= 0) {
      // Sudah kadaluarsa
      displayString = "Kadaluarsa";
    } else if (remainingTime.inSeconds <= 60) {
      // Sisa garansi ≤ 1 menit: tampilkan dalam detik
      final seconds = remainingTime.inSeconds;
      displayString = "$seconds detik";
    } else {
      // Normal: tampilkan tanggal akhir
      displayString = "Hingga ${_formatDate(masaAktif)}";
    }

    return {
      'endDate': masaAktif,
      'displayString': displayString,
      'isExpired': isExpired,
    };
  }

  /// Format tanggal ke format "dd MMM yyyy, HH:mm"
  static String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final monthName = months[date.month - 1];
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return "${date.day.toString().padLeft(2, '0')} $monthName ${date.year}, $hour:$minute";
  }

  /// Mengambil data koleksi dari Firestore
  static Future<List<QueryDocumentSnapshot>> fetchCollection(String collectionName) async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection(collectionName).get();
      return snapshot.docs;
    } catch (e) {
      return [];
    }
  }

  /// Mengambil garansi unik dari collection 'garansi'
  /// Format: "30 Hari", "1 Tahun", dll
  static Future<List<String>> fetchUniqueGaransi() async {
    try {
      final snapshot = await FirebaseFirestore.instance.collection('garansi').get();
      final Set<String> uniqueGaransi = {};

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;

        int? lama;
        if (data?['lama'] != null) {
          final lamaRaw = data!['lama'];
          if (lamaRaw is int) {
            lama = lamaRaw;
          } else if (lamaRaw is String) {
            lama = int.tryParse(lamaRaw);
          }
        }

        final satuanRaw = data?['satuan'];
        final satuan = satuanRaw is String ? satuanRaw : null;

        if (lama != null && satuan != null && satuan.isNotEmpty) {
          uniqueGaransi.add("$lama $satuan");
        }
      }

      return uniqueGaransi.toList();
    } catch (e) {
      return [];
    }
  }

  /// Mengambil seri berdasarkan nama merk
  static Future<List<QueryDocumentSnapshot>> fetchSeriByMerk(String merkName) async {
    if (merkName.isEmpty) return [];

    try {
      final merkSnapshot = await FirebaseFirestore.instance
          .collection('merk')
          .where('nama', isEqualTo: merkName)
          .limit(1)
          .get();

      if (merkSnapshot.docs.isEmpty) return [];

      final merkId = merkSnapshot.docs.first.id;
      final seriSnapshot = await FirebaseFirestore.instance
          .collection('seri')
          .where('merk_id', isEqualTo: merkId)
          .get();

      return seriSnapshot.docs;
    } catch (e) {
      return [];
    }
  }

  /// Validasi kode pelanggan di Firestore
  /// Returns: Map dengan data pelanggan dan docId, atau null jika tidak ditemukan
  static Future<Map<String, dynamic>?> validateCustomerCode(String code) async {
    if (code.isEmpty) return null;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('pelanggan')
          .where('kode_pelanggan', isEqualTo: code)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        return {
          'data': doc.data(),
          'docId': doc.id,
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Validasi kode kupon manual di Firestore
  /// Returns: DocumentSnapshot jika valid, null jika tidak ditemukan
  static Future<DocumentSnapshot?> validateCouponCode(String code) async {
    if (code.isEmpty) return null;

    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('kupon')
          .where('kode', isEqualTo: code)
          .where('status', isEqualTo: 'tersedia')
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        return snapshot.docs.first;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Mengambil voucher siap pakai untuk pelanggan
  static Future<List<Map<String, dynamic>>> getAvailableVouchersForCustomer(String kodePelanggan) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('vouchers')
          .where('kode_pelanggan_penukar', isEqualTo: kodePelanggan)
          .where('status', isEqualTo: 'siap pakai')
          .get();

      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'code': (data['kode'] ?? data['code'])?.toString(),
          'name': data['name'] ?? data['nama'] ?? '',
          'discount_percent': (data['discount_percent'] as num?)?.toDouble() ?? 0.0,
          'max_discount': (data['max_discount'] as num?)?.toDouble() ?? 0.0,
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  /// Validasi apakah ada draft data yang belum disimpan
  /// Gunakan di home_screen untuk check sebelum navigate keluar
  static bool hasDraftData({
    required String? kodePelangganInput,
    required String? jenisServis,
    required String? merkHp,
    required String? seriHp,
    required String? garansi,
    required String? hargaSparepartInput,
    required String? kodeKuponInput,
    required bool hasSelectedVoucher,
  }) {
    return (kodePelangganInput?.isNotEmpty ?? false) ||
        jenisServis != null ||
        merkHp != null ||
        seriHp != null ||
        garansi != null ||
        (hargaSparepartInput?.isNotEmpty ?? false) ||
        (kodeKuponInput?.isNotEmpty ?? false) ||
        hasSelectedVoucher;
  }
}

