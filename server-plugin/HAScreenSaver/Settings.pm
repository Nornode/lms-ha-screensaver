package Plugins::HAScreenSaver::Settings;

use strict;
use warnings;

use base qw(Slim::Web::Settings);

use Slim::Utils::Prefs;

my $prefs = preferences('plugin.hascreensaver');

sub name {
    return Slim::Web::HTTP::CSRF->protectName('PLUGIN_HASCREENSAVER');
}

sub page {
    return Slim::Web::HTTP::CSRF->protectURI('plugins/HAScreenSaver/settings/basic.html');
}

sub prefs {
    return (
        $prefs,
        qw(
            ha_url
            ha_token
            poll_interval
            font_name
            weather_entity
            alert_entity
            alert_label
            sensor1_entity
            sensor1_label
            sensor1_decimals
            sensor1_unit
            sensor2_entity
            sensor2_label
            sensor2_decimals
            sensor2_unit
            sensor3_entity
            sensor3_label
            sensor3_decimals
            sensor3_unit
            sensor4_entity
            sensor4_label
            sensor4_decimals
            sensor4_unit
        )
    );
}

sub handler {
    my ($class, $client, $params, $callback, @args) = @_;

    if ($params->{saveSettings}) {
        if (defined $params->{pref_poll_interval}) {
            $params->{pref_poll_interval} =
                Plugins::HAScreenSaver::Plugin::sanitizePollInterval($params->{pref_poll_interval});
        }
        if (defined $params->{pref_font_name}) {
            $params->{pref_font_name} =
                Plugins::HAScreenSaver::Plugin::sanitizeFontName($params->{pref_font_name});
        }
    }

    my ($baseUrl, $token, $mode) = Plugins::HAScreenSaver::Plugin::resolveHAConfig($prefs, \%ENV);
    $params->{ha_mode} = $mode;

    my $host = $params->{host} || 'localhost:9000';
    $params->{local_repo_url} = "http://${host}/plugins/HAScreenSaver/repo.xml";

    my @players;
    my @clients = eval {
        require Slim::Player::Client;
        Slim::Player::Client::clients();
    };
    my @sorted = sort {
        lc((eval { $a->name } || eval { $a->id } || ''))
        cmp
        lc((eval { $b->name } || eval { $b->id } || ''))
    } grep { defined $_ } @clients;

    for my $c (@sorted) {
        my $cfg = Plugins::HAScreenSaver::Plugin::resolveEffectiveConfig($prefs, $c);
        push @players, {
            id            => (eval { $c->id }        || ''),
            name          => (eval { $c->name }      || eval { $c->id } || ''),
            model         => (eval { $c->modelName } || eval { $c->model } || ''),
            has_overrides => $cfg->{has_overrides},
            summary       => Plugins::HAScreenSaver::Plugin::describeClientOverrides($prefs, $c),
        };
    }
    $params->{players} = \@players;

    return $class->SUPER::handler($client, $params, $callback, @args);
}

1;
