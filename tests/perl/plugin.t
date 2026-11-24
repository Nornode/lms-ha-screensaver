#!/usr/bin/env perl
use strict;
use warnings;

use FindBin;
use File::Spec::Functions qw(catdir);
use Test::More;

# Minimal LMS module stubs so Plugin.pm can be unit-tested standalone on macOS/Linux
BEGIN {
    my $pluginRoot = catdir($FindBin::Bin, '..', '..', 'server-plugin');
    unshift @INC, $pluginRoot;

    # Stub main::WEBUI
    *main::WEBUI = sub () { 0 };

    # Stub Slim::Plugin::Base
    $INC{'Slim/Plugin/Base.pm'} = 1;
    {
        package Slim::Plugin::Base;
        sub initPlugin { return 1; }
    }

    # Stub JSON::XS::VersionOneAndTwo using core JSON::PP
    $INC{'JSON/XS/VersionOneAndTwo.pm'} = 1;
    {
        package JSON::XS::VersionOneAndTwo;
        use JSON::PP ();
        use Exporter 'import';
        our @EXPORT = qw(decode_json encode_json);
        sub decode_json { return JSON::PP::decode_json(@_); }
        sub encode_json { return JSON::PP::encode_json(@_); }
    }

    # Stub Slim::Utils::Log
    $INC{'Slim/Utils/Log.pm'} = 1;
    {
        package Slim::Utils::Log;
        sub addLogCategory { return bless {}, shift; }
        sub warn  {}
        sub error {}
        sub info  {}
        sub debug {}
    }

    # Stub Slim::Utils::Prefs
    $INC{'Slim/Utils/Prefs.pm'} = 1;
    {
        package Slim::Utils::Prefs;
        use Exporter 'import';
        our @EXPORT = qw(preferences);
        my %stores;
        sub preferences {
            my ($ns) = @_;
            $stores{$ns} ||= bless { data => {}, defaults => {}, clients => {} }, 'MockPrefs';
            return $stores{$ns};
        }
        package MockPrefs;
        sub init {
            my ($self, $defaults) = @_;
            $self->{defaults} ||= {};
            for my $k (keys %$defaults) {
                $self->{defaults}{$k} = $defaults->{$k};
                $self->{data}{$k} = $defaults->{$k} unless exists $self->{data}{$k};
            }
        }
        sub get {
            my ($self, $k) = @_;
            return exists $self->{data}{$k} ? $self->{data}{$k} : $self->{defaults}{$k};
        }
        sub set {
            my ($self, $k, $v) = @_;
            $self->{data}{$k} = $v;
        }
        sub client {
            my ($self, $client) = @_;
            return undef unless $client;
            my $id = ref($client) && $client->can('id') ? $client->id : "$client";
            $self->{clients}{$id} ||= bless {
                data     => {},
                defaults => $self->{defaults},
            }, 'MockClientPrefs';
            return $self->{clients}{$id};
        }
        package MockClientPrefs;
        sub get {
            my ($self, $k) = @_;
            return exists $self->{data}{$k} ? $self->{data}{$k} : $self->{defaults}{$k};
        }
        sub set {
            my ($self, $k, $v) = @_;
            $self->{data}{$k} = $v;
        }
    }

    # Stub Slim::Web::HTTP::CSRF and Slim::Web::Settings
    $INC{'Slim/Web/HTTP/CSRF.pm'} = 1;
    {
        package Slim::Web::HTTP::CSRF;
        sub protectName { shift; return shift; }
        sub protectURI  { shift; return shift; }
    }

    $INC{'Slim/Web/Settings.pm'} = 1;
    {
        package Slim::Web::Settings;
        sub new { return bless {}, shift; }
        sub handler {
            my ($class, $client, $params, $callback, @args) = @_;
            my ($prefObj, @keys) = $class->prefs($client);
            if ($prefObj && $params->{saveSettings}) {
                for my $k (@keys) {
                    if (exists $params->{"pref_$k"}) {
                        $prefObj->set($k, $params->{"pref_$k"});
                    }
                }
            }
            if ($prefObj) {
                $params->{prefs} ||= {};
                for my $k (@keys) {
                    $params->{prefs}{$k} = $prefObj->get($k);
                }
            }
            return 'RENDERED';
        }
    }

    # Mock Slim::Player::Client objects for per-radio tests
    {
        package MockClient;
        sub new {
            my ($class, %args) = @_;
            return bless \%args, $class;
        }
        sub id        { return shift->{id}; }
        sub name      { return shift->{name}; }
        sub modelName { return shift->{modelName} || 'Squeezebox Radio'; }
    }

    # Stub Slim::Control::Request
    $INC{'Slim/Control/Request.pm'} = 1;
    {
        package Slim::Control::Request;
        our @DISPATCHED;
        our @NOTIFIED;
        sub addDispatch     { push @DISPATCHED, [@_]; }
        sub notifyFromArray { push @NOTIFIED,   [@_]; }
    }

    # Stub Slim::Web::Pages
    $INC{'Slim/Web/Pages.pm'} = 1;
    {
        package Slim::Web::Pages;
        our @PAGE_ROUTES;
        sub addPageFunction { shift; push @PAGE_ROUTES, [@_]; }
        sub addRawFunction  { shift; push @PAGE_ROUTES, [@_]; }
    }

    # Stub Slim::Control::Jive
    $INC{'Slim/Control/Jive.pm'} = 1;
    {
        package Slim::Control::Jive;
        our %EXTENSION_PROVIDERS;
        sub registerExtensionProvider {
            my ($name, $cb, $optstr) = @_;
            $EXTENSION_PROVIDERS{$name} = { provider => $cb, optstr => $optstr };
        }
        sub removeExtensionProvider {
            my ($name) = @_;
            delete $EXTENSION_PROVIDERS{$name};
        }
    }

    # Stub Slim::Utils::Network
    $INC{'Slim/Utils/Network.pm'} = 1;
    {
        package Slim::Utils::Network;
        sub serverURL { return 'http://192.0.2.10:9000'; }
    }

    # Stub Slim::Networking::SimpleAsyncHTTP (captures calls + checks cache => 0)
    $INC{'Slim/Networking/SimpleAsyncHTTP.pm'} = 1;
    {
        package Slim::Networking::SimpleAsyncHTTP;
        our @REQUESTS;
        our %MOCK_RESPONSES;
        sub new {
            my ($class, $cb, $ecb, $params) = @_;
            return bless { cb => $cb, ecb => $ecb, params => $params }, $class;
        }
        sub get {
            my ($self, $url, %headers) = @_;
            push @REQUESTS, {
                method  => 'GET',
                url     => $url,
                headers => \%headers,
                params  => $self->{params},
            };
            if (exists $MOCK_RESPONSES{$url}) {
                my $mock = $MOCK_RESPONSES{$url};
                if ($mock->{error}) {
                    $self->{ecb}->($self, $mock->{error});
                } else {
                    my $resp = bless { content => $mock->{content} }, 'MockHttpResponse';
                    $self->{cb}->($resp);
                }
            } else {
                $self->{ecb}->($self, '404 Not Found');
            }
        }
        sub post {
            my ($self, $url, @args) = @_;
            my $body = pop @args;
            my %headers = @args;
            push @REQUESTS, {
                method  => 'POST',
                url     => $url,
                headers => \%headers,
                body    => $body,
                params  => $self->{params},
            };
            if (exists $MOCK_RESPONSES{$url}) {
                my $mock = $MOCK_RESPONSES{$url};
                if ($mock->{error}) {
                    $self->{ecb}->($self, $mock->{error});
                } else {
                    my $resp = bless { content => $mock->{content} }, 'MockHttpResponse';
                    $self->{cb}->($resp);
                }
            } else {
                $self->{ecb}->($self, '404 Not Found');
            }
        }
        package MockHttpResponse;
        sub content { return shift->{content}; }
    }
}

