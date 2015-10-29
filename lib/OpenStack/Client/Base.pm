package OpenStack::Client::Base;

use strict;
use warnings;

use HTTP::Request  ();
use LWP::UserAgent ();

use JSON::XS    ();
use URI::Encode ();

sub new ($%) {
    my ($class, $endpoint, %opts) = @_;

    die('No API endpoint provided') unless $endpoint;

    my $ua = LWP::UserAgent->new(
        'ssl_opts' => {
            'verify_hostname' => 0
        }
    );

    return bless {
        'ua'       => $ua,
        'endpoint' => $endpoint,
        'token'    => $opts{'token'}
    }, $class;
}

sub endpoint ($) {
    shift->{'endpoint'};
}

sub uri ($$$) {
    my ($self, $path) = @_;

    return join '/', map {
        s/^\///;
        s/\/$//;
        $_
    } $self->{'endpoint'}, $path;
}

sub call ($$$$) {
    my ($self, $method, $path, $body) = @_;

    my $request = HTTP::Request->new(
        $method => $self->uri($path)
    );

    my @headers = (
        'Accept'          => 'application/json, text/plain',
        'Accept-Encoding' => 'identity, gzip, deflate, compress',
        'Content-Type'    => 'application/json'
    );

    push @headers, (
        'X-Auth-Token' => $self->{'token'}->{'id'}
    ) if defined $self->{'token'}->{'id'};

    my $count = scalar @headers;

    die('Uneven number of header elements') if $count % 2 != 0;

    for (my $i=0; $i<$count; $i+=2) {
        my $name  = $headers[$i];
        my $value = $headers[$i+1];

        $request->header($name => $value);
    }

    $request->content(JSON::XS::encode_json($body)) if defined $body;

    my $response = $self->{'ua'}->request($request);
    my $type     = $response->header('Content-Type');

    if ($response->code =~ /^2\d{2}$/) {
        die("Unexpected response type $type") unless lc $type =~ qr{^application/json}i;

        return JSON::XS::decode_json($response->decoded_content);
    }

    if ($response->code =~ /^[45]\d{2}$/) {
        die($response->decoded_content);
    }

    return $response->message;
}

sub get ($$%) {
    my ($self, $path, %opts) = @_;

    my $params;

    foreach my $name (sort keys %opts) {
        my $value = $opts{$name};

        $params .= "&" if defined $params;

        $params .= sprintf "%s=%s", map {
            URI::Encode::uri_encode($_)
        } $name, $value;
    }

    if (defined $params) {
        #
        # $path might already have request parameters; if so, just append
        # subsequent values with a & rather than ?.
        #
        if ($path =~ /\?/) {
            $path .= "&$params"
        } else {
            $path .= "?$params";
        }
    }

    return $self->call('GET' => $path);
}

sub each ($$$) {
    my ($self, $path, @args) = @_;

    my $opts = {};
    my $callback;

    if (scalar @args == 2) {
        ($opts, $callback) = @args;
    } elsif (scalar @args == 1) {
        ($callback) = @args;
    } else {
        die('Invalid number of arguments');
    }

    while (defined $path) {
        my $result = $self->get($path, %{$opts});

        $callback->($result);

        $path = $result->{'next'};
    }

    return;
}

1;
