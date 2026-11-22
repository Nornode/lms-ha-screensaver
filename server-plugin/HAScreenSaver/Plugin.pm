package Plugins::HAScreenSaver::Plugin;

use strict;
use warnings;

use base qw(Slim::Plugin::Base);

use Digest::SHA qw(sha1_hex);
use File::Basename qw(dirname);
use File::Spec::Functions qw(catfile);
use JSON::XS::VersionOneAndTwo;
use POSIX qw(strftime);

use Slim::Control::Request;
use Slim::Networking::SimpleAsyncHTTP;
use Slim::Utils::Log;
use Slim::Utils::Prefs;
use Slim::Web::Pages;

our $VERSION = '1.3.0';

my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.hascreensaver',
    defaultLevel => 'ERROR',
    description  => 'PLUGIN_HASCREENSAVER',
});

my $prefs = preferences('plugin.hascreensaver');

my %ALLOWED_FONTS = map { $_ => 1 } (
    'FreeSansBold',
    'FreeSans',
    'FreeMonoBold',
    'FreeSerifBold',
);

my %INACTIVE_ALERT_STATES = map { $_ => 1 } (
    '',
    'off',
    'closed',
    'close',
    'none',
    'ok',
    'normal',
    'clear',
    'false',
    '0',
    'unknown',
    'unavailable',
);

my %WEATHER_ICON_MAP = (
    'sunny'           => 'sunny',
    'clear'           => 'sunny',
    'clear-night'     => 'clear_night',
    'partlycloudy'    => 'partlycloudy',
    'partly-cloudy'   => 'partlycloudy',
    'cloudy'          => 'cloudy',
    'overcast'        => 'cloudy',
    'rainy'           => 'rainy',
    'rain'            => 'rainy',
    'pouring'         => 'pouring',
    'snowy'           => 'snowy',
    'snow'            => 'snowy',
    'snowy-rainy'     => 'snowy',
    'hail'            => 'pouring',
    'fog'             => 'fog',
    'mist'            => 'fog',
    'lightning'       => 'lightning',
    'lightning-rainy' => 'lightning',
    'windy'           => 'windy',
    'windy-variant'   => 'windy',
);

sub initPlugin {
    my $class = shift;

    $prefs->init({
        ha_url           => '',
        ha_token         => '',
        poll_interval    => 60,
        font_name        => 'FreeSansBold',
        weather_entity   => '',
        alert_entity     => '',
        alert_label      => 'Open',
        sensor1_entity   => '',
        sensor1_label    => '',
        sensor1_decimals => '1',
        sensor1_unit     => '',
        sensor2_entity   => '',
        sensor2_label    => '',
        sensor2_decimals => '1',
        sensor2_unit     => '',
        sensor3_entity   => '',
        sensor3_label    => '',
        sensor3_decimals => '1',
        sensor3_unit     => '',
        sensor4_entity   => '',
        sensor4_label    => '',
        sensor4_decimals => '1',
        sensor4_unit     => '',
    });

    if (main::WEBUI) {
        require Plugins::HAScreenSaver::Settings;
        Plugins::HAScreenSaver::Settings->new;

        require Plugins::HAScreenSaver::PlayerSettings;
        Plugins::HAScreenSaver::PlayerSettings->new;
    }

    # Player-aware live sensor + alarm query (stateless, zero caching)
    Slim::Control::Request::addDispatch(
        ['hascreensaver', 'sensors'],
        [0, 1, 0, \&handleSensorsRequest]
    );

    # Stateless event trigger so HA automations can push an immediate refresh
    Slim::Control::Request::addDispatch(
        ['hascreensaver', 'refresh'],
        [0, 0, 0, \&handleRefreshRequest]
    );

    # Self-hosted local AppletInstaller repository endpoints
    Slim::Web::Pages->addPageFunction(
        qr/^plugins\/HAScreenSaver\/repo\.xml$/,
        \&handleRepoXml
    );
    Slim::Web::Pages->addPageFunction(
        qr/^plugins\/HAScreenSaver\/HAScreenSaver\.zip$/,
        \&handleAppletZip
    );

    # Register native Jive extension provider so Squeezebox Radios discover and
    # download the bundled applet directly from LMS over plain HTTP (no HTTPS
    # failure on SqueezeOS and no extra repository URL required).
    eval {
        require Slim::Control::Jive;
        Slim::Control::Jive::registerExtensionProvider('hascreensaver', \&getJiveExtensions);
    };

    $class->SUPER::initPlugin(@_);
}

