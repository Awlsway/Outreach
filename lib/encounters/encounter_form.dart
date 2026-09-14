import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../auth/session_controller.dart';
import '../database/outreach_repository.dart' hide Row;

const _testChoices = ['No', 'Non reactive', 'Reactive'];
const _userTypes = [
  'PWID',
  'PWUD',
  'SPOUS',
  'MSM',
  'FSW',
  'FM',
  'Youth',
  'Other',
];
const _previousHivHcv = ['Unknown', 'Positive', 'Negative'];
const _previousHbvChoices = ['Unknown', 'Positive', 'Negative', 'Vaccinated'];
const _previousMmtChoices = ['No', 'Drop Out', 'Current'];
const _previousArtChoices = ['No', 'Defaulter', 'Current'];

class EncounterForm extends StatefulWidget {
  const EncounterForm({
    super.key,
    required this.repository,
    required this.session,
    required this.hotspot,
    required this.onBack,
    this.initialRecord,
    this.onSaved,
  });

  final OutreachRepository repository;
  final SessionController session;
  final Map<String, Object?> hotspot;
  final VoidCallback onBack;
  final Map<String, Object?>? initialRecord;
  final VoidCallback? onSaved;

  @override
  State<EncounterForm> createState() => _EncounterFormState();
}

class _EncounterFormState extends State<EncounterForm> {
  final _form = GlobalKey<FormState>();
  final _clientYear = TextEditingController(
    text: DateTime.now().year.toString(),
  );
  final _clientNumber = TextEditingController();
  final _remark = TextEditingController();
  final _quantities = <String, TextEditingController>{
    for (final key in _quantityLabels.keys)
      key: TextEditingController(text: '0'),
  };
  String? _clientKind;
  bool _newClientDetailsComplete = false;
  var _userType = 'PWID';
  String? _gender;
  var _previousHiv = 'Unknown';
  var _previousHcv = 'Unknown';
  var _previousHbv = 'Unknown';
  var _previousMmt = 'No';
  var _previousArt = 'No';
  var _hiv = 'No';
  var _hcv = 'No';
  var _hbv = 'No';
  var _syphilis = 'No';
  var _referDic = false;
  bool _saving = false;
  String? _message;
  bool get _editing => widget.initialRecord != null;

  static const _quantityLabels = <String, String>{
    'dist_3cc': 'Distribution 3cc',
    'dist_1cc': 'Distribution 1cc',
    'dist_lds': 'Distribution LDS',
    'dist_alcohol_swab': 'Distribution alcohol swab',
    'dist_sterile_water': 'Distribution sterile water',
    'dist_condom': 'Distribution condom',
    'recollect_3cc': 'Recollection 3cc',
    'recollect_1cc': 'Recollection 1cc',
    'recollect_lds': 'Recollection LDS',
  };

  @override
  void initState() {
    super.initState();
    final record = widget.initialRecord;
    if (record == null) return;
    final code = (record['client_code'] as String?) ?? '';
    final parts = code.split('/');
    if (parts.length == 3) {
      _clientYear.text = parts[0];
      _clientNumber.text = parts[2].replaceFirst(RegExp(r'^0+(?!$)'), '');
    }
    _clientKind = record['client_kind'] as String?;
    _newClientDetailsComplete = _clientKind == 'New';
    _userType = (record['user_type'] as String?) ?? 'PWID';
    _gender = record['gender'] as String?;
    _previousHiv = (record['previous_hiv'] as String?) ?? 'Unknown';
    _previousHcv = (record['previous_hcv'] as String?) ?? 'Unknown';
    _previousHbv = (record['previous_hbv'] as String?) ?? 'Unknown';
    _previousMmt = (record['previous_mmt'] as String?) ?? 'No';
    _previousArt = (record['previous_art'] as String?) ?? 'No';
    _hiv = (record['hiv'] as String?) ?? 'No';
    _hcv = (record['hcv'] as String?) ?? 'No';
    _hbv = (record['hbv'] as String?) ?? 'No';
    _syphilis = (record['syphilis'] as String?) ?? 'No';
    _referDic = record['refer_dic'] == 1;
    _remark.text = (record['remark'] as String?) ?? '';
    for (final field in _quantities.keys) {
      _quantities[field]!.text = (record[field] ?? 0).toString();
    }
  }