# Load Plugin.pm
require HAScreenSaver::Plugin;
# Alias package if loaded via HAScreenSaver/Plugin.pm
ok(defined &Plugins::HAScreenSaver::Plugin::resolveHAConfig, 'Plugin.pm loaded cleanly');

# 1. Test resolveHAConfig: Supervisor mode vs Custom mode vs Unconfigured
{
    my $p = Slim::Utils::Prefs::preferences('test.auth');
    $p->init({ ha_url => '', ha_token => '' });

    my ($url, $tok, $mode) = Plugins::HAScreenSaver::Plugin::resolveHAConfig($p, { SUPERVISOR_TOKEN => 'sup-tok-123' });
    is($url,  'http://supervisor/core', 'Supervisor mode resolves supervisor URL');
    is($tok,  'sup-tok-123',            'Supervisor mode uses SUPERVISOR_TOKEN');
    is($mode, 'supervisor',             'Mode reported as supervisor');

    ($url, $tok, $mode) = Plugins::HAScreenSaver::Plugin::resolveHAConfig($p, {});
    is($mode, 'unconfigured', 'Blank URL without SUPERVISOR_TOKEN is unconfigured');

    $p->set('ha_url',   'http://homeassistant.local:8123/');
    $p->set('ha_token', 'custom-tok-456');
    ($url, $tok, $mode) = Plugins::HAScreenSaver::Plugin::resolveHAConfig($p, { SUPERVISOR_TOKEN => 'sup-tok-123' });
    is($url,  'http://homeassistant.local:8123', 'Custom URL trims trailing slash and overrides supervisor');
    is($tok,  'custom-tok-456',                  'Custom token used');
    is($mode, 'custom',                          'Mode reported as custom');
}

# 2. Test sanitizePollInterval & sanitizeFontName
is(Plugins::HAScreenSaver::Plugin::sanitizePollInterval(undef), 60,  'Default poll interval is 60s');
is(Plugins::HAScreenSaver::Plugin::sanitizePollInterval(5),     10,  'Poll interval clamped to min 10s');
is(Plugins::HAScreenSaver::Plugin::sanitizePollInterval(999),   300, 'Poll interval clamped to max 300s');
is(Plugins::HAScreenSaver::Plugin::sanitizePollInterval(60),    60,  'Valid poll interval preserved');

is(Plugins::HAScreenSaver::Plugin::sanitizeFontName('FreeMonoBold'), 'FreeMonoBold', 'Allowed font accepted');
is(Plugins::HAScreenSaver::Plugin::sanitizeFontName('../evil.ttf'),  'FreeSansBold', 'Invalid font falls back to FreeSansBold');

# 3. Test formatSensorState
{
    my $res = Plugins::HAScreenSaver::Plugin::formatSensorState(
        { state => '6.15', attributes => { unit_of_measurement => '°C' } },
        { label => 'Out', decimals => '1', unit => '' }
    );
    is($res->{label}, 'Out',  'Sensor label preserved');
    is($res->{value}, '6.2',  'Numeric value rounded to 1 decimal');
    is($res->{unit},  '°C',   'Unit taken from HA attributes');
    is($res->{ok},    1,      'Sensor marked ok');

    my $unavail = Plugins::HAScreenSaver::Plugin::formatSensorState(
        { state => 'unavailable', attributes => { unit_of_measurement => '°C' } },
        { label => 'Out', decimals => '1', unit => '' }
    );
    is($unavail->{value}, '--', 'Unavailable state formatted as --');
    is($unavail->{ok},    0,    'Unavailable sensor marked not ok');

    my $textSensor = Plugins::HAScreenSaver::Plugin::formatSensorState(
        { state => 'Sunny', attributes => {} },
        { label => 'Sky', decimals => '1', unit => '' }
    );
    is($textSensor->{value}, 'Sunny', 'Non-numeric text sensor passed through intact');
    is($textSensor->{ok},    1,       'Text sensor marked ok');
}

# 4. Test formatAlertState (binary_sensor + text door sensor)
{
    my $closed = Plugins::HAScreenSaver::Plugin::formatAlertState({ state => 'off' }, 'Door');
    is($closed->{active}, 0, 'Binary sensor off is inactive');

    my $none = Plugins::HAScreenSaver::Plugin::formatAlertState({ state => 'none' }, 'Open');
    is($none->{active}, 0, 'Text sensor "none" is inactive');

    my $openBin = Plugins::HAScreenSaver::Plugin::formatAlertState(
        { state => 'on', attributes => { friendly_name => 'Front Door' } },
        ''
    );
    is($openBin->{active}, 1,                  'Binary sensor on is active');
    is($openBin->{text},   'Front Door: Open', 'Binary sensor uses friendly_name when prefix blank');

    my $openText = Plugins::HAScreenSaver::Plugin::formatAlertState(
        { state => 'Front Door, Patio' },
        'Open'
    );
    is($openText->{active}, 1,                        'Text door sensor is active');
    is($openText->{text},   'Open: Front Door, Patio', 'Text door sensor combines prefix and state');
}

# 4b. Test formatWeatherIcon (all 15 official HA conditions)
is(Plugins::HAScreenSaver::Plugin::formatWeatherIcon({ state => 'partlycloudy' }),    'partlycloudy',    'Weather partlycloudy maps cleanly');
is(Plugins::HAScreenSaver::Plugin::formatWeatherIcon({ state => 'clear-night' }),     'clear_night',     'Weather clear-night maps to clear_night');
is(Plugins::HAScreenSaver::Plugin::formatWeatherIcon({ state => 'lightning-rainy' }), 'lightning_rainy', 'Weather lightning-rainy maps to lightning_rainy');
is(Plugins::HAScreenSaver::Plugin::formatWeatherIcon({ state => 'hail' }),            'hail',            'Weather hail maps to hail');
is(Plugins::HAScreenSaver::Plugin::formatWeatherIcon({ state => 'snowy-rainy' }),     'snowy_rainy',     'Weather snowy-rainy maps to snowy_rainy');
is(Plugins::HAScreenSaver::Plugin::formatWeatherIcon({ state => 'windy-variant' }),   'windy_variant',   'Weather windy-variant maps to windy_variant');
is(Plugins::HAScreenSaver::Plugin::formatWeatherIcon({ state => 'exceptional' }),     'exceptional',     'Weather exceptional maps to exceptional');
is(Plugins::HAScreenSaver::Plugin::formatWeatherIcon({ state => 'unknown' }),         '',                'Unknown weather returns empty icon');

