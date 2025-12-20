
import 'dart:convert';

enum ExpenseCategory { Food, Transport, Stay, Fun, Shopping, Bills, Other }

class Expense {
  final String id;
  final String date;
  final String person;
  final double amount;
  final ExpenseCategory category;
  final String remarks;

  Expense({
    required this.id,
    required this.date,
    required this.person,
    required this.amount,
    required this.category,
    this.remarks = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': date,
      'person': person,
      'amount': amount,
      'category': category.toString().split('.').last,
      'remarks': remarks,
    };
  }

  factory Expense.fromJson(Map<String, dynamic> json) {
    return Expense(
      id: json['id'],
      date: json['date'],
      person: json['person'],
      amount: (json['amount'] as num).toDouble(),
      category: ExpenseCategory.values.firstWhere(
        (e) => e.toString().split('.').last == json['category'],
        orElse: () => ExpenseCategory.Other,
      ),
      remarks: json['remarks'] ?? '',
    );
  }
}

class Settlement {
  final String from;
  final String to;
  final double amount;

  Settlement({required this.from, required this.to, required this.amount});
}

class PersonBalance {
  final String name;
  final double totalPaid;
  final double balance;

  PersonBalance({required this.name, required this.totalPaid, required this.balance});
}

class AppSummary {
  final double totalExpense;
  final double averagePerPerson;
  final List<PersonBalance> personBalances;
  final List<Settlement> settlements;

  AppSummary({
    required this.totalExpense,
    required this.averagePerPerson,
    required this.personBalances,
    required this.settlements,
  });
}
