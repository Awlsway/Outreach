import 'package:flutter/material.dart';
import '../auth/session_controller.dart';
import '../database/outreach_repository.dart';
import 'location_service.dart';

class NewHotspotForm extends StatefulWidget {
  const NewHotspotForm({
    super.key,
    required this.repository,
    required this.session,
    required this.location,
    required this.onSaved,
    required this.onBack,
  });
  final OutreachRepository repository;
  final SessionController session;
  final HotspotLocationService location;
  final VoidCallback onSaved;
  final VoidCallback onBack;

  @override
  State<NewHotspotForm> createState() => _NewHotspotFormState();
}

class _NewHotspotFormState extends State<NewHotspotForm> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _peers = [TextEditingController()];
  LocationCapture? _capture;
  bool _locating = true;
  bool _saving = false;
  int _request = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _locate();
    });
  }

  @override
  void dispose() {
    _request++;
    _name.dispose();
    for (final peer in _peers) {
      peer.dispose();
    }
    super.dispose();
  }

  Future<void> _locate() async {
    final request = ++_request;
    setState(() {
      _locating = true;
      _capture = null;
    });
    final result = await widget.location.capture();
    if (!mounted || request != _request) return;
    setState(() {
      _locating = false;
      _capture = result;
    });
  }

  Future<void> _save() async {
    if (_saving || _locating || !_form.currentState!.validate()) return;
    widget.session.activity();
    if (widget.session.currentWorkerId == null) {
      widget.session.lock();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.createHotspot(
        name: _name.text,
        peers: _peers.map((p) => p.text).toList(),
        latitude: _capture?.latitude,
        longitude: _capture?.longitude,
      );
      if (mounted) widget.onSaved();
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error =
              'Could not save the hotspot. Your form is still here. Please retry.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('New hotspot'),
      leading: BackButton(onPressed: _saving ? null : widget.onBack),
    ),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: Form(
            key: _form,
            child: ListView(
              padding: const EdgeInsets.all(20),
              children: [
                TextFormField(
                  key: const ValueKey('hotspot-name'),
                  controller: _name,
                  enabled: !_saving,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Hotspot name'),
                  onChanged: (_) => widget.session.activity(),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Enter the hotspot name.'
                      : null,
                ),
                const SizedBox(height: 24),
                Text(
                  'Assigned peers',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < _peers.length; i++)
                  Padding(
                    key: ObjectKey(_peers[i]),
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      key: ValueKey('peer-$i'),
                      controller: _peers[i],
                      enabled: !_saving,
                      textCapitalization: TextCapitalization.words,
                      onChanged: (_) => widget.session.activity(),
                      decoration: InputDecoration(
                        labelText: 'Peer ${i + 1}',
                        suffixIcon: _peers.length == 1
                            ? null
                            : IconButton(
                                tooltip: 'Remove peer ${i + 1}',
                                onPressed: _saving
                                    ? null
                                    : () {
                                        final removed = _peers[i];
                                        setState(() => _peers.removeAt(i));
                                        // Dispose after the old text field unmounts.
                                        WidgetsBinding.instance
                                            .addPostFrameCallback(
                                              (_) => removed.dispose(),
                                            );
                                      },
                                icon: const Icon(Icons.close),
                              ),
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    key: const ValueKey('add-peer'),
                    onPressed: _saving
                        ? null
                        : () => setState(
                            () => _peers.add(TextEditingController()),
                          ),
                    icon: const Icon(Icons.person_add_alt),
                    label: const Text('Add peer'),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _locating
                              ? 'Getting GPS location…'
                              : _capture?.available == true
                              ? 'Location captured'
                              : 'GPS unavailable',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        if (_locating) ...[
                          const LinearProgressIndicator(),
                          const SizedBox(height: 8),
                          const Text(
                            'Allow location access when prompted. This attempt takes up to 20 seconds.',
                          ),
                          TextButton(
                            onPressed: () {
                              _request++;
                              setState(() {
                                _locating = false;
                                _capture = const LocationCapture.unavailable(
                                  'Saved without GPS by your choice.',
                                );
                              });
                            },
                            child: const Text('Continue without GPS'),
                          ),
                        ] else if (_capture?.available == true) ...[
                          Text(
                            'Latitude: ${_capture!.latitude!.toStringAsFixed(6)}',
                          ),
                          Text(
                            'Longitude: ${_capture!.longitude!.toStringAsFixed(6)}',
                          ),
                          if (_capture!.accuracy != null &&
                              _capture!.accuracy!.isFinite)
                            Text(
                              'Estimated accuracy: ±${_capture!.accuracy!.round()} m',
                            ),
                        ] else
                          Text(
                            _capture?.reason ??
                                'You can still save this hotspot.',
                          ),
                        if (!_locating)
                          TextButton.icon(
                            onPressed: _saving ? null : _locate,
                            icon: const Icon(Icons.my_location),
                            label: const Text('Retry GPS'),
                          ),
                      ],
                    ),
                  ),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  key: const ValueKey('save-hotspot'),
                  onPressed: _saving || _locating ? null : _save,
                  icon: const Icon(Icons.check),
                  label: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_saving ? 'Saving…' : 'Save hotspot'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
