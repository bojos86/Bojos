import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const BBKSuperApp());
}

class BBKSuperApp extends StatelessWidget {
  const BBKSuperApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BBK AI OCR',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E356B), brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Inputs
  final rawCtrl = TextEditingController();
  final acctCtrl = TextEditingController(); // BBK debit 12
  final ibanCtrl = TextEditingController();
  final bicCtrl = TextEditingController();
  final amtCtrl = TextEditingController();
  String ccy = 'KWD';
  final benNameCtrl = TextEditingController();
  final benBankCtrl = TextEditingController();
  String purposeCode = 'SALA';
  final purposeTextCtrl = TextEditingController();
  String charges = 'SHA';

  bool hasIntermediary = false;
  final intBankCtrl = TextEditingController();
  final intBicCtrl = TextEditingController();

  // Staff/compliance
  bool staffMode = false;
  bool svApproved = false; // SigCap
  String amlStatus = 'PENDING'; // CLEAR / WARN / BLOCK / PENDING
  String amlReason = '';

  // OCR
  final TextRecognizer recLat = TextRecognizer(script: TextRecognitionScript.latin);
  final TextRecognizer recAra = TextRecognizer(script: TextRecognitionScript.arabic);
  bool busy = false;
  CameraController? cam;
  List<CameraDescription>? cams;

  // Purpose codes (نموذج)
  final List<Map<String,String>> cbkCodes = const [
    {'code':'SALA','label':'SALA — Salary/Payroll'},
    {'code':'RENT','label':'RENT — Rent Payment'},
    {'code':'MEDC','label':'MEDC — Medical/Insurance'},
    {'code':'GOOD','label':'GOOD — Goods/Trade'},
    {'code':'SERV','label':'SERV — Services'},
    {'code':'TUIT','label':'TUIT — Tuition/Education'},
    {'code':'OTHR','label':'OTHR — Other'},
  ];

  // Supported currencies
  final List<String> currencies = const ['AED','SAR','BHD','OMR','QAR','USD','EUR','GBP','KWD','INR','CHF','JPY'];

  @override
  void dispose() {
    recLat.close();
    recAra.close();
    cam?.dispose();
    super.dispose();
  }

  // Helpers
  String _stripNums(String v) {
    const ara = '٠١٢٣٤٥٦٧٨٩';
    final map = {for (var i=0;i<10;i++) ara[i]: i.toString()};
    return v.split('').map((ch)=> map[ch] ?? ch).join();
  }
  String _strip(String v) => _stripNums(v).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  String _cleanAmt(String v){
    v=_stripNums(v).replaceAll(RegExp('[،,]'),'').replaceAll('/', '.').replaceAll(RegExp('[^0-9.]'),'');
    final p=v.split('.'); if(p.length>2) v=p.first+'.'+p.sublist(1).join();
    return v;
  }
  bool _ibanOk(String iban){
    final s=_strip(iban);
    if(s.length!=30) return false;
    final t=s.substring(4)+s.substring(0,4);
    var e='';
    for(final c in t.split('')){
      if(RegExp('[A-Z]').hasMatch(c)){ e+=(c.codeUnitAt(0)-55).toString(); } else { e+=c; }
    }
    var r=0;
    for(var i=0;i<e.length;i+=7){ r=int.parse('$r${e.substring(i,i+7>e.length?e.length:i+7)}')%97; }
    return r==1;
  }
  final Set<String> iso2 = {
    'AD','AE','AF','AG','AI','AL','AM','AO','AQ','AR','AS','AT','AU','AW','AX','AZ','BA','BB','BD','BE','BF','BG','BH','BI','BJ','BL','BM','BN','BO','BQ','BR','BS','BT','BV','BW','BY','BZ','CA','CC','CD','CF','CG','CH','CI','CK','CL','CM','CN','CO','CR','CU','CV','CW','CX','CY','CZ','DE','DJ','DK','DM','DO','DZ','EC','EE','EG','EH','ES','ET','FI','FJ','FK','FM','FO','FR','GA','GB','GD','GE','GF','GG','GH','GI','GL','GM','GN','GP','GQ','GR','GS','GT','GU','GW','GY','HK','HM','HN','HR','HT','HU','ID','IE','IL','IM','IN','IO','IQ','IR','IS','IT','JE','JM','JO','JP','KE','KG','KH','KI','KM','KN','KP','KR','KW','KY','KZ','LA','LB','LC','LI','LK','LR','LS','LT','LU','LV','LY','MA','MC','MD','ME','MF','MG','MH','MK','ML','MM','MN','MO','MP','MQ','MR','MS','MT','MU','MV','MW','MX','MY','MZ','NA','NC','NE','NF','NG','NI','NL','NO','NP','NR','NU','NZ','OM','PA','PE','PF','PG','PH','PK','PL','PM','PN','PR','PS','PT','PW','PY','QA','RE','RO','RS','RU','RW','SA','SB','SC','SD','SV','SX','SY','SZ','TC','TD','TF','TG','TH','TJ','TK','TL','TM','TN','TO','TR','TT','TV','TW','TZ','UA','UG','UM','US','UY','UZ','VA','VC','VE','VG','VI','VN','VU','WF','WS','YE','YT','ZA','ZM','ZW'
  };
  String? _valBIC(String raw){
    raw=raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'),'');
    if(!(raw.length==8||raw.length==11)) return null;
    if(!RegExp(r'^[A-Z]{4}[A-Z]{2}[A-Z0-9]{2}([A-Z0-9]{3})?$').hasMatch(raw)) return null;
    final cc=raw.substring(4,6); if(!iso2.contains(cc)) return null;
    final loc=raw.substring(6,8); if(RegExp(r'^[01]').hasMatch(loc)) return null;
    return raw;
  }