sub shutdownPlugin {
    my $class = shift;

    eval {
        require Slim::Control::Jive;
        Slim::Control::Jive::removeExtensionProvider('hascreensaver');
    };

    $class->SUPER::shutdownPlugin(@_) if $class->can('SUPER::shutdownPlugin');
}

sub getDisplayName {
    return 'PLUGIN_HASCREENSAVER';
}

sub resolveHAConfig {
    my ($prefObj, $envRef) = @_;
    $envRef ||= \%ENV;

    my $customUrl   = _trim($prefObj->get('ha_url'));
    my $customToken = _trim($prefObj->get('ha_token'));

    if ($customUrl ne '') {
        $customUrl =~ s{/+$}{};
        return ($customUrl, $customToken, 'custom');
    }

    my $supToken = _trim($envRef->{SUPERVISOR_TOKEN});
    if ($supToken ne '') {
        return ('http://supervisor/core', $supToken, 'supervisor');
    }

    return ('', '', 'unconfigured');
}

sub sanitizePollInterval {
    my ($val) = @_;
    $val = 60 unless defined $val && $val =~ /^\d+$/;
    $val = 10  if $val < 10;
    $val = 300 if $val > 300;
    return int($val);
}

sub sanitizeFontName {
    my ($font) = @_;
    $font = _trim($font);
    return $ALLOWED_FONTS{$font} ? $font : 'FreeSansBold';
}

sub playerPrefKeys {
    return (
        'player_font_name',
        'player_weather_entity',
        'player_alert_entity',
        'player_alert_label',
        map {
            (
                "player_sensor${_}_entity",
                "player_sensor${_}_label",
                "player_sensor${_}_decimals",
                "player_sensor${_}_unit",
            )
        } (1 .. 4)
    );
}

sub isHiddenOverride {
    my ($val) = @_;
    return lc(_trim($val)) eq 'none' ? 1 : 0;
}

sub resolveEffectiveConfig {
    my ($prefObj, $client) = @_;

    my $cprefs = ($client && $prefObj && $prefObj->can('client'))
        ? $prefObj->client($client)
        : undef;

    my $hasOverrides = 0;
    my $pollInterval = sanitizePollInterval($prefObj ? $prefObj->get('poll_interval') : undef);

    my $pFont = $cprefs ? _trim($cprefs->get('player_font_name')) : '';
    my $fontName;
    if ($pFont ne '') {
        $hasOverrides = 1;
        $fontName     = sanitizeFontName($pFont);
    } else {
        $fontName = sanitizeFontName($prefObj ? $prefObj->get('font_name') : undef);
    }

    my $pWeather = $cprefs ? _trim($cprefs->get('player_weather_entity')) : '';
    my $weatherEntity;
    if (isHiddenOverride($pWeather)) {
        $hasOverrides  = 1;
        $weatherEntity = '';
    } elsif ($pWeather ne '') {
        $hasOverrides  = 1;
        $weatherEntity = $pWeather;
    } else {
        $weatherEntity = $prefObj ? _trim($prefObj->get('weather_entity')) : '';
    }

    my $pAlert = $cprefs ? _trim($cprefs->get('player_alert_entity')) : '';
    my ($alertEntity, $alertLabel);
    if (isHiddenOverride($pAlert)) {
        $hasOverrides = 1;
        $alertEntity  = '';
        $alertLabel   = '';
    } elsif ($pAlert ne '') {
        $hasOverrides = 1;
        $alertEntity  = $pAlert;
        $alertLabel   = _trim($cprefs->get('player_alert_label'));
    } else {
        $alertEntity = $prefObj ? _trim($prefObj->get('alert_entity')) : '';
        $alertLabel  = $prefObj ? _trim($prefObj->get('alert_label'))  : '';
    }

    my @slots;
    for my $i (1 .. 4) {
        my $pEntity = $cprefs ? _trim($cprefs->get("player_sensor${i}_entity")) : '';
        if (isHiddenOverride($pEntity)) {
            $hasOverrides = 1;
            next;
        } elsif ($pEntity ne '') {
            $hasOverrides = 1;
            my $dec = _trim($cprefs->get("player_sensor${i}_decimals"));
            if ($dec eq '' && $prefObj) {
                $dec = _trim($prefObj->get("sensor${i}_decimals"));
            }
            push @slots, {
                index    => scalar(@slots),
                entity   => $pEntity,
                label    => _trim($cprefs->get("player_sensor${i}_label")),
                decimals => $dec,
                unit     => _trim($cprefs->get("player_sensor${i}_unit")),
            };
        } else {
            my $gEntity = $prefObj ? _trim($prefObj->get("sensor${i}_entity")) : '';
            next if $gEntity eq '';
            push @slots, {
                index    => scalar(@slots),
                entity   => $gEntity,
                label    => _trim($prefObj->get("sensor${i}_label")),
                decimals => _trim($prefObj->get("sensor${i}_decimals")),
                unit     => _trim($prefObj->get("sensor${i}_unit")),
            };
        }
    }

    return {
        poll_interval  => $pollInterval,
        font_name      => $fontName,
        weather_entity => $weatherEntity,
        alert_entity   => $alertEntity,
        alert_label    => $alertLabel,
        slots          => \@slots,
        has_overrides  => $hasOverrides,
    };
}

