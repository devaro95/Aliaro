import Foundation

/// Balance maths shared by the live Finances screen and archives.
enum FinanceBalances {
    /// Net balance for each member, splitting every expense/income
    /// equally among everyone: positive = owed to them, negative = owes the group.
    static func balances(expenses: [Expense], members: [FamilyMember]) -> [UUID: Double] {
        guard members.count > 1 else { return [:] }
        let n = Double(members.count)
        var result: [UUID: Double] = [:]
        for member in members { result[member.id] = 0 }
        for expense in expenses {
            let share = expense.amount / n
            let sign: Double = expense.isIncome ? -1 : 1
            for member in members {
                if member.id == expense.personID {
                    result[member.id, default: 0] += sign * (expense.amount - share)
                } else {
                    result[member.id, default: 0] -= sign * share
                }
            }
        }
        return result
    }

    /// Pairs debtors with creditors to settle all balances with the
    /// fewest possible transfers.
    static func settlements(expenses: [Expense], members: [FamilyMember]) -> [(from: FamilyMember, to: FamilyMember, amount: Double)] {
        let balances = balances(expenses: expenses, members: members)
        var creditors: [(FamilyMember, Double)] = []
        var debtors: [(FamilyMember, Double)] = []
        for member in members {
            let balance = balances[member.id] ?? 0
            if balance > 0.01 { creditors.append((member, balance)) }
            else if balance < -0.01 { debtors.append((member, -balance)) }
        }
        creditors.sort { $0.1 > $1.1 }
        debtors.sort { $0.1 > $1.1 }

        var result: [(from: FamilyMember, to: FamilyMember, amount: Double)] = []
        var i = 0, j = 0
        while i < debtors.count, j < creditors.count {
            let amount = min(debtors[i].1, creditors[j].1)
            result.append((from: debtors[i].0, to: creditors[j].0, amount: amount))
            debtors[i].1 -= amount
            creditors[j].1 -= amount
            if debtors[i].1 < 0.01 { i += 1 }
            if creditors[j].1 < 0.01 { j += 1 }
        }
        return result
    }
}
