import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'services.dart';

/// يفتح رابط الراعي في المتصفح (http/https فقط)
Future<void> openLink(BuildContext context, String link) async {
  final u = Uri.tryParse(link.trim());
  void msg(String m) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m))); }
  if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) { msg('الرابط غير صالح'); return; }
  final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
  if (!ok) msg('تعذر فتح الرابط');
}

/// حقل صورة: معاينة + رفع من المعرض + إزالة. يرجع رابط الصورة عبر onChanged
class ImageField extends StatefulWidget {
  final String label, folder, url;
  final ValueChanged<String> onChanged;
  const ImageField({super.key, required this.label, required this.folder, required this.url, required this.onChanged});
  @override
  State<ImageField> createState() => _ImageFieldState();
}

class _ImageFieldState extends State<ImageField> {
  bool busy = false;

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, imageQuality: 82);
    if (x == null) return;
    setState(() => busy = true);
    try {
      final bytes = await x.readAsBytes();
      final ext = x.path.toLowerCase().endsWith('.png') ? 'png' : 'jpg';
      widget.onChanged(await Cms.uploadImage(widget.folder, bytes, ext));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر رفع الصورة (الحد 3 ميغابايت)')));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.label, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Container(
            height: 110, width: double.infinity,
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(12)),
            clipBehavior: Clip.antiAlias,
            child: busy
                ? const Center(child: CircularProgressIndicator())
                : widget.url.isEmpty
                    ? const Icon(Icons.image_outlined, size: 40, color: Colors.grey)
                    : Image.network(widget.url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)),
          ),
          Row(children: [
            TextButton.icon(onPressed: busy ? null : _pick, icon: const Icon(Icons.upload), label: Text(widget.url.isEmpty ? 'رفع صورة' : 'تغيير')),
            if (widget.url.isNotEmpty) TextButton(onPressed: () => widget.onChanged(''), child: const Text('إزالة')),
          ]),
        ]),
      );
}