sub describeOverrides {
    my ($getter) = @_;
    return 'Using Global Defaults' unless ref($getter) eq 'CODE';

    my @parts;

    my $pFont = _trim($getter->('player_font_name'));
    if ($pFont ne '') {
        push @parts, 'Font (' . sanitizeFontName($pFont) . ')';
    }

    my $pWeather = _trim($getter->('player_weather_entity'));
    if (isHiddenOverride($pWeather)) {
        push @parts, 'Weather (hidden)';
    } elsif ($pWeather ne '') {
        push @parts, 'Weather (custom)';
    }

    my $pAlert = _trim($getter->('player_alert_entity'));
    if (isHiddenOverride($pAlert)) {
        push @parts, 'Alert (hidden)';
    } elsif ($pAlert ne '') {
        my $lbl = _trim($getter->('player_alert_label'));
        push @parts, 'Alert (' . ($lbl ne '' ? $lbl : 'custom') . ')';
    }

    for my $i (1 .. 4) {
        my $pEntity = _trim($getter->("player_sensor${i}_entity"));
        if (isHiddenOverride($pEntity)) {
            push @parts, "Sensor $i (hidden)";
        } elsif ($pEntity ne '') {
            my $lbl = _trim($getter->("player_sensor${i}_label"));
            push @parts, "Sensor $i (" . ($lbl ne '' ? $lbl : $pEntity) . ')';
        }
    }

    return @parts ? join(', ', @parts) : 'Using Global Defaults';
}

sub describeClientOverrides {
    my ($prefObj, $client) = @_;
    return 'Using Global Defaults' unless $client && $prefObj && $prefObj->can('client');

    my $cprefs = $prefObj->client($client);
    return 'Using Global Defaults' unless $cprefs;

    return describeOverrides(sub {
        my ($key) = @_;
        return $cprefs->get($key);
    });
}

sub formatSensorState {
    my ($stateData, $slot) = @_;
    my $label = _trim($slot->{label});

    if (!ref($stateData) || !defined $stateData->{state}) {
        return {
            label => $label,
            value => '--',
            unit  => _trim($slot->{unit}),
            ok    => 0,
        };
    }

    my $raw = _trim($stateData->{state});
    my $lc  = lc($raw);
    if ($raw eq '' || $lc eq 'unknown' || $lc eq 'unavailable') {
        return {
            label => $label,
            value => '--',
            unit  => _trim($slot->{unit}),
            ok    => 0,
        };
    }

    my $unit = _trim($slot->{unit});
    if ($unit eq '' && ref($stateData->{attributes}) && defined $stateData->{attributes}->{unit_of_measurement}) {
        $unit = _trim($stateData->{attributes}->{unit_of_measurement});
    }

    my $value = $raw;
    my $dec   = _trim($slot->{decimals});
    if ($raw =~ /^[+-]?(?:\d+\.?\d*|\.\d+)$/ && $dec =~ /^\d+$/) {
        my $d = int($dec);
        $d = 4 if $d > 4;
        $value = sprintf("%.${d}f", $raw + 0);
    }

    return {
        label => $label,
        value => $value,
        unit  => $unit,
        ok    => 1,
    };
}

