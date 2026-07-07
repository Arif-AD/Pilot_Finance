import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/connectivity_service.dart';
import '../widgets/animated_dialog.dart';
import 'dart:async';
import 'dart:math';

// --- Model Data Voucher dari Firestore ---
class Voucher {
  final String id;
  final String code;
  final String name; // Nama/Tipe Voucher
  final int kuponDiperlukan;
  final String status;

  Voucher({
    required this.id,
    required this.code,
    required this.name,
    required this.kuponDiperlukan,
    required this.status,
  });
}

// --- QR Scanner Dialog dengan Kamera ---
// scanType: 'voucher' atau 'kupon'
Future<String?> showQrScannerDialog(
  BuildContext context, {
  String title = 'Scan QR Code',
  String scanType = 'voucher', // 'voucher' atau 'kupon'
  String? selectedVoucherName, // Untuk validasi voucher
  String? expectedStatus, // Optional expected status (mis. 'tersedia' or 'siap pakai')
  String? customerCode, // Kode pelanggan untuk validasi kupon
  List<String>? existingCouponCodes, // Kode kupon yang sudah diinput
}) async {
  // Request izin kamera
  final PermissionStatus status = await Permission.camera.request();

  if (status.isDenied) {
    if (context.mounted) {
      showErrorDialog(
        context,
        title: 'Izin Diperlukan',
        message: 'Izin kamera diperlukan untuk scan QR code.',
      );
    }
    return null;
  } else if (status.isPermanentlyDenied) {
    if (context.mounted) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Izin Kamera Dibutuhkan'),
          content: const Text(
            'Aplikasi ini memerlukan akses kamera untuk scan QR code. '
            'Silakan aktifkan izin kamera di pengaturan aplikasi.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Tutup'),
            ),
            TextButton(
              onPressed: () {
                openAppSettings();
                Navigator.pop(ctx);
              },
              child: const Text('Buka Pengaturan'),
            ),
          ],
        ),
      );
    }
    return null;
  }

    if (context.mounted) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => QrScannerDialog(
        title: title,
        scanType: scanType,
        selectedVoucherName: selectedVoucherName,
        expectedStatus: expectedStatus,
        customerCode: customerCode,
        existingCouponCodes: existingCouponCodes,
      ),
    );
  }
  return null;
}

class QrScannerDialog extends StatefulWidget {
  final String title;
  final String scanType; // 'voucher' atau 'kupon'
  final String? selectedVoucherName;
  final String? expectedStatus;
  final String? customerCode; // Kode pelanggan untuk validasi kupon
  final List<String>? existingCouponCodes; // Kode kupon yang sudah diinput
  
  const QrScannerDialog({
    super.key,
    required this.title,
    required this.scanType,
    this.selectedVoucherName,
    this.expectedStatus,
    this.customerCode,
    this.existingCouponCodes,
  });

  @override
  State<QrScannerDialog> createState() => _QrScannerDialogState();
}

class _QrScannerDialogState extends State<QrScannerDialog> {
  late MobileScannerController cameraController;
  bool _scanProcessed = false;
  late TextEditingController _manualInputController;
  String _validationMessage = '';
  bool _isValidating = false;

  @override
  void initState() {
    super.initState();
    cameraController = MobileScannerController();
    _manualInputController = TextEditingController();
  }

  @override
  void dispose() {
    cameraController.dispose();
    _manualInputController.dispose();
    super.dispose();
  }

  Future<void> _validateScannedCode(String scannedValue) async {
    setState(() {
      _isValidating = true;
      _validationMessage = 'Memvalidasi kode...';
    });

    try {
      final upperCode = scannedValue.toUpperCase();

      if (widget.scanType == 'voucher') {
        // Cari voucher dengan kode tersebut
        final voucherSnapshot = await FirebaseFirestore.instance
            .collection('vouchers')
            .where('kode', isEqualTo: upperCode)
            .limit(1)
            .get();

        if (voucherSnapshot.docs.isEmpty) {
          setState(() {
            _isValidating = false;
            _validationMessage = '❌ Kode voucher tidak ditemukan di database.';
          });
          // Tampilkan pesan singkat lalu refresh scanner
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted) {
            setState(() {
              _validationMessage = '';
              _scanProcessed = false;
            });
          }
          return;
        }

        final voucherData = voucherSnapshot.docs.first.data();
        final voucherStatus = (voucherData['status'] as String? ?? '').toString();
        final voucherName = voucherData['name'] as String? ?? '';

        // Normalisasi status and compare to expectedStatus if provided, otherwise default to 'tersedia'
        final required = (widget.expectedStatus ?? 'tersedia').toString().toLowerCase().replaceAll('_', ' ').trim();
        final voucherStatusNorm = voucherStatus.toLowerCase().replaceAll('_', ' ').trim();
        if (voucherStatusNorm != required) {
          setState(() {
            _isValidating = false;
            _validationMessage = '⚠️ Voucher ini statusnya "$voucherStatus", bukan "$required".';
          });
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted) {
            setState(() {
              _validationMessage = '';
              _scanProcessed = false;
            });
          }
          return;
        }

        // Cek nama voucher sesuai (jika diberikan)
        if (widget.selectedVoucherName != null && voucherName != widget.selectedVoucherName) {
          setState(() {
            _isValidating = false;
            _validationMessage = '⚠️ Voucher tidak sesuai. Dipilih "${widget.selectedVoucherName}" tetapi ini "$voucherName".';
          });
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted) {
            setState(() {
              _validationMessage = '';
              _scanProcessed = false;
            });
          }
          return;
        }

