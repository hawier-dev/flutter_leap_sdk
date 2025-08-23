import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:flutter_leap_sdk/flutter_leap_sdk.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('FlutterLeapSdkService', () {
    late List<MethodCall> methodCalls;

    setUp(() {
      methodCalls = [];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_leap_sdk'),
        (MethodCall methodCall) async {
          methodCalls.add(methodCall);
          
          switch (methodCall.method) {
            case 'isModelLoaded':
              return false;
            case 'loadModel':
              return 'Model loaded successfully';
            case 'generateResponse':
              return 'Test response from AI';
            case 'unloadModel':
              return 'Model unloaded successfully';
            default:
              return null;
          }
        },
      );
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('flutter_leap_sdk'),
        null,
      );
    });

    test('checkModelLoaded returns correct status', () async {
      final result = await FlutterLeapSdkService.checkModelLoaded();
      
      expect(result, false);
      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'isModelLoaded');
    });

    test('loadModel calls native method with correct parameters', () async {
      const testPath = '/test/model.bundle';
      
      final result = await FlutterLeapSdkService.loadModel(modelPath: testPath);
      
      expect(result, 'Model loaded successfully');
      expect(methodCalls.length, 1);
      expect(methodCalls[0].method, 'loadModel');
      expect(methodCalls[0].arguments['modelPath'], testPath);
    });

    test('generateResponse works when model is loaded', () async {
      // First load a model
      await FlutterLeapSdkService.loadModel(modelPath: '/test/model.bundle');
      
      // Then generate response
      final result = await FlutterLeapSdkService.generateResponse('test message');
      
      expect(result, 'Test response from AI');
      expect(methodCalls.length, 2); // loadModel + generateResponse
      expect(methodCalls[1].method, 'generateResponse');
    });

    test('ModelInfo creates correctly from map', () {
      final map = {
        'fileName': 'test.bundle',
        'displayName': 'Test Model',
        'size': '100MB',
        'url': 'https://test.com/model',
      };

      final modelInfo = ModelInfo.fromMap(map);

      expect(modelInfo.fileName, 'test.bundle');
      expect(modelInfo.displayName, 'Test Model');
      expect(modelInfo.size, '100MB');
      expect(modelInfo.url, 'https://test.com/model');
    });

    test('DownloadProgress calculates percentage correctly', () {
      const progress = DownloadProgress(
        bytesDownloaded: 50,
        totalBytes: 100,
        percentage: 50.0,
      );

      expect(progress.percentage, 50.0);
      expect(progress.isComplete, false);

      const completeProgress = DownloadProgress(
        bytesDownloaded: 100,
        totalBytes: 100,
        percentage: 100.0,
      );

      expect(completeProgress.isComplete, true);
    });

    test('getModelDisplayName returns correct display name', () {
      const fileName = 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle';
      final displayName = FlutterLeapSdkService.getModelDisplayName(fileName);
      
      expect(displayName, 'LFM2-350M');
    });

    test('getModelInfo returns correct model info', () {
      const fileName = 'LFM2-350M-8da4w_output_8da8w-seq_4096.bundle';
      final modelInfo = FlutterLeapSdkService.getModelInfo(fileName);
      
      expect(modelInfo, isNotNull);
      expect(modelInfo!.displayName, 'LFM2-350M');
      expect(modelInfo.size, '322 MB');
    });

    test('exceptions have correct messages and codes', () {
      const exception = ModelLoadingException('Test error', 'TEST_CODE');
      
      expect(exception.message, 'Test error');
      expect(exception.code, 'TEST_CODE');
      expect(exception.toString(), 'FlutterLeapSdkException(TEST_CODE): Test error');
    });
  });
}