sub formatAlertState {
    my ($stateData, $prefixLabel) = @_;
    $prefixLabel = _trim($prefixLabel);

    if (!ref($stateData) || !defined $stateData->{state}) {
        return { active => 0, text => '' };
    }

    my $raw = _trim($stateData->{state});
    my $lc  = lc($raw);
    if ($INACTIVE_ALERT_STATES{$lc}) {
        return { active => 0, text => '' };
    }

    my $text;
    if ($lc eq 'on' || $lc eq 'open' || $lc eq 'true' || $lc eq 'detected') {
        my $friendly = (ref($stateData->{attributes}) && defined $stateData->{attributes}->{friendly_name})
            ? _trim($stateData->{attributes}->{friendly_name})
            : '';
        if ($prefixLabel ne '') {
            $text = $prefixLabel;
        } elsif ($friendly ne '') {
            $text = "$friendly: Open";
        } else {
            $text = 'Alert';
        }
    } else {
        $text = ($prefixLabel ne '') ? "$prefixLabel: $raw" : $raw;
    }

    return { active => 1, text => $text };
}

sub formatWeatherIcon {
    my ($stateData) = @_;
    return '' unless ref($stateData) && defined $stateData->{state};
    my $lc = lc(_trim($stateData->{state}));
    return $WEATHER_ICON_MAP{$lc} || '';
}

sub getPlayerAlarmInfo {
    my ($client) = @_;
    return { alarm_active => 0, alarm_time => '' } unless $client;

    my $nextAlarm = eval {
        require Slim::Utils::Alarm;
        Slim::Utils::Alarm->getNextAlarm($client);
    };
    return { alarm_active => 0, alarm_time => '' } unless $nextAlarm;

    my $timeStr = '';
    my $epoch = eval { $nextAlarm->findNextTime() };
    if (defined $epoch && $epoch > 0) {
        $timeStr = strftime('%H:%M', localtime($epoch));
    } elsif (eval { defined $nextAlarm->time() }) {
        my $secs = $nextAlarm->time();
        my $h = int($secs / 3600) % 24;
        my $m = int(($secs % 3600) / 60);
        $timeStr = sprintf('%02d:%02d', $h, $m);
    }

    return {
        alarm_active => 1,
        alarm_time   => $timeStr,
    };
}

sub handleRefreshRequest {
    my ($request) = @_;
    if ($request->isNotCommand([['hascreensaver'], ['refresh']])) {
        $request->setStatusBadDispatch();
        return;
    }

    # Broadcast a stateless refresh notification to subscribed players
    Slim::Control::Request::notifyFromArray($request->client(), ['hascreensaver', 'refresh']);
    $request->addResult('status', 'ok');
    $request->setStatusDone();
}

sub _populateSensorsResponse {
    my ($request, $cfg, $alarmInfo, $weatherIcon, $alertRes, $results, $mode) = @_;

    $request->addResult('poll_interval', $cfg->{poll_interval});
    $request->addResult('font_name',     $cfg->{font_name});
    $request->addResult('alarm_active',  $alarmInfo->{alarm_active});
    $request->addResult('alarm_time',    $alarmInfo->{alarm_time});
    $request->addResult('weather_icon',  $weatherIcon);
    $request->addResult('alert_active',  $alertRes->{active});
    $request->addResult('alert_text',    $alertRes->{text});
    $request->addResult('sensors_loop',  $results);
    $request->addResult('mode',          $mode);
    $request->addResult('config_scope',  $cfg->{has_overrides} ? 'player' : 'default');
    $request->setStatusDone();
}

