import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_leap_sdk/flutter_leap_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  
  group('Performance Tests', () {
    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_leap_sdk'),
        (MethodCall methodCall) async {
          // Simulate processing time
          await Future.delayed(const Duration(milliseconds: 10));
          
          switch (methodCall.method) {
            case 'loadModel':
              return 'Model loaded successfully';
            case 'generateResponse':
              return 'Generated response';
            default:
              return null;
          }
        },
      );
    });

    test('loadModel performance benchmark', () async {
      final stopwatch = Stopwatch()..start();
      
      await FlutterLeapSdkService.loadModel(modelPath: '/test/model.bundle');
      
      stopwatch.stop();
      print('loadModel took: ${stopwatch.elapsedMilliseconds}ms');
      
      // Assert performance threshold
      expect(stopwatch.elapsedMilliseconds, lessThan(100));
    });

    test('multiple generateResponse calls', () async {
      // Load model first
      await FlutterLeapSdkService.loadModel(modelPath: '/test/model.bundle');
      
      final stopwatch = Stopwatch()..start();
      
      // Generate multiple responses
      for (int i = 0; i < 10; i++) {
        await FlutterLeapSdkService.generateResponse('Test message $i');
      }
      
      stopwatch.stop();
      print('10 generateResponse calls took: ${stopwatch.elapsedMilliseconds}ms');
      
      // Average should be reasonable
      final avgTime = stopwatch.elapsedMilliseconds / 10;
      expect(avgTime, lessThan(50));
    });
  });
}