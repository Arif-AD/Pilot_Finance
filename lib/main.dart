import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_options.dart';
import 'widgets/navbar.dart';
import 'screens/riwayat_screen.dart';
import 'screens/splash_screen.dart';
import 'services/update_service.dart';
import 'widgets/update_dialog.dart';

Future<void> main() async {
  // Pastikan Flutter sudah terhubung sebelum Firebase diinisialisasi
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi SharedPreferences terlebih dahulu
  await SharedPreferences.getInstance();

  // Inisialisasi Firebase dengan konfigurasi platform
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PilotFinance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),

      // Gunakan splash screen sebagai halaman pertama, kemudian ke MainScreen
      home: const SplashScreenWrapper(),

      // Daftarkan route agar bisa pindah ke halaman Riwayat setelah input
      routes: {
        '/home': (context) => const MainScreen(),
        '/riwayat': (context) => const RiwayatScreen(),
      },
    );
  }
}

// Wrapper untuk menampilkan splash screen pertama kali
class SplashScreenWrapper extends StatefulWidget {
  const SplashScreenWrapper({super.key});

  @override
  State<SplashScreenWrapper> createState() => _SplashScreenWrapperState();
}

class _SplashScreenWrapperState extends State<SplashScreenWrapper> {
  bool _showSplash = true;

  @override
  void initState() {
    super.initState();
    // Tampilkan splash screen singkat sebelum MainScreen
    Future.delayed(const Duration(milliseconds: 1000), () {
      if (mounted) {
        // Check untuk update setelah splash selesai
        _checkForUpdates();
        
        setState(() {
          _showSplash = false;
        });
      }
    });
  }

  Future<void> _checkForUpdates() async {
    try {
      // STEP 0: Check apakah ada update yang sudah berhasil diinstall
      // Jika versi berubah, hapus APK file (instalasi berhasil)
      final isUpdated = await UpdateService.isVersionUpdated();
      if (isUpdated) {
        print('App version updated successfully! Cleaning up APK file...');
        // Try delete APK file yang sudah tidak diperlukan
        try {
          final pendingApkPath = await UpdateService.detectPendingApkUpdate();
          if (pendingApkPath != null) {
            await UpdateService.deleteApkFile(pendingApkPath);
            print('APK file deleted after successful update');
          }
        } catch (e) {
          print('Error cleaning up APK: $e');
        }
        return; // Keluar, tidak perlu check update lagi
      }

      // STEP 1: Check untuk pending APK terlebih dahulu
      final pendingApkPath = await UpdateService.detectPendingApkUpdate();
      
      if (pendingApkPath != null && mounted) {
        print('Found pending APK update: $pendingApkPath');
        // Show install dialog untuk APK yang sudah ada
        showPendingApkDialog(context, pendingApkPath);
        return; // Jangan check Firestore jika ada pending APK
      }

      // STEP 2: Check untuk update baru di Firestore
      final updateInfo = await UpdateService.checkForUpdates();
      
      if (updateInfo != null && mounted) {
        // Show update dialog
        showDialog(
          context: context,
          barrierDismissible: !updateInfo.isRequired, // Wajib untuk required update
          builder: (context) => UpdateDialog(
            updateInfo: updateInfo,
            onUpdateLater: () {
              // Optional: Save preference untuk jangan ingatkan untuk update ini
              // (bisa implement nanti)
            },
          ),
        );
      }
    } catch (e) {
      print('Error checking updates: $e');
      // Silent fail - jangan ganggu user experience
    }
  }

  @override
  Widget build(BuildContext context) {
    return _showSplash ? const SplashScreen() : const MainScreen();
  }
}

// Main navigation screen dengan navbar (dari navbar.dart)
// MainScreen sudah diimport dari widgets/navbar.dart