        // Berhasil validasi
        setState(() {
          _isValidating = false;
          _validationMessage = '✅ Voucher valid!';
          _scanProcessed = true;
        });

        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.pop(context, upperCode);
        }
      } else if (widget.scanType == 'kupon') {
        // Cari kupon dengan kode tersebut
        final kuponSnapshot = await FirebaseFirestore.instance
            .collection('kupon')
            .where('kode', isEqualTo: upperCode)
            .limit(1)
            .get();

        if (kuponSnapshot.docs.isEmpty) {
          setState(() {
            _isValidating = false;
            _validationMessage = '❌ Kode kupon tidak ditemukan di database.';
          });
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted) {
            setState(() {
              _validationMessage = '';
              _scanProcessed = false;
            });
          }
          return;
        }

        final kuponData = kuponSnapshot.docs.first.data();
        final kuponStatus = (kuponData['status'] as String? ?? '').toString();

        // Normalisasi status and compare to expectedStatus if provided, otherwise default to 'siap pakai'
        final required = (widget.expectedStatus ?? 'siap pakai').toString().toLowerCase().replaceAll('_', ' ').trim();
        final kuponStatusNorm = kuponStatus.toLowerCase().replaceAll('_', ' ').trim();
        if (kuponStatusNorm != required) {
          setState(() {
            _isValidating = false;
            _validationMessage = '⚠️ Kupon ini statusnya "$kuponStatus", bukan "$required".';
          });
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted) {
            setState(() {
              _validationMessage = '';
              _scanProcessed = false;
            });
          }
          return;
        }

        // ✅ CHECK 1: Validasi kupon milik pelanggan ini (customer ownership)
        // Fetch data pelanggan dari textbox input
        if (widget.customerCode != null && widget.customerCode!.isNotEmpty) {
          final customerSnapshot = await FirebaseFirestore.instance
              .collection('pelanggan')
              .where('kode_pelanggan', isEqualTo: widget.customerCode!.toUpperCase())
              .limit(1)
              .get();

          if (customerSnapshot.docs.isEmpty) {
            setState(() {
              _isValidating = false;
              _validationMessage = '❌ Kode pelanggan tidak ditemukan di database.';
            });
            await Future.delayed(const Duration(milliseconds: 1500));
            if (mounted) {
              setState(() {
                _validationMessage = '';
                _scanProcessed = false;
              });
            }
            return;
          }

          final customerData = customerSnapshot.docs.first.data();
          final List<dynamic> usedCouponsDynamic = customerData['used_coupon_codes'] ?? [];
          final List<String> usedCoupons = usedCouponsDynamic.map((e) => e.toString().toUpperCase()).toList();

          // Cek apakah kupon ada di daftar used_coupon_codes pelanggan
          if (!usedCoupons.contains(upperCode)) {
            setState(() {
              _isValidating = false;
              _validationMessage = '❌ Kupon ini BUKAN MILIK PELANGGAN! Kode "$upperCode" tidak ada dalam daftar kupon milik pelanggan ${widget.customerCode}.';
            });
            await Future.delayed(const Duration(milliseconds: 2000));
            if (mounted) {
              setState(() {
                _validationMessage = '';
                _scanProcessed = false;
              });
            }
            return;
          }
        }

        // ✅ CHECK 2: Validasi tidak ada duplikasi dengan kupon lain yang sudah diinput
        if (widget.existingCouponCodes != null && widget.existingCouponCodes!.contains(upperCode)) {
          setState(() {
            _isValidating = false;
            _validationMessage = '⚠️ DUPLIKASI! Kode "$upperCode" sudah diinput di textbox lain. Setiap kupon HARUS BERBEDA.';
          });
          await Future.delayed(const Duration(milliseconds: 1500));
          if (mounted) {
            setState(() {
              _validationMessage = '';
              _scanProcessed = false;
            });
          }
          return;
        }

        // Berhasil validasi
        setState(() {
          _isValidating = false;
          _validationMessage = '✅ Kupon valid!';
          _scanProcessed = true;
        });

        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.pop(context, upperCode);
        }
      }
    } catch (e) {
      setState(() {
        _isValidating = false;
        _validationMessage = '❌ Error saat validasi: $e';
      });
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        setState(() {
          _validationMessage = '';
          _scanProcessed = false;
        });
      }
    }
  }

  void _handleBarcode(BarcodeCapture barcodes) {
    if (_scanProcessed || barcodes.barcodes.isEmpty || _isValidating) return;

    final scannedValue = barcodes.barcodes.first.rawValue;
    if (scannedValue != null && scannedValue.isNotEmpty) {
      setState(() {
        _scanProcessed = true;
      });
      _validateScannedCode(scannedValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxDialogHeight = MediaQuery.of(context).size.height * 0.85;
    final previewHeight = min(420.0, MediaQuery.of(context).size.height * 0.45);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxDialogHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header with blue gradient
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Kamera QR Scanner dengan Focus Box
              Stack(
                alignment: Alignment.center,
                children: [
                  // Camera Preview
                  Container(
                    height: previewHeight,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black,
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: MobileScanner(
                      controller: cameraController,
                      onDetect: _handleBarcode,
                      errorBuilder: (context, error, child) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 48),
                                const SizedBox(height: 12),
                                Text(
                                  'Aktifkan izin kamera untuk scan QR',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(color: Colors.grey.shade400),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),

                  // Focus Box (QR Detection Frame) - animated and locks on detection
                  // Note: keep only the corner painter (no full rectangle border) to avoid double lines
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: _scanProcessed ? 200 : 250,
                    height: _scanProcessed ? 200 : 250,
                    decoration: BoxDecoration(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CustomPaint(
                      painter: QrFocusBoxPainter(
                        color: _validationMessage.contains('✅') ? Colors.green : const Color(0xFF0B63D4),
                      ),
                    ),
                  ),

                  // Validation Message Overlay
                  if (_validationMessage.isNotEmpty)
                    Positioned(
                      bottom: 20,
                      left: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _validationMessage.contains('✅')
                              ? Colors.green.shade700
                              : _validationMessage.contains('❌')
                                  ? Colors.red.shade700
                                  : Colors.orange.shade700,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _validationMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),

                  // Loading Indicator
                  if (_isValidating)
                    Container(
                      color: Colors.black.withValues(alpha: 0.3),
                      child: const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                    ),
                ],
              ),

              // Info Text
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Arahkan QR code ke dalam kotak',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    if (widget.scanType == 'voucher')
                      Text(
                        'Scanning: Voucher (Status: tersedia)',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF0B63D4),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      )
                    else
                      Text(
                        'Scanning: Kupon (Status: siap pakai)',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF0B63D4),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),

              // Divider
              Divider(height: 1, color: Colors.grey.shade300),

              // Manual Input Tab
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Input Manual:',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _manualInputController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: 'Masukkan Kode',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        prefixIcon: const Icon(Icons.edit),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onSubmitted: (value) {
                        if (value.trim().isNotEmpty && !_isValidating) {
                          _validateScannedCode(value.trim());
                        }
                      },
                    ),
                  ],
                ),
              ),

              // Buttons
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    TextButton(
                      onPressed: _isValidating ? null : () => Navigator.pop(context),
                      child: const Text('Batal'),
                    ),
                    // Gradient Confirm button (blue)
                    Expanded(
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _isValidating
                                ? null
                                : () {
                                    final code = _manualInputController.text.trim().toUpperCase();
                                    if (code.isNotEmpty) {
                                      _validateScannedCode(code);
                                    }
                                  },
                            borderRadius: BorderRadius.circular(8),
                            child: Center(
                              child: Text('Konfirmasi', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                          ),
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
    );
  }
}

