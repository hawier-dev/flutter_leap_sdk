class LeapLogger {
  static void debug(String message) {
    print('[DEBUG] $message');
  }
  
  static void info(String message) {
    print('[INFO] $message');
  }
  
  static void warning(String message) {
    print('[WARNING] $message');
  }
  
  static void error(String message) {
    print('[ERROR] $message');
  }
}