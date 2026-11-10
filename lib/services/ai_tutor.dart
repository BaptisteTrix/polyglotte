import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

class AiProviderInfo {
  final String id;
  final String label;
  final bool free;
  final String keyUrl;
  final String keyHelp;
  final String defaultModel;
  final List<String> models;
  const AiProviderInfo({
    required this.id,
    required this.label,
    required this.free,
    required this.keyUrl,
    required this.keyHelp,
    required this.defaultModel,
    required this.models,
  });
}

const aiProviders = <AiProviderInfo>[
  AiProviderInfo(
    id: 'gemini',
    label: 'Google Gemini',
    free: true,
    keyUrl: 'https://aistudio.google.com/apikey',
    keyHelp:
        'Gratuit (avec limites quotidiennes). Connecte-toi avec un compte Google sur AI Studio, puis « Create API key ». '
        'Sur l\'offre gratuite, Google peut utiliser les échanges pour améliorer ses produits.',
    defaultModel: 'gemini-2.5-flash',
    models: ['gemini-2.5-flash', 'gemini-2.5-flash-lite', 'gemini-2.5-pro'],
  ),
  AiProviderInfo(
    id: 'groq',
    label: 'Groq (Llama)',
    free: true,
    keyUrl: 'https://console.groq.com/keys',
    keyHelp:
        'Gratuit (avec limites). Crée un compte sur console.groq.com puis « Create API Key ». Très rapide, un peu moins précis en russe et en chinois.',
    defaultModel: 'llama-3.3-70b-versatile',
    models: ['llama-3.3-70b-versatile', 'llama-3.1-8b-instant'],
  ),
  AiProviderInfo(
    id: 'claude',
    label: 'Anthropic Claude',
    free: false,
    keyUrl: 'https://platform.claude.com/settings/keys',
    keyHelp:
        'Payant à l\'usage (quelques centimes par conversation). Excellente qualité de correction. Crée une clé sur la console Claude.',
    defaultModel: 'claude-opus-5-5',
    models: ['claude-opus-5-5', 'claude-sonnet-5-5', 'claude-haiku-5-5'],
  ),
];

AiProviderInfo providerInfo(String id) =>
    aiProviders.firstWhere((p) => p.id == id, orElse: () => aiProviders.first);

class ChatMsg {
  final bool fromUser;
  final String text;
  final bool hidden;
  const ChatMsg(this.fromUser, this.text, {this.hidden = false});
}

/// Réponse structurée du tuteur.
class TutorReply {
  final String raw;
  final String? target;
  final String? pron;
  final String? french;
  final String? correction;
  TutorReply(this.raw, {this.target, this.pron, this.french, this.correction});

  static TutorReply parse(String raw) {
    String? grab(String label) {
      final m = RegExp(
              '^[\\s*_#>-]*$label[\\s*_]*[:：][\\s*_]*(.+)\$',
              caseSensitive: false,
              multiLine: true)
          .firstMatch(raw);
      return m?.group(1)?.replaceAll('**', '').trim();
    }

    return TutorReply(
      raw,
      target: grab('CIBLE'),
      pron: grab('PRONONCIATION'),
      french: grab('FRAN[ÇC]AIS'),
      correction: grab('CORRECTION'),
    );
  }

  bool get structured => target != null;
}

class AiException implements Exception {
  final String message;
  AiException(this.message);
  @override
  String toString() => message;
}

class AiTutor {
  AiTutor._();
  static const _storage = FlutterSecureStorage();

  static Future<String?> getKey(String provider) async {
    try {
      return await _storage.read(key: 'key_$provider');
    } catch (_) {
      return null;
    }
  }

  static Future<void> setKey(String provider, String key) async {
    if (key.trim().isEmpty) {
      await _storage.delete(key: 'key_$provider');
    } else {
      await _storage.write(key: 'key_$provider', value: key.trim());
    }
  }

  static String systemPrompt(Lang lang, String level, String scenario) {
    final langName = lang == Lang.ru ? 'russe' : 'chinois mandarin';
    final pron = lang == Lang.ru
        ? 'translittération latine avec la voyelle accentuée marquée (ex : privét)'
        : 'pinyin avec les marques de ton (ex : nǐ hǎo)';
    final script = lang == Lang.zh
        ? ' Écris le chinois en caractères simplifiés.'
        : ' Écris le russe en cyrillique.';
    return '''
Tu es un tuteur de $langName chaleureux et patient pour un élève francophone de niveau $level.
Scénario de la conversation : $scenario.
Tu joues ton rôle dans la scène et tu fais avancer la conversation en posant une question simple à chaque réplique.
Adapte strictement ton vocabulaire au niveau de l'élève : phrases courtes, mots fréquents.$script
L'élève peut écrire en $langName, en ${lang == Lang.zh ? 'pinyin' : 'translittération'} ou en français.

Réponds TOUJOURS exactement dans ce format, sur 4 lignes, sans rien ajouter :
CIBLE: <ta réplique en $langName, 1 à 2 phrases courtes>
PRONONCIATION: <$pron>
FRANÇAIS: <traduction en français>
CORRECTION: <si le dernier message de l'élève contient une erreur ou est écrit en français, donne la formulation correcte en $langName avec sa prononciation et une explication très brève en français ; s'il est correct, écris « ✓ Parfait ! » ; pour ta toute première réplique, écris « — »>''';
  }