# 5. Test buildRepoXml
{
    my $xml = Plugins::HAScreenSaver::Plugin::buildRepoXml('192.0.2.10:9000', '0.1.0', 'abc123');
    like($xml, qr/target="baby\|fab4\|jive\|squeezeplay\|jivelite"/, 'repo.xml targets baby, fab4 (Touch), and jivelite');
    like($xml, qr/url="http:\/\/192\.0\.2\.10:9000\/plugins\/HAScreenSaver\/HAScreenSaver\.zip"/, 'repo.xml uses dynamic host URL');
    like($xml, qr/sha="abc123"/, 'repo.xml includes SHA-1');
}

# 6. Test handleSensorsRequest end-to-end: verifies cache => 0 and Cache-Control: no-cache
{
    my $prefs = Slim::Utils::Prefs::preferences('plugin.hascreensaver');
    $prefs->init({
        ha_url           => 'http://example.ha:8123',
        ha_token         => 'test-token',
        poll_interval    => 60,
        font_name        => 'FreeMonoBold',
        weather_entity   => 'weather.home',
        alert_entity     => 'sensor.open_doors',
        alert_label      => 'Open',
        sensor1_entity   => 'sensor.outside_temperature',
        sensor1_label    => 'Out',
        sensor1_decimals => '1',
        sensor1_unit     => '',
        sensor2_entity   => 'sensor.indoor_temperature',
        sensor2_label    => 'In',
        sensor2_decimals => '1',
        sensor2_unit     => '',
        sensor3_entity   => '',
        sensor4_entity   => '',
    });

    %Slim::Networking::SimpleAsyncHTTP::MOCK_RESPONSES = (
        'http://example.ha:8123/api/states/sensor.outside_temperature' => {
            content => '{"state":"5.44","attributes":{"unit_of_measurement":"°C"}}',
        },
        'http://example.ha:8123/api/states/sensor.indoor_temperature' => {
            content => '{"state":"21.82","attributes":{"unit_of_measurement":"°C"}}',
        },
        'http://example.ha:8123/api/states/sensor.open_doors' => {
            content => '{"state":"Patio"}',
        },
        'http://example.ha:8123/api/states/weather.home' => {
            content => '{"state":"partlycloudy"}',
        },
    );
    @Slim::Networking::SimpleAsyncHTTP::REQUESTS = ();

    my %mockResults;
    my $done = 0;
    my $req = bless {}, 'MockRequest';
    {
        package MockRequest;
        sub isNotQuery         { return 0; }
        sub client             { return undef; }
        sub setStatusProcessing{}
        sub setStatusDone      { $done = 1; }
        sub addResult          { my ($s, $k, $v) = @_; $mockResults{$k} = $v; }
    }

    Plugins::HAScreenSaver::Plugin::handleSensorsRequest($req);

    is($done, 1, 'Async request completed');
    is(scalar(@Slim::Networking::SimpleAsyncHTTP::REQUESTS), 4, 'Fired 4 live HTTP requests (2 sensors + 1 weather + 1 alert)');
    for my $r (@Slim::Networking::SimpleAsyncHTTP::REQUESTS) {
        is($r->{params}{cache}, 0, "HTTP request to $r->{url} explicitly sets cache => 0");
        is($r->{headers}{'Cache-Control'}, 'no-cache', "HTTP request to $r->{url} sends Cache-Control: no-cache");
    }

    is($mockResults{poll_interval}, 60,             'Returns poll_interval 60');
    is($mockResults{font_name},     'FreeMonoBold', 'Returns configured font_name');
    is($mockResults{weather_icon},  'partlycloudy', 'Returns normalized weather_icon');
    is($mockResults{alert_active},  1,              'Alert active when door open');
    is($mockResults{alert_text},    'Open: Patio',  'Alert text formatted');
    is(scalar(@{$mockResults{sensors_loop}}), 2,    'Returns 2 sensors');
    is($mockResults{sensors_loop}[0]{value}, '5.4', 'Sensor 1 value rounded');
    is($mockResults{sensors_loop}[1]{value}, '21.8','Sensor 2 value rounded');
    is($mockResults{config_scope}, 'default', 'Unscoped request reports config_scope=default');
}

