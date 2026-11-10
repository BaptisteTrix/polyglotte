import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';
import '../services/ai_tutor.dart';
import '../services/reminders.dart';
import '../services/speech.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final keyCtrl = TextEditingController();
  final modelCtrl = TextEditingController();
  bool keyVisible = false;
  bool keySaved = false;

  @override
  void initState() {
    super.initState();
    _loadProvider();
  }

  Future<void> _loadProvider() async {
    final s = AppScope.read(context);
    final k = await AiTutor.getKey(s.aiProvider);
    if (!mounted) return;
    setState(() {
      keyCtrl.text = k ?? '';
      keySaved = (k ?? '').isNotEmpty;
      modelCtrl.text =
          s.aiModels[s.aiProvider] ?? providerInfo(s.aiProvider).defaultModel;
    });
  }

  Future<void> _saveAi() async {
    final s = AppScope.read(context);
    await AiTutor.setKey(s.aiProvider, keyCtrl.text);
    s.aiModels[s.aiProvider] = modelCtrl.text.trim().isEmpty
        ? providerInfo(s.aiProvider).defaultModel
        : modelCtrl.text.trim();
    await s.saveSettings();
    if (!mounted) return;
    setState(() => keySaved = keyCtrl.text.trim().isNotEmpty);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Réglages du tuteur enregistrés')));
  }

  Future<void> _setReminder(AppState s, bool on, [TimeOfDay? t]) async {
    s.reminderOn = on;
    if (t != null) {
      s.reminderHour = t.hour;
      s.reminderMinute = t.minute;
    }
    final ok = await Reminders.schedule(
        enabled: on, hour: s.reminderHour, minute: s.reminderMinute);
    if (!ok && on) s.reminderOn = false;
    await s.saveSettings();
    if (!ok && on && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Autorise les notifications pour recevoir le rappel.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppScope.of(context);
    final p = providerInfo(s.aiProvider);
    final cs = Theme.of(context).colorScheme;
    final time = TimeOfDay(hour: s.reminderHour, minute: s.reminderMinute);

    return Scaffold(
      appBar: AppBar(title: const Text('Réglages')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _header('Apprentissage'),
          ListTile(
            title: const Text('Nouveaux éléments par jour'),
            subtitle: Text('${s.newPerDay} par langue — plus = plus rapide, mais plus de révisions'),
          ),
          Slider(
            value: s.newPerDay.toDouble(),
            min: 3,
            max: 25,
            divisions: 22,
            label: '${s.newPerDay}',
            onChanged: (v) {
              s.newPerDay = v.round();
              s.saveSettings();
            },
          ),
          SwitchListTile(
            title: const Text('Afficher la prononciation'),
            subtitle: const Text('Pinyin / translittération sous les mots'),
            value: s.showRoman,
            onChanged: (v) {
              s.showRoman = v;
              s.saveSettings();
            },
          ),
          SwitchListTile(
            title: const Text('Exercices de prononciation'),
            subtitle: const Text('Parler dans le micro (reconnaissance vocale)'),
            value: s.speakingEnabled,
            onChanged: (v) {
              s.speakingEnabled = v;
              s.saveSettings();
            },
          ),
          ListTile(
            title: const Text('Vitesse de la voix'),
            subtitle: Text('${(s.ttsRate * 100).round()} %'),
            trailing: IconButton(
              icon: const Icon(Icons.volume_up),
              onPressed: () {
                Tts.rate = s.ttsRate;
                Tts.speak(s.lang == Lang.ru ? 'Привет! Как дела?' : '你好！你好吗？', s.lang);
              },
            ),
          ),
          Slider(
            value: s.ttsRate,
            min: 0.2,
            max: 0.8,
            divisions: 12,
            onChanged: (v) {
              s.ttsRate = v;
              Tts.rate = v;
              s.saveSettings();
            },
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Pas de voix ? Installe les voix russe et chinoise dans Paramètres Android › '
              'Synthèse vocale (moteur Google) › Installer les données vocales.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          _header('Rappel quotidien'),
          SwitchListTile(
            title: const Text('Me rappeler de pratiquer'),
            subtitle: Text('Chaque jour à ${time.format(context)}'),
            value: s.reminderOn,
            onChanged: (v) => _setReminder(s, v),
          ),
          ListTile(
            enabled: s.reminderOn,
            leading: const Icon(Icons.schedule),
            title: const Text('Heure du rappel'),
            trailing: Text(time.format(context)),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: time);
              if (t != null) await _setReminder(s, true, t);
            },
          ),
          _header('Tuteur IA'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: DropdownButtonFormField<String>(
              initialValue: s.aiProvider,
              decoration: const InputDecoration(labelText: 'Fournisseur'),
              items: [
                for (final x in aiProviders)
                  DropdownMenuItem(
                    value: x.id,
                    child: Text('${x.label}  ${x.free ? '· gratuit' : '· payant'}'),
                  ),
              ],
              onChanged: (v) async {
                if (v == null) return;
                s.aiProvider = v;
                await s.saveSettings();
                await _loadProvider();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Card(
              color: p.free ? Colors.green.withValues(alpha: 0.12) : cs.secondaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p.keyHelp),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: SelectableText(p.keyUrl,
                          style: TextStyle(color: cs.primary)),
                    ),
                    IconButton(
                      tooltip: 'Copier le lien',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: p.keyUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Lien copié')));
                      },
                    ),
                  ]),
                ]),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: TextField(
              controller: keyCtrl,
              obscureText: !keyVisible,
              decoration: InputDecoration(
                labelText: 'Clé API ${p.label}',
                helperText: keySaved ? 'Clé enregistrée sur ce téléphone (chiffrée)' : null,
                suffixIcon: IconButton(
                  icon: Icon(keyVisible ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => keyVisible = !keyVisible),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Autocomplete<String>(
              initialValue: TextEditingValue(text: modelCtrl.text),
              optionsBuilder: (_) => p.models,
              onSelected: (v) => modelCtrl.text = v,
              fieldViewBuilder: (context, ctrl, focus, onSubmit) {
                // Garde les deux contrôleurs synchronisés.
                if (ctrl.text != modelCtrl.text && !focus.hasFocus) {
                  ctrl.text = modelCtrl.text;
                }
                return TextField(
                  controller: ctrl,
                  focusNode: focus,
                  onChanged: (v) => modelCtrl.text = v,
                  decoration: const InputDecoration(
                    labelText: 'Modèle',
                    helperText: 'Touchez pour voir les suggestions, ou saisissez un autre nom.',
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: DropdownButtonFormField<String>(
              initialValue: s.tutorLevel,
              decoration: const InputDecoration(labelText: 'Mon niveau'),
              items: const [
                DropdownMenuItem(value: 'grand débutant (connaît seulement quelques mots)', child: Text('Grand débutant')),
                DropdownMenuItem(value: 'débutant', child: Text('Débutant')),
                DropdownMenuItem(value: 'intermédiaire', child: Text('Intermédiaire')),
                DropdownMenuItem(value: 'avancé', child: Text('Avancé')),
              ],
              onChanged: (v) {
                if (v == null) return;
                s.tutorLevel = v;
                s.saveSettings();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _saveAi,
              icon: const Icon(Icons.save),
              label: const Text('Enregistrer le tuteur'),
            ),
          ),
          _header('Données'),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            title: const Text('Réinitialiser ma progression'),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Tout effacer ?'),
                  content: const Text('Ta progression et ta série seront perdues.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
                    TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Effacer')),
                  ],
                ),
              );
              if (ok == true) await s.resetProgress();
            },
          ),
        ],
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Text(t,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold)),
      );
}
