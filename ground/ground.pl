#!/usr/bin/env perl
# Proyecto Kepler — GROUND node
# Mojolicious::Lite REST server, puerto 5000
# Persiste eventos en MySQL 8 via DBI + DBD::mysql

use strict;
use warnings;
use lib 'lib';
use Mojolicious::Lite -signatures;
use JSON::XS         ();
use Try::Tiny;
use Kepler::DB      ();
use Kepler::Display ();

my $json = JSON::XS->new->utf8->allow_nonref;

# Conectar al arrancar
app->hook(before_server_start => sub {
    Kepler::DB::db_connect();
    Kepler::Display::log_info("GROUND iniciado — esperando eventos en :5000");
});

# ---------------------------------------------------------------
# POST /api/events  — recibe JSON enriquecido de ATLAS
# ---------------------------------------------------------------
post '/api/events' => sub ($c) {
    my $data = try { $json->decode($c->req->body) }
    catch { $c->render(json => { error => "JSON inválido: $_" }, status => 400); return undef };
    return unless defined $data;

    Kepler::Display::log_info("POST /api/events  mission=" . ($data->{mission_id} // 'unknown'));

    my $err = _validate_event($data);
    if ($err) {
        Kepler::Display::log_info("Validación fallida: $err");
        return $c->render(json => { error => $err }, status => 422);
    }

    my ($obs_id, $trans_id);
    try {
        # 1. Garantizar misión existe
        Kepler::DB::upsert_mission(
            mission_id         => $data->{mission_id},
            name               => $data->{mission_id},
            target_system      => 'Deep Space',
            responsible_agency => $data->{responsible_agency} // 'UNKNOWN',
        );

        # 2. Insertar observación
        my $coords   = $data->{coordinates} // {};
        my $spec_raw = $data->{spectral_reading} // [];
        $obs_id = Kepler::DB::insert_observation(
            mission_id            => $data->{mission_id},
            right_ascension       => $coords->{right_ascension} // '',
            declination           => $coords->{declination}     // '',
            spectral_reading_json => $json->encode($spec_raw),
            confidence            => $data->{confidence}        // 0,
            observed_at_utc       => _iso_to_mysql($data->{timestamp_utc}),
            conclusion            => $data->{conclusion}        // '',
            inference_chain_json  => $json->encode($data->{inference_chain} // []),
        );

        # 3. Insertar transmisión
        $trans_id = Kepler::DB::insert_transmission(
            observation_id          => $obs_id,
            traceability_chain_json => $json->encode($data->{traceability_chain} // []),
            payload_hash            => $data->{payload_hash}         // '',
            corrected_bits_count    => $data->{corrected_bits_count} // 0,
        );

        # 4. Insertar alerta
        Kepler::DB::insert_alert(
            observation_id => $obs_id,
            priority_level => $data->{priority_level} // 'PRIORITY_LOW',
            justification  => sprintf(
                "confidence=%.2f conclusion=%s",
                $data->{confidence} // 0, $data->{conclusion} // ''
            ),
        );
    }
    catch {
        my $e = $_;
        Kepler::Display::log_info("ERROR DB: $e");
        return $c->render(json => { error => "DB error: $e" }, status => 500);
    };

    # Imprimir banner de pantalla de control
    Kepler::Display::print_event_banner($data);

    $c->render(json => {
        status         => 'stored',
        observation_id => $obs_id,
        transmission_id => $trans_id,
    }, status => 201);
};

# ---------------------------------------------------------------
# GET /api/summary/:mission_id
# ---------------------------------------------------------------
get '/api/summary/:mission_id' => sub ($c) {
    my $mid = $c->param('mission_id');
    Kepler::Display::log_info("GET /api/summary/$mid");

    my $row = Kepler::DB::get_summary($mid);
    unless ($row) {
        return $c->render(json => { error => "Misión no encontrada: $mid" }, status => 404);
    }
    $c->render(json => $row);
};

# ---------------------------------------------------------------
# GET /api/history/:mission_id
# ---------------------------------------------------------------
get '/api/history/:mission_id' => sub ($c) {
    my $mid   = $c->param('mission_id');
    my $limit = $c->param('limit') // 20;
    Kepler::Display::log_info("GET /api/history/$mid  limit=$limit");

    my $rows = Kepler::DB::get_history($mid, $limit);
    $c->render(json => {
        mission_id   => $mid,
        total        => scalar @$rows,
        observations => $rows,
    });
};

# ---------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------
sub _validate_event {
    my ($d) = @_;
    return "missing mission_id"  unless $d->{mission_id};
    return "missing confidence"  unless defined $d->{confidence};
    return "missing conclusion"  unless $d->{conclusion};
    return "missing timestamp_utc" unless $d->{timestamp_utc};
    return undef;
}

sub _iso_to_mysql {
    my ($iso) = @_;
    return '1970-01-01 00:00:00' unless $iso;
    # 2026-05-12T14:23:01Z  →  2026-05-12 14:23:01
    (my $mysql = $iso) =~ s/T/ /;
    $mysql =~ s/Z$//;
    return $mysql;
}

app->start;
