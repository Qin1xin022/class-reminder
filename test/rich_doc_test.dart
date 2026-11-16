import 'package:flutter_test/flutter_test.dart';
import 'package:class_reminder/utils/rich_doc.dart';

void main() {
  group('rich_doc 编解码', () {
    test('有内容的行保存时必须全部保留（v1.13.14 回归：过滤条件反了丢光正文）', () {
      final doc = encodeRichDoc([
        RichLine(text: '第一段要点'),
        RichLine(text: '第二段', styles: {'b'}),
        RichLine(imagePath: '/data/rich_images/a.jpg'),
        RichLine(), // 空行不保留
      ]);
      final lines = decodeRichDoc(doc);
      final texts = lines.where((l) => !l.isImage).map((l) => l.text).toList();
      expect(texts, containsAll(['第一段要点', '第二段']));
      expect(lines.where((l) => l.isImage).length, 1);
    });

    test('历史坏数据 "[]" 解析不崩、至少有一个空行', () {
      final lines = decodeRichDoc('[]');
      expect(lines, isNotEmpty);
      expect(lines.first.isImage, isFalse);
    });

    test('全部空行保存结果为空字符串，重开仍可编辑', () {
      final doc = encodeRichDoc([RichLine(), RichLine()]);
      expect(doc, '');
      expect(decodeRichDoc(doc), isNotEmpty);
    });

    test('单个普通文本行存纯文本，图片行不走纯文本路径', () {
      expect(encodeRichDoc([RichLine(text: 'hello')]), 'hello');
      final imgDoc = encodeRichDoc([RichLine(imagePath: '/x/y.jpg')]);
      expect(imgDoc, contains('"t":"img"'));
      expect(decodeRichDoc(imgDoc).first.imagePath, '/x/y.jpg');
    });

    test('非法 JSON 回退为单行纯文本', () {
      final lines = decodeRichDoc('[这不是json');
      expect(lines.length, 1);
      expect(lines.first.text, '[这不是json');
    });
  });
}
