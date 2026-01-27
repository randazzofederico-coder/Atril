// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $FoldersTableTable extends FoldersTable
    with TableInfo<$FoldersTableTable, FoldersTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FoldersTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _parentIdMeta =
      const VerificationMeta('parentId');
  @override
  late final GeneratedColumn<String> parentId = GeneratedColumn<String>(
      'parent_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES folders_table (id)'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _positionMeta =
      const VerificationMeta('position');
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
      'position', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, parentId, name, position, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'folders_table';
  @override
  VerificationContext validateIntegrity(Insertable<FoldersTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('parent_id')) {
      context.handle(_parentIdMeta,
          parentId.isAcceptableOrUnknown(data['parent_id']!, _parentIdMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('position')) {
      context.handle(_positionMeta,
          position.isAcceptableOrUnknown(data['position']!, _positionMeta));
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FoldersTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FoldersTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      parentId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}parent_id']),
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      position: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $FoldersTableTable createAlias(String alias) {
    return $FoldersTableTable(attachedDatabase, alias);
  }
}

class FoldersTableData extends DataClass
    implements Insertable<FoldersTableData> {
  final String id;
  final String? parentId;
  final String name;
  final int position;
  final int createdAt;
  final int updatedAt;
  const FoldersTableData(
      {required this.id,
      this.parentId,
      required this.name,
      required this.position,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    if (!nullToAbsent || parentId != null) {
      map['parent_id'] = Variable<String>(parentId);
    }
    map['name'] = Variable<String>(name);
    map['position'] = Variable<int>(position);
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  FoldersTableCompanion toCompanion(bool nullToAbsent) {
    return FoldersTableCompanion(
      id: Value(id),
      parentId: parentId == null && nullToAbsent
          ? const Value.absent()
          : Value(parentId),
      name: Value(name),
      position: Value(position),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory FoldersTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FoldersTableData(
      id: serializer.fromJson<String>(json['id']),
      parentId: serializer.fromJson<String?>(json['parentId']),
      name: serializer.fromJson<String>(json['name']),
      position: serializer.fromJson<int>(json['position']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'parentId': serializer.toJson<String?>(parentId),
      'name': serializer.toJson<String>(name),
      'position': serializer.toJson<int>(position),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  FoldersTableData copyWith(
          {String? id,
          Value<String?> parentId = const Value.absent(),
          String? name,
          int? position,
          int? createdAt,
          int? updatedAt}) =>
      FoldersTableData(
        id: id ?? this.id,
        parentId: parentId.present ? parentId.value : this.parentId,
        name: name ?? this.name,
        position: position ?? this.position,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  FoldersTableData copyWithCompanion(FoldersTableCompanion data) {
    return FoldersTableData(
      id: data.id.present ? data.id.value : this.id,
      parentId: data.parentId.present ? data.parentId.value : this.parentId,
      name: data.name.present ? data.name.value : this.name,
      position: data.position.present ? data.position.value : this.position,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FoldersTableData(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, parentId, name, position, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FoldersTableData &&
          other.id == this.id &&
          other.parentId == this.parentId &&
          other.name == this.name &&
          other.position == this.position &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class FoldersTableCompanion extends UpdateCompanion<FoldersTableData> {
  final Value<String> id;
  final Value<String?> parentId;
  final Value<String> name;
  final Value<int> position;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const FoldersTableCompanion({
    this.id = const Value.absent(),
    this.parentId = const Value.absent(),
    this.name = const Value.absent(),
    this.position = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FoldersTableCompanion.insert({
    required String id,
    this.parentId = const Value.absent(),
    required String name,
    required int position,
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        position = Value(position),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<FoldersTableData> custom({
    Expression<String>? id,
    Expression<String>? parentId,
    Expression<String>? name,
    Expression<int>? position,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (parentId != null) 'parent_id': parentId,
      if (name != null) 'name': name,
      if (position != null) 'position': position,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FoldersTableCompanion copyWith(
      {Value<String>? id,
      Value<String?>? parentId,
      Value<String>? name,
      Value<int>? position,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return FoldersTableCompanion(
      id: id ?? this.id,
      parentId: parentId ?? this.parentId,
      name: name ?? this.name,
      position: position ?? this.position,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (parentId.present) {
      map['parent_id'] = Variable<String>(parentId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FoldersTableCompanion(')
          ..write('id: $id, ')
          ..write('parentId: $parentId, ')
          ..write('name: $name, ')
          ..write('position: $position, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DocsTableTable extends DocsTable
    with TableInfo<$DocsTableTable, DocsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _displayNameMeta =
      const VerificationMeta('displayName');
  @override
  late final GeneratedColumn<String> displayName = GeneratedColumn<String>(
      'display_name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _authorMeta = const VerificationMeta('author');
  @override
  late final GeneratedColumn<String> author = GeneratedColumn<String>(
      'author', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _internalRelPathMeta =
      const VerificationMeta('internalRelPath');
  @override
  late final GeneratedColumn<String> internalRelPath = GeneratedColumn<String>(
      'internal_rel_path', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _folderIdMeta =
      const VerificationMeta('folderId');
  @override
  late final GeneratedColumn<String> folderId = GeneratedColumn<String>(
      'folder_id', aliasedName, true,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES folders_table (id)'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        displayName,
        author,
        internalRelPath,
        folderId,
        createdAt,
        updatedAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'docs_table';
  @override
  VerificationContext validateIntegrity(Insertable<DocsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('display_name')) {
      context.handle(
          _displayNameMeta,
          displayName.isAcceptableOrUnknown(
              data['display_name']!, _displayNameMeta));
    } else if (isInserting) {
      context.missing(_displayNameMeta);
    }
    if (data.containsKey('author')) {
      context.handle(_authorMeta,
          author.isAcceptableOrUnknown(data['author']!, _authorMeta));
    }
    if (data.containsKey('internal_rel_path')) {
      context.handle(
          _internalRelPathMeta,
          internalRelPath.isAcceptableOrUnknown(
              data['internal_rel_path']!, _internalRelPathMeta));
    } else if (isInserting) {
      context.missing(_internalRelPathMeta);
    }
    if (data.containsKey('folder_id')) {
      context.handle(_folderIdMeta,
          folderId.isAcceptableOrUnknown(data['folder_id']!, _folderIdMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DocsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DocsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      displayName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}display_name'])!,
      author: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}author']),
      internalRelPath: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}internal_rel_path'])!,
      folderId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}folder_id']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $DocsTableTable createAlias(String alias) {
    return $DocsTableTable(attachedDatabase, alias);
  }
}

class DocsTableData extends DataClass implements Insertable<DocsTableData> {
  final String id;
  final String displayName;
  final String? author;
  final String internalRelPath;
  final String? folderId;
  final int createdAt;
  final int updatedAt;
  const DocsTableData(
      {required this.id,
      required this.displayName,
      this.author,
      required this.internalRelPath,
      this.folderId,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['display_name'] = Variable<String>(displayName);
    if (!nullToAbsent || author != null) {
      map['author'] = Variable<String>(author);
    }
    map['internal_rel_path'] = Variable<String>(internalRelPath);
    if (!nullToAbsent || folderId != null) {
      map['folder_id'] = Variable<String>(folderId);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  DocsTableCompanion toCompanion(bool nullToAbsent) {
    return DocsTableCompanion(
      id: Value(id),
      displayName: Value(displayName),
      author:
          author == null && nullToAbsent ? const Value.absent() : Value(author),
      internalRelPath: Value(internalRelPath),
      folderId: folderId == null && nullToAbsent
          ? const Value.absent()
          : Value(folderId),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DocsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DocsTableData(
      id: serializer.fromJson<String>(json['id']),
      displayName: serializer.fromJson<String>(json['displayName']),
      author: serializer.fromJson<String?>(json['author']),
      internalRelPath: serializer.fromJson<String>(json['internalRelPath']),
      folderId: serializer.fromJson<String?>(json['folderId']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'displayName': serializer.toJson<String>(displayName),
      'author': serializer.toJson<String?>(author),
      'internalRelPath': serializer.toJson<String>(internalRelPath),
      'folderId': serializer.toJson<String?>(folderId),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  DocsTableData copyWith(
          {String? id,
          String? displayName,
          Value<String?> author = const Value.absent(),
          String? internalRelPath,
          Value<String?> folderId = const Value.absent(),
          int? createdAt,
          int? updatedAt}) =>
      DocsTableData(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        author: author.present ? author.value : this.author,
        internalRelPath: internalRelPath ?? this.internalRelPath,
        folderId: folderId.present ? folderId.value : this.folderId,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  DocsTableData copyWithCompanion(DocsTableCompanion data) {
    return DocsTableData(
      id: data.id.present ? data.id.value : this.id,
      displayName:
          data.displayName.present ? data.displayName.value : this.displayName,
      author: data.author.present ? data.author.value : this.author,
      internalRelPath: data.internalRelPath.present
          ? data.internalRelPath.value
          : this.internalRelPath,
      folderId: data.folderId.present ? data.folderId.value : this.folderId,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DocsTableData(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('author: $author, ')
          ..write('internalRelPath: $internalRelPath, ')
          ..write('folderId: $folderId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, displayName, author, internalRelPath, folderId, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DocsTableData &&
          other.id == this.id &&
          other.displayName == this.displayName &&
          other.author == this.author &&
          other.internalRelPath == this.internalRelPath &&
          other.folderId == this.folderId &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DocsTableCompanion extends UpdateCompanion<DocsTableData> {
  final Value<String> id;
  final Value<String> displayName;
  final Value<String?> author;
  final Value<String> internalRelPath;
  final Value<String?> folderId;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const DocsTableCompanion({
    this.id = const Value.absent(),
    this.displayName = const Value.absent(),
    this.author = const Value.absent(),
    this.internalRelPath = const Value.absent(),
    this.folderId = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DocsTableCompanion.insert({
    required String id,
    required String displayName,
    this.author = const Value.absent(),
    required String internalRelPath,
    this.folderId = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        displayName = Value(displayName),
        internalRelPath = Value(internalRelPath),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<DocsTableData> custom({
    Expression<String>? id,
    Expression<String>? displayName,
    Expression<String>? author,
    Expression<String>? internalRelPath,
    Expression<String>? folderId,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (displayName != null) 'display_name': displayName,
      if (author != null) 'author': author,
      if (internalRelPath != null) 'internal_rel_path': internalRelPath,
      if (folderId != null) 'folder_id': folderId,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DocsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? displayName,
      Value<String?>? author,
      Value<String>? internalRelPath,
      Value<String?>? folderId,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return DocsTableCompanion(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      author: author ?? this.author,
      internalRelPath: internalRelPath ?? this.internalRelPath,
      folderId: folderId ?? this.folderId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (displayName.present) {
      map['display_name'] = Variable<String>(displayName.value);
    }
    if (author.present) {
      map['author'] = Variable<String>(author.value);
    }
    if (internalRelPath.present) {
      map['internal_rel_path'] = Variable<String>(internalRelPath.value);
    }
    if (folderId.present) {
      map['folder_id'] = Variable<String>(folderId.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocsTableCompanion(')
          ..write('id: $id, ')
          ..write('displayName: $displayName, ')
          ..write('author: $author, ')
          ..write('internalRelPath: $internalRelPath, ')
          ..write('folderId: $folderId, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SetlistsTableTable extends SetlistsTable
    with TableInfo<$SetlistsTableTable, SetlistsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SetlistsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
      'notes', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [id, name, notes, createdAt, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'setlists_table';
  @override
  VerificationContext validateIntegrity(Insertable<SetlistsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('notes')) {
      context.handle(
          _notesMeta, notes.isAcceptableOrUnknown(data['notes']!, _notesMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SetlistsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SetlistsTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      notes: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}notes']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $SetlistsTableTable createAlias(String alias) {
    return $SetlistsTableTable(attachedDatabase, alias);
  }
}

class SetlistsTableData extends DataClass
    implements Insertable<SetlistsTableData> {
  final String id;
  final String name;
  final String? notes;
  final int createdAt;
  final int updatedAt;
  const SetlistsTableData(
      {required this.id,
      required this.name,
      this.notes,
      required this.createdAt,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  SetlistsTableCompanion toCompanion(bool nullToAbsent) {
    return SetlistsTableCompanion(
      id: Value(id),
      name: Value(name),
      notes:
          notes == null && nullToAbsent ? const Value.absent() : Value(notes),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SetlistsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SetlistsTableData(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      notes: serializer.fromJson<String?>(json['notes']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'notes': serializer.toJson<String?>(notes),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  SetlistsTableData copyWith(
          {String? id,
          String? name,
          Value<String?> notes = const Value.absent(),
          int? createdAt,
          int? updatedAt}) =>
      SetlistsTableData(
        id: id ?? this.id,
        name: name ?? this.name,
        notes: notes.present ? notes.value : this.notes,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  SetlistsTableData copyWithCompanion(SetlistsTableCompanion data) {
    return SetlistsTableData(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      notes: data.notes.present ? data.notes.value : this.notes,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SetlistsTableData(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, notes, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SetlistsTableData &&
          other.id == this.id &&
          other.name == this.name &&
          other.notes == this.notes &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SetlistsTableCompanion extends UpdateCompanion<SetlistsTableData> {
  final Value<String> id;
  final Value<String> name;
  final Value<String?> notes;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const SetlistsTableCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.notes = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SetlistsTableCompanion.insert({
    required String id,
    required String name,
    this.notes = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        name = Value(name),
        createdAt = Value(createdAt),
        updatedAt = Value(updatedAt);
  static Insertable<SetlistsTableData> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? notes,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (notes != null) 'notes': notes,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SetlistsTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? name,
      Value<String?>? notes,
      Value<int>? createdAt,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return SetlistsTableCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SetlistsTableCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('notes: $notes, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SetlistItemsTableTable extends SetlistItemsTable
    with TableInfo<$SetlistItemsTableTable, SetlistItemsTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SetlistItemsTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _setlistIdMeta =
      const VerificationMeta('setlistId');
  @override
  late final GeneratedColumn<String> setlistId = GeneratedColumn<String>(
      'setlist_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES setlists_table (id)'));
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  @override
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
      'doc_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES docs_table (id)'));
  static const VerificationMeta _positionMeta =
      const VerificationMeta('position');
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
      'position', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [setlistId, docId, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'setlist_items_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<SetlistItemsTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('setlist_id')) {
      context.handle(_setlistIdMeta,
          setlistId.isAcceptableOrUnknown(data['setlist_id']!, _setlistIdMeta));
    } else if (isInserting) {
      context.missing(_setlistIdMeta);
    }
    if (data.containsKey('doc_id')) {
      context.handle(
          _docIdMeta, docId.isAcceptableOrUnknown(data['doc_id']!, _docIdMeta));
    } else if (isInserting) {
      context.missing(_docIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(_positionMeta,
          position.isAcceptableOrUnknown(data['position']!, _positionMeta));
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {setlistId, docId};
  @override
  SetlistItemsTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SetlistItemsTableData(
      setlistId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}setlist_id'])!,
      docId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}doc_id'])!,
      position: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}position'])!,
    );
  }

  @override
  $SetlistItemsTableTable createAlias(String alias) {
    return $SetlistItemsTableTable(attachedDatabase, alias);
  }
}

class SetlistItemsTableData extends DataClass
    implements Insertable<SetlistItemsTableData> {
  final String setlistId;
  final String docId;
  final int position;
  const SetlistItemsTableData(
      {required this.setlistId, required this.docId, required this.position});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['setlist_id'] = Variable<String>(setlistId);
    map['doc_id'] = Variable<String>(docId);
    map['position'] = Variable<int>(position);
    return map;
  }

  SetlistItemsTableCompanion toCompanion(bool nullToAbsent) {
    return SetlistItemsTableCompanion(
      setlistId: Value(setlistId),
      docId: Value(docId),
      position: Value(position),
    );
  }

  factory SetlistItemsTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SetlistItemsTableData(
      setlistId: serializer.fromJson<String>(json['setlistId']),
      docId: serializer.fromJson<String>(json['docId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'setlistId': serializer.toJson<String>(setlistId),
      'docId': serializer.toJson<String>(docId),
      'position': serializer.toJson<int>(position),
    };
  }

  SetlistItemsTableData copyWith(
          {String? setlistId, String? docId, int? position}) =>
      SetlistItemsTableData(
        setlistId: setlistId ?? this.setlistId,
        docId: docId ?? this.docId,
        position: position ?? this.position,
      );
  SetlistItemsTableData copyWithCompanion(SetlistItemsTableCompanion data) {
    return SetlistItemsTableData(
      setlistId: data.setlistId.present ? data.setlistId.value : this.setlistId,
      docId: data.docId.present ? data.docId.value : this.docId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SetlistItemsTableData(')
          ..write('setlistId: $setlistId, ')
          ..write('docId: $docId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(setlistId, docId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SetlistItemsTableData &&
          other.setlistId == this.setlistId &&
          other.docId == this.docId &&
          other.position == this.position);
}

class SetlistItemsTableCompanion
    extends UpdateCompanion<SetlistItemsTableData> {
  final Value<String> setlistId;
  final Value<String> docId;
  final Value<int> position;
  final Value<int> rowid;
  const SetlistItemsTableCompanion({
    this.setlistId = const Value.absent(),
    this.docId = const Value.absent(),
    this.position = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SetlistItemsTableCompanion.insert({
    required String setlistId,
    required String docId,
    required int position,
    this.rowid = const Value.absent(),
  })  : setlistId = Value(setlistId),
        docId = Value(docId),
        position = Value(position);
  static Insertable<SetlistItemsTableData> custom({
    Expression<String>? setlistId,
    Expression<String>? docId,
    Expression<int>? position,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (setlistId != null) 'setlist_id': setlistId,
      if (docId != null) 'doc_id': docId,
      if (position != null) 'position': position,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SetlistItemsTableCompanion copyWith(
      {Value<String>? setlistId,
      Value<String>? docId,
      Value<int>? position,
      Value<int>? rowid}) {
    return SetlistItemsTableCompanion(
      setlistId: setlistId ?? this.setlistId,
      docId: docId ?? this.docId,
      position: position ?? this.position,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (setlistId.present) {
      map['setlist_id'] = Variable<String>(setlistId.value);
    }
    if (docId.present) {
      map['doc_id'] = Variable<String>(docId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SetlistItemsTableCompanion(')
          ..write('setlistId: $setlistId, ')
          ..write('docId: $docId, ')
          ..write('position: $position, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $DocStateTableTable extends DocStateTable
    with TableInfo<$DocStateTableTable, DocStateTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DocStateTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  @override
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
      'doc_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES docs_table (id)'));
  static const VerificationMeta _lastPageMeta =
      const VerificationMeta('lastPage');
  @override
  late final GeneratedColumn<int> lastPage = GeneratedColumn<int>(
      'last_page', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [docId, lastPage, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'doc_state_table';
  @override
  VerificationContext validateIntegrity(Insertable<DocStateTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('doc_id')) {
      context.handle(
          _docIdMeta, docId.isAcceptableOrUnknown(data['doc_id']!, _docIdMeta));
    } else if (isInserting) {
      context.missing(_docIdMeta);
    }
    if (data.containsKey('last_page')) {
      context.handle(_lastPageMeta,
          lastPage.isAcceptableOrUnknown(data['last_page']!, _lastPageMeta));
    } else if (isInserting) {
      context.missing(_lastPageMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {docId};
  @override
  DocStateTableData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DocStateTableData(
      docId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}doc_id'])!,
      lastPage: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_page'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $DocStateTableTable createAlias(String alias) {
    return $DocStateTableTable(attachedDatabase, alias);
  }
}

class DocStateTableData extends DataClass
    implements Insertable<DocStateTableData> {
  final String docId;
  final int lastPage;
  final int updatedAt;
  const DocStateTableData(
      {required this.docId, required this.lastPage, required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['doc_id'] = Variable<String>(docId);
    map['last_page'] = Variable<int>(lastPage);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  DocStateTableCompanion toCompanion(bool nullToAbsent) {
    return DocStateTableCompanion(
      docId: Value(docId),
      lastPage: Value(lastPage),
      updatedAt: Value(updatedAt),
    );
  }

  factory DocStateTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DocStateTableData(
      docId: serializer.fromJson<String>(json['docId']),
      lastPage: serializer.fromJson<int>(json['lastPage']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'docId': serializer.toJson<String>(docId),
      'lastPage': serializer.toJson<int>(lastPage),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  DocStateTableData copyWith({String? docId, int? lastPage, int? updatedAt}) =>
      DocStateTableData(
        docId: docId ?? this.docId,
        lastPage: lastPage ?? this.lastPage,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  DocStateTableData copyWithCompanion(DocStateTableCompanion data) {
    return DocStateTableData(
      docId: data.docId.present ? data.docId.value : this.docId,
      lastPage: data.lastPage.present ? data.lastPage.value : this.lastPage,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DocStateTableData(')
          ..write('docId: $docId, ')
          ..write('lastPage: $lastPage, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(docId, lastPage, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DocStateTableData &&
          other.docId == this.docId &&
          other.lastPage == this.lastPage &&
          other.updatedAt == this.updatedAt);
}

class DocStateTableCompanion extends UpdateCompanion<DocStateTableData> {
  final Value<String> docId;
  final Value<int> lastPage;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const DocStateTableCompanion({
    this.docId = const Value.absent(),
    this.lastPage = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DocStateTableCompanion.insert({
    required String docId,
    required int lastPage,
    required int updatedAt,
    this.rowid = const Value.absent(),
  })  : docId = Value(docId),
        lastPage = Value(lastPage),
        updatedAt = Value(updatedAt);
  static Insertable<DocStateTableData> custom({
    Expression<String>? docId,
    Expression<int>? lastPage,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (docId != null) 'doc_id': docId,
      if (lastPage != null) 'last_page': lastPage,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DocStateTableCompanion copyWith(
      {Value<String>? docId,
      Value<int>? lastPage,
      Value<int>? updatedAt,
      Value<int>? rowid}) {
    return DocStateTableCompanion(
      docId: docId ?? this.docId,
      lastPage: lastPage ?? this.lastPage,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (docId.present) {
      map['doc_id'] = Variable<String>(docId.value);
    }
    if (lastPage.present) {
      map['last_page'] = Variable<int>(lastPage.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DocStateTableCompanion(')
          ..write('docId: $docId, ')
          ..write('lastPage: $lastPage, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AnnotationStrokesTableTable extends AnnotationStrokesTable
    with TableInfo<$AnnotationStrokesTableTable, AnnotationStrokesTableData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AnnotationStrokesTableTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
      'id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _docIdMeta = const VerificationMeta('docId');
  @override
  late final GeneratedColumn<String> docId = GeneratedColumn<String>(
      'doc_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _setlistIdMeta =
      const VerificationMeta('setlistId');
  @override
  late final GeneratedColumn<String> setlistId = GeneratedColumn<String>(
      'setlist_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _pageIndexMeta =
      const VerificationMeta('pageIndex');
  @override
  late final GeneratedColumn<int> pageIndex = GeneratedColumn<int>(
      'page_index', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  static const VerificationMeta _toolMeta = const VerificationMeta('tool');
  @override
  late final GeneratedColumn<String> tool = GeneratedColumn<String>(
      'tool', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _widthMeta = const VerificationMeta('width');
  @override
  late final GeneratedColumn<double> width = GeneratedColumn<double>(
      'width', aliasedName, false,
      type: DriftSqlType.double, requiredDuringInsert: true);
  static const VerificationMeta _pointsJsonMeta =
      const VerificationMeta('pointsJson');
  @override
  late final GeneratedColumn<String> pointsJson = GeneratedColumn<String>(
      'points_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
      'created_at', aliasedName, false,
      type: DriftSqlType.int, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns =>
      [id, docId, setlistId, pageIndex, tool, width, pointsJson, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'annotation_strokes_table';
  @override
  VerificationContext validateIntegrity(
      Insertable<AnnotationStrokesTableData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('doc_id')) {
      context.handle(
          _docIdMeta, docId.isAcceptableOrUnknown(data['doc_id']!, _docIdMeta));
    } else if (isInserting) {
      context.missing(_docIdMeta);
    }
    if (data.containsKey('setlist_id')) {
      context.handle(_setlistIdMeta,
          setlistId.isAcceptableOrUnknown(data['setlist_id']!, _setlistIdMeta));
    }
    if (data.containsKey('page_index')) {
      context.handle(_pageIndexMeta,
          pageIndex.isAcceptableOrUnknown(data['page_index']!, _pageIndexMeta));
    } else if (isInserting) {
      context.missing(_pageIndexMeta);
    }
    if (data.containsKey('tool')) {
      context.handle(
          _toolMeta, tool.isAcceptableOrUnknown(data['tool']!, _toolMeta));
    } else if (isInserting) {
      context.missing(_toolMeta);
    }
    if (data.containsKey('width')) {
      context.handle(
          _widthMeta, width.isAcceptableOrUnknown(data['width']!, _widthMeta));
    } else if (isInserting) {
      context.missing(_widthMeta);
    }
    if (data.containsKey('points_json')) {
      context.handle(
          _pointsJsonMeta,
          pointsJson.isAcceptableOrUnknown(
              data['points_json']!, _pointsJsonMeta));
    } else if (isInserting) {
      context.missing(_pointsJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AnnotationStrokesTableData map(Map<String, dynamic> data,
      {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AnnotationStrokesTableData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}id'])!,
      docId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}doc_id'])!,
      setlistId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}setlist_id']),
      pageIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}page_index'])!,
      tool: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}tool'])!,
      width: attachedDatabase.typeMapping
          .read(DriftSqlType.double, data['${effectivePrefix}width'])!,
      pointsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}points_json'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $AnnotationStrokesTableTable createAlias(String alias) {
    return $AnnotationStrokesTableTable(attachedDatabase, alias);
  }
}

class AnnotationStrokesTableData extends DataClass
    implements Insertable<AnnotationStrokesTableData> {
  final String id;
  final String docId;
  final String? setlistId;
  final int pageIndex;
  final String tool;
  final double width;
  final String pointsJson;
  final int createdAt;
  const AnnotationStrokesTableData(
      {required this.id,
      required this.docId,
      this.setlistId,
      required this.pageIndex,
      required this.tool,
      required this.width,
      required this.pointsJson,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['doc_id'] = Variable<String>(docId);
    if (!nullToAbsent || setlistId != null) {
      map['setlist_id'] = Variable<String>(setlistId);
    }
    map['page_index'] = Variable<int>(pageIndex);
    map['tool'] = Variable<String>(tool);
    map['width'] = Variable<double>(width);
    map['points_json'] = Variable<String>(pointsJson);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  AnnotationStrokesTableCompanion toCompanion(bool nullToAbsent) {
    return AnnotationStrokesTableCompanion(
      id: Value(id),
      docId: Value(docId),
      setlistId: setlistId == null && nullToAbsent
          ? const Value.absent()
          : Value(setlistId),
      pageIndex: Value(pageIndex),
      tool: Value(tool),
      width: Value(width),
      pointsJson: Value(pointsJson),
      createdAt: Value(createdAt),
    );
  }

  factory AnnotationStrokesTableData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AnnotationStrokesTableData(
      id: serializer.fromJson<String>(json['id']),
      docId: serializer.fromJson<String>(json['docId']),
      setlistId: serializer.fromJson<String?>(json['setlistId']),
      pageIndex: serializer.fromJson<int>(json['pageIndex']),
      tool: serializer.fromJson<String>(json['tool']),
      width: serializer.fromJson<double>(json['width']),
      pointsJson: serializer.fromJson<String>(json['pointsJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'docId': serializer.toJson<String>(docId),
      'setlistId': serializer.toJson<String?>(setlistId),
      'pageIndex': serializer.toJson<int>(pageIndex),
      'tool': serializer.toJson<String>(tool),
      'width': serializer.toJson<double>(width),
      'pointsJson': serializer.toJson<String>(pointsJson),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  AnnotationStrokesTableData copyWith(
          {String? id,
          String? docId,
          Value<String?> setlistId = const Value.absent(),
          int? pageIndex,
          String? tool,
          double? width,
          String? pointsJson,
          int? createdAt}) =>
      AnnotationStrokesTableData(
        id: id ?? this.id,
        docId: docId ?? this.docId,
        setlistId: setlistId.present ? setlistId.value : this.setlistId,
        pageIndex: pageIndex ?? this.pageIndex,
        tool: tool ?? this.tool,
        width: width ?? this.width,
        pointsJson: pointsJson ?? this.pointsJson,
        createdAt: createdAt ?? this.createdAt,
      );
  AnnotationStrokesTableData copyWithCompanion(
      AnnotationStrokesTableCompanion data) {
    return AnnotationStrokesTableData(
      id: data.id.present ? data.id.value : this.id,
      docId: data.docId.present ? data.docId.value : this.docId,
      setlistId: data.setlistId.present ? data.setlistId.value : this.setlistId,
      pageIndex: data.pageIndex.present ? data.pageIndex.value : this.pageIndex,
      tool: data.tool.present ? data.tool.value : this.tool,
      width: data.width.present ? data.width.value : this.width,
      pointsJson:
          data.pointsJson.present ? data.pointsJson.value : this.pointsJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AnnotationStrokesTableData(')
          ..write('id: $id, ')
          ..write('docId: $docId, ')
          ..write('setlistId: $setlistId, ')
          ..write('pageIndex: $pageIndex, ')
          ..write('tool: $tool, ')
          ..write('width: $width, ')
          ..write('pointsJson: $pointsJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id, docId, setlistId, pageIndex, tool, width, pointsJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AnnotationStrokesTableData &&
          other.id == this.id &&
          other.docId == this.docId &&
          other.setlistId == this.setlistId &&
          other.pageIndex == this.pageIndex &&
          other.tool == this.tool &&
          other.width == this.width &&
          other.pointsJson == this.pointsJson &&
          other.createdAt == this.createdAt);
}

class AnnotationStrokesTableCompanion
    extends UpdateCompanion<AnnotationStrokesTableData> {
  final Value<String> id;
  final Value<String> docId;
  final Value<String?> setlistId;
  final Value<int> pageIndex;
  final Value<String> tool;
  final Value<double> width;
  final Value<String> pointsJson;
  final Value<int> createdAt;
  final Value<int> rowid;
  const AnnotationStrokesTableCompanion({
    this.id = const Value.absent(),
    this.docId = const Value.absent(),
    this.setlistId = const Value.absent(),
    this.pageIndex = const Value.absent(),
    this.tool = const Value.absent(),
    this.width = const Value.absent(),
    this.pointsJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AnnotationStrokesTableCompanion.insert({
    required String id,
    required String docId,
    this.setlistId = const Value.absent(),
    required int pageIndex,
    required String tool,
    required double width,
    required String pointsJson,
    required int createdAt,
    this.rowid = const Value.absent(),
  })  : id = Value(id),
        docId = Value(docId),
        pageIndex = Value(pageIndex),
        tool = Value(tool),
        width = Value(width),
        pointsJson = Value(pointsJson),
        createdAt = Value(createdAt);
  static Insertable<AnnotationStrokesTableData> custom({
    Expression<String>? id,
    Expression<String>? docId,
    Expression<String>? setlistId,
    Expression<int>? pageIndex,
    Expression<String>? tool,
    Expression<double>? width,
    Expression<String>? pointsJson,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (docId != null) 'doc_id': docId,
      if (setlistId != null) 'setlist_id': setlistId,
      if (pageIndex != null) 'page_index': pageIndex,
      if (tool != null) 'tool': tool,
      if (width != null) 'width': width,
      if (pointsJson != null) 'points_json': pointsJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AnnotationStrokesTableCompanion copyWith(
      {Value<String>? id,
      Value<String>? docId,
      Value<String?>? setlistId,
      Value<int>? pageIndex,
      Value<String>? tool,
      Value<double>? width,
      Value<String>? pointsJson,
      Value<int>? createdAt,
      Value<int>? rowid}) {
    return AnnotationStrokesTableCompanion(
      id: id ?? this.id,
      docId: docId ?? this.docId,
      setlistId: setlistId ?? this.setlistId,
      pageIndex: pageIndex ?? this.pageIndex,
      tool: tool ?? this.tool,
      width: width ?? this.width,
      pointsJson: pointsJson ?? this.pointsJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (docId.present) {
      map['doc_id'] = Variable<String>(docId.value);
    }
    if (setlistId.present) {
      map['setlist_id'] = Variable<String>(setlistId.value);
    }
    if (pageIndex.present) {
      map['page_index'] = Variable<int>(pageIndex.value);
    }
    if (tool.present) {
      map['tool'] = Variable<String>(tool.value);
    }
    if (width.present) {
      map['width'] = Variable<double>(width.value);
    }
    if (pointsJson.present) {
      map['points_json'] = Variable<String>(pointsJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AnnotationStrokesTableCompanion(')
          ..write('id: $id, ')
          ..write('docId: $docId, ')
          ..write('setlistId: $setlistId, ')
          ..write('pageIndex: $pageIndex, ')
          ..write('tool: $tool, ')
          ..write('width: $width, ')
          ..write('pointsJson: $pointsJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $FoldersTableTable foldersTable = $FoldersTableTable(this);
  late final $DocsTableTable docsTable = $DocsTableTable(this);
  late final $SetlistsTableTable setlistsTable = $SetlistsTableTable(this);
  late final $SetlistItemsTableTable setlistItemsTable =
      $SetlistItemsTableTable(this);
  late final $DocStateTableTable docStateTable = $DocStateTableTable(this);
  late final $AnnotationStrokesTableTable annotationStrokesTable =
      $AnnotationStrokesTableTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
        foldersTable,
        docsTable,
        setlistsTable,
        setlistItemsTable,
        docStateTable,
        annotationStrokesTable
      ];
}

typedef $$FoldersTableTableCreateCompanionBuilder = FoldersTableCompanion
    Function({
  required String id,
  Value<String?> parentId,
  required String name,
  required int position,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$FoldersTableTableUpdateCompanionBuilder = FoldersTableCompanion
    Function({
  Value<String> id,
  Value<String?> parentId,
  Value<String> name,
  Value<int> position,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

final class $$FoldersTableTableReferences extends BaseReferences<_$AppDatabase,
    $FoldersTableTable, FoldersTableData> {
  $$FoldersTableTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FoldersTableTable _parentIdTable(_$AppDatabase db) =>
      db.foldersTable.createAlias(
          $_aliasNameGenerator(db.foldersTable.parentId, db.foldersTable.id));

  $$FoldersTableTableProcessedTableManager? get parentId {
    final $_column = $_itemColumn<String>('parent_id');
    if ($_column == null) return null;
    final manager = $$FoldersTableTableTableManager($_db, $_db.foldersTable)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_parentIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$DocsTableTable, List<DocsTableData>>
      _docsTableRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
          db.docsTable,
          aliasName:
              $_aliasNameGenerator(db.foldersTable.id, db.docsTable.folderId));

  $$DocsTableTableProcessedTableManager get docsTableRefs {
    final manager = $$DocsTableTableTableManager($_db, $_db.docsTable)
        .filter((f) => f.folderId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_docsTableRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$FoldersTableTableFilterComposer
    extends Composer<_$AppDatabase, $FoldersTableTable> {
  $$FoldersTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  $$FoldersTableTableFilterComposer get parentId {
    final $$FoldersTableTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.parentId,
        referencedTable: $db.foldersTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$FoldersTableTableFilterComposer(
              $db: $db,
              $table: $db.foldersTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> docsTableRefs(
      Expression<bool> Function($$DocsTableTableFilterComposer f) f) {
    final $$DocsTableTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.docsTable,
        getReferencedColumn: (t) => t.folderId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocsTableTableFilterComposer(
              $db: $db,
              $table: $db.docsTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$FoldersTableTableOrderingComposer
    extends Composer<_$AppDatabase, $FoldersTableTable> {
  $$FoldersTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  $$FoldersTableTableOrderingComposer get parentId {
    final $$FoldersTableTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.parentId,
        referencedTable: $db.foldersTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$FoldersTableTableOrderingComposer(
              $db: $db,
              $table: $db.foldersTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$FoldersTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $FoldersTableTable> {
  $$FoldersTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$FoldersTableTableAnnotationComposer get parentId {
    final $$FoldersTableTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.parentId,
        referencedTable: $db.foldersTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$FoldersTableTableAnnotationComposer(
              $db: $db,
              $table: $db.foldersTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> docsTableRefs<T extends Object>(
      Expression<T> Function($$DocsTableTableAnnotationComposer a) f) {
    final $$DocsTableTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.docsTable,
        getReferencedColumn: (t) => t.folderId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocsTableTableAnnotationComposer(
              $db: $db,
              $table: $db.docsTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$FoldersTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $FoldersTableTable,
    FoldersTableData,
    $$FoldersTableTableFilterComposer,
    $$FoldersTableTableOrderingComposer,
    $$FoldersTableTableAnnotationComposer,
    $$FoldersTableTableCreateCompanionBuilder,
    $$FoldersTableTableUpdateCompanionBuilder,
    (FoldersTableData, $$FoldersTableTableReferences),
    FoldersTableData,
    PrefetchHooks Function({bool parentId, bool docsTableRefs})> {
  $$FoldersTableTableTableManager(_$AppDatabase db, $FoldersTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FoldersTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FoldersTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FoldersTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String?> parentId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<int> position = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              FoldersTableCompanion(
            id: id,
            parentId: parentId,
            name: name,
            position: position,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            Value<String?> parentId = const Value.absent(),
            required String name,
            required int position,
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              FoldersTableCompanion.insert(
            id: id,
            parentId: parentId,
            name: name,
            position: position,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$FoldersTableTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({parentId = false, docsTableRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (docsTableRefs) db.docsTable],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (parentId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.parentId,
                    referencedTable:
                        $$FoldersTableTableReferences._parentIdTable(db),
                    referencedColumn:
                        $$FoldersTableTableReferences._parentIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (docsTableRefs)
                    await $_getPrefetchedData<FoldersTableData,
                            $FoldersTableTable, DocsTableData>(
                        currentTable: table,
                        referencedTable: $$FoldersTableTableReferences
                            ._docsTableRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$FoldersTableTableReferences(db, table, p0)
                                .docsTableRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.folderId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$FoldersTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $FoldersTableTable,
    FoldersTableData,
    $$FoldersTableTableFilterComposer,
    $$FoldersTableTableOrderingComposer,
    $$FoldersTableTableAnnotationComposer,
    $$FoldersTableTableCreateCompanionBuilder,
    $$FoldersTableTableUpdateCompanionBuilder,
    (FoldersTableData, $$FoldersTableTableReferences),
    FoldersTableData,
    PrefetchHooks Function({bool parentId, bool docsTableRefs})>;
typedef $$DocsTableTableCreateCompanionBuilder = DocsTableCompanion Function({
  required String id,
  required String displayName,
  Value<String?> author,
  required String internalRelPath,
  Value<String?> folderId,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$DocsTableTableUpdateCompanionBuilder = DocsTableCompanion Function({
  Value<String> id,
  Value<String> displayName,
  Value<String?> author,
  Value<String> internalRelPath,
  Value<String?> folderId,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

final class $$DocsTableTableReferences
    extends BaseReferences<_$AppDatabase, $DocsTableTable, DocsTableData> {
  $$DocsTableTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $FoldersTableTable _folderIdTable(_$AppDatabase db) =>
      db.foldersTable.createAlias(
          $_aliasNameGenerator(db.docsTable.folderId, db.foldersTable.id));

  $$FoldersTableTableProcessedTableManager? get folderId {
    final $_column = $_itemColumn<String>('folder_id');
    if ($_column == null) return null;
    final manager = $$FoldersTableTableTableManager($_db, $_db.foldersTable)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_folderIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static MultiTypedResultKey<$SetlistItemsTableTable,
      List<SetlistItemsTableData>> _setlistItemsTableRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.setlistItemsTable,
          aliasName: $_aliasNameGenerator(
              db.docsTable.id, db.setlistItemsTable.docId));

  $$SetlistItemsTableTableProcessedTableManager get setlistItemsTableRefs {
    final manager =
        $$SetlistItemsTableTableTableManager($_db, $_db.setlistItemsTable)
            .filter((f) => f.docId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_setlistItemsTableRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }

  static MultiTypedResultKey<$DocStateTableTable, List<DocStateTableData>>
      _docStateTableRefsTable(_$AppDatabase db) =>
          MultiTypedResultKey.fromTable(db.docStateTable,
              aliasName: $_aliasNameGenerator(
                  db.docsTable.id, db.docStateTable.docId));

  $$DocStateTableTableProcessedTableManager get docStateTableRefs {
    final manager = $$DocStateTableTableTableManager($_db, $_db.docStateTable)
        .filter((f) => f.docId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_docStateTableRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$DocsTableTableFilterComposer
    extends Composer<_$AppDatabase, $DocsTableTable> {
  $$DocsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get internalRelPath => $composableBuilder(
      column: $table.internalRelPath,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  $$FoldersTableTableFilterComposer get folderId {
    final $$FoldersTableTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.folderId,
        referencedTable: $db.foldersTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$FoldersTableTableFilterComposer(
              $db: $db,
              $table: $db.foldersTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<bool> setlistItemsTableRefs(
      Expression<bool> Function($$SetlistItemsTableTableFilterComposer f) f) {
    final $$SetlistItemsTableTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.setlistItemsTable,
        getReferencedColumn: (t) => t.docId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SetlistItemsTableTableFilterComposer(
              $db: $db,
              $table: $db.setlistItemsTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }

  Expression<bool> docStateTableRefs(
      Expression<bool> Function($$DocStateTableTableFilterComposer f) f) {
    final $$DocStateTableTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.docStateTable,
        getReferencedColumn: (t) => t.docId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocStateTableTableFilterComposer(
              $db: $db,
              $table: $db.docStateTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$DocsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $DocsTableTable> {
  $$DocsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get author => $composableBuilder(
      column: $table.author, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get internalRelPath => $composableBuilder(
      column: $table.internalRelPath,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  $$FoldersTableTableOrderingComposer get folderId {
    final $$FoldersTableTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.folderId,
        referencedTable: $db.foldersTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$FoldersTableTableOrderingComposer(
              $db: $db,
              $table: $db.foldersTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$DocsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $DocsTableTable> {
  $$DocsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get displayName => $composableBuilder(
      column: $table.displayName, builder: (column) => column);

  GeneratedColumn<String> get author =>
      $composableBuilder(column: $table.author, builder: (column) => column);

  GeneratedColumn<String> get internalRelPath => $composableBuilder(
      column: $table.internalRelPath, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$FoldersTableTableAnnotationComposer get folderId {
    final $$FoldersTableTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.folderId,
        referencedTable: $db.foldersTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$FoldersTableTableAnnotationComposer(
              $db: $db,
              $table: $db.foldersTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  Expression<T> setlistItemsTableRefs<T extends Object>(
      Expression<T> Function($$SetlistItemsTableTableAnnotationComposer a) f) {
    final $$SetlistItemsTableTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.setlistItemsTable,
            getReferencedColumn: (t) => t.docId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$SetlistItemsTableTableAnnotationComposer(
                  $db: $db,
                  $table: $db.setlistItemsTable,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }

  Expression<T> docStateTableRefs<T extends Object>(
      Expression<T> Function($$DocStateTableTableAnnotationComposer a) f) {
    final $$DocStateTableTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.docStateTable,
        getReferencedColumn: (t) => t.docId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocStateTableTableAnnotationComposer(
              $db: $db,
              $table: $db.docStateTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$DocsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DocsTableTable,
    DocsTableData,
    $$DocsTableTableFilterComposer,
    $$DocsTableTableOrderingComposer,
    $$DocsTableTableAnnotationComposer,
    $$DocsTableTableCreateCompanionBuilder,
    $$DocsTableTableUpdateCompanionBuilder,
    (DocsTableData, $$DocsTableTableReferences),
    DocsTableData,
    PrefetchHooks Function(
        {bool folderId, bool setlistItemsTableRefs, bool docStateTableRefs})> {
  $$DocsTableTableTableManager(_$AppDatabase db, $DocsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> displayName = const Value.absent(),
            Value<String?> author = const Value.absent(),
            Value<String> internalRelPath = const Value.absent(),
            Value<String?> folderId = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DocsTableCompanion(
            id: id,
            displayName: displayName,
            author: author,
            internalRelPath: internalRelPath,
            folderId: folderId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String displayName,
            Value<String?> author = const Value.absent(),
            required String internalRelPath,
            Value<String?> folderId = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              DocsTableCompanion.insert(
            id: id,
            displayName: displayName,
            author: author,
            internalRelPath: internalRelPath,
            folderId: folderId,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$DocsTableTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: (
              {folderId = false,
              setlistItemsTableRefs = false,
              docStateTableRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (setlistItemsTableRefs) db.setlistItemsTable,
                if (docStateTableRefs) db.docStateTable
              ],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (folderId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.folderId,
                    referencedTable:
                        $$DocsTableTableReferences._folderIdTable(db),
                    referencedColumn:
                        $$DocsTableTableReferences._folderIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [
                  if (setlistItemsTableRefs)
                    await $_getPrefetchedData<DocsTableData, $DocsTableTable,
                            SetlistItemsTableData>(
                        currentTable: table,
                        referencedTable: $$DocsTableTableReferences
                            ._setlistItemsTableRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$DocsTableTableReferences(db, table, p0)
                                .setlistItemsTableRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.docId == item.id),
                        typedResults: items),
                  if (docStateTableRefs)
                    await $_getPrefetchedData<DocsTableData, $DocsTableTable,
                            DocStateTableData>(
                        currentTable: table,
                        referencedTable: $$DocsTableTableReferences
                            ._docStateTableRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$DocsTableTableReferences(db, table, p0)
                                .docStateTableRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.docId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$DocsTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DocsTableTable,
    DocsTableData,
    $$DocsTableTableFilterComposer,
    $$DocsTableTableOrderingComposer,
    $$DocsTableTableAnnotationComposer,
    $$DocsTableTableCreateCompanionBuilder,
    $$DocsTableTableUpdateCompanionBuilder,
    (DocsTableData, $$DocsTableTableReferences),
    DocsTableData,
    PrefetchHooks Function(
        {bool folderId, bool setlistItemsTableRefs, bool docStateTableRefs})>;
typedef $$SetlistsTableTableCreateCompanionBuilder = SetlistsTableCompanion
    Function({
  required String id,
  required String name,
  Value<String?> notes,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$SetlistsTableTableUpdateCompanionBuilder = SetlistsTableCompanion
    Function({
  Value<String> id,
  Value<String> name,
  Value<String?> notes,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

final class $$SetlistsTableTableReferences extends BaseReferences<_$AppDatabase,
    $SetlistsTableTable, SetlistsTableData> {
  $$SetlistsTableTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$SetlistItemsTableTable,
      List<SetlistItemsTableData>> _setlistItemsTableRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.setlistItemsTable,
          aliasName: $_aliasNameGenerator(
              db.setlistsTable.id, db.setlistItemsTable.setlistId));

  $$SetlistItemsTableTableProcessedTableManager get setlistItemsTableRefs {
    final manager = $$SetlistItemsTableTableTableManager(
            $_db, $_db.setlistItemsTable)
        .filter((f) => f.setlistId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache =
        $_typedResult.readTableOrNull(_setlistItemsTableRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$SetlistsTableTableFilterComposer
    extends Composer<_$AppDatabase, $SetlistsTableTable> {
  $$SetlistsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  Expression<bool> setlistItemsTableRefs(
      Expression<bool> Function($$SetlistItemsTableTableFilterComposer f) f) {
    final $$SetlistItemsTableTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.setlistItemsTable,
        getReferencedColumn: (t) => t.setlistId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SetlistItemsTableTableFilterComposer(
              $db: $db,
              $table: $db.setlistItemsTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$SetlistsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SetlistsTableTable> {
  $$SetlistsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get notes => $composableBuilder(
      column: $table.notes, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$SetlistsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SetlistsTableTable> {
  $$SetlistsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> setlistItemsTableRefs<T extends Object>(
      Expression<T> Function($$SetlistItemsTableTableAnnotationComposer a) f) {
    final $$SetlistItemsTableTableAnnotationComposer composer =
        $composerBuilder(
            composer: this,
            getCurrentColumn: (t) => t.id,
            referencedTable: $db.setlistItemsTable,
            getReferencedColumn: (t) => t.setlistId,
            builder: (joinBuilder,
                    {$addJoinBuilderToRootComposer,
                    $removeJoinBuilderFromRootComposer}) =>
                $$SetlistItemsTableTableAnnotationComposer(
                  $db: $db,
                  $table: $db.setlistItemsTable,
                  $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                  joinBuilder: joinBuilder,
                  $removeJoinBuilderFromRootComposer:
                      $removeJoinBuilderFromRootComposer,
                ));
    return f(composer);
  }
}

class $$SetlistsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SetlistsTableTable,
    SetlistsTableData,
    $$SetlistsTableTableFilterComposer,
    $$SetlistsTableTableOrderingComposer,
    $$SetlistsTableTableAnnotationComposer,
    $$SetlistsTableTableCreateCompanionBuilder,
    $$SetlistsTableTableUpdateCompanionBuilder,
    (SetlistsTableData, $$SetlistsTableTableReferences),
    SetlistsTableData,
    PrefetchHooks Function({bool setlistItemsTableRefs})> {
  $$SetlistsTableTableTableManager(_$AppDatabase db, $SetlistsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SetlistsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SetlistsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SetlistsTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> notes = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SetlistsTableCompanion(
            id: id,
            name: name,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String name,
            Value<String?> notes = const Value.absent(),
            required int createdAt,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SetlistsTableCompanion.insert(
            id: id,
            name: name,
            notes: notes,
            createdAt: createdAt,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$SetlistsTableTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({setlistItemsTableRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (setlistItemsTableRefs) db.setlistItemsTable
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (setlistItemsTableRefs)
                    await $_getPrefetchedData<SetlistsTableData,
                            $SetlistsTableTable, SetlistItemsTableData>(
                        currentTable: table,
                        referencedTable: $$SetlistsTableTableReferences
                            ._setlistItemsTableRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$SetlistsTableTableReferences(db, table, p0)
                                .setlistItemsTableRefs,
                        referencedItemsForCurrentItem:
                            (item, referencedItems) => referencedItems
                                .where((e) => e.setlistId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$SetlistsTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SetlistsTableTable,
    SetlistsTableData,
    $$SetlistsTableTableFilterComposer,
    $$SetlistsTableTableOrderingComposer,
    $$SetlistsTableTableAnnotationComposer,
    $$SetlistsTableTableCreateCompanionBuilder,
    $$SetlistsTableTableUpdateCompanionBuilder,
    (SetlistsTableData, $$SetlistsTableTableReferences),
    SetlistsTableData,
    PrefetchHooks Function({bool setlistItemsTableRefs})>;
typedef $$SetlistItemsTableTableCreateCompanionBuilder
    = SetlistItemsTableCompanion Function({
  required String setlistId,
  required String docId,
  required int position,
  Value<int> rowid,
});
typedef $$SetlistItemsTableTableUpdateCompanionBuilder
    = SetlistItemsTableCompanion Function({
  Value<String> setlistId,
  Value<String> docId,
  Value<int> position,
  Value<int> rowid,
});

final class $$SetlistItemsTableTableReferences extends BaseReferences<
    _$AppDatabase, $SetlistItemsTableTable, SetlistItemsTableData> {
  $$SetlistItemsTableTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $SetlistsTableTable _setlistIdTable(_$AppDatabase db) =>
      db.setlistsTable.createAlias($_aliasNameGenerator(
          db.setlistItemsTable.setlistId, db.setlistsTable.id));

  $$SetlistsTableTableProcessedTableManager get setlistId {
    final $_column = $_itemColumn<String>('setlist_id')!;

    final manager = $$SetlistsTableTableTableManager($_db, $_db.setlistsTable)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_setlistIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }

  static $DocsTableTable _docIdTable(_$AppDatabase db) =>
      db.docsTable.createAlias(
          $_aliasNameGenerator(db.setlistItemsTable.docId, db.docsTable.id));

  $$DocsTableTableProcessedTableManager get docId {
    final $_column = $_itemColumn<String>('doc_id')!;

    final manager = $$DocsTableTableTableManager($_db, $_db.docsTable)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_docIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$SetlistItemsTableTableFilterComposer
    extends Composer<_$AppDatabase, $SetlistItemsTableTable> {
  $$SetlistItemsTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnFilters(column));

  $$SetlistsTableTableFilterComposer get setlistId {
    final $$SetlistsTableTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.setlistId,
        referencedTable: $db.setlistsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SetlistsTableTableFilterComposer(
              $db: $db,
              $table: $db.setlistsTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$DocsTableTableFilterComposer get docId {
    final $$DocsTableTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.docId,
        referencedTable: $db.docsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocsTableTableFilterComposer(
              $db: $db,
              $table: $db.docsTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SetlistItemsTableTableOrderingComposer
    extends Composer<_$AppDatabase, $SetlistItemsTableTable> {
  $$SetlistItemsTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get position => $composableBuilder(
      column: $table.position, builder: (column) => ColumnOrderings(column));

  $$SetlistsTableTableOrderingComposer get setlistId {
    final $$SetlistsTableTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.setlistId,
        referencedTable: $db.setlistsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SetlistsTableTableOrderingComposer(
              $db: $db,
              $table: $db.setlistsTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$DocsTableTableOrderingComposer get docId {
    final $$DocsTableTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.docId,
        referencedTable: $db.docsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocsTableTableOrderingComposer(
              $db: $db,
              $table: $db.docsTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SetlistItemsTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $SetlistItemsTableTable> {
  $$SetlistItemsTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  $$SetlistsTableTableAnnotationComposer get setlistId {
    final $$SetlistsTableTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.setlistId,
        referencedTable: $db.setlistsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$SetlistsTableTableAnnotationComposer(
              $db: $db,
              $table: $db.setlistsTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }

  $$DocsTableTableAnnotationComposer get docId {
    final $$DocsTableTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.docId,
        referencedTable: $db.docsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocsTableTableAnnotationComposer(
              $db: $db,
              $table: $db.docsTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$SetlistItemsTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SetlistItemsTableTable,
    SetlistItemsTableData,
    $$SetlistItemsTableTableFilterComposer,
    $$SetlistItemsTableTableOrderingComposer,
    $$SetlistItemsTableTableAnnotationComposer,
    $$SetlistItemsTableTableCreateCompanionBuilder,
    $$SetlistItemsTableTableUpdateCompanionBuilder,
    (SetlistItemsTableData, $$SetlistItemsTableTableReferences),
    SetlistItemsTableData,
    PrefetchHooks Function({bool setlistId, bool docId})> {
  $$SetlistItemsTableTableTableManager(
      _$AppDatabase db, $SetlistItemsTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SetlistItemsTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SetlistItemsTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SetlistItemsTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> setlistId = const Value.absent(),
            Value<String> docId = const Value.absent(),
            Value<int> position = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SetlistItemsTableCompanion(
            setlistId: setlistId,
            docId: docId,
            position: position,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String setlistId,
            required String docId,
            required int position,
            Value<int> rowid = const Value.absent(),
          }) =>
              SetlistItemsTableCompanion.insert(
            setlistId: setlistId,
            docId: docId,
            position: position,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$SetlistItemsTableTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({setlistId = false, docId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (setlistId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.setlistId,
                    referencedTable:
                        $$SetlistItemsTableTableReferences._setlistIdTable(db),
                    referencedColumn: $$SetlistItemsTableTableReferences
                        ._setlistIdTable(db)
                        .id,
                  ) as T;
                }
                if (docId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.docId,
                    referencedTable:
                        $$SetlistItemsTableTableReferences._docIdTable(db),
                    referencedColumn:
                        $$SetlistItemsTableTableReferences._docIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$SetlistItemsTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SetlistItemsTableTable,
    SetlistItemsTableData,
    $$SetlistItemsTableTableFilterComposer,
    $$SetlistItemsTableTableOrderingComposer,
    $$SetlistItemsTableTableAnnotationComposer,
    $$SetlistItemsTableTableCreateCompanionBuilder,
    $$SetlistItemsTableTableUpdateCompanionBuilder,
    (SetlistItemsTableData, $$SetlistItemsTableTableReferences),
    SetlistItemsTableData,
    PrefetchHooks Function({bool setlistId, bool docId})>;
typedef $$DocStateTableTableCreateCompanionBuilder = DocStateTableCompanion
    Function({
  required String docId,
  required int lastPage,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$DocStateTableTableUpdateCompanionBuilder = DocStateTableCompanion
    Function({
  Value<String> docId,
  Value<int> lastPage,
  Value<int> updatedAt,
  Value<int> rowid,
});

final class $$DocStateTableTableReferences extends BaseReferences<_$AppDatabase,
    $DocStateTableTable, DocStateTableData> {
  $$DocStateTableTableReferences(
      super.$_db, super.$_table, super.$_typedResult);

  static $DocsTableTable _docIdTable(_$AppDatabase db) =>
      db.docsTable.createAlias(
          $_aliasNameGenerator(db.docStateTable.docId, db.docsTable.id));

  $$DocsTableTableProcessedTableManager get docId {
    final $_column = $_itemColumn<String>('doc_id')!;

    final manager = $$DocsTableTableTableManager($_db, $_db.docsTable)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_docIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$DocStateTableTableFilterComposer
    extends Composer<_$AppDatabase, $DocStateTableTable> {
  $$DocStateTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get lastPage => $composableBuilder(
      column: $table.lastPage, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  $$DocsTableTableFilterComposer get docId {
    final $$DocsTableTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.docId,
        referencedTable: $db.docsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocsTableTableFilterComposer(
              $db: $db,
              $table: $db.docsTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$DocStateTableTableOrderingComposer
    extends Composer<_$AppDatabase, $DocStateTableTable> {
  $$DocStateTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get lastPage => $composableBuilder(
      column: $table.lastPage, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  $$DocsTableTableOrderingComposer get docId {
    final $$DocsTableTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.docId,
        referencedTable: $db.docsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocsTableTableOrderingComposer(
              $db: $db,
              $table: $db.docsTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$DocStateTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $DocStateTableTable> {
  $$DocStateTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get lastPage =>
      $composableBuilder(column: $table.lastPage, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$DocsTableTableAnnotationComposer get docId {
    final $$DocsTableTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.docId,
        referencedTable: $db.docsTable,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$DocsTableTableAnnotationComposer(
              $db: $db,
              $table: $db.docsTable,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$DocStateTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $DocStateTableTable,
    DocStateTableData,
    $$DocStateTableTableFilterComposer,
    $$DocStateTableTableOrderingComposer,
    $$DocStateTableTableAnnotationComposer,
    $$DocStateTableTableCreateCompanionBuilder,
    $$DocStateTableTableUpdateCompanionBuilder,
    (DocStateTableData, $$DocStateTableTableReferences),
    DocStateTableData,
    PrefetchHooks Function({bool docId})> {
  $$DocStateTableTableTableManager(_$AppDatabase db, $DocStateTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DocStateTableTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DocStateTableTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DocStateTableTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> docId = const Value.absent(),
            Value<int> lastPage = const Value.absent(),
            Value<int> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              DocStateTableCompanion(
            docId: docId,
            lastPage: lastPage,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String docId,
            required int lastPage,
            required int updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              DocStateTableCompanion.insert(
            docId: docId,
            lastPage: lastPage,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable(table),
                    $$DocStateTableTableReferences(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: ({docId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (docId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.docId,
                    referencedTable:
                        $$DocStateTableTableReferences._docIdTable(db),
                    referencedColumn:
                        $$DocStateTableTableReferences._docIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$DocStateTableTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $DocStateTableTable,
    DocStateTableData,
    $$DocStateTableTableFilterComposer,
    $$DocStateTableTableOrderingComposer,
    $$DocStateTableTableAnnotationComposer,
    $$DocStateTableTableCreateCompanionBuilder,
    $$DocStateTableTableUpdateCompanionBuilder,
    (DocStateTableData, $$DocStateTableTableReferences),
    DocStateTableData,
    PrefetchHooks Function({bool docId})>;
typedef $$AnnotationStrokesTableTableCreateCompanionBuilder
    = AnnotationStrokesTableCompanion Function({
  required String id,
  required String docId,
  Value<String?> setlistId,
  required int pageIndex,
  required String tool,
  required double width,
  required String pointsJson,
  required int createdAt,
  Value<int> rowid,
});
typedef $$AnnotationStrokesTableTableUpdateCompanionBuilder
    = AnnotationStrokesTableCompanion Function({
  Value<String> id,
  Value<String> docId,
  Value<String?> setlistId,
  Value<int> pageIndex,
  Value<String> tool,
  Value<double> width,
  Value<String> pointsJson,
  Value<int> createdAt,
  Value<int> rowid,
});

class $$AnnotationStrokesTableTableFilterComposer
    extends Composer<_$AppDatabase, $AnnotationStrokesTableTable> {
  $$AnnotationStrokesTableTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get docId => $composableBuilder(
      column: $table.docId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get setlistId => $composableBuilder(
      column: $table.setlistId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get pageIndex => $composableBuilder(
      column: $table.pageIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get tool => $composableBuilder(
      column: $table.tool, builder: (column) => ColumnFilters(column));

  ColumnFilters<double> get width => $composableBuilder(
      column: $table.width, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pointsJson => $composableBuilder(
      column: $table.pointsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$AnnotationStrokesTableTableOrderingComposer
    extends Composer<_$AppDatabase, $AnnotationStrokesTableTable> {
  $$AnnotationStrokesTableTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get docId => $composableBuilder(
      column: $table.docId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get setlistId => $composableBuilder(
      column: $table.setlistId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get pageIndex => $composableBuilder(
      column: $table.pageIndex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get tool => $composableBuilder(
      column: $table.tool, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<double> get width => $composableBuilder(
      column: $table.width, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pointsJson => $composableBuilder(
      column: $table.pointsJson, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$AnnotationStrokesTableTableAnnotationComposer
    extends Composer<_$AppDatabase, $AnnotationStrokesTableTable> {
  $$AnnotationStrokesTableTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get docId =>
      $composableBuilder(column: $table.docId, builder: (column) => column);

  GeneratedColumn<String> get setlistId =>
      $composableBuilder(column: $table.setlistId, builder: (column) => column);

  GeneratedColumn<int> get pageIndex =>
      $composableBuilder(column: $table.pageIndex, builder: (column) => column);

  GeneratedColumn<String> get tool =>
      $composableBuilder(column: $table.tool, builder: (column) => column);

  GeneratedColumn<double> get width =>
      $composableBuilder(column: $table.width, builder: (column) => column);

  GeneratedColumn<String> get pointsJson => $composableBuilder(
      column: $table.pointsJson, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AnnotationStrokesTableTableTableManager extends RootTableManager<
    _$AppDatabase,
    $AnnotationStrokesTableTable,
    AnnotationStrokesTableData,
    $$AnnotationStrokesTableTableFilterComposer,
    $$AnnotationStrokesTableTableOrderingComposer,
    $$AnnotationStrokesTableTableAnnotationComposer,
    $$AnnotationStrokesTableTableCreateCompanionBuilder,
    $$AnnotationStrokesTableTableUpdateCompanionBuilder,
    (
      AnnotationStrokesTableData,
      BaseReferences<_$AppDatabase, $AnnotationStrokesTableTable,
          AnnotationStrokesTableData>
    ),
    AnnotationStrokesTableData,
    PrefetchHooks Function()> {
  $$AnnotationStrokesTableTableTableManager(
      _$AppDatabase db, $AnnotationStrokesTableTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AnnotationStrokesTableTableFilterComposer(
                  $db: db, $table: table),
          createOrderingComposer: () =>
              $$AnnotationStrokesTableTableOrderingComposer(
                  $db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AnnotationStrokesTableTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> id = const Value.absent(),
            Value<String> docId = const Value.absent(),
            Value<String?> setlistId = const Value.absent(),
            Value<int> pageIndex = const Value.absent(),
            Value<String> tool = const Value.absent(),
            Value<double> width = const Value.absent(),
            Value<String> pointsJson = const Value.absent(),
            Value<int> createdAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              AnnotationStrokesTableCompanion(
            id: id,
            docId: docId,
            setlistId: setlistId,
            pageIndex: pageIndex,
            tool: tool,
            width: width,
            pointsJson: pointsJson,
            createdAt: createdAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String id,
            required String docId,
            Value<String?> setlistId = const Value.absent(),
            required int pageIndex,
            required String tool,
            required double width,
            required String pointsJson,
            required int createdAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              AnnotationStrokesTableCompanion.insert(
            id: id,
            docId: docId,
            setlistId: setlistId,
            pageIndex: pageIndex,
            tool: tool,
            width: width,
            pointsJson: pointsJson,
            createdAt: createdAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$AnnotationStrokesTableTableProcessedTableManager
    = ProcessedTableManager<
        _$AppDatabase,
        $AnnotationStrokesTableTable,
        AnnotationStrokesTableData,
        $$AnnotationStrokesTableTableFilterComposer,
        $$AnnotationStrokesTableTableOrderingComposer,
        $$AnnotationStrokesTableTableAnnotationComposer,
        $$AnnotationStrokesTableTableCreateCompanionBuilder,
        $$AnnotationStrokesTableTableUpdateCompanionBuilder,
        (
          AnnotationStrokesTableData,
          BaseReferences<_$AppDatabase, $AnnotationStrokesTableTable,
              AnnotationStrokesTableData>
        ),
        AnnotationStrokesTableData,
        PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$FoldersTableTableTableManager get foldersTable =>
      $$FoldersTableTableTableManager(_db, _db.foldersTable);
  $$DocsTableTableTableManager get docsTable =>
      $$DocsTableTableTableManager(_db, _db.docsTable);
  $$SetlistsTableTableTableManager get setlistsTable =>
      $$SetlistsTableTableTableManager(_db, _db.setlistsTable);
  $$SetlistItemsTableTableTableManager get setlistItemsTable =>
      $$SetlistItemsTableTableTableManager(_db, _db.setlistItemsTable);
  $$DocStateTableTableTableManager get docStateTable =>
      $$DocStateTableTableTableManager(_db, _db.docStateTable);
  $$AnnotationStrokesTableTableTableManager get annotationStrokesTable =>
      $$AnnotationStrokesTableTableTableManager(
          _db, _db.annotationStrokesTable);
}
