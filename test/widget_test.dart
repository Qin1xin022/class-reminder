// 最小化冒烟测试：只验证工程能编译、测试框架可用。
// 真正的界面测试以后可在此基础上扩展。
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('工程骨架可用', () {
    expect(1 + 1, 2);
  });
}