  // OCR extraction
  Map<String,String> _extract(String text){
    final up=text.toUpperCase();

    // Debit BBK 12 (starts 12/22)
    String debit='';
    for(final line in text.split(RegExp(r'\r?\n'))){
      final L=line.toUpperCase();
      if(RegExp(r'\b(A/C|A\s*\.?C|ACCOUNT|ACCT|ACC\.? NO)\b').hasMatch(L)){
        final digits=line.replaceAll(RegExp(r'[^0-9]'),'');
        if((digits.startsWith('12')||digits.startsWith('22'))&&digits.length>=12){ debit=digits.substring(0,12); break; }
      }
    }
    if(debit.isEmpty){
      final m=text.replaceAll(RegExp('[^0-9]'),' ').replaceAll(RegExp(r'\s+'),' ').trim();
      final r=RegExp(r'\b(12\d{10}|22\d{10})\b').firstMatch(m); if(r!=null) debit=r.group(0)!;
    }

    // IBAN
    String ibanRaw='';
    final mi=RegExp(r'\bIBAN\b\s*[:\-]?\s*([A-Z0-9\s]+)').firstMatch(up) ?? RegExp(r'\bKW\s*\d{2}[A-Z0-9\s]{20,}').firstMatch(up);
    if(mi!=null) ibanRaw=mi.group(1)??mi.group(0)!;
    String iban='';
    if(ibanRaw.isNotEmpty){
      final base=_strip(ibanRaw);
      final vars={base, base.replaceAll('O','0'), base.replaceAll('I','1')};
      for(final v in vars){
        final vv=v.startsWith('KW')&&v.length>30? v.substring(0,30):v;
        if(vv.length==30 && _ibanOk(vv)){ iban=vv; break; }
      }
    }

    // BIC
    String bic='';
    final ctx=RegExp(r'(?:BIC\s*[\/|]?\s*SWIFT\s*CODE|SWIFT\s*CODE|BIC)\s*[:\-]?\s*([A-Z0-9\.\s]{6,40})', caseSensitive:false).firstMatch(text);
    if(ctx!=null){
      final win=(ctx.group(1)??'').toUpperCase().replaceAll(RegExp('[^A-Z0-9\s]'),' ');
      for(final tok in win.split(RegExp(r'\s+'))){
        final v=tok.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'),'');
        final ok=_valBIC(v); if(ok!=null){ bic=ok; break; }
      }
    }
    if(bic.isEmpty){
      for(final tok in up.replaceAll(RegExp(r'[^A-Z0-9]'),' ').split(RegExp(r'\s+'))){
        final ok=_valBIC(tok); if(ok!=null){ bic=ok; break; }
      }
    }

    // Amount/Currency
    String amt='';
    final ma=RegExp(r'AMOUNT\s*[:\-]?\s*([A-Z]{0,3}\s*[0-9\.,/]+)', caseSensitive:false).firstMatch(text)
      ?? RegExp(r'\bKWD\b\s*([0-9\.,/]+)').firstMatch(text)
      ?? RegExp(r'\bKD\b\s*([0-9\.,/]+)').firstMatch(up)
      ?? RegExp(r'AMOUNT\s*[:\-]?\s*([0-9\.,/]+)').firstMatch(up);
    if(ma!=null) amt=_cleanAmt(ma.group(1)!);

    String dccy='';
    for(final c in currencies){ if(RegExp(r'(^|\s)'+c+r'(\s|:|/|$)').hasMatch(up)){ dccy=c; break; } }

    // Beneficiary
    String ben='';
    final mn=RegExp(r'BENEFICIARY\s*NAME\s*[:\-]?\s*([^\n\r]+)', caseSensitive:false).firstMatch(text)
      ?? RegExp(r'M\/S\.?\s*([^\n\r]+)', caseSensitive:false).firstMatch(text);
    if(mn!=null) ben=(mn.group(1)??'').trim().toUpperCase().replaceAll(RegExp(r'\s+'),' ');

    String bank='';
    final mb=RegExp(r'BENEFICIARY\s*BANK\s*[:\-]?\s*([^\n\r]+)', caseSensitive:false).firstMatch(text)
      ?? RegExp(r'BANK\s*[:\-]?\s*([^\n\r]+)', caseSensitive:false).firstMatch(text);
    if(mb!=null) bank=(mb.group(1)??'').trim().toUpperCase().replaceAll(RegExp(r'\s+'),' ');

    String ptext='';
    final mp=RegExp(r'PURPOSE\s*OF\s*TRANSFER\s*[:\-]?\s*([^\n\r]+)', caseSensitive:false).firstMatch(text)
      ?? RegExp(r'FIELD\s*70\s*[:\-]?\s*([^\n\r]+)', caseSensitive:false).firstMatch(text);
    if(mp!=null) ptext=(mp.group(1)??'').trim().toUpperCase();

    String ch='';
    if(RegExp(r'\bOUR\b', caseSensitive:false).hasMatch(text) || RegExp('TO OUR ACCOUNT', caseSensitive:false).hasMatch(text)) ch='OUR';
    if(RegExp(r'\bSHA\b', caseSensitive:false).hasMatch(text) || RegExp('SHARED', caseSensitive:false).hasMatch(text)) ch='SHA';

    return {'debit':debit,'iban':iban,'bic':bic,'amt':amt,'ccy':dccy,'ben':ben,'bank':bank,'purposeText':ptext,'charges':ch};
  }

