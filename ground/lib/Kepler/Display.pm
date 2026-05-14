package Kepler::Display;
use strict;
use warnings;
use POSIX    qw(strftime);
use Encode   qw(encode_utf8);

sub timestamp_utc {
    return strftime('%Y-%m-%dT%H:%M:%SZ', gmtime);
}

sub log_info {
    my ($msg) = @_;
    print encode_utf8(sprintf "[GROUND %s] %s\n", timestamp_utc(), $msg);
}

sub print_event_banner {
    my ($data) = @_;
    my $sep = '=' x 72;
    print "\n$sep\n";
    printf "  *** KEPLER GROUND CONTROL — EVENTO RECIBIDO ***\n";
    print "$sep\n";
    printf "  MISIÓN        : %s\n", $data->{mission_id}      // 'N/A';
    printf "  AGENCIA       : %s\n", $data->{responsible_agency} // 'N/A';
    printf "  PRIORIDAD     : %s\n", $data->{priority_level}  // 'N/A';
    printf "  CONFIANZA     : %.2f\n", $data->{confidence}    // 0;
    printf "  CONCLUSIÓN    : %s\n", $data->{conclusion}      // 'N/A';
    printf "  AR / DEC      : %s  /  %s\n",
        ($data->{coordinates}{right_ascension} // 'N/A'),
        ($data->{coordinates}{declination}     // 'N/A');
    printf "  HASH PAYLOAD  : %s\n", substr($data->{payload_hash} // 'N/A', 0, 16) . '...';
    printf "  BITS CORREG.  : %d\n", $data->{corrected_bits_count} // 0;
    printf "  TIMESTAMP UTC : %s\n", $data->{timestamp_utc} // 'N/A';
    my $chain = $data->{traceability_chain} // [];
    if (ref $chain eq 'ARRAY' && @$chain) {
        print "  TRAZABILIDAD  :\n";
        for my $step (@$chain) {
            printf "    [%s] %s @ %s\n",
                $step->{action} // '?',
                $step->{node}   // '?',
                $step->{timestamp_utc} // '?';
        }
    }
    print "$sep\n\n";
}

1;
