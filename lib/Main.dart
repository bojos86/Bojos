import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BBKOCRApp());
}

class BBKOCRApp extends StatelessWidget {
  const BBKOCRApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BBK OCR',
        theme: ThemeData(
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF0E356B),
            brightness: Brightness.dark,
          ),
          useMaterial3: true,
        ),
        home: const HomePage(),
      );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final TextEditingController rawCtrl = TextEditingController(),
      acctCtrl = TextEditingController(),
      ibanCtrl = TextEditingController(),
      bicCtrl = TextEditingController(),
      amtCtrl = TextEditingController(),
      ccyCtrl = TextEditingController(text: 'KWD'),
      benNameCtrl = TextEditingController(),
      benBankCtrl = TextEditingController(),
      purposeCtrl = TextEditingController(),
      chargesCtrl = TextEditingController(text: 'SHA');

  final TextRecognizer recognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  final TextRecognizer recognizerAra =
      TextRecognizer(script: TextRecognitionScript.arabic);

  bool busy = false;
  CameraController? cam;
  List<CameraDescription>? cams;

  @override
  void dispose() {
    recognizer.close();
    recognizerAra.close();
    cam?.dispose();
    super.dispose();
  }

  Future<void> initCam() async {
    cams ??= await availableCameras();
    final back = cams!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams!.first);
    cam = CameraController(back, ResolutionPreset.medium, enableAudio: false);
    await cam!.initialize();
    setState(() {});
  }

  String _stripNums(String v) {
    const ara = '٠١٢٣٤٥٦٧٨٩';
    final map = {for (var i = 0; i < 10; i++) ara[i]: '$i'};
    return v.split('').map((ch) => map[ch] ?? ch).join();
  }

  String _cleanAmt(String v) {
    v = _stripNums(v)
        .replaceAll(RegExp('[،,]'), '')
        .replaceAll('/', '.')
        .replaceAll(RegExp('[^0-9\.]'), '');
    final p = v.split('.');
    if (p.length > 2) v = p.first + '.' + p.sublist(1).join();
    return v;
  }

  String _strip(String v) {
    v = _stripNums(v).toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
    return v;
  }

  bool _ibanOk(String iban) {
    final s = _strip(iban);
    if (s.length != 30) return false;
    final t = s.substring(4) + s.substring(0, 4);
    var e = '';
    for (final c in t.split('')) {
      e += RegExp('[A-Z]').hasMatch(c)
          ? (c.codeUnitAt(0) - 55).toString()
          : c;
    }
    var r = 0;
    for (var i = 0; i < e.length; i += 7) {
      r = int.parse('$r${e.substring(i, i + 7 > e.length ? e.length : i + 7)}') %
          97;
    }
    return r == 1;
  }

  Map<String, String> _extract(String text) {
    final up = text.toUpperCase();
    String debit = '';
    for (final line in text.split(RegExp(r'\r?\n'))) {
      final L = line.toUpperCase();
      if (RegExp(r'\b(A/C|A\s*\.?C|ACCOUNT|ACCT|ACC\.? NO)\b')
          .hasMatch(L)) {
        final digits = line.replaceAll(RegExp('[^0-9]'), '');
        if ((digits.startsWith('12') || digits.startsWith('22')) &&
            digits.length >= 12) {
          debit = digits.substring(0, 12);
          break;
        }
      }
    }
    if (debit.isEmpty) {
      final m = text
          .replaceAll(RegExp('[^0-9]'), ' ')
          .replaceAll(RegExp('\s+'), ' ')
          .trim();
      final r = RegExp(r'\b(12\d{10}|22\d{10})\b').firstMatch(m);
      if (r != null) debit = r.group(0)!;
    }

    String ibanRaw = '';
    final mi = RegExp(r'\bIBAN\b\s*[:\-]?\s*([A-Z0-9\s]+)').firstMatch(up) ??
        RegExp(r'\bKW\s*\d{2}[A-Z0-9\s]{20,}').firstMatch(up);
    if (mi != null) {
      ibanRaw = mi.group(1) ?? mi.group(0)!;
    }
    String iban = '';
    if (ibanRaw.isNotEmpty) {
      final base = _strip(ibanRaw);
      final vars = {base, base.replaceAll('O', '0'), base.replaceAll('I', '1')};
      for (final v in vars) {
        final vv = v.startsWith('KW') && v.length > 30 ? v.substring(0, 30) : v;
        if (vv.length == 30 && _ibanOk(vv)) {
          iban = vv;
          break;
        }
      }
    }

    String bic = '';
    final ctx = RegExp(
            r'(?:BIC\s*[\/|]?\s*SWIFT\s*CODE|SWIFT\s*CODE|BIC)\s*[:\-]?\s*([A-Z0-9\.\s]{6,40})',
            caseSensitive: false)
        .firstMatch(text);
    if (ctx != null) {
      final win =
          (ctx.group(1) ?? '').toUpperCase().replaceAll(RegExp('[^A-Z0-9\s]'), ' ');
      for (final tok in win.split(RegExp('\s+'))) {
        final v = tok.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
        if (v.length == 8 || v.length == 11) {
          bic = v;
          break;
        }
      }
    }
    if (bic.isEmpty) {
      for (final tok
          in up.replaceAll(RegExp('[^A-Z0-9]'), ' ').split(RegExp('\s+'))) {
        final v = tok.toUpperCase();
        if (v.length == 8 || v.length == 11) {
          bic = v;
          break;
        }
      }
    }

    String amt = '';
    final ma = RegExp(r'AMOUNT\s*[:\-]?\s*([A-Z]{0,3}\s*[0-9\.,\/]+)',
                caseSensitive: false)
            .firstMatch(text) ??
        RegExp(r'\bKWD\b\s*([0-9\.,\/]+)').firstMatch(text) ??
        RegExp(r'\bKD\b\s*([0-9\.,\/]+)').firstMatch(up) ??
        RegExp(r'AMOUNT\s*[:\-]?\s*([0-9\.,\/]+)').firstMatch(up);
    if (ma != null) amt = _cleanAmt(ma.group(1)!);

    String ben = '';
    final mn = RegExp(r'BENEFICIARY\s*NAME\s*[:\-]?\s*([^\n\r]+)',
                caseSensitive: false)
            .firstMatch(text) ??
        RegExp(r'M\/S\.?\s*([^\n\r]+)', caseSensitive: false)
            .firstMatch(text);
    if (mn != null) ben = (mn.group(1) ?? '').trim().toUpperCase();

    String bank = '';
    final mb = RegExp(r'BENEFICIARY\s*BANK\s*[:\-]?\s*([^\n\r]+)',
                caseSensitive: false)
            .firstMatch(text) ??
        RegExp(r'BANK\s*[:\-]?\s*([^\n\r]+)', caseSensitive: false)
            .firstMatch(text);
    if (mb != null) bank = (mb.group(1) ?? '').trim().toUpperCase();

    String purpose = '';
    final mp = RegExp(r'PURPOSE\s*OF\s*TRANSFER\s*[:\-]?\s*([^\n\r]+)',
                caseSensitive: false)
            .firstMatch(text) ??
        RegExp(r'FIELD\s*70\s*[:\-]?\s*([^\n\r]+)', caseSensitive: false)
            .firstMatch(text);
    if (mp != null) purpose = (mp.group(1) ?? '').trim().toUpperCase();

    String charges = '';
    if (RegExp(r'\bOUR\b', caseSensitive: false).hasMatch(text) ||
        RegExp('TO OUR ACCOUNT', caseSensitive: false).hasMatch(text))
      charges = 'OUR';
    if (RegExp(r'\bSHA\b', caseSensitive: false).hasMatch(text) ||
        RegExp('SHARED', caseSensitive: false).hasMatch(text))
      charges = 'SHA';

    return {
      'debit': debit,
      'iban': iban,
      'bic': bic,
      'amt': amt,
      'ben': ben,
      'bank': bank,
      'purpose': purpose,
      'charges': charges
    };
  }

  Future<void> _pickFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res == null) return;
    await _runOCR(File(res.files.single.path!));
  }

  Future<void> _runOCR(File img) async {
    setState(() => busy = true);
    try {
      final input = InputImage.fromFile(img);
      final latin = await recognizer.processImage(input);
      final arabic = await recognizerAra.processImage(input);
      final text = (latin.text + "\n" + arabic.text).trim();
      rawCtrl.text = text;
      final o = _extract(text);
      if (o['debit']!.isNotEmpty) acctCtrl.text = o['debit']!;
      if (o['iban']!.isNotEmpty) ibanCtrl.text = o['iban']!;
      if (o['bic']!.isNotEmpty) bicCtrl.text = o['bic']!;
      if (o['amt']!.isNotEmpty) amtCtrl.text = o['amt']!;
      if (o['ben']!.isNotEmpty) benNameCtrl.text = o['ben']!;
      if (o['bank']!.isNotEmpty) benBankCtrl.text = o['bank']!;
      if (o['purpose']!.isNotEmpty) purposeCtrl.text = o['purpose']!;
      if (o['charges']!.isNotEmpty) chargesCtrl.text = o['charges']!;
      if (ccyCtrl.text.isEmpty) ccyCtrl.text = 'KWD';
    } finally {
      setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext ctx) => Scaffold(
        appBar: AppBar(title: const Text('BBK OCR (Upload + Camera)')),
        body: ListView(padding: const EdgeInsets.all(12), children: [
          Row(children: [
            Expanded(
                child: ElevatedButton.icon(
                    onPressed: busy ? null : _pickFile,
                    icon: const Icon(Icons.upload),
                    label: const Text('Upload & Scan'))),
            const SizedBox(width: 8),
            Expanded(
                child: ElevatedButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            await initCam();
                            if (!mounted) return;
                            final pic = await cam!.takePicture();
                            await _runOCR(File(pic.path));
                          },
                    icon: const Icon(Icons.photo_camera),
                    label: const Text('Camera Scan'))),
          ]),
          const SizedBox(height: 8),
          TextField(
              controller: rawCtrl,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'RAW OCR TEXT')),
          const Divider(),
          TextField(
              controller: acctCtrl,
              decoration: const InputDecoration(
                  labelText: 'BBK DEBIT ACCOUNT (12 DIGITS START 12/22)')),
          TextField(
              controller: ibanCtrl,
              decoration:
                  const InputDecoration(labelText: 'BENEFICIARY IBAN (30 CHARS)')),
          TextField(
              controller: bicCtrl,
              decoration: const InputDecoration(labelText: 'BIC / SWIFT')),
          Row(children: [
            Expanded(
                child: TextField(
                    controller: amtCtrl,
                    decoration: const InputDecoration(labelText: 'AMOUNT'))),
            const SizedBox(width: 8),
            Expanded(
                child: TextField(
                    controller: ccyCtrl,
                    decoration: const InputDecoration(labelText: 'CURRENCY'))),
          ]),
          TextField(
              controller: benNameCtrl,
              decoration:
                  const InputDecoration(labelText: 'BENEFICIARY NAME')),
          TextField(
              controller: benBankCtrl,
              decoration:
                  const InputDecoration(labelText: 'BENEFICIARY BANK')),
          TextField(
              controller: purposeCtrl,
              decoration: const InputDecoration(
                  labelText: 'PURPOSE OF PAYMENT (FIELD 70)')),
          TextField(
              controller: chargesCtrl,
              decoration:
                  const InputDecoration(labelText: 'CHARGES (OUR/SHA)')),
          const SizedBox(height: 12),
          ElevatedButton.icon(
              onPressed: () {
                final ok =
                    acctCtrl.text.length == 12 &&
                        (acctCtrl.text.startsWith('12') ||
                            acctCtrl.text.startsWith('22')) &&
                        _ibanOk(ibanCtrl.text) &&
                        (bicCtrl.text.length == 8 ||
                            bicCtrl.text.length == 11) &&
                        amtCtrl.text.isNotEmpty &&
                        benNameCtrl.text.isNotEmpty &&
                        benBankCtrl.text.isNotEmpty &&
                        purposeCtrl.text.isNotEmpty &&
                        chargesCtrl.text.isNotEmpty;
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                    content: Text(ok ? 'OK ✅ Ready' : 'Fix fields before submit')));
              },
              icon: const Icon(Icons.verified),
              label: const Text('Validate')),
        ]));
}
