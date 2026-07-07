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

class KelolaKuponScreen extends StatefulWidget {
  const KelolaKuponScreen({super.key});

  @override
  State<KelolaKuponScreen> createState() => _KelolaKuponScreenState();
}

class _KelolaKuponScreenState extends State<KelolaKuponScreen> {
  final CollectionReference _kuponRef =
      FirebaseFirestore.instance.collection('kupon');
  
  File? _templateImage;
  bool _isLoading = false;
  final ImagePicker _imagePicker = ImagePicker();
  final List<String> _generatedCoupons = [];
  
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

  // Helper modern gradient button
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

  // Search state for kupon
  final TextEditingController _searchControllerKupon = TextEditingController();

  Future<String> _getTemplateHash(File imageFile) async {
    // Gunakan hanya path file sebagai hash untuk konsistensi
    // (tidak tergantung pada timestamp yang bisa berubah)
    final path = imageFile.path;
    return path.hashCode.toString().replaceAll('-', ''); // Hapus minus sign
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

  Widget _buildCouponPreview(String couponCode) {
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
      (_generatedCoupons.isNotEmpty ? _generatedCoupons.first : _generateRandomCode(7).toUpperCase());

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

                  // (Overlay label removed per UI request)

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

  Future<void> _generateKupon() async {
    if (_templateImage == null || !_barcodePositionFixed) {
      showWarningDialog(
        context,
        title: 'Perhatian',
        message: 'Pilih gambar template dan klik "Fix Posisi" terlebih dahulu',
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
      _generatedCoupons.clear();

      const int targetCount = 10;
      const int maxAttemptsPerCode = 50;

      for (int i = 0; i < targetCount; i++) {
        int attempts = 0;
        bool created = false;

        while (!created && attempts < maxAttemptsPerCode) {
          final code = _generateRandomCode(7).toUpperCase();
          final docRef = _kuponRef.doc(code); // use code as document ID for atomic uniqueness

          try {
            await FirebaseFirestore.instance.runTransaction((tx) async {
              final snapshot = await tx.get(docRef);
              if (snapshot.exists) {
                // Let the transaction throw to indicate this code is taken
                throw Exception('exists');
              }
              tx.set(docRef, {
                'kode': code,
                'status': 'tersedia',
                'createdAt': FieldValue.serverTimestamp(),
              });
            });

            // If transaction succeeded, we created the document atomically
            _generatedCoupons.add(code);
            created = true;
          } catch (e) {
            // If it failed because the doc exists, just retry with a new code.
            // For other errors (network, permission), we increment attempts and retry conservatively.
            attempts++;
            if (attempts >= maxAttemptsPerCode) {
              throw Exception('Gagal menghasilkan kode unik setelah $maxAttemptsPerCode percobaan. Error: $e');
            }
            // small delay to avoid tight loop in rare contention cases
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
          title: 'Gagal Membuat Kupon',
          message: 'Error saat menyimpan kupon: $e',
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }



  Future<void> _downloadPdf(Uint8List pdfBytes) async {
    try {
      // Show download confirmation dialog
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unduh PDF'),
          content: const Text('Unduh PDF kupon sekarang?'),
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
        final fileName = 'kupon_${DateTime.now().millisecondsSinceEpoch}.pdf';
        
        // Try to save to Downloads folder using path_provider
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

  // Save PDF automatically without confirmation (used when preview opens)
  Future<void> _savePdfAutomatically(Uint8List pdfBytes) async {
    try {
      final fileName = 'kupon_${DateTime.now().millisecondsSinceEpoch}.pdf';
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
      // For Android, use getExternalStorageDirectory() + /Download
      if (Theme.of(context).platform == TargetPlatform.android) {
        // Note: This requires android.permission.WRITE_EXTERNAL_STORAGE
        // You can use path_provider_android or manually handle the path
        final Directory appDir = await _getApplicationDocumentsDirectory();
        final String androidDownloadPath = appDir.path.replaceFirst('/documents', '/downloads');
        return Directory(androidDownloadPath);
      }
      // For other platforms, fallback
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<Directory> _getApplicationDocumentsDirectory() async {
    // This is a placeholder; you'd use path_provider in real code
    // For now, return a default Documents directory simulation
    return Directory('/storage/emulated/0/Documents');
  }

  void _showPdfPreviewWithBytes(Uint8List pdfBytes) {
    // Auto-save PDF to Downloads when preview opens
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
                title: const Text('Preview PDF - 10 Kupon'),
                automaticallyImplyLeading: true,
                actions: [
                  IconButton(
                    icon: const Icon(Icons.print),
                    tooltip: 'Print PDF',
                    onPressed: () async {
                      await Printing.sharePdf(
                        bytes: pdfBytes,
                        filename: 'kupon_${DateTime.now().millisecondsSinceEpoch}.pdf',
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

    // Capture PNG images untuk setiap kupon
    final List<Uint8List> capturedImages = [];
    for (final code in _generatedCoupons) {
      setState(() => _previewForcedCode = code);
      await Future.delayed(const Duration(milliseconds: 150));
      final bytes = await _capturePreviewAsPng(pixelRatio: 3.0);
      if (bytes == null) {
        if (mounted) {
          showErrorDialog(
            context,
            title: 'Gagal',
            message: 'Gagal capture preview untuk satu kupon',
          );
        }
        setState(() => _previewForcedCode = null);
        return Uint8List(0);
      }
      capturedImages.add(bytes);
    }
    setState(() => _previewForcedCode = null);

    // PDF generation using 300 DPI for sharp printing
    // Image size: 1181px x 532px @ 300 DPI
    // A4 paper: 2480px x 3508px @ 300 DPI
    // Spacing: 1px between images (all directions) = ~0.085mm, nearly touching
    
    const double dpi300ToPoints = 72.0 / 300.0; // 0.24 points per px at 300 DPI
    const double imageWidthPx = 1181;
    const double imageHeightPx = 532;
    const double spacingPx = 1; // Changed from 2 to 1 for tighter spacing
    
    final couponWidth = imageWidthPx * dpi300ToPoints;   // ~283.44 points
    final couponHeight = imageHeightPx * dpi300ToPoints;  // ~127.68 points
    final spacingPoints = spacingPx * dpi300ToPoints;     // ~0.24 points

    // A4 at 300 DPI: 2480px x 3508px = 595.2 x 842.4 points
    const double a4Width = 2480 * dpi300ToPoints;   // ~595.2 points
    const double a4Height = 3508 * dpi300ToPoints;  // ~842.4 points
    
    // No margins (user request)
    const double marginLeftRight = 0.0;
    const double marginTopBottom = 0.0;

    final contentWidth = a4Width - (2 * marginLeftRight);
    final contentHeight = a4Height - (2 * marginTopBottom);

    // Layout: 2 kolom x 5 baris = 10 kupon
    // Total width: 2 images + 1 spacing gap between them
    // Total height: 5 images + 4 spacing gaps between them
    final totalWidthNeeded = (couponWidth * 2) + spacingPoints;
    final totalHeightNeeded = (couponHeight * 5) + (spacingPoints * 4);

    // Center grid in content area
    final scaleX = contentWidth / totalWidthNeeded;
    final scaleY = contentHeight / totalHeightNeeded;
    final scale = min(scaleX, scaleY);
    final bool needsScalingDown = scale < 1.0;
    final double finalScale = needsScalingDown ? scale : 1.0;

    final scaledCouponWidth = couponWidth * finalScale;
    final scaledCouponHeight = couponHeight * finalScale;
    final scaledSpacing = spacingPoints * finalScale;

    // Calculate actual total size after scaling
    final scaledTotalWidth = (scaledCouponWidth * 2) + scaledSpacing;
    final scaledTotalHeight = (scaledCouponHeight * 5) + (scaledSpacing * 4);

    // Center in available content area
    final startLeftX = marginLeftRight + (contentWidth - scaledTotalWidth) / 2;
    final startTopY = marginTopBottom + (contentHeight - scaledTotalHeight) / 2;

    if (needsScalingDown && mounted) {
      showWarningDialog(
        context,
        title: 'Info',
        message: 'Ukuran kupon diskalakan sedikit agar muat di A4.',
      );
    }

    List<pw.Widget> pageElements = [];
    for (int i = 0; i < capturedImages.length; i++) {
      final col = i % 2;
      final row = i ~/ 2;
      // Position: each image with spacing between them (not including spacing in position multiplication)
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
        pageFormat: const PdfPageFormat(a4Width, a4Height),
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
    _searchControllerKupon.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
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
                      child: Text('Kelola Kupon', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      tooltip: 'Bantuan',
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Petunjuk Singkat'),
                            content: const Text('Pilih template gambar, atur posisi barcode lalu tekan "Fix Posisi". Setelah itu tekan "Generate 10 Kupon & Preview PDF" untuk menyimpan dan melihat PDF.'),
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
                    controller: _searchControllerKupon,
                    decoration: InputDecoration(
                      hintText: 'Cari kupon berdasarkan kode ...',
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
                              Text('Preview Kupon', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                              const SizedBox(height: 12),
                              StreamBuilder<QuerySnapshot>(
                                stream: FirebaseFirestore.instance.collection('kupon').snapshots(),
                                builder: (context, snapshot) {
                                  final q = _searchControllerKupon.text.trim().toLowerCase();
                                  if (!snapshot.hasData) {
                                    return _buildCouponPreview(_generatedCoupons.isNotEmpty ? _generatedCoupons.first : _generateRandomCode(7).toUpperCase());
                                  }
                                  final docs = snapshot.data!.docs.where((d) {
                                    if (q.isEmpty) return false;
                                    final data = d.data() as Map<String, dynamic>?;
                                    final code = (data?['kode'] ?? data?['code'] ?? '').toString().toLowerCase();
                                    final status = (data?['status'] ?? '').toString().toLowerCase();
                                    return code.contains(q) || status.contains(q);
                                  });
                                  
                                  if (q.isNotEmpty && docs.isNotEmpty) {
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        ...docs.map((d) {
                                          final data = d.data() as Map<String, dynamic>?;
                                          final code = (data?['kode'] ?? data?['code'] ?? '').toString();
                                          final status = (data?['status'] ?? 'unknown').toString();
                                          final statusColor = status == 'tersedia' ? Colors.green : (status == 'hangus' ? Colors.red : Colors.orange);
                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 8),
                                            child: Card(
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                              child: ListTile(
                                                title: Text(code, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                                                subtitle: Text('Status: $status'),
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
                                  return _buildCouponPreview(_generatedCoupons.isNotEmpty ? _generatedCoupons.first : _generateRandomCode(7).toUpperCase());
                                },
                              ),
                              const SizedBox(height: 14),
                              const SizedBox(height: 8),
                              // White star-style generate button
                              Container(
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0,3))]),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: (_isLoading || !_barcodePositionFixed || _templateImage == null) ? null : _generateKupon,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(Icons.star, color: Color(0xFFFFC107)),
                                          const SizedBox(width: 10),
                                          Text('Generate 10 Kupon & Preview PDF', style: TextStyle(color: (_isLoading || !_barcodePositionFixed || _templateImage == null) ? Colors.grey[500] : Colors.black, fontWeight: FontWeight.w600)),
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

                        // Right: Controls & actions (compact modern card)
                        Expanded(
                          flex: 1,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Card(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 2,
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    children: [
                                      const Text('Aksi Cepat', style: TextStyle(fontWeight: FontWeight.w600)),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              onPressed: _templateImage != null ? _pickTemplateImage : null,
                                              icon: const Icon(Icons.image_search),
                                              label: const Text('Ganti Template'),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Align(alignment: Alignment.centerLeft, child: Text('Kupon Tersimpan', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[800]))),
                                      const SizedBox(height: 8),
                                      Container(
                                        constraints: const BoxConstraints(maxHeight: 220),
                                        child: _generatedCoupons.isEmpty
                                            ? Center(child: Text('Belum ada kupon', style: TextStyle(color: Colors.grey[600])))
                                            : SingleChildScrollView(
                                                child: Wrap(
                                                  spacing: 8,
                                                  runSpacing: 8,
                                                  children: _generatedCoupons.map((c) => Chip(label: Text(c))).toList(),
                                                ),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : // Narrow layout
                  Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Preview Kupon', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 12),
                        StreamBuilder<QuerySnapshot>(
                          stream: FirebaseFirestore.instance.collection('kupon').snapshots(),
                          builder: (context, snapshot) {
                            final q = _searchControllerKupon.text.trim().toLowerCase();
                            if (!snapshot.hasData) {
                              return _buildCouponPreview(_generatedCoupons.isNotEmpty ? _generatedCoupons.first : _generateRandomCode(7).toUpperCase());
                            }
                            final docs = snapshot.data!.docs.where((d) {
                              if (q.isEmpty) return false;
                              final data = d.data() as Map<String, dynamic>?;
                              final code = (data?['kode'] ?? data?['code'] ?? '').toString().toLowerCase();
                              final status = (data?['status'] ?? '').toString().toLowerCase();
                              return code.contains(q) || status.contains(q);
                            });
                            
                            if (q.isNotEmpty && docs.isNotEmpty) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  ...docs.map((d) {
                                    final data = d.data() as Map<String, dynamic>?;
                                    final code = (data?['kode'] ?? data?['code'] ?? '').toString();
                                    final status = (data?['status'] ?? 'unknown').toString();
                                    final statusColor = status == 'tersedia' ? Colors.green : (status == 'hangus' ? Colors.red : Colors.orange);
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: Card(
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        child: ListTile(
                                          title: Text(code, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
                                          subtitle: Text('Status: $status'),
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
                            return _buildCouponPreview(_generatedCoupons.isNotEmpty ? _generatedCoupons.first : _generateRandomCode(7).toUpperCase());
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
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0,3))]),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: (_isLoading || !_barcodePositionFixed || _templateImage == null) ? null : _generateKupon,
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.star, color: Color(0xFFFFC107)),
                                    const SizedBox(width: 10),
                                    Text('Generate 10 Kupon & Preview PDF', style: TextStyle(color: (_isLoading || !_barcodePositionFixed || _templateImage == null) ? Colors.grey[500] : Colors.black, fontWeight: FontWeight.w600)),
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




