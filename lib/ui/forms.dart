import 'package:flutter/material.dart';
import '../core/models.dart';

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.required = true,
    this.secret = false,
    this.lines = 1,
    this.number = false,
    this.options,
    this.initial,
    this.hint,
    this.minLength,
    this.maxLength,
  });
  final String key, label;
  final bool required, secret, number;
  final int lines;
  final Map<String, String>? options;
  final dynamic initial;
  final String? hint;
  final int? minLength, maxLength;
}

Future<Json?> showFields(
  BuildContext context,
  String title,
  List<FieldSpec> fields, {
  String submitLabel = '保存',
  Future<void> Function(Json)? onSubmit,
  Widget? header,
}) => showModalBottomSheet<Json>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  constraints: const BoxConstraints(maxWidth: 640),
  builder: (_) => _FieldsSheet(
    title: title,
    fields: fields,
    submitLabel: submitLabel,
    onSubmit: onSubmit,
    header: header,
  ),
);

class _FieldsSheet extends StatefulWidget {
  const _FieldsSheet({
    required this.title,
    required this.fields,
    required this.submitLabel,
    this.onSubmit,
    this.header,
  });
  final String title, submitLabel;
  final List<FieldSpec> fields;
  final Future<void> Function(Json)? onSubmit;
  final Widget? header;
  @override
  State<_FieldsSheet> createState() => _FieldsSheetState();
}

class _FieldsSheetState extends State<_FieldsSheet> {
  final form = GlobalKey<FormState>();
  late final controllers = {
    for (final field in widget.fields)
      field.key: TextEditingController(text: textOf(field.initial)),
  };
  late final choices = <String, String?>{
    for (final f in widget.fields.where((f) => f.options != null))
      f.key: f.options!.containsKey(textOf(f.initial))
          ? textOf(f.initial)
          : f.options!.keys.first,
  };
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    final result = <String, dynamic>{
      for (final field in widget.fields)
        field.key: field.options != null
            ? choices[field.key]
            : field.number
            ? num.tryParse(controllers[field.key]!.text.trim()) ?? 0
            : controllers[field.key]!.text.trim(),
    };
    if (widget.onSubmit == null) {
      Navigator.pop(context, result);
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSubmit!(result);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted) setState(() => error = friendlyError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 20),
              if (widget.header != null) widget.header!,
              for (final field in widget.fields)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: field.options != null
                      ? DropdownButtonFormField<String>(
                          initialValue: choices[field.key],
                          isExpanded: true,
                          decoration: InputDecoration(labelText: field.label),
                          items: field.options!.entries
                              .map(
                                (e) => DropdownMenuItem(
                                  value: e.key,
                                  child: Text(e.value),
                                ),
                              )
                              .toList(),
                          onChanged: busy
                              ? null
                              : (value) =>
                                    setState(() => choices[field.key] = value),
                        )
                      : TextFormField(
                          controller: controllers[field.key],
                          enabled: !busy,
                          obscureText: field.secret,
                          minLines: field.lines,
                          maxLines: field.lines,
                          maxLength: field.maxLength,
                          keyboardType: field.number
                              ? const TextInputType.numberWithOptions(
                                  decimal: true,
                                )
                              : null,
                          decoration: InputDecoration(
                            labelText: field.label,
                            hintText: field.hint,
                          ),
                          validator: (value) {
                            if (field.required &&
                                (value == null || value.trim().isEmpty))
                              return '请填写${field.label}';
                            if (field.minLength != null &&
                                (value?.length ?? 0) < field.minLength!)
                              return '至少 ${field.minLength} 个字符';
                            if (field.number &&
                                value != null &&
                                value.isNotEmpty &&
                                num.tryParse(value) == null)
                              return '请输入数字';
                            return null;
                          },
                        ),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              FilledButton(
                onPressed: busy ? null : submit,
                child: busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.submitLabel),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
