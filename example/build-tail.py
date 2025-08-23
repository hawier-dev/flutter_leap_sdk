#!/usr/bin/env python3
"""
build-tail.py - Build APK and send via Tailscale to target device

Usage:
    python build-tail.py --debug    # Build debug APK
    python build-tail.py --release  # Build release APK
"""

import argparse
import subprocess
import sys
import os
import glob
import datetime
import shutil
from pathlib import Path

# Configure your target Tailscale device name here
TARGET_DEVICE_NAME = "asus"

def run_command(cmd, description=""):
    """Run a shell command and handle errors"""
    print(f"🔄 {description}")
    print(f"Running: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(cmd, check=True, capture_output=True, text=True)
        if result.stdout:
            print(result.stdout)
        return result
    except subprocess.CalledProcessError as e:
        print(f"❌ Error {description}: {e}")
        if e.stdout:
            print("STDOUT:", e.stdout)
        if e.stderr:
            print("STDERR:", e.stderr)
        sys.exit(1)

def find_apk_file(build_type):
    """Find the generated APK file"""
    if build_type == "debug":
        pattern = "build/app/outputs/flutter-apk/app-debug.apk"
    else:
        pattern = "build/app/outputs/flutter-apk/app-release.apk"
    
    apk_path = Path(pattern)
    if apk_path.exists():
        return str(apk_path)
    
    # Try alternative patterns
    alt_patterns = [
        f"build/app/outputs/flutter-apk/*{build_type}*.apk",
        f"build/app/outputs/apk/{build_type}/*.apk"
    ]
    
    for pattern in alt_patterns:
        files = glob.glob(pattern)
        if files:
            return files[0]
    
    return None

def rename_apk_with_version(apk_path, build_type):
    """Rename APK file with timestamp and version number"""
    # Get current timestamp
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    
    # Get original file path components
    original_path = Path(apk_path)
    directory = original_path.parent
    name_without_ext = original_path.stem
    extension = original_path.suffix
    
    # Create new filename with version number
    new_filename = f"{name_without_ext}_{timestamp}{extension}"
    new_path = directory / new_filename
    
    # Rename the file
    shutil.move(str(original_path), str(new_path))
    
    print(f"🏷️  APK renamed: {original_path.name} -> {new_filename}")
    return str(new_path)

def send_apk_via_tailscale(apk_path, device_name):
    """Send APK to device via Tailscale using 'tailscale cp'"""
    filename = os.path.basename(apk_path)
    
    # Use 'tailscale file cp' to send the file.
    # The destination 'device_name:' sends the file to the default Downloads folder.
    ts_cmd = [
        'tailscale',
        'file',
        'cp',
        apk_path,
        f'{device_name}:'
    ]
    
    run_command(ts_cmd, f"Sending {filename} to {device_name} via Tailscale")
    
    print(f"✅ APK sent successfully!")
    print(f"📱 Check the Downloads folder on {device_name} for {filename}")

def main():
    parser = argparse.ArgumentParser(description='Build Flutter APK and send via Tailscale')
    build_group = parser.add_mutually_exclusive_group(required=True)
    build_group.add_argument('--debug', action='store_true', help='Build debug APK')
    build_group.add_argument('--release', action='store_true', help='Build release APK')
    
    args = parser.parse_args()
    
    # Determine build type
    build_type = "debug" if args.debug else "release"
    
    print(f"🚀 Starting {build_type} build process...")
    
    # Check if we're in Flutter project directory
    if not os.path.exists('pubspec.yaml'):
        print("❌ Not in Flutter project directory (pubspec.yaml not found)")
        sys.exit(1)
    
    # Clean previous builds
    run_command(['flutter', 'clean'], "Cleaning previous builds")
    
    # Get dependencies
    run_command(['flutter', 'pub', 'get'], "Getting dependencies")
    
    # Build APK only for arm64-v8a
    if build_type == "debug":
        build_cmd = ['flutter', 'build', 'apk', '--debug', '--target-platform', 'android-arm64']
    else:
        build_cmd = ['flutter', 'build', 'apk', '--release', '--target-platform', 'android-arm64']
    
    run_command(build_cmd, f"Building {build_type} APK")
    
    # Find the generated APK
    apk_path = find_apk_file(build_type)
    if not apk_path:
        print(f"❌ Could not find {build_type} APK file")
        sys.exit(1)
    
    print(f"✅ APK built successfully: {apk_path}")
    
    # Get file size
    file_size = os.path.getsize(apk_path) / (1024 * 1024)  # MB
    print(f"📦 APK size: {file_size:.1f} MB")
    
    # Rename APK with version number
    versioned_apk_path = rename_apk_with_version(apk_path, build_type)
    
    # Send APK via Tailscale to the target device
    print(f"📡 Preparing to send APK to '{TARGET_DEVICE_NAME}' via Tailscale...")
    send_apk_via_tailscale(versioned_apk_path, TARGET_DEVICE_NAME)
    
    print(f"""
🎉 Build and transfer complete!

📱 On your {TARGET_DEVICE_NAME} device:
   1. Go to the Downloads folder
   2. Install {os.path.basename(versioned_apk_path)}
   3. Enable "Install from unknown sources" if needed
""")

if __name__ == "__main__":
    main()