// Custom Painter untuk Focus Box
class QrFocusBoxPainter extends CustomPainter {
  final Color color;
  QrFocusBoxPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Corner length
    const cornerLen = 25.0;

    // Top-left corner
    canvas.drawLine(Offset.zero, const Offset(cornerLen, 0), paint);
    canvas.drawLine(Offset.zero, const Offset(0, cornerLen), paint);

    // Top-right corner
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width - cornerLen, 0),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, 0),
      Offset(size.width, cornerLen),
      paint,
    );

    // Bottom-left corner
    canvas.drawLine(
      Offset(0, size.height),
      Offset(cornerLen, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(0, size.height),
      Offset(0, size.height - cornerLen),
      paint,
    );

    // Bottom-right corner
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width - cornerLen, size.height),
      paint,
    );
    canvas.drawLine(
      Offset(size.width, size.height),
      Offset(size.width, size.height - cornerLen),
      paint,
    );
  }

  @override
  bool shouldRepaint(QrFocusBoxPainter oldDelegate) => false;
}

// --- Layar Penukaran Voucher ---
class PenukaranScreen extends StatefulWidget {
  const PenukaranScreen({super.key});

  @override
  State<PenukaranScreen> createState() => _PenukaranScreenState();
}

class _PenukaranScreenState extends State<PenukaranScreen> {
  final TextEditingController _customerCodeController = TextEditingController();
  final TextEditingController _voucherCodeController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  Timer? _debounce;

