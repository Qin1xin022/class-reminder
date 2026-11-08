import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'idea_list_screen.dart';
import 'note_list_screen.dart';
import 'resource_list_screen.dart';

/// 「记录」标签：笔记 + 灵感/痛点/想法 + 资源库，共用一块地，避免底部导航过长。
class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(
    length: 3,
    vsync: this,
    initialIndex: widget.initialTab.clamp(0, 2),
  );

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('记录'),
        bottom: TabBar(
          controller: _tab,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          unselectedLabelStyle: const TextStyle(fontSize: 14),
          tabs: [
            Tab(text: '笔记 ${s.notes.length}'),
            Tab(text: '灵感 ${s.ideaCount}'),
            Tab(text: '资源库 ${s.resources.length}'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [NotePane(), IdeaPane(), ResourcePane()],
      ),
    );
  }
}
