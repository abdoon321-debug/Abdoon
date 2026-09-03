import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

void main() {
  runApp(const SmartWalletApp());
}

class SmartWalletApp extends StatelessWidget {
  const SmartWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'المحفظة الذكية',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
        fontFamily: 'Cairo',
      ),
      // إجبار التطبيق بالكامل على العمل من اليمين ليسار (RTL) لترتيب العناصر العربية بالشكل الصحيح
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child!,
        );
      },
      home: const WalletHomeScreen(),
    );
  }
}

class WalletHomeScreen extends StatefulWidget {
  const WalletHomeScreen({super.key});

  @override
  State<WalletHomeScreen> createState() => _WalletHomeScreenState();
}

class _WalletHomeScreenState extends State<WalletHomeScreen> {
  final TextEditingController _palpayPhoneController = TextEditingController();
  final TextEditingController _palpayPinController = TextEditingController();
  final TextEditingController _palpayAmountController = TextEditingController();

  final TextEditingController _jawwalPhoneController = TextEditingController();
  final TextEditingController _jawwalPinController = TextEditingController();
  final TextEditingController _jawwalAmountController = TextEditingController();

  // false = الدفع لصديق (على اليمين وهو الافتراضي)، true = دفع لتاجر (على اليسار)
  bool _palpayIsMerchant = false;
  bool _jawwalIsMerchant = false;

  List<Map<String, dynamic>> _recentTransactions = [];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    final prefs = await SharedPreferences.getInstance();
    final String? txData = prefs.getString('recent_transactions');