  Voucher? _selectedVoucherType; // Tipe voucher berdasarkan nama
  List<Voucher> _availableVouchers = []; // Daftar tipe voucher unik
  int _customerCouponCount = 0; // Jumlah kupon siap pakai pelanggan
  int _requiredCoupons = 0; // Kupon yang diperlukan untuk voucher terpilih
  List<String> _availableKuponCodes = []; // Daftar kode kupon siap pakai pelanggan

  Map<String, dynamic>? _selectedCustomer;
  List<TextEditingController> _couponControllers = [];
  String _message = '';
  bool _isLoading = true;
  bool _isCustomerLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchVouchers();
  }

  @override
  void dispose() {
    _customerCodeController.dispose();
    _voucherCodeController.dispose();
    _disposeCouponControllers();
    _debounce?.cancel();
    super.dispose();
  }

  InputDecoration _buildPenukaranInputDecoration(String label, IconData prefixIcon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(prefixIcon),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0B63D4), width: 1.4)),
      filled: true,
      fillColor: const Color(0xFFF0F5FF),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
    );
  }

  void _disposeCouponControllers() {
    for (var controller in _couponControllers) {
      controller.dispose();
    }
    _couponControllers.clear();
  }

  Future<void> _validateCustomerCode(String code) async {
    setState(() {
      _selectedCustomer = null;
      _customerCouponCount = 0;
      _isCustomerLoading = true;
      _message = '';
      _onVoucherTypeSelected(null); // Reset voucher selection
    });

    if (code.isEmpty) {
      setState(() {
        _isCustomerLoading = false;
      });
      return;
    }

    final normalizedCode = code.toUpperCase();

    try {
      final customerSnapshot = await FirebaseFirestore.instance
          .collection('pelanggan')
          .where('kode_pelanggan', isEqualTo: normalizedCode)
          .limit(1)
          .get();

      if (customerSnapshot.docs.isNotEmpty) {
        final customerData = customerSnapshot.docs.first.data();
        final List<dynamic> usedCouponsDynamic = customerData['used_coupon_codes'] ?? [];
        final List<String> usedCoupons = usedCouponsDynamic.map((e) => e.toString().toUpperCase()).toList();

        int readyToUseCount = 0;
        List<String> availableCoupons = [];

        if (usedCoupons.isNotEmpty) {
          final kuponSnapshot = await FirebaseFirestore.instance
              .collection('kupon')
              .where('kode', whereIn: usedCoupons)
              .get();

          for (var doc in kuponSnapshot.docs) {
            final data = doc.data();
            final status = (data['status'] as String? ?? '').toString().toLowerCase();
            final code = (data['kode'] as String? ?? '').toUpperCase();
            
            if (status == 'siap pakai') {
              readyToUseCount++;
              availableCoupons.add(code);
            }
          }
        }

        setState(() {
          _selectedCustomer = customerData;
          _customerCouponCount = readyToUseCount;
          _availableKuponCodes = availableCoupons;
          _isCustomerLoading = false;
        });
      } else {
        setState(() {
          _isCustomerLoading = false;
          _message = "Kode Pelanggan tidak ditemukan.";
          _customerCouponCount = 0;
        });
      }
    } catch (e) {
      setState(() {
        _isCustomerLoading = false;
        _message = "Error: Gagal validasi kode pelanggan.";
        _customerCouponCount = 0;
      });
    }
  }

  Future<void> _fetchVouchers() async {
    setState(() {
      _isLoading = true;
    });
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('vouchers')
          .where('status', isEqualTo: 'tersedia')
          .get();

      final List<Voucher> fetchedVouchers = snapshot.docs.map((doc) {
        final data = doc.data();
        return Voucher(
          id: doc.id,
          code: data['kode'] as String? ?? '',
          name: data['name'] as String? ?? 'Nama Voucher Tidak Ada',
          kuponDiperlukan: (data['kupon_diperlukan'] as num?)?.toInt() ?? 0,
          status: data['status'] as String? ?? 'unknown',
        );
      }).toList();

      final Map<String, Voucher> uniqueVouchersByName = {};

      for (final voucher in fetchedVouchers) {
        if (!uniqueVouchersByName.containsKey(voucher.name)) {
          uniqueVouchersByName[voucher.name] = voucher;
        }
      }

      _availableVouchers = uniqueVouchersByName.values.toList();
      _availableVouchers.sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      setState(() {
        _message = 'Gagal memuat data voucher. Coba lagi.';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onVoucherTypeSelected(Voucher? voucherType) {
    _disposeCouponControllers();

    setState(() {
      _selectedVoucherType = voucherType;
      _voucherCodeController.clear();
      _message = '';
    });

    if (voucherType != null) {
      _requiredCoupons = voucherType.kuponDiperlukan;

      if (_requiredCoupons > 0 && _customerCouponCount < _requiredCoupons) {
        setState(() {
          _message = '⚠️ Gagal memilih Voucher: Anda hanya memiliki $_customerCouponCount kupon siap pakai, tetapi voucher ini memerlukan $_requiredCoupons kupon.';
          _selectedVoucherType = null;
        });
        return;
      }

      for (int i = 0; i < _requiredCoupons; i++) {
        _couponControllers.add(TextEditingController());
      }
    }
  }

  Future<void> _validateVoucherCode(String code) async {
    if (code.isEmpty || _selectedVoucherType == null) return;

    setState(() {
      _message = '';
    });

    try {
      final voucherSnapshot = await FirebaseFirestore.instance
          .collection('vouchers')
          .where('kode', isEqualTo: code.toUpperCase())
          .where('status', isEqualTo: 'tersedia')
          .limit(1)
          .get();

      if (voucherSnapshot.docs.isNotEmpty) {
        final voucherData = voucherSnapshot.docs.first.data();
        final voucherName = voucherData['name'] as String? ?? '';

        if (voucherName != _selectedVoucherType!.name) {
          setState(() {
            _message = '⚠️ Voucher ini tidak sesuai. Anda memilih "${ _selectedVoucherType!.name}" tetapi kode ini untuk "$voucherName".';
          });
        } else {
          setState(() {
            _message = '✅ Kode Voucher valid.';
          });
        }
      } else {
        setState(() {
          _message = '❌ Kode Voucher tidak ditemukan atau sudah digunakan.';
        });
      }
    } catch (e) {
      setState(() {
        _message = 'Error: Gagal validasi kode voucher.';
      });
    }
  }

  Future<void> _validateKuponCode(int index, String code, List<String> availableCoupons) async {
    if (code.isEmpty) {
      setState(() {
        _message = '';
      });
      return;
    }

    final upperCode = code.trim().toUpperCase();

    // ✅ CHECK 1: Apakah kupon milik pelanggan ini (dari _availableKuponCodes)?
    if (!availableCoupons.contains(upperCode)) {
      setState(() {
        _message = '❌ Kode Kupon ke-${index + 1}: "$upperCode" BUKAN MILIK PELANGGAN atau belum "siap pakai". Gunakan kupon milik pelanggan yang statusnya "siap pakai".';
      });
      return;
    }

    // ✅ CHECK 2: Apakah ada duplikasi dengan kupon lain di textbox?
    final otherCoupons = _couponControllers.asMap().entries
        .where((entry) => entry.key != index)
        .map((entry) => entry.value.text.trim().toUpperCase())
        .where((text) => text.isNotEmpty)
        ;

    if (otherCoupons.contains(upperCode)) {
      setState(() {
        _message = '⚠️ Kode Kupon ke-${index + 1}: DUPLIKASI! Kode "$upperCode" sudah digunakan di textbox lain. Setiap kupon HARUS BERBEDA.';
      });
      return;
    }

    // ✅ Semua valid
    setState(() {
      _message = '✅ Kode Kupon ke-${index + 1}: "$upperCode" valid dan siap digunakan.';
    });
  }

  Future<void> _redeemVoucher() async {
    // ✅ VALIDATE FORM FIRST
    if (!_formKey.currentState!.validate()) {
      setState(() {
        _message = '❌ Pastikan semua field sudah diisi dengan benar dan tidak ada error.';
      });
      return;
    }

    if (_voucherCodeController.text.isEmpty || 
        _selectedCustomer == null ||
        _selectedVoucherType == null) {
      setState(() {
        _message = '❌ Pastikan semua field sudah diisi dengan benar.';
      });
      return;
    }

    // ✅ NEW: Check if already loading
    if (_isLoading) {
      return;
    }

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

    setState(() {
      _isLoading = true;
      _message = '';
    });

    final String customerCode = _customerCodeController.text.trim().toUpperCase();
    final String voucherCode = _voucherCodeController.text.trim().toUpperCase();
    final List<String> couponCodes = _couponControllers.map((c) => c.text.trim().toUpperCase()).toList();

    try {
      if (couponCodes.length != _requiredCoupons) {
        setState(() {
          _message = '❌ Gagal: Jumlah Kode Kupon yang diinput (${couponCodes.length}) tidak sesuai dengan yang disyaratkan ($_requiredCoupons).';
        });
        return;
      }

      // ✅ STEP 1: Validasi tidak ada kode kupon kosong
      final emptyIndices = <int>[];
      for (int i = 0; i < couponCodes.length; i++) {
        if (couponCodes[i].isEmpty) {
          emptyIndices.add(i);
        }
      }
      if (emptyIndices.isNotEmpty) {
        setState(() {
          _message = '❌ Kode Kupon ke-${emptyIndices.map((i) => i + 1).join(", ")} masih kosong.';
        });
        return;
      }

      // ✅ STEP 2: Validasi duplikasi kode kupon di antara textbox
      final couponSet = <String>{};
      final duplicates = <String>[];
      for (final code in couponCodes) {
        if (!couponSet.add(code)) {
          duplicates.add(code);
        }
      }
      if (duplicates.isNotEmpty) {
        setState(() {
          _message = '❌ Gagal: Ditemukan kode kupon yang duplikat: ${duplicates.join(", ")}. Setiap kupon harus berbeda.';
        });
        return;
      }

      final batch = FirebaseFirestore.instance.batch();

      // 1. Validasi dan Tandai Kupon
      if (couponCodes.isNotEmpty) {
        // Ambil data pelanggan terbaru dan cek used_coupon_codes
        final customerSnapshot = await FirebaseFirestore.instance
            .collection('pelanggan')
            .where('kode_pelanggan', isEqualTo: customerCode)
            .limit(1)
            .get();

        if (customerSnapshot.docs.isEmpty) {
          setState(() {
            _message = '❌ Kode pelanggan tidak ditemukan saat validasi kupon.';
          });
          return;
        }

        final customerData = customerSnapshot.docs.first.data();
        final List<dynamic> usedCouponsDynamic = customerData['used_coupon_codes'] ?? [];
        final List<String> usedCoupons = usedCouponsDynamic.map((e) => e.toString().toUpperCase()).toList();

        // ✅ STEP 3: Pastikan semua kode kupon yang diinput HANYA milik pelanggan ini
        final notAssociated = couponCodes.where((c) => !usedCoupons.contains(c));
        if (notAssociated.isNotEmpty) {
          setState(() {
            _message = '❌ Kode kupon BUKAN milik pelanggan ini atau belum terdaftar: ${notAssociated.join(', ')}. Hanya kupon milik pelanggan yang dapat digunakan.';
          });
          return;
        }

        // ✅ STEP 4: Ambil dokumen kupon untuk memeriksa status
        final kuponSnapshot = await FirebaseFirestore.instance
            .collection('kupon')
            .where('kode', whereIn: couponCodes)
            .get();

        // Pastikan semua kode kupon ada di koleksi kupon
        final foundKuponCodes = kuponSnapshot.docs.map((d) => (d.data()['kode'] as String? ?? '').toUpperCase()).toSet();
        final notFound = couponCodes.where((c) => !foundKuponCodes.contains(c));
        if (notFound.isNotEmpty) {
          setState(() {
            _message = '❌ Kode kupon tidak ditemukan di database: ${notFound.join(', ')}';
          });
          return;
        }

        // ✅ STEP 5: Pastikan semua kupon HANYA berstatus 'siap pakai'
        final notReady = <String>[];
        for (var doc in kuponSnapshot.docs) {
          final data = doc.data();
          final code = (data['kode'] as String? ?? '').toUpperCase();
          final status = (data['status'] as String? ?? '').toString().toLowerCase().replaceAll('_', ' ').trim();
          if (status != 'siap pakai') {
            notReady.add(code);
          }
        }

        if (notReady.isNotEmpty) {
          setState(() {
            _message = '❌ Beberapa kupon tidak siap pakai: ${notReady.join(', ')}';
          });
          return;
        }

        // Semua valid — update semua dokumen kupon menjadi 'hangus'
        for (var doc in kuponSnapshot.docs) {
          batch.update(doc.reference, {
            'status': 'hangus',
            'updatedAt': Timestamp.now(),
            'voucher_ditukar': voucherCode,
          });
        }
      }

      // 2. Tandai Voucher sebagai 'siap pakai'
      final voucherRef = FirebaseFirestore.instance.collection('vouchers').doc(voucherCode);
      batch.update(voucherRef, {
        'status': 'siap pakai',
        'tanggal_penukaran': Timestamp.now(),
        'kode_pelanggan_penukar': customerCode,
      });

      // 3. Catat Transaksi
      final transactionRef = FirebaseFirestore.instance.collection('transaksi_penukaran').doc();
      batch.set(transactionRef, {
        'kode_pelanggan': customerCode,
        'voucher_code': voucherCode,
        'voucher_name': _selectedVoucherType!.name,
        'kupon_yang_digunakan': couponCodes,
        'tanggal_penukaran': Timestamp.now(),
      });

      await batch.commit();

      setState(() {
        _message = '✅ Penukaran Voucher $voucherCode (${_selectedVoucherType!.name}) berhasil untuk pelanggan $customerCode!';
        _customerCodeController.clear();
        _selectedCustomer = null;
        _onVoucherTypeSelected(null);
        _customerCouponCount = 0;
      });
    } catch (e) {
      setState(() {
        _message = 'Terjadi kesalahan saat mencoba menukarkan voucher: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  child: Text('Penukaran Voucher', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        ),
      ),
      body: _isLoading && _availableVouchers.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Form(
                key: _formKey,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0,4))],
                  ),
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                    // Input Kode Pelanggan
                    TextFormField(
                      controller: _customerCodeController,
                      textCapitalization: TextCapitalization.characters,
                      decoration: _buildPenukaranInputDecoration('Kode Pelanggan', Icons.person).copyWith(
                        suffixIcon: _isCustomerLoading
                            ? const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
                            : _selectedCustomer != null
                                ? const Icon(Icons.check_circle, color: Colors.green)
                                : null,
                      ),
                      onChanged: (v) {
                        final code = v.trim();
                        if (_debounce?.isActive ?? false) _debounce!.cancel();
                        _debounce = Timer(const Duration(milliseconds: 700), () {
                          _validateCustomerCode(code);
                        });
                      },
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Kode Pelanggan wajib diisi.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),

                    // Detail Pelanggan
                    if (_selectedCustomer != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("✅ Pelanggan Ditemukan:", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                            Text("Nama: ${_selectedCustomer!['nama'] ?? 'N/A'}", style: const TextStyle(fontWeight: FontWeight.w500)),
                            Text("Kode: ${_customerCodeController.text.toUpperCase()}"),
                            Text("Kupon Siap Pakai: $_customerCouponCount", style: TextStyle(fontWeight: FontWeight.bold, color: _customerCouponCount > 0 ? Colors.blue : Colors.red)),
                          ],
                        ),
                      ),

                    const SizedBox(height: 10),

                    // Dropdown: Pilih Tipe Voucher
                    DropdownButtonFormField<Voucher>(
                      decoration: _buildPenukaranInputDecoration('Pilih Tipe Voucher', Icons.category),
                      value: _selectedVoucherType,
                      onChanged: _selectedCustomer != null ? _onVoucherTypeSelected : null,
                      items: _availableVouchers.map((Voucher voucher) {
                        return DropdownMenuItem<Voucher>(
                          value: voucher,
                          child: Text('${voucher.name} (${voucher.kuponDiperlukan} Kupon)'),
                        );
                      }).toList(),
                      validator: (value) {
                        if (value == null && _selectedCustomer != null) {
                          return 'Voucher wajib dipilih.';
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 20),

                    // TextBox + Scan: Kode Voucher Spesifik
                    if (_selectedVoucherType != null)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _voucherCodeController,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _buildPenukaranInputDecoration('Kode Voucher', Icons.redeem).copyWith(
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.qr_code_scanner),
                                onPressed: () async {
                                  final scannedCode = await showQrScannerDialog(
                                    context,
                                    title: 'Scan Kode Voucher',
                                    scanType: 'voucher',
                                    selectedVoucherName: _selectedVoucherType?.name,
                                  );
                                  if (scannedCode != null) {
                                    setState(() {
                                      _voucherCodeController.text = scannedCode;
                                    });
                                    _validateVoucherCode(scannedCode);
                                  }
                                },
                                tooltip: 'Scan QR Code',
                              ),
                            ),
                            onChanged: (value) {
                              if (value.isNotEmpty) {
                                _validateVoucherCode(value);
                              }
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Kode Voucher wajib diisi.';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 20),
                        ],
                      ),

                    // TextBox + Scan: Kode Kupon
                    if (_selectedVoucherType != null && _requiredCoupons > 0)
                      ..._couponControllers.asMap().entries.map((entry) {
                        int idx = entry.key;
                        TextEditingController controller = entry.value;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 15.0),
                          child: TextFormField(
                            controller: controller,
                            textCapitalization: TextCapitalization.characters,
                            decoration: _buildPenukaranInputDecoration('Kode Kupon ke-${idx + 1}', Icons.confirmation_number).copyWith(
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.qr_code_scanner),
                                onPressed: () async {
                                  // Kumpulkan kupon codes yang sudah diinput (kecuali current field)
                                  final existingCodes = _couponControllers.asMap().entries
                                      .where((entry) => entry.key != idx)
                                      .map((entry) => entry.value.text.trim().toUpperCase())
                                      .where((text) => text.isNotEmpty)
                                      ;

                                  final scannedCode = await showQrScannerDialog(
                                    context,
                                    title: 'Scan Kode Kupon ke-${idx + 1}',
                                    scanType: 'kupon',
                                    customerCode: _customerCodeController.text.trim().toUpperCase(),
                                    existingCouponCodes: existingCodes.toList(),
                                  );
                                  
                                  if (scannedCode != null) {
                                    // ✅ CHECK: Deteksi duplikasi antar textbox saat input/scan
                                    if (existingCodes.contains(scannedCode)) {
                                      showWarningDialog(
                                        context,
                                        title: '⚠️ Duplikasi Kupon!',
                                        message: 'Kode "$scannedCode" sudah diinput di textbox lain.\n\nSetiap kupon HARUS BERBEDA. Silakan gunakan kupon yang berbeda.',
                                      );
                                      return;
                                    }

                                    setState(() {
                                      controller.text = scannedCode;
                                    });
                                  }
                                },
                                tooltip: 'Scan QR Code',
                              ),
                            ),
                            onChanged: (value) {
                              if (value.isNotEmpty) {
                                // ✅ CHECK: Deteksi duplikasi saat mengetik manual
                                final otherCodes = _couponControllers.asMap().entries
                                    .where((entry) => entry.key != idx)
                                    .map((entry) => entry.value.text.trim().toUpperCase())
                                    .where((text) => text.isNotEmpty)
                                    ;

                                if (otherCodes.contains(value.trim().toUpperCase())) {
                                  showWarningDialog(
                                    context,
                                    title: '⚠️ Duplikasi Kupon!',
                                    message: 'Kode "${value.trim().toUpperCase()}" sudah diinput di textbox lain.\n\nSetiap kupon HARUS BERBEDA. Silakan gunakan kupon yang berbeda.',
                                  );
                                  controller.text = '';
                                  return;
                                }

                                _validateKuponCode(idx, value, _availableKuponCodes);
                              }
                            },
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Kode Kupon ke-${idx + 1} wajib diisi.';
                              }

                              final upperCode = value.trim().toUpperCase();

                              // ✅ CHECK 1: Apakah kupon milik pelanggan SEKARANG?
                              // (bukan dari list lama, tapi dari list yang di-fetch real-time)
                              if (!_availableKuponCodes.contains(upperCode)) {
                                return '❌ KUPON INI BUKAN MILIK PELANGGAN: Kode "$upperCode" tidak ada di daftar kupon pelanggan ATAU belum berstatus "siap pakai". Hanya gunakan kupon milik pelanggan yg statusnya siap pakai!';
                              }

                              // ✅ CHECK 2: Apakah ada duplikasi dengan kupon lain di textbox?
                              final otherCoupons = _couponControllers.asMap().entries
                                  .where((entry) => entry.key != idx)
                                  .map((entry) => entry.value.text.trim().toUpperCase())
                                  .where((text) => text.isNotEmpty)
                                  ;

                              if (otherCoupons.contains(upperCode)) {
                                return '⚠️ DUPLIKASI: Kode "$upperCode" sudah digunakan di textbox lain. SETIAP KUPON HARUS BERBEDA!';
                              }

                              return null;
                            },
                          ),
                        );
                      }),

                    // Pesan untuk Voucher tanpa Kupon
                    if (_selectedVoucherType != null && _requiredCoupons == 0)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.lightGreen.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.lightGreen)),
                        child: const Text(
                          'Voucher ini tidak memerlukan kupon untuk ditukarkan. Klik Tukarkan.',
                          style: TextStyle(color: Colors.lightGreen, fontWeight: FontWeight.w600),
                        ),
                      ),

                    const SizedBox(height: 30),

                    // Tombol Tukarkan
                    Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: (_isLoading || _selectedCustomer == null || _voucherCodeController.text.isEmpty) ? null : _redeemVoucher,
                          borderRadius: BorderRadius.circular(10),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: _isLoading
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation(Colors.white)),
                                  )
                                : const Text(
                                    'Tukarkan Voucher',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Pesan Status
                    if (_message.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _message.startsWith('✅') ? Colors.green.shade50 : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: _message.startsWith('✅') ? Colors.green : Colors.red),
                        ),
                        child: Text(
                          _message,
                          style: TextStyle(
                              color: _message.startsWith('✅') ? Colors.green.shade800 : Colors.red.shade800,
                              fontWeight: FontWeight.w500),
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