sub handleSensorsRequest {
    my ($request) = @_;

    if ($request->isNotQuery([['hascreensaver'], ['sensors']])) {
        $request->setStatusBadDispatch();
        return;
    }

    my $client    = $request->client();
    my $cfg       = resolveEffectiveConfig($prefs, $client);
    my $alarmInfo = getPlayerAlarmInfo($client);

    my ($baseUrl, $token, $mode) = resolveHAConfig($prefs, \%ENV);

    my @slots         = @{ $cfg->{slots} };
    my $weatherEntity = $cfg->{weather_entity};
    my $alertEntity   = $cfg->{alert_entity};
    my $alertLabel    = $cfg->{alert_label};

    my $totalFetches = scalar(@slots)
        + ($weatherEntity ne '' ? 1 : 0)
        + ($alertEntity   ne '' ? 1 : 0);

    if ($totalFetches == 0 || $mode eq 'unconfigured') {
        my @fallbackSensors = map { formatSensorState(undef, $_) } @slots;
        _populateSensorsResponse($request, $cfg, $alarmInfo, '', { active => 0, text => '' }, \@fallbackSensors, $mode);
        return;
    }

    $request->setStatusProcessing();

    my @results     = map { formatSensorState(undef, $_) } @slots;
    my $weatherIcon = '';
    my $alertRes    = { active => 0, text => '' };
    my $remaining   = $totalFetches;

    my $finishOne = sub {
        $remaining--;
        return if $remaining > 0;
        _populateSensorsResponse($request, $cfg, $alarmInfo, $weatherIcon, $alertRes, \@results, $mode);
    };

    my @headers = (
        'Accept'        => 'application/json',
        'Cache-Control' => 'no-cache',
    );
    if ($token ne '') {
        push @headers, ('Authorization' => "Bearer $token");
    }

    for my $slot (@slots) {
        my $idx = $slot->{index};
        my $url = $baseUrl . '/api/states/' . $slot->{entity};

        my $http = Slim::Networking::SimpleAsyncHTTP->new(
            sub {
                my $resp = shift;
                my $data = eval { decode_json($resp->content) };
                if ($@ || !ref($data)) {
                    $log->warn("Invalid JSON from Home Assistant for $slot->{entity}");
                    $results[$idx] = formatSensorState(undef, $slot);
                } else {
                    $results[$idx] = formatSensorState($data, $slot);
                }
                $finishOne->();
            },
            sub {
                my ($httpObj, $err) = @_;
                $log->warn("HA fetch failed for $slot->{entity}: $err");
                $results[$idx] = formatSensorState(undef, $slot);
                $finishOne->();
            },
            {
                cache   => 0,
                timeout => 5,
            }
        );

        $http->get($url, @headers);
    }

    if ($weatherEntity ne '') {
        my $url = $baseUrl . '/api/states/' . $weatherEntity;

        my $http = Slim::Networking::SimpleAsyncHTTP->new(
            sub {
                my $resp = shift;
                my $data = eval { decode_json($resp->content) };
                if ($@ || !ref($data)) {
                    $log->warn("Invalid JSON from Home Assistant for weather $weatherEntity");
                    $weatherIcon = '';
                } else {
                    $weatherIcon = formatWeatherIcon($data);
                }
                $finishOne->();
            },
            sub {
                my ($httpObj, $err) = @_;
                $log->warn("HA weather fetch failed for $weatherEntity: $err");
                $weatherIcon = '';
                $finishOne->();
            },
            {
                cache   => 0,
                timeout => 5,
            }
        );

        $http->get($url, @headers);
    }

    if ($alertEntity ne '') {
        my $url = $baseUrl . '/api/states/' . $alertEntity;

        my $http = Slim::Networking::SimpleAsyncHTTP->new(
            sub {
                my $resp = shift;
                my $data = eval { decode_json($resp->content) };
                if ($@ || !ref($data)) {
                    $log->warn("Invalid JSON from Home Assistant for alert $alertEntity");
                    $alertRes = { active => 0, text => '' };
                } else {
                    $alertRes = formatAlertState($data, $alertLabel);
                }
                $finishOne->();
            },
            sub {
                my ($httpObj, $err) = @_;
                $log->warn("HA alert fetch failed for $alertEntity: $err");
                $alertRes = { active => 0, text => '' };
                $finishOne->();
            },
            {
                cache   => 0,
                timeout => 5,
            }
        );

        $http->get($url, @headers);
    }
}

sub _appletZipPath {
    return catfile(dirname(__FILE__), 'AppletDist', 'HAScreenSaver.zip');
}

sub _appletZipSha1 {
    my $zipPath = _appletZipPath();
    return undef unless -r $zipPath;

    open my $fh, '<:raw', $zipPath or return undef;
    local $/;
    my $bytes = <$fh>;
    close $fh;

    return sha1_hex($bytes);
}