    if (txData != null) {
      try {
        setState(() {
          _recentTransactions =
              List<Map<String, dynamic>>.from(json.decode(txData));
        });
      } catch (_) {
        _recentTransactions = [];
      }
    }
  }

  Future<void> _addTransaction(
    String service,
    String phone,
    String amount,
  ) async {
    final now = DateTime.now();

    final String timeStr =
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}';

    setState(() {
      _recentTransactions.insert(0, {
        'service': service,
        'phone': phone,
        'amount': amount,
        'time': timeStr,
      });

      if (_recentTransactions.length > 5) {
        _recentTransactions = _recentTransactions.sublist(0, 5);
      }
    });

    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      'recent_transactions',
      json.encode(_recentTransactions),
    );
  }

  Future<void> _clearTransactions() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('recent_transactions');

    setState(() {
      _recentTransactions.clear();
    });

    _showSnackBar(
      'تم مسح السجل بنجاح',
      Colors.orangeAccent,
    );
  }

  void _clearPalPayFields() {
    _palpayPhoneController.clear();
    _palpayPinController.clear();
    _palpayAmountController.clear();

    _showSnackBar(
      'تم مسح حقول PalPay',
      Colors.blueGrey,
    );
  }

  void _clearJawwalFields() {
    _jawwalPhoneController.clear();
    _jawwalPinController.clear();
    _jawwalAmountController.clear();

    _showSnackBar(
      'تم مسح حقول Jawwal Pay',
      Colors.blueGrey,
    );
  }

  void _fillFieldsFromTransaction(Map<String, dynamic> tx) {
    final String service = tx['service']?.toString() ?? '';
    final String phone = tx['phone']?.toString() ?? '';
    final String amount = tx['amount']?.toString() ?? '';

    setState(() {
      if (service.contains('PalPay')) {
        _palpayPhoneController.text = phone;
        _palpayAmountController.text = amount;
        _palpayIsMerchant = service.contains('تاجر');
      } else if (service.contains('Jawwal')) {
        _jawwalPhoneController.text = phone;
        _jawwalAmountController.text = amount;
        _jawwalIsMerchant = service.contains('تاجر');
      }
    });

    _showSnackBar(
      'تمت تعبئة البيانات في خدمة $service',
      Colors.blueGrey,
    );
  }

  Future<void> _makeCall(String ussdCode) async {
    final String encodedCode = ussdCode.replaceAll('#', '%23');

    final Uri url = Uri.parse('tel:$encodedCode');

    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      _showSnackBar(
        'تعذر فتح شاشة الاتصال',
        Colors.redAccent,
      );
    }
  }

  void _processPalPay() {
    final String phone = _palpayPhoneController.text.trim();
    final String pin = _palpayPinController.text.trim();
    final String amount = _palpayAmountController.text.trim();

    if (phone.length != 10) {
      _showSnackBar(
        'يرجى إدخال رقم هاتف مكون من 10 أرقام',
        Colors.redAccent,
      );
      return;
    }

    if (pin.length != 4) {
      _showSnackBar(
        'يرجى إدخال رمز سري مكون من 4 أرقام',
        Colors.redAccent,
      );
      return;
    }

    if (amount.isEmpty) {
      _showSnackBar(
        'يرجى إدخال المبلغ المراد تحويله',
        Colors.redAccent,
      );
      return;
    }

    final String code = _palpayIsMerchant
        ? '*370*2*1*$phone*$amount*$pin#'
        : '*370*1*1*$phone*$amount*$pin#';

    final String serviceName =
        _palpayIsMerchant ? 'PalPay (تاجر)' : 'PalPay (صديق)';

    _addTransaction(serviceName, phone, amount);
    _makeCall(code);
  }

  void _processJawwalPay() {
    final String phone = _jawwalPhoneController.text.trim();
    final String pin = _jawwalPinController.text.trim();
    final String amount = _jawwalAmountController.text.trim();

    if (phone.length != 10) {
      _showSnackBar(
        'يرجى إدخال رقم جوال مكون من 10 أرقام',
        Colors.redAccent,
      );
      return;
    }

    if (pin.length != 4) {
      _showSnackBar(
        'يرجى إدخال رمز سري مكون من 4 أرقام',
        Colors.redAccent,
      );
      return;
    }

    if (amount.isEmpty) {
      _showSnackBar(
        'يرجى إدخال المبلغ المراد تحويله',
        Colors.redAccent,
      );
      return;
    }

    final String code = _jawwalIsMerchant
        ? '*110*2*1*$pin*$phone*$amount#'
        : '*110*1*$pin*$phone*$amount#';

    final String serviceName =
        _jawwalIsMerchant ? 'Jawwal Pay (تاجر)' : 'Jawwal Pay (صديق)';

    _addTransaction(serviceName, phone, amount);
    _makeCall(code);
  }

  void _showSnackBar(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          text,
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  void dispose() {
    _palpayPhoneController.dispose();
    _palpayPinController.dispose();
    _palpayAmountController.dispose();
    _jawwalPhoneController.dispose();
    _jawwalPinController.dispose();
    _jawwalAmountController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          children: [
            _buildHeader(),
            Transform.translate(
              offset: const Offset(0, -25),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    _buildDeveloperCard(),
                    const SizedBox(height: 16),
                    _buildPalPayCard(),
                    const SizedBox(height: 16),
                    _buildJawwalPayCard(),
                    const SizedBox(height: 16),
                    _buildRecentTransactionsCard(),
                    const SizedBox(height: 16),
                    _buildMartyrsPrayerCard(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(
        top: 50,
        bottom: 45,
        left: 20,
        right: 20,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF1E40AF),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(40),
          bottomRight: Radius.circular(40),
        ),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.account_balance_wallet_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'المحفظة الذكية',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: Colors.white,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'دفع سريع عبر خدمات USSD في فلسطين',
            style: TextStyle(
              fontFamily: 'Cairo',
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeveloperCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.code_rounded,
              color: Color(0xFF2563EB),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          const Text(
            'برمجة وتصميم أبو خالد ( عبدون )',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E293B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMartyrsPrayerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.favorite_rounded,
                  color: Color(0xFF16A34A),
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'رحم الله شهداءنا الأبرار',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'اللهم تقبل شهداءنا في عليين وأسكنهم فسيح جناتك',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // شريط التبديل: بفضل الـ RTL العام أصبح العنصر الأول (الدفع لصديق) يقع على اليمين تماماً وهو الافتراضي
  Widget _buildModernToggle({
    required bool isMerchant,
    required ValueChanged<bool> onChanged,
    required Color activeColor,
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // 1. الدفع لصديق (على اليمين وهو الافتراضي)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(false),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: !isMerchant ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: !isMerchant
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_outline_rounded,
                      size: 16,
                      color: !isMerchant ? activeColor : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'الدفع لصديق',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: !isMerchant ? activeColor : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // 2. دفع لتاجر (على اليسار)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(true),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isMerchant ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: isMerchant
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.storefront_rounded,
                      size: 16,
                      color: isMerchant ? activeColor : const Color(0xFF64748B),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'دفع لتاجر',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isMerchant ? activeColor : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPalPayCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _clearPalPayFields,
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
                tooltip: 'مسح الحقول',
              ),
              Row(
                children: [
                  const Text(
                    'خدمة PalPay',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildServiceLogo(
                    imagePath: 'assets/images/palpay.png',
                    backgroundColor: const Color(0xFFEFF6FF),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildModernToggle(
            isMerchant: _palpayIsMerchant,
            activeColor: const Color(0xFF2563EB),
            onChanged: (val) {
              setState(() {
                _palpayIsMerchant = val;
              });
            },
          ),
          const SizedBox(height: 16),
          _buildModernInputField(
            controller: _palpayPhoneController,
            label: _palpayIsMerchant ? 'رقم أو رمز التاجر' : 'رقم هاتف الصديق',
            hint: _palpayIsMerchant ? 'أدخل رقم التاجر' : '05xxxxxxxx',
            icon: Icons.phone_android_rounded,
            maxLength: 10,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildModernInputField(
                  controller: _palpayPinController,
                  label: 'الرمز السري',
                  hint: '* * * *',
                  isPassword: true,
                  icon: Icons.lock_outline_rounded,
                  maxLength: 4,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildModernInputField(
                  controller: _palpayAmountController,
                  label: 'المبلغ (شيكل)',
                  hint: '0.00',
                  icon: Icons.payments_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2563EB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              onPressed: _processPalPay,
              icon: const Icon(
                Icons.phone_forwarded_rounded,
                size: 18,
              ),
              label: const Text(
                'فتح شاشة الاتصال',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildJawwalPayCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                onPressed: _clearJawwalFields,
                icon: const Icon(
                  Icons.refresh_rounded,
                  color: Color(0xFF94A3B8),
                  size: 20,
                ),
                tooltip: 'مسح الحقول',
              ),
              Row(
                children: [
                  const Text(
                    'خدمة Jawwal Pay',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _buildServiceLogo(
                    imagePath: 'assets/images/jawwalpay.png',
                    backgroundColor: const Color(0xFFF0FDF4),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildModernToggle(
            isMerchant: _jawwalIsMerchant,
            activeColor: const Color(0xFF16A34A),
            onChanged: (val) {
              setState(() {
                _jawwalIsMerchant = val;
              });
            },
          ),
          const SizedBox(height: 16),
          _buildModernInputField(
            controller: _jawwalPhoneController,
            label: _jawwalIsMerchant ? 'رقم أو رمز التاجر' : 'رقم جوال الصديق',
            hint: _jawwalIsMerchant ? 'أدخل رقم التاجر' : '059xxxxxxx',
            icon: Icons.phone_android_rounded,
            maxLength: 10,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildModernInputField(
                  controller: _jawwalPinController,
                  label: 'الرمز السري',
                  hint: '* * * *',
                  isPassword: true,
                  icon: Icons.lock_outline_rounded,
                  maxLength: 4,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildModernInputField(
                  controller: _jawwalAmountController,
                  label: 'المبلغ',
                  hint: '0.00',
                  icon: Icons.payments_outlined,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF16A34A),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              onPressed: _processJawwalPay,
              icon: const Icon(
                Icons.phone_forwarded_rounded,
                size: 18,
              ),
              label: const Text(
                'فتح شاشة الاتصال',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServiceLogo({
    required String imagePath,
    required Color backgroundColor,
  }) {
    bool isPalPay = imagePath.contains('palpay');
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Icon(
        isPalPay
            ? Icons.account_balance_wallet_rounded
            : Icons.phone_android_rounded,
        color: isPalPay ? const Color(0xFF2563EB) : const Color(0xFF16A34A),
        size: 26,
      ),
    );
  }

  Widget _buildRecentTransactionsCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.history_rounded,
                    color: Color(0xFF64748B),
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'سجل آخر 5 حركات',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  if (_recentTransactions.isNotEmpty)
                    InkWell(
                      onTap: _clearTransactions,
                      child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(
                          Icons.delete_outline_rounded,
                          color: Colors.redAccent,
                          size: 18,
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    '${_recentTransactions.length} / 5',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const Divider(height: 20),
          _recentTransactions.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(10),
                  child: Center(
                    child: Text(
                      'لا توجد حركات مسجلة حالياً',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        color: Color(0xFF94A3B8),
                        fontSize: 13,
                      ),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _recentTransactions.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final tx = _recentTransactions[index];
                    final String serviceName = tx['service'] ?? '';
                    final bool isPalPay = serviceName.contains('PalPay');

                    return InkWell(
                      onTap: () => _fillFieldsFromTransaction(tx),
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: isPalPay
                                  ? const Color(0xFFEFF6FF)
                                  : const Color(0xFFF0FDF4),
                              child: Icon(
                                isPalPay
                                    ? Icons.account_balance_wallet_rounded
                                    : Icons.phone_android_rounded,
                                color: isPalPay
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF16A34A),
                                size: 18,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${tx['service']} - ${tx['phone']}',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                    ),
                                  ),
                                  Text(
                                    'الساعة: ${tx['time']} (اضغط للتعبئة)',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 10,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Text(
                              '${tx['amount']} ₪',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: isPalPay
                                    ? const Color(0xFF2563EB)
                                    : const Color(0xFF16A34A),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ],
      ),
    );
  }

  Widget _buildModernInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool isPassword = false,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            right: 4,
            bottom: 4,
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 11,
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFE2E8F0),
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              if (maxLength != null)
                LengthLimitingTextInputFormatter(maxLength),
            ],
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
            decoration: InputDecoration(
              counterText: '',
              prefixIcon: Icon(
                icon,
                color: const Color(0xFF94A3B8),
                size: 18,
              ),
              hintText: hint,
              hintStyle: const TextStyle(
                fontFamily: 'Cairo',
                color: Color(0xFF94A3B8),
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                vertical: 12,
                horizontal: 16,
              ),
            ),
          ),
        ),
      ],
    );
  }
}