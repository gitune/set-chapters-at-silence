#!/usr/bin/env perl

use strict;
use constant MIN_INTERVAL => 31.0;
use constant NOISE_THRESH => 5.0;
use File::Temp 'tempfile';

if (@ARGV < 2) {
    print STDERR "Usage: $0 [INPUT] [OUTPUT]\n";
    exit 1;
}

sub print_chapter {
    local *FH = @_[0];
    my $start = @_[1];
    my $end = @_[2];

    print FH "[CHAPTER]\n";
    print FH "TIMEBASE=1/1000\n";
    printf FH "START=%d\n", ($start * 1000);
    printf FH "END=%d\n", ($end * 1000);
}

# get original metadata and open it in append mode
my ($tmpfh, $tmpfile) = tempfile;
close $tmpfh;
`ffmpeg -v quiet -y -i $ARGV[0] -f ffmetadata $tmpfile`;
die "cannot get the original metadata: $!" if $?;
open(MD, ">> $tmpfile");

my $last_time = 0;
my $last_chapter_start_time = 0;
my $start_time = 0;

# silence detect
open(SD, "ffmpeg -hide_banner -nostats -y -i $ARGV[0] -af 'silencedetect=d=0.5' -c:v copy -c:a pcm_dvd -f null - 2>&1 | grep 'silence_start' |") or die "cannot detect silence: $!";
while (<SD>) {
    ($start_time) = (/^.*silence_start: ([0-9\.]+).*$/);
    my $diff = $start_time - $last_time;

    # Determine if this interval should trigger a new chapter.
    # It triggers if:
    # 1. The interval is longer than MIN_INTERVAL (standard program start).
    # 2. The interval is not a multiple of 15s (not a typical CM) and not too short (noise).
    my $nearest_15 = int($diff / 15 + 0.5) * 15;
    my $is_cm_interval = ($diff < MIN_INTERVAL && $nearest_15 > 0 && abs($diff - $nearest_15) < 1.0);

    if ($diff > MIN_INTERVAL || ($diff > NOISE_THRESH && !$is_cm_interval)) {
        # set chapter
        if ($last_chapter_start_time != $last_time) {
            # set chapter at the end of CM
            print_chapter(*MD, $last_chapter_start_time, $last_time);
            $last_chapter_start_time = $last_time;
        }
        print_chapter(*MD, $last_chapter_start_time, $start_time);
        $last_chapter_start_time = $start_time;
    }
    $last_time = $start_time;
}
if ($last_chapter_start_time != $start_time) {
    print_chapter(*MD, $last_chapter_start_time, $start_time);
}
close(SD);
close(MD);

# set chapters
`ffmpeg -v quiet -y -i $ARGV[0] -i $tmpfile -movflags faststart -map_metadata 1 -codec copy -strict -2 "$ARGV[1]"`;
die "cannot set chapters: $!" if $?;

# delete tmpfile
unlink $tmpfile;
