import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_picker/image_picker.dart';
import 'package:barcode_widget/barcode_widget.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/connectivity_service.dart';
import '../widgets/animated_dialog.dart';

class KelolaVoucherScreen extends StatefulWidget {
  const KelolaVoucherScreen({super.key});

  @override
  State<KelolaVoucherScreen> createState() => _KelolaVoucherScreenState();
}

class _KelolaVoucherScreenState extends State<KelolaVoucherScreen> {
  final CollectionReference _voucherRef =
      FirebaseFirestore.instance.collection('vouchers');
  
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _discountPercentController = TextEditingController();
  final TextEditingController _maxDiscountController = TextEditingController();
  final TextEditingController _kuponDiperlukanController = TextEditingController();

  File? _templateImage;
  bool _isLoading = false;
  final ImagePicker _imagePicker = ImagePicker();
  final List<String> _generatedVouchers = [];
  
  // Key to capture the preview as an image for WYSIWYG PDF
  final GlobalKey _previewRepaintKey = GlobalKey();
  // When generating PDF we temporarily force the preview to show a specific code
  String? _previewForcedCode;
  
  // Posisi barcode untuk preview (dalam percentage dari ujung kiri dan atas)
  double _barcodeOffsetX = 0.85;
  double _barcodeOffsetY = 0.05;
  
  // Ukuran container barcode di preview UI
  static const double _previewBarWidth = 50;
  static const double _previewBarHeight = 50;
  
  // Aspek rasio gambar template (diupdate saat gambar dipilih)
  double _templateAspectRatio = 10 / 4.5; // Default: 10cm x 4.5cm ratio
  
  // Flag untuk tracking status
  bool _barcodePositionFixed = false;
  
  // Hash template untuk menyimpan posisi per template
  String? _currentTemplateHash;

  // Helper modern gradient button (reused here)
  Widget _buildGradientButton({required String label, required Gradient gradient, VoidCallback? onPressed, Widget? icon}) {
    return Opacity(
      opacity: onPressed == null ? 0.6 : 1.0,
      child: Container(
        decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(10)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[icon, const SizedBox(width: 10)],
                  Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Search state
  final TextEditingController _searchController = TextEditingController();

  Future<String> _getTemplateHash(File imageFile) async {
    // Gunakan hanya path file sebagai hash untuk konsistensi
    // (tidak tergantung pada timestamp yang bisa berubah)
    final path = imageFile.path;
    return path.hashCode.toString().replaceAll('-', ''); // Hapus minus sign
  }

  // Modern input decoration for borderless fields with focus outline and light blue background
  InputDecoration _modernInputDecoration(String hint) {
    return InputDecoration(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF0B63D4), width: 1.4)),
      fillColor: const Color(0xFFF0F5FF),
      filled: true,
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
    );
  }

  String _generateRandomCode(int length) {
    const letters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    const numbers = '0123456789';
    final random = Random.secure();

    if (length < 2) {
      return letters[random.nextInt(letters.length)] + 
             numbers[random.nextInt(numbers.length)];
    }

    List<String> code = [
      letters[random.nextInt(letters.length)],
      numbers[random.nextInt(numbers.length)],
    ];

    const allChars = letters + numbers;
    for (int i = 2; i < length; i++) {
      code.add(allChars[random.nextInt(allChars.length)]);
    }

    code.shuffle(random);
    return code.join();
  }

