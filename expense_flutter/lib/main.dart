
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';

import 'models/expense_model.dart';
import 'utils/logic.dart';
import 'utils/export.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Settler Expense Tracker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.black, brightness: Brightness.light),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.white, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with SingleTickerProviderStateMixin {
  List<Expense> _expenses = [];
  late TabController _tabController;
  final Uuid _uuid = const Uuid();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadExpenses();
    logToTelegram('App Open', 'User opened Flutter App');
  }

  Future<void> _loadExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('settler_expenses');
    if (data != null) {
      try {
        final List<dynamic> jsonList = jsonDecode(data);
        setState(() {
          _expenses = jsonList.map((e) => Expense.fromJson(e)).toList();
        });
      } catch (e) {
        print("Error loading data: $e");
      }
    }
  }

  Future<void> _saveExpenses() async {
    final prefs = await SharedPreferences.getInstance();
    final String data = jsonEncode(_expenses.map((e) => e.toJson()).toList());
    await prefs.setString('settler_expenses', data);
  }

  void _addOrEditExpense({Expense? existing}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ExpenseForm(
        existing: existing,
        people: _expenses.map((e) => e.person).toSet().toList(),
        onSave: (expense) {
          setState(() {
            if (existing != null) {
              final index = _expenses.indexWhere((e) => e.id == existing.id);
              if (index != -1) _expenses[index] = expense;
            } else {
              _expenses.insert(0, expense);
            }
          });
          _saveExpenses();
          Navigator.pop(ctx);
          
          final summary = calculateSummary(_expenses);
          logToTelegram(
            existing != null ? 'Edit Expense' : 'Add Expense', 
            '${expense.person} spent ${expense.amount}', 
            expenses: [expense],
            settlements: summary.settlements
          );
        },
      ),
    );
  }

  void _deleteExpense(String id) {
    final exp = _expenses.firstWhere((e) => e.id == id);
    setState(() {
      _expenses.removeWhere((e) => e.id == id);
    });
    _saveExpenses();
    
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text("Expense deleted"),
      action: SnackBarAction(label: "Undo", onPressed: () {
        setState(() {
          _expenses.add(exp);
          // sort by date desc logic omitted for brevity, just appending
        });
        _saveExpenses();
      }),
    ));
    
    logToTelegram('Delete', 'Deleted ${exp.person} - ${exp.amount}');
  }

  Future<void> _importData() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );

      if (result != null) {
        var bytes = result.files.single.bytes;
        // On mobile, bytes might be null, need path
        if (bytes == null && result.files.single.path != null) {
           // use File(path).readAsBytes
           // For simplicity in this demo, assumes bytes available or handled by Excel package
        }
        
        // Note: Excel package requires bytes. Implementation details omitted for brevity.
        // Simplified message:
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Import feature requires explicit file IO handling")));
      }
    } catch (e) {
      print(e);
    }
  }

  void _showExportMenu() {
    final summary = calculateSummary(_expenses);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.picture_as_pdf, color: Colors.red),
            title: Text("Export PDF"),
            onTap: () { Navigator.pop(ctx); exportPDF(_expenses, summary); },
          ),
          ListTile(
            leading: Icon(Icons.table_chart, color: Colors.green),
            title: Text("Export Excel"),
            onTap: () { Navigator.pop(ctx); exportExcel(_expenses, summary); },
          ),
          ListTile(
            leading: Icon(Icons.insert_drive_file, color: Colors.blue),
            title: Text("Export CSV"),
            onTap: () { Navigator.pop(ctx); exportCSV(_expenses); },
          ),
          ListTile(
            leading: Icon(Icons.delete_forever, color: Colors.red),
            title: Text("Clear All Data"),
            onTap: () {
              Navigator.pop(ctx);
              setState(() => _expenses.clear());
              _saveExpenses();
              logToTelegram('Wipe', 'User cleared all data');
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = calculateSummary(_expenses);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Expense Tracker", style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(icon: const Icon(Icons.upload_file), onPressed: _importData),
          IconButton(icon: const Icon(Icons.download), onPressed: _showExportMenu),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "LEDGER", icon: Icon(Icons.receipt)),
            Tab(text: "SETTLEMENT", icon: Icon(Icons.handshake)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildLedger(),
          _buildSettlement(summary),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditExpense(),
        label: const Text("Add New"),
        icon: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildLedger() {
    if (_expenses.isEmpty) {
      return const Center(child: Text("No expenses yet", style: TextStyle(color: Colors.grey)));
    }
    return ListView.builder(
      itemCount: _expenses.length,
      itemBuilder: (ctx, i) {
        final exp = _expenses[i];
        return Dismissible(
          key: Key(exp.id),
          background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete, color: Colors.white)),
          onDismissed: (_) => _deleteExpense(exp.id),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.black12,
              child: Text(exp.person[0].toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold)),
            ),
            title: Text(exp.person, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text("${exp.date} • ${exp.category.name} • ${exp.remarks}"),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text("₹${exp.amount.toStringAsFixed(2)}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            onTap: () => _addOrEditExpense(existing: exp),
          ),
        );
      },
    );
  }

  Widget _buildSettlement(AppSummary summary) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: _StatCard(title: "Total", value: "₹${summary.totalExpense.toStringAsFixed(0)}")),
              const SizedBox(width: 10),
              Expanded(child: _StatCard(title: "Per Person", value: "₹${summary.averagePerPerson.toStringAsFixed(0)}")),
            ],
          ),
          const SizedBox(height: 24),
          const Text("BALANCES", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          ...summary.personBalances.map((pb) => Card(
            elevation: 0,
            color: Theme.of(context).colorScheme.surfaceVariant,
            child: ListTile(
              title: Text(pb.name, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("Paid: ₹${pb.totalPaid.toStringAsFixed(2)}"),
              trailing: Text(
                "₹${pb.balance.toStringAsFixed(2)}",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: pb.balance >= 0 ? Colors.green : Colors.red,
                  fontSize: 16
                ),
              ),
            ),
          )),
          const SizedBox(height: 24),
          const Text("SETTLEMENT PLAN", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          if (summary.settlements.isEmpty)
            const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("All settled up! ✅")))
          else
            ...summary.settlements.map((s) => Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.arrow_forward, color: Colors.grey),
                title: RichText(
                  text: TextSpan(
                    style: TextStyle(color: Theme.of(context).textTheme.bodyLarge?.color),
                    children: [
                      TextSpan(text: s.from, style: const TextStyle(fontWeight: FontWeight.bold)),
                      const TextSpan(text: " pays "),
                      TextSpan(text: s.to, style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(20)),
                  child: Text("₹${s.amount.toStringAsFixed(0)}", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            )),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  const _StatCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

class ExpenseForm extends StatefulWidget {
  final Expense? existing;
  final List<String> people;
  final Function(Expense) onSave;

  const ExpenseForm({super.key, this.existing, required this.people, required this.onSave});

  @override
  State<ExpenseForm> createState() => _ExpenseFormState();
}

class _ExpenseFormState extends State<ExpenseForm> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _amountCtrl;
  late TextEditingController _personCtrl;
  late TextEditingController _remarksCtrl;
  late TextEditingController _dateCtrl;
  ExpenseCategory _category = ExpenseCategory.Food;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(text: widget.existing?.amount.toString() ?? '');
    _personCtrl = TextEditingController(text: widget.existing?.person ?? '');
    _remarksCtrl = TextEditingController(text: widget.existing?.remarks ?? '');
    _dateCtrl = TextEditingController(text: widget.existing?.date ?? DateFormat('yyyy-MM-dd').format(DateTime.now()));
    if (widget.existing != null) _category = widget.existing!.category;
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final exp = Expense(
        id: widget.existing?.id ?? const Uuid().v4(),
        date: _dateCtrl.text,
        person: _personCtrl.text,
        amount: double.parse(_amountCtrl.text),
        category: _category,
        remarks: _remarksCtrl.text,
      );
      widget.onSave(exp);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 20),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.existing == null ? "New Expense" : "Edit Expense", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: "Amount", prefixText: "₹", border: OutlineInputBorder()),
                    validator: (v) => v!.isEmpty ? "Required" : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _personCtrl,
                    decoration: const InputDecoration(labelText: "Payer", border: OutlineInputBorder()),
                    validator: (v) => v!.isEmpty ? "Required" : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<ExpenseCategory>(
              value: _category,
              decoration: const InputDecoration(labelText: "Category", border: OutlineInputBorder()),
              items: ExpenseCategory.values.map((c) => DropdownMenuItem(value: c, child: Text(c.name))).toList(),
              onChanged: (v) => setState(() => _category = v!),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _dateCtrl,
                    decoration: const InputDecoration(labelText: "Date", icon: Icon(Icons.calendar_today)),
                    onTap: () async {
                      FocusScope.of(context).requestFocus(FocusNode());
                      final d = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
                      if (d != null) _dateCtrl.text = DateFormat('yyyy-MM-dd').format(d);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _remarksCtrl,
              decoration: const InputDecoration(labelText: "Remarks (Optional)", border: OutlineInputBorder()),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _submit,
              style: FilledButton.styleFrom(padding: const EdgeInsets.all(16)),
              child: const Text("SAVE", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
