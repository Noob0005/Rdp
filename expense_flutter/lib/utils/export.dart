
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import '../models/expense_model.dart';

Future<void> exportCSV(List<Expense> expenses) async {
  final header = "Date,Person,Category,Amount,Remarks";
  final rows = expenses.map((e) => "${e.date},${e.person},${e.category.name},${e.amount},${e.remarks}").join("\n");
  final content = "$header\n$rows";

  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/settler_export.csv');
  await file.writeAsString(content);
  
  await Share.shareXFiles([XFile(file.path)], text: 'Settler CSV Export');
}

Future<void> exportExcel(List<Expense> expenses, AppSummary summary) async {
  var excel = Excel.createExcel();
  
  // Sheet 1: Expenses
  Sheet sheet1 = excel['Expenses'];
  sheet1.appendRow(['Date', 'Person', 'Category', 'Amount', 'Remarks'].map((e) => TextCellValue(e)).toList());
  for (var e in expenses) {
    sheet1.appendRow([
        TextCellValue(e.date), 
        TextCellValue(e.person), 
        TextCellValue(e.category.name), 
        DoubleCellValue(e.amount), 
        TextCellValue(e.remarks)
    ]);
  }

  // Sheet 2: Summary
  Sheet sheet2 = excel['Summary'];
  sheet2.appendRow([TextCellValue('Total'), DoubleCellValue(summary.totalExpense)]);
  sheet2.appendRow([TextCellValue('Avg Per Person'), DoubleCellValue(summary.averagePerPerson)]);
  sheet2.appendRow([]);
  sheet2.appendRow([TextCellValue('Settlements')]);
  for (var s in summary.settlements) {
    sheet2.appendRow([TextCellValue(s.from), TextCellValue('pays'), TextCellValue(s.to), DoubleCellValue(s.amount)]);
  }

  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/settler_report.xlsx');
  final bytes = excel.save();
  if (bytes != null) {
      await file.writeAsBytes(bytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Settler Excel Report');
  }
}

Future<void> exportPDF(List<Expense> expenses, AppSummary summary) async {
  final pdf = pw.Document();

  pdf.addPage(
    pw.MultiPage(
      build: (context) => [
        pw.Header(level: 0, child: pw.Text('Settler Report', style: pw.TextStyle(fontSize: 24, fontWeight: pw.FontWeight.bold))),
        pw.SizedBox(height: 20),
        pw.Text('Total Expense: ${summary.totalExpense.toStringAsFixed(2)}'),
        pw.Text('Average Per Person: ${summary.averagePerPerson.toStringAsFixed(2)}'),
        pw.Divider(),
        pw.Text('Settlements:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
        ...summary.settlements.map((s) => pw.Bullet(text: '${s.from} pays ${s.to}: ${s.amount}')),
        pw.Divider(),
        pw.Table.fromTextArray(
          headers: ['Date', 'Person', 'Category', 'Amount'],
          data: expenses.map((e) => [e.date, e.person, e.category.name, e.amount.toString()]).toList(),
        ),
      ],
    ),
  );

  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/settler_report.pdf');
  await file.writeAsBytes(await pdf.save());
  await Share.shareXFiles([XFile(file.path)], text: 'Settler PDF Report');
}
