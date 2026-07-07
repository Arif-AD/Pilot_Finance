import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class KelolaJenisServisScreen extends StatefulWidget {
  const KelolaJenisServisScreen({super.key});

  @override
  State<KelolaJenisServisScreen> createState() => _KelolaJenisServisScreenState();
}

class _KelolaJenisServisScreenState extends State<KelolaJenisServisScreen> {
  final TextEditingController _jenisController = TextEditingController();
  final CollectionReference _jenisServisRef =
      FirebaseFirestore.instance.collection('jenis_servis');

  Future<void> _tambahJenis() async {
    final jenis = _jenisController.text.trim();
    if (jenis.isEmpty) return;
    await _jenisServisRef.add({'nama': jenis});
    _jenisController.clear();
  }

  Future<void> _hapusJenis(String id) async {
    await _jenisServisRef.doc(id).delete();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(100),
        child: Container(
          padding: const EdgeInsets.only(top: 26, left: 16, right: 16, bottom: 12),
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
          ),
          child: SafeArea(
            bottom: false,
            child: Row(children: const [SizedBox(width: 8), Expanded(child: Text('Kelola Jenis Servis', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)))]),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _jenisController,
                    decoration: InputDecoration(
                      hintText: 'Nama Jenis Servis',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _tambahJenis,
                    style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), backgroundColor: Colors.transparent, elevation: 2),
                    child: Ink(
                      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]), borderRadius: BorderRadius.all(Radius.circular(8))),
                      child: Container(alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 16), child: const Text('Tambah', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                    ),
                  ),
                )
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _jenisServisRef.snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = snapshot.data?.docs ?? [];
                  if (data.isEmpty) {
                    return const Center(child: Text('Belum ada data'));
                  }
                  return ListView.builder(
                    itemCount: data.length,
                    itemBuilder: (context, index) {
                      final item = data[index];
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 4))]),
                        child: ListTile(
                          title: Text(item['nama']),
                          trailing: InkWell(
                            onTap: () => _hapusJenis(item.id),
                            borderRadius: BorderRadius.circular(10),
                            child: Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(color: Colors.red.shade600, borderRadius: BorderRadius.circular(10)),
                              child: const Icon(Icons.delete, color: Colors.white, size: 18),
                            ),
                          ),
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

