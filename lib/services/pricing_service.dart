import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class PricingService {
  /// Menghitung harga jual dengan markup berdasarkan harga sparepart dan jenis servis
  /// Rumus: harga_sparepart + (markup * harga_sparepart) + biaya_dasar
  /// 
  /// Parameters:
  /// - hargaSparepart: Harga sparepart
  /// - jenisServis: Jenis servis ("LCD" atau "baterai"), default "LCD"
  static double hitungHargaJual(double hargaSparepart, {String jenisServis = "LCD"}) {
    double markup = 0;
    double biayaDasar = 0;

    // Normalize: lowercase dan hapus spasi
    final jenisServisNormalized = jenisServis.toLowerCase().trim();

    if (jenisServisNormalized == "baterai") {
      // Rumus untuk baterai
      if (hargaSparepart <= 50000) {
        markup = 0.35;
        biayaDasar = 72000;
      } else if (hargaSparepart <= 100000) {
        markup = 0.30;
        biayaDasar = 75000;
      } else if (hargaSparepart <= 150000) {
        markup = 0.25;
        biayaDasar = 80000;
      } else if (hargaSparepart <= 200000) {
        markup = 0.20;
        biayaDasar = 88000;
      } else if (hargaSparepart <= 250000) {
        markup = 0.15;
        biayaDasar = 98000;
      }
    } else {
      // Rumus default untuk LCD
      if (hargaSparepart <= 100000) {
        markup = 0.45;
        biayaDasar = 99000;
      } else if (hargaSparepart <= 250000) {
        markup = 0.28;
        biayaDasar = 116000;
      } else if (hargaSparepart <= 400000) {
        markup = 0.20;
        biayaDasar = 136000;
      } else if (hargaSparepart <= 600000) {
        markup = 0.15;
        biayaDasar = 157000;
      } else if (hargaSparepart <= 800000) {
        markup = 0.09;
        biayaDasar = 195000;
      }
    }

    return hargaSparepart + (markup * hargaSparepart) + biayaDasar;
  }

  /// Membulatkan harga ke ribuan terdekat
  /// Contoh: 123456 -> 123000
  static double roundToThousand(double price) {
    return (price / 1000).round() * 1000.0;
  }

  /// Menghitung harga servis kotor (sebelum diskon voucher)
  static double hitungHargaServisKotor(double hargaSparepart, {String jenisServis = "LCD"}) {
    if (hargaSparepart <= 0) return 0.0;
    final hargaJual = hitungHargaJual(hargaSparepart, jenisServis: jenisServis);
    return roundToThousand(hargaJual);
  }

  /// Menghitung harga final setelah diskon voucher/kupon
  /// 
  /// Parameters:
  /// - hargaServisKotor: Harga servis sebelum diskon (kotor)
  /// - discountPercent: Persentase diskon voucher (0-100)
  /// - maxDiscount: Maksimal diskon yang bisa diambil
  /// 
  /// Returns: Harga final setelah diskon diterapkan
  static double hitungHargaFinal({
    required double hargaServisKotor,
    required double discountPercent,
    required double maxDiscount,
  }) {
    if (hargaServisKotor <= 0) return 0.0;

    // Hitung diskon: harga servis x discount_percent
    double discountAmount = hargaServisKotor * (discountPercent / 100.0);

    // Batasi dengan max_discount
    if (discountAmount > maxDiscount) {
      discountAmount = maxDiscount;
    }

    // Harga final setelah diskon
    double finalPrice = hargaServisKotor - discountAmount;

    // Pastikan tidak negatif
    if (finalPrice < 0) {
      finalPrice = 0.0;
    }

    return finalPrice;
  }

  /// Mengambil data voucher dari Firestore berdasarkan kode
  /// 
  /// Returns: Map berisi discount_percent dan max_discount, atau null jika tidak ditemukan
  static Future<Map<String, dynamic>?> getVoucherData(String kodeVoucher) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('vouchers')
          .where('kode', isEqualTo: kodeVoucher)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final voucherDoc = snapshot.docs.first.data();
        return {
          'discount_percent': (voucherDoc['discount_percent'] as num?)?.toDouble() ?? 0.0,
          'max_discount': (voucherDoc['max_discount'] as num?)?.toDouble() ?? 0.0,
        };
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// Format harga ke format currency Indonesia
  static String formatCurrency(double amount) {
    final format = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    return format.format(amount);
  }

  /// Parsing harga dari string (menghilangkan Rp dan koma)
  static double parseCurrencyString(String text) {
    final cleaned = text.replaceAll(RegExp(r'[^0-9]'), '');
    return cleaned.isEmpty ? 0.0 : double.parse(cleaned);
  }

  /// Menghitung harga final dengan priority: voucher redeemed > voucher dari kode > tidak ada diskon
  /// 
  /// Parameters:
  /// - hargaSparepart: Harga sparepart input
  /// - jenisServis: Jenis servis ("LCD" atau "baterai"), default "LCD"
  /// - redeemedVoucher: Data voucher yang sudah ditukarkan (dari transaksi_penukaran)
  /// - voucherData: Data voucher jika input manual
  /// 
  /// Returns: Map dengan keys: hargaServisKotor, hargaServisFinal, discountAmount
  static Map<String, double> calculateServicePrices({
    required double hargaSparepart,
    String jenisServis = "LCD",
    Map<String, dynamic>? redeemedVoucher,
    Map<String, dynamic>? voucherData,
  }) {
    double basePrice = hitungHargaServisKotor(hargaSparepart, jenisServis: jenisServis);
    double finalPrice = basePrice;
    double discountAmount = 0.0;

    // Priority 1: Voucher yang sudah ditukarkan
    if (redeemedVoucher != null) {
      final percent = (redeemedVoucher['discount_percent'] as num?)?.toDouble() ?? 0.0;
      final maxDiscount = (redeemedVoucher['max_discount'] as num?)?.toDouble() ?? 0.0;

      discountAmount = basePrice * (percent / 100.0);
      if (discountAmount > maxDiscount) {
        discountAmount = maxDiscount;
      }

      finalPrice = basePrice - discountAmount;
    }
    // Priority 2: Voucher dari input manual
    else if (voucherData != null) {
      final percent = (voucherData['discount_percent'] as num?)?.toDouble() ?? 0.0;
      final maxDiscount = (voucherData['max_discount'] as num?)?.toDouble() ?? 0.0;

      discountAmount = basePrice * (percent / 100.0);
      if (discountAmount > maxDiscount) {
        discountAmount = maxDiscount;
      }

      finalPrice = basePrice - discountAmount;
    }

    // Pastikan tidak negatif
    if (finalPrice < 0) {
      finalPrice = 0.0;
    }

    return {
      'hargaServisKotor': basePrice,
      'hargaServisFinal': finalPrice,
      'discountAmount': discountAmount,
    };
  }
}
