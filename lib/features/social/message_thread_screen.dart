import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_client.dart';
import '../../core/theme/foe_theme.dart';
import '../../core/ui/pressable.dart';
import '../common/widgets/parchment_page.dart';
import '../settlement/widgets/parchment_sheet.dart';
import 'models/message.dart';
import 'services/messages_service.dart';

/// One 1:1 chat thread. Loads history via [MessagesService.loadThread], then
/// stays live via a Realtime subscription (messages_service.dart) — the
/// fallback/on-open load means a message sent while this screen's socket was
/// dropped still shows up next time it's opened.
class MessageThreadScreen extends StatefulWidget {
  final String otherUserId;
  final String otherUsername;

  const MessageThreadScreen({
    super.key,
    required this.otherUserId,
    required this.otherUsername,
  });

  @override
  State<MessageThreadScreen> createState() => _MessageThreadScreenState();
}

class _MessageThreadScreenState extends State<MessageThreadScreen> {
  final _svc = MessagesService();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  RealtimeChannel? _channel;
  List<ChatMessage> _messages = [];
  bool _loading = true;

  String get _myId => supabase.auth.currentUser!.id;

  @override
  void initState() {
    super.initState();
    _load();
    _channel = _svc.subscribeToMessages((msg) {
      final mine = (msg.senderId == _myId && msg.recipientId == widget.otherUserId) ||
          (msg.senderId == widget.otherUserId && msg.recipientId == _myId);
      if (!mine || !mounted) return;
      setState(() => _messages = [..._messages, msg]);
      if (msg.recipientId == _myId) _svc.markThreadRead(widget.otherUserId);
      _scrollToEnd();
    });
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final msgs = await _svc.loadThread(widget.otherUserId);
    await _svc.markThreadRead(widget.otherUserId);
    if (!mounted) return;
    setState(() {
      _messages = msgs;
      _loading = false;
    });
    _scrollToEnd();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text;
    if (text.trim().isEmpty) return;
    _inputCtrl.clear();
    await _svc.sendMessage(widget.otherUserId, text);
  }

  @override
  Widget build(BuildContext context) => ParchmentPage(
    title: widget.otherUsername,
    bands: false,
    child: Column(
      children: [
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  controller: _scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  itemCount: _messages.length,
                  itemBuilder: (context, i) => _bubble(_messages[i]),
                ),
        ),
        _composer(),
      ],
    ),
  );

  Widget _bubble(ChatMessage m) {
    final mine = m.sentByMe(_myId);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 280),
        decoration: ShapeDecoration(
          color: mine
              ? ParchmentSheet.accent.withValues(alpha: 0.18)
              : ParchmentSheet.ink.withValues(alpha: 0.06),
          shape: FoE.facet(radius: 12),
        ),
        child: Text(
          m.body,
          style: FoE.label(size: 13).copyWith(color: ParchmentSheet.ink),
        ),
      ),
    );
  }

  Widget _composer() => Padding(
    padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
    child: Row(
      children: [
        Expanded(
          child: TextField(
            controller: _inputCtrl,
            onSubmitted: (_) => _send(),
            textInputAction: TextInputAction.send,
            style: FoE.label(size: 13).copyWith(color: ParchmentSheet.ink),
            decoration: InputDecoration(
              hintText: 'Message…',
              hintStyle: FoE.label(size: 13).copyWith(color: ParchmentSheet.inkFaint),
              filled: true,
              fillColor: ParchmentSheet.ink.withValues(alpha: 0.04),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Pressable(
          onTap: _send,
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: ShapeDecoration(
              color: ParchmentSheet.accent,
              shape: FoE.facet(radius: 20),
            ),
            child: const Icon(Icons.send_rounded, size: 18, color: Colors.white),
          ),
        ),
      ],
    ),
  );
}