# 7. Test isHiddenOverride, resolveEffectiveConfig, and describeClientOverrides
{
    is(Plugins::HAScreenSaver::Plugin::isHiddenOverride('none'),   1, 'isHiddenOverride matches "none"');
    is(Plugins::HAScreenSaver::Plugin::isHiddenOverride(' NONE '), 1, 'isHiddenOverride matches trimmed case-insensitive NONE');
    is(Plugins::HAScreenSaver::Plugin::isHiddenOverride(''),       0, 'Empty string is not hidden');
    is(Plugins::HAScreenSaver::Plugin::isHiddenOverride(undef),    0, 'undef is not hidden');
    is(Plugins::HAScreenSaver::Plugin::isHiddenOverride('sensor.outside'), 0, 'Normal entity is not hidden');

    my $p = Slim::Utils::Prefs::preferences('test.per_radio');
    $p->init({
        poll_interval    => 60,
        font_name        => 'FreeSansBold',
        weather_entity   => 'weather.home',
        alert_entity     => '',
        alert_label      => 'Open',
        sensor1_entity   => 'sensor.outside_temp',
        sensor1_label    => 'Out',
        sensor1_decimals => '1',
        sensor1_unit     => '',
        sensor2_entity   => 'sensor.floor1_avg_temp',
        sensor2_label    => '1st',
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

    my $floor1Radio = MockClient->new(id => 'aa:bb:cc:00:00:01', name => 'Living Room');
    my $kidsRadio   = MockClient->new(id => 'aa:bb:cc:00:00:02', name => 'Kids Room');
    my $masterRadio = MockClient->new(id => 'aa:bb:cc:00:00:03', name => 'Master Bedroom');

    # Unconfigured radio inherits global defaults
    my $cfg1 = Plugins::HAScreenSaver::Plugin::resolveEffectiveConfig($p, $floor1Radio);
    is($cfg1->{has_overrides}, 0, 'Unconfigured radio has_overrides == 0');
    is($cfg1->{weather_entity}, 'weather.home', 'Unconfigured radio inherits global weather');
    is($cfg1->{alert_entity},   '',             'Unconfigured radio inherits blank alert');
    is(scalar(@{$cfg1->{slots}}), 2,            'Unconfigured radio inherits 2 global sensors');
    is($cfg1->{slots}[1]{entity}, 'sensor.floor1_avg_temp', 'Unconfigured radio gets 1st floor temp');
    is(Plugins::HAScreenSaver::Plugin::describeClientOverrides($p, $floor1Radio), 'Using Global Defaults', 'Unconfigured radio summary says Using Global Defaults');

    # Kids radio overrides Sensor 2 only (inherits Outside + Weather, no Door Alert)
    my $cpKids = $p->client($kidsRadio);
    $cpKids->set('player_sensor2_entity', 'sensor.kids_room_temp');
    $cpKids->set('player_sensor2_label',  'Kids');
    $cpKids->set('player_sensor2_decimals', '');

    my $cfgKids = Plugins::HAScreenSaver::Plugin::resolveEffectiveConfig($p, $kidsRadio);
    is($cfgKids->{has_overrides}, 1, 'Kids radio has_overrides == 1');
    is($cfgKids->{weather_entity}, 'weather.home', 'Kids radio still inherits global weather');
    is($cfgKids->{alert_entity},   '',             'Kids radio stays alert-free');
    is($cfgKids->{slots}[0]{entity}, 'sensor.outside_temp',   'Kids radio inherits Sensor 1');
    is($cfgKids->{slots}[1]{entity}, 'sensor.kids_room_temp', 'Kids radio overrides Sensor 2');
    is($cfgKids->{slots}[1]{label},  'Kids',                  'Kids radio uses custom label');
    is($cfgKids->{slots}[1]{decimals}, '1',                   'Kids radio falls back to global decimals when left blank');
    is(Plugins::HAScreenSaver::Plugin::describeClientOverrides($p, $kidsRadio), 'Sensor 2 (Kids)', 'Kids radio summary describes Sensor 2');

    # Master radio enables Door Alert + overrides Sensor 2 with explicit 0 decimals + font override
    my $cpMaster = $p->client($masterRadio);
    $cpMaster->set('player_font_name',        'FreeSans');
    $cpMaster->set('player_alert_entity',     'sensor.open_doors');
    $cpMaster->set('player_alert_label',      'Doors');
    $cpMaster->set('player_sensor2_entity',   'sensor.floor2_avg_temp');
    $cpMaster->set('player_sensor2_label',    '2nd');
    $cpMaster->set('player_sensor2_decimals', '0');

    my $cfgMaster = Plugins::HAScreenSaver::Plugin::resolveEffectiveConfig($p, $masterRadio);
    is($cfgMaster->{has_overrides}, 1, 'Master radio has_overrides == 1');
    is($cfgMaster->{font_name},     'FreeSans',          'Master radio overrides font');
    is($cfgMaster->{alert_entity},  'sensor.open_doors', 'Master radio enables Door Alert');
    is($cfgMaster->{alert_label},   'Doors',             'Master radio uses custom alert label');
    is($cfgMaster->{slots}[1]{entity},   'sensor.floor2_avg_temp', 'Master radio overrides Sensor 2');
    is($cfgMaster->{slots}[1]{decimals}, '0',                      'Master radio explicit decimals "0" preserved');
    is(Plugins::HAScreenSaver::Plugin::describeClientOverrides($p, $masterRadio),
        'Font (FreeSans), Alert (Doors), Sensor 2 (2nd)',
        'Master radio summary lists font, alert, and sensor overrides');

    # Hiding a global default via "none" + slot compaction
    my $hideRadio = MockClient->new(id => 'aa:bb:cc:00:00:04', name => 'Minimal');
    my $cpHide = $p->client($hideRadio);
    $cpHide->set('player_weather_entity', 'NONE');
    $cpHide->set('player_sensor1_entity', 'none');
    my $cfgHide = Plugins::HAScreenSaver::Plugin::resolveEffectiveConfig($p, $hideRadio);
    is($cfgHide->{has_overrides},  1,  'Hidden override sets has_overrides == 1');
    is($cfgHide->{weather_entity}, '', 'Weather hidden via NONE');
    is(scalar(@{$cfgHide->{slots}}), 1, 'Sensor 1 hidden compacts slots to remaining Sensor 2');
    is($cfgHide->{slots}[0]{entity}, 'sensor.floor1_avg_temp', 'Compacted slot 0 is global Sensor 2');
    is(Plugins::HAScreenSaver::Plugin::describeClientOverrides($p, $hideRadio),
        'Weather (hidden), Sensor 1 (hidden)',
        'Hidden summary describes hidden items');

    # Dynamic Global Default update flows to inherited slots without overwriting overrides
    $p->set('sensor1_entity', 'sensor.new_outside_temp');
    my $cfgKidsAfter = Plugins::HAScreenSaver::Plugin::resolveEffectiveConfig($p, $kidsRadio);
    is($cfgKidsAfter->{slots}[0]{entity}, 'sensor.new_outside_temp', 'Global default change flows to inherited Sensor 1');
    is($cfgKidsAfter->{slots}[1]{entity}, 'sensor.kids_room_temp',   'Global default change preserves custom Sensor 2');

    # Invalid player font falls back to FreeSansBold
    $cpMaster->set('player_font_name', '../evil.ttf');
    my $cfgBadFont = Plugins::HAScreenSaver::Plugin::resolveEffectiveConfig($p, $masterRadio);
    is($cfgBadFont->{font_name}, 'FreeSansBold', 'Invalid per-player font falls back to FreeSansBold');
}

# 8. End-to-end handleSensorsRequest across multiple radios
{
    my $prefs = Slim::Utils::Prefs::preferences('plugin.hascreensaver');
    $prefs->set('ha_url',         'http://example.ha:8123');
    $prefs->set('ha_token',       'test-token');
    $prefs->set('poll_interval',  60);
    $prefs->set('font_name',      'FreeSansBold');
    $prefs->set('weather_entity', 'weather.home');
    $prefs->set('alert_entity',   '');
    $prefs->set('alert_label',    'Open');
    $prefs->set('sensor1_entity', 'sensor.outside_temperature');
    $prefs->set('sensor1_label',  'Out');
    $prefs->set('sensor2_entity', 'sensor.floor1_avg_temp');
    $prefs->set('sensor2_label',  '1st');

    %Slim::Networking::SimpleAsyncHTTP::MOCK_RESPONSES = (
        'http://example.ha:8123/api/states/sensor.outside_temperature' => {
            content => '{"state":"4.2","attributes":{"unit_of_measurement":"°C"}}',
        },
        'http://example.ha:8123/api/states/sensor.floor1_avg_temp' => {
            content => '{"state":"21.4","attributes":{"unit_of_measurement":"°C"}}',
        },
        'http://example.ha:8123/api/states/sensor.kids_room_temp' => {
            content => '{"state":"19.8","attributes":{"unit_of_measurement":"°C"}}',
        },
        'http://example.ha:8123/api/states/sensor.open_doors' => {
            content => '{"state":"Patio"}',
        },
        'http://example.ha:8123/api/states/weather.home' => {
            content => '{"state":"sunny"}',
        },
    );

    my $r1 = MockClient->new(id => '11:11:11:11:11:01', name => 'Kitchen');
    my $r2 = MockClient->new(id => '11:11:11:11:11:02', name => 'Kids');
    my $r3 = MockClient->new(id => '11:11:11:11:11:03', name => 'Bedroom');

    $prefs->client($r2)->set('player_sensor2_entity', 'sensor.kids_room_temp');
    $prefs->client($r2)->set('player_sensor2_label',  'Room');

    $prefs->client($r3)->set('player_alert_entity',   'sensor.open_doors');
    $prefs->client($r3)->set('player_alert_label',    'Doors');
    $prefs->client($r3)->set('player_weather_entity', 'none');

    my $runReq = sub {
        my ($client) = @_;
        @Slim::Networking::SimpleAsyncHTTP::REQUESTS = ();
        my %res;
        my $done = 0;
        my $req = bless {
            client  => $client,
            results => \%res,
            done    => \$done,
        }, 'MockClientRequest';
        Plugins::HAScreenSaver::Plugin::handleSensorsRequest($req);
        return (\%res, $done, [@Slim::Networking::SimpleAsyncHTTP::REQUESTS]);
    };

    {
        package MockClientRequest;
        sub isNotQuery          { return 0; }
        sub client              { return shift->{client}; }
        sub setStatusProcessing {}
        sub setStatusDone       { my $s = shift; ${$s->{done}} = 1; }
        sub addResult           { my ($s, $k, $v) = @_; $s->{results}{$k} = $v; }
    }

    my ($res1, $done1, $reqs1) = $runReq->($r1);
    is($done1, 1, 'Kitchen request done');
    is($res1->{config_scope}, 'default', 'Kitchen uses default scope');
    is($res1->{alert_active}, 0,         'Kitchen has no door alert');
    is($res1->{sensors_loop}[1]{value}, '21.4', 'Kitchen gets 1st floor avg');
    is(scalar(@$reqs1), 3, 'Kitchen fires 3 HTTP calls (2 sensors + weather, no alert)');

    my ($res2, $done2, $reqs2) = $runReq->($r2);
    is($done2, 1, 'Kids request done');
    is($res2->{config_scope}, 'player', 'Kids uses player scope');
    is($res2->{alert_active}, 0,        'Kids has no door alert');
    is($res2->{sensors_loop}[0]{value}, '4.2',  'Kids gets global outside temp');
    is($res2->{sensors_loop}[1]{value}, '19.8', 'Kids gets custom room temp');
    is($res2->{sensors_loop}[1]{label}, 'Room', 'Kids gets custom label');
    is(scalar(@$reqs2), 3, 'Kids fires 3 HTTP calls (no alert fetch)');
    my @urls2 = sort map { $_->{url} } @$reqs2;
    is_deeply(\@urls2, [
        'http://example.ha:8123/api/states/sensor.kids_room_temp',
        'http://example.ha:8123/api/states/sensor.outside_temperature',
        'http://example.ha:8123/api/states/weather.home',
    ], 'Kids fetched exact expected HA entities');

    my ($res3, $done3, $reqs3) = $runReq->($r3);
    is($done3, 1, 'Bedroom request done');
    is($res3->{config_scope}, 'player',       'Bedroom uses player scope');
    is($res3->{weather_icon}, '',             'Bedroom hid weather via none');
    is($res3->{alert_active}, 1,              'Bedroom shows active door alert');
    is($res3->{alert_text},   'Doors: Patio', 'Bedroom formats custom door alert');
    my @urls3 = sort map { $_->{url} } @$reqs3;
    is_deeply(\@urls3, [
        'http://example.ha:8123/api/states/sensor.floor1_avg_temp',
        'http://example.ha:8123/api/states/sensor.open_doors',
        'http://example.ha:8123/api/states/sensor.outside_temperature',
    ], 'Bedroom skipped hidden weather fetch and fetched custom alert');
    for my $r (@$reqs3) {
        is($r->{params}{cache}, 0, "Per-radio request to $r->{url} sets cache => 0");
        is($r->{headers}{'Cache-Control'}, 'no-cache', "Per-radio request to $r->{url} sets Cache-Control: no-cache");
    }
}

# 9. Test PlayerSettings.pm: needsClient, prefs guard, save sanitization, and reset
{
    require HAScreenSaver::PlayerSettings;

    is(Plugins::HAScreenSaver::PlayerSettings->needsClient(), 1, 'PlayerSettings requires a client');
    is_deeply([Plugins::HAScreenSaver::PlayerSettings->prefs(undef)], [], 'prefs(undef) returns empty list safely');

    my $pClient = MockClient->new(id => '22:22:22:22:22:01', name => 'Study Radio');
    my ($store, @keys) = Plugins::HAScreenSaver::PlayerSettings->prefs($pClient);
    ok($store && scalar(@keys) == 30, 'prefs($client) returns client store and 30 player preference keys');

    my $params = {
        saveSettings             => 1,
        pref_player_font_name    => '../invalid',
        pref_player_weather_entity => ' NONE ',
        pref_player_alert_entity => '  sensor.open_doors  ',
        pref_player_alert_label  => ' Doors ',
        pref_player_sensor2_entity => ' sensor.study_temp ',
        pref_player_sensor2_label  => ' Study ',
    };
    Plugins::HAScreenSaver::PlayerSettings->handler($pClient, $params);

    is($params->{player_name}, 'Study Radio', 'handler populates player_name');
    is($params->{defaults}{sensor1_entity}, 'sensor.outside_temperature', 'handler populates global defaults for template');
    is($store->get('player_font_name'),      'FreeSansBold',      'Invalid font sanitized on save');
    is($store->get('player_weather_entity'), 'none',              'Case-insensitive NONE normalized to none');
    is($store->get('player_alert_entity'),   'sensor.open_doors', 'Alert entity trimmed on save');
    is($store->get('player_sensor2_entity'), 'sensor.study_temp', 'Sensor 2 entity trimmed on save');
    like($params->{override_summary}, qr/Alert \(Doors\).*Sensor 2 \(Study\)/, 'override_summary updated on save');

    # Test resetPlayerOverrides clears all player_* fields
    my $resetParams = {
        saveSettings               => 1,
        resetPlayerOverrides       => 1,
        pref_player_sensor2_entity => 'sensor.study_temp',
    };
    Plugins::HAScreenSaver::PlayerSettings->handler($pClient, $resetParams);
    is($store->get('player_font_name'),      '', 'Reset clears player_font_name');
    is($store->get('player_weather_entity'), '', 'Reset clears player_weather_entity');
    is($store->get('player_alert_entity'),   '', 'Reset clears player_alert_entity');
    is($store->get('player_sensor2_entity'), '', 'Reset clears player_sensor2_entity');
    is($resetParams->{override_summary}, 'Using Global Defaults', 'Reset restores override_summary to Using Global Defaults');
}

# 10. Test Settings.pm: players overview summary
{
    $INC{'Slim/Player/Client.pm'} = 1;
    my @mockClients = (
        MockClient->new(id => '11:11:11:11:11:02', name => 'Kids'),
        MockClient->new(id => '11:11:11:11:11:01', name => 'Kitchen'),
        MockClient->new(id => '11:11:11:11:11:03', name => 'Bedroom'),
    );
    {
        package Slim::Player::Client;
        sub clients { return @mockClients; }
    }

    require HAScreenSaver::Settings;
    my $params = { host => 'lms.local:9000' };
    Plugins::HAScreenSaver::Settings->handler(undef, $params);

    is($params->{local_repo_url}, 'http://lms.local:9000/plugins/HAScreenSaver/repo.xml', 'Settings builds local_repo_url');
    is(scalar(@{$params->{players}}), 3, 'Settings populates 3 sorted players');
    is($params->{players}[0]{name}, 'Bedroom', 'Players sorted alphabetically (Bedroom first)');
    is($params->{players}[0]{has_overrides}, 1, 'Bedroom marked has_overrides=1');
    is($params->{players}[2]{name}, 'Kitchen', 'Kitchen sorted last');
    is($params->{players}[2]{summary}, 'Using Global Defaults', 'Kitchen summary reports Using Global Defaults');
}

# 11. Test Jive extension provider (plain HTTP Applet Installer delivery)
{
    Plugins::HAScreenSaver::Plugin->initPlugin();

    ok(exists $Slim::Control::Jive::EXTENSION_PROVIDERS{hascreensaver},
        'initPlugin registers hascreensaver Jive extension provider');
    ok(!defined $Slim::Control::Jive::EXTENSION_PROVIDERS{hascreensaver}{optstr},
        'Jive extension provider has undef optstr so it appears even with Recommended Applets Only');

    # Ensure AppletDist/HAScreenSaver.zip exists or create a temporary stub if absent in clean CI checkout
    my $zipPath = Plugins::HAScreenSaver::Plugin::_appletZipPath();
    my $createdTempZip = 0;
    if (!-r $zipPath) {
        require File::Basename;
        require File::Path;
        File::Path::make_path(File::Basename::dirname($zipPath));
        open my $fh, '>:raw', $zipPath or die "Cannot write temp zip: $!";
        print $fh "PK\x03\x04dummy-applet-zip-for-unit-test";
        close $fh;
        $createdTempZip = 1;
    }

    my ($cbReq, $cbRes);
    Plugins::HAScreenSaver::Plugin::getJiveExtensions({
        type   => 'applet',
        target => 'baby',
        cb     => sub { ($cbReq, $cbRes) = @_; },
        pt     => ['REQ_TOKEN'],
    });

    is($cbReq, 'REQ_TOKEN', 'getJiveExtensions forwards passthrough args to callback');
    is(scalar(@$cbRes), 1, 'getJiveExtensions returns 1 applet entry for baby');
    is($cbRes->[0]{name},    'HAScreenSaver', 'Applet name is HAScreenSaver');
    is($cbRes->[0]{title},   'Home Assistant Clock', 'Applet title is Home Assistant Clock');
    is($cbRes->[0]{version}, $Plugins::HAScreenSaver::Plugin::VERSION, 'Applet version matches plugin VERSION');
    is($cbRes->[0]{relurl},  '/plugins/HAScreenSaver/HAScreenSaver.zip', 'Applet provides relurl for plain HTTP download');
    is($cbRes->[0]{url},     'http://192.0.2.10:9000/plugins/HAScreenSaver/HAScreenSaver.zip', 'Applet url uses plain HTTP serverURL');
    like($cbRes->[0]{sha},   qr/^[0-9a-f]{40}$/, 'Applet sha is a 40-char lowercase SHA-1');

    # Non-applet type returns empty
    my $nonAppletRes;
    Plugins::HAScreenSaver::Plugin::getJiveExtensions({
        type   => 'wallpaper',
        target => 'baby',
        cb     => sub { $nonAppletRes = $_[0]; },
        pt     => [],
    });
    is(scalar(@$nonAppletRes), 0, 'getJiveExtensions returns empty for non-applet type');

    # jive (Squeezebox Controller), fab4 (Squeezebox Touch) and jivelite targets return applet
    for my $t (qw(jive fab4 jivelite Jivelite)) {
        my $tRes;
        Plugins::HAScreenSaver::Plugin::getJiveExtensions({
            type   => 'applet',
            target => $t,
            cb     => sub { $tRes = $_[0]; },
            pt     => [],
        });
        is(scalar(@$tRes), 1, "getJiveExtensions returns 1 applet entry for $t");
    }

    # Unsupported target returns empty
    my $badTargetRes;
    Plugins::HAScreenSaver::Plugin::getJiveExtensions({
        type   => 'applet',
        target => 'unsupported_device',
        cb     => sub { $badTargetRes = $_[0]; },
        pt     => [],
    });
    is(scalar(@$badTargetRes), 0, 'getJiveExtensions returns empty for unsupported target');

    # shutdownPlugin removes provider
    Plugins::HAScreenSaver::Plugin->shutdownPlugin();
    ok(!exists $Slim::Control::Jive::EXTENSION_PROVIDERS{hascreensaver},
        'shutdownPlugin unregisters hascreensaver Jive extension provider');

    if ($createdTempZip) {
        unlink $zipPath;
    }
}

# 12. Test binary_sensor / lock / cover localization helpers & /api/template integration
{
    # Entity ID validation (template injection guard)
    is(Plugins::HAScreenSaver::Plugin::isValidEntityId('binary_sensor.front_door'), 1, 'Valid binary_sensor ID accepted');
    is(Plugins::HAScreenSaver::Plugin::isValidEntityId('lock.main_door'),           1, 'Valid lock ID accepted');
    is(Plugins::HAScreenSaver::Plugin::isValidEntityId("sensor.x') }} {{ 1"),       0, 'Template injection entity ID rejected');
    is(Plugins::HAScreenSaver::Plugin::isValidEntityId('bad_id_without_dot'),       0, 'Entity ID without domain dot rejected');

    # Textual vs numeric detection
    is(Plugins::HAScreenSaver::Plugin::isTextualSensorState({ state => '21.5' }),        0, 'Numeric state is not textual');
    is(Plugins::HAScreenSaver::Plugin::isTextualSensorState({ state => 'unavailable' }), 0, 'Unavailable state is not textual');
    is(Plugins::HAScreenSaver::Plugin::isTextualSensorState({ state => 'on' }),          1, 'Binary "on" state is textual');
    is(Plugins::HAScreenSaver::Plugin::isTextualSensorState({ state => 'unlocked' }),    1, 'Lock "unlocked" state is textual');

    # Template builder & response parser
    my $tmpl = Plugins::HAScreenSaver::Plugin::buildStateTranslatedTemplate([
        'binary_sensor.front_door',
        "bad') + 1",
        'lock.patio',
    ]);
    is($tmpl, "{{ [state_translated('binary_sensor.front_door'), state_translated('lock.patio')] | tojson }}",
        'buildStateTranslatedTemplate builds batched tojson template and skips invalid IDs');

    is_deeply(
        Plugins::HAScreenSaver::Plugin::parseStateTranslatedResponse("[\"\xC3\x96ppen\",\"Ol\xC3\xA5st\"]", 2),
        ["\x{00D6}ppen", "Ol\x{00E5}st"],
        'parseStateTranslatedResponse parses valid JSON array'
    );
    is(Plugins::HAScreenSaver::Plugin::parseStateTranslatedResponse('["only_one"]', 2), undef,
        'parseStateTranslatedResponse rejects mismatched array length');
    is(Plugins::HAScreenSaver::Plugin::parseStateTranslatedResponse('not json', 1), undef,
        'parseStateTranslatedResponse rejects malformed JSON');

    # Fallback device_class & domain state mapping
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'on',  attributes => { device_class => 'door' } }),         'Open',         'door on -> Open');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'off', attributes => { device_class => 'door' } }),         'Closed',       'door off -> Closed');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'on',  attributes => { device_class => 'window' } }),       'Open',         'window on -> Open');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'off', attributes => { device_class => 'garage_door' } }),  'Closed',       'garage_door off -> Closed');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'on',  attributes => { device_class => 'lock' } }),         'Unlocked',     'binary_sensor lock on -> Unlocked (HA inverted)');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'off', attributes => { device_class => 'lock' } }),         'Locked',       'binary_sensor lock off -> Locked (HA inverted)');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'on',  attributes => { device_class => 'motion' } }),       'Detected',     'motion on -> Detected');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'off', attributes => { device_class => 'motion' } }),       'Clear',        'motion off -> Clear');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'on',  attributes => { device_class => 'presence' } }),     'Home',         'presence on -> Home');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'off', attributes => { device_class => 'presence' } }),     'Away',         'presence off -> Away');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'on',  attributes => { device_class => 'moisture' } }),     'Wet',          'moisture on -> Wet');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'off', attributes => { device_class => 'connectivity' } }), 'Disconnected', 'connectivity off -> Disconnected');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'on',  attributes => { device_class => 'battery' } }),      'Low',          'battery on -> Low');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'unlocked' }), 'Unlocked', 'lock.* unlocked -> Unlocked');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'locked' }),   'Locked',   'lock.* locked -> Locked');
    is(Plugins::HAScreenSaver::Plugin::translateSensorFallback({ state => 'not_home' }), 'Away',     'person.* not_home -> Away');

    # formatSensorState with translated text vs fallback vs untranslated raw on/off
    my $transDoor = Plugins::HAScreenSaver::Plugin::formatSensorState(
        { state => 'on', attributes => { device_class => 'door' } },
        { label => 'Door', decimals => '1', unit => '' },
        'Öppen'
    );
    is($transDoor->{value}, 'Öppen', 'formatSensorState uses HA translated string');
    is($transDoor->{unit},  '',      'Textual state has empty unit');

    my $rawUntranslated = Plugins::HAScreenSaver::Plugin::formatSensorState(
        { state => 'on', attributes => { device_class => 'door' } },
        { label => 'Door', decimals => '1', unit => '' },
        'on'
    );
    is($rawUntranslated->{value}, 'Open', 'Untranslated raw "on" with device_class upgrades via fallback');

    # End-to-end handleSensorsRequest with mixed numeric + binary_sensor + lock
    my $prefs = Slim::Utils::Prefs::preferences('plugin.hascreensaver');
    $prefs->set('ha_url',         'http://example.ha:8123');
    $prefs->set('ha_token',       'test-token');
    $prefs->set('weather_entity', '');
    $prefs->set('alert_entity',   '');
    $prefs->set('sensor1_entity', 'sensor.outside_temperature');
    $prefs->set('sensor1_label',  'Out');
    $prefs->set('sensor2_entity', 'binary_sensor.front_door');
    $prefs->set('sensor2_label',  'Door');
    $prefs->set('sensor3_entity', 'lock.front_door');
    $prefs->set('sensor3_label',  'Lock');
    $prefs->set('sensor4_entity', '');

    %Slim::Networking::SimpleAsyncHTTP::MOCK_RESPONSES = (
        'http://example.ha:8123/api/states/sensor.outside_temperature' => {
            content => '{"state":"5.44","attributes":{"unit_of_measurement":"°C"}}',
        },
        'http://example.ha:8123/api/states/binary_sensor.front_door' => {
            content => '{"state":"on","attributes":{"device_class":"door"}}',
        },
        'http://example.ha:8123/api/states/lock.front_door' => {
            content => '{"state":"unlocked","attributes":{}}',
        },
        'http://example.ha:8123/api/template' => {
            content => "[\"\xC3\x96ppen\",\"Ol\xC3\xA5st\"]",
        },
    );
    @Slim::Networking::SimpleAsyncHTTP::REQUESTS = ();

    my %resA;
    my $doneA = 0;
    my $reqA = bless { client => undef, results => \%resA, done => \$doneA }, 'MockClientRequest';
    Plugins::HAScreenSaver::Plugin::handleSensorsRequest($reqA);

    is($doneA, 1, 'Mixed numeric + textual request completed');
    my @postReqsA = grep { ($_->{method} || '') eq 'POST' } @Slim::Networking::SimpleAsyncHTTP::REQUESTS;
    is(scalar(@postReqsA), 1, 'Fired exactly 1 batched POST to /api/template');
    is($postReqsA[0]{params}{cache}, 0, 'POST /api/template explicitly sets cache => 0');
    is($postReqsA[0]{headers}{'Cache-Control'}, 'no-cache', 'POST /api/template sets Cache-Control: no-cache');
    is($resA{sensors_loop}[0]{value}, '5.4',   'Numeric slot formatted normally');
    is($resA{sensors_loop}[1]{value}, "\x{00D6}ppen", 'Binary sensor localized via HA state_translated');
    is($resA{sensors_loop}[2]{value}, "Ol\x{00E5}st", 'Lock localized via HA state_translated');

    # Case B: /api/template fails -> graceful fallback to English device_class / domain labels
    $Slim::Networking::SimpleAsyncHTTP::MOCK_RESPONSES{'http://example.ha:8123/api/template'} = {
        error => '500 Internal Server Error',
    };
    @Slim::Networking::SimpleAsyncHTTP::REQUESTS = ();
    my %resB;
    my $doneB = 0;
    my $reqB = bless { client => undef, results => \%resB, done => \$doneB }, 'MockClientRequest';
    Plugins::HAScreenSaver::Plugin::handleSensorsRequest($reqB);

    is($doneB, 1, 'Fallback request completed when /api/template failed');
    is($resB{sensors_loop}[1]{value}, 'Open',     'Door binary_sensor falls back to Open');
    is($resB{sensors_loop}[2]{value}, 'Unlocked', 'Lock falls back to Unlocked');

    # Case C: Numeric-only setup -> 0 POST calls to /api/template
    $prefs->set('sensor2_entity', '');
    $prefs->set('sensor3_entity', '');
    @Slim::Networking::SimpleAsyncHTTP::REQUESTS = ();
    my %resC;
    my $doneC = 0;
    my $reqC = bless { client => undef, results => \%resC, done => \$doneC }, 'MockClientRequest';
    Plugins::HAScreenSaver::Plugin::handleSensorsRequest($reqC);

    is($doneC, 1, 'Numeric-only request completed');
    my @postReqsC = grep { ($_->{method} || '') eq 'POST' } @Slim::Networking::SimpleAsyncHTTP::REQUESTS;
    is(scalar(@postReqsC), 0, 'Numeric-only setup fires 0 POST requests to /api/template');
}

