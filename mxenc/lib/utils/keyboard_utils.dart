import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

class KeyboardUtils {
  static void hide(BuildContext context) {
    FocusScope.of(context).unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }
}
