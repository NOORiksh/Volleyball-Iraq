import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'services.dart';
import 'widgets.dart';

/// الصفحة الرئيسية: غلاف + نبذة + الرعاة (كلها من إعدادات المدير)
class HomeTab extends StatelessWidget {
  const HomeTab({super.key});
  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: Cms.site(),
        builder: (c, s) {
          final site = s.data?.data() ?? <String, dynamic>{};
          final about = '${site['about'] ?? ''}'.trim(), footer = '${site['footer'] ?? ''}'.trim();
          final st = '${site['sponsorsTitle'] ?? ''}'.trim();
          return ListView(padding: EdgeInsets.zero, children: [
            _Hero(site),
            if (about.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(about, style: const TextStyle(height: 1.6)))),
              ),
            _Sponsors(st.isEmpty ? 'رعاة البطولة' : st),
            if (footer.isNotEmpty)
              Padding(padding: const EdgeInsets.all(24), child: Text(footer, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor))),
          ]);
        },
      );
}

class _Hero extends StatelessWidget {
  final Map<String, dynamic> site;
  const _Hero(this.site);
  @override
  Widget build(BuildContext context) {
    final hero = '${site['heroImage'] ?? ''}', logo = '${site['logo'] ?? ''}';
    final t = '${site['title'] ?? ''}'.trim(), sub = '${site['subtitle'] ?? ''}'.trim();
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: Container(
        height: 240, width: double.infinity,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFFE8590C), Color(0xFF8A2B00)], begin: Alignment.topRight, end: Alignment.bottomLeft),
          image: hero.isEmpty ? null : DecorationImage(image: NetworkImage(hero), fit: BoxFit.cover, colorFilter: const ColorFilter.mode(Colors.black54, BlendMode.darken)),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircleAvatar(
            radius: 38, backgroundColor: Colors.white,
            backgroundImage: logo.isEmpty ? null : NetworkImage(logo),
            child: logo.isEmpty ? const Icon(Icons.sports_volleyball, size: 44, color: Color(0xFFE8590C)) : null,
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(t.isEmpty ? 'بطولة شهداء العراق للكرة الطائرة' : t, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(height: 6),
          Text(sub.isEmpty ? 'تابع النتائج والترتيب والتصفيات' : sub, style: const TextStyle(color: Colors.white70)),
        ]),
      ),
    );
  }
}

class _Sponsors extends StatelessWidget {
  final String title;
  const _Sponsors(this.title);
  @override
  Widget build(BuildContext context) => StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: Cms.sponsors(),
        builder: (c, s) {
          final all = (s.data?.docs ?? []).map((d) => d.data()).where((d) => d['active'] != false).toList();
          if (all.isEmpty) return const SizedBox.shrink();
          final main = all.where((d) => d['tier'] == 'main').toList();
          final rest = all.where((d) => d['tier'] != 'main').toList();
          final w = (MediaQuery.of(context).size.width - 44) / 2;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.handshake, color: Color(0xFFE8590C)),
                const SizedBox(width: 8),
                Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ]),
              const SizedBox(height: 12),
              for (final d in main) Padding(padding: const EdgeInsets.only(bottom: 12), child: _SponsorCard(d, big: true, width: double.infinity)),
              Wrap(spacing: 12, runSpacing: 12, children: [for (final d in rest) _SponsorCard(d, big: false, width: w)]),
            ]),
          );
        },
      );
}

class _SponsorCard extends StatelessWidget {
  final Map<String, dynamic> d;
  final bool big;
  final double width;
  const _SponsorCard(this.d, {required this.big, required this.width});
  @override
  Widget build(BuildContext context) {
    final logo = '${d['logo'] ?? ''}', link = '${d['link'] ?? ''}'.trim();
    return SizedBox(
      width: width,
      child: Card(
        elevation: big ? 4 : 1, clipBehavior: Clip.antiAlias, margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: big ? const BorderSide(color: Color(0xFFFFB300), width: 2) : BorderSide.none),
        child: InkWell(
          onTap: link.isEmpty ? null : () => openLink(context, link),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              if (big) const Text('الراعي الرئيسي', style: TextStyle(color: Color(0xFFFF8F00), fontWeight: FontWeight.bold)),
              SizedBox(
                height: big ? 110 : 70,
                child: logo.isEmpty
                    ? const Icon(Icons.store, size: 40)
                    : Image.network(logo, fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
              ),
              const SizedBox(height: 8),
              Text('${d['name'] ?? ''}', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.bold)),
              if (link.isNotEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.open_in_new, size: 14), SizedBox(width: 4), Text('زيارة', style: TextStyle(fontSize: 12)),
                  ]),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
