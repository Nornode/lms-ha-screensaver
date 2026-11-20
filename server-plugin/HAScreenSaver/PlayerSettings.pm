package Plugins::HAScreenSaver::PlayerSettings;

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.hascreensaver');

my %ENTITY_KEYS = map { $_ => 1 } (
    'player_weather_entity',
    'player_alert_entity',
    map { "player_sensor${_}_entity" } (1 .. 4)
);

sub name {
    return Slim::Web::HTTP::CSRF->protectName('PLUGIN_HASCREENSAVER');
}

sub page {
    return Slim::Web::HTTP::CSRF->protectURI('plugins/HAScreenSaver/settings/player.html');
}

sub needsClient {
    return 1;
}

sub prefs {
    my ($class, $client) = @_;
    return () unless $client;
    return ($prefs->client($client), Plugins::HAScreenSaver::Plugin::playerPrefKeys());
}

sub _trim {
    my ($s) = @_;
    return '' unless defined $s;
    $s =~ s/^\s+//;
    $s =~ s/\s+$//;
    return $s;
}

sub _buildDefaultsHash {
    my %defaults = (
        font_name      => Plugins::HAScreenSaver::Plugin::sanitizeFontName($prefs->get('font_name')),
        weather_entity => _trim($prefs->get('weather_entity')),
        alert_entity   => _trim($prefs->get('alert_entity')),
        alert_label    => _trim($prefs->get('alert_label')),
    );

    for my $i (1 .. 4) {
        $defaults{"sensor${i}_entity"}   = _trim($prefs->get("sensor${i}_entity"));
        $defaults{"sensor${i}_label"}    = _trim($prefs->get("sensor${i}_label"));
        $defaults{"sensor${i}_decimals"} = _trim($prefs->get("sensor${i}_decimals"));
        $defaults{"sensor${i}_unit"}     = _trim($prefs->get("sensor${i}_unit"));
    }

    return \%defaults;
}

sub handler {
    my ($class, $client, $params, $callback, @args) = @_;

    $params->{defaults} = _buildDefaultsHash();

    if ($client) {
        $params->{player_name} = eval { $client->name() } || eval { $client->id() } || '';

        if ($params->{saveSettings}) {
            my @keys = Plugins::HAScreenSaver::Plugin::playerPrefKeys();

            if ($params->{resetPlayerOverrides}) {
                for my $k (@keys) {
                    $params->{"pref_$k"} = '';
                }
                delete $params->{resetPlayerOverrides};
            } else {
                for my $k (@keys) {
                    my $pk = "pref_$k";
                    next unless defined $params->{$pk};
                    my $val = _trim($params->{$pk});
                    if ($ENTITY_KEYS{$k} && lc($val) eq 'none') {
                        $val = 'none';
                    }
                    $params->{$pk} = $val;
                }

                if (defined $params->{pref_player_font_name} && $params->{pref_player_font_name} ne '') {
                    $params->{pref_player_font_name} =
                        Plugins::HAScreenSaver::Plugin::sanitizeFontName($params->{pref_player_font_name});
                }
            }

            $params->{override_summary} = Plugins::HAScreenSaver::Plugin::describeOverrides(sub {
                my ($key) = @_;
                return $params->{"pref_$key"};
            });
        } else {
            $params->{override_summary} =
                Plugins::HAScreenSaver::Plugin::describeClientOverrides($prefs, $client);
        }
    } else {
        $params->{player_name}      = '';
        $params->{override_summary} = 'Using Global Defaults';
    }

    return $class->SUPER::handler($client, $params, $callback, @args);
}

1;
