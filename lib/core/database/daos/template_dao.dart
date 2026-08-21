import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables/templates.dart';

part 'template_dao.g.dart';

@DriftAccessor(tables: [TemplatesTable, TemplateExercisesTable])
class TemplateDao extends DatabaseAccessor<AppDatabase>
    with _$TemplateDaoMixin {
  TemplateDao(super.db);

  /// Watch all templates, ordered by name.
  Stream<List<Template>> watchAll() =>
      (select(templatesTable)..orderBy([(t) => OrderingTerm.asc(t.name)]))
          .watch()
          .map((rows) => rows.map<Template>(Template.fromDrift).toList());

  /// Get a single template by ID with exercises.
  Future<TemplateWithExercises?> getWithExercises(String templateId) async {
    final template = await (select(
      templatesTable,
    )..where((t) => t.id.equals(templateId)))
        .getSingleOrNull();
    if (template == null) return null;

    final exercises = await (select(templateExercisesTable)
          ..where((t) => t.templateId.equals(templateId))
          ..orderBy([(t) => OrderingTerm.asc(t.orderIndex)]))
        .get();

    return TemplateWithExercises(
      template: Template.fromDrift(template),
      exercises:
          exercises.map<TemplateExercise>(TemplateExercise.fromDrift).toList(),
    );
  }

  /// Insert a new template with exercises in a transaction.
  Future<String> insertTemplate(
    TemplatesTableCompanion template,
    List<TemplateExercisesTableCompanion> exercises,
  ) {
    return transaction(() async {
      await into(templatesTable).insert(template);
      await batch((b) => b.insertAll(templateExercisesTable, exercises));
      return template.id.value;
    });
  }

  /// Update a template and its exercises.
  Future<void> updateTemplate(
    TemplatesTableCompanion template,
    List<TemplateExercisesTableCompanion> exercises,
  ) {
    return transaction(() async {
      await update(templatesTable).replace(template);
      // Delete existing exercises and re-insert
      await (delete(
        templateExercisesTable,
      )..where((t) => t.templateId.equals(template.id.value)))
          .go();
      await batch((b) => b.insertAll(templateExercisesTable, exercises));
    });
  }

  /// Delete a template (cascades to exercises via FK).
  Future<void> deleteTemplate(String templateId) =>
      (delete(templatesTable)..where((t) => t.id.equals(templateId))).go();

  /// Watch built-in templates only.
  Stream<List<Template>> watchBuiltIn() => (select(templatesTable)
        ..where((t) => t.isBuiltIn.equals(true))
        ..orderBy([(t) => OrderingTerm.asc(t.name)]))
      .watch()
      .map((rows) => rows.map<Template>(Template.fromDrift).toList());
}

/// Template with nested exercises.
class TemplateWithExercises {
  const TemplateWithExercises({
    required this.template,
    required this.exercises,
  });

  final Template template;
  final List<TemplateExercise> exercises;
}
