#!/usr/bin/env python3
"""Build a thin Hopper Tool Plugin for the selected host SDK ABI."""
import argparse
from pathlib import Path
import platform
import shutil
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--identity", default="-")
    parser.add_argument("--architecture", choices=("arm64", "x86_64"), default=platform.machine())
    parser.add_argument("--sdk-version", type=int, default=4)
    parser.add_argument("--output", type=Path, help="Destination plugin bundle path")
    options = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    sdk = root / "HopperSDK"
    if not sdk.exists():
        sdk = root.parent / "HopperMCP-Upstream/Hopper/Sources/Hopper/include"
    # File Provider may attach Finder metadata to bundles inside Documents.
    # Sign on a local staging volume, then copy file contents to destinations.
    with tempfile.TemporaryDirectory(prefix="hopper-mcp-build-") as staging:
        bundle = Path(staging) / "HopperMCPBridge.hopperTool"
        contents = bundle / "Contents"
        (contents / "MacOS").mkdir(parents=True, exist_ok=True)
        shutil.copyfile(root / "Plugin/Info.plist", contents / "Info.plist")
        (contents / "Resources").mkdir()
        shutil.copyfile(root / "Plugin/api-native.json", contents / "Resources/api-native.json")
        sources = sorted(root.glob("Plugin/*.m"))
        subprocess.run([
            "xcrun", "clang", "-fobjc-arc", "-fmodules", "-Wall", "-Wextra", "-Werror",
            "-Wno-nullability-completeness", "-Wno-deprecated-declarations",
            "-mmacosx-version-min=12.0", "-arch", options.architecture,
            "-DHB_HOPPER_SDK_VERSION=" + str(options.sdk_version), "-I" + str(sdk),
            "-Wl,-no_fixup_chains,-no_data_const",
            "-bundle", "-framework", "Foundation", *map(str, sources),
            "-o", str(contents / "MacOS/HopperMCPBridge"),
        ], check=True)
        subprocess.run(["codesign", "--force", "--sign", options.identity, str(bundle)], check=True)
        destinations = [options.output or root / "Build/HopperMCPBridge.hopperTool"]
        for destination in destinations:
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copytree(bundle, destination, dirs_exist_ok=True, copy_function=shutil.copyfile)
            subprocess.run(["xattr", "-d", "com.apple.FinderInfo", str(destination)],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run(["codesign", "--verify", "--strict", str(destination)], check=True)
            print(destination)


if __name__ == "__main__":
    main()
