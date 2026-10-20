part of 'ledger.dart';

class Wallet {
  const Wallet({
    required this.id,
    required this.label,
    this.icon = 'wallet',
    this.color = 'plum',
    this.archived = false,
    this.removed = false,
  });
  const Wallet.reference(this.id)
    : label = id,
      icon = 'wallet',
      color = 'plum',
      archived = false,
      removed = false;
  static const cash = Wallet(id: 'cash', label: 'Cash', icon: 'cash');
  static const gcash = Wallet(
    id: 'gcash',
    label: 'GCash',
    icon: 'phone',
    color: 'blue',
  );
  static const values = [cash, gcash];
  final String id, label, icon, color;
  final bool archived, removed;
  String get name => id;
  Wallet copy({
    String? label,
    String? icon,
    String? color,
    bool? archived,
    bool? removed,
  }) => Wallet(
    id: id,
    label: label ?? this.label,
    icon: icon ?? this.icon,
    color: color ?? this.color,
    archived: archived ?? this.archived,
    removed: removed ?? this.removed,
  );
  @override
  bool operator ==(Object other) => other is Wallet && id == other.id;
  @override
  int get hashCode => id.hashCode;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': label,
    'icon': icon,
    'color': color,
    'archived': archived,
    'removed': removed,
  };
  factory Wallet.fromJson(dynamic value) {
    final m = object(value);
    final label = stringField(m, 'name', max: 30).trim();
    final icon = stringField(m, 'icon', max: 20),
        color = stringField(m, 'color', max: 20);
    if (boolField(m, 'removed', fallback: false) && !boolField(m, 'archived') ||
        label.isEmpty ||
        !walletIcons.contains(icon) ||
        !walletColors.contains(color)) {
      throw const LedgerException(
        'A wallet has an invalid name, icon or color.',
      );
    }
    return Wallet(
      id: idField(m, 'id'),
      label: label,
      icon: icon,
      color: color,
      archived: boolField(m, 'archived'),
      removed: boolField(m, 'removed', fallback: false),
    );
  }
}

const walletIcons = ['cash', 'phone', 'card', 'bank', 'wallet'];
const walletColors = ['plum', 'blue', 'green', 'amber', 'rose', 'slate'];

String entryAction(EntryKind kind) =>
    kind == EntryKind.income ? 'Received in' : 'Paid with';
