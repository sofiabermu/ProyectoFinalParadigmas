package Kepler::DB;
use strict;
use warnings;
use DBI;
use Try::Tiny;

my $dbh;

sub db_connect {
    my $host = $ENV{MYSQL_HOST}     // '127.0.0.1';
    my $port = $ENV{MYSQL_PORT}     // 3307;
    my $db   = $ENV{MYSQL_DB}       // 'kepler';
    my $user = $ENV{MYSQL_USER}     // 'kepler';
    my $pass = $ENV{MYSQL_PASSWORD} // 'kepler_dev_2026';

    my $dsn = "DBI:mysql:database=$db;host=$host;port=$port;mysql_enable_utf8mb4=1";

    $dbh = DBI->connect($dsn, $user, $pass, {
        RaiseError       => 1,
        AutoCommit       => 1,
        mysql_auto_reconnect => 1,
    }) or die "DB connect failed: $DBI::errstr";

    return $dbh;
}

sub dbh {
    return $dbh // db_connect();
}

# Insert or ignore mission (idempotent for demo re-runs)
sub upsert_mission {
    my (%args) = @_;
    my $h = dbh();
    $h->do(
        'INSERT IGNORE INTO missions (mission_id, name, launched_at, target_system, responsible_agency)
         VALUES (?,?,NOW(),?,?)',
        undef,
        $args{mission_id}, $args{name} // $args{mission_id},
        $args{target_system} // 'Unknown', $args{responsible_agency} // 'UNKNOWN'
    );
}

sub insert_observation {
    my (%args) = @_;
    my $h = dbh();
    $h->do(
        'INSERT INTO observations
           (mission_id, right_ascension, declination, spectral_reading_json,
            confidence, observed_at_utc, conclusion, inference_chain_json)
         VALUES (?,?,?,?,?,?,?,?)',
        undef,
        $args{mission_id}, $args{right_ascension}, $args{declination},
        $args{spectral_reading_json}, $args{confidence},
        $args{observed_at_utc}, $args{conclusion}, $args{inference_chain_json}
    );
    return $h->{mysql_insertid};
}

sub insert_transmission {
    my (%args) = @_;
    my $h = dbh();
    $h->do(
        'INSERT INTO transmissions
           (observation_id, traceability_chain_json, payload_hash,
            corrected_bits_count, received_at_ground_utc)
         VALUES (?,?,?,?,NOW(3))',
        undef,
        $args{observation_id}, $args{traceability_chain_json},
        $args{payload_hash}, $args{corrected_bits_count} // 0
    );
    return $h->{mysql_insertid};
}

sub insert_alert {
    my (%args) = @_;
    my $h = dbh();
    $h->do(
        'INSERT INTO alerts (observation_id, priority_level, justification, created_at_utc)
         VALUES (?,?,?,NOW(3))',
        undef,
        $args{observation_id}, $args{priority_level}, $args{justification} // ''
    );
}

sub get_summary {
    my ($mission_id) = @_;
    my $h = dbh();
    my $row = $h->selectrow_hashref(
        'SELECT m.mission_id, m.name, m.target_system, m.responsible_agency,
                p.probe_id, p.model, p.sensor_status,
                COUNT(DISTINCT o.observation_id) AS total_observations,
                MAX(o.observed_at_utc)           AS last_observed_at,
                MAX(o.confidence)                AS max_confidence
         FROM missions m
         LEFT JOIN probes p      ON p.mission_id = m.mission_id
         LEFT JOIN observations o ON o.mission_id = m.mission_id
         WHERE m.mission_id = ?
         GROUP BY m.mission_id, p.probe_id',
        undef, $mission_id
    );
    return $row;
}

sub get_history {
    my ($mission_id, $limit) = @_;
    $limit //= 20;
    my $h = dbh();
    my $rows = $h->selectall_arrayref(
        'SELECT o.observation_id, o.right_ascension, o.declination,
                o.confidence, o.observed_at_utc, o.conclusion,
                o.inference_chain_json, o.spectral_reading_json,
                t.payload_hash, t.corrected_bits_count,
                t.traceability_chain_json, t.received_at_ground_utc,
                a.priority_level
         FROM observations o
         LEFT JOIN transmissions t ON t.observation_id = o.observation_id
         LEFT JOIN alerts a        ON a.observation_id = o.observation_id
         WHERE o.mission_id = ?
         ORDER BY o.observed_at_utc DESC
         LIMIT ?',
        { Slice => {} }, $mission_id, $limit
    );
    return $rows;
}

1;