# 11. v2.0.0 Appearance sanitizers, tri-state label_bold, per-player overrides, strings.txt & assets
{
    is(Plugins::HAScreenSaver::Plugin::sanitizeBackgroundStyle('SILVER'),  'silver',  'Valid background style normalized');
    is(Plugins::HAScreenSaver::Plugin::sanitizeBackgroundStyle('velvet'),  'velvet',  'Velvet background style accepted');
    is(Plugins::HAScreenSaver::Plugin::sanitizeBackgroundStyle('invalid'), 'slate',   'Invalid background style falls back to slate');
    is(Plugins::HAScreenSaver::Plugin::sanitizeWeatherSize('compact'),     'compact', 'Compact weather size accepted');
    is(Plugins::HAScreenSaver::Plugin::sanitizeWeatherSize('bogus'),       'large',   'Invalid weather size falls back to large');
    is(Plugins::HAScreenSaver::Plugin::sanitizeLabelSize('medium'),        'medium',  'Medium label size accepted');
    is(Plugins::HAScreenSaver::Plugin::sanitizeLabelSize('huge'),          'default', 'Invalid label size falls back to default');
    is(Plugins::HAScreenSaver::Plugin::sanitizeScaleSize('compact'),       'compact', 'Compact scale size accepted');
    is(Plugins::HAScreenSaver::Plugin::sanitizeScaleSize('nope'),          'default', 'Invalid scale size falls back to default');
    is(Plugins::HAScreenSaver::Plugin::sanitizeBoolFlag('1'),              '1',       'Bool flag 1 -> 1');
    is(Plugins::HAScreenSaver::Plugin::sanitizeBoolFlag('0'),              '0',       'Bool flag 0 -> 0');
    is(Plugins::HAScreenSaver::Plugin::sanitizeHexColor('a1b2c3'),         '#A1B2C3', 'Hex without # normalized uppercase');
    is(Plugins::HAScreenSaver::Plugin::sanitizeHexColor('#ff00aa'),        '#FF00AA', 'Hex with # normalized uppercase');
    is(Plugins::HAScreenSaver::Plugin::sanitizeHexColor('not-a-hex'),      '',        'Invalid hex sanitized to empty');
    is(Plugins::HAScreenSaver::Plugin::sanitizeHexColor(''),               '',        'Blank hex remains empty');

    # Tri-state player_label_bold & corrupt-pref sanitization on emit
    my $prefs = Slim::Utils::Prefs::preferences('plugin.hascreensaver');
    $prefs->set('background_style', 'corrupt_bg');
    $prefs->set('weather_size',     'large');
    $prefs->set('label_size',       'default');
    $prefs->set('label_bold',       '1');
    $prefs->set('clock_color',      'badcolor');
    $prefs->set('label_color',      '#b8c4d4');

    my $cInherit = MockClient->new(id => 'aa:bb:cc:dd:ee:01', name => 'Inherit Radio');
    my $cfgInh = Plugins::HAScreenSaver::Plugin::resolveEffectiveConfig($prefs, $cInherit);
    is($cfgInh->{background_style}, 'slate',   'Corrupt global background_style sanitized on emit');
    is($cfgInh->{clock_color},      '',        'Corrupt global clock_color sanitized on emit');
    is($cfgInh->{label_color},      '#B8C4D4', 'Valid global label_color normalized on emit');
    is($cfgInh->{label_bold},       '1',       'Player inherits global label_bold=1 when blank');

    my $cOverride = MockClient->new(id => 'aa:bb:cc:dd:ee:02', name => 'White Radio');
    my $cp = $prefs->client($cOverride);
    $cp->set('player_background_style', 'silver');
    $cp->set('player_weather_size',     'compact');
    $cp->set('player_label_bold',       '0');
    $cp->set('player_label_size',       'large');
    $cp->set('player_clock_color',      '#112233');

    my $cfgOv = Plugins::HAScreenSaver::Plugin::resolveEffectiveConfig($prefs, $cOverride);
    is($cfgOv->{has_overrides},    1,         'Appearance overrides set has_overrides=1');
    is($cfgOv->{background_style}, 'silver',  'Player overrides background_style to silver');
    is($cfgOv->{weather_size},     'compact', 'Player overrides weather_size to compact');
    is($cfgOv->{label_bold},       '0',       'Tri-state player_label_bold="0" explicitly overrides global "1"');
    is($cfgOv->{label_size},       'large',   'Player overrides label_size to large');
    is($cfgOv->{clock_color},      '#112233', 'Player overrides clock_color');

    my $summary = Plugins::HAScreenSaver::Plugin::describeClientOverrides($prefs, $cOverride);
    like($summary, qr/Background \(silver\)/,       'Override summary mentions Background (silver)');
    like($summary, qr/Weather size \(compact\)/,    'Override summary mentions Weather size (compact)');
    like($summary, qr/Label \(large, regular\)/,    'Override summary shows explicit regular override');
    like($summary, qr/Colors \(custom\)/,           'Override summary mentions Colors (custom)');

    # Validate strings.txt formatting (real TABs + all 6 languages DE, EN, ES, FI, FR, SV)
    for my $sfile (
        'server-plugin/HAScreenSaver/strings.txt',
        'radio-applet/HAScreenSaver/strings.txt',
    ) {
        open my $fh, '<:raw', $sfile or die "Cannot open $sfile: $!";
        my $raw = do { local $/; <$fh> };
        close $fh;

        my $curToken;
        my %langsByToken;
        my $badLines = 0;
        for my $line (split /\r?\n/, $raw) {
            next if $line eq '';
            if ($line =~ /^[A-Z0-9_]+$/) {
                $curToken = $line;
                $langsByToken{$curToken} = {};
            } elsif ($line =~ /^\t(DE|EN|ES|FI|FR|SV)\t.+/) {
                $langsByToken{$curToken}{$1} = 1 if defined $curToken;
            } else {
                $badLines++;
            }
        }
        is($badLines, 0, "$sfile has zero malformed lines (strict TAB format)");
        my @missing;
        for my $tok (sort keys %langsByToken) {
            for my $lg (qw(DE EN ES FI FR SV)) {
                push @missing, "$tok:$lg" unless $langsByToken{$tok}{$lg};
            }
        }
        is(scalar(@missing), 0, "$sfile has all 6 languages (DE/EN/ES/FI/FR/SV) for every token");
    }

    # Validate all 15 weather icons (standard + _dark) + alarm icons + door icon exist
    my @weatherKeys = qw(
        sunny clear_night partlycloudy cloudy rainy pouring hail
        snowy snowy_rainy fog lightning lightning_rainy windy windy_variant exceptional
    );
    my @missingIcons;
    for my $wk (@weatherKeys) {
        for my $sfx ('', '_dark') {
            my $p = "radio-applet/HAScreenSaver/weather_${wk}${sfx}.png";
            push @missingIcons, $p unless -f $p;
        }
    }
    for my $extra (qw(icon_alarm.png icon_alarm_dark.png icon_door.png)) {
        my $p = "radio-applet/HAScreenSaver/$extra";
        push @missingIcons, $p unless -f $p;
    }
    is(scalar(@missingIcons), 0, 'All 33 weather/alarm/door PNG icons exist in radio-applet/HAScreenSaver/');
}

done_testing();