  Future<void> _pickTemplateImage() async {
    final XFile? pickedFile = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (pickedFile != null) {
      final File imageFile = File(pickedFile.path);
      // Get image dimensions untuk aspect ratio
      final Image img = Image.file(imageFile);
      final Completer<double> completer = Completer();
      
        img.image.resolve(const ImageConfiguration()).addListener(
        ImageStreamListener((ImageInfo info, bool synchronousCall) {
          final double aspectRatio = info.image.width / info.image.height;
          if (!completer.isCompleted) {
            completer.complete(aspectRatio);
          }
        }),
      );
      
      try {
        final double aspectRatio = await completer.future.timeout(
          const Duration(seconds: 5),
          onTimeout: () => 10 / 4.5, // Default ratio jika timeout
        );
        
        // Generate hash untuk template ini
        final templateHash = await _getTemplateHash(imageFile);
        
        // Cek apakah ada posisi tersimpan untuk template ini
        double savedOffsetX = 0.85;
        double savedOffsetY = 0.05;
        bool hasSavedPosition = false;
        try {
          final prefs = await SharedPreferences.getInstance();
          final savedX = prefs.getDouble('qr_offset_x_$templateHash');
          final savedY = prefs.getDouble('qr_offset_y_$templateHash');
          
          if (savedX != null && savedY != null) {
            savedOffsetX = savedX;
            savedOffsetY = savedY;
            hasSavedPosition = true;
          }
        } catch (e) {
          // Error silently handled
        }
        
        setState(() {
          _templateImage = imageFile;
          _templateAspectRatio = aspectRatio;
          _currentTemplateHash = templateHash;
          _barcodeOffsetX = savedOffsetX;
          _barcodeOffsetY = savedOffsetY;
          _barcodePositionFixed = hasSavedPosition;
        });
        
        if (hasSavedPosition && mounted) {
          showSuccessDialog(context, title: 'Berhasil', message: 'Posisi barcode dimuat dari penyimpanan');
        }
      } catch (e) {
        final templateHash = await _getTemplateHash(imageFile);
        setState(() {
          _templateImage = imageFile;
          _templateAspectRatio = 10 / 4.5;
          _currentTemplateHash = templateHash;
          _barcodeOffsetX = 0.85;
          _barcodeOffsetY = 0.05;
          _barcodePositionFixed = false;
        });
      }
    }
  }

