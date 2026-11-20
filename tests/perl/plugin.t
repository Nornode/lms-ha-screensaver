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
            $stores{$ns} ||= bless { data => {} }, 'MockPrefs';
            return $stores{$ns};
        }
        package MockPrefs;
        sub init {
            my ($self, $defaults) = @_;
            for my $k (keys %$defaults) {
                $self->{data}{$k} = $defaults->{$k} unless exists $self->{data}{$k};
            }
        }
        sub get {
            my ($self, $k) = @_;
            return $self->{data}{$k};
        }
        sub set {
            my ($self, $k, $v) = @_;
            $self->{data}{$k} = $v;
        }
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

# 4b. Test formatWeatherIcon
is(Plugins::HAScreenSaver::Plugin::formatWeatherIcon({ state => 'partlycloudy' }), 'partlycloudy', 'Weather partlycloudy maps cleanly');
is(Plugins::HAScreenSaver::Plugin::formatWeatherIcon({ state => 'clear-night' }),  'clear_night',  'Weather clear-night maps to clear_night');
is(Plugins::HAScreenSaver::Plugin::formatWeatherIcon({ state => 'lightning-rainy' }), 'lightning', 'Weather lightning-rainy maps to lightning');
is(Plugins::HAScreenSaver::Plugin::formatWeatherIcon({ state => 'unknown' }),      '',             'Unknown weather returns empty icon');

# 5. Test buildRepoXml
{
    my $xml = Plugins::HAScreenSaver::Plugin::buildRepoXml('192.0.2.10:9000', '0.1.0', 'abc123');
    like($xml, qr/target="baby\|fab4\|jive\|squeezeplay"/, 'repo.xml targets baby (Squeezebox Radio)');
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
}

done_testing();