  /// Envoie la conversation et renvoie le texte de la réponse.
  static Future<String> send({
    required String provider,
    required String model,
    required String system,
    required List<ChatMsg> history,
  }) async {
    final key = await getKey(provider);
    if (key == null || key.isEmpty) {
      throw AiException(
          'Aucune clé API configurée. Ajoute-la dans Réglages › Tuteur IA.');
    }
    try {
      switch (provider) {
        case 'claude':
          return await _claude(key, model, system, history);
        case 'groq':
          return await _groq(key, model, system, history);
        default:
          return await _gemini(key, model, system, history);
      }
    } on AiException {
      rethrow;
    } on TimeoutException {
      throw AiException('Le serveur met trop de temps à répondre. Réessaie.');
    } catch (e) {
      throw AiException('Erreur réseau : vérifie ta connexion internet. ($e)');
    }
  }

  static Never _httpError(http.Response r, String apiName) {
    String detail = '';
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      detail = (j['error']?['message'] ?? j['error'] ?? '').toString();
    } catch (_) {}
    switch (r.statusCode) {
      case 400:
        throw AiException('Requête refusée par $apiName (modèle inconnu ?). $detail');
      case 401:
      case 403:
        throw AiException('Clé API $apiName invalide ou non autorisée. $detail');
      case 404:
        throw AiException('Modèle introuvable chez $apiName. Choisis-en un autre dans les réglages. $detail');
      case 429:
        throw AiException(
            'Limite de requêtes atteinte chez $apiName (quota gratuit ?). Attends une minute et réessaie.');
      default:
        throw AiException('Erreur $apiName (${r.statusCode}). $detail');
    }
  }

  // ---- Google Gemini ----
  static Future<String> _gemini(
      String key, String model, String system, List<ChatMsg> history) async {
    final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent');
    final body = {
      'systemInstruction': {
        'parts': [
          {'text': system}
        ]
      },
      'contents': [
        for (final m in history)
          {
            'role': m.fromUser ? 'user' : 'model',
            'parts': [
              {'text': m.text}
            ]
          }
      ],
    };
    final r = await http
        .post(uri,
            headers: {'content-type': 'application/json', 'x-goog-api-key': key},
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) _httpError(r, 'Gemini');
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    final parts = (j['candidates']?[0]?['content']?['parts'] as List?) ?? [];
    final text = parts
        .where((p) => p['thought'] != true && p['text'] != null)
        .map((p) => p['text'] as String)
        .join();
    if (text.trim().isEmpty) {
      throw AiException('Gemini n\'a pas renvoyé de réponse. Reformule ton message.');
    }
    return text;
  }

  // ---- Groq (API compatible OpenAI) ----
  static Future<String> _groq(
      String key, String model, String system, List<ChatMsg> history) async {
    final uri = Uri.parse('https://api.groq.com/openai/v1/chat/completions');
    final body = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': system},
        for (final m in history)
          {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text}
      ],
    };
    final r = await http
        .post(uri,
            headers: {
              'content-type': 'application/json',
              'authorization': 'Bearer $key'
            },
            body: jsonEncode(body))
        .timeout(const Duration(seconds: 60));
    if (r.statusCode != 200) _httpError(r, 'Groq');
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    return (j['choices']?[0]?['message']?['content'] ?? '').toString();
  }

  // ---- Anthropic Claude (Messages API) ----
  static Future<String> _claude(
      String key, String model, String system, List<ChatMsg> history) async {
    final uri = Uri.parse('https://api.anthropic.com/v1/messages');
    // Haiku n'a pas de bascule automatique côté serveur en cas de refus.
    final useFallbacks = !model.contains('haiku');
    final body = <String, dynamic>{
      'model': model,
      'max_tokens': 16000,
      'system': system,
      // Conversation simple : effort bas = réponses rapides et économiques.
      'output_config': {'effort': 'low'},
      'messages': [
        for (final m in history)
          {'role': m.fromUser ? 'user' : 'assistant', 'content': m.text}
      ],
      if (useFallbacks) 'fallbacks': 'default',
    };
    final headers = {
      'content-type': 'application/json',
      'x-api-key': key,
      'anthropic-version': '2026-10-21',
      if (useFallbacks) 'anthropic-beta': 'server-side-fallback-2026-07-01',
      if (kIsWeb) 'anthropic-dangerous-direct-browser-access': 'true',
    };
    final r = await http
        .post(uri, headers: headers, body: jsonEncode(body))
        .timeout(const Duration(seconds: 120));
    if (r.statusCode != 200) _httpError(r, 'Claude');
    final j = jsonDecode(utf8.decode(r.bodyBytes));
    if (j['stop_reason'] == 'refusal') {
      throw AiException('Le modèle a refusé de répondre à ce message. Reformule-le.');
    }
    final blocks = (j['content'] as List?) ?? [];
    return blocks
        .where((b) => b['type'] == 'text')
        .map((b) => b['text'] as String)
        .join();
  }
}