  @override
  void dispose() {
    _clientYear.dispose();
    _clientNumber.dispose();
    _remark.dispose();
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _selectClientKind(String? value) async {
    if (_saving || value == _clientKind) return;
    widget.session.activity();
    if (value != 'New') {
      setState(() {
        _clientKind = value;
        _newClientDetailsComplete = false;
      });
      return;
    }
    final completed = await _showNewClientDialog();
    if (!mounted) return;
    setState(() {
      _clientKind = completed ? 'New' : null;
      _newClientDetailsComplete = completed;
    });
  }

  Future<bool> _showNewClientDialog() async {
    final submitted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('New client details'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _choice('User type', _userType, _userTypes, (value) {
                    setDialogState(() => _userType = value!);
                  }),
                  const SizedBox(height: 12),
                  _choice<String?>(
                    'Gender',
                    _gender,
                    const [null, 'Male', 'Female'],
                    (value) {
                      setDialogState(() => _gender = value);
                    },
                    choiceLabel: (value) => value ?? 'Not specified',
                  ),
                  const SizedBox(height: 12),
                  _choice(
                    'Previous HIV testing status',
                    _previousHiv,
                    _previousHivHcv,
                    (value) {
                      setDialogState(() => _previousHiv = value!);
                    },
                  ),
                  const SizedBox(height: 12),
                  _choice(
                    'Previous HCV status',
                    _previousHcv,
                    _previousHivHcv,
                    (value) {
                      setDialogState(() => _previousHcv = value!);
                    },
                  ),
                  const SizedBox(height: 12),
                  _choice(
                    'Previous HBV status',
                    _previousHbv,
                    _previousHbvChoices,
                    (value) {
                      setDialogState(() => _previousHbv = value!);
                    },
                  ),
                  const SizedBox(height: 12),
                  _choice(
                    'Previous MMT status',
                    _previousMmt,
                    _previousMmtChoices,
                    (value) {
                      setDialogState(() => _previousMmt = value!);
                    },
                  ),
                  const SizedBox(height: 12),
                  _choice(
                    'Previous ART status',
                    _previousArt,
                    _previousArtChoices,
                    (value) {
                      setDialogState(() => _previousArt = value!);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Save details'),
            ),
          ],
        ),
      ),
    );
    return submitted ?? false;
  }

  DropdownButtonFormField<T> _choice<T>(
    String fieldLabel,
    T value,
    List<T> choices,
    ValueChanged<T?> onChanged, {
    String Function(T)? choiceLabel,
  }) => DropdownButtonFormField<T>(
    key: ValueKey('new-client-$fieldLabel'),
    initialValue: value,
    decoration: InputDecoration(labelText: fieldLabel),
    items: choices
        .map(
          (choice) => DropdownMenuItem(
            value: choice,
            child: Text(choiceLabel?.call(choice) ?? choice.toString()),
          ),
        )
        .toList(),
    onChanged: onChanged,
  );

  int? _quantity(String field) {
    final value = int.tryParse(_quantities[field]!.text.trim());
    return value != null && value >= 0 ? value : null;
  }

  String get _clientCode =>
      '${_clientYear.text.trim()}/MY/${_clientNumber.text.trim().padLeft(4, '0')}';

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    for (final field in _quantities.keys) {
      if (_quantity(field) == null) {
        setState(
          () => _message =
              'Supply quantities must be whole numbers of zero or more.',
        );
        return;
      }
    }
    widget.session.activity();
    if (widget.session.currentWorkerId == null) {
      widget.session.lock();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _message = null;
    });
    try {
      final payload = {
        'hotspot_id': widget.hotspot['hotspot_id'],
        'client_code': _clientCode,
        'client_kind': _clientKind,
        if (_clientKind == 'New' && _newClientDetailsComplete) ...{
          'user_type': _userType,
          'gender': _gender,
          'previous_hiv': _previousHiv,
          'previous_hcv': _previousHcv,
          'previous_hbv': _previousHbv,
          'previous_mmt': _previousMmt,
          'previous_art': _previousArt,
        },
        'hiv': _hiv,
        'hcv': _hcv,
        'hbv': _hbv,
        'syphilis': _syphilis,
        for (final field in _quantities.keys) field: _quantity(field),
        'refer_dic': _referDic ? 1 : 0,
        'remark': _remark.text,
      };
      final initial = widget.initialRecord;
      if (initial == null) {
        await widget.repository.createEncounter(payload);
      } else {
        await widget.repository.updateEncounter(
          initial['encounter_id'] as String,
          payload,
          expectedRevision: (initial['revision'] as num).toInt(),
        );
      }
      if (!mounted) return;
      if (!_editing) _resetForm();
      setState(() {
        _saving = false;
        _message = _editing
            ? 'Record updated.'
            : 'Record saved. Enter the next client.';
      });
      if (_editing) widget.onSaved?.call();
    } on DatabaseException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _message = error.isUniqueConstraintError()
            ? 'This client already has a record for this hotspot today.'
            : 'Could not save the record. Your form is still here. Please retry.';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _message =
              'Could not save the record. Your form is still here. Please retry.';
        });
      }
    }
  }

  void _resetForm() {
    _clientYear.text = DateTime.now().year.toString();
    _clientNumber.clear();
    _remark.clear();
    for (final controller in _quantities.values) {
      controller.text = '0';
    }
    _clientKind = null;
    _newClientDetailsComplete = false;
    _userType = 'PWID';
    _gender = null;
    _previousHiv = 'Unknown';
    _previousHcv = 'Unknown';
    _previousHbv = 'Unknown';
    _previousMmt = 'No';
    _previousArt = 'No';
    _hiv = _hcv = _hbv = _syphilis = 'No';
    _referDic = false;
  }

  Widget _testChoice(
    String label,
    String value,
    ValueChanged<String?> change,
    Color color,
    Color labelColor,
  ) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: labelColor,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          key: ValueKey('test-$label'),
          initialValue: value,
          decoration: const InputDecoration(
            filled: true,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          ),
          items: _testChoices
              .map(
                (option) =>
                    DropdownMenuItem(value: option, child: Text(option)),
              )
              .toList(),
          onChanged: _saving ? null : change,
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(_editing ? 'Edit record' : 'Client entry'),
      leading: BackButton(onPressed: _saving ? null : widget.onBack),
      actions: [
        if (_editing)
          IconButton(
            key: const ValueKey('update-record-top'),
            tooltip: 'Update record',
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_outlined),
          ),
      ],
    ),
    body: SafeArea(
      child: Form(
        key: _form,
        child: ListView(
          key: const ValueKey('client-entry-scroll'),
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.hotspot['name'] as String,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 20),
            Text('Client code', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('client-year'),
                    controller: _clientYear,
                    enabled: !_saving && !_editing,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Year',
                      counterText: '',
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(widget.session.activity),
                    validator: (value) =>
                        value == null || value.trim().length != 4
                        ? 'Use 4 digits.'
                        : null,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 18, 8, 0),
                  child: Text('/MY/'),
                ),
                Expanded(
                  child: TextFormField(
                    key: const ValueKey('client-number'),
                    controller: _clientNumber,
                    enabled: !_saving && !_editing,
                    autofocus: !_editing,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(4),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Number',
                      hintText: '0004',
                      counterText: '',
                    ),
                    textInputAction: TextInputAction.next,
                    onChanged: (_) => setState(widget.session.activity),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter the client number.'
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _editing
                  ? 'Client code cannot be changed while editing.'
                  : 'Saved as $_clientCode',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 20),
            Text('Client type', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              key: const ValueKey('client-kind'),
              segments: const [
                ButtonSegment(
                  value: 'Unspecified',
                  label: Text('Not specified'),
                ),
                ButtonSegment(value: 'New', label: Text('New')),
                ButtonSegment(value: 'Old', label: Text('Old')),
              ],
              selected: {_clientKind ?? 'Unspecified'},
              showSelectedIcon: false,
              onSelectionChanged: _saving
                  ? null
                  : (value) => _selectClientKind(
                      value.single == 'Unspecified' ? null : value.single,
                    ),
            ),
            if (_clientKind == 'New') ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('edit-new-client-details'),
                onPressed: _saving
                    ? null
                    : () async {
                        if (await _showNewClientDialog() && mounted) {
                          setState(() => _newClientDetailsComplete = true);
                        }
                      },
                icon: const Icon(Icons.edit_outlined),
                label: Text(
                  _newClientDetailsComplete
                      ? 'Edit new client details'
                      : 'Enter new client details',
                ),
              ),
            ],
            const SizedBox(height: 28),
            Text(
              'Testing',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _testChoice(
              'HIV',
              _hiv,
              (v) => setState(() => _hiv = v!),
              Theme.of(context).colorScheme.errorContainer,
              Theme.of(context).colorScheme.onErrorContainer,
            ),
            const SizedBox(height: 12),
            _testChoice(
              'HCV',
              _hcv,
              (v) => setState(() => _hcv = v!),
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.onPrimaryContainer,
            ),
            const SizedBox(height: 12),
            _testChoice(
              'HBV',
              _hbv,
              (v) => setState(() => _hbv = v!),
              Theme.of(context).colorScheme.secondaryContainer,
              Theme.of(context).colorScheme.onSecondaryContainer,
            ),
            const SizedBox(height: 12),
            _testChoice(
              'Syphilis',
              _syphilis,
              (v) => setState(() => _syphilis = v!),
              Theme.of(context).colorScheme.tertiaryContainer,
              Theme.of(context).colorScheme.onTertiaryContainer,
            ),
            const SizedBox(height: 28),
            Text(
              'Distribution',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _quantityGroup(
              context,
              title: 'Needles and syringes',
              color: Theme.of(context).colorScheme.primaryContainer,
              fields: const {
                'dist_3cc': '3cc',
                'dist_1cc': '1cc',
                'dist_lds': 'LDS',
              },
            ),
            const SizedBox(height: 12),
            _quantityGroup(
              context,
              title: 'Other supplies',
              color: Theme.of(context).colorScheme.tertiaryContainer,
              fields: const {
                'dist_alcohol_swab': 'Swab',
                'dist_sterile_water': 'Water',
                'dist_condom': 'Condom',
              },
            ),
            const SizedBox(height: 20),
            Text(
              'Recollection',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            _quantityGroup(
              context,
              title: 'Returned needles and syringes',
              color: Theme.of(context).colorScheme.secondaryContainer,
              fields: const {
                'recollect_3cc': '3cc',
                'recollect_1cc': '1cc',
                'recollect_lds': 'LDS',
              },
            ),
            const SizedBox(height: 20),
            SwitchListTile(
              key: const ValueKey('refer-dic'),
              title: const Text('Refer to DIC'),
              subtitle: Text(_referDic ? 'Yes' : 'No'),
              value: _referDic,
              onChanged: _saving
                  ? null
                  : (value) => setState(() => _referDic = value),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const ValueKey('remark'),
              controller: _remark,
              enabled: !_saving,
              minLines: 3,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Remark (optional)',
                alignLabelWithHint: true,
              ),
              onChanged: (_) => widget.session.activity(),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Text(
                _message!,
                key: const ValueKey('encounter-message'),
                style: TextStyle(
                  color: _message!.startsWith('Record saved')
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              key: const ValueKey('save-encounter'),
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  _saving
                      ? (_editing ? 'Updating...' : 'Saving...')
                      : (_editing ? 'Update record' : 'Save record'),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _quantityGroup(
    BuildContext context, {
    required String title,
    required Color color,
    required Map<String, String> fields,
  }) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final entry in fields.entries) ...[
              if (entry.key != fields.keys.first) const SizedBox(width: 8),
              Expanded(child: _quantityField(entry.key, entry.value)),
            ],
          ],
        ),
      ],
    ),
  );

  Widget _quantityField(String field, String label) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 4),
      TextFormField(
        key: ValueKey('quantity-$field'),
        controller: _quantities[field],
        enabled: !_saving,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(
          hintText: '0',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        validator: (value) {
          final number = int.tryParse(value?.trim() ?? '');
          return number != null && number >= 0
              ? null
              : 'Enter zero or a whole number.';
        },
        onChanged: (_) => widget.session.activity(),
      ),
    ],
  );
}
