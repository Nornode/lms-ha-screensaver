# LMS 9.x Perl Plugin API Cheatsheet

## `install.xml` Required Fields
- `name`: `PLUGIN_HASCREENSAVER` (matches key in `strings.txt`)
- `module`: `Plugins::HAScreenSaver::Plugin`
- `targetApplication`: `id="SlimServer"`, `minVersion="8.0"`, `maxVersion="*"`
- `optionsURL`: `plugins/HAScreenSaver/settings/basic.html`

## `Slim::Utils::Prefs`
```perl
my $prefs = preferences('plugin.hascreensaver');
$prefs->init({
    ha_url        => '',
    ha_token      => '',
    poll_interval => 60,
    font_name     => 'FreeSansBold',
    alert_entity  => '',
    alert_label   => '',
    # Up to 4 sensor slots: sensor1..sensor4
});
```
Never store transient HA sensor readings in `$prefs`.

## `Slim::Networking::SimpleAsyncHTTP`
```perl
my $http = Slim::Networking::SimpleAsyncHTTP->new(
    sub {
        my $response = shift;
        my $data = eval { decode_json($response->content) };
        ...
    },
    sub {
        my ($http, $error) = @_;
        ...
    },
    {
        cache   => 0,
        timeout => 5,
    }
);
$http->get(
    $url,
    'Authorization' => "Bearer $token",
    'Accept'        => 'application/json',
    'Cache-Control' => 'no-cache',
);
```

## `Slim::Web::Pages->addPageFunction`
```perl
Slim::Web::Pages->addPageFunction(
    qr/^plugins\/HAScreenSaver\/repo\.xml$/,
    \&handleRepoXml
);
```
Callback signature: `sub handleRepoXml { my ($client, $params, $callback, $httpClient, $response) = @_; ... }`
Set headers via `$response->header('Content-Type' => 'application/xml; charset=utf-8')` and return a scalar reference `\$xml`.

## Logging
```perl
my $log = Slim::Utils::Log->addLogCategory({
    category     => 'plugin.hascreensaver',
    defaultLevel => 'ERROR',
    description  => 'PLUGIN_HASCREENSAVER',
});
```
Avoid logging `ha_token` or `$ENV{SUPERVISOR_TOKEN}` at any log level!
