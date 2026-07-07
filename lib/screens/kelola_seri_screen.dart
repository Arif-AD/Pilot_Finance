import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class KelolaSeriScreen extends StatefulWidget {
  const KelolaSeriScreen({super.key});

  @override
  State<KelolaSeriScreen> createState() => _KelolaSeriScreenState();
}

class _KelolaSeriScreenState extends State<KelolaSeriScreen> {
  final TextEditingController _seriController = TextEditingController();
  final CollectionReference _seriRef = FirebaseFirestore.instance.collection('seri');
  final CollectionReference _merkRef = FirebaseFirestore.instance.collection('merk');

  String? _selectedMerkId;
  String? _selectedMerkName;

  Future<void> _tambahSeri() async {
    if (_selectedMerkId == null || _seriController.text.trim().isEmpty) return;
    await _seriRef.add({
      'nama': _seriController.text.trim(),
      'merk_id': _selectedMerkId,
      'merk_nama': _selectedMerkName,
    });
    _seriController.clear();
  }

  Future<void> _hapusSeri(String id) async {
    await _seriRef.doc(id).delete();
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
            child: Row(children: const [SizedBox(width: 8), Expanded(child: Text('Kelola Seri', style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)))]),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            StreamBuilder<QuerySnapshot>(
              stream: _merkRef.snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox();
                final merks = snapshot.data!.docs;
                return DropdownButtonFormField<String>(
                  value: _selectedMerkId,
                  hint: const Text('Pilih Merk'),
                  items: merks.map((doc) {
                    return DropdownMenuItem(
                      value: doc.id,
                      child: Text(doc['nama']),
                      onTap: () => _selectedMerkName = doc['nama'],
                    );
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedMerkId = val),
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    labelText: 'Merk',
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  ),
                );
              },
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _seriController,
              decoration: InputDecoration(
                hintText: 'Nama Seri',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                filled: true,
                fillColor: Colors.white,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 48,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _tambahSeri,
                style: ElevatedButton.styleFrom(padding: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), backgroundColor: Colors.transparent, elevation: 2),
                child: Ink(
                  decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF0B63D4), Color(0xFF4EA8FF)]), borderRadius: BorderRadius.all(Radius.circular(8))),
                  child: Container(alignment: Alignment.center, padding: const EdgeInsets.symmetric(horizontal: 16), child: const Text('Tambah', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600))),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _seriRef.snapshots(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final data = snapshot.data!.docs;
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
                          title: Text('${item['merk_nama']} - ${item['nama']}'),
                          trailing: InkWell(
                            onTap: () => _hapusSeri(item.id),
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