  Widget _buildVoucherPreview(String voucherCode) {
    if (_templateImage == null) {
      return Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 220, maxHeight: 360),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        padding: const EdgeInsets.all(20),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.photo_library_outlined, size: 40, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                'Pilih gambar template terlebih dahulu',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[700], fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    final displayCode = _previewForcedCode ?? 
      (_generatedVouchers.isNotEmpty ? _generatedVouchers.first : _generateRandomCode(7).toUpperCase());

    return RepaintBoundary(
      key: _previewRepaintKey,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        clipBehavior: Clip.hardEdge,
        child: AspectRatio(
          aspectRatio: _templateAspectRatio,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final maxWidth = constraints.maxWidth;
              final maxHeight = constraints.maxHeight;

              final barLeft = (_barcodeOffsetX * maxWidth) - (_previewBarWidth / 2);
              final barTop = (_barcodeOffsetY * maxHeight) - (_previewBarHeight / 2);

              return Stack(
                children: [
                  // Template image as background
                  Positioned.fill(
                    child: Container(
                      color: Colors.grey.shade50,
                      child: Center(
                        child: Image.file(
                          _templateImage!,
                          fit: BoxFit.contain,
                          width: maxWidth,
                          height: maxHeight,
                        ),
                      ),
                    ),
                  ),

                  // Draggable QR container
                  Positioned(
                    left: barLeft,
                    top: barTop,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.move,
                      child: GestureDetector(
                        onPanUpdate: (details) {
                          setState(() {
                            final currentCenterX = _barcodeOffsetX * maxWidth;
                            final currentCenterY = _barcodeOffsetY * maxHeight;

                            double newCenterX = currentCenterX + details.delta.dx;
                            double newCenterY = currentCenterY + details.delta.dy;

                            final double minCenterX = _previewBarWidth / 2;
                            final double maxCenterX = maxWidth - (_previewBarWidth / 2);
                            final double minCenterY = _previewBarHeight / 2;
                            final double maxCenterY = maxHeight - (_previewBarHeight / 2);

                            newCenterX = newCenterX.clamp(minCenterX, maxCenterX);
                            newCenterY = newCenterY.clamp(minCenterY, maxCenterY);

                            _barcodeOffsetX = (newCenterX / maxWidth);
                            _barcodeOffsetY = (newCenterY / maxHeight);

                            _barcodePositionFixed = false;
                          });
                        },
                        child: Container(
                          width: _previewBarWidth,
                          height: _previewBarHeight,
                          decoration: BoxDecoration(
                            color: Colors.white,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: _previewBarWidth * 0.78,
                                height: _previewBarHeight * 0.56,
                                child: BarcodeWidget(
                                  data: displayCode,
                                  barcode: Barcode.qrCode(),
                                  color: Colors.black,
                                  drawText: false,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                displayCode,
                                style: const TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Future<Uint8List?> _capturePreviewAsPng({double pixelRatio = 3.0}) async {
    try {
      final boundary = _previewRepaintKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return null;
      final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<void> _fixBarcodePosition() async {
    if (_templateImage == null) {
      showWarningDialog(
        context,
        title: 'Perhatian',
        message: 'Pilih gambar template terlebih dahulu',
      );
      return;
    }

    // Simpan posisi ke SharedPreferences
    try {
      if (_currentTemplateHash != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('qr_offset_x_$_currentTemplateHash', _barcodeOffsetX);
        await prefs.setDouble('qr_offset_y_$_currentTemplateHash', _barcodeOffsetY);
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          title: 'Gagal',
          message: 'Error menyimpan posisi: $e',
        );
      }
      return;
    }

    setState(() {
      _barcodePositionFixed = true;
    });

    if (mounted) {
      showSuccessDialog(
        context,
        title: 'Berhasil',
        message: 'Posisi barcode berhasil di-fix dan disimpan! Siap generate PDF.',
      );
    }
  }

  Future<void> _generateVoucher() async {
    final name = _nameController.text.trim();
    final discountPercent = int.tryParse(_discountPercentController.text.trim()) ?? 0;
    final maxDiscount = int.tryParse(_maxDiscountController.text.trim()) ?? 0;
    final kuponDiperlukan = int.tryParse(_kuponDiperlukanController.text.trim()) ?? 0;

    if (name.isEmpty || discountPercent <= 0 || maxDiscount <= 0 || kuponDiperlukan < 0) {
      showWarningDialog(
        context,
        title: 'Perhatian',
        message: 'Isi nama, potongan %, maksimal diskon, dan jumlah kupon diperlukan dengan benar',
      );
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

    setState(() => _isLoading = true);

    try {
      _generatedVouchers.clear();

      const int targetCount = 10;
      const int maxAttemptsPerCode = 50;

      for (int i = 0; i < targetCount; i++) {
        int attempts = 0;
        bool created = false;

        while (!created && attempts < maxAttemptsPerCode) {
          final code = _generateRandomCode(7).toUpperCase();
          final docRef = _voucherRef.doc(code);

          try {
            await FirebaseFirestore.instance.runTransaction((tx) async {
              final snapshot = await tx.get(docRef);
              if (snapshot.exists) {
                throw Exception('exists');
              }
              tx.set(docRef, {
                'name': name,
                'kode': code,
                'status': 'tersedia',
                'discount_percent': discountPercent,
                'max_discount': maxDiscount,
                'kupon_diperlukan': kuponDiperlukan,
                'createdAt': FieldValue.serverTimestamp(),
              });
            });

            _generatedVouchers.add(code);
            created = true;
          } catch (e) {
            attempts++;
            if (attempts >= maxAttemptsPerCode) {
              throw Exception('Gagal menghasilkan kode unik setelah $maxAttemptsPerCode percobaan. Error: $e');
            }
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      }

      final pdfBytes = await _generatePdf();
      _showPdfPreviewWithBytes(pdfBytes);
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          title: 'Gagal Membuat Voucher',
          message: 'Error saat menyimpan voucher: $e',
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadPdf(Uint8List pdfBytes) async {
    try {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unduh PDF'),
          content: const Text('Unduh PDF voucher sekarang?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Unduh Sekarang'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        final fileName = 'voucher_${DateTime.now().millisecondsSinceEpoch}.pdf';
        
        final Directory? downloadsDir = await _getDownloadsDirectory();
        
        if (downloadsDir != null) {
          final String filePath = '${downloadsDir.path}/$fileName';
          final File file = File(filePath);
          await file.writeAsBytes(pdfBytes);
          
          if (mounted) {
            showSuccessDialog(
              context,
              title: 'Berhasil',
              message: 'PDF tersimpan: $filePath',
            );
          }
        } else {
          if (mounted) {
            showErrorDialog(
              context,
              title: 'Gagal',
              message: 'Tidak dapat mengakses folder Download',
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          title: 'Error',
          message: 'Error: $e',
        );
      }
    }
  }

  Future<void> _savePdfAutomatically(Uint8List pdfBytes) async {
    try {
      final fileName = 'voucher_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final Directory? downloadsDir = await _getDownloadsDirectory();
      if (downloadsDir != null) {
        final String filePath = '${downloadsDir.path}/$fileName';
        final File file = File(filePath);
        await file.writeAsBytes(pdfBytes);
        if (mounted) {
          showSuccessDialog(
            context,
            title: 'Berhasil',
            message: 'PDF otomatis tersimpan: $filePath',
          );
        }
      } else {
        if (mounted) {
          showErrorDialog(
            context,
            title: 'Gagal',
            message: 'Tidak dapat mengakses folder Download untuk auto-save',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          title: 'Error',
          message: 'Error saat auto-save PDF: $e',
        );
      }
    }
  }

  Future<Directory?> _getDownloadsDirectory() async {
    try {
      if (Theme.of(context).platform == TargetPlatform.android) {
        final Directory appDir = await _getApplicationDocumentsDirectory();
        final String androidDownloadPath = appDir.path.replaceFirst('/documents', '/downloads');
        return Directory(androidDownloadPath);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _getApplicationDocumentsDirectory() async {
    return Directory('/storage/emulated/0/Documents');
  }

  void _showPdfPreviewWithBytes(Uint8List pdfBytes) {
    _savePdfAutomatically(pdfBytes);
    showDialog(
      context: context,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(10),
        child: SizedBox(
          width: double.maxFinite,
          height: double.maxFinite,
          child: Column(
            children: [
              AppBar(
                title: const Text('Preview PDF - 10 Voucher'),
                automaticallyImplyLeading: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.print),
                    tooltip: 'Print PDF',
                    onPressed: () async {
                      await Printing.sharePdf(
                        bytes: pdfBytes,
                        filename: 'voucher_${DateTime.now().millisecondsSinceEpoch}.pdf',
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.download),
                    tooltip: 'Unduh PDF',
                    onPressed: () => _downloadPdf(pdfBytes),
                  ),
                ],
              ),
              Expanded(
                child: PdfPreview(
                  build: (format) => Future.value(pdfBytes),
                  previewPageMargin: EdgeInsets.zero,
                  allowSharing: false,
                  allowPrinting: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _generatePdf() async {
    final pdf = pw.Document();

    final List<Uint8List> capturedImages = [];
    for (final code in _generatedVouchers) {
      setState(() => _previewForcedCode = code);
      await Future.delayed(const Duration(milliseconds: 150));
      final bytes = await _capturePreviewAsPng(pixelRatio: 3.0);
      if (bytes == null) {
        if (mounted) {
          showErrorDialog(
            context,
            title: 'Gagal',
            message: 'Gagal capture preview untuk satu voucher',
          );
        }
        setState(() => _previewForcedCode = null);
        return Uint8List(0);
      }
      capturedImages.add(bytes);
    }
    setState(() => _previewForcedCode = null);

    const double dpi300ToPoints = 72.0 / 300.0;
    const double imageWidthPx = 1181;
    const double imageHeightPx = 532;
    const double spacingPx = 1;
    
    final couponWidth = imageWidthPx * dpi300ToPoints;
    final couponHeight = imageHeightPx * dpi300ToPoints;
    final spacingPoints = spacingPx * dpi300ToPoints;

    const double a4Width = 2480 * dpi300ToPoints;
    const double a4Height = 3508 * dpi300ToPoints;
    
    const double marginLeftRight = 0.0;
    const double marginTopBottom = 0.0;

    final contentWidth = a4Width - (2 * marginLeftRight);
    final contentHeight = a4Height - (2 * marginTopBottom);

    final totalWidthNeeded = (couponWidth * 2) + spacingPoints;
    final totalHeightNeeded = (couponHeight * 5) + (spacingPoints * 4);

    final scaleX = contentWidth / totalWidthNeeded;
    final scaleY = contentHeight / totalHeightNeeded;
    final scale = min(scaleX, scaleY);
    final bool needsScalingDown = scale < 1.0;
    final double finalScale = needsScalingDown ? scale : 1.0;

    final scaledCouponWidth = couponWidth * finalScale;
    final scaledCouponHeight = couponHeight * finalScale;
    final scaledSpacing = spacingPoints * finalScale;

    final scaledTotalWidth = (scaledCouponWidth * 2) + scaledSpacing;
    final scaledTotalHeight = (scaledCouponHeight * 5) + (scaledSpacing * 4);

    final startLeftX = marginLeftRight + (contentWidth - scaledTotalWidth) / 2;
    final startTopY = marginTopBottom + (contentHeight - scaledTotalHeight) / 2;

    if (needsScalingDown && mounted) {
      showWarningDialog(
        context,
        title: 'Info',
        message: 'Ukuran voucher diskalakan sedikit agar muat di A4.',
      );
    }

    List<pw.Widget> pageElements = [];
    for (int i = 0; i < capturedImages.length; i++) {
      final col = i % 2;
      final row = i ~/ 2;
      final left = startLeftX + col * scaledCouponWidth + (col > 0 ? scaledSpacing : 0);
      final top = startTopY + row * scaledCouponHeight + (row > 0 ? scaledSpacing * row : 0);

      final pwImage = pw.MemoryImage(capturedImages[i]);
      pageElements.add(
        pw.Positioned(
          left: left,
          top: top,
          child: pw.Container(
            width: scaledCouponWidth,
            height: scaledCouponHeight,
            child: pw.Image(pwImage, fit: pw.BoxFit.contain),
          ),
        ),
      );
    }

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(a4Width, a4Height),
        margin: pw.EdgeInsets.zero,
        build: (context) => pw.SizedBox.expand(
          child: pw.Stack(children: pageElements),
        ),
      ),
    );

    return pdf.save();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _discountPercentController.dispose();
    _maxDiscountController.dispose();
    _kuponDiperlukanController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(150),
        child: Container(
          padding: const EdgeInsets.only(top: 26, left: 16, right: 16, bottom: 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Kelola Voucher', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      tooltip: 'Bantuan',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Petunjuk Singkat'),
                            content: const Text('Pilih template gambar, atur posisi barcode lalu tekan "Fix Posisi". Isi nama, potongan %, dan maksimal diskon. Setelah itu tekan "Generate 10 Voucher & Preview PDF" untuk menyimpan dan melihat PDF.'),
                            actions: [
                              TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Tutup')),
                            ],
                          ),
                        );
                      },
                      icon: const Icon(Icons.help_outline, color: Colors.white),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Cari voucher berdasarkan nama / kode ...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool wide = constraints.maxWidth > 900;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight - 40),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Left: Preview area
                        Expanded(
                          flex: 2,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text('Preview Voucher', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 12),
                              StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance.collection('vouchers').snapshots(),
                                builder: (context, snapshot) {
                                  final q = _searchController.text.trim().toLowerCase();
                                  if (!snapshot.hasData) {
                                    return _buildVoucherPreview(_generatedVouchers.isNotEmpty ? _generatedVouchers.first : _generateRandomCode(7).toUpperCase());
                                  }
                                  final docs = snapshot.data!.docs.where((d) {
                                    if (q.isEmpty) return false;
                                    final data = d.data() as Map<String, dynamic>?;
                                    final name = (data?['name'] ?? data?['nama'] ?? '').toString().toLowerCase();
                                    final code = (data?['kode'] ?? data?['code'] ?? '').toString().toLowerCase();
                                    return name.contains(q) || code.contains(q);
                                  });
                                  if (q.isNotEmpty && docs.isNotEmpty) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        ...docs.map((d) {
                                          final data = d.data() as Map<String, dynamic>?;
                                          final title = (data?['name'] ?? data?['nama'] ?? '').toString();
                                          final code = (data?['kode'] ?? data?['code'] ?? '').toString();
                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 8),
                                            child: Card(
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              child: ListTile(
                                                title: Text(title),
                                                subtitle: Text('Kode: $code'),
                                              ),
                                            ),
                                          );
                                        }),
                                        const SizedBox(height: 12),
                                      ],
                                    );
                                  }
                                  return _buildVoucherPreview(_generatedVouchers.isNotEmpty ? _generatedVouchers.first : _generateRandomCode(7).toUpperCase());
                                },
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildGradientButton(
                                      label: 'Pilih Template',
                                      gradient: const LinearGradient(colors: [Color(0xFFF2994A), Color(0xFFFBAC66)]),
                                      onPressed: _pickTemplateImage,
                                      icon: const Icon(Icons.image, color: Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    height: 48,
                                    child: _buildGradientButton(
                                      label: _barcodePositionFixed ? 'Posisi Fixed' : 'Fix Posisi',
                                      gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                                      onPressed: _isLoading ? null : _fixBarcodePosition,
                                      icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0,3))]),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: (_isLoading || !_barcodePositionFixed || _templateImage == null) ? null : _generateVoucher,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.star, color: Color(0xFFFFC107)),
                                          const SizedBox(width: 10),
                                          Text('Generate 10 Voucher & Preview PDF', style: TextStyle(color: (_isLoading || !_barcodePositionFixed || _templateImage == null) ? Colors.grey[500] : Colors.black, fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 24),

                        // Right: Controls & info
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // Modern white box for configuration (text fields without borders)
                              Container(
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0,4))]),
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Konfigurasi Voucher', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 12),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(color: const Color(0xFFF0F5FF), borderRadius: BorderRadius.circular(8)),
                                      child: TextField(
                                        controller: _nameController,
                                        decoration: _modernInputDecoration('Nama Voucher'),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(color: const Color(0xFFF0F5FF), borderRadius: BorderRadius.circular(8)),
                                      child: TextField(
                                        controller: _discountPercentController,
                                        keyboardType: TextInputType.number,
                                        decoration: _modernInputDecoration('Potongan (%)'),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(color: const Color(0xFFF0F5FF), borderRadius: BorderRadius.circular(8)),
                                      child: TextField(
                                        controller: _maxDiscountController,
                                        keyboardType: TextInputType.number,
                                        decoration: _modernInputDecoration('Maksimal Diskon (Rp)'),
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(color: const Color(0xFFF0F5FF), borderRadius: BorderRadius.circular(8)),
                                      child: TextField(
                                        controller: _kuponDiperlukanController,
                                        keyboardType: TextInputType.number,
                                        decoration: _modernInputDecoration('Jumlah Kupon Diperlukan'),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 12),
                            ],
                          ),
                        ),
                      ],
                    )
                  : // Narrow layout
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Preview Voucher', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('vouchers').snapshots(),
                          builder: (context, snapshot) {
                            final q = _searchController.text.trim().toLowerCase();
                            if (!snapshot.hasData) {
                              return _buildVoucherPreview(_generatedVouchers.isNotEmpty ? _generatedVouchers.first : _generateRandomCode(7).toUpperCase());
                            }
                            final docs = snapshot.data!.docs.where((d) {
                              if (q.isEmpty) return false;
                              final data = d.data() as Map<String, dynamic>?;
                              final name = (data?['name'] ?? data?['nama'] ?? '').toString().toLowerCase();
                              final code = (data?['kode'] ?? data?['code'] ?? '').toString().toLowerCase();
                              return name.contains(q) || code.contains(q);
                            });
                            if (q.isNotEmpty && docs.isNotEmpty) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ...docs.map((d) {
                                    final data = d.data() as Map<String, dynamic>?;
                                    final title = (data?['name'] ?? data?['nama'] ?? '').toString();
                                    final code = (data?['kode'] ?? data?['code'] ?? '').toString();
                                    final status = (data?['status'] ?? 'unknown').toString();
                                    final discount = (data?['discount_percent'] ?? 0).toString();
                                    final statusColor = status == 'tersedia' ? Colors.green : (status == 'siap pakai' ? Colors.blue : Colors.orange);
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: Card(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        elevation: 1,
                                        child: ListTile(
                                          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                          subtitle: Text('Kode: $code | Diskon: $discount%'),
                                          trailing: Chip(
                                            label: Text(status, style: const TextStyle(fontSize: 12, color: Colors.white)),
                                            backgroundColor: statusColor,
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                  const SizedBox(height: 12),
                                ],
                              );
                            }
                            return _buildVoucherPreview(_generatedVouchers.isNotEmpty ? _generatedVouchers.first : _generateRandomCode(7).toUpperCase());
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildGradientButton(
                          label: 'Pilih Template',
                          gradient: const LinearGradient(colors: [Color(0xFFF2994A), Color(0xFFFBAC66)]),
                          onPressed: _pickTemplateImage,
                          icon: const Icon(Icons.image, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        _buildGradientButton(
                          label: _barcodePositionFixed ? 'Posisi Fixed' : 'Fix Posisi',
                          gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                          onPressed: _isLoading ? null : _fixBarcodePosition,
                          icon: const Icon(Icons.check_circle_outline, color: Colors.white),
                        ),
                        const SizedBox(height: 12),
                        // Modern white box for configuration (borderless inputs)
                        Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0,4))]),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Konfigurasi Voucher', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 10),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), child: TextField(controller: _nameController, decoration: const InputDecoration(border: InputBorder.none, hintText: 'Nama Voucher', isDense: true))),
                              const SizedBox(height: 10),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), child: TextField(controller: _discountPercentController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: InputBorder.none, hintText: 'Potongan (%)', isDense: true))),
                              const SizedBox(height: 10),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), child: TextField(controller: _maxDiscountController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: InputBorder.none, hintText: 'Maksimal Diskon (Rp)', isDense: true))),
                              const SizedBox(height: 10),
                              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)), child: TextField(controller: _kuponDiperlukanController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: InputBorder.none, hintText: 'Jumlah Kupon Diperlukan', isDense: true))),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0,3))]),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: (_isLoading || !_barcodePositionFixed || _templateImage == null) ? null : _generateVoucher,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.star, color: Color(0xFFFFC107)),
                                    const SizedBox(width: 10),
                                    Text('Generate 10 Voucher & Preview PDF', style: TextStyle(color: (_isLoading || !_barcodePositionFixed || _templateImage == null) ? Colors.grey[500] : Colors.black, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
          );
        },
      ),
    );
  }
}