  Future<void> _scanFromFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if(res==null) return;
    await _runOCR(File(res.files.single.path!));
  }
  Future<void> _scanFromCamera() async {
    cams ??= await availableCameras();
    final back = cams!.firstWhere((c)=>c.lensDirection==CameraLensDirection.back, orElse: ()=>cams!.first);
    cam = CameraController(back, ResolutionPreset.medium, enableAudio:false);
    await cam!.initialize();
    final pic = await cam!.takePicture();
    await _runOCR(File(pic.path));
  }
  Future<void> _runOCR(File img) async {
    setState(()=>busy=true);
    try{
      final input = InputImage.fromFile(img);
      final latin = await recLat.processImage(input);
      final arabic = await recAra.processImage(input);
      final text = (latin.text+"\n"+arabic.text).trim();
      rawCtrl.text = text;
      final o=_extract(text);
      if(o['debit']!.isNotEmpty) acctCtrl.text=o['debit']!;
      if(o['iban']!.isNotEmpty) ibanCtrl.text=o['iban']!;
      if(o['bic']!.isNotEmpty) bicCtrl.text=o['bic']!;
      if(o['amt']!.isNotEmpty) amtCtrl.text=o['amt']!;
      if(o['ccy']!.isNotEmpty) ccy=o['ccy']!;
      if(o['ben']!.isNotEmpty) benNameCtrl.text=o['ben']!;
      if(o['bank']!.isNotEmpty) benBankCtrl.text=o['bank']!;
      if(o['purposeText']!.isNotEmpty) purposeTextCtrl.text=o['purposeText']!;
      if(o['charges']!.isNotEmpty) charges=o['charges']!;
      if(ccy=='KWD') charges='SHA';
      setState((){});
    } finally { setState(()=>busy=false); }
  }

  bool _validate(){
    final acct = acctCtrl.text.replaceAll(RegExp(r'\D'), '');
    final debitOk = acct.length==12 && (acct.startsWith('12')||acct.startsWith('22'));
    final ibanOk = _ibanOk(ibanCtrl.text);
    final bicOk  = _valBIC(bicCtrl.text)!=null;
    final amtOk  = amtCtrl.text.isNotEmpty && double.tryParse(amtCtrl.text.replaceAll(',', ''))!=null;
    final namesOk= benNameCtrl.text.trim().isNotEmpty && benBankCtrl.text.trim().isNotEmpty;
    final purposeOk = purposeTextCtrl.text.trim().isNotEmpty;
    final chargesOk = charges=='OUR'||charges=='SHA';
    var interOk = true;
    if(hasIntermediary){
      interOk = intBankCtrl.text.trim().isNotEmpty && (_valBIC(intBicCtrl.text)!=null);
    }
    if(staffMode && !svApproved) return false;
    return debitOk && ibanOk && bicOk && amtOk && namesOk && purposeOk && chargesOk && interOk;
  }

  Future<void> _exportJSON() async {
    final obj = _payload();
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/bbk_payment_${DateTime.now().millisecondsSinceEpoch}.json');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(obj));
    _toast('Saved JSON: ${f.path}');
  }
  Future<void> _exportCSV() async {
    final obj = _payload();
    final headers = obj.keys.toList();
    final values  = headers.map((k)=> (obj[k]??'').toString().replaceAll(',', '')).toList();
    final csv = [headers.join(','), values.join(',')].join('\n');
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/bbk_payment_${DateTime.now().millisecondsSinceEpoch}.csv');
    await f.writeAsString(csv);
    _toast('Saved CSV: ${f.path}');
  }

  Map<String,dynamic> _payload()=> {
    'bbkDebit': acctCtrl.text.replaceAll(RegExp(r'\D'), ''),
    'iban': _strip(ibanCtrl.text),
    'bic': bicCtrl.text.toUpperCase(),
    'amount': amtCtrl.text,
    'currency': ccy,
    'beneficiaryName': benNameCtrl.text.trim().toUpperCase(),
    'beneficiaryBank': benBankCtrl.text.trim().toUpperCase(),
    'purposeCode': purposeCode,
    'purposeText': purposeTextCtrl.text.trim(),
    'charges': charges,
    'intermediaryBank': hasIntermediary? intBankCtrl.text.trim().toUpperCase() : '',
    'intermediaryBic':  hasIntermediary? intBicCtrl.text.toUpperCase() : '',
    'svApproved': svApproved,
    'amlStatus': amlStatus,
  };

  String _mt103(){
    final now = DateTime.now();
    final ymd = DateFormat('yyMMdd').format(now);
    final amtFixed = (double.tryParse(amtCtrl.text.replaceAll(',', '')) ?? 0.0).toStringAsFixed(2);
    final debit = acctCtrl.text.replaceAll(RegExp(r'\D'), '');
    final lines = <String>[
      ':20:BBKREF'+DateFormat('yyMMddHHmmss').format(now),
      ':23B:CRED',
      ':32A
