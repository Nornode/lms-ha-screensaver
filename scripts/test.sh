#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

echo "==> 1. Checking Lua syntax (luac -p)..."
for f in radio-applet/HAScreenSaver/*.lua; do
    luac -p "$f"
    echo "    OK: $f"
done

echo "==> 2. Checking Lua 5.1 compatibility (no Lua 5.2+ operators/keywords)..."
if grep -nE '(\bgoto\b|//|<<|>>|<const>|<close>)' radio-applet/HAScreenSaver/*.lua; then
    echo "ERROR: Found Lua 5.2+ syntax in radio-applet/HAScreenSaver/*.lua" >&2
    exit 1
fi
echo "    OK: Lua 5.1 compatible"

echo "==> 3. Running Lua unit tests..."
lua tests/lua/test_model.lua

echo "==> 4. Running Perl unit tests (with LMS stubs)..."
perl tests/perl/plugin.t

echo "==> 5. Checking Perl Settings.pm & PlayerSettings.pm syntax (with minimal stubs)..."
perl -e '
    BEGIN {
        unshift @INC, "server-plugin";
        $INC{"Slim/Web/Settings.pm"}  = 1;
        $INC{"Slim/Web/HTTP/CSRF.pm"} = 1;
        $INC{"Slim/Utils/Prefs.pm"}   = 1;
        package Slim::Web::Settings;
        sub new { return bless {}, shift; }
        package Slim::Web::HTTP::CSRF;
        sub protectName { shift; return shift; }
        sub protectURI  { shift; return shift; }
        package Slim::Utils::Prefs;
        use Exporter "import";
        our @EXPORT = qw(preferences);
        sub preferences { return bless {}, "S"; }
    }
    require HAScreenSaver::Settings;
    require HAScreenSaver::PlayerSettings;
    print "    OK: Settings.pm and PlayerSettings.pm compile cleanly\n";
'

echo "==> 6. Checking strings.txt files for CRLF line endings..."
if grep -l $'\r' server-plugin/HAScreenSaver/strings.txt radio-applet/HAScreenSaver/strings.txt; then
    echo "ERROR: Found CR/CRLF line endings in strings.txt (must use Unix LF)" >&2
    exit 1
fi
echo "    OK: strings.txt files use Unix LF"

echo "==> All local tests passed!"
