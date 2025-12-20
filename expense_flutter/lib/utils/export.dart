
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' as excel_pkg;
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
  var excel = excel_pkg.Excel.createExcel();
  
  // Sheet 1: Expenses
  excel_pkg.Sheet sheet1 = excel['Expenses'];
  sheet1.appendRow(['Date', 'Person', 'Category', 'Amount', 'Remarks'].map((e) => excel_pkg.TextCellValue(e)).toList());
  for (var e in expenses) {
    sheet1.appendRow([
        excel_pkg.TextCellValue(e.date), 
        excel_pkg.TextCellValue(e.person), 
        excel_pkg.TextCellValue(e.category.name), 
        excel_pkg.DoubleCellValue(e.amount), 
        excel_pkg.TextCellValue(e.remarks)
    ]);
  }

  // Sheet 2: Summary
  excel_pkg.Sheet sheet2 = excel['Summary'];
  sheet2.appendRow([excel_pkg.TextCellValue('Total'), excel_pkg.DoubleCellValue(summary.totalExpense)]);
  sheet2.appendRow([excel_pkg.TextCellValue('Avg Per Person'), excel_pkg.DoubleCellValue(summary.averagePerPerson)]);
  sheet2.appendRow([]);
  sheet2.appendRow([excel_pkg.TextCellValue('Settlements')]);
  for (var s in summary.settlements) {
    sheet2.appendRow([excel_pkg.TextCellValue(s.from), excel_pkg.TextCellValue('pays'), excel_pkg.TextCellValue(s.to), excel_pkg.DoubleCellValue(s.amount)]);
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
