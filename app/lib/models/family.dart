class Family {
  const Family({required this.id, required this.name, required this.inviteCode});

  final String id;
  final String name;
  final String inviteCode;

  factory Family.fromJson(Map<String, dynamic> json) => Family(
        id: json['id'] as String,
        name: json['name'] as String,
        inviteCode: json['invite_code'] as String,
      );
}

/// A person on the family without an account — a relation to the baby (Dad, Mum, ...)
/// and a name, to stamp records with.
class Caregiver {
  const Caregiver({required this.id, required this.name, this.relation});

  final String id;
  final String name;
  final String? relation;

  factory Caregiver.fromJson(Map<String, dynamic> json) => Caregiver(
        id: json['id'] as String,
        name: json['name'] as String,
        relation: json['relation'] as String?,
      );
}

class Baby {
  const Baby({
    required this.id,
    required this.familyId,
    required this.name,
    this.nicknames = const [],
    this.birthdate,
    this.sex,
  });

  final String id;
  final String familyId;
  final String name;
  final List<String> nicknames;
  final DateTime? birthdate;
  final String? sex;

  factory Baby.fromJson(Map<String, dynamic> json) => Baby(
        id: json['id'] as String,
        familyId: json['family_id'] as String,
        name: json['name'] as String,
        nicknames:
            (json['nicknames'] as List?)?.cast<String>() ?? const <String>[],
        birthdate: json['birthdate'] == null
            ? null
            : DateTime.parse(json['birthdate'] as String),
        sex: json['sex'] as String?,
      );
}
