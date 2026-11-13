import 'package:web/web.dart' as web;

void setWebBusy(bool busy) {
  final el = web.document.getElementById('atril-busy');
  if (el == null) return;
  if (busy) {
    el.classList.add('on');
  } else {
    el.classList.remove('on');
  }
}
