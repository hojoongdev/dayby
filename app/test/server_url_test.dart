import 'package:dayby/providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a bare IP gets http and the default port', () {
    expect(normalizeServerUrl('192.168.68.79'), 'http://192.168.68.79:8000');
  });
  test('an IP with a port is kept as typed', () {
    expect(normalizeServerUrl('192.168.68.79:9000'), 'http://192.168.68.79:9000');
  });
  test('a full URL with a scheme is left alone', () {
    expect(normalizeServerUrl('https://dayby.example.com'), 'https://dayby.example.com');
  });
  test('a trailing slash is trimmed', () {
    expect(normalizeServerUrl('192.168.0.10/'), 'http://192.168.0.10:8000');
  });
}