sub getJiveExtensions {
    my ($args) = @_;
    my $cb = $args->{cb};
    my $pt = $args->{pt} || [];

    my @res;
    my $type   = $args->{type}   || '';
    my $target = $args->{target} || '';

    if ($type eq 'applet' && ($target eq '' || $target =~ /^(?:baby|fab4|jive|squeezeplay|jivelite)$/i)) {
        my $sha1 = _appletZipSha1();
        if (defined $sha1) {
            my $serverUrl = eval {
                require Slim::Utils::Network;
                Slim::Utils::Network::serverURL();
            } || 'http://localhost:9000';
            $serverUrl =~ s{/+$}{};

            push @res, {
                name    => 'HAScreenSaver',
                title   => 'Home Assistant Clock',
                desc    => 'Dark-shaded digital clock screensaver for Squeezebox Radio, Squeezebox Touch, and Jivelite with bottom-center weather icon, up to 4 live Home Assistant sensors, subtle radio alarm indicator, and optional door/alert banner. Zero long-term caching.',
                creator => 'Nornode',
                link    => 'https://github.com/Nornode/lms-ha-screensaver',
                version => $VERSION,
                url     => $serverUrl . '/plugins/HAScreenSaver/HAScreenSaver.zip',
                relurl  => '/plugins/HAScreenSaver/HAScreenSaver.zip',
                sha     => $sha1,
            };
        }
    }

    if (ref($cb) eq 'CODE') {
        $cb->(@$pt, \@res);
    }

    return \@res;
}

sub buildRepoXml {
    my ($hostHeader, $version, $sha1) = @_;
    $hostHeader ||= 'localhost:9000';
    $version    ||= $VERSION;
    $sha1       ||= '';

    my $zipUrl = "http://${hostHeader}/plugins/HAScreenSaver/HAScreenSaver.zip";

    return <<"XML";
<?xml version="1.0" encoding="UTF-8"?>
<extensions>
  <applets>
    <applet name="HAScreenSaver"
            creator="Nornode"
            minTarget="7.7"
            maxTarget="*"
            target="baby|fab4|jive|squeezeplay|jivelite"
            version="$version"
            url="$zipUrl"
            sha="$sha1">
      <title lang="EN">Home Assistant Clock</title>
      <desc lang="EN">Clear digital clock screensaver for Squeezebox Radio, Squeezebox Touch, and Jivelite with alarm indicator, optional door/alert banner, and up to 4 live Home Assistant sensors.</desc>
    </applet>
  </applets>
</extensions>
XML
}

sub handleRepoXml {
    my ($client, $params, $callback, $httpClient, $response) = @_;

    my $zipPath = _appletZipPath();
    if (!-r $zipPath) {
        $response->code(404);
        $response->header('Content-Type' => 'text/plain; charset=utf-8');
        my $msg = "HAScreenSaver.zip not found in AppletDist. Run scripts/build.sh first.\n";
        return \$msg;
    }

    open my $fh, '<:raw', $zipPath or do {
        $response->code(500);
        my $msg = "Failed to read HAScreenSaver.zip\n";
        return \$msg;
    };
    local $/;
    my $bytes = <$fh>;
    close $fh;

    my $sha1 = sha1_hex($bytes);
    my $host = $params->{host} || '';
    if (!$host && $response && $response->request && $response->request->header('Host')) {
        $host = $response->request->header('Host');
    }
    $host ||= 'localhost:9000';

    my $xml = buildRepoXml($host, $VERSION, $sha1);
    $response->code(200);
    $response->header('Content-Type'  => 'application/xml; charset=utf-8');
    $response->header('Cache-Control' => 'no-cache');
    return \$xml;
}

sub handleAppletZip {
    my ($client, $params, $callback, $httpClient, $response) = @_;

    my $zipPath = _appletZipPath();
    if (!-r $zipPath) {
        $response->code(404);
        $response->header('Content-Type' => 'text/plain; charset=utf-8');
        my $msg = "HAScreenSaver.zip not found.\n";
        return \$msg;
    }

    open my $fh, '<:raw', $zipPath or do {
        $response->code(500);
        my $msg = "Failed to open HAScreenSaver.zip\n";
        return \$msg;
    };
    local $/;
    my $bytes = <$fh>;
    close $fh;

    $response->code(200);
    $response->header('Content-Type'  => 'application/zip');
    $response->header('Cache-Control' => 'no-cache');
    return \$bytes;
}

sub _trim {
    my ($s) = @_;
    return '' unless defined $s;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return $s;
}

1;
