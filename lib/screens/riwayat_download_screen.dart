import 'dart:io';
import 'package:flutter/material.dart';
import '../widgets/animated_dialog.dart';

class RiwayatDownloadScreen extends StatefulWidget {
  const RiwayatDownloadScreen({super.key});

  @override
  State<RiwayatDownloadScreen> createState() => _RiwayatDownloadScreenState();
}

class _RiwayatDownloadScreenState extends State<RiwayatDownloadScreen> {
  List<DownloadItem> downloadHistory = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDownloadHistory();
  }

  Future<void> _loadDownloadHistory() async {
    setState(() => isLoading = true);
    try {
      List<DownloadItem> allFiles = [];

      // Scan Excel files in /storage/emulated/0/Documents/PilotFinance
      final excelDir = Directory('/storage/emulated/0/Documents/PilotFinance');
      if (await excelDir.exists()) {
        final files = await excelDir.list().toList();
        final excelFiles = files
            .whereType<File>()
            .where((f) => f.path.endsWith('.xlsx'))
            ;

        allFiles.addAll(excelFiles.map((file) {
          final stat = file.statSync();
          return DownloadItem(
            fileName: file.path.split('/').last,
            filePath: file.path,
            fileSize: stat.size,
            createdAt: stat.modified,
            fileType: 'Excel',
          );
        }));
      }

      // Scan PDF files (kupon & voucher) in /storage/emulated/0/Documents
      final documentsDir = Directory('/storage/emulated/0/Documents');
      if (await documentsDir.exists()) {
        final files = await documentsDir.list().toList();
        final pdfFiles = files
            .whereType<File>()
            .where((f) => f.path.endsWith('.pdf'))
            ;

        allFiles.addAll(pdfFiles.map((file) {
          final stat = file.statSync();
          final fileName = file.path.split('/').last;
          final fileType = fileName.startsWith('kupon_') ? 'Kupon' : (fileName.startsWith('voucher_') ? 'Voucher' : 'PDF');
          
          return DownloadItem(
            fileName: fileName,
            filePath: file.path,
            fileSize: stat.size,
            createdAt: stat.modified,
            fileType: fileType,
          );
        }));
      }

      // Sort by creation time (newest first)
      allFiles.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      setState(() {
        downloadHistory = allFiles;
      });
    } catch (e) {
      showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Gagal memuat riwayat: $e',
      );
    } finally {
      setState(() => isLoading = false);
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Color _getFileTypeColor(String fileType) {
    switch (fileType) {
      case 'Excel':
        return const Color(0xFF0B63D4); // Blue
      case 'Kupon':
        return Colors.green; // Green
      case 'Voucher':
        return Colors.orange; // Orange
      default:
        return Colors.grey; // Grey
    }
  }

  Future<void> _deleteFile(int index, String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        setState(() => downloadHistory.removeAt(index));
        if (mounted) {
          showSuccessDialog(
            context,
            title: 'Berhasil',
            message: 'File berhasil dihapus',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        showErrorDialog(
          context,
          title: 'Gagal',
          message: 'Gagal menghapus file: $e',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // ✅ IMMEDIATE navigation: Don't wait for file I/O to complete
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F8FB),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(110),
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
                const CircleAvatar(radius: 26, backgroundColor: Colors.white24, child: Icon(Icons.download, color: Colors.white, size: 26)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Text('Riwayat Download', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                      SizedBox(height: 4),
                      Text('Kelola file Excel yang sudah diunduh', style: TextStyle(color: Colors.white70, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(onPressed: _loadDownloadHistory, icon: const Icon(Icons.refresh, color: Colors.white)),
              ],
            ),
          ),
        ),
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : downloadHistory.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.download_done, size: 80, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text('Belum ada file yang diunduh', style: TextStyle(fontSize: 18, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                      const SizedBox(height: 8),
                      Text('File Excel akan muncul di sini setelah diunduh', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: downloadHistory.length,
                  itemBuilder: (context, index) {
                    final item = downloadHistory[index];
                    return _buildDownloadCard(context, item, index);
                  },
                ),
      ),
    );
  }

  Widget _buildDownloadCard(BuildContext context, DownloadItem item, int index) {
    // Format tanggal secara manual tanpa locale untuk menghindari error
    final date = item.createdAt;
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final monthStr = months[date.month - 1];
    final dateStr = '${date.day.toString().padLeft(2, '0')} $monthStr ${date.year} - ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header dengan icon dan nama file
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Icon(Icons.description, color: Colors.white, size: 24),
                      ),
                    ),
                  const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.fileName,
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0B63D4)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _getFileTypeColor(item.fileType).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  item.fileType,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _getFileTypeColor(item.fileType),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _formatFileSize(item.fileSize),
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Tanggal dan waktu
                Row(
                  children: [
                    Icon(Icons.schedule, size: 16, color: Colors.grey.shade500),
                    const SizedBox(width: 8),
                    Text(
                      dateStr,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Divider
          Container(height: 1, color: Colors.grey.shade200),
          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () => _deleteFile(index, item.filePath),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Hapus'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.red,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class DownloadItem {
  final String fileName;
  final String filePath;
  final int fileSize;
  final DateTime createdAt;
  final String fileType; // 'Excel', 'Kupon', 'Voucher', atau 'PDF'

  DownloadItem({
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    required this.createdAt,
    required this.fileType,
  });
}


